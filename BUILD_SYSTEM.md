# BUILD_SYSTEM: the hammer and physical blueprints

Status: implemented on branch `claude/hammer-build` (not merged, no PR). Replaces the BUILD toggle and the build palette. Plan owner: Connor (design, 6 October 2026). Rules live in pure modules (`Shared/BlueprintBook`, `Shared/HammerLogic`); this note says why.

## The idea

You build with a **hammer** and **blueprints**, and both are things you hold.

1. Everyone always has a **Hammer** in the hotbar (second slot, after the axes).
2. A **blueprint** is a physical rolled plan: a Tool you buy, find, carry, drop and pick up like an axe. **Using** one (click, RT, tap) consumes the item and adds that building to your **blueprint book**, which you own forever (saved per slot).
3. Hold the hammer and use it (mouse click, RT on Xbox, tap on a phone, or the PLANS button on the hammer bar): your owned blueprints open as a list with name, size and what it needs.
4. Pick one. The same ghost as before follows your aim; every placement rule is unchanged (`PlotLogic.Check`: bought squares, 10-stud pad grid, overlap boxes, tier, height). Rotate and move work as they did (R, D-pad right; LT lock plus stick flicks; RB/LB slide). Place it and the hammer swings: a knock, a puff of dust.
5. A kit piece then needs **wood**: it is a ghost until planks are dropped into it (`FillLogic`, `PlotService.FillStep`, the fill hints). That is today's rule, untouched.
6. Aim the hammer at a piece you already placed and use it: a small sheet offers **Move**, **Turn** and **Sell**. This replaces the old Move/Sell prompts and the edit mode.

## What did not change (on purpose)

- Cash. Only `EconomyService` moves `profile.cash`. Placing still charges what it did (`PlotData.Price`: the kit fee is `KitCashPerUnit` per unit, other pieces their price). Selling still refunds via `PlotData.SellBack`, all of it inside `UNDO_SECONDS`. `tools/economy` and `tools/economy1` need no re-run for this change (they do not model building); `./scripts/check.sh` re-checks both.
- Sawmills and the chop saw. They stay boxes from the Tool Shed (`profile.sawmillStock`), consumed on placing. They show in the hammer list as stock, never as owned plans.
- The BuilderTools bar (rotate, move, resize, copy, delete, undo) for an unfilled kit ghost. It works with the hammer in hand.
- Server authority. Remotes carry intents; every handler validates and rate-limits.

## Data

- `profile.blueprintBook: { string }`: ids in the order learned, unique. Per slot (SaveSlotLogic carries it automatically because it is not an account key).
- `profile.blueprintItems: { { uid, id } }`: unused physical blueprints you own (carried or dropped). Same pattern as `profile.axes`: a dropped one stays yours, comes back on rejoin.
- `profile.hammer: boolean`: always true. The flag is what the loadout reads and what Migrate sets, so an existing save is given the hammer by the same path as a new one.
- Old `profile.furnitureBlueprints` is left in the save (rollback) and is read as part of the book.

### Migration (`BlueprintBook.Migrate`, idempotent, never removes)

A save's book becomes the union of:

- the **starter plans**: every blueprint that was placeable for a fee under the old palette (not a store unlock, not a boxed machine). New players start with these;
- every id in `furnitureBlueprints` (store unlocks already bought);
- every `blueprintId` of anything already on the plot (including sawmills and the chop saw they paid for);
- every sawmill or machine id in `sawmillStock`.

So nothing a player had unlocked or paid for is lost, and running it twice changes nothing.

## Where blueprints come from

- **Stores.** The General Store's boxes with `unlock = true` (Shed, Wood Sign, Paint Can, Mailbox, the furniture). Paying at the counter now grants a physical blueprint instead of flipping a flag. The price is the old one.
- **Owner.** `/gift <player> Blueprint <id>` gives the item (any blueprint id, not only store ones). Owner-only as before.
- **Found / dropped.** `BlueprintService.Drop` and the pick-up prompt exist now (drop with Backspace or the Drop button, like an axe), and `BlueprintService.Spawn(position, id)` puts one in the world for later content. No world spawns are placed yet (open question).

## Hammer use, by device

| Device | Use | Rotate / move | Cancel |
|---|---|---|---|
| PC | left click (Tool.Activated) | R; mouse aims | Q |
| Phone | tap the world, or the PLANS button on the hammer bar | ROTATE button; tap to aim | CANCEL |
| Xbox | RT | D-pad right; LT lock plus LEFT stick flick; RB/LB slide | B |

No new binds: Tool.Activated carries RT, click and tap, so `HudRules` and `InputKit` are unchanged. The list is a ShopUI panel (selectable, B closes, nothing else on the D-pad). On Xbox the crosshair is the aim, so the hammer on a piece opens that piece's sheet.

## Server

- `PlaceBlueprint(blueprintId, x, z, rot, y)`: new check first, the blueprint must be in your book (or a boxed machine in stock). Everything else is as before.
- `UseBlueprint(uid)`: you hold that item, it is removed, the book gains the id (`BlueprintBook.Redeem`).
- `DropBlueprint(uid)`: the item leaves your hands and lies in the world with a pick-up prompt; only its owner can pick it up.
- Hammer FX: after a successful place or move `PlotService` sends `WorldFX("Hammer", { pos, by })` to every other player within 150 studs (`HammerLogic.FxRange`). The placer swings, knocks and dusts at once on their own client. Only the arm swing (the Tool's grip) is local; others hear and see the knock and dust.
- Rate limits and `Net.RemoteNames` entries for each new remote.

## UI

- The BUILD button is gone. Holding the hammer on your own plot shows the **hammer bar**: PLANS, LAND, WIRE, PUT AWAY. (WIRE and LAND lived on the build bar and still need a home.)
- The list has a filter row (All, Buildings, Decor, Machines) that cycles (categories instead of free-text search, which is awkward on Xbox), and a LAND row. A row shows name, size, and what it needs: `8 u³ of planks · fee $32`, `$150 to place`, or `Box from the Tool Shed`.
- The tutorial steps `build`, `place`, `land` keep their ids and order (save keys); only their text changes. `buildOpened` fires when the hammer list opens on your plot.

## Decisions I made (open for Connor)

1. **Starter plans.** Everything that was free to unlock before is in everyone's book from the start, so nothing gets a new price. Only the store unlocks and machines are gated behind a bought item. If Connor wants Cabin, Warehouse and the rest to be bought blueprints too, they need prices and the economy model needs a build sink.
2. **One click uses a plan.** No confirm: it is safe, since the building is yours forever.
3. **Hammer is not droppable.** It is `profile.hammer`, regranted every spawn.
4. **No world-found blueprints yet**, only the machinery for them.
5. **LAND and WIRE live on the hammer bar**, because they were on the build bar and there is no other home for them.

## Where the code is

- Rules, pure and tested: `Shared/BlueprintBook` (book, items, Redeem, Allowed, list order, filter, rows, Migrate), `Shared/HammerLogic` (what a use does, the piece sheet, the swing, dust, FX range).
- Server: `BlueprintService` (hammer, plan items, use, drop, pick up, `Spawn`), `PlotService.Place` (book check, knock), `ShopService` (store blueprints and `/gift` hand over the item), `ProfileSchema` (`blueprintBook`, `blueprintItems`, `hammer`).
- Client: `HammerController` (use, sheet, swing, knock, plan use), `PlotUI` (hammer bar, list), `BlueprintPlacer` (keeps the hammer, `OnPlaced`), `BuilderTools` (`SelectModel`, quiet toast with the hammer), `AxeController` (Drop plan), `ShopUI` (`IsOpen`, focus row).
- Art: `Shared/Art/HammerArt`, `Shared/Art/BlueprintArt`, preview scene `tools/preview/scenes/hammer.luau`.
- The shelf boxes in the General Store still look like crates (store art is another branch's work); only the item you receive is a rolled plan.
- Not touched: store builders, HUD layout beyond one side button, economy tables (no number moved).
