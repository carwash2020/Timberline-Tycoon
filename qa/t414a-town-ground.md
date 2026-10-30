# T414a town ground — plan (posted before code)

Player story: a new player spawns on the plaza, walks to Hearth & Home, then drives to the sell point. They see cobble town lanes, asphalt-gravel roads with low stone kerbs, and dirt footpaths that blend into the grass. No flickering seam, no green placeholder block, no hard grass rectangle. The truck does not snag on a kerb.

## Approach

- `TownGround` still computes the same piece names, groups, gaps and `Covers` / `TopAt` / `Pieces` / `Gaps` / `Counts`. Other code keeps finding `TownGround`, `TownRoads`, `TownCurbs`, `TownPaths`, `TownLines`, `PlotEdges`, and the path names MapBuilder lifts.
- Roads, yards, the lot, footpaths, centre lines and plot-edge strips are terrain paint, not stacked parts. `TerrainGen.SurfaceMaterial` asks `TownGround.MaterialAt` (registered on `TerrainGen.TownSurface`, so there is no require cycle). Paint stays inside the piece, which for haul roads is `WorldLayout.PlanWidth`.
- A 1.6-stud dither on the piece edge lets grass break the rectangle. Stray Asphalt, Rock, Slate and LeafyGrass inside the town zone still read as Grass when they are not this paint.
- Only kerbs are parts: Slate, StoneBase via `Kit.hex`, 0.6 studs tall (under the 1-stud cap), `CanCollide` false. `TownGroundArt.KerbMeshId` is 0, so `MeshKit` keeps the on-style part. That greybox is a known gap.
- Palette: roads `#A8A49C` Asphalt, town lanes and the lot `#9C958A` Cobblestone (terrain has no WoodPlanks), kerbs `#8C877E` Slate, footpaths `#8E6C4A` Ground, grass stays the terrain colours `#6E9F45` / `#5A8A3C`. No new `Color3.fromRGB`.
- Foot paths are 8 wide. Drive widths stay Main 32 / Branch 24.

## Graded bed stays 28 outside town

`WorldLayout.PlanWidth` stays 28. That bed is what the country stretch uses. Inside town the East Link and South Link are flat to half-width 16.3, paved to 16, with the kerb at 16.15 and a grass blend outward from 16.3 to 20.3. Widening the country grade still moves trees and puts rocks in cabins, so the plan bed did not move. The drive width on `WorldLayout.Roads` stays 32 / 24.

Known gap: `TownGroundArt.KerbMeshId` is 0. The slate bar is the look until the mesh is uploaded.

## Specs written first (red, then left alone)

Appended to `tests/TownGround.spec.luau` and not edited to pass:

1. Built ground parts do not overlap on one plane.
2. Foot paths are 8 wide; kerbs are Slate, 0.6 tall, not collidable; lane and road colours are the palette above.
3. Terrain at the street, the spawn walk and the lot is that paint, and a sample past the East Link bed is not Asphalt.
4. The group models and the path names MapBuilder and the footpath spec read still exist. Built parts carry `MeshId` `"0"`.
5. No `Color3.fromRGB` in `TownGround` or `TownGroundArt`.

## Files

`World/TownGround.luau`, `Art/TownGroundArt.luau`, `World/TerrainGen.luau`, the specs that still describe the T402 strips (`TownGround`, `Footpaths`, `MapBuilder`, `NoGreyStrips`, `LandscapeStyle`), `STATUS.md`, `PHASE2_NOTES.md`, `preview/t414a/`.

## Studio (for Connor, after the build)

1. Spawn on the plaza and walk to Hearth & Home: cobble, then a dirt path, no flickering strip.
2. Drive the starter truck across a kerb into the sell yard. It does not bump.
3. The lot reads as cobble up to the grass, with a low stone edge you can drive through.
4. Kerb meshes are still the slate bar until the upload below.
5. Tool Shed, mill, Weigh House, bridges, ferry docks and shop doors are where they were.

Mesh upload: `TownGroundArt.KerbMeshId` is 0.

1. Model one kerb strip (about 0.6 studs tall, stone) and Bulk Import it.
2. Paste the MeshPart id into `TownGroundArt.KerbMeshId`.
3. New Play. The slate bar swaps for the mesh. Until then the bar is the look.
