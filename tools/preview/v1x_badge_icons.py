#!/usr/bin/env python3
"""Lane X: 512 x 512 icon DRAFTS for the eight new badges (Creator Hub wants
512 x 512). Drafts only: Connor (or the Game Art Director) redraws or approves,
and uploads them himself. A walnut disc, a brass ring and one simple emblem
in the GAD placeholder palette (walnut #2A1F17, brass #C9A24A, cream #F3E7C9,
amber #F2C14E).

  python3 tools/preview/v1x_badge_icons.py   writes previews/v1-x/badge-icons/*.png
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "previews", "v1-x", "badge-icons")
BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

WALNUT = (0x2A, 0x1F, 0x17)
PLATE = (0x3A, 0x2B, 0x20)
BRASS = (0xC9, 0xA2, 0x4A)
CREAM = (0xF3, 0xE7, 0xC9)
AMBER = (0xF2, 0xC1, 0x4E)
SIZE = 512
S = 2  # draw at 2x, then shrink, for smooth edges


def base():
	im = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse((8 * S, 8 * S, (SIZE - 8) * S, (SIZE - 8) * S), fill=BRASS)
	d.ellipse((30 * S, 30 * S, (SIZE - 30) * S, (SIZE - 30) * S), fill=WALNUT)
	d.ellipse((46 * S, 46 * S, (SIZE - 46) * S, (SIZE - 46) * S), fill=PLATE)
	return im, d


def p(*pts):
	return [(x * S, y * S) for x, y in pts]


def label(d, text, y=392, size=44):
	f = ImageFont.truetype(BOLD, size * S)
	w = d.textbbox((0, 0), text, font=f)[2]
	d.text(((SIZE * S - w) / 2, y * S), text, font=f, fill=CREAM)


def bayou(d):
	for i, y in enumerate((324, 346)):
		d.line(p(*[(110 + k * 40, y + (6 if k % 2 else -6)) for k in range(0, 8)]), fill=(0x6F, 0xB5, 0xA5), width=8 * S)
	d.rectangle(p((244, 150), (268, 320)), fill=(0x7A, 0x52, 0x30))
	d.polygon(p((256, 110), (176, 240), (336, 240)), fill=(0x4F, 0x8A, 0x5A))
	d.polygon(p((256, 160), (160, 290), (352, 290)), fill=(0x3F, 0x7A, 0x4A))
	label(d, "BAYOU")


def mesa(d):
	d.polygon(p((120, 330), (150, 200), (230, 200), (250, 250), (330, 250), (360, 200), (392, 330)), fill=(0xB5, 0x4A, 0x2E))
	d.polygon(p((120, 330), (392, 330), (392, 350), (120, 350)), fill=(0x8A, 0x34, 0x20))
	d.ellipse(p((330, 120), (390, 180)), fill=AMBER)
	label(d, "RED MESA", size=40)


def cypress(d):
	d.polygon(p((256, 110), (190, 250), (322, 250)), fill=(0x4F, 0x8A, 0x5A))
	d.polygon(p((256, 170), (170, 310), (342, 310)), fill=(0x3F, 0x7A, 0x4A))
	d.polygon(p((226, 310), (286, 310), (310, 350), (202, 350)), fill=(0x7A, 0x52, 0x30))
	for x in (150, 190, 322, 362):
		d.polygon(p((x - 12, 350), (x, 322), (x + 12, 350)), fill=(0x7A, 0x52, 0x30))
	label(d, "BOG CYPRESS", size=36)


def ironwood(d):
	for r, c in ((130, (0x5E, 0x66, 0x70)), (100, (0x7C, 0x86, 0x92)), (70, (0x5E, 0x66, 0x70)), (40, (0x9A, 0xA4, 0xB0))):
		d.ellipse(p((256 - r, 250 - r), (256 + r, 250 + r)), fill=c)
	label(d, "IRONWOOD")


def firstbuild(d):
	d.rectangle(p((166, 230), (346, 340)), fill=(0xC9, 0xA2, 0x4A))
	d.polygon(p((146, 236), (256, 140), (366, 236)), fill=(0x9E, 0x3B, 0x2E))
	d.rectangle(p((236, 270), (276, 340)), fill=WALNUT)
	label(d, "FIRST BUILD", size=38)


def homestead(d):
	d.rectangle(p((146, 230), (326, 340)), fill=(0xC9, 0xA2, 0x4A))
	d.polygon(p((126, 236), (236, 140), (346, 236)), fill=(0x9E, 0x3B, 0x2E))
	d.rectangle(p((290, 150), (318, 210)), fill=(0x7A, 0x52, 0x30))
	d.rectangle(p((216, 270), (256, 340)), fill=WALNUT)
	d.ellipse(p((318, 280), (398, 360)), fill=AMBER)
	f = ImageFont.truetype(BOLD, 44 * S)
	d.text((332 * S, 292 * S), "40", font=f, fill=WALNUT)
	label(d, "HOMESTEAD", size=40)


def stonemason(d):
	d.rectangle(p((156, 250), (356, 340)), fill=(0xC8, 0x64, 0x3C))
	d.line(p((156, 295), (356, 295)), fill=(0x9A, 0x4A, 0x2A), width=6 * S)
	d.line(p((256, 250), (256, 295)), fill=(0x9A, 0x4A, 0x2A), width=6 * S)
	d.line(p((206, 295), (206, 340)), fill=(0x9A, 0x4A, 0x2A), width=6 * S)
	d.line(p((306, 295), (306, 340)), fill=(0x9A, 0x4A, 0x2A), width=6 * S)
	d.polygon(p((330, 150), (360, 170), (300, 246), (276, 226)), fill=(0x9A, 0xA4, 0xB0))
	d.rectangle(p((262, 226), (300, 252)), fill=(0x7A, 0x52, 0x30))
	label(d, "STONEMASON", size=38)


def millionaire(d):
	f = ImageFont.truetype(BOLD, 150 * S)
	text = "$1M"
	w = d.textbbox((0, 0), text, font=f)[2]
	d.text(((SIZE * S - w) / 2, 170 * S), text, font=f, fill=AMBER)
	label(d, "MILLIONAIRE", size=38)


ICONS = {
	"AreaBayou": bayou,
	"AreaMesa": mesa,
	"WoodCypress": cypress,
	"WoodIronwood": ironwood,
	"FirstBuild": firstbuild,
	"Homestead": homestead,
	"Stonemason": stonemason,
	"Millionaire": millionaire,
}


def main():
	os.makedirs(OUT, exist_ok=True)
	for key, draw in ICONS.items():
		im, d = base()
		draw(d)
		im = im.resize((SIZE, SIZE), Image.LANCZOS)
		im.save(os.path.join(OUT, key + ".png"))
	print("wrote", len(ICONS), "drafts to", OUT)


if __name__ == "__main__":
	main()
