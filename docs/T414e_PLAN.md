# T414e plot pads, mining nodes, town board and boxes

Goal: plot pads get a built stone curb and dirt rim that logs slide off, mining nodes read as real rock with ore veins, the town board reads at phone distance, and item boxes are kraft cardboard instead of glass. Vision rows 43, 47, 49. No economy, StoreData, ProfileSchema or remote change.

## Files

- `Shared/PlotPlatform.luau`: each exposed edge becomes a StoneBase `Curb` strip (top flush with the pad top, step 0.03) plus a TrailDirt `Ramp` wedge that slopes from the curb to the terrain. Layout, Origin and the slab rects are unchanged, so saved plots load as before.
- `Shared/Art/NodeArt.luau` (new, pure) and `ServerScriptService/NodeService.luau`: the node look is a rock cluster (CliffRock / QuarrySlate, no cubes) with Amber or Garnet ore veins. The hit box, attributes, tag, hits, yield and respawn are untouched.
- `ServerScriptService/UndergroundBuilder.luau`: the Rubble model keeps its name, tag, attributes and 12-part cap, but is boulders instead of eight cubes.
- `Shared/Art/TownBoardArt.luau`: TimberBrown frame and posts, SignCream face with SignInk text, Brass corner caps. Part names, counts and collision stay.
- `Shared/Art/BoxArt.luau`, `Shared/BoxWindows.luau`: the six Glass references go. The shell is KraftTan Cardboard, SignCream tape, SignInk print. Part names, welds, PriceTag, BoxPriceTag tag and the Open attribute stay. BoxWindows only tints a pane that is still glass, so kraft is never turned translucent on Lower quality.
- `Shared/Art/Palette.luau` and `tests/Palette.spec.luau`: append KraftTan #B8925F (count 39 to 40).

## Specs (written first, shown red, then green)

1. PlotPlatform: curb top is flush with the pad top; the largest vertical step along the edge profile is at most 0.25 and the rim reaches the terrain; Origin is HeightAt plus PlatformHeight; no pad overlaps a road; layout and slab rects unchanged for every tier and square set.
2. Same file: no lip higher than 0.25. Cloud tests have no physics, so the slide itself is a Studio check.
3. NodeArt: not floating, no part inside the hit box's collision, veins use Amber or Garnet, rock uses CliffRock or QuarrySlate, no block-shaped body, Atomic model, payout fields equal to ItemCatalog.
4. TownBoardArt: palette, text height at phone distance, posts off the walk path. BoxArt: kraft, no Glass or ForceField, size matches ItemBox, price tag intact.
5. Names and attributes BoxService, NodeService and PlotService read stay; world Overlap, Clearance, GeometryLint, MustKeep, AllowlistCap and PipelineE2E stay green with no new allowlist entry.

## Renders (preview/t414e, three.js previews)

Before and after: pad corner, node close-up, board at phone distance, a box beside its item, top-down of a plot meeting paving. Plus top-down, eye level and 667x375 crops.
