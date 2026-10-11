#!/usr/bin/env python3
"""Contact sheet of every store's interior renders.

    python3 tools/preview/store_contact_sheet.py

Reads previews/store-interiors/<store>-{entrance,tier-stand,phone,night}.png
for every store that has them and writes previews/store-interiors/contact-sheet.png:
one row per store, the four views in that order, each scaled to a 480 px tall
cell with its name under it. Stores are listed in the order of STORES; a store
with no renders yet is skipped.
"""
import os
import sys

from PIL import Image, ImageDraw

STORES = ["toolshed", "hearth", "sparkworks", "dealership"]
VIEWS = ["entrance", "tier-stand", "phone", "night"]
CELL_H = 360
LABEL_H = 28
PAD = 12
BG = (42, 31, 23)  # UITheme Panel
INK = (243, 231, 201)  # UITheme Cream

root = os.path.join(os.path.dirname(__file__), "..", "..", "previews", "store-interiors")
rows = []
for store in STORES:
    cells = []
    for view in VIEWS:
        path = os.path.join(root, f"{store}-{view}.png")
        if os.path.exists(path):
            img = Image.open(path).convert("RGB")
            w = round(img.width * CELL_H / img.height)
            cells.append((view, img.resize((w, CELL_H), Image.LANCZOS)))
    if cells:
        rows.append((store, cells))
if not rows:
    sys.exit("no store renders under previews/store-interiors")

width = max(sum(c.width for _, c in cells) + PAD * (len(cells) + 1) for _, cells in rows)
height = len(rows) * (CELL_H + LABEL_H + PAD) + PAD
sheet = Image.new("RGB", (width, height), BG)
draw = ImageDraw.Draw(sheet)
y = PAD
for store, cells in rows:
    x = PAD
    for view, img in cells:
        sheet.paste(img, (x, y))
        draw.text((x + 4, y + CELL_H + 6), f"{store} · {view}", fill=INK)
        x += img.width + PAD
    y += CELL_H + LABEL_H + PAD
out = os.path.join(root, "contact-sheet.png")
sheet.save(out)
print(out, sheet.size)
