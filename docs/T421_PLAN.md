# T421 plan: every truck and trailer is its real custom model

Branch t421-vehicles, base main 3fcaace. Plan first; code follows in commits by area.

## Source files: what exists and what does not

The brief says assets/vehicles/t421/ (bbox_check.md, glb/<Trailer>/<Truck>/stats.json, glb/TimberClassic/stats.json,
mesh_ids.txt, UPLOAD_STEPS.md, style guide section 12, quality-bar.md, vision.md) is attached. It is not in the repo or
the uploads. Searched: assets/, docs/, previews/vehicles-fixed, tools/, whole worktree by name.

Derivable exactly from repo data (provenance goes in assets/vehicles/t421/PROVENANCE.md and in the data module header):
- The 54 mesh names: 3 trailers x 4 variants x Body/Bed/Lights/Hitch, plus TimberClassic Body/Glass/Lights/Bed/Wheel/Hitch.
  Written to assets/vehicles/t421/mesh_ids.txt as `<Name> = ` with empty ids (never invented).
- Piece sizes and `at` for every trailer variant: already in VehicleModels.luau and pinned to the repo GLBs
  (assets/glb/vehicles/by_truck, tests/VehicleWheelClearance.spec). Kept as the source for `at`.
- Axles from the brief: Pony {1.30}, Ranch {0.26, 3.38}, HeavyHauler {0.91, 4.29}, trailer-local, bed centre Z 0.
- TimberClassic numbers the brief states: hitch (0, 2.005, 12.875), wheel centres (+-4.713, 1.755, -9.685) and
  (+-4.713, 1.755, 7.085), bed footprint 7.22 x 15.5.

NOT derivable (nothing in the repo holds them), so those parts stop and are listed in a PR comment:
- bbox_check.md per-variant wheel X (spec 5, last clause). The GLB wheel node is one wheel centred on its own origin,
  so its X in the assembly is not in any GLB.
- TimberClassic/stats.json part sizes and `at` (no TimberClassic GLB exists in the repo). Spec 8's size match and the
  TimberClassic piece table (Body, Glass, Lights, Bed sizes/at) can only be checked against the brief's stated
  numbers (hitch, wheel centres, bed footprint).
- The 54 MeshIds themselves.

## Correction from Connor (overrides the brief)

TimberClassic is not a cash item: it is granted by the existing Classic pass (StoreData.CreatorIds.Passes.TimberClassic,
MonetizationService.HasPass / PaidItems.SaveHasPass). No cash price anywhere. The Dealership shows it with a
"Classic Pass" label and the existing pass prompt for non-owners. Owners spawn it free. Empty mesh ids still make it
unspawnable, even for owners (BootReport lists it). It already exists in ItemCatalog.Trucks (robux, sold = false);
that entry stays and gains no price.

## Approach (commits by area)

1. Data: tools/gen_vehicle_mesh_ids.luau makes src/ReplicatedStorage/Shared/Art/VehicleMeshIds.luau from mesh_ids.txt;
   scripts/check.sh fails if the module is out of date. VehicleMeshes exposes the 54 keys.
2. VehicleMeshes: ids for trailer pieces and TimberClassic come from the keyed table. Empty id = missing. The part-built
   fallback (keepPartBuilt) is removed for the T421 set. Visual MeshParts Massless, CanCollide/CanQuery/CanTouch false,
   CollisionFidelity Box; Glass Transparency 0.4, CastShadow false.
3. Missing means not sold: pure Shared/VehicleMeshGate (missing names per vehicle). Dealership stock, ShopLogic buy and
   VehicleService purchase refuse it; BootReport logs vehicleMeshesMissing. Owned vehicles still spawn.
4. Trailers: Shared/TrailerAxleData (axle values, provenance) replaces tandemGap and * 0.6 in TruckLayout.ForTrailer.
5. TimberClassic: pass rule, mesh table, Dealership bay and label.
6. Dealership: stand under the hitch nose, ceiling over the Logging Rig bay, lints, stock.

## Tests (each must fail before the change)

1 VehicleMeshIds, 2 VehicleMeshesMissing, 3 VehicleGlass, 4 VehicleVisualParts, 5 TrailerAxles, 6 TrailerTow extended,
7 VehicleWheelClearance extended, 8 TimberClassic, 9 VehicleCoverage, 10 geometry lint with the 15 combos parked,
11 PipelineE2E plus the 12-log TimberClassic and Ranch Trailer test. Added from Connor: TimberClassicPass (non-owner refused,
owner spawns free, never in a cash price list).

## The six gaps, confirmed on main 3fcaace

1. Trailer wheels: Shared/TruckLayout.luau:328-330 (tandemGap per style), :368-371 (`bedStart + bedLength * 0.6`, tandem
   +-gap/2); Shared/Art/TruckArt.luau:1279 draws one wheel pair per tl.axleZ entry, so Ranch has one axle.
2. Part-built stand-in: Shared/Art/VehicleMeshes.luau:57-69 keepPartBuilt, called at :438 (Fitted copy), :448 (missing
   mesh); applyNow returns false and leaves the hull.
3. Display trailers: Shared/Art/DealershipLot.luau:350-359 placeTrailer puts the trailer's middle on the pivot with no stand
   or jack; nothing checks wheels against the plinth top.
4. Crane: DealershipLot.luau:97-103 MaxVehicleHeight = 12.0 and :374-406 fitUnderCeiling scale the Logging Rig down;
   ceiling beams and rafters are built in Shared/Art/ShopInteriors/Dealership.luau:394-403. No lint checks display
   vehicles against them.
5. Stock: Shared/ItemBox.luau:37-46 Showroom has no TimberClassic; sub-sign text is DealershipLot.BedText
   (DealershipLot.luau:318-329).
6. Display trucks are built through TruckArt.Build (DealershipLot.luau:343-349) and, when a mesh is missing or the copy is
   "Fitted", fall back to the part-built hull via VehicleMeshes.luau:438.

Anything that cannot be finished inside this PR is written in the PR body, not worked around.
