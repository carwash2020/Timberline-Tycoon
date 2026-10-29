# STATUS: read this first in a new session

Shed Blueprint: placing the ghost now costs $0 (Connor's decision, 13 Oct 2026; branch `phase-2/shed-blueprint-free-place`, `Blueprint.placeFee`). Last updated 29 October 2026. **Main is at `16cd31a` (T413, #277).** This branch is the T413 fixes (`cursor/t413-fixes`): graded shoulders and the travel art.

## T413 roads, the car ferry, and the Skyroot climb (28 October 2026)

The town bridge at (−36, 40) is free. The Dealership lift at (113, 80) is the only cash toll: $100 for 180 seconds, westbound free, unpaid crossings pushed to the west approach. The north-strip gorge and its old booth stay where they are and no longer charge. The ferry fare is $350. The deck is 18×84. Trucks and trailers ride; a seated driver is one fare, taken at cast-off. Mainland dock (920, −640), island dock (1100, −700). Sparkworks stays shut until the ferry binds. The Skyroot road runs to the GateLodge at (−40, 720), grade capped at 12%, hairpin radius 32, no road toll. Junction signs use the Designer copy. MeshId 0 greybox.

Travel haul roads on `WorldLayout.Roads` now record the drive width: mains 32 (RingRoad, HillsRoad, SnowRoad, EastLink, SouthLink, HillsCross, SkyrootRoad) and branches 24 (VolcanoRoad, DockRoad, RavineRoad, BayouRoad, MesaRoad). Gravel, the town slabs, and the tree plan stay on the old 28-stud bed (`WorldLayout.PlanWidth`). Live height flattens to `WorldLayout.DriveHalf` (16 on a main), so the outer 2 studs are level with the centreline and paint as Ground (TrailDirt `#8E6C4A`), not gravel. A declared flat keeps its own floor. Branches are already inside the 28-stud bed. The old Skyroot east polyline stays soft terrain. `TravelArt.SkyrootRoad` is the solid climb, deck width 32, `CanCollide` true. The lift arm is a StopRed bar beside the booth, the town bridge is plank boards with post rails, the ferry has a ghost truck footprint, a waterline and a low cabin, and the stone and foot spans use post and rope rails. Shots: `preview/t413/` (`lift-top`, `free-town-bridge`, `ferry-truck`, `bridges-contrast`, `travel-pins`, `eastlink-shoulder`, `ferry-cabin`). Studio checks: PHASE2_NOTES.md "T413 travel". Nothing here has been seen in Studio. Cloud has no physics.

## T412 shops placed (28 October 2026, branch `cursor/t412-shops-placed-cbeb`)

Shop pins live in `ShopPins`. `WorldPlan.Town().shops` is still the flat-town three (Tool Shed, Hearth & Home, Dealership). Sparkworks, the coat and boot kiosks, Odds and Ends, the Land Office cottage, the secret cave, and the cloud forge and market are `town.outlets`. The ground Sky Forge court is gone. KeeperSpot, TemperSpot, and the four relic sockets are on `TimberlineMap/SkyForge` at cloud Y 840. The Weigh House and the town mill did not move. Dale's door is still (189.25, 100.3); Origin 207 / 100.2 is the lot corner, not a second site.

Insulated Coat, Heat Boots, and the Lantern are not on Hazel's shelf. Nell, Soot, and Nim sell them at the kiosks and at Odds and Ends. The General Store menu lists only gear whose shop is Hearth & Home. A blasting charge at Odds, from the menu or from its box, spends `DynamitePrice` ($220) and adds a mining bomb. The kiosks and Odds have counter shelf slots, so BoxService stocks them. Sparkworks is on the harbour at (1115, −700) and signed "Ferry required"; buys there fail while that sign is on the model. SecretShop has `Sold = false` and no prompt. MeshId stays 0. Greyboxes are the REDO look until Connor says yes to a GLB. Harbour Sparkworks, the coat and boot kiosks, Odds, the secret cave and the Land Office are town floors for paint and trees. They are not store pads, so HeightAt keeps the old town Sparkworks floor.

Nothing here has been seen in Studio. Cloud tests do not walk or drive. Studio checks are in PHASE2_NOTES.md "T412 shops placed". Shots: `preview/t412/`.

Every branch section below is merged to main (some headings still say "draft PR": that is how they were written); the only open work is this branch. #135 (machine meshes), #136 (backlog
meshes) and #138 (NPCs, tutorial, goals) are all on main, and so are the Sparkworks shop in town (#144), the ButtonR2 removal
(#143) and the right-trigger grab (#151), the load and freeze fixes (#150, #153 to #158) and the four store interiors
(#159, with #160 to #162). **What Connor checks in Studio right now, and every open decision with its default, are in
`V1_STUDIO_CHECKLIST.md`** (top section and section D). Each lane's own longer checklist is in PHASE2_NOTES.md.

**Merged to main (V1):** #118 A1 economy, saves and caps; #119 nature; #120 buildings, shops and props; #121 world; #122 axes,
boxes, shelves, hover tags; #123 Sparkworks logic; #124 UI redesign; #125 mining and crafting; #126 real-mesh previews; #127
faster CI; #128 UI round 3; #129 automation; #130 Blender asset pipeline; #131 building and blueprints; #132 end game; #133
purchases; #134 end game follow-ups; #135 machine meshes; #136 backlog meshes; #137 badges and the town board; #138 NPCs,
tutorial, goals, HUD remake (Foreman Rook, the `Stage:S1` to `S8` events); #139 Bayou and Red Mesa; #140 owner UserId; #141
integration pass; #142 lightning finds open ground; #143 no ButtonR2; #144 Sparkworks shop; #145 moderation and policy; #146
GrabService spec fix; #147 launch settings; #148 and #149 hardening; #150 client module load race; #151 grab on RT; #152
first screen fix; #153 startup errors; #154 server audit (staged terrain, save prefetch); #155 client freeze; #156 meshes never
block the build; #157 client audit; #158 world first look; #159 store interiors: the kit, Tool Shed, Hearth & Home, Sparkworks and Dealership (#160 to #162 squashed in).

**Still open:** T411 (this branch) remakes the town sawmill and the Weigh House. The mill and planer economy bump is on main (`690e9e8`, #272, BonusCap 7.5). The ClientFreeze seat yield is on main (`852d247`, #274). Square Block wood is on main (`fd98f20`, #273). T409 is on main (#270). Older "only this branch" notes below are history.

## T411 town sawmill and Weigh House (27 October 2026, branch `cursor/t411-sawmill-weigh-1d06`)

The town mill is a shared working mill, not dress only. `BuildingArt.Sawmill` tags the model `Sawmill`, sets `MillId` `SawmillRickety` (no new catalog row), `OwnerId` 0, `Tunnel` `housing`, `ExposedBlade` true, and gives it an Intake, a Conveyor and an Output. The blade is visible inside IronBlack housing and stays out of the door and the walk. Any nearby player can set the cut. The setting is not saved. A shared belt is not refused for `notYours` or offline. A plot Rickety mill, built by `MachineArt`, stays a closed tunnel with `ExposedBlade` false. Wood on the slip, the deck, the carriage and the sell rack is square Block. Volume stays `SectionMetrics` Block. `ItemCatalog` prices, bonuses and Cap are the #272 values and are not edited here.

The cabin door is 4 by 7 or wider, the walk in front is at least 6, and the east slip, carriage, west outfeed and both aprons have no stray solid. The Weigh House is barn red with a slate roof, a scale tower whose dial is about 6 studs and whose top is at least 18, and a truck bay at least 14 wide with rails only at the edges. Sell pay-once is unchanged. The mill and the pad stay one cluster; Dealership and Tool Shed did not move.

The new GLBs are `assets/meshes/buildings/Sawmill/Sawmill.glb` and `assets/meshes/buildings/WeighHouse/WeighHouse.glb`. `TownModels` mesh ids, piece sizes and the 9944 triangle pin are unchanged, so Studio still shows the previously uploaded mill until Connor re-uploads. Live collision stays the part twin (no Hull dress). Shots: `preview/t411/`. Studio checks: PHASE2_NOTES.md "T411 town sawmill and Weigh House". Nothing here has been seen in Studio. Cloud has no physics.

## Economy machine bump (27 October 2026, branch `cursor/economy-machine-bump-a1a4`, on main as #272)

Connor's cash ladder (11:40 MT table, BonusCap 7.5 at 11:57 MT). Mill `plankBonus` is 1.00 / 1.35 / 1.70 / 2.15 / 2.50 and `maxWidth` is 2.0 / 2.2 / 2.4 / 2.6 / 2.6. Planer `boardBonus` is 1.50 / 2.00 / 2.50 / 3.00. `SellLogic.BonusCap` is 7.5 (was 3), so Millmaster 200 Long × Industrial (2.50 × 3.00) pays 7.5 and Millmaster 200 × Steam (2.15 × 2.50) pays 5.375. Prices, maxLength, StoreData, paint, passes and ProfileSchema are unchanged. Fit is still `Accepts` against `maxWidth × WoodUnit` (1.6): a Rickety takes an oak Block at about 2.0 studs (limit 3.2). The v2 model is now 68 s / 8.0 min / 15.1 min / 75.5 min / 12.1 h. Connor locked the CI bands the same day (~3:03 PM MT): Steel 300–510 s, Cobalt 2700–4800 s, full plot 10–14 h (36000–50400 s), Ironwood ideal $40,000–$47,000/h. E1 (0–180 s), the first $1k (780–1200 s) and Bog Cypress ($9,000–$11,000/h) stayed. Measured times did not move: Steel 482 s, Cobalt 4527 s, full plot 12.1 h, Ironwood $43,136/h, all inside. Nothing here has been seen in Studio. Studio checks: PHASE2_NOTES.md "Economy machine bump".

## Client freeze: seat the forest in slices (27 October 2026, branch `cursor/clientfreeze-seat-yield-ee88`, on main as #274)

`WorldPlan.Trees` seats each extra batch on the valley as it is handed over. The town's first batch also seats every country and forest tree already planned, one `LiveHeightAt` per trunk, and that loop did not yield. On this machine that was about 62 ms (54 town trunks plus 219 already planned). The #273 CI runner measured the same plan at 100.6 ms, over ClientFreeze's 100 ms limit. The pause count was unchanged from the green parent (76547), and `WorldPlan` / `TreeFill` did not change in #273. Yielding every 8 trunks, matching the final seating pass, splits that stretch. The Y values do not change. Square Block wood stays. ItemCatalog caps, bonuses and prices stay. Studio checks: PHASE2_NOTES.md "Client freeze: seat the forest in slices".

## T410-fix square Block wood (27 October 2026, branch `cursor/t410-square-block-wood-ee88`)

This overrides the round path in #271. Standing trunks, logs and stumps are `PartType.Block`, size `(t, L, t)`, length on Y. A priced volume is `t² × L`. `GameConfig.CutWindow` is 1.0 (half band ±0.5). The notch is the server ray on the hit face; the fall is toward that face. A cut under 2.5 studs leaves no stump. A cut at or above 2.5 leaves one square Block stump (bark sides, core cap), not a frustum mesh. Crown meshes still dress the tree and do not replace the section. Uploaded section meshes are not applied. Oak and birch colours, thickness and prices are unchanged. Planks stay boards. Decay timers are unchanged (90 / 170 / 180 / 190, sink 0.3).

`FallLogic.LiveFall` and `CargoLock.LiveDrive` stay `"playtest"`. Cloud has no physics, so the live tumble and a CargoLock drive are Studio checks. `SectionMetrics.CargoPose` returns the part's own CFrame and Size and a nil shape, so the bed uses the box. A 45° roll of that box can change the share; the log is not a cylinder.

MustKeep, `WorldLayout.WorldHalf` (1350), the gate lodge door `(-48, 41.21, 730.05)`, T408 centres and `StoreData.CreatorIds` are untouched. StoreData, pass gates, `plankBonus` / `boardBonus`, mill `maxWidth`, the T411 town mill and plot mill/planer silhouettes are untouched. Near the spawn (70 studs) the grove is still oak only. Shots: `preview/t410-fix/`. Studio checks: PHASE2_NOTES.md "T410 square Block wood". Nothing here has been seen in Studio.

## T410 round bark logs (27 October 2026, branch `cursor/t410-round-bark-logs-bc65`, superseded by T410-fix)

Starter trees cut where the axe hits and fall toward the notch (`StumpLogic.FallDirection`). Every wood section is a round log: a Cylinder along local X, or a MeshPart once its mesh loads. Gameplay, prices and saves stay on the logical Y-up frame `(side, length, side)` in `SectionMetrics`. A priced volume is still `side² × length`. No WoodData size or price changed. Planks stay Blocks. The stump is the existing T420 kit: no stump under `MinHeight` 2.5, and a cut at or above that leaves one stump. Cut faces are the core colour on `Enum.Material.Wood` (lumenwood's `Core` itself stays Neon). Oak and birch bark stay Wood, not SmoothPlastic.

`FallLogic.LiveFall` and `CargoLock.LiveDrive` are `"playtest"`. Cloud cannot run the fall or a truck drive. The pure specs cover the notch ray, the Block ban, volume, the stump, MeshId (no part fallback), the 20k triangle cap, and a round log's bed share when it rolls. A live oak or birch section stays a Y-up MeshPart `(t, L, t)`. `SectionMetrics.CargoPose` hands the bed a cylinder of size `(L, d, d)` with `d = 2 * RoundRadius(t)`, so the lock uses that diameter and a roll does not shrink its share. A resting log is kinematic: it sits on the ground or the river bed and does not sink (`FallLogic.WaterPolicy = "drag"`).

MustKeep, `WorldLayout.WorldHalf` (1350), the gate lodge door, T408 centres and `StoreData.CreatorIds` are untouched. Near the spawn (70 studs) the grove is still oak only. The part-built before and after shots are `preview/t410/before` and `preview/t410/after`. Studio checks: PHASE2_NOTES.md "T410 round bark logs". Nothing here has been seen in Studio.

## T409 living ground (27 October 2026, branch `cursor/t409-terrain-86a7`)

The nine T408 regions are the ground you drive. `TerrainGen.HeightAt` is that one landform (`ValleyGround`); the classic ground is still there for the first trees and is unchanged. WorldHalf is 1350, so Frostpeak's north rim and Lantern Isle sit inside the square. Blend belts are 48 studs on a trunk and 32 on a foot road (`gateClear` 30). Roadside stamps (signs, scatter, odd wood lots under the wood-part cap) stream in and do not collide. The gate lodge is at (−40, 720), facing north, on `HeightAt`. Its door moved with it: `tests/mustkeep.json` is now (−48.00, 41.21, 730.05). Country roads stay terrain gravel (`Asphalt` #A8A49C). No cliff meshes were uploaded, so the cliffs are terrain, not parts. Cloud isles, the gondola, shops, fares and saves are untouched.

The live height fingerprint was re-sampled twice. First sample, from the pre-valley ground: was sum 68494.704463124, wsum 2.750488850, sq 4785571.335868491. Second sample, after the mine's rock roof, the volcano's cliff wall, the ferry shore and the shelf ease: sum 68286.279255775, wsum 163.574182878, sq 4493789.845065589 (the in-between valley sample was sum 68174.730151801, wsum 161.629373361, sq 4489556.241387829). `lo` and `hi` and the classic fingerprint did not move. The tree plan kept all 1,052 trees at the same X and Z. The checksum moved 10199207 → 12618450 → 254093984 because each tree's Y is the valley height. The east ferry dock sits on the old shore again. Six meadow trunks close squares the valley made plantable; six wild trees were relocated to pay for them. The three ground cameras are in `preview/t409/after` (`t409-ground` 1 to 3), beside the same cameras on main. Nothing here has been seen in Studio. Cloud tests do not run physics. Studio checks: PHASE2_NOTES.md "T409 living ground".

## T408 map plan (built by T409)

Connor approved the nine-region picture with notes. T409 (above) is that picture as the live ground. The draft note below is how it was approved: `TerrainGen`, `WorldPlan` and `MapBuilder` do not read it. Skyroot Highlands is the ground summit at (−60, 800), radius 170. The gate lodge is (−40, 720), facing north. Cloud isles stay separate notes. Frostpeak is (−340, 1000), radius 160, layer ground, clear of Skyroot. Its north rim passes WorldHalf 1000, the same class as Lantern Isle. `OverlapHits()` is empty. Corridors carry roadside markers and 48-stud blend belts (32 on a foot road) for T409. The picture is `previews/t408/overview.png`. Removals stay cards, not deletions. The cabin card does not name the removed ride script, so the source scan from that removal stays clean. The ring road and the truck tunnel stay a T409 redo. Studio has nothing new to walk.

**Stages:** with #138 on main the `Stage:S1` to `S8` keys are written (`MilestoneService.CheckStages`); the stage (`StageOf`)
still also comes from the best axe and gear. S8 (Master Timber) is set only by its key: deriving it from a full plot is awaiting
Connor (it would raise cash packs about 25%).

## T407 remove the gondola (26 October 2026, branch `cursor/remove-gondola-823b`)

Travel is roads, bridges, the ferry and trucks. The ride, the stations, the cables, the turnstile and the Cloud Chute hoppers are gone. The Sky Pass stays: Gus still signs the charter, the save keys `gondolaPass` and `skyPass` still migrate together, and the gear id is still `GondolaPass`. Player-facing copy says Sky Pass. The gate lodge (28×20, peak 14, a brass lamp past 80) stands on the Snow Road's north end, about (−30, 790), front toward the road. The bar blocks the lane until the pass; leaving the summit side does not need it. There is no ride fee. The floating isles stay at (680, 280), y 650, and are not reachable until a later map pass. A Sky Bin on a plot still sells. Hoppers are not built; T413 owns whatever replaces the chute. Nothing here has been seen in Studio.

**Studio:** walk the old station pad (north yard, about −40, 150): no station, no cable, no turnstile, no chute hopper, a Skyroot sign or bare ground. Drive north to the snow-road end and find the lodge near (−30, 790). The sign reads Sky Pass. The bar blocks without the pass. Gus's charter still grants it; the bar's edge goes green and you can pass. You can leave the summit side without the pass and you are not stranded. No ride prompt and no $250 charge. A Sky Bin on a plot still sells. Shops, the ferry and the sell pad are unchanged. The isles are still up there and no ride reaches them.

**Rules that did not change:** the five formerly off-sale products now have their ids (T387, 20 Oct 2026; no Robux price in code), badge ids stay 0 until Connor
pastes them, no trading or gifting, ButtonR2 is named once in the source (`GrabLogic.PadGrabKey`, the empty-hand grab, read and
never bound; `NoButtonR2.spec`), no Robux price in code.

## MEGA batch T380 to T401 (20 October 2026)

All 22 jobs are on main (#222 to #243; #244 fixes a ClientFreeze stretch that T397 introduced). Their Studio checks and the decisions they need are in the last section of PHASE2_NOTES.md ("MEGA batch T380 to T401"). No screenshots were possible, so everything there is untested in Studio.

## T420 art follow-ups (23 October 2026, branch `phase-2/t420-art-followups`, one PR)

The Art Director's HOLD items on #259, #260 and #261. (1) The PLOT DISTRICT sign is built from kit parts (PlankHoney planks on TimberBrown posts, Ink #3C2814 text on a SignCream #F3E7C9 panel on the board face; `BuildingArt.Signpost(..., panel)`, `Palette.Ink`); it no longer takes the Signpost mesh, whose board stood low on the ground away from the text. (2) The picker card corner tab is Blueprint blue #2F5D8A (`UITheme.Colors.BlueprintTab`). Wire is now one "Wire Box (160 studs)" at $100 (Connor, 23 Oct): a run is up to 160 studs, only the studs placed come out of the box, and runs join end to end (a run may end in the open and another start from or end on that end; a chain carries power like one wire). The $2/stud placeholder is gone and the box price shows on the buy button. (3) The wire spool is the uploaded model 139086937634351 (five MeshParts, `WireArt.Config`), loaded once at boot by `ServerScriptService/WireSpoolMeshes` (the second InsertService file, after `StumpMeshes`); if it fails to load the spool is not shown (no part-built spool exists). (4) Stump renders re-shot: a frustum stand-in, since the R13/R22 meshes cannot be opened here. (5) Two new CI checks: `Shared/Lint/StandIn` (no visible part-built piece in registered meshed art) and `tools/render_touched.py` (no render touched without a change). Nothing seen in Studio; Studio checks: PHASE2_NOTES.md "T420 art follow-ups".

## T406 playtest fixes (22 October 2026, branch `phase-2/t406-playtest-fixes`)

Connor's playtest notes, nine fixes, each with a spec. Studio was not available: nothing below has been seen in the game. (1) Drag: a held log starts 12 studs out and the wheel, D-pad up/down or the phone's +/- move it 6 to 22; the server lets go past 24 and judges the release velocity (clamp 30, refuse over 60 or without network ownership). (2) Footpaths: the eight T402 paths are pinned and a part the drawn terrain would bury is raised onto it (`World/GroundLift`); path rounds stand on the ground. (3) Grey strips: the per-stall grey curb block and the Graphite plot's grey rail are gone. (4) The "put your axe away" line shows 3.4 s after a try, then goes (`AxeHintTimer`). (5) `GameConfig.TownMeshes` is true again (it was the only reason the log said OFF). (6) Asset 203785492 is not in the repo; a spec now bans it and checks every id's expected type. (7) The gamepad selection ring was centred with an AnchorPoint the engine ignores; it is now placed from the corner. (8) The plot picker has no timeout and never assigns a plot. (9) A meshed axe's part-built Handle is invisible (it z-fought the mesh haft). Details, causes and Studio checks: PHASE2_NOTES.md "T406 playtest fixes".

## T402 good-looking ground (21 October 2026, branch `phase-2/t402-ground`)

The town's roads, curbs, footpaths, the lot's pavement and edge, and every plot pad's lawn edge are now parts (`Shared/World/TownGround`, built by `Art/TownGroundArt`, 145 parts: 73 in the town zone, 72 plot edges, budget 150). Country roads stay terrain. Terrain inside `WorldLayout.TownZone` never writes Asphalt, Rock, Slate or LeafyGrass (all read Grass); under Grass the voxels are Ground; the surface band is 3 voxels. `MaterialSetup` is the only `SetMaterialColor` writer (full table in its header, Mud and Rock kept as they were, no Pavement row). The terrain build writes 16-column blocks and yields every 4 ms; the town zone's blocks go first; each step's time is logged (`[Perf] terrain step ...`). Studio checks and the numbers: PHASE2_NOTES.md "T402 good-looking ground". Nothing has been seen in Studio.

## T404 roof clearance (21 October 2026, branch `phase-2/t404-roof-clearance`)

Second porch roofs no longer clip into building fronts. With the town mesh on, the Tool Shed and Hearth & Home skip the facade's striped awning and door frame (the mesh brings its own); the parts-only versions keep them. A mesh that lands after the facade is built (the world does not wait for meshes) no longer leaves the awning posts as invisible solids, and it no longer removes the door and lanterns that were added while it loaded. Every awning is now 15 degrees (the Dealership canopy 16), stands wholly out of the wall (0.005 clear), and the main eaves stand 1.05 past every wall at any store Scale (the Dealership's were 0.5 and 0.1; the code-built Sawmill's shed was 2.6 at the sides). `tests/RoofClearance.spec.luau` pins it for the four shops and the Sawmill at Scale 1.5 and 2.25; `tools/blender/check.py` has a narrow porch-through-the-wall check. The Sawmill GLB is fine (Connor): its clipping came from the code-built parts, now fixed; no mesh change is planned. Studio checks and the changed numbers: PHASE2_NOTES.md "T404 roof clearance". Nothing has been seen in Studio.

## #201 to #213 and open work
#201 What's New fixes, grey box backing, held-tool teleport; #202 console safe area and text sizes; #203 axe head placement, gear meshes, Xbox chop diagnostics; #204 remaining gear meshes, pending-mesh swap, real layout specs; #205 event and cave prop mesh ids; #206 worn gear meshes, rope ladder tiles, scroll V2; #207 first badge ids; #208 build menu; #209 chop feel; #210 wood effects on buildings; #211 Cherry, Willow, Amber, Garnet, added trees and teasers. Open draft: #213 (custom sound ids).
Sound ids: #213 wires the custom ids for TreeCreak, Engine, CricketsNight, WindHowl, LavaRumble, Wings, Quack, StormCrackle and LogThud. Chop, ChopFinal, TreeFall and LogLoad keep their stand-ins until Connor confirms the uploads are Approved.

## Overlap fix (branch `phase-2/overlap-fix`, 19 October 2026, draft)
The 13 overlap hits are fixed by small post-plan moves (four boulders, the Ruined Cabin, one Reach tree, two Mesa ironwoods, two north-strip clumps); `tools/overlap_report` prints 0 hits and `Overlap.spec` names no exemption. Details: PHASE2_NOTES.md "Overlap fix".

## Spread supply (branch `phase-2/spread-supply`, 18 October 2026, draft)
Nine supply trees moved inside their own zone (`TreeSpreadData.Moved`, `tools/spread_supply`); the zones are nearly full, so 40 could not be placed. `ClientFreeze` and `TreeFill` pins re-pinned with the reason. Details: PHASE2_NOTES.md "Spread supply".

## World-spread (branch `phase-2/world-spread-thin`, 18 October 2026, draft)
Trees spread over the whole map without changing `WorldPlan.Trees()` (so `ClientFreeze` is untouched): `TreeSpread` (wood mix per zone, thinning of 20 movable trees, the refill rows), `NearGrove` (oak clumps by the spawn), `Clearance` and `OverlapCheck` (the one overlap pass). Tools: `lune run tools/tree_report` (`--exempt`, `--skip`), `lune run tools/overlap_report`. Details and the named exceptions: PHASE2_NOTES.md "World-spread".

## Playtest fixes (t351, branch `phase-2/playtest-fixes`, 17 October 2026, draft)
Three phone-emulator bugs, each with a spec that failed on main. (1) Rook's job board closed the same frame it opened (`DailyUI.refresh` hid the panel); (2) the carving prompts had a 0.3 s hold, which a tap never completes; (3) a tree whose meshes loaded after it registered kept stale section parts, so chops on its new MeshPart sections were "unknown". Chop rejects `unknown`, `gone` and `bad` are now counted in the `[Chop]` line. Details and Studio checks: PHASE2_NOTES.md "Playtest fixes (t351)". Unconfirmed: that bug 3 is the whole story of the brown trees in the playtest (reproduced only in a simulated late swap).

## World additions (branch `phase-2/world-t323`, 16 October 2026, draft)
Cherry and Willow woods with meshes, Amber and Garnet ores (Mix and mining pins updated), 100 added trees and the teasers that pass the stage rule (outside `BiomeData.trees`, so the economy supply caps do not move). Deviations and Studio checks: PHASE2_NOTES.md "World additions".

## Wood effects on buildings (branch `phase-2/wood-effects`, 16 October 2026, draft)
Frost, ember, gloam and lumen doors take an accent colour; ember, gloam and lantern doors glow at night; ember and gloam buildings get a few sparks (capped 8 high, 4 medium, 0 low). Cosmetic and client-side; no price, save or remote change. Details and Studio checks: PHASE2_NOTES.md "Wood effects on buildings".

## Chop feel pass (branch `phase-2/chop-feel-t325`, 16 October 2026, draft)
Chips and thunk at the impact frame (predicted, then taken by the server's own Cut or handed back), thunk pitch and a canopy rock as a cut nears its end, a cut guide ring with per-side value on felled logs, aim cone for touch and gamepad, Small-motor rumble (unverified on a real pad), per-device landing-shake caps, `TreeArt.FaceLook` (WoodPlanks, never Neon) for stump faces and notches, Chop reject telemetry, `tools/chop_feel`. No new remote, no economy change. The custom sound ids are wired (TreeCreak, Engine, crickets, wind, lava, wings, quack, storm crackle, LogThud); Chop, ChopFinal, TreeFall and LogLoad keep their stand-ins until approved (PHASE2_NOTES.md "Sounds to pick"). Details and Studio checks: PHASE2_NOTES.md "Chop feel pass".
## Launch performance (branch `phase-2/launch-perf`, 14 October 2026)

Connor's Studio log: playable at +4.6 s but heavy work ran until +11.9 s (the points-of-interest plan one 5.07 s step, 1,205 trees over
8.1 s, the terrain write 9.2 s, the client's filler plan 4.8 s, client Starts about 1.4 s each, 696 mesh swap-ins in bursts). The build agent cannot
run Studio: nothing below is measured there. **What changed** (full list and Studio checks: PHASE2_NOTES.md "Launch performance"):
one shared per-frame budget for the server's background work (`Shared/FrameBudget`; 30 ms while nobody plays, 10 ms in all once a player
can play, where the forest, terrain and deferred queue each took 12 ms before); the POI plan and every other `(plan)` step run on the
step's slice (`WorldPlan.PlanPointsOfInterest(pause)`, byte-identical output: `PoiPlanSplit.spec`); the forest is planted nearest the
players first (`Shared/NearFirst`, re-sorted as they move) while the planner is still working; the later terrain blocks go to the players
first; the client's deferrable Starts run after "can play" through `Shared/ClientBoot` (start on first use as a fallback); ForestFiller
waits for them and adapts to slow frames; mesh swap-ins are capped per frame and nearest-first (`MeshKit.Pump`); the loading card waits
(at most 6 s) for the trees round the spawn (`NearRingBuilt`); `[Perf]` lines on the server and the client (`Shared/PerfProbe`).
**Open:** Connor reads the `[Perf]` lines from one cold-server join and sends them back; the budgets (10 ms, 6 swaps, 2 Starts a frame,
6 s card wait) are guesses until then.
## Axe heads were backwards (branch `phase-2/axe-grip-forward`, 14 October 2026)
Connor: every axe is held with the blade toward the player and the head the wrong way round. Cause: Roblox's import turns the Blender axe meshes a half turn about Y from their GLBs (the NPC meshes do the same, `TownModels.NpcMeshYaw`), so the mesh's cutting edge landed on +Z while the haft, the Lux points, the swing and the preview all assume the edge is at -Z. The grip was right all along (the Handle's -Z is the blade; the grip frame's -Z is the look vector with the arm raised), so `AxeArt.Grip` is unchanged. Fix, in one place: `AxeModels.MeshYaw` (a half turn) is applied to the handle, head and glow mesh in `AxeArt.applyAxeNow`; the held tool, dropped axe, shop rack, box display and temper effects all come from `AxeArt.Build`, so they follow. `tools/preview/export.luau` turns the `axes/` GLBs the same half turn so renders show the engine (`PREVIEW_AXE_TURN=0` for raw GLBs). New `tests/AxeGrip.spec` (every axe incl. Lux and the Maul, part-built and meshed: edge forward and head up in the hand frame, one shared grip). Renders: `previews/axe-grip/` (`contact-before.png`, `contact-after.png`, close-ups in `before-single/` and `after-single/`; scene `tools/preview/scenes/axe-grip.luau`). The Hermit's Maul is part-built and was never affected.
Studio checks (not run, Studio cannot be run from the build environment): 1. Equip each axe incl. the Lux Axe: in third person the handle is in the hand, the head is on top, the cutting edge points away from you at the tree; the same in first person. 2. Swing at a tree: the edge goes into the trunk, and the Lux glow arc and trail are at the edge. 3. Hotbar icon and shop rack/box display: the blade faces the way it did in the renders. 4. Drop an axe (Q): it lies on its side, head intact. If the blade is still backward, set `AxeModels.MeshYaw = 0`: the import turn assumption was wrong for the axes.
## What's New centred, no scrim (branch `phase-2/whats-new-centre`, 14 October 2026)

The grey box was NewsUI's full-screen Scrim button (removed; the card is alone in its ScreenGui) and the short-screen placement that moved the card off centre (now always centred). Spec in GreyBox.spec; previews are computed diagrams in `previews/whats-new/`. Studio checks: PHASE2_NOTES.md "What's New centred". Max Players = 12 is set by Connor in Game Settings (LAUNCH.md Studio setup; PlaceCheck points to it).

## Grey box after the join (branch `phase-2/grey-box-after-load`, 13 October 2026)

Connor on Xbox: once the game loaded, a grey veil lay over the screen.
Cause found in `NewsUI`: its full-screen dim (`Scrim`, PanelAlt at 45%) was
built visible inside an always-enabled ScreenGui (DisplayOrder 16, over the
HUD), with only the card hidden. It now starts hidden and shows and hides
with the card. Also: a one-time failsafe 4 s after the hand-over in
`LoadingScreen` (destroys a leftover card, warns naming it) and in the HUD's
own loading card; `UITheme.HiddenSelection` on the Badges list (a
panel-sized selection group); the plot-claim fade survives a failing hide.
`tests/GreyBox.spec` builds the overlays and fails on any visible, big,
translucent object. Needs Connor on Xbox: see the PR's checks.
## Save load kick, error 267 (branch `phase-2/save-load-kick-fix`, 13 October 2026)

A failed save load no longer kicks at once: ProfileService retries (3 tries, 2 for Migrate errors, only when no session
was left and nothing written), the loading card says so, and the kick message and server Output carry a reason code
(`start`, `lock`, `contended`, `migrate`, `error`, `closing`) and the seconds waited. Root cause not yet confirmed: it
needs Connor's server Output lines `[ProfileService] ... load attempt` / `FAILED (reason=...)`. Details and Studio checks:
PHASE2_NOTES.md "Save load kick".

## Store item models (branch `phase-2/store-item-models`, 12 October 2026)

Connor's item 2: the ten store GLBs (`assets/glb/store-items/`, from `phase-2/v1-store-items`) are in the repo and wired, one model
slot per item, with **no Roblox mesh id yet** (he uploads them later). Nothing about prices, what is on sale, buying or the
shelves changed while the ids are unset: every item keeps its part-built look and nothing errors.

- **One slot per item (`Shared/StoreModelSlots`, pure data).** The same slot draws the item in the shop box (and so the carried
  box), on the plot and as the placement ghost. Mine: Barrel, Crate, Glow Wire, Sky Bin (new GLBs), RobuxCoins (the Robux box),
  Parcel (the fallback), and the already-uploaded InsulatedCoat, HeatBoots, FeatherfallCloak (`BacklogModels` ids) and the lamp
  post (`ItemMeshData` ids). **Flashlight, Lantern, WoodSign and ShedBlueprint are the Hearth & Home lane's (#183): no slot here**
  (their GLBs are in the folder and listed in ASSETS.md as "wired by the Hearth and Home lane"; they can add rows to the same module).
- **Fallback rule, in one place.** `StoreModelSlots.Resolve(itemId, kind)` = the item's slot, else the Parcel (and says which).
  `ItemModel` uses it for an item with no model of its own (today none of the shop items is one; a made-up gear id shows it). The
  last step is the part-built look: a slot with no id, a mesh that is still loading and a mesh that failed all keep it.
- **Engine side (`Art/StoreModelArt`).** `Build` makes the slot's MeshParts (`MeshKit.Create`, which never yields) standing on a
  frame; `Dress` runs it inside `MeshKit.Attempt`, so a mesh that lands later swaps in and an unset or failed one changes nothing.
  Wired: `BoxArt` (box contents), `BlueprintModels.Build` (placed Barrel, Crate, Glow Wire and their ghosts), `MachineArt.BuildSkyBin`
  (the bin; the flume, cloud and the labelled collider stay), `RobuxBoxArt` (a coin pile on the mesh crate's lid, or on the floor of
  the part-built open crate). `LogicItems`' silent Glow Wire fallback now says "has a model slot with no Roblox mesh id yet".
- **Sizes.** The model is scaled uniformly to its slot's `fit`, the item's part-built size (Barrel 1.75 x 2.2, Crate 2, Glow Wire
  4 x 2 footprint, Sky Bin 4, parcel 1.4). With an id set the BOX is sized for the model (`ItemModel` extent), so the Glow Wire's
  spool is not shrunk to the 0.3 stud bar's box; with no id the boxes are exactly what they were. The numbers (GLB size, fit, yaw,
  scale) are the MODEL_SLOTS table in `ASSETS.md`, generated from the data and checked against each GLB by the spec.
- **Scenery unchanged.** The town's Crate and Barrel props (`BuildingArt` PROPS, `TownMeshes`, the shops' stock corners) stay
  part-built / on their old uploaded meshes: the new store models are the shop and plot items, not the scenery.
- **Lamp post.** The store's lamp is `assets/meshes/items/LampPost` (1.25 x 8.4, the plot item ItemMeshData already places),
  not `environment/LampPost` (the 10.6 stud street lamp with its arm, town scenery). Only the box display is new for it.
- **Gear is worn now (16 October 2026).** The store boxes still show the old BacklogModels coat, boots and cloak (preloaded:
  `MeshManifest` group "store", 5 ids). The character wears the uploaded `Art/WornModels` meshes, visual only, no Tool
  (`Art/GearWear`, started by `GearWearService` on spawn and when `OwnedGear` changes; R15 only): the coat body and both sleeves,
  the heat boots with their glow, the wader boots, the Featherfall Cloak with its glow, and a belt (`GearBelt`, or plain Parts
  when its id is 0) carrying the Lantern and the Flashlight from their store slots (moved 0.35 back under the cloak; the night
  light of `BiomeService` sits on the worn lantern mesh). The hardhat is dressed with `HardhatWorn` (`MiningService.wearHat`
  keeps its `HeadWeld`; `GearWear.DressHardhat`), the rope ladder is three `RopeLadderSeg` tiles and a `RopeLadderTop`
  (`MiningArt.RopeLadder`, `Length` 12, rails kept as invisible proxies) and the blueprint scroll is the V2 roll with a tinted
  seal (`BlueprintArt`, scale 0.625; `BlueprintArt.SealTint = false` keeps the wax ball and tail instead). Every piece has a
  white `Color` (vertex colours carry the look, no texture). An id of 0 falls back to what the game showed before. The 14
  meshes are preloaded (`MeshManifest` group "worn"; `BuildBudget` pin 696 to 710). Specs: `WornModels`, `GearWear`, `WornDress`.
- **Previews.** `tools/preview/export.luau` registers every slot's GLB (a made-up id for an unset piece, `Slots.PreviewIds`), so
  renders show the real models; `PREVIEW_STORE_GLBS=0` shows the part-built look. Scenes `store-item-models`,
  `store-item-models-placed`, `store-models-raw`. Renders (37 PNGs, `previews/store-item-models/`): `contact-sheet.png`,
  `table-1920x1080.png`, `phone-glowwire-667x375.png`, `<item>-display.png` and `-display-3q.png` for barrel, crate, glowwire, skybin,
  insulatedcoat, heatboots, featherfallcloak, lamppost, `parcel-fallback`, `robux-box` (mesh crate, coins on the lid) and
  `robux-box-partbuilt` (open crate, coins on the heap), `<item>-placed.png` and `-placed-3q.png` (part build, model, ghost) for
  barrel, crate, glowwire, skybin, `placed-all.png`, and the shop entrances `toolshed-`, `sparkworks-`, `hearth-entrance.png`.
  Made with `python3 tools/preview/backlog_manifest.py` then `PREVIEW_MESHES=preview/backlog-meshes.json bash tools/preview/shoot.sh
  store-item-models` (and `-placed`). In Lune the Robux crate's Glow and Badge pieces are put at their GLB places by the scene (Studio
  keeps them by the mesh pivot).
- **What only Studio can tell** (nothing here was seen in Studio): that an uploaded GLB loads and faces the way the previews show
  (the GLBs' front is -Z; a half turn is `yaw` in the slot row); that the textured GLBs (Barrel, Crate, Glow Wire have a wood
  texture) keep their wood through a plain mesh id (see Awaiting Connor); the Sky Bin's "SKY BIN" and log-count labels over the
  mesh bin; the Glow Wire's on/off look (its mesh glows always; the lamp's light still switches).
- **How Connor switches a model on** (Windows, one item at a time; the PR body has the same steps): in Studio open the place, View
  > Asset Manager > Bulk Import, pick the item's GLB (`assets/glb/store-items/<Name>.glb`), Import; click the new MeshPart in the
  Explorer, in Properties copy the number inside `MeshId` (`rbxassetid://123` gives 123; NOT the model's id from Creator Hub); open
  `src/ReplicatedStorage/Shared/StoreModelSlots.luau`, find the row with that `id`, and replace the `0` in `meshId = 0` with the number.
  Nothing else changes. The ids are checked by `lune run tools/assets` (ASSETS.md) the same as every other mesh.
## Dealership lot tier strips are paint (branch `phase-2/lot-tier-strips`)

The coloured strips on the dealership's 8 plinths (the tier colour that matches each T1 to T5 / T1 to T3 flag) looked like loose slabs: the top stripe was a 0.12-thick bar inset from the corners and the aisle band a bar floating on the face with gaps. In `Art/DealershipLot` both are now 0.05-thick skins (`PaintThickness`): the `PlinthStripe` lies flush on the plinth's top along the aisle edge, full width corner to corner; the `PlinthBand` is the aisle face's own outer skin, top edge on the plinth's top edge, outer face the bay's edge (the slab is 0.05 shallower there, so no face is coplanar and nothing leaves the bay). CanCollide, CanTouch, CanQuery and CastShadow are all false; colours, prices, tiers and lot layout are unchanged. New spec `DealershipLotStrips.spec` checks every plinth (8): flush within 0.1 (actually 0.001), thin, inside the bay footprint, corner to corner, no collide or shadow, one tier colour for stripe, band and flag. Two existing specs were adjusted for the design move, not weakened: `DealershipLot.spec` measures the aisle from the bay edges (the slab now stops 0.05 short, the band fills it) and `StoreInterior.Dealership.spec` finds the stripe with a 1e-3 tolerance. Scene `lot-strips` (new); renders in `previews/lot-strips/before-*.png` and `after-*.png` (8 views: lot from above, both rows low along the aisle, corners, seam, edge). The grass-green/blue pads the boxes stand on (`BoxBlock`, accent colour) are the vehicle box pedestals, not tier strips, and are untouched. Not seen in Studio.

## Robux store icons and the Pickup's wheels (branch `phase-2/robux-icons-pickup-wheels`, 12 October 2026)

- **Six store icons set** (`StoreData` `image`, Connor's IMAGE uploads, user 5682024709): 2x Cash 129566569237407, Lux Axe
  80267879981455, Small Cash Pack ($1,000 product 3716312861) 95950318286949, Large Cash Pack ($10,000 product 3716312899)
  102370875631166, 2x Wood (product 3717310556) 83265240736148, Instant Delivery (product 3717310577) 96661273504040. They show
  through `StoreArt.ImageFor` as before. The three older ids (91282142796474, 79037897236948, 71028498113750) were on Tow
  Service, Timber Classic and Paint Shop, none of the six, so they stay. The $1,000 / $10,000 game passes are untouched. No
  price, id, sale flag or badge changed: 2x Wood and Instant Delivery keep product id 0, so they stay "Coming soon" cards (they
  were never hidden: `offSale = "soon"`) and nothing can buy them. **Not verified**: the sandbox cannot reach Roblox, so nobody
  has seen that each id shows the right picture or has cleared moderation. `scripts/check-store-icons.ps1` (Windows PowerShell
  5.1, read-only) asks Roblox's thumbnail service on Connor's machine and writes `STORE-ICONS-CHECK.md`. `tests/StoreIcons.spec`
  pins the ids, no duplicates, well-formed ids, hidden rows stay unbuyable and the script lists all six. `ASSETS.md` lists each
  new id as "image id, not checked on Roblox from the sandbox" (`tools/assetscan` now names the row).
- **Pickup wheels.** `Pickup.glb` (like every truck GLB) holds ONE unplaced Wheel piece at its origin, not four placed wheels;
  the game stands four copies at the truck's wheel positions (`VehicleMeshes` swaps each part-built wheel for the mesh), so the
  Pickup, in game and in the dealership copy, has always had four mesh wheels (centres x +-4.7125, y 1.7545, z -9.685 and
  7.085, radius 1.7545, width 1.373; the Body mesh's arches are centred at z -9.75 and 7.0, flare top 3.97 over the tyre top
  3.509). What looked wheel-less: the wheel mesh shows its rim and hub on its +X face only and every wheel was placed the same
  way, so the Pickup's whole left (-X) side showed flat black tyre backs. The Pickup's left wheels are now turned half way
  round about Y (`VehicleModels` `mirrorLeft`, `VehicleMeshes.swapWheel`; **off for a day after the 13 Oct GLB pass below, then on for every vehicle (next bullet): Roblox still holds the one-sided wheel**); `TruckArt.Rig` keeps the Axle joint on the unturned
  frame (turn in C1), so spin and steering are unchanged. Look only: no physics, hitbox, price or stat. Other trucks show the
  same flat left side and are **not** changed (Awaiting Connor). `tests/PickupWheels.spec` pins all of it, and that no other
  truck changed. Renders: `previews/pickup-wheels/`; UI and board: `previews/robux-icons/` (placeholder art, real art needs Roblox).
- **Vehicle GLB pass (branch `phase-2/vehicle-models-fixed`, 13 October 2026).** Connor's fixed vehicle GLBs
  (`origin/phase-2/v1-store-items` at 86be542: 8 vehicles and 12 `by_truck` trailer variants) are in `assets/glb/vehicles` and
  replace the files in `assets/meshes/vehicles` (same one-Wheel-per-GLB, copied per axle). **Roblox still holds the OLD meshes:
  38 mesh ids need re-uploading in Creator Hub** (list in `ASSETS.md`, "Creator Hub re-upload list", Windows steps in
  `PHASE2_NOTES.md`); every id stays in `VehicleModels`, so nothing breaks, and the looks change when each new id is pasted in.
  Until then the new file only shows in previews. Changes: (1) every piece's `size` is its GLB node's own bounds (the Pickup
  wheel is 1.377 x 3.52 x 3.51 around the game's radius 1.755, width 1.365, never resized) and carries `at`, its middle in the
  GLB's assembly, which is where `VehicleMeshes` now puts it (the old hull rule dropped the Body 0.7 stud below its arches, so
  tyres went through the body). (2) The Pickup's half-turn (`mirrorLeft`, PR #186) is off: the new wheel is dished on both
  faces; the switch and its test stay for a one-sided mesh. (3) Part-built art (the Timber Classic for good, every truck while
  its meshes load, the Dealership's trailer copies): fenders keep off the tyres, the Pickup's one mudflap hangs flush from the
  rear fender (a meshed Pickup drops it; the mesh has its own), a dished cream rim with four lug nuts and a chrome cap on the
  Pickup and Timber Classic wheels, the Classic's stake bed (posts and a top rail), stripes 0.04 proud, the Heavy Hauler's side
  markers clear of its wheels. (4) New `tests/VehicleWheelClearance.spec`: no wheel overlaps its body, bed or arch parts, part-built
  and meshed (real GLB triangles), with named, depth-capped exemptions. **No price, stat, hitbox or physics change.** Open: the
  GLBs still put the wheel-well liner 0.2 stud inside the tyre and the Heavy Hauler's deck and marker lamps over its tyres
  (hidden, capped in the spec; Connor to fix in the GLBs). Renders: `previews/vehicles-fixed/` (before, after, contact sheet).
- **Every truck and trailer shows its rim on the left side (branch `phase-2/all-trucks-wheel-faces`, 13 October 2026).** Connor: all
  trucks need the fix. Cause: the 13 Oct GLB pass switched the Pickup's half turn off because the repo's new wheel GLBs are dished
  on both faces (checked from the triangles and vertex colours: the same rim, dish, lugs and cap on +X and -X in all 8 vehicles and
  all 12 `by_truck` files, see `tests/VehicleWheelFaces.spec`), **but the wheel meshes live in Roblox are still the old one-sided
  uploads** (rim on +X only; the ids did not change and the re-upload list in `ASSETS.md` is not done), so in Studio every
  left wheel was a flat black back again. Now `mirrorLeft` is on for every truck, the Scout ATV and every trailer variant in
  `VehicleModels` (the half turn of a two-sided wheel looks identical, so it stays safe after the re-upload; remove it only when you
  want, nothing needs it then). Part-built wheels (Timber Classic, Paint Shop recolours, the Dealership trailer copies, every truck
  while meshes load) already show rim, dish, lugs and cap on both faces. Spin and steer axes, layout, sizes, hitbox, price and
  stats unchanged (spec pins it). Renders: `previews/wheel-faces/` (before = the old uploaded wheel, after = fixed, contact sheet).
## Store event expansion room (branch `phase-2/store-event-expansion`, system only, nothing on sale)

Every store can grow for an event without a rebuild. This PR is the system; each store's builder places the geometry.
Plain version, with the how-to in `EVENTS.md`:

- **Nothing is on sale and nothing is visible by default.** The schedule (`Shared/StoreEventData.Events`) is empty, the 12 event
  slots (`StoreData.EventSlots`, 3 per store) are unapproved with no price, and with the default empty schedule every store,
  row, price and visibility is identical to before (`StoreEventService.spec` pins it). `tools/economy` and `ECONOMY.md` did not change.
- **An event slot can be bought only when ALL of these hold:** an enabled event for that store is running now, the event lists the slot,
  Connor has set `approved = true` with an `itemKind`, `itemId` and an explicit `price` on the row. An unset price keeps it refused.
  The server check is in `ShopService.ChargeAndGrant`; the slot id is never an ordinary shop item.
- **Switching an event on or off needs no code change:** edit one table (`StoreEventData`) with a start date, an end date and
  `enabled`, or in Studio paste JSON into the Workspace attribute `StoreEventConfig` (Studio only, nothing published).
  `StoreEventService` re-checks every minute from the config and `os.time()`; a restart, a clock change or a toggle off mid-event just
  recomputes. Items vanish from sale when an event ends or is turned off; items already bought stay owned.
- **New modules:** `Shared/StoreEvents` (pure rules, dates, sanitising, 60-day cap), `Shared/StoreEventData` (the schedule),
  `Shared/Art/ShopEventKit` (the roped-off zone and the event banner builder, about 26 and 8 parts), `StoreEventService` (server).
  Small hooks: `StoreData.EventSlots`, `ShopService.SetLiveEventSlots` and the event-slot gate, `BoxService` passes `eventSlot`.
- **Still to do (other lanes):** each store's builder calls `ShopEventKit.BuildZone` and `BuildBanner` (API at the top of the module);
  Hearth & Home, Tool Shed and Sparkworks restyles are in other PRs.
- **Awaiting Connor:** approve the event items and their prices when an event is planned; the banner wording per event; whether
  an owner chat command to start an event is wanted (not built: `AdminService` has no event pattern to follow).
- **Not verified:** the zone and banner have not been seen in Studio or rendered with real meshes (they are plain parts); the
  Studio attribute path is tested with a fake clock and mocks only.

## Dealership sign spacing (branch `phase-2/dealership-sign-spacing`, follow-up to #180)

Connor approved the #180 renders with "signs may be a little too close together and a little too much in abundance".
Counted before: 16 hung boards inside (SHOWROOM, 5 TRUCKS/TRAILERS headers, 8 bed sub-signs, CHECKOUT board and a CHECKOUT
plaque on the counter), 4 flags along the front wall, a swatch board, 17 hung lanterns; outside, 6 text signs (DEALERSHIP, a
second TRUCKS & TRAILERS board over the windows, the door-end board, hours board, closed sign, a sandwich board). After: 6 hung
boards inside (SHOWROOM, 4 headers, CHECKOUT), no interior flags, no swatch board, 9 hung lanterns; 4 text signs outside. What went:
the 8 hung sub-signs (each plinth's own name sign, now bigger, carries the name and a second line with what it hauls, from
`DealershipLot.BedText`), the repeated header for a kind that comes back later in a row (the plinths' name signs tell it),
the counter plaque (CHECKOUT hangs lower now, under the SHOWROOM board's line of sight from the door, where it was cropped), the
per-bay hung lanterns (each plinth has its own lamp post), the OfficeSign over the windows, the sandwich board (the hours board
says it), the swatch board and the front-wall flags. Kept: SHOWROOM, TRUCKS and TRAILERS, CHECKOUT, the DEALERSHIP roof sign, the
door-end board, tier T-flags, plinth name signs, hours and closed signs. Specs: 3 studs minimum between hung boards, no board in
front of another from the door, a ceiling on hung boards (6) and on every sign on the building (12). No price, vehicle, tier or
buying change. Renders `previews/store-polish/dealership-v2-*.png`.

**No-overlap spec (`tests/DealershipOverlap.spec.luau`).** In 3D, on the building (inside and out), the lot and the vehicles: 1225 sign-group pairs, about 105,000 sign-part against structure/prop/vehicle pairs, about 83,000 prop/display/structure pairs, all with 0.05 tolerance. It found and fixed: the hours board stood 0.25 into the wall above the door and the canopy's near end pierced it (canopy now stands 0.7 off the wall, far end unchanged, `ShopFacade.AwningGap`), the lobby trash can overlapped a barrel (moved), and each plinth's aisle stripe ran under the box's accent block (stripe is now 0.3 wide at the very edge, `DealershipLot.StripeWidth`).

## Store polish: the Dealership (branch `phase-2/store-polish-dealership`, 12 October 2026)

Connor's item 5. The Dealership stays its own building; nothing about buying, prices, stock, hidden Coming-soon items, StoreUI or
the purchase flow changed. **Connor's reference screenshots never arrived, so this was designed to the written brief** (and
renders are the thing to approve). Audited the #162 build with `tools/preview` and a new geometry spec, then fixed what was real:

- **Floating parts (found by the new spec).** The ceiling beams and rafters stopped 0.7 short of the walls; every hung sign, chain
  and lantern ended 0.9 under the roof (in the air); the reception chair's backrest sat 0.2 off its seat; each vehicle's name sign
  hovered 0.2 over the floor and 0.35 off its plinth. Beams and rafters now run into the walls (`Dealership.WallTuck`), every
  chain runs to the roof's underside, the backrest touches the seat, the name sign stands on the floor against the plinth band.
- **Clearance.** The Logging Rig's display copy topped out 0.1 under the beams (`MaxVehicleHeight` 12.4); now 12.0 (0.5 of air).
  Display copy only; the gameplay truck, its stats and every price are untouched.
- **Exterior** (`BuildingArt.dealership`): a paved forecourt (`Forecourt`, `ForecourtKerb`, 5 deep, two pieces with the door's walk left open and looks only (it does not collide), because `DealershipLot.spec` and `WorldPlan.spec` keep colliding parts off `DealershipPath`, roads and grass; the doormat lies on the street) level with the hall floor, so the
  planters, bench, sandwich board, awning posts and doormat stand on something (they stood 0.4 over the lawn); six cream piers
  between the windows, a cornice under the roof's lip, five forecourt lamp posts (0.9 / 14, under ShopKit's caps), the accent stripe
  round all four sides, and a `TRUCKS & TRAILERS` board across the door end's wall (the end the approach road meets). The second pair
  of porch posts is gone: the porch lantern hangs on the awning post.
- **Specs** (`StoreInterior.Dealership.spec`): no floating parts for the interior, the whole hall and the lot's stands; every display
  rests on its own plinth, one per vehicle; nothing hung touches a display vehicle; every display under the beams with 0.4 spare;
  forecourt, end board (text fits, faces west, against the wall) and stripes. Moved: `MaxVehicleHeight` 12.4 to 12.0 (design
  moved). Whole hall 384 parts (cap 400, interior 218 of its own 400, lot 528).
- **Renders** in `previews/store-polish/dealership-*.png` (exterior front, 3/4, night, the door end, interior from the door, the
  tier stand, the counter, phone size). The keeper's body does not draw in the preview (only his name tag), for every store.
- **Awaiting Connor:** the reference screenshots (send them if the brief missed something); whether the lot lamps should be dimmer
  or fewer.
## Hearth & Home restyle, Shed Blueprint and model slots (branch `phase-2/store-polish-hearth`, PR #183, 12 October 2026)

Connor's fixes after the #183 renders. No price, on/off-sale or buy-flow change (the five formerly off-sale products stay id 0).

- **Shed Blueprint.** The General Store's Small Shed is now the **Shed Blueprint**, $600 as before. Buying hands over the plan (the
  hammer's plan item, unchanged); placing it costs the kit fee (60 units x $4 = $240) and puts down a **ghost you fill with 60 plank
  units**, like the wall (`PlotData` Shed: `kit = true`, `storePrice = 600`, `storeName = "Shed Blueprint"`, `displayName = "Shed"`).
  The save id stays `Shed`, so no migration is needed: a save that owned the plan, carried it or had a shed standing loads unchanged
  (a placed shed with no `fill` stays a finished shed). Spec: `tests/ShedBlueprint.spec.luau`. Moved pins (design moved): the
  `Shed` rows in `BuildingKit`, `ModernKit`, `PlotLogic`, `BlueprintBook`, `PlotService`, `ShopService`, `BlueprintService` specs.
- **MODEL_SLOTS.** Four items get one model slot each, in `Shared/Art/ModelSlots.luau`: `Flashlight`, `Lantern`, `WoodSign`,
  `ShedBlueprint` (Connor's GLBs, `assets/glb/store-items/<Name>.glb`). Put the Roblox MeshPart id in the slot's `meshId` (it is 0
  now, so every path keeps its part-built look) and the model swaps in, through `MeshKit.Attempt`, never blocking, on: the shop
  box's window copy and the sample on the General Store's back ledge (display: `BoxArt.Dress`, `BuildingArt`), the item in the hand
  (held: `BlueprintArt.Held` for a plan, `ItemModel.Held` for gear) and the item in the world (placed: `BlueprintModels.Build` for the
  Wood Sign on a plot, `BlueprintArt.Dropped` for the plan on the ground, `ItemModel.Placed` for gear). What the model must be:
  its `size` is the GLB's own proportions times `fit` (Flashlight 2.30 x 0.58 x 0.58 lying along X, Lantern 0.61 x 1.55 x 0.61,
  Wood Sign 2.29 x 3.90 x 0.41, Shed Blueprint 2.10 x 4.57 x 2.71), pivot at the middle of the bounding box, +Y up, front toward -Z.
  Gear is worn today, so nothing in the game equips `ItemModel.Held`/`Placed` for the Lantern and Flashlight yet; the slot paths
  exist and are tested. The Shed's model is the plan, so on a plot the Shed ghost stays the part-built shed. The preview loads the
  GLBs through `tools/preview/store-items-meshes.json` (`PREVIEW_MESHES=tools/preview/store-items-meshes.json`). Spec:
  `tests/ModelSlots.spec.luau` (also reads each GLB's bounding box).
- **Display tables** (`ShopKit.DisplayTable`, `SpotTag`, `SpotLamp`; `SteppedUnit(..., "table")`): a wood-top plank table per row of
  boxes (trim edge), a small price card per box read from `StoreStock.UnitPrice` (carries the hover tag), a lock card ("S5 SMITH")
  beside the price card for a gated item (shown only while locked, as the old chip), and a warm spot over each table. The tier
  flags on posts are gone (the stray purple "T5 / S5 SMI..." flag was one standing against the wall); nothing stands outside its table.
- **Signs.** HOME PLANS and BUILD PLANS are 7.2 wide and nearer the aisle (whole word on screen from the door and on a phone); the
  four back-wall item boards are 5.7 x 2.25 (were 8.4 x 3.45) and read SHED BLUEPRINT; CHECKOUT stands on two posts on the counter
  front over the register (no plaque, no chains across other signs).
- **Door frame and awning** (`ShopFacade.DoorFrame`, `ShopFacade.StripedAwning`): cream posts on stone footings, a flush stone
  threshold (looks only: no step), and a striped canopy of 0.18 thick fabric slabs with a stepped valance, rail, posts and brackets.
  The swing leaves are framed doors now (ring of trim, middle rail).
- **Room fill:** two wall shelf units (jars, books, baskets), four framed pictures, a rug in the east nook, two more plants.
- **Event room** (#185 `ShopEventKit`): the roped zone (16 x 9, back west corner, back against the wall) and the banner (front west
  corner, off the doorway aisle).
- **Parts:** the whole shop is 451 (cap 350 to 460: the event room is 34 of it). Interior budget unchanged (400).
- **Specs:** `StoreOverlap.HearthAndHome` (families for every new part, plus a guard that no new name is unchecked),
  `StoreInterior.HearthAndHome` (tables, cards, lock cards, spots, `DisplayTable`), `BuildingArt` (box on its table, cap 450).
- **Renders:** `previews/store-polish/hearth-v3-*.png` (exterior front, three-quarter, night, door close-up, interior from the door,
  table close-up, counter and CHECKOUT, phone 667x375). Not seen in Studio.
- **v4 (Connor's review of the v3 renders):** the coloured slab under each box was BoxArt's accent floor; scoped to Hearth & Home only
  with `BoxArt` `spec.wood` (BoxService and the preview pass it for the General Store's boxes): a wood base board of the same size and a
  slim walnut name card (0.36 tall, 74% of the box width) instead of the accent floor and band; box size, hover tag, prompts and focus
  are identical, and no other store's boxes change. The display tables are oak (colours that show in the preview), a thick top with a
  cream trim along its front edge, two legs to the floor under each table's front corners, tables stepping up and meeting; the unit's
  solid core stays as an invisible collider. `store-hearth-event` scene shows the event zone and banner active; the banner now faces
  into the room (it faced the wall). Parts 451 (cap 460). Renders: `previews/store-polish/hearth-v4-*.png`.
- **Awaiting Connor:** (1) DECIDED by Connor, 13 Oct 2026: placing the Shed Blueprint ghost is free (`placeFee = 0`); the plan is still $600 and the fill is still 60 plank units; an old save's `paid` 240 still sells back at half; (2) the Lantern and
  Flashlight have no held model in the game, so their held slot path waits for a held-gear feature; (3) the blue under each box is
  the box's own accent floor (BoxArt, shared by every store), not a plinth; (4) parts 444 against the old 350 cap.

## Tool Shed restyle (branch `phase-2/store-restyle-toolshed`, look only; no price, item, stock, on-sale or buy-flow change)

The Hearth & Home restyle (#183, #185) applied to the Tool Shed. Each store stays its own building. Not seen in Studio.
- **Tables:** `ShopKit.SteppedUnit(..., "table")` on both units: a wood-top `DisplayTable` per row of boxes (plank top, cream trim edge,
  two legs), a small price card per box (`SpotTag`, the price from `StoreStock.UnitPrice`), a lock card for a gated axe, a spot over the
  middle of each table. The coloured plinths, tier flags on posts and "NEEDS ..." chips on posts are gone. Boxes get the wood base and
  slim name card (`BoxArt` `spec.wood`): `BoxService` passes it for `ToolShed` too (not for the gold Robux boxes, not for other stores).
- **Signs:** two headers (AXES & BELTS, MACHINES) 8.6 wide, toward the aisle, hung on short chains from a cross beam (the collar ties
  stuck through the lower roof slope and floated; they are gone, `ShopKit.SectionSigns` got an optional `noTie`); no sub-signs; rack
  name plates 2.4 x 1.0 (were 3.0 x 1.3); CHECKOUT on two posts on the counter's front edge (no plaque).
- **Street side:** `ShopFacade.DoorFrame` (cream posts on stone footings, a lantern each, threshold) and `ShopFacade.StripedAwning`
  (barn red and cream) over the barn door, which still slides: its open leaves stand 2.1 further out (`ShopDoor.Spec.openShift`, optional)
  so they clear the posts. The porch posts are gone. From #181: two lit windows in each long wall, a flagstone path, the firewood
  moved off the wall. The hours board used to sit inside the wall (invisible): it stands on the wall's face above the awning and the
  door track.
- **Room fill:** two shelves with tools and cans over the tables each side, four framed pictures, a pegboard of tools each side of the
  door, a rug and two plants before the counter, a plant by the door; the back-room door moved to the west wall.
- **Event room:** the roped zone (11.9 x 8.6, `ShopEventKit.BuildZone`) in the back east corner and the blank banner at the aisle's west
  edge just inside the door, both hidden by default, nothing on sale. **The tables fill both sides, so no 14 x 8 patch of floor is free:**
  `BuildZone` got an optional `minSize` (the Tool Shed passes 11 x 8; other stores unchanged) and the banner cannot be off the 6-stud
  middle of the aisle (the aisle is 10 wide; it stands in the west 3.5 of it, clear of the 3-stud walk and of the table).
- **Parts:** 452 whole shop (cap 400 to 460, `BuildingArt.spec`); interior budget unchanged (400).
- **Specs:** `StoreOverlap.ToolShed` (new: oriented-box overlap over the whole shop plus a stand-in per box, sign/sign, sign/building,
  prop/prop, props vs walls and roof, nothing up in the barn through the roof, screen-space from the door, phone, entrance and street,
  and a guard that every part name is classified), `StoreInterior.ToolShed` (rewritten for tables, headers, CHECKOUT, dressing, event
  room, nothing floats), `BuildingArt` (box on its table; cap 460), `BoxService` (wood look for the Tool Shed, not for gold boxes).
- **Out front:** the barn's floor is 0.75 over the lawn (a ramp climbs to the door), and the facade props used to stand at the floor's
  level, hovering: the door posts, awning posts, barrel, crate and doormat now stand on the lawn (the threshold stays at the floor);
  the grindstone moved 0.6 west so its leg is clear of the awning post.
- **Renders:** `previews/store-polish/toolshed-v4-*.png`, 25 of them (exterior front, three-quarter, night, side, phone 667x375, door
  close-up, awning and hours board, door post and lantern, both yards; interior from the door, phone 667x375, night, table close-up,
  counter and CHECKOUT, from above, stock corner, machine table, west wall, pegboard; event zone, from above, at night, banner).
  Scenes `store-toolshed`, `store-toolshed-exterior`, `store-toolshed-event` (the last shows the event room active).
- **Awaiting Connor:** (1) event room is 11.9 x 8.6 (not 16 x 9) and the banner stands at the aisle's west edge, because the tables leave
  no other floor; (2) the barn door's open leaves slide 2.1 further out than before; (3) the CHECKOUT board hides the middle two rack
  name plates from some angles (it stands on the counter in front of the rack).
## Dealership restyle in the Hearth & Home look (branch `phase-2/store-restyle-dealership`, 12 October 2026)

The Hearth & Home cleanup (#183, with the event kit #185) applied to the showroom hall. Looks and layout only: no price, economy, stock,
sale or buy-flow change; the lot, plinths, vehicles, boxes, bays and the sign-spacing and lot-strip work are kept.

- **Door frame and awning** (`ShopFacade.DoorFrame` now takes an optional `gap`; `ShopFacade.StripedAwning`; the Dealership branch of
  `ShopFacade.Add`): cream posts on stone footings, the dark header and jambs, a flush stone threshold; the flat blue/cream canopy is
  now an 8-stripe fabric awning with a stepped valance, posts and brackets (`ShopFacade.DealerAwning`: back 12.15, reach 4.6). The
  hours board over the door is raised clear of the canopy's back (`BuildingArt.Shop`), the front footing starts past the right post,
  the planters stand 0.5 further out, the porch lantern follows the new awning post.
- **Plinths and boxes** (`DealershipLot`): the big accent pad under each box was a 0.3 slab; it is now a 0.1 inlay inside a 0.05 wood
  border (`BoxMatFrame`), both flush on the plinth's top, the border's edge meeting the tier stripe's inner edge. Vehicles' boxes wear
  the wood base and slim name card the General Store's do (`BoxService`: `wood` for the Dealership too). Name signs 5.0 x 1.9 x 0.16
  (were 6.0 x 2.6 x 0.3), tier flags 2.8 x 1.6 on a post 4.6 up (were 3.4 x 2.0 at 5.0); each flag, band and stripe keeps its plinth's tier colour.
- **CHECKOUT** stands on two posts on the counter (`ShopKit.CheckoutSign` `onCounter`), no plaque, no chains.
- **Room fill** (`ShopInteriors/Dealership`): wooden tables from the kit (`ShopKit.DisplayTable`: reception and finance, legs on the
  rug), two rugs, wall shelving with binders and model trucks (west and back walls), five framed pictures, plants, the brochure racks
  moved to the front wall. Everything is clear of the runner, the doorway aisle and every vehicle.
- **Event room** (`ShopEventKit`): the roped zone (16 x 9, turned so its back is on the west wall and its open front faces the runner)
  with its three tables on the pads (the Hearth's wood, looks only), and the blank banner in the front corner by the entrance,
  facing the doorway aisle; hidden/closed by default, nothing on sale. Scene `store-dealership-event` shows it active.
- **Parts:** whole hall 408 (was 285), cap 400 to 420 (`BuildingArt.spec`, `StoreInterior.Dealership.spec`); interior still under 400.
- **Specs:** new `StoreRestyle.Dealership` (door frame, awning, tables, furnishings, box mats, slim signs and flag colours, CHECKOUT, event
  zone and banner placement, hidden by default, nothing on sale, caps); `DealershipOverlap` has every new part name in a class, a
  guard that no part name goes unchecked (the floor skins and door mechanics are named as looks-only) and an event-room test.
  Pinned numbers that moved because the design moved: the hall's part cap 400 to 420 (two specs); wall furniture may meet the wall's
  face (0.41 instead of 0.31 in the inside-the-hall check, for `BrochureRack`, `NookPanel`, `PictureFrame` only).
- **Renders (`tools/preview`, scenes `store-dealership`, `store-dealership-exterior` (new view 9), `store-dealership-event`):**
  `previews/store-polish/dealership-v4-*.png`: exterior-front, exterior-three-quarter, exterior-night, door-closeup, awning-closeup,
  door-phone-667x375, interior-door, interior-night, interior-phone-667x375, plinth-closeup, name-sign, lot-row, table-closeup,
  counter-checkout, lobby-west-wall, front-wall, event-zone, event-zone-from-door, event-banner. The Dealership vehicles are part-built
  (no meshes), so these are the real parts. Not seen in Studio.
## Sparkworks restyle (branch `phase-2/store-restyle-sparkworks`, 13 October 2026)

The Hearth & Home look (#183) applied to the Sparkworks in its teal and copper. Look only: no price, stock, on-sale or buy-flow change.

- **Tables and boxes:** `SteppedUnit(..., "table")`: a wood-top table on legs per row (9), a small price card per box (no tiers or gated
  items here, so no flags and no lock cards), a spot over each table. `BoxArt` `spec.wood` now also reaches the Sparkworks boxes
  (`BoxService`, one condition); a new optional `spec.cardColor` gives them a dark teal name card (`BoxArt.WoodTealCard`) on the same
  wood base. Other stores unchanged.
- **Street side:** `ShopFacade` `sparkworksFront` (from #184: plinth, doorstep, pilasters, fascia, copper conduit with spark lamps, rods,
  lamp posts) plus `DoorFrame` and a teal and cream `StripedAwning`; the hours board sits over the awning. Room is 15 high (roof rests on
  the walls), no porch posts or WIRE IT UP board.
- **Inside:** two headers 10 wide (BELTS & INPUTS, LOGIC & OUTPUTS) fully inside the walls, CHECKOUT on the counter, a SPARKWORKS name
  board over it (no sub-signs), wall shelves, six framed pictures, rug, plants, spools on a pallet, stock corner, conduit and fuse boxes.
- **Event room:** `ShopEventKit` zone 12 x 10 in the back west corner against the west wall (turned so its open front faces the aisle),
  hidden by default; banner by the counter's east end facing the door, off the aisle, hidden and blank. The room is only 35 wide and
  the lanes fill both side walls to z 4.7 and 8.3, so the corner is 12 wide: `ShopEventKit.MinSize` 14 x 8 to 12 x 8 (its three table
  spots come out about 2.3 wide there). The front corners are lane fronts, so the banner is not by the door (Awaiting Connor).
- **Parts:** whole shop 419 (cap 400 to 440, `BuildingArt.spec`); interior within the 400 budget. 
- **Specs:** `StoreOverlap.Sparkworks` (3D SAT, families for every part, unchecked-name guard, screen views), `StoreInterior.Sparkworks`
  (tables, cards, spots, headers, floating, event zone and banner placement), `StoreExterior.Sparkworks` (cap, floating, door frame and
  awning), `BoxArt`, `BoxService`, `ShopEventKit`. Pinned numbers moved (design moved): sign-pair counts 5000 to 4000 and 10 to 6 signs.
- **Renders:** `previews/store-polish/sparkworks-v4-*.png` (scenes `store-sparkworks`, `-exterior`, `-event`). Not seen in Studio.
- **Awaiting Connor:** (1) banner placement by the counter, not the door (no free floor by the door); (2) event tables 2.3 wide here;
  (3) #184 is superseded by this branch (same room height, no sub-signs, exterior front).

## Store card images through the asset thumbnail (branch `phase-2/store-images-thumb`, 12 October 2026)

The three pasted store image ids (91282142796474 Tow Service, 79037897236948 Timber Classic, 71028498113750 Paint Shop) may be Decal ids, which an ImageLabel cannot load by `rbxassetid://`. `Shared/StoreArt.ImageFor(id, size)` now returns `rbxthumb://type=Asset&id=<id>&w=<n>&h=<n>` (150 on the panel card, 420 on the world board) for a nonzero id and `""` for 0; `StoreUI` and `StoreBoard` use it, and the letter or mark fallback (failed load, id 0) is unchanged. No prices, sale flags or ids changed. Unverified: that the thumbnails render (needs Studio). `AssetIds.spec` allows the one rbxthumb literal in `StoreArt.luau` and still fails any other.

## Asset audit (branch `phase-2/audit-assets`, 12 October 2026)

`ASSETS.md` (generated: `lune run tools/assets`, kept current by `check.sh`) lists every asset id in the source with its use and
status. **Nothing in it is verified on Roblox or in Studio**: the agent sandbox is blocked from every Roblox host. What is pinned
by `tests/AssetIds.spec.luau`: id format and length per kind, no URL or zero ids, kinds never mixed (no Model container used as a
MeshId), unique containers, mesh sharing only Blender-to-Backlog, well-formed MeshTemplates. The four machines that stayed
part-built in Connor's log (SmeltingFurnace, Prospector, OreChute, CraftBench) had correct ids; they were built at server start
outside `MeshKit.Attempt`, so a mesh that was not in yet was final. `MiningArt` now swaps the mesh in when it lands, and
`MachineSkin.Prepare` asks for every piece at once so a five-piece machine is dressed in one round. **Plot machines (13 October 2026,
branch `phase-2/plot-machines-swap-meshes`):** the same gap on `MachineArt` (sawmills, planers, chop saw, belts) is closed: a
machine built before its meshes are cached is part-built and usable at once, then `MeshKit.Attempt` swaps the mesh in place
(`MachineArt.wearWhenLoaded`; same gameplay part instances, pivot kept after a move, a failed load keeps the part build with one
log line, a destroyed machine is dropped). `tests/MachineSwap.spec` pins it for every kind. The Sky Bin has no mesh entry in
`MachineMeshes`, so there is nothing to swap. Nothing seen in Studio. The Creator Hub checks for Connor are at the end of `ASSETS.md`.

**Asset check tool (branch `phase-2/asset-check-tool`).** No id has been checked on Roblox (sandbox blocked). Connor runs
`scripts\check-assets.ps1` on Windows (steps in `ASSETS.md`): it reads `tools/asset-ids.json` (written by `tools/assets`), asks
`economy.roblox.com/v2/assets/<id>/details` for each id, and writes `ASSETS-CHECK.md` / `.csv` (type, owner, will it load, must-fix
list, the four machine meshes first). Read-only. Pinned by `tests/AssetCheckTool.spec.luau`. **Open:** run it and bring back the table.

## Server boot and runtime audit (branch `phase-2/audit-server-boot`, 12 October 2026)

Read all of ServerScriptService and the server side of Shared for things a real Studio server start would trip on that the mocked specs cannot see. Fixed: the v2 wiring in GameServer ran bare (one throw and "services" never opened, PlayerAdded never connected); MiningBoot built the mine at server start, before MapBuilder's Underground step, so the mine's own rubble could be doubled by an untracked wall (it now waits for the Remotes folder like BaseBoot); a player who left and rejoined the same server did not get their stored shop boxes back (BoxService "restored" flag); MiningBoot, TownBoardBoot and BaseBoot now warn when a module is missing or does not load. Checks in PHASE2_NOTES.md "Server boot and runtime audit". Specs: `ServerBootAudit.spec`, `BoxService.spec`.

## Client boot audit (branch `phase-2/audit-client-boot`, 12 October 2026)

Connor's log: `ChopSawController Start took 8.03s`, `SawmillController Start took 8.02s`. Seven controllers (ChopSaw, Sawmill,
Carry, Chop, Cut, Drag, WoodFX) polled for `CoreLoopActive` with `task.wait` inside Start (8 to 120 s), held the client ready
handshake, and after the wait decided for the v1 loop for good. `CoreLoop.WhenKnown` now runs their setup when the server
publishes the loop, however late, and Start returns at once. Also: ForgeUI waited 60 s for the Remotes folder (a build takes
300 s, so the Forge never opened) and QuestUI 30 s for Murph's portrait; both wait past the build now. The store's art discs show
their letter when an image fails to load. The loading card no longer needs a bare `require` of LoadingTips. Spec:
`tests/CoreLoopWhenKnown.spec.luau`. Studio checks are in the PR body.

## Load and spawn path audit (branch `phase-2/load-path-audit`, 12 October 2026)

Void rescue for characters (Shared/VoidRescue, y -200, 3 per character), spawn-area streaming before every respawn, guarded join steps. Details in PHASE2_NOTES.md. Needs a Studio look (checks listed there).

## Docs, CI and accessibility (branch `phase-2/docs-ci-accessibility`, 12 October 2026, draft PR)

- **CI type definitions are pinned and cached.** `scripts/check.sh` used to download luau-lsp's `globalTypes.d.luau` from the
  upstream `main` branch on every run. It now reads the pin in `scripts/globalTypes.pin` (a luau-lsp tag, kept equal to the
  luau-lsp version in `rokit.toml`), downloads that tag once to `globalTypes.d.luau` (gitignored, with a `.pin` stamp so a changed
  pin refreshes it), and reuses it. `.github/workflows/checks.yml` caches both files with `actions/cache` keyed on the pin
  (the `lint` job only; job names `lint`, `tests (1/4..4/4)`, `checks` and the sharding are unchanged). To move the pin, change
  `scripts/globalTypes.pin` together with `rokit.toml`.
- **Reduce flashing** (Settings, GAME tab, saved per player as `settings.reduceFlashing`, default off). The only full-screen
  flash in the game is the lightning one (`WeatherController.onLightning` calls `LightingController.Flash` twice, a pulse of
  `ExposureCompensation`); the audit found no other (the cash chip's green tint is a small chip, the plot claim fade is a slow
  black fade, confetti is not a flash). With it on, `LightingController.Flash` (the one place every flash goes through) drops
  the second flash and plays the first at a quarter of the strength for 0.35 s (`SettingsLogic.SoftenFlash`). It is also in force
  while Camera shake is off (`SettingsLogic.ReduceFlashing`; the row then reads "REDUCE FLASHING: ON (SHAKE OFF)"), because
  shake already means "calm the screen". The bolt, the thunder and the warning ring are unchanged. Old saves load with it off
  (`SettingsLogic.Sanitize` inside `ProfileSchema.Migrate`, idempotent). Previews (layout composites, not engine shots):
  `previews/docs-ci-accessibility/settings-*.png`.


## Earlier V1 notes (kept)

- **Client freeze and the late forest** (branch `phase-2/fix-client-freeze`, 11 October 2026, draft PR): Studio showed `TreeFill:380: Script timeout` every 10 s, `WeatherController Start took 11.28s`, and 3 trees at spawn then 1,217 about 10 s later. Causes: `WorldPlan.Trees` (about 10 s of work in Lune) was started again by every client script that asked for it while ForestFiller's paused build was still running (a paused build caches nothing until it ends), and the first ask came through `NatureData.FromWorldPlan` (cave points of interest are placed against every tree) from `WeatherController.Start`'s aurora and from `AmbientLife.zones` (each a full unpaused build); several planners had no pause at all (Scenery 2.2 s, BoulderClusters 3 s, ForestTrees, the Boulders, which were also never cached: 0.6 s each, MeadowBoulders 0.7 s each, many times). Fixes: `TreeFill.takenNear` is a hash grid (same answers as the scan, `TreeFill.TakenNearScan` is the reference); `WorldPlan.WithPause` plus `breathe()` in every planner's hot loop (bound to the calling thread, results unchanged); `WorldPlan.Trees`, `FirstTrees` and the heavy planners run one at a time (a second caller waits for the first's result); `WorldPlan.TreesReady`; `NatureData.FromWorldPlan` is worked out once per plan and leaves the caves out until the trees are ready (callers: `WeatherController`, `AmbientLife`; cells loaded before the caves joined are re-scattered); `WeatherController.Start` spawns the aurora off its path; Boulders and MeadowBoulders cached. The server (`MapBuilder` "5. The trees") plants `WorldPlan.FirstTrees` first (meadow and wild groves, under a second), then each batch the planner hands over (`WorldPlan.Trees(pause, emit)`: the town's trees first, they stand round the spawn; `TreeFill.Extra` plans them first, and keeps the list order, so every tree is where it was: pinned checksum in `tests/ClientFreeze.spec`), nearest the spawn first inside each batch, instead of planning all 1,041 before planting any (one global sawmill-first sort). No tree count, wood or price changed, so ECONOMY.md and ECONOMY_V1.md did not move. The one design change: the old "nearest the sawmill first, globally" spec became "the first batch, then the town's trees, each nearest the spawn first" (MapBuilder.spec). Still needs Studio: no frame over 100 ms in the profiler on PC, phone and Xbox, and the tree timeline (PHASE2_NOTES.md "Client freeze and the late forest").
- **V1 backlog meshes** (branch `phase-2/v1-backlog-meshes`, 10 October 2026, off main `ec9d2cb`; draft PR): `Art/BacklogModels` holds the 109 uploaded backlog assets (shops, gear, landmarks, furniture, plants, cave props, critters, polish, the two environment remakes, townsfolk) with every piece's real MeshPart id, and `TownModels.Get` falls through to it (not for townsfolk, which stay with the NPC lane). All 372 ids have `MeshTemplates` files. Wired now: OddsAndEnds, Sparkworks, LandOffice, GateKiosk (glow keeps the gate colour), ArrivalArch (`TownMeshes.Dress`) and the Robux crate (`RobuxBoxArt`, the open crate of parts stays as the fallback). A missing mesh keeps the part build, sets `MeshFallback` on the model and logs once per asset. Trees: `TreeModels` rows for Lanternwood (live), Bog Cypress and Ironwood (waiting for job 11) plus the `Knees` branch in `TreeMeshes`. Not wired, waiting on a design call or a builder: the Robux table (mesh is a one-row 2.5 high table, the shelf has two rows on a riser at 3.9), Sky Forge Court, the other boards and scenes, gear, landmarks, plants, cave props, critters, polish, the two environment remakes (`SawdustPileV2`, `PathRoundV2`). Source GLBs for the backlog are in `assets/glb/backlog` (from `phase-2/v1-glb-sources`, npcs excluded). Previews with the real meshes: `previews/v1-backlog/` (34 shots: five shops, the Robux crate, Lanternwood, five angles each; made by `python3 tools/preview/backlog_manifest.py` then `PREVIEW_MESHES=preview/backlog-meshes.json bash tools/preview/shoot.sh v1-backlog`) and `previews/v1-a2/relic-trophies.png` re-shot (`v1-backlog-trophies`). Studio checklist: PHASE2_NOTES.md "V1 backlog meshes".

## First-session polish (branch `phase-2/first-session-polish`, 12 October 2026, draft PR)

Five small fixes to the first half hour. No price, economy, pacing, amount, on-sale, badge-id or asset-id changed (ECONOMY.md and ECONOMY_V1.md did not move). Studio has seen none of it.
- **TIPS setting now works.** `SettingsLogic.TipsShown(setting, step)` (pure): only a real `false` turns tips off (default on); while a tutorial step runs (`TutorialStep` 1 or more) tips stay on, because the bottom hint bar and the "put your axe away" toast carry lessons. `HUD` hides the hint bar with it (it already had `SetTips`, but only SettingsUI drove it and a tutorial could not override it; it now also follows the `SettingShowTips` attribute and `TutorialStep`), `HUD.Toast` drops a tip (`NoticePolicy.IsTip`: a notice with a once-key) when tips are off, and `QuestService`'s first cold/heat tip is skipped (and left unseen, so it returns when tips come back). Refusals, results and Murph's card never read the setting.
- **No "What's new in V1" over the farewell for a new player.** `NewsLogic.IsBrandNew(tutorialDone, refresher, replay)`; `NewsService.Start` marks `News:V1` seen for a brand-new save (still in its first tutorial, not a returning player's refresher or a replay). Returning players (finished save, refresher, replay) keep the auto popup; the Settings "What's new" button is unchanged.
- **"Badge earned: <name>" toast.** `BadgeUI` compares each `BadgeSync` payload with the last (`BadgeData.NewlyEarned`, `BadgeData.ToastText`) and calls `HUD.Toast(text, nil, { priority = "normal" })`, so `NoticePolicy` limits apply (one non-critical at a time, queued behind any other toast such as a future stage toast, dropped in the first-sale quiet flow; the panel always has it). The first sync after join is silent; several at once fold into "Badges earned: X and N more". The text never says Roblox awarded it; badge ids stay 0 and `AwardBadge` is untouched.
- **Buy, Equip and a step tick.** `SoundData.ForNotice(text)` returns "Buy" for the server's "Bought the ..." line (HUD's Notify handler; a refusal never starts that way); `SoundData.EquipPlays` gates "Equip" when a Tool lands in the character's hands (`AxeController`; not in the first 1.5 s after a spawn); `SoundData.StepTick(prev, step)` gives the existing `UIClick` when the tutorial moves on to a new step (`QuestUI.refresh`; not at join, not at the end, not on a replay start). All through `SoundData.Play`, which honours the SFX switch and volume. All three ids already exist; none was added.
- **Day-1 login toast is held, then shown.** During the tutorial `DailyService.claimLogin` still pays the same cash but now stores the toast text in `profile.daily.loginToast` (new optional field; `ProfileSchema` type, `applyDaily` drops anything not real text under 120 characters, idempotent) instead of dropping it. `QuestService.OnFinished` listeners run when the tutorial ends; `DailyService` shows it 4 s later (clear before send, so once only) and also on the next join if it is still held (rejoin mid-tutorial keeps it).

## Store interiors: shared kit and the Tool Shed pilot (branch `phase-2/store-interiors-polish`, draft PR, look-and-layout only)

A polish pass on every store interior so all stores read as one Timberline family (timber, brass, pine). This branch is the KIT and ONE PILOT (the Tool Shed); the other stores are applied by their own agents from this branch. Nothing here touches StoreUI, the purchase flow, prices, stock contents or order, what is on sale, ids, the hidden "Coming soon" items (RobuxTableArt is untouched), lanes, footprints, doors or paths. Studio has seen none of it.

**What is where**
- `Shared/StoreTier` (pure): the one tier colour ramp T1 to T9 (honey, moss, sage, lake, plum, brick, brass, ember, frost), the badge ink for each (`InkOn`, WCAG), `Of(kind, itemId)` (which tier an item has, from the catalogs; axes by ladder rung, sawmills, planers, gear by stage, plans by plot tier above 1, vehicles by price rank within their kind), `LockOf` / `IsLocked` (axes in order; gear for a later stage). `StoreTier.spec` pins distinct colours and AA contrast.
- `Shared/Art/ShopKit` (the kit): `HeaderSign`, `SubSign`, `SectionSigns`, `TierStand` (plinth in the tier colour, a tier flag "T3" on a post at the aisle-side front corner, a lock chip, hover tag on all three), `SteppedUnit` (the tables and shelf units; calls `TierStand` per placement), `HoverAnchor`, `CheckoutSign` (brass plaque on the counter front, optional hanging board) and the keeper mat, `WarmLamp` and `Light` (warm, brightness 0.9, range 16, no shadows), `Beams` / `Rafter`, `MeshProp` (a real mesh with a part-built fallback, then swapped in: `MeshKit.Attempt`, no yielding load), `CountParts` / `Budget` (400), `TextPx` (phone legibility rule), and the older floor, runner, plant, crate and back-door helpers.
- `Shared/Art/ShopInterior` only dispatches to one module per store in `Shared/Art/ShopInteriors/`: `ToolShed` (new look, the pilot), `HearthAndHome`, `Sparkworks`, `Dealership` (the old interiors, moved unchanged, `Build(model, frame[, west, east, zf, zb, bays])`). Each agent edits only its own file, its own `tests/StoreInterior.<Store>.spec.luau` and its own `tools/preview/scenes/store-<store>.luau`.
- Client: `StarterPlayerScripts/StoreStandState` greys a stand while its item is locked for the player (`BestAxeTier`, `StoreStage` attributes; display only) and shows the lock chip.

**Recipe: apply the kit to a store** (copy `ShopInteriors/ToolShed.luau` as the model)
1. Read the store's lanes and stock: `StoreStock.Lanes/Placements(shop)`. Do not move them.
2. In `ShopInteriors/<Store>.luau` keep `Build(model, frame)`. First `ShopKit.SteppedUnit(model, shop, frame, name, body, top)` (it builds the stands and flags). Then the floor (`plankFloor`, `floorBorder`, `runner`), `ShopKit.Beams` / `Rafter`, `ShopKit.WarmLamp` (6 to 9 lamps; every one is warm and capped), `ShopKit.SectionSigns(model, shop, <Store>.Sections, { headerY, headerZ, ceilY })`, `ShopKit.CheckoutSign(model, frame[, true])`, and `ShopKit.MeshProp` for crates, barrels, plants, benches and so on (always with a part-built fallback model).
3. `<Store>.Sections` is a list of `{ lane, header, accent, subs = { { text, ids } } }`, built from the shop's real categories (ids are the items' `itemId`s). A header is at most 18 characters, a sub-sign 16 (one line). Every slot must be under exactly one sub-sign.
4. Keep the interior at or under `ShopKit.Budget` (400 parts, count with `ShopKit.CountParts`) and the whole shop with boxes under `GameConfig.StorePartBudget`.
5. Spec: copy `tests/StoreInterior.ToolShed.spec.luau`, change `KIND` and the builder path (it checks the budget, the signs and their phone legibility, one stand per placement in its tier colour, warm modest lights, no big Neon, looks-only, inside the room, and the store budget).
6. Preview: copy `tools/preview/scenes/store-toolshed.luau` to `store-<store>.luau` (views are always 1 entrance, 2 tier-stand, 3 phone, 4 night; extra views from 5). Render `bash tools/preview/shoot.sh store-<store> 1 1920x1080` (and 2, 4; view 3 at `667x375`), inspect each image up close, and copy them to `previews/store-interiors/<store>-{entrance,tier-stand,phone,night}.png`.
7. Hearth & Home's side aisles are 3.2 studs and the lanes are pinned by `ShelfLayout.spec` and `StoreStock.spec`; do not move lanes to widen them (Awaiting Connor).

**Tool Shed (pilot)**: header "AXES & BELTS" over the west table and "MACHINES" over the east one, sub-signs AXES, BELT KIT, SAWMILLS, PLANERS & SAW (the four groups cover all 21 slots); a tier stand per slot (axes T2 to T8, sawmills T1 to T5, planers T1 to T4; belts, Sky Bin and chop saw have no tier, so a category-colour stand and no flag); lock chips on axes ("NEEDS STEEL" over Hardened and so on); a CHECKOUT plaque on the counter with a keeper mat; 8 warm lanterns on a 4-beam, 1-rafter timber frame, the signs hung from collar ties up in the barn (y 15.2); a stock corner with the real Crate and Barrel meshes (parts first, swapped in). Interior parts: about 245 (budget 400, `StoreInterior.ToolShed.spec`). Preview renders (scene `store-toolshed`, roof off): `previews/store-interiors/toolshed-entrance.png`, `toolshed-tier-stand.png`, `toolshed-phone.png` (667x375), `toolshed-night.png`, and `contact-sheet.png` (`python3 tools/preview/store_contact_sheet.py` rebuilds it from every store's PNGs). The white blown-out blocks (over the door, at the table fronts) in the first pilot renders were NOT interior parts: they are lamp blocks baked into the Tool Shed barn GLB (the shell mesh). `GameConfig.TownMeshes` is false today, so the game shows the part-built shell and no such blocks; the preview scenes now set `TownMeshes.Enabled = false` for the shell to match (`opts.townMeshes = true` brings the barn GLB back). Interior lights and Neon are capped by `ShopKit.MaxLightBrightness` (1), `MaxLightRange` (22) and `ShopKit.NearWhite` (no near-white Neon), checked for the whole shop in `StoreInterior.ToolShed.spec`. Headers hang over mid-lane (z -8) from collar ties so they read from just inside the door; sub-signs never hang in the first 6 studs of a lane (`ShopKit.SubSetback`) and sit toward the wall.

**Dealership (branch `phase-2/store-interiors-dealership`, draft PR on the kit branch)**: the showroom hall in the same look. The hall is 154 x 61 studs, the lobby (door, counter, keeper) at the west end, the two rows of bays east of it; `Art/DealershipLot` still owns the vehicles, plinths, name signs and boxes (stock, order, prices, lanes, bays and footprints are untouched). `ShopInteriors/Dealership` now builds: a warm maple plank floor with a deep-blue runner down the central aisle and the lobby (the Dealership keeps its blue), timber beams and four rafters (none over the logging rig's crane), 17 warm lanterns under the kit caps (0.9 / 16, none beside a header), a SHOWROOM board over the lobby, a big header over each run of one kind of vehicle in a row (TRUCKS, TRAILERS: the bays are price-ordered so a kind can come back, five runs today, built from `DealershipLot.Layout`, so the signs follow the stock), turned to face the door end so they read from the lobby and down the aisle, a sub-sign over each bay saying what it hauls ("BED: 12 LOGS", "NO BED", "+12 BED SPACE": ShopLogic's own words), the CHECKOUT plaque and hung board over the counter with the keeper's mat, and the lobby's racks, reception corner, plants and a crate and barrel corner (real meshes, parts first). Tier stands: in `DealershipLot` each plinth gets a tier-colour band on its aisle face and a tier-colour aisle stripe, and a T-flag on a brass post beside its box (`StoreTier.Of`: price rank within trucks (T1 to T5) and trailers (T1 to T3), display only), with the item's hover tag on the flag and post; a lock chip (and the `StoreStand` tags `StoreStandState` greys) is built when `StoreTier.LockOf` names a lock, and none does for a vehicle today (the catalog has no vehicle stage), so no vehicle is drawn locked. The display vehicles' Neon lamp lenses (the live trucks' pale `#FFE9B0`, near-white) are warm amber on the display copies only. Interior 218 parts (budget 400, `StoreInterior.Dealership.spec`); the lot is 528 parts (was 496). Preview scene `store-dealership` (`_store.luau` gained an optional `populate` hook for the lot): `previews/store-interiors/dealership-entrance.png`, `dealership-tier-stand.png`, `dealership-phone.png` (667x375), `dealership-night.png`, and the rebuilt `contact-sheet.png`. The Logging Rig's crane (y 16.5) stands taller than the hall's 15-stud ceiling: that is the existing vehicle art, not moved here (Awaiting Connor).

**Pinned number moved (design moved), Dealership:** `BuildingArt.spec` whole-shop part cap for the Dealership 250 to 400 (the hall is 347 parts now; its interior alone has the 400 budget in `StoreInterior.Dealership.spec`).

**Pinned number moved (design moved):** `BuildingArt.spec` whole-shop part cap for the Tool Shed 250 to 400 (the shop is 366 parts now; the interior alone has the 400 budget in `StoreInterior.ToolShed.spec`).

**Sparkworks (kit applied, branch `phase-2/store-interiors-sparkworks`)**: header "BELTS & INPUTS" over the west unit (sub-signs BELTS, INPUTS) and "LOGIC & OUTPUTS" over the east one (GATES & TIMERS, OUTPUTS, LASERS); the five sub-signs cover all 21 slots (4 belt fittings + 17 logic pieces) once. A stand per box in its category colour (belts yellow, logic spark teal); belts and logic pieces have no tier in `StoreTier.Of`, so there are no T-flags and no lock chips (display only, nothing gated). Brass CHECKOUT plaque on the counter plus a brass board over it (own `HeaderSign`, 9.6 high, clear of Juno's name tag), 8 warm lanterns, 3 beams and a rafter, copper conduit and fuse boxes on both wall panels, wire spools and real Crate and Barrel meshes (parts first) in the back corners. Interior parts: 162 (budget 400, `StoreInterior.Sparkworks.spec`). Previews (scene `store-sparkworks`): `previews/store-interiors/sparkworks-{entrance,tier-stand,phone,night}.png`.

**Awaiting Connor** (defaults used): (1) tier flags are posts with a flag at 40 degrees to the aisle over each box (the plinth is only 0.3 tall, so a badge on it would not read). (2) Vehicles get tiers from their price order within trucks and trailers (the catalog has no vehicle tier). (3) A plan shows a badge only when it needs plot tier 2 or more. (4) Locked means axes in order and gear for a later stage; nothing else is gated in the stores today. (5) Hearth & Home side aisles stay 3.2 studs. (6) The preview takes the roof off (a roofed interior renders black in the preview; the game's Lighting lifts it), so judge the light by the caps (0.9 / 16) and a Studio look.

**General Store / Hearth & Home (branch `phase-2/store-interiors-hearth`, draft PR into the kit branch, look-and-layout only)**: `ShopInteriors/HearthAndHome.luau` in the new look. Headers GEAR, BUILD PLANS, HOME PLANS, LAMPS (over mid-lane at z -12.5, y 12.3, from collar ties under the flat roof); sub-signs WEAR & LIGHT (all five gear), SHED & YARD and INDOORS (west plans), HOME DECOR and FIRE & LAMP (east plans), LAMP POST; every one of the 20 slots is under exactly one. A tier stand per slot (gear T3 to T5 with lock chips; plans and the lamp post have no tier, so a category-colour stand and no flag); 8 warm lanterns on 5 beams and a rafter; a CHECKOUT plaque and keeper mat on the counter; plants at the front corners; a crate and barrel corner (real meshes, parts first); the old wall shelving behind the gear and lamp units kept. Interior parts 189 (budget 400, `StoreInterior.HearthAndHome.spec`); whole shop 302. Lanes, stock, prices, footprints and the 3.2-stud side aisles are untouched: the aisles read open because nothing hangs below y 9 in them and the lanterns are over them at y 11. Backward-compatible additions to `ShopKit.SectionSigns`: `cfg.subShift` (default 1.3, as before) and per-section `subAbove`, `subW`, `subStagger` (all optional, defaults as before), so two sub-signs in one 9-stud island stand side by side instead of hiding each other from the door. Pinned number moved (design moved): `BuildingArt.spec` whole-shop cap for HearthAndHome 250 to 350. Previews (scene `store-hearth`, roof off): `previews/store-interiors/hearth-entrance.png`, `hearth-tier-stand.png`, `hearth-phone.png` (667x375), `hearth-night.png`, and the contact sheet. Not seen in Studio.

**Hearth & Home polish (branch `phase-2/store-polish-hearth`, look only; no price, item, stock or buy-flow change)**: street side (`ShopFacade`): stone plinth, timber corner posts, cornice, green shutters and flower boxes on the windows, two wall lanterns clear of the door leaves, roof shingle strips, two windows in each side wall, a flagstone path to the door with a lamp post each side (all looks only, lights 0.9 / 14, shadowless). Inside: a HEARTH & HOME name board over the counter, four lamps and two beams over the back half (no dark corner), a plank ceiling fills the 0.6 stud between the beams and the roof (the sign ties and the entrance lamps used to hang under the roof with nothing above them) and every lamp chain ends on a beam, and the lock chip stands on its flag's backing (it floated 0.1 above it, in every store). New specs in `StoreInterior.HearthAndHome.spec` (nothing floats, name board, signs do not overlap, back corners lit, street lights under the caps). Signage thinned (Connor: too many signs, too close): the six small category sub-signs are gone (headers, T-badges, unlock labels, item name tags and the checkout stay); interior boards 15 to 10. New `tests/StoreOverlap.HearthAndHome.spec.luau`: oriented-box (SAT) overlap checks over the whole shop plus a stand-in per stocked box (signs vs signs, signs vs building and fittings, props vs props, props vs shell; about 47,000 pairs) and screen-space checks from the door, phone, entrance and street cameras. It found and I fixed: the hours board buried in the wall over the door (now on the wall's face, above the awning), the porch lantern inside its post, the wall-shelf panel inside the shelf units, the path stone on the doormat, and the lock chip floating over its flag; flag chips narrowed 3.0 to 2.6 and back lamps moved so nothing stacks on screen. Part cap: the whole shop is 345 parts, inside the existing 350 (no cap change); the StoreInterior.HearthAndHome spec no longer wants sub-signs (design moved). Connor's reference screenshots never arrived: designed to the written brief. Previews: `previews/store-polish/hearth-*.png` (scene `store-hearth-outside` for the street side; `store-hearth` for the inside, views re-aimed). Not seen in Studio.

## Robustness and performance pass (branch `phase-2/robustness-pass`, 12 October 2026, draft PR, no visuals, no prices or balance)

Measured in Lune with work counters (Studio is slower; nothing here has been seen in Studio). Every change has a spec that fails without it.
- **Flaky spec.** `TerrainStaged` "the second stage yields as it goes" asserted more than 100 yields, but the terrain builder yields when `os.clock()` passes its slice (12 ms, 30 ms): a fast CI runner finished the 100 flat chunks inside the slices and yielded fewer times (it failed once on #159, passed on re-run; with a clock that never advances the spec fails every time). The spec now injects a clock that moves 4 ms per read (like `ModulesReady.spec` injects `task`), so the count is exact. The assertion is unchanged. Other specs that read the real clock or random: `ClientFreeze.spec` (longest stretch < 100 ms and < 50 ms against 8 ms slices) and `TownTrees.spec` (planning < 1 s, about 30 ms measured) keep a wall-clock bound with a wide margin and are listed as the only remaining timing assumptions; `os.time()` in `ForestService`, `TreeService`, `PlotService` specs compares against a window of 1 s or more (a second boundary cannot break it); `math.random` appears only in `SaveNowLogic.spec` (a uid with no collision check) and a source grep in `WoodFX.spec`; `NPCTalkService`, `BoxService`, `GondolaService` read `os.clock()` and pass the same value on.
- **`CanopyFade`** asked every tree under `TimberlineMap.Trees` for its `HomePivot` ten times a second (1,500 attribute reads a look at 1,500 trees). Now `Shared/TreeIndex` (a 48-stud grid, pure) is kept up from the folder's children (new trees learned 150 a look, gone ones dropped) and a look asks only the trees in the cells round the two sightlines: 4 attribute reads a look at 1,500 trees, at most 10 trees visited. `TreeIndex.spec` pins that it returns exactly what a scan with `CanopyLogic.NearSightline` returns; `CanopyFadeWork.spec` counts reads.
- **`PromptUI.Start`** walked every descendant of the workspace in one frame and ran an `IsA` call for every instance added afterwards. Now the listener is connected first, the scan runs `PromptUI.ScanPerFrame` (4,000) instances a frame on its own thread, and only a `ClassName` read is done per instance (`PromptUI.spec`: 50,000 instances, at most 4,000 of work between waits, same prompts restyled, nothing else touched). Not done: tagging every prompt through `InputKit.PromptDefaults` (a file this lane does not edit; 5 prompt creators do not call it).
- **`RegionWake`**: the pass over ~1,400 trees every 0.75 s is now sliced (150 trees a frame), skipped while the players are where the last finished sweep saw them, and looks each player's region up once a sweep (`RegionLogic.Heres` / `KeepTreeWith`, the same answers as `KeepTree`), and a tree that is planted is put where the last sweep's players want it in the same frame (a beat later, so the placer's attributes are on it) instead of staying in the workspace, replicated, until the next sweep parked it. `RegionWake.spec`: same parent for every one of 1,400 trees against the old rule for three player layouts, at most 150 trees a frame, zero work when nobody moved, a far new tree parked in one move.
- **`DialogueService.watchKeepers`** hooks the models tagged "NPC" (the ones there, then the tag's added signal) instead of walking the workspace and listening to every instance added; NPCService tags every keeper and is the only maker of a Talk prompt (`KeeperWatch.spec`). **`SkyForgeService.V1Init`** walks the map once and listens only to `TownScenes`, where MapBuilder puts the court (the only maker of `TemperSpot`, pinned by a source spec).
- **`ClientReady`**: the listener is `ClientHandshake.Bind`, connected as soon as the remotes exist, before the first service's Init. The first fire marks the player ready at once; the resend of state waits for `Handshake.SetResend(resendState)` and goes out for everyone who asked (`ClientHandshake.spec`, and a source check that it is bound before the first Init and only once).
- Notes, not changed: `ClientFreeze` and `TownTrees` wall-clock bounds (above); `GameServer` still waits for the world in one thread before any service starts; the forest planter adds ~1,400 trees into `TimberlineMap.Trees` (every `ChildAdded` consumer, `TreeService` among them, is called once per tree).

## Client boot and first minute audit (branch `phase-2/fix-client-audit`, 11 October 2026, draft PR)

Goal: a new player is playable within about 15 s of joining on phone, PC and Xbox. Method: read the whole client boot (`Client.client` controller order, every `Start`, `LoadingScreen` / `JoinFlow` / `ClientReady`, HUD build, per-frame loops, tagged-instance handlers), and measure the pure parts in Lune (a counter in the `pause` hook; Studio's client is slower than Lune, `WorldPlan.Trees` was 6 s in Lune and 11 s in Studio). Nothing here was seen in Studio. Fix status: FIXED (this PR), THEIRS (in another agent's open branch: `fix-load-meshes`, `fix-client-freeze`, `fix-startup-errors`, `fix-first-screen-ui`, `fix-world-first-look`), TODAY-RISKY / NOTE (listed, not changed).

| # | Severity | Where | Evidence | Status |
|---|---|---|---|---|
| 1 | blocks play (a multi-second freeze right after the card fades) | `ForestFiller.Start` ran the filler plan steps one per frame with no slicing: `WorldPlan.Scenery` 2.1 s, `BoulderClusters` 0.6 s, `CountryStands` 0.5 s, `ForestTrees` 0.4 s, filler clutter 0.9 s in Lune, plus a one-off 0.3 s coast scan | measured before #155 with a counter in the pause; found at the same time as `fix-client-freeze` and fixed there (`WorldPlan.WithPause`, #155). With #155 merged I re-measured: the worst gap between pause offers is 53 ms in every step (the 62,480 offers in `Trees` included) | FIXED in #155 (my duplicate change was dropped on the merge) |
| 2 | hitch every 0.25 to 0.5 s on phones and "Lower", memory growth on every device | `TreeCosmetics`: with the accents off (low and medium) `clearAccent` ran `tree:GetDescendants()` on every streamed-in tree on every pass (an estimate of about 1,000 trees inside the 640-stud streaming radius, 2 to 4 passes a second, 40 to 100 descendants each; the tree count was not measured in Studio); a season change or the spawn trees arriving repainted every tree in one frame; five tables keyed by tree and part were strong, so every tree that ever streamed in (and each canopy part's colour) stayed in memory for the session | `tests/TreeCosmetics.spec.luau`: 0 `GetDescendants` over 20 low passes of 300 trees; a pass dresses at most `PerPass` (24); a stump stops being searched after 5 passes; the tables are weak (the spec fails with strong tables) | FIXED |
| 3 | long load (client) | `AmbientLife.zones` and `WeatherController.shelterZonesNow` called `NatureData.FromWorldPlan` at Start: `GroveDiscs` builds the first 322 trees (0.68 to 0.74 s in Lune) in one frame | measured `WorldPlan.FirstTreeCount()` | FIXED in #155 (weather start off the plan, `NatureData`) |
| 4 | hitch | `WorldPlan.Trees` step: up to 0.9 s between two pauses inside `TreeFill.Extra` | counter in the pause before #155; after it the worst gap is 38 ms | FIXED in #155 |
| 5 | minor | `LightingController` and `CarryController` waited for `TimberlineMap` (and the sell area) with no timeout inside their own threads: an "infinite yield" warning if the map is late, a thread that never ends if it never comes | read | FIXED (bounded 120 s, then a warning and no sell prompt) |
| 6 | minor | `WeatherController` `watchMapEmitters`: the same bare `WaitForChild("TimberlineMap")` | read | FIXED (bounded 120 s) |
| 7 | minor | `CanopyFade.look` loops every child of `TimberlineMap.Trees` 10 times a second (2 on Lower) doing a `GetAttribute("HomePivot")` and a sightline test per tree; fine at a few hundred trees; an estimate of a few ms at a thousand on a phone, not measured | read | FIXED in `phase-2/robustness-pass` (a grid by trunk position, `Shared/TreeIndex`) |
| 8 | minor | `PromptUI.Start` walks `workspace:GetDescendants()` once and `workspace.DescendantAdded` calls `restyle` for every instance that ever streams in or is built (the filler forest too); each call is one `IsA` | read | FIXED in `phase-2/robustness-pass` (scan sliced, `ClassName` check) |
| 9 | NOTE | `ForestFiller` slices the plan at 8 ms a frame (`PLAN_SLICE`) for 20 to 40 s on a phone after joining; the ring forest appears gradually and the frame budget loses about a quarter meanwhile | read | NOTE (a lower slice on the Lower tier is a one-line change if Studio says it hitches) |
| 10 | NOTE | `LoadingScreen` gives up at 30 s (`MAX_SECONDS`), the goal is 15 s; the server's gates (`JoinFlow.GateWaitSeconds` 90, `ClientWaitSeconds` 12) decide when a player is let in | read | NOTE (server side and the mesh load are `fix-load-meshes`) |
| 11 | NOTE | `Client.client` indexes `ReplicatedStorage.Shared` without waiting, as every module does; it has worked in Studio and is the same assumption everywhere | read | NOTE, not changed |

Checked and fine (no change): every `Net.Remote("X")` name is in `Net.RemoteNames` (so no remote waits forever); the controllers' `Start` waits (the `CoreLoop` attribute is set before the build, `Net.Remote` waits for the remotes the client cannot talk without anyway); `ClientReady` goes out when every `Start` has returned or after 20 s and the server never waits more than 12 s; every other `WaitForChild` is `PlayerGui` or has a timeout; the per-frame loops are all on `CosmeticHz` (`TownFX`, `WindSway`, `AmbientLife`, `RegionFX`, `LifeFX`, `CanopyFade`, `TownMarkers`, `ForestFiller`); `TreeFX` returns at once under the v2 loop; the join screens take turns through `PickerSequence`; `UIArt` preloads one image a thread; B closes every started panel (`LeaderboardUI` is not started); all client modules together load in 0.64 s in Lune (`WorldPlan` 0.32 s of it).


## Load takes 5 minutes: the world build no longer waits on meshes (branch `phase-2/fix-load-meshes`, 12 October 2026, draft PR)

Connor's bug report items 1, 7 and 9. His Studio log: `[MapBuilder] 4. The shops done in 300.2s`, `meshes: 476 of 685 loaded
... (timed out)`, `[BaseBoot] no Remotes folder`, `GlowWire has no MeshTemplates model`.

- **Cause (item 1).** `MeshKit.Create` yielded in `CreateMeshPartAsync` for every mesh that was not cached yet. The shops, the
  buildings, the townsfolk and the trees all call it on the build thread, one mesh after another, and the 24 preload workers
  already held the asset quota (a load is about 0.4 s of network time). 685 serial loads is minutes, and the preload timed out
  at 40 s with 476 in. NPCService (up to 40 s) and PlotService (3 s) also waited on loads by design.
- **Fix.** `MeshKit.Create` never yields: an uncached mesh is `nil` at once (the caller keeps its part-built art, as for a
  failed load) and is requested in the background. Every dresser runs inside `MeshKit.Attempt(model, step)`; a step that failed
  only because meshes were still loading is run again when every mesh it missed has landed, a few ms a frame (`MeshKit.Pump`,
  `SwapBudget` 4 ms), in the frame it was built in for the dressers that write absolute coordinates. A failed mesh never
  retries. The old yielding call is `MeshKit.CreateAwait`, fenced to `ItemMeshes.LoadAsync` (its own thread). Wired:
  TownMeshes (Dress, Adorn), NPCMeshes, VehicleMeshes, TreeMeshes, AxeArt, NatureArt (rocks, mine mouth), RobuxBoxArt,
  KitMeshes, LogicItems (machines). MapBuilder starts the preload with `MeshKit.PreloadAsync` and no longer probes a mesh;
  NPCService no longer joins a preload; `PlotService.Init` no longer waits 3 s for the plot kit (pads are built part-built and
  redrawn when it lands, as before). The `meshes` gate is not a first-player gate.
- **Timings.** `Shared/BuildTimings` records every top-level build step; at the world gate MapBuilder prints
  `[MapBuilder] build phases that gate play:` (seconds per step, slow ones flagged) and `gating build X of 15s budget`, and
  warns with the slowest step if it is over. `Gating build` is terrain, town, shops and the rest before SellArea goes in.
- **Client.** The loading card never waited on meshes (it waits for a character, the save and `game:IsLoaded()`, 30 s cap);
  the only client preload is UIArt's own thread. The client's dressers (AmbientLife rocks and mushrooms) were blocking its
  render thread the same way; they are now non-blocking too. Pinned in `tests/BuildBudget.spec`.
- **BaseBoot (item 7).** Name and parent were right: GameServer makes `ReplicatedStorage.Remotes` only after the world is
  built (it waits up to 600 s for SellArea), and BaseBoot waited 60 s. With a 300 s build it gave up at +60 s and `SaveNow` and
  `PaintAllType` were never bound. It now waits `Net.RemotesWaitSeconds` (600, as long as GameServer waits for the world).
  `tests/BaseBootWait.spec`.
- **GlowWire (item 9).** No GLB for it exists on `phase-2/v1-glb-sources` or main (no GlowWire anywhere in `assets/glb`) and it
  has no `MachineMeshes` row, so there is nothing to make a template from. Its part build is by design: the fallback is silent
  and said once at debug level (`LogicItems.Debug` prints, `LogicItems.DebugSink` for specs). Pieces that have mesh art and
  lose it still warn. Pending: a GLB for the Glow Wire (a 3.4 x 0.28 neon bar on two iron posts, footprint 4 x 2).
- **What is proven here and what is not.** Lune cannot load meshes, so `tests/BuildBudget.spec` holds the engine load: a
  685-dressing build returns with zero loads run and without yielding, then the meshes land and every dressing swaps in (part
  built, then load, then swap), batched. A source scan fences who may call a yielding load, and a failing spec means a build
  step awaits a mesh. The real timings (play within 15 s, meshes popping in without a hitch, the swap of a shop and an NPC
  in place) need Studio: PHASE2_NOTES.md "Load: meshes never block the build".
## Server audit: game-breaking and long-loading bugs (branch `phase-2/fix-server-audit`, 11 October 2026, draft PR)

Goal: a new player playable within about 15 s of joining. Traced the server boot and a new player's first 60 seconds end to
end; measured the pure build code in Lune. Full findings (severity, file:line, evidence, status): PHASE2_NOTES.md "Server
audit". Fixed here:

- **Long load: the terrain.** The "terrain" gate sat behind all 100 chunks (about 0.54 s a chunk in Lune, 54 s; most of the
  wait for a first player). `TerrainBuilder.Build` now takes `{ nearRadius, firstSpots, sliceSeconds }`: the chunks touching a
  230-stud disc round the sawmill block (the spawn, shops, sell area, Murph, the tutorial grove), the rest comes back as
  `finish`, which MapBuilder runs after the world gate in 16-column blocks (about 1/16 of a chunk, one a frame), the
  plot pads' ground first, then outward, the caves last. New gate `terrainFull`; `LoadState.Track("terrain")` keeps "fully
  built" honest. `TerrainGen.WaterLevelFor(x, z, h)` stops `WaterLevelAt` recomputing the height the builder already has
  (about a third of the time of writing the terrain).
- **Long load: the save.** GameServer connected PlayerAdded only after the world and every service, so the DataStore
  load began then. `ProfileService.Prefetch` (PlayerAdded at the top of GameServer) starts it on arrival; `LoadProfile`
  picks it up; `PrefetchLeft` releases the session of a player who left before the join flow had it.
- **Plots lookups.** `SkyForgeService` and `MiningService` looked for `Workspace/Plots`; PlotService builds
  `TimberlineMap/Plots`. Trophies never appeared, mining never found a plot, and a thread waited 120 s.
- Not done, in other lanes or too risky for today: see the PHASE2_NOTES list (BaseBoot's 60 s wait for Remotes is the
  fix-load-meshes lane; the town settle at the start of the terrain, about 4 s, is left alone).

## First screen UI fix (branch `phase-2/fix-first-screen-ui`, 11 October 2026, draft PR)

Connor's bug report PART B items 10 and 11 (PC window 963x478, phone 667x375, Xbox). Nothing seen in Studio yet; the
previews are composites (the engine viewer cannot draw UI): `previews/fix-first-screen/` (`before-*`, `after-*`,
`closeup-*`, `markers-sell-logs.png`, made by `python3 tools/preview/first_screen_ui.py`). Studio checks: PHASE2_NOTES.md
"First screen UI fix".

- **Join flow.** The save picker only opens when two or more saves have been played (`JoinPickLogic.AutoPick`); a brand
  new profile or a single save loads straight in (`SaveSlotService.PlayerJoined` plays it and asks for its pad). One played
  save that is not the last-played slot still shows the picker (a swap would spend the 120 s cooldown). The tutorial
  (tracker, Murph's card, the beacon) waits for the pick (`JoinPickLogic.TutorialWaits`, `QuestUI`).
- **Saves panel layout.** `SaveSlotLogic.Layout` / `Panel`: the panel is as tall as its cards, never taller than the screen;
  while joining there is no Unload base / Save now row, so the cards sit right under the note (no empty gap); a card is one
  94 px block (name and a 44 px PLAY side by side, facts under them) so all three fit on 963x478 and 667x375, and the list
  scrolls on a window too short for the SAVES panel's extra row.
- **Hint bar.** The bottom row (hint and load chip) hides while the picker is up and while the SAVES panel is open
  (`HUD.HoldHint`, `JoinPickLogic.HintHidden`).
- **HUD overlap.** BADGES waits for the end of the tutorial (`HudRules.BadgesButton`); Murph's portrait circle stays hidden
  until his head is in it; side buttons with a mark start their label after the mark and left-aligned
  (`HudLayout.MarkTextLeft`); the tutorial beacon slides clear of HUD boxes or hides (`HudLayout.ClearOfRects`,
  `HUD.Obstacles`) instead of being cut off behind SAVES; the town markers have a cream rim (SELL LOGS was a dark blob
  on dark forest); an NPC's name tag hides whole if any of its ends or its top is behind a wall (`TextAnchor.Probes`).
- **Not found / not reproduced.** The "S behind the icon" and the "empty outlined box" could not be traced to one cause by
  reading the code (the old label math put the text clear of the mark at 110 px); the box may be Roblox's own chat window.
  Studio checks 7 and 9 ask Connor to confirm or send a screenshot.
- **Awaiting Connor** (defaults used): picker only with 2+ played saves; the tutorial text starts after the pick; BADGES
  hidden while the tutorial runs.

## V1 hardening: exploit guards and performance (branch `phase-2/v1-hardening-guards`, 11 October 2026, draft PR)

Launch items 2 and 3. Audit first, then only what was missing.

- **Exploit guards.** `tests/RemoteGuards.spec.luau` classifies every remote in `Net.RemoteNames` (a new one fails until it
  is added to the table), proves each handler's file connects it and spends its own `RateLimiter` budget, that every payload
  parameter is typed `unknown`, that no budget is over 8 a second (sell, buy, build and grab are pinned tighter), that spam
  is dropped quietly and a flood is kicked, and that the v1-loop remotes connect only under the v1 loop. Bad-payload tests
  (NaN, infinity, huge, negative, long, missing, wrong class, far away, someone else's plot or box) sit in the family specs:
  ShopService, PlotService, GrabService, BoxService, SectionTrees, MiningService, PermissionLogic.
- **Fixed in the audit.** A NaN distance passed every `distance > reach` check (the comparison is false): box opening
  (BoxLogic, BoxService), box unpacking, the Sky Bin, Grab, Chop, node mining and the Hermit now use `not (d <= reach)`.
  Chop and Dialogue no longer write a log line for every rate-limited request (a flood could fill Output).
- **Loose caps.** Wood already had `MaxWoodPiecesPerPlayer` 150 and `MaxWoodPartsServer` 2500 (oldest unowned first).
  New: `WoodService.Hooks.onBed` was never wired, so wood on a truck bed aged out and could be capped; GameServer now wires
  it to `TruckLoad.BedOwner`, and a bed piece is never capped away. New: `Shared/LooseCaps` plus
  `BuildMaterials.EnforceCaps` cap slabs, ore chunks and ingots (`MaxLooseMaterialsPerPlayer` 64, `MaxLooseMaterialsServer`
  400), oldest first, never a held or boxed one, run each second from `WoodService.Hooks.afterTick`. Saved plot items and
  `plot.loose` records are not in the world, so they are never candidates.
- **Streaming.** Reviewed, not changed: Improved, PauseOutsideLoadedArea, min 128, target 640, Opportunistic stream-out.
  `tests/StreamingSafe.spec.luau` pins them and scans the client for unsafe world lookups (none found). Plots, items,
  wood, trees and trucks stay Atomic; the town anchors the client waits for are Persistent (MapBuilder.spec).
- **Phone profile.** `tests/PhoneProfile.spec.luau`: a 667 x 375 touch-only phone runs the low tier; part, mesh and light
  budgets, effects and tap sizes are pinned.
- Studio checks: PHASE2_NOTES.md "V1 hardening: exploit guards and performance".
## V1 launch hardening: saves and the server (branch `phase-2/v1-hardening-saves`, 11 October 2026, draft PR)

Launch hardening items 1 (save safety) and 4 (server). Audit first; only the gaps were filled. Studio checks: PHASE2_NOTES.md "V1 hardening: saves and the server".

- Already there, untouched: session locking and takeover, load and final-save retries with backoff, parallel BindToClose saves, autosave every 120 s (all in the vendored ProfileStore, used through `ProfileService`), `LeaveCommit` (once-only commit that the shutdown save also runs), `ProfileSchema.Migrate` (idempotent) with the four old-save fixtures in `tests/fixtures/saves` and `V1Migration.spec`, `JoinSync`, Max Players 12 (`GameConfig.MaxPlayers`, `default.project.json`, `PlaceCheck`, LAUNCH.md), plot teardown and pad freeing on leave (`PlotService.PlayerRemoving`).
- Added: `Shared/Backoff` (pure) used by `ProfileService.Save` to retry a manual save that did not land (2, 4, 8 s, then the autosave); a 150 s ceiling on the join's save load (then the player is told to rejoin, never left on the loading card); `StartSessionAsync` and `Reconcile`/`Migrate` wrapped, so a failed load or a save that cannot be prepared is put back as the DataStore gave it, its session ended, and the player marked unsaveable (`ProfileService.Unsaveable`): nothing is ever written for it; `Shared/IdleLogic` + `IdleService` + client `IdlePing` (warn at 18 min, remove at 20, never in the first 5 minutes after they can play; any remote, chat, movement or key/tap/click/stick counts; off in Studio unless `workspace` has an `IdleScale` attribute); the leave order is now commit (`LeaveCommit.Flush`), then the plot comes down (`PlotService.PlayerRemoving`), then the save is released, and the plot's loose wood is a `LeaveCommit` step (`PlotService.CommitLoose`), so a shutdown save that beats `PlayerRemoving` includes it too.
- New remote `Activity` (client to server, no data, 2/s budget, the client sends at most one in 30 s). Specs: `Backoff`, `IdleLogic`, `IdleService`, `ProfileService` (new), `PlotService` (leave order).

## V1 launch hardening: settings, analytics, launch extras (branch `phase-2/v1-hardening-settings`, 11 October 2026, draft PR)

Items 5, 6 and 8 of the hardening list. The audit came first; only what was missing was added.

| Piece | Found on main | Added or fixed here |
| --- | --- | --- |
| Settings card, music and sound volume, graphics (Lower / Higher via `QualityProfile`), camera shake, UI scale, tips, Restart save, What's new, controller and touch handling | all there (`SettingsLogic`, `SettingsUI`, `QualityService`) | a CODES tab (the Camera speed row was dropped on 11 October, see Startup errors below), the four tabs on one row, the card cut to end above the jump button on a phone |
| Tutorial replay | "RESET TUTORIAL" two-press row + `QuestService.Reset` | Renamed REPLAY TUTORIAL. **Bug fixed:** a replay paid every step's `rewardCash` again; now `tutorialReplay` pays nothing (spec) |
| Save fields | `settings` table sanitised in `ProfileSchema.Migrate` | no new field: the new setting is a key in `settings` (idempotent, specced); flags for funnel, codes and the reminder live in the existing account-wide `onboarding` table |
| Funnel analytics | `MilestoneService` funnel (Joined, First chop, First sale, Claimed a plot, ...) once per player, `LogProgressionCompleteEvent` stages | `GameAnalytics` wrapper (pcall, once-ever flags), `First machine placed` step (appended: number 13), `Shared/AnalyticsEvents` (pure names, sku and amount checks) |
| Economy analytics | `EconomyService` logged every earn / spend with a sku | now through `GameAnalytics` (same events; sku cleaned, bad amounts dropped) |
| Store analytics | none | `StoreOpened` (client remote, rate limited), `PurchasePrompted`, `PurchaseCompleted` (inside the once-only receipt grant, and when a pass purchase finishes) |
| Update log | `NewsLogic` + `NewsUI` (What's new, auto once after the tutorial, also in Settings) | the lines moved to `Shared/NewsData` (content only) with a spec: lines at most 52 characters, at most 7 rows (what the phone card fits) |
| Redeem codes | none | `CodeLogic` (pure rules), `ServerScriptService/CodeData` (server only, one disabled placeholder), `CodeService`, `RedeemCode` / `CodeResult` remotes |
| Favorite reminder | none | `FavoriteLogic` + `FavoriteService`: one toast after 10 minutes of play, once ever, never in a tutorial step or a dialogue |

- **Codes.** Rewards are cash (through `EconomyService.AddCash`, so the wallet cap clamps it; a full wallet refuses without using the code) or a free crafted furniture piece (`PlotService.GrantPiece`). `CodeLogic.ValidReward` refuses any other shape, so a Robux or paid reward cannot exist. One use per player ever: `onboarding["Code:<id>"]`. Expiry is a UTC date, good through 23:59:59 UTC, compared on the server's clock; an unreadable date counts as expired. Six wrong codes in a minute lock the box for 30 s; the remote is rate limited at one a second. `CodeData` lives under ServerScriptService on purpose (nothing in ReplicatedStorage reaches a client). It ships with only `PLACEHOLDER-DISABLED` (disabled): **no real codes exist yet.**
- **Favorite reminder.** Roblox has no API that favorites an experience (`AvatarEditorService:PromptSetFavorite` is for avatar assets, `SocialService` only prompts invites), so it is a toast pointing at the star on the game's page.
- **Camera speed (dropped).** It wrote the player's own game settings, which scripts may not do ("Insufficient permissions", repeated). We run Roblox's default camera, which has no supported hook to scale its input, so the row is hidden and the `settings.cameraSensitivity` save field stays, harmless (default 1, still sanitized). `NoUserGameSettingsWrites.spec` fails if any source names those engine properties.
- Previews (composites of the UITheme layout, not engine shots; made by `python3 tools/preview/v1h_settings.py`): `previews/v1-hardening/settings-{game,scrolled,bottom,codes}-{667x375,1920x1080}.png`.
- Studio checks: PHASE2_NOTES.md "V1 launch hardening".

## Lane R: Bayou and Red Mesa (#139, 11 October 2026)
## V1 launch hardening: moderation and policy (branch `phase-2/v1-hardening-moderation`, 11 October 2026, draft PR)

Launch items 7 (moderation) and 9 (policy and purchases). The audit came first; only what was missing was added.

| Area | Found already | Missing, now added |
| --- | --- | --- |
| Player-typed text others can see | Save names: `SaveSlotService` filtered them with `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync` and fell back to the default name. That is the only player-typed text in the game: plot signs show the owner's Roblox DisplayName, blueprint names are fixed data, the town board shows Roblox names, chat is Roblox's own and `DevCommands` chat commands are owner-only; the only TextBoxes are the save-name box and the owner hub's search / amount boxes (never shown to others). | One server door, `TextFilter` (+ pure `Shared/TextFilterLogic`): `Broadcast`, `ForUser` / `ForEach` (per reader, `GetChatForUserAsync`), `TryBroadcast`; every failure is the placeholder `####` (or nil for a caller that keeps a default), never the raw text. `SaveSlotService` now uses it; a spec fails if any other server file calls `FilterStringAsync`. |
| Plot permissions | `PermissionService` / `PermissionLogic` / `EditRights` / `PlotLogic.CanEdit`: per-person flags, owner always, `SetPermission` and `VisitPlot` rate limited and validated, `VisitStep` sweeps people with visit off. `AdminService` kick / ban is the game owner's, for the whole server. | Owner-only plot **kick / ban / unban** (`PlotService.Moderate`, remote `PlotModerate`, 2 per second): a kick lasts 2 minutes (memory only); a ban is saved in the slot's `permissions` (`PermissionLogic.Ban`, no new schema field, survives Migrate) and resolves to every flag off, so visit, the Visit list, the sweep, build, grab, drive and doors (interact) all refuse it with no change at each caller. Up to 30 bans; owner and banned player get clear toasts; the game owner can't be moderated; Settings > Visitors has Kick, Ban (second tap) and an Unban list. |
| Report | nothing | REPORT tab in Settings: pick a player, pick a reason, `Players:ReportAbuse` (Roblox's report). Hidden where the call does not exist or nobody else is in the server; 44 px rows; no ButtonR2; selection ring from `UITheme.Button`. |
| Receipts | `MonetizationService.ProcessReceipt` through `ProfileService.ProcessPurchaseAsync`: receipt ids saved in `profile.purchaseIds` (last 100), granted once, `NotProcessedYet` on a failed grant, `PurchaseGranted` only after the save holding the id is written. Its spec mocked `ProcessPurchaseAsync`. | `PurchaseReceipts.spec` runs the REAL `ProcessPurchaseAsync` over a fake DataStore: answer held until the write lands, a failed write is not an answer, double delivery grants once, a throwing grant forgets the id, a player leaving mid purchase (final save carries the receipt; if it fails the answer is `NotProcessedYet` and the retry pays once), and a source scan that every Robux prompt and the only `ProcessReceipt` are in `MonetizationService` (MarketplaceService). |
| Robux list | 5 passes (2x Cash, Lux Axe, Tow Service, Timber Classic, Paint Shop) and 4 products (two cash packs, 2x Wood, Instant Delivery). **None is a random-reward box or crate**, so nothing needs hiding today. | `PolicyGate` (`PolicyService:GetPolicyInfoForPlayerAsync`, pcall, cached per player, 3 retries, strict when it fails) and `Shared/PolicyLogic`. StoreData items may carry `paidRandom` / `tradable`; such an item is hidden in `StoreUI` and refused by `BuyRobuxItem` where `ArePaidRandomItemsRestricted` (or not `IsPaidItemTradingAllowed`). `AllowedExternalLinkReferences` is read (`LinkAllowed`) but the game shows no external link. Fail safe: no answer means restricted. A receipt for something already bought is never refused. |
| Nothing needed to progress | Axe ladder skips the Robux axe; stage, gear and biome gates are cash or quests. | `NoPurchaseRequired.spec`: every paid item is classified (boost / cosmetic / convenience / side-grade), none is paid random or tradable, no ladder rung is Robux, stage gear and biome gates are cash or quest, every mining level has a free pick, the Robux truck equals the Pickup, and the gate modules never read a pass, product or the store. |

- Prices, ids and what is on sale are unchanged. Nothing was published.
- Previews (composites of the layout, not engine shots): `previews/v1-hardening-mod/` (`tools/preview/v1_mod_ui.py`), phone 667x375 and PC 1920x1080.
- Studio checks: PHASE2_NOTES.md "V1 hardening: moderation and policy".
- Decision for Connor: the report uses `Players:ReportAbuse`, which is not in Roblox's public docs but is in the engine API dump; confirm it sends a report in a live server (see the checks). If it does not, the tab hides itself or says the report failed and points at the Esc menu.

## V1: no ButtonR2 anywhere (branch `phase-2/v1-no-buttonr2`, 11 October 2026, draft PR)

Connor's instruction: remove every use of `Enum.KeyCode.ButtonR2` and move Xbox extras off the right trigger. The engine fires `Tool.Activated` on RT by itself (it cannot be remapped from script), and any script that binds or sinks RT breaks chopping. Now no file under `src/` names the button (`tests/NoButtonR2.spec.luau` scans all of it, no exemption list).

| Action | Context | Old Xbox key | New Xbox key | Why that key |
| --- | --- | --- | --- | --- |
| Chop / swing (axe, hammer, picks) | tool in hand | RT (engine) | RT (engine) | Unchanged. `Tool.Activated` fires on RT by itself; CutController now listens only to that (and the mouse). Pacing (cooldown, Keen multiplier) is the same `clickSwing` path. |
| Select a placed piece (BuilderTools) | empty hands | RT (CAS bind) | RB (`ButtonR1`) | Free in that context; RB only means Push inside the placer, which BuilderTools already yields to. Still unbound while a tool is held (LB + RB unequips). |
| Wire pick (WireTool, BUILD) | wiring | RT (CAS bind) | RB (`ButtonR1`) | X is Cut, B is Done in that list; the placer is not up, so RB is free (`InputKit.WireSafe`). |
| Grab / drag wood and boxes (DragController) | empty hands, held | RT (InputBegan read) | RB, held (`ButtonR1`) | RB was "further" while holding; that stays on D-pad up (D-pad down and LB are nearer). X would clash with world prompts (Interact/Talk/Buy), so not X. |
| Place a blueprint (InputKit target table) | placer | RT (table only) | A (`ButtonA`) | The real binding was already A (`PlaceControlsLogic`); the table now says what the game does. RB stays Push there. |

- Hints now say RB for these: wiring bar "RB pick · X cut · B done", `{grab}` was "hold RB" and the drag line "Hold RB on wood to drag it" (both now RT, see "Grab on the right trigger"), the holding line "LT + left stick: turn · D-pad: reach". RT stays in the chop hint and `{click}` ("RT to swing", "press RT"): that is the tool's own button.
- PC and phone inputs are unchanged.
- Studio checks: PHASE2_NOTES.md "No ButtonR2 (Xbox remap)".

## Sparkworks shop in the world (branch `phase-2/v1-sparkworks-shop`, 11 October 2026, draft PR)

The integration pass found that the automation pieces could not be bought in a normal game: the stock data and the buy path (PR #131) were on main, but the Sparkworks building, its shelves and its keeper were not. They are now.

- **Where**: `WorldPlan.Town().shops` has a fourth shop, `Sparkworks` (title SPARKWORKS, teal accent) at (135, 0, 132), 36 x 36 built (24 x 24 design, `BuildingArt.Scale.Sparkworks` 1.5, roof 39 x 39). East of the Mill Road (its edge is x 113, the roof starts at x 115.5), north of the East Link (z 94), west of the showroom's loading pad (x 160), on flat dry grass. Its front (-Z) faces the East Link; `WorldLayout` `SparkworksPath` (x 129 to 141, z 93 to 114.5) runs from the link's edge to the door and `SparkworksFloor` is the dirt under the walls. `TownTreeData` keeps the building (`Buildings`) and the door (`Empty`) clear of town trees. Two ornamental trees that stood on the site moved to (162, 134) and (164, 150). No economy, price or stage number changed.
- **Deviation from an older note**: the NPC table below said the Sparkworks keeper would stand on the ferry isle's dock side. A shop on another island would make the automation pieces a ferry trip away, so Juno is in town (see Awaiting Connor in the PR). The row below is updated.
- **Building**: `BuildingArt.Shop("Sparkworks", ...)` builds the same open-front barn as Hearth & Home (15 stud door, swing leaves, awning, sandwich board reading OPEN ALL DAY) with a slate roof, teal trim, a counter at the back, five spark lamps over their switches on the back wall and a WIRE IT UP board. 173 parts plus 302 for the 21 stocked boxes, inside `StorePartBudget`. Part-built: the uploaded `shops/Sparkworks` mesh (landed in #136) is the old 20 x 16 demo-board building, not this shop's shape, so the shop does not Dress with it.
- **Shelves**: `StoreStock` has a `Sparkworks` layout: a shelf unit down each side wall (`FittingShelf`, west: the four belt pieces then the first logic pieces; `LogicShelf`, east: the rest), a 10.4 stud aisle, the counter at the back. All 21 pieces (17 logic, 4 belt) fit, none overflow. `ShopInterior` builds the stepped units, two hanging boards and a copper-edged floor. `BoxService.StockMap` stocks it like the other shops.
- **Boxes**: a Logic box shows its piece's own blueprint model (`ItemModel` handled only the other kinds, so all 17 boxes were identical parcels), is accented spark teal (`BoxLook.Logic`) and opens straight into the buyer's stock (`BoxUnpack.Mode("Logic")` is `stock`, so the hammer places it). Belt pieces still open into a placement ghost.
- **Keeper**: Juno, "Wire keeper", behind the counter at (135, 0, 146), facing the door, Talk prompt like the other keepers (`NPCData`, `DialogueData` Sparkworks lines are live, `DialogueService` maps Juno to Sparkworks). No hours (`ShopHoursLogic` has no span for it: "Open all day"), so she never sleeps and the door never locks.
- **Buying**: walk in, pick up a box, carry it to the counter, Talk to Juno, Yes (the same flow as the other three counters). The server charges `StoreStock.UnitPrice`: the one price, in the v2 loop only, on a player with a plot (`needsLand` otherwise), through `EconomyService.SpendCash`.
- **What's New** now says "Sparkworks sells logic pieces, belts and lasers." / "Up the road past the Land Office. A plot first."
- **Not done**: no map chip on `TownMarkers` for it, no sign on the street (the name board over the roof is what you see from the East Link), the old demo board (`LogicService.BuildDemo`) is not in the shop (the shelves stand where it would), no uploaded mesh.
- Specs: `tests/SparkworksShop.spec.luau` (world placement, the shelves, the keeper, the talk box, the box stocking and pay, the buy rules for every piece, What's New). Previews: `previews/v1-sparkworks/`.

## Lane R: Bayou and Red Mesa (branch `phase-2/v1-r-regions`, 11 October 2026, draft PR)

The two reserved regions are filled. Each has its own wood and one rare find, a signpost that says what it needs, and a small build of part-made art (built-in materials, the Art Director palette, no uploads). Numbers: `Shared/Regions/BayouData`, `MesaData`; rules: `MudLogic`, `QuarryLogic`, `RegionItems`, `RegionScatter`; art: `Shared/Art/RegionArt`; server: `RegionService`, started by `RegionBoot.server.luau`.

- **Bog Cypress** (Bayou, Stage 2, the Steel Axe): log $6/u³, plank plan 60, hardness 8. **Ironwood** (Red Mesa, Stage 4, the Cobalt Axe or Heat Boots): log $14/u³, plank plan 70, hardness 18. Both are the last two rows of `WoodData` (the detector filter saves woods by index, so a new wood goes on the end). They are in `tools/economy`: Bog Cypress $10,529/h and Ironwood $30,010/h ideal, inside the Designer's bands ($9k to $11k, $28k to $34k), and the five headlines still hold (ECONOMY.md "Region woods"). `BiomeData` has `bayou` and `mesa` entries with `needsStage` and `gateWords`, but no `area` (they carry `region`, because every `area` switches on a family of exclusions in WorldPlan, TerrainGen and TreeFill).
- **Trees**: `WorldPlan.RegionTrees()` plants 44 Bog Cypress (all within 120 studs of the log landing) and 38 Ironwood, outside `Trees()` like the Reach's, planted by MapBuilder. Footprints of the regions' own builds are kept clear through `WorldLayout.TreeBlocked`. Both woods are part-built trees (the generator's skeleton) until job 17 wires the uploaded meshes.
- **Mud**: four discs (B's anchors). `MudLogic.Factor` runs inside BiomeService's WalkSpeed step: 0.6x in a disc without Wader Boots; the road, the log landing, the boardwalk and the shack are dry. **Wader Boots** (`ItemCatalog.Gear.WaderBoots`, quest-only, never on the Hearth & Home shelf) cost $2,000 plus 20 u³ of Bog Cypress planks laid by the Bait Shack counter (hand-in like Gus's, cash first, atomic).
- **Quarry**: eight `SlabNode` prompts (hold 0.6 s) give one carried slab each (`BuildMaterials.ReturnSlab`: 24 loose a player, $0, the Ore Chute refuses it, the loose save keeps it). A node refills in 60 s (PROPOSAL). Needs Stage 4. B's eight anchors sat along the whole +Z rim and three were inside MesaRoad's junction circle; `WorldPlan.SlabNodes` is now `MesaData.QuarryNodes()`, eight points on the east rim.
- **Rare finds**: one prompt at each `UniqueItemSpawn` (the Bayou's stump plinth, the butte top). Both ship disabled with the line "Something rare lives here"; pickup, respawn, the one-per-frame rule and the `Region:Found:<id>` stamp in `guideStamps` are built and tested. First visits stamp `Region:Seen:<id>`, toast the region's name once and fire `MilestoneService.Event("area", { id })`.
- **Art**: boardwalk loop (47 parts), Bait Shack (26), four lanterns, mud and pools, the BAYOU mist as a `FogZone` volume (LightingController stays the only Atmosphere writer); the quarry face with its truck lot (35), the butte (three steps, truss ladders), the overlook (19, 11 degree ramp), the wedge arch (28), two lanterns; 36 and 30 scatter pieces of at most 10 parts. The ground is Limestone `#4E4A36` in the Bayou and Sandstone, Sand and a Rock rim on the mesa.
- **Re-baselined**: ECONOMY headlines 17.8 to 15.4 min, 50.7 to 48.2 min, 31.5 to 31.4 h (Builder and BuildingKit pins); scenery floor 1,500 to 1,400 parts and clusters 25 to 20 (the region discs are no longer grass); resource regions count the new trees; `LaneW` filter list and the field guide's wood list gain the two woods; the "up the list" climb test skips stage-gated woods.
- Previews (`bash tools/preview/shoot.sh v1-r-bayou` and `v1-r-mesa`, part-built trees and art, no uploaded meshes yet): `previews/v1-r/bayou-wide.png`, `bayou-dusk.png`, `bait-shack.png`, `boardwalk.png`, `bog-cypress.png`, `bayou-667x375.png`, `unique-items-bayou.png`, `region-signs-bayou.png`, `mesa-wide.png`, `mesa-arch.png`, `quarry.png`, `overlook.png`, `ironwood.png`, `mesa-667x375.png`, `unique-items-mesa.png`, `region-signs-mesa.png`. Studio checks: PHASE2_NOTES.md "Bayou and Red Mesa (Lane R)". Not done: the tree meshes and the six uploaded models (job 17), Lane E's keeper lines and region banner, badge ids (Lane X, ids stay 0).

## Lane B: world (merged, #121)

Playable square goes from 3000×3000 to 2000×2000 (`WorldHalf` 1000). Area 9,000,000 sq studs down to 4,000,000 (44%). A 200-stud skirt is generated past the edge and is not playable. Town, the sawmill (0, 110) and the spawn stay. StreamingTargetRadius stays 640.

The picture shows the 28-wide ring, four town links, the hills cross-link, the truck tunnel, the mine mouth (MINE), three hidden mouths (H), five secrets (?), the ore furnace pad and the dock. The sell station (SELL) stays at the sawmill plus (53, 1): pad and zone middle (53, 111). Trucks back straight north off MainStreet into that lane. Lane C's furnace art uses this same zone. The ore pad at (48, −110) is Lane M's, not the sell station. Region, pad and secret coordinates are in `MAP_V1.md`.

Bayou (−760, −700, radius 140) is a flat basin sunk 7 studs. Red Mesa (590, −790, radius 115) is flat at the base height. BayouRoad and MesaRoad are 28 wide and each end in a 32-radius junction with a signpost. Lane R fills both later: trees, scatter and the unique items are hooks only (`WorldPlan` anchors, including one `UniqueItemSpawn` each and the leaderboard at (−50, 0, 92) facing south). The Lanternwood grotto stays at (−240, −420); it is about 416 studs from the Bayou edge.

NPC stand spots, weather zones and critter zones (for Lanes E and G; the live modules still have the old numbers until those lanes read these):

| Who | Position | Yaw (degrees, 0 faces −Z) |
|---|---|---|
| Murph | (−25, 0, 44) | toward the spawn |
| Millie | (71, 0, 120) | toward the sell lane |
| Tink | (−84, 0, 134) | toward the Tool Shed door |
| Dale | (194, 0, 158) | toward the showroom aisle |
| Hazel | (−100, 0, 205) | toward Hearth & Home's door |
| Gus | town gondola (−40, 0, 150) | toward the isle column (680, 280) |
| Rosa, Pip, Bram | unchanged town walks | unchanged |
| Old Hank | Land Office counter | toward the door |
| Hermit | secret camp mouth (−360, 4, −90) | 180, facing the cave |
| Old Tolly | folded toll booth, east of the deck near z 940 | south, toward town |
| Capn Moss | ferry dock (860, 4, 160) | toward the isle (930, −50) |
| Odds & Ends keeper | snow junction (30, 4, 450) on the new north road, adjusted when the junction is placed | toward the road |
| Sparkworks keeper (Juno) | behind the Sparkworks counter in town (135, 0, 146) | toward the door (was: ferry isle dock side; moved into town, see the Sparkworks section) |
| Fishing scene | pond (−40, 0, −160) | toward the water |
| Campfire scene | starter edge (40, 0, −80) | toward town |
| Lookout scene | (40, 8, 820), facing the volcano | toward (450, 500) |
| Bench scene | town square | toward the mill |

Weather and critter zones (same discs Lane G should read from `ScatterZones` once that module lands):

| Zone | Kind | Centre | Radius |
|---|---|---|---|
| town | town | (0, 90) | 180 |
| starter | forest | (8, −178) | 143 |
| hills | forest | (−500, 110) | 150 |
| meadow-east | meadow | (300, −40) | 80 |
| snow | snow | (0, 720) | 115 |
| volcano | volcano | (450, 500) | 125 |
| gloam | gloam | (10, −720) | 80 |
| shore | shore | (820, 40) | 120 |
| isle | isle | (680, 280) | 100 |
| cave | cave | (150, −200) | 80 |

Preview paths so far:

- `previews/v1-b/00-overview.png` (top-down, Bayou and Red Mesa labelled)
- `previews/v1-b/bayou-top.png`
- `previews/v1-b/bayou-three-quarter.png`
- `previews/v1-b/mesa-top.png`
- `previews/v1-b/mesa-three-quarter.png`

### Map remake finish (10 and 11 October 2026, PR #121)

The ring map is now what the specs pin, not what the first draft of this file said. Where it differs from the tables above, the code wins (`WorldLayout`, `PlotData`, `BiomeData`, `UndergroundData`).

- Mine mouth: `NatureArt.CaveMouth` stands at (150, -150), door toward town, with a walkable 16-wide bore (about 18 degrees) down to the upper mine and a hill over it (`UndergroundData.Ramp`, `HillAt`). The ground at the door is 1.5 (`Ramp.top`). `tests/MineMouth.spec` walks a capsule from the tunnel floor out to open ground, checks the doorway is clear of colliders, the roof keeps rock over it and five lamps hang in the bore (shadows off).
- Starter Forest disc is (8, -178) radius 143 (it was (0, -180) radius 100): Birch Side, Oak Side and the South Link leave too little free ground for the 70 oak and 26 birch otherwise. Every plot centre stays outside the disc.
- The first tree batch is placed on the map as it is (no legacy layout), wild groves keep off the river and the forest lanes, boulders stay in the 2000 square, scenery cells are 200.
- River moved west (x about -815) so its footbridge has firm banks outside Pine Bend's yard. Lighthouse lamp at (780, 48, -240) on the sand south of the ferry. The overview picture is redrawn from the shipped layout (`tools/preview/v1b_map.py` now reads the same numbers).
- Economy headlines moved with the shorter hauls (ECONOMY.md regenerated): first sale 68 s (same), Steel Axe 5.4 min (same), first $1k 17.9 to 17.8 min, Cobalt Axe 66.3 to 50.7 min, full plot 33.5 to 31.5 h. All inside their targets.
- Previews: `previews/v1-b/mine-1.png` `mine-2.png` `mine-3.png` `mine-7.png` `mine-8.png`, `landmarks-3.png` (lighthouse), `landmarks-5.png` (footbridge), `landmarks-7.png` (lake dock), `landmarks-8.png` (coast dock).


- **End game follow-ups** (#134, 10 October 2026): the plot sign shows the owner's name first with the plot line under it, above the post that ran up over it (`PlotData.SignText`); the player-facing "Sky Pass" is "Gondola Pass" everywhere (the save keys `gondolaPass` / `skyPass` and the `SkyQuest` remote are unchanged); `BiomeData.Gate(biomeId)` returns `{ needs, words }` (sky: `GondolaPass`, "Obsidian Axe + Gondola Pass from Gus"; `SkyQuestLogic.GateWords` reads it); Keen now speeds the swing you feel (`CutController` multiplies the client cooldown by `TemperLogic.CooldownMultiplier`, read from the tool's `TemperPrefix` / `TemperTier` attributes that `AxeService.StampTemper` sets; no input code touched); `EndGameBoot` is folded into `V1Boot`. Town model check: no real problems in the part-built town the game ships. Previews: `previews/v1-end-game-followups/plot-sign-1.png` to `plot-sign-5.png`, `town-pieces-*.png`. Studio checks: PHASE2_NOTES.md "End game follow-ups".
- **Lane A2 end game** (branch `phase-2/v1-a2-end-game`, 8 October 2026, off main `ae2c3f9`): Gus's Charter (Obsidian Axe, then 120 Frostwood, 120 Emberwood and 40 Gloamwood planks laid at the town station; no cash fee) gives the Gondola Pass; Ride up needs it (ride down never does; $250 fare and 40 s ride unchanged) and a gate sign states it in words. The Sky Forge window (`ForgeUI`, new `SkyForgeService`) has Starfall, four relics ($22.5k / $37.5k / $60k / $90k once each, trophies by your plot sign), Old Bram's weekly order ($18,000 + 4 Sky Shards, Monday 00:00 UTC) and tempering (Keen / Heavy / Prosperous I to III, one family per axe, fixed costs, no Robux, not the Lux Axe). Previews: `previews/v1-a2/court-bram.png`, `previews/v1-a2/gondola-gate-gus.png`, `previews/v1-a2/isle-starfall-forge.png`, `previews/v1-a2/relic-trophies.png`, `previews/v1-a2/forge-phone-temper.png`, `previews/v1-a2/forge-phone-confirm.png`, `previews/v1-a2/forge-phone-starfall.png`, `previews/v1-a2/forge-pc-temper.png`, `previews/v1-a2/forge-pc-confirm.png`, `previews/v1-a2/forge-pc-relics.png`, `previews/v1-a2/forge-pc-order.png`. Studio checks: PHASE2_NOTES.md "Lane A2: end game".
- **V1 UI redesign** (branch `phase-2/v1-u-ui`, 8 October 2026): mockups `previews/v1-u/loading-667x375.png`, `previews/v1-u/loading-1920x1080.png` (sunset scene, the wordmark, a progress bar, one tip), `previews/v1-u/hud-667x375.png`, `previews/v1-u/hud-1920x1080.png` (in-context HUD: cash, Field Guide with its book icon, side buttons with saves/hammer/truck icons, a selection ring, a dark hint pill, and on the phone Roblox's thumbstick ring plus the jump button, with the hotbar clear of the stick), `previews/v1-u/hud-buttons-667x375.png`, `previews/v1-u/hud-buttons-1920x1080.png` (button styles only), `previews/v1-u/owner-menu-667x375.png`, `previews/v1-u/owner-menu-1920x1080.png`, `previews/v1-u/theme-sheet-667x375.png`, `previews/v1-u/theme-sheet-1920x1080.png` (Danger fill `#B23B30`; cream on danger is 4.80:1), `previews/v1-u/news-667x375.png`, `previews/v1-u/news-1920x1080.png` (the card is as tall as its rows, with a sunset wordmark; each headline has a muted second line; Close is centred, 44px on the phone, and clear of the jump box and the thumbstick). Live UI uses the same tokens (walnut, cream, amber, confirm, danger, muted; GothamBold and Gotham; radius 8; 2px stroke; 4px selection ring). Loading tips rotate one at a time from `ReplicatedFirst/LoadingTips`. What's new is seven headlines plus a short second line in `NewsLogic.Entries` (island map with the Bayou and Red Mesa, mining, blueprints, Foreman Rook's jobs, axe tempering, Sparkworks, the gondola sky island). It shows once after the tutorial (`onboarding["News:V1"]`, no new save field), and from Settings. On a short screen the card, including Close, sits right of the thumbstick and above the jump box. Owner menu, quick menu, Settings and What's new select their first button on open; B closes; none of them binds the right trigger. **Lane E:** `DailyUI` stays in the client module list, but the client does not start it, so there is no DailyUI startup warning. Lane E (Foreman) replaces that module. Studio checks: PHASE2_NOTES.md "V1 UI".
- **V1 UI round 3** (branch `phase-2/v1-u-ui-r3`, 9 October 2026; #124 is merged): the GAD skins (`UITheme.Skin`, `UITheme.Plaque`/`Panel` from frames, buttons with a 3 px edge, corner 10, shine, starter stroke), the new loading card (one plaque, Ink 45% backdrop), the phone HUD column (MENU, HAMMER, Sell here as 44 x 44 icon buttons; SAVES, Send truck home and OWNER inside MENU; `Shared/PhoneHud`) with the real icon Image ids (`UITheme.HudIcons`, PNGs in `assets/ui/icons/`), and a 44 x 44 What's New Close. Previews: `previews/v1-u/r3-hud-phone-667x375.png`, `previews/v1-u/r3-menu-phone-667x375.png`, `previews/v1-u/r3-loading-667x375.png`, `previews/v1-u/r3-loading-1920x1080.png`, `previews/v1-u/r3-news-667x375.png`, `previews/v1-u/r3-news-1920x1080.png`, `previews/v1-u/r3-hud-pc-1920x1080.png`, `previews/v1-u/r3-buttons-667x375.png`, `previews/v1-u/r3-buttons-1920x1080.png`, `previews/v1-u/r3-theme-sheet-667x375.png`, `previews/v1-u/r3-theme-sheet-1920x1080.png` (made by `tools/preview/v1u_round3.py`). Studio checks: PHASE2_NOTES.md "V1 UI round 3". Cash plaque, prompts and tutorial cards keep the UIArt image skins for now.

## Lane K wire-in: Blender machines on the plot (job 15, branch `phase-2/v1-k-wirein`, 10 October 2026, draft)

The uploaded machine meshes are wired into the plot machines and the logic pieces. Draft PR; Connor merges when CI is green.

- `Shared/Art/MachineMeshes.luau` (data): 41 assets (25 TLD-1 line kit from the addendum, 16 older pieces TLD-1 does not cover), every piece with its real uploaded meshId, size and bounds-centre offset from the mesh origin (ground centre, +Z outfeed), plus named points (arbor, cutter, hinges, ports), the TLD-1 standard constants, the gameplay-part layouts of mills, planers and the chop saw, and the logic pieces' hinge poses. `Shared/Art/MachineSkin.luau`: Prepare (load every piece or none, log once per machine) then Commit (place, hide the covered parts, tag the blade) and Swing/PoseAbout (hinged pieces). 116 `MeshTemplates/<id>.model.json` files (every distinct id). MeshManifest has a `machines` group after job 14's `blender` group.
- Wired in `MachineArt` (mills, planers, chop saw, belts, switch, tilted, support, detector), `MiningArt` (furnace, stall, ore chute, craft bench) and `LogicItems` (Button, Lever, Plate, Wall Switch, Spark Lamp, Hatch, gates, Delay, Clock, Sustain, Sweeper, lasers via the Body/Indicator/Moving slots). Gameplay parts keep name, size, CFrame and group; mesh pieces are looks only; walls, roof and rails go see-through and keep colliding; the part build stays when any piece is missing. Tier decor is skipped under the mesh (Rickety 19 of 21).
- TLD-1 addendum section C: mills 8x12, 8x14, 10x16, 10x18, 10x26 and planers 8x8, 8x10, 8x12, 8x16 run along the feed; straight belt 6 wide; chop saw deck 5.0 wide, top 0.72, bed 52 (footprint 6 x 56). Cut maths untouched: `tests/CutParity.spec.luau` pins size and value of every wood through every tier (numbers taken from main before the change).
- Sky Forge Court: a brass `Sign` board (6 x 1.4) on the back wall reading SKY FORGE on its -Z face.
- Not done: wood stage looks (addendum D: WoodLook, TimberSawn/TimberPlaned, saved Stage; needs service and ProfileSchema edits); catalog items for ConveyorShort, Long, Reversible and BeltDrop (their meshes and templates are in). The 25 TLD-1 GLBs are in `assets/glb/machines-tld1/`; every piece offset in MachineMeshes is now read from them (sizes match the GLBs to 0.001). Real-mesh renders of all 25 plus a deck line: `previews/v1-k/tld1/`. Previews (real meshes, the older pieces only; `tools/preview/v1_k_manifest.py`, scene `v1-k`): `previews/v1-k/` has the 13 logic pieces (`logic-*.png`, `pc-gate-and.png`, `pc-lever.png`), poses (`pc-lever-on.png`, `pc-hatch-open.png`, `posed-*.png`), `pc-prospector-stall-and-chute.png`, `ore-chute-1280.png`, `pc-craft-bench.png`, the court sign (`pc-sky-forge-court-sign.png`, `phone-sky-forge-court-sign.png`) and `phone-gate-and.png`. Studio checks: PHASE2_NOTES.md "Lane K wire-in".
## Lane X: milestone badges and the town leaderboard board (branch `phase-2/v1-x-extras`, 11 October 2026)
## Lane X: milestone badges and the town leaderboard board (merged, #137)

Eight new badges (25 in all, every id still 0 until Connor pastes them into `BadgeData.Ids`): AreaBayou, AreaMesa, WoodCypress, WoodIronwood, FirstBuild, Homestead (40 filled kit pieces, a proposal), Stonemason (a filled `Sand*` piece) and Millionaire (`profile.totalEarned >= 1,000,000`). The two regions use `WorldLayout.Bayou` and `WorldLayout.RedMesa` (so they work before Lane R fills them); the build and Millionaire badges are read from the profile in `BadgeService.Poll`, so no other lane has to fire an event (a `"build"` or `"earned"` event also works). `BadgeService.OnNewArea(fn)` fires once per new area from Poll (E's DailyService subscribes to it). The town board: `TownBoardLogic` (rows, states, layout, footprint), `TownBoardArt` (ten parts, one SurfaceGui, no light), `TownBoardService` (builds it at `WorldPlan.LeaderboardBoard`, redraws on `LeaderboardService.OnRefresh`, no DataStore call of its own), `TownBoardBoot.server`. `LeaderboardService` gains read-only `Top()`, `Failed()` and `OnRefresh(fn)`. Studio checks are in PHASE2_NOTES.md "Lane X".

Lane X previews (`previews/v1-x/`; `tools/preview/scenes/v1-x-board.luau` with `shoot.sh`, and `tools/preview/v1x_badges.py` for the panel): `town-board-day.png`, `town-board-night.png`, `town-board-street-30-667x375.png`, `town-board-street-eye-667x375.png`, `town-board-closeup.png`, `town-board-empty.png`, `town-board-failed.png`, `town-board-side.png`, `town-board-back.png`, `badges-667x375.png`, `badges-1920x1080.png`. The viewer draws each label centred in its own box and has no rounded plates or medals, so row text is centred in the previews; in game it sits left of the cash line on a plate, beside a rank medal. The badge panel shots are drawn from UITheme's tokens (the same method as Lane U's).

## Lane P: purchases (merged, #133)

Branch `phase-2/v1-p-purchases`. Four Robux items carry real ids (2x Cash, Lux Axe, Small and Large Cash Pack); Tow Service, Timber Classic, Paint Shop, 2x Wood and Instant Delivery stay at id 0 (Coming soon) until Connor flips them, their ids kept in comments in `StoreData`. Prices are only ever Roblox's live answer. Pieces: the bulletin board redesigned to the approved mockup (pages of three cards and a Coming soon strip), the store panel in the GAD look, open gold crates on a two-row gold table in the Tool Shed, and stage-scaled cash packs. Previews are in `previews/v1-p/`. Creator Hub steps are in `STORE_SETUP.md`, and Studio checks are in PHASE2_NOTES.md "Lane P". Awaiting Connor: whether 2x Wood should mean twice the logs (it doubles wood value today); fitting the uploaded RobuxTable and RobuxBox meshes (job 17) to the crate table; and two-line card bodies on the board, which go beyond GAD's one line.

Lane P previews (`previews/v1-p/`, UI laid out from the real Instances, board and crates from the real scene): `store-passes-667x375.png`, `store-passes-1920x1080.png`, `store-products-667x375.png`, `store-products-1920x1080.png`, `store-gamepad-1920x1080.png`, `purchase-flow-states-1920x1080.png`, `bulletin-board-day.png`, `bulletin-board-night.png`, `board-side.png`, `gold-boxes.png`, `gold-box-closeup.png`. The bright block at the counter in `gold-boxes.png` is the shop lamp, not a crate.

## Lane H: Blender asset registry and upload list (merged, #130)

Code side of Lane H only. Nothing is uploaded, no generator was added (that waits on Connor), and nothing changes in game.

- `Shared/Art/BlenderAssets.luau`: one row per Blender model (169): 143 with their GLB in `assets/meshes` (status `repo`, meshId 0, live ids stay in the module named in `wiredBy`), 19 Lane H items from the uploaded Blender backlog (status `backlog`, wired by job 17's `BacklogModels`), 7 still to model (status `planned`, id 0). `MeshManifest` has a new last group `blender` that preloads `BlenderAssets.MeshIds()`: empty while the ids are 0.
- `assets/UPLOAD_LIST.md`: the 7 planned models (two cliff faces, shop shelf, shop counter, three temper trims) and every uploaded row. `docs/art/terrain-water.md`, `docs/art/blender-pipeline.md`.
- `tools/blender/check.py` (import limits on GLBs; all 214 repo GLBs and 217 pack GLBs pass), `registry.py`, `render_tiles.py`, `contact_sheet.py`.
- Previews (real GLBs, headless Blender): `previews/v1-h/buildings.png`, `shops.png`, `environment.png`, `items.png`, `kit.png` (unpainted base colour; paint tints it in game), `axes.png`, `gear.png`, `plants.png`, `npcs.png`, `trees.png` (crown meshes). Rocks and vehicles are not on a sheet: their GLBs are assembled and tinted by code, so the raw file is not what you see in game (see `previews/v1-g/` and `previews/meshes/truck-real.png`).

## Lane D: axes, boxes, shelves, displays (merged, #122)

Branch `phase-2/v1-d-axes-displays`, rebased onto main at `f96b62c` (A1). Connor reviews each render before this merges. Paths below are the pictures to open.

Axes, temper colours, the stepped shelf unit, window boxes and hover price colours are on this branch. The store board is not: `StoreBoard` and its spec match main, and the board scene and pictures are gone. Lane P owns a full board redesign. This branch does not type Robux prices onto the board. The shop's shelves on screen are still `ShopInterior.SteppedUnit` (lane C). `ShelfLayout.Build` is the unit those shelves should copy. Economy numbers did not move in this lane.

Keen is the speed temper (sky blue wind, `#6FB7E8`). Heavy is the damage temper (white edge sheen, `#FFFFFF`). Prosperous stays coin gold (`#F2C14E`). `TemperLook` covers exactly the prefixes `TemperLogic` exports. The neon edge, Keen's streaks and Heavy's sheen sit on the front face of `MeshHead` (its Size and CFrame after MeshKit places it). With no mesh, they use the part-built head. The Hermit's Maul has no uploaded mesh. It stays the part-built wedge (head 0.9×2.4×1.7, a flat poll, rope on the haft). It needs a Blender mesh. Do not invent one.

Part-built axe, temper and shelf pictures are not in this PR. Connor rejected them. Reshoot after `phase-2/v1-preview-meshes` is on main. The box and hover pictures are still here:

- `previews/v1-d/boxes-before-lineup.png` — five window boxes before the remake.
- `previews/v1-d/boxes-before-axe.png`
- `previews/v1-d/boxes-before-sawmill.png`
- `previews/v1-d/boxes-after-lineup.png` — the same boxes after: 0.1 accent band and a brass plate, no price.
- `previews/v1-d/boxes-after-axe.png`
- `previews/v1-d/boxes-after-sawmill.png`
- `previews/v1-d/hover-colours.png` — gold when you can pay, red when you cannot, cream when the line is not a cash price.

Awaiting Connor: the Hermit's Maul is part-built and needs a Blender mesh. The hand stays 0.75 studs up the haft (`AxeArt.GripFromFoot`, shared with `SwingLogic`). The brief's 25–30% would move that swing constant. The Lux design length is 4.0 in `AxeModels.Look`, but the gameplay Handle stays 3.5 because `tests/MeshArt.spec` pins it. Four 0.1 corner bevels on a box are not parts: `BoxLogic.ShellPartCap` is 9 and a truck already fills `BoxPartCap` 42, so bevel parts need those caps raised (lane F). The accent band is 0.1 deep and the brass plate uses the spare shell slot. Damage, range, cooldown and cash prices are unchanged.

## Lane F: building and blueprints (merged, #131)

Merged in #131. Previews in `previews/v1-f/`. What landed:

- The four new pieces (Copper Trim, Sandstone Wall, Floor, Arch) are placeable: the fill takes slabs and ingots (`BuildCost.Of`, atomic take; `BuildMaterials` server side). Unlocked, no free placement.
- `PlotService.CanEdit` (shared rule `PlotLogic.CanEdit` / `EditRights`) at every edit site: Sawmill, ChopSaw, Paint, Blueprint drop, PlotFill contributions, Vehicle, Logic, Permission. BeltService has no player edit site; its prompts live in LogicService and stay owner-only.
- 1,200 kit-part cap on NEW placement ("Your plot holds 1200 kit parts at most"); existing builds are never deleted. PlacedCap 320 and `SaveSize` measured: 886,791 -> 950,591 bytes (90.7% of 1 MB; DataStore limit 4 MB).
- Undo and Take apart refund slabs and ingots (`PlotLogic.SellPlan`).
- `PlaceControls` (phone, PC, Xbox; no ButtonR2). Furniture and `GrantPiece`: Copper Lamp Post and Gold-banded Chest, CraftData recipes enabled. Save now (30 s cooldown). Unload keeps loose wood (`LooseSave`, `LooseService`). Free-piece blueprints, Paint all of this type (free), recall fee on the button, Sparkworks counter stock (data and buy path), fallen pieces rescued (`FallenLogic`, `strandedLoad` restored), `StageOf` helper wired to `BlueprintBook.UnlockStage`.

**Awaiting Connor** (all PROPOSALS, used as defaults)

- Costs: Copper Trim $4 + 1 Copper ingot; Sandstone Wall $8 + 2 slabs; Sandstone Floor $8 + 2 slabs; Sandstone Arch $16 + 4 slabs.
- Stage unlocks: walls, floors, flat roof S1; tall walls, sloped roofs, ramp, door and window walls S2; railings, beams, posts, gate S3; sandstone S4; copper S5. Starter pieces are not gated; only the 4 new plans show as locked rows.
- `StageOf` names and the lifetime-earned fallback lines (100, 1,000, 5,000, 25,000, 100,000, 400,000, 1,000,000, 2,000,000) are guesses until Lane E's stage keys are the only source.
- Loose-wood save caps 150 pieces / 300 sections; crafted furniture stock cap 20; fall rescue below Y -80; paint is free.
- "Free" blueprints are marked on owned store unlocks only (not auto-given, which would free store purchases).
- Odds & Ends is not stocked (no building; the blasting charge is pay-at-boulder). The Sparkworks shop building, counter and keeper are in the town (see the Sparkworks section at the top).
- `mining`, `guideStamps` and `dayCounter` are account-wide in code and specs while the brief says per slot. Left as is.
- Colours: GAD palette still pending; sandstone `#C8643C`, copper `#B87333`.
- Furniture meshes are not in the lite pack, so furniture renders part-built (job 17).
- Worst case: a plot of 400 WindowWall8 is 1,600 parts; the cap now stops placement at 1,200.

Cross-lane edits: MiningService (IngotRoom, ReturnIngot), CraftingService hooks and furniture grant, CraftData enabled, HammerController paint-all row, VehicleController fee label, HintLogic build text, EditLogic, LogicService / PermissionService / VehicleService / ChopSawService rules, WoodService recover hook, PlotUI locked rows. New `BaseBoot.server` binds the new remotes and hooks. The unsharded full Lune run has a GondolaService/GrabService order dependence that is already on main.

Studio checks: PHASE2_NOTES.md, "Lane F: building and blueprints".

## Lane W: practical automation (merged, #129)

Merged. Wires from #123 now drive belts and machines. Every belt, sawmill, planer and the new line pieces register `LogicService.RegisterTarget(uid, {power, reverse})`. Ports: belts 1 power, 2 reverse; Switch Belt 1 side, 2 power, 3 reverse; sawmill and planer 1 power. An unwired port keeps the old behaviour, so old plots run as before (no new attributes, no new saved fields). Power off mid-cut pauses the log where it is and the clock resumes with power. Reverse is an owner-only prompt saved as `item.reversed = true`; Switch Belt flip is `item.flip = true`. New pieces: Switch Belt, Tilted Belt (rise 2.0), Belt Support (saddle 2.0), Wood Detector (belt-shaped wire source with a wood filter, saved in `plot.logic[uid].filter`, index pinned to WoodData order), Wood Sweeper (a pulse pushes up to 10 loose plot pieces off the belt), Laser Emitter and Receiver (only wood breaks the beam; `MaxLaserPairs` 8 per plot). Part builds per TLD-1; the uploaded TLD-1 meshes are wired in job 15. Previews: `previews/v1-w/`.

**Awaiting Connor**

- Prices (all PROPOSALS): Switch Belt $150, Tilted Belt $120, Belt Support $40, Wood Detector $200, Wood Sweeper $450, Laser Emitter $380, Laser Receiver $220.
- The line pieces are sold at Sparkworks (with the sweeper and lasers). The Sparkworks counter in town stocks them (Sparkworks section at the top).
- `MaxLaserPairs` 8 per plot (proposal).
- Flip on a Switch Belt is a world prompt (Open key), not a placer key: the placer's Q is Cancel. A placer flip key is a cross-lane request.

Studio checks: PHASE2_NOTES.md, "Lane W: practical automation".

## Lane M: mining and crafting (merged, #125)

Merged. V1 mining: ore rocks that show the vein, a cash pick ladder, bombs that open rubble, a smelting furnace and a craft bench on the furnace pad. Income stays at or under 0.8× the best wood the player can already reach (`MINING.md`). The Lux Pickaxe is not for sale. `profile.mining` is account-wide, like the pick level.

The earlier tier-3 cut (Opal $36/$70, Heartstone $80/$140, compared with Gloamwood $7,262) is overridden. Gloam compares with Frostwood, $28,677/h, so the 0.8× cap is $22,942/h. Timber Opal is $90 / $240. Heartstone is $210 / $560. Steel or Lux at Gloam is about $10.7k/h. Obsidian is about $19.1k/h (0.67×). Hills and Snow ore values are unchanged. Hills now quotes Pine at $17,136 from ECONOMY.md (was $15,232). The Obsidian Pick costs $50,000 plus 5 Timber Opal ingots. The save key stays `crafted.HeartstoneTurnIn`.

**Awaiting Connor**

- Lux Pickaxe: a new pass, or a bundle with the Lux Axe pass (`StoreData` Lux Axe id 2005226878), and the price. `passId` stays 0. Level stays 4. No StoreData row. Nothing is on sale. Do not run a purchase test until Connor says yes.
- Whether the crafted Miner's Lamp should also count as the Lantern for Gloam. Default: no. It does light tier 3 mining.
- Furniture (Copper Lamp Post, Gold-banded Chest) stays "Coming soon" until lane F can grant a placed piece.
- No texture or mesh uploads. Rocks, picks, the furnace and the gear are part-built.

Turn-in fixes (PR #125 QA round 2): a second turn-in no longer eats 5 more Timber Opal ingots (toast "Already turned in"), and the turn-in only counts ingots near the Prospector stall and not welded in a truck bed, through `CraftingService.StockNear`. Specs in `tests/MiningService.spec.luau`.

Studio checks: PHASE2_NOTES.md, "Mining and crafting".

Last updated 7 October 2026 (LT2 ground branch on top of main at #98; store fixes branch; mill tiers on top of #93), after PR #90 (everything through store polish is on main). Keep this file current: update it in the same PR as any change that moves a goal, a rule below, or an open question. Older plans (HANDOFF.md, MORNING_HANDOFF.md) are history; this file wins when they disagree.
Last updated 7 October 2026 (dialogue box branch on top of main at #95), after PR #90 (everything through store polish is on main). Keep this file current: update it in the same PR as any change that moves a goal, a rule below, or an open question. Older plans (HANDOFF.md, MORNING_HANDOFF.md) are history; this file wins when they disagree.

- **No floating speech bubbles (`remove-bubbles`, 8 October 2026):** Connor: with the pop-up dialogue box, remove the floating chat bubbles. Gone: the wave hello, idle chatter, Murph's first-tip bubble, and every NPC's bubble code (`NPCController`, `NPCDialogue.AutoBubbles` and the Bubble* helpers, `TextAnchor.CardPx`/`Side`). Kept: name tags (wall-safe through `TextAnchor`), the Talk prompt, the box, the wave and talking gestures (the talking gesture now plays while the box is open), the murmur sound (plays as the box opens). Murph's three onboarding tips now open in the box the first time a new player talks to him on step one (`QuestUI`). Ferry fare, toll fee and shop prices still arrive through the prompts' own text (`Board ($x)`, `Pay toll ($x)`), the keepers' box lines and the toasts. Studio checklist in PHASE2_NOTES.md.
- **Hotfix `fix-shop-talk-buy` (8 October 2026):** Talk and Buy prompts went dead after #107-#111 (the global prompt switch was saved and restored by four scripts that overlap); now `PromptGate` / `PromptSwitch` hold it by name. Open until Connor confirms on Xbox: see PHASE2_NOTES.md "Hotfix: Talk and Buy prompts". Output tags to send back: `[Talk]`, `[PromptSwitch]`, `[Drag]`.
- **Preview meshes (`phase-2/v1-preview-meshes`):** the model preview draws the uploaded GLBs in `assets/meshes` (axes, trucks, trees, buildings, kit). A mesh id with no file is a magenta MISSING MESH box, never a silent part-built stand-in.

## Lane G: V1 nature looks (merged, #119)

Renders are in `previews/v1-g/`. Trees in those shots are the live section trees (`TreeArt.FromSkeleton`). Rocks, plants, cave dressing, the gull, the snow fox and the sky moth are new part-built models. Rain shots are parts, because the preview tool does not draw particles: blobs are the old puff, streaks are the remake.

The client now places those pieces. `AmbientLife` reads zones from `NatureData` (`ScatterZones` when Lane B has merged it, otherwise `WorldPlan`, plus `UndergroundData` rooms). Cave dressing shares `MaxDecor`, stays at or under 120 parts per cave, and uses at most 6 unshadowed lights (2 on low, 4 on medium, 6 on high). Surface nature parts near the camera stay within 560 / 320 / 148. Critters also stop at 320 / 240 / 120 parts, and still at `MaxCritters`. Walkers stay off a road's edge by more than 4 studs. Filler trees come from `TreeArt.FillerTree` (same part counts as before). Rain is a thin streak (`Size` 0.05, `Squash` 9, slanted) plus ground splashes, both inside the old 560 budget: about 198 live particles on high, 139 on medium, 99 on low. A raycast plus cave, tunnel and grotto zones fades rain and the rain sound under shelter. The wet-air haze is `RainFog`: WeatherController only publishes a 0–1 wetness, and LightingController adds it once to its own fog target (`+0.08` density, `+1.1` haze at full storm). Steady rain no longer stacks fog until the sky goes white. No cash change and no tree-volume change. Palm section trees stay at 3 coconuts.

Rocks are six families (`Boulder`, `CrackedBoulder`, `Spire`, `Slab`, `PebbleCluster`, `Outcrop`), three sizes, each tilted 8–20° and sunk 20–30%. No block is taller than 1.5× its width (a spire is stacked offset courses). A built rock is 7 parts, 8 for a pebble cluster. Meadow moss and the snow cap are two thin wedges on the crown (Grass `#667552`, or Snow), at most 0.3 studs proud. Other biomes use the same patches in their own stone. `NatureArt.OreRock(shape, size, oreColor, oreMaterial, glow, oreId?)` is a contrasting host plus 2 vein wedges, each about a fifth of the face it sits on, 8 parts or fewer, tagged `OreRockArt`. `OreId` stays `""` unless the caller passes an ore id. That id reads `OreData` (vein color, material, glow; no prices) and wins over the color arguments. A dark ore (coal) sits on light grey; a bright ore sits on dark stone. Neon and a shadowless PointLight are added only when the ore glows: a pale vein (opal) gets a dim light, a saturated one (heartstone) shines. Ore rocks are not scattered yet.

`RockModels` holds the uploaded Blender rocks (ids pasted 2026-10-08): six kinds, each with an A and a B variant, and six slots per variant (`MeshHost`, `MeshVein1`, `MeshVein2`, `MeshMoss`, `MeshSnow`, `MeshGlow`) with Blender sizes, per-piece `offset` and a `hostCentre`. `NatureArt` puts MeshHost at `hostCentre * scale` and every other piece at `MeshHost.CFrame * CFrame.new(offset * scale)`, before `settle()` tilts and sinks the whole model, so caps and veins sit on the stone. Scatter rocks pick A or B from their seed (same seed, same variant). `RockModels.KindFor(shape)` maps Lane M's ore shapes (boulder, split, standing, slab, mossy, pebbles) to a kind and variant (`mossy` is Boulder B plus a MeshMoss cap); capitalised kind names pass through, anything else is Boulder A, logged once. `NatureArt.CaveMouth()` builds the mine mouth from the uploaded Body, Frame, Glow and Collision (Collision is the invisible collider, Body does not collide, Glow is Neon with a PointLight range 14), or a part-built frame when an id is 0 or a load fails. `RockModels.Scenery` also holds RubbleBoulders and RubbleTunnel with their uploaded ids (not built yet, Lane M). A missing id or failed load keeps the part build and logs once per shape, variant and slot. `NatureArt.BuildFlat` is Build without the tilt, for specs and previews. The preview manifest (`assets/meshes/manifest.json`, with `"tint": true`) now lists the 84 rock and scenery ids, with their GLBs under `assets/meshes/rocks/`.

The preview renderer multiplies a mesh by its part colour only when the manifest entry says `"tint": true` (the rock vertex colours are greyscale shading, so without it the rocks draw white); `tools/preview/viewer.html` and `export.luau` carry that opt-in and nothing else changed there. A mossy ore rock's moss cap uses the meadow cap green, not the ore host's grey, so it reads as moss.

`src/ReplicatedStorage/MeshTemplates/<meshId>.model.json` now exists for all 84 rock, cave and rubble ids (the same MeshPart format as the other templates), so MeshKit finds each piece in Studio and no rock falls back. `tests/RockModels.spec` checks that every id `RockModels.MeshIds()` returns has a template, and `tests/NatureArt.spec` builds every kind, variant, look, size, ore shape and the cave mouth and asserts no `MeshFallback` attribute and no "mesh is missing" warning. The fallback code stays for an id of 0 or a missing template.

Cave mouth placement is not wired here: B's `UndergroundData.MineMouth` does not exist on this branch (see the PR's cross-lane requests).

**Awaiting Connor:** palm section trees stay at 3 coconuts, because that count is a shape field and changing it would move the economy volumes. Say if any rock, plant, critter or rain streak below should change before it is placed.

Rock and ore previews are one model per frame: a 3/4 camera about 25° up, the rock about 55% of the frame height, name on a ground plaque turned 180° about Y so it reads from the camera. Boulder carries the meadow moss, cracked boulder the snow cap. Each ore vein is turned toward the camera. The cave shot is the same eight rocks, preview-lit (mean brightness about 44%) with heartstone the bright one. The meadow shot is from 12 studs up, 30° down, over a 60×60 patch with grass, flowers, small rocks, a rabbit and a deer. Nothing in those scene files changes the game.

Preview paths:

- `previews/v1-g/cave-mouth.png` (real meshes)
- `previews/v1-g/ore-host.png`, `ore-coal.png`, `ore-copper.png`, `ore-iron.png`, `ore-silver.png`, `ore-gold.png`, `ore-opal.png`, `ore-heartstone.png`, `ore-rocks-cave.png` (reshot with the real Blender rocks, Lane M's ore shapes; opal is the mossy Boulder B)
- `previews/v1-g/rock-boulder.png`, `rock-crackedboulder.png`, `rock-spire.png`, `rock-slab.png`, `rock-pebblecluster.png`, `rock-outcrop.png` (reshot with the real Blender rocks)
- `previews/v1-g/trees-lineup.png`
- `previews/v1-g/trees-oak.png`
- `previews/v1-g/trees-birch.png`
- `previews/v1-g/trees-pine.png`
- `previews/v1-g/trees-maple.png`
- `previews/v1-g/trees-palm.png`
- `previews/v1-g/trees-frostwood.png`
- `previews/v1-g/trees-lanternwood.png`
- `previews/v1-g/trees-emberwood.png`
- `previews/v1-g/trees-gloamwood.png`
- `previews/v1-g/trees-lumenwood.png`
- `previews/v1-g/trees-lanternwood-night.png`
- `previews/v1-g/trees-emberwood-night.png`
- `previews/v1-g/trees-gloamwood-night.png`
- `previews/v1-g/trees-lumenwood-night.png`
- `previews/v1-g/rock-boulder.png`
- `previews/v1-g/rock-crackedboulder.png`
- `previews/v1-g/rock-spire.png`
- `previews/v1-g/rock-slab.png`
- `previews/v1-g/rock-pebblecluster.png`
- `previews/v1-g/rock-outcrop.png`
- `previews/v1-g/nature-meadow.png`
- `previews/v1-g/ore-host.png`
- `previews/v1-g/ore-coal.png`
- `previews/v1-g/ore-copper.png`
- `previews/v1-g/ore-iron.png`
- `previews/v1-g/ore-silver.png`
- `previews/v1-g/ore-gold.png`
- `previews/v1-g/ore-opal.png`
- `previews/v1-g/ore-heartstone.png`
- `previews/v1-g/ore-rocks-cave.png`
- `previews/v1-g/nature-plants.png`
- `previews/v1-g/nature-flowers-close.png`
- `previews/v1-g/nature-cave.png`
- `previews/v1-g/nature-glow-fungus.png`
- `previews/v1-g/nature-mushroom-ring-lantern-pods.png`
- `previews/v1-g/critters-lineup.png`
- `previews/v1-g/critters-birds.png`
- `previews/v1-g/critters-rabbits.png`
- `previews/v1-g/critters-deer.png`
- `previews/v1-g/critters-gulls.png`
- `previews/v1-g/critters-snow-fox.png`
- `previews/v1-g/critters-sky-moth.png`
- `previews/v1-g/critters-wisps.png`
- `previews/v1-g/critters-embers.png`
- `previews/v1-g/rain-high-before-blobs.png`
- `previews/v1-g/rain-high-after-streaks.png`
- `previews/v1-g/rain-low-after-streaks.png`
- `previews/v1-g/rain-shop-inside.png`
- `previews/v1-g/rain-shop-outside.png`
## Lane C previews (merged, #120)

Connor (8 October 2026): every design is rendered as soon as it exists, before merge, so he can see it and send tweaks. Renders live in `previews/v1-c/` (the `preview/` folder stays gitignored). Studio checklist: PHASE2_NOTES.md, "V1 buildings, shops, props and palette". Economy headlines are unchanged (no price, recipe, or walk-time edit).

Part counts, whole model, Lune (shop cap 250, including the interior):

| Model | Before | After |
| --- | --- | --- |
| Tool Shed | 626 | 241 |
| Hearth and Home | 311 | 195 |
| Dealership | 245 | 215 |
| Sawmill | 398 | 402 |
| Gate kiosk | — | 7 |
| Odds and Ends | — | 37 |
| Sparkworks | — | 20 (the empty demo-board model; the live shop is `BuildingArt.Shop("Sparkworks")`, 173) |
| Sky Market | — | 10 |
| Sky turnstile | — | 4 |
| Plot map | — | 3 |
| Arrival arch | — | 4 |
| Land Office (art only) | — | 8 |
| Sky forge court | — | 23 |

Round 1 framing (8 October 2026). `town-overview.png` is one elevated three-quarter of a grouped street (the per-building fronts are unchanged). The four scene shots are three-quarter views from about 25 studs, each prop about half the frame. The DAILY JOBS board is wider, with the posts on its edges, so the words clear the posts. The Tool Shed gold table is unchanged.

Round 2 (8 October 2026). The sky forge court uses the street palette: honey plank walls, a weathered-timber furnace with thick timber and honey bands, and a stone chimney. Darker slate photographed as a missing material on the shadowed street face. The four scene props are rebuilt, 10 to 30 parts each: a teepee fire with a tripod pot and log seats, a dock on water with posts, a rod, a bucket and a crate, a lookout platform about 9 studs up with a ladder and a coin telescope, and a park bench with a back and arms. `mill-foreman.png` is unchanged.

Round 3 (8 October 2026). Those five are in the live town (`WorldPlan.Town().scenes`, built by MapBuilder into `TownScenes`). Lane B's map merged in #121; the spots are the live town layout. The sky forge court is on the south-west meadow at (-112, -20), front toward the mill, on `SkyForgeFloor`. The lookout is just west of it at (-136, -20), telescope toward town. The park bench is at (-84, 56) and the campfire at (-72, 56), on the green south of MainStreet. The fishing dock is on the Starter Forest pond's north bank (pond centre 78, -182), posts down into the water; MapBuilder drops the preview water sheet. The town-overview aerial reshoot waits on `phase-2/v1-preview-meshes` (the exporter still drops MeshParts, so the Blender shops still read as boxes).

Paths:
- `previews/v1-c/sawmill-front.png`
- `previews/v1-c/toolshed-front.png`
- `previews/v1-c/hearth-front.png`
- `previews/v1-c/dealership-front.png`
- `previews/v1-c/floor-toolshed.png`
- `previews/v1-c/floor-hearth.png`
- `previews/v1-c/floor-dealership.png`
- `previews/v1-c/weigh-house.png`
- `previews/v1-c/gate-kiosk.png`
- `previews/v1-c/odds-and-ends.png`
- `previews/v1-c/sparkworks.png`
- `previews/v1-c/sky-market.png`
- `previews/v1-c/sky-turnstile.png`
- `previews/v1-c/plot-map.png`
- `previews/v1-c/arrival-arch.png`
- `previews/v1-c/land-office.png`
- `previews/v1-c/sky-forge-court.png`
- `previews/v1-c/campfire.png`
- `previews/v1-c/fence.png`
- `previews/v1-c/lamp-post.png`
- `previews/v1-c/scene-fishing.png`
- `previews/v1-c/scene-campfire.png`
- `previews/v1-c/scene-lookout.png`
- `previews/v1-c/scene-bench.png`
- `previews/v1-c/machine-sawmill.png`
- `previews/v1-c/mill-foreman.png`

Foreman stand for Lane E. `MillForemanSpot` is an anchored, transparent, non-colliding part on the sawmill, west of the office door, facing the road (-Z). With the mill at `WorldPlan.Town().sawmill` (`CFrame.new(0, 0, 116.5)`), the spot's world CFrame is `CFrame.new(-26.025, 0.15, 97.45)` (look -Z). In the scaled model, before that placement, it is `CFrame.new(-26.025, 0.15, -19.05)`. The DAILY JOBS board stands just west of it, wide enough that the words sit between the posts with padding on both sides. The office lumber, barrel and crates moved behind the cabin so the stand has 6 studs of clear ground.

## Who and how

- Owner: Connor. A beginner on Windows PowerShell (also has a Mac): give commands one per line, never chained with `&&`, and never print secrets.
- Connor tests in Roblox Studio; the build agent cannot run it. Every change ships with the exact Studio checks to do and what good looks like.
- Standing instruction: open a PR, subscribe to it, and merge when CI is green (squash, with `expectedHeadSha`). Do not open a PR unless asked, but Connor has asked for merge-when-green on this work stream.
- Commits: `phase-2: <what changed>`. Verify with `./scripts/check.sh` before pushing (the real exit code).
- Update commands to give Connor after a merge (PowerShell, one per line): `cd C:\Users\nicho\timberline-tycoon`, `git checkout main`, `git pull`, `rojo serve`.

## Where the game is

The live core loop is v2 (`GameConfig.CoreLoop = 2`). The v1 code stays for a rollback until M1.10. Plans: V2_PLAN.md (v2), V1_PLAN.md, GAME_DESIGN.md (§14 spec, §8 milestones, §9 automation rules, §15 materials). Playtest checklists: PHASE1_NOTES.md, PHASE2_NOTES.md.

- **Building is the hammer plus physical blueprints** (branch `hammer-build`; BUILD_SYSTEM.md is the design note and decision list, PHASE2_NOTES.md the Studio checklist). Everyone has a Hammer; a blueprint is a Tool you buy, carry, drop and use once to own that building for good (`profile.blueprintBook`); the hammer opens the list, places, and moves, turns or sells what you built. The BUILD toggle and its HUD button are gone. Everything that was free to place before is in every book from the start, so no price moved.

### Rules decided by Connor (do not undo without asking)

- **No floating speech bubbles over NPCs.** Every NPC talk is the dialogue box; name tags and the Talk prompt stay. Anything an NPC used to tell you by bubble must reach you through the box, a prompt's text or a toast (NoticePolicy), never a new bubble.
- **Prices build up.** The more valuable an item, the higher its cost; the first step up the axe ladder is cheap and each next one costs more. One price per item shown to players, never two numbers and never "u³" in player text.
- **Rarer wood and its planks sell for more** (WoodData `RareBoost`), to reward people who go get the better stuff. The full plot lands inside 28–36 h (the model is 33.5 h at the $7,600 step).
- **No free plot.** A player buys their first plot at the Land Office counter: `GameConfig.PlotPrice` = $150. Murph's plot tutorial step pays back $175 (the plot plus the Rustbucket's $25 over its old price) so the economy headlines hold. Saves that already own a plot keep it. Plots start small (80) and grow in tiers 80/110/140/170/200, each homestead with its own look. A plot is **plain grass all round with a raised dark grey build platform on it** (Connor, 7 October 2026, replacing the bare-dirt pads): a flat concrete slab exactly the buildable area (the tier's square plus every bought 40-stud square), `PlotData.PlatformHeight` = 1 stud above the grass, a 6-stud ramp (`PlatformRamp`) in a darker grey along every exposed edge so Humanoids and trucks drive up it; plot-local y = 0 is the platform's TOP, so saved layouts load unchanged. `Shared/PlotPlatform` (layout, parts, `Origin`) builds it; the terrain under a pad and for `TerrainGen.PlotLawn` (40) studs past it is Grass in every region; no decor spawns on the shelf and its blend (`EnvironmentData.DecorBlocked`). `TreeFill.PlotRings` adds up to 12 choppable trees (oak/birch/pine/maple of the region, 'wild' biome, one small regrow zone per cluster) just past each pad's 56-stud blend, leaning toward the forest side; skipped inside the phone discs (QUIET). Not in BiomeData counts, so the economy model is unchanged.
- **No vehicle without a pad.** Every vehicle comes boxed; the box becomes a pad on the player's plot and the pad has the respawn button. The Rustbucket is purchased, not free: **$100**. Bigger vehicles cost more (400 / 2,500 / 5,000 / 19,000; trailers 1,800 / 6,000 / 13,000) so keeping one vehicle has value.
- **Respawn fee** = 5% of the vehicle's price, minimum $5 (`ShopLogic.RespawnFee`, `VehicleLogic.PadFee`). Each vehicle's first two spawns are free (`VehicleLogic.FreeSpawns = 2`) so a lost truck can never soft-lock a player. Recall, pad Press and Equip share one per-pad `presses` counter, and swapping vehicles charges. Tow Service makes recall free.
- **Buying hands over the box; opening it delivers the item** (pickup, BUILD stock, or a pad for a vehicle). Doors shut on the keeper's hours and never trap anyone. The Dealership is a hall on the old lot with the vehicles inside.
- **Owner tools are ONLY Connor's.** Chat commands (cash, free gifts, kick, ban, teleport, announce, super run, time speed and set hour, god, heal, freeze, stats, tutorial reset, unlock buildings, shutdown), plus the owner hub (branch `owner-hub`; tabs are now PLAYERS / GIFTS / PAID ITEMS / WORLD / ROLES / LOG, see Owner hub 2 below): one shared player pick, a status strip, confirmations, tool search, Xbox order and LB/RB tabs (OWNER button or L3+R3; rules in `Shared/AdminHubLogic`). Delegation (owner-only grants, roles HELPER / MODERATOR / BUILDER / CUSTOM / TESTER, server memory only, never persisted; saving "until revoked" is a follow-up that must go through ProfileService/ProfileSchema): see OWNER_TOOLS.md. TESTER = full owner power except delegation, short, two-step grant, needs care. Skipped on purpose: fly/noclip, walk and jump presets, invisibility, mute, named-place teleports, wood and weather tools, vehicles, maxing a plot, "reset player save" (ask Connor before adding any). The server checks `AdminLogic.IsOwner` on every request (OwnerUserIds list, or the experience creator, or Studio); the client `IsOwner` attribute is for UI only and the server never trusts it. See OWNER_TOOLS.md. **Connor must paste his UserId into `AdminLogic.OwnerUserIds`** (not done yet).
- **Xbox:** LT hangs a held piece and the right stick turns it; RB/LB push and pull; longer reach. Blueprints use their own scheme (LT lock, stick flicks, RB/LB slide). HudRules forbids extra D-pad binds.
- **Owner tools are ONLY Connor's.** Chat commands (cash, free gifts, kick, ban, teleport, announce, super run, time speed and set hour), plus an Xbox owner menu (OWNER button or L3+R3). The server checks `AdminLogic.IsOwner` on every request (OwnerUserIds list, or the experience creator, or Studio); the client `IsOwner` attribute is for UI only and the server never trusts it. See OWNER_TOOLS.md. **Connor must paste his UserId into `AdminLogic.OwnerUserIds`** (not done yet).
- **Xbox:** LT hangs a held piece and the LEFT (movement) stick turns it (it does not also walk you; the right stick stays the camera); RB/LB push and pull; longer reach. Blueprints use their own scheme (LT lock, left-stick flicks, RB/LB slide). HudRules forbids extra D-pad binds. The View button opens a quick menu of every HUD destination (SAVES, STORE, BADGES, DAILY, FIELD GUIDE, SETTINGS, LAND, OWNER ... and HUD BUTTONS); Badges moved into it. Panels share one selection helper (`GamepadNav` Focus/Restore, via `MenuPad` and `HUD.Popup`): the stick stays inside an open panel and B returns to the HUD button that opened it.
- **Scope guardrails:** milestones in GAME_DESIGN §8 (the core feels good, then retention such as seasons, festivals and companies, then more content). Gathered materials need a job and a home biome. Wallet cap $2,000,000.

### How plots work

14 pre-built homestead pads (`PlotData.Homes`), one per player slot plus two spares. A player buys one at the Land Office (`PlotService.Claim`, range-checked, charged once, refunded if the build fails). It starts as an 80-stud Campsite and grows through tiers 80/110/140/170/200 ($2,500 / $10,000 / $30,000 / $60,000), plus individually bought 40-stud squares out to a 5x5 grid (square k costs `ExpansionPriceStep` 7600 x k; the first costs `FirstPlotPrice` 100; the full plot is $2,280,100). Each pad stands on a raised dark grey platform (`Shared/PlotPlatform`, 1 stud, ramps all round, grows with the tier and the bought squares); plot-local y = 0 is its top. Builds are saved in plot-local studs so a layout loads on any pad. Limits: 200 prebuilt pieces and 400 kit pieces; selling returns half. A base can be unloaded from the SAVES panel (saved with its save, pad freed) and loaded back onto any pad (`BaseLogic`); saves are picked by hand at join and only a save with a plot opens the pad picker. Rules live in `PlotData` and `PlotLogic`, the server side in `PlotService`. The square step is in the economy model (33.5 h for the full plot).

### Economy model

`lune run tools/economy` (v2) and `lune run tools/economy1` (v1) regenerate ECONOMY.md and ECONOMY_V1.md; commit them with any balance change. The headline times are strict CI ranges: first sale under 3 min, Steel Axe 5–8 min, first $1k 13–20 min, Cobalt 45–75 min, full plot 28–36 h. This pass: 68 s / 5.4 min / 17.9 min / 66.3 min / 33.5 h. The headline strings are also pinned in the Builder, BuildingKit and TownMesh specs, and the tutorial's plot reward is pinned in TutorialData.spec. Retired tutorial step ids are save-migration keys: never reuse or reorder them. If a price change breaks a range, retune a reward or price rather than loosening the range. A model that hangs (instead of failing) usually means the simulated player cannot afford the next purchase and earns $0/h (it did when the Rustbucket went to $100 before the plot was priced in).

### Load time (LOAD-01, 6 October 2026)

Connor reported a very long start. Measured in Lune (slower than Roblox, so use the ratios): the world plan for 1,157 forest trees costs about 6.5 s, the terrain is 144+ chunks of heights (about 20 us a height), and ~1,400 section trees are about 43 Instances each (~60k). All of it ran before the sell area, so players waited for every tree. Now the forest is planted after SellArea (near the sawmill first, 20 ms a frame; `MapBuilder` `forestPlanter`, `SectionTrees.OnPlanted` gives late trees their figure, `WorldClock.Refresh` re-applies night-only woods), the client's filler plan waits for the player to be in, and terrain yields by time. `[Load]` lines in Output (server: per MapBuilder step with timings, forest planned/planted, GameServer slow hooks and "can play"; client: module/controller Start times) say where time goes: ask Connor for them. Still serial: terrain writing (Prebuilt bake in HANDOFF.md removes it). LOAD-02 (7 October, see "What has landed") then found the real costs were serial mesh loads (NPCService.Init 60 s, PlotService.Init 10.7 s), now parallel, and deferred the decor and the sky until after the first player can play; `[Load] ready for play at +X s; fully built at +Y s` is the line to ask Connor for.

## What has landed (everything here is on main; newest first)

- **Sparkworks logic sandbox** (branch `phase-2/v1-s-sparkworks`; PHASE2_NOTES.md "Sparkworks logic sandbox" has the Studio checks). V1 wires: Button, Lever, Pressure Plate, Wall Switch, AND/OR/XOR/NOT, Delay, Sustain, Clock, Spark Lamp, Glow Wire, Hatch, plus the existing Door. Rules are `Shared/LogicGraph` (200 evaluations a pass, timers on a 0.1 s step, a loop shows Overloaded) and `Shared/WireLogic` (80 logic pieces and 160 wires per plot, proposals). Each gate wears a unique top label (AND, OR, XOR, NOT, DLY, HOLD, CLK) in cream GothamBold and an accent strip taken from UITheme colors. Settings for Delay, Sustain and Clock are `profile.plot.logic` via `LogicSet`. The wire tool's first session says "Pick an output", "Pick an input", "Done: flip it" (not saved; that needs a remote, V1.1). `Shared/SparkworksStock` is the shelf list for Lane F. A `DemoBoard` part gets a live unsaved demo. Laser, Detector and Wood Detector are V1.1. Preview renders for Connor: `previews/v1-s/pieces-1.png` through `previews/v1-s/pieces-4.png` (at most four pieces, 3/4 at 30 degrees, the group about 70% of the width, name on a ground plaque), `previews/v1-s/wired.png` (lever and button into AND into a lamp, unlit beside lit, right-angle wires), `previews/v1-s/settings-panel-phone.png` (667x375) and `previews/v1-s/settings-panel-desktop.png` (1920x1080). The panel reads UITheme colors. Its display order (16) stays in `LogicPanelUI`'s `SparkworksTheme` until Lane U adds `Layers.LogicPanel`. Each piece looks for a `MeshTemplates` model of its id (slots Body, Indicator, Moving, LabelFace) and stays part-built, with one log line, when that model is missing. `LogicService.RegisterTarget` takes a machine's power and reverse inputs for Lane W and does not drive them yet. `V1Boot.Start` is given the remote table and calls `LogicService.V1Init`, so `LogicSet` is bound at boot. `LogicService.Tick` has a re-entrancy flag: a Tick that yields inside its 2 ms `TimeSlice` makes the next Heartbeat Tick return at once, each plot runs inside `pcall` (one failing plot warns once and the others still tick), and the flag always clears. `LogicService._setSlice` is the test-only seam, and three specs cover a nested Tick, the flag after an error, and error isolation. No preview for this change (logic only). Nothing of this has been seen in Studio yet.
- **V1 economy core, climate, and the save contract** (branch `phase-2/v1-a1-economy-core`; PHASE2_NOTES.md "V1 economy core" has the Studio checks). Headlines are 68 s / 5.4 min / 17.9 min / 66.3 min / 33.5 h. `WoodData.PlankScale` is 0.40 and frostwood's plan price is 120 so Cobalt and the full plot stay inside range after the coat gate and the $7,600 expansion step (designer plan 95 at scale 0.35 was 83 min and 42 h). Mill `plankBonus` and planer `boardBonus` are in the model (Industrial planer is 1.80). Steel Axe v2 is $110, Cobalt Axe v2 is $2,500. Prosperous stamps `t` (1, 1.04, 1.07, 1.10) on the fell; it carries through the sawmill, the planer, the truck and a rejoin, and the sale is log price × `t`, or plank price × min(3, mill × board × `t`). Snow exposure is 4 DPS after 8 s, removed by the Insulated Coat; volcano exposure outside the crater is 6 DPS after 6 s, removed by Heat Boots; the crater stays the old 5 DPS lava. A recall is free when cash is under $5. Per-slot `secrets` starts empty. `GameConfig.WorldVersion` is 1; a new profile starts there; Migrate parks `truckAt` and moves `groundLoad` onto `strandedLoad` only when the save's version (missing counts as 1) is below the constant, then writes the constant exactly. **Lane B, after this merges, edits only `BiomeData` haulStuds and possibly `GameConfig.ExpansionPriceStep`, then reruns `tools/economy`.** Lane B bumps `WorldVersion` to 2 in its own PR. Lane F restores `strandedLoad` at the plot and clears it, and never touches `worldVersion`. `V1Boot` lists SecretService and skips the module when it is not there yet. Each daily goal has `paid` (false until the Sawmill Foreman pays it; Migrate sets `paid = done` when the flag is missing, so a goal the old loop already paid is not paid again, and a second Migrate leaves it). `daily.bonusOwed` is the all-done bonus still waiting (default 0). Lane E pays these at turn-in and owns DailyService; this pass does not change how goals pay today. `MineAction` (8/s) and `CraftAction` (2/s) are client-to-server intents with no handlers yet; Lane M owns those. `GameConfig.PlacedCap` is 320, enforced when a piece is added, so a full three-slot save stays under 1 MB (`tests/SaveSize.spec.luau`; the DataStore limit is 4 MB). Player-to-player trading is not in V1: no trade save fields, no trade remotes, and TradeService is not on the V1Boot list. A returning player keeps their cash, axes, trucks, placed pieces and saved sections (`tests/fixtures/saves`, `tests/V1Migration.spec.luau`). What they see changed: the Steel Axe is $110 (was $120) and the Cobalt Axe is $2,500 (was $3,000); frostwood's plan price is 120 and plank scale is 0.40, so those planks sell for more; the next expansion square uses the $7,600 step (was $3,050); an Industrial planer's new boards use a 1.80 bonus (was 2.0); snow and the volcano outside the crater now deal exposure damage; a recall is free under $5; a daily goal that was already finished is marked paid, so it is not paid again.
- **Choppable trees in and round the spawn area** (branch `spawn-trees`; PHASE2_NOTES.md "Trees in the spawn area" has the sites, the keep-outs, the load numbers and the Studio checks). Connor: "We need more choppable trees in the spawn area too, near the pad, by the dealership. All over, it's a lumberjack game." `TreeFill.TownRings` (appended after `PlotRings`, its own rng per site) plants 54 real felling trees (stump stays, regrow) in 16 clusters from `Shared/TownTreeData.Sites`: 7 south-west of the spawn pad along the Forest Path, 20 round the showroom hall and Land Office (west strip, forecourt, behind, east), 10 on the town's west edge, 14 north (behind the mill, the Snow Road, north of the General Store), 3 south of the plot road. Woods follow the region (`woodsNear`), biome 'wild', one regrow zone per cluster ("town:<site>", cap = its size, radius 16 at most); NOT in BiomeData counts, so `tools/economy` and `tools/economy1` are unchanged (ECONOMY.md untouched). A town zone's regrow uses `TreeFill.GroundFor` -> `TownGround` (the flat town has no `GoodGround`), so a stump is never a dead end and a regrow obeys the same keep-outs as the first planting. Keep-outs: sell area x -60..60 z 80..140, a spawn lane x -18..18 z 8..100, every road (11 off), path, floor, building (9 off), the parking lot (12) and its pull-outs, loading pads, shop doors, the Land Office queue, the gondola's first 280 studs, the lighthouse lamp's sight line from the pad (WorldPlan.spec), the townsfolk's walks, props, lamps, signs, the ornamental greenery, plots (30 off), water, slopes. Tiers (`TownTreeData.Tiers`, `Count`, `Budget`): low 54 (shipped, `ShippedTier`), medium 74, high 85; trees are server-wide so one tier ships for everybody (a phone's), the others are pinned by spec and are a one-word switch. Phone discs: spawn 1.66x -> 1.95x trees and parts (189 -> 314 -> 368 trees) (cap `TownTreeData.PhoneDiscMax` 2.0; the fill alone is still held to 1.7x). Planning cost: `WorldPlan.Trees()` 8.7-9.0 s (Lune) before, 8.7-8.9 s after (town planning about 40 ms); it stays inside the deferred forest planter, nearest the sawmill first. New preview scene `spawn-trees`. Nothing seen in Studio yet.
- **Saves by hand, Restart save in Settings, and Unload base** (branch `plot-save-switch`, PR #113; PHASE2_NOTES.md "Saves by hand, and Unload base" has the design, the safeguards and the Studio checks). Connor: "with plots, they need a way to unload/save their base and switch to another"; "it shouldn't automatically load a save ... if that player has a plot, they pick a spot"; "restart save should be in settings"; and "switching between saves, and unloading your base with a button which also saves it, LT2 style". Switching bases is switching saves (the three whole-game slots, SAVES panel). Join is quality -> save picker -> (only if the picked save has a plot) plot picker (`Shared/JoinPickLogic`, `PickerSequence` quality/slot/plot); `SaveSlotService` holds a player "picking" (`SlotPick`) until `play(index)`; the save last left off is "Last played"; the 60 s plot-picker timeout starts when the picker is shown (`PlotShown`). REDO is gone from the SAVES list: RESTART SAVE n is a two-press row in Settings (`SettingsLogic.RestartRow`). UNLOAD BASE / LOAD BASE is the top button of the SAVES panel (`BaseLogic.ButtonFor`, `PlotService.BaseAction` "unload" / "load"): unload saves the save with the base in it, takes the pad's models down, sets visitors outside, frees the pad and leaves you in the world padless (the `profile.plot` record is untouched); load opens the free plot picker. 120 s cooldown (`baseCooldownUntil`, `GameConfig.BaseCooldownSec`), rate limited, refuses with loose wood on the plot, rolls back if the release throws. `VehicleService.ClearPads` takes pad models down on unload, slot swap and leave; pads are restored when a base lands on a pad. Old Hank is unchanged. Nothing seen in Studio yet.
- **Drop axe has no button** (branch `drop-axe-controls`; PHASE2_NOTES.md "Drop axe controls" has the B audit and the Studio checks). Connor: "why is there a drop axe button". The side button is gone on every platform. The held axe (or rolled plan) drops with B on a gamepad, Q or Backspace on a keyboard, and a long press on the hotbar strip on a phone (Roblox's hotbar is the engine's, so no per-slot button is possible); two presses as before, a toast says "Press B again to drop the Steel Axe." The rules are `Shared/DropControls` (`Decide`: drop, close or ignore; B closes whatever is open and never drops), bound in `AxeController` below every menu's B. Same conditions as before (`HudRules.DropAxe`, the server checks). The D-pad Down shortcut and the quick-menu tile are gone.
- **Vehicle meshes placed from the hull** (branch `vehicle-models`; PHASE2_NOTES.md "Vehicle meshes" has the cause and the Studio checks). Connor (Xbox, after #108): "the vehicle models are messed up" (a Logging Rig at the dealership with a plank bed at ground level, black lumps, floating pale pillars). Cause: each uploaded vehicle piece (Body, Glass, Lights, Bed, Hitch) is its own mesh asset and carries no pivot, so `VehicleMeshes` stood every piece's bounds bottom-centre on the ground centre; only the Body is drawn that way. Now `VehicleMeshes.Place` puts each role from the part-built hull it replaces (bed on the frame at the BedFloor, glass at the cab glass, lights from the lowest lamp, hitch at the chassis end; a trailer: on its TrailerBed and coupler); a surviving pivot is used only within 2 studs of that. Wheels, handling, welds and part counts untouched; the part-built fallback is unchanged. New preview scene `vehiclemesh` and `tests/VehicleMeshPlace.spec.luau`. Mesh shapes cannot be seen in Lune: nothing seen in Studio yet.
- **Box hold: a grabbed shop box no longer spins** (branch `box-hold-axes`; PHASE2_NOTES.md "Box hold" has the Studio checks). Connor (Xbox): a grabbed shop box "is spinning". Cause: a box's assembly (about 35 mass at the biggest) weighs more than `DragForceCap` lifts, and the turn's torque (2 x the pull) was less than the pull at the grip's lever, so the box hung from the grip and tumbled. Now a box (tag ShopBox) is held by `GrabLogic.HoldForce` (at least 1.6 x its weight), pulled at the centre of mass, turned with `GrabLogic.HoldTorque` (sized to its radius), started upright (`GrabLogic.Upright`) with its spin zeroed on confirm. Logs and other items are unchanged. "Custom axes not working": traced buy -> box -> open -> equip and owner grant -> equip, no break found in code; the likely cause is the mesh asset permissions (open item 3). Not seen in Studio.
- **Final pass** (branch `final-pass`; PHASE2_NOTES.md "Final pass" has the Studio checks). Read-through of everything not yet seen in Studio (join flow, boxes and store, owner hub and paid items, mill tiers, planers, belts, plot platforms, load pipeline). Fixed: a failed `LoadCharacterAsync` left a player with no character (now `JoinFlow.LoadWithRetry`, 3 tries, also for respawns); the client's `ClientReady` fires lasted only 18 s and could all predate the server's listener (now every 3 s up to 90 s); a plot-picker respawn after close could lock WalkSpeed and the camera for good; the quality screen closes before it talks to the server; the plot picker's buttons shrink text on a narrow phone; a hover-tag error on a destroyed item. Not changed: hand-fed wood that waits over 4 s for a busy mill is treated as belt-fed (see the report in PHASE2_NOTES.md).
- **Plot picker view** (branch `plot-picker-view`; PHASE2_NOTES.md "Plot picker: you can see which pad you are choosing" has the Studio checks). Connor: the picker did not show which plot he was selecting, then teleported him. Now a render-step loop holds the Scriptable camera on the pad every frame (gliding between pads), the stream request waits longer and shows "Loading view...", a map card (`Shared/PlotPickerMap`) and a client-made pillar with a name tag mark the chosen pad without needing the world streamed, and a claim fades through black with "Claimed <pad>!". No server, remote or economy change. Nothing seen in Studio yet.
- **Owner hub 2: paid items and a calmer panel** (branch `owner-panel-2`; PHASE2_NOTES.md "Owner hub 2" has the Studio checks, OWNER_TOOLS.md the tab list). Connor: "give them paid items such as 2x and lux axe, plus any future ones". New PAID ITEMS tab: `Shared/PaidItems` builds the list from `Shared/StoreData` (every pass and product, with kind, how it is given, what a revoke does), so a store item added later shows up by itself. `MonetizationService.OwnerGrant / OwnerRevoke / OwnerState` give, take back and read it through the same effects a purchase has (pass switch and its listener, `EconomyService.AddCash`, the boost helper), with no Robux, receipt or purchase analytics; a pass grant is saved in the new account-wide `profile.ownerGrants` (the join check ORs it in, a revoke never touches a purchase) and every give or revoke goes into `profile.ownerGrantLog` (last 30). Owner only, plus a delegable **Gifts** power (`paidgive`, themself only); `paidrevoke` is never delegable and TESTER does not hold paid items on purpose. Panel: tabs PLAYERS / GIFTS / PAID ITEMS / WORLD / ROLES / LOG, a persistent who-and-role header, search on every long list, recents first, B goes back one level, LB/RB and LT/RT change tab, tabs wrap on a phone, taller rows on a pad, buttons that can't go say why, one second-press for everything destructive, UNBAN in the hub. Not added on purpose (ask first): weather on a live server, clear plot, spawn vehicles, reset player save.
- **Spaced-out shelves and the Lower / Higher quality choice** (branch `quality-picker`; PHASE2_NOTES.md has the numbers and the Studio checks). Connor: "space them out more" and "just let them pick between lower quality (Phone) or higher quality at launch". Boxes: 1.5 studs side by side (`BoxSize.Gap`) and 2.5 between rows (`BoxSize.RowGap`) on every shelf (plinths still 1.0 / 2.0 apart, the axe rack's blocks 1.5 apart, the Robux table too, the showroom was already 10+); the Tool Shed is 35.7 wide (was 29.1; same depth and place, tables 12.1 wide so two boxes stand side by side, aisle still 10, counter at the back; the firewood stack moved to the west wall, one planter and the floor paint moved a little) and the General Store's plans are split over both islands (2 a row). Quality: every account is asked once on a join screen (`QualityPickerUI`, gamepad / touch / mouse, the device's recommendation pre-selected: touch-only Lower, console and PC Higher) and can change it in Settings (Graphics: Lower / Higher). Saved as `settings.quality` (`unset` | `low` | `high`, `SettingsLogic` and `ProfileSchema.Migrate`), set through the rate-limited `SetQuality` remote (`QualityService`). `QualityProfile.TierFor` turns it into a `QualityBudgets` tier: Lower is always `low`, Higher is the device's own tier (a device that reports `low` gets `medium`). Lower takes the item copies out of the shop box windows on the player's own client and tints the glass (`QualityDressing`, `Shared/BoxWindows`; one server box for everyone), shortens shop lights (`LightScale`) and townsfolk animation (`NpcAnimateRange`) on top of the existing low decor / filler / weather budgets; nothing about prices, hover tags, grabbing, opening or hitboxes changes. The streaming radius is a place setting and stays 640 for everyone. The old four-way `settings.graphics` row is gone (the key still loads). Nothing seen in Studio.
- **Join race fix** (branch `join-race-fix`; PHASE2_NOTES.md "Join race fix" has the root causes and the Studio checks). Connor, after #103: the character glitched and could not move, and the plot picker could not be used. Causes: MapBuilder let everyone spawn at world-ready (+6.5 s), before the services, the save, the plot pads, Murph and the streamed spawn area, and the deferred build then filled the town around them; the client controllers (now early) never told the server they were listening, so one-shots (plot offer, slots, cash) could be lost; the quality screen (layer 90) opened over the plot picker (80) with both holding a movement lock; and the late plot-mesh redraw rebuilt pads under players. Now `Shared/JoinFlow` orders it: MapBuilder loads nobody; GameServer's `enterWorld` waits for the first-player gates (terrain, town, world, services, new `plots` and `murph`), streams the spawn area, loads the character, waits until it stands, and waits for the client's new `ClientReady` handshake (`ServerScriptService/JoinSync` resends cash, the plot offer and the slots) before `ProfileLoaded` and "can play"; GameServer also respawns the dead; `Shared/PickerSequence` makes quality go before the plot picker; `Shared/PlotRedraw` holds a pad redraw back while a player is near. No economy change. Nothing seen in Studio yet.
- **Load time 2** (branch `faster-load-2`; PHASE2_NOTES.md "Load time 2" has Connor's before numbers, the changes and the Studio checks). Cause of the 60 s `NPCService.Init`: the nine townsfolk's 153 mesh pieces were loaded one at a time with `CreateMeshPartAsync` (about 0.4 s each) inside `CharacterArt.Build`; `PlotService.Init`'s 10.7 s was the plot kit's 32 meshes loaded the same way. Now every uploaded mesh starts loading 24 at a time when `MapBuilder` starts (`MeshKit.Preload`, `Art/MeshManifest`, `Shared/WorkPool`), overlapping the terrain; Murph is built at once and the other townsfolk are deferred steps; the decor (town dressing, boulders, scenery, points of interest, trails, landmarks, backdrop, volcano crater, the whole sky) is built after the first player can play, by `Shared/LoadQueue` (tiers, nearest the players first, 12 ms slices; `ServerScriptService/LoadState` holds the queue, the `ReadyGates` and the milestones); `WorldPlan.Trees(pause)` no longer freezes a frame; the client's HUD no longer holds the other controllers and its loading card has a bar (`Shared/LoadStages`). One summary line: `[Load] ready for play at +X s; fully built at +Y s`. Terrain writing (13 s) and the terrain prebake are unchanged. No balance change. Nothing seen in Studio yet.

- **LT2 window boxes and stepped shelves** (branch `lt2-boxes`; PHASE2_NOTES.md has the Studio checks; Connor sent two Lumber Tycoon 2 pictures: "I want our boxes to reflect closer to this", "keep the box size accurate to the item inside"). A shop box is a dark charcoal box with a Glass window on the front, top and aisle side showing the REAL item (`Shared/Art/ItemModel`: AxeArt, MachineArt, TruckArt, BlueprintModels, small gear icons; a low-detail, weightless, non-colliding copy), an accent band with the name (axes by tier colour, sawmill, planer, belt, machine, gear, plan, lamp, truck, trailer, Robux each their own; `Shared/BoxLook`) and no price (the hover tag is untouched: `HoverItem`, `HoverKind`, `ForSale`, `OnShelf` are on the model). The size is the item's real bounding box plus 0.6 stud each side and over the top and a 0.3 floor (`Shared/BoxSize`, `Shared/ItemBox`; min 2.4 x 1.9 x 1.7, shelf max 3.1 x 4.6 x 3.6, sawmills 6.4 x 4.8 x 4.8, vehicles 15.5 x 7.4 x 8.4; big things are shown smaller, a family at one scale); the size classes are gone. Parts: 9-part shell plus 3 to 32 for the item, cap `BoxLogic.BoxPartCap` 42; `GameConfig.StorePartBudget` 900 to 1200 because every box now carries its item. Shelves are stepped display units (each row 0.22 higher toward the back) with an accent plinth under every box; the Tool Shed axe rack is a stepped wall shelf with a tier-colour backing block per axe; dealership boxes face the walkway on an accent block. Tool Shed aisle 10 studs (was 11.6), General Store plan islands 2 studs wider. No price, recipe or economy change.
- Modern kit (branch `kit-modern`; PHASE2_NOTES.md has the audit, the numbers and the Studio checks): paint for every kit piece (`Shared/KitPaint`, 12 colours, free, hammer sheet Move / Turn / Paint / Sell, saved as `paint`), six glass pieces (picture window walls 8 and 12 long standard and tall, glass door wall, shop front) sold as ONE $500 General Store plan that teaches all six (`family`, `storePrice`, `gated`; the kit fee still applies on every place), three overhang roofs (1.5 stud overhang, dark edge), roof edge trim, awning, Storey Stairs (eight real 0.8 steps, 6.4 rise) and a Balcony, `Shared/ModernKit`. `Shared/SampleBuilds` (modern house, shop, barn; every one passes `PlotLogic.Check`) and the owner-only `/sample <name>` / `/sample clear` (never delegable, TESTER included). Caps kept (MaxKit 400, MaxItems 200); economy tools unchanged. Glass no longer blocks tap and RT aiming (`BuilderTools.Aim`). Nothing seen in Studio yet.
- Sky Bin open-and-place, prices on hover (branch `hover-prices-skybin`): the Sky Bin is a one-time box like the mills (`placeFromBox`; open, ghost, place spends the box, cancel keeps it; hammer sells it back for half, no re-boxing; selling it pays the wood in it out first through `SellService.PayEntries` and is refused, nothing lost, if that is impossible; old saves get a pending box in `profile.storage`, idempotent). No price is printed in the world any more (box labels, axe-rack plates, offer boards, the showroom's vehicle signs are names only); a single depth-tested hover tag (`Shared/HoverTag`, `HoverTagUI`) shows name and the real price when you aim at an item (mouse cursor, gamepad centre aim within 12 studs, touch last tap or nearest within 6), with Closed / You already own this / Out of stock states. Connor's decisions: "open and place", "just show prices when hovering", showroom signs go too. Checks: PHASE2_NOTES.md "The Sky Bin opens and places once; prices show when you aim".
- **LT2 ground and raised plot platforms** (branch `lt2-ground`; Connor sent Lumber Tycoon 2 screenshots: "the actual ground" and "normal grass with a raised dark grey platform ... like 1 stud"). The ground reads as LT2: Grass 100,184,56 and LeafyGrass 82,158,48 (flat, vivid; were 84,125,55 / 66,104,46), `Terrain.Decoration` and the grass blades are OFF (project file, `PlaceCheck`), every road, path, street, the parking lot and the sell yard is light grey gravel (`TerrainGen.GravelMaterial` = Asphalt, 176,176,172; was brown Ground on everything but the haul roads), earth and cliffs are red-brown (Ground 156,94,64, Rock 128,86,64), Midday is a little more saturated. Shop floors stay Ground. Snow, volcano, sky and the Gloam Hollow keep their own looks, and The Climb (the north-road homestead) is just another plot. Plots: the platform above; the plot origin is now `HeightAt` + 1 and the client's `BlueprintPlacer.PlotCFrame` uses the same origin (`PlotPlatform.Origin`; it used world y = 0 before, which was wrong on every homestead: their ground runs from -3.2 to +7.2). Heights, road and flat-zone rules and the economy are untouched. Nothing here has been seen in Studio: PHASE2_NOTES.md "LT2 ground and plot platforms" has the checks, including the one-word swap (`GravelMaterial`) if Asphalt reads too dark.
- Store fixes (branch `store-fixes`): one grab lifts a shelf box (the pull is sized from the parts' mass, not an anchored assembly's 0), the carry cap counts only boxes in your hands and a box let go over its shelf spot goes back on it, shop doors no longer z-fight (`ZFight.spec` scans them), and a shelf box shows ONE price, under its name on its own label (no billboard, no aisle plaques; vehicles use the showroom sign). Causes and Studio checks: PHASE2_NOTES.md "Store fixes".
- Dialogue box, text out of walls, bigger rabbits (branch `npc-dialogue-box`; Connor's playtest on Xbox, phone and PC): talking to an NPC (E / X / tap) opens a dialogue box above the hotbar instead of a bubble: name and role, the line, a Continue prompt with the right glyph; each press pages on, the last press closes it; walking 24+ studs off, the speaker going, or the plot picker closes it (`DialogueUI`, pure rules in `Shared/DialogueFlow`). Townsfolk give a greeting and one line, the keepers and the Hermit are still the server's lines (and offers) shown in the same box, Murph's Talk press shows his tutorial line there, Old Hank opens the plot picker until you own a plot. While it is open that NPC says no bubbles, other prompts are off, toasts wait (`NoticePolicy` hold, `TalkOpen`), and the gamepad selection is handed back. Kept as small bubbles: the wave hello, Murph's first tip, the idle chatter (`NPCDialogue.AutoBubbles`). Text no longer shows in or through walls (`Shared/TextAnchor`): a 4 Hz wall ray hides a bubble and name tag, a ceiling ray lowers them under a shop roof, a bubble with a wall beside it sits above the head, and the Talk card over a head is no longer `AlwaysOnTop`. Rabbits are 2.25x (`CritterArt.RabbitScale`) with a scaled hop. Studio checks: PHASE2_NOTES.md "The dialogue box".
- NPCs lock on while you talk, and everyone speaks in the box (branch `npc-talk-lock`; Connor's playtest: "Dale doesn't have our chat box ... they should lock on you until the chat goes away"): while a dialogue box is open the NPC turns to face that player (yaw only, smooth, head following) and a walker holds where it stands, then returns to normal when the box closes, you walk off, die or leave, or the NPC is removed or lies down. `NPCTalkService` (server) keeps the list of talkers per NPC and publishes the attribute `TalkWith` (the most recent talker); rules in `Shared/TalkLock`; the Dialogue remote gets an `"end"` intent. Visual only on the client (`NPCController`). A keeper's hello (Dale, Tink, Hazel) is now greeting + the shop's line + a line of their own, like everyone's; Old Hank's replies and the Hermit's "too far" moved from toasts into the box. Studio checks: PHASE2_NOTES.md "NPCs turn to face you while you talk".
- Mill tiers, planers, belts and one-time boxes (branch `mill-tiers`): the five sawmills (ids and prices unchanged) stamp a `plankBonus` of 1.00 / 1.10 / 1.22 / 1.36 / 1.50 on every plank they cut, applied in `SellLogic.PieceValue` (a piece keeps its stamp; no stamp is 1.0); a new Planer line (Hand $2,500 / Bench $9,000 / Steam $30,000 / Industrial $95,000, `boardBonus` 1.20 to 2.00, two per plot, owner only) turns a plank into a finished board; a belt kit (Straight $80, Turn $100, Funnel $60, 150 pieces per plot) feeds mills and planers under GAME_DESIGN section 9 (online only, no rare wood, a throughput cap per tier, a loose-plank cap as the Warehouse stand-in); every mill and planer has an adjustable size within its tier's limits. **Sawmills, planers and belts are now boxes that place once** (open the box, a ghost starts, placing spends it; cancel keeps it; no hammer stock; old stock still places). Mill and planer bonuses are in the economy model as of the V1 economy-core pass (Industrial planer `boardBonus` is 1.80). The older "not modelled, or the plot falls to 20.8 h" note is out of date. Tables: V2_PLAN.md 2h and 10a; Studio checks: PHASE2_NOTES.md "Mill and planer tiers".
- Sky Bin item (branch `sky-bin-item`): the fixed bin at the sawmill is gone. It is a $400 boxed Tool Shed item, one per player (`SkyBinLogic`, `ItemCatalog.Machines.SkyBin`), placed on your plot (since the open-and-place branch: from its box, one time; the hammer moves, turns and sells it back for half). The Cloud Chute is locked until you have one placed (nothing is lost; the toast says where to buy it). Old saves with wood in the bin get a free bin and keep the wood (`ProfileSchema.Migrate`, `skyBinOwned`). Economy ranges unchanged. Studio checks: PHASE2_NOTES.md "The Sky Bin is an item".
- #90 store polish: counters at the back of every shop, bigger spaced-out shops (Tool Shed x -84, General Store behind it, showroom hall x 181 to 336 north of the Land Office; the sell pad's keep-out x -60 to 60, z 80 to 140 stays empty), a showroom with a clear 14-stud walkway and boxes on the plinths, raised name boards, new floors, real axe models on the Tool Shed rack, the water tower out of the shop, the showroom light down 30% (`ShowroomLight`), the Tool Shed open 6 AM to 8 PM, and more shop detail (`ShopFacade`, `ShopInterior`). **The Climb plot moved to z 345.** Notes and Studio checks: PHASE2_NOTES.md "Store polish".

- #89 sell station beside the mill (PHASE2_NOTES.md has the Studio checks). Connor: "move the sell logs here pad to the side of the saw mill, and add more to it". The pad left the mill's front (the spawn walk now runs clear to the mill) for a bigger station EAST of the mill's lean-to: pad centre (53, 111), 28 x 32, sell zone 28 x 12 x 52 (z 85 to 137, `WorldPlan.SellZoneSize`, `SellPadWidth/Depth`), clear of the Dealership's loading pad (x 70 to 84). `BuildingArt.SellStation`: a truck lane between painted lines, three LOGS slots and two PLANKS slots (paint only, the sell logic still takes the whole zone), a platform scale, a log rack across the back, a Weigh House with Millie at its window, rails, lanterns; four lamps and the SELL LOGS HERE signpost at (67, 90) mark the gate; the Sky Bin moved into the pad's north-west corner. Beacon `sellPad`, the SELL LOGS marker and Millie follow the zone. Economy headlines 68 s / 7.9 min (ceiling is 8) / 13.7 min / 51.4 min / 30.5 h (the walk from the grove oak grew from 44 to 97 studs; `tools/economy.luau` `A.padX/padZ` = 53/111).
- #87 Xbox navigation and rotation. View button = quick menu (`QuickMenuUI`, `Shared/QuickMenuLogic`), HUD buttons wired for the stick (`HudNav`, `Shared/GamepadNavLogic`), panels use `GamepadNav`; LT + LEFT stick turns a held piece or the build ghost and the left stick is sunk while LT is down. Studio checklist: PHASE2_NOTES.md, "Xbox navigation and rotation".

- #86 NPC heads: `Shared/HeadLook` is the one tested head look-at (70 degree yaw, 35 pitch, smoothed; NPCController uses it). Part-built faces were already on -Z (spec-checked for all 13 NPCs). The Blender NPC meshes are inferred to face +Z (Blender -Y front exports to +Z), so `TownModels.NpcMeshYaw = math.pi` turns every NPC mesh piece half way; unverified in Studio, set it to 0 if the faces then look away.
- Sell station fixes (branch new-session-7e3s9x): the SKYROOT GONDOLA signpost is gone (`town.gondolaSign` removed); `WorldLayout.TownFloors` has a `SellStationFloor` (the MillYard paint stopped at x 33, so grass grew over the pad at x 39 to 67); Millie stands in front of the Weigh House counter at (71.4, 120), just in front of the house the house.
- #88 owner hub: tabs, shared player pick, status strip, confirmations, more owner powers, delegation roles (HELPER, MODERATOR, BUILDER, CUSTOM, TESTER; TESTER equals the owner for testing; never-delegable list stays owner only; delegates live in session memory only).
- #85 `TownMeshes` off again (signs and buildings sank).
- #83 Murph's cart is gone; the first sale (`sell` step, still step 3 of 8) is at the sawmill's sell pad (beacon `sellPad`). Murph still pays $25 on it, the plot step $175. Economy headlines 61 s / 7.3 min / 13.1 min (the floor is 13) / 50.7 min / 30.4 h.
- #79 the hammer and physical blueprints replace BUILD mode (BUILD_SYSTEM.md): blueprints are rolled plans you use to learn a building for good (`BlueprintBook`), the Hammer opens the list on click / RT / tap, pieces are placed, filled with wood, and moved/turned/sold with the hammer; saves migrate (`blueprintBook`, `blueprintItems`, `hammer`).
- #82 real stores: designed boxes sized by item (`BoxSize`), bigger Tool Shed and Hearth & Home, doors that shut on the keeper's hours (`ShopDoorLogic`), the Dealership as an indoor showroom, and buying hands over a box you open (`BoxUnpack`).
- #81 8-step tutorial (`TutorialData.RetiredV2`, `ApplyOrder` order 6) and `NoticePolicy` for fewer pop-ups.
- #80 plain ground on plot pads and trees around plots (`TreeFill.PlotRings`). #78 pumpkins and town decor on the ground, `FacingLogic`, calmer grass. #77 felling fix (stump stays, no exploding, fall sound, swing). #76 Blender meshes back on with diagnostics. #75 faster load (forest plants after you can play, `[Load]` prints). #74 Old Hank the plot salesman. #73 Badges on the View button (L3 is for running). #72/#71 plot picker fix; HUD corner, 12-hour clock, owner time tools, dialogue above hotbar, smooth sawmill. #70 plot bought at $150, Rustbucket $100, respawn fees.
- Before that: #69 pad-only vehicles, #68/#67 owner menu, #66 Xbox carry and build, #65 building fixes, #64 owner chat tools, #63 rare wood prices, #62 axe ladder, #58 smaller plots and looks, boxed stores, plot visits, ferry, NPCs, badges, day/night, W1 to W4 world work (see `git log`).

## Meshes (Blender models)

`GameConfig.TownMeshes` is **false** again (6 Oct: signs and buildings sank under the ground with it on, even with the ground snap; the cause is not found yet; try it per run with the Studio workspace attribute `TownMeshes`). Axes, trees, NPCs, vehicles and plot kit meshes are separate and stay on. Axes, trees, NPCs, vehicles and the plot kit all load through `MeshKit.Create`; a failed load falls back to part-built art and now warns with the engine's error, and the `[MapBuilder] build check:` line prints the load totals. The ids belong to creator `Elucidhealer618`: if the Output says meshes failed, fix asset permissions in Creator Hub (steps and ids in PHASE2_NOTES.md, "Blender meshes are back on"). Shelf boxes show no axe model by design (#42/#51).

## V1.1 polish leftovers (branch `phase-2/polish-v11-leftovers`, 12 October 2026)

No price, economy, balance or shop-item changes. Renders are in `previews/polish-v11/`.
- **Gate signs show per-player state.** `BuildingArt.Signpost(text, lit, solidBoard, gateId)`: with a `gateId` the sign is tagged `GateSign`, gets the `GateId` attribute and a small plaque under the board whose TextLabel is named `State` (WorldUI / `GateSignLogic` repaint it per player). `WorldPlan.GateSigns` returns `gateId` (snow, volcano, grove), `MapBuilder` passes it, and `GondolaService.GateSign` passes `sky`.
- **Bayou and Red Mesa region banner.** `RegionLogic` has `bayou` and `redmesa` regions (biome ids `bayou` and `mesa`, discs from `BiomeData.RegionDiscs`); they are not in the stand list, so no tree filler or wake rule changed. `WorldUI` already shows each region's toast once per session.
- **Plot sign text.** `PlotService` already puts the owner's name and the plot line above the mesh post's top (`PlotData.SignText`, pinned by `PlotService.spec`). The post crossed "Connor" only because the `v1-backlog-trophies` preview scene drew its own one-label text; it now uses `PlotData.SignText`. Render: `previews/polish-v11/plot-sign-trophies.png`.
- **Sparkworks headers.** The chain through "&" and "I" was a sub-sign's chain hanging in front of its header, not a lamp. `subShift = 0.5` (was 1.3) puts both chains in the gaps between letters from the doorway (`Sparkworks.luau` only). Render: `previews/polish-v11/sparkworks-entrance.png`.
- **Logging Rig under the Dealership ceiling.** The rig's crane and stacks stood 15.8 over the plinth (beams hang to 14.1 over the floor). `DealershipLot.MaxVehicleHeight` (12.4) scales a taller display copy down about its feet; the bays and the hall are still laid out from the full-size vehicle (footprint unchanged), and the gameplay truck and its stats are untouched. `DealershipLot.spec` pins every display under the beams. Renders: `dealership-rig-before.png`, `dealership-rig-after.png`, `dealership-entrance.png`.
- **Client waits for Shared.** `Client.client`, `MiningClient` and `ForgeClient` `WaitForChild("Shared", 30)` (and the module they require first) before the first require; no tests changed.
- Not done: the same unbounded `ReplicatedStorage.Shared` indexing inside the individual client modules (only the three entry scripts were asked for).

## Open items

0. **V1 integration pass (11 October 2026):** the consolidated Studio checklist (PC, phone, Xbox) and every open decision with its default are in `V1_STUDIO_CHECKLIST.md`. The scan specs are `V1Refs`, `V1Playthrough`, `V1Migration`, `V1World`, `V1Budgets`. Findings left for other PRs are in that file under "Cross-lane requests".
1. **Studio verification** of everything above: none of it has been seen in Studio. Checklists are in PHASE2_NOTES.md (Land Office, boxed truck and pad flow, free first respawns, Xbox controls, owner menu, the hammer, real stores and doors, Old Hank, felling, tutorial and pop-ups, first sale at the sawmill).
2. **Owner UserIds:** `AdminLogic.OwnerUserIds` holds Elucidhealer618's id (5682024709). The second owner (Catman9732, Xbox) is still blank until Connor sends that id.
3. **If axes or trees still show as plain parts:** send the `[MapBuilder] build check:` and `[MeshKit]` Output lines; the likely fix is asset permissions in Creator Hub (PHASE2_NOTES.md, "Blender meshes are back on"). Send the `[Load]` lines if loading is still slow (the summary line `[Load] ready for play at +X s; fully built at +Y s` first; next win: terrain prebake, HANDOFF.md section 12).
4. **Not reproduced without Studio:** signs/roof/buildings sinking (build-check print and ground snap shipped), backward-walking NPCs, the flat blue ground at night near spawn, smoke at the cursor.
5. **Questions for Connor:** should Cabin, Warehouse and the other free-to-place pieces become bought blueprints? Should blueprints spawn in the world? A real trade window? Lanternwood economy numbers (MORNING_HANDOFF.md)? Badge IDs? Is the Rustbucket recall fee of $5 OK? A real day counter, and weather following game time? Should region/grove toasts wait for the tutorial to end? More trees near plots (done for the town, see Trees in the spawn area)? Should Higher players get a fuller town (needs a per-player tree layer, not just a tier switch)? Install Blender here (uploads still need Connor's account)?
6. **Questions for Connor on unloading:** is the 120 s unload cooldown right? Should unloading also be offered on the quick menu / View menu next to SAVES (today it is the top button of the SAVES panel)? Should loose wood on the plot be swept into the save instead of blocking the unload?
7. The v1 rollback loop still charges the plot with no Murph payback. A tutorial skipper or replayer pays the full $150 with no payback. The Dealership hall now stands at x 181 to 336, z 96 to 162 (store-polish); an unclaimed pickup lives in memory for 5 minutes.

## Tooling notes

- Toolchain via Rokit (`bash scripts/cloud-setup.sh` on Linux). `lune run tests/run [Name]` runs one spec. `bash tools/preview/shoot.sh <scene>` renders a scene to `preview/` for art or world changes.
- `./scripts/check.sh` takes several minutes (WorldPlan.spec alone is about a minute); run it in the background or with a long timeout, since foreground commands time out near 600 s.
- Do not use `pkill -f` patterns that match your own shell.


## Lane E: NPCs, Foreman, stage events (branch `phase-2/v1-e-npcs-ui`, 11 October 2026, draft PR)

Partial lane: what landed and what did not.

Landed:
- Five Blender NPCs wired through MeshKit (Hermit, Old Tolly, Cap'n Moss, Old Hank, the Foreman): `TownModels` rows with the uploaded ids, 74 new `MeshTemplates/<id>.model.json` files, `NPCMeshes.AssetId` (display name to model id). The part-built NPC stays when an id is 0, a template is missing or a mesh fails; a miss sets the `MeshFallback` attribute and warns once per asset. Never InsertService.
- The Foreman is Rook Calloway (`ForemanData`, `NPCData` id `Foreman`), on the mill's MillForemanSpot pad facing the road. A finished daily goal is now OWED, not paid: `DailyService.TurnIn` (remote `ForemanTurnIn`, RateLimiter 2/s, distance to Rook checked on the server) pays every finished unpaid goal plus the all-done bonus (`daily.bonusOwed`) through EconomyService.AddCash; a full wallet leaves the remainder owed; anything still owed is paid at the UTC reset; the streak moves the moment the third goal finishes. `DailyUI` is his job board (opened when his talk box closes; the old corner button is kept hidden); it starts again in `Client`.
- `StageOf.Pending` and `MilestoneService.CheckStages`: "Stage:S1".."Stage:S8" in `profile.onboarding` (no new save field), one `LogProgressionCompleteEvent("Stages", "Sn")` per stage per player, marked before logged.
- `DialogueData.GusCharter` / `GusLine` for every charter step; Gus's talk shows the step line first (`SkyQuestStep` attribute).

Not done (open): visitArea goal (needs a save field and a BadgeService call), day counter, climate vignette, gate-sign state text, region toast wiring, Field Guide stamps, tutorial skip flag rework, NPC remake to under 60 parts, HUD renders at 667x375 and 1920x1080, NextGoal/V1Stages changes.
Previews: `previews/v1-e/foreman-layout-*-PART-BUILT.png` are the part-built fallbacks for layout and facing only. The NPC GLBs are not in the pack (only stats.json), so there are no mesh renders.

### Lane E round 2 (11 October 2026, same branch)

Landed after the first push:
- **Discover a new area** daily goal: kinds `visitArea` (v1) and `visitNewArea` (v2; the pools share no kind name), only rolled up to axe tier 5 (`DailyData.VisitAreaMaxTier`), still three jobs a day. New save field `daily.areasToday` (ProfileSchema, idempotent Migrate). `DailyService.Area` is called from `BadgeService.OnNewArea` in `GameServer`; each area counts once a day, repeats finish the goal once.
- **Day counter**: `DayCounterLogic`; `QuestService.Start` stamps `profile.dayCounter` (stored as first world day + 1, 0 = unset; account-wide, as A1 made it) and sets the `FirstWorldDay` attribute; `WorldUI` shows "Day N" under the clock (not in HUD.luau, which is Lane U's).
- **Climate vignette** (`ClimateHudLogic`, `WorldUI`): frost or heat edge bands from the `ClimateKind` and `Exposure` attributes (HazardService sets `Exposure`, not `ClimateExposure`); the one-line first-time tip is a toast from `QuestService` saved in `tipsSeen` (`climate:cold`, `climate:heat`).
- **Gate signs** (`GateSignLogic`, `WorldUI`): signs tagged `GateSign` with a `GateId` attribute and a `State` TextLabel read "Protected" / "Open" (SaleGreen) or the requirement in words (StopRed), per player. The map now tags them (V1.1 polish leftovers, below): road gate signs and the Gondola sign carry `GateId` and a `State` label.
- **Rosa's Field Guide stamps** (`FieldGuideStamps`, `FieldGuideService.Stamp`): the first sale of each wood stamps it and pays 2 minutes of stage income; a finished biome page pays 6 (PROPOSAL amounts, rounded to $5). The guide's header shows "Stamps n of N. Secrets f of 5." (`SecretLogic.Count`).
- **Tutorial**: Skip shows on every step (still two taps); `tutorialSkipped` is a new slot save field; a skipper is paid the starter cash of the steps they skipped, once (`TutorialData.SkipCash`; nothing on a replay or refresher). Joy beat at the end of the lessons: banner naming the next goal, chime, confetti (`QuestUI.JoyBeat`).
- **NextGoal.PickV1**: the S1 to S8 ladder, one line of at most 40 characters (QuestService uses it). `GameConfig.V1Stages` does not exist on main, so the ladder reads `StageOf` and the gear and wood facts. DailyUI shows tomorrow's first goal greyed out.
- Region toasts show once per region per session (existing `RegionLogic.Toast`); Bayou (`bayou`) and Red Mesa (`redmesa`) are in `RegionLogic` now (V1.1 polish leftovers, below), so their first-visit toasts fire.
- UI renders: `previews/v1-e/ui-*.png` (`tools/preview/v1e_ui.py`), composites built from the UITheme tokens and DailyUI's own numbers, not engine screenshots.
- Not done: NPC part-count trim (14 NPCs at 55 to 88 parts; `tests/NPCPartCount.spec` pins a ceiling of 90), real-mesh NPC renders (no GLBs in the pack).

### Lane E: real NPC mesh renders (11 October 2026)

The five NPC GLBs (`assets/glb/backlog/npcs/<Name>/<Name>.glb`, from `phase-2/v1-glb-sources`) are in, and `previews/v1-e/real-mesh-*.png` are rendered with the real meshes (front = the dialogue pose facing the player, side, back; Rook at the mill pad facing the road; Murph beside them as a Studio-verified calibration figure). Tooling: `python3 tools/preview/npc_preview_meshes.py` writes `preview/npc-meshes.json` from the `TownModels` rows, then `PREVIEW_MESHES=preview/npc-meshes.json bash tools/preview/shoot.sh v1-e-npcs`. The viewer gained an opt-in manifest key `turn` (degrees): the GLBs' front is -Z and the game's import turns them a half turn (`TownModels.NpcMeshYaw`), so the NPC preview entries carry `turn: 180`; without it every NPC (Murph included) renders backwards.
Findings: every piece id, name and size in the five `TownModels` rows matches its GLB node (bounding boxes within 0.02) and has a `MeshTemplates` file; all five stand upright on their ground, face the player, hold their props (lanterns for the Hermit and Cap'n Moss, a pen for Old Tolly, none for Hank, a hand tool for Rook); no floating, sinking, clipping or mis-scaling seen, so no wiring change was needed. The part-built `foreman-layout-*-PART-BUILT.png` stay as the labelled fallback shots. Landmarks (booth, dock, cave, Land Office) are not built in this scene: each NPC stands on a grass patch at the real spot's height.

## Fix: world first look (branch `phase-2/fix-world-first-look`, 11 October 2026, draft PR)

Connor's bug report, items 12 to 14. Studio has not seen any of it.

- **12. TO THE WOODS sign.** The names were already the live ones (`BiomeData.displayName`, the same strings `RegionLogic` toasts use), but the sign only listed four places. It now lists every place a truck drives to, nearest first: Starter Forest 260, The Hills 420, Snowfields 650, The Volcano 700, Red Mesa 1200, Bayou 1330, one space between name and distance (the sign's rocks are seeded by its text length and NPCClearance pins Bram's route off them) (`BiomeData.SignDestinations`, `WorldPlan.WoodsSignLines`; Gloam Hollow, the boat island and the Aether Isles are left off). `WorldPlan.spec` pins that the sign text is built from that data. Renders: `previews/fix-world-first-look/` (scene `first-look`).
- **12. The dark board at the top centre of the first screen.** Not reproducible without Studio. The only board in that view is the sawmill's crest sign (TIMBERLINE SAWMILL, cream on dark brown, on two roof posts); at 1:19 AM it is a dark plank. It has its text in every render (`FirstLook.spec` pins it). The day start (item 13) is the fix for how it read. Also fixed, defensively: with `GameConfig.TownMeshes` on (off today), a sign mesh sat level with its board's text face; it now sits 0.04 behind it (`TownMeshes.SignFaceGap`, `TownMesh.spec`). If a dark blank board is still there in daylight, send a screenshot and the camera position.
- **13. Day start.** A fresh server opens at 08:00 (`GameConfig.StartClockHour`) of the same world day (`WorldClock.StartFresh`, from `MapBuilder` step 7; `WorldTime.FreshStart`). The day number is the real day, so no "Day N" moves: a new player is Day 1 at 8 AM, a returning player keeps their stamp. A clock an owner already set is left alone, `/timereset` still goes back to real time. New players who join a server that is already at night still see its night (one shared clock).
- **14. Lux Axe.** Two ways a $35 player could hold it: in Studio `MonetizationService.PlayerJoined` asked Roblox who owns the pass, and a Studio session runs as the creator; and a Studio test buy saved the axe into the profile (then `accountAxes` kept it on every slot). Now Studio ignores the ownership answer (a pass comes from the save, an owner grant or a test buy), and a Studio test buy gives the axe for the session only (`PaidItems.SessionOnlyAxe`, `AxeService.Ensure(..., sessionOnly)`). Outside Studio nothing changes. A new profile has the Rusty Axe, the Hammer and the Rusty Pick only (`ProfileSchema.spec`). No prices or sale lists touched. A Studio profile that already saved the Lux Axe keeps it: use the hub's Paid items, take back.
## Startup errors (branch `phase-2/fix-startup-errors`, 11 October 2026)

From Connor's Studio log:
- **Analytics progression.** `LogProgressionCompleteEvent` takes `(player, path: string, level: number, levelName: string?)`; we passed the stage name as the level, so Roblox failed with "Unable to cast string to int". `GameAnalytics.Progression(player, path, level, levelName)` now sends the stage number as the level and "S1" as its name; the Sky Charter steps (`SkyQuestService`) go through it too. Non-whole levels and non-int funnel steps are dropped before the call. Every call stays in a pcall. The funnel, custom and economy argument orders were checked against the API and were right. `AnalyticsEvents.spec` asserts the type of every argument of every event.
- **Camera speed** dropped (above).
- **Murph's Talk prompt.** NPCs the tutorial depends on (Murph, Old Hank) carry `persistent = true` in `NPCData`; `NPCService` sets ModelStreamingMode Persistent from it (Murph was already; Old Hank is new). `QuestUI` now waits for the prompt with a bounded `WaitForChild` (`QuestUI.TalkWait`, 15 s) and, on a miss, warns and shows a line in Murph's card telling the player to follow the arrow to his camp.
- Studio checks: PHASE2_NOTES.md "Startup errors".

## Grab on the right trigger (Xbox)

Connor's call: the pad's grab goes back to the right trigger (RT), the same button as chop, because most players put the axe away to carry. The rule is still that no code BINDS the trigger. `DragController` READS it (an `InputBegan`, never a ContextActionService bind), and only with empty hands: `GrabLogic.PadGrabAllowed(toolOut, placing)` is false with a tool in hand (the engine fires `Tool.Activated` on RT, which is the swing, and the grab ignores it, so no toast and no grab) and false while the placer is up. RB no longer grabs: it stays the builder's select, the wire pick and the placer's push. The key is named once in the source, as `GrabLogic.PadGrabKey` (InputKit's key table and DragController read it from there). `tests/NoButtonR2.spec` fails on any other mention of the button, on a second use, and on any ContextActionService line that takes the key. Hints say RT now ("hold RT", "Hold RT on wood to drag it"). PC and phone are unchanged.
