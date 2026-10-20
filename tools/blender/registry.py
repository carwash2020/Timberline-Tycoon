#!/usr/bin/env python3
"""Rebuild the Blender asset registry and the upload list from the GLBs.

    python3 tools/blender/registry.py [backlog.json]

Writes src/ReplicatedStorage/Shared/Art/BlenderAssets.luau and
assets/UPLOAD_LIST.md. Deterministic: rows are sorted, numbers rounded, so a
rerun on the same files gives the same output (the spec and CI read only the
Luau). Run `stylua` on the Luau afterwards (the check script does).

Rows:
  repo     a model whose GLB is in assets/meshes. Its live mesh ids are in the
           module named in wiredBy; the registry meshId stays 0 (no override).
  backlog  uploaded in the Blender backlog (2026-10-08) and wired by job 17
           (BacklogModels). meshId is its main piece's uploaded id.
  wired    a backlog row its builder dresses itself (BUILDER_WIRED below);
           same id as backlog, but wiredBy names the builder module.
  planned  on Lane H's list with no model yet. Nothing is uploaded and the
           part-built model stays. Listed in UPLOAD_LIST.md.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glbstats import stats  # noqa: E402

MESHES = Path("assets/meshes")
OUT_LUAU = Path("src/ReplicatedStorage/Shared/Art/BlenderAssets.luau")
OUT_LIST = Path("assets/UPLOAD_LIST.md")

WIRED = {
    "axes": "AxeModels",
    "buildings": "TownModels",
    "environment": "TownModels",
    "npcs": "TownModels",
    "items": "ItemMeshData",
    "kit": "KitMeshData",
    "rocks": "RockModels",
    "trees": "TreeModels",
    "vehicles": "VehicleModels",
}

# Lane H's asset order that the Blender backlog covers (job 17 wires them).
BACKLOG = {
    "shops": ["OddsAndEnds", "Sparkworks", "SkyForgeCourt", "GateKiosk", "ArrivalArch"],
    "gear": ["HermitsMaul"],
    "plants": [
        "Fern", "Flowers", "Mushroom", "Reeds", "SnowShrub", "AshShrub", "GloamCap",
        "IsleCrystal", "BerryBush", "Cattails", "LilyPad", "GrassTuft", "Bush",
    ],
}

# Backlog rows a builder dresses itself (TownMeshes.Dress in BuildingArt).
BUILDER_WIRED = {"shops/SkyForgeCourt": "BuildingArt"}

# On Lane H's list, no model anywhere yet. (name, group, collision, why)
PLANNED = [
    ("CliffFaceA", "cliffs", "Hull", "cliff face that dresses Lane B's terrain mountains"),
    ("CliffFaceB", "cliffs", "Hull", "second cliff face, taller and narrower"),
    ("ShopShelf", "shopfit", "Box", "stepped shop shelf (part-built by D today)"),
    ("ShopCounter", "shopfit", "Box", "shop counter (part-built by D today)"),
    ("TemperTrimKeen", "axes", "Box", "Keen temper trim (TemperLook colours the part trim today)"),
    ("TemperTrimHeavy", "axes", "Box", "Heavy temper trim"),
    ("TemperTrimProsperous", "axes", "Box", "Prosperous temper trim"),
]


# Store item models, joined into one mesh with one baked 1024px colour texture
# (emissive parts baked bright; there is no glow slot). Uploaded 13 Oct 2026.
# (name, meshId, colour texture id, wiredBy, what it is for)
STORE = [
    ("Flashlight", 104730694619580, 110889000263791, "ModelSlots", "Flashlight store item; replaces the old Flashlight"),
    ("Lantern", 100706399609275, 103276353286757, "ModelSlots", "Lantern store item; replaces environment/Lantern"),
    ("WoodSign", 104427150009380, 115661985339638, "ModelSlots", "WoodSign store item; replaces items/WoodSign"),
    ("ShedBlueprint", 117955534652171, 88429889818385, "ModelSlots", "Shed Blueprint; replaces Small Shed (items/Shed)"),
    ("Barrel", 103482280552543, 101451260913674, "StoreModelSlots", "Barrel store item"),
    ("Crate", 100788396065808, 78298003526634, "StoreModelSlots", "Crate store item"),
    ("GlowWire", 140023205654551, 139395535150744, "StoreModelSlots", "GlowWire store item"),
    ("SkyBin", 136000065218099, 130081290755053, "StoreModelSlots", "SkyBin store item"),
    ("RobuxCoins", 76084140639988, 140571825691428, "StoreModelSlots", "Robux box display"),
    ("Parcel", 106272982653382, 106468421600012, "StoreModelSlots", "fallback for any item without a model"),
]


def store_rows() -> list[dict]:
    rows = []
    for name, mesh_id, tex_id, wired, why in STORE:
        glb = Path(f"assets/glb/store-items/{name}.glb")
        s = stats(glb)
        rows.append(
            {
                "key": f"store/{name}",
                "group": "store",
                "file": glb.as_posix(),
                "files": 1,
                "tris": s["tris"],
                "size": s["size"],
                "collision": collision_for("store", s["size"]),
                "meshId": mesh_id,
                "textures": {"Color": tex_id},
                "status": "store",
                "wiredBy": wired,
                "why": why,
            }
        )
    return rows


def collision_for(group: str, size: list[float]) -> str:
    if group in ("buildings", "vehicles", "trees", "shops"):
        return "Parts"
    if group in ("npcs", "axes", "gear"):
        return "Box"
    biggest = max(size) if size else 0
    if biggest <= 4:
        return "Box"
    if biggest >= 20:
        return "Parts"
    return "Hull"


def num(v: float) -> str:
    text = f"{v:.3f}".rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


def repo_rows() -> list[dict]:
    rows = []
    for group_dir in sorted(p for p in MESHES.iterdir() if p.is_dir()):
        group = group_dir.name
        for asset_dir in sorted(p for p in group_dir.iterdir() if p.is_dir()):
            glbs = sorted(asset_dir.glob("*.glb"))
            if not glbs:
                continue
            main = asset_dir / f"{asset_dir.name}.glb"
            if not main.is_file():
                main = glbs[0]
            tris = 0
            size = [0.0, 0.0, 0.0]
            for g in glbs:
                s = stats(g)
                tris += s["tris"]
                size = [max(size[k], s["size"][k]) for k in range(3)]
            rows.append(
                {
                    "key": f"{group}/{asset_dir.name}",
                    "group": group,
                    "file": main.as_posix(),
                    "files": len(glbs),
                    "tris": tris,
                    "size": size,
                    "collision": collision_for(group, size),
                    "meshId": 0,
                    "status": "repo",
                    "wiredBy": WIRED.get(group, "?"),
                }
            )
    return rows


def backlog_rows(backlog_json: Path, pack_models: Path) -> list[dict]:
    data = json.loads(backlog_json.read_text())
    rows = []
    for category, names in BACKLOG.items():
        for name in names:
            row = data[category][name]
            pieces = row["pieces"]
            main_piece = pieces.get("Body") or pieces.get("Handle") or next(iter(pieces.values()))
            mesh_id = int(str(main_piece["meshId"]).split("//")[-1])
            glb = pack_models / category / name / f"{name}.glb"
            s = stats(glb)
            rows.append(
                {
                    "key": f"{category}/{name}",
                    "group": category,
                    "file": f"assets/meshes/{category}/{name}/{name}.glb",
                    "files": 1,
                    "tris": s["tris"],
                    "size": s["size"],
                    "collision": collision_for(category, s["size"]),
                    "meshId": mesh_id,
                    "status": "wired" if f"{category}/{name}" in BUILDER_WIRED else "backlog",
                    "wiredBy": BUILDER_WIRED.get(f"{category}/{name}", "BacklogModels"),
                }
            )
    return rows


def planned_rows() -> list[dict]:
    return [
        {
            "key": f"{group}/{name}",
            "group": group,
            "file": "",
            "files": 0,
            "tris": 0,
            "size": [0.0, 0.0, 0.0],
            "collision": collision,
            "meshId": 0,
            "status": "planned",
            "wiredBy": "",
            "why": why,
        }
        for name, group, collision, why in PLANNED
    ]


HEADER = """--!strict
-- BlenderAssets: the registry of every Blender-made model (Lane H). Pure
-- data, generated by tools/blender/registry.py from the GLBs in
-- assets/meshes and the Blender backlog list; do not edit rows by hand.
--
-- status
--   repo     the GLB is in assets/meshes. Its live mesh ids live in the
--            module named in wiredBy (TownModels, AxeModels, ...). meshId
--            here is 0: the registry never overrides those modules.
--   backlog  uploaded with the Blender backlog (8 Oct 2026, Approved) and
--            wired by BacklogModels (job 17). meshId is its main piece.
--   wired    uploaded with the backlog and dressed by its own builder
--            (BuildingArt calls TownMeshes.Dress; BacklogModels.Wired lists
--            it for the preload). meshId is its main piece; MeshIds() skips it.
--   store    a store item model (one mesh, one baked colour texture in
--            textures.Color), uploaded 13 Oct 2026. meshId is the live id.
--   planned  on Lane H's list with no model yet (assets/UPLOAD_LIST.md).
--            Nothing is uploaded; the part-built model stays.
--
-- size is the whole model's bounds in studs (1 Blender unit = 1 stud), tris
-- every triangle in its GLB(s). collision is the intent: Box for small
-- props, Hull for medium ones, Parts (invisible part collision) for big
-- buildings, vehicles and trees. Textures are vertex colours today, so
-- every textures table is empty and any texture id is 0, except store rows
-- (one baked colour texture). Store rows mirror ModelSlots / StoreModelSlots,
-- which preload them, so MeshIds() skips them.
-- MeshManifest preloads MeshIds() (none of status repo or planned, so
-- nothing changes in game while those ids are 0).

local BlenderAssets = {}

export type Collision = "Box" | "Hull" | "Parts"
export type Status = "repo" | "backlog" | "wired" | "store" | "planned"

export type Entry = {
\tname: string,
\tgroup: string,
\tfile: string,
\ttris: number,
\tsize: Vector3,
\tcollision: Collision,
\tmeshId: number,
\ttextures: { [string]: number },
\tstatus: Status,
\twiredBy: string,
}

BlenderAssets.MaxTris = 20000

local function V(x: number, y: number, z: number): Vector3
\treturn Vector3.new(x, y, z)
end

local ROWS: { Entry } = {
"""

FOOTER = """}

local BY_NAME: { [string]: Entry } = {}
for _, entry in ipairs(ROWS) do
\tBY_NAME[entry.name] = entry
end

BlenderAssets.All = ROWS

-- The entry for "<group>/<Name>" (for example "buildings/Sawmill"), or nil.
function BlenderAssets.Get(name: string): Entry?
\treturn BY_NAME[name]
end

function BlenderAssets.Names(status: Status?): { string }
\tlocal out: { string } = {}
\tfor _, entry in ipairs(ROWS) do
\t\tif status == nil or entry.status == status then
\t\t\ttable.insert(out, entry.name)
\t\tend
\tend
\treturn out
end

-- Every non-zero meshId the registry itself supplies, for MeshKit.Preload.
function BlenderAssets.MeshIds(): { number }
\tlocal out: { number } = {}
\tlocal seen: { [number]: boolean } = {}
\tfor _, entry in ipairs(ROWS) do
\t\tif entry.status ~= "backlog" and entry.status ~= "wired" and entry.status ~= "store" and entry.meshId ~= 0 and not seen[entry.meshId] then
\t\t\tseen[entry.meshId] = true
\t\t\ttable.insert(out, entry.meshId)
\t\tend
\tend
\treturn out
end

return BlenderAssets
"""


def luau(rows: list[dict]) -> str:
    body = []
    for r in rows:
        sx, sy, sz = (num(v) for v in r["size"])
        body.append(
            "\t{\n"
            f'\t\tname = "{r["key"]}",\n'
            f'\t\tgroup = "{r["group"]}",\n'
            f'\t\tfile = "{r["file"]}",\n'
            f"\t\ttris = {r['tris']},\n"
            f"\t\tsize = V({sx}, {sy}, {sz}),\n"
            f'\t\tcollision = "{r["collision"]}",\n'
            f"\t\tmeshId = {r['meshId']},\n"
            "\t\ttextures = {" + "".join(f" {k} = {v}," for k, v in sorted(r.get("textures", {}).items())).rstrip(",") + (" }" if r.get("textures") else "}") + ",\n"
            f'\t\tstatus = "{r["status"]}",\n'
            f'\t\twiredBy = "{r["wiredBy"]}",\n'
            "\t},\n"
        )
    return HEADER + "".join(body) + FOOTER


VEHICLE_ORDER = ["Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig", "PonyTrailer", "RanchTrailer", "HeavyHauler"]


def vehicle_reupload_section() -> list[str]:
    """T390: the walk-through for the vehicle meshes whose Roblox upload is stale (Rustbucket first).

    The old ids come from the re-upload table in ASSETS.md (written by `lune run tools/assets` from
    VehicleModels.luau), so this section never holds a second copy that could drift.
    """
    import re

    rows: dict[str, list[tuple[str, str]]] = {}
    assets = Path("ASSETS.md")
    if assets.exists():
        for line in assets.read_text().splitlines():
            m = re.match(r"^\| (\d+) \| `[^`]+` \| (\w+) \| (\w+) \| new GLB in repo, needs re-upload \|$", line)
            if m:
                rows.setdefault(m.group(3), []).append((m.group(2), m.group(1)))
    total = sum(len(v) for v in rows.values())
    lines = [
        "## Vehicle meshes: re-upload (T390, Rustbucket first)",
        "",
        f"{total} of the vehicle mesh ids in `VehicleModels.luau` point at Roblox uploads older than the GLBs in",
        "`assets/meshes/vehicles` (`Glass` is unchanged in every GLB: keep its id). Until they are replaced the",
        "display trucks and the bought trucks both dress in the old meshes. The game is not broken meanwhile:",
        "`tests/VehicleMeshes.spec.luau` keeps two expected-fail specs that go green when this is done.",
        "",
        "Do them in this order, one vehicle at a time, and look at each in Studio before starting the next:",
        "",
        "1. Open Roblox Studio and the Timberline place. View tab, Asset Manager, Meshes tab, **Bulk Import**.",
        "2. Pick the vehicle's `.glb` from the table below. The 3D Importer lists its pieces by name",
        "   (`Body`, `Glass`, `Lights`, `Bed`, `Wheel`, `Hitch`). Leave the settings, click **Import**.",
        "3. Each piece becomes a MeshPart with its own mesh. For every piece in the vehicle's table (skip `Glass`):",
        "   click it, copy the number out of **MeshId** (`rbxassetid://123456789`, keep only the number). Never use",
        "   the id of the whole Model.",
        "4. In `src/ReplicatedStorage/Shared/Art/VehicleModels.luau` find the old id (Ctrl+F) and replace only that",
        "   number. Leave `size` and `at` alone: they already match the new file. A mesh id used by more than one",
        "   truck variant (the trailers) is one search and one replace: Replace All.",
        "5. Allow the asset in the experience (Creator Hub, Creations, Assets, the asset, Permissions) if it is not",
        "   already yours to use, or the mesh will not load in game.",
        "6. After the last vehicle: run `lune run tools/assets` and commit `ASSETS.md` and `tools/asset-ids.json`,",
        "   then `scripts/check-assets.ps1` (Windows) and tell the build agent the result so the rows can be marked",
        "   checked. That flips the two expected-fail specs in `tests/VehicleMeshes.spec.luau` to passing; change them",
        "   to `t.test` then.",
        "7. Studio check, a NEW Play session (not a Run in the same session): walk every pad in the Dealership, each",
        "   truck matches its render; Output (View > Output) shows no `[MeshKit]` or `[VehicleMeshes]` warnings; buy the",
        "   Rust Bucket and one other truck, spawn, compare to the display; stop, Play again, still correct.",
        "",
    ]
    order = [v for v in VEHICLE_ORDER if v in rows] + sorted(v for v in rows if v not in VEHICLE_ORDER)
    for n, who in enumerate(order, 1):
        glb = f"assets/meshes/vehicles/{who}/{who}.glb"
        lines += [
            f"### {n}. {who}" + ("  (start here)" if n == 1 else ""),
            "",
            f"File: `{glb}`",
            "",
            "| Piece (node) | Old id to replace |",
            "|---|---|",
        ]
        order_nodes = {"Body": 0, "Lights": 1, "Bed": 2, "Wheel": 3, "Hitch": 4}
        for node, old in sorted(rows[who], key=lambda r: order_nodes.get(r[0], 9)):
            lines.append(f"| {node} | `{old}` |")
        lines.append("")
    lines += [
        "The trailers' `by_truck` variants (`assets/meshes/vehicles/<Trailer>/by_truck/<Truck>/...`) have no ids of",
        "their own yet: each variant draws its trailer's mesh above, stretched to the truck's width. Leave them.",
        "",
    ]
    return lines


def upload_list(rows: list[dict]) -> str:
    lines = [
        "# Blender upload list (Lane H)",
        "",
        "Generated by `python3 tools/blender/registry.py`; the registry is",
        "`src/ReplicatedStorage/Shared/Art/BlenderAssets.luau`. **Nothing here is uploaded by code.**",
        "Connor uploads, only after he says yes to the renders; the ids then go into the",
        "registry (or the module in the Wired by column) in a separate PR.",
        "",
    ] + vehicle_reupload_section() + [
        "## Still to model and upload (status planned)",
        "",
        "No model exists yet. The part-built model stays in game until one is made, approved and uploaded.",
        "Building a Blender generator for these waits on Connor (Awaiting Connor in the PR).",
        "",
        "| Registry key | Asset type | Display name | Expected tris | Collision | What it is |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        if r["status"] == "planned":
            name = r["key"].split("/")[-1]
            lines.append(
                f"| `{r['key']}` | Model (MeshPart) | Timberline {name} | under 2,000 | {r['collision']} | {r['why']} |"
            )
    lines += [
        "",
        "## Already uploaded (no action)",
        "",
        "Every other registry row is uploaded and Approved. Status `repo`: the GLB is in",
        "`assets/meshes` and the live ids are in the Wired by module. Status `backlog`: uploaded",
        "8 Oct 2026 with the Blender backlog, wired by `BacklogModels` (job 17).",
        "",
        "| Registry key | Status | Wired by | Tris | Size (studs) | Collision |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        if r["status"] != "planned":
            size = " x ".join(num(v) for v in r["size"])
            lines.append(
                f"| `{r['key']}` | {r['status']} | {r['wiredBy']} | {r['tris']:,} | {size} | {r['collision']} |"
            )
    lines += [
        "",
        "Kept part-built on purpose (not on this list): shop boxes (the LT2-style dark box with a",
        "window, BoxArt), every gameplay part (hitboxes, prompts, sell zones, signs with text).",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    backlog_json = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/workspace/roblox/handoff/assets/uploaded-backlog.json")
    pack_models = backlog_json.parent / "models" / "backlog"
    rows = repo_rows() + backlog_rows(backlog_json, pack_models) + store_rows() + planned_rows()
    rows.sort(key=lambda r: r["key"])
    OUT_LUAU.write_text(luau(rows))
    OUT_LIST.write_text(upload_list(rows))
    print(f"{len(rows)} rows: " + ", ".join(f"{s} {sum(1 for r in rows if r['status'] == s)}" for s in ("repo", "backlog", "store", "planned")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
