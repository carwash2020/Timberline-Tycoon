#!/usr/bin/env python3
"""Lane E: Rook's job board, the climate vignette, "Day N" and the joy banner.

Hand-built from the same tokens as UITheme (the GAD plaque and button skins,
reused from v1u_round3) and from DailyUI's own numbers: a 280-wide panel, 10 px
padding, a 44 px Close | Take row, goal rows with a bar, one footer line. The
phone panel drops the heading, the calendar, the countdown and "Tomorrow" so it
is about 212 tall and ends above the jump zone; the PC panel shows everything.
Liberation Sans stands in for Gotham. These are composites of the layout, not
engine screenshots.

  python3 tools/preview/v1e_ui.py   writes previews/v1-e/ui-*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_round3 as r  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-e")
m = r.m

GREY = (140, 128, 110)
SALE_GREEN = (0x4C, 0xC3, 0x6A)

GOALS = [
	("[done] Fell 4 trees  (4/4)", "+$30", 1.0, "owed"),
	("[done] Sell 18 logs  (18/18)", "+$30", 1.0, "owed"),
	("Discover a new area  (0/1)", "+$30", 0.0, "open"),
]


def goal_rows(im, x, y, w, row_h, text_px, bar_y):
	d = ImageDraw.Draw(im)
	fnt = r.font(r.REG, text_px)
	fb = r.font(r.BOLD, text_px)
	for text, reward, frac, state in GOALS:
		d.text((x, y), text, font=fnt, fill=r.INK)
		d.text((x + w - r.text_w(d, reward, fb), y), reward, font=fb, fill=r.GREEN)
		d.rounded_rectangle((x, y + bar_y, x + w, y + bar_y + 8), radius=4, fill=r.PAPER_DARK)
		if frac > 0:
			d.rounded_rectangle((x, y + bar_y, x + int(w * frac), y + bar_y + 8), radius=4, fill=r.GREEN)
		y += row_h + 6
	return y


def board(im, right, top, compact):
	"""The panel face as DailyUI lays it out. Returns its bottom edge."""
	pad, inner = 10, 280 - 20
	h = 212 if compact else 330
	face = r.plaque(im, (right - 280, top, right, top + h))
	x0, y0 = face[0] + pad, face[1] + pad
	d = ImageDraw.Draw(im)
	# Close (84 x 44) and Take (fills the rest), 8 px apart.
	r.button(im, (x0, y0, x0 + 84, y0 + 44), "Close", "bark", fnt=r.font(r.BOLD, 16), selected=True)
	r.button(im, (x0 + 92, y0, x0 + inner, y0 + 44), "Take $135", "confirm", fnt=r.font(r.BOLD, 16))
	y = y0 + 44 + 6
	if not compact:
		d.text((x0, y), "ROOK'S JOBS", font=r.font(r.BOLD, 14), fill=r.BARK)
		y += 22
	y = goal_rows(im, x0, y, inner, 34 if compact else 40, 13 if compact else 14, 22 if compact else 26)
	foot = "Bonus for all 3: $60" if compact else "Finish all 3 for a bonus of $60 (2-day streak)."
	d.text((x0, y), foot, font=r.font(r.REG, 13), fill=r.INK)
	y += 20
	if not compact:
		# the daily-return calendar, one row of seven
		cw = (inner - 6 * 3) // 7
		for i in range(7):
			cx = x0 + i * (cw + 3)
			fill = r.GREEN if i == 1 else (r.PAPER_DARK if i < 1 else r.PAPER)
			d.rounded_rectangle((cx, y, cx + cw, y + 46), radius=6, fill=fill, outline=r.BARK)
			d.text((cx + 6, y + 6), f"{i + 1}", font=r.font(r.BOLD, 12), fill=r.CREAM_SKIN if i == 1 else r.INK)
		y += 54
		d.text((x0, y), "New goals in 5h 12m", font=r.font(r.REG, 12), fill=r.BARK)
		y += 18
		d.text((x0, y), "Tomorrow: Fell 5 trees", font=r.font(r.REG, 12), fill=GREY)
	return face[3]


def caption(im, text, size, y):
	d = ImageDraw.Draw(im)
	f = r.font(r.REG, size)
	w = r.text_w(d, text, f)
	d.rectangle((0, y - 4, w + 24, y + size + 6), fill=(0, 0, 0))
	d.text((12, y), text, font=f, fill=(255, 255, 255))


def jobboard_phone():
	im = m.scene_backdrop(667, 375)
	r.cash_plaque(im, 667 - 12, 8)
	bottom = board(im, 667 - 12, 62, True)
	m.phone_zones(im)
	caption(im, f"Phone 667x375: Rook's job board, panel ends at y {bottom}, above the jump zone; Close | Take 44 tall", 10, 352)
	return im


def jobboard_pc():
	w, h = 1920, 1080
	im = m.scene_backdrop(w, h)
	r.cash_plaque(im, w - 24, 16, 200)
	board(im, w - 24, 88, False)
	caption(im, "PC 1920x1080: Rook's job board (E to talk, Esc closes), tomorrow's first goal greyed out", 16, 1046)
	return im


def vignette(im, rgb, alpha):
	"""Four edge bands, solid at the screen edge, clear toward the middle (WorldUI)."""
	w, h = im.size
	band = int(min(w, h) * 0.0 + 0.16 * min(w, h)) if False else None
	over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	px = over.load()
	ew, eh = 0.16 * w, 0.16 * h
	for y in range(h):
		for x in range(w):
			a = 0.0
			a = max(a, 1 - x / ew if x < ew else 0)
			a = max(a, 1 - (w - 1 - x) / ew if w - 1 - x < ew else 0)
			a = max(a, 1 - y / eh if y < eh else 0)
			a = max(a, 1 - (h - 1 - y) / eh if h - 1 - y < eh else 0)
			if a > 0:
				px[x, y] = (rgb[0], rgb[1], rgb[2], int(255 * a * alpha))
	return Image.alpha_composite(im.convert("RGBA"), over).convert("RGB")


def hud_pieces(im, phone, toast):
	w, h = im.size
	d = ImageDraw.Draw(im)
	edge = 12 if phone else 24
	r.cash_plaque(im, w - edge, 8 if phone else 16, 150 if phone else 200)
	ink = (0x1E, 0x1B, 0x18)
	if phone:
		# On a phone the clock is in the corner's second line, under the cash.
		cx, cy, cw, ch = w - edge - 92, 62, 92, 28
	else:
		# On PC it sits left of the cash plaque.
		cx, cy, cw, ch = w - edge - 200 - 8 - 112, 16, 112, 36
	r.button(im, (cx, cy, cx + cw, cy + ch), "Day 2:05 PM", "bark", fnt=r.font(r.BOLD, 13 if phone else 15))
	label = "Day 3"
	f = r.font(r.BOLD, 14)
	d.text((cx + (cw - r.text_w(d, label, f)) // 2, cy + ch + 5), label, font=f, fill=r.CREAM, stroke_width=1, stroke_fill=ink)
	goal = "Buy the Steel Axe ($110)"
	fg = r.font(r.BOLD, 13 if phone else 15)
	gy = (cy + ch + 28) if phone else 16 + 44 + 10
	d.text((w - edge - r.text_w(d, goal, fg), gy), goal, font=fg, fill=r.CREAM, stroke_width=1, stroke_fill=ink)
	if toast:
		tw = int(r.text_w(d, toast, r.font(r.BOLD, 14)) + 24)
		tx = (w - tw) // 2
		d.rounded_rectangle((tx, 52, tx + tw, 84), radius=10, fill=ink)
		d.text((tx + 12, 60), toast, font=r.font(r.BOLD, 14), fill=r.CREAM)


def climate(phone, kind):
	w, h = (667, 375) if phone else (1920, 1080)
	im = m.scene_backdrop(w, h)
	rgb, alpha, tip = ((191, 227, 245), 0.55, "Cold hurts here. Find a campfire or wear a Coat.") if kind == "cold" else ((232, 100, 42), 0.45, "Heat hurts here. Find shade or wear Heat Boots.")
	im = vignette(im, rgb, alpha)
	hud_pieces(im, phone, tip)
	if phone:
		m.phone_zones(im)
	caption(im, f"{'Phone 667x375' if phone else 'PC 1920x1080'}: {kind} vignette (exposure {int(alpha / 0.55 * 100)}%), the first-time tip, Day N under the clock, one goal line", 10 if phone else 16, 352 if phone else 1046)
	return im


def joy(phone):
	w, h = (667, 375) if phone else (1920, 1080)
	im = m.scene_backdrop(w, h)
	hud_pieces(im, phone, None)
	d = ImageDraw.Draw(im)
	bw, bh = 340, 84
	bx, by = (w - bw) // 2, int(h * 0.14)
	d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=12, fill=(0x1E, 0x1B, 0x18), outline=r.AMBER, width=2)
	t = "LESSONS DONE!"
	f = r.font(r.BOLD, 24)
	d.text((bx + (bw - r.text_w(d, t, f)) // 2, by + 6), t, font=f, fill=r.AMBER)
	s = "The forest is yours. Next: Buy the Steel Axe ($110)"
	f2 = r.font(r.BOLD, 14)
	lines = ["The forest is yours. Next:", "Buy the Steel Axe ($110)"]
	for i, line in enumerate(lines):
		d.text((bx + (bw - r.text_w(d, line, f2)) // 2, by + 40 + i * 17), line, font=f2, fill=r.CREAM_SKIN)
	import random

	rnd = random.Random(4)
	for i in range(36):
		x, y = rnd.randint(0, w), rnd.randint(int(h * 0.05), h)
		col = (r.CREAM_SKIN, r.AMBER, r.GREEN)[i % 3]
		d.rectangle((x, y, x + 8, y + 14), fill=col)
	if phone:
		m.phone_zones(im)
	caption(im, f"{'Phone 667x375' if phone else 'PC 1920x1080'}: the joy beat at the end of the lessons (banner, chime, confetti), next goal named", 10 if phone else 16, 352 if phone else 1046)
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	jobboard_phone().save(os.path.join(OUT, "ui-jobboard-667x375.png"))
	jobboard_pc().save(os.path.join(OUT, "ui-jobboard-1920x1080.png"))
	for kind in ("cold", "heat"):
		climate(True, kind).save(os.path.join(OUT, f"ui-{kind}-667x375.png"))
		climate(False, kind).save(os.path.join(OUT, f"ui-{kind}-1920x1080.png"))
	joy(True).save(os.path.join(OUT, "ui-joy-667x375.png"))
	joy(False).save(os.path.join(OUT, "ui-joy-1920x1080.png"))
	print("wrote", OUT)


if __name__ == "__main__":
	main()
