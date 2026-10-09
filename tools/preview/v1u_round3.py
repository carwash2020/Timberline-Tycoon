#!/usr/bin/env python3
"""Lane U round 3 previews (GAD final skins, phone HUD, icons).

Draws the layouts from the same numbers the live code uses: the code-built
plaque and panel (Paper face, Bark 2 px stroke, 4 px Bark drop edge, the
Cream / Paper / PaperDark gradient), the 10 px buttons with a 3 px drop edge,
the shine and the pressed state, the loading plaque, the phone side column
(three 44 x 44 icon buttons drawn from the real assets/ui/icons PNGs), the
quick menu with SAVES and Send truck home inside MENU, and What's New with
its 44 x 44 Close. Phone frames (667 x 375) draw Roblox's thumbstick and the
jump button. DejaVu stands in for FredokaOne, GothamBold, GothamMedium and
Gotham, which are not on this machine.

    python3 tools/preview/v1u_round3.py
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_mockups as base  # noqa: E402  (scene_backdrop, phone_zones)

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-u")
ICONS = os.path.join(ROOT, "assets", "ui", "icons")
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
K = 3  # supersampling

# Tokens (UITheme.Colors)
INK = (0x3C, 0x28, 0x14)
CREAM = (0xF5, 0xEB, 0xD7)
PAPER = (0xF0, 0xE1, 0xC3)
PAPER_DARK = (0xE2, 0xCF, 0xAA)
BARK = (0x58, 0x3A, 0x22)
MUTED_STROKE = (0xA0, 0x91, 0x78)
PANEL = (0x2A, 0x1F, 0x17)
PANEL_ALT = (0x1E, 0x1B, 0x18)
AMBER = (0xF2, 0xC1, 0x4E)
AMBER_EDGE = (0xC9, 0xA2, 0x4A)
CONFIRM = (0x4C, 0xC3, 0x6A)
CONFIRM_EDGE = (0x2F, 0x8A, 0x48)
CONFIRM_INK = (0x14, 0x24, 0x0F)
GREEN = (0x2F, 0x8A, 0x48)
GREEN_EDGE = (0x1E, 0x5C, 0x30)
DANGER = (0xB2, 0x3B, 0x30)
DANGER_EDGE = (0x7A, 0x2C, 0x26)
MUTED_FILL = (0x5A, 0x4A, 0x3E)
MUTED_EDGE = (0x3E, 0x34, 0x2C)
MUTED = (0xCD, 0xBF, 0xA3)
SELECTION = (0xFF, 0xF4, 0xC2)

STYLES = {
	# name: (fill, edge, ink, outline)
	"primary": (AMBER, AMBER_EDGE, CONFIRM_INK, None),
	"confirm": (CONFIRM, CONFIRM_EDGE, CONFIRM_INK, None),
	"danger": (DANGER, DANGER_EDGE, CREAM, None),
	"muted": (MUTED_FILL, MUTED_EDGE, MUTED, None),
	"locked": (MUTED_FILL, MUTED_EDGE, MUTED, None),
	"bark": (PANEL, AMBER_EDGE, CREAM, None),
	"starter": (PANEL_ALT, None, CREAM, MUTED_STROKE),
	"iconGreen": (GREEN, GREEN_EDGE, CREAM, None),
}

base.BOLD, base.REG = BOLD, REG


def lum(rgb):
	def lin(c):
		s = c / 255
		return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

	r, g, b = rgb
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
	hi, lo = lum(a), lum(b)
	if hi < lo:
		hi, lo = lo, hi
	return (hi + 0.05) / (lo + 0.05)


def font(path, size):
	return ImageFont.truetype(path, int(round(size * K)))


def darker(rgb, amount):
	return tuple(max(0, int(c * (1 - amount))) for c in rgb)


class Canvas:
	def __init__(self, w, h, background: Image.Image | None = None):
		self.w, self.h = w, h
		if background is None:
			self.img = Image.new("RGBA", (w * K, h * K), PANEL_ALT + (255,))
		else:
			self.img = background.convert("RGBA").resize((w * K, h * K), Image.BICUBIC)
		self.d = ImageDraw.Draw(self.img)

	def b(self, box):
		return tuple(int(round(v * K)) for v in box)

	def rr(self, box, fill, radius, outline=None, width=0):
		self.d.rounded_rectangle(self.b(box), radius=radius * K, fill=fill, outline=outline, width=width * K)

	def overlay(self, box, rgba, radius=0):
		layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
		ImageDraw.Draw(layer).rounded_rectangle(self.b(box), radius=radius * K, fill=rgba)
		self.img = Image.alpha_composite(self.img, layer)
		self.d = ImageDraw.Draw(self.img)

	def gradient(self, box, radius, stops, mult=None):
		"""A vertical gradient (stops: [(t, rgb)]) clipped to a rounded box."""
		x0, y0, x1, y1 = self.b(box)
		hgt = y1 - y0
		strip = Image.new("RGB", (x1 - x0, hgt))
		sd = ImageDraw.Draw(strip)
		for y in range(hgt):
			t = y / max(hgt - 1, 1)
			for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
				if t0 <= t <= t1:
					f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
					col = tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3))
					break
			else:
				col = stops[-1][1]
			sd.line((0, y, x1 - x0, y), fill=col)
		mask = Image.new("L", strip.size, 0)
		ImageDraw.Draw(mask).rounded_rectangle((0, 0, x1 - x0 - 1, hgt - 1), radius=radius * K, fill=255)
		self.img.paste(strip, (x0, y0), mask)
		self.d = ImageDraw.Draw(self.img)

	def text(self, xy, text, fnt, fill, anchor="la"):
		self.d.text((xy[0] * K, xy[1] * K), text, font=fnt, fill=fill, anchor=anchor)

	def paste_icon(self, path, center, size):
		icon = Image.open(path).convert("RGBA").resize((size * K, size * K), Image.LANCZOS)
		self.img.alpha_composite(icon, (int(center[0] * K - size * K / 2), int(center[1] * K - size * K / 2)))
		self.d = ImageDraw.Draw(self.img)

	def save(self, name):
		os.makedirs(OUT, exist_ok=True)
		out = self.img.resize((self.w, self.h), Image.LANCZOS).convert("RGB")
		out.save(os.path.join(OUT, name))
		print("wrote", name)


def plate(cv, x, y, w, h, kind="Panel"):
	"""The code-built plaque or panel. `h` is the whole height, edge included."""
	cv.rr((x, y, x + w, y + h), BARK, 12)
	cv.gradient((x, y, x + w, y + h - 4), 12, [(0, CREAM), (0.18, PAPER), (1, PAPER_DARK)])
	cv.rr((x, y, x + w, y + h - 4), None, 12, outline=BARK, width=2)
	return (x + 12, y + 12, x + w - 12, y + h - 4 - 12) if kind == "Panel" else (x + 4, y + 4, x + w - 4, y + h - 8)


def button(cv, x, y, w, h, label, style, pressed=False, selected=False, icon=None, fnt=None, ink=None):
	"""A button face w x h with its 3 px drop edge below it."""
	fill, edge, text_ink, outline = STYLES[style]
	fnt = fnt or font(BOLD, 15)
	if selected:
		cv.rr((x - 6, y - 6, x + w + 6, y + h + 3 + 6), None, 14, outline=SELECTION, width=4)
	edge_col = edge or darker(fill, 0.35)
	dy = 3 if pressed else 0
	if not pressed:
		cv.rr((x, y, x + w, y + h + 3), edge_col, 10)
	cv.gradient((x, y + dy, x + w, y + h + dy), 10, [(0, tuple(fill)), (0.12, tuple(int(c * 0.9) for c in fill)), (1, tuple(int(c * 0.9) for c in fill))])
	if outline:
		cv.rr((x, y + dy, x + w, y + h + dy), None, 10, outline=outline, width=2)
	if icon:
		cv.paste_icon(os.path.join(ICONS, icon), (x + w / 2, y + h / 2 + dy), 28)
	elif label:
		shade = tuple(int(c * 0.9) for c in (ink or text_ink))
		cv.text((x + w / 2, y + h / 2 + dy), label, fnt, shade, anchor="mm")


def jump_overlay(img):
	base.phone_zones(img)


def phone_scene(dim=0):
	im = base.scene_backdrop(667, 375)
	base.phone_zones(im)
	return im


def cash(cv, x_right, y, amount="$12,480", scale=1.0):
	w, h = int(150 * scale), int(40 * scale)
	plate(cv, x_right - w, y, w, h, "Plaque")
	cv.text((x_right - w / 2, y + (h - 4) / 2), amount, font(BOLD, 20 * scale), INK, anchor="mm")


# --------------------------------------------------------------------------
# HUD
# --------------------------------------------------------------------------


def hud_phone():
	cv = Canvas(667, 375, phone_scene())
	cash(cv, 655, 12, scale=0.9)
	# The Field Guide at the top of the left column (starter style, 130 x 44).
	button(cv, 12, 60, 130, 44, "FIELD GUIDE", "starter", fnt=font(BOLD, 14))
	# Side column: right edge = the jump button's right (642), bottom 24 above it (261).
	right, bottom = 642, 285 - 24
	x = right - 44
	ys = [bottom - 44 - 2 * 52, bottom - 44 - 52, bottom - 44]
	button(cv, x, ys[0], 44, 44, "", "primary", icon="menu.png")
	button(cv, x, ys[1], 44, 44, "", "iconGreen", icon="hammer.png")
	button(cv, x, ys[2], 44, 44, "", "iconGreen", icon="sell-here.png", selected=True)
	cv.text((x - 12, ys[0] + 22), "MENU", font(BOLD, 12), CREAM, anchor="rm")
	cv.text((x - 12, ys[1] + 22), "HAMMER", font(BOLD, 12), CREAM, anchor="rm")
	cv.text((x - 12, ys[2] + 22), "Sell here", font(BOLD, 12), CREAM, anchor="rm")
	cv.save("r3-hud-phone-667x375.png")


def hud_pc():
	cv = Canvas(1920, 1080, base.scene_backdrop(1920, 1080))
	cash(cv, 1920 - 24, 70, "$12,480", 1.5)
	button(cv, 24, 80, 160, 44, "FIELD GUIDE", "starter", fnt=font(BOLD, 17))
	# 110 x 40 side buttons, up from just under the middle, text labels as before.
	scale = 1.25
	w, h = int(110 * scale), int(40 * scale)
	names = [("MENU", "primary"), ("SAVES", "bark"), ("HAMMER", "confirm"), ("Sell here", "confirm"), ("Send truck home", "primary")]
	bottom = 1080 / 2 + 44 * scale
	for i, (label, style) in enumerate(reversed(names)):
		y = bottom - (i + 1) * h - i * 8 * scale
		button(cv, 1920 - 24 - w, y, w, h, label, style, fnt=font(BOLD, 15), selected=(label == "SAVES"))
	cv.save("r3-hud-pc-1920x1080.png")


# --------------------------------------------------------------------------
# Quick menu (phone): SAVES and Send truck home live inside MENU
# --------------------------------------------------------------------------


def quickmenu_phone():
	cv = Canvas(667, 375, phone_scene())
	cv.overlay((0, 0, 667, 375), PANEL_ALT + (128,))
	pw, ph = 480, 236
	x, y = (667 - pw) / 2, (375 - ph) / 2 - 8
	plate(cv, x, y, pw, ph)
	cv.text((x + pw / 2, y + 30), "QUICK MENU", font(BOLD, 24), INK, anchor="mm")
	tiles = ["SAVES", "SEND TRUCK HOME", "STORE", "BADGES", "FIELD GUIDE", "SETTINGS"]
	tw, th, gap = 138, 50, 10
	gx = x + (pw - (3 * tw + 2 * gap)) / 2
	gy = y + 54
	for i, name in enumerate(tiles):
		cx, cy = gx + (i % 3) * (tw + gap), gy + (i // 3) * (th + gap)
		button(cv, cx, cy, tw, th, name, "bark", selected=(i == 0), fnt=font(BOLD, 12 if len(name) > 12 else 17))
	cv.text((x + pw / 2, y + ph - 22), "A select  ·  B close", font(BOLD, 14), BARK, anchor="mm")
	cv.save("r3-quickmenu-phone-667x375.png")


# --------------------------------------------------------------------------
# Loading card
# --------------------------------------------------------------------------

TIP = "Planks sell for more than logs."


def loading(w, h, name):
	scale = max(1.0, min(1.8, min(h / 420, w / 700)))
	cv = Canvas(w, h, base.scene_backdrop(w, h))
	if w == 667:
		pass
	cv.overlay((0, 0, w, h), INK + (int(255 * 0.55),))
	cw = min(280, 0.72 * (w / scale)) * scale
	chh = 132 * scale
	x, y = (w - cw) / 2, h * 0.45 - chh / 2
	cv.rr((x, y, x + cw, y + chh), BARK, int(12 * scale))
	cv.gradient((x, y, x + cw, y + chh - 4 * scale), int(12 * scale), [(0, CREAM), (0.18, PAPER), (1, PAPER_DARK)])
	cv.rr((x, y, x + cw, y + chh - 4 * scale), None, int(12 * scale), outline=BARK, width=max(2, int(2 * scale)))
	cv.text((x + cw / 2, y + 16 * scale + 13 * scale), "Timberline Tycoon", font(BOLD, 20 * scale), INK, anchor="mm")
	cv.text((x + cw / 2, y + 16 * scale + 50 * scale), TIP, font(REG, 14 * scale), BARK, anchor="mm")
	if w == 667:
		img = cv.img.resize((w, h), Image.LANCZOS).convert("RGB")
		jump = Image.new("RGB", (w, h))
		del jump
		# the thumbstick and jump button over the dimmed world
		tmp = img.copy()
		base.phone_zones(tmp)
		cv = Canvas(w, h, tmp)
	cv.save(name)


# --------------------------------------------------------------------------
# What's New (phone)
# --------------------------------------------------------------------------


def news_phone():
	cv = Canvas(667, 375, phone_scene())
	cv.overlay((0, 0, 667, 375), PANEL_ALT + (115,))
	# Compact card: right of the thumbstick (left 40%), bottom above the jump box.
	left, right, bottom = 667 * 0.4 + 8, 667 - 8, 375 - 90 - 8
	scale = 0.78
	rows = [
		("A new island map, with the Bayou and Red Mesa.", "Two regions past the old town."),
		("Mine the cave for ore.", "Clear rubble, then follow the vein."),
		("Build from blueprints.", "Place a plan, then raise the walls."),
		("Foreman Rook's daily jobs, with streaks.", "Three jobs a day. A streak pays more."),
		("Temper your axe.", "A hotter edge bites harder."),
		("Sparkworks logic pieces.", "Wire switches, gates and lamps."),
		("A sky island, reached by the gondola pass.", "Ride the line up from the pass."),
	]
	strip = 8 + 44 + 8  # screen px
	row_h = 36 * scale
	inset = 4 * scale
	ph = inset + strip + 1 * scale + len(rows) * (row_h + 1 * scale) + inset + 4  # + the 4 px drop edge
	pw = right - left
	y = bottom - ph
	x = left
	plate(cv, x, y, pw, ph)
	# title strip: sunset wash, wordmark left, Close top right
	sx0, sy0, sx1, sy1 = x + 8 * scale, y + inset, x + pw - 8 * scale, y + inset + strip
	cv.gradient((sx0, sy0, sx1, sy1), 6, [(0, (0xE8, 0xA1, 0x5A)), (0.45, AMBER), (1, PANEL)])
	cv.text((sx0 + 8, (sy0 + sy1) / 2), "TIMBERLINE", font(BOLD, 14), CREAM, anchor="lm")
	button(cv, sx1 - 8 - 44, sy0 + 8, 44, 44 - 3, "X", "primary", fnt=font(BOLD, 18))
	ry = sy1 + 1 * scale
	for i, (head, detail) in enumerate(rows):
		cv.rr((sx0, ry + 2, sx0 + 28, ry + 2 + 28), PANEL_ALT, 5, outline=AMBER_EDGE, width=1)
		cv.d.ellipse(cv.b((sx0 + 9, ry + 11, sx0 + 19, ry + 21)), fill=AMBER)
		cv.text((sx0 + 36, ry + 1), head, font(REG, 14), INK)
		cv.text((sx0 + 36, ry + 15), detail, font(REG, 10.5), BARK)
		ry += row_h + 1 * scale
	cv.save("r3-news-phone-667x375.png")
	return {"card": (x, y, x + pw, y + ph), "close": (sx1 - 8 - 44, sy0 + 8, sx1 - 8, sy0 + 8 + 44), "strip": (sx0, sy0, sx1, sy1)}


# --------------------------------------------------------------------------
# PC: a panel and every button style, pressed and selected
# --------------------------------------------------------------------------


def skins_pc():
	cv = Canvas(1920, 1080, base.scene_backdrop(1920, 1080))
	cv.overlay((0, 0, 1920, 1080), PANEL_ALT + (110,))
	px, py, pw, ph = 360, 120, 1200, 840
	plate(cv, px, py, pw, ph, "Panel")
	cv.text((px + 36, py + 48), "Panel (inset 12) and every button style", font(BOLD, 30), INK, anchor="lm")
	cv.text((px + 36, py + 90), "Paper face, Bark 2 px stroke, 4 px Bark drop edge, Cream > Paper > PaperDark gradient, corner 12", font(REG, 17), BARK, anchor="lm")
	# a nested plaque
	plate(cv, px + 36, py + 120, 420, 120, "Plaque")
	cv.text((px + 36 + 210, py + 120 + 58), "Plaque (inset 4)", font(BOLD, 24), INK, anchor="mm")
	names = ["primary", "confirm", "danger", "muted", "locked", "bark", "starter", "iconGreen"]
	bw, bh = 180, 52
	for row, mode in enumerate(["rest", "pressed", "selected"]):
		cv.text((px + 36, py + 280 + row * 190), mode.upper(), font(BOLD, 18), BARK, anchor="lm")
		for i, name in enumerate(names):
			x = px + 36 + (i % 4) * (bw + 24) + (0 if i < 4 else 0)
			yy = py + 316 + row * 190
			if i >= 4:
				continue
			button(cv, x, yy, bw, bh, name.upper(), name, pressed=(mode == "pressed"), selected=(mode == "selected"), fnt=font(BOLD, 18))
	# second half of the styles, on the right
	for row, mode in enumerate(["rest", "pressed", "selected"]):
		for i, name in enumerate(names[4:]):
			x = px + 36 + i * (bw + 24) + 0
			yy = py + 316 + row * 190 + 70
			button(cv, x, yy, bw, bh, name.upper(), name, pressed=(mode == "pressed"), selected=(mode == "selected"), fnt=font(BOLD, 18))
	cv.save("r3-skins-pc-1920x1080.png")


# --------------------------------------------------------------------------
# Theme sheet
# --------------------------------------------------------------------------

TOKENS = [
	("Paper", PAPER, "#F0E1C3"),
	("PaperDark", PAPER_DARK, "#E2CFAA"),
	("Cream", CREAM, "#F5EBD7"),
	("Bark", BARK, "#583A22"),
	("Ink", INK, "#3C2814"),
	("MutedStroke", MUTED_STROKE, "#A09178"),
	("Green", GREEN, "#2F8A48"),
	("GreenEdge", GREEN_EDGE, "#1E5C30"),
	("Amber", AMBER, "#F2C14E"),
	("AmberEdge", AMBER_EDGE, "#C9A24A"),
	("Confirm", CONFIRM, "#4CC36A"),
	("Danger", DANGER, "#B23B30"),
]
PAIRS = [
	("Ink on Paper", INK, PAPER, 4.5),
	("Bark on Paper", BARK, PAPER, 4.5),
	("Ink on PaperDark", INK, PAPER_DARK, 4.5),
	("Bark on PaperDark", BARK, PAPER_DARK, 4.5),
	("Cream on Bark", CREAM, BARK, 4.5),
	("Cream on Green (icons)", CREAM, GREEN, 3.0),
	("Ink on Amber (menu)", INK, AMBER, 3.0),
	("Cream on Confirm (old)", CREAM, CONFIRM, 3.0),
]


def theme_sheet(w, h):
	wide = w > 700
	cv = Canvas(w, h, None)
	cv.rr((0, 0, w, h), PAPER_DARK, 0)
	s = 1.0 if wide else 0.5
	cv.text((24 * s, 22 * s), "Round 3 tokens and contrast", font(BOLD, 34 * s), INK, anchor="lm")
	cols = 6
	cw = (w - 48 * s) / cols
	ch = 96 * s
	for i, (name, col, hexname) in enumerate(TOKENS):
		x = 24 * s + (i % cols) * cw
		y = 60 * s + (i // cols) * (ch + 12 * s)
		cv.rr((x, y, x + cw - 12 * s, y + ch), col, 8, outline=BARK, width=1)
		ink = INK if lum(col) > 0.35 else CREAM
		cv.text((x + 10 * s, y + 22 * s), name, font(BOLD, 18 * s), ink, anchor="lm")
		cv.text((x + 10 * s, y + 52 * s), hexname, font(REG, 16 * s), ink, anchor="lm")
	y0 = 60 * s + 2 * (ch + 12 * s) + 16 * s
	cv.text((24 * s, y0), "Plaque: corner 12, stroke 2 Bark, drop edge 4 Bark, inset 4.  Panel: the same, inset 12.", font(REG, 19 * s), INK, anchor="lm")
	cv.text((24 * s, y0 + 30 * s), "Button: corner 10, drop edge 3 in its edge colour, 2 px stroke only on starter, shine, pressed drops onto the edge.", font(REG, 19 * s), INK, anchor="lm")
	cv.text((24 * s, y0 + 60 * s), "Loading card: plaque (0.5, 0.45), min(280, 0.72 x width) x 132, padding 16, Ink backdrop 45% transparent.", font(REG, 19 * s), INK, anchor="lm")
	y1 = y0 + 100 * s
	pw = (w - 48 * s) / 4
	for i, (name, fg, bg, need) in enumerate(PAIRS):
		x = 24 * s + (i % 4) * pw
		y = y1 + (i // 4) * (70 * s)
		cv.rr((x, y, x + pw - 12 * s, y + 58 * s), bg, 8, outline=BARK, width=1)
		ratio = contrast(fg, bg)
		ok = "ok" if ratio >= need else "UNDER " + str(need)
		cv.text((x + 10 * s, y + 18 * s), name, font(BOLD, 15 * s), fg, anchor="lm")
		cv.text((x + 10 * s, y + 42 * s), f"{ratio:.2f}:1 (needs {need}) {ok}", font(REG, 14 * s), fg, anchor="lm")
	if not wide:
		tmp = cv.img.resize((w, h), Image.LANCZOS).convert("RGB")
		base.phone_zones(tmp)
		cv = Canvas(w, h, tmp)
	cv.save(f"r3-theme-sheet-{w}x{h}.png")


def main():
	hud_phone()
	hud_pc()
	quickmenu_phone()
	loading(667, 375, "r3-loading-667x375.png")
	loading(1920, 1080, "r3-loading-1920x1080.png")
	geo = news_phone()
	skins_pc()
	theme_sheet(667, 375)
	theme_sheet(1920, 1080)
	# The numbers a QA reader checks on the What's New frame.
	cx0, cy0, cx1, cy1 = geo["close"]
	sx0, sy0, sx1, sy1 = geo["strip"]
	print("close box", cx1 - cx0, "x", cy1 - cy0, "; strip top gap", cy0 - sy0, "; right gap", sx1 - cx1, "; bottom gap to first row", sy1 - cy1)


if __name__ == "__main__":
	main()
