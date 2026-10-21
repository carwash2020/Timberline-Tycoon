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
  - a building (a GLB under assets/meshes/buildings with Roof and Collision nodes) whose Roof node has a vertex
    above y PORCH_FLOOR_Y inside the front wall's face band (see below; T404)
Bounds against the part-built model are not checked here: the part-built
sizes live in Luau and Studio. The registry spec (tests/BlenderAssets.spec)
checks the recorded sizes instead.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glbstats import stats, vertices  # noqa: E402

MAX_TRIS = 20000
MAX_TEXTURE = 1024
MAX_BYTES = 5 * 1024 * 1024
UV_SLACK = 0.001

# T404: a building's porch roof stands IN FRONT of its front wall. A Roof vertex above a door's height (PORCH_FLOOR_Y)
# that sits within FACE_BAND of the front wall's outside plane (the front, min Z, face of the Collision node) pokes
# through the wall face or z-fights it from inside. Measured on the repo's building GLBs none does (Sawmill included:
# its mesh is fine, the clipping it showed came from the code-built parts). This is a narrow rule: the wording of the
# ticket ("between the front wall plane and the wall thickness") cannot tell a wall from a porch roof by vertices
# alone, since the wall itself stands there, so only the Roof node is scanned and the band is the face itself.
PORCH_FLOOR_Y = 8.0
FACE_BAND = 0.1


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


def porch_problems(path: Path) -> list[str]:
    """Roof vertices above PORCH_FLOOR_Y inside FACE_BAND of a building's front wall plane."""
    if "buildings" not in path.parts:
        return []
    verts = vertices(path)
    if "Roof" not in verts or "Collision" not in verts:
        return []
    front = min(v[2] for v in verts["Collision"])
    bad = [v for v in verts["Roof"] if v[1] > PORCH_FLOOR_Y and front <= v[2] <= front + FACE_BAND]
    if not bad:
        return []
    return [
        f"Roof: {len(bad)} vertices above y {PORCH_FLOOR_Y:g} within {FACE_BAND:g} of the front wall plane "
        f"(z {front:.2f}): a porch roof through the front wall"
    ]


def main(argv: list[str]) -> int:
    targets = [Path(a) for a in argv] or [Path("assets/meshes")]
    files: list[Path] = []
    for t in targets:
        files.extend(sorted(t.rglob("*.glb")) if t.is_dir() else [t])
    bad = 0
    for f in files:
        found = problems(f)
        found += porch_problems(f)
        if found:
            bad += 1
            for line in found:
                print(f"FAIL {f}: {line}")
    print(f"checked {len(files)} glb files, {bad} with problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
