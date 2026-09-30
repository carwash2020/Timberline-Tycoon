# V1 plan

What V1 needs, what's done, and the order to build the rest. Keep this file
current: tick items as they land, and move anything cut to "After V1".

**V1 = a new player can go from the Rusty Axe to the forged Starfall Axe**
(about 17 hours of focused play, ECONOMY.md), in a world with every biome
on that path, and build a lumber empire on their own plot, trade with
other players, run a company with friends, fill in the Field Guide, and
spend Robux fairly. Scope set by Connor, 2026-09-30.

**Build order** (each lands on the branch with tests and a playtest
checklist in PHASE2_NOTES.md):
1. Robux purchase handling (so products can be set up in Creator Hub in
   parallel) → 2. the Field Guide → 3. the Aether Isles + materials + the
   forge → 4. plots and the empire, in slices → 5. trading → 6. companies →
   7. launch polish.

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
  pass (item 9)

### 3. Hauling upgrades on the path
- 🟡 Trailers (Pony, Ranch, Heavy Hauler): bought at the Dealership, hitched
  behind the truck, extra bed space. The model buys all three on the way to
  V1, so they're not optional. V1 hitches them rigidly (the rig turns as
  one piece); a swinging hitch is a later polish.

### 4. The V1 finale: the Aether Isles (GAME_DESIGN §10, phase 5b; in V1)
- ⬜ The Skyroot and its gondola (ride time + fee from BiomeData)
- ⬜ The isles: Lumenwood trees, Sky Shard crystal nodes (mined with an axe)
- ⬜ Cloud Chute + Sky Bin (logs go down to the sawmill) and the Featherfall
  Cloak
- ⬜ Materials inventory (Sky Shards) and the Starfall Axe forge

### 5. The Field Guide (GAME_DESIGN §11 beat 7, §13)
- ⬜ A journal of every wood: silhouettes until you find it, then its facts
  (where, HP, hardness, price, the axe you need); discovered on first fell
- ⬜ Murph hands it over at the end of the tutorial

### 6. Plots and the empire (GAME_DESIGN §9, §10; in V1)
Slices, in order:
- ⬜ Claim a plot in the plot district; base tiers (Campsite → Timber
  Empire) that grow the plot
- ⬜ Blueprint Store + placement: ghost preview, rotate, grid snap, bounds
  and overlap checked on the server; move and sell back; saved with the
  profile
- ⬜ Buildings and decor: Warehouse (stores logs and materials), Axe Rack,
  walls, lights
- ⬜ Production: Sawmill Shed (logs → planks), Workshop (planks →
  furniture), flumes linking machines, hand work vs Auto Saw ratios
- ⬜ Storefront (sell furniture while you're out) and contracts
- ⬜ Automation, online only: Apprentice Crew, self-replanting saplings,
  Warehouse-capped (§9 rules)
- ⬜ Sapling plots (tended by hand)
- ⬜ More gathered materials with a job each: Stone, Iron Ore, Resin, Ember
  Glass (tier-ups, machines, kilns)

### 7. Trading and companies (GAME_DESIGN §5, phase 7; in V1)
- ⬜ Trading: a two-player trade window (axes, materials, planks,
  furniture, cash), both confirm, a short countdown, then one swap on the
  server
- ⬜ Companies: create or join a company with friends; a name (filtered by
  Roblox), a member list, company earnings leaderboard. Needs a design
  pass with Connor first (what a company shares).
- ⬜ Lifetime earnings leaderboard (opt-in)

### 8. Fair monetization (GAME_DESIGN §7; nothing pay-to-win; in V1)
- 🟡 Purchase handling done right: receipts granted exactly once, saved with
  the profile (ProfileStore), never lost on a crash
- 🟡 Game passes: 2x Cash. ⬜ Extra Plot and Master Builder (with plots);
  ⬜ VIP axe skin and Lumberjack Truck
- 🟡 Developer products: cash packs (checked against the $2,000,000 cap
  before the prompt), 2x Wood (48 h), Instant Delivery
- ⬜ Connor: create the items in Creator Hub and put their ids in
  `Shared/StoreData.luau` (steps in PHASE2_NOTES.md)
- ⬜ Private servers (a Roblox setting, no code)
- Prices are Connor's call (the design has starting points), and each item
  must be created in Creator Hub; its id goes in `Shared/StoreData.luau`.

### 9. Launch polish (phase 9)
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

## After V1 (first updates)
- The Island + boats (palmwood; off the progression path)
- Seasons and festivals (the build plan is in GAME_DESIGN §12)

## What only Connor can do
- Play each build in Studio and report back (Claude can't run Studio)
- Decide prices, the cut line, and anything that changes the design's
  numbers
- Art in Studio, publishing, Creator Hub settings
