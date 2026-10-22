"""Draws preview/t420-hammer/{before,after}-<w>x<h>.png from preview/t420-hammer/layout.json
(written by `lune run tools/preview/picker_layout`: numbers from BuildMenuLogic and
HammerPicker, and the real card text). A flat-colour LAYOUT DIAGRAM, NOT a Studio
screenshot: boxes show where the tabs and cards sit, how big they are and what
they say. Fonts are not Gotham, so line breaks are approximate."""
import json, textwrap
from PIL import Image, ImageDraw, ImageFont

d = json.load(open("preview/t420-hammer/layout.json"))
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def F(n, bold=False):
    try:
        return ImageFont.truetype(BOLD if bold else FONT, max(8, int(n)))
    except OSError:
        return ImageFont.load_default()

OLD_RAIL = ["Walls", "Floors", "Doors", "Stairs", "Roofs", "Fences", "Indoor", "Decor", "Houses", "More"]
NEW_RAIL = [t["label"] for t in d["tabs"]]
CREAM, PAPER, BARK, GOLD, INK = (243, 231, 201), (228, 210, 174), (62, 46, 34), (255, 196, 40), (30, 27, 24)

def wrap(text, font, width, dr):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if dr.textlength(t, font=font) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines

for s in d["sizes"]:
    for kind in ("before", "after"):
        sc, W, H = s["scale"], s["w"], s["h"]
        im = Image.new("RGB", (W, H), (40, 52, 44))
        dr = ImageDraw.Draw(im)
        pw = s["panelW"]
        ph = min(640, H / sc - 74)
        ox = (W - pw * sc) / 2
        oy = 66 * sc + ((H - 66 * sc - 8 * sc) - ph * sc) / 2
        R = lambda x, y, w, h, **k: dr.rectangle([ox + x * sc, oy + y * sc, ox + (x + w) * sc, oy + (y + h) * sc], **k)
        T = lambda x, y, txt, size, bold=False, fill=INK: dr.text((ox + x * sc, oy + y * sc), txt, fill=fill, font=F(size * sc, bold))
        R(0, 0, pw, ph, fill=PAPER, outline=BARK, width=3)
        pad = 14
        T(pad + 2, pad + 8, "Blueprints", 24, True)
        R(pw - pad - 44, pad, 44, 44, fill=(200, 140, 60), outline=BARK)
        top = pad + 44 + 8
        rail = s["rail"]
        names = OLD_RAIL if kind == "before" else NEW_RAIL
        row = 56 if s["phone"] else 60
        for i, n in enumerate(names + ["Land"]):
            y = top + i * (row + 6)
            if y + row > ph:
                break
            on = i == 0
            R(pad, y, rail, row, fill=CREAM if on else PAPER, outline=GOLD if on else BARK, width=3 if on else 1)
            R(pad + 8, y + 8, row - 16, row - 16, fill=(140, 106, 69))
            T(pad + row, y + row / 2 - 9, n, 16 if s["phone"] else 18, True)
        gx = pad + rail + 12
        data = s[kind]
        cw, ch, cols = data["tileW"], data["tileH"], data["cards"] if "cards" in data else data["cols"]
        cols = data["cols"]
        cards = d["tabs"][0]["cards"]
        for i in range(cols * 3):
            r, c = divmod(i, cols)
            x, y = gx + c * (cw + 8), top + r * (ch + 8)
            if y > ph:
                break
            R(x, y, cw, min(ch, ph - y - 4), fill=CREAM, outline=GOLD if i == 0 else BARK, width=4 if i == 0 else 2)
            card = cards[i % len(cards)]
            if kind == "before":
                R(x + cw * 0.15, y + 8, cw * 0.7, ch - 50, fill=(150, 150, 150))
                nm = F(16 * sc if s["phone"] else 18 * sc, True)
                for k, line in enumerate(wrap(card["name"], nm, (cw - 16) * sc, dr)[:2]):
                    dr.text((ox + (x + 8) * sc, oy + (y + ch - 40 + k * 18) * sc), line, fill=INK, font=nm)
            else:
                cs = data["card"]
                R(x + cw * 0.15, y + 4, cw * 0.7, cs["artH"] - 6, fill=(150, 150, 150))
                yy = y + cs["artH"]
                nm, bl, co = F(cs["nameText"] * sc, True), F(cs["blurbText"] * sc), F(cs["costText"] * sc, True)
                for k, line in enumerate(wrap(card["name"], nm, (cw - 16) * sc, dr)[:2]):
                    dr.text((ox + (x + 8) * sc, oy + (yy + k * cs["nameText"] * 1.2) * sc), line, fill=INK, font=nm)
                yy += cs["nameH"] + cs["gap"] * 2
                for k, line in enumerate(wrap(card["blurb"], bl, (cw - 16) * sc, dr)[:3]):
                    dr.text((ox + (x + 8) * sc, oy + (yy + k * cs["blurbText"] * 1.25) * sc), line, fill=BARK, font=bl)
                yy = y + ch - cs["costH"] - cs["gap"]
                for k, line in enumerate(wrap(card["cost"], co, (cw - 16) * sc, dr)[:2]):
                    dr.text((ox + (x + 8) * sc, oy + (yy + k * cs["costText"] * 1.2) * sc), line, fill=INK, font=co)
        # What does not fit in the panel scrolls: cut the drawing at the panel's edge.
        dr.rectangle([0, oy + ph * sc + 1, W, H], fill=(40, 52, 44))
        R(0, 0, pw, ph, outline=BARK, width=3)
        dr.text((8, H - 22), f"{kind.upper()}  {s['label']}  layout diagram from BuildMenuLogic/HammerPicker numbers, NOT a Studio screenshot", fill=(255, 255, 255), font=F(13))
        out = f"preview/t420-hammer/{kind}-{W}x{H}.png"
        im.save(out)
        print(out)
