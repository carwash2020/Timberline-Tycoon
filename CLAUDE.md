# Timberline Tycoon: notes for Claude

Roblox game, Rojo + Luau. Design spec: GAME_DESIGN.md (§14 is the
implementation spec; ask Connor before deviating from its data values or
architecture). Current phase status: PHASE1_NOTES.md.

- Connor tests in Roblox Studio on a Mac; Claude can't run Studio. After a
  change, list exactly what to check in Studio.
- Verify before pushing: `./scripts/check.sh` (StyLua, Selene, luau-lsp
  strict type check against the Roblox API). Game code is `--!strict`.
- The server owns all state; remotes carry intents only and every handler
  validates (range, ownership, rate via RateLimiter).
- Only EconomyService changes `profile.cash`; only ProfileService touches
  DataStores (via vendored ProfileStore; never edit `Vendor/`).
- Balance lives in WoodData / ItemCatalog / BiomeData; shared tuning in GameConfig.
  After any balance change, re-run `lune run tools/economy` and commit the
  regenerated ECONOMY.md.
- Commit messages: `phase-N: <what changed>`.
