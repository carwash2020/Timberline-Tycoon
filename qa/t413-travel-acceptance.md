# T413 Travel — acceptance (written FIRST)

Sources: vision.md §3 RULE 3 (roads/bridges/ferry/Skyroot, no gondola), §4 travel times, §12 audit rows 1–2 REMOVE / 24–26 REDO, §13 T413; quality-bar.md DoD; main `a66c562` (post-T412): GameConfig TollFee=100 TollSeconds=180 FerryFare=400; FerryLogic TravelSec=40 Deck 14×22; FerryService (trucks currently refused); GateService toll window; ShopPlace Sparkworks FerryRequired; WorldPlanDraft.Bridge / Roads / LiveFerry; MustKeep TollBooth Counter + FerryDock; Manager ticket 2026-10-28 ~3:41 PM America/Denver. Checked 2026-10-28 America/Denver.

## Connor locks (do not reinterpret)
- Town / main bridge: **free** (no TollFee).
- Out-of-town important (Dealership) lift bridge: **$100** (`GameConfig.TollFee`, keep 100 / TollSeconds 180 unless ticket retunes window).
- Ferry: **$350** (wire `GameConfig.FerryFare` from 400 → 350; all UI/NPC copy reads the config).
- No paid fast travel in V1.

## Locks / MustKeep
- MustKeep unmoved except intentional travel pins: SpawnLocation; TollBooth/Counter; FerryDock; GateLodge; T411 Weigh House + town mill; T412 live shop ids ToolShed / HearthAndHome / Dealership / Sparkworks (+ Counter/ShopPoint) and Coat/Heat/Odds/Land/Secret pins; SellPad CanCollide false; Block wood pipeline; no gondola runtime.
- No StoreData / Cap / ItemCatalog prices / paint / pass / truckPaint ProfileSchema edits.
- MeshId 0 greybox OK for ferry boat + lift/stone bridges until turntables; HideStandIns when MeshId set (vision §10).
- Soft bay-stack stays parked (Manager).

## Acceptance tests (failing specs / lints first)
| # | Player-visible / pipeline | Spec shape |
|---|---|---|
| 1 | Town/main bridge crosses with **$0** toll; no GateService charge on that span | Toll / WorldPlan bridge kind |
| 2 | Dealership-side lift bridge charges exactly `TollFee` **$100** once; within `TollSeconds` (180) no second charge; unpaid barrier / push-back still works | GateService + TollLogic real path |
| 3 | `GameConfig.FerryFare == 350`; FerryLogic ActionText / TalkLines / board UI and any timetable board show that fare (no hardcoded 400) | GameConfig + FerryLogic / FerryService.spec |
| 4 | Car ferry: player **walks the deck**; crossing ≤ `FerryLogic.TravelSec` (40); timetable / leave-board visible at dock | FerryLogic + FerryService |
| 5 | **Vehicle-on-ferry:** truck (and trailer if present) may board and ride; flip current FerryService truck refuse; seated driver is not rejected as "truck" for a legal car ferry | FerryService.spec red→green |
| 6 | Fare taken at departure from riders aboard only; short cash / away / board-close fail closed with clear toast; no double charge mid-crossing | FerryService |
| 7 | Sparkworks: while isle unreachable, `FerryRequired` refuse buys; when ferry dock + berth ready and isle land exists, clear attribute and buys succeed | ShopService + ShopPlace |
| 8 | No gondola stations, cabins, cables, turnstiles, ride prompts, or Gondola* services reintroduced | MustKeep + rg / GateLodge only for Sky Pass |
| 9 | Skyroot switchback road reaches GateLodge / summit disc; pull-outs present; junction signs at forks (at least SKYROOT / FERRY / Dealership-side) | WorldPlanDraft.Roads + sign markers |
| 10 | Main road/bridge clearances fit truck + trailer (vision main 32 / branch 24); doors/paths clear; whole-world collidable overlap lint empty | Clearance + OverlapCheck |
| 11 | Lift bridge + stone branch bridges + ferry hull/deck exist at WorldPlan pins; Footbridge KEEP assets not deleted | MustKeep / LandmarkArt |
| 12 | Diff gate: no StoreData/Cap/catalog/paint/pass/ProfileSchema; Block wood untouched | Diff vs `a66c562` |
| 13 | Previews: lift bridge, both docks + ferry, Skyroot hairpin, one junction sign; Art PASS look; Builder PASS clearances | preview/t413/ |

## Edge cases
14. Re-pay toll only after window expires; leave and re-enter within window free.
15. Ferry with loose cargo: weld or refuse consistently; rider who jumps off mid-crossing does not keep welded cargo arrival (existing FerryService rule).
16. Gloam rope footbridge (if placed this ticket): foot only; trucks blocked / long road remains.
17. Island berth aligns with Sparkworks harbour pin ~(1115, −700) / LiveFerry; no open-sea shop without deck.
18. Invisible CanCollide only with documented Kit.blocker reason.
19. No teleport / paid fast-travel UI or remotes.

## Cloud-test (TEST place; no physics)
- Build world; assert bridge/dock/ferry/Skyroot road pins, fare constants, MustKeep paths, no Gondola*, Sparkworks FerryRequired state vs dock readiness math.
- Live drive / board / toll = Studio / Connor.

## Gate
PASS only: green CI + specs 1–13 + Art/Builder PASS + Connor fare locks + no MustKeep/T411/T412/economy regression + no gondola return + no paid fast travel. FAIL: FerryFare still 400; trucks still refused while ticket claims car ferry; town bridge charges; gondola leftovers; silent MustKeep delete; Sparkworks live without ferry path when FerryRequired cleared incorrectly.

## Lane locks from Builder/Designer (2026-10-28 ~3:54 PM America/Denver)
- Ferry deck grow **18×84** (live FerryLogic 14×22 cannot fit LoggingRig≈46.7 + HeavyHauler≈75.3). Dock aprons ≥20×16. Travel mains **32** / branch 24 / foot 8. Junction r≥32. Grade ≤12%.
- Promote MainlandDock **(920, −640)** + IslandDock **(1100, −700)** by Sparkworks harbour; move WorldLayout.FerryDock with them. TravelSec 40 stays.
- Paid lift at draft Bridge ≈(113, 80), CHANNEL_HALF 18, deck 32×56; free town/main: same deck, no TollLine/booth. Dealership door MustKeep (189.25, 100.3); do not pave Land Office.
- Sign copy (Designer): `TOLL $100` · `DEALERSHIP →` · `FERRY / LANTERN ISLE` · `LANTERN FERRY` + `FERRY $350 · every 6 min · ~40 s` · `SKYROOT ↑` · `TOWN (free bridge)`.
- FAIL if deck stays 14×22 while claiming car ferry, or Sparkworks opens before FerryService Ready.
