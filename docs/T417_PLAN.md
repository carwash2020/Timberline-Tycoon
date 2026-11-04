# T417 Studio boot fixes

One PR, branch `t417-studio-boot-fixes`, base main `fbd97bf`. Connor opened the game in Studio (place built with `rojo build`): there is no ground, the Dealership lot did not build, and the Output window is full of errors. Three fixes plus one investigation. Every fix: a spec that fails on main, shown red, then green. No spec is loosened.

## 1. Terrain grid alignment (the blocker)

Log: `Region has to be aligned to the grid ... TerrainBuilder:173 (writeChunk)`, then `Bad argument materials to 'WriteVoxels' (15x9x15 array expected)` for ~2300 blocks.

Cause (to verify in the spec): `TerrainBuilder.Jobs` starts its chunks at `-half`, `half = WorldHalf + TerrainSkirt`. T409 (#270, commit 0eff8b8) raised `WorldHalf` from 1000 to 1350, so half became 1550. 1550 is not a multiple of the 4-stud voxel, so every block origin is 2 studs off the grid. The engine expands an unaligned Region3 to the grid, so the arrays no longer fit. The Lune fake never checked, so check.sh and CI stayed green.

Plan:
- A shared strict fake (`tests/support/StrictTerrain.luau`) that behaves like the engine: `WriteVoxels` errors when the region's min or max is not a multiple of the resolution, and when the materials or occupancy dimensions differ from the region's voxel counts (nx, ny, nz). The terrain specs (TerrainBuilder, TerrainStaged, Terrain, TerrainFit, TownBoot) use it. Shown red on main.
- Fix in one place: `TerrainBuilder.Jobs` rounds the generated half up to a multiple of VOXEL (1550 -> 1552). `WorldLayout.WorldHalf` is not changed. Split, Order, SettleTown, the background blocks, the probes and TerrainGen sampling all derive from the job origins, so they follow.
- `writeChunk` is also made robust: x0/z0 aligned down and the far corner up (ExpandToGrid semantics), arrays built for the aligned region, so no future origin can misalign.
- New spec: every block from Jobs / Split / Order for the real WorldLayout has x0, z0 multiples of VOXEL and an ExpandToGrid-identity region.
- Re-check with the strict fake that the town ground ends at y = 0 and surface(-60,73) is Cobblestone, surface(0,50) is Ground.

## 2. CollisionFidelity runtime writes (T421)

Log: `The current thread cannot write 'CollisionFidelity' (lacking capability PluginOrOpenCloud)` from MeshKit / VehicleMeshes, which aborts the Dealership lot, and `[StumpMeshes] CollisionFidelity Hull could not be set` repeated.

Plan: game code never assigns CollisionFidelity on an existing MeshPart. A single helper `MeshKit.TrySetFidelity` (pcall, remembers the first failure, logs once) is used where the assignment cannot be dropped; creation through `AssetService:CreateMeshPartAsync` keeps passing fidelity in its options. CanCollide / CanQuery / CanTouch / Massless stay (writable). The Lune fake MeshPart's setter throws the real error text so specs go red on main. T420/T421 specs that asserted `CollisionFidelity = Box` on visual parts now assert the writable flags. `DealershipLot` builds each vehicle under pcall, logs which one failed, and keeps the lot standing.

## 3. ContentId "Asset type does not match requested type" (investigation)

Find the code that requests these ids (T415 FirstViewPreload, ContentProvider:PreloadAsync, MeshKit.Request), decide whether it is Studio noise or a real failure (the log also says 188 / 188 and 834 / 834 meshes loaded). Fix only if clearly ours and small; keep the Preload.spec cap (96). Report either way.

## 4. Left alone

ProfileStore / DataStore unavailable, ColorMapGuard Plugin capability, PlaceCheck: expected in an unpublished place.

## Out of the diff

StoreData, EconomyService, prices, ProfileSchema, PassService, VehicleService, PaintService, RemoteEvents, `Vendor/`, `default.project.json`, `scripts/check.sh`, `tests/geometry_allow.json` (no entries), `tests/mustkeep.json`.

## Studio-only (Connor)

Output window free of `Region has to be aligned` and terrain `failed` lines; ground within about 10 s of spawn; the Dealership lot builds; the uploaded stump, spool and vehicle meshes' CollisionFidelity in the Properties panel. Nothing visual changes, so no renders.
