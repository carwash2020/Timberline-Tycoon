# T415 performance pass (issue #286)

Player story: on a mid phone, Xbox or low-end PC I join, see the loading screen, and land in town with the real meshes showing. I drive to any biome without freezes or part-built stand-ins, and the world looks as good as before.

Rule: nothing here changes the look. No mesh simplification, no decor removal, no texture changes. Only streaming, LOD and shadow flags change, plus a preload list.

## Audit of main (0d65588), one line per scope item

1. Streaming settings: already true. `default.project.json` has StreamingEnabled, ModelStreamingBehavior Improved, radii 128 / 640; `PlaceCheck` pins the live place. Pinned by Streaming.spec. Radii are not touched.
2. ModelStreamingMode: changed. Atomic is already set for trees, logs, wood, nodes, trucks, machines, NPCs, plots. Persistent was on far more than the list: the town sawmill, the preload shops, SellArea, Backdrop, DeepWater, MineMouth, LiftBooth, Lighthouse, every sky isle, cloud bank, sky bridge, the Skyroot and the waterfall. Those move to Atomic (interactive) or Default (decor). Persistent ends up exactly: FerryBoat, LiftBridge, MainlandDock, IslandDock, GateLodge, and the spawn landmarks (TownBoard, StoreBoard, the tutorial guides Murph and Old Hank). The player's own plot frame is not changed: a per-player persistent model needs PersistentPerPlayer, which is unverified from script, so it stays Atomic and is listed for Connor.
3. LOD: already true. Meshes use Automatic or Performance; `Precise` appears nowhere (allowlist is empty and pinned). Scatter and critters are part-built, they have no MeshParts. Model LevelOfDetail (SLIM) is unverified from script: Studio step for Connor, not claimed.
4. Instancing: MeshKit already caches one master per id and clones it. New: a duplicate check, live MeshIds grouped by source mesh (assets/meshes/manifest.json file + node), fails when one source mesh has two live ids. No SurfaceAppearances exist (vertex colours), so nothing to share.
5. Shadows: changed for scatter. Critters and boxes already have CastShadow off. Small scatter parts (largest side under PerfPolicy.NoShadowSize) now get CastShadow false when built. Big rocks and stumps keep their shadows. Light counts are untouched.
6. Loading screen and preload: LoadingScreen already holds for character, save and the near ring. Changed: a client first-view list (axes, Murph, the spawn buildings) goes through ContentProvider:PreloadAsync, capped at PerfPolicy.PreloadCap, and the card waits at most 4 s for it. NoFallbackVisible.spec pins that a dressed model shows no part-built shell.
7. No hitches: StreamAhead / NearFirst stay. Changed: FerryService calls RequestStreamAroundAsync (pcall, timeout) before it stands riders at the far dock, and once ahead of arrival.
8. Server memory: already true (LogDespawnSec 300, data-driven world); no change.

## Files

New: `Shared/PerfPolicy.luau` (pure: cap, persistent set, shadow rule, duplicate check, first-view list), `Shared/FirstView.luau` if the list needs MeshManifest, six specs (PerfAssets, Streaming, Preload, Shadows, NoFallbackVisible, FerryStream).
Edited: MapBuilder, TravelArt, LandmarkArt, UndergroundBuilder, ScatterBuilder, FerryService, LoadingScreen, a client boot hook, cloud entry / CloudCheck (shadow, streaming and stand-in checks on the built town).

## Measurable here and Studio-only

Measurable in Lune: counts of parts, unique meshes, preload list size and cap, Persistent set, shadow flags, source-level ordering of the ferry call. Not measurable here: frame time, memory, join time, real streaming, SLIM LOD, physics (cloud has none). Those are the Studio checklist in the PR body.
