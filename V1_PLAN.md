# V1 plan

What V1 needs, what's done, and the order to build the rest. Keep this file
current: tick items as they land, and move anything cut to "After V1".

**V1 = a new player can go from the Rusty Axe to the forged Starfall Axe**
(about 17 hours of focused play, ECONOMY.md), in a world with every biome
on that path, with saving, shops, the tutorial, daily goals, a few fair
ways to spend Robux, and launch polish.

Status key: ✅ built and played · 🟡 built, not yet played in Studio ·
⬜ not started. Nothing is ✅ yet: Studio playtests are what turn 🟡 into ✅.

## Must have for V1

### 0. Prove the core (blocks everything else feeling right)
- 🟡 Phase 1 core loop on `main` (PHASE1_NOTES.md checklist)
- 🟡 Phase 2+ branch (PHASE2_NOTES.md checklists), then merge to `main`
- ⬜ Calibrate EFFICIENCY from a real 10-minute session (stopwatch line →
  `lune run tools/economy --calibrate …`), then re-check ECONOMY.md

### 1. Core systems (🟡 on the branch)
- 🟡 Saving (ProfileStore), wallet cap, anti-exploit rate limits
- 🟡 Axes as items + the Tool Shed
- 🟡 Trucks, the Dealership, physics driving, Truck to lot
- 🟡 Murph's tutorial
- 🟡 Daily goals and streaks
- 🟡 Tests + GitHub checks on every push

### 2. The world: biomes on the progression path (GAME_DESIGN §8 phase 5)
- 🟡 World map: 3,000-stud world, roads and signposts from the sawmill
- 🟡 The Hills (pine, maple), Snowfields (frostwood), the Volcano
  (emberwood), Phantom Grove (phantomwood, night only)
- 🟡 Biome rules: snow slows you without the Insulated Coat; the volcano
  burns without Heat Boots; the grove needs a Lantern and only exists at
  night
- 🟡 Day/night cycle, the same on every server
- 🟡 Hearth & Home: the gear shop (Lantern, Insulated Coat, Heat Boots)
- Placeholder art: every biome is code-built parts until the Studio art
  pass (item 6)

### 3. Hauling upgrades on the path
- ⬜ Trailers (Pony, Ranch, Heavy Hauler): bought at the Dealership, hitched
  behind the truck, extra bed space. The model buys all three on the way to
  V1, so they're not optional.

### 4. The V1 finale: the Aether Isles (GAME_DESIGN §10, phase 5b)
- ⬜ The Skyroot and its gondola (ride time + fee from BiomeData)
- ⬜ The isles: Lumenwood trees, Sky Shard crystal nodes (mined with an axe)
- ⬜ Cloud Chute + Sky Bin (logs go down to the sawmill) and the Featherfall
  Cloak
- ⬜ Materials inventory (Sky Shards) and the Starfall Axe forge
- The design allows shipping this as the first big update if V1 runs long;
  without it, V1 ends at the Inferno Axe (~13 h).

### 5. Fair monetization (GAME_DESIGN §7; nothing pay-to-win)
- ⬜ Purchase handling done right: receipts granted exactly once, saved with
  the profile (ProfileStore), never lost on a crash
- ⬜ Game passes: 2x Cash, VIP axe skin (cosmetic)
- ⬜ Cash packs that check the $2,000,000 cap before offering
- ⬜ Private servers (a Roblox setting, no code)
- Prices are Connor's call; the design has starting points.

### 6. Launch polish (phase 9)
- ⬜ Sounds: chop, fell, sell, buy, UI clicks; a music toggle
- ⬜ Settings menu (music, sound effects)
- ⬜ Icon and thumbnail (Claude Design prompt, then Studio renders)
- ⬜ Art pass on the code-built placeholders: trees, buildings, trucks
  (GAME_DESIGN §13, §14.7), at least the starter area and sawmill
- ⬜ Phone pass: every screen on a small phone, performance with many trees
- ⬜ Roblox settings: maturity questionnaire, devices, StreamingEnabled
  checked, API access, a fresh DataStore name for launch (wipe test saves)
- ⬜ Analytics check: funnels and economy events show up in Creator Hub
- ⬜ Bug bash with friends (a 4-6 player test), then a soft launch

## After V1 (first updates), recommended cuts
These are big, and the progression doesn't need them. GAME_DESIGN §15:
"cut phase 6–7 scope before cutting core-loop feel."
- The Island + boats (palmwood; off the progression path)
- Plots and the empire: blueprints, droppers, flumes, processing,
  warehouse, storefront, automation (phase 6)
- Trading, companies, leaderboards (phase 7)
- Seasons and festivals (the build plan is in GAME_DESIGN §12)
- The Field Guide (compendium)

## What only Connor can do
- Play each build in Studio and report back (Claude can't run Studio)
- Decide prices, the cut line, and anything that changes the design's
  numbers
- Art in Studio, publishing, Creator Hub settings
