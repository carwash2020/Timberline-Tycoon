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
- 🟡 Live on Roblox since 1 October 2026 (Connor played it on PC and Xbox).
  Glitch wave 1 (PHASE2_NOTES.md) fixed what the first session showed:
  sunk NPCs, trucks and spawns (terrain calibration), grass through shop
  floors, walk-through props, and a plain landscape (a little more LT2).
  Next: Connor's checks on it, then wave 2 from what players hit.
- 🟡 The v2 core loop (V2_PLAN.md M1): section trees cut anywhere, wood
  dragged and carried loose on the beds, sold by volume, the spec's
  numbers. Flipped on (`CoreLoop = 2`) on 2 October 2026 without a Studio
  pass, at Connor's go-ahead; PHASE2_NOTES.md "The v2 loop goes live" has
  the checks. Old saves are bought back and topped up (MigrateV2).
- 🟡 Phase 1 core loop (PHASE1_NOTES.md checklist)
- 🟡 Phase 2+ and the October 2026 redesign, all on `main` now
  (PHASE2_NOTES.md checklists, "The redesign" first)
- ⬜ Calibrate EFFICIENCY from a real 10-minute session (stopwatch line →
  `lune run tools/economy --calibrate …`, the v2 model), then re-check
  ECONOMY.md (the model says first $1k, Cobalt and a full plot are about
  1.5x slower than V2_PLAN §17's targets: tune after calibrating)

### 1. Core systems (🟡 on `main`)
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
- 🟡 The world on generated terrain (hills, river, lake, coast, the
  Snowfields plateau, the Volcano's cone, the grove's hollow, mountains)
  with real art for every tree, building and prop (REDESIGN.md)
- 🟡 A living environment: keyframed light per hour, biome and weather;
  the weather schedule with storms and lightning; decoration, wildlife,
  wind and ambient sound (REDESIGN.md)
- 🟡 The townsfolk: Murph and eight others with routines (NPCData)

### 3. Hauling upgrades on the path
- 🟡 Trailers (Pony, Ranch, Heavy Hauler): bought at the Dealership, hitched
  behind the truck, extra bed space. The model buys all three on the way to
  V1, so they're not optional. V1 hitches them rigidly (the rig turns as
  one piece); a swinging hitch is a later polish.

### 4. The V1 finale: the Aether Isles (GAME_DESIGN §10, phase 5b; in V1)
- 🟡 The Skyroot and its gondola (ride time + fee from BiomeData), leaving
  from a station by the sawmill (plus one at the Skyroot's foot)
- 🟡 The isles: Lumenwood trees, Sky Shard crystal nodes (mined with an axe)
- 🟡 Cloud Chute + Sky Bin (logs go down to the sawmill) and the Featherfall
  Cloak (glide instead of losing your logs when you fall)
- 🟡 Materials inventory (Sky Shards) and the Starfall Axe forge (on the
  main isle for V1)
- 🟡 The Skyroot as a colossal tree holding the isles, the waterfall,
  cloud banks, rope bridges
- 🟡 Isle weather: wind and golden motes; lightning strikes there are
  marked but harmless for now (a design call, REDESIGN.md)

### 5. The Field Guide (GAME_DESIGN §11 beat 7, §13)
- 🟡 A journal of every wood: silhouettes until you find it, then its facts
  (where, HP, hardness, price, the axe you need); discovered on first fell
- 🟡 Murph hands it over at the end of the tutorial
- ⬜ A worn-journal look (GAME_DESIGN §13) in the art pass; for now it uses
  the shop panel

### 5b. The Living Forest (GAME_DESIGN §16; the twist, in V1)
- 🟡 Heartseeds, planting in stumps, the planter's share
- 🟡 Grove vitality and tiers, Elder trees, the Skyroot Bloom
- 🟡 The Hidden Grain (figured wood, bark clues, the sawmill's reveal,
  the Field Guide's page), storm-struck trees and Stormgrain
- ⬜ Genes and breeding on Sapling Plots, then Skyroot Rising (§16 "Next")

### 6. Plots and the empire (GAME_DESIGN §9, §10; in V1)
Slices, in order:
- 🟡 Claim a plot in the plot district (12 plots east of the parking lot);
  base tiers (Campsite → Timber Empire) that grow the plot, cash only
  until Stone and planks exist (tier prices are a first pass to tune)
- 🟡 Blueprint Store + placement: ghost preview, rotate, 2-stud grid snap,
  bounds and overlap checked on the server; move, and sell back for half
  (all of it within a minute); saved with the profile, plot-local so a
  layout rebuilds on whichever plot you get
- ⬜ Buildings and decor: Warehouse (stores logs and materials), Axe Rack,
  walls, lights. Placeable now as looks (with a Cabin, fences, lamps, a
  flag and more); what they do comes next
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
- 🟡 Sounds: chop, fell, sell, buy, UI clicks, ambience and music
  (SoundData). ⬜ Pick ids for the silent ones (REDESIGN.md, Status)
- 🟡 Settings menu (music, sound effects), saved with the profile
- 🟡 Feel: the chop target outline, the cash count-up and "+$" pops,
  camera shake when a tree lands
- 🟡 UI pass from the Claude Design spec: HUD, side buttons, shop panel,
  tutorial and Murph cards, beacon, custom prompts, console and phone
  sizes (UITheme). Still to do: upload the wood-grain and kraft textures
- ⬜ Icon and thumbnail: layouts are in the UI spec (6a/6b, 7a/7b); they
  need Studio renders of a big pine, an axe and a loaded Logging Rig
- 🟡 Art pass: every tree, building, truck, axe, person, prop and isle
  rebuilt in code (GAME_DESIGN §17); ⬜ tune by eye in Studio
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
