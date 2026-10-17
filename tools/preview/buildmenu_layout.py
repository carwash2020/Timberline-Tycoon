"""Draws previews/build-menu/after-<w>x<h>.png from previews/build-menu/layout.json
(numbers taken from BuildMenuLogic.Layout). A computed layout diagram, NOT a Studio
screenshot: boxes show where the rail, grid and cards sit and how wide they are."""
import json
from PIL import Image, ImageDraw, ImageFont

d = json.load(open("previews/build-menu/layout.json"))
try:
    F = lambda n: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", max(9, int(n)))
    F(10)
except OSError:
    F = lambda n: ImageFont.load_default()
RAIL = ["Walls", "Floors", "Doors", "Stairs", "Roofs", "Fences", "Indoor", "Decor", "Houses"]
for s in d["sizes"]:
    sc, W, H = s["scale"], s["w"], s["h"]
    im = Image.new("RGB", (W, H), (40, 52, 44))
    dr = ImageDraw.Draw(im)
    z = s["s"]
    ph = min(640, H / sc - 74)
    pw = s["panelW"]
    ox = (W - pw * sc) / 2
    oy = 66 * sc + ((H - 66 * sc - 8 * sc) - ph * sc) / 2
    R = lambda x, y, w, h, **k: dr.rectangle([ox + x * sc, oy + y * sc, ox + (x + w) * sc, oy + (y + h) * sc], **k)
    R(0, 0, pw, ph, fill=(222, 200, 160), outline=(70, 45, 25), width=3)
    pad = 14
    dr.text((ox + (pad + 2) * sc, oy + (pad + 8) * sc), "Blueprints", fill=(30, 20, 10), font=F(24 * sc))
    R(pw - pad - 44, pad, 44, 44, fill=(200, 140, 60), outline=(70, 45, 25))
    top = pad + 44 + 8
    rail = z["rail"]
    for i, n in enumerate(RAIL):
        y = top + i * (z["row"] + 6)
        if y + z["row"] > ph - pad:
            break
        R(pad, y, rail, z["row"], fill=(240, 225, 190) if i else (255, 240, 170), outline=(70, 45, 25))
        dr.text((ox + (pad + 8) * sc, oy + (y + z["row"] / 2 - 8) * sc), n, fill=(30, 20, 10), font=F(z["label"] * sc))
    gx = pad + rail + 12
    names = d["kinds"]["Walls"]
    for i, n in enumerate(names):
        c, r = i % s["cols"], i // s["cols"]
        x = gx + c * (s["tileW"] + 8)
        y = top + r * (z["tileH"] + 8)
        if y + z["tileH"] > ph - pad:
            break
        R(x, y, s["tileW"], z["tileH"], fill=(190, 170, 130), outline=(70, 45, 25), width=2)
        R(x, y + z["tileH"] - z["plate"], s["tileW"], z["plate"], fill=(245, 235, 210), outline=(70, 45, 25))
        dr.text((ox + (x + 8) * sc, oy + (y + z["tileH"] - z["plate"] + 6) * sc), n, fill=(30, 20, 10), font=F(z["name"] * sc))
    cap = f"{W}x{H}  scale {sc}  {'phone' if s['phone'] else 'wide'}  panel {pw:.0f}  cols {s['cols']}  card {s['tileW']:.0f}x{z['tileH']}  name {z['name']}px  (computed from BuildMenuLogic; not a Studio shot)"
    dr.text((6, 4), cap, fill=(255, 255, 255), font=F(11))
    im.save(f"previews/build-menu/after-{W}x{H}.png")
