#!/usr/bin/env python3
"""Lane X: the BADGES panel with the eight new rows, locked and earned.

Hand-built from the same tokens as UITheme (Skin / Styles) and BadgeUI's own
numbers: a 280-wide Panel card (Paper plaque, 8 px inset), a 20 px BADGES
title, an 18 px "n of 25" line, then 248 x 44 rows 6 px apart: UITheme
"full" (walnut, amber edge, cream) for an earned badge and "locked" (muted)
for the rest, reading "Name  ·  Earned" or "Name  ·  Locked". It is scrolled
to the end so the new rows show. Phone frames are 667x375 with Roblox's
thumbstick and jump button drawn and the HUD's real icon column; the panel
is 200 tall there and clear of both. PC frames are 1920x1080 with the real
HUD layout around the panel (420 tall). Liberation Sans stands in for Gotham.

  python3 tools/preview/v1x_badges.py   writes previews/v1-x/badges-*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_round3 as r  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-x")

# BadgeData.All(), in order: (name, earned in this picture).
BADGES = [
	("First Sale", True),
	("First Truck", True),
	("First Plank", True),
	("Starter Forest", True),
	("The Hills", True),
	("Snowfields", False),
	("The Volcano", False),
	("Gloam Hollow", False),
	("Aether Isles", False),
	("Ferry Island", False),
	("Secret Cave", False),
	("North Strip", False),
	("Frostwood", True),
	("Emberwood", False),
	("Gloamwood", False),
	("Lumenwood", False),
	("Lanternwood", False),
	("The Bayou", True),
	("Red Mesa", False),
	("Bog Cypress", False),
	("Ironwood", False),
	("First Build", True),
	("Homestead", False),
	("Stonemason", False),
	("Millionaire", False),
]

ROW_W, ROW_H, GAP, INSET = 248, 44, 6, 8
CARD_W = 280
BTN = r.BTN_DROP


def card(im, right, top, height):
	d = ImageDraw.Draw(im)
	face = r.plaque(im, (right - CARD_W, top, right, top + height))
	x0, y0, x1, y1 = face
	pitch = ROW_H + BTN + GAP
	head_h = 20 + GAP + 18 + GAP
	rows_top = INSET + head_h
	canvas_h = rows_top + len(BADGES) * pitch + INSET
	view_h = y1 - y0 - 2 * 2
	# Scrolled to the end, in whole rows: the first row shown sits just under the top edge.
	visible = int((view_h - 6) // pitch)
	first = len(BADGES) - visible
	scroll = rows_top + first * pitch - 6
	scroll = min(scroll, canvas_h - view_h + pitch)
	paste = Image.new("RGB", (x1 - x0, view_h), r.PAPER)
	earned = sum(1 for _, e in BADGES if e)
	y = rows_top - scroll
	for name, on in BADGES:
		bx0 = INSET + 6
		if -ROW_H < y < view_h:
			r.button(
				paste,
				(bx0, y, bx0 + ROW_W, y + ROW_H),
				f"{name}  \u00b7  {'Earned' if on else 'Locked'}",
				"bark" if on else "locked",
				fnt=r.font(r.BOLD, 14),
			)
		y += pitch
	# The title and count scroll away; a thin header strip says where we are.
	im.paste(paste, (x0, y0 + 2))
	d.rounded_rectangle((x0, y0, x1, y1), radius=r.PLAQUE_CORNER, outline=r.BARK, width=2)
	bar_h = max(20, int(view_h * view_h / canvas_h))
	d.rounded_rectangle((x1 - 11, y1 - 8 - bar_h, x1 - 6, y1 - 8), radius=2, fill=(0x8A, 0x7A, 0x60))
	return face, earned


def caption(im, text, size, y):
	d = ImageDraw.Draw(im)
	f = r.font(r.REG, size)
	w = r.text_w(d, text, f)
	d.rectangle((0, y - 4, w + 24, y + size + 6), fill=(0, 0, 0))
	d.text((12, y), text, font=f, fill=(255, 255, 255))


def phone():
	im = r.m.scene_backdrop(667, 375)
	r.cash_plaque(im, 667 - 12, 8)
	# The side buttons put themselves away while a popup is open (HUD.Popup).
	right = 667 - 12
	_, earned = card(im, right, 62, 196)
	r.m.phone_zones(im)
	caption(im, f"Phone 667x375: BADGES panel, scrolled to the new rows ({earned} of {len(BADGES)} earned here), clear of thumbstick and jump", 10, 352)
	return im


def pc():
	w, h = 1920, 1080
	im = r.m.scene_backdrop(w, h)
	r.cash_plaque(im, w - 24, 16, 200)
	# The left column (UITheme.LeftColumn): the BADGES button, selected.
	r.button(im, (16, 120, 232, 164), "FIELD GUIDE", "bark", fnt=r.font(r.BOLD, 18))
	r.button(im, (16, 176, 232, 220), "BADGES", "bark", fnt=r.font(r.BOLD, 18), selected=True)
	_, earned = card(im, w - 24, 88, 420)
	d = ImageDraw.Draw(im)
	d.rounded_rectangle((750, 1000, 1170, 1065), radius=8, fill=(0x22, 0x22, 0x22))
	caption(im, f"PC 1920x1080: BADGES (B opens, Esc closes), 420 tall so seven rows show, scrolled to the new ones ({earned} of {len(BADGES)} earned here)", 16, 1046)
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	phone().save(os.path.join(OUT, "badges-667x375.png"))
	pc().save(os.path.join(OUT, "badges-1920x1080.png"))
	print("wrote", OUT)


if __name__ == "__main__":
	main()
