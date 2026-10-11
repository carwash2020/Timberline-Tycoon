#!/usr/bin/env python3
"""Lane F mockups: the placer's controls, the blueprint book and the SAVES
panel, at 667x375 (phone), 1920x1080 (PC) and an Xbox 1920x1080.

A faithful PIL mock from the UITheme tokens, like Lane U's (v1u_mockups.py,
whose backdrop, thumbstick and jump button it reuses). Inter stands in for
Roblox Gotham. The layouts follow Shared/PlaceControlsLogic (the numbers
below are copied from it and asserted against the zones), SaveSlotUI and
PlotUI; run `lune run tests/run PlaceControlsLogic` for the rules themselves.
"""

from __future__ import annotations

import importlib.util
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("v1u", os.path.join(HERE, "v1u_mockups.py"))
v1u = importlib.util.module_from_spec(spec)
sys.modules["v1u"] = v1u
spec.loader.exec_module(v1u)

OUT = os.path.join(HERE, "..", "..", "previews", "v1-f")
font, rr, center_text = v1u.font, v1u.rr, v1u.center_text
BOLD, REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
v1u.BOLD, v1u.REG = BOLD, REG
CREAM, AMBER, AMBER_EDGE = v1u.CREAM, v1u.AMBER, v1u.AMBER_EDGE
CONFIRM, CONFIRM_EDGE, CONFIRM_INK = v1u.CONFIRM, v1u.CONFIRM_EDGE, v1u.CONFIRM_INK
MUTED_FILL, SELECTION = v1u.MUTED_FILL, v1u.SELECTION
PAPER, PAPER_DARK, BARK, INK = (0xF0, 0xE1, 0xC3), (0xE2, 0xCF, 0xAA), (0x58, 0x3A, 0x22), (0x3C, 0x28, 0x14)
GREEN_EDGE = (0x2F, 0x8A, 0x48)

# --- PlaceControlsLogic numbers -------------------------------------------
MIN_BUTTON, GAP = 44, 8
THUMB = (240, 220)  # ThumbZone w, h
JUMP = (200, 200)  # JumpZone w, h
HOTBAR = 70  # UITheme.Bottom() on desktop (margin 12 + 70 tool hotbar); a phone 12 + 58


def scale_for(w, h):
	short = min(w, h)
	if short < 500:
		return max(0.7, min(0.85, short / 480))
	return max(1.0, h / 864)


def ghost_wall(im, w, h, valid=True):
	"""A placement ghost on the platform: a green (or red) translucent wall."""
	overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
	d = ImageDraw.Draw(overlay)
	cx, base = int(w * 0.5), int(h * 0.62)
	ww, wh = int(w * 0.17), int(h * 0.2)
	col = (70, 200, 90, 120) if valid else (255, 80, 80, 120)
	edge = (70, 200, 90, 255) if valid else (255, 80, 80, 255)
	# a platform slab
	d.rectangle((cx - ww * 2, base, cx + ww * 2, base + int(h * 0.04)), fill=(0x6E, 0x94, 0x48, 255))
	d.rectangle((cx - ww // 2, base - wh, cx + ww // 2, base), fill=col, outline=edge, width=3)
	im.paste(Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB"))


def card(draw, box, radius=12):
	"""A Paper plaque on a Bark drop edge, like UITheme.Card."""
	x0, y0, x1, y1 = box
	rr(draw, (x0, y0 + 4, x1, y1 + 4), BARK, radius=radius)
	rr(draw, box, PAPER_DARK, radius=radius, outline=AMBER_EDGE, width=2)


def btn(draw, box, label, style, fnt, selected=False):
	fills = {
		"buy": (CONFIRM, CONFIRM_EDGE, CONFIRM_INK),
		"bark": (BARK, (0x3A, 0x26, 0x16), CREAM),
		"skip": (MUTED_FILL, (0x3E, 0x32, 0x29), CREAM),
		"locked": (MUTED_FILL, (0x3E, 0x32, 0x29), (0xCD, 0xBF, 0xA3)),
	}
	fill, edge, ink = fills[style]
	x0, y0, x1, y1 = box
	drop = 3
	if selected:
		rr(draw, (x0 - 6, y0 - 6, x1 + 6, y1 + drop + 6), None, radius=14, outline=SELECTION, width=4)
	rr(draw, (x0, y0 + drop, x1, y1 + drop), edge, radius=10)
	rr(draw, (x0, y0, x1, y1), fill, radius=10)
	center_text(draw, (x0, y0, x1, y1), label, fnt, ink)


def dashed_zone(im, box, color):
	overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
	d = ImageDraw.Draw(overlay)
	d.rectangle(box, fill=color + (36,), outline=color + (200,), width=2)
	im.paste(Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB"))


# --- placer ----------------------------------------------------------------
def placer_phone() -> Image.Image:
	w, h = 667, 375
	s = scale_for(w, h)
	im = v1u.scene_backdrop(w, h)
	ghost_wall(im, w, h)
	v1u.phone_zones(im)
	d = ImageDraw.Draw(im)
	# The two zones Builder's thumbstick and jump button use: the bar must stay out.
	thumb = (0, h - THUMB[1], THUMB[0], h)
	jump = (w - JUMP[0], h - JUMP[1], w, h)
	dashed_zone(im, thumb, (255, 255, 255))
	dashed_zone(im, jump, (255, 255, 255))
	d = ImageDraw.Draw(im)
	d.text((thumb[0] + 8, thumb[1] + 6), "thumbstick zone", font=font(REG, 10), fill=(255, 255, 255))
	d.text((jump[0] + 8, jump[1] + 6), "jump zone", font=font(REG, 10), fill=(255, 255, 255))
	# The bar: two columns of 80, three rows of 44 (8 apart), label above.
	bw = (2 * 80 + GAP) * s
	bh = (40 + 3 * MIN_BUTTON + 2 * GAP + 8) * s
	x0 = (w - bw) / 2 - 8 * s
	y1 = h - (12 + 58) * s
	bar = (x0, y1 - bh - 10 * s, x0 + bw + 16 * s, y1)
	for zone in (thumb, jump):
		assert not v1u.overlaps(bar, zone), f"phone bar overlaps a zone: {bar} vs {zone}"
	card(d, bar, 10)
	f = font(BOLD, max(10, int(13 * s)))
	label = (bar[0] + 8 * s, bar[1] + 6 * s, bar[2] - 8 * s, bar[1] + 6 * s + 36 * s)
	d.multiline_text((label[0], label[1]), "Place the Short Wall\n$32", font=f, fill=INK, spacing=2)
	bx, by = bar[0] + 8 * s, bar[1] + (6 + 40) * s
	bf = font(BOLD, max(9, int(14 * s)))
	cells = [
		("ROTATE", "bark", 0, 0, 80),
		("PLACE", "buy", 88, 0, 80),
		("UP", "bark", 0, 52, 80),
		("DOWN", "bark", 88, 52, 80),
		("CANCEL", "skip", 0, 104, 168),
	]
	for text, style, cx, cy, cw in cells:
		btn(d, (bx + cx * s, by + cy * s, bx + (cx + cw) * s, by + (cy + 44) * s), text, style, bf)
	return im


def hotbar(d, w, h, s):
	hw = 6 * 56 * s
	x0 = (w - hw) / 2
	for i in range(6):
		bx = x0 + i * 56 * s
		rr(d, (bx, h - 66 * s, bx + 50 * s, h - 12 * s), (0x22, 0x22, 0x22), radius=6, outline=AMBER if i == 0 else (0x55, 0x55, 0x55), width=2)
	center_text(d, (x0, h - 66 * s, x0 + 50 * s, h - 12 * s), "Hammer", font(BOLD, int(11 * s)), CREAM)


def placer_pc() -> Image.Image:
	w, h = 1920, 1080
	s = scale_for(w, h)
	im = v1u.scene_backdrop(w, h)
	ghost_wall(im, w, h)
	d = ImageDraw.Draw(im)
	bw = (5 * 96 + 4 * GAP) * s
	bar_w = max(bw, 320 * s) + 20 * s
	bh = (24 + MIN_BUTTON + 16) * s
	x0 = (w - bar_w) / 2
	y1 = h - (12 + 70) * s
	bar = (x0, y1 - bh, x0 + bar_w, y1)
	card(d, bar, 12)
	f = font(BOLD, int(14 * s))
	center_text(d, (bar[0], bar[1] + 6 * s, bar[2], bar[1] + 30 * s), "Place the Short Wall · $32", f, INK)
	bx = bar[0] + (bar_w - bw) / 2
	by = bar[1] + 34 * s
	bf = font(BOLD, int(14 * s))
	for i, (text, style) in enumerate([("ROTATE", "bark"), ("UP", "bark"), ("DOWN", "bark"), ("PLACE", "buy"), ("CANCEL", "skip")]):
		btn(d, (bx + i * (96 + GAP) * s, by, bx + (i * (96 + GAP) + 96) * s, by + MIN_BUTTON * s), text, style, bf)
	hotbar(d, w, h, s)
	hint = "Click to place · R turn · Q stop"
	d.text((24 * s, 24 * s), hint, font=font(REG, int(16 * s)), fill=(255, 255, 255))
	return im


def glyph(d, cx, cy, r, text, fnt, fill=CREAM, ink=INK):
	d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=(0x20, 0x20, 0x20), width=2)
	bbox = d.textbbox((0, 0), text, font=fnt)
	d.text((cx - (bbox[2] - bbox[0]) / 2, cy - (bbox[3] - bbox[1]) / 2 - 2), text, font=fnt, fill=ink)


def placer_xbox() -> Image.Image:
	w, h = 1920, 1080
	s = scale_for(w, h)
	im = v1u.scene_backdrop(w, h)
	ghost_wall(im, w, h)
	# the crosshair the ghost follows
	d = ImageDraw.Draw(im)
	cx, cy = w // 2, int(h * 0.62)
	d.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), outline=(255, 255, 255), width=3)
	d.line((cx - 24, cy, cx + 24, cy), fill=(255, 255, 255), width=2)
	d.line((cx, cy - 24, cx, cy + 24), fill=(255, 255, 255), width=2)
	# The placing bar is the label line only; the pad has every action.
	bar_w, bar_h = 560 * s, 64 * s
	bar = ((w - bar_w) / 2, h - (60 + 70) * s - bar_h, (w + bar_w) / 2, h - (60 + 70) * s)
	card(d, bar, 12)
	center_text(d, (bar[0], bar[1], bar[2], bar[3]), "Place the Short Wall · $32", font(BOLD, int(20 * s)), INK)
	# The hint line with the pad's glyphs, as the HUD shows it (HintLogic "build").
	rowy = bar[3] + 22 * s
	gf = font(BOLD, int(16 * s))
	tf = font(REG, int(18 * s))
	x = (w - 1100 * s) / 2
	items = [("A", "place"), ("▶", "turn"), ("▲▼", "raise / lower"), ("LT", "lock"), ("RB LB", "slide"), ("B", "stop")]
	for g, text in items:
		r = 18 * s
		glyph(d, x + r, rowy, r, g, gf) if len(g) <= 2 else (rr(d, (x, rowy - r, x + 64 * s, rowy + r), CREAM, radius=int(r), outline=(0x20, 0x20, 0x20), width=2), center_text(d, (x, rowy - r, x + 64 * s, rowy + r), g, gf, INK))
		width = (2 * r if len(g) <= 2 else 64 * s)
		d.text((x + width + 8 * s, rowy - 12 * s), text, font=tf, fill=(255, 255, 255))
		x += width + 8 * s + d.textlength(text, font=tf) + 36 * s
	hotbar(d, w, h, s)
	return im


# --- the blueprint book ------------------------------------------------------
ROWS = [
	("Short Wall", "· Free?", None, "Buildings · 4 × 1 studs · 4 u³ of planks, one wood · fee $16", "Place $16", "buy", (0x82, 0x5A, 0x32)),
	("Tall Wall", None, None, "Buildings · 8 × 1 studs · 12 planks · fee $48", "Place $48", "buy", (0x82, 0x5A, 0x32)),
	("Sloped Roof", None, None, "Buildings · 8 × 8 studs · fee $64", "Place $64", "buy", (0x82, 0x5A, 0x32)),
	("Table", "· Free", None, "Decor · 4 × 4 studs · Free to place", "Place", "buy", (0x82, 0x5A, 0x32)),
	("Gold-banded Chest", "· 1 in stock", None, "Decor · 4 × 3 studs · Placed from what you crafted", "Place", "buy", (0xD4, 0xA9, 0x2E)),
	("Sandstone Wall", None, None, "Buildings · 2 sandstone slabs · fee $8 · Unlocks at Red Mesa", "Red Mesa", "locked", (0xC8, 0x64, 0x3C)),
	("Sandstone Arch", None, None, "Buildings · 4 sandstone slabs · fee $16 · Unlocks at Red Mesa", "Red Mesa", "locked", (0xC8, 0x64, 0x3C)),
	("Copper Trim", None, None, "Decor · 1 Copper ingot · fee $4 · Unlocks at Smith", "Smith", "locked", (0xB8, 0x73, 0x33)),
]


def blueprint_book(w, h) -> Image.Image:
	s = scale_for(w, h)
	im = v1u.scene_backdrop(w, h)
	d = ImageDraw.Draw(im)
	pw = min(w - 24 * s * 2, 760 * s)
	ph = h - 16 * s
	x0, y0 = (w - pw) / 2, 8 * s
	rr(d, (x0, y0 + 4, x0 + pw, y0 + ph + 4), BARK, radius=int(14 * s))
	rr(d, (x0, y0, x0 + pw, y0 + ph), PAPER, radius=int(14 * s), outline=AMBER_EDGE, width=3)
	d.text((x0 + 18 * s, y0 + 8 * s), "Blueprints", font=font(BOLD, int(22 * s)), fill=INK)
	d.text((x0 + 18 * s, y0 + 36 * s), "Your hammer's list: plans you know", font=font(REG, int(13 * s)), fill=BARK)
	cx = x0 + pw - 52 * s
	btn(d, (cx, y0 + 8 * s, cx + 40 * s, y0 + 8 * s + 40 * s), "X", "skip", font(BOLD, int(16 * s)))
	d.line((x0, y0 + 62 * s, x0 + pw, y0 + 62 * s), fill=PAPER_DARK, width=2)
	y = y0 + 70 * s
	rows = ROWS if w >= 1000 else ROWS[3:]
	# the Land row and filter row, then the plans
	for text in ["Showing: All", "LAND  ·  raise your plot size"] if w >= 1000 else ["Showing: All"]:
		rr(d, (x0 + 12 * s, y, x0 + pw - 12 * s, y + 40 * s), PAPER_DARK, radius=int(10 * s))
		d.text((x0 + 24 * s, y + 10 * s), text, font=font(BOLD, int(15 * s)), fill=INK)
		y += 46 * s
	for name, own, _o, detail, button, style, color in rows:
		rh = 66 * s if w >= 1000 else 60 * s
		if y + rh > y0 + ph - 6 * s:
			break
		rr(d, (x0 + 12 * s, y, x0 + pw - 12 * s, y + rh), PAPER_DARK, radius=int(12 * s))
		sw = 40 * s
		sx, sy = x0 + 24 * s, y + (rh - sw) / 2
		d.ellipse((sx, sy, sx + sw, sy + sw), fill=color, outline=INK, width=3)
		nf = font(BOLD, int(17 * s))
		d.text((x0 + 76 * s, y + 8 * s), name, font=nf, fill=INK)
		if own and "?" not in own:
			d.text((x0 + 84 * s + d.textlength(name, font=nf), y + 11 * s), own, font=font(BOLD, int(12 * s)), fill=BARK)
		d.text((x0 + 76 * s, y + 8 * s + 22 * s), detail[: int(64 if w >= 1000 else 40)], font=font(REG, int(11 * s)), fill=BARK)
		bwid, bhei = 100 * s, 44 * s
		btn(d, (x0 + pw - 12 * s - bwid - 8 * s, y + (rh - bhei) / 2 - 2, x0 + pw - 20 * s, y + (rh - bhei) / 2 - 2 + bhei), button, style, font(BOLD, int(13 * s)))
		y += rh + 6 * s
	return im


# --- the SAVES panel ----------------------------------------------------------
def save_panel(w, h, xbox=False) -> Image.Image:
	s = scale_for(w, h)
	im = v1u.scene_backdrop(w, h)
	d = ImageDraw.Draw(im)
	pw, ph = 360 * s, 360 * s
	ph = min(ph, h - 8 * s)
	x0, y0 = (w - pw) / 2, (h - ph) / 2
	rr(d, (x0, y0, x0 + pw, y0 + ph), PAPER, radius=int(14 * s), outline=BARK, width=3)
	d.text((x0 + 16 * s, y0 + 10 * s), "Saves", font=font(BOLD, int(26 * s)), fill=INK)
	btn(d, (x0 + pw - 52 * s, y0 + 8 * s, x0 + pw - 8 * s, y0 + 52 * s), "X", "skip", font(BOLD, int(18 * s)))
	d.multiline_text((x0 + 12 * s, y0 + 50 * s), "Loading a save puts this one away. Cash, wood,\nplot and visitor rules stay with each save.", font=font(REG, max(9, int(13 * s))), fill=INK, spacing=2)
	by = y0 + 90 * s
	bh = 48 * s
	btn(d, (x0 + 12 * s, by, x0 + 176 * s, by + bh), "UNLOAD BASE", "bark", font(BOLD, int(14 * s)), selected=False)
	btn(d, (x0 + 184 * s, by, x0 + 348 * s, by + bh), "Save now", "buy", font(BOLD, int(14 * s)), selected=xbox)
	f = font(REG, max(9, int(14 * s)))
	t = "Saved at 11:42"
	d.text((x0 + 348 * s - d.textlength(t, font=f), y0 + 142 * s), t, font=f, fill=INK)
	ry = y0 + 164 * s
	for i, (name, cash, active) in enumerate([("Save 1", "$12,480", True), ("Save 2", "Empty", False)]):
		rh = 92 * s
		if ry + rh > y0 + ph - 8 * s:
			break
		rr(d, (x0 + 12 * s, ry, x0 + pw - 12 * s, ry + rh), PAPER_DARK if active else PAPER, radius=int(10 * s), outline=GREEN_EDGE if active else BARK, width=2)
		rr(d, (x0 + 20 * s, ry + 6 * s, x0 + pw - 20 * s, ry + 38 * s), (0xF5, 0xEB, 0xD7), radius=int(8 * s))
		d.text((x0 + 30 * s, ry + 12 * s), name, font=font(BOLD, int(15 * s)), fill=INK)
		d.text((x0 + 20 * s, ry + 44 * s), f"{cash}  ·  Steel Axe  ·  38 pieces  ·  Saved 3 min ago" if cash != "Empty" else "Empty  ·  Not saved", font=font(REG, max(9, int(12 * s))), fill=INK)
		d.text((x0 + 20 * s, ry + 66 * s), "Playing" if active else "LOAD", font=font(BOLD, int(14 * s)), fill=GREEN_EDGE if active else INK)
		ry += rh + 8 * s
	if xbox:
		d.text((24 * s, h - 40 * s), "A select   B close", font=font(REG, int(16 * s)), fill=(255, 255, 255))
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	shots = {
		"placer-667x375.png": placer_phone(),
		"placer-1920x1080.png": placer_pc(),
		"placer-xbox-1920x1080.png": placer_xbox(),
		"blueprint-book-667x375.png": blueprint_book(667, 375),
		"blueprint-book-1920x1080.png": blueprint_book(1920, 1080),
		"save-panel-667x375.png": save_panel(667, 375),
		"save-panel-1920x1080.png": save_panel(1920, 1080),
		"save-panel-xbox-1920x1080.png": save_panel(1920, 1080, xbox=True),
	}
	for name, im in shots.items():
		path = os.path.join(OUT, name)
		im.save(path, "PNG")
		print(path)


if __name__ == "__main__":
	main()
