#!/usr/bin/env python3
"""Lay rendered tiles out as labelled contact sheets.

    python3 tools/blender/contact_sheet.py <tiles dir> <out dir> [columns]

Tiles are named <group>__<Name>.png (render_tiles.py). One sheet per group,
<out dir>/<group>.png, each tile labelled with its name under it.
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def font(size: int):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main() -> int:
    tiles, out = Path(sys.argv[1]), Path(sys.argv[2])
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    out.mkdir(parents=True, exist_ok=True)
    groups: dict[str, list[Path]] = defaultdict(list)
    for tile in sorted(tiles.glob("*.png")):
        group = tile.stem.split("__")[0]
        groups[group].append(tile)
    label_font, title_font = font(20), font(30)
    for group, files in sorted(groups.items()):
        size = Image.open(files[0]).size[0]
        rows = (len(files) + cols - 1) // cols
        label_h, title_h, pad = 34, 56, 8
        sheet = Image.new(
            "RGB", (cols * (size + pad) + pad, title_h + rows * (size + label_h + pad) + pad), (40, 36, 32)
        )
        draw = ImageDraw.Draw(sheet)
        draw.text((pad + 4, 12), f"{group}  ({len(files)})", fill=(243, 231, 201), font=title_font)
        for i, f in enumerate(files):
            r, c = divmod(i, cols)
            x = pad + c * (size + pad)
            y = title_h + r * (size + label_h + pad)
            sheet.paste(Image.open(f).convert("RGB"), (x, y))
            draw.text((x + 4, y + size + 6), f.stem.split("__", 1)[1], fill=(243, 231, 201), font=label_font)
        sheet.save(out / f"{group}.png", optimize=True)
        print(out / f"{group}.png", sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
