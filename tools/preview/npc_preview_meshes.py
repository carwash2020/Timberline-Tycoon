#!/usr/bin/env python3
"""Write the preview-only manifest for the NPC GLBs and say how to use it.

The five Blender NPCs (Hermit, Old Tolly, Cap'n Moss, Old Hank, the Foreman)
have their GLBs under assets/glb/backlog/npcs/<Name>/<Name>.glb, not in
assets/meshes, so the renderer needs a PREVIEW_MESHES manifest (export.luau).
Piece names, mesh ids and sizes are read from TownModels.luau, so the manifest
and the game's rows cannot drift. Murph's own GLBs (assets/meshes) are added as
a calibration figure. Every entry carries "turn": 180: the game's FBX import
turns these meshes a half turn from the GLB (TownModels.NpcMeshYaw), and
NPCMeshes adds that yaw, so the preview needs the same turn (viewer.html).

  python3 tools/preview/npc_preview_meshes.py
  PREVIEW_MESHES=preview/npc-meshes.json bash tools/preview/shoot.sh v1-e-npcs
"""

import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
FIVE = ("Hermit", "OldTolly", "CapnMoss", "OldHank", "Foreman")


def main():
	src = open(os.path.join(ROOT, "src/ReplicatedStorage/Shared/Art/TownModels.luau")).read()
	out = {}
	for name in FIVE:
		start = src.index(f'id = "{name}"')
		block = src[start : src.index("\n\t},\n", start)]
		glb = os.path.abspath(os.path.join(ROOT, f"assets/glb/backlog/npcs/{name}/{name}.glb"))
		for piece, mesh_id, x, y, z in re.findall(
			r'name = "(\w+)", meshId = (\d+), size = V\(([\d.]+), ([\d.]+), ([\d.]+)\)', block
		):
			out[mesh_id] = {"file": glb, "node": piece, "initialSize": [float(x), float(y), float(z)], "turn": 180}
	manifest = json.load(open(os.path.join(ROOT, "assets/meshes/manifest.json")))
	for mesh_id, info in manifest.items():
		if info["file"].startswith("npcs/Murph/"):
			out[mesh_id] = {
				"file": os.path.abspath(os.path.join(ROOT, "assets/meshes", info["file"])),
				"node": info["node"],
				"initialSize": info["initialSize"],
				"turn": 180,
			}
	os.makedirs(os.path.join(ROOT, "preview"), exist_ok=True)
	path = os.path.join(ROOT, "preview", "npc-meshes.json")
	json.dump(out, open(path, "w"))
	print(f"wrote {path} ({len(out)} meshes)")


if __name__ == "__main__":
	main()
