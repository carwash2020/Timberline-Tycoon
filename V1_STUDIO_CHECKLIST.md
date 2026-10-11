# V1 Studio checklist, open decisions and cross-lane findings

Written 11 October 2026 for main at `2bf981d` (#139), by the V1 integration pass. Nobody can run Studio from a
session, so this is what Connor checks by hand. About 30 minutes for the three parts. Each lane's own, longer
checklist is in PHASE2_NOTES.md (the section name is in brackets). Not on main yet, so not covered here: #135
machine meshes, #136 backlog meshes, #138 NPCs, tutorial and goals.

Set up: `rojo build -o build.rbxlx`, open it, turn on "Enable Studio Access to API Services" (saves only keep
with it), press Play. Output window open. The owner chat commands (`AdminLogic`) let you skip ahead: give cash,
set the time, unlock buildings. Never publish or put anything on sale from this list.

## A. PC (keyboard and mouse, about 15 minutes)

1. Join. Good: loading card, quality choice, save picker, no red Output text, first player can play inside
   about 10 s. [Join race fix, Load time 2]
2. Walk to the sell pad east of the sawmill, chop one oak, carry it to the pad, sell. Good: cash goes up once,
   one toast. [Murph tutorial lines belong to #138; on main the tutorial is the 8 step one]
3. Land Office (Old Hank): buy a plot for $150. Good: the picker shows which pad, you are charged once, a sign
   with your name stands on the plot. A visitor cannot place anything on it. [Lane F CanEdit, plot picker]
4. Tool Shed: buy the Steel Axe ($150 by the v1 table, $110 under the live v2 loop). Good: each next axe is
   locked until the one before it is owned; the Starfall Axe shows "forged". [Lane D]
5. Dealership: buy a truck. Good: a box, open it on your plot, the box becomes a pad, the truck drives, Call
   truck works. [Real stores]
6. Hammer: place a Cabin, fill it with planks (carry planks to the ghost). Good: "Your plot holds 1200 kit parts
   at most" is the only refusal; Undo inside 60 s refunds in full. [Lane F]
7. Climate: walk into the Snowfields without the Insulated Coat (cold bar fills, damage after 8 s), buy the coat
   at Hearth and Home, repeat (no damage). Same with Heat Boots at the Volcano and the Lantern at Gloam Hollow
   (night only). [V1 economy core]
8. Mine: walk into the mine mouth at (150, -150), mine copper with the Rusty Pick, smelt at the furnace pad
   (48, -110), craft a Miner's Lamp at the bench. Good: a bomb opens the rubble; no money for slabs or ore the
   chute refuses. [Lane M, MINING.md]
9. Bayou (BayouRoad): the sign says "Needs Stage 2: the Steel Axe". Mud slows you to 0.6x until Wader Boots
   ($2,000 and 20 u3 of Bog Cypress planks at the Bait Shack). Red Mesa: "Needs Stage 4: the Cobalt Axe", eight
   quarry faces give one carried sandstone slab each ($0, never cash). [Bayou and Red Mesa]
10. Sandstone: fill a Sandstone Wall with slabs. Good: it takes the slabs and the cash fee atomically; an
    empty-handed press takes nothing. [Lane F, Lane R]
11. End game (cheat to Obsidian Axe): Gus's Charter at the town gondola (Obsidian Axe, then 120 Frostwood,
    120 Emberwood, 40 Gloamwood planks), then ride up ($250), forge at the Sky Forge, temper an axe, buy a relic.
    Good: no cash fee for the charter, "Gondola Pass needed" before it, the ride down is never refused.
    [Lane A2, End game follow-ups]
12. Leave and rejoin: cash, axes, plot, loose wood and slabs return once. Pick a different save slot and back.
    [Saves by hand, Lane F]

## B. Phone (667 x 375 emulator, then a real phone, about 8 minutes)

13. Lower quality. Drive the ring road once. Good: no stutter at the junctions, the Bayou or the mesa (FPS on a
    real device is the open AR1 check).
14. Open every panel from MENU: Store, Saves, Field Guide, Settings, What's new, Badges, Forge, Craft. Good: each
    Close is 44 x 44 or larger, clear of the thumbstick and the jump button.
15. Prompts (Quarry a slab, Wader Boots, Look around, Talk, Buy) tap clean; a 0.6 s quarry hold works by touch.
16. Place a piece with the touch placer: drag, rotate, Place; no ButtonR2 needed. [PlaceControls]
17. The HUD column: MENU, HAMMER, Sell here stay in view, and the hotbar is clear of the stick.

## C. Xbox (controller, about 7 minutes)

18. Every panel above: the selection ring is visible, the first button is selected on open, the D-pad reaches
    every control, B closes and gives focus back. View button opens the quick menu with Badges in it.
19. Swing on RT, place with the placer's own keys (LT lock, left stick flicks, RB/LB slide), drop an axe with B.
20. Interact and Buy are ButtonX; nothing new binds ButtonR2 (the older R2 uses are listed in section E).

What good looks like overall: no Output errors, no duplicated money or items after a rejoin, no prompt you
cannot reach on a phone or a pad.

## D. Open decisions, with the default the code uses

Nothing here blocks V1; each default holds until Connor says otherwise.

| # | Decision | Default in code |
|---|---|---|
| 1 | Badge ids (25 badges, 8 new), names, descriptions, icons | ids stay 0 until pasted into `BadgeData.Ids`; Homestead needs 40 filled pieces |
| 2 | Off-sale products: Tow, Timber Classic, Paint Shop, 2x Wood, Instant Delivery | ids stay 0 (Coming soon); never put on sale from code |
| 3 | Real prices of the four live Robux items | read from Roblox's live answer only; none written in code |
| 4 | Does 2x Wood mean twice the logs? | it doubles wood value |
| 5 | Lux Pickaxe pass or bundle, and its price | not for sale, `passId` 0, level 4 |
| 6 | Miner's Lamp also counts as the Lantern in Gloam | no (it only lights tier 3 mining) |
| 7 | Stage names and the pack income table (`StageOf.Names`, `IncomePerHour`) | the proposed names; Lane E's keys become the only source with #138 |
| 8 | Sparkworks prices (Switch Belt $150 ... Laser Receiver $220) and `MaxLaserPairs` 8 | proposals as coded |
| 9 | Building costs: Copper Trim $4 + 1 ingot, Sandstone Wall and Floor $8 + 2 slabs, Arch $16 + 4 slabs; stage unlocks S1 to S5 | proposals as coded |
| 10 | Quarry slab refill 60 s, 24 loose slabs, Wader Boots $2,000 + 20 u3 | as coded |
| 11 | Bayou gate Stage 2 and Red Mesa gate Stage 4 | as coded |
| 12 | Hermit's Maul mesh, hand 25 to 30% up the haft, Lux haft 4.0, box corner bevels | part-built Maul, 0.75 grip, 3.5 haft, no bevel parts |
| 13 | Lanternwood tuning values marked `TBD (Designer)` in `WoodData.luau` | the current numbers; economy bands hold |
| 14 | Palm section trees keep 3 coconuts | yes |
| 15 | Unload cooldown 120 s; loose wood blocks unload | as coded |
| 16 | `AdminLogic.OwnerUserIds` (Connor's UserIds) | empty, owner tools work only in Studio |
| 17 | `mining`, `guideStamps`, `dayCounter` account-wide (briefs said per slot) | account-wide |
| 18 | Phone tree disc ceiling 2.0x (`TownTreeData.PhoneDiscMax`) | 2.0x |
| 19 | The old ButtonR2 uses (see E) | a separate branch, `phase-2/v1-no-buttonr2`, removes them |
| 20 | Paid boosts have no cap (Connor, 8 October) | none; boosts stack fully |

## E. Cross-lane requests and findings left for other PRs

Found by the integration pass's scans and specs (`V1Refs`, `V1Playthrough`, `V1Migration`, `V1World`,
`V1Budgets`). None loses save data, duplicates money, or breaks a stage; the first is the one to fix before V1.

1. **The Sparkworks counter is not in the world on main.** The buy path and stock exist (`StoreStock.Sparkworks`,
   `ShopService`), `BuildingArt.Sparkworks()` exists, but no builder places the shop and its keeper (lines only
   in `DialogueData`, "DRAFT: no Sparkworks building"). So Button, Lever, Pressure Plate, the gates, Delay,
   Sustain, Clock, Glow Wire, Hatch, Wood Sweeper, Laser Emitter, Laser Receiver, Switch Belt, Tilted Belt, Belt
   Support and Wood Detector cannot be bought in a normal game, and `BlueprintBook.Message` tells a player to
   "Buy the X at the Sparkworks counter first". What's new also advertises "Sparkworks logic pieces".
   Owner: Lane F task 16 / Lane E (#138, the keeper). Until then they come only from the owner Gifts tab.
2. **Stage 8 (Master Timber) cannot be reached on main.** `StageOf.FromProgress` tops out at S7 (the Starfall
   Axe) and nothing writes `Stage:S8`; Lane E's `MilestoneService` stage events are in #138. Cash packs, the
   blueprint book and the S8 badge read it.
3. **Old ButtonR2 uses**, not touched here (restricted Xbox files): `BuilderTools.luau` (select ray bound on R2
   while hands are empty, passes the press through), `WireTool.luau` and `InputKit.luau` (Pick, Place and Grab
   lists), `CutController.luau` and `DragController.luau` (read as input). A separate branch removes them.
4. **The Dealership sits outside the ambient "town" zone.** It stands at (258, 130), 261 studs from the zone
   centre (0, 90) whose radius is 180 (`ScatterZones`, `WorldPlan` scatter), so town weather and critter rules do
   not cover the showroom. Lane G / B decide whether to widen the zone to about 300.
5. **No STATUS.md notes from #135, #136, #138 yet.** They add to it when they merge; merge conflicts there are
   keep-both.
6. **Not run here (Studio only):** phone FPS on a real device (AR1), wade depth (AR6), every look in this file.

Scans that passed (and that CI now runs): 68 remotes each once with a RateLimiter budget, a server user and a
client or server peer; no trade or gift remote; every client module in the Client list; only EconomyService
writes cash; only ProfileService touches a DataStore; no Robux price in code; every profile field a service
writes is in `ProfileSchema.Template`; a hand-built pre-V1 save joins, rejoins and three-slot-switches with
nothing lost, no duplicate grant, the stranded wood restored once and under 1 MB; the axe ladder, every gate,
wood, ore, gear and recipe has a job, a home and a cash path from Rusty Axe to the forged Starfall Axe; plots,
fixed NPC spots, shops and both new regions are on dry ground, 500+ studs from each other and off the roads;
phone budgets sit under the PC budgets on every axis. The five economy headlines (68 s, 5.4 min, 15.4 min,
48.2 min, 31.4 h) are inside their CI ranges (`lune run tools/economy --check`).
