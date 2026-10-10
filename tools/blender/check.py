#!/usr/bin/env python3
"""Check exported Blender meshes against the Roblox import limits.

    python3 tools/blender/check.py                 every .glb under assets/meshes
    python3 tools/blender/check.py path/a.glb ...  just these files or folders

Pure Python, no Blender needed (the GLB is what the preview renderer draws
and what was exported next to each uploaded FBX). Fails (exit 1) on:
  - a mesh over 20,000 triangles
  - a mesh with more than one material
  - a primitive that is not a triangle list (n-gons and strips)
  - UVs outside 0 to 1 (0.001 slack)
  - an embedded texture over 1024 px
  - a file over 5 MB
Bounds against the part-built model are not checked here: the part-built
sizes live in Luau and Studio. The registry spec (tests/BlenderAssets.spec)
checks the recorded sizes instead.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glbstats import stats  # noqa: E402

MAX_TRIS = 20000
MAX_TEXTURE = 1024
MAX_BYTES = 5 * 1024 * 1024
UV_SLACK = 0.001


def problems(path: Path) -> list[str]:
    out: list[str] = []
    s = stats(path)
    if s["bytes"] > MAX_BYTES:
        out.append(f"file is {s['bytes']} bytes (max {MAX_BYTES})")
    for name, mesh in s["meshes"].items():
        if mesh["tris"] > MAX_TRIS:
            out.append(f"{name}: {mesh['tris']} tris (max {MAX_TRIS})")
        if mesh["materials"] > 1:
            out.append(f"{name}: {mesh['materials']} materials (max 1)")
        if mesh["ngons"]:
            out.append(f"{name}: {mesh['ngons']} primitive(s) not a triangle list")
    uv = s["uv"]
    if uv and (uv[0] < -UV_SLACK or uv[1] > 1 + UV_SLACK):
        out.append(f"UVs run {uv[0]} to {uv[1]} (want 0 to 1)")
    for tex in s["textures"]:
        size = tex["size"]
        if size and max(size) > MAX_TEXTURE:
            out.append(f"texture {tex['name']} is {size[0]}x{size[1]} (max {MAX_TEXTURE})")
    return out


def main(argv: list[str]) -> int:
    targets = [Path(a) for a in argv] or [Path("assets/meshes")]
    files: list[Path] = []
    for t in targets:
        files.extend(sorted(t.rglob("*.glb")) if t.is_dir() else [t])
    bad = 0
    for f in files:
        found = problems(f)
        if found:
            bad += 1
            for line in found:
                print(f"FAIL {f}: {line}")
    print(f"checked {len(files)} glb files, {bad} with problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
