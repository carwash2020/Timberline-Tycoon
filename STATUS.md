# STATUS: read this first in a new session

Last updated 6 October 2026 (branch `claude/short-tutorial`). Keep this file current: update it in the same PR as any change that moves a goal, a rule below, or an open question. Older plans (HANDOFF.md, MORNING_HANDOFF.md) are history; this file wins when they disagree.
Last updated 6 October 2026 (branch claude/restore-meshes, on top of PR #70). Keep this file current: update it in the same PR as any change that moves a goal, a rule below, or an open question. Older plans (HANDOFF.md, MORNING_HANDOFF.md) are history; this file wins when they disagree.

## Who and how

- Owner: Connor. A beginner on Windows PowerShell (also has a Mac): give commands one per line, never chained with `&&`, and never print secrets.
- Connor tests in Roblox Studio; Claude cannot run it. Every change ships with the exact Studio checks to do and what good looks like.
- Standing instruction: open a PR, subscribe to it, and merge when CI is green (squash, with `expectedHeadSha`). Do not open a PR unless asked, but Connor has asked for merge-when-green on this work stream.
- Commits: `phase-2: <what changed>`. Verify with `./scripts/check.sh` before pushing (the real exit code).
- Update commands to give Connor after a merge (PowerShell, one per line): `cd C:\Users\nicho\timberline-tycoon`, `git checkout main`, `git pull`, `rojo serve`.

## Where the game is

The live core loop is v2 (`GameConfig.CoreLoop = 2`). The v1 code stays for a rollback until M1.10. Plans: V2_PLAN.md (v2), V1_PLAN.md, GAME_DESIGN.md (§14 spec, §8 milestones, §9 automation rules, §15 materials). Playtest checklists: PHASE1_NOTES.md, PHASE2_NOTES.md.

- **Building is the hammer plus physical blueprints** (branch `claude/hammer-build`, not merged yet; BUILD_SYSTEM.md is the design note and decision list, PHASE2_NOTES.md the Studio checklist). Everyone has a Hammer; a blueprint is a Tool you buy, carry, drop and use once to own that building for good (`profile.blueprintBook`); the hammer opens the list, places, and moves, turns or sells what you built. The BUILD toggle and its HUD button are gone. Everything that was free to place before is in every book from the start, so no price moved.

### Rules decided by Connor (do not undo without asking)

- **Prices build up.** The more valuable an item, the higher its cost; the first step up the axe ladder is cheap and each next one costs more. One price per item shown to players, never two numbers and never "u³" in player text.
- **Rarer wood and its planks sell for more** (WoodData `RareBoost`), to reward people who go get the better stuff. Full plot is about 30 h.
- **No free plot.** A player buys their first plot at the Land Office counter: `GameConfig.PlotPrice` = $150. Murph's plot tutorial step pays back $175 (the plot plus the Rustbucket's $25 over its old price) so the economy headlines hold. Saves that already own a plot keep it. Plots start small (80) and grow in tiers 80/110/140/170/200, each homestead with its own look. A plot's ground is bare dirt, never grass: `PlotData.Looks` use Ground/Sand/Slate/Mud, the terrain under a pad paints Ground (`TerrainGen.SurfaceMaterial`), no decor spawns on it (`EnvironmentData.DecorBlocked`); the country keeps its grass in the blend outside. `TreeFill.PlotRings` adds up to 12 choppable trees (oak/birch/pine/maple of the region, 'wild' biome, one small regrow zone per cluster) just past each pad's 56-stud blend, leaning toward the forest side; skipped inside the phone discs (QUIET). Not in BiomeData counts, so the economy model is unchanged.
- **No vehicle without a pad.** Every vehicle comes boxed; the box becomes a pad on the player's plot and the pad has the respawn button. The Rustbucket is purchased, not free: **$100**. Bigger vehicles cost more (400 / 2,500 / 5,000 / 19,000; trailers 1,800 / 6,000 / 13,000) so keeping one vehicle has value.
- **Respawn fee** = 5% of the vehicle's price, minimum $5 (`ShopLogic.RespawnFee`, `VehicleLogic.PadFee`). Each vehicle's first two spawns are free (`VehicleLogic.FreeSpawns = 2`) so a lost truck can never soft-lock a player. Recall, pad Press and Equip share one per-pad `presses` counter, and swapping vehicles charges. Tow Service makes recall free.
- **Owner tools are ONLY Connor's.** Chat commands (cash, free gifts, kick, ban, teleport, announce, super run, time speed and set hour), plus an Xbox owner menu (OWNER button or L3+R3). The server checks `AdminLogic.IsOwner` on every request (OwnerUserIds list, or the experience creator, or Studio); the client `IsOwner` attribute is for UI only and the server never trusts it. See OWNER_TOOLS.md. **Connor must paste his UserId into `AdminLogic.OwnerUserIds`** (not done yet).
- **Xbox:** LT hangs a held piece and the right stick turns it; RB/LB push and pull; longer reach. Blueprints use their own scheme (LT lock, stick flicks, RB/LB slide). HudRules forbids extra D-pad binds.
- **Scope guardrails:** milestones in GAME_DESIGN §8 (the core feels good, then retention such as seasons, festivals and companies, then more content). Gathered materials need a job and a home biome. Wallet cap $2,000,000.

### How plots work

14 pre-built homestead pads (`PlotData.Homes`), one per player slot plus two spares. A player buys one at the Land Office (`PlotService.Claim`, range-checked, charged once, refunded if the build fails). It starts as an 80-stud Campsite and grows through tiers 80/110/140/170/200 ($2,500 / $10,000 / $30,000 / $60,000), plus individually bought 40-stud squares out to a 5x5 grid (square k costs `ExpansionPriceStep` 3050 x k; the first costs `FirstPlotPrice` 100). Builds are saved in plot-local studs so a layout loads on any pad. Limits: 200 prebuilt pieces and 400 kit pieces; selling returns half. Rules live in `PlotData` and `PlotLogic`, the server side in `PlotService`. Tier and square prices are a first pass and are not tuned in the economy model yet.

### Economy model

`lune run tools/economy` (v2) and `lune run tools/economy1` (v1) regenerate ECONOMY.md and ECONOMY_V1.md; commit them with any balance change. The headline times are strict CI ranges: first sale under 3 min, Steel Axe 5–8 min, first $1k 13–20 min, Cobalt 45–75 min, full plot 28–36 h. The headline strings are also pinned in the Builder, BuildingKit and TownMesh specs, and the tutorial's plot reward is pinned in TutorialData.spec. Retired tutorial step ids are save-migration keys: never reuse or reorder them. If a price change breaks a range, retune a reward or price rather than loosening the range. A model that hangs (instead of failing) usually means the simulated player cannot afford the next purchase and earns $0/h (it did when the Rustbucket went to $100 before the plot was priced in).

### Load time (LOAD-01, 6 October 2026)

Connor reported a very long start. Measured in Lune (slower than Roblox, so use the ratios): the world plan for 1,157 forest trees costs about 6.5 s, the terrain is 144+ chunks of heights (about 20 us a height), and ~1,400 section trees are about 43 Instances each (~60k). All of it ran before the sell area, so players waited for every tree. Now the forest is planted after SellArea (near the sawmill first, 20 ms a frame; `MapBuilder` `forestPlanter`, `SectionTrees.OnPlanted` gives late trees their figure, `WorldClock.Refresh` re-applies night-only woods), the client's filler plan waits for the player to be in, and terrain yields by time. `[Load]` lines in Output (server: per MapBuilder step with timings, forest planned/planted, GameServer slow hooks and "can play"; client: module/controller Start times) say where time goes: ask Connor for them. Still serial and unmeasured in Studio: terrain writing (Prebuilt bake in HANDOFF.md removes it), PlotService's 14 pads (small).

## What has landed (newest first, PR numbers on main)

- Not on main yet: `claude/hammer-build` (the hammer and physical blueprints, above).
- claude/fix-pumpkins-npcs (branch, no PR yet): pumpkin patches no longer half sunk (PivotTo on a bbox pivot), town decor lifted onto the drawn ground, `FacingLogic` for NPC facing plus a spec, forward walk lean, shorter and muted grass tufts. Night blue ground plane at spawn not reproduced; see PHASE2_NOTES.md.
- Branch `claude/short-tutorial` (not yet a PR): the v2 tutorial is 8 steps (fell, drag, sell, plot, one build lesson, truck box, pad, spawn; the axe, mill and load steps are retired in `TutorialData.RetiredV2`, saves migrate forward in `ApplyOrder` order 6); `NoticePolicy` governs every toast (priorities, one non-critical at a time, cooldown, dedupe, quiet during the first-sale flow). Economy unchanged. Checks in PHASE2_NOTES.md.
- claude/fix-felling (branch, not merged): trees fall where you cut them (stump stays rooted, only the trunk above the cut falls; was #36's "ground cut frees the whole section"), rigid fall with velocity caps, layered procedural fell sound (`FellSoundId` still overrides), swing pose re-applied pre-render with a tool-grip fallback. Checklist in PHASE2_NOTES.md.

- Old Hank, the plot salesman (branch claude/plot-salesman, not a PR yet): an old farmer NPC behind the Land Office counter, always there. His offers are data (`Shared/PlotSalesmanData`; today only "Buy a plot" at `GameConfig.PlotPrice`); Talk runs the same `PlotService.Claim` flow. New offers: add to `Offers` and `PlotService`'s `SALESMAN_OFFERS`. Checklist in PHASE2_NOTES.md.
- Branch `claude/hud-clock-owner` (not yet a PR): corner chips raised into the top bar, 12-hour AM/PM clock everywhere (`WorldTime.Format`, shop-hour lines), owner time tools (`/timespeed`, `/settime`, `/timereset` and the menu; not saved), shopkeeper card above the hotbar, smooth slower sawmill blade (TownFX, per frame).
- #70 plot bought at $150, Rustbucket $100, respawn fees, economy retuned (in review when this was written).
- #69 vehicle always has its own pad; Rustbucket boxed. #68/#67 owner menu (Xbox). #66 Xbox carry and build controls. #65 building fixes on the 80 plot (bought squares, collision boxes for mills and the chop saw, 10-stud pad grid). #64 owner chat tools. #63 rare wood and plank prices. #62 axe price ladder. #61/#60 one price, no u³. #59 build-check print at map start. #58 smaller starting plot and homestead looks. #57 HUD corner, run, ground and mesh fixes.
- Before that: boxed stores, plot visits, wire tool, ferry, NPCs, badges, day/night, W1–W4 world work (see `git log`).

## Meshes (Blender models)

`GameConfig.TownMeshes` is **true** again (kill switch: false, or the Studio workspace attribute `TownMeshes`); town meshes are ground-snapped to the part-built art. Axes, trees, NPCs, vehicles and the plot kit all load through `MeshKit.Create`; a failed load falls back to part-built art and now warns with the engine's error, and the `[MapBuilder] build check:` line prints the load totals. The ids belong to creator `Elucidhealer618`: if the Output says meshes failed, fix asset permissions in Creator Hub (steps and ids in PHASE2_NOTES.md, "Blender meshes are back on"). Shelf boxes show no axe model by design (#42/#51).

## Open items

1. **Studio verification** of everything above (and the hammer build, PHASE2_NOTES.md 'The hammer and physical blueprints'), none of it has been seen in Studio: Land Office purchase, boxed truck and pad flow, free first respawns, Xbox controls, owner menu. Checklists in PHASE2_NOTES.md.
2. **Not reproduced without Studio:** signs, roof and buildings sinking under the map. Mitigations shipped (`standOnGround` lift, `TownMeshes = false`, a build-check print). Connor should send the `[MapBuilder] build check:` Output line, screenshots, and any red/orange Output.
3. **Questions for Connor:** should Cabin, Warehouse and the other pieces that were free to place also need a bought blueprint (they would need prices and a build sink in the economy model)? Should world-found blueprints spawn anywhere yet (the machinery exists)? A real trade window (yes/no)? Lanternwood economy numbers (proposal in MORNING_HANDOFF.md)? Badge IDs? Is the Rustbucket recall fee of $5 (not free) acceptable?
1. **Studio verification** of everything above, none of it has been seen in Studio: Land Office purchase, boxed truck and pad flow, free first respawns, Xbox controls, owner menu. Checklists in PHASE2_NOTES.md.
2. **Not reproduced without Studio:** signs, roof and buildings sinking under the map. Mitigations shipped (`standOnGround` lift, a mesh ground snap, the `TownMeshes` kill switch, a build-check print). Connor should send the `[MapBuilder] build check:` Output line, screenshots, and any red/orange Output.
3. **Questions for Connor:** a real trade window (yes/no)? Lanternwood economy numbers (proposal in MORNING_HANDOFF.md)? Badge IDs? Is the Rustbucket recall fee of $5 (not free) acceptable?
4. The v1 rollback loop still charges the plot with no Murph payback (ECONOMY_V1.md shows the Steel Axe at 18 min). Fix only if v1 is ever re-enabled.
5. A tutorial skipper or replayer pays the full $150 with no Murph payback.

## Tooling notes

- Toolchain via Rokit (`bash scripts/cloud-setup.sh` on Linux). `lune run tests/run [Name]` runs one spec. `bash tools/preview/shoot.sh <scene>` renders a scene to `preview/` for art or world changes.
- `./scripts/check.sh` takes several minutes (WorldPlan.spec alone is about a minute); run it in the background or with a long timeout, since foreground commands time out near 600 s.
- Do not use `pkill -f` patterns that match your own shell.
