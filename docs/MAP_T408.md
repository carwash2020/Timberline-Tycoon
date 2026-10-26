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
- Pine Ridge, Frostpeak, Ember Caldera, Gloam Ravine, Bayou, Red Mesa and Lantern Isle use the live discs (`BiomeData` / `WorldLayout`). The Bait Shack stays at `BayouData.BaitShackSpot` (−720, −660).
- Mainland ferry dock `WorldLayout.FerryDock` (780, 136). The isle harbour pin is the inland end of the live ferry path.
- Odds & Ends sits on the first point of the live `HillsCross` road, (−460, −300).

Proposed, for this picture only. Connor can move them before anyone builds terrain:

- Skyroot foot (−200, 900) and the gate lodge (−200, 860). The live sky disc stays at (680, 280), y 650, until a build.
- River centre x = 113 (26 studs east of the sell floor's east edge). Channel half-width 18. The west bank stays off the sell floor.
- Cloud picture radius 64. Not a build size. The shaft, cab and doors above are the build sizes.
- The switchback's hairpins. The grade is not locked. See the questions.
- The lighthouse mark at (760, −310) is a stand-in on the live search band (z −440 to −180). `WorldPlan.Lighthouse()` still picks the real tower.

## The river and the bay

The channel leaves the Skyroot falls, runs east of Frostpeak, then south on x = 113 past the Weigh House, and meets the east water at the live shore (x 780). West of that channel is the timber country: town, Pine Ridge, Frostpeak, the Skyroot, Gloam Ravine, the Bayou. East of it is the shore the Dealership, the plots, the Caldera and Red Mesa sit on, and then the bay. Lantern Isle is in the bay. The lighthouse is on the east headland, not on the ferry dock.

One lift bridge, at (113, 80), where the east road leaves town. Towers on the two banks. $100. The Caldera road branches off on the east bank, so it does not need a second bridge and a second fare. Logs on the river are later. This plan does not float them.

## Roads

| Road | Width | Where it goes |
|---|---|---|
| Main Street | 32 | Along the live street to the bridge |
| Pine Road | 32 | The live Hills Road |
| Frost Road | 32 | The live Snow Road. Coat kiosk at the foot, (−28, 480) |
| Bay Road | 32 | Bridge, east bank, live east-link point, mainland dock |
| Dealership Spur | 24 | Up from the bay road to the hall door |
| Caldera Road | 32 | East bank north to the live Volcano Road. Heat Boots beside the last bend |
| Mesa Road | 32 | From the east link down the live Mesa Road |
| Gloam Road | 32 | Forest path, south link, ravine floor |
| Skyroad | 32 | Switchback from the frost road's end to the gate lodge. Sign: SKY PASS |
| Pine Link, Gloam Link | 24 | Meet at (−460, −300). Odds & Ends |
| Bayou Road | 24 | From that cross to the Bayou centre |
| Cave Path | 8 | Ravine floor to the secret shop (32, −744) |
| Lodge Path | 8 | Lodge to the trunk, and the lift |

There is no ring, and no truck tunnel, on this plan. The live ring and the live tunnel are removal candidates below.

## Shops

| # | Pin | Why |
|---|---|---|
| 1 | Tool Shed (−84, 117.7) | Axes and mill tools. In town, in sight of spawn. |
| 2 | General Store (−100, 187.5) | Home goods. In town, in sight of spawn. |
| 3 | Weigh House (53, 111) | Millie buys logs. Truck back-in. Kept. |
| 4 | Land Office (153.5, 100) | Old Hank, at the plot edge. |
| 5 | Dealership (189.25, 100.3) | Trucks, across the first lift bridge. |
| 6 | Coat kiosk (−28, 480) | Insulated Coat, $500, before the cold. |
| 7 | Heat Boots (393, 482) | Heat Boots, $800, before the caldera. |
| 8 | Odds & Ends (−460, −300) | Where the Pine link meets the Gloam link. |
| 9 | Sparkworks (923, −41) | Logic and machines, on the isle harbour. The live shop at (135, 132) stays until a build. |
| 10 | Sky Forge (−172, 918), y 840 | On the clouds only. |
| 11 | Sky Market (−230, 884), y 840 | On the clouds only. |
| 12 | Secret shop (32, −744) | In the Gloam caves. No name yet. |
| 13 | Bait Shack (−720, −660) | Waders. Already there. Not moved. |

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
| ring-road | `RingRoad` only circles the old map. | No |
| truck-tunnel | The ring's shortcut from the peak to the caldera. Caldera Road is on the surface. | No |
| floating-isles | Live sky disc at (680, 280), y 650, with no road to a summit. Lumenwood moves. The gondola top and the root bridges do not. | No |
| skyroot-bloom | WORLD_DESIGN retires it. `ForestService` still runs the clock, and it still doubles figure chances. | No |
| north-toll | Old Tolly's booth at (22, 888). The nine regions do not name that strip. | Yes. The counter stays until Connor picks. |
| meadow-lookout | At (−136, −20), beside the court, telescope toward town. It may be a deliberate view. | No |

Roads that still go somewhere (Snow Road, Hills Road, the dock, Bayou, Mesa) are not on this list. The plan reuses their points under the new names. The timber footbridge and the fishing dock are landmarks from the art direction. They are not on the list.

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
6. Is the Skyroot foot at (−200, 900) the right summit? The live isles stay where they are until you say build.
7. y 800→880 is an 80-stud ride. A haul grade of 0.2 cannot climb to world-height 800 inside this square (that wants about 4,000 studs of road). Is 800 the height up the trunk from the lodge, or the world height of the lodge?
8. One cloud deck, because root bridges are out. Do you still want separate walkable isles, and if so how do you cross?
9. The secret shop has no name and no stock. What is it, and what does it sell?
10. Sparkworks moves to the harbour only when this plan is built. The live shop stays at (135, 132). Confirm the move.
11. The meadow lookout: keep it as a view of town, or remove it with the court?
12. The Skyroot Bloom still doubles figure chances. Retire the clock with the gondola, or keep the bonus?
13. Gus's charter grants the Gondola Pass. Replace that check with the Sky Pass at the lodge?
14. The Featherfall Cloak was the glide off the high isles. There is no updraft, and the lift is short. Does the cloak still have a job?
15. River half-width 18 and the cloud picture radius 64 are tunes for the drawing. Say if you want them different before a terrain build.
