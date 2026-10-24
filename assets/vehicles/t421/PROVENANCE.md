# assets/vehicles/t421

mesh_ids.txt is Connor's 78-line file, committed as supplied (empty ids: none has been supplied): 48 trailer lines
`<Trailer>_<Truck>_<Part>`, 6 `TimberClassic_<Part>` and 24 `trucks/<Truck>/<Part>`. Fill in the number after `=` (digits only) when the uploads exist, then run
`lune run tools/gen_vehicle_mesh_ids` and commit the regenerated Shared/Art/VehicleMeshIds.luau.

The source set the T421 brief names (bbox_check.md, stats.json files, quality-bar.md, vision.md) was not attached to the
branch. Nothing in this folder claims to come from it.

The four recoloured trucks' 24 lines are `trucks/<Truck>/<Part>` in mesh_ids.txt itself (Bed, Body, Glass, Hitch, Lights, Wheel). An empty id
keeps the truck's current mesh (VehicleModels.luau); those trucks are never removed from sale.

## Data bundle (Connor, for PR 265)

`bbox_check.md` and every `glb/<Trailer>/<Truck>/stats.json` plus `glb/TimberClassic/stats.json` are Connor's T421 data bundle,
saved here unchanged. `Shared/Art/VehicleStats.luau` is generated from the stats files by `tools/gen_vehicle_stats.luau`
(checked by scripts/check.sh). The axles, wheel X, sizes and `at` offsets in code come from there and nowhere else.
(The earlier note that these files were not attached no longer applies.)
