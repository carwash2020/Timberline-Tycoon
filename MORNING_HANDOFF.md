# Morning handoff (5 October 2026)

Written overnight while Connor slept. Everything below is merged to `main`
unless it says "in flight". CI (the "checks" job) now takes about 5 minutes
because the slow specs were fixed (PR #51), down from about 50.

## What landed on main

| PR | What |
|----|------|
| #50 | Xbox fixes, W3 (toll, ferry, boulders, gondola checks), W4 (sea warning, Secret Cave, Hermit, Hermit's Maul), plots (Land panel, tutorial steps), B09 furniture, B11 wiring, B13 daily return calendar, B14 Halloween, B15 anti-exploit, B16 text pass, opt-in leaderboard, off-sale passes removed |
| #51 | Boxed stores everywhere (Dealership, chop saw, build palette is not a shop), gold Robux shelf in the Tool Shed, deeper Tool Shed, Xbox input audit fixes, smooth ferry, Old Tolly and Cap'n Moss NPCs, test speedups |

## In flight when this was written

Three agents were working on follow-ups (each becomes its own PR, merged when
CI is green): a longer Hearth & Home shelf plus a bigger Robux board and map
marker; plot visits, a wire tool UI and saved switch positions; a UI cleanup
pass. Check the PR list for what finished.

## Decisions only you can make

1. **Lanternwood in the economy (needs your numbers).** The ferry now works,
   so Ferry Island is reachable, but `ShopLogic.onAxeCard` still skips
   `access == "boat"` biomes and the economy models leave ferryisle out, so
   `economy --check` is unchanged. To bring it in: add `v2` fields on
   palmwood and lanternwood in `WoodData` with a rare-wood price, model the
   ferry as a $400 fare per rider per trip plus up to a 6 minute wait in
   `tools/economy`, regenerate ECONOMY.md and ECONOMY_V1.md, then drop the
   boat skip. Today's inputs: Lanternwood is $6 per u3 (log) and plank 60;
   palmwood is $20 per log, plank 32; lumenwood (the sky rare wood) is $120
   per log, plank 90. A rare-wood price somewhere between palmwood and
   lumenwood fits the ferry cost; it is your call.
2. **Badge ids.** Create the badges in Creator Hub and paste ids where the
   `-- PASTE:` comments are in `BadgeData`. `AreaToll`, `AreaFerry` and
   `AreaCave` now have PASTE lines (their triggers are built). Left at 0 they
   simply skip the award.
3. **Off-sale passes.** Tow Service, Timber Classic and Paint Shop have id 0
   in `StoreData` (hidden everywhere, server refuses). The old ids are in the
   comments; put them back when those passes are real.
4. **DataStore leaderboard.** Studio needs Game Settings > Security > Enable
   Studio Access to API Services for the board to persist. It is opt-in
   (Settings > Leaderboard), off by default.

## Studio checklist (do these on a real device)

**Xbox**
- Equip an axe, stand near a tree, press RT: it swings and deals damage.
- Unequip, press RT on loose wood: it carries (hold RT). RT on a placed item
  while building: selects it. Placing a blueprint with RT only places.
- Hit a tree, then press D-pad Down and Y: drop-axe and send-home still work,
  and the D-pad shortcuts open mid-chop.
- Drive a truck with the stick: small push, small turn; drift is ignored.
  Roll it onto its side: it stands back up after about a second.
- Settings (D-pad Right) > Leaderboard: reachable with the D-pad, B steps back.
- Every menu closes with B; text is 18 px or more on a TV.

**Trucks and cargo**
- Set a log on the bed: it sticks within a moment. Flip the truck: the load
  falls off.
- Hold a log near the bed: the bed sides turn see-through and let it pass;
  the floor stays solid.

**Stores**
- Tool Shed: boxes sit on two tables with an aisle; carry one to the counter
  and pay (phone tap, PC, RT on Xbox).
- Gold ROBUX SHELF: Yes at the counter opens Roblox's purchase dialog; No does
  nothing; an owned pass says you already have it.
- Dealership: no browse window; a lot box paid at Dale's counter opens on your
  plot. Chop saw box is $7,500.
- The Tool Shed's baked workbench mesh may clip the west display table. If it
  does, move the table or replace the mesh.

**Plots**
- New save: sell at the cart, claim a plot, then BUILD, place one item, LAND,
  then the truck. Phone, PC and Xbox.
- Land panel: "Plot size" section (raise level) and "Expand" grid; every
  blocked tap gives a toast.
- Walk off your plot: "Walk back to your plot to build."

**World**
- Toll booth (Old Tolly): pay $100, cross north within 3 minutes; second tap
  is free; under $100 says so.
- Ferry dock: "Board ($400)", fare is taken at casting off, step off first and
  it is free; trucks are refused. With a second player watching, the boat
  should glide (if riders jitter, set `FerryLogic.ClientDriven = false`).
- Boulders: hold 1 s for a blasting charge ($220), 5 s fuse, harmless.
- Secret Cave: Hermit intro on E; five carved marks give the Totem and then the
  Hermit's Maul once; no Lantern in the cave shows one dark toast.
- Deep water: warning toast 40 studs out, then 3 s grace, then damage.

**Content**
- Set Workspace attribute `EventOverride` = "halloween": pumpkins at the
  lamps, Halloween section in Daily, Pumpkin Hat after 3 days of both goals.
- First join of a UTC day: "Daily return, day N of 7" cash and calendar.
- Furniture: Table and Chair at Hearth & Home; Bookshelf, Rug, Barrel, Crate
  and Fire Pit from BUILD. Wall Switch and Spark Lamp: hold Wire (F / Y) on
  the switch to link the nearest lamp or door.

## Known gaps

- No Blender models; Blender is not installed in the cloud container.
- WoodData still has 46 TBD comments (a locked file, left untouched).
- No client wiring tool or drawn wires until the in-flight PR lands.
- The Hermit's Maul has no authored mesh (generic axe shape); carved-mark art
  and a placeable Totem are not built; the frost path is not built.
- Cap'n Moss stands on the mainland dock; there is no island-side NPC.
- The Land Office squares are a prompt on your plot sign, not a building.

## Tooling notes

- `./scripts/check.sh` now finishes in about 8 minutes in the cloud container
  (it never finished before). `tests/run` prints each spec's seconds.
- Worktree branches under `.claude/worktrees/` belong to the overnight agents
  and are not committed.
