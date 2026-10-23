#!/usr/bin/env python3
"""Writes build/cloud.project.json: default.project.json plus the cloud runner.

    python3 tools/cloud/make_project.py && rojo build build/cloud.project.json -o build/test.rbxl

The game's own project file stays as it is (the shipping place never carries the test runner). This
adds ServerStorage.CloudTests: tests/cloud (the runner) with the two data files the checks read
(tests/geometry_allow.json, tests/mustkeep.json) as modules beside it. Paths are rewritten relative to
build/ so Rojo finds the sources.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def rewrite(node, base: Path):
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            if k == "$path" and isinstance(v, str):
                out[k] = os.path.relpath(REPO / v, base)
            else:
                out[k] = rewrite(v, base)
        return out
    return node


def make(out_dir: Path) -> Path:
    project = json.loads((REPO / "default.project.json").read_text())
    tree = project["tree"]
    tree["ServerStorage"] = {
        "$className": "ServerStorage",
        "CloudTests": {
            "$path": "tests/cloud",
            "geometry_allow": {"$path": "tests/geometry_allow.json"},
            "mustkeep": {"$path": "tests/mustkeep.json"},
        },
    }
    project["name"] = project.get("name", "TimberlineTycoon") + "Cloud"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "cloud.project.json"
    path.write_text(json.dumps(rewrite(project, out_dir), indent=2) + "\n")
    return path


if __name__ == "__main__":
    print(make(Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "build"))
