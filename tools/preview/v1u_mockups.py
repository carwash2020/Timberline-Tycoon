#!/usr/bin/env python3
"""Lane U mockups: phone 667x375 and PC 1920x1080.

Inter stands in for Roblox Gotham / GothamBold. Hex, radius and the
selection ring match UITheme. Phone frames also draw the thumbstick
zone (left 40% of the bottom half) and the jump button.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "previews", "v1-u")
BOLD = "/usr/share/fonts/truetype/macos/Inter-Bold.ttf"
REG = "/usr/share/fonts/truetype/macos/Inter-Regular.ttf"

PANEL = (0x2A, 0x1F, 0x17)
PANEL_ALT = (0x1E, 0x1B, 0x18)
CREAM = (0xF3, 0xE7, 0xC9)
MUTED = (0xCD, 0xBF, 0xA3)
AMBER = (0xF2, 0xC1, 0x4E)
AMBER_EDGE = (0xC9, 0xA2, 0x4A)
CONFIRM = (0x4C, 0xC3, 0x6A)
CONFIRM_EDGE = (0x2F, 0x8A, 0x48)
CONFIRM_INK = (0x14, 0x24, 0x0F)
DANGER = (0xB2, 0x3B, 0x30)  # cream on this is >= 4.5:1
DANGER_EDGE = (0x7A, 0x2C, 0x26)
DANGER_TEXT = (0xD9, 0x53, 0x4F)
MUTED_FILL = (0x5A, 0x4A, 0x3E)
SELECTION = (0xFF, 0xF4, 0xC2)
RADIUS = 8
STROKE = 2
RING = 4

TIP = "Planks sell for more than logs."

NEWS = [
	("map", "A new island map, with the Bayou and Red Mesa."),
	("mine", "Mine the cave for ore."),
	("blueprint", "Build from blueprints."),
	("daily", "Foreman Rook's daily jobs, with streaks."),
	("temper", "Temper your axe."),
	("spark", "Sparkworks logic pieces."),
	("gondola", "A sky island, reached by the gondola pass."),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
	return ImageFont.truetype(path, size)


def lum(rgb: tuple[int, int, int]) -> float:
	def lin(c: int) -> float:
		s = c / 255
		return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

	r, g, b = rgb
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
	hi, lo = lum(a), lum(b)
	if hi < lo:
		hi, lo = lo, hi
	return (hi + 0.05) / (lo + 0.05)


def rr(draw: ImageDraw.ImageDraw, box, fill, radius=RADIUS, outline=None, width=STROKE):
	draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def center_text(draw, box, text, fnt, fill):
	x0, y0, x1, y1 = box
	bbox = draw.textbbox((0, 0), text, font=fnt)
	tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
	draw.text((x0 + (x1 - x0 - tw) / 2, y0 + (y1 - y0 - th) / 2 - 1), text, font=fnt, fill=fill)


def button(draw, box, label, fill, edge, ink, fnt, selected=False):
	if selected:
		x0, y0, x1, y1 = box
		rr(
			draw,
			(x0 - RING - 2, y0 - RING - 2, x1 + RING + 2, y1 + RING + 2),
			None,
			radius=RADIUS + RING,
			outline=SELECTION,
			width=RING,
		)
	rr(draw, box, fill, outline=edge, width=STROKE)
	center_text(draw, box, label, fnt, ink)


def phone_zones(im: Image.Image):
	# Left 40% of the bottom half: the thumbstick. Jump: 70px, 95 from the
	# right edge and 90 up from the bottom (667x375: 572,285 to 642,355).
	w, h = im.size
	overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	od = ImageDraw.Draw(overlay)
	top = h // 2
	od.rectangle((0, top, int(w * 0.4), h), fill=(255, 255, 255, 28), outline=(255, 244, 194, 90))
	# 70px jump box: left edge 95px from the right, top 90px up from the bottom.
	jx0, jy0 = w - 95, h - 90
	od.rounded_rectangle((jx0, jy0, jx0 + 70, jy0 + 70), radius=12, fill=(255, 255, 255, 36), outline=(255, 244, 194, 140))
	im.paste(Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB"))
	draw = ImageDraw.Draw(im)
	small = font(REG, 11)
	draw.text((8, top + 6), "thumbstick", font=small, fill=MUTED)
	draw.text((jx0 + 18, jy0 + 28), "jump", font=small, fill=MUTED)


def loading(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), PANEL_ALT)
	px = im.load()
	for y in range(h):
		t = y / max(h - 1, 1)
		col = tuple(int(PANEL[i] * (1 - t) + PANEL_ALT[i] * t) for i in range(3))
		for x in range(w):
			px[x, y] = col
	draw = ImageDraw.Draw(im)
	title_px = 40 if w > 700 else 28
	body_px = 18 if w > 700 else 15
	title = font(BOLD, title_px)
	kicker = font(BOLD, 14)
	body = font(REG, body_px)
	draw.text((w / 2, h * 0.22), "Timberline Tycoon", font=title, fill=CREAM, anchor="mm")
	draw.rounded_rectangle((w / 2 - 48, h * 0.22 + title_px * 0.7, w / 2 + 48, h * 0.22 + title_px * 0.7 + 4), radius=2, fill=AMBER)
	y = h * 0.22 + title_px * 0.7 + 28
	draw.text((w / 2, y), "TIP", font=kicker, fill=AMBER, anchor="mm")
	y += 28
	draw.text((w / 2, y), TIP, font=body, fill=MUTED, anchor="mm")
	y += body_px + 10
	# pulsing dots
	cx = w / 2 - 17
	for i in range(3):
		draw.ellipse((cx + i * 17, y + 8, cx + i * 17 + 10, y + 18), fill=AMBER)
	note = font(REG, 12)
	draw.text((16, h - 22), "GothamBold title  ·  Gotham tips  ·  stand-in: Inter", font=note, fill=MUTED)
	if w == 667:
		phone_zones(im)
	return im


def hud(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), PANEL_ALT)
	draw = ImageDraw.Draw(im)
	title = font(BOLD, 22 if w > 700 else 16)
	label = font(BOLD, 16 if w > 700 else 13)
	note = font(REG, 13 if w > 700 else 11)
	draw.text((24, 18), "HUD buttons", font=title, fill=CREAM)
	draw.text((24, 48), "primary   confirm   danger   muted   locked     ring #FFF4C2  4px", font=note, fill=MUTED)
	styles = [
		("PRIMARY", AMBER, AMBER_EDGE, CONFIRM_INK, True),
		("CONFIRM", CONFIRM, CONFIRM_EDGE, CONFIRM_INK, False),
		("DANGER", DANGER, DANGER_EDGE, CREAM, False),
		("MUTED", MUTED_FILL, PANEL_ALT, MUTED, False),
		("LOCKED", MUTED_FILL, PANEL_ALT, MUTED, False),
	]
	bw, bh = (150, 44) if w > 700 else (112, 44)
	gap = 12
	total = len(styles) * bw + (len(styles) - 1) * gap
	x = max(24, (w - total) / 2)
	y = h * 0.38
	for name, fill, edge, ink, sel in styles:
		button(draw, (x, y, x + bw, y + bh), name, fill, edge, ink, label, selected=sel)
		x += bw + gap
	draw.text((24, h - 36), "GothamBold labels. Selection sits outside the fill.", font=note, fill=MUTED)
	if w == 667:
		phone_zones(im)
	return im


def owner(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), (0x14, 0x10, 0x0C))
	draw = ImageDraw.Draw(im)
	margin = 12
	pw = min(w - margin * 2, 920 if w > 700 else 640)
	ph = min(h - margin * 2, 620 if w > 700 else 340)
	x0 = (w - pw) / 2
	y0 = (h - ph) / 2
	rr(draw, (x0, y0, x0 + pw, y0 + ph), PANEL, outline=AMBER_EDGE, width=STROKE)
	title = font(BOLD, 20 if w > 700 else 15)
	small = font(BOLD, 13 if w > 700 else 11)
	body = font(REG, 13 if w > 700 else 11)
	draw.text((x0 + 16, y0 + 12), "OWNER", font=title, fill=CREAM)
	# search
	sx1 = x0 + pw - 16 - 44 - 8
	rr(draw, (x0 + 120, y0 + 12, sx1, y0 + 12 + 32), PANEL_ALT, outline=AMBER_EDGE, width=STROKE)
	draw.text((x0 + 132, y0 + 18), "Find a tool...", font=body, fill=MUTED)
	button(draw, (sx1 + 8, y0 + 10, x0 + pw - 12, y0 + 10 + 36), "X", MUTED_FILL, PANEL_ALT, MUTED, small)
	tabs = ["PLAYERS", "GIFTS", "PAID", "WORLD", "ROLES", "LOG"]
	tw = (pw - 32 - 8 * (len(tabs) - 1)) / len(tabs)
	tx = x0 + 16
	ty = y0 + 56
	for i, name in enumerate(tabs):
		button(
			draw,
			(tx, ty, tx + tw, ty + 32),
			name,
			AMBER if i == 0 else PANEL,
			AMBER_EDGE,
			CONFIRM_INK if i == 0 else CREAM,
			small,
			selected=(i == 0),
		)
		tx += tw + 8
	draw.text((x0 + 16, ty + 48), "Players on this server", font=title, fill=CREAM)
	row_y = ty + 84
	for name in ("Connor", "Millie", "Old Hank"):
		rr(draw, (x0 + 16, row_y, x0 + pw - 16, row_y + 28), PANEL_ALT, radius=6)
		draw.text((x0 + 28, row_y + 6), name, font=body, fill=CREAM)
		row_y += 34
		if row_y > y0 + ph - 70:
			break
	rr(draw, (x0 + 16, y0 + ph - 48, x0 + pw - 16, y0 + ph - 12), PANEL_ALT, radius=6)
	draw.text((x0 + 28, y0 + ph - 40), "Player: nobody", font=body, fill=MUTED)
	if w == 667:
		phone_zones(im)
	return im


def theme_sheet(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), PANEL_ALT)
	draw = ImageDraw.Draw(im)
	title = font(BOLD, 18 if w > 700 else 13)
	label = font(BOLD, 12 if w > 700 else 10)
	body = font(REG, 12 if w > 700 else 10)
	draw.text((12, 6), "UITheme tokens", font=title, fill=CREAM)
	swatches = [
		("Panel", "#2A1F17", PANEL),
		("PanelAlt", "#1E1B18", PANEL_ALT),
		("Cream", "#F3E7C9", CREAM),
		("Muted", "#CDBFA3", MUTED),
		("Amber", "#F2C14E", AMBER),
		("AmberEdge", "#C9A24A", AMBER_EDGE),
		("Confirm", "#4CC36A", CONFIRM),
		("ConfirmEdge", "#2F8A48", CONFIRM_EDGE),
		("ConfirmInk", "#14240F", CONFIRM_INK),
		("Danger", "#B23B30", DANGER),
		("DangerEdge", "#7A2C26", DANGER_EDGE),
		("DangerText", "#D9534F", DANGER_TEXT),
		("MutedFill", "#5A4A3E", MUTED_FILL),
		("Selection", "#FFF4C2", SELECTION),
	]
	wide = w > 700
	cols = 7 if wide else 5
	cw = (w - 24) / cols
	ch = 52 if wide else 22
	gap = 6 if wide else 2
	top = 28 if wide else 20
	for i, (name, hexname, col) in enumerate(swatches):
		c, r = i % cols, i // cols
		x, y = 12 + c * cw, top + r * (ch + gap)
		ink = CONFIRM_INK if lum(col) > 0.4 else CREAM
		rr(draw, (x, y, x + cw - 6, y + ch), col, outline=AMBER_EDGE, width=1)
		draw.text((x + 3, y + 1), name, font=label, fill=ink)
		draw.text((x + 3, y + (22 if wide else 11)), hexname, font=body, fill=ink)
	rows = (len(swatches) + cols - 1) // cols
	fy = top + rows * (ch + gap) + 4
	draw.text((12, fy), "Title  GothamBold", font=font(BOLD, 18 if wide else 13), fill=CREAM)
	draw.text((w * 0.34, fy), "Button  GothamBold", font=font(BOLD, 16 if wide else 12), fill=AMBER)
	draw.text((w * 0.62, fy + 1), "Body  Gotham", font=font(REG, 14 if wide else 12), fill=CREAM)
	pairs = [
		("Cream / Panel", CREAM, PANEL),
		("Cream / PanelAlt", CREAM, PANEL_ALT),
		("Muted / Panel", MUTED, PANEL),
		("Muted / MutedFill", MUTED, MUTED_FILL),
		("Cream / Danger", CREAM, DANGER),
		("Ink / Confirm", CONFIRM_INK, CONFIRM),
		("Ink / Amber", CONFIRM_INK, AMBER),
		("Selection / Panel", SELECTION, PANEL),
	]
	# On a phone the ratio chips sit right of the thumbstick and above the
	# jump box, so Cream / Danger stays readable.
	if wide:
		py = fy + 28
		pw = (w - 24) / 4
		ph = 36
		for i, (name, fg, bg) in enumerate(pairs):
			c, r = i % 4, i // 4
			x, y = 12 + c * pw, py + r * (ph + 6)
			ratio = contrast(fg, bg)
			rr(draw, (x, y, x + pw - 8, y + ph), bg, outline=AMBER_EDGE, width=1)
			draw.text((x + 6, y + 3), name, font=label, fill=fg)
			draw.text((x + 6, y + 16), f"{ratio:.2f}:1", font=body, fill=fg)
	else:
		stick_right = int(w * 0.4) + 8
		py = fy + 20
		pw = (w - stick_right - 12) / 2
		ph = 28
		for i, (name, fg, bg) in enumerate(pairs):
			c, r = i % 2, i // 2
			x, y = stick_right + c * pw, py + r * (ph + 4)
			ratio = contrast(fg, bg)
			rr(draw, (x, y, x + pw - 6, y + ph), bg, outline=AMBER_EDGE, width=1)
			draw.text((x + 4, y + 1), name, font=label, fill=fg)
			draw.text((x + 4, y + 13), f"{ratio:.2f}:1", font=body, fill=fg)
	if w == 667:
		phone_zones(im)
	return im


def zones(w, h):
	"""Thumbstick (left 40% of the bottom half) and the 70px jump box."""
	stick = (0, h // 2, int(w * 0.4), h)
	jx0, jy0 = w - 95, h - 90
	jump = (jx0, jy0, jx0 + 70, jy0 + 70)
	return stick, jump


def overlaps(a, b) -> bool:
	return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def icon(draw, kind, box):
	x0, y0, x1, y1 = box
	cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	rr(draw, box, PANEL_ALT, radius=6, outline=AMBER_EDGE, width=1)
	if kind == "map":
		draw.polygon([(cx, y0 + 4), (x1 - 4, cy), (cx, y1 - 4), (x0 + 4, cy)], fill=CONFIRM)
		draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=AMBER)
	elif kind == "mine":
		draw.line((x0 + 6, y1 - 5, x1 - 5, y0 + 6), fill=MUTED, width=3)
		draw.polygon([(x1 - 8, y0 + 3), (x1 - 2, y0 + 7), (x1 - 9, y0 + 12)], fill=AMBER)
	elif kind == "blueprint":
		rr(draw, (x0 + 5, y0 + 3, x1 - 5, y1 - 3), CREAM, radius=2)
		draw.line((x0 + 8, cy - 2, x1 - 8, cy - 2), fill=AMBER, width=2)
		draw.line((x0 + 8, cy + 3, x1 - 10, cy + 3), fill=AMBER_EDGE, width=2)
	elif kind == "daily":
		draw.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), fill=AMBER)
		draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=PANEL)
	elif kind == "temper":
		draw.line((x0 + 5, y1 - 4, x1 - 4, y0 + 4), fill=CREAM, width=3)
		draw.polygon([(x1 - 9, y0 + 2), (x1 - 2, y0 + 7), (x1 - 10, y0 + 12)], fill=AMBER)
	elif kind == "spark":
		draw.polygon([(cx, y0 + 3), (cx + 5, cy), (cx, y1 - 3), (cx - 5, cy)], fill=AMBER)
		draw.ellipse((x0 + 4, y0 + 4, x0 + 8, y0 + 8), fill=CREAM)
	elif kind == "gondola":
		draw.line((x0 + 3, y0 + 6, x1 - 3, y0 + 8), fill=CREAM, width=2)
		rr(draw, (cx - 6, cy, cx + 6, y1 - 3), AMBER, radius=2)
	else:
		draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill=CREAM)


def news(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), (0x14, 0x10, 0x0C))
	draw = ImageDraw.Draw(im)
	# Short screens: the card (and Close) stay right of the thumbstick and
	# above the jump box. Wide screens centre the card.
	if min(w, h) < 600:
		margin = 8
		x0 = w * 0.4 + margin
		y0 = margin
		x1 = w - margin
		y1 = h - 90 - margin
	else:
		pw = min(520, w - 80)
		ph = min(460, h - 80)
		x0 = (w - pw) / 2
		y0 = (h - ph) / 2
		x1, y1 = x0 + pw, y0 + ph
	rr(draw, (x0, y0, x1, y1), PANEL, outline=AMBER_EDGE, width=STROKE)
	title = font(BOLD, 20 if w > 700 else 15)
	body = font(REG, 15 if w > 700 else 13)
	btn = font(BOLD, 15 if w > 700 else 13)
	draw.text((x0 + 14, y0 + 8), "WHAT'S NEW IN V1", font=title, fill=CREAM)
	bw, bh = 140, 40
	bx = x0 + ((x1 - x0) - bw) / 2
	by = y1 - 10 - bh
	row_h = 32 if w > 700 else 24
	y = y0 + (40 if w > 700 else 30)
	for kind, line in NEWS:
		if y + row_h > by - 4:
			raise SystemExit(f"news line does not fit above Close on {w}x{h}")
		icon(draw, kind, (x0 + 14, y, x0 + 14 + row_h - 4, y + row_h - 4))
		draw.text((x0 + 14 + row_h + 6, y + 3), line, font=body, fill=CREAM)
		y += row_h
	close = (bx, by, bx + bw, by + bh)
	if min(w, h) < 600:
		stick, jump = zones(w, h)
		if overlaps(close, stick) or overlaps(close, jump):
			raise SystemExit(f"Close overlaps a touch zone: {close}")
	button(draw, close, "CLOSE", AMBER, AMBER_EDGE, CONFIRM_INK, btn, selected=True)
	if w == 667:
		phone_zones(im)
	return im


def backdrop(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), (0x8E, 0xC6, 0xE0))
	draw = ImageDraw.Draw(im)
	horizon = int(h * 0.56)
	draw.rectangle((0, int(h * 0.34), w, horizon), fill=(0xB7, 0xD7, 0xC4))
	draw.rectangle((0, horizon, w, h), fill=(0x3E, 0x6B, 0x34))
	draw.rectangle((0, horizon, w, horizon + max(8, h // 40)), fill=(0x6E, 0x94, 0x48))
	trunk = (0x5C, 0x3B, 0x24)
	leaf = (0x2F, 0x6A, 0x32)
	for x, scale in ((70, 1.0), (150, 0.8), (230, 1.15), (w * 0.42, 0.9), (w * 0.55, 1.05)):
		th = int(70 * scale * (h / 375 if h < 500 else 1.4))
		tw = int(16 * scale)
		base = horizon + 8
		draw.rectangle((x, base - th * 0.35, x + tw, base), fill=trunk)
		draw.polygon(
			[
				(x + tw / 2, base - th),
				(x - tw * 1.6, base - th * 0.28),
				(x + tw + tw * 1.6, base - th * 0.28),
			],
			fill=leaf,
		)
	return im


def hud_context(w, h) -> Image.Image:
	"""The live HUD: cash, the real side buttons, one selection ring.

	Side-button geometry follows HudLayout.SideColumn (margin 12, 24px
	above the jump box, or 44px under centre) and the SideButton sizes.
	"""
	phone = min(w, h) < 600
	raw = (min(w, h) / 480) if phone else max(1.0, h / 864)
	scale = max(0.7, min(0.85, raw)) if phone else raw
	im = backdrop(w, h)
	draw = ImageDraw.Draw(im)
	# A stand-in for Roblox's top bar. Cash sits just under it.
	draw.rectangle((0, 0, w, 32), fill=(0x1A, 0x1A, 0x1A))
	small = font(BOLD, 11)
	draw.text((12, 8), "Timberline Tycoon", font=small, fill=(0xE8, 0xE8, 0xE8))

	label = font(BOLD, 13 if phone else 16)
	body = font(REG, 13 if phone else 15)
	cash_font = font(BOLD, 20 if phone else 26)

	# Top row, right aligned: settings gear, then the cash plaque.
	plaque_w = 128 if phone else 188
	plaque_h = 36 if phone else 44
	gear = 38
	right = w - 12
	top = 40
	plaque = (right - plaque_w, top, right, top + plaque_h)
	rr(draw, plaque, PANEL, outline=AMBER, width=3)
	inset = 4
	rr(
		draw,
		(plaque[0] + inset, plaque[1] + inset, plaque[2] - inset, plaque[3] - inset),
		CREAM,
		radius=6,
	)
	center_text(draw, plaque, "$1,250", cash_font, PANEL_ALT)
	gx1 = plaque[0] - 8
	gear_box = (gx1 - gear, top + (plaque_h - gear) / 2, gx1, top + (plaque_h + gear) / 2)
	draw.ellipse(gear_box, fill=(0x3E, 0x2E, 0x22), outline=PANEL_ALT, width=2)
	cx = (gear_box[0] + gear_box[2]) / 2
	cy = (gear_box[1] + gear_box[3]) / 2
	draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), outline=CREAM, width=2)
	draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=CREAM)

	# Second line, right aligned: clock, then STORE. (Daily Goals is not started.)
	clock_w, clock_h = (92, 28) if phone else (110, 32)
	store_w, store_h = (90, 36) if phone else (90, 32)
	line_y = top + plaque_h + 8
	store = (right - store_w, line_y, right, line_y + store_h)
	clock = (store[0] - 8 - clock_w, line_y + (store_h - clock_h) / 2, store[0] - 8, line_y + (store_h + clock_h) / 2)
	button(draw, clock, "Day 2:05 PM", PANEL, AMBER_EDGE, CREAM, font(BOLD, 11 if phone else 13))
	button(draw, store, "STORE", CONFIRM, CONFIRM_EDGE, CONFIRM_INK, font(BOLD, 12 if phone else 13))

	# Field guide: a page icon on a phone, the words on a wide screen.
	if phone:
		guide = (12, 40, 52, 83)
		button(draw, guide, "", PANEL, AMBER_EDGE, CREAM, label)
		rr(draw, (guide[0] + 12, guide[1] + 10, guide[2] - 12, guide[3] - 12), CREAM, radius=2)
	else:
		guide = (16, 48, 160, 86)
		button(draw, guide, "FIELD GUIDE", PANEL, AMBER_EDGE, CREAM, label)

	# Side column. Phone shows HAMMER (no number keys); both show SAVES
	# and Send truck home. MENU is gamepad-only, OWNER is the owner only.
	bw, bh = (116, 44) if phone else (110, 40)
	pw, ph = bw * scale, bh * scale
	gap = 8 * scale
	screen_w, screen_h = w / scale, h / scale
	col_right = screen_w - 12
	col_bottom = screen_h / 2 + 44
	if phone:
		_, jump = zones(w, h)
		col_right = min(col_right, jump[2] / scale)
		col_bottom = jump[1] / scale - 24
	buttons = (
		[
			("SAVES", PANEL, AMBER_EDGE, CREAM, False),
			("HAMMER", CONFIRM, CONFIRM_EDGE, CONFIRM_INK, True),
			("Send truck home", AMBER, AMBER_EDGE, CONFIRM_INK, False),
		]
		if phone
		else [
			("SAVES", PANEL, AMBER_EDGE, CREAM, True),
			("Send truck home", AMBER, AMBER_EDGE, CONFIRM_INK, False),
		]
	)
	xr = col_right * scale
	yb = col_bottom * scale
	placed = []
	for name, fill, edge, ink, selected in reversed(buttons):
		box = (xr - pw, yb - ph, xr, yb)
		placed.append((box, name, fill, edge, ink, selected))
		yb -= ph + gap
	placed.reverse()
	if phone:
		stick, jump = zones(w, h)
		for box, name, *_rest in placed:
			if overlaps(box, stick) or overlaps(box, jump):
				raise SystemExit(f"{name} overlaps a touch zone: {box}")
	for box, name, fill, edge, ink, selected in placed:
		side_px = 15 if not phone else 12
		side_font = font(BOLD, side_px)
		while side_px > 8:
			bb = draw.textbbox((0, 0), name, font=side_font)
			if bb[2] - bb[0] <= (box[2] - box[0]) - 10:
				break
			side_px -= 1
			side_font = font(BOLD, side_px)
		button(draw, box, name, fill, edge, ink, side_font, selected=selected)

	# Hint and the tool hotbar, above the bottom edge.
	hint = "Tap a tree to swing your axe" if phone else "Click a tree to swing · E to interact"
	hot_w, hot_h = (300, 52) if phone else (420, 64)
	hot = ((w - hot_w) / 2, h - 12 - hot_h, (w + hot_w) / 2, h - 12)
	draw.text((w / 2, hot[1] - 18), hint, font=body, fill=CREAM, anchor="mm")
	rr(draw, hot, (0x22, 0x22, 0x22), radius=8)
	slot = (hot[0] + 8, hot[1] + 6, hot[0] + 8 + hot_h - 12, hot[3] - 6)
	rr(draw, slot, PANEL, radius=6, outline=AMBER, width=2)
	center_text(draw, slot, "Axe", font(BOLD, 11), CREAM)

	if w == 667:
		phone_zones(im)
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	scenes = {
		"loading": loading,
		"hud-buttons": hud,
		"hud": hud_context,
		"owner-menu": owner,
		"theme-sheet": theme_sheet,
		"news": news,
	}
	for name, fn in scenes.items():
		for w, h in ((667, 375), (1920, 1080)):
			path = os.path.join(OUT, f"{name}-{w}x{h}.png")
			fn(w, h).save(path, "PNG")
			print(path)


if __name__ == "__main__":
	main()
