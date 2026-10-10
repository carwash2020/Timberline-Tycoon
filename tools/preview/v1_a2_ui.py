#!/usr/bin/env python3
"""Lane A2 previews: the real ForgeUI over the Sky Forge Court with the HUD.

  python3 tools/preview/v1_a2_meshes.py
  PREVIEW_HUD=0 PREVIEW_MESHES=preview/a2-meshes.json \\
      bash tools/preview/shoot.sh v1-a2-endgame 6 1280x720   (copy to preview/a2-backdrop-1280.png)
  ... view 5 at 667x375                                      (preview/a2-backdrop-667.png)
  lune run tools/preview/v1_a2_forge_ui                       (preview/forge-ui-*.json)
  python3 tools/preview/v1_a2_ui.py                           (previews/v1-a2/forge-*.png)

The window is ForgeUI's own instance tree (built in Lune by ForgeUI.Ensure
and Show from SkyForgeService.View): every rect, fill, corner, stroke, shine
and string comes from the JSON. The HUD is the round-3 HUD
(tools/preview/v1u_round3.py). Liberation Sans stands in for Gotham (not on
this machine); Gotham runs a little wider, and button labels shrink to fit
in game (down to 12 px on a phone).

Fails if any text overflows its box, any button is under 44 px, or the
window meets the phone's thumbstick, jump button, HUD column or cash plaque.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_mockups as m  # noqa: E402
import v1u_round3 as r3  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-a2")
PREVIEW = os.path.join(ROOT, "preview")
BOLD_FONTS = {"GothamBold", "GothamBlack", "GothamMedium", "FredokaOne", "SourceSansBold", "Bangers"}
CASH = "$64,000"  # the save in v1_a2_forge_ui.luau

problems: list[str] = []


def font(bold: bool, size: int) -> ImageFont.FreeTypeFont:
	return ImageFont.truetype(r3.BOLD if bold else r3.REG, max(1, int(size)))


def width(draw, text, fnt):
	return draw.textbbox((0, 0), text, font=fnt)[2] if text else 0


def wrap(draw, text, fnt, w):
	lines = []
	for para in text.split("\n"):
		cur = ""
		for word in para.split(" "):
			trial = word if not cur else cur + " " + word
			if width(draw, trial, fnt) <= w or not cur:
				cur = trial
			else:
				lines.append(cur)
				cur = word
		lines.append(cur)
	return lines


def draw_text(im, node, label):
	draw = ImageDraw.Draw(im)
	pad = node.get("pad") or [0, 0, 0, 0]
	x0 = node["x"] + pad[0]
	y0 = node["y"] + pad[1]
	w = node["w"] - pad[0] - pad[2]
	h = node["h"] - pad[1] - pad[3]
	bold = node["font"] in BOLD_FONTS
	text = node["text"]
	size = node["size"]
	if node["scaled"]:
		hi = node.get("maxSize") or 100
		lo = node.get("minSize") or 1
		size = hi
		while size > lo:
			f = font(bold, size)
			if width(draw, text, f) <= w and size * 1.2 <= h + 1:
				break
			size -= 1
	fnt = font(bold, size)
	line_h = round(size * 1.2)
	if node["wrapped"]:
		lines = wrap(draw, text, fnt, w)
	else:
		lines = text.split("\n")
	if node["truncate"] == "AtEnd":
		out = []
		for line in lines:
			if width(draw, line, fnt) > w:
				while line and width(draw, line + "…", fnt) > w:
					line = line[:-1]
				line += "…"
			out.append(line)
		lines = out
	for line in lines:
		if width(draw, line, fnt) > w + 0.5:
			problems.append(f"{label}: '{line}' is {width(draw, line, fnt)} px in a {w:.0f} px box")
	total = line_h * len(lines)
	if total > h + 2 and not node["scaled"]:
		problems.append(f"{label}: '{text[:40]}' needs {total} px, has {h:.0f}")
	if node["yalign"] == "Top":
		y = y0
	elif node["yalign"] == "Bottom":
		y = y0 + h - total
	else:
		y = y0 + (h - total) / 2
	for line in lines:
		lw = width(draw, line, fnt)
		if node["xalign"] == "Left":
			x = x0
		elif node["xalign"] == "Right":
			x = x0 + w - lw
		else:
			x = x0 + (w - lw) / 2
		draw.text((x, y + (line_h - size) / 2 - size * 0.08), line, font=fnt, fill=tuple(node["color"]))
		y += line_h


def draw_node(base, node, label):
	layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	x0, y0 = node["x"], node["y"]
	x1, y1 = x0 + node["w"], y0 + node["h"]
	radius = node.get("corner", 0)
	alpha = int(round((1 - node["bgT"]) * 255))
	if alpha > 0 and node["class"] != "ScrollingFrame":
		if node.get("shine"):
			face = Image.new("RGB", base.size, (0, 0, 0))
			r3.shine_face(face, (x0, y0, x1, y1), tuple(node["bg"]), radius)
			mask = Image.new("L", base.size, 0)
			ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=radius, fill=alpha)
			layer.paste(face, (0, 0), mask)
		else:
			d.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=radius, fill=tuple(node["bg"]) + (alpha,))
	if node.get("stroke"):
		t = node["stroke"]["thickness"]
		d.rounded_rectangle(
			(x0 - t / 2, y0 - t / 2, x1 - 1 + t / 2, y1 - 1 + t / 2),
			radius=radius + t / 2,
			outline=tuple(node["stroke"]["color"]) + (255,),
			width=max(1, round(t)),
		)
	if node.get("text"):
		draw_text(layer, node, label)
	clip = node.get("clip")
	if clip:
		mask = Image.new("L", base.size, 0)
		ImageDraw.Draw(mask).rectangle(tuple(clip), fill=255)
		cut = Image.new("RGBA", base.size, (0, 0, 0, 0))
		cut.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", base.size, 0), mask))
		layer = cut
	return Image.alpha_composite(base, layer)


def check_buttons(data, label):
	for n in data["nodes"]:
		if n["class"] == "TextButton" and n["name"] == "Face":
			if n["h"] < 44 or n["w"] < 44:
				problems.append(f"{label}: button '{n.get('text')}' is {n['w']:.0f}x{n['h']:.0f}")


def overlaps(a, b):
	return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def phone_frame(data, label):
	w, h = data["w"], data["h"]
	im = Image.open(os.path.join(PREVIEW, "a2-backdrop-667.png")).convert("RGB")
	assert im.size == (w, h), im.size
	# The round-3 phone HUD: cash plaque top right, MENU / HAMMER / Sell here
	# above the jump button, Roblox's thumbstick and jump.
	cash = (w - 12 - 150, 8, w - 12, 52)
	face = r3.plaque(im, cash)
	ImageDraw.Draw(im).text((face[0] + 14, face[1] + 9), CASH, font=font(True, 22), fill=r3.INK)
	right = (w - 95) + 70
	column = r3.hud_column(im, right, h - 90 - 24)
	for box, icon, style in column:
		r3.button(im, box, None, style, icon=icon)
	m.phone_zones(im)
	rect = data["rect"]
	panel = (rect["x"], rect["y"], rect["x"] + rect["w"], rect["y"] + rect["h"] + 4)
	stick = (78 - 46, h - 78 - 46, 78 + 46, h - 78 + 46)
	jump = (w - 95, h - 90, w - 25, h - 20)
	for name, zone in [("thumbstick", stick), ("jump", jump), ("cash plaque", cash)] + [
		(f"HUD {icon}", (b[0], b[1], b[2], b[3] + 3)) for b, icon, _ in column
	]:
		if overlaps(panel, zone):
			problems.append(f"{label}: the window meets the {name}")
	return im


def pc_frame(data):
	w, h = data["w"], data["h"]
	back = Image.open(os.path.join(PREVIEW, "a2-backdrop-1280.png")).convert("RGB")
	orig_backdrop, orig_center = m.backdrop, m.center_text

	def center_text(draw, box, text, fnt, fill):
		orig_center(draw, box, CASH if text == "$1,250" else text, fnt, fill)

	m.backdrop = lambda _w, _h: back.copy()
	m.center_text = center_text
	try:
		im = r3.pc_hud(w, h)
	finally:
		m.backdrop, m.center_text = orig_backdrop, orig_center
	# pc_hud writes its own caption at (16, 44): cover it with the backdrop.
	im.paste(back.crop((0, 40, 700, 66)), (0, 40))
	return im


def caption(im, text):
	d = ImageDraw.Draw(im)
	f = font(False, 11 if im.size[0] < 800 else 14)
	tw = width(d, text, f)
	x, y = 8, 4
	d.rectangle((x - 4, y - 2, x + tw + 4, y + (13 if im.size[0] < 800 else 17)), fill=(0, 0, 0))
	d.text((x, y), text, font=f, fill=(255, 255, 255))


SHOTS = [
	("phone-temper", "Phone 667x375 · Temper: each axe and its three tempers"),
	("phone-confirm", "Phone 667x375 · Temper confirm: exact cost and result before Temper"),
	("phone-starfall", "Phone 667x375 · Starfall: recipe, progress, what's missing"),
	("pc-temper", "PC 1280x720 · Temper"),
	("pc-confirm", "PC 1280x720 · Temper confirm (Obsidian Axe, Heavy I to Keen I)"),
	("pc-relics", "PC 1280x720 · Relics"),
	("pc-order", "PC 1280x720 · Old Bram's weekly order"),
]


def main() -> int:
	os.makedirs(OUT, exist_ok=True)
	for name, text in SHOTS:
		data = json.load(open(os.path.join(PREVIEW, f"forge-ui-{name}.json")))
		check_buttons(data, name)
		im = phone_frame(data, name) if data["phone"] else pc_frame(data)
		im = im.convert("RGBA")
		for i, node in enumerate(data["nodes"]):
			im = draw_node(im, node, f"{name} #{i} {node['name']}")
		im = im.convert("RGB")
		caption(im, text)
		path = os.path.join(OUT, f"forge-{name}.png")
		im.save(path)
		print(os.path.relpath(path, ROOT))
	if problems:
		print("\n".join(problems))
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
