# Render check (T409)

What to look at before and after any art, layout or world change, without Studio. Each scene is rendered
with `bash tools/preview/shoot.sh <scene> <view> [WIDTHxHEIGHT]`, which writes `preview/<scene>-<view>.png`
(the folder is gitignored: keep the before and after pairs next to the PR, or attach them). Take every
shot before the change and again after, on the same view numbers, and compare. Every scene gets a
top-down shot, a player-eye shot and a phone frame (`844x390`, the HUD's phone profile).

The shots show geometry, colour and layout only. They do not show physics: belts carrying wood,
logs sliding down the slip, doors opening and the ferry stay Studio checks.

Baseline taken at the T409 head (no art change in this PR: the only code that touches the world is the
`InvisibleBlocker` attribute on invisible blockers, which draws nothing). Views are the scene's own numbers
(the camera list in `tools/preview/scenes/<scene>.luau`).

| # | Scene | Preview scene and views | Top-down | Player eye | Phone | What changed | What must not change |
|---|-------|--------------------------|----------|------------|-------|--------------|----------------------|
| 1 | Spawn town | `town` | view 2 (aerial) | view 1 (from the spawn) | `town 1 844x390` | nothing | the street, the sawmill facing the spawn, shop fronts, lamps, signs |
| 2 | Sawmill | `town` view 1 (the mill dead ahead), `buildings` (the mill on its own) | `buildings` overhead cameras | `town` view 1 | `town 1 844x390` | nothing (the Sawmill GLB is unchanged) | the slip, the carriage and the headrig stay clear of posts; the front door stays open |
| 3 | Sale area | `pads`, `town` view 1 | `pads 1` | `town` view 1 | as the eye shot | nothing | the SellPad stays flat and walkable (CanCollide off), the zone's size and place |
| 4 | Yard and plot with a belt into a mill | `plot`, `machines` | `plot 1` | `plot 3` | `plot 3 844x390` | nothing | the mill's Intake and Output, planks leaving past the Output. Belt physics is a Studio item |
| 5 | Store interiors | `stores` (Tool Shed 1 and 2, Hearth and Home 3 and 4, Dealership 5) | views 1, 3, 5 | views 2, 4 | `stores 2 844x390` | nothing: each shop front door and counter as on main today | front Door, back door, Counter, shelf and display table places (tests/mustkeep.json) |
| 6 | Roads, paths, bridges | `roads`, `landmarks` | `roads 3` | `roads 1`, `landmarks 2` | `roads 1 844x390` | nothing | the fork, the footbridge, path widths |
| 7 | Cabin and camp | `town` (Murph's camp, view 7) | view 2 | view 7 | `town 7 844x390` | nothing | the camp's tents and fire against the spawn walk |
| 8 | Biome gates | `world` views 4 to 6 | not rendered here (heavy: up to 3 minutes a view) | not rendered here | not rendered here | nothing | the gate signs and road ends |
| 9 | Sky island forges | `isles`, `gate-lodge` | `gate-lodge` 1 | `gate-lodge` 2 and 4 | `gate-lodge` 2 | the gondola is gone; the gate lodge is the north-road checkpoint (`gate-lodge` views 1–4, `town` view 6 is the old station pad) | isles still float; shops, ferry, sell pad |

## What was actually rendered for the baseline

Rendered in the build environment with `shoot.sh` (software GL, so lighting is flatter than Studio): `town`
views 1 (eye, 1280x800 and phone 844x390) and 2 (aerial), `stores` views 1 and 2, `roads` views 1 and 3,
`plot` views 1 and 3, `machines` 1, `pads` 1, `landmarks` 2. Scenes 8 and 9 were not rendered, and the
phone frame was shot for the town only. The PNGs are not committed (gitignored), so a reviewer re-runs the
commands above.

## How to use it

1. Before the change: shoot the scenes the change can touch (`bash tools/preview/shoot.sh town 1`, and so on), and copy `preview/*.png` to a folder called `before`.
2. After the change: shoot the same views, copy to `after`.
3. Put each pair side by side in the PR with one line each for what changed and what must not have.
4. The numbers behind the pictures are in CI: `tests/GeometryLint.spec` (nothing solid shares space), `tests/MustKeep.spec` (the doors, counters, spots and machine ends stay put), `tests/PipelineE2E.spec` (the core loop) and the `cloud-test` job.

## T409 round 1: before and after renders

`preview/t409/before` is origin/main (878c4ce) and `preview/t409/after` is this branch, same scenes and
views (`bash tools/preview/shoot.sh <scene> <view>`): town 1 and 2, town 1 at 844x390, stores 1 and 2,
roads 1 and 3, plot 1 and 3, machines 1, pads 1, landmarks 2. `sawmill-lanes` (views 1 to 4) draws the
lane and door boxes from `Shared/Lint/LaneData` over the sawmill (the "before" side uses the same boxes
over the old sawmill). These are flat-colour previews, not Studio.

## T409 ground cameras

`bash tools/preview/shoot.sh t409-ground <view>`. The mesh is sampled every 2 studs so the few-stud belt beside a road is in the picture. `preview/t409/before/t409-ground-*.png` is origin/main (`a276c1b`). `preview/t409/after/t409-ground-*.png` is this branch.

| View | File | What it shows |
|------|------|----------------|
| 1 | `t409-ground-1.png` | Frostpeak meets Skyroot, top down. The snow edge is a dithered belt. |
| 2 | `t409-ground-2.png` | Gate lodge on the Skyroot approach. |
| 3 | `t409-ground-3.png` | Valley Trunk belt, cross section. The bed is warm RoadGravel `#A8A49C`. The same camera on main is the old dark `#55585A`. |

The town, roads, plot and store pairs above are the round-1 set. Several of those afters match their befores: those scenes do not draw this ground.
