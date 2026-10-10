# tools/blender

Lane H tooling for Blender-made models. Nothing here uploads anything.

- `check.py`: checks exported GLBs against the Roblox import limits (pure Python, no Blender).
  `python3 tools/blender/check.py` checks every GLB in `assets/meshes`.
- `registry.py`: rebuilds `src/ReplicatedStorage/Shared/Art/BlenderAssets.luau` and
  `assets/UPLOAD_LIST.md` from the GLBs (deterministic). Run `stylua` on the Luau after.
- `glbstats.py`: the GLB reader both use (triangles, materials, UVs, textures, bounds in studs).
- `render_tiles.py` + `contact_sheet.py`: headless Blender renders of each GLB and labelled sheets
  (`blender -b --factory-startup -P tools/blender/render_tiles.py -- <out> 384 <glb ...>`, then
  `python3 tools/blender/contact_sheet.py <out> previews/v1-h`).

CI has no Blender or Python step; CI runs `tests/BlenderAssets.spec.luau`. Run `check.py` by hand before
adding GLBs. See `docs/art/blender-pipeline.md`.
