#!/usr/bin/env python3
"""Lane U round 3 previews: the GAD skins, the phone HUD, the icons.

Hand-built from the same token values as UITheme.Skin / UITheme.Styles and
the three real icon PNGs in assets/ui/icons (the very images uploaded as the
HUD icons). Liberation Sans stands in for Gotham / Fredoka (not on this
machine). Phone frames are 667x375 with Roblox's thumbstick and jump button
drawn; PC frames are 1920x1080.

  python3 tools/preview/v1u_round3.py      writes previews/v1-u/r3-*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_mockups as m  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-u")
ICONS = os.path.join(ROOT, "assets", "ui", "icons")
BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
m.BOLD, m.REG = BOLD, REG

# UITheme.Skin (GAD, final)
PAPER = (0xF0, 0xE1, 0xC3)
PAPER_DARK = (0xE2, 0xCF, 0xAA)
CREAM_SKIN = (0xF5, 0xEB, 0xD7)
BARK = (0x58, 0x3A, 0x22)
INK = (0x3C, 0x28, 0x14)
MUTED_SKIN = (0xA0, 0x91, 0x78)
GREEN = (0x2F, 0x8A, 0x48)
GREEN_EDGE = (0x1E, 0x5C, 0x30)
PLAQUE_CORNER, PLAQUE_DROP = 12, 4
BTN_CORNER, BTN_DROP = 10, 3

AMBER, AMBER_EDGE = m.AMBER, m.AMBER_EDGE
CONFIRM, CONFIRM_EDGE, CONFIRM_INK = m.CONFIRM, m.CONFIRM_EDGE, m.CONFIRM_INK
DANGER, DANGER_EDGE, CREAM = m.DANGER, m.DANGER_EDGE, m.CREAM
MUTED_FILL, MUTED_EDGE, MUTED = m.MUTED_FILL, (0x3E, 0x34, 0x2C), m.MUTED
PANEL, PANEL_ALT, SELECTION = m.PANEL, m.PANEL_ALT, m.SELECTION

# name: (fill, drop-edge colour or None, ink, stroke or None)
STYLES = {
	"primary": (AMBER, AMBER_EDGE, CONFIRM_INK, None),
	"confirm": (CONFIRM, CONFIRM_EDGE, CONFIRM_INK, None),
	"danger": (DANGER, DANGER_EDGE, CREAM, None),
	"muted": (MUTED_FILL, MUTED_EDGE, MUTED, None),
	"locked": (MUTED_FILL, MUTED_EDGE, MUTED, None),
	"starter": (PANEL_ALT, None, CREAM, MUTED_SKIN),
	"forged": (PANEL_ALT, AMBER_EDGE, AMBER, None),
	"bark": (PANEL, AMBER_EDGE, CREAM, None),
	"iconGreen": (GREEN, GREEN_EDGE, CREAM_SKIN, None),
}


def font(path, size):
	return ImageFont.truetype(path, size)


def mul(c, k):
	return tuple(max(0, min(255, int(v * k))) for v in c)


def text_w(draw, text, fnt):
	return draw.textbbox((0, 0), text, font=fnt)[2]


def shine_face(im, box, fill, radius):
	"""A rounded face with the shine: white at 0, 0.9 grey from 12% down."""
	x0, y0, x1, y1 = [int(v) for v in box]
	w, h = x1 - x0, y1 - y0
	face = Image.new("RGB", (w, h), fill)
	fd = ImageDraw.Draw(face)
	for y in range(h):
		t = y / max(h - 1, 1)
		k = 1.0 if t <= 0 else (1 - 0.1 * min(t / 0.12, 1.0))
		fd.line((0, y, w, y), fill=mul(fill, k))
	mask = Image.new("L", (w, h), 0)
	ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
	im.paste(face, (x0, y0), mask)


def ring(draw, box, radius):
	x0, y0, x1, y1 = box
	draw.rounded_rectangle(
		(x0 - 6, y0 - 6, x1 + 6, y1 + 6 + BTN_DROP), radius=radius + 4, outline=SELECTION, width=4
	)


def button(im, box, label, style, fnt=None, pressed=False, selected=False, icon=None, hover=False):
	"""A UITheme.Button: face `box`, a 3 px drop edge in the style's edge colour.
	Pressed: the face moves down 3 px onto the edge, which is hidden."""
	draw = ImageDraw.Draw(im)
	fill, edge, ink, stroke = STYLES[style]
	x0, y0, x1, y1 = box
	if pressed:
		fill = mul(fill, 0.92)
	if selected:
		ring(draw, box, BTN_CORNER)
	if edge is not None and not pressed:
		draw.rounded_rectangle((x0, y0 + BTN_DROP, x1, y1 + BTN_DROP), radius=BTN_CORNER, fill=edge)
	dy = BTN_DROP if pressed else 0
	fbox = (x0, y0 + dy, x1, y1 + dy)
	shine_face(im, fbox, fill, BTN_CORNER)
	if stroke is not None:
		draw.rounded_rectangle(fbox, radius=BTN_CORNER, outline=stroke, width=2)
	if icon is not None:
		cx, cy = (x0 + x1) // 2, (y0 + y1) // 2 + dy
		g = Image.open(os.path.join(ICONS, icon)).convert("RGBA").resize((28, 28), Image.LANCZOS)
		im.paste(g, (cx - 14, cy - 14), g)
	elif label:
		m.center_text(draw, fbox, label, fnt or font(BOLD, 15), ink)


def plaque(im, box, inset_label=None):
	"""A GAD plaque: a Bark edge 4 px lower, a Paper face (corner 12, 2 px Bark
	stroke) with the Cream / Paper / PaperDark gradient."""
	draw = ImageDraw.Draw(im)
	x0, y0, x1, y1 = [int(v) for v in box]
	draw.rounded_rectangle((x0, y0 + PLAQUE_DROP, x1, y1), radius=PLAQUE_CORNER, fill=BARK)
	w, h = x1 - x0, (y1 - PLAQUE_DROP) - y0
	face = Image.new("RGB", (w, h), PAPER)
	fd = ImageDraw.Draw(face)
	for y in range(h):
		t = y / max(h - 1, 1)
		if t <= 0.18:
			a, b, u = CREAM_SKIN, PAPER, t / 0.18
		else:
			a, b, u = PAPER, PAPER_DARK, (t - 0.18) / 0.82
		fd.line((0, y, w, y), fill=tuple(int(a[i] * (1 - u) + b[i] * u) for i in range(3)))
	mask = Image.new("L", (w, h), 0)
	ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=PLAQUE_CORNER, fill=255)
	im.paste(face, (x0, y0), mask)
	draw.rounded_rectangle((x0, y0, x1, y0 + h), radius=PLAQUE_CORNER, outline=BARK, width=2)
	return (x0, y0, x1, y0 + h)


def lum(rgb):
	return m.lum(rgb)


def contrast(a, b):
	return m.contrast(a, b)


# --------------------------------------------------------------------------
# Scenes
# --------------------------------------------------------------------------

TIP = "Planks sell for more than logs."


def loading(w, h):
	im = m.scene_backdrop(w, h).convert("RGBA")
	veil = Image.new("RGBA", (w, h), INK + (int(255 * 0.55),))  # Ink at 45% transparency
	im = Image.alpha_composite(im, veil).convert("RGB")
	scale = max(1.0, min(1.8, min(h / 420, w / 700)))
	pw = min(280, 0.72 * w / scale) * scale
	ph = 132 * scale
	cx, cy = w * 0.5, h * 0.45
	box = (cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2)
	face = plaque(im, box)
	draw = ImageDraw.Draw(im)
	pad = 16 * scale
	title = font(BOLD, int(20 * scale))
	draw.text((face[0] + pad, face[1] + pad), "Timberline Tycoon", font=title, fill=INK)
	body = font(REG, int(14 * scale))
	words, line, y = TIP.split(), "", face[1] + pad + 34 * scale
	for word in words:
		trial = (line + " " + word).strip()
		if text_w(draw, trial, body) > pw - 2 * pad:
			draw.text((face[0] + pad, y), line, font=body, fill=BARK)
			y += 18 * scale
			line = word
		else:
			line = trial
	draw.text((face[0] + pad, y), line, font=body, fill=BARK)
	if w == 667:
		m.phone_zones(im)
	return im


def hud_column(im, right, bottom):
	"""MENU, HAMMER, Sell here: 44 x 44 faces, 8 px apart, a 3 px edge each."""
	items = [("menu.png", "primary"), ("hammer.png", "iconGreen"), ("sell-here.png", "iconGreen")]
	boxes = []
	y = bottom
	for icon, style in reversed(items):
		y1 = y - BTN_DROP  # the root's bottom holds the edge
		box = (right - 44, y1 - 44, right, y1)
		boxes.append((box, icon, style))
		y = y1 - 44 - 5  # 8 px between faces = 5 + the 3 px edge
	return list(reversed(boxes))


def cash_plaque(im, right, top, w=150):
	draw = ImageDraw.Draw(im)
	rr = (right - w, top, right, top + 44)
	face = plaque(im, rr)
	draw.text((face[0] + 14, face[1] + 9), "$12,480", font=font(BOLD, 22), fill=INK)


def phone_hud(w=667, h=375):
	im = m.scene_backdrop(w, h)
	cash_plaque(im, w - 12, 8)
	jump_top = h - 90
	bottom = jump_top - 24
	right = (w - 95) + 70  # no further right than the jump button
	for box, icon, style in hud_column(im, right, bottom):
		button(im, box, None, style, icon=icon, selected=(icon == "hammer.png"))
	m.phone_zones(im)
	d = ImageDraw.Draw(im)
	d.text((12, 8), "Phone 667x375: MENU, HAMMER, Sell here (real icon PNGs)", font=font(REG, 11), fill=(255, 255, 255))
	return im


def phone_menu(w=667, h=375):
	"""MENU open on a phone: SAVES and Send truck home are tiles in it."""
	im = phone_hud()
	veil = Image.new("RGBA", (w, h), PANEL_ALT + (128,))
	im = Image.alpha_composite(im.convert("RGBA"), veil).convert("RGB")
	draw = ImageDraw.Draw(im)
	tiles = [
		"SAVES", "STORE", "BADGES", "FIELD GUIDE",
		"SETTINGS", "LAND", "HAMMER", "SELL HERE",
		"SEND TRUCK HOME", "HUD BUTTONS",
	]
	cols, rows = 4, 3
	tw, th, gap = 118, 48, 8
	gw = cols * tw + (cols - 1) * gap
	gh = rows * (th + BTN_DROP) + (rows - 1) * gap
	pw, ph = gw + 28, gh + 28 + 26 + 22
	x0, y0 = (w - pw) / 2 + 20, (h - ph) / 2 - 6
	# The walnut panel (as before: Card with an amber edge).
	m.rr(draw, (x0, y0, x0 + pw, y0 + ph), PANEL, outline=AMBER_EDGE, width=2)
	draw.text((x0 + pw / 2 - 70, y0 + 8), "QUICK MENU", font=font(BOLD, 20), fill=CREAM)
	for i, label in enumerate(tiles):
		c, r = i % cols, i // cols
		bx = x0 + 14 + c * (tw + gap)
		by = y0 + 40 + r * (th + BTN_DROP + gap)
		style = "primary" if label == "HUD BUTTONS" else "bark"
		fnt = font(BOLD, 13)
		button(im, (bx, by, bx + tw, by + th), label, style, fnt=fnt, selected=(label == "SAVES"))
	draw.text(
		(x0 + pw / 2 - 100, y0 + ph - 24), "Tap one  -  tap outside to close", font=font(BOLD, 12), fill=MUTED
	)
	d2 = ImageDraw.Draw(im)
	d2.text((12, 8), "MENU open (phone): SAVES and SEND TRUCK HOME are inside it", font=font(REG, 11), fill=(255, 255, 255))
	return im


NEWS_ROWS = [
	("A new island map, with the Bayou and Red Mesa.", "Two regions past the old town."),
	("Mine the cave for ore.", "Clear rubble, then follow the vein."),
	("Build from blueprints.", "Place a plan, then raise the walls."),
	("Foreman Rook's daily jobs, with streaks.", "Three jobs a day. A streak pays more."),
	("Temper your axe.", "A hotter edge bites harder."),
	("Sparkworks logic pieces.", "Wire switches, gates and lamps."),
	("A sky island, reached by the gondola pass.", "Ride the line up from the pass."),
]


def news(w, h):
	im = m.scene_backdrop(w, h).convert("RGBA")
	im = Image.alpha_composite(im, Image.new("RGBA", (w, h), (14, 10, 8, 150))).convert("RGB")
	draw = ImageDraw.Draw(im)
	phone = w == 667
	hero = 20 if phone else 108
	row = 26 if phone else 52
	pad = 3 if phone else 10
	gap_rows = 1 if phone else 6
	close = 44
	gap_close = 8
	pw = (w - 12 - int(w * 0.4)) if phone else 560
	ph = pad + hero + len(NEWS_ROWS) * row + len(NEWS_ROWS) * gap_rows + gap_close + close + BTN_DROP + pad
	if phone:
		x0, y1 = w * 0.4 + 6, h - 90 - 8
		y0 = y1 - ph
	else:
		x0, y0 = (w - pw) / 2, (h - ph) / 2
		y1 = y0 + ph
	x1 = x0 + pw
	if y0 < 0:
		raise SystemExit(f"news card taller than the screen: {y0}")
	m.rr(draw, (x0, y0, x1, y1), PANEL, outline=AMBER_EDGE, width=2)
	hx0, hy0, hx1, hy1 = x0 + 8, y0 + pad, x1 - 8, y0 + pad + hero
	draw.rounded_rectangle((hx0, hy0, hx1, hy1), radius=6, fill=(0xE8, 0xA1, 0x5A))
	draw.text((hx0 + 8, hy0 + 2), "TIMBERLINE  -  WHAT'S NEW IN V1", font=font(BOLD, 13 if phone else 24), fill=CREAM)
	y = hy1
	body, detail = font(REG, 13 if phone else 18), font(REG, 11 if phone else 15)
	for line, sub in NEWS_ROWS:
		draw.rounded_rectangle((x0 + 8, y + 1, x0 + 8 + (24 if phone else 36), y + 1 + (24 if phone else 36)), 4, fill=PANEL_ALT, outline=AMBER_EDGE, width=2)
		tx = x0 + 8 + (24 if phone else 36) + 8
		draw.text((tx, y), m.fit_text(draw, line, body, x1 - 8 - tx), font=body, fill=CREAM)
		draw.text((tx, y + (13 if phone else 21)), m.fit_text(draw, sub, detail, x1 - 8 - tx), font=detail, fill=MUTED)
		y += row + gap_rows
	last_row_bottom = y - gap_rows
	cb = ((x0 + x1) / 2 - close / 2, last_row_bottom + gap_close)
	box = (cb[0], cb[1], cb[0] + close, cb[1] + close)
	if phone:
		stick, jump = m.zones(w, h)
		assert not m.overlaps(box, stick) and not m.overlaps(box, jump), "Close overlaps a touch zone"
		assert box[1] - last_row_bottom == 8, "Close is 8 under the last row"
		assert box[3] + BTN_DROP <= y1, "Close sits inside the card"
	button(im, box, "X", "primary", fnt=font(BOLD, 20), selected=True)
	if phone:
		m.phone_zones(im)
		ImageDraw.Draw(im).text((12, 8), "What's New at 667x375: Close 44 x 44, 8 under the last row", font=font(REG, 11), fill=(255, 255, 255))
	return im


def pc_hud(w=1920, h=1080):
	"""The PC HUD: the layout is unchanged; buttons and plaque wear the new skins."""
	orig = m.button

	def patched(draw, box, label, fill, edge, ink, fnt, selected=False):
		# Map the old call onto the new look: drop edge in `edge`, no stroke.
		style_im = draw._image
		fill_c = fill
		x0, y0, x1, y1 = [int(v) for v in box]
		if selected:
			ring(draw, (x0, y0, x1, y1), BTN_CORNER)
		if edge is not None and fill_c != PANEL_ALT:
			draw.rounded_rectangle((x0, y0 + BTN_DROP, x1, y1 + BTN_DROP), radius=BTN_CORNER, fill=edge)
		shine_face(style_im, (x0, y0, x1, y1), fill_c, BTN_CORNER)
		if fill_c == PANEL_ALT:
			draw.rounded_rectangle((x0, y0, x1, y1), radius=BTN_CORNER, outline=MUTED_SKIN, width=2)
		m.center_text(draw, (x0, y0, x1, y1), label, fnt, ink)

	m.button = patched
	try:
		im = m.hud_context(w, h)
	finally:
		m.button = orig
	ImageDraw.Draw(im).text((16, 44), "PC 1920x1080: layout unchanged, new button skins (3 px edge, corner 10, shine)", font=font(REG, 16), fill=(255, 255, 255))
	return im


def buttons(w, h):
	im = Image.new("RGB", (w, h), (0x3A, 0x2C, 0x20))
	draw = ImageDraw.Draw(im)
	phone = w == 667
	k = 1 if phone else 2
	draw.text((12 * k, 8 * k), "Button styles: resting | pressed (face drops onto the 3 px edge) | selected (4 px ring)", font=font(BOLD, 11 * k), fill=CREAM)
	names = list(STYLES)
	bw, bh = (60 if phone else 96 * k), 30 * k
	step = bh + 12 * k + (3 if phone else 6)
	per_col = (len(names) + 1) // 2 if phone else len(names)
	ys = 30 * k
	for i, name in enumerate(names):
		block = i // per_col if phone else 0
		r = i % per_col
		bx0 = 12 * k + block * 272 * k
		by = ys + r * step
		draw.text((bx0, by + 7 * k), name, font=font(REG, 10 * k), fill=CREAM)
		label = name.upper() if not phone else name.upper()[:7]
		lx = bx0 + (50 if phone else 70 * k)
		for j, (pressed, selected) in enumerate(((False, False), (True, False), (False, True))):
			bx = lx + j * (bw + (14 if phone else 12 * k))
			button(im, (bx, by, bx + bw, by + bh), label, name, fnt=font(BOLD, (10 if phone else 12 * k)), pressed=pressed, selected=selected)
	# The plaque and the panel (inset 4 and 12).
	py = h - 100 if phone else ys + per_col * step + 10
	for n, (label, inset) in enumerate((("Plaque (inset 4)", 4), ("Panel (inset 12)", 12))):
		bx = 12 * k + n * (150 * k)
		box = (bx, py, bx + 140 * k, py + 70 * k)
		face = plaque(im, box)
		draw.text((face[0] + inset * k, face[1] + inset * k), label.split(" ")[0], font=font(BOLD, 13 * k), fill=INK)
		draw.text((face[0] + inset * k, face[1] + inset * k + 16 * k), label.split(" ", 1)[1], font=font(REG, 11 * k), fill=BARK)
	return im


def theme_sheet(w, h):
	phone = w == 667
	k = 1 if phone else 2
	im = Image.new("RGB", (w, h), (0xFA, 0xF4, 0xE6))
	draw = ImageDraw.Draw(im)
	draw.text((12 * k, 8 * k), "Round 3 tokens (UITheme.Skin)", font=font(BOLD, 14 * k), fill=INK)
	swatches = [
		("Paper", PAPER), ("PaperDark", PAPER_DARK), ("Cream", CREAM_SKIN),
		("Bark", BARK), ("Ink", INK), ("Muted", MUTED_SKIN),
	]
	sx, sy, sw, sh = 12 * k, 30 * k, 52 * k, 34 * k
	for i, (name, col) in enumerate(swatches):
		x = sx + i * (sw + 8 * k)
		draw.rounded_rectangle((x, sy, x + sw, sy + sh), radius=6, fill=col, outline=INK, width=1)
		draw.text((x, sy + sh + 2), name, font=font(REG, 8 * k), fill=INK)
		draw.text((x, sy + sh + 2 + 10 * k), "#%02X%02X%02X" % col, font=font(REG, 8 * k), fill=INK)
	# Numbers
	ty = sy + sh + 28 * k
	notes = [
		"Plaque: corner 12, stroke 2 Bark, drop edge 4 Bark, gradient 90: Cream 0 / Paper 0.18 / PaperDark 1, inset 4",
		"Panel: the plaque with inset 12",
		"Button: corner 10, drop edge 3 (style edge colour), shine white 0 / 0.9 grey 0.12..1, starter stroke 2 Muted",
		"Loading card: plaque 0.5, 0.45, min(280, 72% width) x 132, padding 16, Ink backdrop 45% transparent",
		"Fonts: FredokaOne 20 Ink (title), GothamMedium 14 Bark (line, MinTextSize 14)",
	]
	for i, line in enumerate(notes):
		draw.text((12 * k, ty + i * 12 * k), line, font=font(REG, 8 * k), fill=INK)
	# Contrast
	cy = ty + len(notes) * 12 * k + 8 * k
	pairs = [
		("Ink on Paper", INK, PAPER, 4.5), ("Ink on Cream", INK, CREAM_SKIN, 4.5),
		("Ink on PaperDark", INK, PAPER_DARK, 4.5), ("Bark on Paper", BARK, PAPER, 4.5),
		("Bark on Cream", BARK, CREAM_SKIN, 4.5), ("Bark on PaperDark", BARK, PAPER_DARK, 4.5),
		("Ink on amber (MENU)", INK, AMBER, 3.0), ("Cream on deep green (HAMMER, SELL)", CREAM_SKIN, GREEN, 3.0),
		("Ink on confirm", CONFIRM_INK, CONFIRM, 3.0), ("Cream on danger", CREAM, DANGER, 4.5),
	]
	draw.text((12 * k, cy), "Contrast (WCAG), needs >= bar", font=font(BOLD, 10 * k), fill=INK)
	cy += 14 * k
	for i, (name, fg, bg, bar) in enumerate(pairs):
		col = i // 5
		row = i % 5
		x = 12 * k + col * 320 * k
		y = cy + row * 16 * k
		ratio = contrast(fg, bg)
		draw.rounded_rectangle((x, y, x + 22 * k, y + 12 * k), 3, fill=bg)
		draw.text((x + 5 * k, y), "Aa", font=font(BOLD, 9 * k), fill=fg)
		draw.text((x + 28 * k, y), "%s  %.2f:1  (bar %.1f) %s" % (name, ratio, bar, "ok" if ratio >= bar else "FAIL"), font=font(REG, 9 * k), fill=INK)
		assert ratio >= bar, f"{name} {ratio}"
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	outputs = {
		"r3-hud-phone-667x375": phone_hud(),
		"r3-menu-phone-667x375": phone_menu(),
		"r3-loading-667x375": loading(667, 375),
		"r3-loading-1920x1080": loading(1920, 1080),
		"r3-news-667x375": news(667, 375),
		"r3-news-1920x1080": news(1920, 1080),
		"r3-hud-pc-1920x1080": pc_hud(),
		"r3-buttons-667x375": buttons(667, 375),
		"r3-buttons-1920x1080": buttons(1920, 1080),
		"r3-theme-sheet-667x375": theme_sheet(667, 375),
		"r3-theme-sheet-1920x1080": theme_sheet(1920, 1080),
	}
	for name, im in outputs.items():
		path = os.path.join(OUT, name + ".png")
		im.save(path, "PNG")
		print(path)


if __name__ == "__main__":
	main()
