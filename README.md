# Lumber Game (working title)

A Lumber-Tycoon-style Roblox game, built with Claude Code + Rojo.

## Workflow

1. Install the Rojo CLI on your Mac (see https://rojo.space/docs/installation)
   and the **Rojo** plugin inside Roblox Studio (Plugins tab → search "Rojo").
2. In a terminal, from this folder: `rojo serve`
3. In Roblox Studio, open your place, click the Rojo plugin → **Connect**.
4. Edit `.lua` / `.luau` files under `src/` in VS Code (or Claude Code).
   Saving syncs into Studio within milliseconds. Press **Play** to test.

## Rules of the road

- **Files are the source of truth.** Rojo syncs filesystem → Studio.
  Don't hand-edit scripts inside Studio or the next sync overwrites them.
- File conventions (Rojo defaults):
  - `*.server.luau` → Script (runs on server)
  - `*.client.luau` → LocalScript (runs on client)
  - other `*.luau` → ModuleScript (shared, `require()` it)
- `require()` uses Roblox paths: `require(ReplicatedStorage.Shared.Foo)`,
  not relative file paths.
- It's **Luau**, not stock Lua: `task.wait()` instead of `wait()`,
  type annotations allowed, `string.split` / `table.find` exist.
- The 3D map itself lives in Studio (Workspace is not mapped here).
  Build the world in Studio; code lives here.

## Layout

- `src/ServerScriptService` — server logic (economy, chopping, data saving)
- `src/ReplicatedStorage` — shared modules, RemoteEvents/RemoteFunctions
- `src/StarterPlayer/StarterPlayerScripts` — client scripts (UI, input)
- `src/StarterGui` — UI screens

## Build a place file (no Studio sync needed)

`rojo build -o build.rbxlx`
