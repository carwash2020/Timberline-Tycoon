# V1 Studio checklist, open decisions and cross-lane findings

Refreshed 12 October 2026 for main at `4ecfa51` (#159). Main now has #135 machine meshes, #136 backlog meshes, #138 NPCs,
tutorial and goals, the Sparkworks shop in town (#144), the ButtonR2 removal (#143), grab on RT (#151), the four store interiors (#159 to #162) and the load, freeze and
first-look fixes (#150 to #158). Nobody can run Studio from a session, so this is what Connor checks by hand. Each lane's
own, longer checklist is in PHASE2_NOTES.md (the section name is in brackets).

Set up: `rojo build -o build.rbxlx`, open it, turn on "Enable Studio Access to API Services" (saves only keep
with it), press Play. Output window open. The owner chat commands (`AdminLogic`) let you skip ahead: give cash,
set the time, unlock buildings. Never publish or put anything on sale from this list. DataStore and "publish this place"
log lines are normal.

## What to check in Studio right now (about 20 minutes, fresh profile, PC then phone 667 x 375 then Xbox)

Nothing below has been seen in Studio. Each line says what good looks like.

1. **Play within 15 s.** Press Play on a fresh server. Good: the loading card goes and you can walk within about 15 s.
   Output shows `[Load] +N.Ns ...` lines and `[MapBuilder] ... done in` lines, then `[MapBuilder] World built in` and
   `build phases that gate play:` with `gating build X of 15s budget` (a warning names the slowest step if over). Lines
   `[Load] deferred <name> took` follow after you are in. Note the seconds for the gating build and the worst `[Load]` step.
2. **No PlayerScripts errors.** Good: no red text from `PlayerScripts`, no `[Client] ... failed to start`, no
   "Infinite yield", no `Script timeout`, no `[BaseBoot] no Remotes folder`.
3. **Staged terrain.** Walk out of town toward the woods straight away. Good: ground is under you everywhere you walk, the
   far chunks fill in a block at a time behind you (`[MapBuilder] Terrain n/100`), nobody falls through, no pop-in right at
   your feet.
4. **8 AM, Day 1.** Good: the first screen is morning daylight, the clock reads about 8:00 AM and "Day 1". Rejoin the same
   server: the clock does not restart at 8:00.
5. **The picker only with 2+ saves.** A brand-new profile (or one played save) goes straight in with no save picker.
   Play a second save, rejoin: the picker shows, three cards fit, PLAY is 44 px. Murph and the tracker wait for the pick.
6. **Starter loadout.** Good: Rusty Axe, Hammer, Rusty Pick (three slots, 44 px on phone). No Lux Axe unless the pass is owned.
7. **The Foreman.** Walk west of the sawmill door: Rook Calloway (hard hat, clipboard) faces the road. E opens the job board
   with three goals; Take pays once; Esc or B closes; Murph's tutorial blocks it until finished; phone board ends above the
   jump button; Xbox first button is selected.
8. **RT grab and chop (Xbox).** Axe put away, aim at a loose log, hold RT: it lifts; release drops it; D-pad turns it. With
   the axe equipped RT chops as before and never grabs. Nothing is bound to R2 or shown as ButtonR2.
9. **Mesh swap-in.** Good: the world appears first in plain parts, then shops, NPCs, trees and the machines pop to their real
   meshes over a few seconds with no hitch. `[MeshKit]` lines list a miss once per asset; the Glow Wire stays a plain bar
   (no GLB yet, silent by design). `[MapBuilder] meshes after the build:` ends with most meshes loaded.
10. **Store interiors.** All four are on main (#159 with #160 to #162). Good for all: warm beams and lanterns (never white), a sign over each table and a small sign over each group
    readable from the door, every box on a coloured stand, aisle wide enough to carry a box, frame rate fine on Lower.
    - **Tool Shed:** "AXES & BELTS" and "MACHINES" headers, sub-signs AXES, BELT KIT, SAWMILLS, PLANERS & SAW;
      tier flags T2 to T8 on axes; on a new save the axes above the next one show a dark "NEEDS <axe>" chip and a grey stand;
      a CHECKOUT plaque on the counter; crates and barrels in the west back corner (parts first, then the real meshes).
    - **Hearth & Home:** headers GEAR, BUILD PLANS, HOME PLANS, LAMPS; gear stands T3 to T5 with lock chips by
      stage; side aisles still 3.2 studs.
    - **Sparkworks:** "BELTS & INPUTS" and "LOGIC & OUTPUTS", five sub-signs over all 21 boxes, belts yellow and
      logic teal stands (no tier flags); Juno behind the counter; copper conduit on the walls.
    - **Dealership:** a SHOWROOM board, a header per run of one kind (TRUCKS, TRAILERS), a sub-sign over each bay
      ("BED: 12 LOGS"), tier stripes on the aisle; the Logging Rig's crane pokes above the 15 stud ceiling (known).
11. **Reduce flashing (this branch).** Settings, GAME tab: a REDUCE FLASHING row (44 px, ring on Xbox, B closes). Turn
    CAMERA SHAKE off: the row reads "ON (SHAKE OFF)". Force a storm in the Starter Forest: in the server command bar `workspace:SetAttribute("WeatherOverride", "Storm")`.
    Good: with it off, a double white flash with each bolt; with it on, one soft pulse and no flicker; the bolt and thunder
    still happen. Rejoin: the choice is kept.

## A. PC (keyboard and mouse, about 15 minutes)

1. Join. Good: loading card, quality choice, save picker, no red Output text, first player can play inside
   about 10 s. [Join race fix, Load time 2]
2. Walk to the sell pad east of the sawmill, chop one oak, carry it to the pad, sell. Good: cash goes up once,
   one toast. [Murph's 8 step tutorial, #138]
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
20. Interact and Buy are ButtonX; the grab is RT with empty hands and RB selects; nothing binds ButtonR2.

What good looks like overall: no Output errors, no duplicated money or items after a rejoin, no prompt you
cannot reach on a phone or a pad.

## D. Open decisions, with the default the code uses

Nothing here blocks V1; each default holds until Connor says otherwise.

| # | Decision | Default in code |
|---|---|---|
| 1 | Badge ids (25 badges, 8 new), names, descriptions, icons | ids stay 0 until pasted into `BadgeData.Ids`; Homestead needs 40 filled pieces |
| 2 | The five formerly off-sale products: Tow, Timber Classic, Paint Shop, 2x Wood, Instant Delivery | ids stay 0 (Coming soon); never put on sale from code |
| 3 | Real prices of the four live Robux items | read from Roblox's live answer only; none written in code |
| 4 | Does 2x Wood mean twice the logs? | it doubles wood value |
| 5 | Lux Pickaxe pass or bundle, and its price | not for sale, `passId` 0, level 4 |
| 6 | Miner's Lamp also counts as the Lantern in Gloam | no (it only lights tier 3 mining) |
| 7 | Stage names and the pack income table (`StageOf.Names`, `IncomePerHour`) | the proposed names; #138's `Stage:Sn` keys now set the stage |
| 8 | Sparkworks prices (Switch Belt $150 ... Laser Receiver $220) and `MaxLaserPairs` 8 | proposals as coded |
| 9 | Building costs: Copper Trim $4 + 1 ingot, Sandstone Wall and Floor $8 + 2 slabs, Arch $16 + 4 slabs; stage unlocks S1 to S5 | proposals as coded |
| 10 | Quarry slab refill 60 s, 24 loose slabs, Wader Boots $2,000 + 20 u3 | as coded |
| 11 | Bayou gate Stage 2 and Red Mesa gate Stage 4 | as coded |
| 12 | Hermit's Maul mesh, hand 25 to 30% up the haft, Lux haft 4.0, box corner bevels | part-built Maul, 0.75 grip, 3.5 haft, no bevel parts |
| 13 | Lanternwood tuning values marked `TBD (Designer)` in `WoodData.luau` | the current numbers; economy bands hold |
| 14 | Palm section trees keep 3 coconuts | yes |
| 15 | Unload cooldown 120 s; loose wood blocks unload | as coded |
| 16 | `AdminLogic.OwnerUserIds`: the second owner id | one id is in (#140); the second stays blank, owner tools work only in Studio for it |
| 17 | `mining`, `guideStamps`, `dayCounter` account-wide (briefs said per slot) | account-wide |
| 18 | Phone tree disc ceiling 2.0x (`TownTreeData.PhoneDiscMax`) | 2.0x |
| 19 | Camera speed in Settings | dropped (#153): the engine owns the camera speed, we never write it; the saved `cameraSensitivity` key stays so old saves load |
| 20 | Paid boosts have no cap (Connor, 8 October) | none; boosts stack fully |
| 21 | Stage 8 (Master Timber) from a full plot (top tier plus all 24 squares) | not derived; only the `Stage:S8` key sets it (it would raise cash packs about 25%) |
| 22 | Glow Wire GLB (a 3.4 x 0.28 neon bar on two iron posts, footprint 4 x 2) | none exists; the part build is used silently |
| 23 | Reduce flashing: the softened flash (quarter strength, one pulse, 0.35 s) and being forced on by Camera shake off | as coded |

## E. Cross-lane requests and findings left for other PRs

Found by the integration pass's scans and specs (`V1Refs`, `V1Playthrough`, `V1Migration`, `V1World`,
`V1Budgets`). None loses save data, duplicates money, or breaks a stage.

1. ~~The Sparkworks counter is not in the world~~: done (#144, the shop, Juno and the path; PHASE2_NOTES.md "Sparkworks shop in the world").
2. **Stage 8 (Master Timber) has no derivation from progress**: only Lane E's `Stage:S8` key sets it. DECISION FOR
   CONNOR: derive S8 from a full plot (top tier plus all 24 squares)? It would raise the stage-scaled cash packs for
   full-plot players by about 25% ($160k/h to $200k/h), so it waits for your approval. Default: not changed.
3. ~~Old ButtonR2 uses~~: done (#143 removed them; #151 put the empty-hand grab on RT, read only, never bound; `NoButtonR2.spec`).
4. **The ambient "town" zone now covers the Dealership** (fixed in this PR): `ScatterZones` town radius 180 to 300
   (centre (0, 90)); the Dealership at (258, 130) is inside, and `V1World` pins every shop inside it. No town
   scatter pieces exist (`NatureData` town = {}), so only town weather and critter rules widen.
5. ~~No STATUS.md notes from #135, #136, #138~~: they landed; STATUS.md lists them.
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
