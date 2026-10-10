# Terrain and water: what Roblox can and can't do (Lane H, 8 Oct 2026)

Short answers for planning art. Links are the Roblox Creator Docs.

## Terrain

- Terrain is voxels on a 4-stud grid, written by code: `TerrainGen` and `TerrainBuilder` (Lane B) fill
  regions and smooth them. See [Terrain](https://create.roblox.com/docs/parts/terrain) and the
  [Terrain class](https://create.roblox.com/docs/reference/engine/classes/Terrain).
- **Mountains stay terrain.** Terrain is walkable, drivable, streamed with the map and cheap on phones.
  A Blender mountain mesh would need its own collision, would not stream the same way and would cost
  far more triangles. Blender adds **cliff faces and boulders as meshes on top** of the terrain
  (`assets/meshes/rocks`, and the planned `cliffs/CliffFaceA`/`B` rows in the registry).
- **A Blender heightmap can feed terrain**, two ways:
  1. As a Luau height grid that `TerrainGen` reads (export the heightmap from Blender as numbers, not an
     image). This is a later Lane B task and is flagged, not done.
  2. Studio's Terrain Editor > Import (heightmap and colour map). That is a manual Studio step for Connor
     and writes terrain once; code-built terrain would overwrite it on the next build.
  See [Terrain Editor](https://create.roblox.com/docs/studio/terrain-editor).

## Terrain materials

- Terrain materials (Grass, Rock, Sand, Snow, ...) can get a custom look only through a
  **MaterialVariant in MaterialService** set as the place-wide override for that base material. There is
  one override per base material per place: every Grass voxel in the whole map gets it.
  See [Materials](https://create.roblox.com/docs/parts/materials) and
  [MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant).
- A MaterialVariant needs **uploaded textures** (Color, Normal, Roughness, Metalness maps). Uploads are
  Connor's. Nothing in this PR uploads.
- Flat LT2-style grass stays the built-in Grass material with its colour set in Terrain (Connor's decision
  6: no upload needed).

## Water

- Terrain water **cannot take a custom texture or MaterialVariant.** The only controls are the Terrain
  properties `WaterColor`, `WaterTransparency`, `WaterReflectance`, `WaterWaveSize` and `WaterWaveSpeed`.
- A textured mesh plane could look custom, but it has **no swimming, no buoyancy and no ripples**. The
  ferry and the boats rely on terrain water, so water stays terrain water, tuned with those five
  properties.
- Optional extras that are fine: foam strips or shore decals as thin meshes laid at the waterline, with
  collision off.

## Mesh limits (for anything Blender adds)

From [Mesh specifications](https://create.roblox.com/docs/art/modeling/specifications) and the Lane H
brief: at most 20,000 triangles per mesh, one material per mesh, UVs inside 0 to 1, textures at most
1024 x 1024, 1 Blender unit = 1 stud. `python3 tools/blender/check.py` checks the exported GLBs.
