# Phase 2+ build notes

Everything after the Phase 1 vertical slice. It's all on `main` now
(merged October 2026, with the redesign below).

**Status:** code complete, **not yet played in Studio.** `./scripts/check.sh`
passes (formatter, linter, strict types against the Roblox API, 351 unit
tests, ECONOMY.md current); GitHub runs it on every push.

What's here, each with its own checklist below:
1. **The redesign (October 2026):** every model rebuilt, the world on
   terrain, a living environment, the Living Forest twist, feel and fixes
2. **Axe shop**: the Tool Shed
3. **Murph's tutorial**
4. **Trucks**: the Dealership, every truck, physics driving, Truck to lot
5. **Daily goals and streaks**
6. **The world**: biomes, roads, day and night, Hearth & Home
7. **Trailers**
8. **Robux**: the Store, 2x Cash, cash packs, 2x Wood, Instant Delivery
9. **The Field Guide**
10. **The Aether Isles**: gondola, Lumenwood, Sky Shards, Cloud Chute, Sky Bin, the forge
11. **Plots**: claim a plot, grow it, the Blueprint Store, placing, moving, selling back
12. **The new look**: every screen restyled from the Claude Design UI spec

Where the redesign changed something an older section describes (the
world layout, the trucks' looks, chop range, the Sky Bin), the redesign's
section wins.

Old saves carry over: new save fields are filled in on load and old ones
migrated. Play the sections in order the first time (a fresh save gets the
tutorial).

## Sawmills and planks (M2.2)

A straight log pushed into a sawmill on your plot comes out as planks.
Planks drag, ride the truck and sell for more than the same wood as a log
(oak is 2.5×). Buy one at the Tool Shed (**Browse saws**), then
place it from **BUILD** on your plot. The Rickety ($130) takes an oak
trunk and refuses a pine base or anything with a branch.

### What to check (in Studio)

| # | Do this | Good looks like |
|---|---|---|
| 1 | Claim the free plot. At the Tool Shed, Browse saws, buy the Rickety Sawmill ($130). Open BUILD on your plot | The mill is listed with "Place" and "in stock". The ghost is the saw, not an empty box. Placing it does not charge again |
| 2 | Cut a straight oak piece about 9 studs long (no branches) and push it into the back of the mill | After a short pause, core-coloured planks come out the front. The X/Y buttons step the cut by 0.2 u and the panel reads the size |
| 3 | Push a branched piece, then a thick pine base | A toast refuses each. A plank pushed back in is ignored |
| 4 | Drag the planks onto the truck and sell them on the pad | The toast pays the plank price (oak is 2.5× the log price) |
| 5 | Leave and rejoin with planks on the truck | They come back as planks, core-coloured, not bark |
| 6 | A second player presses your mill's X/Y buttons | Your cut does not change |

## Day 3: bigger trucks and the LT2 look (3 October 2026)

Connor's day-3 feedback: the car wouldn't drive, the tutorial never
appeared, the parking spaces were huge runways, the trucks should be
bigger again, and the trees and world should look like the reference game
(LT2_RESEARCH.md has what it does). In this build:

- **The client keeps going** when one of its scripts fails to load (the
  day-3 crash, "HUD is not a valid member of PlayerScripts", stopped
  everything: no driving, no tutorial). It waits up to 30 s for all of
  them together, then starts without a missing one and says so.
- **Trucks 1.3x** (TruckLayout.Scale). Driving is retuned so each truck
  turns its old circle, the sell zone is 24 x 12 x 40, and the Drive
  prompt reaches 9 studs. Bigger beds carry about twice the wood a trip:
  ECONOMY.md moved (first $1k 29 -> 19 min, Cobalt Axe 1.9 h -> 81 min,
  full plot 59 -> 46 h; the Steel Axe now comes at 3.3 min, faster than
  its 5-8 min target: a price call for Connor).
- **Parking bays that fit**: 13 painted bays in 4 sizes (8 small, 2
  Flatbed, 2 long pull-through, 1 longest pull-through), each about the
  truck plus 3 across and 4 along. Your truck takes the smallest free bay
  it fits; switching trucks moves it and a toast names the bay.
- **The look** (ATMOS):
  - a darker, muted meadow green (Grass 84,125,55; LeafyGrass 66,104,46)
  - haul roads pale grey across their whole width
  - a real night fog from 23:00, lifting by 09:30
  - a thick red fog in the Volcano, a cold haze in the Snowfields, a
    violet mist in the Gloam Hollow
  - big, bold name signs on the sawmill and the shops

The world slice landed with that look:

- **Trees.** Section trunks are boxes in that wood's bark (frostwood and
  lumenwood smooth, phantomwood concrete, the rest wood). Leaf crowns are
  crisp cubes. The biome forests are spaced about 1.5x wider and still
  have more than 775 trees. The filler woods behind them are thinner.
- **Roads.** Hills, Snow and Volcano roads are 28 wide, Skyroot 24, Forest
  Path and the plot road 16. The splits at about (30, 450) and (-20, 760)
  flare out. Brown boulders sit on the open grass.
- **Regions.** A brown cliff ring around the Snowfields with one pass on
  the Snow Road. A dark stone rim around the Volcano with one gap on the
  Volcano Road. Three shallow pools in the Gloam Hollow. A sign at each
  gate (SNOWFIELDS, VOLCANO, GLOAM).
- **Town.** A 22-wide way east of the Dealership, then north to the Snow
  Road. A 16-wide loop south of the lot, around to the plot road. The
  street is wider up to the sell pad, the lamps sit back off it, and the
  Forest Path, Hills Road and mill road open onto the plaza. Murph's camp
  sits just north of the widened Hills Road.

The first 322 trees kept the spots they had before the roads widened
(their height follows the new ground). Lune counts 778 tree spots and
31,409 section-tree parts (average 40.4, about 1.17x the old round
trees). Studio boot of this slice was not timed here; the earlier Studio
boot was 775 section trees in 0.6 s and the world in 4.6 s.

### What to check (in Studio)

Server command bar helpers: `workspace:SetAttribute("ClockOverride", 13)`
sets the hour (`nil` clears it); `workspace:SetAttribute("WeatherOverride",
"Clear")`; to jump somewhere: `local TG=require(game.ReplicatedStorage.Shared.World.TerrainGen); local x,z=950,1060; game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(x,TG.HeightAt(x,z)+8,z))`.

| # | Do this | Good looks like |
|---|---|---|
| 1 | Play with Output open | `[Client] Timberline Tycoon client started.` and no red, no `failed to load` or `never arrived` warnings |
| 2 | Wait a few seconds on the spawn | Murph's tutorial panel appears (a returning save that had finished the old tutorial gets a short "WHAT'S NEW 1/4" version) |
| 3 | Walk to the lot | Your Rustbucket sits centred in bay 1 (west end, south row), paint showing all round; it looks chunky next to you |
| 4 | Use the Drive prompt (from about 9 studs), drive out forward, turn round, drive along the street | Your head clears the roof and your legs stay inside the hood; no scraping or sticking; full lock at a crawl turns about the same circle as before; no tipping on fast turns |
| 5 | Jump out | You stand beside the driver's door, not inside the truck |
| 6 | Back onto the sell pad with wood on the bed, until the tail meets the mill ramp | The wood sells; the post, Sky Bin and lamps aren't touched |
| 7 | Switch to the Flatbed, then the Logging Rig + Heavy Hauler, at the Dealership | A toast names the new bay (Flatbed: bay 9; Rig + Heavy Hauler: bay 11), the rig sits inside its paint, and bay 1 is free again |
| 8 | Drive more than 42 studs from your bay, press Call/Send home | The button shows only beyond 42; the truck returns to its bay (or a better free one, with a toast) |
| 9 | 2 players | The second Rustbucket takes bay 2; when that player leaves, the bay frees |
| 10 | 13:00 at the spawn, then drive north up the Snow Road | A dark, muted green (still green, not olive) with darker patches; out of town the road is light grey edge to edge with only the odd brown voxel at its edges |
| 11 | `ClockOverride` 1, look round the spawn; then 6, 8, 10 | A grey-blue fog: the town clear, things past about 150-300 studs fading, still dark (lamps matter, a trunk reads at 30 studs). 6: a thick rose mist; 8: lifting; 10: exactly the daytime look |
| 12 | Jump to (950, 1060) at 13:00 (stand in a truck or wear Heat Boots), then 01:00 | A thick red-orange fog, emberwood trees still findable at 60-100 studs; at night a dark red fog, not glowing. Walking out past the Volcano's edge it fades back in about 3 s |
| 13 | Jump to (0, 1080) and (-565, -455), at 13:00 and 01:00 | The Snowfields: a light cold white-blue haze by day, no whiteout. The Gloam Hollow: a violet mist, the darkest place at night but never black |
| 14 | Look at the shops from the spawn, the middle of the lot (about 80, 0, 24) and a truck on the street; again at 22:00 | DEALERSHIP, TIMBERLINE SAWMILL, TOOL SHED and HEARTH & HOME readable from the lot, letters filling the boards, nothing through a roof or blocking a door; two lamps light each sign at night. If the letters look small inside a big board, tell Claude |
| 15 | In the Rustbucket, then the Logging Rig: drive the Hills Road, the Snow Road, and through both splits (toward the Volcano near (30, 450), toward the Skyroot near (-20, 760)) | The haul roads are wide enough that the Rig isn't filling the lane; each split opens into a flare instead of a sharp corner; the road stays pale grey |
| 16 | Drive east of the Dealership, north past the sawmill, onto the Snow Road; then south of the lot, around the loop, and up to the sell pad | A truck-wide road clears the mill and the shops and meets the Snow Road; the south loop lets a long rig turn without backing the length of the lot; backing onto the pad is a straight, wide approach; lamps and benches sit off the street |
| 17 | Walk a birch, a pine and (if you can reach it) a frostwood or phantomwood; look at the crowns | Trunks are square boxes in that wood's colour; crowns are blocky cubes, not soft blobs; trees in a biome forest stand further apart than they used to, and the woods still read as a forest |
| 18 | From town, look across the open grass; then jump to the Snowfields pass (0, 1240, then south to the cliff), the Volcano gap (950, 1060), and the Gloam Hollow (-565, -455) | Brown boulders on the open grass, with a thinner scatter of background trees. Snow: a brown rock wall with one low pass. Volcano: a dark rim with one gap. Hollow: three shallow pools and a GLOAM sign; SNOWFIELDS and VOLCANO signs stand at their gates |

## The v2 loop goes live (M1.9, 2 October 2026)

Connor's call (V2_PLAN.md): the game now plays like the spec he sent.
`GameConfig.CoreLoop = 2`. Trees are section trees you can cut anywhere:
a notch grows where you keep hitting, the tree tips and falls, and you cut
the trunk and limbs into pieces. You put the axe away and drag the wood
(heavy pieces drag slowly; cut them shorter). Loose wood rides on the
truck's bed by friction, and wood resting on the green sell pad by the
sawmill sells by volume: u³ x the wood's price per u³. A new player starts
with $20 and a Rusty Axe. Prices and axe numbers are the spec's (ECONOMY.md
is the v2 model now; ECONOMY_V1.md keeps the old one).

**Old saves.** The first time a player joins, the logs they had on hand
(truck bed, left-behind logs, Sky Bin) are bought back at their saved
value: "Murph bought back the logs you had on hand: +$X". Anyone under $20
is topped up to it ("Murph chipped in $X to get you started."). Lumenwood
in the forge becomes forge wood (40 logs = 60 u³). Axes, trucks, plots,
Heartseeds, the Field Guide, streaks and Robux purchases are all kept;
tutorial progress restarts only on the steps whose unit changed.

**Rollback** if something is badly wrong: set `CoreLoop = 1` in
GameConfig, rebuild and republish. Migrated saves load fine under v1.

### How to update the live game

As in Glitch wave 1 below: fetch `main`, `rojo build -o build.rbxlx`, open
it, run the checks, **File > Publish to Roblox**. Then on create.roblox.com
open the game and use **Restart servers for updates** (Migrate to Latest
Update), so no server keeps running the old loop.

### What to check (in Studio, before publishing)

| # | Do this | Good looks like |
|---|---|---|
| 1 | Play with Output open | `[CoreLoop] 2`, `[MapBuilder] N section trees in X s` (**paste this line to Claude**: it's the boot-time risk), `[SectionTrees] N trees on N sites`, `[GameServer] <you>'s save is now on the v2 loop (bought back $X, topped up $Y)` the first time, and a toast with the buy-back or Murph's $20. No red |
| 2 | Walk into the Starter Forest | Big, varied trees, some young |
| 3 | Tutorial step 1: hit an oak's trunk at knee height with the Rusty Axe | A notch grows on the face you hit and a ring fills; on about hit 16 the tree tips away from you, its leaves drop about 1.5 s later, and a stub with a pale cut face stays |
| 4 | Step 2: press 1 to put the axe away, then click and hold a log | It drags. A whole trunk is heavy: cut it in half (about 16 hits) and drag the halves. Cutting a limb where it joins frees it |
| 5 | Step 3: drag the wood onto the Rustbucket's bed | It rests there; the HUD shows the bed's u³ and $ |
| 6 | Step 4: drive to the mill at full speed and back onto the green pad | Nothing falls off on the straights (a hard turn may slide a log). On the pad: "Sold N pieces · X u³ · $Y". The truck stays. Spawn to first sale under 4 minutes |
| 7 | Steps 5-7: plant the Heartseed in your stump, sell $60 more, buy the Steel Axe | The sapling grows with your name; Murph pays $25; the Steel Axe costs $90 |
| 8 | Stop and Play again with wood on the bed, parked in town | The load is back on the bed where it lay. Leave it out in the forest instead: "Your last load is waiting where you left your truck." |
| 9 | **Test > Clients and Servers**, 2 players | Player 2 can't grab wood on your bed ("That's on <you>'s truck."); a log of theirs you sell pays them; no jitter on either screen |
| 9b | Ownership (2 players): player 1 hits an oak once, then player 2 swings at it; player 1 fells it, then player 2 tries to grab the trunk; then player 1 leaves | Player 2: "Player1 is cutting this tree. Find another one."; then "That's Player1's wood."; once player 1 has left (and 45 s after the cut), player 2 can take it. A tree player 1 stops hitting for 60 s is free to take over |
| 10 | If logs jitter on the bed: Server command bar `workspace:SetAttribute("Tune_BedAutoWeld", 1)` | Resting logs weld within a second; grabbing one unwelds it. Tell Claude if you needed it |
| 11 | The isles: lay a Lumenwood piece on a Cloud Chute's hopper; at the mill press **Sell Sky Bin**; lay plain Lumenwood on the forge | "Sent 1 piece down the Cloud Chute. Sky Bin X/120 u³"; the bin sells with the usual toast; "Into the forge: X u³. Lumenwood X/60 u³ · Sky Shards ... · $20,000" |
| 12 | Phone emulator + **View > MicroProfiler** during a felling in the Starter Forest | 30+ fps, no long spike when the tree lands |
| 13 | Rollback check: in edit mode `workspace:SetAttribute("CoreLoop", 1)`, Play | Today's game as before (logs in hands, Load and Sell prompts). Clear the attribute afterwards (`nil`): PlaceCheck warns if it's left set |

The stopwatch prints `lune run tools/economy --calibrate ...` once you've
sold enough: paste it to Claude (it calibrates ECONOMY.md).

## Glitch wave 1 (after the first live session, 2 October 2026)

Connor played the live game and sent screenshots: NPCs standing chest-deep
in the cobbles, a Rustbucket buried to its fenders in the lot, the parking
paint missing, players spawning under the ground, tall grass inside the
shops, lots of things you could walk through, and a landscape that still
looked bare. What this wave changed, and how to check it.

### How to update the live game

In PowerShell, in the game folder:

```powershell
Get-Process rojo -ErrorAction SilentlyContinue | Stop-Process
git fetch origin
git checkout main
git reset --hard origin/main
git log --oneline -1
rojo build -o build.rbxlx
Invoke-Item build.rbxlx
```

In Studio: Play once with **View > Output** open (checks below), Stop,
then **File > Publish to Roblox**. On create.roblox.com open the game and
use **Restart servers for updates** (or **Shut down all servers**).

On the live game, the same Output lines are in the in-game console: press
**F9** (or type `/console` in chat) and pick **Server**.

### What to check

| # | Do this | Good looks like |
|---|---|---|
| 1 | Play with Output open | `[TerrainBuilder] Town ground: written at 0, drawn at 2.00; heights shifted -2.00 studs (tries: ...)` (the first Studio run read 2.00) and then `[TerrainBuilder] Town ground at y = 0.0x (6 probes): good`. **Paste both lines to Claude.** A yellow `Town ground is at y = ...` warning means the ground is still off |
| 2 | Look at the townsfolk: Millie by the sell pad, the three shopkeepers, Murph, the walkers (Rosa, Pip, ...), and Murph's camp | Feet on the ground, whole legs visible, nobody waist-deep. The tent, campfire and log seats stand on the ground |
| 3 | Walk to the parking lot | Your truck sits on its wheels; every slot shows its pale lines, number and lamp |
| 4 | Respawn a few times (reset your character) | You appear standing on the spawn pad, never inside the ground |
| 5 | Walk into each shop and the gondola station | Packed dirt round the walls and no grass poking up through the floor or hiding the fronts; grass elsewhere is shorter |
| 6 | Look around the town and a forest | Trees, stumps, boulders, signposts and flowers stand on the ground: nothing sunk, nothing floating |
| 7 | Walk into the solid-looking things (COL-01): in town the log piles east of the mill, the mailbox at the west end of the street, the benches' backs, the tool rack, the hand cart, the sawmill's log deck and carriage log, the Tool Shed's grindstone (out front) and workbench, Hearth & Home's coat stand and boot shelf, the Dealership's tyre stack, the gondola lectern, Murph's rocks and firewood, the town rocks | You stop at each one (you can stand on the logs and rocks) |
| 8 | Out in the country: an outcrop (up the Snow Road), a fence or hay line, a lookout tower, a ruined cabin, a windmill, the island palms' trunks, a biome road sign's board | You stop and can climb the rocks; sails, braces and ladder rungs are still walk-through. Driving along the roads touches none of them |
| 9 | Drive a Logging Rig from the street onto the sell pad, back out, and between the SELL LOGS HERE posts; walk from the spawn to Murph under TO THE WOODS | Nothing in the way (those boards stay walk-through on purpose) |
| 10 | Cross each rope bridge on the isles and walk sideways into the rope | An invisible wall stops you; getting on and off at the ends is smooth |
| 11 | Frame rate in the open country (about 1,650 more solid parts) | Same as before |
| 12 | A little more Lumber Tycoon 2 (STY-01..05): stand on the spawn, then drive the Snow Road north out of town and look at the hills and mountains | A deeper green meadow, brown cliffs and ridges under white snow, and the haul roads with a pale gravel crown between dirt verges (the town's street stays dirt; day 3 made the roads pale grey edge to edge, see the top section). If the gravel looks like tiles, tell Claude (it's one setting) |
| 13 | West of the Starter Forest, about (-124, -177) and (-261, -189), and the Hills' grassland | Groups of 3-5 half-buried brown boulders; every lone boulder and outcrop is brown too. They block you, and none sit on a road or in water |
| 14 | The timber footbridge over the river at about (-877, 575); the plank docks on Mirror Lake (-716, -111) and on the east coast (1194, -760) | You walk on and off the bridge without a hop, the rails stop you, TIMBER BRIDGE and MIRROR LAKE signs read. Each dock has a ladder, a lantern (lit at dusk) and a rowboat you can walk through |
| 15 | On the spawn pad, look east | A small red-and-white lighthouse on the horizon just left of the PLOT DISTRICT sign. At night its lamp glows (Server command bar: `workspace:SetAttribute("ClockOverride", 22)`, `nil` to clear) |
| 16 | `ClockOverride` 1, then 8, then 12 (and 12 on a phone emulator) | A little hazier at night, thinning through the morning, exactly today's look by day |
| 17 | The forest ring (FOR-01..04): stand on the spawn and turn round, then walk into the forest about (-100, -450) and drive the Snow Road north | The town and plots stay an open lawn; a forest edge closes the view about 300 studs out; inside, blocky background trees all round (you walk through those; they fade if they'd hide you) and detailed choppable trees along the edges, clearings and road verges (771 on the ground now; the roomier plots took seven stand trees, and the lighthouse vista took two more). Output: `[ForestFiller] plan ready in X s` (under ~2 s), no `plan step N failed` |
| 18 | The forest floor and grass | No grass blades under the forest (a leafy floor instead); blades on the town lawn, plots and meadows; fanned tufts with light tips along forest fringes, road edges, rocks and fence posts |
| 19 | Phone emulator (iPhone SE, 14 Pro) in the deep south forest and on the Snow Road, with the frame-rate stats | 30+ fps, `[Quality] low` in Output, the `workspace.ForestFiller` folder about 4k parts or fewer (desktop about 7.5k or fewer) |
| 20 | Optional: Roblox's textures on the ground. In Studio, MaterialService: GrassName = TimberGrass, LeafyGrassName = TimberLeafy, GroundName = TimberGround | Textured ground at a softer tiling, blades still on Grass. If it looks grey or flat, clear the three names again; if it looks good, tell Claude and they go into the project |

Left walk-through on purpose: town signpost boards (TO THE WOODS hangs
over the spawn walk; SELL LOGS HERE over the rig's lane), rocks at
signpost feet (too close to the roads), the mailbox post (the box still
stops you), the wheelbarrow on the plaza, sawdust piles, bushes, flowers,
leaves and branches, felled logs, plot rails, and everything the client
scatters on its own (rocks, stumps and logs in the forests: a collider
only one player has would fight the truck physics), and bark-clue burls
(a round lump would collide as a box).

## Tonight (phase 10): smoke test and what each build changed

Players arrive at 9:00 pm Mountain time (03:00 UTC). Everything lands on
`main` in small green merges; the freeze is at 8:00 pm, and after it only
what Connor reports from Studio gets fixed. HANDOFF.md has the plan and
the backlog ids used below.

### Once per build

1. `git checkout main && git pull`, then `rojo build -o build.rbxlx`. Open
   it in Studio and **File > Publish to Roblox** over your private test
   place (this is how place settings arrive; `rojo serve` doesn't sync
   them). Then `rojo serve` and **Plugins > Rojo > Connect**.
   - Rojo now owns **ReplicatedFirst** (the loading card). Anything you put
     there by hand is deleted on Connect; it should be empty.
2. **Game Settings > Places > Max Players: 12** and **Game Settings >
   Security > Enable Studio Access to API Services: on**.

### Tonight's smoke test (run it on Build #1, then again on the last build)

Paste the Output and screenshots of anything wrong into the session.
Anything red becomes a P0 and jumps the queue.

| # | Do this | Good looks like |
|---|---|---|
| 1 | Press **Play** with **View > Output** open | Roblox's loader, then a brown **Timberline Tycoon** card with a rotating tip, then a fade into the spawn. No grey frames. Output: a white `[PlaceCheck] can't check ...` line, `[PlaceCheck] OK`, `[MapBuilder] World built in Xs (terrain Ys)`, `[GameServer] Online: world built in Xs (terrain Ys), 334 trees, 1 player`, `[Client] Timberline Tycoon client started.` No red lines. Note X |
| 2 | Look around at the spawn | You face the sawmill with SELL LOGS HERE between the two lamps (from Build #2). A mountain ring, the volcano and the sea fill the horizon in every direction (Build #4) |
| 3 | Tutorial step 1: fell the oak Murph points at | Murph says the woods are south of town and says **Click** (Tap on a phone, Press RT on a pad). The swing turns you to face the tree |
| 4 | Steps 2-3: pick up logs, load the truck | Your arms come up under the logs (Build #2) and the hint changes to "Take logs to your truck's tailgate" |
| 5 | Step 4: drive to the sawmill and sell | Sitting in the truck switches the hint to "WASD to drive · Space to hop out". The rear wheels follow the front in a tight turn (no tail slide). Under 4 min from spawn to sale. Say if a truck stops dead at a road edge (ACT-05) |
| 6 | Step 5: plant | No Plant prompt on any stump before step 5 (the toast says "keep it for now"). At step 5 your first stump is still there (held up to 4 min) or the beacon points at a tree to fell. The sapling grows in 8 s with your name |
| 7 | Walk the thickest part of the Starter Forest | You can always see your character; leaves in the way fade (Build #2) |
| 8 | Ride the gondola up and down | Smooth, about 40 s, no stepping (Build #3) |
| 9 | Stop, then Play again | Cash, axe, truck bed and settings are all kept |
| 10 | **Test > Clients and Servers**, 2 players | Each sees the other's truck move smoothly; your logs stay yours for 45 s |
| 11 | **File > Studio Settings > Network > Incoming Replication Lag** 0.2, drive 60 s | No rubber-banding, no put-back |
| 12 | **Device Emulator**: iPhone SE, then iPhone 14 Pro (landscape) | Toasts stack under the tracker and never cover the cash, ♪ or tracker. During the tutorial: no Daily Goals button and no clock. Note anything that overlaps |
| 13 | Phone emulation + **View > MicroProfiler**. Night: in the **Server** command bar run `workspace:SetAttribute("ClockOverride", 23)` (`nil` clears it). Town at night, the Starter Forest, the Snowfields, the isles | 30+ fps (frame under 33 ms). Note the top script costs |

### Build #4 (the horizon, the town, the truck ladder)

- **WLD-02 / WLD-09 horizon** Stand on the spawn and turn slowly 360
  degrees, on desktop and in the iPhone emulator: north, west and south
  show mossy ridges in front of grey snow-capped peaks; north-east the
  volcano's dark cone; east and south-east a sea horizon with low
  islands. No flicker where snow meets rock. During Play,
  Workspace.TimberlineMap.Backdrop exists with 284 parts (Persistent;
  nothing collides). Ride the gondola to the main isle and look N, W and
  E: no void and no cut edge. Walk round the volcano: no dark faceted
  faces poking through the real cone. At ClockOverride 23 the ring is a
  dark silhouette; at 13 hazy but visible.
- **TWN-01 town greenery** From the spawn, a maple behind the Dealership,
  a birch behind the Tool Shed and pine tips beside the mill; from above,
  trees frame the town in stone rings. Swinging at a town tree does
  nothing (no outline, no HP bar). Only trunks block you; bushes,
  flowers, ring stones and rocks don't. No greenery in a pull-out lane,
  on a road, or in the gondola's way.
- **TWN-04 markers** From the spawn on an iPhone 14 (landscape): SELL
  LOGS, AXES, TRUCKS, BLUEPRINTS & GEAR and GONDOLA cards float over the
  right buildings, readable; they fade as you walk up and hide while a
  shop is open. A SELL LOGS HERE signpost stands by the pad (on the Tool
  Shed side: say if it reads as the Tool Shed buying logs).
- **ACT-07** In the Dealership line-up, the trucks step up in height:
  Rustbucket < Pickup < Flatbed (glossy mustard) < Logging Rig (bigger
  wheels, tallest cab, tall chrome stacks). The Rig still parks in its
  slot, loads from the tailgate, and turns as in Build #3.

- **WLD-18** MicroProfiler or View > Script Profiler (Client), phone
  emulation, 10 s in the Starter Forest at midday: LightingController
  well under 0.1 ms a frame. Watch a dusk (HUD clock about Day 16:50, 2
  real minutes): long shadows lengthen smoothly, sky colours glide, lamps
  come on one by one. Walk into the Phantom Grove and back: a smooth
  ~3 s fade. Storm (`workspace:SetAttribute("WeatherOverride", "Storm")`):
  each bolt flashes and the scene returns to its stormy brightness.
- **UI-19** iPhone SE, every shop, the Store, the Blueprint Store and the
  Field Guide: each subtitle reads in full; row names end before the Buy
  button (check "Featherfall Cloak · owned" and "The Hidden Grain").
  Skip tutorial shows from step 2, not step 1.
- **UI-12** HUD headings in the same rounded face as the signs; the
  beacon is an amber triangle with an even dark rim at 10, 40 and 100
  studs; the sound button is a drawn speaker and still opens Settings
  once per tap.

**Not done tonight** (backlog ids for tomorrow, none started on main):
WLD-05 waterfall motion (a partial patch exists only in this session's
container), WLD-08 isle tops, TWN-06 lot lines and lights, TWN-07 night
signs, TWN-05 road links, UI-15 gamepad shortcuts, ACT-09 round hubs,
ACT-08 Starfall axe, WLD-01 open country, NAT-14 stands, WLD-10 snow
contrast, WLD-12/13/14/15, NAT-08/10/11/16/18, ACT-06/10/11/12/14,
UI-11/17, PLAY-06 sounds (needs your ids), PLAY-12, PLAY-16, TWN-09/10/
11/12.

### Build #3 (phones, frame rate, driving, the gondola, trees)

- **WLD-07 gondola (check this first)** Ride up from town and back down,
  with View > Output open. Good: the cabin eases out, glides with no
  stepping, eases in at about 40 s, you stand on the platform, $250 is
  charged once, no gondola errors. With 2 clients the watcher sees a
  smooth glide; two riders pass through each other. Jump out 10 s in:
  you fall, the cabin vanishes, no refund. Watch the first 30 studs out
  of the town station for any snag (riders now collide with the world).
  With Studio Settings > Physics > Are Owners Shown, the cabin shows the
  rider's colour.
- **ACT-05** Full throttle from the lot onto terrain, over road edges and
  kerbs, up the Starter Forest hill: no dead stops, at most a small bump.
  A 0.5-stud part head-on and at 45 degrees: the truck climbs over.
  Getting out still parks it upright. With a trailer too.
- **ACT-03 fix** The Logging Rig turns a visibly wider circle at low speed
  (about 30 studs across); the Rustbucket and Pickup feel as before. Pull
  the Rig out of a slot between two parked trucks: it clears them (a west
  slot may need a three-point turn, as before).
- **ACT-04** Sit in the Pickup, Flatbed and Logging Rig with a tall hat:
  the head and hat stay under the roof. On the Scout ATV the legs pass
  under the bars. Check R6 too (Roblox may seat it a little higher).
- **UI-07 / UI-09** iPhone SE and iPhone 14 Pro (both landscapes): every
  button is easy to tap, text is readable, the side buttons and the shop
  panel stay clear of the notch and the top bar. Desktop looks as before.
- **UI-04 fix** The load chip appears with your first log, not before.
- **UI-14 / UI-16** Toasts stay up long enough to read (the truck recall
  confirm 6 s) and say "an oak". Every button clicks once; silent with
  SOUND FX off.
- **Small fixes** The sell hint shows only with something to sell; the
  tutorial beacon never points at an Elder; the first Heartseeds say
  "keep them for now"; the phone clock doesn't flash while loading; the
  corner clock follows ClockOverride; Skip says Tap/Click/Press.
- **PLAY-04 / PLAY-05 / NAT-09** Output prints `[Quality] high (...)` on
  desktop and `[Quality] low (Automatic, touch only)` in the phone
  emulator. MicroProfiler in a Snowfields frostwood stand: WindSway under
  1 ms (high) / 0.5 ms (low). Trees beyond the nearest 32 (16 on low)
  don't sway. A tree you fell, then leave and come back to, sways normally.
- **WLD-06 / WLD-17** ClockOverride 23: night is lighter (trunks read at
  30 studs in the Starter Forest and Hills); the Phantom Grove is darkest
  but not black. On the isles at midday the Lumenwood crowns keep their
  shape (bloom 0.7).
- **NAT-17 / NAT-07** Pines are 5-sided tiers; frostwood is deep blue with
  a white tip and collar and a dark slate trunk, and stands out from the
  snow (its foot ice shards are gone, on purpose: part budget). The world
  is about 2,200 parts lighter.
- **NAT-04 / NAT-12** A planted sprout sits on its stump (no soil in the
  air) and grows to the tree; the Heartseed orb is bigger with a trail.
- **NAT-13 / NAT-19** Decor fallen logs and old stumps look old (grey,
  mossy, mushrooms); the rabbit's eyes sit in its head.

### Build #2 (Phase 2: chop, carry, drive feel right; first town fixes)

- **ACT-01** Carrying logs raises your arms (R15: about halfway up with
  the elbows bent; R6: straight out). One log rests in the forearms, a
  second hangs just under it, and nothing covers your eyes or mouth.
  Loading, selling, dropping, sitting or dying lowers the arms at once.
  Load 1 of 2 logs into a bed with room for one: the log left in hand
  moves up to the top spot. With 2 players, each sees the other's pose.
  Check an R6 avatar too (Game Settings > Avatar).
- **UI-04** A load chip left of the hint: "Hands 1/2 · Bed 0/6", amber
  "Bed full" at capacity. (Build #2 still shows it from the first second
  as "Hands 0/2 · Bed 0/6"; it hides until you carry something in the
  next build.)
- **UI-03** Open the Tool Shed with $0 and press Buy on Steel: the toast
  sits inside the panel's bottom-left, the hint pill is hidden, and the
  title and Buy buttons stay readable (iPhone SE and a 1366x768 window).
- **WLD-03** (HUD part) Under the loading card the HUD's own card says
  "Building the world...", then "Loading your save...". No "Infinite
  yield possible" lines in Output.
- **NAT-02** Walk the densest Starter Forest patch and stand under a Hills
  pine with the default camera: leaves between the camera and you fade
  to see-through and come back after you pass. Trunks never fade.
- **NAT-03** Every stump's highest point is the pale cut ring; the root
  flares stay low around its foot.
- **NAT-06 fix** A felled tree fades out as the logs appear (no blink of
  empty ground).
- **TWN-03** (early, from Phase 3) The first frame after the loading card
  looks north at the sawmill with SELL LOGS HERE between the two lamps,
  the Dealership on the left and the Tool Shed on the right. Same after
  a reset, on R6 and R15, and for 2 players.
- **TWN-08** (early) No well in the street: it stands on the green between
  the benches south of the street. No barrels on the gondola path. Drive
  the whole main street and back onto the sell pad without bumping
  anything.
- Previews only (no game change): the town preview is rebuilt from the
  real layout (TWN-02); a world-eye scene with eye-level and night views
  (WLD-19); the shared flume and road-sign helpers build exactly what
  they did before (check the four road signs still read THE HILLS /
  SNOWFIELDS / THE VOLCANO / AETHER ISLES and the Cloud Chute flumes go
  out and down from the isles).

### Build #1 (Phase 1: a first session that can't break)

- **PLAY-07** One broken builder no longer stops anyone spawning. To see
  it: put `error("x")` as the first line of `BuildingArt.Sawmill()`, Play:
  you still spawn, the sawmill is missing, one yellow `[MapBuilder] 4. The
  sawmill failed, the rest of the world still builds:` warning, and the
  Online line ends `, 1 build step failed`. Remove the line again. In
  Play, Workspace's attributes show MapBuildSeconds, MapTerrainSeconds,
  MapTrees = 334 and MapBuildFailures = 0.
- **PLAY-02** `[PlaceCheck]` compares the live place with
  `default.project.json`. Untick Workspace.StreamingEnabled (don't save),
  Play: one yellow `[PlaceCheck] Workspace.StreamingEnabled is false,
  expected true. Fix: ...`, no OK. Set Max Players to 20: a warning naming
  Max Players (if it doesn't warn, run `print(game.Players.MaxPlayers)` in
  Play and tell Claude the number). Turn API access off: a warning that
  saves won't persist. Put each back. Three settings can't be read by
  scripts (StreamingTargetRadius, StreamingIntegrityMode,
  Terrain.Decoration); check those by eye in Properties.
- **PLAY-01** The Online line reports build seconds, terrain seconds,
  trees and players.
- **WLD-03** (loading card) Shows from the first frame; fades once your
  character and save are in, 30 s at most, never stuck. On an iPhone SE
  the title and tip fit with margin.
- **WLD-06** (step 1) `ClockOverride` (Studio only, set from the
  **Server** command bar): 23 gives night within a second (sun, lamps,
  windows, headlights, the Phantom Grove wakes), 12 gives day, `nil`
  returns to the shared clock. The HUD clock label keeps the real hour.
  A live server ignores it.
- **UI-18** With TextChatService > ChatWindowConfiguration.Enabled
  unticked, Play still prints `[Client] Timberline Tycoon client started.`
  and no `failed to start` line.
- **NAT-01 (ui part)** Placing a blueprint: the ghost is theme green when
  it fits, brick red (#C0503A) when it doesn't.
- **UI-01** Toasts keep to a lane: on desktop between the tracker column
  and the corner; on phones under the tracker, 2 at most. On phones the
  clock sits on corner line 2 and is hidden during the tutorial.
- **PLAY-03** See smoke-test step 6. Also: plant before step 5 (if you
  can find a way) is refused with "Hang onto it: Murph will show you
  where." and the seed is kept.
- **UI-05** The hint follows what you do: chop / carrying / driving /
  the sell pad / placing a blueprint, worded per device. Known: on the
  sell pad with nothing to sell it still says "Press E to sell your logs".
- **UI-08** During the tutorial: no Daily Goals button, no daily toasts
  (progress still counts), the Heartseed pouch only from step 5. "Truck to
  lot" is now **Send truck home** and only shows when your truck is more
  than 20 studs from its slot and you're 40+ studs from it.
- **UI-06** Drop axe shows only with a spare or better axe, needs two
  presses ("Confirm drop" in amber), and sits on D-pad down (not X). The
  server keeps your last axe ("You need an axe to chop!"). On a gamepad:
  check D-pad down doesn't open a Roblox menu.
- **ACT-02** (early, from Phase 2) A swing turns you to the tree when it's
  off to the side. Not while seated.
- **ACT-03** (early, from Phase 2) Trucks turn about the rear axle. Hold
  full lock at walking pace in the Rustbucket: a tight circle about the
  rear wheels, no jitter. In the Logging Rig, drive up and down the
  steepest Hills slope braking hard: no nose-dive or wheelie. Say if the
  long rig's nose now clips town lamps or corners.
- **PLAY-08** Lighting.PrioritizeLightingQuality is off (better phone
  frame rate). A fresh `build.rbxlx` shows it unticked; if your published
  place still has it on, `[PlaceCheck]` warns. A/B it if you have time:
  during Play, Esc > Settings > Graphics Mode Manual, quality 1-3, town at
  night (ClockOverride 23), read fps from the **View > Stats** panels (not
  Shift+F5, which stops the test) with it on and off. Studio's emulator
  still uses the Mac's GPU, so a real phone on the published place is the
  deciding number.
- **PLAY-15** Logs you fell are yours for 45 s (was 10). With 2 players,
  the other one is refused with "Their logs are up for grabs in N
  seconds." counting down.
- **PLAY-14** At most 72 left-behind logs are saved and restored (a full
  Logging Rig + Heavy Hauler).
- **NAT-01** The tree HP bar sits just over your head (7 studs up) for
  every tree, and is a pill: green, amber at half, red at a quarter. On a
  phone, tapping the trunk where the bar overlaps still swings.
- **NAT-05** Chips arc out, land around the trunk, rest about a second and
  fade. None below the ground.
- **NAT-06** The fall dust is soft smoke (no sparkles) in the biome's
  colour, about ten leaves flutter down, and the trunk fades out as the
  logs appear. Say if there is a blink of empty ground before the logs
  (it gets shifted in Build #2). A regrown tree is fully solid.

## Try this build

```sh
git checkout main
git pull
rojo build -o build.rbxlx   # once: open this file in Studio (see below)
rojo serve                  # then connect from Studio as usual
```

**Open the built place once.** `rojo serve` syncs scripts, but some of the
place settings in `default.project.json` only arrive in a built place:
StreamingEnabled and its radii, Lighting's style and quality, terrain
decoration (grass), GlobalWind. Open `build.rbxlx`, then File > **Publish
to Roblox** over your existing place (or set those properties by hand in
the Explorer to match the project file). After that, `rojo serve` as
usual.

Also in Studio, once:
- **Game Settings > Places > Max Players: 12 or fewer** (there are 12
  plots).
- Game Settings > Security > **Enable Studio Access to API Services**, so
  saves persist between tests. Studio playtests save to their own
  DataStore (`PlayerProfiles_Studio`), so testing can never touch a real
  player's save.

## The redesign (October 2026): models, a living world, the Living Forest

REDESIGN.md has the engineering side (rules, contracts, who owns what);
GAME_DESIGN §16 has the twist and §17 the art and world. In short:

- **The world is terrain**, generated from code (`Shared/World`): rolling
  hills, a river from the Skyroot's waterfall down to a lake, the coast and
  an island, the Snowfields plateau, the Volcano's cone with its lava
  crater, the Phantom Grove's hollow, mountains round the edge, dirt roads
  between them. The server writes it when it starts (nearest the town
  first; nobody spawns until the ground exists).
- **Every model is new** and built from code in `Shared/Art` (so the
  preview tool draws exactly what the game builds): 9 woods' trees with
  stumps, logs and saplings; the sawmill with its spinning blade, the Tool
  Shed barn, the Dealership garage, Hearth & Home; the gondola stations,
  Murph's camp, lamps, fences and props; the Skyroot (a colossal tree whose
  limbs hold the isles), the isles, rope bridges, the waterfall and cloud
  banks; 5 trucks and 3 trailers; 9 axes; Murph and 8 townsfolk; rocks,
  bushes, flowers, ferns, reeds, lily pads and more; birds, butterflies,
  rabbits, deer, ducks, fish, fireflies, wisps and ember sprites.
- **A living environment:** a smooth 20-minute day (dawn, midday, golden
  hour, dusk, night) with lamps and windows that light up one by one;
  weather from the server clock (clear, cloudy, rain, storms with real
  lightning, fog at night; snow and blizzards on the Snowfields, ashfall at
  the Volcano, wind on the isles); trees that sway; decoration and
  wildlife around you; ambient sound and day/night music.
- **The Living Forest** (the twist): felled trees drop **Heartseeds** you
  plant in stumps (the tree regrows at once with your name on a stake);
  you earn a **planter's share** when anyone fells a tree you planted;
  each grove has a **vitality** that replanting raises (thriving groves get
  more flowers, wildlife and figured wood, old-growth ones wake a giant
  **Elder tree** the whole server fells together); some trees hide
  **figured wood** (curly, birdseye, quilted, burl, stormgrain, starfall)
  you learn to spot from **bark clues**, revealed with a stamp when you
  sell; **storms strike real trees**, which glow and give Stormgrain; when
  every grove thrives, the **Skyroot blooms**.
- **Feel and fixes:** chopping outlines the tree you'd hit and measures
  reach from the bark; the cash counts up with a "+$" pop; a ♪ Settings
  button (music and sound effects, saved); trucks are owner-only, park
  themselves on exit and keep their load across sessions; the Featherfall
  Cloak glides properly; Robux cash over the wallet cap is banked, not
  lost; a dozen smaller fixes.

### Handy test commands

In Studio's command bar while playing (server side, the "Server" view):
- `workspace:SetAttribute("WeatherOverride", "Storm")` (or `"Rain"`,
  `"Fog"`, `"Cloudy"`, `"Clear"`); `nil` hands the weather back to the
  schedule. `WeatherOverrideIntensity` (0 to 1) sets how strong.
- `workspace:SetAttribute("RainbowTest", true)`: a rainbow, by day.
- `require(game.ServerScriptService.ForestService).WakeElder("starter")`:
  an Elder oak now.
- `require(game.ServerScriptService.ForestService).Strike(Vector3.new(0, 0, -110))`:
  lightning hits the nearest tree to that point.
- `workspace:SetAttribute("Vitality_starter", 85)` on the client view
  re-scatters the Starter Forest's decoration as a thriving grove (the
  server's own vitality is unchanged).
- In chat (Studio only): `/giveaxe inferno` (any part of an axe's name)
  gives a temporary axe.

### Sounds to pick

Some new sounds have no id yet and stay silent until you pick one (Toolbox
> Audio, Creator = Roblox, right-click > Copy Asset ID, paste as
`"rbxassetid://<id>"` in `Shared/SoundData.luau`): **BirdsDay,
CricketsNight, WindHowl, LavaRumble, Wings, Quack, StormCrackle, Engine**.
An id that fails to load is just silent (a warning in Output).

### Playtest checklist

**Start-up and the world**
- [ ] Output: `[MapBuilder] Terrain n/n` lines, then `World built in ...s`,
      with no errors from MapBuilder, TerrainBuilder, NPCService,
      ForestService or any controller (`[Client] X failed to start` means a
      controller died; paste it)
- [ ] You spawn on the cobbled pad at the town, standing on solid ground
      (nobody spawns into the void while the terrain is still building)
- [ ] Fly around (or drive): hills, the river from the Skyroot's
      waterfall to the lake, the beach and the island, the Snowfields up
      north, the Volcano north-east, the Phantom Grove's hollow south-west,
      mountains round the edge; roads reach each biome with a signpost
- [ ] Nothing floats or is buried: trees, boulders, signposts, the
      Skyroot's roots, buildings (the town is flat at y 0)
- [ ] The invisible walls at the world's edge stop you

**The town**
- [ ] From the spawn: the sawmill straight ahead with "SELL LOGS HERE" on
      the pad reading upright (if it's upside down: remove the
      `* ANG(0, PI, 0)` in `BuildingArt.SellPad`), the Tool Shed barn to
      the left, the Dealership to the right, Hearth & Home past the Tool
      Shed, the gondola station behind, Murph's camp by the spawn
- [ ] The sawmill's big blade spins; smoke rises from its smokestack and
      Hearth & Home's chimney; the campfire flickers
- [ ] Each shop: walk in through the front; **Browse** appears before the
      counter; the keeper (Tink, Dale, Hazel) stands behind the counter,
      not inside a wall
- [ ] Drive a truck from your parking slot onto the sell pad, and out to
      the Starter Forest and the Hills road: no lamp post, fence, bench or
      crate in the way (they collide on purpose)
- [ ] The Sky Bin (blue, with a cloud and a flume behind it) shows your
      own count, e.g. "SKY BIN 0/30"
- [ ] At night: lamps come on one by one from about 18:40, windows glow,
      some go dark after midnight; by day windows are blue glass

**Trees and chopping**
- [ ] Hold an axe and point at a tree: a cream outline on the one you'd
      chop (amber if your axe is too weak); out of reach (about 12 studs
      from the bark), no outline
- [ ] Each swing: a whoosh at once, then the thunk, wood chips and a
      wobble; the last hit: a creak, the tree falls away from you, the
      ground shakes a little, logs lie along where it fell, a stump stays
- [ ] Felled trees regrow after their wood's time (the stump goes, the
      tree grows up from it); a planted one regrows at once (below)
- [ ] Trees sway in the wind (harder in storms); a tree you're chopping
      doesn't

**Trucks** (Vehicles)
- [ ] Your Rustbucket is in your slot, wheels on the ground; **Drive**
      (E) seats you
- [ ] Two players: player 2 has no Drive prompt on your truck; if they
      sit in it anyway, they're put out with a toast
- [ ] Drive with WASD, a gamepad and a phone thumbstick: smooth, no
      rubber-banding (also with Studio's network latency turned up); the
      truck leans with the ground, up to about 30°
- [ ] Wheels roll and the front ones steer; dust behind on dirt, sand
      and snow (not grass); exhaust puffs with throttle (the Rustbucket
      smokes and coughs); headlights at night; taillights brighten when
      braking
- [ ] Get out at speed and on a slope: it brakes, parks upright on the
      ground within about 1.5 s, and you land beside the driver's door
- [ ] Load logs: they appear in the bed with pale ends (figured ones keep
      their coloured band); leave and rejoin: the same logs are back, and
      the bed count is right even when the truck is far away
- [ ] Every truck and trailer from the Dealership looks right and fits its
      slot; buying a trailer on the Scout ATV says it can't tow

**Townsfolk and axes**
- [ ] Murph stands in front of his campfire facing the spawn; his name
      tag shows; he breathes, blinks, turns his head to follow you and
      waves when you come close (if nobody ever moves, tell me: the
      animation needs a Studio check); his **Talk** prompt works
- [ ] After the tutorial, townsfolk greet you and say a line in a bubble
      now and then (with a soft click)
- [ ] Millie by the sell pad, Gus by the gondola, and the walkers (Rosa
      west of the plaza, Pip east, Old Bram by the street) don't block
      prompts or bump you; two clients see the walkers in about the same
      place
- [ ] `/giveaxe` each axe: each looks different, held near the foot of the
      haft, blade forward; the Inferno and Starfall axes glow and sparkle;
      a dropped axe lies flat and **Pick up** works

**Light, weather and wildlife** (Environment)
- [ ] Two clients show the same time of day; the sun moves smoothly
- [ ] A full day looks right: pink-gold dawn, clear midday, warm golden
      hour, purple dusk, dark-blue night where lamps stand out (tune
      `EnvironmentData.Keyframes` by eye)
- [ ] Walk into the Volcano (red haze) and the Phantom Grove at night
      (very dark violet): the light crossfades over about 3 s; on the
      isles: bright, low haze, a slight far blur
- [ ] Force `Rain`: rain streaks (if they look like blobs, see the env
      notes in `WeatherController`), the rain sound, a darker sky; `nil`
      fades it out
- [ ] Force `Storm` in the Starter Forest: a bolt every 20 to 50 s, never
      in town: a crackle ring first, then the bolt, a flash, thunder late
      with distance; a struck tree glows blue with sparks and a toast
- [ ] Storm on the Snowfields: blizzard; at the Volcano: ash and embers;
      on the isles: golden motes and wind; `Fog` at night: ground mist
- [ ] Clear night on the Snowfields: an aurora to the north
- [ ] Decoration round you: grass, flowers, ferns, bushes, rocks, berry
      bushes, fallen logs, snow piles at the Snowfields, lava rocks at the
      Volcano, glowing mushrooms in the grove, reeds and cattails by the
      water, lily pads on the lake and the pond; none on roads, in town or
      inside trunks; driving fast, it loads in without hitches
- [ ] Wildlife: a flock overhead that scatters when you walk under it,
      songbirds that fly off when you come close, butterflies, rabbits and
      deer that bound away, ducks on the pond (78, -182), fish leaping;
      at night fireflies, wisps in the grove, ember sprites at the Volcano
- [ ] Sound: music crossfades at dusk and dawn; the river follows the
      nearest water; the waterfall roars near the Skyroot
- [ ] ♪ (left of the cash) > Music OFF fades the music out, SOUND FX OFF
      silences effects; both stay that way after rejoining

**The Living Forest**
- [ ] Workspace attributes on start: `Vitality_starter` = 60 and
      `VitalityTier_starter` = "Healthy" (also hills, snow, volcano, grove)
- [ ] About 1 tree in 16 wears a bark clue (wavy pale strips = curly, dark
      eyes = birdseye, scaly plates = quilted, a knobbly lump at the foot =
      burl); clicking the clue still chops the tree
- [ ] Fell a tree: a glowing Heartseed arcs into you with a pop and the
      pouch chip left of the Daily Goals button counts it (first time: a
      toast)
- [ ] Tutorial: after your first sale Murph asks you to plant a Heartseed;
      the beacon points at the nearest stump you have a seed for;
      **Plant Heartseed (1)** (F / Y) grows a sapling for 8 s, then the
      tree springs up with your name on a stake
- [ ] Can't plant without a seed of that wood, twice on a sprouting stump,
      from far away, or in an Elder's stump
- [ ] Two players: A plants, B fells it: A gets "Your oak was harvested by
      B: +$..." ; A felling their own planted tree gets an extra seed
- [ ] Figured logs carry a coloured band (in hand, on the ground and in the
      truck bed); selling them shows a stamp ("BURL x4!") and pays more;
      the Field Guide's Hidden Grain page counts them
- [ ] `WakeElder("starter")`: a giant oak on open ground with a glowing
      ring and a light pillar, a server-wide toast and a marker from town;
      felled by two players: both get paid and 2 seeds, its logs are free
      to grab; left alone it fades after 15 min
- [ ] Replant until a grove reaches Thriving (75+): entering it says "a
      thriving grove: more figured wood"; more flowers and wildlife there
- [ ] Every grove at 80+: the Skyroot blooms with golden motes and a toast
- [ ] Daily goals can include "Plant N Heartseeds" and "Sell N figured logs"

**The Skyroot and the isles**
- [ ] From town the Skyroot reads as a giant tree with the isles in its
      crown and the waterfall pouring off one; at night its canopy and
      vines glow
- [ ] Ride the gondola from town and from the Skyroot's foot: the cabin
      never clips a root, limb, leaf or station roof
- [ ] On the isles: tops are flat and solid to the rim; bridges walkable
      with lanterns at each end; the Cloud Chute's flume runs off the edge;
      figured logs go down the chute too and sell at their worth from the
      Sky Bin
- [ ] Featherfall Cloak: step off an isle: it opens about 15 studs down,
      you drift down at a steady speed and can steer, and it closes when
      you land; without it, the logs in your hands are lost to the clouds
- [ ] Reset (respawn) while on the isles: no "You fell!" toast in town
- [ ] The Starfall Forge refuses with "You own 20 axes" when you're at the
      axe limit, before taking anything

**Feel, UI and money**
- [ ] Sell a load: the cash counts up, "+$..." floats left of the plaque,
      the paper flashes green; buying shows "-$..." in ink
- [ ] Top right on a phone and at 1080p: Store, clock, ♪ and the cash
      plaque in a row with no overlaps, even at $1,999,999; the Daily Goals
      button and the Heartseed pouch in the row below don't overlap; the
      Settings card, the goals panel and the pouch list open one at a time
      under that row; side buttons spill into a second column instead of
      climbing over the Daily button; a shop's X is clear of the cash
- [ ] Two logs in hand: drop one by selling the other, pick up again: the
      new log never sits inside the old one
- [ ] Lava doesn't burn you inside a truck or mid-jump
- [ ] A Robux cash pack near the wallet cap (test purchase): the part
      that fits arrives now, the rest says it's saved and arrives as you
      spend
- [ ] Mined Sky Shard crystals vanish with their glow and grow back

**Performance** (Studio's device emulator, phone size, MicroProfiler)
- [ ] Town at night with every lamp lit, the lot full of trucks: smooth
- [ ] AmbientLife + WindSway under about 1 ms a frame; NPCController well
      under 0.5 ms (if decoration is heavy: lower `MAX_DECOR` in
      AmbientLife or `EnvironmentData.DecorCandidates`)
- [ ] The Skyroot, isles and cloud banks in view: still smooth

### After the review (October 2026): fixes to check

A review of the merged redesign found about 30 problems; all are fixed.
These checks cover the ones that change what you see or do:

**Hauling**
- [ ] Fill the bed in the Hills, walk 40+ studs away, **Truck to lot**:
      the first press warns that the load will be left; press again within
      6 s: the truck is back in your slot empty, the logs lie where it
      stood (figured ones keep their band and value), with a toast; they
      stay yours for 10 minutes, and if you leave before collecting them
      they're saved and back where they lay when you rejoin
- [ ] Loaded at the sell pad or the Dealership: Truck to lot or switching
      trucks keeps the load
- [ ] Leave with a loaded truck in a far biome and rejoin: truck empty in
      the lot, the logs waiting at the old spot (once, not twice); leave
      loaded in the lot and rejoin: the load is back in the bed
- [ ] Two players: park in the other's slot, they press Truck to lot: your
      truck goes back to your own slot (with a toast), theirs isn't built
      inside it
- [ ] Hop out across a dip or a slope (Flatbed + trailer): it stays where
      it rests, nothing sunk in; hop out mid-air off a ledge: it lands first
- [ ] Out of the truck on the sell pad with logs: the prompt says **Sell**,
      not Drive; Drive comes back after selling or off the pad
- [ ] Instant Delivery with cash near $2,000,000: refused with a toast,
      and no use is spent
- [ ] Normal driving: no rubber-banding (a network stall over 2 s puts the
      truck back to its last good spot: tell me if that happens in normal
      play); selling from the truck at the pad works

**Trees and the Living Forest**
- [ ] Two players on one oak: A chops it to 1 HP, B lands the last hit: A
      gets the logs' window, the Heartseed and the tutorial/daily credit
- [ ] Plant your own oak and refell it at once: a seed back but no
      steward's bonus, and the grove's vitality drops back; after 10 minutes
      standing, the bonus returns
- [ ] Plant a Lumenwood stump: the toast says about 8 minutes and a sapling
      stands on the stump the whole time, for anyone who comes by; no plant
      prompt on it meanwhile
- [ ] A tree that grows back (or a Phantom tree at dusk) where a truck is
      parked: it appears, the truck isn't flung, you can drive off, and the
      trunk turns solid within about 2 s
- [ ] By day in the Phantom Grove: no invisible stumps to bump into; a
      phantomwood felled seconds before dawn leaves no visible stump
- [ ] `WakeElder("grove")` at night, then let dawn come: the Elder, its
      aura and marker fade together and another grove can wake one
- [ ] Fell a tree uphill on a steep slope: its logs lie on the surface
- [ ] Fell a storm-struck tree in the glow's last second: still Stormgrain

**The world**
- [ ] Drive west from the lot along the Hills road and east along the Plot
      road: nothing in the lane (Murph's camp now sits beside the TO THE
      WOODS sign, Murph facing the spawn; his Talk prompt works)
- [ ] Sign text (sawmill crest, shop titles, signposts, SKY BIN, plot
      signs) reads unstretched
- [ ] Wade into the lake, the river and the pond: no air pockets under the
      water; water reaches the shallow edges (a place saved with
      `Workspace.Terrain` attribute `Prebuilt = true` keeps its old terrain:
      clear it to rebuild)
- [ ] From the volcano's rim: a level glowing pool fills the crater floor
- [ ] The four biome road signs: both posts on the ground, clear of the
      road; no boulders floating on mountainsides
- [ ] Gondola up from town and from the Skyroot's foot, and back down: the
      cabin leaves through the station's open back and comes in level over
      the isle's rim, no clipping; still about 40 s a ride

**Screens**
- [ ] Tutorial "Sell logs at the sawmill": the arrow sits over the sell pad
- [ ] Finishing the tutorial: FIELD GUIDE at the top left with Murph's
      farewell card under it (not covering it)
- [ ] Phone (iPhone 14 landscape and SE): Murph's card lets a thumb move
      you; all four side buttons (on your plot, axe out, truck far away,
      Instant Deliveries) fit above the jump button in two columns
- [ ] Phone, Tool Shed: the panel sits left of the cash; its X shows and
      closes it
- [ ] Open the daily goals (or Settings, or the Heartseed pouch) with side
      buttons showing: the side buttons go away while it's open and come
      back when it closes; tapping the open panel never presses anything
      under it
- [ ] Build mode on a small phone with three side buttons: none covers the
      BUILD MODE bar's buttons
- [ ] Lightning and a nearby tree falling: the rumble plays out in full
- [ ] Shift-lock or first person near a falling tree: after the shake the
      view points where it did
- [ ] Aether Isles: the next isle sharp, the ground far below a little soft

## Axe shop (GAME_DESIGN §8 phase 2)

The **Tool Shed** stands west of the sawmill (left of it as you walk up
from spawn). At the counter, **Browse axes** opens the shop screen:

- Every axe on the ladder, with its damage and the toughest woods it fells
  (the Steel Axe: "Fells oak in 3 · birch in 5 · pine in 13").
- The next axe has a **Buy** button (green when you can afford it). Axes
  you own can be bought again, for a collection. Later axes say **Locked**
  until you buy the one before; the Starfall Axe says **Forged**.
- Buying takes the cash, puts the axe in your hotbar and in your hand.
- Walking away (or the X, or B on a gamepad) closes the screen.

The server checks everything again: that you're at the counter, that the
axe is next in line, and your cash. You can own at most
`GameConfig.MaxOwnedAxes` (20) axes.

### Playtest checklist
- [ ] The Tool Shed is west of the sawmill; **Browse axes** shows at the counter
- [ ] The screen lists all 9 axes; Rusty says Starter, Steel has a price,
      Hardened and later say Locked, Starfall says Forged
- [ ] With less than $150, clicking Steel's price says how much more you need
- [ ] With $150+: the button turns green; buying takes $150, and the Steel
      Axe is in your hand and hotbar; oak now falls in 3 hits
- [ ] Steel's row now says "you own 1"; the Hardened Axe is buyable next
- [ ] Buy a second Steel Axe: two in the hotbar, "you own 2"
- [ ] Walk away: the screen closes; the prompt comes back when you return
- [ ] Leave + rejoin: bought axes are still there (needs API access)
- [ ] `/giveaxe gold` (Studio test axe) does **not** unlock Cobalt in the shop
- [ ] Toasts show on top of the shop screen
- [ ] Phone (device emulator): the screen fits and scrolls; buttons are tappable
- [ ] `[Stopwatch] … First upgrade bought at …` prints after the first buy

## Murph's tutorial (GAME_DESIGN §11)

**Murph** (big beard, red flannel, beanie) stands just ahead of the spawn.
New players get one objective at a time in a tracker on the left,
with Murph's line under it and an amber arrow over what to do next:

1. Chop down a tree (arrow on the nearest tree)
2. Pick up a log (nearest log)
3. Load logs into your truck (your truck)
4. Sell logs at the sawmill (the sell pad)
5. Sell 18 more logs: Murph chips in **$25**
6. Buy the Steel Axe at the Tool Shed (the Tool Shed counter)

**Skip tutorial** (tap twice) ends it; **Talk** at Murph repeats his line.
Progress is saved, so a rejoin carries on where you left off. Saves from
before the tutorial that already own a better axe skip it.

Balance note: with the $25, the model has players affording the Steel Axe
at ~9 min (design target 12–15). Connor chose to keep the bonus
(2026-09-30); ECONOMY.md flags those two early rows, and that's expected.

### Playtest checklist
- [ ] New save (or reset: see below): the tracker shows step 1 of 6, Murph's
      line appears, the arrow bounces over a nearby tree
- [ ] Each step advances the moment you do it; the arrow moves to the next thing
- [ ] Step 5 counts logs as you sell ("(6/18)"), then "Murph chipped in $25!"
- [ ] Buying the Steel Axe ends it: the tracker goes, Murph says goodbye
- [ ] Rejoin mid-tutorial: same step and progress
- [ ] Skip (tap twice): the tracker goes and doesn't come back after rejoining
- [ ] **Talk** at Murph repeats his current line
- [ ] The tracker sits on the left, below the chat window; on a phone it
      stays clear of the thumbstick (Murph's card may dip toward it: tap
      the card to dismiss)
- [ ] `[Stopwatch] … Finished the tutorial at …` prints at the end

To see the tutorial again with an old save: with API access off (or a new
test account), progress starts fresh each Play session.

## Screen layout

- **Cash, top right**, with the Daily Goals button under it, the clock and
  STORE to its left.
- **Tutorial tracker, left**: high up on a phone (its chat is a button), a
  third of the way down on a computer, under Roblox's chat window.
- **Side buttons, right**: BUILD (on your own plot), Sell here (Instant
  Delivery), Drop axe, Truck to lot, stacked so the bottom one always ends
  above a phone's jump button.
- **Toasts, top centre**, newest on top. **Control hint, bottom centre.**
- Roblox's own **player list is off** (it opens top right on computers,
  over the cash) until the game has its own leaderboard. Turn it back on
  with `ShowRobloxPlayerList = true` in `GameConfig.luau`.

### Playtest checklist
- [ ] Cash shows top right on a computer and on a phone, clear of Roblox's
      menu buttons; no Roblox player list covering it
- [ ] The tutorial tracker is on the left and doesn't cover the chat

## Trucks: Dealership and physics driving (GAME_DESIGN §8 phase 4)

- **Every truck is real now:** Rustbucket, Pickup, Scout ATV, Flatbed and
  Logging Rig, each its own size and colour, built from ItemCatalog. Beds
  fill with visible logs. Bigger beds drive slower (top speeds 24 to 40).
- **Dealership** east of the sawmill (opposite the Tool Shed): **Browse
  trucks** lists every truck with its bed and top speed. Buy one and it
  replaces your truck in your parking spot, load and all if it fits (and
  if the truck is in town: see the redesign's "Truck to lot"). Trucks
  you own show **Use** to switch back. The Scout ATV has no bed.
- **Physics driving:** trucks collide with trees and buildings instead of
  gliding through them. Your device drives your truck (smooth, no lag);
  the server checks it never goes faster than it can. Getting out parks it
  where it is. Set `VehiclePhysics = false` in `GameConfig.luau` to get
  the Phase 1 arcade driving back if physics misbehaves.
- **Truck to lot:** a button (right edge) when your truck is far away:
  it goes back to your parking spot. 10 s cooldown. Since the redesign
  the load comes along only from within 150 studs of town; from farther
  out it's left on the ground where the truck stood (yours for 10
  minutes), so the drive home can't be skipped.
- The parking lot is bigger (slots fit the Logging Rig).

### Playtest checklist
- [ ] The Rustbucket spawns on its slot with its wheels on the ground, not
      floating or sunk
- [ ] Drive with WASD / arrows: it speeds up, turns, reverses, stops when you
      let go. It bumps into trees and walls instead of passing through
- [ ] Hop out while rolling: it stops where it is and stays put; nobody can
      push it around
- [ ] Load logs at the tailgate; they show in the bed; sell at the mill
- [ ] Dealership: **Browse trucks** shows 5 trucks; the Rustbucket says
      **In use**; buying the Pickup ($1,200) takes the cash and the Pickup
      appears in your spot; the Rustbucket now says **Use**
- [ ] Switch with logs in the bed (truck parked in town): the load moves
      over (if it fits)
- [ ] Walk far from your truck: **Truck to lot** appears; press it: the truck
      is back in your spot (its load stays where it stood if that was out of
      town); pressing again right away says to wait
- [ ] Phone (device emulator): drive with the thumbstick; the Truck to lot
      button doesn't cover the jump button
- [ ] A second player (Test → 2 players) sees your truck move smoothly, but
      can't drive it: trucks are owner-only since the redesign
- [ ] Output has no `[AntiExploit] … truck moved` warnings during normal driving
      (if it does, tell Claude: the speed check is too strict)
- [ ] If physics driving feels bad: set `VehiclePhysics = false` and report
      what went wrong

Numbers to tune after this playtest (all in `GameConfig.luau` /
`ItemCatalog.luau`): `VehicleAccel` 14, `VehicleBrake` 40, `VehicleCoast` 8,
each truck's `topSpeed` and `turnRate`.

## Daily goals and streaks (GAME_DESIGN §12)

A **DAILY GOALS 0/3** button sits under your cash, top right. Tap it for
today's three goals, e.g. "Fell 4 trees", "Sell 12 logs", "Sell 6 birch logs", "Earn
$60 selling logs", "Load 12 logs into your truck", with progress bars and
rewards. Each goal pays when done; all three pay a bonus that grows with
your **streak** (days in a row, up to 2x at 5 days). Goals are sized to
your best axe, reset at midnight UTC (the panel counts down), and a missed
day resets the streak.

### Playtest checklist
- [ ] The button shows under the cash with "0/3"; tapping opens the goals
- [ ] Felling, loading and selling move the right bars; a finished goal
      toasts "Daily goal done … +$15" and turns green
- [ ] Finishing all three: "All daily goals done! +$30. Streak: 1 day."; the
      button turns green and shows the streak
- [ ] Rejoin the same day: same goals, same progress
- [ ] "New goals in …" counts down to midnight UTC
- [ ] Phone: the button and panel fit under the cash and close with a tap

To test a new day without waiting: temporarily change `SecondsPerDay` in
`DailyData.luau` to `300` (a "day" every 5 minutes), then set it back to
`86400`.

## The world: biomes, day and night, Hearth & Home (GAME_DESIGN §8 phase 5)

The world is now 3,000 studs across, with every biome on the way to V1.
Roads and signposts lead out from town (a signpost by the spawn lists
them all):

| Biome | Where | Woods | Rule |
|---|---|---|---|
| Starter Forest | south of spawn | oak, birch | none |
| The Hills | west, ~400 studs | pine, maple | none |
| Snowfields | far north, ~1,200 | frostwood | you walk 15% slower without an **Insulated Coat** |
| The Volcano | far north-east, ~1,600 | emberwood | the ground burns without **Heat Boots**, and you can't chop there |
| Phantom Grove | hidden south-west, no road | phantomwood | trees only at night; you need a **Lantern** to chop |

- **Hearth & Home** (west of the Tool Shed) sells the gear: Lantern $150,
  Insulated Coat $500, Heat Boots $800. The Featherfall Cloak says **Soon**
  until the Aether Isles exist.
- **Day and night:** a full day is 20 minutes, the same on every server;
  night runs 19:00 to 05:00 (about 8 minutes). The clock is next to the
  cash. A Lantern glows on you at night.
- Everything is placeholder art (coloured ground, simple mounds, a stepped
  volcano cone) until the Studio art pass.

### Playtest checklist
- [ ] The signpost by the spawn lists the Hills, Snowfields and Volcano
- [ ] Follow each road: it ends at its biome, with a sign naming the woods
      and the gear to bring; entering shows a toast
- [ ] The Hills: pine and maple trees; the Steel Axe fells pine in 13 hits
- [ ] Snowfields: noticeably slower walking; buy the Insulated Coat: normal speed
- [ ] The Volcano: you take damage and "The ground is scorching!"; chopping
      says you need Heat Boots; with Heat Boots neither happens
- [ ] Phantom Grove (about 800 studs south-west of the sawmill, no road): by
      day, no trees and a toast saying so; at night, trees; chopping needs a Lantern
- [ ] The clock shows Day/Night; the sky darkens at night; the Lantern glows
- [ ] Hearth & Home: buy each piece once; buying again says you have it
- [ ] Driving all the way to the Volcano: no falling through the ground, no
      `[AntiExploit]` warnings; the world edge stops you
- [ ] The far biomes stream in as you drive (no empty void on arrival)

Quick night test: set `DayCycleMinutes = 2` in `GameConfig.luau` (a day
every 2 minutes), then set it back to `20`.

## Trailers

The Dealership now lists the three trailers under the trucks: Pony Trailer
(+6, $600), Ranch Trailer (+12, $3,000), Heavy Hauler (+24, $12,000).
Buying one hitches it behind your truck; **Hitch** / **Unhitch** swap them.
The truck bed fills first, then the trailer; the **Load logs** prompt moves
to the back of the trailer. The Scout ATV can't tow. For V1 the trailer is
fixed to the truck (the whole rig turns as one), which is simple and hard
to break; a swinging hitch can come later. Parking slots are now 37 studs
long (two rows of 12) to fit a Logging Rig with a Heavy Hauler.

### Playtest checklist
- [ ] Buy the Pony Trailer: it appears behind your truck in your spot
- [ ] Bed shows 6 + 6 = 12; logs fill the truck bed, then the trailer
- [ ] **Load logs** shows at the back of the trailer; loading works from there
- [ ] Driving and turning with a trailer feels OK (tight turns swing the back out)
- [ ] Sell the whole load (truck + trailer) at the mill
- [ ] Unhitch with logs in the trailer: refused ("Sell your load first")
- [ ] Switch trucks at the Dealership: the trailer comes along; on the Scout ATV
      it doesn't (and hitching says the ATV can't tow)
- [ ] Parked rigs never overlap their neighbours in the lot

## Robux: the Store

A **STORE** button (next to the clock) opens the Robux Store once at least
one item is set up. Items (GAME_DESIGN §7; starting prices there):

| Item | Kind | What it does |
|---|---|---|
| 2x Cash | game pass | every log sells for double, forever |
| $1,000 / $10,000 | developer products | cash, only offered if it fits under the $2,000,000 cap |
| 2x Wood (48 hours) | developer product | felled trees drop twice the logs; buying again extends it |
| Instant Delivery | developer product | a "Sell load here" button sells your truck bed from anywhere, once |

Purchases are granted exactly once and saved before Roblox is told, so a
server crash can't lose one or pay it twice.

### Setting the items up (Connor, in Creator Hub)
1. Publish the place (File → Publish to Roblox) if it isn't already.
2. Creator Hub → Creations → Timberline Tycoon → **Monetization → Passes** →
   Create a Pass: "2x Cash", an icon, then set it on sale at your price.
   Copy its **ID**.
3. **Monetization → Developer Products** → Create: "$1,000", "$10,000",
   "2x Wood (48 hours)", "Instant Delivery", each with a price. Copy each ID.
4. Paste the IDs into `src/ReplicatedStorage/Shared/StoreData.luau` (the
   `id = 0` lines), or send them to Claude.

### Playtest checklist (Studio purchases are free test purchases)
- [ ] With the IDs in, the STORE button shows; the Store lists each item with
      its Robux price
- [ ] Buy $1,000: the Roblox prompt, then +$1,000 and a thank-you toast
- [ ] With over $1,990,000 (set `cash` in Studio or lower `CashCap` for a
      test), the $10,000 pack says "Wallet full" and never prompts
- [ ] Buy 2x Wood: felled trees drop double logs; the Store shows the hours left
- [ ] Buy Instant Delivery with logs in the truck: "Sell load here (1)" appears;
      pressing it sells the bed anywhere
- [ ] Buy 2x Cash: sales pay double; the Store says Owned; rejoin: still owned
- [ ] Leave during a purchase and rejoin: it's granted (once)

## The Field Guide

When the tutorial ends (or is skipped), Murph hands over the **Field
Guide**: a button on the left. It lists all nine woods. Ones you haven't
felled are "???" with a hint of where to look ("Grows in Snowfields",
"Somewhere hidden, and only at night"). Fell one and its page fills in:
biome, HP, hardness, logs and price, and which axe cuts it ("Rusty Axe: 100
hits; Steel Axe: 13"). Each new wood toasts "New in your Field Guide".

### Playtest checklist
- [ ] No Field Guide button during the tutorial; it appears when it ends
- [ ] Oak and birch show as found if you felled them in the tutorial
- [ ] Felling a first pine: toast "New in your Field Guide: Pine! (3 of 9)";
      its page fills in
- [ ] Undiscovered woods never show their price

## The Aether Isles (the V1 finale)

The **Skyroot**, a colossal tree in the far north-west corner, is visible
from everywhere; the isles float above it. How it works:

- **Getting up:** the **Skyroot Gondola** leaves from a station behind the
  Tool Shed (north-west of the sawmill), $250 a ride, about 40 seconds up
  the cable. There's a second station at the Skyroot's foot. From the top,
  "Ride down" goes back to town.
- **Lumenwood:** 12 glowing trees on the three outer isles, joined to the
  main isle by rope bridges. Only the Inferno Axe dents it (67 hits); the
  Starfall Axe fells it in 12.
- **Sky Shards:** blue crystals on the isles. Any axe mines one in 12 swings
  (+1 Sky Shard); they grow back after 10 minutes.
- **Cloud Chute:** one on each outer isle. "Send logs down" puts the logs in
  your hands into your **Sky Bin**, the crate by the sawmill's sell pad
  (holds 30; it shows your count). Selling on the pad sells the bin too.
- **Falling off** loses the logs in your hands, unless you wear the
  **Featherfall Cloak** (Hearth & Home, $2,500): then you glide down.
- **The Starfall Forge** (main isle): "Add lumenwood" puts carried Lumenwood
  in (40 needed); "Forge the Starfall Axe" (hold) takes $60,000 and 12 Sky
  Shards and puts the axe in your hand. It says what's still missing.

### Playtest checklist
- [ ] The Skyroot is visible from town and from the far biomes
- [ ] Gondola from town: $250 taken, a ~40 s ride, you land on the main isle
- [ ] Jump out mid-ride: you fall (no refund); the ride ends cleanly
- [ ] Lumenwood: the Inferno Axe works (slowly); weaker axes say it's too hard
- [ ] Mine a Sky Shard: HP bar, +1 toast; it vanishes and comes back later
- [ ] Cloud Chute: logs leave your hands; back in town the Sky Bin shows the
      count; selling on the pad pays for them
- [ ] Fall off without the cloak: logs in hand are lost; with it: a slow glide
- [ ] Forge: adding lumenwood shows progress; forging with everything takes
      the cash and shards and hands you the Starfall Axe
- [ ] Ride down: back at the town station
- [ ] Performance on a phone while riding the gondola (streaming the map)

Quick test with a Studio test axe: `/giveaxe inferno` or `/giveaxe starfall`.

## Plots (V1_PLAN §6, first slices)

The **plot district** is east of the parking lot: 12 plots, 3 columns by
4 rows (one per player on a full server). The north road stays on the
town's mouth. Lanes between the pads are wide enough for a Logging Rig,
with grass either side, and a road runs along the south edge out toward
the forest. Each pad is marked with rails and corner posts even before
anyone claims it. A sign at the north edge, off the driveway, reads
PLOT n / FREE, or the tier and your name once it's yours. A 13th player
is told the district is full and keeps their save until a plot frees.

- **Claiming:** walk to a free plot's sign, "Claim this plot" (hold). It's
  free, and you keep it: each time you join, your saved layout is rebuilt
  on whichever plot is free (the sign says "FREE PLOT" until someone
  claims it; plots are plot-local, so nothing is lost if you get a
  different one).
- **Building:** on your plot a **BUILD** button shows (right side). It opens
  the **Blueprint Store** and turns on build mode (a bar with BLUEPRINTS
  and DONE at the bottom). Pick a blueprint and a see-through ghost follows
  your mouse (the last spot you tapped on a phone; the middle of the screen
  on a gamepad), green where it fits and red with the reason where it
  doesn't. Click or PLACE to build it (you pay then); R or ROTATE turns it;
  Q or CANCEL stops. You keep placing the same thing until you cancel, so
  fences are quick.
- **Moving and selling:** in build mode, walk up to anything you placed:
  **Move** (E) picks it up as a ghost to put somewhere else (free); **Sell**
  (F, hold) pays back half the price, or all of it within a minute of
  placing it.
- **Growing:** the store's top row grows the plot to the next base tier:
  Homestead (140 × 140, $2,500), Lumber Yard (160, $10,000), Timber Works
  (180, $30,000), Timber Empire (200, $60,000). The Warehouse and Axe Rack
  need a Homestead. **These prices are a first pass for you to tune**
  (`PlotData.luau`); tier-ups will also cost Stone and planks once those
  exist.
- **What's there:** Fence, Flower Bed, Bench, Lamp Post (lights up), Log
  Pile, Flag, Cabin, and (Homestead) the Warehouse and Axe Rack. They're
  looks for now; the Warehouse storing logs and the Axe Rack showing axes
  come in the next slice.

### Playtest checklist
- [ ] The plot district is east of the parking lot, with roads and a
      "PLOT DISTRICT" sign; the old plot markers by town are gone
- [ ] Claim a plot: the sign reads PLOT n, CAMPSITE and your name; rails
      and corner posts mark the edge (they're there on free plots too);
      claiming a second one says you already have one
- [ ] BUILD shows only on your plot; walking off ends build mode
- [ ] Place a fence: the ghost snaps, turns with R, goes red over another
      fence or past the edge (with the reason), green where it fits;
      placing takes the price
- [ ] Place several fences in a row without reopening the store
- [ ] Move something: it hides, the ghost takes its place, and it lands
      where you put it (no charge)
- [ ] Sell something right after placing it (full refund), and again after
      a minute (half)
- [ ] Grow to a Homestead: the pad and sign grow, the Warehouse unlocks
- [ ] Leave and rejoin: the plot and everything on it come back (maybe on a
      different plot)
- [ ] Two players: each sees the other's build; nobody gets Move or Sell
      prompts on someone else's things
- [ ] On a phone: tap to aim, PLACE / ROTATE / CANCEL work, prompts are
      reachable
- [ ] Lamp posts glow at night
- [ ] Drive a Logging Rig down a lane between two Timber Empire pads and
      out the south road; the claim sign is not sitting in the north road
- [ ] A full server (or a 13th Studio player): the extra player gets a
      toast that the district is full, and a plot when someone leaves

## Save slots (three per account)

**SAVES** on the right opens three cards. Each shows cash, the best axe,
and when it was last played. The one you're in has **REDO**; the others
have **LOAD** or **START**. Redo asks you to confirm. After a load or a
redo, saves are locked for 2 minutes (the lock is in the save, so leaving
and rejoining doesn't clear it). Wood in the world is put into the slot
you're leaving before the other one loads, so it can't be in both.

Robux stays on the account, not the slot: 2x Cash, 2x Wood, Instant
Delivery charges, cash-pack receipts, and the Lux Axe. An old single save
loads as slot 1; slots 2 and 3 start empty.

### Playtest checklist
- [ ] An existing Studio save opens as slot 1 with the same cash, axe,
      plot and truck wood; slots 2 and 3 say New game
- [ ] START slot 2: your plot is empty, cash is $0, you have a Rusty Axe,
      and slot 1 still has what you left (including logs that were on the
      ground)
- [ ] LOAD slot 1: the money and the build come back. A second load inside
      2 minutes is refused, and a log you drop in that window is not copied
      onto the other slot
- [ ] REDO, then confirm: the current slot is a fresh game. Cancel does
      nothing. The Lux Axe, if you own it, is still in your inventory
- [ ] Buy a cash pack or spend an Instant Delivery on one slot, switch
      slots, and it is not granted again

## The new look (Claude Design UI spec)

Every screen is rebuilt from the UI spec you made in Claude Design
(colours, sizes and states are in `UITheme.luau`; each screen builds from
it):

- **Cash plaque:** kraft paper in a bark frame with an ink edge; at the
  $2,000,000 cap it turns amber and reads **MAX**.
- **Toasts:** paper pills at the top, newest on top, older ones fading
  back; money shows in green.
- **Control hint:** one short line for the device in use ("Tap a tree to
  swing your axe", "Click a tree to swing · E to interact", "RT to swing ·
  X to interact"); it switches when you pick up a gamepad.
- **Side buttons:** chunky buttons that press down onto their edge. On a
  gamepad each shows its glyph: X drops your axe, Y calls your truck (only
  when no world prompt is using that button, so X near a shop still opens
  the shop).
- **Shops** (Tool Shed, Dealership, Hearth & Home, Field Guide, Blueprint
  Store, Robux Store): the screen dims behind a wood-framed paper panel;
  tapping outside it closes it, and you can't walk while it's open. Rows
  have a round swatch (the Inferno and Starfall axes glow), the name with
  "· you own 2", two lines of detail, and a button in one of the spec's
  states (Buy, can't afford, Starter, Locked, Forged, Full, Use, In use).
  On a gamepad the first Buy button is selected, with an amber ring.
- **Tutorial:** the kraft tracker card with an amber "Tap again to skip"
  confirm; Murph's wood card has his portrait (a live view of the Murph by
  the spawn) and fades away when tapped.
- **Beacon:** an amber arrow with an ink rim and a distance pill, bobbing
  over the target; it hides once you're there.
- **World prompts:** the spec's wood cards with a key cap that fills amber
  while you hold, TAP on a phone, the pad's glyph on a gamepad. If any
  prompt misbehaves, `CustomPrompts = false` in `GameConfig.luau` brings
  back Roblox's default ones.
- **Scaling:** 1x on phones, about 1.25x on a 1080p monitor, 1.5x on a TV,
  with the TV-safe margin on consoles.

Where it differs from the spec, and why:
- The cash stays **top right** (you asked for that); the spec drew it top
  left.
- On a computer the tracker sits lower than the spec's y 96, to clear
  Roblox's chat window.
- **No wood grain or paper fibre yet:** those are tiled images. Upload them
  and put the ids in `UITheme.Textures` (Wood, Kraft) and every surface
  picks them up; until then the surfaces are flat colour.
- Drop shadows are drawn as solid edges, and the beacon's triangle is a
  text arrow (no image needed).
- The icon and thumbnail layouts (6a/6b, 7a/7b) need Studio renders; they
  aren't in the game itself.

### Playtest checklist
- [ ] Phone (Studio's device emulator, e.g. iPhone 14 landscape): cash,
      tracker and side buttons clear of the thumbstick, the jump button
      and Roblox's top bar; nothing overlaps
- [ ] Computer at 1080p: everything a little bigger (1.25x), still in the
      right places; at a small window size, still 1x
- [ ] Toasts: three at once, the newest on top; "$18" shows in green;
      they fade after 3 seconds
- [ ] Wallet at the cap (quick test: set `CashCap = 100` in
      `GameConfig.luau` for one Play, then sell a load): the plaque turns
      amber and says MAX
- [ ] Buttons press down when held, and brighten under the mouse
- [ ] A shop: the screen dims, the panel fits on a phone (the list
      scrolls), tapping the dim area closes it, WASD doesn't walk while
      it's open, B on a gamepad closes it
- [ ] Gamepad in a shop: the first Buy button has the amber ring; the
      D-pad moves between buttons; A buys
- [ ] Tool Shed rows: Starter (outlined), Full, Buy, the grey price you
      can't afford yet, Locked; the Inferno and Starfall swatches glow
- [ ] Tutorial: Skip turns amber and says "Tap again to skip", then goes
      back after 3 seconds; Murph's portrait shows his face; tapping his
      card fades it
- [ ] Beacon: bobs over the tree / log / truck / sell pad with the
      distance; disappears when you're next to it
- [ ] World prompts: key cap with E; holding fills it amber; on a phone the
      card says TAP and tapping it works (Pick up, Load, Drive); on a plot
      in build mode, Move and Sell stack instead of overlapping
- [ ] Gamepad: X drops the axe away from prompts, but next to a shop X
      opens the shop instead; Y calls the truck

## W3: the toll, the ferry, the blasting charge (Studio checks)
- [ ] Toll: walk to Old Tolly's booth (east of the bridge, z 1566). The prompt reads "Pay toll ($100)" (E, gamepad X, tap on a phone). Pay, cross within 3 minutes: you stay north. A second tap says you are paid up and charges nothing. With under $100 the toast is "The toll costs $100." Crossing unpaid pushes you back with Old Tolly's toast. A driver who pays carries the truck and any passenger across.
- [ ] Ferry: at the dock (1180, -700) the prompt reads "Board ($400)" and its object line counts down. Board: you stand on the boat; nothing is charged until it casts off, then $400 per rider on deck; step off first and you pay nothing. Riders and loose planks ride welded to the deck and are set down on the island dock. A truck on the deck is put back on the dock. The island dock boards the return trip.
- [ ] Boulders (Gloam Hollow back way, three of them): the prompt is a 1 second hold, "Set a blasting charge ($220)". Fuse 5 seconds, then a harmless blast and the boulder goes. It returns after 20 minutes, never onto a player or a truck (it waits 10 seconds and tries again).
- [ ] Gondola: with a truck seat you get "Hop out of your seat first".
- [ ] Nothing here takes Robux. The badges (Ferry Island, North Strip) stay at id 0 until you paste the ids in BadgeData.Ids.

## Furniture and wiring (B09, B11)

New pieces, all cash only (no gathered materials): `Shared/DecorData` (Table
$90, Chair $50, Bookshelf $140, Rug $60, Barrel $70, Crate $60, Fire Pit
$110) and `Shared/LogicItems` (Wall Switch $100, Spark Lamp $150). Table,
Chair and the two logic pieces are `unlock` boxes at Hearth & Home (buy once,
place free). The shelf holds 14 boxes and is now full: more `unlock` pieces
need a longer shelf (StoreStock layout and BuildingArt). The rest are paid
per placement from BUILD, like the Bench.

Wiring (`Shared/WireLogic`, `SSS/LogicService`, saved in `plot.wires`): a
switch has Flip (E / ButtonX) and Wire (hold F / ButtonY). Wire links the
nearest free Spark Lamp or Door within 32 studs; press again for the next;
with none left it clears that switch. A lamp nobody wired stays lit. A wired
lamp or door follows its switches (any on). Switch positions are not saved.
The Wire remote carries (fromUid, 1, toUid, 1) or ("cut", uid) for a future
tool; there is no client wiring UI yet and no drawn wire.

Studio checks
1. Hearth & Home: 14 boxes, none off the shelf, Table / Chair / Wall Switch /
   Spark Lamp among them. Buy a Wall Switch, open its box on your plot.
2. BUILD menu: Bookshelf, Rug, Barrel, Crate, Fire Pit appear, price on the
   card. Place on phone (tap), PC (click), Xbox (RT, D-pad Right rotates).
   Overlap and plot-edge ghosts go red. Fire Pit glows.
3. Place a switch, a lamp 6 studs away. The lamp is lit. Hold Wire on the
   switch: "Wired to the Spark Lamp.", lamp goes dark. Tap Flip: lamp lights,
   lever tips. Flip again: dark. Hold Wire until "Wires cleared.": lamp lit.
4. Wire a switch to a Door (hosted in a door wall): Flip opens, Flip shuts.
   Put a block in the swing: the door stays shut and says why.
5. Leave and rejoin: wires are kept, all switches are off, wired lamps dark.
6. Sell the switch: its lamp relights. A visitor without Interact cannot
   flip, without Build cannot wire.
