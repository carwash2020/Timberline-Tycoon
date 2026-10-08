#!/usr/bin/env python3
"""Top-down map of the V1 remake, drawn from the same numbers as MAP_V1.md.

Writes previews/v1-b/00-overview.png. No Studio render: a labelled plan
Connor can mark up before the terrain is built.
"""

from __future__ import annotations

import math
import os
import struct
import zlib

# Playable square is WorldHalf 1000. The picture includes the 200-stud skirt.
HALF = 1000
SKIRT = 200
SPAN = HALF + SKIRT
RING_C = (0.0, 80.0)
RING_R = 600.0
SAWMILL = (0.0, 110.0)

# Biome discs (these centers are the map; BiomeData.area is updated to match).
BIOMES = [
    ("starter", "Starter Forest", (0, -180), 100, (90, 150, 60)),
    ("hills", "Hills", (-500, 110), 150, (70, 130, 55)),
    ("snow", "Snow Peak", (0, 720), 115, (210, 225, 235)),
    ("volcano", "Volcano", (450, 500), 125, (160, 80, 50)),
    ("grove", "Gloam Ravine", (10, -720), 80, (90, 70, 120)),
    ("ferry", "Ferry Isle", (930, -50), 55, (210, 190, 120)),
    ("sky", "Lumen Isles", (680, 280), 100, (170, 190, 220)),
]

WATERS = [
    ("pond", "disc", (-40, -160), 16),
    ("lake", "disc", (-700, 180), 70),
    ("tarn", "disc", (40, 820), 16),
    ("ravine", "disc", (20, -760), 22),
    ("brook", "line", (210, -240), (210, -360)),
    ("cove", "disc", (-280, -760), 12),
    ("seep", "disc", (-300, -500), 12),
    ("mist", "disc", (690, 490), 12),
    ("pool", "disc", (-420, -261), 14),
    ("snowmelt", "disc", (-430, 760), 12),
    ("spring", "disc", (-700, 500), 12),
    ("coast", "shore", 780, 420),  # water east of x, south of z
]

# 28-wide roads. The ring is closed. The tunnel is underground.
def ring_points() -> list[tuple[float, float]]:
    pts = []
    for i in range(25):
        a = math.radians(i * 15)
        pts.append((RING_C[0] + RING_R * math.cos(a), RING_C[1] + RING_R * math.sin(a)))
    return pts


ROADS = [
    ("RingRoad", 28, ring_points()),
    ("SnowRoad", 28, [(0, 205), (0, 680), (0, 900)]),
    ("HillsRoad", 28, [(-125, 80), (-600, 80), (-560, 200)]),
    ("VolcanoRoad", 28, [(424, 504), (560, 560)]),
    ("SkyrootRoad", 28, [(600, 80), (800, 200), (700, 320)]),
    ("HillsCross", 28, [(-460, -300), (-560, -40), (-520, 220), (-460, 460)]),
    ("SouthLink", 28, [(0, -32), (0, -520)]),
    ("EastLink", 28, [(140, 80), (600, 80)]),
    ("DockRoad", 28, [(600, 80), (860, 160)]),
    ("RavineRoad", 28, [(0, -520), (-90, -560), (-90, -780)]),
]

TUNNEL = [(60, 700), (180, 660), (300, 600), (400, 560)]

# name, id, region, x, z. Order is the save order (first four fixed).
# Outer ring sits 118 studs outside the 28-wide ring (radius 718 about (0, 80)).
# Homes 5+ are listed nearest the sawmill first. The first four are the opener.
# Outer pads sit 118 studs outside a ring vertex (30 degrees apart).
# Homes 5+ are nearest the sawmill first.
PADS = [
    ("Birch Side", "birch", "Starter Forest", -118, -120),
    ("Orchard Edge", "orchard", "Starter Forest", -340.8, -260.8),
    ("Oak Side", "oak", "Starter Forest", 118, -300),
    ("The Climb", "climb", "The Hills", -718, 80),
    ("Ash Gate", "ash", "the east road", 359, 701.8),
    ("West Shelf", "west", "west country", -359, 701.8),
    ("North Bend", "north", "the north road", 118, 798),
    ("High Meadow", "high", "the north road", 621.8, 439),
    ("Pine Bend", "pine", "The Hills", -621.8, 439),
    ("East Meadow", "mill", "east of town", 710, -10),
    ("Long Meadow", "long", "south country", -621.8, -279),
    ("Lower Ridge", "ridge", "south country", -359, -541.8),
    ("North Meadow", "meadow", "the north road", 359, -541.8),
    ("East Field", "east", "east country", -208, -760),
]

SECRETS = [
    ("waterfall", (250, 260)),
    ("camp", (-360, -90)),
    ("ice", (190, 880)),
    ("lava", (700, 720)),
    ("ravine", (200, -820)),
]

MINE_MOUTH = (150, -150)
HIDDEN = [(-400, 40), (90, 800), (540, 640)]
FURNACE = (48, -110)  # 30 x 24 pad, long axis along X
DOCK = (860, 160)
TOWN = (-125, 140, -32, 205)


def dist(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def seg_dist(p, a, b) -> float:
    ax, az = a
    bx, bz = b
    abx, abz = bx - ax, bz - az
    len2 = abx * abx + abz * abz
    if len2 < 1e-6:
        return math.hypot(p[0] - ax, p[1] - az)
    t = max(0.0, min(1.0, ((p[0] - ax) * abx + (p[1] - az) * abz) / len2))
    return math.hypot(p[0] - (ax + abx * t), p[1] - (az + abz * t))


def poly_len(pts) -> float:
    return sum(dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def road_dist(p, roads, min_width=28) -> tuple[float, str]:
    best, name = 1e9, ""
    for road_name, width, pts in roads:
        if width < min_width:
            continue
        for i in range(len(pts) - 1):
            d = seg_dist(p, pts[i], pts[i + 1])
            if d < best:
                best, name = d, road_name
    return best, name


def nearest_biome(p):
    best, bd = None, 1e9
    for bid, _label, c, _r, _col in BIOMES:
        d = dist(p, c)
        if d < bd:
            best, bd = bid, d
    return best, bd


def nearest_water(p):
    best, bd = None, 1e9
    for w in WATERS:
        kind = w[1]
        if kind == "disc":
            d = max(0.0, dist(p, w[2]) - w[3])
            name = w[0]
        elif kind == "line":
            d = seg_dist(p, w[2], w[3])
            name = w[0]
        else:
            shore_x, north_z = w[2], w[3]
            if p[1] > north_z:
                d = 1e9
            else:
                d = max(0.0, shore_x - p[0])
            name = w[0]
        if d < bd:
            best, bd = name, d
    return best, bd


def tunnel_len() -> float:
    return poly_len(TUNNEL)


def validate() -> list[str]:
    lines = []
    bad = []
    tl = tunnel_len()
    lines.append(f"tunnel length {tl:.1f} (want 300-450)")
    if not 300 <= tl <= 450:
        bad.append("tunnel")
    seen = {}
    for i, a in enumerate(PADS):
        p = (a[3], a[4])
        rd, rname = road_dist(p, ROADS)
        biome, bd = nearest_biome(p)
        water, wd = nearest_water(p)
        h = dist(p, SAWMILL)
        lines.append(
            f"pad {a[1]:8} road {rd:6.1f} {rname:12}  {biome:8} {bd:6.0f}  water {water:8} {wd:6.0f}  haul {h:.0f}"
        )
        if rd > 120 or rd < 100:
            bad.append(f"{a[1]} road {rd:.0f}")
        if bd > 450:
            bad.append(f"{a[1]} biome {bd:.0f}")
        key = (biome, water)
        if key in seen:
            bad.append(f"{a[1]} shares {key} with {seen[key]}")
        seen[key] = a[1]
        for b in PADS[i + 1 :]:
            d = dist(p, (b[3], b[4]))
            if d < 248:
                bad.append(f"spacing {a[1]} {b[1]} {d:.0f}")
    mill = next(a for a in PADS if a[1] == "mill")
    if not (mill[3] > 296 and -140 < mill[4] < 80):
        bad.append("east meadow box")
    for name, p in SECRETS:
        rd, _rname = road_dist(p, ROADS, 1)
        lines.append(f"secret {name} road dist {rd:.1f}")
        if rd < 150:
            bad.append(f"secret {name} {rd:.0f}")
    sky = next(b for b in BIOMES if b[0] == "sky")
    lines.append(f"isles to dock {dist(sky[2], DOCK):.1f}")
    rest = PADS[4:]
    order = ", ".join(f"{a[1]} {dist((a[3], a[4]), SAWMILL):.0f}" for a in rest)
    lines.append("haul order: " + order)
    for i in range(len(rest) - 1):
        if dist((rest[i][3], rest[i][4]), SAWMILL) > dist((rest[i + 1][3], rest[i + 1][4]), SAWMILL) + 1e-6:
            bad.append(f"order {rest[i][1]} before {rest[i+1][1]}")
    if bad:
        lines.append("PROBLEMS:")
        lines.extend("  " + b for b in bad)
    return lines, bad


# --- PNG -----------------------------------------------------------------

def write_png(path: str, w: int, h: int, rgb: bytearray) -> None:
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw.extend(rgb[y * stride : (y + 1) * stride])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


# 5x7 glyphs, enough for labels. Rows are bit strings, left is high bit.
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "?": ["01110", "10001", "00001", "00110", "00100", "00000", "00100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
}


def blit(img, w, h, x, y, text, rgb, scale=2):
    gx = int(x)
    gy = int(y)
    for ch in text.upper():
        glyph = FONT.get(ch, FONT[" "])
        for row, bits in enumerate(glyph):
            for col, bit in enumerate(bits):
                if bit == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            px = gx + col * scale + sx
                            py = gy + row * scale + sy
                            if 0 <= px < w and 0 <= py < h:
                                i = (py * w + px) * 3
                                img[i] = rgb[0]
                                img[i + 1] = rgb[1]
                                img[i + 2] = rgb[2]
        gx += 6 * scale


def disc(img, w, h, to_px, c, r, rgb):
    cx, cy = to_px(c[0], c[1])
    rr = abs(to_px(c[0] + r, c[1])[0] - cx)
    rr2 = rr * rr
    x0, x1 = int(cx - rr), int(cx + rr)
    y0, y1 = int(cy - rr), int(cy + rr)
    for y in range(max(0, y0), min(h, y1 + 1)):
        for x in range(max(0, x0), min(w, x1 + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= rr2:
                i = (y * w + x) * 3
                img[i] = (img[i] * 2 + rgb[0]) // 3
                img[i + 1] = (img[i + 1] * 2 + rgb[1]) // 3
                img[i + 2] = (img[i + 2] * 2 + rgb[2]) // 3


def thick_line(img, w, h, x0, y0, x1, y1, rgb, rad):
    steps = int(max(abs(x1 - x0), abs(y1 - y0), 1))
    rad2 = rad * rad
    for s in range(steps + 1):
        t = s / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        for yy in range(int(y - rad) - 1, int(y + rad) + 2):
            for xx in range(int(x - rad) - 1, int(x + rad) + 2):
                if 0 <= xx < w and 0 <= yy < h and (xx - x) ** 2 + (yy - y) ** 2 <= rad2:
                    i = (yy * w + xx) * 3
                    img[i], img[i + 1], img[i + 2] = rgb


def render(path: str) -> None:
    w, h = 1280, 1100
    img = bytearray([232, 224, 206]) * (w * h)
    margin = 36
    map_w = 860

    def to_px(x, z):
        u = (x + SPAN) / (2 * SPAN)
        v = (SPAN - z) / (2 * SPAN)
        return margin + u * (map_w - 2 * margin), margin + 28 + v * (h - 2 * margin - 28)

    # skirt vs playable
    map_bottom = h - margin
    map_top = margin + 28
    map_span_y = map_bottom - map_top
    for y in range(map_top, map_bottom):
        for x in range(margin, map_w - margin):
            wx = (x - margin) / (map_w - 2 * margin) * 2 * SPAN - SPAN
            wz = SPAN - (y - map_top) / map_span_y * 2 * SPAN
            i = (y * w + x) * 3
            if abs(wx) > HALF or abs(wz) > HALF:
                img[i], img[i + 1], img[i + 2] = 168, 156, 126
            elif wx > 780 and wz < 420:
                img[i], img[i + 1], img[i + 2] = 90, 150, 170
            else:
                img[i], img[i + 1], img[i + 2] = 196, 176, 120

    for _bid, _label, c, r, col in BIOMES:
        disc(img, w, h, to_px, c, r, col)
    for water in WATERS:
        if water[1] == "disc":
            disc(img, w, h, to_px, water[2], water[3], (70, 140, 170))

    scale = (map_w - 2 * margin) / (2 * SPAN)
    for name, width, pts in ROADS:
        col = (90, 86, 78) if name != "RavineRoad" else (70, 60, 50)
        rad = max(2.0, width * scale * 0.5)
        for i in range(len(pts) - 1):
            a, b = to_px(*pts[i]), to_px(*pts[i + 1])
            thick_line(img, w, h, a[0], a[1], b[0], b[1], col, rad)
    # tunnel
    for i in range(len(TUNNEL) - 1):
        a, b = to_px(*TUNNEL[i]), to_px(*TUNNEL[i + 1])
        thick_line(img, w, h, a[0], a[1], b[0], b[1], (40, 40, 40), 3)

    # town
    x0, y0 = to_px(TOWN[0], TOWN[3])
    x1, y1 = to_px(TOWN[1], TOWN[2])
    thick_line(img, w, h, x0, y0, x1, y0, (40, 40, 40), 1.5)
    thick_line(img, w, h, x1, y0, x1, y1, (40, 40, 40), 1.5)
    thick_line(img, w, h, x1, y1, x0, y1, (40, 40, 40), 1.5)
    thick_line(img, w, h, x0, y1, x0, y0, (40, 40, 40), 1.5)

    ink = (20, 16, 12)
    for name, _i, _r, x, z in PADS:
        px, py = to_px(x, z)
        thick_line(img, w, h, px - 5, py - 5, px + 5, py - 5, (40, 30, 20), 2)
        thick_line(img, w, h, px + 5, py - 5, px + 5, py + 5, (40, 30, 20), 2)
        thick_line(img, w, h, px + 5, py + 5, px - 5, py + 5, (40, 30, 20), 2)
        thick_line(img, w, h, px - 5, py + 5, px - 5, py - 5, (40, 30, 20), 2)
        blit(img, w, h, px + 7, py - 10, name.split()[0], ink, 2)

    mx, my = to_px(*MINE_MOUTH)
    blit(img, w, h, mx - 18, my - 16, "MINE", (120, 30, 20), 2)
    for hx, hz in HIDDEN:
        px, py = to_px(hx, hz)
        blit(img, w, h, px - 8, py - 8, "H", (140, 40, 20), 2)
    for name, (sx, sz) in SECRETS:
        px, py = to_px(sx, sz)
        blit(img, w, h, px - 4, py - 8, "?", (20, 20, 80), 2)

    fx, fy = to_px(*FURNACE)
    blit(img, w, h, fx, fy, "FURNACE", ink, 1)
    dx, dy = to_px(*DOCK)
    blit(img, w, h, dx, dy, "DOCK", ink, 1)

    labels = [
        ((0, 40), "TOWN"),
        ((0, -180), "STARTER"),
        ((-500, 110), "HILLS"),
        ((0, 720), "SNOW"),
        ((450, 500), "VOLCANO"),
        ((10, -720), "GLOAM"),
        ((930, -50), "FERRY"),
        ((680, 280), "LUMEN"),
        ((-700, 180), "LAKE"),
        ((100, -220), "POND"),
        ((220, 640), "TUNNEL"),
    ]
    for (x, z), text in labels:
        px, py = to_px(x, z)
        blit(img, w, h, px - 3 * len(text), py - 22, text, ink, 2)

    blit(img, w, h, 16, 8, "TIMBERLINE V1  2000 STUD SQUARE  NORTH UP", ink, 2)
    legend = [
        "RING ROAD 28 WIDE",
        "4 LINKS PLUS HILLS",
        "TUNNEL PEAK-VOLCANO",
        "MINE WALK-IN SOUTH",
        "H HIDDEN ENTRANCE",
        "? SECRET",
        "FURNACE PAD",
        "DOCK AND FERRY",
        "LUMEN ISLES",
        "SKIRT PAST EDGE",
    ]
    lx = map_w + 16
    blit(img, w, h, lx, 40, "KEY", ink, 2)
    for i, line in enumerate(legend):
        blit(img, w, h, lx, 70 + i * 22, line, ink, 2)
    blit(img, w, h, lx, 320, "PADS", ink, 2)
    for i, (name, _pid, _region, _x, _z) in enumerate(PADS):
        blit(img, w, h, lx, 348 + i * 18, f"{i+1} {name}", ink, 1)
    write_png(path, w, h, img)


def main() -> None:
    lines, bad = validate()
    for line in lines:
        print(line)
    if bad:
        raise SystemExit(1)
    out = os.path.join("previews", "v1-b", "00-overview.png")
    render(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
