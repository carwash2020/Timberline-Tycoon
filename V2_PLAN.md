# V2_PLAN.md: the LT2-style core loop in Timberline

Owner: Connor. Plan written 2026-10-02 against `main` at `ea4ccf6`. The lead keeps it current. It covers spec §1-§21 of `LT2_Mechanics_Spec.md`, plus Connor's two later asks: much bigger, better-looking trees, and vehicles resized to carry them.

---

## Status (kept by the lead)

| Slice | State | Commit |
|---|---|---|
| Plan | on main | b13fa65 |
| M1.0 flag, Tune, v2 data, Gloamwood | live | 1260925 |
| M1.4 grab and drag (+ /spawnwood in Studio) | live | 8f4cc09 |
| M1.7a SellLogic, M1.7 SellService | live | 5aee212, ccc882a |
| M1.8a v2 tutorial, hints, HUD rules, dailies, guide, shop data | live | 2da706e |
| M1.1 + M1.2 TreeGen, SectionLogic, economy2, the tree remodel | live | e444b1b |
| M1.5 bigger trucks, lot, pad zone | live | 0077061 |
| M1.8b wiring the tutorial, dailies, shop, guide, HUD | live | 9597e0d |
| M1.6 trucks by friction (TruckLoad, BedZones, saved loads, Instant Delivery v2) | live | da28498 |
| M1.3 cut anywhere (SectionTrees, WoodService, GrowLogic, CutController, WoodFX) | live | 146a7ce |
| M1.7b Cloud Chute and forge hoppers, Sky Bin by u³, falls off the isles | live | f8b529a |
| M1.9 migration (MigrateV2, v2Credit) and the flip (`CoreLoop = 2`; economy2 is now tools/economy, v1's is tools/economy1) | live once Connor publishes; flipped without a Studio pass, at Connor's go-ahead (2 Oct 2026) | see log |
| Phase 12 VEH: trucks 1.3x, driving retuned, 13 bays in 4 sizes, sell zone 40 deep | on main | c0f865d |
| Phase 12 ATMOS: dark muted meadow, grey roads, night fog, region air, bold signs | on main | 58a5520 |
| Phase 12 TREE, ROADS, REGIONS, TOWN (LT2_RESEARCH.md plan) | landed | 2e02fcd |
| M2.2 sawmills and planks (Tool Shed stock, place on a plot; M2.1 boxes not in this slice) | in review | |
| M1.10 cleanup | after about a week live | |

**As built, where it differs from the plan (lead's notes, 2 Oct 2026):**
- Dead trees stay anchored and non-colliding while clients sink them (unanchored, they'd collapse and fight the sink).
- A felled trunk tips 4° over the cut's far edge with a spin before its physics passes to the cutter (a server impulse doesn't carry to a client-owned assembly).
- The planter's 15% share is summed over the pieces others freed and paid once, when the tree is felled (at least $1).
- Time per growth stage is growSec / 4, at boot and live.
- Falls off the isles: AetherService loses wood 40 studs under the deck (not "the sky floor - 50").
- A saved bed load has no section graph: WoodService.LinkByContact rebuilds one from which sections touch.
- The v2 forge: 60 u³ of plain lumenwood, 12 Sky Shards and $20,000 (`StarfallAxe.v2.forgeCash`, §2c).
- **Ownership (Connor, 2 Oct 2026): nobody can steal a tree you're cutting or the wood it gives.** The first cut claims a standing tree (`rec.claim`, mirrored as the model's ClaimedBy/ClaimedAt): nobody else may cut it while the claimer is in the server and has hit it within `GameConfig.TreeClaimSec` (60 s), and the toast says "<name> is cutting this tree. Find another one." (SectionLogic.ClaimBlocks). Whoever holds the claim fells it and owns every piece it frees. A player claims one tree at a time (a new claim frees their last tree, so nobody can lock up a grove), and Murph's beacon skips trees someone else is cutting. Elders stay everyone's (no claim; helpers share as §16). Loose wood is its owner's while they're in the server: nobody else may grab or cut it ("That's <name>'s wood.", GrabLogic "owned"), except off your own truck bed; once the owner leaves, the old 45 s PickupGraceSec from being cut applies, then anyone may. Ownership still lapses on wood left untouched for WoodUnownedAfterSec (WoodService). Moving someone's wood never changes who is paid.
- Boot: section trees take about 7.5 s in Lune (v1's took 1.4 s); MapBuilder prints `[MapBuilder] N section trees in X s` so a live boot can be measured. If it's over budget, speed up TreeGen and FromSkeleton before anything else.

**Day 3 (3 Oct 2026), after Connor's first Studio run of v2:**
- His client crashed on its first line (`HUD is not a valid member of PlayerScripts`): no HUD, tutorial, axe, drag or driving. His place was half-synced (new server code, Soft lighting, a client module missing), and the client could also start before its siblings arrived. Client.client now waits for every module in its folder before its first require (19d08a2; Client.spec checks the list).
- The HUD's v2 hints now know what the axe points at (loose wood, wood too hard) and whether a held piece is longer than the bed (2c40a6f).
- The client also loads each module in its own protected call (a1ba6ed): one whose top level errors is skipped with a warning instead of stopping the rest, and the module wait is 30 s for all of them together.
- VEH landed (c0f865d): every truck and trailer 1.3x (`TruckLayout.Scale`), `TurnRadiusPerWheelbase` 0.477 (each truck turns its M1.5 circle), 13 bays in 4 sizes picked by `VehicleLogic.BayChoices`, SellZone 24 x 12 x 40 (z 62-102), SellTruckRange 45, ShowBeyond 42, EXIT_GAP 3.4, Drive prompt 9. Beds carry about twice the u³ a trip, which moved ECONOMY.md toward §17 (first $1k 19 min, Cobalt 81 min, full plot 46 h) but brings the Steel Axe at 3.3 min (target 5-8): a price question for Connor.
- Axe ladder retuned (3 Oct 2026): Steel is $160 so the model buys it in the 5-8 minute window (the tutorial's loads step is $120). Obsidian's 10.2 damage out-cut the forged Starfall Axe, and Inferno was a downgrade off emberwood. Damage, reach and cooldown now climb the ladder; Starfall is the fastest cut on every wood. See ItemCatalog `v2` and ECONOMY.md.
- ATMOS landed (58a5520), per LT2_RESEARCH.md: Grass 84,125,55 / LeafyGrass 66,104,46, haul roads Pavement 170,169,165 edge to edge, the night mist +0.16 density in a grey-blue (23:00-09:30), the Volcano's air 0.55 red-orange at every hour, a cold Snowfields haze, a violet Gloam Hollow mist at 0.53, and big name signs (`BuildingArt.nameSign`, 120 px boards).
- TREE, ROADS, REGIONS and TOWN landed (LT2_RESEARCH.md plan). Box logs use each wood's bark (frostwood and lumenwood smooth, phantomwood concrete, the rest wood) and the leaf crowns are crisp cubes. Biome forests are spaced about 1.5x wider and still clear 775 trees. Haul roads (Hills, Snow, Volcano) are 28 wide, Skyroot 24, Forest Path and Plot Road 16, with flares at (30, 450) and (-20, 760). Brown boulders sit on the open grass and the filler forest is thinner. The Snowfields have a brown cliff ring with one pass, the Volcano a dark rim with one gap, the Gloam Hollow three shallow pools, and a sign at each gate. Town has a 22-wide way east of the mill to the Snow Road, a 16-wide loop south of the lot, a wider street up to the sell pad, lamps set back, and road mouths at the plaza. The first 322 trees kept their old XZ (they were placed on the old road widths, then their Y was snapped to the new ground).
- Server boot measured in Studio before this slice: 775 section trees in 0.6 s, world built in 4.6 s. This slice was not timed in Studio. Lune counts 778 tree spots and 31,409 section-tree parts (average 40.4, about 1.17x the round trees).
- M2.2 first slice (sawmills): bought at the Tool Shed ("Browse saws") into `profile.sawmillStock`, then placed from BUILD, or paid for on the plot if you have none in stock. `PlacedItem.data` is the cut (`{x, y}` in u). The panel is the owner only, in range (`SawmillSet`); permissions wait for M3. Plank prices are the §2b ratios scaled by 0.35, and never under 2.5× the log (oak is 2.5×, not 6.7×): a Rickety mill can take frostwood, and the full ratios made the first $1k about twice too fast even with a few minutes of handling per load. Not in this slice: M2.1 counters, boxes and dialogue, a "sell planks" daily, and saving loose wood on the plot (M3.2). The town mill stays the sell pad; the new road east of it is the world's, not a processing mill.

**Follow-ups after the flip (from the pre-flip review, 2 Oct 2026):**
- ~~Wood a rejoin or "Send truck home" leaves on the ground out of town is lost if the player leaves again.~~ Fixed (day 3): TruckLoad remembers each owner's left-behind pieces and saves what's still theirs and lying about as `groundLoad` (each piece where it lay); it comes back there on rejoin.
- ~~The HUD's v2 hints `tooLong`, `tooHard` and `onWood` are still always false.~~ Fixed (day 3, 2c40a6f).
- Calibrate EFFICIENCY from a real session, then tune the pacing (the model has first $1k, Cobalt and a full plot about 1.5x slower than §17).
- Fixed before the flip: the Instant Delivery button reads BedVolume under v2; the Dealership won't swap a truck with loose wood on it in town; wood on someone's bed can't be cut by others; TreesPerGrowTick 20; WorldClock's tick and each boot tree are guarded; the v1 left-behind restore is v1-only; the tutorial's wood, bed and pad beacons point at a tree when you have no wood (saves migrated mid-tutorial).

---

## 0. Decisions and ground rules

**Connor's calls**
- We rebuild the core loop the LT2 way, inside our own world.
- We keep the smooth terrain and restyle it.
- We use LT2's numbers, renamed.
- Saves are migrated, never wiped.
- Trees get much bigger and better looking. Vehicles grow to match.

**Rules this plan adds to CLAUDE.md and HANDOFF §3**

1. **One flag, live-safe.**
   - `GameConfig.CoreLoop = 1` is today's loop and stays live until the M1 flip. `2` is the section-tree loop.
   - A new pure `Shared/CoreLoop.luau` (built like `ClockOverride`) reads it. `CoreLoop.Resolve(config, attr, isStudio)` honours the workspace attribute `CoreLoop` **only in Studio**.
   - To test v2, Connor runs `workspace:SetAttribute("CoreLoop", 2)` in edit mode, then presses Play. A live server ignores the attribute. PlaceCheck warns if it was saved into the place.
   - MapBuilder resolves the loop once and sets `workspace.CoreLoopActive` before `TimberlineMap` is parented. Server and client both branch on that.
   - Every M1 slice merges to `main` while dormant, so main stays today's game until slice M1.9 flips the flag.
2. **Studio feel-tuning without code.** A new `Shared/Tune.luau`: `Tune.Get(key)` returns `GameConfig[key]`, unless Studio has a numeric workspace attribute `Tune_<key>`. Drag force, bed friction and cut numbers can be tuned in Play without edits. PlaceCheck warns about saved `Tune_*` attributes too.
3. **v2 data sits next to v1 data until the flip.**
   - Each WoodData entry and each ItemCatalog axe, truck and trailer gets a nested `v2 = {...}` table.
   - The v1 economy model ignores these tables, so `ECONOMY.md --check` stays green.
   - `tools/economy2.luau` writes `ECONOMY_V2.md`, and `check.sh` checks it too.
   - At M1.9, economy2 replaces economy and ECONOMY.md is regenerated. At M1.10 the `v2` fields are hoisted to the top level and the v1 fields are deleted.
4. **No LT2 names in `src/`, not even in comments**, because ReplicatedStorage modules ship to clients. LT2 provenance lives only in this file and in `tools/`.
   - We write our own dialogue. LT2's lines ("what are you trying to pull?" and so on) are never copied.
   - No LT2 audio, logos or assets.
5. **The timber unit.**
   - `GameConfig.WoodUnit = 1.6` studs, written "u".
   - Our trees are 1.6x LT2's in every direction. That makes them as big as Connor asked, while LT2's per-unit numbers stay exact.
   - The formulas:
     - `required = hardness * (sx/U) * (sz/U) * CutK`
     - `volume_u3 = sx*sy*sz / U^3`
     - `value = volume_u3 * price`
   - Sawmill limits and plank sizes are given in u. Characters, axe reach, plots (40-stud squares) and drag distances stay in studs.
   - Tooltips read "Oak log · 26 u³ · $39".
6. Tutorial step ids stay append-only. Profile fields are never renamed or removed, and a field's type never changes. Only EconomyService writes cash. Every remote is listed in `Net.RemoteNames` and has an entry in RateLimiter `LIMITS`.

---

## 1. Spec to code mapping

### 1a. By spec section

| Spec § | Replaces | Extends | Leaves alone |
|---|---|---|---|
| 1 Core loop | GAME_DESIGN §2 loop (fell → carry 2 → bed slots → press Sell) | | |
| 2 Architecture | `ChopTree/PickupLog/LoadToTruck/SellLogs` remotes | Net, RateLimiter, GameConfig (CoreLoop, v2 constants), tags `Wood`, `WoodSection`, `Box`, `ShopItem`, collision groups | ProfileService/ProfileStore, EconomyService as the sole cash writer |
| 3 Trees | TreeService (whole-tree HP, stump models, log spawning), TreeLogic size/HP/LogLayout/fall timing, `TreeArt.Build/Stump/Log` | TreeArt palettes and canopy builders (now `TreeArt.FromSkeleton`), TreeLogic debris flights | WorldPlan tree spots, BiomeData tree counts, WindSway/CanopyFade part names |
| 4 Woods | WoodData `treeHP/hardness/logsPerTree/pricePerLog` | WoodData `v2` (logPrice, plankPrice, hardness, growSec, core, shape) | ids, display names, colours, biomes, `respawnSec` (now the stump-to-sapling delay) |
| 5 Chopping | ChopController targeting, TreeService.ApplyChop, TreeUI HP bars, TreeFX fall animation | FaceTarget, TreeFX chips/dust/shake (moving to WoodFX), BiomeService.CanChop | AxeService.GetEquippedAxe, NodeService/MineNode |
| 6 Axes | `ItemCatalog.AxeDamage`, `biomeDamage`, chopping's use of `GameConfig.SwingCooldown` | axes `v2` (damage, range, cooldown, `vs`), ShopLogic texts | AxeService items/drop/pickup, AxeArt, the ladder order |
| 7 Sawmills/planks | (new) | PlotService placement, WoodService (planks) | |
| 8 Selling | onSellLogs/completeSale, 2x Wood "logs per tree" meaning, Instant Delivery meaning | EconomyService.AddCash, ForestService.OnSale figure reveal | wallet cap $2M |
| 9 Land | PlotData.Tiers, UpgradePlot | PlotService (slots, signs), PlotUI, PlotLogic | PlotData.Slots (12 slots, 220 apart) |
| 10 Building | PlotData.Blueprints become "furniture" | BlueprintPlacer, BlueprintModels, PlotLogic | |
| 11 Grab/buy/unbox | CarryService, CarryController, CarryPose, CarryLayout, PickupGrace, ShopUI tabs for axes/gear, BuyItem for axes/gear | ShopService (counter checkout), NPCData/NPCService (dialogue) | StoreUI (Robux) |
| 12 Vehicles | TruckLayout `logSlots`, BedLog visuals, AddBedLog/TakeBedLogs, truckBed/leftLoad, LeftLoad | TruckArt (bigger bodies, bed friction, BedZone), VehicleService hooks, pads in M4 | Drive/Heading physics, speed check, settle, parking |
| 13 Conveyors/logic | (new) | GAME_DESIGN §9 "flumes" (now the conveyor skin) | |
| 14 Saving | truckBed/leftLoad/skyBin meaning | ProfileSchema (schema, truckLoad, plot.squares/items) | ProfileStore, one profile per player (no 6 slots) |
| 15 World/gates | | WorldPlan (toll bridge, boulders, ferry, island in M6), TerrainGen restyle | map, biomes, smooth terrain, town coordinates |
| 16 Visuals/audio | | EnvironmentData/LightingController biome atmosphere, SoundData chop sounds by hardness | 20-minute day |
| 17 NPCs/shops | ShopUI browse (physical goods) | NPCData, NPCService, new DialogueData/DialogueUI | Murph and the townsfolk |
| 18 Quests/events | | QuestService (quest axe in M6), TutorialData.StepsV2 | DailyService framework, seasons plan |
| 19 Anti-exploit/perf | | RateLimiter, VehicleLogic.JudgeMove reused (WoodWatch), QualityBudgets | |
| 21 Our twist | | ForestService/ForestLogic/ForestData/ForestArt (§3i) | GAME_DESIGN §16 rules |

### 1b. By existing module

| Module (lines) | Today | v2 fate | Slice |
|---|---|---|---|
| SSS/TreeService (873) | Whole trees with HP, a stump model, 3-10 anchored logs, regrow, ghost/dormant, Decorate | **Replaced** by `SSS/SectionTrees` (standing trees: sites, growth, cuts, felling) and `SSS/WoodService` (loose pieces). SectionTrees keeps TreeService's **public API and TreeRecord shape**, so ForestService, WorldClock, WeatherService and QuestService switch with one require. Deleted at M1.10 | M1.3 |
| Art/TreeArt (817) | One builder per wood, Stump, Log, Sapling | **Extended**: `FromSkeleton(def, skel, opts)`, `CutFace`, `Notch`, `Plank`, grown-up `Sapling`. Palettes and canopy builders are reused. Build/Stump/Log go at M1.10 | M1.2 |
| Shared/TreeLogic (298) | Size classes, HP, LogLayout, fall timing, chip/leaf flights | Keep the flights, `FallDirection` and the size roll (scales 0.85/1/1.15). Delete hpMul/logDelta/LogLayout/FallProgress at M1.10 | M1.3 |
| SPS/ChopController (379) | Whole-tree targeting, ChopTree, MineNode | **Replaced** by `SPS/CutController` (section and height, MineNode kept) | M1.3 |
| SPS/TreeFX (621) | Hit wobble, animated fall, leaves, regrow spring | **Replaced** by `SPS/WoodFX`: chips in the core colour, notch progress ring, pooled leaf fall, landing shake, regrow spring, "+$" pops, figure band, death sink. The fall itself is real physics | M1.3 |
| SPS/TreeUI (147) | HP bars | Becomes the cut-progress ring, drawn inside WoodFX. File deleted at M1.10 | M1.3 |
| SSS/CarryService (162), SPS/CarryController (214), SPS/CarryPose (225), Shared/CarryLayout (99) | 2 logs welded to the torso, Load/Sell prompts, arm pose | **Replaced** by GrabService, DragController and physical zones. CarryPose is off under v2 (a reach pose is optional polish) | M1.4, deleted M1.10 |
| SSS/VehicleService (1381) | Trucks, parking, physics driving, speed check, bed list, left-behind loads | **Kept**: driving physics, speed check, settle, parking, recall. **Added**: 3 hooks for TruckLoad. **Removed at M1.10**: AddBedLog/TakeBedLogs/GetBedCount/spill/RestoreLeftLoad | M1.5, M1.6 |
| Art/TruckArt (1326), Shared/TruckLayout (279) | Bodies; `logSlots` per bedCapacity; every rig fits a 6.5x37 slot | **Resized** (§4c). Bed friction, `BedZone` parts, stakes. logSlots deleted at M1.10 | M1.5, M1.6 |
| SSS/EconomyService (185) | Sole cash writer | Unchanged | |
| SSS/ShopService (365), SPS/ShopUI (815), Shared/ShopLogic (231) | Browse UI and BuyItem for axes, trucks, trailers, gear | M1: ShopUI shows v2 prices and texts. M2: counter checkout plus boxes for axes, gear, sawmills; ShopUI keeps only the Dealership until M4. ShopLogic ladder rules kept, texts rewritten | M1.8, M2.1 |
| Shared/ItemCatalog (408) | Axes/trucks/trailers/boats/gear/materials | Gains `v2` stats and prices, `Sawmills` (M2), resized truck looks (M1.5). `AxeDamage` replaced by `AxeStats(axe, woodId) -> (damage, cooldown)` | M1.0 |
| Shared/WoodData (190) | HP/hardness/logs/$ per log | Gains `v2` (§2b, §3a) | M1.0, M1.1 |
| SSS/AxeService (439), Art/AxeArt (817) | Axes as items | Kept. M2: `Grant` is called when a box is opened | M2.1 |
| SSS/QuestService (188), Shared/TutorialData (154), SPS/QuestUI (649) | 7 steps | `TutorialData.StepsV2` (same ids, same order), new events, new beacons | M1.8 |
| SSS/ForestService (934), Shared/ForestLogic (496), Shared/ForestData (246), Art/ForestArt | Seeds, vitality, figures, storms, Elders | Ported (§3i); same rules | M1.3 |
| SSS/PlotService (531), Shared/PlotLogic (90), Shared/PlotData (316), Shared/BlueprintModels (60) | 12 slots, tiers 120-200, cash-placed decor | M2: sawmills placed from boxes (PlacedItem gains `data`). M3: 40-stud squares, plank blueprints, plot saving, permissions | M2.2, M3 |
| SSS/DailyService (202), Shared/DailyData (197) | Goals counted in logs | Goal kinds counted in u³, $ and pieces; rewards rescaled | M1.8 |
| SSS/MilestoneService (255) | Funnel, stopwatch, calibrate line | Same funnel names; the calibrate line prints `oak=<u3>` | M1.8 |
| Shared/FieldGuide (165), SSS/FieldGuideService (106) | HP, hardness, logs, $ per log, first axe | Hardness, $/u³ for logs and planks, typical tree size, "first axe to cut its trunk in 20 hits or fewer" | M1.8 |
| SSS/LeftLoad (30) | Caps restored left-behind logs | Repurposed to cap restored pieces (`MaxSavedPieces`) | M1.6 |
| SSS/PickupGrace (51) | Feller's 45 s window | Folded into `Shared/GrabLogic`; deleted M1.10 | M1.4 |
| SSS/AetherService (367) | Chute and forge take logs from hands; Sky Bin holds counted logs | Chute and forge become physical hoppers that take pieces; the bin holds volume entries | M1.7 |
| SSS/GameServer (741) | All handlers | Wiring only: `Chop` goes to SectionTrees/WoodService; pickup/load/sell move to Grab/TruckLoad/SellService | M1.3-M1.9 |
| Shared/Net (42) | 21 RemoteEvents | Adds `Chop`, `Grab`, `Release` (M1), `Dialogue` (M2), `SawmillSet` (M2), `BuyLand`, `ExpandLand`, `SetPermission` (M3), `Wire` (M5). Removes the 4 v1 names at M1.10 | M1.0+ |
| SSS/RateLimiter (97) | Per-remote limits | New entries (§12) | M1.0+ |
| SSS/ProfileSchema (220) | Schema, Template, Migrate | `schema`, `v2Credit`, `truckLoad`, `forgeWood`, `skyWood`, stats; `MigrateV2` (§14) | M1.6-M1.9 |
| tools/economy (975), ECONOMY.md (151) | HP-based model | `tools/economy2.luau`: volumes from TreeGen, hits per cut, bed volume, LT2 targets. Becomes `tools/economy` at M1.9 | M1.1-M1.9 |

---

## 2. Data model

### 2a. Units

1 u = `GameConfig.WoodUnit` = 1.6 studs. Prices are $/u³. Hardness applies per u² of cross-section. Each row below names the LT2 source its numbers come from; that column is reference only and never goes in `src/`.

### 2b. Woods (`WoodData[*].v2`)

| Our wood | LT2 source | Log $/u³ | Plank $/u³ | Hardness | growSec | Core colour / material | Why |
|---|---|---|---|---|---|---|---|
| oak | Oak | 1.5 | 10 | 2 | 240 | #E2BE84 Wood | Starter, soft, cheap. LT2 oak grows in 3-11 min; we take 4 min so the busy starter forest refills |
| birch | Birch | 2.25 | 15 | 7 | 960 | #F1E3C2 Wood | Same role. Hard for the hatchet (35 hits), which motivates the first upgrade |
| pine | Pine/Fir | 3.2 | 18 | 5.5 | 600 | #E8C98F Wood | Tall Hills conifer. Fir's grow time because ours is the common one |
| maple | Koa | 2.8 | 26.4 | 6 | 1140 | #E6C38E Wood | The Hills' premium hardwood. Slightly under pine as logs, the best mid-tier plank wood (9.4x), so "mill your maple" becomes a real choice in M2 |
| palmwood | Palm | 2.9 | 32 | 2.9 | 480 | #EFD6A2 Wood | Direct. Island arrives in M6 |
| frostwood | Frost | 9 | 106 | 10 | 360 | #E4F2FA **Ice** | Direct. The rare far-north wood |
| emberwood | Gold (swamp) row, see §18 | 5.7 | 36 | 11 | 1020 | #FFB25A **CrackedLava** | Taken: the swamp-gold row (open question 3), keeping the Inferno Axe as its specialist |
| phantomwood | Spook (twisted, leafless, limited) | 19 | 54 | 23 | 1200 (ours) | #C8B5F0 **Foil** | LT2 limits Spook to an event; ours is limited by night, the Lantern and hardness. Phantom (150/u³, one tree per server) would break a 15-tree grove |
| lumenwood | Sinister (glowing core, the rarer variant) | 25 | 90 | 30 | 1800 (ours) | #FFF6DA **Neon** | The finale must out-earn phantomwood. Cavecrawler (5.1/35) would pay less than frost. The gondola and 12 trees already provide scarcity |

The core colour is our TreeArt `heart` colour, which is also the plank colour, so our palette is kept. `respawnSec` (today's values) becomes the stump-to-sapling delay. `lifespan = {3, 6}` multiples of growSec. `shape` is in §3a.

```lua
-- WoodData entry excerpt (v2 nested until M1.10)
oak = { ..., respawnSec = 45, v2 = {
	logPrice = 1.5, plankPrice = 10, hardness = 2, growSec = 240, lifespan = { 3, 6 },
	core = "#E2BE84", coreMaterial = "Wood",
	shape = { --[[ §3a ]] },
} },
```

### 2c. Axes (`ItemCatalog.Axes[*].v2`)

The ladder order is unchanged, so `bestAxeTier` keeps its meaning. LT2's rows are mapped one tier down. Our display names therefore never sit on the LT2 axe of the same name.

| Our axe | LT2 row | Price | Damage | Range | Cooldown | Specialist |
|---|---|---|---|---|---|---|
| RustyAxe | Basic Hatchet | free (LT2 $12) | 0.2 | 4.8 | 0.65 | |
| SteelAxe | Plain Axe | 90 | 0.55 | 6 | 0.73 | |
| HardenedAxe | Steel Axe | 190 | 0.93 | 8 | 0.70 | |
| SilverAxe | Hardened Axe | 550 | 1.45 | 8 | 0.65 | |
| CobaltAxe | Silver Axe | 2,040 | 1.6 | 10 | 0.48 | |
| GoldAxe | quest-axe stats (sold here) | 7,720 | 1.68 | 10 | 0.40 | |
| ObsidianAxe | "best generalist" event axe | 11,000 (ours; LT2 has no price) | 3.4 | 12 | 0.7 | retuned: 10.2 out-cut Starfall |
| InfernoAxe | Fire Axe | 14,400 | 4.6 | 14 | 0.5 | emberwood 7.5 / 0.4 |
| StarfallAxe | Bird Axe | forged | 6.5 | 16 | 0.35 | emberwood 9.5, lumenwood 12 |
| (M6 quest axe, off the ladder) | Amber Axe (slow heavy hitter) | quest | 3.73 | 9 | 1.25 | |

```lua
-- ItemCatalog.Axes[*].v2
RustyAxe    = { v2 = { price = 0,     damage = 0.2,  range = 4.8, cooldown = 0.65 } },
SteelAxe    = { v2 = { price = 160,   damage = 0.55, range = 6,   cooldown = 0.73 } },
HardenedAxe = { v2 = { price = 190,   damage = 0.93, range = 8,   cooldown = 0.70 } },
SilverAxe   = { v2 = { price = 550,   damage = 1.45, range = 8,   cooldown = 0.65 } },
CobaltAxe   = { v2 = { price = 2040,  damage = 1.6,  range = 10,  cooldown = 0.48 } },
GoldAxe     = { v2 = { price = 7720,  damage = 1.68, range = 10,  cooldown = 0.40 } },
ObsidianAxe = { v2 = { price = 11000, damage = 3.4,  range = 12,  cooldown = 0.7 } },
InfernoAxe  = { v2 = { price = 14400, damage = 4.6,  range = 14,  cooldown = 0.5,
	vs = { emberwood = { damage = 7.5, cooldown = 0.4 } } } },
StarfallAxe = { sold = false, v2 = { price = 0, damage = 6.5, range = 16, cooldown = 0.35,
	vs = { emberwood = { damage = 9.5 }, lumenwood = { damage = 12 } },
	forge = { cash = 20000, wood = { lumenwood = 60 }, materials = { SkyShard = 12 } } } },
-- ItemCatalog.AxeStats(axe, woodId): (damage, cooldown); a `vs` entry overrides either field
```

**Hits to cut a mature trunk at its base**, `ceil(hardness * (t/1.6)^2 / damage)`, with t from §3a. Time per cut is (hits - 1) x cooldown. Emberwood uses hardness 11 (Rusty 124, Steel 45, Hardened 27, Silver 18, Cobalt 16, Gold 15, Obsidian 8, Inferno 4, Starfall 3). SectionLogic.spec pins the table.

| Axe | oak 2.0 | birch 1.6 | pine 2.6 | maple 2.4 | palm 1.8 | frost 2.2 | ember 2.4 | phantom 2.0 | lumen 2.6 |
|---|---|---|---|---|---|---|---|---|---|
| Rusty | 16 | 35 | 73 | 68 | 19 | 95 | 124 | 180 | 397 |
| Steel | 6 | 13 | 27 | 25 | 7 | 35 | 45 | 66 | 145 |
| Hardened | 4 | 8 | 16 | 15 | 4 | 21 | 27 | 39 | 86 |
| Silver | 3 | 5 | 11 | 10 | 3 | 14 | 18 | 25 | 55 |
| Cobalt | 2 | 5 | 10 | 9 | 3 | 12 | 16 | 23 | 50 |
| Gold | 2 | 5 | 9 | 9 | 3 | 12 | 15 | 22 | 48 |
| Obsidian | 1 | 3 | 5 | 4 | 2 | 6 | 8 | 11 | 24 |
| Inferno | 1 | 2 | 4 | 3 | 1 | 5 | **4** | 8 | 18 |
| Starfall | 1 | 2 | 3 | 3 | 1 | 3 | **3** | 6 | **7** |

### 2d. Trucks and trailers

Prices are in `v2.price`. Body sizes are in `look` and land live in M1.5 (§4c).

```lua
Rustbucket = { v2 = { price = 0 } },      -- ours: LT2 has no free truck
Pickup     = { v2 = { price = 400 } },    -- LT2 starter pickup
ScoutATV   = { v2 = { price = 2500 } },   -- ours, no LT2 analog
Flatbed    = { v2 = { price = 5000 } },   -- LT2 long pickup
LoggingRig = { v2 = { price = 19000 } },  -- LT2 biggest hauler
PonyTrailer = { v2 = { price = 1800 } }, RanchTrailer = { v2 = { price = 6000 } }, HeavyHauler = { v2 = { price = 13000 } },
-- bedCapacity stays only for the v1 loop; v2 shows bed size in studs
```

### 2e. Sawmills (M2, `ItemCatalog.Sawmills`)

Limits are in u.

```lua
SawmillRickety = { displayName = "Rickety Sawmill",     priceCash = 130,   maxLength = 10.9, maxWidth = 1.4, maxX = 1.8, maxY = 1.2 },
SawmillSturdy  = { displayName = "Sturdy Sawmill",      priceCash = 1600,  maxLength = 10.9, maxWidth = 1.6, maxX = 2.4, maxY = 1.6 },
Millmaster100  = { displayName = "Millmaster 100",      priceCash = 11000, maxLength = 10.9, maxWidth = 2.0, maxX = 3.0, maxY = 2.0 },
Millmaster200  = { displayName = "Millmaster 200",      priceCash = 22500, maxLength = 10.9, maxWidth = 2.6, maxX = 3.0, maxY = 2.6 },
Millmaster200L = { displayName = "Millmaster 200 Long", priceCash = 86500, maxLength = 18.9, maxWidth = 2.6, maxX = 3.0, maxY = 2.6 },
-- GameConfig: PlankStep 0.2, PlankMinX 0.6, PlankMinY 0.4 (u)
```

In studs, the Rickety takes an oak trunk (2.0 < 2.24) but not a pine base (2.6). Elders need a Millmaster 200 (4.16 studs).

### 2f. GameConfig additions (M1.0)

```lua
CoreLoop = 1, WoodUnit = 1.6, StartingCash = 20,
-- cutting
CutK = 1, CutWindow = 0.6, CutEdge = 0.3, MaxCutsPerSection = 2, MinPieceVolume = 0.05, -- studs; volume in u³
FallNoCollideSec = 2.5, FellImpulse = 8, LeafDropSec = 1.5,
-- wood physics
WoodDensity = 0.15, WoodFriction = 0.8, WoodElasticity = 0.05, BedFriction = 1.0, BedAutoWeld = false,
-- grab
GrabRange = 12, HoldMin = 3, HoldMax = 14, ReleaseDistance = 20, DragForcePerMass = 400, DragForceCap = 4000,
DragResponsiveness = 30, DragMaxSpeed = 40, ReleaseKeepOwnerSec = 2, -- PickupGraceSec 45 stays
-- wood lifetime and caps
WoodUnownedAfterSec = 600, WoodDespawnAfterSec = 300, MaxWoodPiecesPerPlayer = 150, MaxWoodPartsServer = 2500,
WoodMaxSpeed = 80, WoodJudgeEvery = 0.5, SellPollSec = 0.25, MaxSavedPieces = 40, MaxSavedSections = 300,
-- growth
GrowTickSec = 5, GrowStages = 4, TreesPerGrowTick = 12, PreDeadAt = 0.9, DeadSinkSec = 4,
-- later phases
PlankYield = 1, PlankStep = 0.2, PlankMinX = 0.6, PlankMinY = 0.4,
FirstPlotPrice = 100, ExpansionPriceStep = 3000, PlotSquare = 40, PlotGrid = 5, BlueprintPricePerUnit = 10,
VehicleRespawnFeeRate = 0.02, TollFee = 100, TollSeconds = 180, FerryFare = 400, FerryIntervalSec = 360,
BlastingChargePrice = 220, BoulderRespawnSec = 1200, WaterDamage = 15, WaterTickSec = 1.5,
ConveyorSpeed = 4, LogicEvalsPerTick = 200, LogicTickSec = 0.1, MaxConveyorsPerPlot = 150, MaxLogicPerPlot = 200,
```

- Expansion k costs 3000 x k for k = 1..24. The full plot totals $900,100.
- These stay as they are: CashCap $2M, the 20-minute day, `SwingCooldown` (crystal nodes and the v1 model only).
- The wood drag lift limit is about 20 mass. At density 0.15 that is about 130 studs³, so an oak trunk lifts and a whole pine trunk drags along the ground.

### 2g. Names (LT2 → ours)

| LT2 | Ours |
|---|---|
| Lumberland | Timberline |
| Main store / keeper | Tool Shed / Tink |
| Land store / keeper | Land Office / Ada (new, M3) |
| Furniture store / keeper | Hearth & Home / Hazel |
| Vehicle store / keeper | Dealership / Dale |
| Misc shack / keeper | Odds & Ends / Rosa (M6) |
| Logic store / keeper | Sparkworks / Pip (M5) |
| Ferry captain, toll keepers | Cap'n Moss, Old Tolly (M6) |
| Wood dropoff | the sell pad at Millie's mill |
| Shabby / Fair / Sawmax 01 / 02 / 02L | Rickety / Sturdy / Millmaster 100 / 200 / 200 Long |
| Dynamite | Blasting Charge |
| Quest axe | Hermit's Maul (M6) |
| Shrine, strange man, void cave | The Lantern Shrine, the Wanderer, the Gloam Pit (M6) |
| Rare colour "Hot Pink" | Blossom Pink, 1 in 500 |
| Phantom Wood | phantomwood (rename the display name: open question 1) |

---

## 3. Section trees (M1): bigger, remodelled, cut anywhere

### 3a. Sizes and art spec per wood

- The player is about 5 studs. Heights are mature trees across the size roll (0.85 / 1 / 1.15 at 25/50/25%).
- Sections are **Blocks** (square cross-section, length on the part's Y axis): LT2's look, exact volumes, logs that stack instead of rolling, planks, and the cheapest collision.
- What keeps it cozy:
  - Per-section yaw twist.
  - Bark colour varied ±4% per section with `Kit.vary`.
  - Chunky root flares.
  - Big multi-part leaf clusters (`Kit.blob`, 3-5 parts each).
  - Today's palettes, glow, bark details and conifer tiers.
- The core colour shows only on cut faces and in notches.

Shape fields (the spec's Appendix A plus ours):
- `trunkSegments`: the trunk is split into that many sections.
- `leader`: excurrent trees keep a straight leader, and side branches come off it.
- `taper`: thickness multiplier per trunk segment.
- `lean`: palms bend.
- `splitChance[d]`: the chance at depth d after the trunk.
- `canopy`: the builder that dresses the tips.

```lua
oak = { height = { 22, 30 }, trunkThickness = 2.0, trunkLength = 9, trunkSegments = 2, taper = 0.9,
	maxDepth = 3, splitChance = { 1.0, 0.75, 0.45 }, minSplits = 2, maxSplits = 3, branchAngle = 38, angleJitter = 10,
	twistiness = 8, firstBranchLength = 7, lengthDecay = { 0.62, 0.82 }, thicknessDecay = 0.68, minThickness = 0.6,
	canopy = "clusters", leafSize = 7.5, clusterParts = { 3, 5 }, flares = 5, maxSections = 18,
	leafColors = { "#5DA24A", "#6FB352", "#4C8F3E", "#86BF57" }, bark = "#7A5230" }, -- broad round dome, crown ~20 wide
birch = { height = { 24, 32 }, trunkThickness = 1.6, trunkLength = 15, trunkSegments = 3, taper = 0.88, leader = true,
	maxDepth = 2, splitChance = { 0.7, 0.5 }, minSplits = 1, maxSplits = 2, branchAngle = 25, twistiness = 5,
	firstBranchLength = 5, lengthDecay = { 0.5, 0.7 }, thicknessDecay = 0.55, minThickness = 0.5,
	canopy = "clusters", leafSize = 5.5, clusterParts = { 3, 4 }, barkMarks = 6, flares = 3, maxSections = 14,
	leafColors = { "#A6CE5C", "#BCD96B", "#8EBF4E", "#D2DF7A" }, bark = "#D8D2C4", accent = "#2E2A28" }, -- tall airy column
pine = { height = { 45, 60 }, trunkThickness = 2.6, trunkLength = 46, trunkSegments = 6, taper = 0.86, spire = 6,
	maxDepth = 0, canopy = "tiers", tiers = 5, tierSides = 5, firstTierAt = 12, tierRadius = { 9.5, 3 }, tierHeight = 9,
	flares = 3, maxSections = 8, leafColors = { "#2F7A3D", "#3A8A47", "#276B36", "#45975A" }, bark = "#6B4A2F" }, -- clear trunk to 12, then cone
maple = { height = { 24, 32 }, trunkThickness = 2.4, trunkLength = 8, trunkSegments = 2, taper = 0.92,
	maxDepth = 3, splitChance = { 1.0, 0.8, 0.5 }, minSplits = 2, maxSplits = 3, branchAngle = 42, twistiness = 12,
	firstBranchLength = 7, lengthDecay = { 0.6, 0.8 }, thicknessDecay = 0.7, minThickness = 0.6,
	canopy = "clusters", leafSize = 8, clusterParts = { 4, 5 }, flares = 5, maxSections = 22,
	leafColors = { "#D88F2C", "#C8642A", "#E5A33B", "#B84A24", "#EDBB4C" }, bark = "#7A5230" }, -- forked, wide flat-topped fire crown ~26 wide
palmwood = { height = { 26, 36 }, trunkThickness = 1.8, trunkLength = 28, trunkSegments = 7, taper = 0.94, lean = 0.2,
	maxDepth = 0, canopy = "fronds", fronds = 8, frondLength = 11, coconuts = 3, rings = 4, maxSections = 8,
	leafColors = { "#3FAE5A", "#52BF66", "#33964B" }, bark = "#8A6A45", accent = "#7A5A36" }, -- curved trunk, drooping tuft
frostwood = { height = { 40, 52 }, trunkThickness = 2.2, trunkLength = 38, trunkSegments = 6, taper = 0.85, spire = 5,
	maxDepth = 0, canopy = "snowtiers", tiers = 4, tierSides = 5, firstTierAt = 10, tierRadius = { 8, 2.5 }, snowCaps = 2,
	flares = 3, maxSections = 8, leafColors = { "#3F7FA6", "#4F90B5", "#2F6E96", "#5B9CC0" }, bark = "#485462", accent = "#FFFFFF" },
emberwood = { height = { 24, 32 }, trunkThickness = 2.4, trunkLength = 10, trunkSegments = 2, taper = 0.9,
	maxDepth = 2, splitChance = { 1.0, 0.6 }, minSplits = 3, maxSplits = 3, branchAngle = 34, elbow = 20, twistiness = 15,
	firstBranchLength = 6, lengthDecay = { 0.65, 0.85 }, thicknessDecay = 0.62, minThickness = 0.6,
	canopy = "embers", leafSize = 6.5, clusterParts = { 4, 5 }, cracks = 5, flares = 5, maxSections = 14,
	leafColors = { "#FF7A1A", "#F2601A", "#FF9A33", "#E04A12" }, bark = "#3A2A24", glow = "#FF8A2A" }, -- crooked, smouldering
phantomwood = { height = { 22, 30 }, trunkThickness = 2.0, trunkLength = 8, trunkSegments = 2, taper = 0.85,
	maxDepth = 3, splitChance = { 1.0, 0.7, 0.4 }, minSplits = 2, maxSplits = 3, branchAngle = 48, twistiness = 28,
	firstBranchLength = 6, lengthDecay = { 0.6, 0.85 }, thicknessDecay = 0.6, minThickness = 0.5,
	canopy = "wisps", wisps = 5, pods = 3, flares = 5, maxSections = 22,
	leafColors = { "#7A4FD0", "#6A3FC0", "#9468E0", "#5A34A8" }, bark = "#2A2138", glow = "#55F2E0" }, -- bare and twisted
lumenwood = { height = { 34, 44 }, trunkThickness = 2.6, trunkLength = 20, trunkSegments = 3, taper = 0.9,
	maxDepth = 3, splitChance = { 0.9, 0.5, 0.3 }, minSplits = 2, maxSplits = 3, branchAngle = 30, twistiness = 6,
	firstBranchLength = 7, lengthDecay = { 0.55, 0.75 }, thicknessDecay = 0.65, minThickness = 0.6,
	canopy = "glowtiers", leafSize = 7, veins = 6, flares = 5, maxSections = 18,
	leafColors = { "#FFF4C2", "#FFE89A", "#FFF9DC", "#F7D97A" }, bark = "#F2E6C8", glow = "#FFE7A0" }, -- tall, pale, layered light
```

**Elders:**
- `ForestData.Elder.scale = 1.7` and `depthBonus = 1` for broadleaves. Total height is capped at 95 studs, so an Elder pine is about 88 studs with a 4.4-stud trunk.
- Always figured, with an aura.
- `maxSections` still holds, up to the hard cap of 40.

**Readable at 50 studs:** oak is a round dome, birch a pale column, pine a dark cone, maple a wide orange table, palm a curved tuft, frostwood a blue cone with white caps, emberwood glows orange and crooked, phantomwood is bare violet with teal pods, lumenwood is gold and layered.

### 3b. Generation: `Shared/TreeGen.luau` (pure)

- `TreeGen.Skeleton(woodId, seed, scale) -> Skeleton`.
- Each section is `{ id, parent, children, depth, cf, length, thickness, dress }`. `cf` is the bottom centre with Y up the branch, relative to the tree base. `dress` lists the leaf, tier and detail specs attached to that section.
- Trunk: `trunkSegments` sections, each tapered and twisted by half the twistiness.
- After the trunk, the spec's `grow(section, depth)`:
  - Stop and dress a leaf cluster if depth ≥ maxDepth, or sections ≥ maxSections, or thickness < minThickness.
  - Otherwise split with `splitChance[depth]` into n children. `leader` keeps child 1 straight (thickness x 0.85), and the others branch at `branchAngle ± angleJitter`, spread evenly around the parent's yaw.
  - Otherwise continue straight with twist noise.
- Rejected: any section end below y 0.5, and any first branch below 8 studs (trucks are about 8 tall) on woods with roads nearby.
- `TreeGen.AtStage(skel, s)` for s in {0.25, 0.5, 0.75, 1}: hide sections with depth > (maxDepth + trunkSegments) x s, and scale lengths and thicknesses by s. Leaves keep their size until the first split shows. Below 0.25 the tree is `TreeArt.Sapling` (not cuttable).
- Randomness only from `Kit.rng(seed + k)`. CFrames built with `fromMatrix` (the Lune lookAt shim gotcha).

### 3c. Building the model: `TreeArt.FromSkeleton(def, skel, opts)`

**Sections**
- Parts named `Section`, tagged `WoodSection`, attribute `Section` = id.
- Material Wood in bark colour.
- Anchored, CanCollide true, CanQuery true, CanTouch false.
- In collision group `Wood`.

**Dress**
- Leaf clusters are parts named `Leaves`, `Frond` or `Facet`, or sit inside `Tier` models. Those names are what WindSway and CanopyFade look for.
- Each dress part has attribute `Section` (the section it rides on), CanCollide false, CanTouch false, CanQuery true, and collision group `Leaves` so chop rays skip them.
- Root flares go on section 1. Birch marks, ember cracks and lumen veins go on trunk sections.
- PointLights and particles stay where they are today (no shadows).

**Model**
- Model tagged `Tree`, `ModelStreamingMode = Atomic`.
- PrimaryPart = section 1.
- Attributes: `Uid, WoodId, Stage, Scale, Felled, Dormant, PlanterId, Elder, HomePivot`.

**Part budgets per tree**, max over 200 seeds x 3 sizes, Elder included. The weighted average must stay at or below about 48, about today's tree total.

| Wood | maxSections | Budget (all parts) | Today's max |
|---|---|---|---|
| oak | 18 | 46 | 27 |
| birch | 14 | 40 | 24 |
| pine | 8 | 56 | 44 |
| maple | 22 | 52 | 28 |
| palmwood | 8 | 32 | 28 |
| frostwood | 8 | 66 | 60 |
| emberwood | 14 | 46 | 41 |
| phantomwood | 22 | 48 | 33 |
| lumenwood | 18 | 44 | 31 |

There are no stump models any more: the stub is the cut root section.

### 3d. Cutting (server authoritative)

**`Chop(part, hitPos, normal)` in GameServer under v2**, checked in this order:
1. RateLimiter `Chop` (6/s).
2. `AxeService.GetEquippedAxe`.
3. Cooldown from `ItemCatalog.AxeStats(axe, woodId)` on the `nextSwingAt` schedule with `SwingTolerance`.
4. `part` is a known section, through `SectionTrees.FromPart` or `WoodService.FromPart`.
5. `|HRP - hitPos| ≤ axe.v2.range + RangeTolerance`.
6. `hitPos` lies inside the section's box grown by 0.6.
7. One line-of-sight ray from the head to `hitPos` hits the same section.
8. `BiomeService.CanChop`.
9. Damage > 0. Zero gives a clink and the toast "This wood needs a special axe".
10. For a loose piece, the grab permission (§4a).

**Applying the swing (`SectionLogic`, pure)**
- `h = clamp(localY + L/2, CutEdge, L - CutEdge)`.
- Find a cut on that section within ±CutWindow, else add one. At most 2 cuts per section; a third replaces the one with the least damage.
- Add damage and record `damageBy[userId]` for the cut and for the whole tree.
- `required = hardness * (sx/U) * (sz/U) * CutK`.
- Fire WorldFX `Cut {part, pos, normal, woodId, progress}`.
- If damage ≥ required, split.

**SplitStanding(tree, s, h)**
- Resize s to length h, bottom fixed, still anchored.
- Make Q, the upper part, with length L - h, same thickness, rotation and colour. Q takes over s's children.
- Component B = Q plus its descendants plus their dress. It becomes a WoodService piece.
- If s is a trunk segment (depth < trunkSegments), the tree is **felled**. What stays standing is the stub; there is no separate stump model.

**SplitPiece(piece, s, h)** works the same way on the piece's local graph, using the parts' live CFrames. Cutting one edge of a tree graph always leaves exactly two components:

```
low  = s resized to h         -- keeps s.parent
high = new part, L - h long   -- takes s.children
A = flood fill from low, B = flood fill from high
rebuild two models, re-weld each to its largest section,
copy the assembly's linear and angular velocity onto both
```

- A component smaller than `MinPieceVolume` becomes chips and is destroyed.
- Cuts on the split section are dropped. Cuts elsewhere keep their notches.
- Who a new piece belongs to (`Owner`): the top damage contributor to the finishing cut, the same rule as `ForestLogic.Feller`, so a last swing can't steal it. Cutting a loose piece keeps its owner.

### 3e. Notches and cut faces

**Notch**
- Part `Notch` with attributes `Section, Height, Damage, Required`.
- Size: depth along the hit face's local axis = t x min(0.95, damage/required), 0.35 tall, t wide.
- Flush with the face it was cut from, coloured core shaded -0.25.
- Anchored on a standing tree; welded and massless on a loose piece.
- WoodFX draws the progress ring from its attributes.

**CutFace**
- On each new end: a thin plate, 0.06 thick, 0.86t square, in the core colour and core material (Ice, CrackedLava, Foil, Neon).
- Massless, CanCollide false, CanQuery false.
- Two parts per cut. Planks are all core.

### 3f. Felled pieces become physics wood (`SSS/WoodService.luau`)

**The Model**
- `Wood_<uid>` under `TimberlineMap/Wood`, tag `Wood`, Atomic.
- PrimaryPart = the largest section. Every part is welded (WeldConstraint) to it and unanchored.
- `CustomPhysicalProperties(WoodDensity, WoodFriction, WoodElasticity)`.
- Attributes: `Uid, Owner (UserId, 0 = nobody), WoodId, Kind ("log"|"plank"), Volume (u³), Value ($), Figure?, HeldBy (0), Elder, LastInteracted`.

**The server record** holds the graph, `ownerId`, `lastHolderId`, `figure`, `boost` (2x Wood), `planterId`, `treeUid`, `createdAt`, `lastInteracted`, `lastGood`/`lastGoodAt` for WoodWatch, and `selling`. Only the record is trusted; attributes are for display.

**The fall**
- The new piece's network owner is set to the cutter for 3 s.
- `FellImpulse` is applied at the top, along `TreeLogic.FallDirection` (away from the cutter).
- Collision group `WoodFalling` (doesn't collide with `Players`) for `FallNoCollideSec`, then `Wood`.
- Leaves are destroyed after `LeafDropSec`. WorldFX `LeafFall` makes clients flutter pooled leaves, which saves parts and physics.
- On landing, WorldFX `Felled {pos, mass}` drives the creak and crash, and a camera shake within 40 studs if the mass is over 5.

### 3g. Despawn and caps

- Off any plot and untouched for `WoodUnownedAfterSec` (10 min): owner set to 0.
- Unowned and untouched for another `WoodDespawnAfterSec` (5 min): destroyed.
- "Touched" means grabbed, cut, carried on a truck bed while it's driven, or resting on its owner's bed (bed wood never ages).
- Over `MaxWoodPiecesPerPlayer` (150) or `MaxWoodPartsServer` (2,500), the oldest unowned pieces go first, then the owner's oldest untouched ones.
- Wood that falls below the sky biome's floor minus 50 is lost to the clouds.

### 3h. Saplings, growth, death

**Sites**
- Every `WorldPlan.Trees()` spot and every Sky lumenwood is a site. The deterministic world and the BiomeData counts stay.
- At boot: 85% of sites are mature, 15% at a random growth stage.

**Life cycle**
1. Felled: the stub stands for `respawnSec` (today's values).
2. Then a sapling grows through 4 stages over `growSec`. The server rebuilds parts per stage on a 5 s tick, at most 12 trees per tick.
3. Growing trees can be cut and are worth less. A tree that has been cut stops growing.
4. At 90% of its lifespan (`lifespan` x growSec) the leaves drop.
5. At 100%: Dead. Bark goes black and glow woods turn dull blue. Sections are unanchored with no Wood tag (they can't be cut, grabbed or sold). Clients sink them over `DeadSinkSec`, then the server destroys them.
6. The site regrows after `respawnSec`.

Existing behaviour carried over: ghost-until-clear on regrow, `SetBiomeDormant` (the Phantom Grove), `HoldRegrow` (the tutorial's stump hold), `StumpHold`.

### 3i. The Living Forest

**Felling and Heartseeds**
- **Felled = the first cut through a trunk segment.** `OnFelled(feller, rec, pieceUids)` fires once, with the feller decided by `ForestLogic.Feller` over the tree's `damageBy`.
- What fires there, as today: Heartseeds (`SeedDrop` facts: large = scale ≥ 1.1, storm, steward), vitality `FellDelta`, Field Guide discovery, the quest, daily and milestone `treeFelled` events.
- Cuts on limbs only are "limbing" and give no seeds.

**Planting**
- `PlantSeed(treeUid)` on a stub, as today.
- After `ForestLogic.SproutSeconds` (8 s in the groves) `SectionTrees.Regrow(uid, planterId, { stage = 1 })` brings the tree back **mature**, while natural regrowth takes `growSec`. That makes planting far stronger than before, which is the twist doing its job.

**Planter's share:** whenever someone else frees a piece from a tree you planted, you get 15% of that piece's base value (`ForestLogic.Royalty(baseValue)`). The steward rules are unchanged.

**Hidden Grain (figured wood)**
- The figure is rolled when the tree grows (`ForestService.grow`) and kept server-side.
- Bark clues (ForestArt) are welded to the trunk sections, so they fall with the piece.
- Every piece cut from a figured tree gets `Figure`. Clients draw a coloured band on figured pieces (no server parts).
- Value is multiplied by `ForestLogic.Multiplier`. The sell pad reveals the figure ("BIRDSEYE MAPLE x2!") through `ForestService.OnSale`.
- Planks keep the figure (M2).

**Storms:** `Strike(position)` marks the nearest standing tree for 2 minutes. Pieces freed in that window are Stormgrain, and the felling gives +1 seed.

**Elders**
- `SectionTrees.SpawnTree(wood, cf, { elder = true, temporary = true })` at scale 1.7.
- Helpers who did 10% or more of `damageBy` get 2 seeds and 10% of the freed volume's value.
- Elder pieces can be grabbed by anyone at once.
- They fade, using the death sink, after 15 minutes or at dawn.

### 3j. Preview-render checks (M1.2; the gate before M1.3 merges)

New scene `tools/preview/scenes/sections.luau`. Each check is a spec or a render, and the merge summary lists pass/fail with the PNG paths.

**Views**
1. All 9 woods mature, beside an R15 dummy (CharacterArt), at eye level.
2. The same from 50 studs (readability).
3. Small, normal and large of oak, pine and maple.
4. Growth stages (sapling, 0.25 to 1) for oak and pine.
5. Elder oak, pine and frostwood with the dummy.
6. A felled oak lying on the ground with its stub, cut faces and one half-done notch.
7. Bucked logs sized to each truck tier, on the M1.5 beds.
8. A Starter Forest patch from the real WorldPlan spots, at eye level.
9. Night: emberwood, phantomwood and lumenwood glow.

**Specs (TreeGen/TreeArt)**
- Mature heights are inside `height` for every seed and size. Elders are 1.6-1.7x.
- Trunk base thickness matches the table within ±5%.
- Canopy width/height bands: oak ≥ 0.7, birch ≤ 0.45, pine and frostwood conical (width shrinking up the tiers), maple ≥ 0.85.
- Budgets per §3c.
- Every dress part's `Section` exists and the part sits within leafSize of that section's top.
- No section below ground.
- At least 3 distinct skeletons in 5 seeds of each wood.
- Leaves never collide; sections always do.

**Renders**
- Before/after: trees 1-6 vs sections 1-9. Also world 3 (Starter Forest), 4 (Hills), 5 (Snowfields), 7 (isles), and town 1 (the protected spawn view: the sawmill between its lamps with the Skyroot showing; town greenery keeps its current scale).

**World parts:** `lune run tools/preview/export world` must stay at or under 31k (about 28k today). The weighted per-tree average is at most 48.

**Connor approves view 1 and view 2** before M1.3 merges.

---

## 4. Grab, drag and trucks

### 4a. Grab and drag (replaces CarryService and the Pick up prompts)

**Client: `SPS/DragController`**
- The axe must be put away to drag (LT2's rule). With an axe out, clicking a loose piece chops it, and a hint says "Put your axe away (1) to drag".
- Mouse: hold the left button on a `Wood` part. Touch: tap and hold for 0.25 s; the input is consumed so the camera doesn't turn. Gamepad: hold L2 at the centre reticle.
- On grab:
  - Fire `Grab(part, hitPos)`.
  - Create an Attachment at the hit point plus a local Neon ball.
  - Add an `AlignPosition` (OneAttachment; MaxForce = `min(mass * DragForcePerMass, DragForceCap)`; Responsiveness 30; MaxVelocity `DragMaxSpeed`; not applied at the centre of mass, so pieces swing from the grip).
  - Add an `AlignOrientation` holding the grab-time orientation times the player's rotations.
- Target: the camera ray at the hold distance. Distance is set with the scroll wheel, D-pad up/down, or +/- touch buttons, and clamped to `HoldMin`-`HoldMax` from the character.
- Rotate: Shift+WASD or Q/E in 15° steps, LB/RB on gamepad, a rotate button on touch.
- Release: button up, the piece more than `ReleaseDistance` away, death or sitting. Destroy the constraints and fire `Release(part)`.
- If `HeldBy` isn't you within 0.5 s, drop the grab and show the server's toast.
- Other clients draw the ball from the `HeldBy` and `GrabPoint` attributes.
- Hover or hold tooltip: "Oak log · 26 u³ · $39".

**Server: `SSS/GrabService`**
- Validates: rate (Grab and Release 6/s), live character, `|HRP - hitPos| ≤ GrabRange + RangeTolerance`, piece not dead and not selling, `GrabLogic.CanGrab`.
- On success: `SetNetworkOwner(player)`, `HeldBy`, collision group `WoodHeld` (doesn't collide with Players: no riding your own log), `lastHolderId`, `lastInteracted`. At most one piece per player.
- On release: `ReleaseKeepOwnerSec`, then `SetNetworkOwnershipAuto`.
- Forced release on death, leave, seat, or the piece being sold or cut.

**`Shared/GrabLogic.CanGrab(facts)`**, pure:
- Dead, sold, or held by someone else: no.
- Display item in a shop: yes.
- On someone else's truck bed: no ("That's on Dale's truck").
- Owner 0, the owner, or an Elder piece: yes.
- Within `PickupGraceSec` of `createdAt`: no.
- Otherwise yes. Moving someone's wood never changes who gets paid. Unowned wood becomes the grabber's.
- M3 adds plot permissions.

**WoodWatch (inside WoodService)**
- Every 0.5 s, for pieces with a player network owner (held, just released, or on a driven truck): `VehicleLogic.JudgeMove(lastGood, now, dt, WoodMaxSpeed)`.
- A move that's too far puts the piece back, stopped, owned by the server for 1 s.
- SellService and the sawmill intake only accept pieces whose last verdict was ok.
- This blocks teleport-to-the-pad.

**Studio dev commands** (Studio only, like `/giveaxe`): `/spawnwood <wood> <length>`, `/growall`, `/givecash <n>`.

### 4b. Trucks carry by friction (replaces bed slots)

- TruckArt gives bed floors `BedFriction` (1.0) and adds collidable stake posts or rails on the flatbed and the rig.
- Each bed part gets an invisible, non-colliding, non-query child `BedZone`: interior width x 4 x bed length.

**`SSS/TruckLoad`**
- Every 0.25 s, for a truck with a driver: pieces whose centre of mass is inside a BedZone (`GetPartBoundsInBox`, Wood folder only) get `SetNetworkOwner(driver)` unless someone is holding them. Truck and cargo then simulate on one device, so friction works.
- When the driver gets out and the truck settles: back to auto ownership.
- Each second: `BedVolume` and `BedValue` attributes on the truck and on the player, for the HUD.
- `GameConfig.BedAutoWeld` (off) is the fallback if beds jitter in Studio: weld a piece to the bed once it rests (under 1 stud/s for 0.5 s) and unweld it on grab.

**VehicleService hooks**, the only changes to that file:
- `OnDriverChanged(rec, driver?)`
- `OnRebuilt(player, fromCF, toCF, keepsLoad)`: Recall and switching trucks. Bed pieces move with the truck if `VehicleLogic.InTown`, otherwise they stay where they are.
- `BedZones(player)`

Drive and Heading, the speed check, settle and parking are not touched. Loose cargo isn't part of the truck's assembly; the existing `MaxForce = mass * 120` pulls it fine, and loaded trucks just feel heavier.

### 4c. Vehicle resize (M1.5; lands live, before the flip)

**How long logs come out**
- Pieces are cut wherever the player chooses. Natural joints are trunk segments: oak 4.5, birch 5, pine 7.7, maple 4, frostwood 6.3, lumenwood 6.7 studs. Limbs run 3-7 studs.
- A limbed oak or birch trunk is 9-15 studs and is bucked into 7-10 stud pieces.
- A pine trunk is 46 studs: 4-5 pieces of about 10, or 2-3 of about 18 on bigger beds.
- Frostwood: 2 x 19 or 3 x 13. Elder trunks are bucked to 26 or less.

**Target dimensions** (studs)

| Truck | Body width | Cab length | Bed L x interior W | Wall/stake height | Wheel radius | Bed floor top | Overall length | Seat top to roof underside |
|---|---|---|---|---|---|---|---|---|
| Rustbucket (farm) | 6.2 | 7.0 | 10 x 5.6 | walls 1.4 | 1.3 | 3.0 | 17.5 | ≥ 4.6 (canvas top, rolled up) |
| Pickup | 6.6 | 7.4 | 12 x 6.0 | walls 1.6 | 1.35 | 3.1 | 19.9 | ≥ 4.6 (today 4.0) |
| Scout ATV | 4.6 | 6.5 | rack 2 (no wood) | | 1.25 | | 8.5 | open |
| Flatbed | 7.2 | 7.8 | 18 x 6.8 | stakes 2.5 | 1.45 | 3.3 | 26.3 | ≥ 4.8 |
| Logging Rig | 7.8 | 9.4 | 26 x 7.2 | bunk stakes 3.2 | 1.8 | 4.0 | 35.9 | ≥ 5.0 |
| Pony / Ranch / Heavy Hauler trailer | the towing truck's | tongue 2.0 | 10 / 14 / 20 | 1.2 / 2.0 / 2.5 | 1.15 / 1.2 / 1.25 (Heavy is tandem) | 2.5 | 12 / 16 / 22 | |

**Physics kept**
- The chassis is the only massive part; its mass grows with volume, so `mass * 120` scales itself.
- Skids are frictionless with bottoms at y 0. `SkidRampRun` goes from 2 to 2.6 so the ramp angle stays at or under 26.6°.
- Turning stays about the rear axle (`DriveAxleZ`).
- `DriveMath.TurnRadiusPerWheelbase` goes from 0.75 to 0.62, so the Rig's circle (wheelbase about 25.5) stays about 15.8, inside today's 14.8 + 10%.
- `TruckLayout.ChassisY` (and with it `WHEEL_CLEARANCE`) is taken from the new wheel radii. `EXIT_GAP` goes from 2 to 2.6.
- The v1 bed still holds its 6-48 logs in `logSlots`: same counts, more spacing.

**Parking (town stream)**
- `WorldPlan.Town().parkingSlots` becomes one row of 12 slots, 10 wide x 60 long, 11 apart (the longest rig with a trailer is 57.9).
- If the lot can't grow east, use two rows of 6.
- `MapBuilder` section 4 sizes the `ParkingSlot` parts to match (the contract: name, tag, Index, CFrame and Size.Y are kept).
- `VehicleLogic.OverflowSpot` spacing goes to at least 11. `HomeRadius` goes from 30 to 40.

**Roads and pad (land stream)**
- `WorldLayout` haul roads go from 14 to 18. ForestPath from 10 to 14. PlotRoad from 10 to 14. PlotLane from 8 to 12.
- `WorldPlan.GoodGround` road clearance follows. Tree spots near roads re-roll; BiomeData counts hold.
- Sell pad: trucks back in from the street. Rustbucket, Pickup and Flatbed beds fit inside the 18-deep `SellZone`. The town stream extends the zone south by 8 to 26 deep (z 69-95, the centre still on the pad and north of the lamps at z 60), so the Rig's 26-stud bed fits too. The SellPad itself stays ≤ 0.25 tall and non-colliding.

**Specs to update**
- `TruckLayout.spec`: every rig plus trailer fits 10 x 60; bed sizes per tier; wheels under bed clearance.
- `TruckArt.spec`: chassis the only massive part; only beds, walls, stakes and skids collide; skid bottoms at y 0; ramps ≤ 26.6°; enclosed-cab headroom ≥ 4.5 above the seat; one `BedZone` per bed.
- `VehicleLogic.spec`: RigCorners and RestingCFrame with the new dimensions; overflow spacing; HomeRadius.
- `TrailerTow.spec`, `TruckHome.spec`.
- `DriveMath.spec`: each truck's minimum turn radius at or under today's + 10%.
- `WorldPlan.spec`: slot count and size; the 35-stud pull-outs (were 25) clear; nothing that collides in a bay; greenery off the lot; road widths; the pad approach lane.
- `MapBuilder.spec`, `PreviewCameras.spec`.

**Renders:** trucks 1, 3, 6, 8, 9, 10, plus a new view with a seated R15 dummy (hats) in each cab and sections view 7 (logs on beds); town 1, 2, 9; buildings 4 (Dealership display truck).

**As built (phase 12, day 3):** everything above grew 1.3x (`TruckLayout.Scale`; the Rig is 46.7 long and 12.9 wide across its mirrors, 75.3 with the Heavy Hauler); `TurnRadiusPerWheelbase` 0.477 keeps each truck's M1.5 circle; the lot is 13 painted bays in 4 sizes (`WorldPlan.ParkingBays`: small 14.25 x 30, Flatbed 15 x 38.75, long 16 x 51 and longest 16 x 80, both pull-through), each about the rig plus 3 across and 4 along, picked by `VehicleLogic.BayChoices`; SellZone 24 x 12 x 40 (z 62-102). The Rig needs 28-wide haul roads (bends) and flared junctions at (30, 450) and (-20, 760); the ROADS and TOWN slices landed with that (Hills, Snow and Volcano 28, Skyroot 24, the mill road 22, the lot loop 16).

**As built (M1.5):** Flatbed and Rig wheels are 1.4 and 1.75 (the plan's 1.45/1.8 cut into the open decks); the roads were NOT widened (widening moves the pinned first-322 trees and 472 of 775 trees; two rigs pass with outer wheels on the verges); TruckHome.ShowBeyond 20 -> 30; the lot is one row of 12 bays of 10 x 60 east of the spawn; SellZone 24 x 12 x 26 (z 69-95); BedZone comes with M1.6.

### 4d. What happens to CarryService, LeftLoad and the truck save

- CarryService's job (hands, `CarriedLogs`, restack, `TakeLogs`/`TakeWhere` for the chute and forge) moves to GrabService plus physical hoppers. HUD "Hands n/2" becomes the hold tooltip; "Bed n/N" becomes "Bed 14 u³ · $38".
- **Truck save:**
  - On leave and on autosave, pieces in your BedZones go into `profile.truckLoad`: a compact record per piece, relative to the bed, capped at `MaxSavedPieces` (40) and `MaxSavedSections` (300).
  - On rejoin they are rebuilt on the bed if `truckAt` was in town. Otherwise they go on the ground at `truckAt`, yours for `LeftLoadGraceSec`.
  - `LeftLoad.ToRestore` caps the list.
- Wood lying anywhere else isn't saved until plots save wood (M3.2), which is LT2's rule. A v1 `leftLoad` is paid out at migration (§14).

---

## 5. Selling: `SSS/SellService` (M1.7)

- Every `SellPollSec`: `GetPartBoundsInBox(SellZone)` over the Wood folder, grouped by piece.
- A piece qualifies when it's been inside the zone for 0.3 s, isn't `selling`, isn't a `ShopItem`, isn't dead, and its WoodWatch verdict is ok. Then:
  - set `selling = true` (the per-piece debounce);
  - compute `value = Σ section volume_u3 * (log or plank price) * Multiplier(figure) * boost`;
  - **credit the owner** if online, else `lastHolderId` if online, else nobody;
  - destroy the piece.
- Per owner, per tick: `EconomyService.AddCash(owner, total * SaleMultiplier, "sold wood", "wood")`, one toast ("Sold 3 pieces · 41 u³ · $96"), WorldFX `Sold {pos, amount}` for the "+$" pops, `ForestService.OnSale(figures)`, and Quest, Daily and Milestone events (pieces, u³, $, by wood).
- **Instant Delivery** (Robux): `SellService.SellBed(player)` sells the pieces in your BedZones from anywhere, with the same wallet-room check as today.
- **2x Wood** (Robux): wood you cut while it's active carries `boost = 2`. 2x Cash stays at sale.
- **Sky Bin**: wood dropped in a Cloud Chute hopper (AetherService) becomes `skyWood` entries `{w, v (u³), f?, p?}`, capped at `skyBinVolume` = 120 u³ in BiomeData. A "Sell Sky Bin" prompt by the pad pays it out through `SellService.PayEntries`.
- **Forge**: lumenwood dropped in its hopper adds to `forgeWood`. `ForgeLogic` checks 60 u³.

---

## 6. Shops: counters, boxes, dialogue (M2.1)

- **Display items**: real models on racks and floors (AxeArt axes, boxed machines), tagged `ShopItem` with attributes `ItemId, Shop, Home`.
  - They can be dragged inside the shop.
  - They snap back to their rack after 60 s idle, or if taken more than 30 studs from the counter.
  - SellService ignores them. A client-side price tag shows nearby.
- **Counter**: BuildingArt adds an invisible `CounterTop` zone above each shop's `Counter` (the 2.6-stud keeper gap and `ShopPoint` are kept).
  - The keeper's prompt "Talk" fires `Dialogue("open", npcId)`.
  - The server picks a node with `Shared/DialogueLogic` from what's on the counter, the total, your cash and the ladder rules, and sends it back.
  - Picking "Yes" runs `ShopService.Checkout`: range, `ShopLogic` (ladder, `MaxOwnedAxes`), `SpendCash(total)`. Each display item is replaced by a **Box** at the counter (tag `Box`, `ItemId`, `Owner` = buyer, draggable) and respawns on its rack. Several items at once are fine.
- **Boxes**: prompt "Open", owner only, handled by `SSS/BoxService`.
  - Axe: `AxeService.Grant`.
  - Gear: owned.
  - Sawmill or furniture: the placement ghost (BlueprintPlacer, `PlaceBlueprint` with the box uid).
  - M4 vehicles: a pad.
  - Unopened boxes still lying in the world when you leave go into `profile.storage` and come back at that shop's counter ("Tink kept your box").
- **`Shared/DialogueData`**: `{ [npcId] = { [nodeId] = { text, options = { { label, next?, action? } } } } }`, our own voice. For Tink:
  - greet: "Mornin'! Axes on the rack, saws by the door. Set what you fancy on the counter and holler."
  - empty: "Counter's bare, friend."
  - offer: "{items}. That's {total} all told. Box it up?"
  - broke: "That's {total} and your pockets say {cash}. Fell a few more and come see me."
  - locked: "Get the feel of the {prev} first, eh?"
  - thanks: "Pleasure! Mind the edge."
- ShopUI loses the Tool Shed and Hearth & Home tabs (the Dealership stays until M4). StoreUI (Robux) is untouched.

---

## 7. Sawmills and planks (M2.2)

- Bought as a box, placed on your plot as a `PlacedItem { blueprintId = "SawmillRickety", data = { x = 1.0, y = 0.6 } }`. `ProfileSchema.PlacedItem` gains an optional `data`.
- `Art/MachineArt.luau` (new): five sawmill models, each with `Intake` (zone), `Output` (CFrame) and a `Panel` SurfaceGui with X+/X-/Y+/Y- buttons that fire `SawmillSet(uid, axis, dir)` (owner or permitted, in range).
- `SawmillService` polls each intake every 0.25 s. `SawmillLogic.Accepts(piece, mill)`: a straight chain (every section within 12° of the first; no branches), total length ≤ maxLength x U, thickness ≤ maxWidth x U, volume ≥ one 0.2u plank.
  - It anchors the log and tweens it through over 1-3 s by volume, destroys it, and emits planks one at a time.
  - Each plank is `X*U x L x Y*U`, with `L = min(maxLength*U, remaining/(X*Y))` and the last plank taking the remainder.
  - `PlankYield = 1` (volume conserved).
- Planks: `Kind = "plank"`, all core colour and material, the figure kept. They can be cut: required = hardness x (sx/U)(sz/U).

---

## 8. Plots and building (M3)

**Squares (M3.1)**
- Each of the 12 slots holds a 5x5 grid of 40-stud squares around its centre.
- Saved as `profile.plot.squares = { "0,0", ... }`.
- The Land Office (Ada, a new building by the plot district) sells the first square for $100, the centre square of a free slot you pick (PlotUI cycles free slots).
- `ExpandLand(x, z)` must touch a square you own and costs 3000 x k.
- `PlotLogic.InSquares` replaces `InBounds(size)`.
- Migration: a Campsite (tier 1) gets the centre 3x3. Higher tiers get the 3x3, plus any ring squares their placed items need, plus a cash refund of the tier prices paid. Existing PlacedItems stay.

**Plot saving (M3.2)**
- `Shared/PlotSave` (pure) encodes every model on owned squares relative to the plot origin: wood (compact section graphs), planks, boxes, machines with `data`, structures, ghosts with fill, conveyors, wires.
- Short keys, 3 decimals. Caps: 1,500 items and 6,000 sections, sized so a full slot is about 1 MB or less inside ProfileStore.
- Restored in batches of 60 per frame, anchored while loading.
- Autosaved every 90 s, on leave and on BindToClose. A 30 s load cooldown.

**Permissions (M3.3)**
- `Shared/PermissionLogic`: visit, place, move, destroy, drive, sit, interact, grab, save, per target userId, plus "Visits from anyone" and "Collisions".
- A SettingsUI tab. Per-owner wood collision groups (12 slot groups plus `WoodFree`).
- A client-side visit barrier and a server teleport-out.

**Blueprints (M3.4)**
- `Shared/BlueprintData`, our names: Tiny Floor 1 u³, Small Floor 3, Floor 6, Large Floor 18, Stairs 10, Door 10, Half Door 6, Counter with Basin 30, walls, wedges, roofs.
- Price = 10 x units, unlocked for good (`profile.blueprints`).
- A Blueprint Manager tool on the first purchase. The ghost is placed with BlueprintPlacer (R/T rotate, snap toggle 1 / 0.2).
- `BlueprintService` polls `GetPartsInPart(ghost)` every 0.5 s for permitted planks, absorbs them into `fill[wood]`, and when the fill reaches the requirement builds the structure in the majority wood's plank colour and material.
- Today's PlotData blueprints become Furniture, sold boxed at Hearth & Home.

---

## 9. Vehicles and pads (M4)

- The Dealership sells trucks and trailers as boxes. Opened on your plot, a box becomes a **spawn pad**: a plank with four white corner marks and an orange button (a prompt; M5 adds a logic input).
- Pressing it despawns that pad's old vehicle, builds a new one (VehicleService and TruckArt), picks a weighted colour (Blossom Pink 1 in 500) and charges 2% of the price.
- Trailers hitch with a `BallSocketConstraint` when within 1.5 studs and the player presses E. This replaces today's rigid hitch and is retested against the speed check.
- The Rustbucket stays in the town lot for everyone. Migration: other `ownedTrucks` and trailers become pad boxes in `profile.storage`.
- Pads save with the plot; vehicles don't.

## 10. Conveyors and logic (M5)

- Conveyors keep our flume skin (GAME_DESIGN §9): anchored troughs with `AssemblyLinearVelocity = dir * ConveyorSpeed`. Straight 80, Tilted 95, Funnel 60, Tight Turn 100, Switch 320-480, Supports 12-20, Sweeper 430.
- Logic items: Button 320, Lever 520, Pressure Plate 640, Laser 11,300 / Detector 3,200, Wood Detector 11,300 (wood filter), AND/OR/XOR 260, NOT 200, Delay 520, Sustain 520, Clock 902, Hatch 830, Wire 205, Glow Wire 720, lamps.
- `Shared/LogicGraph` (pure): ports, a propagation queue capped at 200 evaluations per tick, timers on a 0.1 s tick.
- `SSS/LogicService`, a wiring tool, and the Sparkworks shop at the east docks (moving behind the ferry in M6).
- Caps per plot (§2f). Runs online only (GAME_DESIGN §9).

## 11. Gates, hazards, quest axe (M6)

- **Toll bridge** where the north road crosses the river: $100 for 3 minutes, Old Tolly. It is the gate to the Snowfields and the Volcano. Raising it pushes players and vehicles off.
- **Blasting charges** ($220, 5 s fuse, `Explosion` with `BlastPressure 0`) break tagged `Breakable` boulders sealing the Phantom Grove hollow and a cave. The boulders come back after 20 minutes.
- **Ferry** to the Island ($400, every 6 minutes, Cap'n Moss): the Island biome, palmwood (about 30 trees, 8-minute growth) and Sparkworks. Riders and cargo are welded to the deck for the trip.
- **Hazards**: damaging deep sea at the map edge (15 per 1.5 s), a slippery frost peak path (low friction), the volcano drain (today's burn).
- **Quest**: three items from three shops (Tool Shed, Hearth & Home, Odds & Ends; about $7.7k total), a hidden snow trapdoor under a carved symbol, three hermits on plates, then the **Hermit's Maul** (3.73 / 9 / 1.25, off the ladder).
- Our own secret glowing box with our own line, and a firewood bin at a snow cabin.

---

## 12. Remotes and rate limits

| Remote | Direction / arguments | Limit/s | From |
|---|---|---|---|
| Chop | C→S (part, hitPos, normal) | 6 | M1.3 |
| Grab / Release | C→S (part, hitPos) / (part) | 6 / 6 | M1.4 |
| Dialogue | C→S ("open", npcId) or ("pick", nodeId, i); S→C (npcId, node) | 4 | M2.1 |
| SawmillSet | C→S (uid, "x" or "y", ±1) | 6 | M2.2 |
| BuyLand / ExpandLand | C→S (slot) / (x, z) | 1 / 1 | M3.1 |
| SetPermission | C→S (userId, flag, on) | 4 | M3.3 |
| Wire | C→S (fromUid, port, toUid, port) or ("cut", uid) | 4 | M5 |

- Kept: DropAxe, SkipTutorial, EquipItem and CallTruck (until M4), BuyRobuxItem, UseInstantDelivery, MineNode, PlantSeed, SaveSetting, PlaceBlueprint, MoveBlueprint, SellPlaced, CashChanged, Notify, WorldFX.
- Removed at M1.10: ChopTree, PickupLog, LoadToTruck, SellLogs. UpgradePlot goes at M3.1, BuyItem at M4.
- Box opening, pad buttons, the toll and the ferry are server ProximityPrompts.
- An Instance argument can arrive nil; every handler checks its type and that the part is known.

---

## 13. Murph's tutorial v2

`TutorialData.StepsV2` uses **the same 7 ids in the same order**; `TutorialData.For(loop)` picks the list.

| id | Objective | Event (count) | Murph | Beacon |
|---|---|---|---|---|
| fell | Chop down a tree | treeFelled (1) | "Mornin'! I'm Murph. See the oaks south of town? Swing low on a trunk and keep hittin' the same spot. Watch the notch. {Click}, or hold, to keep swingin'." | tree |
| pickup | Drag a log | woodGrabbed (1) | "Timber! Put your axe away ({unequip}), then {click} and hold a log to drag it. Big ones are heavy: chop 'em shorter first." | log (your nearest piece) |
| load | Drag a log onto your truck's bed | woodLoaded (1: your piece rests in your BedZone) | "That's your Rustbucket. Drag the wood up onto the bed and lay it flat so it rides." | truck bed |
| sell | Sell wood at the sawmill | woodSold (1) | "Back her onto the green pad by the mill and the wood sells itself. Bigger logs pay more. It's all by the cubic unit." | sellPad |
| plant | Fell a tree, then plant its Heartseed in the stump | seedPlanted (1) | (unchanged) | stump |
| loads | Sell $%d more wood | woodSoldCash (120), reward $25 | "See it grow? That tree's yours now. That old hatchet's slow on birch, though. Sell a few more loads and I'll chip in for a Steel Axe." | |
| steel | Buy the Steel Axe at the Tool Shed | axeBought (1) | "Here's a little somethin' from me. Tink's Tool Shed is just west of the mill." In M2 this becomes "Set the Steel Axe on Tink's counter and talk to him." | toolShed |

- New HintLogic token `{unequip}`: "press 1", "press the D-pad", "tap your axe".
- Rough cash path: start $20, first oak about $35, $120 more sold, $25 from Murph, which reaches the $160 Steel Axe.
- `StumpHold` and `CanPlant` are unchanged.
- **Old saves mid-tutorial**: `tutorialStep` and the onboarding keys carry over because ids and order match. `MigrateV2` sets `tutorialProgress = 0` if the current step is pickup, load, sell or loads (their units changed). AlreadyDone (best tier ≥ 2) and realign are unchanged.
- Later beats (M3 "Buy your first plot square") are **appended** after `steel`.

---

## 14. Profile migration

**New fields (template)**
- `schema = 0`: 2 = core loop, 3 = squares, 4 = pads.
- `v2Credit = 0`.
- `truckLoad = {}`, `forgeWood = {}`, `skyWood = {}`, `storage = {}`, `blueprints = {}`.
- `stats.volumeSold` and `stats.cuts` (filled in Migrate if Reconcile misses nested keys).
- M3: `plot.squares`, `plot.items`, `plot.permissions`.
- `PlacedItem.data` is optional.

**`ProfileSchema.MigrateV2(data)`** runs only when the loop is v2 and `schema < 2`, then sets `schema = 2`. It is idempotent and has fixture specs.

1. `v2Credit += Σ value` over `truckBed`, `leftLoad` and `skyBin` (their saved per-log values, figures included). Then those lists are emptied (fields and types kept) and `truckAt = {}`. *Every* v2 join also drains these lists if non-empty, in case an old server refilled them.
2. Cash is kept 1:1. If `cash + v2Credit < StartingCash`, `v2Credit` is topped up to reach $20. GameServer pays `v2Credit` on join through `EconomyService.AddCash(..., "v2 buy-back")` and toasts "Murph bought back the logs you had on hand: +$X". Migrate itself never writes cash.
3. Axes are kept. `bestAxeTier` = the highest `AxeTier` over `axes`, an unchanged ladder order.
4. Trucks, trailers, gear, heartseeds, compendium, forest stats, onboarding and Robux fields are kept.
5. `forgeWood.lumenwood = min(60, forgeLogs.lumenwood * 1.5)`. `forgeLogs` stays untouched until M1.10, so a rollback to v1 loses nothing.
6. Tutorial progress resets per §13.
7. `daily`: if today's goals use log-count kinds, set `daily.day = 0` so DailyService rerolls today's goals. Streak, bestStreak and lastCompleteDay are kept, and a spec covers it.
8. The plot is unchanged until M3 (`MigrateV3`: tier to squares, refund). Vehicles are unchanged until M4 (`MigrateV4`: owned trucks to pad boxes in `storage`).

**Rollout**
- Publish the flip with Creator Hub, Places, "Migrate to Latest Update", so no v1 servers keep running.
- Rollback = `CoreLoop = 1` and republish. Migrated saves load fine in v1: same fields, same types, the credit already paid.

---

## 15. Milestones

### 15.0 How every slice stays safe

**The rhythm for each slice:**
1. Build in its own worktree (HANDOFF §11: `git worktree add ... -b v2/<slice> origin/main`, copy `globalTypes.d.luau`).
2. `./scripts/check.sh` exits 0.
3. Renders where listed.
4. A fresh-agent review.
5. The lead merges.
6. Studio checks go to Connor, run with the `CoreLoop` override.

Until M1.9, `CoreLoop = 1` keeps live servers on today's game.

**Streams** (one owner per file; ask the owner through the lead):
- **lead/data**: GameConfig, CoreLoop, Tune, WoodData, ItemCatalog, Net, RateLimiter, ProfileSchema, PlaceCheck, GameServer, check.sh, economy2, docs.
- **trees**: TreeGen, SectionLogic, TreeArt, ForestArt, SectionTrees, WoodService, ForestService/Logic/Data, TreeLogic, CutController, WoodFX, `scenes/sections`.
- **actors**: GrabLogic, GrabService, DragController, TruckLoad, TruckLayout, TruckArt, VehicleService hooks and constants, VehicleLogic, DriveMath.
- **economy-ui**: SellService, AetherService, ForgeLogic, MonetizationService, StoreData, TutorialData, QuestService, QuestUI, HintLogic, HUD, HudRules, DailyData/Service, FieldGuide/Service, ShopLogic, ShopUI, MilestoneService, Client.client.
- **town** and **land** as in HANDOFF §8, for the lot, roads, pad zone and counters.

**Merge order:** M1.0 → M1.1 → (M1.2 alongside M1.4) → M1.3 → M1.5 → M1.6 → M1.7 → M1.8 → M1.9 → M1.10.

### M1 "the core feel": section trees, cut anywhere, drag, truck by friction, volume selling, LT2 numbers, Murph

**M1.0 Flag, tuning hook, v2 data** (lead)
- Files: GameConfig, `Shared/CoreLoop` (new), `Shared/Tune` (new), WoodData (+v2 economy), ItemCatalog (+v2), PlaceCheck, MapBuilder (one line to publish `CoreLoopActive`; ask land).
- Specs: `CoreLoop.spec`, `Tune.spec`, Data/ItemCatalog (every wood and axe has v2 fields; plank price ≥ log price; `vs` keys are wood ids; prices rise up the ladder).
- Studio:
  1. Play: unchanged game, Output `[CoreLoop] 1`.
  2. Set the attribute to 2 and Play: `[CoreLoop] 2 (Studio override)`. PlaceCheck shows the "clear before publishing" warning.
- Risks: none to live. Confirm ECONOMY.md doesn't change.

**M1.1 TreeGen and SectionLogic** (trees)
- Files: `Shared/TreeGen`, `Shared/SectionLogic` (both new), WoodData `v2.shape`, `tools/economy2.luau` plus `ECONOMY_V2.md` (volumes, $/tree, the §2c hits table), check.sh line (lead).
- Specs:
  - TreeGen: determinism, heights, thickness, budgets, connectivity, above ground, variety.
  - SectionLogic: the hits table, window merge, clamps, volume conserved by splits, exactly 2 components, minimum piece.
- Studio: none (all pure).
- Risks: ugly shapes, caught by the M1.2 renders.

**M1.2 The tree remodel** (trees)
- Files: TreeArt (FromSkeleton, CutFace, Notch, Sapling stages), ForestArt (clues on a section), `scenes/sections.luau`, TreeArt/ForestArt specs.
- Gate: §3j passes and Connor approves views 1-2.
- Risks: part budget, which the specs and the world export catch.

**M1.3 Cut anywhere** (trees; lead does the GameServer wiring)
- Files: `SSS/SectionTrees`, `SSS/WoodService`, `SPS/CutController`, `SPS/WoodFX` (all new); ForestService (switch, OnFelled with pieces, clues, Elders); ForestLogic (Royalty by value, IsLarge by scale, Elder scale); ForestData; one require switch each in WorldClock, WeatherService and QuestService; MapBuilder step 5 plus the sky lumenwood; Client.client (v2 controllers); Net and RateLimiter `Chop`; collision groups `Wood/WoodFalling/WoodHeld/Leaves/Players`.
- Specs: SectionTrees (reasons far/noLOS/tooHard/cooldown; OnFelled once; the stub stays anchored; regrow; dormant; ghost), WoodService (despawn, owner loss, split keeps owner and figure, caps, WoodWatch put-back), CutController (auto-target height from the HRP, leaves skipped), ForestService on the v2 path.
- Studio (override on):
  1. Output `[SectionTrees] N trees on N sites`, no red. MapBuilder time grows by 3 s or less.
  2. The Starter Forest: big trees, varied, some young.
  3. With the Rusty Axe, hit an oak trunk at knee height: a notch grows on the face you hit and the ring fills. On hit 16 it tips away from you as one physical piece, the leaves drop about 1.5 s later, and a stub stays.
  4. Cut the fallen trunk mid-way (16 hits): two pieces. Cut a limb where it joins: it falls free.
  5. A different height each swing: no cut ever finishes, and at most 2 notches show per section.
  6. Step past the axe's reach: "Too far".
  7. Fell a pine: it lands without flinging you (you stay put for 2.5 s), and the camera shakes.
  8. After about 45 s a sapling appears and grows in 4 steps over about 4 minutes.
  9. Plant a Heartseed in a stub: a mature tree 8 s later, with your stake.
  10. MicroProfiler: no spike when a tree falls.
- Risks: physics of 50-stud pines (tunnelling into terrain: the fall uses an impulse, not a teleport), boot time, Atomic streaming.

**M1.4 Grab and drag** (actors)
- Files: `Shared/GrabLogic`, `SSS/GrabService`, `SPS/DragController` (all new); Net and RateLimiter `Grab/Release`; character collision group (lead, GameServer); the `/spawnwood` command.
- Specs: GrabLogic (the permission matrix, force cap, distance clamps), GrabService (mocks: far, held, ownership set, auto ownership after 2 s, forced release on death), DragController's pure input maths.
- Studio:
  1. With the axe away, drag a limb: the blue ball, smooth, with rotate and scroll.
  2. An oak trunk lifts. A whole pine trunk only drags along the ground.
  3. Phone emulator: tap and hold, then +/- buttons. Gamepad: L2 hold, then the D-pad.
  4. Two players: the other can't grab your piece for 45 s, and both see the ball.
  5. 200 ms lag: holding stays smooth.
- Risks: feel (tune with `Tune_*`), touch versus camera, exploits (WoodWatch).

**M1.5 Bigger trucks, lot and roads** (actors, town, land; lands live)
- Files: per §4c.
- Studio:
  1. Drive every truck and trailer; the turning circle feels like today's.
  2. Hats clear the cab roofs.
  3. Every slot spawns cleanly; recall works.
  4. The lot exits and the pad approach clear the Rig plus Heavy Hauler.
  5. Two rigs pass on a haul road.
  6. The v1 bed still loads and sells.
- Risks: driving regressions. VehicleService code is untouched apart from constants; the speed check is retested with 200 ms lag.

**M1.6 Trucks carry by friction** (actors; lead adds `truckLoad`)
- Files: `SSS/TruckLoad` (new), TruckArt (BedZone, friction, stakes), VehicleService (three hooks), GameServer (save and restore under v2), LeftLoad.
- Specs: TruckLoad (bed membership, save/restore round trip, caps, the in-town rule, recall carry).
- Studio:
  1. Load 4 bucked oak pieces and drive forest to mill at full speed: nothing falls off on the road. A badly balanced log may slide in a hard turn, which is acceptable.
  2. A second player watches: no jitter, nothing falls through the bed.
  3. Leave and rejoin in town: the load is back on the bed.
  4. If logs jitter, set `Tune_BedAutoWeld = 1` and compare.
- Risks: ownership races; `BedAutoWeld` is the fallback.

**M1.7 Volume selling** (economy-ui)
- Files: `SSS/SellService` (new), AetherService (hoppers, Sky Bin, forge), ForgeLogic, MonetizationService and StoreData texts, ProfileSchema `skyWood`/`forgeWood` (lead).
- Specs: SellService (pays the owner not the pusher, offline owner falls to the last holder, debounce, value maths with figure x boost x 2x Cash, teleported wood refused), chute and forge volumes, Instant Delivery v2.
- Studio:
  1. Drag a log onto the pad: "+$" pops and the toast reads u³ and $.
  2. Back a loaded truck onto the pad: the whole bed sells.
  3. A friend's log on your bed pays them.
  4. A figured log reveals its figure.
  5. Chute a lumenwood piece, then sell the Sky Bin at the mill.
- Risks: the zone catching wood while it's being dragged through (intended).

**M1.8 Murph, HUD, dailies, guide, shop text** (economy-ui)
- Files: TutorialData (StepsV2), QuestService, QuestUI beacons, HintLogic (`{unequip}`, the drag hint, "cut it to fit the bed"), HUD/HudRules (hold tooltip, bed volume, no Hands under v2), DailyData/Service (kinds in u³/$/pieces, rewards rescaled by economy2), FieldGuide/Service, ShopLogic/ShopUI (v2 prices and texts), MilestoneService (calibrate line).
- Specs: TutorialData (StepsV2 ids == Steps ids, in order), QuestService v2 events, DailyData, FieldGuide, ShopLogic, HudRules, HintLogic.
- Studio:
  1. A fresh save under the override runs all 7 steps end to end; time from spawn to first sale is under 4 minutes.
  2. Phone layouts don't overlap.
  3. The stopwatch line pastes into `lune run tools/economy2 --calibrate ...`.

**M1.9 Migration and the flip** (lead)
- Files: ProfileSchema (MigrateV2), GameServer (v2Credit, drain), `GameConfig.CoreLoop = 2`, ItemCatalog `priceCash` from the v2 prices, economy2 replacing economy, ECONOMY.md, check.sh, docs (GAME_DESIGN §2-4, §11, §14, §16-17; CLAUDE.md; V1_PLAN; PHASE2_NOTES Studio checks).
- Specs: migration fixtures (beds, left logs and Sky Bin paid; forge converted; tutorial progress reset; top-up; idempotent; a v1-shaped read of a v2 save doesn't fail).
- Studio:
  1. With the attribute cleared and the flag at 1, play v1 and fill the bed.
  2. Switch to this build: the toast "+$X", axes kept, tutorial step kept.
  3. Publish with "Migrate to Latest Update".
- Risks: old servers (mitigated by migrating); rollback per §14.

**M1.10 Cleanup** (each owner, after about a week live)
- Delete TreeService, CarryService, CarryController, CarryPose, CarryLayout, PickupGrace, TreeUI, TreeFX, ChopController, the bed-slot code, the v1 remotes and limits.
- Hoist the v2 fields; `Steps = StepsV2`.
- Profile fields stay.

### M2 Shops and sawmills
- **M2.1 Counters, boxes, dialogue** (§6).
  - Files: DialogueData, DialogueLogic, DialogueUI, BoxService (new); ShopService; NPCService/NPCData; BuildingArt `CounterTop` and racks (town); ShopUI.
  - Studio: drag the Steel Axe to Tink's counter and talk; check the price line, Yes gives a box, Open gives the axe in the hotbar; the broke line when short of cash; two items at once; a display item snaps back.
  - Risks: flinging display items, dialogue on phones.
- **M2.2 Sawmills and planks** (§7).
  - Files: ItemCatalog.Sawmills (lead), SawmillLogic, SawmillService, MachineArt (new), WoodService (planks), TreeArt.Plank, PlotService (place from a box, `data`).
  - Studio: buy a Rickety Sawmill, place it, feed it a 9-stud oak trunk: planks come out; X/Y buttons step 0.32 studs; a branched piece or a pine base is refused; planks sell at 2.5x the oak log price (prices scaled, see the status notes).
- **M2.3 Plank economy**: economy2 adds a plank path, a "sell planks" daily, Field Guide plank prices, figured planks.

### M3 Land and building
- M3.1 Squares and the Land Office, plus MigrateV3.
- M3.2 Plot saving.
- M3.3 Permissions and collisions.
- M3.4 Plank blueprints.
- Studio:
  - M3.1: buy a square, expand next to it, a non-adjacent expansion is refused, an old Campsite shows 3x3.
  - M3.2: stack 30 logs, planks and a sawmill on the plot, rejoin on another slot: all rebuilt.
  - M3.3: two players, grab refused without permission.
  - M3.4: buy a Small Floor ($30), place it, push 3 u³ of planks in: the floor appears in that wood.

### M4 Vehicles and pads
- Boxes and pads, respawn fee, colours, ball hitch, MigrateV4.
- Studio: open a Pickup box on the plot, press the button (fee 2% = $8), respawn, hitch a trailer and tow on the forest road.

### M5 Conveyors and logic
- Flume conveyors, sweeper, LogicGraph/LogicService, wiring tool, Sparkworks.
- Studio: a lever reverses a flume; a wood detector sorts oak from birch; a 200-item loop doesn't freeze the server.

### M6 Gates and hazards
- Toll bridge, blasting charges, ferry and Island, hazards, the quest, the secrets.
- Studio: each gate opens only after paying or blasting; the quest gives the Maul once.

### Terrain restyle (land; any time, unflagged)
- R1: per-biome terrain material colours (TerrainBuilder `SetMaterialColor`, palette per spec §16) and brown cliffs and rock.
- R2: per-biome Atmosphere and ColorCorrection tweening.
- R3: the sea edge, groundwork for M6 water damage.
- The usual terrain renders, and prebake after.

---

## 16. Performance budget (phones, Xbox; StreamingTargetRadius 1024)

- **Parts**: about 28k world parts today. Trees average 48 parts or fewer, so the world stays at or under 31k (the M1.2 gate). No stump models.
- **Loose wood**: about 5 parts per piece (sections plus cut faces; leaves are gone after 1.5 s). At most 150 pieces per player and 2,500 wood parts per server.
- **Physics**: blocks only (no cylinders). Resting pieces sleep. Low density, no elasticity. Falling and held pieces skip collisions with players.
- **Network**: only held pieces, cargo on a driven truck and freshly felled pieces have a player owner. Wood and tree models are Atomic. WoodWatch looks only at player-owned pieces, every 0.5 s.
- **Server**: growth rebuilds at most 12 trees per 5 s tick. Sell and intake polls are one box query per 0.25 s each. Cuts are rare.
- **Client**:
  - CutController hover raycast at 30 Hz (15 Hz on the low tier).
  - DragController does 1 ray per frame, only while holding.
  - WoodFX pools: chips 24 low / 48 high, leaves 32 / 64. New QualityBudgets fields `ChipCount, LeafPool, LeafShadows`. The low tier turns CastShadow off on leaf parts locally.
  - WindSway and CanopyFade keep their part caps (canopy names unchanged).
- **Studio checks** with phone emulation and the MicroProfiler: a frame under 33 ms in the Starter Forest at night, during a pine fall, and with 40 pieces on a moving Rig.

## 17. Economy model (`tools/economy2.luau`, `ECONOMY_V2.md` until M1.9)

**Inputs**: v2 data plus TreeGen.
- Average volume per mature tree and size class over 50 seeds.
- Cuts per tree: fell + limbs + bucks to fit the bed. Hits from §2c, times from per-axe cooldowns.
- Drag time: pieces x 20 studs / 16 studs/s, with a heavy factor.
- Bed volume x 0.4 packing.
- Trips: 2 x haul / top speed + 8 s.
- Selling: 4 s.
- Supply: trees per biome / growSec, giving "players a biome feeds".

**Estimated $ per mature tree, logs / planks** (economy2 computes the real values): oak 39/260, birch 28/187, pine 128/720, maple 88/830, palm 52/570, frost 240/2,830, ember 79/635, phantom 348/990, lumen 1,090/3,900.

**Targets**
- First sale under 3 minutes (GAME_DESIGN §2).
- Steel Axe ($160) in 5-8 minutes.
- First $1k in 15-20 minutes.
- Cobalt ($2,040, LT2's best store axe) in about 1 hour.
- Full plot ($900,100) in 20-40 hours.
- Wallet cap far beyond all of that.

**Risk**: until the M6 gates exist, a hatchet player can drive north and cut frostwood (95 hits per cut). Today's gates are distance, bed size, the snow slowdown and the volcano's Heat Boots. If the model says it's too fast, pull the toll bridge forward from M6.

---

## 18. Open questions for Connor

**Taken for now (2 October 2026).** Connor said "keep going, get it done, we will check after", so the lead took the defaults below; any of them can be reversed later, and each is noted where it lands.

| # | Taken |
|---|---|
| 1 | Yes: phantomwood shows as **Gloamwood** and its grove as **Gloam Hollow** (ids stay) |
| 2 | Yes: square trunks, softened by the art spec |
| 3 | Emberwood takes the swamp-gold row (5.7 / 36 / hardness 11): the volcano is harder to reach than the snow, so it pays more per u³ than the starter woods; frostwood stays the rare top earner below the isles |
| 4 | Yes, as proposed |
| 5 | Yes, as proposed |
| 6 | Keep "axes are never lost" (cozy) |
| 7 | Both: backing a truck onto the pad sells the bed, and pushing wood into the zone sells too |
| 8 | Yes, as proposed |
| 9 | Yes: the bigger trucks, wider roads and new lot ship live before the flip |

The questions as asked:

1. Rename **Phantomwood** for display, since LT2 has "Phantom Wood"? Something like Gloamwood, and Gloam Hollow for the grove. Ids stay.
2. **Square trunks**, softened by the art spec, instead of today's round ones? (Logs that don't roll, cheaper physics, exact planks.)
3. With LT2's rows, **frostwood out-earns emberwood** (9 vs 3.5 $/u³). Accept that, or give emberwood the swamp-gold row (5.7 / 36 / hardness 11)?
4. **Phantomwood and lumenwood** take LT2's limited Halloween rows (19/54/h23 and 25/90/h30), with our own grow times (20 and 30 minutes). OK?
5. **Grow times in minutes**, LT2-style: oak 4 minutes, up to frost 6 and pine 10. A planted Heartseed still gives a mature tree in 8 s. OK?
6. Keep **"axes are never lost"** (LT2 drops them where you die)?
7. **Selling**: back the truck onto the pad and the whole bed sells (our convenience), or LT2's push-it-off-into-the-zone only?
8. **Existing players**: cash kept 1:1 (worth more under the new prices), old logs bought back at their old value, Campsite plots become 3x3 squares (9 of 25). OK?
9. Ship the **bigger trucks** (and wider roads and the new lot) live before the flip? They also fix hats poking through roofs.

---

### Critical files for implementation
- /home/user/Timberline-Tycoon/src/ServerScriptService/TreeService.luau (its API and TreeRecord shape are what the new `SectionTrees` must keep)
- /home/user/Timberline-Tycoon/src/ReplicatedStorage/Shared/Art/TreeArt.luau (palettes and canopy builders reused by `FromSkeleton`)
- /home/user/Timberline-Tycoon/src/ServerScriptService/GameServer.server.luau (remote wiring, sale, join/leave hooks)
- /home/user/Timberline-Tycoon/src/ServerScriptService/ProfileSchema.luau (MigrateV2 and the new fields)
- /home/user/Timberline-Tycoon/src/ReplicatedStorage/Shared/TruckLayout.luau and /home/user/Timberline-Tycoon/src/ReplicatedStorage/Shared/Art/TruckArt.luau (resize, bed friction, BedZone)
- /home/user/Timberline-Tycoon/src/ServerScriptService/ForestService.luau (the Living Forest hooks)
- /home/user/Timberline-Tycoon/src/ReplicatedStorage/Shared/WoodData.luau and /home/user/Timberline-Tycoon/src/ReplicatedStorage/Shared/ItemCatalog.luau (v2 data)
