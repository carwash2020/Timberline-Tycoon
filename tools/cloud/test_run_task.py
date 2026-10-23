#!/usr/bin/env python3
"""Tests for run_task.py: python3 tools/cloud/test_run_task.py (tests/RunTask.spec runs it under check.sh)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_task as rt  # noqa: E402

KEY = "sk-secret-key-123"


def cfg(**kw):
    d = tempfile.mkdtemp()
    rbxl = Path(d) / "x.rbxl"
    rbxl.write_bytes(b"rbxl")
    script = Path(d) / "task.luau"
    script.write_text("return 1")
    base = dict(
        rbxl=rbxl, script=script, universe=rt.TEST_UNIVERSE_ID, place=rt.TEST_PLACE_ID, key=KEY, required=False,
        summary="", poll=3, timeout=600, dry_run=False,
    )
    base.update(kw)
    return rt.Config(**base)


class Fake:
    """A scripted Open Cloud: records every request."""

    def __init__(self, states=("QUEUED", "PROCESSING", "COMPLETE"), publish=(200, {"versionNumber": 7}), create=(200, None), task_error=None):
        self.calls = []
        self.states = list(states)
        self.publish = publish
        self.create = create
        self.task_error = task_error
        self.sleeps = []

    def http(self, method, url, headers, body):
        self.calls.append((method, url, dict(headers), body))
        if "/universes/v1/" in url:
            return self.publish[0], json.dumps(self.publish[1]).encode()
        if url.endswith("/luau-execution-session-tasks"):
            status, payload = self.create
            payload = payload if payload is not None else {"path": f"universes/{rt.TEST_UNIVERSE_ID}/places/{rt.TEST_PLACE_ID}/versions/7/luau-execution-sessions/s/tasks/t", "state": "QUEUED"}
            return status, json.dumps(payload).encode()
        if url.endswith("/logs"):
            return 200, json.dumps({"luauExecutionSessionTaskLogs": [{"messages": ["[cloud-test] lint: 0 finding(s)", "line two"]}]}).encode()
        state = self.states.pop(0) if len(self.states) > 1 else self.states[0]
        task = {"path": "p", "state": state}
        if state == "FAILED":
            task["error"] = self.task_error or {"code": "SCRIPT_ERROR", "message": "cloud-test: 1 failure(s)"}
        if state == "COMPLETE":
            task["output"] = {"results": [{"passed": 5, "failed": 0, "failures": []}]}
        return 200, json.dumps(task).encode()

    def tasks_created(self):
        return [c for c in self.calls if c[0] == "POST" and c[1].endswith("/luau-execution-session-tasks")]


def run(config, fake):
    lines = []
    code = rt.run(config, fake.http, lambda s: fake.sleeps.append(s), lambda: len(fake.sleeps) * 3.0, lines.append)
    return code, "\n".join(lines)


class ParseArgs(unittest.TestCase):
    def test_defaults_and_env(self):
        c = rt.parse_args([], {})
        self.assertEqual((c.universe, c.place, c.key, c.required, c.poll, c.dry_run), (rt.TEST_UNIVERSE_ID, rt.TEST_PLACE_ID, "", False, 3, False))
        c = rt.parse_args(["--rbxl", "a.rbxl", "--script", "b.luau", "--poll", "1", "--timeout", "9", "--dry-run"],
                          {"ROBLOX_API_KEY": " k ", "CLOUD_TEST_REQUIRED": "1", "GITHUB_STEP_SUMMARY": "/tmp/s"})
        self.assertEqual((str(c.rbxl), str(c.script), c.poll, c.timeout, c.dry_run, c.key, c.required, c.summary), ("a.rbxl", "b.luau", 1, 9, True, "k", True, "/tmp/s"))

    def test_required_is_only_the_exact_1(self):
        for value in ("", "0", "true", "yes"):
            self.assertFalse(rt.parse_args([], {"CLOUD_TEST_REQUIRED": value}).required, value)

    def test_unknown_arguments_are_refused(self):
        with self.assertRaises(rt.Refused):
            rt.parse_args(["--live"], {})


class Target(unittest.TestCase):
    def test_only_the_test_place_runs(self):
        rt.check_target(cfg())
        for place in ("1", "109062394774074", "", "0109062394774073"):
            fake = Fake()
            with self.assertRaises(rt.Refused) as ctx:
                run(cfg(place=place), fake)
            self.assertIn("not the TEST place", str(ctx.exception))
            self.assertEqual(fake.calls, [], "no network call for place " + repr(place))

    def test_a_place_supplied_through_a_variable_is_refused_too(self):
        c = rt.parse_args([], {"TEST_PLACE_ID": "123456", "ROBLOX_API_KEY": KEY})
        fake = Fake()
        with self.assertRaises(rt.Refused):
            run(c, fake)
        self.assertEqual(fake.calls, [])

    def test_the_universe_is_pinned_as_well(self):
        fake = Fake()
        with self.assertRaises(rt.Refused):
            run(cfg(universe="42"), fake)
        self.assertEqual(fake.calls, [])

    def test_main_exits_2_and_says_why_without_the_key(self):
        code = rt.main([], {"TEST_PLACE_ID": "5", "ROBLOX_API_KEY": KEY})
        self.assertEqual(code, 2)


class MissingKey(unittest.TestCase):
    def test_missing_key_skips_and_never_passes(self):
        summary = Path(tempfile.mkdtemp()) / "summary.md"
        fake = Fake()
        code, text = run(cfg(key="", summary=str(summary)), fake)
        self.assertEqual(code, 0)
        self.assertEqual(text, "cloud-test SKIPPED: missing ROBLOX_API_KEY")
        self.assertNotIn("PASSED", text)
        self.assertIn("SKIPPED", summary.read_text())
        self.assertEqual(fake.calls, [], "nothing was sent")

    def test_required_makes_a_missing_key_fail(self):
        code, text = run(cfg(key="", required=True), Fake())
        self.assertEqual(code, 1)
        self.assertIn("cloud-test FAILED: missing ROBLOX_API_KEY", text)

    def test_the_env_missing_dry_run_says_skipped(self):
        code = rt.main(["--dry-run"], {})
        self.assertEqual(code, 0)

    def test_dry_run_with_a_key_sends_nothing(self):
        fake = Fake()
        code, text = run(cfg(dry_run=True), fake)
        self.assertEqual(code, 0)
        self.assertIn("dry run", text)
        self.assertEqual(fake.calls, [])


class Flow(unittest.TestCase):
    def test_a_passing_run_publishes_once_makes_one_task_polls_every_3s_and_prints_logs(self):
        fake = Fake()
        code, text = run(cfg(), fake)
        self.assertEqual(code, 0, text)
        self.assertEqual(len(fake.tasks_created()), 1, "exactly one task per run")
        publishes = [c for c in fake.calls if "/universes/v1/" in c[1]]
        self.assertEqual(len(publishes), 1)
        self.assertTrue(publishes[0][1].endswith("/places/" + rt.TEST_PLACE_ID + "/versions?versionType=Saved"))
        self.assertIn(rt.TEST_UNIVERSE_ID, publishes[0][1])
        self.assertEqual(publishes[0][3], b"rbxl")
        self.assertEqual(fake.tasks_created()[0][1].split("/versions/")[1].split("/")[0], "7", "the task runs on the version just published")
        self.assertEqual(fake.sleeps, [3, 3], "polled every 3 seconds")
        self.assertIn("[cloud-test] lint: 0 finding(s)", text)
        self.assertIn("cloud-test PASSED", text)
        for method, url, headers, body in fake.calls:
            self.assertEqual(headers["x-api-key"], KEY)
        self.assertNotIn(KEY, text, "the key is never printed")

    def test_a_publish_500_is_retried_and_a_400_is_not(self):
        class Flaky(Fake):
            def __init__(self, codes, **kw):
                super().__init__(**kw)
                self.codes = list(codes)

            def http(self, method, url, headers, body):
                if "/universes/v1/" in url and self.codes:
                    self.calls.append((method, url, dict(headers), body))
                    code = self.codes.pop(0)
                    if code != 200:
                        return code, b'{"title":"boom"}'
                    return 200, b'{"versionNumber": 7}'
                return super().http(method, url, headers, body)

        f = Flaky([500, 200])
        out = []
        self.assertEqual(rt.run(cfg(), http=f.http, sleep=lambda s: None, clock=lambda: 0.0, out=out.append), 0)
        self.assertEqual(sum(1 for c in f.calls if "/universes/v1/" in c[1]), 2)
        f = Flaky([500, 500, 500])
        self.assertEqual(rt.run(cfg(), http=f.http, sleep=lambda s: None, clock=lambda: 0.0, out=out.append), 1)
        self.assertEqual(sum(1 for c in f.calls if "/universes/v1/" in c[1]), 3)
        f = Flaky([400])
        self.assertEqual(rt.run(cfg(), http=f.http, sleep=lambda s: None, clock=lambda: 0.0, out=out.append), 1)
        self.assertEqual(sum(1 for c in f.calls if "/universes/v1/" in c[1]), 1)

    def test_the_task_timeout_is_inside_the_api_limit(self):
        fake = Fake()
        run(cfg(), fake)
        body = json.loads(fake.tasks_created()[0][3])
        seconds = int(body["timeout"].rstrip("s"))
        self.assertTrue(1 <= seconds <= 300, body["timeout"])
        self.assertEqual(body["script"], "return 1")

    def test_only_the_test_place_is_in_every_url(self):
        fake = Fake()
        run(cfg(), fake)
        for _, url, _, _ in fake.calls:
            if "/places/" in url:
                self.assertIn("/places/" + rt.TEST_PLACE_ID + "/", url + "/")

    def test_a_failed_task_exits_1_and_prints_the_findings(self):
        fake = Fake(states=("PROCESSING", "FAILED"))
        code, text = run(cfg(), fake)
        self.assertEqual(code, 1)
        self.assertIn("cloud-test FAILED: task state FAILED", text)
        self.assertIn("line two", text)
        self.assertEqual(len(fake.tasks_created()), 1)

    def test_401_403_409_fail_with_the_code_and_no_task(self):
        for status in (401, 403, 409):
            fake = Fake(publish=(status, {"message": f"nope {KEY}"}))
            code, text = run(cfg(), fake)
            self.assertEqual(code, 1)
            self.assertIn(f"HTTP {status}", text)
            self.assertNotIn(KEY, text, "the key is redacted from the server's words too")
            self.assertEqual(fake.tasks_created(), [], "no task after a refused publish")

    def test_a_refused_task_creation_fails_with_its_code(self):
        for status in (401, 403, 409):
            fake = Fake(create=(status, {"message": "no"}))
            code, text = run(cfg(), fake)
            self.assertEqual(code, 1)
            self.assertIn(f"HTTP {status}", text)
            self.assertEqual(len(fake.tasks_created()), 1, "one attempt, never a second task")

    def test_it_gives_up_after_the_timeout(self):
        fake = Fake(states=("PROCESSING",))
        code, text = run(cfg(timeout=9), fake)
        self.assertEqual(code, 1)
        self.assertIn("timed out", text)


if __name__ == "__main__":
    unittest.main()
