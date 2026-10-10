#!/usr/bin/env python3
"""Lane P: pastes the board's real poster canvas (v1p_gui + v1p_shots) onto
the cork face of a 3D render (shoot.sh v1-p), projected with the viewer's
own camera (three.js PerspectiveCamera: vertical fov, aspect W/H, looking at
the target with +Y up). The canvas is shaded like a SurfaceGui with
LightInfluence 0.6: 40% its own colour, 60% lit the way the render lit the
cork it sits on (measured from the render's empty cork).

  python3 tools/preview/v1p_composite.py render.png canvas-alpha.png out.png \
      --pos x,y,z --target x,y,z --fov 45 --face "[x,y,z],[x,y,z],[x,y,z],[x,y,z]"
"""
import argparse, json, math
import numpy as np
from PIL import Image

CORK = np.array([0xB5, 0x8A, 0x5C], dtype=float)


def project(points, pos, target, fov, w, h):
    pos, target = np.array(pos, float), np.array(target, float)
    f = target - pos
    f /= np.linalg.norm(f)
    r = np.cross(f, [0.0, 1.0, 0.0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    t = math.tan(math.radians(fov) / 2)
    out = []
    for p in points:
        d = np.array(p, float) - pos
        z = d @ f
        x = (d @ r) / z / (t * w / h)
        y = (d @ u) / z / t
        out.append(((x + 1) / 2 * w, (1 - y) / 2 * h))
    return out


def coeffs(dst, src):
    # PIL PERSPECTIVE: maps an output pixel (dst quad) to an input pixel (src).
    m = []
    for (x, y), (X, Y) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        m.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    b = [v for pt in src for v in pt]
    return np.linalg.solve(np.array(m, float), np.array(b, float)).tolist()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("render")
    ap.add_argument("canvas")
    ap.add_argument("out")
    ap.add_argument("--pos", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--fov", type=float, default=50)
    ap.add_argument("--face", required=True)
    a = ap.parse_args()
    render = Image.open(a.render).convert("RGBA")
    canvas = Image.open(a.canvas).convert("RGBA")
    W, H = render.size
    face = json.loads("[" + a.face + "]")
    quad = project(face, [float(v) for v in a.pos.split(",")], [float(v) for v in a.target.split(",")], a.fov, W, H)
    cw, ch = canvas.size
    src = [(0, 0), (cw, 0), (cw, ch), (0, ch)]
    warped = canvas.transform((W, H), Image.PERSPECTIVE, coeffs(quad, src), Image.BICUBIC)
    # How the render lit the cork: its median colour over the canvas's empty
    # (transparent) cork, against the cork's true colour.
    rgb = np.asarray(render, float)[..., :3]
    alpha = np.asarray(warped, float)[..., 3]
    inside = Image.new("L", (W, H), 0)
    from PIL import ImageDraw

    ImageDraw.Draw(inside).polygon(quad, fill=255)
    cork = (np.asarray(inside) > 0) & (alpha < 8)
    lit = np.median(rgb[cork], axis=0) / CORK if cork.any() else np.ones(3)
    shade = 0.4 + 0.6 * np.clip(lit, 0, 1.6)
    w = np.asarray(warped, float)
    w[..., :3] = np.clip(w[..., :3] * shade, 0, 255)
    warped = Image.fromarray(w.astype(np.uint8), "RGBA")
    render.alpha_composite(warped)
    render.convert("RGB").save(a.out)
    print(a.out, "quad", [(round(x), round(y)) for x, y in quad], "light", np.round(lit, 2).tolist())


if __name__ == "__main__":
    main()
