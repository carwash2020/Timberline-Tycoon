#!/usr/bin/env python3
"""Copy custom meshes and rebuild assets/meshes/manifest.json.

Reads uploaded_assets.json (meshId, piece name, initialSize, source file)
and the matching .glb next to each upload. Confirms the piece name is a
node or mesh name inside that GLB. Writes:

  assets/meshes/<same relative path as the .glb>
  assets/meshes/manifest.json   { "<meshId>": { "file", "node", "initialSize" } }

Usage (from the repo root):

  python3 tools/preview/build_mesh_manifest.py /workspace/roblox/models

No .blend, .blend1 or .fbx is copied. Exits non-zero if a meshId has no
matching node, a GLB is missing, or any GLB is over 5 MB.
"""

from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

MAX_BYTES = 5 * 1024 * 1024
DEST_ROOT = Path("assets/meshes")
SKIP_KEYS = {"_meta", "_failures", "_skippedVehicles"}


def gltf_json(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path} is not a GLB")
    offset = 12
    while offset + 8 <= len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        offset += 8 + length
        if kind == 0x4E4F534A:
            return json.loads(chunk)
    raise ValueError(f"{path} has no JSON chunk")


def node_names(doc: dict) -> dict[str, str]:
    """Map a piece name to the node name that carries it.

    Prefers a node whose own name matches. Falls back to a node whose mesh
    name matches, and records the node name (that is what the viewer clones).
    """
    meshes = doc.get("meshes") or []
    found: dict[str, str] = {}
    for node in doc.get("nodes") or []:
        name = node.get("name")
        mesh_index = node.get("mesh")
        mesh_name = None
        if isinstance(mesh_index, int) and 0 <= mesh_index < len(meshes):
            mesh_name = meshes[mesh_index].get("name")
        if isinstance(name, str) and name not in found:
            found[name] = name
        if isinstance(mesh_name, str) and mesh_name not in found and isinstance(name, str):
            found[mesh_name] = name
    return found


def numeric_id(value) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    if isinstance(value, float):
        return int(value) if value > 0 and value.is_integer() else None
    if isinstance(value, str):
        digits = "".join(ch for ch in value if ch.isdigit())
        if not digits:
            return None
        number = int(digits)
        return number if number > 0 else None
    return None


def iter_pieces(node, inherited_file: str | None = None):
    if isinstance(node, dict):
        source = node.get("file") or node.get("source") or inherited_file
        parts = node.get("meshParts")
        if isinstance(parts, list):
            for part in parts:
                if isinstance(part, dict):
                    yield source, part
        else:
            mesh_id = numeric_id(node.get("meshId"))
            name = node.get("name")
            size = node.get("initialSize")
            if mesh_id and isinstance(name, str) and isinstance(size, list):
                yield source, node
        for key, child in node.items():
            if key in SKIP_KEYS or key == "meshParts":
                continue
            yield from iter_pieces(child, source if isinstance(source, str) else inherited_file)
    elif isinstance(node, list):
        for child in node:
            yield from iter_pieces(child, inherited_file)


def glb_for(models: Path, source: str | None) -> Path | None:
    """The GLB that holds this upload.

    A combined model (vehicles/Pickup/Pickup.fbx) sits next to its GLB.
    Per-piece uploads (upload_staging/vehicles/Pickup/Body.fbx) have no GLB
    of their own: the piece is a node of that name in the combined GLB.
    Those staging ids are the ones the game asks MeshKit for.
    """
    if not source:
        return None
    rel = Path(source)
    candidate = models / rel.with_suffix(".glb")
    if candidate.is_file():
        return candidate
    parts = rel.parts
    if parts and parts[0] == "upload_staging" and len(parts) >= 3:
        group, asset = parts[1], parts[2]
        combined = models / group / asset / f"{asset}.glb"
        if combined.is_file():
            return combined
    return None


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 tools/preview/build_mesh_manifest.py <models dir>", file=sys.stderr)
        return 2
    models = Path(sys.argv[1]).resolve()
    uploaded = models / "uploaded_assets.json"
    if not uploaded.is_file():
        print(f"missing {uploaded}", file=sys.stderr)
        return 2
    catalog = json.loads(uploaded.read_text())

    repo = Path.cwd()
    dest_root = repo / DEST_ROOT
    if dest_root.exists():
        shutil.rmtree(dest_root)
    dest_root.mkdir(parents=True)

    copied: set[Path] = set()
    too_big: list[str] = []
    for glb in models.rglob("*.glb"):
        rel = glb.relative_to(models)
        if rel.parts[0] in {"upload_staging", "previews", "scripts"}:
            continue
        if glb.stat().st_size > MAX_BYTES:
            too_big.append(f"{rel} ({glb.stat().st_size} bytes)")
            continue
        target = dest_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(glb, target)
        copied.add(rel)

    names_cache: dict[Path, dict[str, str]] = {}
    manifest: dict[str, dict] = {}
    missing: list[str] = []
    conflicts: list[str] = []
    seen_ids: dict[str, str] = {}

    for source, part in iter_pieces(catalog):
        mesh_id = numeric_id(part.get("meshId"))
        piece = part.get("name")
        size = part.get("initialSize")
        if not mesh_id or not isinstance(piece, str) or not isinstance(size, list) or len(size) < 3:
            continue
        glb = glb_for(models, source if isinstance(source, str) else None)
        key = str(mesh_id)
        if glb is None:
            missing.append(f"{key} {piece}: no GLB for {source}")
            continue
        rel = glb.relative_to(models)
        if rel not in names_cache:
            try:
                names_cache[rel] = node_names(gltf_json(glb))
            except ValueError as err:
                missing.append(f"{key} {piece}: {err}")
                continue
        node = names_cache[rel].get(piece)
        if node is None:
            have = ", ".join(sorted(names_cache[rel])) or "(none)"
            missing.append(f"{key} {piece}: no node in {rel} (have {have})")
            continue
        file_rel = rel.as_posix()
        entry = {
            "file": file_rel,
            "node": node,
            "initialSize": [round(float(size[0]), 4), round(float(size[1]), 4), round(float(size[2]), 4)],
        }
        previous = seen_ids.get(key)
        signature = f"{file_rel}#{node}"
        if previous and previous != signature:
            # The same Roblox mesh id reused on another file (a shared wheel,
            # a kit collision, an NPC root). Keep the first file when the
            # piece name matches. A different piece name is a real clash.
            prev_node = previous.split("#", 1)[1]
            if prev_node != node:
                conflicts.append(f"{key}: {previous} vs {signature}")
            continue
        seen_ids[key] = signature
        manifest[key] = entry

    out = dest_root / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    print(f"copied {len(copied)} glb files")
    print(f"manifest {out}  {len(manifest)} mesh ids")
    if too_big:
        print(f"OVER 5 MB ({len(too_big)}):")
        for line in too_big:
            print("  " + line)
    if conflicts:
        print(f"CONFLICTS ({len(conflicts)}):")
        for line in conflicts:
            print("  " + line)
    if missing:
        print(f"MISSING ({len(missing)}):")
        for line in missing:
            print("  " + line)
    if too_big or conflicts or missing:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
