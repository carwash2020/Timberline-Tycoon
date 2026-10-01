# Timberline Tycoon: notes for Claude

Roblox game, Rojo + Luau. Design spec: GAME_DESIGN.md (§14 is the
implementation spec; ask Connor before deviating from its data values or
architecture). What V1 needs and where it stands: V1_PLAN.md (keep it
current). Playtest checklists: PHASE1_NOTES.md (phase 1), PHASE2_NOTES.md
(everything since; all on main). Tonight's cleanup plan: HANDOFF.md.

- Connor tests in Roblox Studio on a Mac; Claude can't run Studio. After a
  change, list exactly what to check in Studio.
- Verify before pushing: `./scripts/check.sh` (StyLua, Selene, luau-lsp
  strict type check against the Roblox API, Lune unit tests, ECONOMY.md
  current). CI runs the same script. Game code is `--!strict`.
- See an art or world change without Studio: `bash tools/preview/shoot.sh
  <scene> [view]` (scenes in `tools/preview/scenes`) writes
  `preview/<scene>-<view>.png`; compare renders before and after. On Linux
  without Rokit, `bash scripts/cloud-setup.sh` installs the toolchain.
- Tests live in `tests/*.spec.luau` (`lune run tests/run [filter]`). Put
  rules in pure modules (e.g. `Shared/ShopLogic`, `ProfileSchema`) so they
  can be tested; services are tested with `mocks` (see `ShopService.spec`).
  Add or update a spec with every rule change.
- The server owns all state; remotes carry intents only and every handler
  validates (range, ownership, rate via RateLimiter).
- Only EconomyService changes `profile.cash`; only ProfileService touches
  DataStores (via vendored ProfileStore; never edit `Vendor/`). New save
  fields go in `ProfileSchema` (type + template, and `Migrate` if old saves
  need converting).
- Balance lives in WoodData / ItemCatalog / BiomeData; shared tuning in GameConfig.
  After any balance change, re-run `lune run tools/economy` and commit the
  regenerated ECONOMY.md.
- Commit messages: `phase-N: <what changed>`.
- Scope guardrails (from Connor):
  - Gathered materials are OK, but each needs a job (a recipe input for a
    building, upgrade or forge) and a home biome (GAME_DESIGN §15).
  - The economy model's EFFICIENCY is a guess until calibrated. The
    stopwatch prints `lune run tools/economy --calibrate ...`; running it
    saves `tools/calibration.json`. Commit that file with ECONOMY.md.
  - Milestones (GAME_DESIGN §8): the core feels good, then retention
    (seasons, festivals, companies), then more content.
  - Late game, automation may out-earn hand work, inside the rules in
    GAME_DESIGN §9 (runs on what you unlocked, rare content stays manual,
    online only for now, Warehouse-capped).
  - Wallet cap: `GameConfig.CashCap` = $2,000,000. All cash goes through
    EconomyService.AddCash, which clamps and returns (credited, overflow).
