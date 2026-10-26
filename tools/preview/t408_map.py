#!/usr/bin/env python3
"""Top-down T408 draft and one card per removal.

Reads previews/t408/plan.json (lune run tools/preview/t408_dump) and writes:

  previews/t408/overview.png
  previews/t408/removals/<id>.png
  previews/t408/removals/contact-sheet.png

North is up. The live terrain is not in this picture.
"""

from __future__ import annotations

import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLAN = os.path.join(ROOT, "previews", "t408", "plan.json")
OUT = os.path.join(ROOT, "previews", "t408")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Map covers the playable square with a margin, north up.
HALF = 1100.0
MAP = 1500


def rgb(hex6: str) -> tuple[int, int, int]:
    h = hex6.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def mix(a, b, t: float):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


class Map:
    def __init__(self, ox: int, oy: int):
        self.ox = ox
        self.oy = oy

    def px(self, x: float, z: float) -> tuple[float, float]:
        return (
            self.ox + (x + HALF) / (2 * HALF) * MAP,
            self.oy + (HALF - z) / (2 * HALF) * MAP,
        )

    def scale(self, studs: float) -> float:
        return studs / (2 * HALF) * MAP


def disc(draw: ImageDraw.ImageDraw, m: Map, x, z, r, fill):
    cx, cy = m.px(x, z)
    rr = m.scale(r)
    draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=fill)


def thick(draw, m: Map, pts, studs, fill):
    if len(pts) < 2:
        return
    xy = [m.px(p["x"], p["z"]) for p in pts]
    draw.line(xy, fill=fill, width=max(2, int(m.scale(studs))), joint="curve")


def halo(draw, xy, text, font, fill, back, anchor="lt"):
    x, y = xy
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1)):
        draw.text((x + dx, y + dy), text, font=font, fill=back, anchor=anchor)
    draw.text((x, y), text, font=font, fill=fill, anchor=anchor)


def offset_band(pts, half):
    """A polygon around a polyline, half-width in the same units as pts."""

    def sub(a, b):
        return (a[0] - b[0], a[1] - b[1])

    def add(a, b):
        return (a[0] + b[0], a[1] + b[1])

    def mul(a, s):
        return (a[0] * s, a[1] * s)

    def norm(a):
        length = (a[0] ** 2 + a[1] ** 2) ** 0.5
        if length < 1e-6:
            return (1.0, 0.0)
        return (a[0] / length, a[1] / length)

    left, right = [], []
    for i, p in enumerate(pts):
        if i == 0:
            d = norm(sub(pts[1], p))
        elif i == len(pts) - 1:
            d = norm(sub(p, pts[i - 1]))
        else:
            d = norm(add(norm(sub(p, pts[i - 1])), norm(sub(pts[i + 1], p))))
        n = (-d[1], d[0])
        left.append(add(p, mul(n, half)))
        right.append(sub(p, mul(n, half)))
    return left + list(reversed(right))


def draw_overview(plan: dict) -> Image.Image:
    pal = plan["palette"]
    ink = rgb(pal["ink"])
    cream = rgb(pal["cream"])
    water = rgb(pal["water"])
    trail = rgb(pal["trail"])
    cliff = rgb(pal["cliff"])
    valley = rgb(pal["valley"])
    canopy = rgb(pal["canopy"])
    lumen = rgb(pal["lumen"])
    ember = rgb(pal["ember"])
    snow = rgb(pal["snow"])
    W, H = 2460, 1780
    im = Image.new("RGB", (W, H), mix(cream, trail, 0.35))
    draw = ImageDraw.Draw(im)
    title = load_font(FONTB, 28)
    sub = load_font(FONT, 15)
    label = load_font(FONTB, 15)
    small = load_font(FONT, 13)
    tiny = load_font(FONTB, 11)
    pin_font = load_font(FONTB, 13)

    draw.rectangle((0, 0, W, 78), fill=ink)
    draw.text((28, 14), "T408  RIVER VALLEY  —  DRAFT FOR CONNOR", font=title, fill=cream)
    draw.text(
        (28, 48),
        "No gondola.  No ring road.  Trunk lift to the clouds.  Bridge $100.  Ferry $400.  No fast travel.",
        font=sub,
        fill=rgb(pal["lumen"]),
    )

    ox, oy = 24, 96
    m = Map(ox, oy)
    # Country, warmer in the valley, rockier at the north and west edges.
    base = Image.new("RGB", (MAP, MAP), mix(valley, trail, 0.45))
    bd = ImageDraw.Draw(base)
    bm = Map(0, 0)
    for i in range(8):
        t = i / 7
        band = mix(cliff, mix(valley, trail, 0.4), 0.35 + 0.5 * (1 - abs(t - 0.15)))
        z0 = HALF - t * 2 * HALF
        z1 = HALF - (t + 1 / 7) * 2 * HALF
        y0 = bm.px(0, z0)[1]
        y1 = bm.px(0, z1)[1]
        bd.rectangle((0, min(y0, y1), MAP, max(y0, y1)), fill=band)
    # Edge rock, so the square does not read as a flat baseplate.
    fringe = bm.scale(80)
    bd.rectangle((0, 0, MAP, fringe), fill=cliff)
    bd.rectangle((0, 0, fringe, MAP), fill=cliff)
    im.paste(base, (ox, oy))

    coast = plan["coast"]
    shore = coast["shoreX"]
    beach = coast["beachWidth"]
    north_z = coast["northZ"]
    sand = rgb(pal["sand"])
    b0 = m.px(shore - beach, north_z)
    b1 = m.px(shore, -HALF)
    draw.rectangle((b0[0], b0[1], b1[0], b1[1]), fill=mix(sand, cream, 0.25))

    bay = [m.px(p["x"], p["z"]) for p in plan["bay"]]
    draw.polygon(bay, fill=water)
    river_xy = [(p["x"], p["z"]) for p in plan["river"]]
    band = offset_band(river_xy, plan["riverHalf"])
    draw.polygon([m.px(x, z) for x, z in band], fill=mix(water, snow, 0.25))

    # Regions. Valley is the starter disc plus the town rectangle.
    for region in plan["regions"]:
        if region["id"] == "valley":
            continue
        tint = rgb(region["tint"])
        if region["id"] == "pine":
            disc(draw, m, region["x"], region["z"], region["radius"] + 28, cliff)
        if region["id"] == "frost":
            disc(draw, m, region["x"], region["z"], region["radius"] + 10, rgb(pal["frostGlow"]))
        disc(draw, m, region["x"], region["z"], region["radius"], tint)
        if region["id"] == "gloam":
            disc(draw, m, region["x"], region["z"], region["radius"] * 0.45, rgb(pal["gloamGlow"]))
        if region["id"] == "skyroot":
            disc(draw, m, region["x"], region["z"], plan["cloudRadius"], mix(lumen, snow, 0.35))

    valley_r = next(r for r in plan["regions"] if r["id"] == "valley")
    disc(draw, m, valley_r["x"], valley_r["z"], valley_r["radius"], valley)
    town = plan["town"]
    t0 = m.px(town["x0"], town["z1"])
    t1 = m.px(town["x1"], town["z0"])
    draw.rectangle((t0[0], t0[1], t1[0], t1[1]), fill=mix(valley, cream, 0.2))

    sell = plan["sellFloor"]
    s0 = m.px(sell["x0"], sell["z1"])
    s1 = m.px(sell["x1"], sell["z0"])
    draw.rectangle((s0[0], s0[1], s1[0], s1[1]), outline=ink, width=2)

    road_fill = {
        "main": mix(trail, ink, 0.15),
        "branch": mix(trail, cream, 0.25),
        "foot": mix(cream, trail, 0.35),
    }
    for road in plan["roads"]:
        thick(draw, m, road["points"], road["width"], road_fill[road["kind"]])

    # Lift bridge towers on the banks.
    bridge = plan["bridge"]
    bank = plan["riverHalf"] + 6
    for side in (-1, 1):
        cx, cy = m.px(bridge["x"] + side * bank, bridge["z"])
        draw.rectangle((cx - 5, cy - 9, cx + 5, cy + 9), fill=ink)
        draw.rectangle((cx - 3, cy - 14, cx + 3, cy - 8), fill=ember)
    deck0 = m.px(bridge["x"] - bank, bridge["z"])
    deck1 = m.px(bridge["x"] + bank, bridge["z"])
    draw.line((deck0, deck1), fill=cream, width=4)
    halo(draw, m.px(bridge["x"] + 70, bridge["z"] - 28), "LIFT BRIDGE $100", tiny, ink, cream, "mm")

    # Ferry.
    a = m.px(plan["mainlandDock"]["x"], plan["mainlandDock"]["z"])
    b = m.px(plan["islandDock"]["x"], plan["islandDock"]["z"])
    steps = 18
    for i in range(0, steps, 2):
        t0, t1 = i / steps, min(1, (i + 1) / steps)
        draw.line(
            (
                (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0),
                (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1),
            ),
            fill=cream,
            width=3,
        )
    halo(draw, m.px(860, 210), "CAR FERRY  $400", tiny, ink, cream, "mm")

    # Landmarks from spawn: plume, Skyroot, lighthouse.
    plume = plan["plume"]
    for i, rad in enumerate((26, 16, 8)):
        disc(draw, m, plume["x"] + i * 6, plume["z"] + i * 10, rad, ember if i < 2 else rgb("FFD2A8"))
    halo(draw, m.px(plume["x"] + 20, plume["z"] + 48), "CALDERA PLUME", tiny, cream, ink, "mm")

    root = plan["skyroot"]
    disc(draw, m, root["x"], root["z"], 46, canopy)
    disc(draw, m, root["x"], root["z"], 18, mix(lumen, valley, 0.3))
    tx, ty = m.px(root["x"], root["z"])
    draw.rectangle((tx - 4, ty - 16, tx + 4, ty + 10), fill=mix(ink, trail, 0.3))
    halo(draw, m.px(root["x"] - 78, root["z"]), "TRUNK LIFT", tiny, ink, lumen, "mm")

    light = plan["lighthouse"]
    lx, ly = m.px(light["x"], light["z"])
    draw.polygon([(lx, ly - 16), (lx - 7, ly), (lx + 7, ly)], fill=cream)
    draw.rectangle((lx - 4, ly, lx + 4, ly + 14), fill=ink)
    halo(draw, (lx, ly + 22), "LIGHTHOUSE", tiny, ink, cream, "mt")

    # Region names.
    name_font = load_font(FONTB, 14)
    placements = {
        "valley": (0, -60),
        "pine": (-500, 110),
        "frost": (0, 700),
        "caldera": (450, 470),
        "gloam": (10, -700),
        "bayou": (-760, -700),
        "mesa": (590, -790),
        "isle": (930, 20),
        "skyroot": (-250, 960),
    }
    light_names = {"frost", "isle", "skyroot", "valley"}
    for region in plan["regions"]:
        pos = placements[region["id"]]
        fill = ink if region["id"] in light_names else cream
        back = cream if fill == ink else ink
        halo(draw, m.px(*pos), region["name"].upper(), name_font, fill, back, "mm")

    # Signed roads: a board at the signed end.
    for road in plan["roads"]:
        if not road.get("sign"):
            continue
        end = road["points"][-1]
        ex, ey = m.px(end["x"], end["z"])
        board = road["sign"]
        tw = draw.textlength(board, font=tiny)
        top = ey - 22
        draw.rounded_rectangle((ex - tw / 2 - 4, top, ex + tw / 2 + 4, top + 14), radius=2, fill=cream, outline=ink)
        draw.text((ex, top + 7), board, font=tiny, fill=ink, anchor="mm")
        draw.line((ex, top + 14, ex, ey), fill=ink, width=2)

    # Shop pins.
    for shop in plan["shops"]:
        cx, cy = m.px(shop["x"], shop["z"])
        draw.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=ember if shop.get("y") else ink, outline=cream, width=2)
        draw.text((cx, cy), str(shop["n"]), font=pin_font, fill=cream, anchor="mm")

    # Frame and north arrow.
    draw.rectangle((ox, oy, ox + MAP - 1, oy + MAP - 1), outline=ink, width=2)
    halo(draw, (ox + 28, oy + 18), "N", label, ink, cream, "mm")
    draw.line((ox + 28, oy + 28, ox + 28, oy + 52), fill=ink, width=2)
    draw.polygon([(ox + 28, oy + 24), (ox + 23, oy + 34), (ox + 33, oy + 34)], fill=ink)
    bar0 = m.px(-900, -980)
    bar1 = m.px(-700, -980)
    draw.line((bar0, bar1), fill=ink, width=3)
    halo(draw, (bar0[0], bar0[1] + 6), "200 STUDS", tiny, ink, cream, "lt")
    halo(draw, (ox + 12, oy + MAP - 36), "DRAFT. The live map is not changed.", tiny, ink, cream, "lt")
    halo(draw, m.px(plan["weighHouse"]["x"], plan["sellFloor"]["z1"] + 18), "TRUCKS BACK IN", tiny, ink, cream, "mm")

    # Legend.
    lx0 = ox + MAP + 28
    y = 96
    draw.text((lx0, y), "NINE REGIONS", font=label, fill=ink)
    y += 24
    for region in plan["regions"]:
        tint = rgb(region["tint"])
        draw.rectangle((lx0, y, lx0 + 16, y + 16), fill=tint, outline=ink)
        mark = "  proposed summit" if region["proposed"] else ""
        draw.text((lx0 + 22, y - 1), f"{region['order']}. {region['name']}{mark}", font=small, fill=ink)
        y += 20
    y += 8
    draw.text((lx0, y), "SHOPS  (number on the map)", font=label, fill=ink)
    y += 22
    for shop in plan["shops"]:
        draw.ellipse((lx0, y, lx0 + 16, y + 16), fill=ember if shop.get("y") else ink)
        draw.text((lx0 + 8, y + 8), str(shop["n"]), font=tiny, fill=cream, anchor="mm")
        draw.text((lx0 + 22, y - 1), shop["label"], font=load_font(FONTB, 12), fill=ink)
        y += 16
        why = shop["why"]
        # Wrap near 52 characters.
        words, line, lines = why.split(), "", []
        for word in words:
            trial = (line + " " + word).strip()
            if len(trial) > 52:
                lines.append(line)
                line = word
            else:
                line = trial
        if line:
            lines.append(line)
        for line in lines:
            draw.text((lx0 + 22, y), line, font=tiny, fill=mix(ink, cliff, 0.25))
            y += 13
        y += 4

    y += 4
    draw.text((lx0, y), "TRUNK LIFT  (not to map scale)", font=label, fill=ink)
    y += 22
    box = (lx0, y, lx0 + 210, y + 150)
    draw.rounded_rectangle(box, radius=6, fill=cream, outline=ink)
    # Shaft.
    draw.rectangle((lx0 + 70, y + 18, lx0 + 130, y + 132), outline=ink, width=2)
    draw.rectangle((lx0 + 82, y + 28, lx0 + 118, y + 58), fill=ember, outline=ink)
    draw.text((lx0 + 100, y + 40), "CAB", font=tiny, fill=cream, anchor="mm")
    draw.text((lx0 + 148, y + 22), "y 880 clouds", font=tiny, fill=ink)
    draw.text((lx0 + 148, y + 118), "y 800 lodge", font=tiny, fill=ink)
    draw.text((lx0 + 8, y + 64), "shaft 24", font=tiny, fill=ink)
    draw.text((lx0 + 8, y + 78), "door 10", font=tiny, fill=ink)
    draw.line((lx0 + 140, y + 36, lx0 + 190, y + 120), fill=trail, width=4)
    draw.text((lx0 + 150, y + 78), "log chute", font=tiny, fill=ink)
    y += 162
    notes = [
        "Roads: 32 main, 24 branch, 8 foot.",
        "Sky Pass is checked at the gate lodge.",
        "No root bridges. No updraft.",
        "River-float logs are later, not this plan.",
        "West of the river: timber country.",
        "East of the river: the shore and the bay.",
        "Fares are GameConfig until Connor picks.",
        "Ferry crossing is the live 40s (see the doc).",
    ]
    for note in notes:
        draw.text((lx0, y), note, font=small, fill=ink)
        y += 18

    return im


def card(plan: dict, row: dict) -> Image.Image:
    pal = plan["palette"]
    ink = rgb(pal["ink"])
    cream = rgb(pal["cream"])
    ember = rgb(pal["ember"])
    water = rgb(pal["water"])
    W, H = 1280, 720
    im = Image.new("RGB", (W, H), cream)
    draw = ImageDraw.Draw(im)
    title = load_font(FONTB, 28)
    body = load_font(FONT, 18)
    small = load_font(FONT, 15)
    draw.rectangle((0, 0, W, 64), fill=ink)
    draw.text((20, 16), row["title"].upper(), font=title, fill=cream)
    badge = "MUSTKEEP — do not delete" if row["mustKeep"] else "Not on the MustKeep list"
    draw.text((W - 20, 22), badge, font=small, fill=rgb(pal["lumen"]) if row["mustKeep"] else rgb(pal["sand"]), anchor="rt")

    # Locator: the whole square, this item in ember.
    ox, oy, side = 36, 100, 520
    draw.rectangle((ox, oy, ox + side, oy + side), fill=mix(rgb(pal["valley"]), cream, 0.45), outline=ink)

    def lp(x, z):
        return (
            ox + (x + HALF) / (2 * HALF) * side,
            oy + (HALF - z) / (2 * HALF) * side,
        )

    # River ghost, so the card still shows the draft the item is leaving.
    river_xy = [(p["x"], p["z"]) for p in plan["river"]]
    draw.line([lp(x, z) for x, z in river_xy], fill=water, width=3)
    if row.get("points"):
        draw.line([lp(p["x"], p["z"]) for p in row["points"]], fill=ember, width=4)
        for p in row["points"]:
            cx, cy = lp(p["x"], p["z"])
            draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill=ember)
    if row.get("x") is not None:
        cx, cy = lp(row["x"], row["z"])
        draw.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), fill=ember, outline=ink)
        draw.line((cx - 14, cy, cx + 14, cy), fill=ink, width=2)
        draw.line((cx, cy - 14, cx, cy + 14), fill=ink, width=2)
    draw.text((ox, oy + side + 8), "Orange is this leftover. Blue is the draft river.", font=small, fill=ink)

    # Reason, wrapped.
    x, y = 590, 96
    draw.text((x, y), "Waiting on Connor. Nothing is deleted in this PR.", font=load_font(FONTB, 16), fill=ember)
    y += 36
    words, line = row["reason"].split(), ""
    lines = []
    for word in words:
        trial = (line + " " + word).strip()
        if len(trial) > 42:
            lines.append(line)
            line = word
        else:
            line = trial
    if line:
        lines.append(line)
    for line in lines:
        draw.text((x, y), line, font=body, fill=ink)
        y += 26
    y += 16
    if row.get("x") is not None:
        draw.text((x, y), f"Live pin about ({row['x']:.0f}, {row['z']:.0f}). North is +Z.", font=small, fill=ink)
    elif row.get("points"):
        draw.text((x, y), "The orange line is the live path.", font=small, fill=ink)
    else:
        draw.text((x, y), "No fixed plot. It exists for the gondola ride.", font=small, fill=ink)
    return im


def contact(cards: list[Image.Image]) -> Image.Image:
    cols = 4
    thumb_w = 460
    gap = 12
    rows = (len(cards) + cols - 1) // cols
    thumbs = []
    for card_im in cards:
        h = int(card_im.height * (thumb_w / card_im.width))
        thumbs.append(card_im.resize((thumb_w, h), Image.Resampling.LANCZOS))
    thumb_h = thumbs[0].height
    sheet = Image.new("RGB", (cols * thumb_w + (cols + 1) * gap, rows * thumb_h + (rows + 1) * gap + 48), rgb("F3E7C9"))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 10), "T408 removals — one card each. None of these are deleted.", font=load_font(FONTB, 22), fill=rgb("3C2814"))
    for i, thumb in enumerate(thumbs):
        c, r = i % cols, i // cols
        sheet.paste(thumb, (gap + c * (thumb_w + gap), 48 + gap + r * (thumb_h + gap)))
    return sheet


def main() -> None:
    with open(PLAN, encoding="utf-8") as f:
        plan = json.load(f)
    os.makedirs(os.path.join(OUT, "removals"), exist_ok=True)
    overview = draw_overview(plan)
    overview.save(os.path.join(OUT, "overview.png"), optimize=True)
    cards = []
    for row in plan["removals"]:
        image = card(plan, row)
        image.save(os.path.join(OUT, "removals", row["id"] + ".png"), optimize=True)
        cards.append(image)
    contact(cards).save(os.path.join(OUT, "removals", "contact-sheet.png"), optimize=True)
    print(f"wrote overview and {len(cards)} removal cards")


if __name__ == "__main__":
    main()
