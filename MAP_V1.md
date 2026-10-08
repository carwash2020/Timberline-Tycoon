# MAP_V1: the smaller ring map

Plan for the V1 world remake. Picture: `previews/v1-b/00-overview.png`
(north is up, drawn from these numbers by `tools/preview/v1b_map.py`).
Town, the sawmill at (0, 110) and the spawn at (0, 0.5, 40) stay put.
StreamingTargetRadius stays 640.

The sell station stays beside the mill. `town.sellPad` is the sawmill
plus (53, 0, 1), so its middle is (53, 111). `town.sellZone` is the same
point at y 6, still 28 × 12 × 52 (z 85 to 137). Lane C turns the pad art
into a furnace joined to the mill; the zone does not move. Trucks back in
due north off MainStreet (x −128 to 64, z 62 to 84). The street's north
edge meets the zone, and the lane down the pad's middle (x 53, about 6
studs either side) is a straight line from that edge up to the log rack.
No new road crosses that lane. The ore furnace pad at (48, −110) is a
different place, for Lane M.

## Size

| | Before | After |
|---|---|---|
| Playable square | 3000 × 3000 (`WorldHalf` 1500) | 2000 × 2000 (`WorldHalf` 1000) |
| Extra generated land | North strip to z 1900 (about 800 × 400) | None. The toll crossing folds inside the square |
| Playable area | 9,000,000 sq studs, plus the strip | 4,000,000 sq studs (44% of the old square) |
| Side length | 3000 | 2000 (67% of the old side) |
| Terrain past the edge | Mountains started at 1180 | A 200-stud solid skirt, so the camera never sees the underside |

The builder set `WorldHalf` to 1000. That is the size. It is smaller than a 60–70% area cut because a 2000-stud side is two thirds of 3000, and area follows the square.

## How you drive

One 28-wide ring, radius 600 about (0, 80). Four 28-wide links leave town: north along x = 0, east along z = 80, south along x = 0, west along z = 80. A hills cross-link runs the west side from the south-west ring to the north-west ring. The truck tunnel is the other cross-link, under the ridge between the snow peak and the volcano.

Rustbucket speed is 26 studs/s. One-way drive from the sawmill, shorter route, tunnel counted as a road:

| Place | About | Seconds |
|---|---|---|
| Starter forest | 250 studs down the south link | 10 |
| Hills and the lake | 550 studs out the west link | 21 |
| Snow peak | 650 studs up the north road | 25 |
| Volcano | north road plus the 368-stud tunnel | 40 |
| Gloam ravine floor | south link plus the ravine road | 35 |
| Ferry dock | east link plus the dock road | 45 |

Nothing on the surface is a dead end. The ring closes. The tunnel is the short way between the peak and the volcano. The long way is the ring.

## Regions

Wood counts stay as they are today (Frostwood 70, Emberwood 60, Phantomwood 22, Lumenwood 12, Lanternwood 6, plus the common woods). Regrow times and gear gates stay. `haulStuds` is updated to the road length above after A1 merges. Until then the discs below are the map the terrain and the trees use.

| Region | Centre | Radius | Wood | Water and landmarks |
|---|---|---|---|---|
| Starter forest | (0, −180) | 100 | oak, birch | pond (−40, −160), brook to the east |
| Hills | (−500, 110) | 150 | pine, maple | lake (−700, 180) |
| Snow peak | (0, 720) | 115 | Frostwood | tarn (40, 820). Cold, coat gives immunity |
| Volcano | (450, 500) | 125 | Emberwood | cone on the far side. Heat, boots give immunity |
| Gloam ravine | (10, −720) | 80 | Phantomwood | 72 wide, 48 deep, one 28-wide road to the floor. Night plus the Lantern |
| Ferry isle | (930, −50) | 55 | palms | dock (860, 160), east coast at x 780 |
| Lumen isles | (680, 280) | 100, floor y 650 | Lumenwood | 216 studs from the dock (inside 400). Gondola from town |
| Bayou | (−760, −700) | 140 | none yet | flat basin sunk 7 studs. Lane R fills it |
| Red Mesa | (590, −790) | 115 | none yet | flat at the base height. Lane R fills it |

Respawns stay on the pads. No pad sits in the snow disc or the volcano disc.

## Roads

All of these are 28 wide except the plot spurs, which stay 22.

- RingRoad, 24 bends of 15 degrees, radius 600 about (0, 80)
- SnowRoad (0, 205) → (0, 680) → (0, 900), and the folded toll crossing near z 940
- HillsRoad (−125, 80) → (−600, 80) → (−560, 200)
- HillsCross (−460, −300) → (−560, −40) → (−520, 220) → (−460, 460)
- VolcanoRoad (424, 504) → (560, 560)
- SkyrootRoad (600, 80) → (800, 200) → (700, 320), ending under the isles
- SouthLink (0, −32) → (0, −520)
- EastLink (140, 80) → (600, 80)
- DockRoad (600, 80) → (860, 160)
- RavineRoad (0, −520) → (−90, −560) → (−90, −780)
- BayouRoad (−424, −344) → (−692, −612), from the ring vertex at −135 degrees. Ends in a 32-radius junction
- MesaRoad (424, −344) → (540, −470) → (585, −700), from the ring vertex at −45 degrees. Ends in a 32-radius junction

Town streets inside the flat zone (x −125 to 140, z −32 to 205) are dressed 22 wide with curbs and a boardwalk when that step lands. Junctions where a link meets the ring get a circle of radius 32.

## Pads

14 pads. Minimum spacing 248. Each centre is within 120 of a 28-wide road and within 450 of a resource biome. No two share the same nearest biome and nearest water. The first four stay the opener. From the fifth on, nearer the sawmill comes first. East Meadow stays east of the display lot. Saves are plot-local, so a base saved on the old pads loads on these.

| # | Name | Region | Position | Nearest reason |
|---|---|---|---|---|
| 1 | Birch Side | Starter Forest | (−118, −120) | starter, pond |
| 2 | Orchard Edge | Starter Forest | (−341, −261) | starter, pool |
| 3 | Oak Side | Starter Forest | (118, −300) | starter, brook |
| 4 | The Climb | The Hills | (−718, 80) | hills, lake |
| 5 | Ash Gate | the east road | (359, 702) | volcano, tarn |
| 6 | West Shelf | west country | (−359, 702) | snow, snowmelt |
| 7 | North Bend | the north road | (118, 798) | snow, tarn |
| 8 | High Meadow | the north road | (622, 439) | sky, mist |
| 9 | Pine Bend | The Hills | (−622, 439) | hills, spring |
| 10 | East Meadow | east of town | (710, −10) | ferry, coast |
| 11 | Long Meadow | south country | (−622, −279) | hills, pool |
| 12 | Lower Ridge | south country | (−359, −542) | gloam, seep |
| 13 | North Meadow | the north road | (359, −542) | gloam, brook |
| 14 | East Field | east country | (−208, −760) | gloam, cove |

## Underground

Carved in a second pass (`FillBlock`, `FillBall`, `FillCylinder` of Air, then a floor block). Sizes snap to 4 studs. Rock overhead is at least 16 studs on the covered runs. Solid ground continues 24 studs under every cave and tunnel floor. The surface crust is 8 voxels (32 studs) everywhere else.

### Truck tunnel

(60, 700) → (180, 660) → (300, 600) → (400, 560). Length 368. Cross-section 28 wide and 24 tall, gentle bends (about 8 degrees). The tallest loaded Logging Rig (bed zone plus the bunk stakes) stands under 16 studs, so 24 clears it with room. Not blocked by rubble.

### Walk-in caves

Mouths 16 × 16. Passages 12 to 16 wide and at least 12 tall. Chambers 40 to 60 wide and 20 to 28 tall.

- Waterfall hollow, near town, north-east of the square
- Old logging camp, in the west hills
- Ice cave behind the peak
- Lava tube beside the volcano
- Lanternwood grotto under the south-west, chamber 36 tall (tallest Lanternwood is 28, plus 8), 28-wide drive-in mouth, skylight

### Gloam ravine

72 wide, 48 deep. One 28-wide road down to the floor, grade under 12 degrees.

### The mine (Lane M builds the mining)

One normal walk-in mouth near the starter forest, at (150, −150). It opens the upper tier only: shallow, safe, basic ore anchors. No rubble on that path.

Two deeper tiers sit behind rubble walls inside the mine. Three hidden mouths are also sealed with rubble:

| Rubble | Where | Opens |
|---|---|---|
| mine-mid | passage inside the main mine | tier 2, mid depth |
| mine-deep | passage below tier 2 | tier 3, deep |
| hidden-hills | mouth near the hills | tier 2 |
| hidden-peak | mouth behind the peak | tier 3 |
| hidden-lava | mouth by the lava tube | tier 3 |

Rubble is an anchored Model tagged `Rubble`, attributes `RubbleId` and `Tier`, about 16 × 12 × 6, 12 parts or fewer, sitting in a passage at least 12 wide. Lane M removes them. This lane does not script removal. Rubble never blocks the truck tunnel, a secret's only path, or the grotto mouth.

`UndergroundData.Tiers` lists upper (danger 1), mid (danger 2) and deep (danger 3, under the peak and toward the lava tube). `MineAnchors` are invisible parts, `CanCollide`, `CanQuery` and `CanTouch` false, attribute `MineAnchor` plus `Tier`, about every 40 studs on chamber walls, denser in deeper tiers. `FurnaceSite` is a flat 30 × 24 pad at (48, −110), beside the south link, for Lane M's furnace.

Phone caps: 6 PointLights or fewer in a cave system (shadows off), 120 decor parts or fewer. The tunnel gets 8 lights or fewer.

## Secrets

Each is at least 150 studs from every road, reachable on foot, and built from 150 parts or fewer. Marked `?` on the picture. The server checks the character's position on a timer. Pay once per save slot through EconomyService.

| Id | Where | Pay | Gate |
|---|---|---|---|
| waterfall | (250, 260), hollow near town | $300 | none |
| camp | (−360, −90), the logging cave | $2,000 | none |
| ice | (190, 880), behind the peak | $4,000 | Insulated Coat |
| lava | (700, 720), the lava tube | $8,000 | Heat Boots |
| ravine | (200, −820), ravine floor | $3,000 for now | night plus the Lantern |

The ravine's real reward is 2 Sky Shards once A2's grant exists. Explorer badge id is 0 until Connor pastes one. Nothing is paid from a mine anchor.

## Ground and the camera

- `TerrainBuilder` crust is 8 voxels (32 studs) under the surface everywhere
- 24 studs of solid under every cave and tunnel floor
- Sea floor and lake beds stay filled, not a skin
- Flat pads, road slabs, the bridge, the dock and the isle bottoms are at least 4 studs thick, or they sit on terrain, and they query or collide so the camera pulls in
- Cave and tunnel ceilings keep at least 16 studs of rock
- FallenPartsDestroyHeight stays the engine default. Pieces that fall are Lane F's problem
- After the new map is published, restart every server

## Contracts other lanes read

`ScatterZones.Zones`: `{ id, kind, center: Vector2, radius, density }` with kind `meadow`, `forest`, `shore`, `snow`, `volcano`, `gloam`, `isle`, `town` or `cave`. `ScatterZones.Blocked(x, z)` is true on roads, floors, pads and their blend, water, the spawn lane, keep-outs, tunnel floors and cave paths.

`UndergroundData` exposes `Caves`, `Tiers`, `Rubble`, `MineAnchors` (with `tier`), `FurnaceSite` and `Secrets`.

`WorldPlan` exposes the NPC stand spots, weather zones and critter zones so Lane E and Lane G stop hardcoding coordinates. The table is also in STATUS.md.

`SecretLogic.Count(profile)` is the field-guide fraction (found, 5) for Lane E.

## Bayou and Red Mesa

Reserved for Lane R. This lane lays the ground, the roads and the anchors. No trees, scatter or unique items.

Bayou centre (−760, −700), radius 140. The basin is flat and sunk 7 studs (inside the 6–8 band) under the broad ground at its centre. BayouRoad is 28 wide, from the ring vertex (−424, −344) to (−692, −612), and ends in a junction of radius 32 with a signpost reading BAYOU.

Red Mesa centre (590, −790), radius 115. The disc is flattened to the base height, not sunk. MesaRoad is 28 wide, (424, −344) → (540, −470) → (585, −700), and ends in a junction of radius 32 with a signpost reading RED MESA.

Anchors on `WorldPlan` (Lane R reads these):

| Anchor | Where |
|---|---|
| BayouCentre | (−760, −700), radius 140 |
| MesaCentre | (590, −790), radius 115 |
| MudZones | (−820, −640) r20, (−680, −760) r22, (−740, −640) r18, (−700, −800) r22 |
| BaitShackSpot | (−720, −660) |
| BayouLogLanding | (−800, −700), 40 × 30 |
| SlabNodes | 8 points on the mesa's north rim, 8 studs in from the edge |
| MesaTruckLot | (620, −770), 40 × 30 |
| UniqueItemSpawn | one in the Bayou at (−780, −780), one on the mesa at (590, −860) |
| LeaderboardBoard | CFrame (−50, 0, 92), facing south onto MainStreet, between GondolaPath x −37.5 and ToolShedFloor x −62 |

Resource regions (a wood biome, or one of these two) are at least 500 studs apart centre to centre. A pair under 700 keeps 70 trees or fewer combined. Bayou and Red Mesa have 0 trees, so they pass. The Lanternwood grotto stays at (−240, −420): its nearest corner is about 416 studs from the Bayou edge, past the 100-stud gap, so it was not moved.

## Not in this plan

Biome disc centres live in `BiomeData`, which A1 owns. The terrain uses the centres in this file. After A1 merges, this lane writes only `haulStuds`, `GameConfig.WorldVersion = 2`, and `ExpansionPriceStep` if the full plot drops under 28 hours. Tree counts, gear and prices are not touched.
