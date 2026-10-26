#!/usr/bin/env python3
"""Fails a pull request that "touches" a render without changing it (T420).

A render is a PNG under preview/. Two ways a PR can fake a change, both caught here:

  1. TOUCHED BUT UNCHANGED: a commit in the PR lists the PNG, but at the PR's head its bytes
     (git blob hash) equal the PNG at the same path on the base (a re-save, or an edit reverted by
     a later commit). The PR then claims a new render and shows the old one.
  2. A COPY: a PNG the PR adds is byte-identical to a PNG that is already on the base under another
     path (the old render filed again as the new one). A rename (the old path is gone at head) is
     a move, not a copy, and is allowed.
  3. A BEFORE/AFTER PAIR WITH NO DIFFERENCE: the PR touches X-after.png and X-before.png exists at
     head with the same bytes.

What it cannot see: a re-render whose bytes did not change leaves nothing in git (no diff, no
commit entry), so there is nothing to "touch". The shot tool is deterministic enough that an
unchanged scene gives the same bytes; the author has to say which renders are unchanged.
Only PNGs under preview/ are looked at. A new path with no copy on the base has nothing to compare.

  python3 tools/render_touched.py [--base REF] [--head REF]

--base defaults to $RENDER_BASE, then origin/main. Exits 0 when clean (or when there is no base ref to
compare with: prints a skip line), 1 on findings.
"""

import argparse
import os
import subprocess
import sys


def git(args, cwd, check=True):
    res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and res.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(args), res.stderr.strip()))
    return res.stdout


def blob(ref, path, cwd):
    res = subprocess.run(["git", "rev-parse", "--verify", "-q", "%s:%s" % (ref, path)], cwd=cwd, capture_output=True, text=True)
    return res.stdout.strip() if res.returncode == 0 else None


def is_render(path):
    return path.startswith("preview/") and path.lower().endswith(".png")


def find(base, head, cwd="."):
    """The findings (a list of lines) for the PR from `base` to `head`."""
    mb = git(["merge-base", base, head], cwd).strip()
    findings = []

    # Every PNG a commit of the PR lists (even when the net change is nothing).
    touched = set()
    for line in git(["log", "--name-only", "--format=", "%s..%s" % (mb, head), "--", "preview"], cwd).splitlines():
        if line and is_render(line):
            touched.add(line)
    # Net status of the PR: A/M/D/R (a rename's old path is gone at head).
    status = {}
    removed = set()
    for line in git(["diff", "--name-status", "-M100%", mb, head, "--", "preview"], cwd).splitlines():
        parts = line.split("\t")
        code = parts[0][0]
        if code == "R":
            removed.add(parts[1])
            status[parts[2]] = "R"
            touched.add(parts[2])
        elif code == "D":
            removed.add(parts[1])
        elif is_render(parts[1]):
            status[parts[1]] = code
            touched.add(parts[1])

    base_blobs = {}  # blob hash -> a path on the base, for PNGs still present at head
    for line in git(["ls-tree", "-r", mb, "--", "preview"], cwd).splitlines():
        meta, path = line.split("\t", 1)
        if is_render(path) and path not in removed:
            base_blobs.setdefault(meta.split()[2], path)

    for path in sorted(touched):
        mine = blob(head, path, cwd)
        if mine is None:
            continue  # deleted
        theirs = blob(mb, path, cwd)
        if theirs is not None:
            if mine == theirs:
                findings.append("%s: touched by the PR but byte-identical to %s (%s)" % (path, mb[:8], mine[:10]))
        elif status.get(path) != "R":
            other = base_blobs.get(mine)
            if other is not None:
                findings.append("%s: new, but byte-identical to %s already on the base: a copy, not a new render" % (path, other))
        if path.endswith("-after.png"):
            pair = path[: -len("-after.png")] + "-before.png"
            if blob(head, pair, cwd) == mine:
                findings.append("%s: byte-identical to %s: the after shot shows no change" % (path, pair))
    return findings


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=os.environ.get("RENDER_BASE") or "origin/main")
    ap.add_argument("--head", default="HEAD")
    args = ap.parse_args(argv)
    ok = subprocess.run(["git", "rev-parse", "--verify", "-q", args.base + "^{commit}"], capture_output=True).returncode == 0
    if not ok:
        print("render check SKIPPED: no base ref %s to compare with" % args.base)
        return 0
    findings = find(args.base, args.head)
    for line in findings:
        print("[render-touched] " + line)
    if findings:
        print("render check FAILED: %d render(s) touched without a change" % len(findings))
        return 1
    print("render check passed (base %s)" % args.base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
