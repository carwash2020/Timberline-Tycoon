#!/usr/bin/env python3
"""A preview-only mesh manifest for the machine meshes (job 15, K wire-in).

The Blender machine GLBs are in the handoff pack, not in the repo (the game
loads them from Roblox). tools/preview/export.luau reads PREVIEW_MESHES, a
JSON of { "<meshId>": { "file": "<abs path to the .glb>", "node": "<piece>",
"initialSize": [x, y, z] } }, so the review shots draw the real meshes.

  python3 tools/preview/v1_k_manifest.py <pack root> <out.json>
  PREVIEW_MESHES=<out.json> bash tools/preview/shoot.sh v1-k

The ids and sizes are read from src/ReplicatedStorage/Shared/Art/MachineMeshes.luau,
so what is drawn is what the game asks MeshKit for. A machine whose GLB is not
in the pack is listed and skipped (the game keeps its part build there, and
the preview shows that part build, never a stand-in).
Pack layout: assets/models/machines-tld1/<Name>/<Name>.glb (TLD-1 line kit)
and assets/models/machines/<Name>/<Name>.glb (the older pieces).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SOURCE = Path("src/ReplicatedStorage/Shared/Art/MachineMeshes.luau")

ASSET = re.compile(r"^\t(\w+) = \{$")
SOURCE_LINE = re.compile(r'^\t\tsource = "(\w+)",$')
PIECE = re.compile(
    r'^\t\t\t\{ name = "(\w+)", meshId = (\d+), size = V3\(([-\d., ]+)\), offset = V3\(([-\d., ]+)\) \},$'
)


def parse() -> dict:
    assets: dict = {}
    current = None
    in_assets = False
    for line in SOURCE.read_text().splitlines():
        if line.startswith("local ASSETS"):
            in_assets = True
            continue
        if line.startswith("local LAYOUT"):
            break
        if not in_assets:
            continue
        m = ASSET.match(line)
        if m:
            current = {"source": None, "pieces": []}
            assets[m.group(1)] = current
            continue
        if current is None:
            continue
        m = SOURCE_LINE.match(line)
        if m:
            current["source"] = m.group(1)
            continue
        m = PIECE.match(line)
        if m:
            size = [float(v) for v in m.group(3).split(",")]
            current["pieces"].append({"name": m.group(1), "meshId": int(m.group(2)), "size": size})
    return assets


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    pack = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve()
    assets = parse()
    manifest: dict = {}
    missing: list[str] = []
    for name, asset in assets.items():
        folder = "machines-tld1" if asset["source"] == "tld1" else "machines"
        glb = pack / "assets" / "models" / folder / name / f"{name}.glb"
        if not glb.is_file():
            missing.append(f"{name} ({folder})")
            continue
        for piece in asset["pieces"]:
            manifest[str(piece["meshId"])] = {
                "file": str(glb),
                "node": piece["name"],
                "initialSize": piece["size"],
            }
    out.write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"{len(manifest)} mesh ids from {len(assets) - len(missing)} of {len(assets)} machines -> {out}")
    if missing:
        print("no GLB in the pack for: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
