#!/usr/bin/env python3
"""Physical-sense lint for the GLBs: does anything solid stand where wood or a
person has to pass?

    python3 tools/blender/meshlint.py                 every mesh listed in assets/meshes/lanes.json
    python3 tools/blender/meshlint.py --boxes         also print each Collision node's box (JSON)
    python3 tools/blender/meshlint.py --lanes F.json --root DIR   other lane file or mesh folder

assets/meshes/lanes.json is { "<mesh>": [ { name, min, max, kind } ] }: boxes in
the mesh's own studs (the GLB's coordinates, 1 unit = 1 stud, after node
transforms), kind "lane" (wood travels through it), "door" (a person walks
through it) or "path". "<mesh>" is the folder name under assets/meshes/**/
(for example "Sawmill" is buildings/Sawmill/Sawmill.glb).

Pure Python on top of glbstats.py (no Blender, no pip packages). Each node's
world matrix and triangles are read; Body and Collision stay separate (a node
named Body*, Collision*). A box is tested with an AABB pre-filter, then a
triangle-versus-box SAT (13 axes: 3 box faces, the triangle normal, 9 edge
cross products). FAIL (exit 1) when:
  - any Body or Collision triangle enters a box, or
  - Collision blocks a box that Body leaves open (Collision is what a player
    bumps into, so a solid you cannot see is still a block).
A lane's "riders" (rails, carriage, logs, saw blade...) are separate parts in
the part-built model; in the GLB they are merged into Body, so an entry may
list "allow": [ { min, max, why } ] boxes whose Body triangles are not
counted (the rider's own space). Every allowance needs a reason.
Prints "mesh/lane: N tris, first at x,y,z" for each failure.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glbstats import apply, load, mat_mul, node_matrix, read_accessor  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
EPS = 1e-9


def world_triangles(path: Path) -> dict[str, list[tuple]]:
    """node name -> list of triangles ((x,y,z) x3) in mesh-local studs."""
    doc, blob = load(path)
    nodes = doc.get("nodes") or []
    meshes = doc.get("meshes") or []
    out: dict[str, list[tuple]] = {}
    cache: dict[int, list[tuple]] = {}

    def mesh_tris(index: int) -> list[tuple]:
        if index in cache:
            return cache[index]
        tris: list[tuple] = []
        for prim in meshes[index].get("primitives", []):
            if prim.get("mode", 4) != 4:
                continue
            pos = read_accessor(doc, blob, prim["attributes"]["POSITION"])
            if "indices" in prim:
                idx = [i[0] for i in read_accessor(doc, blob, prim["indices"])]
            else:
                idx = list(range(len(pos)))
            for k in range(0, len(idx) - 2, 3):
                tris.append((pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]]))
        cache[index] = tris
        return tris

    def visit(i: int, parent: list[float]):
        node = nodes[i]
        world = mat_mul(parent, node_matrix(node))
        if isinstance(node.get("mesh"), int):
            name = node.get("name") or meshes[node["mesh"]].get("name") or f"mesh{node['mesh']}"
            out.setdefault(name, []).extend(
                tuple(apply(world, p) for p in tri) for tri in mesh_tris(node["mesh"])
            )
        for child in node.get("children", []):
            visit(child, world)

    identity = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
    scenes = doc.get("scenes") or [{"nodes": list(range(len(nodes)))}]
    for root in scenes[doc.get("scene", 0)].get("nodes", []):
        visit(root, identity)
    return out


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def tri_box(tri, lo, hi) -> bool:
    """Triangle versus axis-aligned box, SAT on the 13 axes (touching is not entering)."""
    # AABB pre-filter.
    for k in range(3):
        tmin = min(tri[0][k], tri[1][k], tri[2][k])
        tmax = max(tri[0][k], tri[1][k], tri[2][k])
        if tmax <= lo[k] + EPS or tmin >= hi[k] - EPS:
            return False
    c = tuple((lo[k] + hi[k]) / 2 for k in range(3))
    h = tuple((hi[k] - lo[k]) / 2 for k in range(3))
    v = [_sub(p, c) for p in tri]
    edges = [_sub(v[1], v[0]), _sub(v[2], v[1]), _sub(v[0], v[2])]
    axes = []
    for e in edges:
        for k in range(3):
            unit = [0.0, 0.0, 0.0]
            unit[k] = 1.0
            axes.append(_cross(e, tuple(unit)))
    axes.append(_cross(edges[0], edges[1]))
    for axis in axes:
        if abs(axis[0]) + abs(axis[1]) + abs(axis[2]) < 1e-12:
            continue
        p = [_dot(pt, axis) for pt in v]
        r = h[0] * abs(axis[0]) + h[1] * abs(axis[1]) + h[2] * abs(axis[2])
        if min(p) >= r - EPS * (1 + r) or max(p) <= -r + EPS * (1 + r):
            return False
    return True  # the three box-face axes were settled by the pre-filter


def _inside(p, lo, hi) -> bool:
    return all(lo[k] <= p[k] <= hi[k] for k in range(3))


def hits(tris: list[tuple], lo, hi, skip: list[tuple] | None = None) -> list[tuple]:
    """Triangles that enter the box; `skip` boxes drop a triangle whose centroid lies inside one."""
    out = []
    for tri in tris:
        if not tri_box(tri, lo, hi):
            continue
        if skip:
            cen = tuple(sum(p[k] for p in tri) / 3 for k in range(3))
            if any(_inside(cen, s[0], s[1]) for s in skip):
                continue
        out.append(tri)
    return out


def first_at(tri) -> str:
    cen = tuple(sum(p[k] for p in tri) / 3 for k in range(3))
    return "%.2f,%.2f,%.2f" % cen


def find_glb(root: Path, mesh: str) -> Path | None:
    found = sorted(root.rglob(f"{mesh}/{mesh}.glb"))
    return found[0] if found else None


def box_of(tris: list[tuple]):
    if not tris:
        return None
    lo = [min(p[k] for t in tris for p in t) for k in range(3)]
    hi = [max(p[k] for t in tris for p in t) for k in range(3)]
    return [round(v, 3) for v in lo], [round(v, 3) for v in hi]


def lint_mesh(mesh: str, entries: list[dict], glb: Path) -> list[str]:
    nodes = world_triangles(glb)
    body = [t for n, ts in nodes.items() if n == "Body" or n.startswith("Body.") for t in ts]
    coll = [t for n, ts in nodes.items() if n == "Collision" or n.startswith("Collision.") for t in ts]
    fails: list[str] = []
    for e in entries:
        lo, hi = e["min"], e["max"]
        skip = [(a["min"], a["max"]) for a in e.get("allow", [])]
        for a in e.get("allow", []):
            if not a.get("why"):
                fails.append(f"{mesh}/{e['name']}: an allow box has no reason")
        label = f"{mesh}/{e['name']}"
        b = hits(body, lo, hi, skip)
        c = hits(coll, lo, hi, skip)
        if b:
            fails.append(f"{label}: {len(b)} tris, first at {first_at(b[0])} (Body, {e['kind']})")
        if c:
            fails.append(f"{label}: {len(c)} tris, first at {first_at(c[0])} (Collision, {e['kind']})")
        if c and not b:
            fails.append(f"{label}: Collision blocks a box that Body leaves open")
    return fails


def main(argv: list[str]) -> int:
    lanes_path = REPO / "assets/meshes/lanes.json"
    root = REPO / "assets/meshes"
    show_boxes = False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--lanes":
            lanes_path = Path(args.pop(0))
        elif a == "--root":
            root = Path(args.pop(0))
        elif a == "--boxes":
            show_boxes = True
        else:
            print(__doc__)
            return 2
    lanes = json.loads(lanes_path.read_text())
    bad = 0
    boxes = 0
    for mesh, entries in lanes.items():
        glb = find_glb(root, mesh)
        if glb is None:
            print(f"FAIL {mesh}: no {mesh}.glb under {root}")
            bad += 1
            continue
        fails = lint_mesh(mesh, entries, glb)
        for line in fails:
            print("FAIL " + line)
        bad += len(fails)
        boxes += len(entries)
        if show_boxes:
            nodes = world_triangles(glb)
            print(json.dumps({mesh: {n: box_of(t) for n, t in nodes.items()}}))
    print(f"meshlint: {boxes} boxes in {len(lanes)} meshes, {bad} failures")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
