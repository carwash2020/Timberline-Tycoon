#!/usr/bin/env python3
"""Read a .glb and report what the Roblox import limits care about.

Pure Python (no Blender, no numpy): triangles, materials per mesh, UV range,
embedded texture sizes and the bounds in studs (1 unit = 1 stud) after node
transforms. Used by check.py and registry.py.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


def load(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path} is not a GLB")
    offset = 12
    doc: dict | None = None
    blob = b""
    while offset + 8 <= len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        offset += 8 + length
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
    if doc is None:
        raise ValueError(f"{path} has no JSON chunk")
    return doc, blob


def read_accessor(doc: dict, blob: bytes, index: int) -> list[tuple]:
    acc = doc["accessors"][index]
    count = acc["count"]
    width = COMPONENTS[acc["type"]]
    fmt = FORMATS[acc["componentType"]]
    if "bufferView" not in acc:
        return [tuple([0] * width)] * count
    view = doc["bufferViews"][acc["bufferView"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    item = struct.calcsize("<" + fmt * width)
    stride = view.get("byteStride") or item
    out = []
    for i in range(count):
        out.append(struct.unpack_from("<" + fmt * width, blob, base + i * stride))
    return out


def mat_mul(a: list[float], b: list[float]) -> list[float]:
    # column-major 4x4
    out = [0.0] * 16
    for col in range(4):
        for row in range(4):
            out[col * 4 + row] = sum(a[k * 4 + row] * b[col * 4 + k] for k in range(4))
    return out


def node_matrix(node: dict) -> list[float]:
    if "matrix" in node:
        return [float(v) for v in node["matrix"]]
    tx, ty, tz = node.get("translation", [0, 0, 0])
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    r = [
        1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw), 0,
        2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw), 0,
        2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy), 0,
        0, 0, 0, 1,
    ]
    s = [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, 0, 0, 0, 1]
    t = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, tx, ty, tz, 1]
    return mat_mul(t, mat_mul(r, s))


def apply(m: list[float], p: tuple) -> tuple[float, float, float]:
    x, y, z = p[0], p[1], p[2]
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def png_size(raw: bytes) -> tuple[int, int] | None:
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", raw[16:24])
    if raw[:2] == b"\xff\xd8":
        i = 2
        while i < len(raw):
            if raw[i] != 0xFF:
                i += 1
                continue
            marker = raw[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", raw[i + 5 : i + 9])
                return w, h
            length = struct.unpack(">H", raw[i + 2 : i + 4])[0]
            i += 2 + length
    return None


def stats(path: Path) -> dict:
    doc, blob = load(path)
    meshes = doc.get("meshes") or []
    nodes = doc.get("nodes") or []
    tris = 0
    per_mesh: dict[str, dict] = {}
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    uv_lo, uv_hi = math.inf, -math.inf

    def visit(index: int, parent: list[float]):
        nonlocal tris, uv_lo, uv_hi
        node = nodes[index]
        world = mat_mul(parent, node_matrix(node))
        mesh_index = node.get("mesh")
        if isinstance(mesh_index, int):
            mesh = meshes[mesh_index]
            name = node.get("name") or mesh.get("name") or f"mesh{mesh_index}"
            entry = per_mesh.setdefault(name, {"tris": 0, "materials": set(), "ngons": 0})
            for prim in mesh.get("primitives", []):
                mode = prim.get("mode", 4)
                attrs = prim.get("attributes", {})
                pos = doc["accessors"][attrs["POSITION"]]
                if "indices" in prim:
                    n = doc["accessors"][prim["indices"]]["count"]
                else:
                    n = pos["count"]
                t = n // 3 if mode == 4 else 0
                if mode != 4:
                    entry["ngons"] += 1
                tris += t
                entry["tris"] += t
                entry["materials"].add(prim.get("material", -1))
                pmin, pmax = pos.get("min"), pos.get("max")
                if pmin and pmax:
                    for cx in (pmin[0], pmax[0]):
                        for cy in (pmin[1], pmax[1]):
                            for cz in (pmin[2], pmax[2]):
                                w = apply(world, (cx, cy, cz))
                                for k in range(3):
                                    lo[k] = min(lo[k], w[k])
                                    hi[k] = max(hi[k], w[k])
                if "TEXCOORD_0" in attrs:
                    uv = doc["accessors"][attrs["TEXCOORD_0"]]
                    if uv.get("min") and uv.get("max"):
                        uv_lo = min(uv_lo, *uv["min"])
                        uv_hi = max(uv_hi, *uv["max"])
                    else:
                        for u, v in read_accessor(doc, blob, attrs["TEXCOORD_0"]):
                            uv_lo = min(uv_lo, u, v)
                            uv_hi = max(uv_hi, u, v)
        for child in node.get("children", []):
            visit(child, world)

    identity = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
    scenes = doc.get("scenes") or [{"nodes": list(range(len(nodes)))}]
    roots = scenes[doc.get("scene", 0)].get("nodes", [])
    for root in roots:
        visit(root, identity)

    textures = []
    for image in doc.get("images") or []:
        if "bufferView" in image:
            view = doc["bufferViews"][image["bufferView"]]
            raw = blob[view.get("byteOffset", 0) : view.get("byteOffset", 0) + view["byteLength"]]
            size = png_size(raw)
            textures.append({"name": image.get("name", ""), "size": list(size) if size else None})

    size = [round(hi[k] - lo[k], 3) if hi[k] > lo[k] else 0.0 for k in range(3)]
    return {
        "file": path.as_posix(),
        "bytes": path.stat().st_size,
        "tris": tris,
        "meshes": {
            k: {"tris": v["tris"], "materials": len(v["materials"]), "ngons": v["ngons"]} for k, v in per_mesh.items()
        },
        "bounds": {"min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]} if size[0] else None,
        "size": size,
        "uv": [round(uv_lo, 4), round(uv_hi, 4)] if uv_lo != math.inf else None,
        "textures": textures,
    }


if __name__ == "__main__":
    import sys

    for arg in sys.argv[1:]:
        print(json.dumps(stats(Path(arg)), indent=1))
