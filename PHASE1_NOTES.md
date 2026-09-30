# Phase 1 — Vertical Slice Notes

**Goal:** prove the core loop — chop a tree → carry the logs → sell them at the sawmill.

## What was built

### Shared (`src/ReplicatedStorage/Shared/`)
- **WoodData.luau** — all 8 woods with HP, logs/tree, price, biome, respawn time, silhouette, and colors. Oak: 30 HP, 3 logs, $8/log, 45s respawn → Phantomwood: 1200 HP, 9 logs, $600/log, 300s respawn.
- **ItemCatalog.luau** — axes (Rusty 5 dmg → Inferno 200 dmg), trucks (Rustbucket bed 6 → LoggingRig bed 48), trailers, boats, and biome gear. Phase 1 uses Rusty Axe + Rustbucket only.
- **Util.luau** — `clamp`, `guid`, `formatCash`, `deepCopy`, `pointInPart` (sell-zone check).

### Server (`src/ServerScriptService/`)
- **ProfileService.luau** — DataStore `PlayerProfiles`, key `profile_<UserId>`, full §14.2 schema. Session lock via `UpdateAsync` (10-min stale TTL); failed loads → session-only mode that **never writes**. Autosave 120s, save-on-leave, flush on shutdown.
- **EconomyService.luau** — the SOLE writer of `profile.cash`. `AddCash`/`SpendCash` with reason logging; fires `CashChanged`.
- **TreeService.luau** — builds low-poly trees (cylinder trunk + ball foliage), server-side HP, shake-on-hit, tip-over fell animation, spawns exactly `logsPerTree` logs, respawns per-wood timers. Log records: world/carried/truck, 10s feller grace then free-for-all.
- **VehicleService.luau** — builds the Rustbucket from parts (body, cab, wheels, VehicleSeat, mismatched bed panels), per-player spawn, ProximityPrompt "Drive", arcade CFrame driving while seated. Bed capacity 6 with 3D mini-log visuals.
- **MapBuilder.server.luau** — green ground plane, SpawnLocation at the forest edge, ~40 oak + ~15 birch scattered south of spawn, sawmill building (open front, roof, spinning-prop saw blade, log piles, sign), invisible **SellZone** out front, 4 ghosted 120×120 plot markers for later phases.
- **GameServer.server.luau** — creates `ReplicatedStorage/Remotes` (ChopTree, PickupLog, LoadToTruck, SellLogs, CashChanged). Player join → load profile → spawn truck → give Rusty Axe; leave → save + lock release. All four remote handlers with range/distance validation and per-remote rate limits; 10 violations → kick.

### Client (`src/StarterPlayer/StarterPlayerScripts/`)
- **Client.client.luau** — starts everything.
- **ChopController.luau** — click/hold on a tree raycasts to the tree model, fires ChopTree. Client cooldown mirrors the server's 0.8s.
- **TreeUI.luau** — BillboardGui HP bars that appear once a tree is damaged (green → yellow → red), hide on fell.
- **CarryController.luau** — **E** loads carried logs to your truck, **Q** sells hands + truck bed at the sawmill. Log pickup is via ProximityPrompt on each log.
- **HUD.luau** — cash plaque top-left (wood-grain/kraft-paper theme) synced from the server, control hint bottom-center. Built from code so Rojo syncs it.

## How to play it (Studio Play test)
1. Serve with Rojo, press Play. Spawn at the forest edge with the Rusty Axe in your backpack (equip it).
2. Click a tree (hold to keep chopping) — HP bar appears, tree shakes, tips over at 0 HP and drops exactly 3 oak / 2 birch logs.
3. Walk up to a log → "Pick up" prompt. You can carry 2 at a time (stacked in front of you).
4. Walk to your Rustbucket (parked by spawn, press E near it) → "Drive" prompt in the seat; E loads your carried logs into the bed (6 max).
5. Drive/park at the sawmill (north of spawn), stand in the SellZone in front of it, press **Q** — logs sell, cash appears top-left. Oak log = $8.

## §14.9 acceptance checklist
- [ ] New player spawns with $0, Rusty Axe in backpack, Rustbucket nearby
- [ ] Clicking a tree within 20 studs chops it; >20 studs rejected
- [ ] Oak falls after 30/5 = 6 swings; drops exactly 3 logs
- [ ] Logs pickup-able within 12 studs; max 2 carried; 10s feller grace
- [ ] E near truck loads carried → bed (6 max); Q in SellZone sells hands + bed
- [ ] Selling values logs from SERVER records, destroys models, credits cash
- [ ] Tree respawns after 45s (oak) with full HP
- [ ] Leaving and rejoining restores cash (DataStore round-trip)
- [ ] Spamming ChopTree doesn't bypass the 0.8s cooldown

## Known limitations / next
- **Never tested in Studio** — this is a careful first draft. Expect Rojo/Luau syntax or API issues on first sync (check the Output window).
- Driving is arcade CFrame movement; real VehicleConstraint physics comes in Phase 4.
- Client has no exploit protection beyond server validation; that's by design — server re-checks everything.
- No shop, blueprints, NPCs, quests, seasons, or trading (Phase 2+).
- Tree placement is random-scatter, not art-directed; the full 3000-stud world comes with the biome passes.
- `default.project.json` still names the game `LumberGame` — rename to **Timberline Tycoon** in Studio before publishing.
- Axe Tool has no swing animation yet; it plays `tool:Activate()` which does nothing until one is added.
