#!/usr/bin/env python3
"""V1 hardening (moderation): Settings > Visitors kick / ban / unban and the
REPORT tab, hand-built from the same tokens as UITheme (the GAD plaque and
button skins from v1u_round3) and SettingsUI's own numbers: a 280 x 300 card,
8 px padding, 6 px gaps, 248 x 44 rows (taps are 44 or more), 14 px labels
(18 on a TV). Liberation Sans stands in for Gotham. These are composites of
the layout, not engine screenshots.

  python3 tools/preview/v1_mod_ui.py   writes previews/v1-hardening-mod/*.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v1u_round3 as r  # noqa: E402

# UITheme styles the Settings rows use that round 3 did not draw: buy is the
# green confirm button, skip the muted grey one.
r.STYLES.setdefault("buy", r.STYLES["confirm"])
r.STYLES.setdefault("skip", r.STYLES["muted"])

ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "previews", "v1-hardening-mod")
m = r.m

CARD_W, CARD_H = 280, 300
PAD, GAP, ROW_W, ROW_H = 8, 6, 248, 44


def rows_visitors():
	flags = ["Visit", "Sit", "Collisions", "Build", "Destroy", "Grab", "Interact", "Drive", "Save items"]
	on = {"Visit": True, "Collisions": True}
	out = [
		("tab", "GAME", "skip"),
		("tab", "VISITORS", "buy"),
		("tab", "LEADERBOARD", "skip"),
		("tab", "REPORT", "skip"),
		("head", "VISIT A PLOT"),
		("btn", "Visit Ann", "buy"),
		("btn", "Anyone", "skip"),
		("btn", "Ann", "skip"),
		("btn", "Bob  ·", "bark"),
	]
	for f in flags:
		out.append(("btn", f"{f}: {'ON' if on.get(f) else 'OFF'}", "buy" if on.get(f) else "skip"))
	out += [
		("head", "THIS PLAYER, ON YOUR PLOT"),
		("btn", "Kick from my plot", "skip"),
		("btn", "Ban from my plot", "skip", "sel"),
		("head", "BANNED FROM YOUR PLOT"),
		("btn", "Unban Zed_99", "skip"),
	]
	return out


def rows_ban_armed():
	rows = rows_visitors()
	return [(("btn", "Tap again: ban from my plot", "buy", "sel") if x[1] == "Ban from my plot" else x) for x in rows]


def rows_report_pick():
	return [
		("tab", "GAME", "skip"),
		("tab", "VISITORS", "skip"),
		("tab", "LEADERBOARD", "skip"),
		("tab", "REPORT", "buy"),
		("head", "REPORT A PLAYER"),
		("text", "Who are you reporting?"),
		("btn", "Bob", "skip", "sel"),
		("btn", "Cat", "skip"),
		("btn", "Dan", "skip"),
	]


def rows_report_reason():
	out = [
		("tab", "GAME", "skip"),
		("tab", "VISITORS", "skip"),
		("tab", "LEADERBOARD", "skip"),
		("tab", "REPORT", "buy"),
		("head", "REPORT A PLAYER"),
		("text2", "Why report Bob?"),
	]
	for i, label in enumerate(
		["Bad language", "Bullying", "Bad username", "Scamming", "Cheating", "Links to other sites", "Asking personal things", "Dating"]
	):
		out.append(("btn", label, "skip", "sel" if i == 0 else ""))
	out.append(("btn", "Pick someone else", "bark"))
	return out


def rows_report_sent():
	return [
		("tab", "GAME", "skip"),
		("tab", "VISITORS", "skip"),
		("tab", "LEADERBOARD", "skip"),
		("tab", "REPORT", "buy"),
		("head", "REPORT A PLAYER"),
		("text2", "Report sent to Roblox. Thank you."),
		("text", "Who are you reporting?"),
		("btn", "Bob", "skip", "sel"),
		("btn", "Cat", "skip"),
	]


def layout(rows):
	"""(y of each row, total height) in the scroll content."""
	y = PAD + 18 + GAP
	ys = []
	for x in rows:
		ys.append(y)
		y += {"head": 18, "text": 18, "text2": 36}.get(x[0], ROW_H) + GAP
	return ys, y + PAD


def card_image(rows, anchor=None, title="SETTINGS", h=CARD_H):
	"""The card face: plaque, title, rows scrolled so `anchor` (a row's text)
	is at the top, a scrollbar. Transparent outside the plaque."""
	ys, full = layout(rows)
	scroll = 0
	if anchor is not None:
		for x, y in zip(rows, ys):
			if x[1] == anchor:
				scroll = max(0, min(y - PAD, max(full - h, 0)))
	H = max(full, h)
	tall = Image.new("RGBA", (CARD_W, H + 6), (0, 0, 0, 0))
	rgb = Image.new("RGB", (CARD_W, H + 6), (0, 0, 0))
	r.plaque(rgb, (0, 0, CARD_W - 1, H))
	d = ImageDraw.Draw(rgb)
	d.text((PAD, PAD), title, font=r.font(r.BOLD, 14), fill=r.BARK)
	for x, y in zip(rows, ys):
		kind = x[0]
		if kind in ("head", "text", "text2"):
			col = r.BARK if kind == "head" else r.INK
			d.text((PAD, y), x[1], font=r.font(r.BOLD, 14), fill=col)
		else:
			label, style = x[1], x[2]
			selected = len(x) > 3 and x[3] == "sel"
			r.button(rgb, (PAD, y, PAD + ROW_W, y + ROW_H), label, style, fnt=r.font(r.BOLD, 15), selected=selected)
	mask = Image.new("L", rgb.size, 0)
	ImageDraw.Draw(mask).rounded_rectangle((0, 0, CARD_W - 1, H + 3), radius=14, fill=255)
	tall.paste(rgb, (0, 0), mask)
	view = tall.crop((0, scroll, CARD_W, scroll + h + 6))
	if full > h:
		bar_h = max(30, int((h - 16) * h / full))
		bar_y = int((h - 16 - bar_h) * (scroll / max(full - h, 1)))
		ImageDraw.Draw(view).rounded_rectangle((CARD_W - 12, 8 + bar_y, CARD_W - 7, 8 + bar_y + bar_h), radius=3, fill=r.BARK)
	return view, full


def scene(w, h, phone, rows, anchor, caption_text):
	im = m.scene_backdrop(w, h)
	card, full = card_image(rows, anchor)
	if phone:
		im.paste(card, ((w - CARD_W) // 2, 20), card)
		m.phone_zones(im)
	else:
		big = card.resize((card.width * 2, card.height * 2), Image.LANCZOS)
		im.paste(big, ((w - big.width) // 2, 120), big)
	d = ImageDraw.Draw(im)
	f = r.font(r.REG, 10 if phone else 16)
	ty = h - 22 if phone else h - 34
	d.rectangle((0, ty - 4, d.textbbox((0, 0), caption_text, font=f)[2] + 24, h), fill=(0, 0, 0))
	d.text((12, ty), caption_text, font=f, fill=(255, 255, 255))
	return im


def main():
	os.makedirs(OUT, exist_ok=True)
	shots = {
		"visitors-moderation": (rows_visitors(), "THIS PLAYER, ON YOUR PLOT", "Settings > Visitors: THIS PLAYER, ON YOUR PLOT (Kick, Ban) and BANNED list with Unban; every button 44 tall"),
		"visitors-ban-armed": (rows_ban_armed(), "THIS PLAYER, ON YOUR PLOT", "Ban asks for a second tap (the label changes, the selection ring is on it)"),
		"report-pick": (rows_report_pick(), "REPORT A PLAYER", "REPORT tab: pick who (hidden where the report call is unavailable or nobody else is here)"),
		"report-reason": (rows_report_reason(), "REPORT A PLAYER", "REPORT tab: pick a reason, Roblox's own report goes out; Pick someone else steps back"),
		"report-sent": (rows_report_sent(), "REPORT A PLAYER", "REPORT tab after sending: one confirmation line, the list again"),
	}
	for name, (rows, anchor, cap) in shots.items():
		for phone, (w, h) in ((True, (667, 375)), (False, (1920, 1080))):
			tag = "phone" if phone else "pc"
			im = scene(w, h, phone, rows, anchor, f"{'Phone 667x375' if phone else 'PC 1920x1080'}: {cap}")
			im.save(os.path.join(OUT, f"{name}-{tag}.png"))
	# The whole lists, uncropped, to check every row and gap.
	for name, rows in (("visitors", rows_visitors()), ("report-reason", rows_report_reason())):
		card, _ = card_image(rows, None, h=layout(rows)[1])
		card.save(os.path.join(OUT, f"{name}-full-list.png"))
	print("wrote", sorted(os.listdir(OUT)))


def full_height(rows):
	full = PAD + 18 + GAP
	for x in rows:
		full += {"head": 18, "text": 18, "text2": 36}.get(x[0], ROW_H) + GAP
	return full + PAD


if __name__ == "__main__":
	main()
