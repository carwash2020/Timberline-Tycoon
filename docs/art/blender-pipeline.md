# Blender asset pipeline (Lane H)

How Blender-made models get into Timberline Tycoon, and where each one is recorded.

1. **Model** in Blender 5.2 (1 unit = 1 stud, feet at y = 0, front faces -Z in Roblox, one material
   per mesh, vertex colours by default). Export FBX for the upload and GLB for the repo previews.
2. **Check** the GLB: `python3 tools/blender/check.py [files or folders]` (no Blender needed). It fails
   on a mesh over 20,000 triangles, more than one material, a non-triangle primitive, UVs outside 0 to
   1, a texture over 1024 px or a file over 5 MB. On 8 Oct 2026 all 214 GLBs in `assets/meshes` and
   all 217 in the handoff pack pass.
3. **Approve and upload.** Connor sees real renders first. Connor uploads (never code, never a PR).
4. **Wire.** The uploaded ids go into the module that builds that model (`TownModels`, `AxeModels`,
   `RockModels`, `TreeModels`, `VehicleModels`, `ItemMeshData`, `KitMeshData`, `BacklogModels`), plus
   one `src/ReplicatedStorage/MeshTemplates/<meshId>.model.json` per id. `MeshKit` loads the mesh and
   keeps the part-built model if it fails.
5. **Preview.** `python3 tools/preview/build_mesh_manifest.py <models dir>` copies the GLBs into
   `assets/meshes` so `bash tools/preview/shoot.sh <scene>` draws the real meshes.
6. **Registry.** `python3 tools/blender/registry.py` rebuilds
   `src/ReplicatedStorage/Shared/Art/BlenderAssets.luau` and `assets/UPLOAD_LIST.md` from the GLBs:
   one row per model (file, triangles, size, collision intent, status, wiring module). The spec
   `lune run tests/run BlenderAssets` checks it.

No Blender generator scripts are in the repo yet. The models were made outside it; building
generators for the remaining planned rows waits on Connor.
