# Timberline Tycoon

A cozy low-poly lumber tycoon for Roblox: chop trees, haul logs, sell them
at the sawmill, and grow a lumber empire. Built with Rojo + Luau.

- **What the game is:** [GAME_DESIGN.md](GAME_DESIGN.md)
- **Where Phase 1 stands:** [PHASE1_NOTES.md](PHASE1_NOTES.md)

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

The script installs Rokit if it's missing, then Rojo, StyLua, Selene and
luau-lsp, then the matching Rojo plugin into Studio. It's safe to run
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

`./scripts/check.sh` runs the formatter check, the linter and a strict type
check against the Roblox API: everything that doesn't need Studio.

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
- The Phase 1 world is built from code (`MapBuilder`). The art-directed
  world will be built in Studio later (see GAME_DESIGN §14.7).

## Layout

- `src/ServerScriptService`: server logic
  - `GameServer`: startup, player join/leave, every remote handler
  - `ProfileService`: saving (wraps the vendored `Vendor/ProfileStore`)
  - `EconomyService`: the only code allowed to change cash
  - `TreeService`, `VehicleService`, `MapBuilder`, `RateLimiter`
- `src/ReplicatedStorage/Shared`: code and data both sides use
  - `WoodData`, `ItemCatalog`: balance tables (tune here, not in code)
  - `GameConfig`: ranges, cooldowns, capacities, sound ids
  - `Net`: remote names; `Util`: helpers
- `src/StarterPlayer/StarterPlayerScripts`: client (UI, input, effects)
- `src/StarterGui`: reserved for UI built in Studio (empty for now)
- `THIRD_PARTY_LICENSES/`: licenses for vendored code

## Build a place file without Studio sync

`rojo build -o build.rbxlx`
