# Redesign (October 2026): models, a living world, and the Living Forest

This is the build brief for the redesign on branch `claude/blissful-gates-dba9t3`:
what changed, why, and the rules the new code follows. GAME_DESIGN.md §16–17
hold the design; this file is the engineering side. Keep it current.

## Goals (from Connor)
1. A complete model redesign: every tree, building, truck, character, axe
   and prop rebuilt in the cozy low-poly style of `concept-art/`.
2. An active environment: terrain, water, weather, wind, wildlife, lighting
   that changes with time and biome, ambient sound.
3. A real playable game: the loop works end to end and feels good.
4. A unique twist, researched (LT2, Oaklands, 2025–26 Roblox hits).

## The twist: the Living Forest (Heartseeds and the Hidden Grain)
Research showed weather mutations with multipliers are saturated (Grow a
Garden, Fisch, and *Chop Your Tree* in our own genre). What nobody in the
lumber genre does is make the forest **respond to you**:

- **Heartseeds.** Every felled tree drops Heartseeds (they pop out and fly
  to you). Plant one in any stump of the same wood and the tree regrows
  early, grown by you, wearing a small "planted by" tag.
- **The planter's share.** When anyone else fells a tree you planted, you
  earn a share of its logs' value (paid by the game, nobody loses
  anything). Replanting is good for you and for the server.
- **Grove Vitality.** Each biome has a server-wide vitality meter.
  Replanting raises it, felling lowers it a little, it drifts back to
  normal. Thriving groves come alive (more flowers, butterflies,
  fireflies, birdsong, deer) and grow more figured wood; old-growth groves
  wake an **Elder tree**: a giant, server-announced, co-op fell that pays
  everyone who helped.
- **The Hidden Grain.** Some trees hide a figure in their wood (curly,
  birdseye, quilted, burl; stormgrain from lightning; starfall burl on
  Lumenwood). Each figure shows a **bark clue** you learn to read (the
  Field Guide teaches them); the sawmill reveals it when you sell, with a
  value multiplier.
- **Storms strike trees.** In a storm, lightning hits a real tree: it
  glows for two minutes, and felling it in time gives Stormgrain logs.
  Weather is an input to the forest, never a flat multiplier.

Next (designed, not built yet): genes and breeding on plot Sapling Plots
(Heartseeds carry a genome; neighbouring trees cross-pollinate at dawn; the
first player to grow a new cultivar names it in the Field Guide registry),
then Skyroot Rising (cross-server weekly goals grow new branch isles).

## Architecture rules
- **Art is pure code in `Shared/Art`** (`Kit`, `TreeArt`, `TruckArt`,
  `BuildingArt`, `IsleArt`, `PropArt`, `CharacterArt`, `AxeArt`): only
  `Instance.new` and datatypes, no services, so the same code builds the
  game and the previews. Place parts with `.CFrame` only. Variation comes
  from `Kit.rng(seed)`, never `math.random`. Builders return a Model around
  the origin (ground y = 0, front facing -Z) and list the part names other
  code depends on.
- **Decoration doesn't collide, can't be clicked or touched**
  (`Kit.decor`); small parts cast no shadow. Only what you stand on or bump
  into collides. Canopies stay clickable (CanQuery) so pointing at leaves
  targets the tree.
- **The world is terrain** from `Shared/World/TerrainGen` (pure functions of
  x, z; `TerrainBuilder` writes the voxels). Anything placed in the world
  asks `TerrainGen.HeightAt(x, z)` for the ground. Town and plots are flat
  at y = 0.
- **Server builds only what matters to gameplay** (trees, logs, buildings
  with counters and zones, plots, NPCs). Clients build the decoration
  (flowers, rocks, critters) around the player, deterministically, so
  every player sees the same meadow without replicating it.
- **Everything visual on clients is streaming-tolerant**: tags and
  `GetInstanceAddedSignal`, never long `WaitForChild` chains on streamed
  parts.
- **One animator per tree** (TreeFX): hits wobble, falls fall, regrowth
  grows. Wind sway leaves busy trees alone (`TreeFX.IsBusy`).
- **Sounds come from `Shared/SoundData`** by name.
- Server rules from CLAUDE.md still hold: intents only, every remote has a
  RateLimiter entry, EconomyService is the only cash writer, new save
  fields go in ProfileSchema.

## Contracts other code relies on (keep them)
- Tree: tag `Tree`; PrimaryPart `Trunk` (its CFrame = `HomePivot`);
  attributes WoodId, MaxHP, HP, Uid, BarOffset, HomePivot, Size, Dormant,
  Felled, FallDir, FellAt, PlanterId. Stumps: tag `Stump`, attributes
  WoodId, TreeUid.
- Log: tag `Log`; PrimaryPart `LogPart` holding the ProximityPrompt; caps
  welded, unanchored, massless.
- Truck: tag `Truck`; PrimaryPart chassis with `Drive`/`Heading`; the
  VehicleSeat a direct child; one `LoadPoint` attachment; attributes
  OwnerId, TruckId, TrailerId, BedCapacity, BedCount, TopSpeed, TurnRate.
- Shops: Persistent models `ToolShed`/`Dealership`/`HearthAndHome` under
  TimberlineMap with a direct-child `Counter` holding a `ShopPoint`.
- Sawmill: Persistent `SellArea` with `SellZone` (a box), `SellPoint`,
  `SkyBin` (SurfaceGuis with a TextLabel).
- Gondola: models `GondolaTown`/`GondolaBase`/`GondolaTop`, each with a
  `Platform`. Tags `CloudChute`, `StarfallForge`, `ParkingSlot` (+Index).
- Murph: Persistent model `Murph` under TimberlineMap with parts Head,
  Beard, Beanie, Torso, LeftArm, RightArm (QuestUI's portrait).

## Verifying without Studio
- `./scripts/check.sh`: StyLua, Selene, strict luau-lsp, Lune tests,
  ECONOMY.md.
- `lune run tools/preview/export <scene>` builds a scene from the real art
  modules and writes `preview/<scene>.html` (open in a browser; drag to
  orbit, 1–9 for camera presets). `node tools/preview/render.mjs
  preview/<scene>.html` screenshots it (needs Node + Playwright). One file
  per scene in `tools/preview/scenes/`.
- Then the Studio checklist in PHASE2_NOTES.md.

## Workstreams and file ownership
| Workstream | Owns |
|---|---|
| World (lead) | Kit, TreeArt, TreeLogic, TerrainGen, WorldLayout, TerrainBuilder, MapBuilder, TreeService, TreeFX, GameServer, Net, RateLimiter, ProfileSchema, Client.client, default.project.json, docs |
| Vehicles | TruckArt, VehicleService, VehicleController, VehicleFX, TruckLayout (+spec), ShopService (trailer check only), scenes/trucks |
| Buildings | BuildingArt, scenes/town |
| Nature & isles | PropArt, IsleArt, scenes/props, scenes/isles |
| Characters & axes | CharacterArt, AxeArt, NPCService, NPCController, AxeService (models only), scenes/npcs, scenes/axes |
| Environment | LightingController, WeatherController, AmbientLife, WindSway, AmbientSound, WeatherService, WeatherSchedule (+spec), WorldClock (lighting part), SoundData (additions) |
| Living Forest | ForestData, ForestLogic (+spec), ForestService, ForestUI, FieldGuide additions, DailyData/TutorialData additions, economy model factor |
| Feel & fixes | ChopController, HUD/sale FX, CarryController (Sky Bin sell), ProfileService/MonetizationService fixes |
