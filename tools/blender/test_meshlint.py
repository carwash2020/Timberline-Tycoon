#!/usr/bin/env python3
"""Tests for meshlint.py: python3 tools/blender/test_meshlint.py (check.sh runs it).

Builds tiny GLBs in memory (a Body and a Collision node of boxes) and checks the lint's verdicts: a
triangle entering a lane box fails, touching does not, a Collision wall over an open Body fails, a lane
exemption needs a reason, and the real Sawmill passes.
"""

from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshlint  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


def box(lo, hi):
    """12 triangles of the axis-aligned box lo..hi as (positions, indices)."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    p = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    quads = [(0, 1, 2, 3), (5, 4, 7, 6), (4, 0, 3, 7), (1, 5, 6, 2), (3, 2, 6, 7), (4, 5, 1, 0)]
    idx = []
    for a, b, c, d in quads:
        idx += [a, b, c, a, c, d]
    return p, idx


def glb(path: Path, nodes: dict[str, list]):
    """nodes: name -> list of (lo, hi) boxes. One mesh per node."""
    blob = b""
    accessors, views, meshes, gnodes = [], [], [], []
    for name, boxes in nodes.items():
        pos, idx = [], []
        for lo, hi in boxes:
            p, i = box(lo, hi)
            idx += [k + len(pos) for k in i]
            pos += p
        pb = b"".join(struct.pack("<3f", *v) for v in pos)
        ib = struct.pack(f"<{len(idx)}H", *idx)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(pb)})
        blob += pb
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(ib)})
        blob += ib + b"\x00" * (-len(ib) % 4)
        accessors.append({"bufferView": len(views) - 2, "componentType": 5126, "count": len(pos), "type": "VEC3"})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5123, "count": len(idx), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1}]})
        gnodes.append({"name": name, "mesh": len(meshes) - 1})
    doc = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(gnodes)))}],
        "nodes": gnodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(doc).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    path.write_bytes(
        b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + blob
    )


LANE = {"name": "slip", "kind": "lane", "min": [0, 0, 0], "max": [10, 4, 4]}


class MeshLint(unittest.TestCase):
    def run_lint(self, nodes, entry=LANE):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "Thing").mkdir()
            glb(root / "Thing" / "Thing.glb", nodes)
            return meshlint.lint_mesh("Thing", [entry], root / "Thing" / "Thing.glb")

    def test_clear_lane_passes(self):
        far = ((20, 0, 0), (22, 4, 4))
        self.assertEqual(self.run_lint({"Body": [far], "Collision": [far]}), [])

    def test_touching_is_not_entering(self):
        beside = ((10, 0, 0), (12, 4, 4))
        self.assertEqual(self.run_lint({"Body": [beside], "Collision": [beside]}), [])

    def test_body_in_lane_fails_and_names_the_node_and_place(self):
        post = ((4, 0, 1), (5, 4, 2))
        out = self.run_lint({"Body": [post], "Collision": [((20, 0, 0), (21, 1, 1))]})
        self.assertEqual(len(out), 1)
        self.assertTrue(out[0].startswith("Thing/slip: "), out[0])
        self.assertIn("(Body, lane)", out[0])
        self.assertRegex(out[0], r"\d+ tris, first at -?\d+\.\d\d,-?\d+\.\d\d,-?\d+\.\d\d")

    def test_collision_over_an_open_body_fails(self):
        post = ((4, 0, 1), (5, 4, 2))
        out = self.run_lint({"Body": [((20, 0, 0), (21, 1, 1))], "Collision": [post]})
        self.assertTrue(any("(Collision, lane)" in line for line in out), out)
        self.assertTrue(any("Collision blocks a box that Body leaves open" in line for line in out), out)

    def test_a_triangle_cutting_across_a_corner_is_caught(self):
        # a big flat triangle whose plane clips the box corner but whose vertices are all outside it
        with tempfile.TemporaryDirectory() as d:
            lo, hi = [0, 0, 0], [1, 1, 1]
            tri = ((-1.0, 2.0, 0.5), (2.0, -1.0, 0.5), (2.0, 2.0, 0.5))
            self.assertTrue(meshlint.tri_box(tri, lo, hi))
            far = ((-1.0, 3.0, 0.5), (3.0, -1.0, 0.5), (3.0, 3.0, 0.5))
            self.assertFalse(meshlint.tri_box(far, lo, hi))

    def test_an_exemption_removes_the_riders_and_needs_a_reason(self):
        rail = ((0, 0, 0), (10, 1, 1))
        entry = dict(LANE, allow=[{"min": [-1, -1, -1], "max": [11, 1.5, 1.5], "why": "the lane's own rail"}])
        self.assertEqual(self.run_lint({"Body": [rail], "Collision": [((20, 0, 0), (21, 1, 1))]}, entry), [])
        bad = dict(LANE, allow=[{"min": [-1, -1, -1], "max": [11, 1.5, 1.5]}])
        out = self.run_lint({"Body": [rail], "Collision": [((20, 0, 0), (21, 1, 1))]}, bad)
        self.assertTrue(any("has no reason" in line for line in out), out)

    def test_the_real_meshes_pass(self):
        proc = subprocess.run([sys.executable, str(REPO / "tools/blender/meshlint.py")], capture_output=True, text=True, cwd=REPO)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("0 failures", proc.stdout)


if __name__ == "__main__":
    unittest.main()
