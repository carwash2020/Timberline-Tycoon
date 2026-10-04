# Timberline Tycoon

[![Checks](https://github.com/carwash2020/timberline-tycoon/actions/workflows/checks.yml/badge.svg)](https://github.com/carwash2020/timberline-tycoon/actions/workflows/checks.yml)

A cozy low-poly lumber tycoon for Roblox: chop trees, haul logs, sell them
at the sawmill, and grow a lumber empire. Built with Rojo + Luau.

- **What the game is:** [GAME_DESIGN.md](GAME_DESIGN.md) (the Living Forest twist: §16; art and world: §17)
- **The October 2026 redesign (rules, contracts, status):** [REDESIGN.md](REDESIGN.md)
- **Where Phase 1 stands:** [PHASE1_NOTES.md](PHASE1_NOTES.md)
- **How to test everything in Studio:** [PHASE2_NOTES.md](PHASE2_NOTES.md)
- **How to publish:** [LAUNCH.md](LAUNCH.md)
- **Everything V1 needs, and where it stands:** [V1_PLAN.md](V1_PLAN.md)
- **How fast the economy runs:** [ECONOMY.md](ECONOMY.md) (generated; re-run with `lune run tools/economy`)

## Set up on any computer (one command)

You need **Roblox Studio** installed and signed in; that part can't live in
the repo. Everything else is installed by the setup script at the exact
versions pinned in `rokit.toml`:

**Mac / Linux** (Terminal):
```sh
git clone https://github.com/carwash2020/timberline-tycoon.git
cd timberline-tycoon
bash setup.sh
```

**Windows:** clone the repo (or on GitHub: **Code → Download ZIP** and
unzip it), then double-click **`setup.cmd`**.

The script installs Rokit if it's missing, then Rojo, StyLua, Selene,
luau-lsp and Lune, then the matching Rojo plugin into Studio. It's safe to run
again any time. If it says GitHub is rate-limiting you (common on school
or office Wi-Fi), run `rokit authenticate github` and try again.

**First time only, per game (not per computer):** in Studio, File → New →
**Baseplate**, then File → **Publish to Roblox**, then Home → **Game
Settings** → **Security** → enable **Enable Studio Access to API
Services** → Save. Without API access everything works but progress
resets between tests. On other computers, open the same place with
File → **Open from Roblox**.

*(Optional)* VS Code extensions: **Luau Language Server** (JohnnyMorganz),
**Selene**, **StyLua**: autocomplete for the Roblox API, plus mistakes
flagged as you type.

## Everyday loop

1. `git pull` to get the latest code.
2. `rojo serve` in the repo folder (leave it running).
3. In Studio: **Plugins → Rojo → Connect**. Scripts appear under
   ServerScriptService, ReplicatedStorage and StarterPlayerScripts.
4. Press **Play**. Keep **View → Output** open; errors show up there.
5. Found a problem? Paste the Output text (or a screenshot) to Claude.

`./scripts/check.sh` runs everything that doesn't need Studio: the
formatter check, the linter, a strict type check against the Roblox API,
the unit tests (`lune run tests/run`) and a check that ECONOMY.md is
current. GitHub runs the same script on every push; a red X next to a
commit means something failed (click it to see what).

While you play in Studio, lines starting with **`[Stopwatch]`** in the Output
window time the core loop: first chop, first sale, when you could afford
each axe, and cash per minute. After ~10 minutes they also print a
`lune run tools/economy --calibrate …` line: run it in the repo folder to
measure the economy model against your real play (saved in
`tools/calibration.json`). After changing any prices or HP, run
`lune run tools/economy` to regenerate ECONOMY.md.

## Rules of the road

- **Files are the source of truth.** Rojo syncs files → Studio. Don't
  edit scripts inside Studio; the next sync overwrites them.
- File conventions (Rojo defaults):
  - `*.server.luau` → Script (runs on the server)
  - `*.client.luau` → LocalScript (runs on each player's device)
  - any other `*.luau` → ModuleScript (`require()` it)
- `require()` uses Roblox paths, e.g. `require(ReplicatedStorage.Shared.Util)`.
- It's **Luau**, not stock Lua: `task.wait()` not `wait()`; game code
  starts with `--!strict` so type mistakes are caught before Studio.
- **The server owns the truth** (cash, logs, tree HP). Clients only send
  requests ("chop this tree"), and the server checks every one.
- The whole world is built from code when the server starts: terrain from
  `Shared/World`, every model from `Shared/Art` (pure modules, so
  `tools/preview` can draw them without Studio). See REDESIGN.md.
- **See models without Studio:** `lune run tools/preview/export trees`
  (or town, trucks, world, ... ; run it with no name to list them) writes
  `preview/<scene>.html`; open it in a browser and drag to look around.
  `bash tools/preview/shoot.sh trees 2` saves a screenshot of view 2 as
  `preview/trees-2.png` instead (needs Node and Playwright).
- **On Linux without Rokit** (e.g. a cloud session): `bash scripts/cloud-setup.sh`
  installs the same tool versions.

## Layout

- `src/ServerScriptService`: server logic
  - `GameServer`: startup, player join/leave, every remote handler
  - `ProfileService`: saving (wraps the vendored `Vendor/ProfileStore`)
  - `EconomyService`: the only code allowed to change cash
  - `ProfileSchema`: the save layout, new-player template and migrations
  - `TreeService`, `VehicleService`, `MapBuilder`, `RateLimiter`
  - `MilestoneService`: the Studio stopwatch + Roblox analytics funnel
  - `AxeService`: axes as items (hotbar, drop, pick up)
  - `ShopService`: buying at the Tool Shed and Dealership
  - `QuestService`: Murph's tutorial (progress, rewards, skip)
  - `DailyService`: daily goals and streaks
  - `BiomeService`: what each biome does to you (cold, lava, darkness)
  - `WorldClock`: day and night, the same on every server
  - `MonetizationService`: Robux passes and products (receipts granted once)
  - `FieldGuideService`: the woods each player has found
  - `AetherService`, `GondolaService`, `NodeService`: the Aether Isles
    (Cloud Chute, Sky Bin, forge, falling), the gondola, crystal nodes
  - `CarryService`: the logs in each player's hands
  - `PlotService`: the plot district, claiming, placing, moving, selling
    back and growing plots
  - `MapBuilder` + `TerrainBuilder`: build the world at start-up (terrain,
    town, trees, the Skyroot and isles)
  - `ForestService`: the Living Forest (figures, storm strikes, Elders, the Skyroot Bloom)
  - `WeatherService`: the weather and lightning; `NPCService`: the townsfolk
- `src/ReplicatedStorage/Shared`: code and data both sides use
  - `WoodData`, `ItemCatalog`, `BiomeData`: balance tables (tune here, not in code)
  - `GameConfig`: ranges, cooldowns, capacities, sound ids
  - `ShopLogic`: what the shop may sell a player (both sides use it)
  - `TutorialData`: Murph's tutorial steps and lines
  - `TruckLayout`, `DriveMath`: how trucks are built and how they drive
  - `DailyData`: daily goal sizes, rewards and streak bonus
  - `WorldTime`: the in-game clock
  - `StoreData`: Robux items and their Creator Hub ids
  - `FieldGuide`: the Field Guide's pages
  - `ForgeLogic`: what forging the Starfall Axe takes
  - `PlotData`, `PlotLogic`, `BlueprintModels`: plot tiers and blueprints
    (tune here), where a blueprint may go, and how each one is built
  - `Art/`: every model, built in code (`Kit` helpers; `TreeArt`,
    `BuildingArt`, `TruckArt`, `IsleArt`, `PropArt`, `CharacterArt`,
    `AxeArt`, `ForestArt`, `CritterArt`)
  - `World/`: the world's shape (`WorldLayout` zones and roads,
    `TerrainGen` heights and materials, `WorldPlan` where everything goes)
  - `TreeLogic`: tree sizes, how trees fall, where logs land
  - `ForestData`, `ForestLogic`: the Living Forest's numbers and rules
  - `EnvironmentData`, `WeatherSchedule`: light per hour/biome/weather,
    decoration and wildlife rules, the weather schedule
  - `NPCData`: the townsfolk (looks, spots, routes, lines)
  - `VehicleLogic`: truck rules (speed check, tilt, parking, wheels)
  - `SoundData`: every sound, by name
  - `Net`: remote names; `Util`: helpers
- `src/StarterPlayer/StarterPlayerScripts`: client (UI, input, effects;
  `ShopUI` is the Tool Shed and Dealership screen, `QuestUI` the tutorial
  tracker, `VehicleController` drives your truck and `VehicleFX` animates
  every truck, `DailyUI` the daily goals, `WorldUI` biome names and the
  clock, `StoreUI` the Robux Store, `PlotUI` build mode and the Blueprint
  Store, `BlueprintPlacer` the ghost preview, `ForestUI` the Living
  Forest, `SettingsUI` music and sound settings, `ChopController` and
  `TreeFX` chopping and falling trees, `LightingController`,
  `WeatherController`, `AmbientLife`, `WindSway`, `AmbientSound` and
  `TownFX` the living world, `NPCController` the townsfolk; `HudLayout`
  is the pure geometry the HUD corner, side buttons and shop panel are laid
  out with)
- `src/StarterGui`: reserved for UI built in Studio (empty for now)
- `tools/economy.luau`: the economy calculator that writes ECONOMY.md
- `tools/preview/`: the model preview (Lune export + a three.js viewer;
  one scene per file in `tools/preview/scenes`)
- `tests/`: unit tests, run with Lune outside Roblox (`tools/loader.luau`
  fakes just enough of Roblox to load game modules)
- `scripts/check.sh`: formatter, linter, type checks, tests
- `.github/workflows/checks.yml`: runs `check.sh` on GitHub
- `THIRD_PARTY_LICENSES/`: licenses for vendored code

## Build a place file without Studio sync

`rojo build -o build.rbxlx`
