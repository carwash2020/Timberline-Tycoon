# assets/vehicles/t421

mesh_ids.txt: the 54 names are derived from the naming rule `<Trailer>_<Truck>_<Part>` (3 trailers x 4 width variants x
Body/Bed/Lights/Hitch) plus TimberClassic Body/Glass/Lights/Bed/Wheel/Hitch. The ids are empty on purpose: no id has
been supplied. Fill in the number after `=` (digits only) when the uploads exist, then run
`lune run tools/gen_vehicle_mesh_ids` and commit the regenerated Shared/Art/VehicleMeshIds.luau.

The source set the T421 brief names (bbox_check.md, stats.json files, quality-bar.md, vision.md) was not attached to the
branch. Nothing in this folder claims to come from it.

truck_mesh_ids.txt (added on Connor's addendum): the recoloured Rustbucket, Pickup, Flatbed and LoggingRig get their own
keys `<Truck>/<Part>`, one per MeshPart. The part names are the real node names inside assets/glb/vehicles/<Truck>.glb
(Bed, Body, Glass, Hitch, Lights, Wheel; checked with tools/blender/glbstats.py). 24 keys, so 54 + 24 = 78 in all. They are
kept out of mesh_ids.txt so that file stays exactly the 54-line set the brief names. An empty id here keeps the truck's
current mesh (VehicleModels.luau); these four trucks are never removed from sale.
