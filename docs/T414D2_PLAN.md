# T414d-2 plan: greenery, stumps, saplings and critters along every road

Branch `cursor/t414d2-greenery-critters`, from main 9b2a43f. Plan only; code follows after the specs.

Goal: walking or driving any road shows ground cover, shrubs, rocks and logged stumps, and a deer or birds move off as you pass. Nothing stands in a road, a log lane, a belt or a shop door.

## Files

New:
- `Shared/World/Scatter.luau` (pure, deterministic): keep-out rules, the corridor fill and the region Poisson-disc, returning one plan of items (`cover`: under 4 studs, `solids`: stumps and rocks, `saplings`).
- `Shared/Art/Greenery.luau`: the town Greenery builder moves here (BuildingArt.Greenery becomes a one-line delegate) plus the new decor builders: square Block stump, rock, shrub clump, grass patch.
- `ServerScriptService/ScatterBuilder.luau` and one MapBuilder defer step: builds the solids once at boot, Anchored, one template per kind cloned, streaming Default.
- `StarterPlayerScripts/ScatterCover.luau`: builds ground cover from the seed on the client within 160 studs with a distance fade (not replicated).
- `StarterPlayerScripts/RoadCritters.luau`: client-only critters, one Heartbeat loop over a table, flee, no lane or road entry.
- Specs: `Scatter.spec`, `ScatterWorld.spec` (real world build), `CritterCap.spec`.

Edited: `BuildingArt.Greenery` (delegate only), `CritterArt` (cap constants, template flags), `OverlapCheck` (scatter solids as discs), `Client.client` (start the two modules).

Not touched: shop interiors, town paving, StoreData, economy, Palette, TreeModels wood, chop-spawned stump code.

## Approach

Keep-outs from the road centreline: main (drive width 32) 18, branch 14, foot paths 5; mill lane boxes (LaneData in world space) and the town sawmill belt +2; shop doors 10; docks, bridges 6 past the footprint; plot pads +4; water and flat zones. Everything is a function of fixed data and a seed, so server and client agree without a remote.

Corridor fill: walk each road's centreline in 24-stud windows, both sides; each window gets a cluster (grass, shrub, rock or stump) at 18 to 40 studs out, retrying other offsets if a keep-out rejects it. Region Poisson-disc fills meadow gaps with saplings and sparse dead trees. Heights come from `TerrainGen.HeightAt`, slope cap 35 degrees.

Solids (stumps, large rocks) are rejected against trees, boulders and scenery so the world overlap lint stays clean with no allowlist entry.

## Acceptance specs (written first, shown red)

1. Real-world spec: no item inside any keep-out; solids pass overlap and the lane lint.
2. Grounding: base within 0.1 of HeightAt (rocks sunk their stated 30%).
3. Corridor: a cluster in every 24-stud window of road where the band is open.
4. Flags: under-4 cover and critters CanCollide/CanQuery/CanTouch false, ground cover CastShadow false; zero server critters; cap 12 on phone and 40 on high.
5. Per-region counts asserted; names (TreeService stump tags, ForestService clue attributes, AmbientLife hooks) still present.

## Not in this PR (follow-ups)

Chop-spawned stump restyle, TreeArt.Sapling restyle and ForestArt dress, if the size cap (about 400 lines) is reached.
