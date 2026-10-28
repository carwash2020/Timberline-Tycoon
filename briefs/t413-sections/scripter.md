# T413 Script — Travel (bridges, ferry, Skyroot road, junction signs)

Sources (main `a66c562`): `GameConfig.luau` TollFee=100 TollSeconds=180 FerryFare=**400** FerryIntervalSec=360; `FerryLogic.luau` / `FerryService.luau` / `FerryController.luau`; `TollLogic.luau` / `GateService.luau`; `ShopLogic.FerryClosed` + `ShopService` FerryRequired gate; `Art/ShopPlace` sets Sparkworks FerryRequired; `WorldPlanDraft` CarFerry=true LiftBridgeFee←TollFee FerryFare←GameConfig; `WorldPlan.RoadSigns` / `BiomeSignText`; `LandmarkArt.TollBridge`; tests `FerryLogic.spec` `FerryService.spec` `TollLogic.spec` `GateService.spec` `WorldPlanDraft.spec` `T412Shops.spec`. Connor locks: town/main bridge free; out-of-town important bridge $100; ferry **$350**; no paid fast travel. Vision §3 travel + LT2 $100 lift / $400 ferry lessons. Docs: WeldConstraint CFrame move keeps assembly; network ownership server-owns welded vehicles (create.roblox.com). Checked 2026-10-28 America/Denver.

## Locks
- **Fare:** `GameConfig.FerryFare` 400→**350**. All UI/NPC/tests read GameConfig (FerryLogic TalkLines/ActionText already). Flip hardcoded `$400` / `400` asserts in FerryLogic.spec, FerryService.spec, WorldPlanDraft.spec, T412Shops.spec.
- **Toll:** `GameConfig.TollFee` stays **100**. One paid Crossed strip + booth only (GateService + TollLogic). `Quote`/`Pay` already once-per-window (`already` never recharges). Southbound free. **No** GateService / TollLine on town/main free bridge Builder places.
- **Car ferry:** `WorldPlanDraft.CarFerry = true` but live FerryService **refuses** trucks (`clearVehicles`, Board→`"truck"`, TruckText). T413 inverts: Truck-tagged vehicles stay on deck, weld PrimaryPart at depart, PivotTo with boat, drop on arrive. Charge **once per rider** at depart (seated driver = one rider; do not charge the truck as a second fare). Walk-ons unchanged. Short cash → stand back on dock, uncharged.
- **Fail-closed:** docks missing → no Board / no sail (keep SetupWorld warn). Sparkworks stays closed until ferry Ready.
- **Sparkworks open:** today `ShopLogic.FerryClosed("Sparkworks")` always true + attribute FerryRequired. On successful `FerryService.Bind`, clear Ready gate (FerryClosed false when Ready, and/or clear FerryRequired). Update T412 specs that assert FerryRequired true.
- **No** StoreData / Cap / ItemCatalog price / paint / pass / ProfileSchema edits. Block wood stays. T411/T412 shop find-chains untouched except FerryRequired. No gondola ride revive (`gondolaPass` save id stays for Sky Pass quest).
- MeshId 0 greybox OK for ferry/bridges until turntables (Builder/Art).

## Modules that change
1. `GameConfig.luau` — FerryFare=350.
2. `FerryLogic.luau` — replace TruckText with allow-car copy; optional deck constants if Builder locks larger deck (live 14×22 may be tight for truck+trailer; Script Aboard/Slot follow Builder numbers). TravelSec=40 / BoardCloseSec=3 / Interval=360 keep unless Designer changes timetable.
3. `FerryService.luau` — remove refuse path; weld trucks + seated drivers; SetNetworkOwner(nil) while welded, restore on arrive; Board allows driver already on deck vehicle; Ready flag after Bind; refuse Board if not Ready.
4. `FerryController.luau` — only if client pose needs vehicle deck follow (schedule PoseAt likely enough).
5. `ShopLogic.luau` / `ShopService.luau` / `Art/ShopPlace.luau` — FerryClosed ↔ ferry Ready; stop forcing FerryRequired once docks live.
6. `GateService.luau` / `TollLogic.luau` / `WorldLayout` toll pins — retarget Crossed strip + Booth to the **one** out-of-town paid lift bridge Builder locks; ensure free town/main bridge has no strip.
7. `WorldPlanDraft.luau` — mirrors GameConfig (no hardcode); MainlandDock/IslandDock pins follow Builder if live FerryDock moves.
8. `WorldPlan.RoadSigns` / sign text — only if Designer locks new junction copy; placement is Builder.
9. GateLodge / Sky Pass — no new fare; road climb is geometry. Do not reintroduce gondola scripts.
10. Tests listed below.

## Approach
1. Change FerryFare to 350 first; green fare specs.
2. Flip car-ferry behavior + invert truck specs; add weld/arrive vehicle specs.
3. Wire ferry Ready → open Sparkworks; fail-closed if docks absent.
4. Confirm single $100 toll on paid bridge; zero toll code paths on free town/main bridge.
5. Sign copy only if Designer posts strings; Script does not invent junction text.

## Tests Script owns
1. `GameConfig.FerryFare == 350`; FerryLogic Action/Short/Paid/Talk use $350; WorldPlanDraft.FerryFare mirrors.
2. Fare taken once at depart from each rider on deck; step-off before cast-off → $0; short cash → dock + ShortText.
3. Truck on deck at depart stays welded and lands on far dock; seated driver charged once; Board no longer returns `"truck"`.
4. Board/`Step` no-op or refuse when docks unbound (fail-closed).
5. After Bind Ready: `ShopLogic.FerryClosed("Sparkworks") == false` and/or FerryRequired cleared; before Ready: buys still fail `"ferry"`.
6. Toll: Pay once opens window; second tap `already`; Crossed unpaid → push; southbound free; TollFee=100.
7. Free town/main bridge: no TollLine Crossed / no SpendCash on that span (spec against layout pins).
8. Diff gate: no StoreData/Cap/catalog/gondola-ride revive; MustKeep still bans gondola paths.
9. Extend `FerryService.spec` / `FerryLogic.spec` / `TollLogic.spec` / `GateService.spec` / `T412Shops` FerryRequired flip / `WorldPlanDraft.spec`.

## Risks
- Leaving FerryFare=400 or hardcoded $400 tests → Connor lock miss.
- Keeping truck refuse while CarFerry=true → Dealership→Isle loop broken.
- Clearing FerryRequired before docks Ready → Soft Sparkworks buys with no travel.
- Double-charging driver + truck, or client network-owning welded truck mid-crossing → desync / exploit.
- Adding a second TollLine on the free town bridge → false $100 gate.
- Growing deck without Builder clearance → overlap lint / stuck trailers.

## Out of scope
Mesh uploads / MeshId; StoreData/Cap/catalog; paid fast travel; Sky Pass redesign; T414 remakes; T415 perf; soft bay-stack; Art palette.

## Lock add (QA/Builder 2026-10-28 ~3:55 PM MT)
- FerryLogic.DeckWidth=18 DeckLength=84 (replace 14×22); Aboard/Slot/tests follow.
- WorldLayout.FerryDock → Mainland (920,−640); IslandDock (1100,−700); FerryService.Bind uses new pins.
- Specs must not assert live 14×22 or FerryDock (780,136).
