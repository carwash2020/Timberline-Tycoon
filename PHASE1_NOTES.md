# Phase 1 — Vertical Slice Notes

**Goal:** prove the core loop: chop a tree → carry the logs → sell them at the sawmill.

**Status:** code complete, **not yet played in Studio.** Every script passes a
strict type check against the Roblox API (`./scripts/check.sh`), but only a
Studio playtest proves the loop feels right. See "First playtest" below.

## What's built

### Shared (`src/ReplicatedStorage/Shared/`)
- **WoodData**: all 8 woods (HP, logs/tree, price, biome, respawn, colours).
  Phase 1 spawns oak and birch.
- **ItemCatalog**: axes, trucks, trailers, boats, gear. Phase 1 uses the
  Rusty Axe and the Rustbucket.
- **GameConfig**: ranges, cooldowns, capacities and sound ids that the
  client and server must agree on.
- **Net**: remote names. **Util**: `formatCash`, `pointInPart`, `guid`, …

### Server (`src/ServerScriptService/`)
- **ProfileService** wraps **ProfileStore** (vendored, by loleris): session
  locking across servers, autosave, retries, shutdown flush.
  DataStore `PlayerProfiles`, key `profile_<UserId>`, full §14.2 schema.
- **EconomyService**: the only writer of `profile.cash`, with a logged reason.
- **TreeService**: trees with server-side HP; felling hinges the tree over
  at its base, then lays exactly `logsPerTree` logs along the fallen trunk;
  respawn per wood. Logs: 10 s feller grace, then free-for-all; logs left
  lying around despawn after 5 min.
- **VehicleService**: the Rustbucket (open seat, roll bar, bed of 6, a bit
  of exhaust smoke), one parking slot per player, arcade CFrame driving.
- **MapBuilder**: ground, spawn, 40 oak + 15 birch, parking lot (24 slots),
  sawmill with a visible **SELL LOGS HERE** pad, 4 plot markers.
- **RateLimiter**: drops request spam quietly; only floods earn strikes.
- **GameServer**: remotes, join/leave, all request handlers.

- **AxeService**: axes are items. Every owned axe is in the hotbar; drop
  one and it lies on the ground with a "Pick up" prompt (owner only).
  Dying or leaving never loses an axe. In Studio, chat `/giveaxe inferno`
  (any axe name) for a temporary test axe that isn't saved.

### Client (`src/StarterPlayer/StarterPlayerScripts/`)
- **ChopController**: chop with the axe's Activated event (mouse, touch and
  gamepad), aiming at the tree under the pointer or the nearest one in reach.
- **TreeFX**: wobble, wood chips and optional sounds on every hit.
- **TreeUI**: HP bars over damaged trees.
- **CarryController**: "Load logs" prompt on your tailgate, "Sell logs"
  prompt on the sell pad, shown only when they apply.
- **HUD**: cash, device-aware hint, toasts, "Loading your save…".
- **AxeController**: "Drop axe" button (and Backspace) while holding an axe.

## How to play
1. Spawn by the forest with the Rusty Axe in hand.
2. Click / tap / hold R2 on a tree (hold to keep chopping). It falls after
   6 hits (oak) and leaves 3 logs.
3. Walk up to a log → **Pick up** (E, or tap the prompt). You carry 2.
4. At your truck's tailgate → **Load logs** (bed holds 6). **Drive** is at
   the seat; jump (Space) to get out.
5. Drive to the sawmill (north of spawn), stand on the **SELL LOGS HERE**
   pad → **Sell logs**. Oak is $3 a log, birch $4. The truck bed only sells if the
   truck is parked by the mill.

## First playtest: what to check

§14.9 acceptance (all must pass before Phase 2):
- [ ] Spawn with the Rusty Axe; oak falls in exactly 6 hits (30 HP / 5 dmg)
- [ ] Tree wobbles, chips fly, HP bar shows; falls and leaves exactly 3 logs
- [ ] Pick up ≤ 2 logs by hand (prompt within 10 studs)
- [ ] Rustbucket bed holds 6; sell it at the sawmill
- [ ] Sell on the pad: +$3/log (oak); cash only changes via EconomyService
- [ ] Leave + rejoin: cash and axe persist (needs API access, see README)
- [ ] First sale in < 3 min in a solo Play test
- [ ] ChopTree rejected when too far; can't swing faster than every 0.8 s

Axes as items:
- [ ] Rusty Axe is in the hotbar and in hand on spawn
- [ ] Chat `/giveaxe inferno` and `/giveaxe gold`: both appear in the hotbar;
      switch with number keys or taps; chopping uses the one in hand
- [ ] Drop (Backspace / button): the axe lies on the ground; "Pick up"
      brings it back; a second player sees "That's <name>'s axe"
- [ ] Die, then respawn: every axe is back (except ones lying on the ground)

Wallet cap (optional):
- [ ] Set `CashCap = 50` in `GameConfig.luau`, sell logs past $50: the cash
      shows "MAX" in amber and a toast says what didn't fit. Set it back to
      `2_000_000` afterwards.

Numbers to report back (from the `[Stopwatch]` lines in the Output window):
- [ ] "First sale at …" (target: under 3:00)
- [ ] "Could afford the Steel Axe at …" (design target: 12–15 min)
- [ ] **Calibrate the economy model:** play oak/birch with the Rusty Axe and
      Rustbucket for ~10 minutes, then run the
      `lune run tools/economy --calibrate …` line the Output prints (in the
      repo folder), and commit `tools/calibration.json` + ECONOMY.md (or just
      paste the line to Claude)

Things only a human can judge (report back):
- [ ] Axe sits right in the hand and the swing animation plays
- [ ] The fall looks good (direction, speed) and logs land sensibly
- [ ] Driving feels OK for Phase 1 (it's arcade movement, see limitations)
- [ ] Prompts show at the right moments (Pick up / Load / Drive / Sell)
- [ ] Output window shows no red errors
- [ ] Optional: test on a phone via Studio's device emulator (Test tab)

## Known limitations
- **Driving is arcade CFrame movement**: the truck passes through trees and
  walls and may look choppy to the driver. Real vehicle physics is Phase 4.
- **Anyone can drive anyone's truck** (loading and selling only use your own).
- **No sounds yet**: set `ChopSoundId` / `FellSoundId` in GameConfig to
  sound ids from the Creator Store.
- Range checks give ±3 studs of slack for lag: the client stops aiming past
  20 studs, and the server rejects past 23.
- With Studio API access on, test sessions write to the real
  `PlayerProfiles` store. Fine before launch; wipe test saves before
  release if you like.
- Tree placement is random scatter, not art-directed; the full world comes
  with the biome passes.

## Economy status
- **Economy pace:** tuned on 2026-09-30 to match §4 (see ECONOMY.md):
  first Steel Axe ~10 min, all of V1 ~17 h. Those numbers rest on
  EFFICIENCY = 0.50, a guess; the calibration step above replaces it with
  a measured value.
