# Phase 2+ build notes

Everything after the Phase 1 vertical slice, built on the branch
`claude/sleepy-ptolemy-p7e4pm` while Phase 1 is being playtested. `main`
stays the Phase 1 build until that playtest passes; then this branch is
merged.

**Status:** code complete, **not yet played in Studio.** It passes the same
checks as Phase 1 (`./scripts/check.sh`, also run by GitHub on every push),
plus 162 unit tests.

On this branch, each with its own checklist below:
1. **Axe shop**: the Tool Shed
2. **Murph's tutorial**
3. **Trucks**: the Dealership, every truck, physics driving, Truck to lot
4. **Daily goals and streaks**
5. **The world**: biomes, roads, day and night, Hearth & Home
6. **Trailers**
7. **Robux**: the Store, 2x Cash, cash packs, 2x Wood, Instant Delivery
8. **The Field Guide**
9. **The Aether Isles**: gondola, Lumenwood, Sky Shards, Cloud Chute, Sky Bin, the forge
10. **Plots**: claim a plot, grow it, the Blueprint Store, placing, moving, selling back

Old saves carry over: new save fields are filled in on load. Play the
sections in order the first time (a fresh save gets the tutorial).

## Try this build

```sh
git fetch
git checkout claude/sleepy-ptolemy-p7e4pm
rojo serve
```
Then connect from Studio as usual. `git checkout main` goes back to the
Phase 1 build.

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

- **Cash, top right**, with the Daily Goals button under it.
- **Tutorial tracker, left**, a third of the way down, under Roblox's chat
  window.
- **BUILD** (on your own plot), **Sell load here** and **Truck to lot**
  stack on the right, above the jump button.
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
  replaces your truck in your parking spot, load and all if it fits. Trucks
  you own show **Use** to switch back. The Scout ATV has no bed.
- **Physics driving:** trucks collide with trees and buildings instead of
  gliding through them. Your device drives your truck (smooth, no lag);
  the server checks it never goes faster than it can. Getting out parks it
  where it is. Set `VehiclePhysics = false` in `GameConfig.luau` to get
  the Phase 1 arcade driving back if physics misbehaves.
- **Truck to lot:** a button (right edge) when your truck is far away:
  it goes back to your parking spot with its load. 10 s cooldown.
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
- [ ] Switch with logs in the bed: the load moves over (if it fits)
- [ ] Walk far from your truck: **Truck to lot** appears; press it: the truck
      is back in your spot with its load; pressing again right away says to wait
- [ ] Phone (device emulator): drive with the thumbstick; the Truck to lot
      button doesn't cover the jump button
- [ ] A second player (Test → 2 players) can drive your truck, and it moves
      smoothly for both
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

The **plot district** is east of the parking lot: 12 plots (one per player
on a full server) with a road along the north side and lanes between them.
A sign at each plot's north edge says whose it is.

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
- [ ] Claim a plot: the sign shows your name and "CAMPSITE", a rail marks
      the edge; claiming a second one says you already have one
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
