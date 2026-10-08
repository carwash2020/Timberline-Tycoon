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
DANGER = (0xD9, 0x53, 0x4F)
DANGER_EDGE = (0xA4, 0x3A, 0x36)
MUTED_FILL = (0x5A, 0x4A, 0x3E)
SELECTION = (0xFF, 0xF4, 0xC2)
RADIUS = 8
STROKE = 2
RING = 4

TIPS = [
	"Planks sell for more than logs.",
	"Rook at the main sawmill hands out 3 daily jobs.",
	"Wear the Insulated Coat before heading into the snow.",
]

NEWS = [
	("tree", "Trees you can chop now stand around the spawn."),
	("base", "Unload your base from SAVES, then pick a pad."),
	("axe", "Drop the axe with B, Q, or a long press."),
	("box", "Shop boxes show the real item in a window."),
	("gear", "Choose Lower or Higher quality when you join."),
	("talk", "Talk opens a box, and folks turn to face you."),
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
	for tip in TIPS:
		draw.text((w / 2, y), tip, font=body, fill=MUTED, anchor="mm")
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
		("Danger", "#D9534F", DANGER),
		("DangerEdge", "#A43A36", DANGER_EDGE),
		("MutedFill", "#5A4A3E", MUTED_FILL),
		("Selection", "#FFF4C2", SELECTION),
	]
	cols = 7 if w > 700 else 4
	cw = (w - 24) / cols
	ch = 52 if w > 700 else 28
	gap = 6 if w > 700 else 3
	for i, (name, hexname, col) in enumerate(swatches):
		c, r = i % cols, i // cols
		x, y = 12 + c * cw, (32 if w > 700 else 24) + r * (ch + gap)
		ink = CONFIRM_INK if lum(col) > 0.4 else CREAM
		rr(draw, (x, y, x + cw - 8, y + ch), col, outline=AMBER_EDGE, width=1)
		draw.text((x + 4, y + 2), name, font=label, fill=ink)
		draw.text((x + 4, y + (22 if w > 700 else 13)), hexname, font=body, fill=ink)
	# fonts
	fy = (32 if w > 700 else 24) + ((len(swatches) + cols - 1) // cols) * (ch + gap) + 6
	draw.text((12, fy), "Title 22  GothamBold", font=font(BOLD, 22 if w > 700 else 16), fill=CREAM)
	draw.text((12, fy + (28 if w > 700 else 20)), "Button 16  GothamBold", font=font(BOLD, 16 if w > 700 else 13), fill=AMBER)
	draw.text((w * 0.48, fy + 4), "Body 14  Gotham — cream on walnut.", font=font(REG, 14 if w > 700 else 12), fill=CREAM)
	# radius and stroke
	sy = fy + (56 if w > 700 else 36)
	rr(draw, (12, sy, 92, sy + 36), PANEL, outline=AMBER_EDGE, width=STROKE)
	draw.text((100, sy + 8), "radius 8   stroke 2   chip radius 6", font=body, fill=MUTED)
	rr(draw, (w * 0.55, sy, w * 0.55 + 70, sy + 28), AMBER, radius=6, outline=AMBER_EDGE, width=STROKE)
	draw.text((w * 0.55 + 78, sy + 6), "chip", font=label, fill=CONFIRM_INK)
	# contrast pairs
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
	py = sy + (44 if w > 700 else 32)
	pw = (w - 24) / (4 if w > 700 else 2)
	ph = 36 if w > 700 else 26
	for i, (name, fg, bg) in enumerate(pairs):
		c, r = i % (4 if w > 700 else 2), i // (4 if w > 700 else 2)
		x, y = 12 + c * pw, py + r * (ph + 6)
		ratio = contrast(fg, bg)
		rr(draw, (x, y, x + pw - 8, y + ph), bg, outline=AMBER_EDGE, width=1)
		draw.text((x + 6, y + 3), f"{name}", font=label, fill=fg)
		draw.text((x + 6, y + 16), f"{ratio:.2f}:1", font=body, fill=fg)
	if w == 667:
		phone_zones(im)
	return im


def icon(draw, kind, box):
	x0, y0, x1, y1 = box
	cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	if kind == "tree":
		draw.polygon([(cx, y0 + 2), (x1 - 2, cy), (cx, y1 - 6), (x0 + 2, cy)], fill=CONFIRM)
		draw.rectangle((cx - 2, cy, cx + 2, y1 - 1), fill=AMBER_EDGE)
	elif kind == "base":
		draw.polygon([(cx, y0 + 2), (x1 - 2, cy - 2), (x0 + 2, cy - 2)], fill=AMBER)
		draw.rectangle((x0 + 4, cy - 1, x1 - 4, y1 - 2), fill=CREAM)
	elif kind == "axe":
		draw.line((x0 + 6, y1 - 4, x1 - 4, y0 + 4), fill=MUTED, width=3)
		draw.polygon([(x1 - 8, y0 + 2), (x1 - 1, y0 + 8), (x1 - 10, y0 + 14)], fill=AMBER)
	elif kind == "box":
		rr(draw, (x0 + 3, y0 + 6, x1 - 3, y1 - 2), AMBER_EDGE, radius=3)
		draw.rectangle((x0 + 6, y0 + 9, x1 - 6, cy + 2), fill=PANEL_ALT)
	elif kind == "gear":
		draw.ellipse((x0 + 4, y0 + 4, x1 - 4, y1 - 4), outline=AMBER, width=3)
		draw.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=PANEL)
	else:
		draw.rounded_rectangle((x0 + 2, y0 + 4, x1 - 2, y1 - 2), radius=4, fill=PANEL_ALT, outline=CREAM, width=2)
		draw.ellipse((x0 + 6, cy - 2, x0 + 10, cy + 2), fill=AMBER)


def news(w, h) -> Image.Image:
	im = Image.new("RGB", (w, h), (0x14, 0x10, 0x0C))
	draw = ImageDraw.Draw(im)
	pw = min(w - 24, 640 if w > 700 else 620)
	ph = min(h - 24, 520 if w > 700 else 340)
	x0 = (w - pw) / 2
	y0 = (h - ph) / 2
	# scrim already the backdrop
	rr(draw, (x0, y0, x0 + pw, y0 + ph), PANEL, outline=AMBER_EDGE, width=STROKE)
	title = font(BOLD, 20 if w > 700 else 14)
	body = font(REG, 15 if w > 700 else 12)
	btn = font(BOLD, 15 if w > 700 else 13)
	draw.text((x0 + 16, y0 + 12), "WHAT'S NEW IN V1", font=title, fill=CREAM)
	row_h = 36 if w > 700 else 28
	y = y0 + 48
	for kind, line in NEWS:
		if y + row_h > y0 + ph - 56:
			break
		icon(draw, kind, (x0 + 16, y, x0 + 16 + row_h - 6, y + row_h - 6))
		draw.text((x0 + 16 + row_h + 4, y + 4), line, font=body, fill=CREAM)
		y += row_h
	bw, bh = 140, 40
	bx = x0 + pw - 16 - bw
	by = y0 + ph - 16 - bh
	button(draw, (bx, by, bx + bw, by + bh), "CLOSE", AMBER, AMBER_EDGE, CONFIRM_INK, btn, selected=True)
	if w == 667:
		phone_zones(im)
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	scenes = {
		"loading": loading,
		"hud-buttons": hud,
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
