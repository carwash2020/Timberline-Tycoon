#!/usr/bin/env python3
"""What's New card: computed layout diagram (NOT a screenshot).

Draws the viewport, the ScreenGui safe area and the card box from the same
numbers tests/GreyBox.spec.luau computes from NewsUI's properties (anchor
0.5,0.5, position 0.5,0,0.5,0, width 92% capped at 520, UIScale, rows).
Lune and the preview tooling cannot draw a live GUI.

  python3 tools/preview/whats_new_layout.py [outdir]   (default previews/whats-new)
"""
import sys

from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1] if len(sys.argv) > 1 else "previews/whats-new"
# name, file, viewport, insets (l, t, r, b), UIScale, card w px, card h px
CASES = [
    ("1920x1080 (PC / Xbox)", "whats-new-1920x1080", (1920, 1080), (0, 0, 0, 0), 1.25, 650.0, 623.8),
    ("667x375 (phone)", "whats-new-667x375", (667, 375), (0, 0, 0, 0), 0.7812, 406.2, 261.7),
    ("812x375 (notched phone)", "whats-new-812x375-notch", (812, 375), (44, 0, 44, 21), 0.7812, 406.2, 261.7),
]
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 16)
except OSError:
    font = ImageFont.load_default()

for name, fname, (vw, vh), (il, it, ir, ib), scale, cw, ch in CASES:
    k = min(1.0, 1100 / vw)
    pad = 60
    W, H = int(vw * k) + 2 * pad, int(vh * k) + 2 * pad + 40
    img = Image.new("RGB", (W, H), (245, 245, 245))
    d = ImageDraw.Draw(img)
    ox, oy = pad, pad + 20
    d.rectangle([ox, oy, ox + vw * k, oy + vh * k], fill=(120, 150, 110), outline=(0, 0, 0), width=2)
    d.rectangle(
        [ox + il * k, oy + it * k, ox + (vw - ir) * k, oy + (vh - ib) * k],
        outline=(30, 90, 200),
        width=2,
    )
    ax, ay = il + (vw - il - ir) / 2, it + (vh - it - ib) / 2
    left, top = ax - cw / 2, ay - ch / 2
    d.rectangle(
        [ox + left * k, oy + top * k, ox + (left + cw) * k, oy + (top + ch) * k],
        fill=(42, 31, 23),
        outline=(201, 162, 74),
        width=3,
    )
    d.line([ox + ax * k, oy, ox + ax * k, oy + vh * k], fill=(200, 50, 50))
    d.line([ox, oy + ay * k, ox + vw * k, oy + ay * k], fill=(200, 50, 50))
    d.text((ox, 8), f"COMPUTED layout, not a screenshot: {name}", fill=(0, 0, 0), font=font)
    d.text(
        (ox, oy + vh * k + 8),
        f"card {cw:.0f}x{ch:.0f} px at UIScale {scale}; top-left ({left:.1f}, {top:.1f}); "
        f"centre ({ax:.1f}, {ay:.1f}) = safe-area centre; blue = safe area, red = centre lines; no scrim",
        fill=(0, 0, 0),
        font=font,
    )
    img.save(f"{out}/{fname}.png")
