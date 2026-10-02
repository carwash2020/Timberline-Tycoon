# Game Design Document — **Timberline Tycoon**

An original lumber tycoon game. Do not use "Lumber Tycoon" branding, copy
Defaultio's assets/UI, or reference LT2. Name verified available on Roblox
2026-09-30 (closest existing title is the unrelated "Timberland Tycoon").

## 1. Concept

A multiplayer lumber tycoon: chop trees, haul wood, sell it at the sawmill,
and reinvest in better axes, trucks, and land. Compete/cooperate with other
players, hunt rare wood types in dangerous biomes, and build up your plot.

**Design pillars**
- Satisfying core loop: every swing feels productive, every sale feels earned.
- Visible progression: your axe, truck, and plot should *look* richer as you grow.
- Social by default: trading, visiting plots, and co-op hauling beat solo grind.
- Fair monetization: paying speeds you up, never lets you skip the game.

## 2. Core loop

> **Since 2 October 2026 the live loop is v2** (V2_PLAN.md, `GameConfig.CoreLoop = 2`):
> 1. Swing at a trunk anywhere: hits in one spot grow a notch until the cut goes through; a cut trunk tips and falls (section trees, Shared/TreeGen).
> 2. Cut the fallen trunk and limbs into pieces wherever you like. Put the axe away and drag them (heavy pieces drag slowly: cut them shorter).
> 3. Drag the wood onto your truck's bed; it rides loose, by friction.
> 4. Wood resting on the green sell pad sells by volume: u³ (1.6-stud cubes) x the wood's $ per u³, times its figure and boosts.
> 5. Spend, then push into farther biomes, as below.
>
> The steps below are the v1 loop, kept for a rollback (`CoreLoop = 1`) until M1.10.

1. Swing axe at a tree (hold/click). Tree has HP; axe has damage per hit.
2. Tree falls → becomes carryable logs (log count scales with tree size).
3. Carry logs to your truck (capacity limit) or straight to the sawmill.
4. Sell logs at the sawmill → cash.
5. Spend cash: better axe, bigger/faster truck, plot upgrades, new land access.
6. Repeat, pushing into farther biomes for rarer, pricier wood.

Target feel: first sale within ~3 minutes of spawning. First axe upgrade
within ~15 minutes. Never more than ~60 seconds of walking with nothing to do.

## 3. Progression systems

> **v2:** axe stats (damage, cooldown, range, per-wood bonuses), prices and truck beds are V2_PLAN §2's, in `ItemCatalog.*.v2` and `WoodData[*].v2`; ECONOMY.md shows them. The tables below are v1's.

### Axes (damage per hit / swing speed / price)
| Axe | Damage | Price (cash) |
|---|---|---|
| Rusty Axe (starter) | 5 | free |
| Steel Axe | 12 | 150 |
| Hardened Axe | 25 | 800 |
| Silver Axe | 45 | 3,500 |
| Cobalt Axe | 60 | 7,000 |
| Gold Axe | 80 | 12,000 |
| Obsidian Axe | 120 | 20,000 |
| Inferno Axe | 150 (200 vs. volcano trees) | 45,000 |
| Starfall Axe (V1 final, **forged**) | 180 (300 vs. sky trees) | forge: 60,000 + 40 Lumenwood + 12 Sky Shards |

Axes are **sold in order**: the shop only offers the next tier, so every
axe is a milestone and nobody skips from Silver straight to a late axe.
Cobalt and Obsidian (added 2026-09-30) split the two longest waits
(Silver → Gold and Gold → Inferno); ECONOMY.md shows the resulting path.
A player's tier is the best axe they have *ever* owned, so older axes can
be re-bought for a collection.

**Axes are items.** Every axe you own is its own item, duplicates included,
and all of them sit in your hotbar. Switch with the number keys or a tap,
so the Inferno Axe stays useful on volcano trees even after a stronger
general axe comes out; the game re-equips whichever you held last. Drop an
axe (Backspace or the Drop button) and it lies on the ground with a "Pick
up" prompt, ready for plot displays later. Axes are never lost: dying
doesn't drop them, and one left lying around is back in your inventory
when you rejoin. Only the owner can pick up a dropped axe for now, which
blocks "drop it, I'll hold it" scams. Gifting is one switch
(`GameConfig.AxePickupByOthers`) or, better, the trade window in Phase 7.

Tune so each axe roughly halves time-to-fell vs. the previous tier's trees.

### Wood tiers (HP / hardness / logs per tree / price per log / where)
| Wood | Tree HP | Hardness | Logs | $/log | Biome |
|---|---|---|---|---|---|
| Oak | 30 | 0 | 3 | 3 | Starter forest |
| Birch | 60 | 0 | 4 | 4 | Starter forest |
| Pine | 100 | 4 | 5 | 7 | Hills (short drive) |
| Maple | 200 | 10 | 6 | 10 | Hills |
| Palmwood | 300 | 15 | 6 | 20 | Island (boat required) |
| Frostwood | 400 | 20 | 7 | 25 | Snow biome (far) |
| Emberwood | 900 | 50 | 8 | 55 | Volcano biome (far, hazard) |
| Phantomwood | 1,200 | 70 | 9 | 65 | Night-only grove (timed event) |
| Lumenwood | 2,000 | 120 | 10 | 120 | Aether Isles, high above the map (V1 finale) |

**Hardness** is subtracted from every axe hit, so each wood needs a real
axe upgrade: the Rusty Axe can't cut maple at all, and emberwood needs the
Gold Axe or better. Price per HP falls up the tiers on purpose: rare wood
pays per *log* (worth the long drive in a big truck), not per swing. Tuned
2026-09-30 with `tools/economy.luau` so every §4 target is within 25%; see
ECONOMY.md.

Rare trees respawn slowly (5–15 min) to create scarcity and trading.

### Vehicles
Trucks haul on land, trailers add towed capacity, boats cross water. All
sold at the Dealership in town.

| Truck | Bed capacity | Top speed (studs/s) | Price (cash) |
|---|---|---|---|
| Rustbucket (starter) | 6 | 26 | free |
| Pickup | 12 | 28 | 1,200 |
| Scout ATV | — (fastest vehicle; marks rare trees on your map) | 40 | 2,500 |
| Flatbed | 24 | 26 | 6,000 |
| Logging rig | 48 | 24 | 25,000 |

Bigger beds drive slower (speeds added 2026-09-30, tuned so every §4 rate
stays within 25%). One trailer at a time hitches behind any truck with a
bed (not the Scout ATV); in V1 it's a rigid hitch, the rig turning as one. Any truck can be bought once you can afford it; trucks
you own are swapped at the Dealership, and the one you drive waits in your
parking spot. Driving is physics-based: trucks collide with trees and
buildings, and the driver's device simulates their own truck.

| Trailer (towed) | Extra capacity | Price (cash) |
|---|---|---|
| Pony trailer | +6 | 600 |
| Ranch trailer | +12 | 3,000 |
| Heavy hauler | +24 | 12,000 |

| Boat | Hull capacity | Price (cash) |
|---|---|---|
| Rowboat | 4 | 200 |
| Skiff | 8 | 900 |
| Motorboat | 16 | 4,000 |
| Cargo barge | 32 | 18,000 |

| Gear (Hearth & Home, one-time) | Effect | Price (cash) |
|---|---|---|
| Lantern | see in the dark (Phantom Grove) | 150 |
| Insulated Coat | ignore snow cold | 500 |
| Heat Boots | immune to lava burn | 800 |
| Featherfall Cloak | glide down instead of falling off the Aether Isles | 2,500 |
| Prospector's Pickaxe | mines stone, ore and crystal nodes (one pick for all) | 300 |

**Vehicle upgrades (the Garage, a building on your base).** Every truck
also improves along three tracks, paid in cash + Iron Ore, so vehicles
progress in more than bed size:

| Track | What it does | Why it matters |
|---|---|---|
| Engine | faster driving, per level | the haul is most of a trip; speed buys range |
| Tires & Chains | removes mud (Hills) and snow slowdowns | makes the hard biomes drivable |
| Log Crane | pulls nearby logs into the bed with one prompt | hand-carrying is ~90 s of every full Logging Rig load; this removes the worst chore |

### Materials
Gathered from nodes you mine with the Prospector's Pickaxe or from trees
you tap. Each has a job and a home, so it pulls players across the map.
They go straight into your inventory (logs keep the hauling).

| Material | Where | Used for |
|---|---|---|
| Stone | Hills quarry | base buildings, plot expansions |
| Iron Ore | Hills cliffs | Garage upgrades, machine parts |
| Resin | tap pines and maples, come back later | varnish: furniture sells for more |
| Ember Glass | volcano vents | kilns (dried planks are worth more), heat-proof truck parts |
| Sky Shards | Aether Isles crystal nodes | the Starfall Axe forge |

Your own planks are a building material too: the empire is built from
your own lumber.

### Plot
Player-owned plot near the sawmill: store logs, park truck, place decorations.
Upgrades: extra storage slots, second truck slot, sawmill shortcut (sell from
plot for a 10% fee), cosmetic buildings.

## 4. Economy targets

> **v2:** the targets are V2_PLAN §17's (first sale under 3 min, Steel Axe in 5-8 min, first $1k in 15-20 min, Cobalt in about 1 h, a full plot in 20-40 h). `lune run tools/economy` checks them in ECONOMY.md; the v1 model is `tools/economy1` (ECONOMY_V1.md). The wallet cap and the automation rule below are unchanged.

- New player earns ~$150–200 in the first 15 minutes (oak/birch, Rusty Axe).
- Mid-game (Steel Axe + Pickup, pine/maple): ~$1,500/hour of active play.
- End-game loop (Inferno Axe + rig, ember/phantom): ~$15k–20k/hour.
- Biggest purchases (Inferno Axe, logging rig, plot max) should take a
  dedicated player 2–4 sessions each — long enough to aspire to, short enough
  to reach. Add small money sinks (fuel, repairs optional; decorations) so
  cash always has somewhere to go.
- **Wallet cap: $2,000,000** (`GameConfig.CashCap`). Hardcore players can
  grind, but nobody runs away with the economy. Sales past the cap tell the
  player what didn't fit, and the cash display shows MAX. At the best V1
  loop that's ~67 h of saving, far past the ~17 h progression (ECONOMY.md).
- **Late game, automation may out-earn hand work** (§9), inside the wallet
  cap and warehouse limits.

## 5. Multiplayer / social

- Trading: player-to-player log/item trades with a confirm window (server
  validated — never trust the client's inventory). Axes are already items
  with uids (profile.axes), so they can move between inventories.
- Visit plots; leaderboard for lifetime earnings (opt-in).
- Co-op hauling: friends can load each other's trucks.
- Private servers for friend groups (monetized, see §7).

## 6. Technical architecture (Claude Code builds this)

- **Rojo layout** (`src/`): server logic in ServerScriptService, shared
  modules + RemoteEvents in ReplicatedStorage, client scripts in
  StarterPlayerScripts, UI in StarterGui. Map itself is built in Studio
  (Workspace not file-managed).
- **DataStores**: one Profile per player (cash, owned axes/trucks, plot data,
  stats). Save on interval + on leave. Handle save failures gracefully
  (retry, never wipe).
- **Networking**: RemoteEvents for ChopTree, SellWood, BuyItem, TradeOffer.
  ALL economy changes validated on the server. Client only sends *intents*.
- **Anti-exploit**: server owns cash, inventory, and tree HP. Rate-limit
  remotes. Sanity-check positions (no teleport chopping).
- **Performance**: tree respawn pooling, limit active physics logs, LOD on
  distant trees. Target: smooth on a mid-range phone.

## 7. Monetization (in Robux)

Keep it convenience/cosmetics — no pay-to-win axes that trivialize progression.

**Game passes (one-time)**
- 2x Cash (permanent) — 399 R$
- Lumberjack Truck (exclusive fast truck, sidegrade not best-in-slot) — 799 R$
- Extra Plot (second plot) — 599 R$
- VIP Chainsaw skin (cosmetic axe skin, works on any axe) — 249 R$
- Master Builder (plot expansion + exclusive blueprint skins) — 499 R$

**Developer products (repeatable)**
- Cash packs: 1k cash — 49 R$; 10k cash — 399 R$ (priced below grind value).
  Never offer a pack that would push the wallet past the $2,000,000 cap:
  check before prompting the purchase, because a granted receipt can't be
  undone.
- 2x Wood Weekend (48h) — 199 R$
- Instant delivery (sell truckload from anywhere, one use) — 29 R$

**Private servers** — 150 R$/month for friend groups.

**Built (2026-09-30):** `MonetizationService` + `Shared/StoreData` (item ids;
0 = not set up, hidden). Receipts are granted exactly once and saved before
Roblox is told (ProfileStore's LastSavedData pattern). 2x Cash doubles sale
income; 2x Wood doubles logs per felled tree for 48 h; Instant Delivery
sells the truck bed from anywhere. The Store screen shows Roblox's live
prices.

**Premium Payouts** — passive Robux from Premium subscribers' playtime;
rewards retention directly, so design for session length (events, dailies).

Reality check: creator keeps 70% of in-experience Robux sales; DevEx converts
earned Robux at $0.0038/R$ (min 30,000 earned Robux to cash out). Price and
forecast against that, not against gross Robux.

## 8. Build phases (vertical slices — test each in Play mode before next)

1. **Core loop**: one tree type, Rusty Axe, carry, sell. First sale in <3 min.
2. **Axe shop**: 3 tiers, buy/equip, damage actually changes fell time.
3. **Saving**: DataStore profiles, cash + owned items persist across sessions.
4. **Trucks**: buy, capacity limits, driving.
5. **Wood tiers + biomes**: 4+ tiers across 3 areas, respawn timers.
   5b. **V1 finale, the Aether Isles** (§10): Skyroot gondola, Cloud Chute
   + Sky Bin, Lumenwood, Sky Shards, Starfall Axe forge. If V1 runs long,
   this ships as the first big update instead.
6. **Plot + empire**: claim plot, droppers, flume tracks, sawmill shed,
   processing chain (logs → planks → furniture), warehouse, storefront.
7. **Social**: trading, companies, leaderboard.
8. **Monetization**: passes, dev products, private servers.
9. **Polish & launch**: thumbnail, icon, tutorial, analytics, bug bash.

**Milestones (what the phases add up to):**
1. **The core feels good.** Phases 1–4 pass in playtests, EFFICIENCY in
   `tools/economy.luau` is calibrated from a real playtest, and chop → haul
   → sell is fun to repeat. Nothing else matters until this holds.
2. **Retention: the real next milestone.** V1 is ~17 h for a focused player
   (ECONOMY.md). What carries players past that is seasons and festivals
   (§12), companies (§5, §7) and a reason to come back each day. These are
   doc-only today and come next, ahead of more content.
3. **Content and empire:** the remaining biomes (5), the Aether Isles
   finale (5b), plots and flumes (6). Then monetization and launch (8–9).

## 9. Empire building (blueprint-placed, not buy-buttons)

Your plot is a working lumber empire — but nothing is a buy-pad. Every
structure comes as a **blueprint**: buy it from the Blueprint Store, get a
ghost preview, rotate and snap it anywhere on your plot (grid snap, collision
and plot-bounds checked, all placement validated server-side). Move or sell
placed items freely. Freeform base-building, LT2-style, not a linear pad
ladder. Categories: Droppers, Machines, Flumes, Buildings, Decor.

**Droppers come in two kinds with genuinely different jobs:**

*Manual droppers — your labor is the multiplier (higher yield, needs you)*
- Sapling Plots: plant saplings and tend them by hand (watering) — they only
  grow while you're online and caring for them. Nothing grows while you're
  away; instead you pay to upgrade: fertilizer, better soil, greenhouse
  tiers that speed growth and improve yield. You chop them yourself at
  maturity. Best margins in the game per unit of wood.
- Hand Saw / Crank Mill: feed logs in by hand → better plank ratio than any
  automatic saw (e.g. 1 log → 3 planks by hand vs 2 by machine).
- Use case: active play and early game. If you're standing there working,
  you should earn more than any machine.

*Automatic droppers — the empire works while you don't (lower yield, passive)*
- Apprentice Crew hut: NPC lumberjacks fell trees on your plot on a timer,
  logs go to your intake.
- River Dock: logs float in on a timer.
- Auto Saw: processes logs without you at the worse ratio, throughput-capped.
- Use case: income while you're deep in the wild biomes chasing rare wood.
  The empire keeps moving so you never feel punished for leaving it.

Early and mid game, hand work pays best per unit, so the core loop matters
and every upgrade removes a chore (replanting, hand-feeding the saw,
hauling). **Late game, automation is allowed to take over and out-earn
hand work** (Connor, 2026-09-30): a built-out empire should feel like one.
Automation ladder, one chore at a time: self-replanting saplings → Auto
Saw on a flume → Apprentice Crew felling trees on your plot → crew haul
runs to a biome you've unlocked → Storefront selling while you're away.

**Keeping the game playable once automation wins:**
1. **Automation runs on what you unlocked by hand.** Crews only fell woods
   your best axe can cut and haul from biomes you've reached; machines are
   built and upgraded with materials you gather out in the world.
2. **The best things stay hands-on.** Lumenwood, Phantomwood, festival
   trees and contests, Sky Shards and other rare nodes can't be automated,
   so the wild is always worth going back to.
3. **Nothing runs away.** The $2,000,000 wallet cap (§4), Warehouse
   capacity, online-only production, and sinks that scale with the empire
   (base tiers, upgrades, cosmetics).
4. **The empire asks for decisions, not just waiting.** Contracts and
   storefront orders want specific goods by a deadline, so you plan what
   your lines make.

**Online only (for now, Connor 2026-09-30):** automation runs only while
you're in the game, working in the background while you're out in the
wild. Nothing produces while you're logged off. Output collects in your
Warehouse, which has a size limit. Saplings stay hands-on: they only grow
while you tend them. Offline production can be revisited later as a
retention lever.

**Base tiers.** Your plot grows through named tiers that give the freeform
building a spine, and each tier is visible from the road (sign, gate,
flag):

| Tier | Plot | Unlocks |
|---|---|---|
| Campsite (free) | 120×120 | sapling plots, a log pile |
| Homestead | 140×140 | Warehouse (stores logs + materials), Axe Rack |
| Lumber Yard | 160×160 | Sawmill Shed (planks), Garage (vehicle upgrades) |
| Timber Works | 180×180 | Workshop (furniture), Kiln, Apprentice Crew |
| Timber Empire | 200×200 | Storefront, Forge (the Starfall Axe), crew haul runs |

Tier-ups cost cash + Stone + your own planks. Once you have a Warehouse,
the Sky Bin (§10) can deliver there instead of the sawmill.

**Tracks — Log Flumes (the signature system)**
Lumber mills moved logs by water flume — so tracks are flumes, not sci-fi
conveyors (later tiers unlock belt conveyors). You lay flume segments across
your plot to connect machines into a production line:
Intake → Debarker → Saw → Planer → Assembler → Warehouse / Storefront.
Layout is the puzzle: longer chains multiply value per log but cost floor
space and cash. Throughput limits per flume tier keep it balanced.

**Processing chain (value multiplication)**
- Raw log → Saw → Planks (~2.5x log value)
- Planks → Workbench → Furniture per blueprint (~4–6x)
- Furniture → sold at your Storefront (set your own prices; other players
  and NPCs buy) or warehoused for contracts.
- Blueprint compendium: dozens to discover, some event-only — feeds the
  collector loop from §8.

**Buildings (blueprint unlocks, placed by you)**
- Sawmill Shed → unlocks plank processing
- Workshop → unlocks furniture blueprints
- Warehouse → storage capacity
- Storefront → player-to-player sales
- Walls, gates, lighting, decorations, plot expansions — the empire should
  *look* like an empire at a glance.

**Empire loop**: chop rare wood in the wild (best margins, LT feel) → feed it
through your flume line (multiplies value) → sell furniture, fill contracts,
or trade. Manual work always pays best per log; automation pays while you're
gone.

## 10. World layout & scale

Big world, big plots — everything on the feature list needs room to breathe.

**Plots**: base 120×120 studs, expandable to 200×200 (cash upgrades + Master
Builder pass). Big enough for a full flume line, a dropper farm, machines,
buildings, and decor without playing inventory tetris.

**World**: ~3000×3000 studs, everything spread out — the drive is part of
the game.
- Center: the Sawmill — sell hub and social crossroads.
- Town (next to the sawmill): the **Dealership** (trucks, trailers, boats,
  scout ATV) and **Hearth & Home** (furniture and lighting blueprints for
  your plot, plus biome gear).
- Plot district ringing the sawmill — empires on display.
- South: Starter Forest (oak, birch) — seconds from spawn.
- West: the Hills (pine, maple) — a short drive (~400 studs).
- North: Snow biome (frostwood) — far (~1200 studs).
- Far corner: Volcano (emberwood) — farthest (~1600 studs).
- East: the Beach — dock and boat shop. Offshore: the **Island**
  (palmwood, coconuts) — boat required, trucks can't swim.
- Phantom Grove: hidden, spawns night-only.
- Sky: the **Aether Isles**, floating high above the far corner, reached
  up the trunk of the **Skyroot**, a colossal tree visible from anywhere.

**Biome effects** — every biome pushes back a little:
- Starter Forest: safe. Learn here.
- Hills: muddy in the rain — vehicles slow ~15%.
- Snow: bitter cold — chop and move 15% slower without the Insulated Coat.
- Volcano: lava pools burn, ash storms cut visibility — Heat Boots stop the
  burn; storms you endure.
- Beach/Island: water is the barrier — you need a boat, and boats have
  their own cargo limits.
- Phantom Grove: pitch dark and whispering — a Lantern keeps you sane and
  spotting trees.
- Aether Isles: wind gusts shove you toward the edges and lightning strikes
  marked circles. Falling off loses the logs in your hands (never axes);
  the Featherfall Cloak lets you glide down instead.

### V1 finale: the Aether Isles
The end-game the whole map points at: the Skyroot towers over the far
corner from minute one, and its canopy hides floating islands of glowing
**Lumenwood**.

- **Getting up:** a gondola climbs the Skyroot's trunk ($250 a ride, a
  money sink). No vehicles up top: you work on foot across isles joined by
  rope bridges.
- **Getting logs down:** the **Cloud Chute**. Drop logs in at the edge and
  they ride a flume spiralling down the Skyroot, across the map, into your
  personal **Sky Bin** at the sawmill (30 logs; bigger bins are an upgrade
  later). Sell from the bin when you come down. It's the flume system's
  first appearance before plots get their own (§9).
- **Lumenwood:** 2,000 HP, hardness 120, 10 glowing logs at $120, rare and
  slow to regrow (15 min), so it's worth trading. Only the Inferno Axe can
  dent it at first (67 hits a tree).
- **Starfall Axe:** V1's final axe is **forged, never sold**: $60,000 + 40
  Lumenwood logs + 12 **Sky Shards** (crystals mined on the isles). It fells
  Lumenwood in 12 hits. On volcano trees the Inferno Axe is still better
  (150 vs 130 after hardness), so collectors keep both (axes are items, §3).
- **Pacing (ECONOMY.md):** gathering forge logs with the Inferno Axe pays a
  little less than emberwood (the grind); once forged, the Starfall loop is
  the best in the game (~35% above the volcano). Forging takes about 3 hours
  of saving; all of V1 is about 17 hours for a focused player.
- **Other isle items:** Sky Shards (the forge material, also sellable) and
  a sky-themed plot decoration blueprint.
- **Built (2026-09-30):** the Skyroot stands in the far north-west corner
  (x -1050, z 1050), the isles float above it at ~700 studs. The gondola
  runs from a station by the sawmill (so the Sky Bin is a short walk from
  where you get off, as the economy model assumes) and from one at the
  Skyroot's foot, for anyone who fell. The Starfall Forge is on the main
  isle for V1 (the Timber Empire plot Forge can come with plots). Sky
  Shards aren't sellable yet; wind and lightning aren't in yet.

Distances are deliberate: better wood means a longer haul, so truck upgrades
buy *range*, not just stats. No early fast-travel — the drive is part of the
game.

## 11. New player experience (first 10 minutes)

> **v2:** Murph's seven steps keep their ids and order with v2 objectives (V2_PLAN §13, `TutorialData.StepsV2`): fell a tree, drag a log, drag it onto your bed, sell on the pad, plant a Heartseed, sell $60 more ($25 from Murph), buy the Steel Axe ($90). A new player starts with $20.

A mentor NPC — **Murph**, a retired lumberjack — teaches by doing, not by
dialogue walls. One objective at a time in a quest tracker, beacon guidance,
everything skippable for alt accounts. Tutorial trees are plentiful so new
players never compete for them.

1. **Spawn** at the Starter Forest edge, axe in hand. Murph: "See that oak?
   Give it a whack." Teaches: equip, click/hold to chop. HP bar, hit
   feedback, the fall.
2. **Haul.** "Grab those logs — load your truck." Teaches: pick up, carry
   capacity, the Rustbucket (your run-down starter truck).
3. **First sale.** Beacon to the Sawmill. "Sell 'em at the mill." Cha-ching —
   3 oak logs, $9. Target: under 3 minutes from spawn.
4. **The goal.** "That Rusty Axe won't cut it in the hills." Quest: chop and
   sell 3 more loads; completion bonus bridges the gap to the $150 Steel Axe.
   Teaches the grind loop with a near-term payoff (~12 min to first upgrade).
5. **Claim your plot.** "Every lumberjack needs land — and this one's free."
   Walk the plot district, claim yours. Claiming is free; growing the plot
   bigger costs you. Teaches: plots, the district as a social space.
6. **First blueprint.** Free Sapling Plot blueprint, "on the house." Ghost
   preview → rotate → place → plant your first sapling — then water it.
   "Trees don't grow on wishes, kid. Tend it, or pay to make it grow faster."
   Teaches blueprint placement AND the manual-tending rule: nothing grows
   while you're away; upgrades (fertilizer, greenhouse) speed things up.
   Session-2 hook: your sapling needs you.
7. **The horizon.** Murph hands you a **Field Guide** — your wood compendium,
   every undiscovered species a silhouette. "Hills west for pine," he says,
   marking your map. "Snow north when you're ready. And kid — the Phantom
   Grove only shows at night." You leave the tutorial holding a book full of
   question marks. Teaches: the world has tiers, the compendium is the
   long-term chase; gives aspiration before the tutorial ends.

**Built so far** (Shared/TutorialData, QuestService, QuestUI): beats 1–4,
then "Buy the Steel Axe" as the last step; 5–7 wait for plots, blueprints
and the Field Guide. Beat 4 is "sell 18 more logs" (about three Rustbucket
loads) for a $25 bonus. The model already has players affording the Steel
Axe in ~10 min without it (ECONOMY.md), so the bonus pulls that to ~9 min,
under the 12–15 min target; Connor chose to keep it (2026-09-30).

**Field Guide (built):** Murph hands it over when the tutorial ends (or is
skipped). Every wood is a "???" with a hint of where it grows until you
fell one; then its page shows the biome, HP, hardness, logs and price, the
first axe that cuts it and the first that does so in 30 hits or fewer.

Tutorial ends; the quest log takes over ("Buy the Steel Axe", "Chop 10
birch", "Sell your first planks"...). Session-2 hooks already planted: a
thirsty sapling, the Steel Axe goal, the hills in sight, a Field Guide full
of silhouettes, a rumor about the night.

## 12. Cozy life (Stardew-inspired)

Timberline Tycoon has a tycoon's progression with a farming sim's soul. These
systems make the world worth *living in*, not just optimizing.

- **Seasons.** Four seasons rotate (~2 weeks each), changing the map: winter
  freezes the lake into a shortcut but buries the hill roads; autumn colors
  the starter forest. Some woods and forage only appear in certain seasons.
- **Festivals.** Each season ends with a festival at the sawmill grounds:
  log-chopping contests (mini-game), seasonal market stalls, exclusive
  blueprints and cosmetics. Dates on the in-game calendar — reasons to come
  back.
- **NPC friendships.** Murph, Millie (sawmill keeper), and the blueprint
  shopkeep have friendship meters. Gift them wood, furniture, or forage;
  hearts unlock shop discounts, exclusive blueprints, and personal quest
  lines. Murph's story unfolds across the seasons.
- **Foraging.** Mushrooms, berries, pinecones scattered through the biomes —
  gather by hand, sell for early cash or gift to NPCs. Gives new players
  something to do while trees respawn.
- **Day/night + weather.** Full cycle (the Phantom Grove is night-only);
  rain, storms that knock down bonus trees, auroras over the snow biome.
  Cozy, not just cosmetic — weather changes what the world offers.
- **Daily goals (built).** Three goals a day (UTC), picked per player and
  sized to their axe tier: fell trees, load logs, sell logs, sell one wood,
  earn cash. Each pays a small reward; finishing all three pays a bonus
  that grows with the **streak** (days in a row, up to 2x at 5 days). A
  missed day breaks it. Rewards are modest on purpose (at most $105 a day
  on the Rusty Axe, $9,100 on the Starfall Axe; see ECONOMY.md) so dailies
  bring players back without replacing play. Tuning: `Shared/DailyData`.

### Seasons and festivals: build plan (next)
The next retention milestone after dailies, in this order:
1. **Season clock** (`SeasonService`): one server-agnostic calendar from
   UTC time (no DataStore needed): season = (days since launch // 14) % 4.
   Expose it as a workspace attribute; the HUD shows "Autumn · day 6".
2. **World tint per season**: Lighting presets and leaf colours per season
   (§13), applied by the client from the attribute. No gameplay yet; proves
   the clock and looks good in screenshots.
3. **Seasonal content, from data**: a `SeasonData` table (which woods and
   forage spawn, price multipliers, e.g. frostwood +20% in winter). The
   economy calculator reads it so seasonal swings stay inside the targets.
4. **Festivals**: the last 2 days of each season. First one: a timed
   log-chopping contest at the sawmill (most logs sold in 10 minutes,
   server-wide leaderboard, cosmetic rewards only). Cosmetics avoid
   feeding the economy.
5. **Seasonal dailies**: DailyData gets a per-season goal pool (e.g. "sell
   6 frostwood logs" in winter) once more woods are in the world.

## 13. Art direction — cozy low-poly

Soft shapes, warm light, readable at a glance. Distinct from LT2's classic
blocky look; built for phones (low part counts, no per-tree scripts). After
the first live session Connor asked for "a little more" LT2 styling in the
landscape (October 2026): a deeper meadow green, brown rock and boulders,
pale gravel haul roads, and landmarks (a footbridge, docks, a lighthouse).
The cozy palette stays; the land borrows LT2's wide open spaces and
brown-on-green read.

**Biome palettes**
- Starter Forest: warm greens, honey-brown oak, golden light.
- Hills: deeper greens, amber maple, long afternoon shadows.
- Snow: pale blues, white drifts, cool rim light.
- Volcano: charred dark rock, ember-orange glow, ash in the air.
- Phantom Grove (night): deep purples, teal glow, fireflies.
- Aether Isles: white-gold light, soft cloud banks, Lumenwood motes drifting
  upward, the whole map spread out below.

**Readability rules (gameplay-critical)**
- Every wood tier has a distinct silhouette + color — identify value at 50
  studs, no tooltip needed.
- Tree size scales with tier; rare trees are landmarks, not surprises.
- Chop feedback: shake, chips fly, HP bar, a satisfying *thunk*. The fall
  should feel earned.

**Characters & props**
- Blocky lumberjack archetypes; Murph = big beard, red flannel, beanie.
- Axes read by silhouette: Rusty (dull, pitted) → Cobalt (icy blue) →
  Obsidian (black volcanic glass) → Inferno (glowing edge).
- Trucks: the Rustbucket is visibly held together by hope (mismatched
  panels, a little smoke); the Logging rig gleams.

**UI aesthetic**
- Wood-grain + kraft paper + stenciled type. Chunky rounded buttons.
- The Field Guide looks and feels like a worn journal.
- Screen layout (Connor, 2026-09-30): cash top right with the Daily Goals
  button under it; the quest tracker small, on the left (under Roblox's
  chat window), never nagging. Roblox's own player list stays off until our
  leaderboard exists, since it would cover the cash.

**Lighting & mood**
- Warm days, cozy sunsets, aurora nights over the snow biome.
- Seasons re-tint the world: autumn ambers, winter desaturation, spring
  bloom. The world should *feel* like the calendar turned.

**Thumbnail & icon (launch)**
- Bold and readable at 128px: one big tree, one big axe, title text.
  Face-like tree silhouettes and saturated colors win clicks in the genre.

**Performance budget**
- Trees as simple low-poly (parts or single meshes), pooled respawns.
- Distant trees get LOD swaps; cap active physics logs.
- Target: smooth on a mid-range phone in a busy server.

## 14. Implementation spec (Claude Code handoff)

Written so an AI coder can implement directly. Follow it; ask Connor before
deviating from data values or architecture.

### 14.1 Conventions
- `src/` files are the source of truth. Rojo syncs filesystem → Studio.
  Never hand-edit scripts inside Studio.
- Luau. `task.wait()`, never `wait()`. Type annotations encouraged.
- `*.server.luau` = Script, `*.client.luau` = LocalScript, else ModuleScript.
- `require()` uses Roblox paths: `require(ReplicatedStorage.Shared.WoodData)`.
- PascalCase for modules/services, camelCase for locals.

### 14.2 Profile schema (DataStore "PlayerProfiles", key "profile_<UserId>")

> **v2 fields** (ProfileSchema, V2_PLAN §14): `schema` (2 once migrated), `v2Credit` (the buy-back owed, paid on join), `truckLoad` (loose wood saved off the beds), `forgeWood` and `skyWood` (u³), `stats.volumeSold`, `stats.cuts`. `ProfileSchema.MigrateV2` runs on every v2 join; the v1 fields stay so a rollback loses nothing.
```lua
export type PlacedItem = {
  uid: string,            -- guid
  blueprintId: string,
  x: number, z: number,   -- centre in plot-local studs (PlotData.Grid snap)
  rot: number,            -- 0-3 quarter turns
  -- data: { any }? comes with saplings, e.g. { water: number, stage: number }
}
-- Plot-local, not a world CFrame: your plot slot can differ per server, so
-- the layout rebuilds wherever you land. PlotLogic.Check validates it.
export type Profile = {
  cash: number,
  totalEarned: number,    -- lifetime, for leaderboard + rebirth math
  rebirths: number,
  axes: { AxeItem },      -- AxeItem = { uid: string, id: string }; duplicates allowed
  bestAxeTier: number,    -- highest axe rung ever owned (1 = Rusty); gates the shop
  equippedAxe: string,    -- uid of the axe last held; re-equipped on spawn
  ownedTrucks: { string },
  equippedTruck: string,  -- default "Rustbucket"
  ownedTrailers: { string },
  ownedBoats: { string },
  gear: { string },       -- "Lantern" | "InsulatedCoat" | "HeatBoots" | ...
  materials: { [string]: number },  -- Stone, IronOre, Resin, EmberGlass, SkyShard (when built)
  plot: { claimed: boolean, tier: number, placed: { PlacedItem } },  -- tier: PlotData.Tiers index
  compendium: { [string]: boolean },       -- wood ids discovered
  furnitureBlueprints: { [string]: boolean },
  npcFriendship: { [string]: number },     -- "Murph" | "Millie" | "Tink"
  stats: { treesChopped: number, logsSold: number, playtimeMin: number },
  tutorialDone: boolean,
  tutorialStep: number,   -- index into TutorialData.Steps
  tutorialProgress: number,
  seasonId: string,
  daily: { day: number, goals: { DailyGoal }, streak: number,
           bestStreak: number, lastCompleteDay: number },  -- DailyService
  purchaseIds: { string },  -- recent Robux receipts already granted
  doubleWoodUntil: number, instantDeliveries: number,  -- Robux boosts
}
```
- Autosave every 120s + on PlayerRemoving. Retry with backoff. If load
  fails, hold the player in a safe retry state — never overwrite a good save
  with a blank one.
- Session-lock via UpdateAsync so two servers can't double-spend.

### 14.3 Static data (ReplicatedStorage.Shared) — balance lives HERE
- `WoodData.luau`: per wood — id, displayName, treeHP, hardness,
  logsPerTree, pricePerLog, biome, respawnSec, silhouette, colorHex.
- `ItemCatalog.luau`: axes, trucks, trailers, boats, gear, blueprints —
  id, displayName, priceCash, stats.
- `BiomeData.luau`: per biome — access (truck / boat / gondola), haul
  distance, required gear, slowdowns, night-only, hazards; the sky biome
  adds gondola ride time + fee, Sky Bin size and chute walk. The economy
  calculator reads it too.
- `ItemCatalog.Materials`: gathered materials (Sky Shard) with sell price;
  forged axes carry a `forge` recipe and `sold = false`.
- Tuning = editing these tables, never code.

### 14.4 Remotes (ReplicatedStorage.Remotes) — intents only, never trust
- `ChopTree(treeUid)` — server checks: within 12 studs of the bark (ChopRange + trunk radius), axe equipped,
  per-player 0.8s cooldown. Applies damage to server-side HP.
- `PickupLog(logUid)` — distance check; logs are free-for-all after fell
  (10s grace to the feller).
- `SellLogs()` — only inside the sawmill SellZone; server values logs from
  server-side records, then calls EconomyService.
- `BuyItem(category, itemId)` (ShopService) — within `GameConfig.ShopRange`
  of the shop's counter; axes only if `ShopLogic.StatusOf` allows it (sold
  in order via `ItemCatalog.CanBuyAxe`, never forged ones, at most
  `GameConfig.MaxOwnedAxes`), then `EconomyService.SpendCash` and
  `AxeService.Grant`. The answer comes back as a toast; the shop screen
  redraws from the Cash / OwnedAxes / BestAxeTier player attributes.
- `SkipTutorial()` — ends Murph's tutorial early, no rewards.
- `EquipItem(category, itemId)` — switch to a truck you own; at the
  Dealership counter, not while driving, only if the load fits.
- `CallTruck()` — "Truck to lot": your truck back in your parking slot;
  10 s cooldown, not while driving. The load comes along only from within
  150 studs of town; from farther out it's left on the ground where the
  truck stood (yours for 10 minutes), so the haul home can't be skipped.
  Rejoining works the same way (the save remembers where the truck was).
- `DropAxe(axeUid)` — owner only; the axe becomes a world item with a
  "Pick up" prompt (owner only unless `GameConfig.AxePickupByOthers`).
- `PlaceBlueprint(blueprintId, x, z, rot)` (PlotService) — validates: on
  your own claimed plot, the blueprint's tier unlocked, inside plot bounds,
  no overlap (`PlotLogic.Check`), funds. You pay on placing (the ghost
  preview is free).
- `MoveBlueprint(uid, x, z, rot)`, `SellPlaced(uid)` (half back, all of it
  within a minute of placing), `UpgradePlot()` (the next base tier).
- `WaterSapling(uid)` — distance + ownership check.
- `GiftNPC(npcId, itemRef)`.
- Rate-limit everything per player (ChopTree 4/s, PlaceBlueprint 2/s…).
  Log violations; warn then kick.

### 14.5 Server services (ServerScriptService)
- `GameServer.server.luau` — bootstrap, PlayerAdded/Removing wiring.
- `ProfileService.luau` — sole DataStore reader/writer. The save's types,
  new-player template and migrations live in `ProfileSchema.luau`.
- `EconomyService.luau` — SOLE writer of `profile.cash`.
  `addCash(player, n, reason)` / `spendCash(player, n, reason)`; every change
  logs its reason.
- `TreeService.luau` — spawns trees per biome from WoodData, server-side HP,
  fell → spawns server-owned log Models (attributes: WoodId, Value).
- `AxeService.luau` — axes as items: one Tool per owned axe (attributes
  AxeId, AxeUid), drop/pick up, and `GetEquippedAxe` for ChopTree checks.
- `ShopService.luau` — the BuyItem remote: the Tool Shed (axes), later the
  Dealership (trucks). Shared rules in `Shared/ShopLogic.luau`.
- `PlotService.luau` — claim, size upgrades, place/move/sell validation.
- `DropperService.luau` — manual + automatic dropper ticks.
- `FlumeService.luau` — production lines consume inputs on timers, output
  the next stage.
- `VehicleService.luau` — trucks built from ItemCatalog (`Shared/TruckLayout`),
  parking slots, physics driving via network ownership with a server-side
  speed check (or the arcade fallback, `GameConfig.VehiclePhysics`),
  recall and switching; later trailer attach and boats.
- `QuestService.luau` — tutorial beats + quest log.
- `NPCService.luau` — dialogue, friendship, gifts.
- `DailyService.luau` — daily goals and streaks (rules in `Shared/DailyData`).
- `BiomeService.luau` — biome rules per player (slowdown, lava, gear needed
  to chop; rules in `BiomeData.Rules`). `WorldClock.luau` — day/night from
  real time (`Shared/WorldTime`), night-only trees.
- `SeasonService.luau` — clock, seasons, festivals, weather, day/night.
- `TradingService.luau` — phase 7.

### 14.6 Client (StarterPlayerScripts)
- `Client.client.luau` — bootstrap.
- `ChopController.luau` — click/hold input, swing animation, HP bar UI.
- `CarryController.luau`, `VehicleController.luau`, `AxeController.luau`
  (Drop button + Backspace).
- `BlueprintPlacer.luau` — ghost preview (green/red validity), R to rotate,
  2-stud grid snap, click to place.
- UI modules: `HUD`, `ShopUI`, `FieldGuideUI`, `QuestUI`, `DialogueUI`.

### 14.7 Map build notes (Studio, Workspace — NOT Rojo-managed)
- Trees: Model named `Tree_<WoodId>_<n>`, PrimaryPart set, tag "Tree"
  (CollectionService), attributes: `WoodId` (string), `MaxHP` (number).
- Logs: server-created Models, tag "Log", attributes `WoodId`, `Value`.
- SellZone: invisible Part at the sawmill. Plot spots: Parts tagged
  PlotService builds them from `PlotData.Slots` (plot district east of
  town). Biomes: folders in Workspace, art per §13.

### 14.8 Economy formulas (implement, don't eyeball)

> **v2** (V2_PLAN §2c, SectionLogic, SellLogic): hits to cut a section `ceil(hardness x (thickness / 1.6)² / damage)`; a piece's value is its u³ x the wood's log (or plank) $/u³ x its figure's multiplier x its boost, and 2x Cash once on the sale. The v1 formulas below are kept for a rollback.
- `hitsToFell = ceil(treeHP / max(0, axeDamage - hardness))` (0 damage =
  can't cut it); swing cooldown 0.8s. `lune run tools/economy` applies these
  formulas to the data tables and writes ECONOMY.md.
- `cashPerHour ≈ 3600 / cycleSec × logsPerTree × pricePerLog`
  (cycleSec measured in playtest, not hardcoded).
- After each phase, check against §4 targets; if off by >25%, tune the
  data tables, not the code.
- Automation vs hand work (§9): below the Timber Works tier, automation
  earns less than active play at the same tier; from there it may earn
  more. Automation only runs while the player is online; output is capped
  by Warehouse size and all cash by `GameConfig.CashCap` ($2,000,000).

### 14.9 Phase 1 acceptance checklist (no Phase 2 until all pass)
- [ ] Spawn with Rusty Axe; oak falls in exactly 6 hits (30 HP / 5 dmg).
- [ ] Tree shakes, chips fly, HP bar shows; falls and spawns exactly 3 logs.
- [ ] Pick up ≤ 2 logs by hand (prompt within 10 studs).
- [ ] Rustbucket bed holds 6; load/unload at the sawmill.
- [ ] Sell in SellZone: +$3/log (oak); cash changes ONLY via EconomyService.
- [ ] Leave + rejoin: cash and axe persist.
- [ ] First sale achievable in < 3 min in a solo Play test.
- [ ] `ChopTree` rejected beyond 12 studs from the bark; rate-limited at 4/s.

### 14.10 Definition of done, per phase
Playtest in Studio, checklist passes, zero console errors, commit as
`phase-N: <what changed>`.

## 15. Risks
- **IP**: inspired-by is fine; cloning LT2's name/art/UI is a takedown risk.
- **Exploits**: tycoon economies get cheated fast — server-authoritative from
  day one, not retrofitted.
- **Retention**: launch is the starting line. Plan weekly events and a content
  cadence before promising a date.
- **Scope**: cut phase 6–7 scope before cutting core-loop feel. A tight loop
  with 3 wood tiers beats a sprawling game that feels empty.
- **Item sprawl**: gathered materials are welcome (Connor, 2026-09-30), but
  each needs a job: an input to something players want (a building, an
  upgrade, a forge), found in a specific place so it pulls players across
  the map. A material nothing uses is clutter.
- **Uncalibrated economy**: every pacing number in ECONOMY.md scales with
  EFFICIENCY, a 0.50 guess until a playtest measures it. Calibrate early
  and again whenever the loop changes (the stopwatch prints the command).

## 16. The Living Forest (the twist; added October 2026)

> **v2:** the same rules on section trees (ForestService.UseV2): every piece freed from a figured tree carries its figure, seeds drop by tree size, a Heartseed planted in a stub grows back mature, and the planter's 15% share is paid once when the tree is felled.

**Built (October 2026):** everything in this section except "Next" is in
the game (ForestData holds every number below; ForestLogic the rules;
ForestService, ForestUI and ForestArt the rest). The numbers are a first
pass for playtesting.

Research (REDESIGN.md) found that weather mutations with multipliers are
saturated, including in our own genre (*Chop Your Tree*). What no lumber
game does is make the forest **respond to you**. Timberline's twist: you
don't just harvest the forest, you tend it, and it remembers.

**The loop it adds:** fell a tree → Heartseeds pop out → plant one in a
stump (the tree grows back early, wearing your name) → anyone who later
fells it pays you the planter's share → replanted groves thrive → thriving
groves grow more figured wood and wake Elder giants. Every felled tree is
now three decisions: which tree (read the bark), when, and where its seed
goes.

### Heartseeds
- Every felled tree drops **1** Heartseed of its wood (+1 for a large tree,
  +1 on a 15% roll, +1 for a storm-struck tree). Elders drop more (below).
  Seeds fly to the feller (a glowing pop and a counter tick).
- Seeds are saved per wood (`profile.heartseeds`), at most 50 of a wood and
  200 in all.
- **Planting:** stand at a stump (within 12 studs) holding a seed of that
  wood and press "Plant Heartseed". A sapling sprouts on the stump and the
  tree is standing again **8 seconds** later, long before its natural
  regrowth (woods outside the ground groves keep their rarity: a planted
  Lumenwood sprouts for half its regrowth, about 7.5 minutes; palmwood
  75 s). It's marked as yours (a little name stake at its foot).
- **The planter's share:** when anyone else fells a tree you planted, you
  earn **15% of its logs' base value**, paid by the game (the feller loses
  nothing), if you're on the server. Felling your own planted tree gives
  +1 Heartseed instead (the steward's bonus) once it has stood 10 minutes;
  felling it sooner gives no bonus and takes back the vitality its planting
  gave, so nobody can pump a grove alone by planting and refelling one
  tree. Either way the tree grows back wild unless someone replants it.
- **Who felled it:** a felling (its logs' pickup window, its Heartseeds,
  the tutorial and daily credit) counts for whoever chopped the most of
  it, not whoever landed the last swing.

### Grove Vitality
- Each ground biome has a vitality meter, 0–100, shared by the server
  (workspace attribute `Vitality_<biome>`). It starts at 60 and drifts back
  toward 60 by 1 point a minute.
- Felling a wild tree −1.5; felling a planted tree −0.5; planting +4.
- Tiers: **Thinning** under 35, **Healthy** 35–74, **Thriving** 75–89,
  **Old Growth** 90+. The biome banner shows the tier.
- Thriving and Old Growth groves come alive (more flowers, butterflies,
  birdsong, deer, fireflies at night), grow more figured wood (below) and
  can wake an Elder. Clear-cutting never punishes anyone's own progress:
  a thinning grove just has fewer surprises in it.

### The Hidden Grain (figured wood)
- When a tree grows (spawns or regrows), it may hide a **figure**. Chance:
  6%, ×0.5 / ×1 / ×1.5 / ×2 by the grove's tier, +4% if planted, ×2 during
  a Skyroot Bloom.
- Figures, with their weights and what each log sells for:
  | Figure | Weight | Value | Bark clue |
  |---|---|---|---|
  | Curly | 45 | ×1.5 | wavy diagonal bark strips |
  | Birdseye | 30 | ×2 | small dark "eyes" dotted over the trunk |
  | Quilted | 17 | ×2.5 | scalloped bark plates |
  | Burl | 8 | ×4 | a big knobbly swelling near the base |
  | Starfall Burl | (30% of Lumenwood burls) | ×8 | a burl speckled with stars |
  | Stormgrain | lightning only | ×3 | glowing blue cracks, sparks |
- The clue is always on the bark: reading the forest is the skill (the
  Field Guide's Hidden Grain page teaches every clue). Every log of a
  figured tree carries the figure (a coloured band on the log); the
  **sawmill reveals it** when you sell ("BIRDSEYE MAPLE ×2!").
- Economy: the figure average adds about 6% to wood income at Healthy
  (tools/economy.luau models it).

### Storms strike trees
- In a storm (WeatherService), lightning strikes now and then. A strike
  near a tree marks it **storm-struck** for 2 minutes: glowing cracks,
  sparks, a toast for everyone nearby. Fell it in time and its logs are
  Stormgrain (+1 Heartseed). Weather is an input to the forest, never a
  flat multiplier.

### Elder trees
- At most one Elder on a server at a time. Every 8–15 minutes a Thriving or
  Old Growth grove may wake one (more likely the higher its vitality): a
  giant of that grove's wood (1.7× size, 6× HP, 3× logs, always figured:
  Quilted or Burl), glowing, announced server-wide.
- **Co-op:** everyone who chopped at least 10% of it counts: they all get
  2 Heartseeds and a helper's bonus of 10% of its logs' value, and its
  logs are free to grab at once. An Elder nobody fells fades after 15
  minutes (a Phantom Grove Elder fades at dawn, and only wakes with at
  least 5 minutes of night left). Elders never regrow (the grove has to
  earn the next one).
- A tree that grows back, wakes or appears where a truck or a player
  stands comes up as a ghost (no collisions) until the spot is clear.

### The Skyroot Bloom
- When the five ground groves average 75 vitality or more, the Skyroot
  blooms for 8 minutes (workspace attribute `SkyrootBloom`): golden motes
  pour off it, figure chances double everywhere. Then it rests for 30
  minutes. Servers that replant together see it more.

### Next (designed, not built)
- **Genes and breeding** on plot Sapling Plots: a Heartseed carries a small
  genome (girth, height, hue, density, figure, vigor); neighbouring plot
  trees cross-pollinate at dawn; the first player to grow a new cultivar
  names it in the Field Guide registry (generated names only). Sapling
  Plots stay hands-on (tended while online), per §9.
- **Skyroot Rising:** cross-server weekly goals (offer wood and seeds at the
  roots) that grow new branch isles, once there are players to drive it.

## 17. Art and world, v2 (October 2026)

> **v2 loop:** trees are TreeGen section trees built by TreeArt.FromSkeleton (775 sites), which grow in four stages, age and die; cut pieces are loose WoodService models.

The redesign replaced every placeholder with art built in code
(`Shared/Art`, previewed with `tools/preview` without Studio) and put the
world on generated terrain. REDESIGN.md has the rules and contracts.

**Style.** Cozy low-poly, as §13: chunky faceted shapes, warm saturated
colour, each wood with its own silhouette and canopy palette (oak's broad
crown, birch's pale trunk, pine's tiers, maple's autumn fire, frostwood's
snow caps, emberwood's glowing cracks, phantomwood's violet glow,
lumenwood's light), readable at 50 studs. Buildings stand on stone
plinths with board-by-board plank walls, shingled roofs and warm windows.
Trucks tell their story: the Rustbucket is held together by hope (a
primer-green door, a dented fender, a rope-tied tailgate, heavy smoke),
the Logging Rig gleams. Decoration never collides; what you bump into
does.

**The world** (about 3,000 studs square, `Shared/World`):
- The **town** sits flat at the centre: the sawmill at (0, 110) with the
  sell pad and Sky Bin in front, the Tool Shed, Dealership and Hearth &
  Home along a dirt main street, the gondola station behind, Murph's camp
  by the spawn at (0, 40), the parking lot to the east and the plot
  district beyond it.
- **Biomes** ring it, each reached by a dirt road with a signpost: the
  Starter Forest just south, the Hills west, the Snowfields plateau far
  north, the Volcano's cone in the north-east corner, the Phantom Grove
  hidden in a hollow south-west (no road), the coast and an island to the
  east, a lake south-west, mountains round the edge.
- **Wild groves** (22 small stands of oak, birch, pine and maple) dot the
  open country between the biomes, all at least 300 studs from the
  sawmill so they never shorten the first haul.
- The **Skyroot** rises in the north-west: a colossal tree whose limbs
  hold the four Aether Isles; its waterfall feeds the river that winds
  past the town to the lake.

**A living place.** A 20-minute day with keyframed light per biome and
weather; weather from a shared schedule (storms strike real trees, §16);
town lamps and windows that light up at dusk; wind that sways the trees;
client-side decoration and wildlife that thicken as groves thrive; nine
townsfolk with routines (Murph, three shopkeepers, Millie at the mill, Gus
at the gondola, three walkers); ambient sound and music by time of day.

