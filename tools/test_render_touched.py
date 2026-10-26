#!/usr/bin/env python3
"""Tests for tools/render_touched.py: temporary git repos, each with a base commit on main and a PR
branch. Every failing case is a deliberate control: the check must say so."""

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_touched  # noqa: E402


class Repo:
    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="render_touched_")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.dir, check=True, capture_output=True)

    def write(self, path, data):
        full = os.path.join(self.dir, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)

    def commit(self, msg):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", msg)

    def findings(self):
        return render_touched.find("main", "HEAD", self.dir)


def repo_with_base():
    r = Repo()
    r.write("preview/a/old.png", b"OLD-RENDER")
    r.write("preview/a/other.png", b"OTHER")
    r.write("src/x.luau", b"x")
    r.commit("base")
    r.git("checkout", "-q", "-b", "pr")
    return r


class RenderTouched(unittest.TestCase):
    def test_a_changed_render_passes(self):
        r = repo_with_base()
        r.write("preview/a/old.png", b"NEW-RENDER")
        r.commit("re-render")
        self.assertEqual(r.findings(), [])

    def test_a_new_distinct_render_passes(self):
        r = repo_with_base()
        r.write("preview/b/new.png", b"BRAND-NEW")
        r.commit("add")
        self.assertEqual(r.findings(), [])

    def test_control_touched_but_reverted_fails(self):
        r = repo_with_base()
        r.write("preview/a/old.png", b"CHANGED")
        r.commit("touch")
        r.write("preview/a/old.png", b"OLD-RENDER")
        r.commit("put it back")
        found = r.findings()
        self.assertEqual(len(found), 1, found)
        self.assertIn("preview/a/old.png", found[0])
        self.assertIn("byte-identical", found[0])

    def test_control_a_new_path_that_copies_a_render_on_main_fails(self):
        r = repo_with_base()
        r.write("preview/b/after.png", b"OLD-RENDER")
        r.commit("the old render filed as new")
        found = r.findings()
        self.assertEqual(len(found), 1, found)
        self.assertIn("preview/a/old.png", found[0])
        self.assertIn("copy", found[0])

    def test_a_rename_is_a_move_not_a_copy(self):
        r = repo_with_base()
        r.git("mv", "preview/a/other.png", "preview/a/renamed.png")
        r.commit("rename")
        self.assertEqual(r.findings(), [])

    def test_control_an_after_shot_equal_to_its_before_fails(self):
        r = repo_with_base()
        r.write("preview/c/thing-before.png", b"SAME-BYTES")
        r.write("preview/c/thing-after.png", b"SAME-BYTES")
        r.commit("pair")
        found = r.findings()
        self.assertEqual(len(found), 1, found)
        self.assertIn("thing-after.png", found[0])

    def test_only_pngs_under_preview_count(self):
        r = repo_with_base()
        r.write("docs/shot.png", b"OLD-RENDER")
        r.write("preview/a/notes.txt", b"OLD-RENDER")
        r.commit("not renders")
        self.assertEqual(r.findings(), [])

    def test_the_cli_skips_without_a_base_ref(self):
        r = Repo()
        r.write("preview/a.png", b"x")
        r.commit("only")
        cwd = os.getcwd()
        os.chdir(r.dir)
        try:
            self.assertEqual(render_touched.main(["--base", "origin/main"]), 0)
        finally:
            os.chdir(cwd)

    def test_the_cli_exits_one_on_a_finding(self):
        r = repo_with_base()
        r.write("preview/b/after.png", b"OLD-RENDER")
        r.commit("copy")
        cwd = os.getcwd()
        os.chdir(r.dir)
        try:
            self.assertEqual(render_touched.main(["--base", "main"]), 1)
        finally:
            os.chdir(cwd)


if __name__ == "__main__":
    unittest.main()
