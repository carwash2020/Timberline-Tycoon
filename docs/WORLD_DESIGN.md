# World design

The region map and unlock path for W2–W4. No code in this batch.

It is built on what is already in the world: `BiomeData` (centres, radii, woods, haul distances), `WorldLayout` and `WorldPlan` (roads, river, coast, island, Skyroot, rims), `RegionLogic` (named regions and the Petrified Reach), `EnvironmentData` (region air from phase 12), `SoundData` (ambient loops), and the phase 12 region and road notes in `V2_PLAN.md`. North is +Z, east is +X. The world runs from −1500 to 1500 on both axes (`WorldLayout.WorldHalf`).

Do not move the town, the sawmill at (0, 110), the sell zone, the spawn, Murph's camp, or any biome centre or radius. Distances below are the ones those modules already use.

Approved names, from the wave 1 decisions: **Lanternwood**, **Old Tolly**, **Cap'n Moss**, **the Hermit**, **Hermit's Maul**.

## 1. The toll gates a new area only

The toll bridge gates one new area, past the Snowfields. The Snowfields and the Volcano stay free, on the roads that already reach them (`SnowRoad`, `VolcanoRoad`). Old Tolly takes `GameConfig.TollFee` ($100) for `GameConfig.TollSeconds` (180 seconds, 3 minutes). The paid window is `tollPaidUntil`, a server table on `GateService` keyed by UserId. It is not a save field, it is cleared when the player leaves, and the client never sends it.

The booth has a red-and-white arm. It stands on a new spur that leaves the north side of the Snowfields' cliff ring, outside the snow disc (centre (0, 1240), radius 200) and outside the volcano disc (centre (1100, 1180), radius 220). The ring's one gap already faces south, toward town (`WorldLayout.Rims`, snow `gap = -π/2`). That south gap stays the free pass. The tolled spur is the other way, north, and W2 extends the map past `WorldHalf` to give it ground. What that ground grows is **TBD (Designer)**. No wood id until the Designer names it.

The timber footbridge already on the west river (`WorldPlan`'s footbridge, sign "TIMBER BRIDGE") is a free foot crossing. It is not this toll, and it does not become a gate to the Hills, the lake, or the Skyroot road.

This is the layout W2 builds. `V2_PLAN.md` §11 had put the same $100 / 3 minute toll in front of the Snowfields and the Volcano. That placement is retired. The prices in `GameConfig` stay.

## 2. Unlock path

Each step costs a little and teaches something. Prices below are the keys already in `GameConfig` (wave 0). The gondola fee and ride are `BiomeData` for `sky`.

| Step | Region | Wood | How you get in | Where it sits |
|---|---|---|---|---|
| 0 | Town + Starter Forest | oak, birch | free | town flat zone; starter disc (0, −110), radius 90 |
| 1 | The Hills | pine, maple | free road (`HillsRoad`, 28 wide) | (−420, 110), radius 170. Haul 400 |
| 2 | Snowfields | frostwood | free (`SnowRoad`, 28 wide) | (0, 1240), radius 200. Haul 1200 |
| 2 | The Volcano | emberwood | free (`VolcanoRoad`, 28 wide, off the snow road) | (1100, 1180), radius 220. Haul 1600 |
| 2 | New area beyond the snow cliff | TBD (Designer) | toll, Old Tolly, $100 for 3 minutes | north of the snow rim, outside both free discs. Map grows. W2 |
| 3 | Gloam Hollow, by the back way, and the Secret Cave | gloamwood (`phantomwood`) | blasting charge on the cracked boulders | hollow (−565, −455), radius 120. Cave on the Petrified Reach, about (−765, −655), radius 46 |
| 4 | Ferry Island | palmwood, and Lanternwood after dark | ferry, Cap'n Moss, $400, every 6 minutes | `WorldLayout.Island` (1395, −760), radius 70, height 9 |
| 5 | Skyroot and the Aether Isles | lumenwood, and the forge | gondola, already in the world ($250, 40 s) | foot (−1050, 1050). Isles at y 650, radius 170 |

The blasting charge price is `GameConfig.DynamitePrice` (220). `BlastingChargePrice` is an alias of that key. Broken boulders return after `GameConfig.BoulderRespawnSec` (1200 seconds). The ferry fare is `GameConfig.FerryFare` (400) and the boat leaves every `GameConfig.FerryIntervalSec` (360 seconds).

`GateService`, `FerryService`, `BlastService`, and `HazardService` are the wave 0 stubs. Later batches fill those bodies. They do not add a second connection on `TollPay` or `FerryBoard`.

## 3. Sketch

Top-down terrain from `tools/preview`, scene `terrain`, view 2. The camera is (0, 3800, 1) looking at the origin, field of view 50. It sits one stud north of the origin, so the raw frame has north at the bottom. This sketch is that frame flipped. North is up, east is to the right. The picture is the live heightfield: grass, snow, the volcano, the east ocean, Mirror Lake, and the island. The lines and names were drawn on afterwards.

![Top-down terrain with the regions marked](world-topdown.png)

Yellow rings are free ground that already has a centre in `BiomeData`. The red dash is the new tolled ground, past the snow cliff, which the current ±1500 map does not contain yet. Purple is the Secret Cave on the hollow's far side. Teal is the ferry: the headland dock and Ferry Island. Gold is the Skyroot's foot. The white bars on the north edge of the snow ring are the toll arm.

## 4. Regions

Every region below lists its wood, the way in, the landmarks you steer by, and why you come back. Fog colours are the phase 12 air in `EnvironmentData.BiomeOverrides` unless a row says the colour is still for the Designer. Ambient keys are `SoundData` names that already exist. This doc does not invent asset ids.

Shared reasons, on every region once the matching batch lands: trees regrow in random spots (the regrow branch), daily goals that point at the area (B13), an area badge (B06), and Halloween trees from 1 October through 1 November. Badge ids in `BadgeData` stay 0 until Connor creates the badges. Award code skips id 0 and does not error. `badgesAwarded`, `secretsFound`, and `areasVisited` are account-wide maps (`{ [string]: boolean }` on the profile, not on a save slot). `storage`, `plot.squares`, `permissions`, and `questAxe` stay on the slot.

### Town and the Starter Forest

- **Wood.** Oak and birch. `BiomeData` plants 40 oak and 15 birch in the starter disc. Town itself is the hub, not a grove.
- **Way in.** Free. Spawn is in town. `ForestPath` (16 wide) runs south into the starter disc. Haul back to the sawmill is 190 studs.
- **Landmarks.** The sawmill at (0, 110), the sell pad and the Sky Bin in front of it, the Tool Shed, Dealership, and Hearth & Home, the gondola station, Murph's camp by the spawn, the parking lot to the east, and the signposts (`BuildingArt.nameSign`), including "TO THE WOODS" and "SELL LOGS HERE". The Skyroot is on the northern horizon.
- **Come back for.** Selling, the shops, the limited shelf rotation (B01), the tutorial grove, regrowth, Halloween trees, dailies, and the town badge.
- **Air and sound.** Starter air is the warm green nudge (`EnvironmentData.BiomeOverrides.starter`). Night mist is the grey-blue that thickens from 22:00 and lifts by 09:30. `BirdsDay` by day. `CricketsNight` and `Owl` at night. `MusicDay` and `MusicNight` are the music bed, not a biome loop.

### The Hills

- **Wood.** Pine and maple. 40 pine and 25 maple.
- **Way in.** Free. `HillsRoad` leaves town to the west, 28 wide, haul 400.
- **Landmarks.** The gate sign on the last stretch of `HillsRoad`. The Old Ranger Cabin sits north of the Hills' centre (a `RegionLogic` anchor). Mirrorwater, the river and Mirror Lake, runs down the west side. The river's spring is the Skyroot waterfall.
- **Come back for.** Maple figures (Hidden Grain, `GAME_DESIGN` §16), regrowth, Halloween trees, dailies, and the Hills badge. The cabin board is a clue toward the hollow, not a toll.
- **Air and sound.** Hills air is a small saturation and contrast nudge. `BirdsDay` in the stands. `River` along Mirrorwater.

### Snowfields

- **Wood.** Frostwood, the hero wood. 35 trees. The climb still carries pine (`RegionLogic` species `snowpine` and `conifer`).
- **Way in.** Free. `SnowRoad` runs north from behind the sawmill, 28 wide, with flares at (30, 450) and (−20, 760). Haul 1200. A brown cliff ring sits outside the trees, with one pass, and that pass is this road. Nothing on this road charges a toll.
- **Landmarks.** The gate sign. The cliff ring. The Skyroot road leaving west at the second flare. The volcano road leaving east at the first flare. The smoking volcano rim is visible to the north-east. The toll arm, once W2 builds it, is on the far (north) side of the ring, on the new spur, where it cannot close the south pass.
- **Come back for.** Frostwood, regrowth, Halloween trees, dailies, and the snow badge. Cold is the pressure: chop and move are 15% slower until the Insulated Coat (`BiomeData` slowdown 0.15, `removedBy = "InsulatedCoat"`).
- **Air and sound.** A cold white-blue haze (`EnvironmentData.BiomeOverrides.snow`). `WindHowl`.

### The Volcano

- **Wood.** Emberwood, the hero wood. 30 trees.
- **Way in.** Free. `VolcanoRoad` branches off `SnowRoad` at (30, 450), 28 wide. Haul 1600. A dark rim has one gap, and that gap is this road. The volcano is not behind the toll.
- **Landmarks.** The smoking cone (`WorldLayout.VolcanoCone`, east of the biome centre). The rim. The gate sign. Cinder Cave, on the volcano shelf, is an existing point of interest. It is not the Hermit's Secret Cave.
- **Come back for.** Emberwood, regrowth, Halloween trees, dailies, and the volcano badge. Heat Boots stop the lava burn. Ash storms cut the view. You endure the storms.
- **Air and sound.** Thick red-orange air at every hour, density 0.55 (`EnvironmentData.BiomeOverrides.volcano`). `LavaRumble`.

### New toll ground

- **Wood.** TBD (Designer). Do not reuse frostwood or emberwood as the reason the gate exists. Those two stay on the free roads.
- **Way in.** The toll spur only. Old Tolly, red-and-white arm, $100 for 3 minutes, server-side `tollPaidUntil`. When the time ends, the arm lowers. Raising it pushes players and vehicles off the span, the way `V2_PLAN.md` §11 describes the bridge itself. It pushes them off this span, not off `SnowRoad` or `VolcanoRoad`.
- **Landmarks.** The booth and the arm. A signpost in the same family as the other gates (`BuildingArt.nameSign`). From the spur you can still see the Skyroot and the volcano rim, so the new ground does not become a place you cannot steer out of.
- **Come back for.** Whatever the Designer puts here, plus the shared list (regrowth, Halloween trees, dailies, a badge, the limited shelf if a stall is part of the content). The 3 minute pass is a reason to plan the trip, not a reason the Snowfields close.
- **Air and sound.** Not in `EnvironmentData` or `SoundData` yet. The Designer picks the fog colour with the content. W2 adds the override and the loop. This doc does not invent an asset id.

### Gloam Hollow and the Secret Cave

- **Wood.** Gloamwood, id `phantomwood`. 15 trees in the hollow, night only. The Petrified Reach is the same wood, a lost stand past the ridge (`RegionLogic` id `reach`).
- **Way in.** The hollow has no haul road. The front gap in the ridge faces town (`WorldLayout.GroveRidge`). The back way is the far side of that ridge, away from the sawmill, where the reach sits (about (−765, −655), radius 46). Cracked boulders seal that way and the cave mouth. A blasting charge opens them (`DynamitePrice` 220, 5 second fuse, `BlastPressure` 0, tag `Breakable`, as in `V2_PLAN.md` §11). They return after `BoulderRespawnSec`. The hollow and the cave need the Lantern (`BiomeData` `requiresGear = "Lantern"`). Trees in the hollow are night only.
- **Landmarks.** The Hermit's carved symbol on the cave cliff. The three shallow pools in the hollow (phase 12). A signpost at the gate. The ridge itself, which hides the hollow from the road.
- **Come back for.** Gloamwood, which is not there by day. The secret cave box. The Hermit's quest, which ends at this cave. The axe at the end of that quest is the Hermit's Maul (off the ladder). Regrowth, Halloween trees, dailies, and the hollow badge. The carved-mark for this biome is on the cave cliff with the Hermit's symbol, so the cliff is worth a second look.
- **Air and sound.** Violet mist at any hour, density 0.53 (`EnvironmentData.BiomeOverrides.grove`). `CricketsNight` and `Owl`. A hollow-only loop is not in `SoundData` yet. W2 may add a key. This doc does not invent the asset id.
- **Where the Hermit lives.** On this cave. `V2_PLAN.md` §11 had a snow trapdoor under a carved symbol. For the map, that symbol is on this cliff, and the way in is the blasting charge on the back side of the hollow. The quest still draws its pieces from the Tool Shed, Hearth & Home, and Odds & Ends. This doc does not reprice that shopping list.

### Ferry Island

- **Wood.** Palmwood, and Lanternwood. Palmwood is already a `WoodData` id whose biome is `island`. The island biome has no `area` yet. The land to use is the existing offshore disc, `WorldLayout.Island` at (1395, −760), radius 70. Lanternwood is a new id. It is night-glow, and it is not in `WoodData` in this batch (another batch owns that file). `GameConfig.NightGlowWoodId` stays the wave 0 placeholder `lumenwood`. Lanternwood is an extra night tree on this island. Lumenwood on the isles already glows. Do not collapse the two ids.
- **Way in.** The ferry. Cap'n Moss, $400, every 6 minutes. Riders and cargo weld to the deck for the crossing (`V2_PLAN.md` §11). The dock is the east headland, at the lighthouse the spawn can already see. `WorldPlan`'s town-sign comment places that tower at (1203, 236), on the Strand (`RegionLogic` id `strand`, shore near `WorldLayout.Coast.shoreX` 1190). The island lies offshore to the south-east of that dock. Trucks do not swim. The deep sea past the coast is the barrier (`GameConfig.WaterDamage` 15 every `WaterTickSec` 1.5 seconds).
- **Landmarks.** The lighthouse on the ferry dock. The island's silhouette. A signpost at the dock. Cap'n Moss.
- **Come back for.** Palmwood. Lanternwood, which is only there at night. How many of those trees are glowing depends on grove vitality (below). The night-only painting hangs in the lighthouse and can be seen only after dark, so the dock is a trip of its own when the ferry is not the point. Regrowth, Halloween trees, dailies, and the island badge.
- **Air and sound.** A warm coastal haze is not in `EnvironmentData` yet. The Designer picks the colour. `Splash` is the water hit we already have. An island bed loop is not in `SoundData` yet. W2 adds the key. This doc does not invent the asset id.

### Skyroot and the Aether Isles

- **Wood.** Lumenwood, 12 trees, and the forge on the main isle (Starfall Axe: lumenwood, Sky Shards, cash, as `V2_PLAN.md` already specifies). Sky Shards are the isle nodes (`BiomeData` `SkyShard` 8).
- **Way in.** The gondola, already built. $250 a ride, 40 seconds (`BiomeData.sky.gondola`). One station is by the sawmill, so the Sky Bin is a short walk from where you step off. The other is at the Skyroot's foot, for anyone who fell. `SkyrootRoad` (24 wide) runs from the snow road's second flare to that foot and stays free. No vehicles on the isles. Rope bridges join them. Logs go down the Cloud Chute into the Sky Bin (`skyBinVolume` 120 u³).
- **Landmarks.** The Skyroot, visible from everywhere, which is the navigation mark for the whole map. Skyroot Falls, where the river starts. The gondola cables. The forge.
- **Come back for.** Lumenwood, the forge, Sky Shards, and the Skyroot Bloom (the five ground groves averaging 75 vitality or more, `GAME_DESIGN` §16). Regrowth, Halloween trees, dailies, and the isle badge. Wind gusts and lightning are the pressure. Wood that falls off the isles is lost (axes stay). The Featherfall Cloak is the glide down, as in `GAME_DESIGN` §10.
- **Air and sound.** Thin air above the clouds, density 0.2 (`EnvironmentData.BiomeOverrides.sky`). The night mist does not apply up here. `WindHowl` on the isles. `WaterfallRoar` at the falls.

## 5. Hazards

These keep a shortcut honest. The numbers are the ones `GameConfig` already holds.

- **Deep sea** at the map's edge, east of the coast and around Ferry Island. `HazardService` will apply `WaterDamage` (15) every `WaterTickSec` (1.5). The Strand's beach is the safe side of that line.
- **Volcano heat.** Lava on the cone burns until the player has Heat Boots. Ash storms are weather, not a gate.
- **The dark cave.** The Secret Cave, and the hollow around it, need the Lantern. Without it the player cannot work the wood (`BiomeData.Rules`).

A slippery frost path on the snow peak stays the frost hazard `HazardService`'s stub names. It is not a toll and it does not close `SnowRoad`.

## 6. Landmarks you steer by

| Mark | Role |
|---|---|
| The Skyroot | Already standing in the north-west. Visible from everywhere. |
| Toll booth, red-and-white arm | New. On the spur north of the snow cliff only. Old Tolly. |
| Lighthouse | Already on the east headland, in sight of spawn. It is the ferry dock's tower. |
| Smoking volcano rim | Already on the cone. |
| Hermit's carved symbol | New, on the Secret Cave cliff, on the far side of Gloam Hollow. |
| Gate signposts | Already at the gates. `BuildingArt.nameSign`. New gates use the same sign. |

## 7. Secrets and collectibles

Three secrets. Each found one is a key in the account-wide `secretsFound` map.

- **The secret cave box**, in the Secret Cave, with our own line. Not a copied line. The firewood bin at a snow cabin (`V2_PLAN.md` §11) can stay a snow dressing. It is not this box, and it is not behind the toll.
- **Carved marks.** One hidden in a biome. Finding the set unlocks one decor item. The count is **TBD (Designer)**. The working layout, until that count is chosen, is one mark in each ground biome that exists today: Starter Forest, the Hills, the Snowfields, the Volcano, and Gloam Hollow (the hollow's mark on the cave cliff). Ferry Island and the Aether Isles are not in that five. If the Designer raises the count, those two are the next homes. The decor item's id is also **TBD (Designer)**.
- **The night-only painting**, on the lighthouse wall at the ferry dock. It is drawn only at night.

## 8. Why the map keeps paying a return visit

- Trees regrow in random spots (the regrow branch), so a grove you cleared is not empty tomorrow.
- Lanternwood shows only at night, on Ferry Island.
- Halloween trees from 1 October through 1 November.
- Daily goals that point at each area (B13).
- Area badges (B06), with badge ids left at 0 until they exist on the Creator dashboard.
- The limited shelf rotation (B01), so town is on the loop even after the truck is bought.

`areasVisited` records that a player has reached a region. It is account-wide, same as `secretsFound` and `badgesAwarded`.

## 9. The Timberline twist on this map

`GAME_DESIGN` §16 is already in the world: Heartseeds, the planter's share, grove vitality, and figured grain. This map adds one link.

Grove vitality on Ferry Island changes how many Lanternwood trees are glowing. Caring for a forest pays off on the island, which you can only reach by the ferry, and only read properly at night. The curve is **TBD (Designer)**. Vitality itself stays the §16 meter: 0–100, rest at 60, Thinning under 35, Healthy 35–74, Thriving 75–89, Old Growth 90 and above. Planting and felling move it the way `ForestData` already says. This doc does not retune those rates.

The Skyroot Bloom stays the five-ground-grove average (75 or more). The new toll ground does not become a sixth grove in that average until the Designer gives it a wood and says it counts.

## 10. Designer constants

W1 does not edit `GameConfig` (wave 0 owns it, and a later wave touches it again). The names below are the ones a later batch should add, with the Designer's numbers. Comments say why the value is open.

```lua
-- TBD (Designer): how many carved marks complete the set.
-- Working map in WORLD_DESIGN.md §7 is 5, one per existing ground biome.
CarvedMarkCount = nil

-- TBD (Designer): decor item id unlocked when secretsFound holds every mark.
CarvedMarkRewardId = nil

-- TBD (Designer): Lanternwood trees glowing at vitality 60 (the rest point)
-- and at 90 (Old Growth). Other tiers interpolate. Island only.
LanternwoodGlowAt60 = nil
LanternwoodGlowAt90 = nil

-- TBD (Designer): wood id, fog colour, and ambient key for the tolled ground.
-- Nil until chosen. Snowfields and the Volcano stay free either way.
TollAreaWoodId = nil
```

No number in that block was chosen here.

## 11. What later batches build

W2 (`WorldPlan`, `MapBuilder`, `TerrainGen`) places the toll spur, the extra ground north of the snow rim, the cracked boulders, the Secret Cave, the ferry dock at the existing lighthouse, and Ferry Island's trees on the existing island disc. It does not move a biome centre or radius, the town, the sawmill, the sell zone, the spawn, or Murph's camp.

Wood rows (Lanternwood, and the toll ground's wood once it has a name) belong to the batch that owns `WoodData`. Fog overrides belong with `EnvironmentData`. New ambient keys belong with `SoundData`. Quest copy for the Hermit belongs to the batch that owns dialogue, and it is our own lines.

When those batches add a prompt (toll, ferry, blast, Hermit), it is a server `ProximityPrompt` with `GamepadKeyCode`, a keyboard key, and a touch target of at least 44 px at 667×375, styled with `PromptUI`. Menus set `GuiService.SelectedObject` on open, move with the D-pad, and close with B, inside a 10-foot safe area. Binds go through `InputKit`. A placer action does not use ButtonX or keyboard E while world prompts are on.

## 12. Provenance

The layout echoes a few well-known lumber-game gates: a paid bridge, a ferry, boulders in front of a cave. The echo stays in this file. `src/` does not use those names, even in comments. Our names are the ones in the tables above.

| Our step | Echo, for this doc only |
|---|---|
| Town + Starter Forest | the main biome |
| The Hills | a mountain roadside |
| Toll, $100 for 3 minutes, and only on new ground | a short paid bridge |
| Secret Cave, blasting charge, Hermit | a cave behind boulders |
| Ferry Island, $400, every 6 minutes | a ferry to a palm island |
| Skyroot and the Aether Isles | our own ending. No echo |
