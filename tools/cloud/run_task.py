#!/usr/bin/env python3
"""cloud-test runner: publish the test place, run tests/cloud/entry in a Luau Execution task, report.

    python3 tools/cloud/run_task.py --rbxl build/test.rbxl --script tools/cloud/task.luau

Modeled on Roblox/place-ci-cd-demo (luau_execution_task.py): one Saved version of the TEST place is
published from the rbxl, ONE Luau Execution task runs on that version, the task is polled every 3
seconds until COMPLETE or FAILED, its logs are printed, and the exit code is 0 only for COMPLETE.

Environment (never printed):
    ROBLOX_API_KEY        Open Cloud key, scoped to the TEST experience (universe-places write,
                          luau-execution-sessions write). A secret.
    TEST_UNIVERSE_ID      10772436908 (the TEST universe; a repo variable may set it, but only this value runs)
    TEST_PLACE_ID         109062394774073 (the TEST place; same)
    CLOUD_TEST_REQUIRED   "1": a missing key FAILS the run. Unset or "0": a missing key SKIPS it
                          ("cloud-test SKIPPED: missing ROBLOX_API_KEY", exit 0, SKIPPED in the job summary).
    GITHUB_STEP_SUMMARY   when set, a line about the outcome is appended to it.

It only ever targets the TEST place. Any other place or universe id (even one a repo variable
supplies) is refused before any network call, and so is the live place.

Exit codes: 0 passed or skipped, 1 failed (a check failed, HTTP error, timeout), 2 refused (bad target
or arguments).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

TEST_PLACE_ID = "109062394774073"
TEST_UNIVERSE_ID = "10772436908"
API = "https://apis.roblox.com"
POLL_SECONDS = 3
DEFAULT_TIMEOUT = 900  # whole run, seconds
TASK_TIMEOUT = "600s"  # the task's own limit

# (method, url, headers, body) -> (status, body bytes). Replaced in tests.
Http = Callable[[str, str, dict, "bytes | None"], "tuple[int, bytes]"]


class Refused(Exception):
    """The target is not the test place (or the arguments are unusable): nothing was sent."""


class Failed(Exception):
    """The run failed (an HTTP error, a failed task, a timeout)."""


@dataclass
class Config:
    rbxl: Path
    script: Path
    universe: str
    place: str
    key: str
    required: bool
    summary: str
    poll: float
    timeout: float
    dry_run: bool


def parse_args(argv: list[str], env: "dict[str, str]") -> Config:
    p = argparse.ArgumentParser(prog="run_task.py", description=__doc__.split("\n")[0])
    p.add_argument("--rbxl", default="build/test.rbxl", help="the place file to publish")
    p.add_argument("--script", default="tools/cloud/task.luau", help="the Luau the task runs")
    p.add_argument("--poll", type=float, default=POLL_SECONDS, help="seconds between polls (default 3)")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="seconds before giving up")
    p.add_argument("--dry-run", action="store_true", help="check the target and the environment, send nothing")
    try:
        args = p.parse_args(argv)
    except SystemExit as e:  # argparse exits 2 itself; keep it an exception for the callers
        raise Refused("bad arguments") from e
    return Config(
        rbxl=Path(args.rbxl),
        script=Path(args.script),
        universe=(env.get("TEST_UNIVERSE_ID") or TEST_UNIVERSE_ID).strip(),
        place=(env.get("TEST_PLACE_ID") or TEST_PLACE_ID).strip(),
        key=env.get("ROBLOX_API_KEY", "").strip(),
        required=env.get("CLOUD_TEST_REQUIRED", "").strip() == "1",
        summary=env.get("GITHUB_STEP_SUMMARY", ""),
        poll=args.poll,
        timeout=args.timeout,
        dry_run=args.dry_run,
    )


def check_target(cfg: Config) -> None:
    """Only the TEST place, nothing else. Raises Refused before anything is sent."""
    if cfg.place != TEST_PLACE_ID:
        raise Refused(f"cloud-test REFUSED: place id {cfg.place!r} is not the TEST place {TEST_PLACE_ID}; nothing was sent")
    if cfg.universe != TEST_UNIVERSE_ID:
        raise Refused(
            f"cloud-test REFUSED: universe id {cfg.universe!r} is not the TEST universe {TEST_UNIVERSE_ID}; nothing was sent"
        )


def missing(cfg: Config) -> list[str]:
    return [] if cfg.key else ["ROBLOX_API_KEY"]


def redact(text: str, key: str) -> str:
    return text.replace(key, "***") if key else text


def summarize(cfg: Config, line: str) -> None:
    if not cfg.summary:
        return
    try:
        with open(cfg.summary, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def urllib_http(method: str, url: str, headers: dict, body: "bytes | None") -> "tuple[int, bytes]":
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class Client:
    def __init__(self, cfg: Config, http: Http, sleep: Callable[[float], None], clock: Callable[[], float]):
        self.cfg, self.http, self.sleep, self.clock = cfg, http, sleep, clock

    def call(self, method: str, url: str, body: "bytes | None" = None, content_type: str = "application/json") -> dict:
        headers = {"x-api-key": self.cfg.key}
        if body is not None:
            headers["Content-Type"] = content_type
        status, raw = self.http(method, url, headers, body)
        text = redact(raw.decode("utf-8", "replace"), self.cfg.key)
        if status in (401, 403, 409) or status >= 400:
            raise Failed(f"HTTP {status} from {method} {url.split('?')[0]}: {text[:600]}")
        try:
            return json.loads(text) if text.strip() else {}
        except json.JSONDecodeError:
            raise Failed(f"HTTP {status} from {method} {url.split('?')[0]}: not JSON: {text[:300]}")

    def publish(self) -> int:
        cfg = self.cfg
        data = cfg.rbxl.read_bytes()
        url = f"{API}/universes/v1/{cfg.universe}/places/{cfg.place}/versions?versionType=Saved"
        out = self.call("POST", url, data, "application/octet-stream")
        version = out.get("versionNumber")
        if not isinstance(version, int):
            raise Failed(f"publishing the place returned no versionNumber: {json.dumps(out)[:300]}")
        return version

    def create_task(self, version: int) -> str:
        cfg = self.cfg
        url = f"{API}/cloud/v2/universes/{cfg.universe}/places/{cfg.place}/versions/{version}/luau-execution-session-tasks"
        body = json.dumps({"script": cfg.script.read_text(encoding="utf-8"), "timeout": TASK_TIMEOUT}).encode()
        out = self.call("POST", url, body)
        path = out.get("path")
        if not isinstance(path, str) or not path:
            raise Failed(f"creating the task returned no path: {json.dumps(out)[:300]}")
        return path

    def logs(self, path: str) -> list[str]:
        out = self.call("GET", f"{API}/cloud/v2/{path}/logs")
        lines: list[str] = []
        for chunk in out.get("luauExecutionSessionTaskLogs", []) or []:
            lines.extend(str(m) for m in chunk.get("messages", []) or [])
        return lines

    def wait(self, path: str) -> dict:
        start = self.clock()
        while True:
            task = self.call("GET", f"{API}/cloud/v2/{path}")
            state = task.get("state", "")
            if state in ("COMPLETE", "FAILED", "CANCELLED"):
                return task
            if self.clock() - start > self.cfg.timeout:
                raise Failed(f"timed out after {self.cfg.timeout:.0f}s waiting for the task (last state {state or '?'})")
            self.sleep(self.cfg.poll)


def run(cfg: Config, http: Http = urllib_http, sleep: Callable[[float], None] = time.sleep, clock: Callable[[], float] = time.monotonic, out=print) -> int:
    check_target(cfg)
    lost = missing(cfg)
    if lost:
        names = ", ".join(lost)
        if cfg.required:
            out(f"cloud-test FAILED: missing {names} (CLOUD_TEST_REQUIRED=1)")
            summarize(cfg, f"## cloud-test\n\n**FAILED**: missing {names} (CLOUD_TEST_REQUIRED=1)")
            return 1
        out(f"cloud-test SKIPPED: missing {names}")
        summarize(cfg, f"## cloud-test\n\n**SKIPPED**: missing {names}. Nothing was published or run.")
        return 0
    if cfg.dry_run:
        out(f"cloud-test dry run: target universe {cfg.universe}, place {cfg.place} (the TEST place); nothing sent")
        return 0
    client = Client(cfg, http, sleep, clock)
    try:
        version = client.publish()
        out(f"cloud-test: published Saved version {version} of the TEST place {cfg.place}")
        path = client.create_task(version)
        out(f"cloud-test: task created: {path}")
        task = client.wait(path)
        state = task.get("state")
        for line in client.logs(path):
            out(line)
        if state == "COMPLETE":
            out("cloud-test PASSED: the task completed")
            result = (task.get("output") or {}).get("results")
            if result:
                out("results: " + json.dumps(result)[:2000])
            summarize(cfg, f"## cloud-test\n\n**PASSED** on version {version} of the TEST place.")
            return 0
        err = task.get("error") or {}
        out(f"cloud-test FAILED: task state {state}: {err.get('code', '')} {redact(str(err.get('message', '')), cfg.key)}".rstrip())
        summarize(cfg, f"## cloud-test\n\n**FAILED**: task state {state}. See the job log for the findings.")
        return 1
    except Failed as e:
        out(f"cloud-test FAILED: {e}")
        summarize(cfg, f"## cloud-test\n\n**FAILED**: {e}")
        return 1


def main(argv: list[str], env: "dict[str, str] | None" = None) -> int:
    environ = dict(os.environ) if env is None else env
    try:
        cfg = parse_args(argv, environ)
        return run(cfg)
    except Refused as e:
        if str(e) != "bad arguments":
            print(str(e))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
