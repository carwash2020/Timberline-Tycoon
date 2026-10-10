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
                    "status": "backlog",
                    "wiredBy": "BacklogModels",
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
--   planned  on Lane H's list with no model yet (assets/UPLOAD_LIST.md).
--            Nothing is uploaded; the part-built model stays.
--
-- size is the whole model's bounds in studs (1 Blender unit = 1 stud), tris
-- every triangle in its GLB(s). collision is the intent: Box for small
-- props, Hull for medium ones, Parts (invisible part collision) for big
-- buildings, vehicles and trees. Textures are vertex colours today, so
-- every textures table is empty and any texture id is 0.
-- MeshManifest preloads MeshIds() (none of status repo or planned, so
-- nothing changes in game while those ids are 0).

local BlenderAssets = {}

export type Collision = "Box" | "Hull" | "Parts"
export type Status = "repo" | "backlog" | "planned"

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
\t\tif entry.status ~= "backlog" and entry.meshId ~= 0 and not seen[entry.meshId] then
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
            "\t\ttextures = {},\n"
            f'\t\tstatus = "{r["status"]}",\n'
            f'\t\twiredBy = "{r["wiredBy"]}",\n'
            "\t},\n"
        )
    return HEADER + "".join(body) + FOOTER


def upload_list(rows: list[dict]) -> str:
    lines = [
        "# Blender upload list (Lane H)",
        "",
        "Generated by `python3 tools/blender/registry.py`; the registry is",
        "`src/ReplicatedStorage/Shared/Art/BlenderAssets.luau`. **Nothing here is uploaded by code.**",
        "Connor uploads, only after he says yes to the renders; the ids then go into the",
        "registry (or the module in the Wired by column) in a separate PR.",
        "",
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
    rows = repo_rows() + backlog_rows(backlog_json, pack_models) + planned_rows()
    rows.sort(key=lambda r: r["key"])
    OUT_LUAU.write_text(luau(rows))
    OUT_LIST.write_text(upload_list(rows))
    print(f"{len(rows)} rows: " + ", ".join(f"{s} {sum(1 for r in rows if r['status'] == s)}" for s in ("repo", "backlog", "planned")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
