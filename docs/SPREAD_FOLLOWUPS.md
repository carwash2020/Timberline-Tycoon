# Spread follow-ups: the facts behind four open questions

Report only. Nothing in the game changed: no tree, rock, prop, price, StoreData, Economy, Net or ProfileSchema line. This file and the PR body hold the same lists. Measured on main `1fcbf53` (#219) with read-only scripts (the two tools in `tools/` plus scratch scripts that were not committed).

## 1. Economy proof: `lune run tools/economy --check`

Main (`1fcbf53`, a clean worktree), complete output:
```
ECONOMY.md is up to date.
exit 0
```
This branch (main plus this report file), complete output:
```
ECONOMY.md is up to date.
exit 0
```
**Identical** (byte for byte, `cmp` reports no difference). The plain `lune run tools/economy` output (the full headline table, which also rewrites ECONOMY.md) is identical on both and leaves `git status` clean:
```
Wrote ECONOMY.md
| First sale | under 3 min | 68 s | ✅ on target |
| Steel Axe ($110) | 5-8 min | 5.4 min | ✅ on target |
| First $1k earned | 15-20 min | 15.4 min | ✅ on target |
| Cobalt Axe ($2,500) | about 1 h | 48.2 min | ✅ on target |
| Full plot ($2,280,100) | 28-36 h | 31.4 h | ✅ on target |
| First sale (E1) | under 3 min (0–180 s) | 68 s |
| Steel Axe (E2) | 5–8 min inclusive (300–480 s) | 327 s |
| First $1k (E3) | 13–20 min (780–1200 s) | 921 s |
| Cobalt Axe (E4) | 45–75 min (2700–4500 s) | 2894 s |
| Full plot (E4) | 28–36 h (100800–129600 s) | 113138 s |
| Steel Axe | 6 | 13 | 27 | 25 | 7 | 35 | 33 | 45 | 66 | 145 | 28 | 74 | 9 | 34 |
| Cobalt Axe | 2 | 5 | 10 | 9 | 3 | 12 | 12 | 16 | 23 | 50 | 10 | 26 | 3 | 12 |
```

## 2. Full check

`./scripts/check.sh` on main `1fcbf53` (clean worktree): **4471 passed, 0 failed, All checks passed** (StyLua, Selene, luau-lsp, Lune tests, ECONOMY.md, ASSETS.md). The result for this branch is in the PR body. Nothing failed, so no fix commit was needed.

## 3. The 13 remaining overlap hits

Rules and shapes are in `Shared/World/OverlapCheck.luau`. Gap is edge to edge in studs (a tree is a disc of trunk radius plus 1; negative means the two overlap by that much; the boulder rule asks for a gap of at least 2). Zone is the nearest BiomeData or region disc by edge distance (the north strip and the Reach have no disc). All 13 involve a fixed tree, so none was moved, thinned or dropped, and boulders and scenery never move.

| # | tree | overlaps | gap (studs) | zone | fixed? |
|---|---|---|---|---|---|
| 1 | trees#698 emberwood at (464.7, 392.3) | boulder: boulder#67 at (466.4, 393.7) | -5.48 | volcano (inside the disc) | FIXED (volcano supply tree) |
| 2 | region#2 bogcypress at (-812.2, -602.5) | boulder: boulder#55 at (-816.8, -602.1) | 0.16 | bayou (inside the disc) | FIXED (Bayou or Red Mesa supply tree) |
| 3 | region#43 bogcypress at (-781.0, -587.2) | boulder: boulder#7 at (-776.5, -588.6) | -2.81 | bayou (inside the disc) | FIXED (Bayou or Red Mesa supply tree) |
| 4 | added#78 emberwood at (534.2, 475.8) | boulder: boulder#22 at (537.8, 478.5) | -0.34 | volcano (inside the disc) | FIXED (added tree, T323 rows) |
| 5 | strip#2 maple at (72.5, 962.6) | scenery piece: scenery#71 RuinedCabin at (81.0, 971.1) | -1.16 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: ? |
| 6 | strip#25 birch at (72.5, 977.4) | scenery piece: scenery#71 RuinedCabin at (81.0, 971.1) | -2.19 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: ? |
| 7 | reach#5 phantomwood at (252.8, -746.9) | scenery piece: scenery#60 Outcrop at (240.2, -750.1) | -4.06 | meadow (no zone within 60 studs) | FIXED (Petrified Reach tree); the other tree: ? |
| 8 | trees#238 oak at (639.8, -869.2) | another tree: region#69 ironwood at (638.4, -866.7) | -1.41 | mesa (inside the disc) | FIXED (one of the first 331 trees); the other tree: FIXED (Bayou or Red Mesa supply tree) |
| 9 | trees#255 oak at (522.4, -715.3) | another tree: region#49 ironwood at (518.4, -714.0) | 0.03 | mesa (inside the disc) | FIXED (one of the first 331 trees); the other tree: FIXED (Bayou or Red Mesa supply tree) |
| 10 | strip#14 maple at (103.5, 965.3) | another tree: strip#33 birch at (103.5, 959.7) | 1.60 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: FIXED (north strip tree) |
| 11 | strip#15 maple at (112.5, 962.4) | another tree: strip#32 birch at (112.5, 962.6) | -3.78 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: FIXED (north strip tree) |
| 12 | strip#17 maple at (-107.5, 977.6) | another tree: strip#40 birch at (-107.5, 977.4) | -3.78 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: FIXED (north strip tree) |
| 13 | strip#18 maple at (-116.5, 974.7) | another tree: strip#39 birch at (-116.5, 980.3) | 1.60 | meadow (no zone within 60 studs) | FIXED (north strip tree); the other tree: FIXED (north strip tree) |

Tree ids read `<list>#<index>`: `trees` is WorldPlan.Trees (the first 331 are fixed), `region` RegionTrees, `added` AddedTrees, `strip` StripTrees, `reach` ReachTrees.

### The four cells still over 25 trees (100x100, every tree counted)

| cell corner | trees | zone |
|---|---|---|
| (0, -200) to (100, -100) | 43 | starter (inside the disc) |
| (-500, 100) to (-400, 200) | 37 | hills (inside the disc) |
| (900, -100) to (1000, 0) | 27 | ferryisle (inside the disc) |
| (-100, -300) to (0, -200) | 26 | starter (inside the disc) |

All four hold no movable tree, so they are the named exemptions in `TreeSpreadThin.spec` and `TreeSpreadRows.spec`. The Ferry Isle cell is palms (FerryPalms, not part of BiomeData.trees).

## 4. T366: the supply trees that could not be moved

Measured by re-running `tools/spread_supply` on `a5bbaea` (main just before #219, so the 9 trees that did move are still in place and the rule runs from the same start). Candidate tree indices are the same on main. The rule: cells over 22 trees (over 24 for the one that holds 27), supply trees after the first 331, interior first, never a large-class tree (a clump anchor), Murph's oaks, NearGrove trees or a first tree; a destination must be in the same zone disc, on legal ground, 10 studs from every tree, 2 off a rock, in a cell that finishes at 22 or fewer, **and have the same size class** as the tree.

**A correction to #219's body.** Its table said Hills (-500,100) could not place 13 and Starter (0,-200) 19; that came from an earlier run before I changed the limit of the 44-tree cells from 24 to 22. The right figures are below. The "40" in #219 is right: it is the number of candidate trees that were tried and could not be placed.

| cell corner | zone | held | limit | needed to move | moved | shortfall | candidates tried and failed |
|---|---|---|---|---|---|---|---|
| (-500, 100) | hills | 44 | 22 | 22 | 7 | 15 | 12 |
| (-500, 200) | hills | 23 | 22 | 1 | 0 | 1 | 6 |
| (-400, 100) | hills | 23 | 22 | 1 | 0 | 1 | 3 |
| (-100, -300) | starter | 27 | 24 | 3 | 1 | 2 | 3 |
| (0, -200) | starter | 44 | 22 | 22 | 1 | 21 | 16 |
| (900, -100) | ferry isle palms | 27 | 24 | 3 | 0 | 3 | 0 (palms are not supply trees) |
| total | | | | 52 | 9 | 43 | 40 |

The shortfall (43) is bigger than the 40 candidates: the other 3 are the Ferry Isle palms, and in the two 44-tree cells the rest of the trees are ones the rule never moves (first 331 trees, anchors). In the two 23-tree cells every eligible candidate was tried (6 and 3) and none found a place, though only one move was needed in each.

Reasons: **16 of the 40 have no capacity left in the zone disc** (all of Starter (0,-200)); **24 have capacity left in the disc but no legal spot with their size class** (all of Hills, and the 3 in Starter (-100,-300)). Neither the cell cap, a clearance (rocks, gap, ground) nor a pin was the deciding reason for any tree: the capacity table already folds ground, rocks and the gap in, and the pins were re-pinned. By zone: starter 19 trees, hills 21.

### Hills: 21 trees
| tree index | wood | cell corner | at | size class | why it could not move |
|---|---|---|---|---|---|
| 579 | maple | (-500, 100) | (-401.5, 187.5) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 580 | maple | (-500, 100) | (-491.3, 155.1) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 585 | maple | (-500, 100) | (-417.6, 173.6) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 591 | maple | (-500, 100) | (-470.4, 181.9) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 606 | pine | (-500, 100) | (-402.8, 117.7) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 608 | pine | (-500, 100) | (-419.9, 183.5) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 611 | pine | (-500, 100) | (-485.0, 145.7) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 616 | pine | (-500, 100) | (-451.4, 200.0) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 626 | pine | (-500, 100) | (-494.8, 136.9) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 627 | pine | (-500, 100) | (-406.1, 171.3) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 632 | pine | (-500, 100) | (-477.5, 164.3) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 636 | pine | (-500, 100) | (-460.3, 119.2) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 578 | maple | (-500, 200) | (-460.6, 209.6) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 597 | maple | (-500, 200) | (-461.2, 244.0) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 605 | pine | (-500, 200) | (-473.2, 231.5) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 619 | pine | (-500, 200) | (-451.1, 237.3) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 621 | pine | (-500, 200) | (-483.3, 232.5) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 622 | pine | (-500, 200) | (-420.8, 223.0) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 592 | maple | (-400, 100) | (-384.2, 156.2) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 601 | pine | (-400, 100) | (-369.8, 115.0) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 602 | pine | (-400, 100) | (-375.9, 125.3) | normal | size class: capacity left in the disc, but no legal spot has this tree's size class |

### Starter: 19 trees
| tree index | wood | cell corner | at | size class | why it could not move |
|---|---|---|---|---|---|
| 540 | birch | (-100, -300) | (-63.6, -253.8) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 555 | oak | (-100, -300) | (-45.0, -287.0) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 557 | oak | (-100, -300) | (-29.0, -267.0) | small | size class: capacity left in the disc, but no legal spot has this tree's size class |
| 534 | birch | (0, -200) | (62.1, -130.0) | normal | no capacity left in the zone disc |
| 539 | birch | (0, -200) | (32.2, -153.6) | small | no capacity left in the zone disc |
| 543 | birch | (0, -200) | (33.2, -129.7) | small | no capacity left in the zone disc |
| 548 | oak | (0, -200) | (80.9, -171.0) | small | no capacity left in the zone disc |
| 549 | oak | (0, -200) | (75.4, -140.8) | normal | no capacity left in the zone disc |
| 552 | oak | (0, -200) | (95.6, -176.3) | normal | no capacity left in the zone disc |
| 554 | oak | (0, -200) | (41.3, -119.3) | normal | no capacity left in the zone disc |
| 559 | oak | (0, -200) | (52.6, -186.1) | normal | no capacity left in the zone disc |
| 560 | oak | (0, -200) | (23.0, -187.0) | small | no capacity left in the zone disc |
| 561 | oak | (0, -200) | (23.0, -139.0) | small | no capacity left in the zone disc |
| 562 | oak | (0, -200) | (70.8, -106.6) | normal | no capacity left in the zone disc |
| 564 | oak | (0, -200) | (74.3, -128.2) | normal | no capacity left in the zone disc |
| 566 | oak | (0, -200) | (46.2, -136.5) | normal | no capacity left in the zone disc |
| 570 | oak | (0, -200) | (71.0, -175.0) | small | no capacity left in the zone disc |
| 572 | oak | (0, -200) | (91.0, -151.0) | normal | no capacity left in the zone disc |
| 573 | oak | (0, -200) | (99.0, -187.0) | small | no capacity left in the zone disc |

### Capacity left in every zone disc after the 9 moves (room up to 22 per 100x100 cell; legal spots counted on a 4 stud grid with the 10 stud gap, ground, rocks)

**Starter** (cell corner: trees held, room left up to 22)

| cell corner | holds | room left |
|---|---|---|
| (-200, -400) | 5 | 0 |
| (-200, -300) | 7 | 0 |
| (-100, -400) | 6 | 0 |
| (-100, -300) | 26 | 0 |
| (0, -200) | 43 | 0 |
| (0, -100) | 15 | 0 |
| (100, -200) | 12 | 0 |
**Hills** (cell corner: trees held, room left up to 22)

| cell corner | holds | room left |
|---|---|---|
| (-700, -100) | 1 | 0 |
| (-700, 100) | 1 | 0 |
| (-700, 200) | 4 | 1 |
| (-600, -100) | 8 | 0 |
| (-600, 0) | 5 | 0 |
| (-600, 200) | 4 | 1 |
| (-500, -100) | 21 | 0 |
| (-500, 0) | 22 | 0 |
| (-500, 100) | 37 | 0 |
| (-500, 200) | 23 | 0 |
| (-400, -100) | 4 | 0 |
| (-400, 0) | 11 | 0 |
| (-400, 100) | 23 | 0 |
| (-400, 200) | 2 | 0 |
**Snow** (cell corner: trees held, room left up to 22)

| cell corner | holds | room left |
|---|---|---|
| (-200, 600) | 0 | 1 |
| (-200, 700) | 2 | 2 |
| (-200, 800) | 3 | 0 |
| (-100, 600) | 12 | 10 |
| (-100, 700) | 21 | 1 |
| (-100, 800) | 12 | 5 |
| (0, 600) | 14 | 8 |
| (0, 700) | 19 | 3 |
| (0, 800) | 2 | 5 |
| (100, 600) | 0 | 2 |
| (100, 700) | 5 | 3 |
| (100, 800) | 6 | 0 |
**Volcano** (cell corner: trees held, room left up to 22)

| cell corner | holds | room left |
|---|---|---|
| (300, 300) | 0 | 1 |
| (300, 400) | 8 | 14 |
| (300, 500) | 11 | 11 |
| (300, 600) | 0 | 1 |
| (400, 300) | 6 | 10 |
| (400, 400) | 13 | 9 |
| (400, 500) | 18 | 4 |
| (400, 600) | 2 | 5 |
| (500, 300) | 0 | 1 |
| (500, 400) | 11 | 11 |
| (500, 500) | 3 | 9 |
**Grove** (cell corner: trees held, room left up to 22)

| cell corner | holds | room left |
|---|---|---|
| (-100, -800) | 5 | 17 |
| (-100, -700) | 2 | 13 |
| (0, -800) | 10 | 12 |
| (0, -700) | 10 | 12 |


Snow, Volcano and Grove have room but no cell over 22, so nothing there needed to move. Starter has no room left anywhere; Hills has 2 spots left (cells (-700, 200) and (-600, 200), one each), and neither matches the size class of any waiting tree.
