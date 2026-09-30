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

1. Swing axe at a tree (hold/click). Tree has HP; axe has damage per hit.
2. Tree falls → becomes carryable logs (log count scales with tree size).
3. Carry logs to your truck (capacity limit) or straight to the sawmill.
4. Sell logs at the sawmill → cash.
5. Spend cash: better axe, bigger/faster truck, plot upgrades, new land access.
6. Repeat, pushing into farther biomes for rarer, pricier wood.

Target feel: first sale within ~3 minutes of spawning. First axe upgrade
within ~15 minutes. Never more than ~60 seconds of walking with nothing to do.

## 3. Progression systems

### Axes (damage per hit / swing speed / price)
| Axe | Damage | Price (cash) |
|---|---|---|
| Rusty Axe (starter) | 5 | free |
| Steel Axe | 12 | 150 |
| Hardened Axe | 25 | 800 |
| Silver Axe | 45 | 3,500 |
| Gold Axe | 80 | 12,000 |
| Inferno Axe | 150 | 45,000 |

Tune so each axe roughly halves time-to-fell vs. the previous tier's trees.

### Wood tiers (HP / logs per tree / price per log / where)
| Wood | Tree HP | Logs | $/log | Biome |
|---|---|---|---|---|
| Oak | 30 | 3 | 8 | Starter forest |
| Birch | 60 | 4 | 15 | Starter forest |
| Pine | 120 | 5 | 28 | Hills (short drive) |
| Maple | 220 | 6 | 55 | Hills |
| Palmwood | 300 | 6 | 85 | Island (boat required) |
| Frostwood | 400 | 7 | 120 | Snow biome (far) |
| Emberwood | 700 | 8 | 260 | Volcano biome (far, hazard) |
| Phantomwood | 1,200 | 9 | 600 | Night-only grove (timed event) |

Rare trees respawn slowly (5–15 min) to create scarcity and trading.

### Vehicles
Trucks haul on land, trailers add towed capacity, boats cross water. All
sold at the Dealership in town.

| Truck | Bed capacity | Price (cash) |
|---|---|---|
| Rustbucket (starter) | 6 | free |
| Pickup | 12 | 1,200 |
| Scout ATV | — (fast recon, no cargo) | 2,500 |
| Flatbed | 24 | 6,000 |
| Logging rig | 48 | 25,000 |

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

### Plot
Player-owned plot near the sawmill: store logs, park truck, place decorations.
Upgrades: extra storage slots, second truck slot, sawmill shortcut (sell from
plot for a 10% fee), cosmetic buildings.

## 4. Economy targets

- New player earns ~$150–200 in the first 15 minutes (oak/birch, Rusty Axe).
- Mid-game (Steel Axe + Pickup, pine/maple): ~$1,500/hour of active play.
- End-game loop (Inferno Axe + rig, ember/phantom): ~$15k–20k/hour.
- Biggest purchases (Inferno Axe, logging rig, plot max) should take a
  dedicated player 2–4 sessions each — long enough to aspire to, short enough
  to reach. Add small money sinks (fuel, repairs optional; decorations) so
  cash always has somewhere to go.

## 5. Multiplayer / social

- Trading: player-to-player log/item trades with a confirm window (server
  validated — never trust the client's inventory).
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
- Cash packs: 1k cash — 49 R$; 10k cash — 399 R$ (priced below grind value)
- 2x Wood Weekend (48h) — 199 R$
- Instant delivery (sell truckload from anywhere, one use) — 29 R$

**Private servers** — 150 R$/month for friend groups.

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
6. **Plot + empire**: claim plot, droppers, flume tracks, sawmill shed,
   processing chain (logs → planks → furniture), warehouse, storefront.
7. **Social**: trading, companies, leaderboard.
8. **Monetization**: passes, dev products, private servers.
9. **Polish & launch**: thumbnail, icon, tutorial, analytics, bug bash.

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

The design leans manual-heavy on purpose: there's always something worth
doing by hand, and hand work always pays best per unit. Automation is how
progression *feels* — each upgrade removes a chore (replanting, hand-feeding
the saw, hauling) without ever out-earning an active player at the same tier.
Plot space and budget stay limited so your mix is a real decision:
manual lines for max yield while you're there, automation keeping the empire
breathing while you're out in the wild.
Balance rule: passive empire income caps around ~40% of what active
chopping + manual processing earns at the same tier.

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

Distances are deliberate: better wood means a longer haul, so truck upgrades
buy *range*, not just stats. No early fast-travel — the drive is part of the
game.

## 11. New player experience (first 10 minutes)

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
   3 oak logs, $24. Target: under 3 minutes from spawn.
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

## 13. Art direction — cozy low-poly

Soft shapes, warm light, readable at a glance. Distinct from LT2's classic
blocky look; built for phones (low part counts, no per-tree scripts).

**Biome palettes**
- Starter Forest: warm greens, honey-brown oak, golden light.
- Hills: deeper greens, amber maple, long afternoon shadows.
- Snow: pale blues, white drifts, cool rim light.
- Volcano: charred dark rock, ember-orange glow, ash in the air.
- Phantom Grove (night): deep purples, teal glow, fireflies.

**Readability rules (gameplay-critical)**
- Every wood tier has a distinct silhouette + color — identify value at 50
  studs, no tooltip needed.
- Tree size scales with tier; rare trees are landmarks, not surprises.
- Chop feedback: shake, chips fly, HP bar, a satisfying *thunk*. The fall
  should feel earned.

**Characters & props**
- Blocky lumberjack archetypes; Murph = big beard, red flannel, beanie.
- Axes read by silhouette: Rusty (dull, pitted) → Inferno (glowing edge).
- Trucks: the Rustbucket is visibly held together by hope (mismatched
  panels, a little smoke); the Logging rig gleams.

**UI aesthetic**
- Wood-grain + kraft paper + stenciled type. Chunky rounded buttons.
- The Field Guide looks and feels like a worn journal.
- Quest tracker: small, top-left, never nagging.

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
```lua
export type PlacedItem = {
  uid: string,            -- guid
  blueprintId: string,
  cframe: { number },     -- 12 components, validated server-side
  data: { any }?,         -- e.g. sapling: { water: number, stage: number }
}
export type Profile = {
  cash: number,
  totalEarned: number,    -- lifetime, for leaderboard + rebirth math
  rebirths: number,
  ownedAxes: { string },
  equippedAxe: string,    -- default "RustyAxe"
  ownedTrucks: { string },
  equippedTruck: string,  -- default "Rustbucket"
  ownedTrailers: { string },
  ownedBoats: { string },
  gear: { string },       -- "Lantern" | "InsulatedCoat" | "HeatBoots"
  plot: { claimed: boolean, size: number, placed: { PlacedItem } },
  compendium: { [string]: boolean },       -- wood ids discovered
  furnitureBlueprints: { [string]: boolean },
  npcFriendship: { [string]: number },     -- "Murph" | "Millie" | "Tink"
  stats: { treesChopped: number, logsSold: number, playtimeMin: number },
  tutorialDone: boolean,
  seasonId: string,
}
```
- Autosave every 120s + on PlayerRemoving. Retry with backoff. If load
  fails, hold the player in a safe retry state — never overwrite a good save
  with a blank one.
- Session-lock via UpdateAsync so two servers can't double-spend.

### 14.3 Static data (ReplicatedStorage.Shared) — balance lives HERE
- `WoodData.luau`: per wood — id, displayName, treeHP, logsPerTree,
  pricePerLog, biome, respawnSec, silhouette, colorHex.
- `ItemCatalog.luau`: axes, trucks, trailers, boats, gear, blueprints —
  id, displayName, priceCash, stats.
- `BiomeData.luau`: biome id, effect id + params (slowFactor, damagePerSec).
- Tuning = editing these tables, never code.

### 14.4 Remotes (ReplicatedStorage.Remotes) — intents only, never trust
- `ChopTree(treeUid)` — server checks: distance < 20 studs, axe equipped,
  per-player 0.8s cooldown. Applies damage to server-side HP.
- `PickupLog(logUid)` — distance check; logs are free-for-all after fell
  (10s grace to the feller).
- `SellLogs()` — only inside the sawmill SellZone; server values logs from
  server-side records, then calls EconomyService.
- `BuyItem(category, itemId)` → returns ok/err.
- `PlaceBlueprint(blueprintId, cframe12)` — validates: blueprint owned,
  plot claimed, inside plot bounds, no overlap, funds. Returns uid.
- `MoveBlueprint(uid, cframe12)`, `SellPlaced(uid)`.
- `WaterSapling(uid)` — distance + ownership check.
- `GiftNPC(npcId, itemRef)`.
- Rate-limit everything per player (ChopTree 4/s, PlaceBlueprint 2/s…).
  Log violations; warn then kick.

### 14.5 Server services (ServerScriptService)
- `GameServer.server.luau` — bootstrap, PlayerAdded/Removing wiring.
- `ProfileService.luau` — sole DataStore reader/writer.
- `EconomyService.luau` — SOLE writer of `profile.cash`.
  `addCash(player, n, reason)` / `spendCash(player, n, reason)`; every change
  logs its reason.
- `TreeService.luau` — spawns trees per biome from WoodData, server-side HP,
  fell → spawns server-owned log Models (attributes: WoodId, Value).
- `PlotService.luau` — claim, size upgrades, place/move/sell validation.
- `DropperService.luau` — manual + automatic dropper ticks.
- `FlumeService.luau` — production lines consume inputs on timers, output
  the next stage.
- `VehicleService.luau` — trucks, trailer attach, boats.
- `QuestService.luau` — tutorial beats + quest log.
- `NPCService.luau` — dialogue, friendship, gifts.
- `SeasonService.luau` — clock, seasons, festivals, weather, day/night.
- `TradingService.luau` — phase 7.

### 14.6 Client (StarterPlayerScripts)
- `Client.client.luau` — bootstrap.
- `ChopController.luau` — click/hold input, swing animation, HP bar UI.
- `CarryController.luau`, `VehicleController.luau`.
- `BlueprintPlacer.luau` — ghost preview (green/red validity), R to rotate,
  2-stud grid snap, click to place.
- UI modules: `HUD`, `ShopUI`, `FieldGuideUI`, `QuestUI`, `DialogueUI`.

### 14.7 Map build notes (Studio, Workspace — NOT Rojo-managed)
- Trees: Model named `Tree_<WoodId>_<n>`, PrimaryPart set, tag "Tree"
  (CollectionService), attributes: `WoodId` (string), `MaxHP` (number).
- Logs: server-created Models, tag "Log", attributes `WoodId`, `Value`.
- SellZone: invisible Part at the sawmill. Plot spots: Parts tagged
  "PlotSpot". Biomes: folders in Workspace, art per §13.

### 14.8 Economy formulas (implement, don't eyeball)
- `hitsToFell = ceil(treeHP / axeDamage)`; swing cooldown 0.8s.
- `cashPerHour ≈ 3600 / cycleSec × logsPerTree × pricePerLog`
  (cycleSec measured in playtest, not hardcoded).
- After each phase, check against §4 targets; if off by >25%, tune the
  data tables, not the code.
- Passive cap: total auto-dropper output ≤ 0.4 × active cashPerHour at the
  same tier.

### 14.9 Phase 1 acceptance checklist (no Phase 2 until all pass)
- [ ] Spawn with Rusty Axe; oak falls in exactly 6 hits (30 HP / 5 dmg).
- [ ] Tree shakes, chips fly, HP bar shows; falls and spawns exactly 3 logs.
- [ ] Pick up ≤ 2 logs by hand (prompt within 10 studs).
- [ ] Rustbucket bed holds 6; load/unload at the sawmill.
- [ ] Sell in SellZone: +$8/log; cash changes ONLY via EconomyService.
- [ ] Leave + rejoin: cash and axe persist.
- [ ] First sale achievable in < 3 min in a solo Play test.
- [ ] `ChopTree` rejected beyond 20 studs; rate-limited at 4/s.

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
