#!/usr/bin/env python3
"""T411 sawmill and Weigh House meshes.

Pure Python glTF writer (no Blender in this environment). This file is the
source: regenerate with `python3 tools/blender/t411_build.py`.

Studs are the scaled mesh frame (the part build x 1.5), the same space as
assets/meshes/lanes.json. Wood is a square box. Body and Collision stay out
of the slip, carriage, outfeed and cabin door; the one log on the slip sits
inside the existing allow box. The roof eave is forward of the collision's
front wall so the porch check passes.

Also drops the Sawmill `pending` boxes. Those were the old mesh's known hits;
a pending box that nothing enters fails meshlint, so they leave with the mesh.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LANES = ROOT / "assets" / "meshes" / "lanes.json"

HONEY = (0.769, 0.604, 0.388)
TIMBER = (0.478, 0.322, 0.188)
SLATE = (0.290, 0.310, 0.341)
STONE = (0.549, 0.529, 0.494)
IRON = (0.169, 0.169, 0.180)
BRASS = (0.788, 0.635, 0.290)
CREAM = (0.953, 0.906, 0.788)
INK = (0.18, 0.12, 0.08)
BARN = (0.620, 0.231, 0.180)
HEART = (0.886, 0.745, 0.518)
BIRCH = (0.847, 0.824, 0.769)


class Mesh:
    def __init__(self) -> None:
        self.pos: list[tuple[float, float, float]] = []
        self.nrm: list[tuple[float, float, float]] = []
        self.uv: list[tuple[float, float]] = []
        self.col: list[tuple[float, float, float, float]] = []
        self.idx: list[int] = []

    def box(self, x0, y0, z0, x1, y1, z1, color) -> None:
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        if z1 < z0:
            z0, z1 = z1, z0
        # Outward faces. Two tris each, their own vertices so the normal is flat.
        faces = [
            ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1)),
            ((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (0, 0, -1)),
            ((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0)),
            ((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (1, 0, 0)),
            ((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), (0, 1, 0)),
            ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0)),
        ]
        rgba = (color[0], color[1], color[2], 1.0)
        for a, b, c, d, n in faces:
            base = len(self.pos)
            self.pos.extend((a, b, c, d))
            self.nrm.extend((n, n, n, n))
            self.uv.extend(((0, 0), (1, 0), (1, 1), (0, 1)))
            self.col.extend((rgba, rgba, rgba, rgba))
            self.idx.extend((base, base + 1, base + 2, base, base + 2, base + 3))

    def tris(self) -> int:
        return len(self.idx) // 3


def pack(meshes: dict[str, Mesh], path: Path) -> None:
    """One glTF mesh and one material per node. Vertex colours, no texture."""
    blob = bytearray()
    views = []
    accessors = []
    mesh_defs = []
    nodes = []

    def align(n: int = 4) -> None:
        while len(blob) % n:
            blob.append(0)

    def push(data: bytes, target: int | None) -> int:
        align()
        offset = len(blob)
        blob.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    def acc(view: int, count: int, ctype: int, typ: str, mn, mx) -> int:
        accessors.append(
            {
                "bufferView": view,
                "componentType": ctype,
                "count": count,
                "type": typ,
                "min": mn,
                "max": mx,
            }
        )
        return len(accessors) - 1

    for name, mesh in meshes.items():
        if not mesh.pos:
            continue
        pos = b"".join(struct.pack("<fff", *p) for p in mesh.pos)
        nrm = b"".join(struct.pack("<fff", *p) for p in mesh.nrm)
        uv = b"".join(struct.pack("<ff", *p) for p in mesh.uv)
        col = b"".join(struct.pack("<ffff", *p) for p in mesh.col)
        idx = b"".join(struct.pack("<I", i) for i in mesh.idx)
        xs = [p[0] for p in mesh.pos]
        ys = [p[1] for p in mesh.pos]
        zs = [p[2] for p in mesh.pos]
        pmin = [min(xs), min(ys), min(zs)]
        pmax = [max(xs), max(ys), max(zs)]
        nmin = [min(p[k] for p in mesh.nrm) for k in range(3)]
        nmax = [max(p[k] for p in mesh.nrm) for k in range(3)]
        umin = [min(p[0] for p in mesh.uv), min(p[1] for p in mesh.uv)]
        umax = [max(p[0] for p in mesh.uv), max(p[1] for p in mesh.uv)]
        cmin = [min(p[k] for p in mesh.col) for k in range(4)]
        cmax = [max(p[k] for p in mesh.col) for k in range(4)]
        ipv = push(idx, 34963)
        ppv = push(pos, 34962)
        npv = push(nrm, 34962)
        upv = push(uv, 34962)
        cpv = push(col, 34962)
        mesh_defs.append(
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": acc(ppv, len(mesh.pos), 5126, "VEC3", pmin, pmax),
                            "NORMAL": acc(npv, len(mesh.nrm), 5126, "VEC3", nmin, nmax),
                            "TEXCOORD_0": acc(upv, len(mesh.uv), 5126, "VEC2", umin, umax),
                            "COLOR_0": acc(cpv, len(mesh.col), 5126, "VEC4", cmin, cmax),
                        },
                        "indices": acc(ipv, len(mesh.idx), 5125, "SCALAR", [min(mesh.idx)], [max(mesh.idx)]),
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        )
        nodes.append({"name": name, "mesh": len(mesh_defs) - 1})

    doc = {
        "asset": {"version": "2.0", "generator": "tools/blender/t411_build.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": mesh_defs,
        "materials": [
            {
                "name": "Timber",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [1, 1, 1, 1],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.85,
                },
                "doubleSided": False,
            }
        ],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    raw = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(raw) % 4:
        raw += b" "
    while len(blob) % 4:
        blob.append(0)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(raw) + 8 + len(blob))
    out += struct.pack("<II", len(raw), 0x4E4F534A)
    out += raw
    out += struct.pack("<II", len(blob), 0x004E4942)
    out += blob
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


def sawmill() -> dict[str, Mesh]:
    body, coll = Mesh(), Mesh()
    roof, door, glow = Mesh(), Mesh(), Mesh()
    blade, sign, stack = Mesh(), Mesh(), Mesh()

    def solid(mesh: Mesh, box, color) -> None:
        mesh.box(*box, color)

    def both(box, color) -> None:
        solid(coll, box, color)
        x0, y0, z0, x1, y1, z1 = box
        # Tall shells read as boards. The boards stay inside the shell, so a lane the shell misses stays clear.
        if y1 - y0 >= 3.5:
            rows = max(4, int((y1 - y0) / 0.55))
            h = (y1 - y0) / rows
            for i in range(rows):
                shade = tuple(min(1.0, c * (0.9 + 0.12 * (i % 2))) for c in color)
                solid(body, (x0, y0 + i * h, z0, x1, y0 + (i + 1) * h - h * 0.08, z1), shade)
        else:
            solid(body, box, color)

    # Stone base. Top stays under the slip (y 0.45) and the door (y 1.5).
    both((-30, 0, -18.3, 32.5, 0.4, 20), STONE)
    # Shed floor, under the carriage (the lane starts at y 1.5).
    both((-16.1, 0.4, -17.6, 16.2, 1.42, 18), TIMBER)

    # Shed front wall: the collision's southern face. The roof eave stands in front of it.
    both((-16.2, 1.42, -18.3, 16.4, 20, -17.7), HONEY)
    both((-16.2, 18.5, -17.7, 16.4, 22.2, 18.2), HONEY)  # north gable band, above the lanes
    # Back wall.
    both((-16.2, 1.42, 17.6, 16.4, 20, 18.2), HONEY)
    # West wall, clear of the outfeed (the lane reaches x -16.2).
    both((-17.3, 1.42, -17.6, -16.35, 20, 18), HONEY)
    # East jamb between the carriage (x 16.2) and the slip (x 17.4).
    both((16.35, 1.42, -16, 17.25, 20, 16), HONEY)
    # Lean-to north and south of the slip, and a lintel over it (slip top is y 6.9).
    both((17.25, 0.4, 1.35, 31.5, 12, 16), HONEY)
    both((17.25, 0.4, -16, 31.5, 12, -3.15), HONEY)
    both((17.25, 7.05, -3.05, 31.2, 12, 1.25), TIMBER)
    # Posts at the lean-to's outer corners, outside the slip.
    both((30.2, 0.4, -15.2, 31.4, 12.2, -14), TIMBER)
    both((30.2, 0.4, 13.6, 31.4, 12.2, 14.8), TIMBER)

    # Cabin, west of the shed. The front wall is north of the door lane (z -10).
    both((-31.5, 0.4, -9.2, -17.4, 1.3, 14), STONE)
    both((-31.5, 1.3, 13.4, -17.4, 14, 14), HONEY)  # back
    both((-31.5, 1.3, -9.2, -30.9, 14, 14), HONEY)  # west
    # Front, with a hole wider and taller than the door lane.
    both((-31.5, 1.3, -9.85, -24.3, 14, -9.3), HONEY)
    both((-18.3, 1.3, -9.85, -17.4, 14, -9.3), HONEY)
    both((-24.3, 10.7, -9.85, -18.3, 14, -9.3), HONEY)
    # Timber posts at the cabin's outer corners.
    both((-31.4, 0.4, -9.7, -30.4, 14.4, -8.7), TIMBER)
    both((-31.4, 0.4, 13.2, -30.4, 14.4, 14.2), TIMBER)

    # Square oak on the slip. Centroids stay inside the allow box
    # (20.53, 2.03, -2.47)–(28.37, 6.85, 0.67). Body only: it rides, it does not collide.
    solid(body, (21.6, 3.1, -1.85, 27.4, 5.1, 0.05), TIMBER)
    solid(body, (21.55, 3.25, -1.7, 21.7, 4.95, -0.1), HEART)
    solid(body, (27.3, 3.25, -1.7, 27.45, 4.95, -0.1), HEART)
    # A birch cant on the deck, south of the slip (z < -3) so it is not in the lane.
    solid(body, (22.2, 1.5, -8.2, 28.4, 3.5, -6.2), BIRCH)
    solid(body, (22.4, 3.5, -7.6, 28.2, 5.3, -6.8), TIMBER)

    # Roof. Eave (z -20.6) is in front of the collision's front face (z -18.3).
    # No vertex sits in the 0.1 band on that face.
    roof.box(-18.5, 16.2, -20.6, 18.2, 17.0, -15.8, SLATE)
    roof.box(-17.2, 19.4, -15.6, 17.4, 20.2, 2.0, SLATE)
    roof.box(-17.2, 16.6, 2.0, 17.4, 17.4, 19.4, SLATE)
    roof.box(-33.2, 12.4, -11.2, -16.6, 13.2, 15.2, SLATE)  # cabin roof
    # Shingle courses. None of these vertices sit in the 0.1 band on the front wall (z -18.3).
    for i, z in enumerate((-20.5, -19.6, -17.4, -16.5, -15.4)):
        shade = tuple(min(1.0, c * (0.92 + 0.1 * (i % 2))) for c in SLATE)
        roof.box(-18.2, 16.4 + i * 0.15, z, 17.8, 16.85 + i * 0.15, z + 0.55, shade)
    roof.box(16.2, 11.2, -17.2, 32.4, 12.0, -2.8, SLATE)  # lean-to, south of the slip
    roof.box(16.2, 11.2, 1.4, 32.4, 12.0, 16.4, SLATE)

    # Door swung open beside the opening, not in the doorway.
    door.box(-28.4, 1.4, -13.6, -24.6, 10.2, -13.05, TIMBER)
    door.box(-28.5, 1.3, -13.7, -28.2, 10.3, -12.9, BRASS)

    # Lanterns and the window glow. Kept out of every lane box.
    for lamp in ((-26.2, 8.2, -11.4), (14.5, 12.5, -18.6), (-14.5, 12.5, -18.6), (24, 8.5, -14)):
        glow.box(lamp[0] - 0.35, lamp[1] - 0.35, lamp[2] - 0.35, lamp[0] + 0.35, lamp[1] + 0.35, lamp[2] + 0.35, BRASS)

    # Blade in its own node, east of the carriage's z (the lane ends at z 1.2), inside an iron housing on Body.
    # A hub plus teeth. The node is not a lane, so the teeth can stick out of the disc.
    cx, cy, cz = -3.5, 8.9, 2.25
    blade.box(cx - 0.6, cy - 0.6, cz - 0.15, cx + 0.6, cy + 0.6, cz + 0.15, IRON)
    for i in range(18):
        a = i / 18 * math.tau
        px, py = cx + math.cos(a) * 4.4, cy + math.sin(a) * 4.4
        blade.box(px - 0.28, py - 0.28, cz - 0.12, px + 0.28, py + 0.55, cz + 0.12, (0.86, 0.88, 0.9))
    solid(body, (-8.6, 13.4, 1.7, 1.6, 14.1, 2.8), IRON)
    solid(body, (-8.6, 4.0, 1.7, -8.0, 13.6, 2.8), IRON)
    solid(body, (1.0, 4.0, 1.7, 1.6, 13.6, 2.8), IRON)

    # Crest sign, above the ridge.
    sign.box(-12, 22.4, -16.5, 12, 26.2, -15.9, CREAM)
    sign.box(-12.4, 22.1, -16.6, 12.4, 22.5, -15.8, TIMBER)
    sign.box(-12.4, 26.1, -16.6, 12.4, 26.5, -15.8, TIMBER)

    # Smokestack behind the cabin.
    stack.box(-26.2, 14, 15.2, -22.2, 38.5, 19.2, IRON)
    solid(body, (-26.8, 0.4, 14.6, -21.6, 4.2, 19.8), STONE)

    return {
        "Body": body,
        "Collision": coll,
        "Roof": roof,
        "Door": door,
        "Glow": glow,
        "SawBlade": blade,
        "Sign": sign,
        "Smokestack": stack,
    }


def weigh_house() -> dict[str, Mesh]:
    """The sell yard's barn. The truck bay (|x| < 7, z -15..12, y > 0.35) stays empty."""
    body, coll = Mesh(), Mesh()
    roof, sign, glow = Mesh(), Mesh(), Mesh()

    def both(box, color) -> None:
        coll.box(*box, color)
        x0, y0, z0, x1, y1, z1 = box
        # Tall shells read as boards. The boards stay inside the shell.
        if y1 - y0 >= 3.5:
            rows = max(4, int((y1 - y0) / 0.55))
            h = (y1 - y0) / rows
            for i in range(rows):
                shade = tuple(min(1.0, c * (0.9 + 0.12 * (i % 2))) for c in color)
                body.box(x0, y0 + i * h, z0, x1, y0 + (i + 1) * h - h * 0.08, z1, shade)
        else:
            body.box(*box, color)

    # Pad paint is not this mesh. Edge rails, the tower, the house and the rack collide.
    both((7.45, 0.4, -14.5, 7.85, 2.8, 11.6), IRON)
    both((-7.85, 0.4, -14.5, -7.45, 2.8, 11.6), IRON)
    # Scale tower, east of the bay. The dial is a sign, not a collider.
    both((9.2, 0, 3.2, 12.6, 20.5, 6.6), TIMBER)
    both((9.0, 0, 2.9, 12.8, 1.2, 6.9), STONE)
    # Six-stud dial on the tower face, readable from the approach. Sign node, not a collider.
    sign.box(7.7, 13.6, 2.35, 14.1, 20.0, 2.7, BRASS)  # rim
    sign.box(7.95, 13.85, 2.2, 13.85, 19.75, 2.55, CREAM)
    sign.box(10.55, 14.3, 2.05, 11.25, 19.2, 2.35, INK)  # the needle
    # Weigh House proper, further east, barn red, slate roof.
    both((15.5, 0, 1.5, 24.5, 0.6, 12.5), STONE)
    both((15.6, 0.6, 11.6, 24.4, 8.2, 12.4), BARN)
    both((15.6, 0.6, 1.6, 16.2, 8.2, 12.4), BARN)
    both((23.8, 0.6, 1.6, 24.4, 8.2, 12.4), BARN)
    both((16.2, 6.6, 1.5, 23.8, 8.2, 2.1), BARN)  # lintel over the counter window
    both((17.2, 0.6, 1.2, 22.4, 3.4, 1.7), HONEY)  # counter, facing -Z / the pad side is -X; window faces west
    # Log rack across the back, past z 12. Square cants.
    both((-6.4, 0.4, 13.2, -5.6, 4.8, 14.0), TIMBER)
    both((5.6, 0.4, 13.2, 6.4, 4.8, 14.0), TIMBER)
    body.box(-5.6, 0.7, 13.35, 5.6, 2.1, 14.7, TIMBER)
    body.box(-5.2, 2.2, 13.5, 5.2, 3.5, 14.6, BIRCH)
    coll.box(-5.6, 0.7, 13.35, 5.6, 2.1, 14.7, TIMBER)

    # Roof eave (z 0.2) is in front of the collision's front (the tower base at z 2.9,
    # the rails start at z -14.5, so the rails are the front). Keep the eave forward of
    # the rails and put no roof vertex on the rail face.
    # Collision's min Z is the rail at -14.5. Eave at -16.2.
    roof.box(-9.2, 7.4, -16.2, 9.2, 8.1, -12.0, SLATE)
    roof.box(14.8, 7.6, 0.4, 25.2, 9.4, 13.4, SLATE)
    roof.box(8.4, 20.2, 2.4, 13.4, 21.2, 7.2, SLATE)  # tower cap
    # Shingle courses. None sit in the 0.1 band on the rail face (collision min z is -14.5).
    for i, z in enumerate((-16.05, -15.15, -13.15, -12.35)):
        shade = tuple(min(1.0, c * (0.92 + 0.1 * (i % 2))) for c in SLATE)
        roof.box(-8.6, 7.55 + i * 0.08, z, 8.6, 7.95 + i * 0.08, z + 0.45, shade)
    for i, z in enumerate((0.7, 2.4, 4.1, 5.8, 7.5, 9.2, 10.8)):
        shade = tuple(min(1.0, c * (0.92 + 0.1 * (i % 2))) for c in SLATE)
        roof.box(15.1, 8.0 + (i % 3) * 0.12, z, 24.9, 8.55 + (i % 3) * 0.12, z + 0.7, shade)
    for i, z in enumerate((2.6, 3.8, 5.0, 6.2)):
        shade = tuple(min(1.0, c * (0.92 + 0.1 * (i % 2))) for c in SLATE)
        roof.box(8.7, 20.35, z, 13.1, 20.7, z + 0.45, shade)

    glow.box(7.3, 3.2, -12.5, 8.0, 3.9, -11.8, BRASS)
    glow.box(-8.0, 3.2, -12.5, -7.3, 3.9, -11.8, BRASS)
    glow.box(15.2, 5.4, 2.2, 15.9, 6.1, 2.9, BRASS)
    glow.box(23.6, 5.4, 2.2, 24.3, 6.1, 2.9, BRASS)
    return {"Body": body, "Collision": coll, "Roof": roof, "Sign": sign, "Glow": glow}


def drop_pending() -> None:
    lanes = json.loads(LANES.read_text())
    for entry in lanes.get("Sawmill", []):
        entry.pop("pending", None)
    LANES.write_text(json.dumps(lanes, indent=1) + "\n")


def main() -> None:
    mill = sawmill()
    house = weigh_house()
    pack(mill, ROOT / "assets" / "meshes" / "buildings" / "Sawmill" / "Sawmill.glb")
    pack(house, ROOT / "assets" / "meshes" / "buildings" / "WeighHouse" / "WeighHouse.glb")
    drop_pending()
    for name, mesh in {**mill, **house}.items():
        print(f"{name}: {mesh.tris()} tris")


if __name__ == "__main__":
    main()
