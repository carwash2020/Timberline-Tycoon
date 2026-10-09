#!/usr/bin/env python3
"""Preview-only mesh manifest for the A2 (end game) previews.

The Sky Forge Court, Starfall Forge and Gondola Cabin were uploaded on Oct 8
(assets/uploaded-backlog.json in the handoff pack) but are wired in game by
job 17, so their GLBs are not in assets/meshes yet. This writes
preview/a2-meshes.json, mapping each uploaded piece's meshId to its GLB node,
for tools/preview/export.luau (PREVIEW_MESHES=preview/a2-meshes.json).

  python3 tools/preview/v1_a2_meshes.py /workspace/roblox/handoff/assets

Checks that every piece name is a node in its GLB. The game never reads this.

It also writes preview/a2-centres.json: where each piece of the town models
in these shots (GondolaStation, Signpost, PlotSign) sits in its model, read from the
GLB (the GLB's model space is the part-built model's space). In Studio a
piece loaded from the uploaded model keeps that place (MeshKit marks its
pivot "authored"); Lune has no pivots, so TownMeshes stands every piece on
the ground. The scene moves each piece to its GLB place instead.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

MODELS = ["SkyForgeCourt", "StarfallForge", "GondolaCabin"]


def glb_nodes(path: Path) -> set[str]:
	data = path.read_bytes()
	length = struct.unpack_from("<I", data, 12)[0]
	doc = json.loads(data[20 : 20 + length])
	names = {n.get("name", "") for n in doc.get("nodes", [])}
	names |= {m.get("name", "") for m in doc.get("meshes", [])}
	return names


TOWN_FILES = [
	"environment/Signpost/Signpost.glb",
	"buildings/GondolaStation/GondolaStation.glb",
	"items/PlotSign/PlotSign.glb",
]


def glb_centres(path: Path) -> dict[str, list[float]]:
	"""Each mesh node's bounds centre in model space (no node rotations here)."""
	data = path.read_bytes()
	length = struct.unpack_from("<I", data, 12)[0]
	doc = json.loads(data[20 : 20 + length])
	out = {}
	for node in doc.get("nodes", []):
		if "mesh" not in node:
			continue
		assert "rotation" not in node, f"{path.name}: {node.get('name')} is rotated"
		lo, hi = [1e9] * 3, [-1e9] * 3
		for prim in doc["meshes"][node["mesh"]]["primitives"]:
			acc = doc["accessors"][prim["attributes"]["POSITION"]]
			lo = [min(a, b) for a, b in zip(lo, acc["min"])]
			hi = [max(a, b) for a, b in zip(hi, acc["max"])]
		t = node.get("translation", [0, 0, 0])
		sc = node.get("scale", [1, 1, 1])
		out[node["name"]] = [round((a + b) / 2 * k + o, 4) for a, b, k, o in zip(lo, hi, sc, t)]
	return out


def town_centres() -> dict[str, list[float]]:
	manifest = json.loads(Path("assets/meshes/manifest.json").read_text())
	cache: dict[str, dict[str, list[float]]] = {}
	out = {}
	for mesh_id, info in manifest.items():
		if info.get("file") in TOWN_FILES:
			if info["file"] not in cache:
				cache[info["file"]] = glb_centres(Path("assets/meshes") / info["file"])
			centre = cache[info["file"]].get(info["node"])
			if centre is not None:
				out[mesh_id] = centre
	return out


def main() -> int:
	root = Path(sys.argv[1] if len(sys.argv) > 1 else "/workspace/roblox/handoff/assets")
	uploads = json.loads((root / "uploaded-backlog.json").read_text())
	found = {}
	for category in uploads.values():
		if isinstance(category, dict):
			for name, entry in category.items():
				if name in MODELS and isinstance(entry, dict) and "pieces" in entry:
					found[name] = entry
	out = {}
	for name in MODELS:
		entry = found.get(name)
		if entry is None:
			print(f"missing {name} in uploaded-backlog.json")
			return 1
		glb = root / "models" / "backlog" / Path(entry["file"]).with_suffix(".glb")
		if not glb.is_file():
			print(f"missing {glb}")
			return 1
		nodes = glb_nodes(glb)
		for piece, info in entry["pieces"].items():
			if piece not in nodes:
				print(f"{name}: no node {piece} in {glb.name}")
				return 1
			mesh_id = "".join(ch for ch in info["meshId"] if ch.isdigit())
			out[mesh_id] = {"file": str(glb.resolve()), "node": piece, "initialSize": info["initialSize"], "model": name}
	dest = Path("preview")
	dest.mkdir(exist_ok=True)
	(dest / "a2-meshes.json").write_text(json.dumps(out, indent=1))
	print(f"preview/a2-meshes.json: {len(out)} pieces")
	centres = town_centres()
	(dest / "a2-centres.json").write_text(json.dumps(centres, indent=1))
	print(f"preview/a2-centres.json: {len(centres)} town pieces")
	return 0


if __name__ == "__main__":
	sys.exit(main())
