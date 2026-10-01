# Redesign (October 2026): models, a living world, and the Living Forest

This is the build brief for the redesign (built on `claude/blissful-gates-dba9t3`, now on `main`):
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
Specs check most of these (TruckArt, BuildingArt, IsleArt, PropArt,
CharacterArt, AxeArt, NPCData, ForestService, EnvironmentData); keep them
when changing art.

**Trees, stumps, logs (TreeArt, TreeService, ForestArt)**
- Tree: tag `Tree`; PrimaryPart `Trunk` (an upright cylinder, its axis
  the part's X; its CFrame = `HomePivot`); attributes WoodId, MaxHP, HP,
  Uid, BarOffset, HomePivot, TrunkRadius (reach is measured from the
  bark), Size, Dormant, Felled, FallDir, FellAt, PlanterId; Elders also
  Elder = true and Size "elder".
- WindSway sways parts named `Leaves` and `Frond`, every part inside a
  `Tier` model, and `Facet` parts that are direct children of a tree
  (frostwood snow caps). Glow added to a canopy should use those names to
  sway with it.
- Stump: tag `Stump`, attributes WoodId, TreeUid; PrimaryPart `Stump`.
- Log: tag `Log`; PrimaryPart `LogPart` (a cylinder along X) holding the
  ProximityPrompt; caps welded, unanchored, massless. Figured logs carry
  the `Figure` attribute, a `FigureBand` part and `tags.figure` on the
  server record; `Value` includes the figure.
- Name stakes and Elder auras live in `TimberlineMap/ForestMarks`.

**Trucks (TruckArt, VehicleService, VehicleFX)**
- Tag `Truck`; PrimaryPart the chassis (anchored while parked, the only
  part with mass) with `Drive`/`Heading`; the VehicleSeat a direct child
  holding a `DrivePrompt` (OwnerId attribute); one `LoadPoint` attachment
  on the last bed part; attributes OwnerId, TruckId, TrailerId,
  BedCapacity, BedCount, TopSpeed, TurnRate. BedCount and BedCapacity are
  also on the Player.
- Wheels: parts named `Wheel` (attributes Radius, Steer, Rear) on a Motor6D
  `Axle` (clients spin and steer them through Motor6D.Transform).
- `Headlight` and `Taillight` Neon parts; `Exhaust` parts with an
  `ExhaustOut` attachment and a Smoke attribute.
- Bed logs: models named `BedLog` in the `BedVisuals` folder (WoodId and
  Figure attributes); the bed is saved in `profile.truckBed`.

**Town (BuildingArt, MapBuilder, WorldPlan.Town)**
- Shops: Persistent models `ToolShed`/`Dealership`/`HearthAndHome` under
  TimberlineMap with a direct-child `Counter` (resting on the floor, its
  -Z side toward customers) holding a `ShopPoint`; keep about 2.6 studs of
  open floor behind it for the keeper.
- Sawmill: Persistent `SellArea` with `SellZone` (a box), `SellPoint`,
  `SkyBin` (SurfaceGuis with a TextLabel each); the rest of the Sky Bin's
  art sits outside SellArea. The sawmill's `SawBlade` spins about its own
  X axis (tag `SawBlade`; its teeth are welded and unanchored: never
  re-anchor them). Campfire `Flame` parts (tag `Flame`) flicker.
- Gondola: models `GondolaTown`/`GondolaBase`/`GondolaTop`, each with a
  `Platform` (10x1x10, top at y 1); stations turn their open back (+Z)
  along the cable. Tags `CloudChute` (the 4x3x4 hopper; its flume runs
  out along +Z), `StarfallForge` (the anvil; its -Z faces the approach),
  `ParkingSlot` (+Index), `StreetLamp`.
- Night lights: parts named `WindowGlass`, `LampGlow`, `LanternGlow`
  anywhere under TimberlineMap (Kit.window and Kit.lantern use them).
- Town props collide (lamp posts, fences, the well, barrels...): keep them
  out of truck lanes (WorldPlan.Town keeps the parking exits clear).

**Isles (IsleArt, WorldPlan.Sky)**
- `IsleTop` (PrimaryPart): a flat, colliding cylinder, top face at the
  isle's y. `SkyrootTrunk` (PrimaryPart) and `SkyrootRoots` on the
  Skyroot. The Skyroot is built around the real isle positions
  (WorldPlan.IslesFromRoot); isles keep decoration off
  WorldPlan.IsleClearPoints. The waterfall pours off `sky.waterfall.isle`.

**People (CharacterArt, NPCData, NPCService, NPCController)**
- Murph: Persistent model `Murph` under TimberlineMap with parts Head,
  Beard, Beanie, Torso, LeftArm, RightArm (QuestUI's portrait). Every NPC
  carries tag `NPC` and attributes NPCId, Route, Speed, RouteOffset,
  Scale, RootHeight, Height, TopOffset. Keepers stand behind their shop's
  Counter, Gus beside GondolaTown's Platform; walkers' routes are checked
  against WorldPlan.Town by NPCData.spec. AxeArt.Grip defines how a hand
  holds an axe.

**World state (workspace and player attributes)**
- Server publishes: `Weather`, `WeatherIntensity`, `IsNight`,
  `Vitality_<biome>` (0 to 100), `VitalityTier_<biome>` ("Thinning",
  "Healthy", "Thriving", "OldGrowth"), `SkyrootBloom`, `ElderUid`,
  `ElderWood`, `ElderBiome`, `ElderPos`. Groves: starter, hills, snow,
  volcano, grove.
- Testers set on the server: `WeatherOverride`, `WeatherOverrideIntensity`,
  `RainbowTest`.
- Player: `Cash`, `PendingCash`, `Seeds_<wood>`, `Heartseeds`,
  `FieldGuideFigures`, `SettingMusic`, `SettingSfx`, `BedCount`,
  `BedCapacity`, `SkyBin`, `Biome`.
- Lighting.ClockTime is set by every client each frame (LightingController,
  from the server clock); the server never writes it.

**WorldFX remote kinds** (server to clients; each takes a payload table)
- Weather: `Lightning` {position, struck} and `LightningWarn` {position,
  delay}.
- Forest: `SeedPop`, `Sprout`, `Struck`, `Elder`, `ElderFallen`,
  `ElderFaded`, `ElderShare`, `Royalty`, `Reveal` (fields in
  ForestService's header). Clients ignore kinds they don't know.

## Verifying without Studio
- `./scripts/check.sh`: StyLua, Selene, strict luau-lsp, Lune tests,
  ECONOMY.md. Check its exit code (piping it through `tail` hides it).
- `lune run tools/preview/export <scene>` builds a scene from the real art
  modules and writes `preview/<scene>.html` (open in a browser; drag to
  orbit, 1–9 for camera presets). `node tools/preview/render.mjs
  preview/<scene>.html [view]` screenshots it (needs Node + Playwright);
  heavy scenes (town, world) render more reliably one view per run.
  Scenes: kit, trees, terrain, world, town, buildings, trucks, props,
  isles, critters, forest, npcs, axes.
- `tools/loader.luau` gives modules a CFrame whose `lookAt` and
  `new(pos, lookAt)` behave like Roblox's (Lune 0.10.5 gets them wrong),
  so previews and specs match the game.
- Then the Studio checklist in PHASE2_NOTES.md ("The redesign").

## Where things live (who built what)
| Area | Files |
|---|---|
| World (lead) | Kit, TreeArt, TreeLogic, Shared/World (TerrainGen, WorldLayout, WorldPlan), TerrainBuilder, MapBuilder, TreeService, TreeFX, CameraShake, TownFX, GameServer, Net, RateLimiter, ProfileSchema, Client.client, default.project.json, tools/loader + preview, docs |
| Vehicles | TruckArt, TruckLayout, VehicleLogic, VehicleService, VehicleController, VehicleFX, ShopService (trailer check), scenes/trucks; specs TruckArt, TruckLayout, VehicleLogic, TrailerTow |
| Buildings | BuildingArt, scenes/town and buildings; spec BuildingArt |
| Nature & isles | PropArt, IsleArt, scenes/props and isles; specs PropArt, IsleArt |
| Characters & axes | CharacterArt, AxeArt, NPCData, NPCService, NPCController, AxeService (models), scenes/npcs and axes; specs CharacterArt, AxeArt, NPCData, NPCService |
| Environment | EnvironmentData, WeatherSchedule, CritterArt, LightingController, WeatherController, AmbientLife, WindSway, AmbientSound, WeatherService, WorldClock, SoundData additions, scenes/critters; specs EnvironmentData, WeatherSchedule, WeatherService, WorldClock |
| Living Forest | ForestData, ForestLogic, ForestArt, ForestService, ForestUI, Field Guide's Hidden Grain page, Daily/Tutorial additions, the economy model's figure average, scenes/forest; specs ForestLogic, ForestService |
| Feel & fixes (lead) | ChopController, HUD (cash pops, top row), SettingsUI, CarryController, QuestUI beacon, EconomyService (banked Robux cash), ProfileService (Studio store, receipt rollback), MonetizationService, AetherService (Featherfall, falls, forge cap, Sky Bin entries), CarryService.TakeLogs, NodeService, BiomeService |

## Status (merged to main, October 2026)
Built and passing every check; not yet played in Studio. Open items:
- **Economy:** the model runs about 1.3x over GAME_DESIGN §4's targets
  (it was about 1.23x before the Living Forest's +6% figured-wood
  average). Calibrate with a playtest first (`--calibrate`); if it holds,
  the proposed lever is Rustbucket topSpeed 26 -> 22 and Pickup 28 -> 24.
- **Sounds to pick** (silent until then): BirdsDay, CricketsNight,
  WindHowl, LavaRumble, Wings, Quack, StormCrackle, Engine.
- **Design calls taken** (change if you disagree): a storm-struck tree keeps
  its own figure if that's worth more than Stormgrain; royalties and Elder
  bonuses ignore the 2x Wood boost; isle lightning does no damage; trucks
  are owner-only.
- **Ideas not built:** showroom trucks at the Dealership (TruckArt.Build); real axes in the Tool Shed's
  rows (AxeArt in a ViewportFrame); a "Storm in 4 min" forecast badge
  (WeatherSchedule.Forecast); genes and breeding, then Skyroot Rising
  (§16).
