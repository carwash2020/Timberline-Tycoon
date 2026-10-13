#!/usr/bin/env python3
"""Every vehicle, from every side, with the real meshes: the renders behind
previews/vehicles-fixed (before-*.png, after-*.png, contact-sheet.png).

    python3 tools/preview/vehicle_shots.py shots after vehicles-solo
    python3 tools/preview/vehicle_shots.py dealer after
    python3 tools/preview/vehicle_shots.py sheet after previews/vehicles-fixed/contact-sheet.png

  shots <prefix> <scene>   export the scene (tools/preview/scenes/<scene>.luau), render EVERY
                           view in one browser run, name each file
                           <prefix>-<scene>-<view>-<label>.png in previews/vehicles-fixed.
                           Scenes: vehicles-solo (6 trucks x 10 views), vehicles-rigs (every truck
                           with every trailer, 6 views), vehicles-partbuilt (no mesh, the
                           fallback look), vehicles-partrigs (part-built trailers).
  dealer <prefix>          the Dealership's display copies, one at a time (the others are dropped so
                           no bay blocks the camera): DEALER_ONLY in vehicles-dealership.luau.
  sheet <prefix> <out>     a contact sheet of every <prefix> image, one row a vehicle.

Needs Node and Playwright (see tools/preview/shoot.sh) and Pillow for the sheet. Run from the repo
root. 1280x800 a view; a scene of 60 views takes about 7 minutes on 4 cores.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shutil
import subprocess
import sys

OUT = "previews/vehicles-fixed"
RENDER_HOME = os.path.expanduser(os.environ.get("RENDER_HOME", "~/.cache/timberline-render"))
DEALER = [
    "Truck:Rustbucket",
    "Truck:Pickup",
    "Truck:ScoutATV",
    "Truck:Flatbed",
    "Truck:LoggingRig",
    "Trailer:PonyTrailer",
    "Trailer:RanchTrailer",
    "Trailer:HeavyHauler",
]
SCENES = ["vehicles-solo", "vehicles-rigs", "vehicles-dealership", "vehicles-partbuilt", "vehicles-partrigs"]


def shots(prefix: str, scene: str) -> None:
    root = os.getcwd()
    # shoot.sh exports the scene when it is stale and sets the renderer up; view 1 is a cheap way to run it.
    subprocess.run(["bash", "tools/preview/shoot.sh", scene, "1"], check=True, capture_output=True)
    html = open(f"preview/{scene}.html").read()
    cams = json.loads(re.search(r'<script type="application/json" id="scene">(.*?)</script>', html, re.S).group(1))["cameras"]
    os.makedirs(OUT, exist_ok=True)
    shutil.copy("tools/preview/render.mjs", f"{RENDER_HOME}/render.mjs")
    env = dict(os.environ, THREE_DIR=f"{RENDER_HOME}/node_modules/three")
    subprocess.run(
        ["node", f"{RENDER_HOME}/render.mjs", f"{root}/preview/{scene}.html", "", "1280x800"],
        env=env,
        capture_output=True,
        text=True,
    )
    for i, cam in enumerate(cams, 1):
        label = re.sub(r"[^A-Za-z0-9+]+", "-", cam["label"]).strip("-").lower()
        src = f"preview/{scene}-{i}.png"
        if os.path.exists(src):
            shutil.move(src, f"{OUT}/{prefix}-{scene}-{i:03d}-{label}.png")
        else:
            print("missing view", i, label)
    print(scene, len(cams), "views")


def dealer(prefix: str) -> None:
    for old in glob.glob(f"{OUT}/{prefix}-vehicles-dealership-*.png"):
        os.remove(old)
    for item in DEALER:
        env = dict(os.environ, DEALER_ONLY=item)
        subprocess.run(["lune", "run", "tools/preview/export", "vehicles-dealership"], env=env, check=True, capture_output=True)
        shots(prefix, "vehicles-dealership")


def sheet(prefix: str, out: str) -> None:
    from PIL import Image, ImageDraw

    w, h, label_w = 256, 160, 230
    rows = []
    for scene in SCENES:
        groups: dict[str, list[str]] = {}
        for f in sorted(glob.glob(f"{OUT}/{prefix}-{scene}-*.png")):
            name = re.match(rf".*/{prefix}-{scene}-\d+-(.*)\.png", f).group(1)
            if name.startswith("dealership"):
                key = "-".join(name.split("-")[:2])
            else:
                key = re.split(r"-(?:front|left|right|three|low|rear|near|wheel|trailer)", name)[0]
            groups.setdefault(key, []).append(f)
        rows += [(f"{scene.replace('vehicles-', '')}: {k}", v) for k, v in groups.items()]
    cols = max(len(v) for _, v in rows)
    img = Image.new("RGB", (label_w + cols * w, len(rows) * h), "white")
    draw = ImageDraw.Draw(img)
    for r, (label, files) in enumerate(rows):
        draw.text((6, r * h + 6), label, fill="black")
        for c, f in enumerate(files):
            img.paste(Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS), (label_w + c * w, r * h))
    img.save(out, optimize=True)
    print(out, len(rows), "rows")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "shots" and len(sys.argv) == 4:
        shots(sys.argv[2], sys.argv[3])
    elif cmd == "dealer" and len(sys.argv) == 3:
        dealer(sys.argv[2])
    elif cmd == "sheet" and len(sys.argv) == 4:
        sheet(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(2)
