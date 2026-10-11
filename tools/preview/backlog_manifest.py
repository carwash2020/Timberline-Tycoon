#!/usr/bin/env python3
"""Preview-only mesh manifest for the uploaded Blender backlog (job 17).

Reads Shared/Art/BacklogModels.luau (and the backlog rows in TreeModels.luau
for the three new woods), finds each piece's node in its GLB under
assets/glb/backlog/<group>/<Name>/<Name>.glb (trees: <Wood>/<Piece>.glb) and
writes preview/backlog-meshes.json:

  { "<meshId>": { "file": "../assets/glb/...", "node": ..., "initialSize": [...] } }

Export with PREVIEW_MESHES=preview/backlog-meshes.json (shoot.sh passes the
environment through). The game never reads it. Exits non-zero when a piece
has no GLB or no node of that name, so a preview cannot quietly draw a
MISSING MESH box.

  python3 tools/preview/backlog_manifest.py
"""

from __future__ import annotations

import importlib.util
import json
import re
import struct
import sys
from pathlib import Path

GROUPS = {
    "shop": "shops",
    "gear": "gear",
    "landmark": "landmarks",
    "furniture": "furniture",
    "plant": "plants",
    "cave": "cave",
    "critter": "critters",
    "polish": "polish",
    "environment": "environment",
}
# BacklogModels ids renamed to avoid a TownModels clash -> the GLB's name.
RENAMED = {"GearLantern": "Lantern", "PlantBush": "Bush", "StoreBoardV1": "StoreBoard",
           "SawdustPileV2": "SawdustPile", "PathRoundV2": "PathRound"}
WOODS = {"lanternwood": "Lanternwood", "bogcypress": "BogCypress", "ironwood": "Ironwood"}
ROOT = Path("assets/glb/backlog")


def nodes(path: Path) -> set[str]:
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20 : 20 + length])
    names = {n.get("name", "") for n in doc.get("nodes", [])}
    names |= {m.get("name", "") for m in doc.get("meshes", [])}
    return names


def centres_of(path: Path) -> dict[str, list[float]]:
    spec = importlib.util.spec_from_file_location("a2", "tools/preview/v1_a2_meshes.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.glb_centres(path)


def main() -> int:
    src = Path("src/ReplicatedStorage/Shared/Art/BacklogModels.luau").read_text()
    out: dict[str, dict] = {}
    centres: dict[str, list[float]] = {}
    bad = 0
    # rows: id, category, then pieces
    for m in re.finditer(r'id = "(\w+)",\s*category = "(\w+)",.*?pieces = \{(.*?)\n\t\t\},', src, re.S):
        aid, cat, body = m.group(1), m.group(2), m.group(3)
        if cat == "npc":
            continue
        name = RENAMED.get(aid, aid)
        glb = ROOT / GROUPS[cat] / name / f"{name}.glb"
        if not glb.is_file():
            print("missing", glb)
            bad += 1
            continue
        have = nodes(glb)
        for pm in re.finditer(r'name = "(\w+)", meshId = (\d+), size = V\(([^)]*)\)', body):
            piece, mid, size = pm.group(1), pm.group(2), [float(x) for x in pm.group(3).split(",")]
            if piece not in have:
                print(f"{aid}: no node {piece} in {glb}")
                bad += 1
                continue
            out[mid] = {"file": "../" + str(glb), "node": piece, "initialSize": size}
            try:
                found = centres_of(glb).get(piece)
            except AssertionError:
                found = None  # a rotated node: the scene keeps TownMeshes' ground stand
            if found is not None:
                centres[mid] = found
    trees = Path("src/ReplicatedStorage/Shared/Art/TreeModels.luau").read_text()
    for wood, folder in WOODS.items():
        # crowns: Leaves_A.. / Facet_A.. in file order; sections from the sections table
        sec = re.search(wood + r" = \{ (\d+), (\d+), (\d+) \},", trees)
        crown = re.search(r"\n\t" + wood + r" = \{\n(.*?)\n\t\},", trees, re.S)
        files = sorted((ROOT / "trees" / folder).glob("*.glb"))
        by_stem = {f.stem: f for f in files}
        ids = {}
        if sec:
            for i in range(3):
                ids[f"Section_{i + 1}"] = (sec.group(i + 1), None)
        if crown:
            counters = {"Leaves": 0, "Facet": 0}
            for pm in re.finditer(
                r'name = "(\w+)", meshId = (\d+), size = Vector3\.new\(([^)]*)\), section = (\w+)', crown.group(1)
            ):
                kind, mid, size, section = pm.group(1), pm.group(2), pm.group(3), pm.group(4)
                if kind == "Knees":
                    stem = "Knees_A"
                elif kind == "Facet" and section != "nil":
                    stem = f"Facet_Section_{section}"
                else:
                    stem = f"{kind}_{'ABC'[counters[kind]]}"
                    counters[kind] += 1
                ids[stem] = (mid, [float(x) for x in size.split(",")])
        for stem, (mid, size) in ids.items():
            f = by_stem.get(stem)
            if f is None:
                print("missing tree piece", folder, stem)
                bad += 1
                continue
            n = nodes(f)
            node = sorted(x for x in n if x and x not in ("Scene", "Sketchfab_model"))[0]
            # GLTFLoader drops the dots from "Leaves.001"; the viewer looks the node up by that name.
            node = (stem if stem in n else node).replace(".", "")
            out[mid] = {"file": "../" + str(f), "node": node, "initialSize": size or [2, 4, 2]}
    Path("preview").mkdir(exist_ok=True)
    Path("preview/backlog-meshes.json").write_text(json.dumps(out, indent=1))
    Path("preview/backlog-centres.json").write_text(json.dumps(centres, indent=1))
    print(f"preview/backlog-centres.json: {len(centres)} piece centres")
    print(f"preview/backlog-meshes.json: {len(out)} pieces, {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
