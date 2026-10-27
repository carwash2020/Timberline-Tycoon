# T408: river-valley map, draft for approval

Picture: [`previews/t408/overview.png`](../previews/t408/overview.png) (north is up, east is right). Removal cards: [`previews/t408/removals/`](../previews/t408/removals/). The numbers live in `Shared/World/WorldPlanDraft.luau`. Regenerate the picture with `lune run tools/preview/t408_dump` then `python3 tools/preview/t408_map.py`.

This is a plan. `TerrainGen`, `WorldPlan` and `MapBuilder` do not read the draft. Nothing in the live place moves, and nothing on the MustKeep list is deleted.

## Designer's locked brief

Regions (lock labels): Timber Valley (town/spawn) → Pine Ridge → Frostpeak → Ember Caldera → Gloam Ravine → Bayou → Red Mesa → Lantern Isle (ferry) → Skyroot Highlands + walkable clouds. N–S river splits west land / east bay. No ring road. No gondola.

Shop pins that must stay true: Tool Shed + General Store in town in sight of spawn. Weigh House / Millie sell bay on the river with truck back-in — KEEP Weigh House (ignore any T420 draft that deleted it). Land Office at plot edge. Dealership across the first lift bridge. Coat kiosk at Frostpeak road foot; Heat Boots at Caldera rest stop; Odds & Ends at Pine/Gloam crossroads; Sparkworks on Lantern Isle harbour; Sky Forge + Sky Market on clouds only; one secret shop in Gloam caves.

Travel: roads 32 main / 24 branch / 8 foot. Switchback to Skyroot gate lodge (Sky Pass check here). Car ferry to Isle (walkable deck, under 40 s). Cloud access option B: trunk lift inside Skyroot — shaft ~24×24, cab ~18×18×12, travel y~800→880, doorways 10×10 so player + ~5 logs fit; separate log chute down. No root bridges, no updraft.

Fares defaults until Connor picks: lift bridge $100, ferry $400. Fast travel: none in V1.

Art tints on the picture: Valley MeadowGrass #6E9F45 and TrailDirt #8E6C4A; Pine DeepMeadow #5A8A3C to CliffRock #7E766C; Frost FreshSnow #EEF3F7 and FrostGlow #BFE3F2; Ember AshBasalt #3A3433 and EmberGlow #FF7A1A plume; Gloam WetMud #5A4A3E and GloamGlow #7A4FD0; Bayou BayouSilt #4E4A36; Mesa MesaRed #C8693E; Isle ShoreSand #D8C69A; Skyroot LumenGlow #FFF4C2 moss and cream #F2E6C8 canopy. Water is a blue ink so the river reads. It is not a region tint.

## What is locked, and what is only the picture

Locked, because the game or the brief already has the number:

- The nine names and the order above.
- No ring, no gondola, no root bridges, no updraft, no fast travel.
- Road widths 32 / 24 / 8.
- Lift bridge fee `GameConfig.TollFee` ($100). Ferry fare `GameConfig.FerryFare` ($400).
- Ferry crossing `FerryLogic.TravelSec` (40). Deck `FerryLogic.DeckWidth` × `DeckLength` (14 × 22), which is already a walkable deck.
- Trunk lift: shaft 24, cab 18×18×12, doors 10×10, about 5 logs, travel y 800→880. The cloud deck on the picture sits at y 840, the middle of that band. The log chute is separate from the cab.
- Spawn (0, 40), sawmill (0, 110), Weigh House at the sawmill plus (53, 1), so (53, 111). Sell floor x 31–87, z 84–139. Trucks still back in off Main Street.
- Tool Shed (−84, 117.7) and General Store (−100, 187.5), both inside the town flat zone and in sight of spawn. The live shop id of the General Store is still `HearthAndHome`.
- Land Office at `PlotSalesmanData.Office` (153.5, 100).
- Dealership door (189.25, 100.3), the MustKeep hall entrance. It is east of the bridge.
- Coat and Heat Boots keep their `ItemCatalog` prices ($500 and $800).
- The Bait Shack stays at `BayouData.BaitShackSpot` (−720, −660). It falls inside the draft Bayou disc.
- Odds & Ends stays at the Pine/Gloam cross, (−460, −300).
- The live ferry dock `(780, 136)` and the live isle centre stay until a build. The picture draws the ferry to the draft isle.

Builder discs, for this picture only. `OverlapHits()` is empty: same-layer discs may kiss by 12 studs (Bayou and Gloam miss a tangent by about 10, and those centres stay). Skyroot is the cloud layer, so it may sit over Frostpeak in plan. Connor can move them before anyone builds terrain:

| Region | Centre | r | Layer |
|---|---|---|---|
| Timber Valley | (0, 80) | 220 | ground |
| Pine Ridge | (−420, 110) | 180 | ground |
| Frostpeak | (−200, 900) | 160 | ground |
| Ember Caldera | (700, 900) | 160 | ground |
| Gloam Ravine | (−565, −455) | 140 | ground |
| Bayou | (−700, −700) | 150 | ground |
| Red Mesa | (700, −500) | 150 | ground |
| Lantern Isle | (1200, −700) | 120 | ground |
| Skyroot Highlands | (−60, 800) | 170 | ground |

Skyroot Highlands is the ground summit. Walkable cloud isles are separate `CloudIsle` rows, annotated and not built. The gate lodge is (−40, 720), facing north, on the switchback just south of the summit. Its height is `TerrainGen.HeightAt` when T409 builds it. This plan stores the XZ.

Frostpeak (−200, 900, 160) and Skyroot are both ground, and the locked discs overlap by about 158 studs. The centres stay. `OverlapHits()` is empty apart from that pair, which `KnownOverlap` records for Connor.

- Spawn stays (0, 0.5, 40). The sawmill stays (0, 110).
- River centre x = 113 (26 studs east of the sell floor's east edge). Channel half-width 18. The west bank stays off the sell floor.
- Cloud picture radius 64. Not a build size. The shaft, cab and doors above are the build sizes.
- The switchback's hairpins. The grade is not locked. See the questions.
- The lighthouse mark at (760, −310) is a stand-in on the live search band (z −440 to −180). `WorldPlan.Lighthouse()` still picks the real tower.

## The river and the bay

The channel starts east of Frostpeak, runs south on x = 113 past the Weigh House, and opens into the southeast bay (water east of x 960). West of the channel is the timber country: town, Pine Ridge, Frostpeak, the Skyroot, Gloam Ravine, the Bayou. East of it is the shore the Dealership, the plots, the Caldera and Red Mesa sit on, and then the bay. Lantern Isle is in that bay, past the live world edge. The lighthouse mark is on the east headland. The live tower is not moved.

One lift bridge, at (113, 80), where the east road leaves town. Towers on the two banks. $100. The Caldera road branches off on the east bank, so it does not need a second bridge and a second fare. Logs on the river are later. This plan does not float them.

## Roads

| Road | Width | Where it goes |
|---|---|---|
| Valley Trunk | 32 | North–south on x = −36, from the south country through town to the switchback |
| Main Street | 32 | Town street to the one lift bridge |
| Skyroot Road | 32 | Switchback from the trunk's north end to the gate lodge (−40, 720). Sign: SKY PASS |
| Pine Road | 24 | Trunk to Pine Ridge |
| Frost Road | 24 | Switchback to Frostpeak. Coat kiosk at the foot |
| Bay Road | 24 | Bridge, east bank, mainland dock for the picture ferry |
| Dealership Spur | 24 | Up from the bay road to the hall door |
| Caldera Road | 24 | East bank north to the caldera. Heat Boots at the rest stop |
| Mesa Road | 24 | South to Red Mesa |
| Gloam Road | 24 | Trunk to the crossroads, then the ravine |
| Pine Link | 24 | Pine Ridge down to the crossroads (−460, −300). Odds & Ends |
| Bayou Road | 24 | Crossroads to the Bayou centre |
| Cave Path | 8 | Ravine floor to the secret shop |
| Lodge Path | 8 | Lodge to the trunk, and the lift |

There is no ring, and no truck tunnel, on this plan. The live ring and the live tunnel are a T409 redo, not a deletion. See below.

## Shops

| # | Pin | Why |
|---|---|---|
| 1 | Tool Shed (−84, 117.7) | Axes and mill tools. In town, in sight of spawn. |
| 2 | General Store (−100, 187.5) | Home goods. In town, in sight of spawn. |
| 3 | Weigh House (53, 111) | Millie buys logs. Truck back-in. Kept. |
| 4 | Land Office (153.5, 100) | Old Hank, at the plot edge. |
| 5 | Dealership (189.25, 100.3) | Trucks, across the first lift bridge. |
| 6 | Coat kiosk (−152, 713) | Insulated Coat, $500, at the Frostpeak road foot. |
| 7 | Heat Boots (728, 700) | Heat Boots, $800, at the caldera rest stop. |
| 8 | Odds & Ends (−460, −300) | Where the Pine link meets the Gloam road. |
| 9 | Sparkworks (1115, −700) | On the draft isle harbour. The live shop at (135, 132) stays until a build. |
| 10 | Sky Forge (−32, 818), y 840 | On the clouds only. Not built. |
| 11 | Sky Market (−90, 784), y 840 | On the clouds only. Not built. |
| 12 | Secret shop (−543, −479) | In the Gloam caves. No name yet. |
| 13 | Bait Shack (−720, −660) | Waders. Already there. Not moved. |

## Corridors and belts (annotated, not built)

The space between discs is dressed so the ride feels like country, not a blank. Travel distance does not change. There are no new shortcuts and no new shops.

`WorldPlanDraft.Corridor` is the rhythm. Trunk: tree-belt clumps every 45 studs in a 16-stud band that starts 2 studs off the road bed, small scatter every 24, medium props every 48, mile signs every 200, a vista pull-off (24×16) every 400. Branches are lighter: trees every 90, scatter every 32, medium every 64. River banks and log booms every 300. Four wood lots (pine, oak, birch, maple), under `MaxWoodPartsServer` 2500. Camps at the frost foot and the caldera rest only. They do not sell. An overlook sits on every other Skyroot hairpin.

Blend belts are 48 studs on trunk and branch roads, 32 on a foot road, on the approach into each disc. The inner 30 studs of a belt are tree-clear. The road bed stays RoadGravel. Biome accent (tiny Neon) is only on the inner apron: FrostGlow in the last 10 toward Frostpeak, EmberGlow in the inner 15 toward the Caldera, GloamGlow toward Gloam and the Bayou, LumenGlow at the lodge. Materials: Valley and Pine trade MeadowGrass, DeepMeadow and CliffRock; Frost adds TrailDirt and FreshSnow; Caldera goes to AshBasalt and QuarrySlate; Gloam and Bayou go WetMud to BayouSilt; Mesa goes to MesaRed; the ferry apron goes TrailDirt to ShoreSand.

T409 spawns these as streamed models, reuses mesh ids, and does not add remotes. This PR does not.

## Trunk lift

Inside the Skyroot. Shaft about 24×24. Cab about 18×18×12. Doorways 10×10, so a player and about five logs fit. The cab travels y 800 → 880. A separate chute takes logs down. The Sky Pass is checked at the gate lodge, at the foot of that path, not on a gondola. No root bridges. No updraft. The inset on the picture is not to map scale.

## Removals (do not delete in this PR)

Cards: `previews/t408/removals/<id>.png` and `contact-sheet.png`.

| Card | Why it is on the list | MustKeep |
|---|---|---|
| gondola-station | Town station at (−40, 150). The trunk lift replaces the ride. | No |
| gondola-cabin | Spawned for the ride. No fixed plot. | No |
| gondola-cable | Town station to the live sky disc. The overview draws no cable. | No |
| turnstile | `SkyTurnstile`, signed Gondola Pass. Not placed. Do not build it. | No |
| cloud-chute | Isle chute and flume on the live sky disc. The trunk has its own chute. The Sky Bin stays until that chute exists. | No |
| sky-forge-court | Ground court at (−112, −20). The forge belongs on the clouds. | Yes. Keeper, temper spot, four relic sockets. They move with the forge. They do not vanish. |
| floating-isles | Live sky disc at (680, 280), y 650. That was the gondola top, not this summit. | No |
| skyroot-bloom | WORLD_DESIGN retires it. `ForestService` still runs the clock, and it still doubles figure chances. | No |
| meadow-lookout | At (−136, −20), beside the court, telescope toward town. It may be a deliberate view. | No |

## Redo in T409+ (do not silent-delete)

The live ring road and the live truck tunnel are not on the removal list. `WorldPlanDraft.Redo` names them. A later terrain build replaces the ring with the valley roads and the bore with the surface Caldera Road. This PR leaves both in the live place.

The picture's roads are new lines to the draft centres. The live Snow Road, Hills Road and the rest stay in the place until T409. The timber footbridge and the fishing dock are landmarks from the art direction. They are not on the list.

## What Connor checks

This is a picture. Studio has nothing new to walk. Look at `previews/t408/overview.png` and the removal contact sheet.

1. Nine names, north up, river north–south, bay to the east, no ring, no cable.
2. Tool Shed and General Store in town. Weigh House on the river, trucks backing in. Dealership across the one lift bridge. Land Office at the plot edge.
3. Coat at the frost road foot, Heat Boots at the caldera stop, Odds & Ends at the cross, Sparkworks on the isle, Sky Forge and Sky Market on the cloud, secret shop in the ravine.
4. Skyroot far north, switchback to the lodge, trunk lift, plume to the north-east, lighthouse on the east headland.
5. The removal cards. Say which ones go, and which stay.

## Questions

1. The ferry crossing is `FerryLogic.TravelSec` = 40. The brief says under 40 seconds. Keep 40, or set 39?
2. The live deck is 14×22. That is a walkable deck. A logging truck will not fit. Widen it when the car ferry is built, or keep foot-and-cargo until then?
3. The draft prices the bridge at `TollFee` $100 and the ferry at `FerryFare` $400. An earlier note said both free for V1. The picture uses the two live keys. Which do you want?
4. The ground court's keeper, temper spot and four sockets are MustKeep. Move them onto the cloud forge, or keep a court on the ground?
5. The north toll counter is also MustKeep. Is the town lift bridge that toll moved, or do both crossings stay?
6. Locked: gate lodge (−40, 720) facing north. Skyroot radius 170, layer ground. Frostpeak and Skyroot overlap by about 158 studs. Shrink one before T409, or keep the shared shoulder?
7. y 800→880 is an 80-stud ride. A haul grade of 0.2 cannot climb to world-height 800 inside this square (that wants about 4,000 studs of road). Is 800 the height up the trunk from the lodge, or the world height of the lodge?
8. Three cloud isles are drawn and not built. Root bridges are out. Do you still want separate walkable isles, and if so how do you cross?
9. Lantern Isle at (1200, −700) sits outside the live world (WorldHalf 1000). The picture ferry runs from (920, −640) to (1100, −700). The live dock stays at (780, 136). Grow the map in T409?
10. The secret shop has no name and no stock. What is it, and what does it sell?
11. Sparkworks moves to the harbour only when this plan is built. The live shop stays at (135, 132). Confirm the move.
12. The meadow lookout: keep it as a view of town, or remove it with the court?
13. The Skyroot Bloom still doubles figure chances. Retire the clock with the gondola, or keep the bonus?
14. Gus's charter grants the Gondola Pass. Replace that check with the Sky Pass at the lodge?
15. The Featherfall Cloak was the glide off the high isles. There is no updraft, and the lift is short. Does the cloak still have a job?
16. River half-width 18 and the cloud picture radius 64 are tunes for the drawing. Say if you want them different before a terrain build.
17. Bayou and Gloam overlap by about 10 studs at the locked centres. The plan-level check allows a 12-stud kiss so those centres stay. Move one before T409?
