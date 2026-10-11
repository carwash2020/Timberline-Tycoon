#!/usr/bin/env python3
"""The first screen, before and after the first-screen UI fix (PART B 10 and 11).

COMPOSITES, not engine screenshots: the engine viewer cannot draw Roblox UI. Each
frame is hand-built with PIL from the same numbers the code uses (UITheme tokens
via v1u_round3, SaveSlotLogic.Panel / Layout, HUD and QuestUI sizes), over the
flat sky-and-grass backdrop the other UI composites use. Liberation Sans stands
in for Gotham and Fredoka. "before" frames are rebuilt from the OLD code's
numbers (360 x 360 panel, 148 px cards, the Unload / Save now row's empty gap,
the hint bar on a higher layer than the panel, BADGES under the tutorial card).
They show the layout bugs the code produces; they do not prove a pixel match
with Studio.

  python3 tools/preview/first_screen_ui.py   writes previews/fix-first-screen/*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_round3 as r  # noqa: E402

m = r.m
ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "fix-first-screen")

INK, BARK, CREAM, PAPER, PAPER_DARK = r.INK, r.BARK, r.CREAM_SKIN, r.PAPER, r.PAPER_DARK
GREEN_EDGE = r.GREEN_EDGE
UI_INK = (0x1E, 0x1B, 0x18)  # UITheme.Colors.Ink (the hint bar's solid fill)
UI_CREAM = (0xF3, 0xE7, 0xC9)
UI_BARK = (0x3E, 0x2E, 0x22)
AMBER = r.AMBER

WINDOWS = [(963, 478, 0.85), (667, 375, 0.78125)]  # (w, h, UIScale)
TOPBAR = 36

# SaveSlotLogic.Panel (the numbers the Lua uses)
P = dict(
	Width=360, Margin=12, NoteTop=48, NoteHeight=36, ControlsTop=90, ControlsHeight=48,
	SavedTop=142, SavedHeight=18, Card=94, CardGap=8, Pad=12, ButtonW=96, ButtonH=44,
	CardInset=8, NameTop=6, DetailTop=54, DetailHeight=34,
)


def layout(view_w, view_h, picking, count=3):
	width = max(0, min(P["Width"], view_w - 2 * P["Margin"]))
	rows_top = P["NoteTop"] + P["NoteHeight"] + 4 if picking else P["SavedTop"] + P["SavedHeight"] + 4
	content = count * P["Card"] + (count - 1) * P["CardGap"]
	want = rows_top + content + P["Pad"]
	height = max(min(want, view_h - 2 * P["Margin"]), rows_top + P["Card"] + P["Pad"])
	return width, height, rows_top, height - rows_top - P["Pad"], content


SLOTS = [
	("Save 1", "$12,480 · Rusty Axe · Plot, 41 pieces · 2h ago", True),
	("Save 2", "$3,205 · Steel Axe · No plot yet · 1d ago", False),
	("Save 3", "$890 · Rusty Axe · Plot, 6 pieces · 4d ago", False),
]


class Canvas:
	def __init__(self, w, h, s):
		self.w, self.h, self.s = w, h, s
		self.im = m.scene_backdrop(w, h)
		self.d = ImageDraw.Draw(self.im)

	def S(self, v):
		return int(round(v * self.s))

	def font(self, size, bold=True):
		return r.font(r.BOLD if bold else r.REG, max(8, self.S(size)))

	def topbar(self):
		self.d.rectangle((0, 0, self.w, TOPBAR), fill=(0x20, 0x20, 0x24))
		self.d.text((12, 10), "Roblox   chat", font=r.font(r.REG, 13), fill=(220, 220, 220))

	def cash(self):
		r.cash_plaque(self.im, self.w - 12, TOPBAR + 4, w=self.S(180))

	def button(self, x, y, w, h, label, style="bark", mark=None, fsize=13, text_left=None):
		"""A UITheme.Button at screen px (x, y), face w x h (offset sizes * scale)."""
		box = (x, y, x + w, y + h)
		r.button(self.im, box, "", style)
		d = ImageDraw.Draw(self.im)
		ink = r.STYLES[style][2]
		f = self.font(fsize)
		tw = r.text_w(d, label, f)
		th = d.textbbox((0, 0), label, font=f)[3]
		if mark:
			mx, msz = x + self.S(8), self.S(18)
			ty = y + (h - th) // 2 - 1
			self.mark(mx, y + (h - msz) // 2, msz, ink)
			if text_left == "after":
				left = x + self.S(34)  # HudLayout.MarkTextLeft, left-aligned
			else:
				# the old code: centred in the padded region
				region_l, region_r = x + self.S(34), x + w - self.S(6)
				left = region_l + (region_r - region_l - tw) // 2
			d.text((left, ty), label, font=f, fill=ink)
		else:
			d.text((x + (w - tw) // 2, y + (h - th) // 2 - 1), label, font=f, fill=ink)

	def mark(self, x, y, size, ink):
		k = size / 18
		d = self.d
		d.rounded_rectangle((x + 2 * k, y + 4 * k, x + 16 * k, y + 14 * k), radius=2, fill=ink)
		d.rounded_rectangle((x + 6 * k, y + 2 * k, x + 12 * k, y + 5 * k), radius=1, fill=ink)

	def side_column(self, saves_label_after, show_badges_left=None):
		bw, bh = self.S(110), self.S(40)
		right = self.w - self.S(12)
		bottom = int(self.h / 2 + self.S(60))
		self.button(right - bw, bottom - bh, bw, bh, "SAVES", "bark", mark=True, text_left="after" if saves_label_after else "before")
		self.button(right - bw, bottom - 2 * bh - self.S(8), bw, bh, "BUILD", "iconGreen", mark=True, text_left="after" if saves_label_after else "before")
		return (right - bw, bottom - bh, right, bottom)

	def left_column(self, badges):
		x, y = self.S(12), TOPBAR + 8
		self.button(x, y, self.S(130), self.S(44), "FIELD GUIDE", "bark", fsize=13)
		y += self.S(44) + self.S(6)
		cw = self.S(280)
		ch = self.S(86)
		r.plaque(self.im, (x, y, x + cw, y + ch))
		d = ImageDraw.Draw(self.im)
		d.text((x + self.S(12), y + self.S(8)), "TUTORIAL · 1/7", font=self.font(14), fill=BARK)
		d.text((x + self.S(12), y + self.S(34)), "Chop down a tree", font=self.font(15), fill=INK)
		d.text((x + self.S(12), y + self.S(56)), "Click a tree to swing", font=self.font(12, False), fill=INK)
		y += ch + self.S(6)
		if badges:
			self.button(x, y, self.S(100), self.S(44), "BADGES", "bark", fsize=15)
		return (x, y, x + cw, y + ch)

	def hint(self, text="Click a tree to swing  -  E to interact"):
		f = self.font(13, False)
		d = self.d
		tw = r.text_w(d, text, f)
		w = tw + self.S(28)
		h = self.S(30)
		x = (self.w - w) // 2
		y = self.h - self.S(64)
		d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=UI_INK)
		d.text((x + self.S(14), y + (h - 14) // 2 - 1), text, font=f, fill=UI_CREAM)
		return (x, y, x + w, y + h)

	def beacon(self, cx, cy):
		"""The tutorial beacon: amber arrow over a '20 studs' pill, 64 x 80 px."""
		d = self.d
		d.polygon([(cx - 22, cy - 40), (cx + 22, cy - 40), (cx, cy - 10)], fill=AMBER, outline=INK)
		f = r.font(r.BOLD, 14)
		text = "20 studs"
		tw = r.text_w(d, text, f)
		pw = tw + 16
		d.rounded_rectangle((cx - pw // 2, cy + 8, cx + pw // 2, cy + 28), radius=10, fill=UI_INK, outline=AMBER, width=2)
		d.text((cx - tw // 2, cy + 10), text, font=f, fill=UI_CREAM)
		return (cx - 32, cy - 40, cx + 32, cy + 40)

	def saves_panel(self, mode):
		"""mode 'before' (360 x 360, 148 px cards, the empty row) or 'after'."""
		view_w, view_h = self.w / self.s, (self.h - TOPBAR) / self.s
		if mode == "before":
			pw_, ph_, rows_top, rows_h, picking = 360, 360, 164, 360 - 164 - 12, True
			card_h, gap = 148, 8
		else:
			pw_, ph_, rows_top, rows_h, _ = layout(view_w, view_h, True)
			picking = True
			card_h, gap = P["Card"], P["CardGap"]
		x0 = (self.w - self.S(pw_)) // 2
		y0 = TOPBAR + (self.h - TOPBAR - self.S(ph_)) // 2
		box = (x0, y0, x0 + self.S(pw_), y0 + self.S(ph_))
		self.d.rounded_rectangle(box, radius=self.S(14), fill=PAPER, outline=BARK, width=3)
		d = self.d
		d.text((x0 + self.S(16), y0 + self.S(10)), "Saves", font=self.font(26), fill=INK)
		note = "Pick a save to play. If it has a plot, you choose where your base goes next."
		self.wrap(note, x0 + self.S(12), y0 + self.S(48), self.S(pw_ - 24), self.font(14, False))
		# rows window (clips like a ScrollingFrame)
		rt = y0 + self.S(rows_top)
		rb = rt + self.S(rows_h)
		clip = self.im.crop((0, 0, self.w, self.h))
		layer = Image.new("RGB", (self.w, self.h))
		layer.paste(self.im)
		ld = ImageDraw.Draw(layer)
		y = rt
		for i, (name, facts, active) in enumerate(SLOTS):
			ch = self.S(card_h)
			cx0, cx1 = x0 + self.S(12), x0 + self.S(pw_ - 12)
			ld.rounded_rectangle((cx0, y, cx1, y + ch), radius=self.S(10), fill=PAPER_DARK if active else PAPER, outline=GREEN_EDGE if active else BARK, width=2)
			if mode == "before":
				ld.rounded_rectangle((cx0 + self.S(8), y + self.S(6), cx1 - self.S(8), y + self.S(50)), radius=8, fill=UI_CREAM)
				ld.text((cx0 + self.S(16), y + self.S(18)), name, font=self.font(16), fill=INK)
				ld.text((cx0 + self.S(8), y + self.S(52)), (("Last played  ·  " if active else "") + facts)[:48], font=self.font(13, False), fill=INK)
				bx0 = cx0 + self.S(8)
				by0 = y + self.S(98)
				layer_im = layer
				r.button(layer_im, (bx0, by0, bx0 + self.S(96), by0 + self.S(44)), "PLAY", "confirm", fnt=self.font(15))
			else:
				nw = (cx1 - cx0) - self.S(8 * 3 + P["ButtonW"])
				ld.rounded_rectangle((cx0 + self.S(8), y + self.S(6), cx0 + self.S(8) + nw, y + self.S(6 + 44)), radius=8, fill=UI_CREAM)
				ld.text((cx0 + self.S(16), y + self.S(18)), name, font=self.font(16), fill=INK)
				self.wrap(("Last played  ·  " if active else "") + facts, cx0 + self.S(8), y + self.S(P["DetailTop"]), cx1 - cx0 - self.S(16), self.font(13, False), im=layer)
				bx1 = cx1 - self.S(8)
				r.button(layer, (bx1 - self.S(96), y + self.S(6), bx1, y + self.S(6 + 44)), "PLAY", "confirm", fnt=self.font(15))
			y += ch + self.S(gap)
		# clip: anything below rb is the panel again (the scroll window's edge)
		mask_top = Image.new("L", (self.w, self.h), 0)
		ImageDraw.Draw(mask_top).rectangle((x0, rt, x0 + self.S(pw_), rb), fill=255)
		self.im.paste(layer, (0, 0), mask_top)
		self.d = ImageDraw.Draw(self.im)
		# bits of the cards that the window cut off: tell the reader
		return box

	def wrap(self, text, x, y, width, f, im=None):
		d = ImageDraw.Draw(im or self.im)
		line = ""
		for word in text.split(" "):
			t = (line + " " + word).strip()
			if r.text_w(d, t, f) > width and line:
				d.text((x, y), line, font=f, fill=INK)
				y += int(f.size * 1.2)
				line = word
			else:
				line = t
		d.text((x, y), line, font=f, fill=INK)


def caption(im, text):
	d = ImageDraw.Draw(im)
	f = r.font(r.REG, 11)
	d.rectangle((0, im.size[1] - 16, im.size[0], im.size[1]), fill=(0, 0, 0))
	d.text((6, im.size[1] - 14), text, font=f, fill=(255, 255, 255))


def frame(w, h, s, mode):
	c = Canvas(w, h, s)
	c.topbar()
	c.cash()
	if mode == "before-pick":
		c.left_column(badges=True)
		c.side_column(False)
		c.beacon(w - c.S(12) - c.S(55), h // 2 + c.S(40))  # under SAVES
		c.saves_panel("before")
		c.hint()  # drawn after: the HUD layer is above the panel
		caption(c.im, f"BEFORE (composite of the old layout), {w}x{h}: hint bar over the panel, empty gap above Save 1, 2nd card cut, BADGES under the tutorial card, beacon pill behind SAVES")
	elif mode == "after-pick":
		c.side_column(True)
		c.saves_panel("after")
		caption(c.im, f"AFTER (composite), {w}x{h}: picker with 3 cards visible and PLAY reachable, no gap, hint bar and tutorial held back until the pick")
	elif mode == "after-play":
		c.left_column(badges=False)
		sv = c.side_column(True)
		obstacle = (sv[0] - 8, sv[1] - 8, sv[2] + 8, sv[3] + 8)
		c.beacon(sv[0] - 70, (sv[1] + sv[3]) // 2 + 10)  # slid left by HudLayout.ClearOfRects
		c.hint()
		caption(c.im, f"AFTER (composite), {w}x{h}: after the pick the tutorial starts; no BADGES button over it; beacon slides clear of SAVES; hint bar back")
	elif mode == "before-play":
		c.left_column(badges=True)
		c.side_column(False)
		c.beacon(w - c.S(12) - c.S(55), h // 2 + c.S(40))
		c.hint()
		caption(c.im, f"BEFORE (composite), {w}x{h}: the same HUD without the panel; BADGES under the tutorial card, beacon pill behind SAVES")
	return c.im


def zoom(im, box, factor, label):
	crop = im.crop(box).resize(((box[2] - box[0]) * factor, (box[3] - box[1]) * factor), Image.LANCZOS)
	d = ImageDraw.Draw(crop)
	d.rectangle((0, 0, crop.size[0], 16), fill=(0, 0, 0))
	d.text((4, 2), label, font=r.font(r.REG, 11), fill=(255, 255, 255))
	return crop


def markers():
	"""SELL LOGS before (ink rim on a bark face) and after (cream rim), over forest."""
	w, h = 520, 150
	im = Image.new("RGB", (w, h), (0x1F, 0x3A, 0x22))
	d = ImageDraw.Draw(im)
	for i, (rim, label) in enumerate(((UI_INK, "before: ink rim"), (UI_CREAM, "after: cream rim"))):
		x0 = 20 + i * 250
		d.rounded_rectangle((x0, 40, x0 + 200, 40 + 52), radius=14, fill=UI_INK)
		d.rounded_rectangle((x0, 40, x0 + 200, 40 + 46), radius=14, fill=UI_BARK, outline=rim, width=2)
		d.rounded_rectangle((x0 + 6, 46, x0 + 40, 80), radius=8, fill=(0x4C, 0xC3, 0x6A), outline=UI_CREAM, width=2)
		d.text((x0 + 52, 52), "SELL LOGS", font=r.font(r.BOLD, 22), fill=UI_CREAM)
		d.text((x0, 110), label, font=r.font(r.REG, 13), fill=(255, 255, 255))
	caption(im, "SELL LOGS marker over dark forest (composite of the markers' tokens)")
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	for w, h, s in WINDOWS:
		tag = f"{w}x{h}"
		for mode in ("before-pick", "after-pick", "before-play", "after-play"):
			im = frame(w, h, s, mode)
			im.save(os.path.join(OUT, f"{mode}-{tag}.png"))
		# close-ups (x3): the picker, and the SAVES button with its beacon
		after = Image.open(os.path.join(OUT, f"after-pick-{tag}.png"))
		before = Image.open(os.path.join(OUT, f"before-pick-{tag}.png"))
		cx0, cx1 = w // 2 - 190, w // 2 + 190
		zoom(before, (cx0, TOPBAR, cx1, h), 2, f"before {tag}: panel close-up").save(os.path.join(OUT, f"closeup-before-picker-{tag}.png"))
		zoom(after, (cx0, TOPBAR, cx1, h), 2, f"after {tag}: panel close-up").save(os.path.join(OUT, f"closeup-after-picker-{tag}.png"))
		play_b = Image.open(os.path.join(OUT, f"before-play-{tag}.png"))
		play_a = Image.open(os.path.join(OUT, f"after-play-{tag}.png"))
		box = (w - 230, h // 2 - 120, w, h // 2 + 100)
		zoom(play_b, box, 3, f"before {tag}: SAVES and beacon").save(os.path.join(OUT, f"closeup-before-saves-{tag}.png"))
		zoom(play_a, box, 3, f"after {tag}: SAVES and beacon").save(os.path.join(OUT, f"closeup-after-saves-{tag}.png"))
	markers().save(os.path.join(OUT, "markers-sell-logs.png"))
	print("wrote", OUT)


if __name__ == "__main__":
	main()
