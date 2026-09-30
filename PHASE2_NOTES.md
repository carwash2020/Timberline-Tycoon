# Phase 2+ build notes

Everything after the Phase 1 vertical slice, built on the branch
`claude/sleepy-ptolemy-p7e4pm` while Phase 1 is being playtested. `main`
stays the Phase 1 build until that playtest passes; then this branch is
merged.

**Status:** code complete, **not yet played in Studio.** It passes the same
checks as Phase 1 (`./scripts/check.sh`, also run by GitHub on every push),
plus 93 unit tests.

On this branch, each with its own checklist below:
1. **Axe shop**: the Tool Shed
2. **Murph's tutorial**
3. **Trucks**: the Dealership, every truck, physics driving, Truck to lot
4. **Daily goals and streaks**
5. **The world**: biomes, roads, day and night, Hearth & Home
6. **Trailers**

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
