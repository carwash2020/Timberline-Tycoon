#!/usr/bin/env python3
"""Launch hardening: the Settings card (music, sound, camera speed, graphics,
replay tutorial) and its Codes tab, as the UITheme layout draws them.

Hand-built from the same tokens as UITheme (the GAD plaque and button skins,
reused from v1u_round3) and from SettingsUI's own numbers: a 340 x 300 card
under the corner (cut to end above the jump zone on a phone, SettingsUI.fitCard), a one-row strip of five 44 px tabs (GAME, VISIT, BOARD,
REPORT, CODES; the card is 340 wide), then 308 x 44 rows 6 px apart inside a scroll frame. The card scrolls,
so each size shows the top of the list, the list scrolled to the new rows, and
the Codes tab. Liberation Sans stands in for Gotham. Composites of the layout,
not engine screenshots.

  python3 tools/preview/v1h_settings.py   writes previews/v1-hardening/settings-*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_round3 as r  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-hardening")
m = r.m

CARD_W, CARD_H = 340, 300
ROW_W, ROW_H, GAP, DROP = 308, 44, 6, 3
STEP = ROW_H + DROP + GAP

GAME_ROWS = [
	"MUSIC: ON",
	"Music volume  100%  ±",
	"SOUND FX: ON",
	"Effects volume  100%  ±",
	"Camera speed  100%  ±",
	"Graphics: Lower",
	"CAMERA SHAKE: ON",
	"UI scale  NORMAL",
	"TIPS: ON",
	"REPLAY TUTORIAL",
	"WHAT'S NEW",
	"RESTART SAVE 1",
]
STYLE = {"buy": "confirm", "skip": "muted"}  # UITheme.Styles names -> the preview palette
TABS = ["GAME", "VISIT", "BOARD", "REPORT", "CODES"]
HEAD = 8 + 18 + 6  # padding, title, gap


def tab_strip(canvas, x, y, active):
	w = (ROW_W - 4 * 4) // 5
	for i, name in enumerate(TABS):
		x0 = x + i * (w + 4)
		r.button(
			canvas,
			(x0, y, x0 + w, y + ROW_H),
			name,
			STYLE["buy" if i == active else "skip"],
			fnt=r.font(r.BOLD, 12),
			selected=(i == 0 and active == 0),
		)


def game_canvas():
	h = HEAD + STEP * (1 + len(GAME_ROWS)) + 8
	canvas = Image.new("RGB", (CARD_W, h), r.PAPER)
	d = ImageDraw.Draw(canvas)
	x = (CARD_W - ROW_W) // 2
	d.text((x, 8), "SETTINGS", font=r.font(r.BOLD, 14), fill=r.BARK)
	tab_strip(canvas, x, HEAD, 0)
	y = HEAD + STEP
	for label in GAME_ROWS:
		r.button(canvas, (x, y, x + ROW_W, y + ROW_H), label, STYLE["buy"], fnt=r.font(r.BOLD, 15))
		y += STEP
	return canvas


def codes_canvas(status):
	canvas = Image.new("RGB", (CARD_W, CARD_H), r.PAPER)
	d = ImageDraw.Draw(canvas)
	x = (CARD_W - ROW_W) // 2
	d.text((x, 8), "SETTINGS", font=r.font(r.BOLD, 14), fill=r.BARK)
	tab_strip(canvas, x, HEAD, 4)
	y = HEAD + STEP
	d.text((x, y), "REDEEM A CODE", font=r.font(r.BOLD, 14), fill=r.BARK)
	y += 18 + 6
	d.rounded_rectangle((x, y, x + ROW_W, y + ROW_H), radius=8, fill=r.CREAM_SKIN, outline=r.BARK, width=2)
	d.text((x + 10, y + 13), "TYPE A CODE", font=r.font(r.BOLD, 16), fill=r.MUTED_SKIN)
	y += ROW_H + GAP
	r.button(canvas, (x, y, x + ROW_W, y + ROW_H), "REDEEM", STYLE["buy"], fnt=r.font(r.BOLD, 15))
	y += STEP
	d.text((x, y), status, font=r.font(r.BOLD, 14), fill=r.INK)
	return canvas


def list_canvas(active, heading, ask, labels):
	"""A tab with a heading, one question line and a list of 44 px rows (VISIT, REPORT)."""
	canvas = Image.new("RGB", (CARD_W, CARD_H), r.PAPER)
	d = ImageDraw.Draw(canvas)
	x = (CARD_W - ROW_W) // 2
	d.text((x, 8), "SETTINGS", font=r.font(r.BOLD, 14), fill=r.BARK)
	tab_strip(canvas, x, HEAD, active)
	y = HEAD + STEP
	d.text((x, y), heading, font=r.font(r.BOLD, 14), fill=r.BARK)
	y += 22
	d.text((x, y), ask, font=r.font(r.BOLD, 14), fill=r.INK)
	y += 22
	for label in labels:
		r.button(canvas, (x, y, x + ROW_W, y + ROW_H), label, STYLE["skip"], fnt=r.font(r.BOLD, 15))
		y += STEP
	return canvas


def card(im, right, top, canvas, scroll, scale, height):
	"""The plaque with `canvas` showing through its `height` tall window, scrolled
	`scroll` px, drawn at 1x and then scaled by the screen's UIScale (0.78 on a
	667 x 375 phone, 1.25 at 1080 tall). Returns the card's bottom edge."""
	key = (255, 0, 255)
	tmp = Image.new("RGB", (CARD_W + 2, height + 6), key)
	face = r.plaque(tmp, (1, 0, CARD_W + 1, height))
	inner_h = face[3] - face[1] - 4
	window = canvas.crop((0, scroll, CARD_W, min(canvas.size[1], scroll + inner_h)))
	mask = Image.new("L", window.size, 0)
	ImageDraw.Draw(mask).rounded_rectangle((3, 0, window.size[0] - 4, window.size[1] - 1), radius=10, fill=255)
	tmp.paste(window, (face[0], face[1] + 2), mask)
	size = (round(tmp.size[0] * scale), round(tmp.size[1] * scale))
	big = tmp.resize(size, Image.LANCZOS)
	cut = Image.new("L", size, 0)
	cp, bp = cut.load(), big.load()
	for y in range(size[1]):
		for x in range(size[0]):
			pr, pg, pb = bp[x, y]
			cp[x, y] = 0 if (pr > 200 and pg < 80 and pb > 200) else 255
	im.paste(big, (right - size[0], top), cut)
	return top + size[1]


def caption(im, text, size, y):
	d = ImageDraw.Draw(im)
	f = r.font(r.REG, size)
	w = r.text_w(d, text, f)
	d.rectangle((0, y - 4, w + 24, y + size + 6), fill=(0, 0, 0))
	d.text((12, y), text, font=f, fill=(255, 255, 255))


def scene(phone, canvas, scroll, text):
	w, h = (667, 375) if phone else (1920, 1080)
	im = m.scene_backdrop(w, h)
	edge = 12 if phone else 24
	r.cash_plaque(im, w - edge, 8 if phone else 16, 150 if phone else 200)
	top = 62 if phone else 88
	scale = 0.78 if phone else 1.25
	# SettingsUI.fitCard: on a short touch screen the card ends above the jump zone.
	height = max(190, min(300, int((h - 98 - top) / scale))) if phone else CARD_H
	bottom = card(im, w - edge, top, canvas, scroll, scale, height)
	if phone:
		m.phone_zones(im)
	caption(im, text.format(bottom=bottom), 10 if phone else 16, 352 if phone else 1046)
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	game = game_canvas()
	scrolled = HEAD + STEP * 5  # the Camera speed row at the top of the window
	for phone, tag in ((True, "667x375"), (False, "1920x1080")):
		kind = "Phone" if phone else "PC"
		outs = {
			f"settings-game-{tag}": scene(
				phone, game, 0, f"{kind} {tag}: Settings, GAME tab. Five 44 px tabs in one row; card ends at y {{bottom}}"
			),
			f"settings-scrolled-{tag}": scene(
				phone,
				game,
				scrolled,
				f"{kind} {tag}: Settings scrolled to Camera speed and Graphics (Lower / Higher), 44 px tall each",
			),
			f"settings-bottom-{tag}": scene(
				phone,
				game,
				HEAD + STEP * 8,
				f"{kind} {tag}: Settings scrolled down: TIPS, REPLAY TUTORIAL (asks twice), WHAT'S NEW",
			),
			f"settings-report-{tag}": scene(
				phone,
				list_canvas(3, "REPORT A PLAYER", "Who are you reporting?", ["Sam", "Riley", "Jo"]),
				0,
				f"{kind} {tag}: REPORT tab (shown while the moderation flow is on), one 44 px row per player",
			),
			f"settings-visit-{tag}": scene(
				phone,
				list_canvas(1, "VISIT A PLOT", "", ["Visit Sam", "Anyone", "Sam"]),
				0,
				f"{kind} {tag}: VISIT tab, still reachable on the five-tab row",
			),
			f"settings-codes-{tag}": scene(
				phone,
				codes_canvas("That code isn't valid."),
				0,
				f"{kind} {tag}: Settings, CODES tab. 44 px box and REDEEM; the server's answer shows under it",
			),
		}
		for name, im in outs.items():
			path = os.path.join(OUT, name + ".png")
			im.save(path, "PNG")
			print(path)


if __name__ == "__main__":
	main()
