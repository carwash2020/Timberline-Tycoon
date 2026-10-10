# Phase 2+ build notes

## Lane W: practical automation (8 October 2026, branch `phase-2/v1-w-automation`)

What changed: `AutomationLogic` (ports, power and reverse rules, detector filter, sweeper pick, laser reach), `WireLogic` (belts, mills and planers are wire targets; detector and laser are sources; machines never count toward the logic cap), `LogicGraph` (per-port levels, machine nodes only when wired), `LogicService` (targets, Reverse/Flip/Filter prompts, sweeper, detector, laser), `BeltService` (signed speed), `SawmillService` / `PlanerService` (pause while unpowered), `MachineArt` (TLD-1 deck, Switch Belt, Tilted Belt, Belt Support, Wood Detector), `ItemCatalog`, `LogicItems`, `SparkworksStock`, `ProfileSchema` (keeps `reversed`/`flip` only as `true` on pieces that have them), `RateLimiter` (BeltReverse 2, BeltFlip 2, DetectorFilter 3). Cross-lane: `ItemBox` scales only ToolShed belts in its Belt group.

Studio checks (PC, phone, Xbox):

1. Old plot: load a save with belts and mills and no wires. Everything runs as before.
2. Place a SparkSwitch and a straight belt, wire switch to belt port 1. Switch off: belt stops. On: runs. Wire a second switch to port 2: on reverses the belt.
3. Wire a switch to a sawmill. Start a cut, switch off mid-cut: the log stops and stays held. Switch on: the cut finishes once, the same planks.
4. Reverse a belt with its prompt (E / ButtonX / tap). A visitor gets "Only the plot's owner can change that belt." Rejoin: the belt is still reversed.
5. Switch Belt: Flip prompt (F / ButtonY / tap) moves the paddle to the other side; logs leave on the other exit. Wire port 1: switch on swaps the side.
6. Tilted Belt from a ground belt onto a straight belt on two Belt Supports: logs climb and carry on.
7. Wood Detector: Filter prompt steps Any wood, Oak, Birch ... back to Any wood. Wire it to a lamp: lamp lights while a matching log is under the arch.
8. Wood Sweeper beside a belt, wired from a detector: a matching log is pushed off sideways. Held pieces, other players' wood, players and trucks are never pushed.
9. Laser Emitter facing a Laser Receiver across a belt: thin blue beam. A log breaks it (wired lamp lights); a wall or a player does not.
10. Phone 667x375 and Xbox: every prompt reachable, no ButtonR2 binding added.

Previews: `previews/v1-w/v1-w-automation-1..4.png` (sorting line; tilted belt onto supports; sweeper down and laser; switch belt placed and flipped with a detector).

## Lane D: axes, boxes, shelves, hover tags (8 October 2026, branch `phase-2/v1-d-axes-displays`)

Done on this branch, not on main. Rebased onto main at `f96b62c`. The store board is not in this PR (lane P owns the redesign). Box and hover renders live in `previews/v1-d/` (listed in STATUS.md). Axe, temper and shelf pictures were part-built and are gone until `phase-2/v1-preview-meshes` can draw the real meshes.

Axes (uploaded meshes replace the part-built axe when they load; the Hermit's Maul has no mesh and stays part-built):

1. PC, Play mode. In the command bar run `print(require(game.ReplicatedStorage.Shared.Art.MeshKit).Stats())`. `loaded` is greater than 0 and the axe ids are not in `failedIds`. Equip Rusty, then each rung, then the Lux Axe. The hand sits near the foot of the haft and the blade points forward. A swing still chops. Q or Backspace drops it, and it lies flat. The Hermit's Maul is still the part-built wedge (a heavy head, a flat poll, rope on the haft). It has no custom mesh yet.
2. Phone emulator. The same equip, swing and drop. Drop is a long press on the hotbar. No new button, and nothing sits on the thumbstick or the jump button.
3. Xbox. Swing on RT. Drop is B, twice, with the toast. B still closes a menu instead of dropping. No control is bound to ButtonR2 for good.

Tempers are look-only (`AxeArt.ApplyTemper`). Nothing in the game calls that yet, so Studio will not show Keen, Heavy or Prosperous until lane A2 wires it. Keen is the speed temper (sky blue wind). Heavy is the damage temper (a white edge sheen). Prosperous stays coin gold. The neon edge, the wind streaks and the white sheen sit on the front face of the head mesh, not inside it. With no mesh they use the part-built head. Stats do not move.

Boxes (the window crate; shell stays at 9 parts, a full box at 42):

4. PC. Buy or spawn a boxed axe and a boxed truck. The box has a wood body, a glass front, a 0.1 accent band and a small brass plate under the name, clear of the letters. No price, no decal, no billboard on the box. The item shows through the glass. Good: it matches `previews/v1-d/boxes-after-axe.png` and `boxes-after-sawmill.png`. A truck box still appears (the shell did not grow, so the 42-part cap still holds).
5. Phone emulator, Lower quality. The same boxes. The copies of the item inside are gone and the glass is tinted. The shell, the band and the plate stay. Nothing new sits on the thumbstick or the jump button.
6. Xbox. Look at a box on a shelf. The tag hangs on it. No control is bound to ButtonR2.

Shelves (the unit is `ShelfLayout.Build`; the shop on screen still uses lane C's `ShopInterior.SteppedUnit` until C copies it):

7. The unit is three boards stepping up (tops 3.2, 2.98, 2.76), four timber posts, a dark kick, three cream rails. Feet on the floor, front of the unit at the front. In Studio the Tool Shed shelves will not change until lane C adopts this unit. Gaps stay 1.5 across and 2.5 between rows. No shelf picture in this PR.

Hover tag (the price line only; the words do not change):

8. PC. With enough cash, look at a priced shelf item. The price line is gold (`#F2C14E`). Spend down or look at something you cannot afford: the line is red (`#D9534F`). A free item (price 0) is gold. Closed, already owned, out of stock, and a Robux line stay the old cream. One price, never two numbers.
9. Phone emulator. The same colours. The tag does not cover the thumbstick or the jump button. Touch targets stay about 44×44 and 8px apart.
10. Xbox. The same colours inside the existing look ranges (gamepad 12, touch 6). No new ButtonR2 bind.

Awaiting Connor: a Blender mesh for the Hermit's Maul (it stays part-built until that exists), a hand 25–30% up the haft (it stays at 0.75), a Lux haft of 4.0 in play (it stays 3.5), and four bevel parts on the box corners (they are not parts).

Everything after the Phase 1 vertical slice. It's all on `main` now
(merged October 2026, with the redesign below).

**Status:** code complete, **not yet played in Studio.** `./scripts/check.sh`
passes (formatter, linter, strict types against the Roblox API, 351 unit
tests, ECONOMY.md current); GitHub runs it on every push.

## V1 UI (lane U, branch `phase-2/v1-u-ui`)

Mockups (phone 667x375 and PC 1920x1080): `previews/v1-u/loading-667x375.png`, `previews/v1-u/loading-1920x1080.png`, `previews/v1-u/hud-667x375.png`, `previews/v1-u/hud-1920x1080.png`, `previews/v1-u/hud-buttons-667x375.png`, `previews/v1-u/hud-buttons-1920x1080.png`, `previews/v1-u/owner-menu-667x375.png`, `previews/v1-u/owner-menu-1920x1080.png`, `previews/v1-u/theme-sheet-667x375.png`, `previews/v1-u/theme-sheet-1920x1080.png`, `previews/v1-u/news-667x375.png`, `previews/v1-u/news-1920x1080.png`.

Look: walnut panels, cream text, amber prices and edges, green confirm, danger fill `#B23B30` (cream on it is 4.80:1), muted locked. GothamBold for titles and buttons, Gotham for body. Radius 8, stroke 2, selection ring #FFF4C2 at 4px. Uploaded UIArt skins (cash plaque, prompts) still cover the flat colours once those images load; until then the flat theme shows, and that is what the previews draw (those image ids are not readable from this machine). Side-button marks and the What's new icons are frames, the same shapes as in the game; they have no asset id. The loading card sits on a sunset scene and shows the wordmark, a progress bar and one tip at a time. `hud-667x375.png` and `hud-1920x1080.png` are the in-context HUD (cash, Field Guide labelled with its book icon, side buttons with a saves, hammer or truck mark, one selection ring, and the hint on a solid ink pill). On the phone the thumbstick is Roblox's dark ring and knob, the jump button is the round button, and the hotbar starts to the right of the stick zone. `hud-buttons-*.png` is only the style row.

What's new in V1: seven headlines, each with a short muted second line, in `NewsLogic.Entries` (the island map with the Bayou and Red Mesa, the cave and ore, blueprints, Foreman Rook's daily jobs, axe tempering, Sparkworks logic pieces, the gondola sky island). Once per save after the tutorial, stored as `onboarding["News:V1"]` (no new save field). Settings has WHAT'S NEW. Close or B skips it. The card is only as tall as those rows, with a sunset wordmark on top. On a short screen it sits to the right of the thumbstick and above the jump box. Close is centred on the card and 44px tall on the phone.

Lane E: `DailyUI` remains in the client module list, but the client does not call `DailyUI.Start`. Starting it warned, because the Daily Goals button size was removed. Foreman replaces that module. Output should not contain `[Client] DailyUI failed to start`.

Controller, first selected button:
- Owner menu: PLAYERS tab
- Quick menu: first tile
- Settings: GAME tab
- What's new: Close

B closes those panels. None of them binds ButtonR2 (RT still chops and places, as before).

Studio checks:
- PC: the loading card sits on the sunset scene, shows the title, a progress bar and one tip, then the next tip, with no repeat until the list ends. The HUD matches `hud-1920x1080.png` (cash, FIELD GUIDE with a book icon, SAVES and Send truck home with their icons, the hint on a dark pill). Owner menu (if you are the owner) is walnut with a cream title. Settings, WHAT'S NEW: a sunset wordmark, seven headlines each with a muted second line, Close centred at the bottom of a card that is only as tall as that list. Cash still reads. Output has no DailyUI startup warning.
- Phone (667x375 landscape): the same panels fit. What's new Close is 44px tall, centred, and not under the jump button or in the thumbstick zone. The side buttons are 44px tall, carry a saves, hammer or truck icon, and sit above the jump button. The hotbar starts to the right of the thumbstick. Field Guide reads GUIDE. The chop hint sits on a dark pill. Compare with `hud-667x375.png` and `news-667x375.png`.
- Xbox: open each panel above. The cream ring is on the first button immediately. D-pad and the left stick reach every button. A activates. B closes and returns to the HUD button that opened it. RT still swings the axe and does not change owner-menu tabs.

## V1 UI round 3 (lane U, branch `phase-2/v1-u-ui-r3`)

The Game Art Director's final skins, the phone HUD column and the real icons. Previews are in `previews/v1-u/r3-*.png` (hand-built from the UITheme values and the real icon PNGs in `assets/ui/icons/`; Liberation Sans stands in for Gotham and Fredoka).

- **Tokens:** `UITheme.Skin` holds Paper `#F0E1C3`, PaperDark `#E2CFAA`, Cream `#F5EBD7`, Bark `#583A22`, Ink `#3C2814`, Muted `#A09178` and the plaque numbers. The older `UITheme.Colors` names keep their values, so screens that read them do not move.
- **Plaque and Panel:** `UITheme.Plaque()` (inset 4) and `UITheme.Panel()` (inset 12) are built from frames: a Paper face (corner 12, 2 px Bark stroke, Cream 0 / Paper 0.18 / PaperDark 1 gradient at 90) on a 4 px Bark drop edge. No image, no shadow object. The cash plaque, prompt cards and tutorial cards still use the uploaded UIArt skins (so `UIArt.spec` stays pinned).
- **Buttons:** corner 10, a 3 px drop edge in the style's edge colour, the shine (white at 0, 0.9 grey from 0.12), a 2 px Muted stroke only on `starter`. Pressed, the face drops 3 px onto the edge. The edge adds 3 px to a button's height (`UITheme.ButtonDrop = 3`; callers already added it).
- **Loading card:** one plaque at (0.5, 0.45), `min(280, 72% of the width)` by 132, 16 px padding, over Ink at 45% transparency. FredokaOne 20 Ink title, one GothamMedium 14 Bark line (never smaller). No scene, no progress bar, no buttons. Same 30 s timeout.
- **Phone HUD (touch, no keyboard, under 600 tall):** the side column is MENU, HAMMER and Sell here as 44 x 44 icon buttons, one column, faces 8 px apart. MENU is shown on a phone and opens the quick menu; SAVES, Send truck home and (for the owner) OWNER are tiles in it. The rules are `Shared/PhoneHud`; the look is `HUD.SideButton`. The icons are `UITheme.HudIcons` (Image ids Menu 76852120099119, Hammer 129127727779001, SellHere 96932580819074), 28 x 28 in the face. If an id is 0 or the image fails to load, the button shows MENU, BUILD or SELL.
- **What's New:** Close is a 44 x 44 square (an X), 8 px under the last row.

Studio checks:
1. PC: the loading card is one cream plaque (a darker brown edge under it) near the upper middle, over the dimmed game, with "Timberline Tycoon" and one tip; it fades once you are in. Buttons everywhere have a small darker edge under them; press one and the face sinks onto it. `starter`-style buttons have a thin grey-brown outline.
2. PC: the HUD layout is the same as before (Field Guide, cash, STORE, SAVES, Send truck home); nothing moved except the new button edges.
3. Phone (Studio device emulator, 667x375): the right-hand column is three square buttons, MENU (bars on amber), then the hammer and the coin (cream icons on dark green) when they apply. Each is a real picture, not text. They are 8 px apart, in one column, with no second column. Tap the hammer: it takes the hammer out. Tap the coin near the sell pad: it sells.
4. Phone: tap MENU. The quick menu opens with SAVES, STORE, BADGES and so on, plus SEND TRUCK HOME when your truck is away (and OWNER if you are the owner). Tap SAVES: the saves panel opens. Tap outside the menu: it closes.
5. Phone: the loading card is 280 wide, centred a little above the middle; What's New (Settings, WHAT'S NEW) shows a square X Close under the last line, not touching the jump button or the thumbstick area.
6. Xbox (controller or emulator): the HUD column keeps the wide buttons (MENU with the View glyph, SAVES, Send truck home). Press View: the quick menu lists SAVES and SEND TRUCK HOME, A opens them, B closes. RT still swings the axe.
7. If an icon shows letters (MENU, BUILD, SELL) instead of a picture, the image id did not load in your Studio session; tell Claude which one.

What's here, each with its own checklist below:

15. **V1 economy core** (8 October 2026, branch `phase-2/v1-a1-economy-core`): climate damage, the Prosperous stamp, prices, and the save contract


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

15. **Mining and crafting** (8 October 2026, branch `phase-2/v1-m-mining`): ore rocks, picks, bombs, the smelting furnace, the craft bench

14. **Trees in the spawn area** (8 October 2026, branch `claude/spawn-trees`): 54 more choppable trees in and round the town, by the pad, the dealership and the Land Office

15. **V1 buildings, shops, props and palette** (8 October 2026, branch `phase-2/v1-c-buildings`): one style for the town buildings, shops at 250 parts or fewer, new small buildings, renders in `previews/v1-c/`
16. **Sparkworks logic sandbox** (8 October 2026, branch `phase-2/v1-s-sparkworks`): wires, gates, timers, the settings panel, the demo board

13. **Saves by hand, and Unload base** (8 October 2026, branch `claude/plot-save-switch`): the save picker at join, Restart save in Settings, UNLOAD / LOAD BASE in the SAVES panel
15. **V1 nature looks** (8 October 2026, branch `phase-2/v1-g-nature`): first renders of trees, rocks, plants, cave dressing, critters and rain. Not placed in the world yet.

Where the redesign changed something an older section describes (the
world layout, the trucks' looks, chop range, the Sky Bin), the redesign's
section wins.

Old saves carry over: new save fields are filled in on load and old ones
migrated. Play the sections in order the first time (a fresh save gets the
tutorial).

## V1 buildings, shops, props and palette (8 October 2026, branch `phase-2/v1-c-buildings`)

One upgraded look for the town buildings. Shops keep the pinned footprints (Tool Shed half-depth 15 and half-width 11.9, Hearth 16.5 by 14.5, Dealership hall x 181 to 336). The axe rack is still a stepped shelf with a tier-colour block per axe; each rack axe is a two-part silhouette so the whole Tool Shed stays at or under 250 parts. Prices are not printed on the models. The live Land Office in the world is still `PlotService`'s own model (this lane only adds `BuildingArt.LandOffice`, with no price on the sign). Renders for Connor: every path under `previews/v1-c/` listed in STATUS.md.

**PC**

- Walk the spawn road to the sawmill, the Tool Shed, Hearth and Home, and the Dealership. Each reads as the same timber-and-slate style: stone-coloured base, honey plank walls, a roof, a porch, a lit sign.
- Sawmill office: the foreman stand is the invisible pad west of the office door, facing the road. The chalkboard beside it reads DAILY JOBS, with the posts at the edges of the board and the words clear of them. Nothing solid within 6 studs of the pad. The lumber pile, barrel and crates are behind the cabin.
- Tool Shed: blue sign (#3A6FD8). Step in. The counter top is at the same height as before. The axe rack is on the back wall, blades to the left, stepped, one colour block per axe. Buy an axe; the box still comes off the shelf.
- Hearth and Home: green sign (#2F5D3A). The porch posts stand just inside the front wall (the pad starts at the wall; posts outside it sat on grass).
- Dealership: red sign (#D9534F). The showroom walkway is clear. The three nearest bays have a low plinth and a dim lamp. The porch lantern is no brighter than the showroom lamps.
- Weigh House: red metal roof, a round scale on the side. No new price text.
- New models are built but not placed in the live town yet: gate kiosk, Odds and Ends ("CHARGES", no dollar amount), Sparkworks (empty demo board), Sky Market, Gondola Pass turnstile, plot map, arrival arch, Land Office cottage (the live office is still PlotService's).
- The sky forge court, the pond dock, the campfire, the lookout and the park bench are in the built town (`TownScenes`). Walk south-west across the meadow: the forge court is at (-112, -20), front toward the mill, stone floor, anvil, ORDERS board, four relic sockets. The lookout just west of it (-136, -20) has a ladder you can climb and a telescope aimed at town. On the green south of the main street, west of the well: a park bench at (-84, 56) and a teepee campfire at (-72, 56) with a pot. South of town, the fishing dock stands on the pond's north bank (pond at 78, -182): planks, posts in the water, a rod, a bucket and a crate. No second sheet of water.

**Phone emulator**

- Same walk. Shops should stay readable and not hitch when you enter (Tool Shed 241 parts, Hearth and Home 195, Dealership 215, sawmill 402).
- Signs stay readable at the door. Windows and the porch lantern are the only small lights on the shop fronts.

**Xbox**

- Same walk with the stick. Door prompts still appear in range. Talk to the keeper; the counter does not block the prompt. Aim at an axe on the rack: the hover tag still shows the name and price (nothing on the model itself).

Good: one family of colours, no dollar signs on buildings, doors and counters where they were, rack still stepped. Bad: a shop over 250 parts, a price painted on a sign, the Tool Shed rack missing a sold axe, grass under the Hearth porch, or the Dealership porch lamp brighter than the showroom.
## Sparkworks logic sandbox (8 October 2026, branch `phase-2/v1-s-sparkworks`)

Connor wants Sparkworks in V1, and he wants to see the pieces before they merge. Renders (names only, no prices on the models): `previews/v1-s/pieces-1.png` through `previews/v1-s/pieces-4.png` (at most four pieces, 3/4 at 30 degrees, the group about 70% of the width, name on a ground plaque), `previews/v1-s/wired.png` (lever and button into AND into a lamp, unlit beside lit, right-angle wires), `previews/v1-s/settings-panel-phone.png` (667x375) and `previews/v1-s/settings-panel-desktop.png` (1920x1080, the selection ring on minus). Panel colors are UITheme's. `SparkworksTheme.Layer = 16` is local until Lane U adds it.

What shipped: Button $320, Lever $520, Pressure Plate $640, Wall Switch $100, AND/OR/XOR $260, NOT $200, Delay $520, Sustain $520, Clock $902, Spark Lamp $150, Glow Wire $720, Hatch $830. A Door you already own can be wired. Bought once, then placed free. The Wall Switch and Spark Lamp stay on Hearth & Home until Lane F stocks Sparkworks from `SparkworksStock` (anyone who already owns one keeps it). Laser, Detector and Wood Detector are not in this pass (V1.1).

Caps (proposals): 80 logic pieces and 160 wires on a plot. A looping circuit stops at 200 evaluations and the piece reads Overloaded. The graph ticks only while the owner is online and the plot is loaded. Delay, Sustain and Clock remember their setting in `plot.logic`. Clocks and in-flight delays start again on rejoin (the phase is not saved).

Lane K's meshes: each piece looks for a model of its id under `MeshTemplates`, with slots Body, Indicator, Moving and LabelFace. A missing model keeps the part build and logs once. Indicator is the lamp or LED. Moving is the lever, the button cap, the hatch door or the plate top. The gate label sits on LabelFace. Lane W can call `LogicService.RegisterTarget(uid, { power, reverse })` for a belt, a sawmill or a planer. Those inputs are stored and not driven yet.

`V1Boot.Start` receives the remote table from GameServer and calls `LogicService.V1Init`, so `LogicSet` has a listener before anyone opens the settings panel. The settings panel sits at the top centre, clear of the thumbstick and the jump button. Minus, plus and Done work by tap, click, and the d-pad or arrow keys. B closes it. The wire tool and the panel bind gamepad keys only while they are open.

### Studio checks

1. **PC.** Place a Lever and a Button, wire them into the two inputs of an AND gate, and wire the gate to a Spark Lamp. The lamp lights only when both are on. The button lets go after about a second. The lever stays. Good: the lamp goes dark when either input drops.
2. **PC.** Wire a Clock to a Spark Lamp. Use Set, then plus and minus. The lamp blinks once per the number you set. Leave and rejoin, and swap save slots: the number is the same. The clock starts off again. Good: one number in the panel, in seconds.
3. **PC.** Wire a Pressure Plate to a Hatch. Stand on the plate: the hatch opens. Step off: it shuts. Drop a piece of wood on the plate: it opens again.
4. **PC.** Wire three NOT gates in a ring. Each piece shows Overloaded. The server stays smooth.
5. **PC.** Leave the server. Lamps and clocks stop. Rejoin: levers and settings match what you saved.
6. **Phone emulator.** The wire tool: tap an output, tap an input. The settings panel: tap minus, plus and Done. Nothing sits on the thumbstick or the jump button. The first wiring session shows "Pick an output", then "Pick an input", then "Done: flip it", once.
7. **Xbox.** Wire tool: RT picks, X cuts, B leaves. Settings panel: the stick moves between minus and plus, A presses, B closes. The d-pad is not used (it stays the HUD shortcuts). After both are closed, chopping with RT still swings the axe.
8. **Demo board.** If Sparkworks has a part named DemoBoard, a lever feeds an AND, a clock feeds a lamp, and a plate feeds a hatch, with no save. If the building is not in the world, nothing errors.
9. **Gates.** AND, OR, XOR, NOT, Delay, Sustain and Clock each show a cream label on the dark top (AND, OR, XOR, NOT, DLY, HOLD, CLK) and a different coloured strip. You can tell them apart without opening the shop. Until Lane K's meshes are in the place, Output logs `[LogicItems] <id> has no MeshTemplates model; keeping the part build` once per piece and the parts stay.

## V1 economy core (8 October 2026, branch `phase-2/v1-a1-economy-core`)

Not seen in Studio. The model (ECONOMY.md) is 68 s / 5.4 min / 17.9 min / 66.3 min / 33.5 h. Lane B, after this merges, edits only BiomeData haul distances and possibly `GameConfig.ExpansionPriceStep`, then reruns `lune run tools/economy`.

**Snow and the volcano.** Stand in the Snowfields with no coat. The player attribute `Exposure` climbs from 0 to 1 over 8 seconds and `ClimateKind` is `snow`; health does not drop until the meter is full, then about 4 per second. Sit in a vehicle seat: `Exposure` stops where it is. Step back to the forest, equip the Insulated Coat, or respawn: `Exposure` goes to 0 and the damage stops. On the volcano, outside the crater, the same meter fills over 6 seconds and then health drops about 6 per second; Heat Boots clear it. Inside the crater the old lava burn stays (5 per second) and `ClimateKind` stays empty.

**Prosperous (`t`).** Fell with an axe whose temper is Prosperous I, II or III. The log's attribute `t` is 1.04, 1.07 or 1.10. Run it through a sawmill and a planer: the plank still has that `t`. Load it, unload it, leave and rejoin: `t` is still there. Sell it. A log pays its price times `t`. A plank pays its price times min(3, mill bonus × board bonus × `t`). An axe with no Prosperous temper has no `t`. Truck paint is unchanged.

**Prices and the pass.** The Tool Shed shows the Steel Axe at $110 and the Cobalt Axe at $2,500. The Gondola Pass is not on a shelf. With under $5, recalling a truck is free; with $5 or more it is the usual fee (5%, at least $5), and Tow Service is still free. A new plot's expansion squares use the $7,600 step.

**Saves.** A brand-new profile's `worldVersion` is 1. Nothing here moves a parked truck; that waits until the map's version goes to 2. An old save keeps its cash, axes, trucks, placed pieces and the sections on its truck and on the ground. The shop prices that moved are the Steel Axe ($110, was $120), the Cobalt Axe ($2,500, was $3,000), frostwood planks (plan 120, plank scale 0.40) and the expansion step ($7,600, was $3,050). There is no trade window.

## Mining and crafting (8 October 2026, branch `phase-2/v1-m-mining`)

Not played in Studio yet. The furnace pad is the flat 30×24 at world (48, 0, −110). The mine mouth fallback is (150, 0, −150). If lane B's tagged `MineAnchor` / `Rubble` parts are in the place, those win and the fallback anchors are not used. One chamber of nodes spawns per tier (8 / 5 / 4), even if more anchors exist.

Picks are Tools, not shop axes. Swing with the tool button (mouse click, a phone tap, the gamepad's tool button). There is no extra ButtonR2 bind. The ore label is the existing hover tag (`HoverTag` / `HoverTagUI`), not a second billboard. The server writes `PickLevel` on the player (best owned pick). The rock only stores the required level (`HoverNeed`).

### PC

1. Walk to the pad. You should see SmeltingFurnace, a Prospector stall (the sign says PROSPECTOR, no price on the model) and a craft bench. E on the stall opens the shop. E on the bench opens Craft.
2. The first shop visit puts a Rusty Pick in the backpack and sets `PickLevel` to 1. Equip it. The chip at the top right reads `Rusty Pick · Lv 1`. Unequip it away from the mine and the chip hides.
3. Aim at an Iron rock within 60 studs. One tag, on that rock only. The name is Iron in the rust vein colour. The second line is `Needs Iron Pick` in red (`UITheme` Danger). Buy the Copper Pick ($450, one price). With `PickLevel` 2 the same rock reads `Iron Pick` in cream, with no Needs line. Coal (need 1) never says Needs for a Rusty Pick. No `$` and no `R$` on an ore tag.
4. Move the mouse off the rock. The tag hides in about a third of a second. Move from a shop box to a rock: the tag waits about 0.08s before it switches. Shop and log tags still show their own prices.
5. Click a Coal rock. One click, one swing, then a cooldown. The last hit spawns one chunk. A second click in the same moment does not spawn a second chunk. The chunk has a Pick up prompt. Carry it into the Ore Chute on the stall. Cash goes up once, by the chunk's stored value ($6), and the chunk is gone. The wood sell pad does not pay for ore.
6. With the Rusty Pick, click an Iron rock. A toast says `Needs an Iron Pick` and the swing does not start a cooldown (a Coal rock beside it still swings at once).
7. Buy a Bomb for $220 (the same number as dynamite). Short cash buys nothing. Equip it, stand within 8 studs of a rubble wall, click once. A spark shows for 3 seconds, then the wall's parts hide for everyone for 10 minutes. About 20 seconds before it reseals, dust appears. Crawl out (E) moves you toward the mine mouth, not deeper. If the wall reseals while you are just past its far face (within about 6 studs), Crawl out still works. Two clicks in the same moment spend one bomb.
8. Put a Copper chunk in SmeltIntake. With coal, one coal covers four chunks; without it, each chunk costs $2, once. About 3 seconds later one ingot appears and the chunk is gone. Leaving it there does not charge again. The same chunk cannot also be paid by the chute.
9. Craft bench: one row per recipe (icon, name, cost line, a 44×44 Craft button). Copper Lamp Post and Gold-banded Chest say Soon. B and Esc close the shop and the bench. You have to be within 12 studs of the bench, and the ingots and chunks have to be within 12 studs of it too. A stranger's log, even a closer one, is not yours.
10. Obsidian Pick: Heartstone is too hard for a Steel Pick, so the turn-in is 5 Timber Opal ingots (Opal is hardness 4) plus $50,000, at the stall. Four ingots are refused and stay in the world. Five are consumed, then the pick can be bought. The save still calls that turn-in `HeartstoneTurnIn`. `mining` on the profile is account-wide: a slot swap does not move the picks.

### Phone emulator (667×375)

1. The chip, the shop and the craft list sit in the top half, at least 12px from the edges, and the panel is at most 60% of the screen height. They do not cover the bottom-left thumbstick (left 40% of the bottom half) or the jump button (bottom right).
2. One row per item, 8px apart, in a scrolling list. The name is 16px (18px on a tall screen), not stretched. The cost is 14px under the name. Buy and Craft buttons are at least 44×44.
3. Tap a rock, or stand within 6 studs of one in front of you. The tag shows for about 4 seconds and is readable. One tap on the equipped pick is one swing.
4. In a cave, count PointLights: the lamp (only while equipped, range 12, shadows off) plus at most 4 glowing nodes, 6 or fewer in total, shadows off. Each ore rock is 8 parts or fewer. Live ore chunks on you stop at 40 (a toast names the one that did not fit).

### Xbox

1. With a pick equipped, aim the screen centre at a rock within 12 studs. The tag shows with no extra button, and it does not cover the swing or a target ring.
2. The tool button swings once per press. ButtonR2 is not bound by mining.
3. X on the Shop and Craft prompts opens the panel. The stick stays inside it. B closes it.
4. Crawl out works on X while your character is inside a sealed wall. A too-weak rock shows the Needs line and does not arm a swing.

Good: the five wood headline times in ECONOMY.md are unchanged (68 s, 7.9 min, 13.7 min, 51.4 min, 30.5 h). Mining ratios are in MINING.md (Hills 0.43 of Pine $17,136, Snow 0.57 of Frostwood $28,677, Gloam 0.67 of that same Frostwood). Steel or Lux at Gloam is about $10.7k/h. Obsidian is about $19.1k/h.

## Trees in the spawn area (8 October 2026, branch `claude/spawn-trees`)

Connor: "We need more choppable trees in the spawn area too, near the pad, by
the dealership. All over, it's a lumberjack game." The town used to have no
choppable tree at all: its pines, birches and maples are ornamental (in a
stone ring, `WorldPlan.Town().greenery`), and the real forest starts 190+
studs south. Now 54 real felling trees stand in and round it.

**What they are.** Ordinary section trees (`SectionTrees`): the same chopping,
the stump stays, the tree grows back. Woods follow the region
(`TreeFill.woodsNear`: oak and birch round the town, pine, maple and oak on
the Hills side), biome 'wild'. Each cluster is a small disc and its own regrow
zone `town:<site>` with a cap of its size (radius 16 at most), like the plot
rings. They are **not in BiomeData's counts**, so the economy model does not
see them: `lune run tools/economy` and `tools/economy1` are unchanged and
ECONOMY.md / ECONOMY_V1.md were not regenerated.

**Where (54 trees, 16 clusters; `Shared/TownTreeData.Sites` has each centre).**

| Where | Trees | Sites |
|---|---|---|
| South-west of the spawn pad, west of the Forest Path (45 to 95 studs from the pad, in sight down the path) | 7 | padSW1, padSW3 |
| Round the showroom hall and Land Office: the strip west of the hall past the Land Office and loading pad, two in front of the hall at its east end, behind it, east of it | 20 | strip1, strip2, forecourt, back1, back2, east1 |
| The town's west edge, by the Tool Shed, the General Store and the Hills Road | 10 | west1, west2, west4 |
| North: behind the sawmill, along the Snow Road, north of the General Store and the gondola station | 14 | mill, north1, north2, snowE |
| South of the plot road, east of the lot | 3 | roadS |

Woods: oak 27, birch 15, maple 6, pine 6. The Medium and High tiers add 20 and
31 more trees (see below); they are not planted. No tree stands in front of the
showroom's door or along its forecourt west of x 290: the lighthouse lamp has to
stay in view from the pad (WorldPlan.spec keeps every trunk 10 studs off that
line, and it runs along the front of the hall), and the Land Office, its queue,
the door path and the loading pad take the rest of the west wall.

**The layout rules** (`TreeFill.TownBlocker` / `TownWhy` / `TownGround`, the
numbers in `TownTreeData`). A town tree never stands: in the sell area
(x -60 to 60, z 80 to 140, hard empty); in the spawn lane (x -18 to 18, z 8 to
100) or within 22 of the pad; within 11 studs of a road's edge (every road,
including the Hills, Snow, Mill and Lot Loop roads and the homestead lanes);
within 7 of a TownPaint rect (street, plaza, paths, spawn walk, mill yard) or a
town floor; within 9 of a building (Tool Shed, General Store, showroom hall,
mill, sell station, gondola station, Land Office) or 14 of Murph's camp; within
12 of the parking lot or 8 of its pull-out lanes, 12 of a loading pad; within 12
of a shop door (and a clear apron in front of each door); in the Land Office queue; under the gondola's first 280 studs
(22 either side); within 11 of the line from the spawn pad to the lighthouse lamp; within 7 of a townsperson's walk or 11 of where one stands;
within 11 of an ornamental tree, 9 of a prop, 12 of a sign, 6 of a lamp; within
30 of a plot; on water or ground steeper than 0.5; on a boulder cluster, scenery
piece or landmark's disc. Trunks keep 12 studs apart (the forest's gap is 10)
and from every other tree, so a player or a truck passes between them.

**Regrow.** A "town:" zone's regrow spot is picked with `TreeFill.GroundFor`,
which is `TownGround` for a town zone and the old `Ground` for every other: the
general rule refuses the whole flat town (`GoodGround`), so without it a felled
town tree would never grow back. The same rules apply, so a tree never grows
back onto a road, a path, a door or the sell area. `SectionTrees.pickSpot`
calls it; nothing else about growing changed.

**Quality tiers.** `TownTreeData.Tiers` are `QualityBudgets`' names: low 54
trees, medium 74, high 85 (`Count`, held under `Budget` 60 / 90 / 100 by
spec). Trees are shared by every player on a server, so one list ships:
`ShippedTier = "low"`, a phone's. Medium and High are the same sites in
priority order plus more; `TreeFill.TownRings(taken, pause, tier)` plants any
of them and the spec pins that a lower tier's trees are exactly a subset of a
higher one's. Changing the shipped tier is one word (and a look at the phone
discs below). A fuller town only for Higher players would need a per-player
(client) tree layer, which is not built.

**Phone budget.** The three phone discs (640 studs round the spawn, the meadow
and the pines) were held to 1.7x the first trees in trees and parts. The fill
still is (the test now leaves the town's trees out of that); with the town's 54:
spawn 189 trees -> 314 with the fill (1.66x) -> 368 with the town (1.95x), and 7454 parts -> 12490 -> 14512 (1.95x), the
meadow 1.91x and the pines 1.78x, held under `TownTreeData.PhoneDiscMax` = 2.0.
Each tree is about 43 Instances (the section tree), so the town adds about 2,300.

**Load time** (Lune, same machine, three runs each; Roblox is slower, so use the
ratio). `WorldPlan.Trees()`: 1,225 trees in 8.7 / 8.8 / 9.0 s before, 1,279 in
8.7 / 8.9 / 8.8 s after. The town planner itself is about 40 ms warm (60 to 85 ms with
the obstacle tables built). The work stays inside the deferred forest planter
(`MapBuilder` `forestPlanter`, after the sell area, 12 ms slices, nearest the
sawmill first), so nothing was added before "world ready for players" and the
town's trees plant first. No new mesh, wood or budget: no change to
MeshKit.Preload, the section-tree builder or the WindSway budgets (nearest 16 /
24 / 32 trees). The `[Load] forest planned: N sites in X s` and `forest planted`
lines in Output show it in Studio; N goes up by 54.

**Look.** `bash tools/preview/shoot.sh spawn-trees [view]` (new scene: the town
plus every tree in x -300..520, z -140..380 as they plant at boot). Before
`preview/spawn-trees-before-N.png`, after `preview/spawn-trees-N.png` (gitignored,
render again to see them): 1 from the spawn pad, 2 the pad looking south down the
Forest Path, 3 the pad from the west, 4 the dealership door, 5 the dealership
and Land Office from the lot, 6 from the lot, 7 and 8 top down, 9 aerial,
10 the General Store. The window held 98 trees before and 154 after.

**Studio checks (Connor).**
1. Join. Stand on the spawn pad: the walk north to the mill, the sell area and
   the plaza are as before (no new tree in the lane, none by the sell pad).
2. Turn round and walk south down the Forest Path: choppable trees now line its
   west side, 45 to 95 studs from the pad. Chop one: the same swing, fall and
   stump as the forest. After a few minutes it grows back nearby (inside the
   cluster, never on the path).
3. Walk to the Dealership: trees west of the hall past the Land Office counter
   (55 to 70 studs from its door), one or two in front of the hall's east end, more
   behind it and to its east. The door, its path and the forecourt stay open. You can walk to the door and the Land Office counter and the loading pad
   with room to spare; a truck can drive the forecourt path and pull in.
4. Drive a rig out of the lot (north to the street and south to the Lot Loop),
   along the Mill Road and the Snow Road: no trunk in the way, trees stand back
   from the road edge. Rosa, Pip and Bram still walk their loops.
5. Stand in the gondola station queue and ride: no trunk or crown touches the
   cabin or its cable on the way out of town.
6. Fell every tree in a cluster and wait: each grows back after its wood's
   respawn time (45 s for oak to 3 minutes, with the 0.7 to 1.3 roll), never past the
   cluster's count.
7. A phone (Lower quality): the town looks fuller and still plays smoothly;
   send the `[Load] ready for play` and `forest planted` lines.
8. If a tree looks wrong (on a path, on a shop floor, in a queue), send its
   position: each site is one line in `TownTreeData.Sites`.

## V1 nature looks (8 October 2026, branch `phase-2/v1-g-nature`)

The PNGs under `previews/v1-g/` (listed in STATUS.md) are the looks to review. Trees there are the live choppable section trees. Rain blobs are the old puff; rain streaks are what the weather controller now emits.

Studio checks (PC, the phone emulator, and Xbox). Good looks like this:

1. Chop, fell, and watch a stump and a regrow. Same swing and the same logs as before.
2. In rain, the drops are thin slanted streaks in the world, not soft blobs stuck to the screen. On Lower quality there are fewer, shorter streaks.
3. Step into a shop, under a bridge, into a truck cab, and into the cave, the tunnel and the grotto. Rain, splashes and the rain sound fade within about a second. They come back within about a second of stepping outside. Prompts and the controller cursor still work in the rain.
4. Stand in steady rain for a minute. The air hazes a little and stays there; the sky does not fade to white. When the rain stops, or you step under a roof, the haze goes back to the clear-weather sky.
5. Rocks read as six shapes (round boulder, cracked boulder, stacked standing stone, slab, pebble cluster, mossy outcrop), tilted and partly in the ground. Meadow rocks have moss, snow rocks a white cap, the shore is sandstone, the volcano is dark basalt, the gloam is blue-grey, caves are wet dark stone. Plants and critters are not on roads, plot pads, shop floors or the gondola path. Ducks sit on water. A gull is on the coast. A snow fox is on the snow. A sky moth glows on the isles at night.
6. Lower quality stays smooth. A lanternwood's pods still read in a dark cave (neon, no extra light on a phone). Cave glow lights do not cast shadows.
7. Rock meshes (the uploaded Blender rocks): on the open grass, a rock is a real faceted stone with a green moss cap, not a ball. Walk round a few in the same meadow and you see two shapes of each kind (A and B). Moss or snow sits on the top of the stone, never floating above it or sunk inside it. Rocks are 0.62x, 1x and 1.45x, and the cap scales with them.
8. Ore rocks (once the mine uses them): coal, copper, iron, silver, gold and opal each show two seams of ore across a stone (opal's stone is mossy). Heartstone has red crystals and a red glow. The seams are visible from the front of the rock.
9. The mine mouth (needs Lane B's placement call, see the PR's cross-lane requests): a stone arch with a timber frame, two lanterns and MINE letters; its opening faces out of the hill, the tunnel runs into it, you can walk in, and you cannot walk through the rock around it.
10. Open the Output window and play: no `[NatureArt] ... mesh is missing` or `[MeshKit] ... did not load` lines for rocks, ore rocks or the mine mouth.
11. Phone (667x375): rocks and the mine mouth look the same at Lower quality; no frame-rate drop near a rock-heavy meadow.

## Saves by hand, and Unload base (8 October 2026, branch `claude/plot-save-switch`)

Connor: "with plots, they need a way to unload/save their base and switch to
another"; "it shouldn't automatically load a save ... when picking a save, if
that player has a plot, they pick a spot"; "restart save should be in
settings"; and, answering the first design: "I meant switching between saves,
and unloading your base with a button which also saves it, LT2 style."
Nothing here changes a price, a recipe or the economy model.

**Switching bases is switching saves.** The three whole-game save slots already
exist (cash, axes, plot, storage swap together); the SAVES panel is how you
switch. Nothing new was built for that.

**Join flow.** Quality screen (first time only) -> SAVE PICKER -> (only if the
picked save has a plot) PLOT PICKER with its camera, map and pillar -> world.
Each save row shows name, cash, best axe, "Plot, 12 pieces" or "No plot yet",
when it was saved. The save you left off on says "Last played", never
"Playing". PLAY on it changes nothing; PLAY on another is a normal swap
(commit wood, swap, rebuild, the usual 120 s save cooldown). No close button:
you choose. A player already standing on a pad (a swap from the SAVES button) is
not asked again and keeps their pad. The 60 s plot-picker timeout starts when
the picker is on screen (`PlotShown`), not at profile load. Order of screens:
`PickerSequence` quality, slot, plot (`Shared/JoinPickLogic`).

**Restart save** left the SAVES list (the confusing REDO). It is RESTART SAVE n
on the Settings GAME tab (n is the save you are playing): press once (arms and
says what is wiped), again within 5 s to do what REDO did. Greyed while the
save picker is up and during the cooldown; same server path, arm window,
cooldown and rate limit.

**UNLOAD BASE / LOAD BASE (SAVES panel, top button).**
 * While your base stands on a pad the button reads UNLOAD BASE. A confirm card
   explains: saved with this save, off your pad, pad freed, nothing lost or
   sold. Confirm -> the base's models and vehicle pads come down, anyone on the
   yard is set down outside, the pad is free for others, and you stay in the
   world with no pad. The base stays in that save's `profile.plot`
   (the record is not moved, copied or edited), the save is written at once.
 * While the save has a base but no pad, the button reads LOAD BASE: it opens
   the same free plot picker as a join (camera, map, pillar, any pad, the 60 s
   auto-assign once shown). The base lands there laid out exactly as before
   (plot-local studs).
 * Quitting while unloaded is fine: the save keeps the base, and the next join's
   save picker leads to the free plot picker as usual.
 * Cooldown `GameConfig.BaseCooldownSec` (120 s) between unloads, stored on the
   profile (`baseCooldownUntil`, account-wide); loading back is never cooled.
   Rate limit `BaseAction`. The remote carries only "unload" / "load".

Safeguards: the unload commits carried logs, the truck's load and the truck
into the save the same way a slot swap does; refuses (nothing changed, with a
toast) when logs or planks of yours lie on the plot, while another change is in
flight, during the cooldown, or with no pad; if the release throws, the base is
rebuilt on its pad and no cooldown is spent; if the player leaves in the middle
the save is whole before or after, never half. Vehicle pad models were never
taken down on a leave or a slot swap and were never restored after a join-time
pad claim: both fixed (`VehicleService.ClearPads`, the `assigned` hook).

Old Hank is as he was (buy a plot, pad picker for returning owners). The
earlier "crated bases shelf" design (profile.bases, Hank's Yes / No, BASES
panel) was removed; `ProfileSchema.Migrate` drops a stray `bases` field
idempotently and keeps `profile.plot`.

### Studio checklist
1. Join a fresh save: quality screen (once), then the SAVES list. Nothing loads
   by itself. The first save says "Last played" (or START), not "Playing".
   PLAY: you enter the world; no plot -> nothing else opens.
2. Rejoin on a save with a plot: quality skipped, save list, PLAY -> the plot
   picker opens (pillar, map, camera). Leave the save list open a minute first:
   no pad is taken. Then PLAY and leave the plot picker alone for 60 s: only
   now a free pad is taken.
3. Pick save 2 (another save) on the list: swap, no second prompt; if it has a
   plot the plot picker opens. Cooldown message if you just swapped.
4. Settings (GAME tab): RESTART SAVE n greyed while the save list is up. Press
   once (arms, says what is wiped), again within 5 s (the save restarts). The
   SAVES list has no REDO. Check with a gamepad and on a phone.
5. Build a few pieces and place a vehicle pad. Open SAVES: UNLOAD BASE is the top
   button (tap and A both work; B closes the confirm card then the panel).
6. UNLOAD BASE -> confirm: the house and pad models vanish, the pad sign says OPEN
   PLOT, cash and storage unchanged, you are still standing in the world. A
   second client can claim that pad. A second client standing on your yard is
   set down outside.
7. The button now says LOAD BASE (also after a slot swap away and back). Press
   it: the free plot picker opens; pick a DIFFERENT pad: the same layout stands
   there, pieces in the same relative spots, the vehicle pad's button works.
8. Unload, quit, rejoin the same save: save list -> PLAY -> plot picker -> the
   base lands on the pad you pick. Unload twice quickly: "Give it N more
   seconds". Load back is not delayed.
9. Drop a log on your plot, try UNLOAD BASE: refused with the loose-wood message.
   Pick it up or sell it and retry.
10. Slot swap mid-session keeps your pad and rebuilds its pads (no orphan pad
    models left on the old pad). Old Hank sells a plot exactly as before.

Not seen in Studio yet: the SAVES panel layout (the taller card and the new
button) on phone and TV, the picker after LOAD BASE, visitor set-down with real
raycasts, and the pad models after a claim.

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
- **UI-06** Dropping an axe needs a spare or better axe and two presses; the
  server keeps your last axe ("You need an axe to chop!"). (Superseded: the
  on-screen Drop axe button is gone; see "Drop axe controls" at the end.)
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
  Delivery), Truck to lot, stacked so the bottom one always ends
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

> The BUILD button, build mode and the Blueprint Store palette below were
> replaced by the hammer and physical blueprints (see the last section, "The
> hammer and physical blueprints"). The rest of this section (claiming,
> growing, what's there) still stands.

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
- [ ] (replaced by the hammer: its bar shows only on your plot; walking off ends it)
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
$110) and `Shared/LogicItems` (Wall Switch $100, Spark Lamp $150). all
nine are `unlock` boxes at Hearth & Home (buy once, place free; the box
costs what the piece did). The shelves run 19.6 studs, ten boxes a side (20
slots, 19 used); only kit pieces (walls, floors) are paid per placement.

Wiring (`Shared/WireLogic`, `SSS/LogicService`, saved in `plot.wires`): a
switch has Flip (E / ButtonX) and Wire (hold F / ButtonY). Wire links the
nearest free Spark Lamp or Door within 32 studs; press again for the next;
with none left it clears that switch. A lamp nobody wired stays lit. A wired
lamp or door follows its switches (any on). Switch positions are saved
(`plot.switches`, the uids that are on; Restore puts levers, lamps and
wired doors back when the plot rebuilds). The Wire remote carries (fromUid,
1, toUid, 1) or ("cut", uid); the client tool below uses it.

Wiring tool (`StarterPlayerScripts/WireTool`, rules in `Shared/WireToolLogic`):
BUILD bar > WIRE. Phone tap, PC click, Xbox crosshair + RT pick a piece;
pick a Wall Switch, then lamps or doors to wire them; CUT (X on Xbox)
clears the picked piece; B / DONE leaves. World prompts are off while it is
up. A thin gold line (max 40 Neon parts, reused) joins wired pieces on your
plot for the whole of BUILD mode; each switch model carries a `Wires`
attribute (target uids) so the client can draw it.

Plot visits: Settings > Visitors > VISIT A PLOT lists players here who own a
plot and whose `visit` flag lets you in; Visit sends `VisitPlot (userId)`.
`PlotService.Visit` re-checks (rate limit, owner online with a plot, not
you, `PermissionLogic.CanVisit`) and lands you on the first dry, road-free,
roof-free spot (raycast) around the plot's spawn pad. No cash.

Studio checks
1. Hearth & Home: 19 boxes, ten a side on the long shelves, none floating or
   through a wall, Bookshelf / Rug / Barrel / Crate / Fire Pit among them.
   Buy a Wall Switch, open its box on your plot.
2. BUILD menu: Bookshelf, Rug, Barrel, Crate, Fire Pit say "At the store"
   until bought, then place free. Place on phone (tap), PC (click), Xbox (RT, D-pad Right rotates).
   Overlap and plot-edge ghosts go red. Fire Pit glows.
3. Place a switch, a lamp 6 studs away. The lamp is lit. Hold Wire on the
   switch: "Wired to the Spark Lamp.", lamp goes dark. Tap Flip: lamp lights,
   lever tips. Flip again: dark. Hold Wire until "Wires cleared.": lamp lit.
4. Wire a switch to a Door (hosted in a door wall): Flip opens, Flip shuts.
   Put a block in the swing: the door stays shut and says why.
5. Leave and rejoin: wires are kept and every switch is where you left it
   (a lamp on an "on" switch is lit, a wired door is open).
6. Sell the switch: its lamp relights. A visitor without Interact cannot
   flip, without Build cannot wire.
7. WIRE tool. Phone: BUILD > WIRE, tap the switch (blue box), tap the lamp:
   "Wired.", a gold line appears; tap CUT: the line goes. Buttons are easy
   to hit. PC: same with clicks. Xbox: aim the dot at the switch, RT, aim
   at the lamp, RT, X cuts, B leaves; help text is readable on the TV.
8. Visit (two players). Settings > Visitors lists your friend; Visit on
   phone / PC / Xbox (D-pad, A, B closes) puts you on their plot, never in
   water or on a road. Turn their Visit flag off: the list drops them and a
   forced Visit says "That plot isn't open to visitors." 

## Boxed stores, every shop (box on a shelf, carry it, the keeper takes payment)

What changed:

- **The Dealership window is gone** (it was the last shop screen that sold
  with a Buy button). Trucks and trailers are the lot's boxes; the keeper
  at the counter takes payment. The three shop screens (Tool Shed,
  Dealership, Hearth & Home, plus the saws) are `shelf = true` menus: they
  only open if `GameConfig.BoxedStores = false` (the rollback).
- **The chop saw is a Tool Shed box** ($7,500, `ItemCatalog.ChopSawPrice`,
  unchanged). It waits in the same stock list as the sawmills
  (`sawmillStock`) until you place it from BUILD.
- **The BUILD palette is no longer a shop.** A sawmill, the chop saw or a
  furniture unlock you haven't bought says where to buy it ("At the Tool
  Shed" / "At the store"); PlotService refuses to charge for them there
  (`PlotLogic.Source` is the one rule, client and server). Kit pieces
  (walls, floors) keep their placing fee. Growing the plot to its next base
  tier moved to the Land Office panel, with the squares (the sign prompt).
- **The Robux shelf**: a gold-trimmed table across the back of the Tool
  Shed, one gold box per pass and pack StoreData lists (`Shared/RobuxShelf`
  reads StoreData and writes nothing). Carry a gold box to the counter, say
  Yes, and the client sends the same `BuyRobuxItem` intent the Store screen
  sends; `MonetizationService` checks it and shows Roblox's own dialog. The
  box goes back to its shelf. The STORE screen is still there (Instant
  Delivery's Use button lives in it, and it works from anywhere).
- **Tool Shed interior**: 28.5 studs deep (was 21), so two display tables
  and the Robux table fit with a wide aisle; the counter keeps its place
  from the door. The meshes are stretched 1.36x in depth to match
  (`BuildingArt.MeshStretch`). Hearth & Home's boxes now sit on its lower
  shelves' centre line. The Dealership and Hearth & Home keep their
  footprints (the Dealership has no room east: the loading pad and the mill
  road are 7 studs off; Hearth & Home is already 48 x 36).
- Preview: `bash tools/preview/shoot.sh stores` (roofs off, boxes on the
  shelves, a figure carrying a box down each aisle).

### Playtest checklist
- [ ] Dealership counter: no "Browse trucks" prompt; a truck box from the lot
      carried to the counter is offered by Dale, paid, and opens on your plot
- [ ] Tool Shed: boxes sit on the two side tables (not floating), walk the
      aisle carrying one (phone tap, PC, gamepad RT), set it on the counter,
      Tink offers it, Yes pays
- [ ] The gold ROBUX SHELF at the back: gold boxes with a tag that reads R$
      and then R$ plus the price once Roblox answers; a gold box on the
      counter: "Robux item. Go ahead?", Yes opens Roblox's purchase dialog
      and the box returns to the shelf; No does nothing; an owned pass says
      you already have it
- [ ] Chop saw box ($7,500): after paying, BUILD shows Chop Saw as Place;
      with none in stock the row says "At the Tool Shed" and placing is refused
- [ ] BUILD palette: no Grow row; the Land Office prompt on your sign has the
      Grow button above the squares
- [ ] The Tool Shed from outside: deeper at the back, same front; nothing
      clips the Water Tower or the Cart behind it; the loading pad behind it
- [ ] The Tool Shed mesh in Studio: the baked interior (workbench on the west
      wall) may show through the west table; tell Claude if it clips

## The Robux town board, bigger (arch, banner, marker)

- The board is 5.4 x 7 studs (was 4.6 square) at about (-20.5, 58.3), with
  a tall post either side, a green STORE banner across the top (readable from
  both sides) and a lantern on each post that lights at night (`LanternGlow`).
  It grows up, not out: Murph's camp ring and the street leave 7.6 studs.
  `StoreBoard.Footprint` covers the arch posts; the banner overhangs them.
- TownMarkers has a sixth chip, STORE (gold, market-stall icon), 19 studs
  over the board. On a phone from the spawn it is on screen at eye level and
  may ride off the top of the tilted camera views; it never lands on another
  chip. Preview: `bash tools/preview/shoot.sh town 17` (from the spawn) and
  `18` (close).

### Studio checks
- [ ] From the spawn walk the STORE banner and the chip over it are easy to
      spot; the board's lanterns are lit at night and dark by day
- [ ] Walk up: prompt Browse (E, ButtonX, tap) opens the Store panel; walk
      round the posts without snagging; Bram's walk and Murph's camp are clear
- [ ] The posters on the taller board fit with room to spare; the mesh frame
      (Studio) sits inside the arch posts, not through them

## Plots are bought at the Land Office (nothing is free)

- `GameConfig.PlotPrice` ($150) is the first plot. A new player is not given
  one: no picker at join, no timeout grant, the pad signs no longer claim. A
  Land Office counter in town (PlotService, beside the PLOT DISTRICT sign at
  about (147, 86)) has a "Buy a plot" prompt that opens the picker with the
  price. `ClaimPlot` names a pad; the server checks range to the counter and
  the pad, then `EconomyService.SpendCash`, then assigns (one claim, one
  charge). A short purse gets "You need $X more for a plot." and nothing moves.
- A save whose `profile.plot.claimed` is already true is untouched: it gets
  the free join picker (and its timeout) as before and is never charged. Loading
  another save that never bought a plot releases the pad.
- Price vs the economy (tools/economy): the plot is bought on foot before the
  Rustbucket, so the headlines hold only if Murph's plot step pays $150 toward
  the truck (`plot` step `rewardCash`). Unfunded, an unfunded plot pushes the
  Steel Axe past 8 minutes (a $200 one to 15.5 min). Cart soft-lock: the cart now stays open through
  the plot, build lessons and truck until cash covers plot + truck + $20.

### Studio checks
- [ ] Fresh save: spawn in town, no picker; Murph walks you through chop,
      drag, sell at the cart; the arrow then points at the Land Office
- [ ] Land Office counter (east of the truck lot, by the PLOT DISTRICT sign):
      the sign reads, E / A / tap on "Buy a plot" opens the picker showing
      "BUY PLOT $150"; Next/Previous walk the pads; B or "Not now" closes with
      no plot; a short purse toasts "You need $X more for a plot."
- [ ] Buy: cash drops by $150 once, you land on the pad, Murph pays $150 and
      the Rustbucket step follows; tapping Buy fast charges once
- [ ] A returning save (already has a plot) still gets its picker at join,
      free, and "Give me any open plot" works

## The hammer and physical blueprints (replaces BUILD; BUILD_SYSTEM.md)

- Building is the **Hammer**, a Tool every player always has (second hotbar
  slot, after the axes). A **blueprint** is a rolled plan you buy, carry, drop
  and pick up like an axe. Using one (click, RT, tap) consumes it and adds
  that building to your **blueprint book** for good. Using the hammer opens
  the book as a list; pick a row, a ghost follows your aim, place it (the
  hammer swings, knocks, dust), then fill a kit piece with planks as before.
  Aiming the hammer at something you built opens Move, Turn and Sell.
- The BUILD button, the old build palette and the Move/Sell prompts on every
  piece are gone. Holding the hammer on your own plot shows a bar:
  PLANS, LAND, WIRE, DONE (DONE puts the hammer away). On a phone a HAMMER
  button in the side column takes it out.
- Saved per slot: `blueprintBook`, `blueprintItems` (unused plans you carry),
  `hammer`. Existing saves are migrated on load, once and safely repeatable:
  every plan that was free to place before, every store blueprint already
  bought, everything already on the plot (a placed sawmill too), every box in
  stock.
- Prices, fees and refunds are as before. Sawmills and the chop saw are still
  Tool Shed boxes, spent on placing.

### Studio checks: the hammer
- [ ] New save, buy a plot, spawn on it: the hotbar has the **Axe then the
      Hammer** (slot 2). No BUILD button anywhere on the HUD
- [ ] Take out the hammer on your plot: the bar appears (PLANS, LAND, WIRE,
      DONE) and the hammer sits in the hand like a carpenter's hammer (steel
      head, claw behind, wrapped grip). Walk off your plot: the bar goes and
      one toast says to walk back; walk back on: it returns
- [ ] **PC:** click with the hammer: the blueprint list opens (Showing: All,
      Land, then Buildings, Decor). **Xbox:** RT does the same. **Phone:** tap
      the world with the hammer out, or tap PLANS; the HAMMER side button
      takes the hammer out when it is not in hand
- [ ] The list shows each piece's name, size and what it needs: "8 × 1 studs ·
      8 u³ of planks, one wood · fee $32". D-pad / stick moves between rows,
      A picks, B closes; the Showing row cycles All / Buildings / Decor /
      Machines and keeps the selection on itself
- [ ] Pick the Wall: the green/red ghost follows your aim. R (D-pad right,
      ROTATE) turns it; LT locks it and the LEFT stick flicks it round and
      up/down (the right stick stays the camera); RB/LB slide it; it is red with a reason over another piece,
      off your bought squares, or past the pad grid
- [ ] Place (click, RT, PLACE): the hammer swings back and strikes; at the hit
      a knock and a puff of dust at the piece; the fee comes out once; the
      piece is an empty ghost. Click again keeps placing walls. Q / B ends
- [ ] Another player near you hears the knock and sees the dust when you place
- [ ] Drop planks into the ghost wall: it fills as before (fill hints), the
      wood locks it, and it builds when full
- [ ] Aim the hammer at a built piece (crosshair on Xbox): the sheet shows
      Move, Turn, Sell. Move picks it up as a ghost; Turn is a quarter turn
      in place (red toast if blocked); Sell pays back and the piece goes
- [ ] A kit piece with wood in it: Move and Turn are greyed and say so; Sell
      says "Take apart (planks back)" and the planks drop on the ground
- [ ] Putting the hammer away, or taking out an axe, while a ghost is out
      ends placing. The axe still chops as before; the hammer never chops
- [ ] LAND on the bar, the Land row in the list and the sign's prompt all
      open the Land panel

### Studio checks: blueprints as items
- [ ] Buy a Small Shed blueprint at the General Store (box to the counter):
      the price is what it was, and a rolled plan (cream roll, blue wax seal)
      appears in your hotbar named "Small Shed Blueprint"
- [ ] Hold it and click (RT, tap): it vanishes, a toast says you learned it,
      and the Small Shed is now in the hammer list and places free
- [ ] Buying it again before you use it, or after: refused, nothing charged
- [ ] Hold a plan and press Drop (Q, Backspace, B on a pad, or a long
      press on the hotbar on a phone; two presses): it lies on the ground with a Pick up prompt; only
      you can pick it up; rejoin and it is back in your hotbar
- [ ] A plan you already know can still be held; using it says so and keeps it
- [ ] As the owner, `/gift <name> Blueprint Cabin` puts a Cabin plan in
      their hotbar (a non-owner typing it gets nothing)
- [ ] Sawmill / Chop Saw bought at the Tool Shed: the list shows "Rickety
      Sawmill · 1 in stock", places free; none in stock, no row

### Studio checks: old saves and the tutorial
- [ ] A save from before this change: join; the hotbar has a Hammer, the list
      has every piece the player used to be able to place, every unlock they
      had bought (check the Shed, Table, ...), and any sawmill already on
      the plot does not vanish. Join again: nothing changes
- [ ] New save tutorial: after the plot step Murph says to take out your
      hammer and click; opening the list moves it on; placing a piece moves
      it on; opening LAND moves it on. The three steps keep their order
- [ ] The Xbox audit (docs/qa/input-audit-2026-10-04.md): no new button is
      bound. The hammer is Tool.Activated (RT); the HAMMER side button has no
      pad key; the D-pad is only the placer's rotate (right) and the HUD's
      shortcuts as before
## Real stores: designed boxes, bigger shops, doors, showroom hall, open-the-box

What changed (branch `claude/real-stores`):

- **Boxes** are packaged goods: a kraft body, tape in the item's colour, a
  cream name label on the front (and on the side that faces the aisle), a
  category stripe over the label, a trim round the foot (`Art/BoxArt`, 6 parts
  at most). The Robux boxes are gold. They are much larger and scale with the
  item (`Shared/BoxSize`: a documented class table XS..XXXL, a hatchet is S,
  the chop saw L, a Millmaster XL, vehicles V1..V4, with XXL/XXXL kept free).
  The class comes from the plot footprint when the item has one, otherwise from
  its kind and price tier. `Shared/ShelfLayout` spaces boxes by their own
  width and depth, so a larger class never overlaps its neighbours.
- **Shops** are bigger and fitted out: Tool Shed 30 x 40.5, Hearth & Home
  49.5 x 39 (both were smaller), with display tables and shelf units sized to
  their boxes, an aisle runner, wood floor, ceiling beams, hanging lanterns and
  aisle signs. The Hearth price boards read their prices from the shop's own
  data (they were typed in, and one was stale).
- **Doors**: every shop has a real door (frame, leaves, an invisible blocker, an
  inside sensor and a closed sign). The one open/closed rule is the keeper's
  hours (`ShopHoursLogic.IsOpen`, the same clock as the sky and the Studio
  override). When closed the blocker collides and the sign reads "Closed -
  opens at 7 AM" (12-hour text lives in one helper, `ShopDoorLogic.FormatClock`).
  Nobody is shut in: walking up to the door from inside holds it open (the F
  prompt on the counter still does too), and it never shuts on someone standing
  in the doorway. Leaves are tweened on the client (`ShopDoorAnim`).
- **Dealership**: the open lot is gone. The Dealership is now one showroom hall
  (x 114 to 262, z 76 to 122, on the old approach lawn and lot, inside the same
  reserved area), a lobby with the counter at the west end and the door facing
  the road. Every truck and trailer stands on its own plinth in price order,
  side-on, behind its box, with a name and price sign and a lamp. Nothing is
  parked outside. The old showroom site at x 35 to 70 is empty lawn (its path and
  floor patch are gone from the town paint), and so are the old truck-lot path
  stubs. The hall's east end has a glass band and a glass skylight on purpose:
  the view from the spawn to the lighthouse crosses it (WorldPlan.spec checks).
  The TRUCKS marker is over the hall's sign, far east of the spawn, so it is no
  longer asked to be on screen from the spawn on a phone.
- **Buying hands you the BOX.** The counter charges once and gives the box; you
  open it with Interact (E, X on a gamepad, tap on a phone; works while holding
  it). Axes, gear and the lamp come out as an object you pick up (it goes to the
  hotbar or inventory); sawmills, the chop saw and blueprints unpack into your
  BUILD stock; trucks and trailers unpack onto your pad as before (the pad rule is
  unchanged). The empty box folds away and is destroyed. A paid box you do not
  open is saved with `pending` so it still owes its item; an unclaimed pickup is
  converted into your inventory after 5 minutes or when you leave; a box from an
  older save has no `pending` and only unpacks (its item was granted at the counter).
- Tutorial step ids are unchanged. The quest events `axeBought` and the "First
  upgrade bought" milestone now fire when the axe comes out of its box (that is
  when it is granted).

### Studio checks
- [ ] Tool Shed and Hearth & Home: walk in. The room feels like a shop: wide
      aisle, tables and shelves with boxes spaced evenly, nothing overlapping,
      lanterns lit at night, aisle signs readable from the door. Carry a box
      down the aisle with room to spare.
- [ ] Boxes look like cartons: tape stripe, a name label on the front and on the
      aisle side, a coloured stripe, a dark foot. Hatchet box small, sawmill and
      chop saw boxes big, vehicle boxes biggest. One price floats over each box.
- [ ] The Robux shelf: gold table, gold boxes each with a name label and one R$
      price over it, "ROBUX SHELF" sign hung above, no plinth board in front.
- [ ] The grindstone, its crank, the chopping block and the firewood stand
      clear of the walls with no poking through.
- [ ] Doors: set the clock to 22 (owner menu): Hearth & Home and the Dealership
      doors close smoothly and block you (barn leaves slide, general store doors
      swing, showroom shutter rolls down); "Closed - opens at 7 AM" shows. The
      Tool Shed shuts too since store-polish (6 AM to 8 PM; it used to stay open all night). Stand inside when it closes and walk to the door: it
      opens for you. Stand in the doorway at closing time: it waits for you.
      Set the clock to 8: everything opens, the sign goes.
- [ ] Dealership: walk in from the road. Eight bays in price order (Rustbucket
      first, Logging Rig last), each vehicle in its own paint on a plinth behind
      a big box, a sign with its name and one price, lit well, nothing parked
      outside. You cannot sit in or drive them. Carry a box to the counter in the
      lobby and buy it.
- [ ] Buy anything: you get the box, not the item. Press E / X (also while
      holding it): axes and gear come out as an object to pick up (E again; the
      axe lands in the hotbar), sawmills and blueprints appear in BUILD, a truck
      box unpacks on your pad. The empty box poofs. Pay twice quickly: charged
      once. Leave with an unopened box and rejoin: it is back, and still owes its
      item. Open it at someone else's range or as someone else: refused.
- [ ] Tutorial: Murph's steps still advance; the Rustbucket step needs the box
      opened on your plot (as before) at the Dealership (open 7 AM to 8 PM).
## Pumpkins on the ground, walkers face forward, calmer grass (claude/fix-pumpkins-npcs)

- Cause of the sunk pumpkins: EventService placed each patch with `PivotTo`,
  but a Model with no PrimaryPart pivots on its bounding-box centre, so the
  patch's middle sat on y = 0 and half of every pumpkin was underground. It now
  uses `Kit.placeAt` (origin on the ground) and then probes the drawn terrain
  under both pumpkins (`TerrainBuilder.LiftOnto`) and lifts the patch onto it.
  MapBuilder now runs the same `standOnGround` lift over town lamps, fences,
  props and signposts, so small town decor cannot sink either.
- `Shared/FacingLogic` (YawOf, Face, Direction, CFrameFacing) is the one place
  that turns a direction into a yaw for a -Z-front model; `NPCData.YawOf`
  delegates to it. `tests/FacingLogic.spec` checks that every route walker's
  look vector points along its motion for its whole loop. The walk lean was
  tipping walkers backwards (positive root pitch) and is now forward.
- Grass tufts: blades 0.62x as tall, muted tint and tips (they were bright
  yellow-green and read as glowing under the night bloom).

### Studio checks
- [ ] Join during the Halloween event (or set the event override): pumpkin
      patches beside the town lamps sit on top of the ground, whole, with a
      little ground showing under the round bottoms, near the spawn too
- [ ] Hay bales, crates, signs, fences and lamps in town rest on the ground
- [ ] Watch Rosa, Pip and Bram (and anyone else who strolls) for a full loop:
      they walk face first, turn at corners and at their pauses, never moonwalk;
      standing NPCs turn their front toward you when you are close
- [ ] Walkers lean slightly forward, not back
- [ ] Grass near the spawn and Murph's camp is knee height and a muted green,
      not neon, in the day and at night
- [ ] At night in front of the spawn: if a flat saturated blue plane still
      shows at the bottom of the screen, send a screenshot and the Output
## Plain plot ground (no grass on homestead pads)

- Pad Looks are Loam, Dry Clearing (Sand), Slate Flat, Pine Needles, Packed
  Clay, Red Earth (Mud): none is Grass. The terrain under every pad (the 200
  shelf plus a few studs of margin) paints Ground, so Roblox grows no grass
  blades there; the 56-stud blend outside the pad still fades into the
  country's grass. Decor (flowers, tufts, bushes) and trees were already
  blocked on the shelf and blend (`DecorBlocked`), now pinned by a test.

### Studio checks
- [ ] Walk onto several homestead pads: the yard is brown/sand/slate/red
      dirt, no grass blades, flowers or tufts on it, each homestead a
      different shade
- [ ] At the pad edge the dirt fades into grass over the blend; no hard
      green rectangle, no bare seams
- [ ] Rails, corner posts, bought squares, sign, apron and the build ghost
      still sit flush on the ground; trucks spawn on their pads
- [ ] Buying a tier or a square still resizes the pad; standing on the
      ground works (no falling through or floating)

### Trees round the pads
- [ ] Walk the rim of several homesteads: small clusters of 2-5 trees stand
      about 60-110 studs outside each pad (past the grass blend), denser on
      the forest side; none on the pad, the lanes, truck pads or haul roads
- [ ] Chop one: it behaves like any tree and regrows in its own cluster;
      plots inside the spawn/meadow/pine phone discs get none by design
- [ ] No hitch when running between pads (trees build in the usual chunks)
## Blender meshes are back on (axes, trees, NPCs, vehicles, plot kit, town)

What was wrong, in order of certainty:

1. **The town switch was off.** `GameConfig.TownMeshes = false` (set in #57 as a
   precaution) kept every building, shop and town prop part-built. It is `true`
   again. Dressed models are ground-snapped to their part-built twin
   (`TownMeshes.Dress`: a mesh more than 0.4 studs lower than the part art is
   lifted onto it, and one more than 8 off drops the dressing), so a mesh
   cannot sink under the map. Kill switch: `GameConfig.TownMeshes = false` and
   republish; in Studio set the workspace attribute `TownMeshes` (boolean) to
   try either for one run.
2. **Mesh loading failed silently.** Axes, trees, NPCs, vehicles, the plot kit
   and the town all load through `MeshKit.Create`
   (`AssetService:CreateMeshPartAsync`). When a load fails the art falls back
   to the part-built model and nothing said so. There is no flag or test hook
   that turns the axe, tree, NPC or vehicle meshes off, and none of those
   files changed after #50, so a load failure is the only way they vanish. That
   is almost always asset permission: the ids were uploaded by the creator
   account `Elucidhealer618`, and a mesh only loads for an experience that
   account allows. MeshKit now retries once, warns with the engine's own error
   text, counts loads and failures, and stops asking after 8 misses in a row
   with none loaded (each miss is slow). The `[MapBuilder] build check:` line
   and a second line after the build print the totals. `ItemMeshes.LoadAsync`
   (plot kit) now loads through MeshKit too, so it gets the same retry and
   logging.
3. **Shelf displays are boxes by design.** Since #42/#51 every shop shelf holds
   a plain box with a price tag (`BoxService`), not a model of the axe. That is
   not a mesh failure. The axe model shows in your hand and dropped on the
   ground; a mesh preview on the box is a stores-art decision.

### What Connor must do in Creator Hub (only if the Output says meshes failed)

Look at the Output when the server starts for `[MapBuilder] build check:` and
`[MeshKit] mesh <id> did not load (...)`. If it says `0 mesh assets loaded`:

1. Open Studio **signed in as `Elucidhealer618`** (the uploader), or as an
   account with Team Create edit on this place. Another account cannot load them.
2. Creator Hub > Creations > Assets (Models and Meshes) > open an asset >
   Permissions (Sharing). Allow this experience (Timberline Tycoon). Do it for
   every uploaded asset, or move them to the experience owner (a group-owned
   experience needs group-owned assets).
3. Moderation state must be Approved (the data files say they are).
4. Quick test in the Studio command bar, with the Rusty Axe haft:
   `print(pcall(function() return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri("rbxassetid://125228989315064")) end))`
   Expect `true  Instance`. A `false  <message>` is the real reason.
5. Ids to check first (one per kind; the rest follow the same rule): axe haft
   `125228989315064`, Steel Axe head `139649051325358`, oak trunk section
   `106240781110764`, oak crown `104687332442263`, plot Wall `85233243499195`.
   All ids live in `Art/AxeModels`, `Art/TreeModels`, `Art/TownModels`,
   `Art/NPCMeshes`, `Art/VehicleMeshes`, `KitMeshData` and `ItemMeshData`.

### Studio checks
- [ ] Output at start: `[MapBuilder] build check: uploaded town meshes ON,
      axe/tree/NPC/vehicle/kit meshes: N mesh assets loaded, 0 failed` and the
      same totals after "World built". Any `[MeshKit] mesh ... did not load`
      lines name the failing id and the reason.
- [ ] Hold each axe (Rusty to Lux; the Hermit's Maul is part-built): the Blender
      haft and head show; swing the Lux Axe and see the trail.
- [ ] Trees of every wood: meshed trunk and crown; chop a section and the log
      falls as before; the tree stays cuttable above the cut.
- [ ] Town: sawmill, shops, signs, roofs and floors sit on the ground and signs
      read. If something looks wrong, set the workspace attribute `TownMeshes`
      to false (or the config) and tell Claude which model.
- [ ] Plot kit, the plot sign, corner posts and rails, NPCs and trucks.

### Blender in the cloud session
Not installed here (`which blender` is empty), but possible: `pip download bpy`
works through the proxy (bpy 5.0.1 wheel for Python 3.11, about 375 MB) and apt
lists `blender` 4.0.2. Headless `bpy` can build and export FBX/GLB here; the
upload to Roblox (Creator Hub or Studio's Asset Manager) has to come from
Connor's machine because uploads need his login.
## Felling fix: the cut decides where the tree falls (claude/fix-felling)

Cause: #36 made a cut through the ground section free the whole rooted
section ("no sliver, no stump"), so any cut on the lowest trunk section pulled
the entire trunk out of the ground. Now the first cut through the root splits
it at the hit like any section: the stump stays anchored and rooted, only what
is above the cut falls and gives logs. The stump times out after the wood's
`respawnSec` (0.7 to 1.3x) and the site regrows at a new spot in its zone;
cutting the stump through takes it at once. Also in this change: a felled
trunk is one rigid body (speeds capped by `FallLogic`, no self-collision
between pieces freed together, starts a hair above its stump), dust only for a
trunk landing (a limb just thuds), a layered procedural fall sound
(`FellSound`), and a swing pose that is re-applied just before each frame and
falls back to tipping the tool grip.

### Studio checks
- [ ] Chop an oak low (ground section): a stump about knee high stays in the
      ground with a cut face; the trunk above falls away from you and gives logs
- [ ] Chop higher (aim at the upper trunk): the stump is taller, the top falls
- [ ] Chop the stump again: it goes, and the site regrows after the respawn time
- [ ] Try a birch, a pine, a Skyroot or Lumenwood, a small tree and a big one
- [ ] A tree on your plot and a tree in a dense forest: same behaviour, and the
      falling trunk does not push or fling neighbours
- [ ] The trunk topples as one piece, no pieces flying apart, logs stay together
- [ ] Sound at your ears: a creak, a crack and a whoosh as it goes, a heavy thud
      with dust when it lands; 3D (louder close, quieter far); a falling limb
      thuds but throws no dust cloud
- [ ] The axe swing plays on the published game (not only in Studio); if it
      cannot pose your arms, Output shows "[SwingPose] no arm joints found" and
      the axe itself tips in the hand
- [ ] No smoke puffs where the cursor or aim point is while you chop
- [ ] To use your own fall recording: upload it (Creator Hub, Audio), then set
      `GameConfig.FellSoundId = "rbxassetid://<id>"`; it replaces the layered
      sound and plays at the landing
## Load time (LOAD-01): the world no longer waits for its forest

What changed: the forest (about 1,400 trees: the planning, then a skeleton and
about 43 Instances each) is planted after the sell area goes in, nearest the
sawmill first, about 20 ms of work a frame, so GameServer starts and your save
loads while it grows in. The tutorial grove, the isles' Lumenwood, the town and
the terrain are still done first. The client's filler-forest plan (one step of
a second or more that froze the client) now waits until you are in the game.
The terrain yields by time, not one frame per chunk. Every phase prints a
`[Load]` line.

### Studio checks
- [ ] Cold Play: the branded loading card fades into the town noticeably sooner
      than before; you can move and chop at the tutorial oaks at once
- [ ] The forest fills in round you in the first ten or so seconds (trees near
      the sawmill first, far biomes last). Walk to Gloam Hollow (by day: no
      trees, at night: trees); Output shows `[Load] forest planted: N trees`
- [ ] A tree chopped early still falls and drops wood; figured bark clues
      (burl, etc.) still appear on late-planted trees; Murph's steps unchanged
- [ ] No red/orange Output. `[MapBuilder] build check:` line still there
- [ ] Copy every `[Load]` line from the server Output (and the client's) and
      send them: the numbers say where the time goes now
## Old Hank, the plot salesman at the Land Office

- An old farmer stands behind the Land Office counter day and night (no shop
  hours, never sleeps). Data: `Shared/PlotSalesmanData` (his offers and price
  talk), roster entry `OldHank` in `NPCData`, Talk prompt wired by
  `PlotService.HookSalesman`. Talk and the counter's "Buy a plot" prompt open
  the same picker; the server charges `GameConfig.PlotPrice` once. To sell
  something else through him, add an offer in `PlotSalesmanData.Offers` and a
  handler in `PlotService`'s `SALESMAN_OFFERS` (steps are in the file header).
- New: `CharacterArt` hat style `straw` and spec flag `hayStalk`.

### Studio checks
- [ ] Walk to the Land Office (east of the truck lot): an old man with a
      straw hat, grey beard, hay stalk in his mouth, plaid shirt and overalls
      stands behind the counter facing the street; a pitchfork leans on the
      counter's end and a hay bale sits beside it
- [ ] He looks around now and then; his bubble names the plot price ($150,
      one number); wait through a night (or set the clock to 3:00): he is
      still standing there, no Zzz
- [ ] Press E / ButtonX / tap on Talk at him: the plot picker opens showing
      the price; B closes it with nothing charged; buying charges once
- [ ] The counter's own "Buy a plot" prompt still opens the same picker
- [ ] A player who already owns a plot talks to him: a toast in his voice, no picker
- [ ] You can't walk through the counter; he is not shoved and doesn't fall
      over when you run into him; his prompt and the counter prompt don't overlap badly
- [ ] The tutorial plot step still shows the amber arrow at the Land Office and pays as before
## HUD corner, 12-hour clock, owner time tools, dialogue card, sawmill spin

- The corner chips (STORE, the clock) now share the cash row's strip in the
  top bar when it fits (`HudLayout.CornerInBar`), else sit 4 px under it. The
  clock reads "Day 5:17 AM" / "Night 10:10 PM" (12-hour; the Day/Night word is
  the Gloam Hollow's day or night, there is no day counter). Shop hours read
  "7:00 AM" / "9:00 PM" everywhere (`WorldTime.Format`, `ShopHoursLogic.FormatHour`).
- Owner time tools (`/timespeed`, `/settime`, `/timereset`, menu rows). Not saved.
- The shopkeeper card (Yes / Close) sits above the hotbar (`DialogueData.CardBottom`).
- The sawmill blade and bullwheel turn every frame by dt, slower (3 rad/s).

### Studio checks
- [ ] PC: STORE and the clock sit in the top bar beside the cash plaque, clear
      of Roblox's menu and chat buttons; resize narrow: they drop under the bar
      with no overlap. Phone emulator (with a notch): nothing under the notch
      or the top bar. Xbox / TV: not off the safe area.
- [ ] The clock counts 12:00 AM ... 11:59 AM, 12:00 PM ... 11:59 PM, then 12:00 AM.
      Night/Day word still flips at dusk and dawn. Walk to Hearth & Home before
      7 AM: the keeper says "opens at 7:00 AM"; the door sign reads "Open 7:00 AM to 9:00 PM".
- [ ] Owner (you only): `/settime noon`, `/settime 6pm`, `/settime midnight`
      jump the sky and the corner clock; `/timespeed 60` runs a day in about
      24 s (sky, lamps, shop doors follow); `/timespeed 1` slows it; `/timereset`
      returns to real time. Another account typing these gets nothing.
      Stop and restart the server: time is real again (not saved).
- [ ] Xbox: open the owner menu (OWNER or L3 + R3); D-pad down to Time speed
      and Set hour (the panel scrolls), A on SET SPEED / SET HOUR / RESET TIME;
      B closes. On a phone the panel fits and scrolls.
- [ ] Knock on a closed shop / talk to a keeper: the card shows ABOVE the axe
      hotbar on PC, phone and Xbox, Close (and B) works, nothing overlaps the tool bar.
- [ ] The sawmill blade turns smoothly and slowly, on High and on Low graphics
      (Settings), in town and on your own plot's sawmill.

## Short tutorial and fewer pop-ups (6 October 2026)

Connor's feedback: the tutorial was far too long (it walked through every axe)
and there were way too many pop-ups.

- **Eight steps, not sixteen** (`TutorialData.StepsV2`): chop a tree, drag a
  log, sell it at Murph's cart, buy a plot at the Land Office, place one item
  from the Blueprint Store, buy the Rustbucket box, place its pad, press the
  pad's button. The tutorial ends when the truck rolls out. Retired (kept as
  ids in `TutorialData.RetiredV2`, never reused): build, land, load, mill,
  loads, loads2, loads3, steel (and the earlier plant).
- **Saves midway** (`TutorialData.ApplyOrder`, order 6): a save on build goes to
  place, on land to truck, on load / mill / the sell-more loads / steel the
  tutorial is simply finished (`QuestService.Start`); finished stays finished.
  Progress toward a cut step restarts at 0.
- The next axe is one non-blocking line on the tracker after the tutorial
  (`NextGoal`: "Buy the Steel Axe ($160)", arrow to the Tool Shed) and Murph's
  farewell mentions the sawmill and Tink's Tool Shed.
- **Notice policy** (`Shared/NoticePolicy`, used by `HUD.Toast`): critical
  errors always show; at most two toasts and one non-critical at a time; a 1 s
  cooldown; no repeats of the same text within 8 s; a short queue (4) that drops
  the oldest low-value one first; during the first-sale flow (tutorial step 1
  to the cart sale, and while the save loads) only errors show. Ambient town
  chatter (NPC bubbles) is also quiet then; Talk still answers. The Studio
  stopwatch no longer pops toasts (`MilestoneService.ToastStopwatch`, off). The
  "put your axe away" toast shows once per session. "Murph chipped in" is not
  toasted for the cart sale (the plot card says it).

### Studio checks
- [ ] Fresh save. Count the pop-ups from join to the truck rolling out. Expected:
      Murph's card and the tracker for each of the 8 steps and the arrow;
      no toasts while you chop, drag and sell the first log (only errors,
      e.g. too far away); no "Sold 1 log" or "Murph chipped in $25" toast on
      that first sale; one "Murph chipped in $175!" toast on the plot; no region
      names, Field Guide, daily or stopwatch toasts before the tutorial is done.
- [ ] After the truck rolls out: the tracker shows "Buy the Steel Axe ($160)" with
      the arrow; Murph's farewell says to sell wood at the sawmill and visit Tink.
      There is no step about the load, the mill, the sell-more loads or an axe.
- [ ] Skip tutorial (tap twice) still works on any step and pays nothing.
- [ ] Mash a chop out of range: "Too far away" still shows (not twice at once).
      Try to buy something you cannot afford: the toast shows.
- [ ] Walk through town after the tutorial: at most one non-error toast at a time,
      a second after the first; walking region to region does not stack names.
- [ ] Old save midway (set `tutorialStep` with `tutorialOrder = 5` in a test
      profile): on "build" you land on the place step, on "mill" the tutorial
      is finished, a finished save stays finished.

## Murph's cart removed (6 October 2026)

Connor: the cart was only used once and was clutter after. The first sale is now
at the sawmill's sell pad like every later one.

- **Gone:** the cart model, its sign board and `CartZone` (MapBuilder), the cart
  gate in SellService and GameServer, `TutorialGrove`'s cart rules (the module
  keeps only the three grove oaks), `ProfileSchema.UnstickCart` and the
  `cartVolume` / `cartUsed` fields (old saves' stray keys are harmless), the
  `murphCart` beacon. The sawmill pays by volume with no cap and no minimum, so
  nothing can soft-lock a new player (`tests/TutorialGrove.spec` checks that one
  small oak plus the $20 start and Murph's $25 and $175 buys the plot and the
  $100 Rustbucket).
- **The `sell` step** keeps its id and place (3 of 8): "Sell your first load at
  the sawmill", beacon `sellPad` (the arrow points at the sell zone; with no wood
  to sell it still points at a tree first). A short-of-cash arrow for the plot or
  truck also points at the sell pad. Saves on that step just continue.
- **Economy:** the model's first sale walks the real distance from the nearest
  grove oak to the pad (about 50 studs, was 80): first sale 66 to 61 s, Steel Axe
  7.7 to 7.3 min, first $1k 13.5 to 13.1 min, Cobalt 51.2 to 50.7 min, full plot
  30.5 to 30.4 h. ECONOMY.md regenerated, ECONOMY_V1.md unchanged.

### Studio checks
- [ ] Fresh save: chop an oak in the grove, drag the log (axe away); the arrow
      points at the sawmill's sell pad (SELL LOGS HERE, top of the street).
- [ ] Set the log on the pad: it sells, no "Sold" toast during the tutorial, and
      the plot card says "That sale's yours" with the $25 in your wallet.
- [ ] Walk to Murph's camp and the grove: no cart, no "MURPH BUYS" board, only
      the three oaks and Murph by his fire. Murph's tips still read fine.
- [ ] Buy the plot and the Rustbucket box with only sawmill sales.
- [ ] An old save sitting on the sell step: the arrow now points at the sell pad.


## Store polish: counters at the back, bigger spaced-out shops, a bigger showroom (claude/store-polish)

Connor's notes after playing the real stores (#82), plus the follow-ups he sent
while the branch was open.

- **Counters at the back.** In every shop the counter (and the keeper behind it)
  is against the far wall, so you walk in past the shelves to pay. Tool Shed:
  counter 13.6 studs in from the middle, the gold Robux table behind the keeper
  against the back wall. Hearth & Home: counter 15.3 in. Dealership: in the
  lobby column, against the back wall. The keeper's spot is still derived from
  the Counter part (`NPCData.BehindCounter`), the buy prompt, ShopPoint and the
  CounterLogic zone follow the Counter, so only the fallbacks moved. The
  tutorial's step ids and beacons are unchanged.
- **Bigger shops.** The Tool Shed is 45 deep (was 38.4) and Hearth & Home 43.5
  (was 39); both shelf layouts were shifted back by the extra depth so the front
  clearance is the same.
- **The Dealership showroom**: inside 154 x 64 (was 142 x 43), a 26-stud lobby
  at the west end (door in front, counter at the back wall), then two rows of
  plinths (front row 5 vehicles, back row 3, price order) with a **clear 14-stud
  central walkway** between them. Each vehicle box stands ON its plinth at the
  edge facing the walkway, the vehicle beside it; nothing but a thin price sign
  stands in the walkway. A ceiling spot over every bay, marble floor, slate
  border, yellow edge stripes and blue bars down the walkway, banners, brochure
  racks, reception chairs, plants, flags. Nothing parked outside.
- **Spaced-out town.** The Tool Shed moved west to x -84 (front still z 95.2,
  outside the sell pad's keep-out x -60 to 60, z 80 to 140); Hearth & Home moved
  behind it (z 165.5 to 209, x -124.75 to -75.25) with a 20-stud lane between,
  its path up the lane west of the Tool Shed; the Dealership hall moved to x 181
  to 336, z 96 to 162, clear of the Land Office (147, 86) and the PLOT DISTRICT
  sign (148.5, 76). **The Climb plot moved 55 studs north (z 345)** so the hall's
  lawn can be 64 deep (PlotLogic.spec keeps a shelf's blend 66 studs off the
  reserved lawn). Loading pads, TownFloors/TownPaint, the flat zone, shop paths,
  props, greenery, signs' neighbours, NPC fallbacks and the three markers moved
  with the shops. The re-laid town: `bash tools/preview/shoot.sh town 11`.
- **Signs.** Every name board stands on posts at least `BuildingArt.SignRise`
  (3 design studs, 4.5 on the scaled shops) over its roof; the floating markers
  (TownMarkers) reach 19 to 32 studs over the counter part and clear the boards
  and roofs. `tests/StoreLayout.spec` checks the bottoms (2.5 over the roof).
- **Floors** (`ShopInterior`): Tool Shed warm WoodPlanks with darker planks, a
  dark border and the red runner; Hearth & Home honey boards with a green border,
  a runner and a rug; the showroom polished Marble with a slate border, a pale
  walkway lane with yellow stripes and blue bars. Three non-coplanar layers
  (0, 0.06, 0.12 over the floor), so nothing z-fights.
- **Real axes on the Tool Shed rack**: eight `AxeArt.Build` models (the same art
  as the held tools, uploaded meshes with the part-built fallback), in ladder
  order, each with a name and one price plate. No glow lights on the rack.
- **The water tower** stood inside the Tool Shed (the WaterTower prop at
  (-58, 126) and the Cart at (-71, 124), both inside the lot). Moved out
  (tower (-56, 188), cart (-66, 200)); `StoreLayout.spec` checks no prop, bush,
  lamp, sign, camp or station is inside a shop's footprint.
- **Showroom light** down about 30%: strips 1.0/26 to 0.7/18, plinth lamps
  1.4/17 to 1.0/12, spots 0.65/20, strip neon dimmed. `ShowroomLight` holds the
  numbers; the spec pins every showroom Light at or under 1.0 brightness and 22
  range. The two sign goosenecks are the same on every shop.
- **Tool Shed hours**: 6 AM to 8 PM (`ShopHoursLogic.ToolShedOpen/Close`). It
  closes, the keeper sleeps ("Zzz... the shed opens at 6:00 AM..."), the door
  shuts with "Closed - opens at 6 AM". The post-tutorial goal says "Buy the Steel
  Axe ($120) - opens at 6:00 AM" while it is shut. `/settime` still works (the
  clock override feeds `ShopHoursLogic.Now`).
- **More detail** (all looks only, `ShopFacade` outside, `ShopInterior` inside):
  windows with frames, sills and flower boxes, awnings or a canopy, doormats,
  planters, benches, barrels and crates, sandwich boards with the hours,
  chimneys and roof units; price tags on every shelf item, hanging goods from the
  beams, pegboards, posters, coat hooks, stools, plants, bins, crate stacks, a
  back-room door in each shop, and at every counter a bell, a balance scale, a
  receipt spike, jars and a stool for the keeper. Part budgets raised on purpose:
  Tool Shed 650, Hearth & Home 340, Dealership 300 parts per shop model
  (`BuildingArt.spec`), `GameConfig.StorePartBudget` 450 to 900.
- **Side fixes**: `NPCService.frontAlong` ignores looks-only parts out front when
  deciding who is outside a closed door; the boulder clusters re-seeded
  ("boulder clusters 3") and every new tree keeps off them (`TreeFill.Ground`);
  the Tool Shed sign mesh is no longer stretched with the barn.
- **Pins re-sampled on purpose** because the town moved and The Climb moved:
  Terrain height fingerprint, DecorCover, country stands (481 now), TreeFill and
  FOR-04 hashes, edge-tree count (71).

### Studio checks
- [ ] Walk into the **Tool Shed** from the street: the barn doors, planter-free
      yard (grindstone and block), a barrel and crate by the west wall; inside,
      the tables and shelves to the sides, the red runner down the middle to the
      **counter at the back** with Tink behind it and the gold Robux shelf
      behind him; eight real axes on the wall rack, each with a name and a price;
      a brown back-room door on the east wall near the back. The name board is high
      over the roof on its posts.
- [ ] Carry a box to the counter: the buy card appears at the counter only, the
      keeper asks, pay, open the box. Same at Hearth & Home (counter at the back).
- [ ] At night (set the clock to 21:00 with `/settime`) the Tool Shed is shut like
      the others: barn doors closed with "Closed - opens at 6 AM", Tink asleep with
      Zzz; at 06:00 it opens. The goal line after the tutorial says when it opens.
- [ ] **General Store**: awning, windows with flower boxes, bench, sandwich board;
      its path runs up the lane west of the Tool Shed. The marker over it
      ("GENERAL STORE") is up over the roof, east of the board.
- [ ] **Dealership**: walk in from the street: lobby, the counter at the back wall
      with Dale behind it; the vehicles on plinths in two rows with a wide clear
      aisle; every box sits on its plinth, the price sign by it. Buy a box at the
      counter, open it: the pad flow is unchanged. Nothing is parked outside.
- [ ] The **Land Office** counter, Old Hank and the PLOT DISTRICT sign are in front
      of the showroom lawn, clear and visible; the way from the road to every door
      is open (the path to the showroom door, the lane to the General Store).
- [ ] At night the showroom is noticeably calmer than before and similar to the
      other shops; the vehicles still read.
- [ ] The sell pad beside the sawmill (x -60 to 60) has nothing built on it.
- [ ] No water tower or cart inside the Tool Shed; they stand behind the shops.
- [ ] Floors: no flicker or z-fighting on any floor; planks, borders and runners look
      clean from standing height and from the camera pulled back.
- [ ] Phone: from the spawn the AXES, GENERAL STORE and GONDOLA markers show
      without overlapping.
## Owner hub (branch `claude/owner-hub`)

The owner menu is now a hub: PLAYERS / GIVE / WORLD / SELF tabs, a Find-a-tool box, one shared player pick, a status strip, confirmations, and an Xbox order with LB/RB tabs. Chat commands are unchanged and there are new ones (OWNER_TOOLS.md). Paste your UserId into `AdminLogic.OwnerUserIds` first (or test in Studio, where you count as owner).

Studio checklist (PC, then phone emulator, then Xbox/pad if you can):

- [ ] Only you see the OWNER button. With a second test player (Test tab, 2 players) their client has no OWNER button and no AdminUI in PlayerGui.
- [ ] OWNER opens the hub; X, Esc and B close it; L3 + R3 toggles it. Nothing overlaps at any window size; phone emulator: every button is a fingertip tall and the body scrolls.
- [ ] PLAYERS: the list shows everyone (you first, "(you)"); tapping a name ticks it; the strip says "Player: <name>". Step with the arrows on PLAYERS and GIVE: the same player stays picked. When that player leaves, the pick falls back to someone else.
- [ ] GO TO, BRING, HEAL, FREEZE (press again unfreezes), STATS (one line of cash, plot, tutorial, items) each answer in the strip (green when it worked). RESET TUTORIAL restarts their tutorial. KICK and BAN: the first press turns the button amber "SURE? ..." and does nothing; a second press within 4 seconds does it; picking another player first starts over. You cannot kick, ban or freeze yourself (red line).
- [ ] GIVE: chips pick the amount; typing `10k` in Custom amount overrides them and the label says Amount: $10,000. GIVE CASH and TAKE CASH move the cash (TAKE and SET CASH need a second press). Cash above $2,000,000 stops at the cap. UNLOCK ALL BUILDINGS: they can place any building from the hammer's list.
- [ ] GIVE, free items: TYPE steps through All, Recent, Axe, Gear, Sawmill, Machine, Blueprint; the search narrows the list as you type; tapping an item ticks it and the GIFT button names it; GIFT puts it in their hotbar (a Blueprint is a rolled plan). The item then shows under TYPE: Recent.
- [ ] WORLD: the speed chips plus SET CLOCK SPEED, the hour chips plus SET HOUR and RESET TIME change the sky as before (this server only). Type a message and press ANNOUNCE: everyone gets a toast. Tapping a preset fills the box. SHUT DOWN SERVER asks twice, then kicks everyone.
- [ ] SELF: SUPER RUN, GOD MODE (take fall damage or touch a hazard: no damage; press again to turn off), GO TO SPAWN. LAST ACTIONS lists the last eight results, newest first. Output has an `[Admin] <you> (<id>): ...` line for each.
- [ ] Find a tool: type `kick`, `teleport`, `restart` in the title box: matching tools show over the tab with the picked player; clearing the box or tapping a tab goes back.
- [ ] Xbox: D-pad up from the first body button reaches the tabs, then the search/close row; left/right stay in a row; up/down land on the nearest button in the next row; the selected button has the amber ring; the body scrolls so it stays in view (check the end of a long item list); LB/RB change tab; B closes. If scrolling jumps oddly, say so: it is the safety net over Roblox's own scrolling.
- [ ] Chat still works: `/give Bob 100`, `/god`, `/stats Bob`, `/admin`. Someone who is not you gets nothing from any of them or from the hub (a test player cannot even see it).

Delegation checks (owner hub; use two test players, the second one is the delegate):

- [ ] DELEGATES tab (owner only): pick the second player, role MODERATOR, 1 HOUR, GRANT. Their client now shows a MODERATOR hub titled DELEGATE with only PLAYERS (go to, bring, freeze, stats, kick, ban) and WORLD (announce); no GIVE, no SELF cash tools, no DELEGATES tab. The list shows them with REVOKE.
- [ ] As the delegate: kick or freeze a third player works; BAN lasts at most 1 hour (FOREVER is refused with a red line); anything aimed at you (the owner) is refused ("You can't use that on the owner"); chat `/give`, `/shutdown`, `/delegate` do nothing for them.
- [ ] Your audit list (SELF tab, LAST ACTIONS) shows each of their actions with a `>`; Output has `[Admin] DELEGATE ...` lines with both ids.
- [ ] REVOKE: their hub closes at once and the button goes away; their next request is refused.
- [ ] Expiry: grant 1 HOUR and use `/settime`-style clock tricks is not possible, so test SESSION: have them leave the server and rejoin, they are no longer a delegate.
- [ ] CUSTOM: tick only Kick and Heal, GRANT: their hub shows only those. Try ticking cash or shutdown: they are not on the list.
- [ ] TESTER: choosing it shows a red panel with the warning; GRANT turns amber "SURE? GIVE FULL POWER"; only the second press grants. The 'until the server closes' choice is gone. Their menu shows a red TESTER banner; give cash works; TAKE CASH / BAN / KICK / SHUT DOWN ask twice and pop a toast on YOUR screen. They cannot touch you (kick, ban, cash all refused) and have no DELEGATES tab; typing `/delegate` as them does nothing.
- [ ] Chat: `/delegate Bob helper 1h`, `/delegates`, `/undelegate Bob`; `/delegate Bob tester 1h` only warns until you add `confirm`.


## Sell station beside the mill (claude/sell-pad, 6 October 2026)

Connor: "move the sell logs here pad to the side of the saw mill, and add more to
it." The sell pad no longer sits in front of the mill (on the spawn walk, in the
way of the mill's intake). It is now a sell station EAST of the mill's lean-to,
off the main street's north side and west of the mill road.

- **Where:** pad centre (53, 111), 28 wide x 32 deep (x 39 to 67, z 95 to 127).
  `WorldPlan.Town()` `sellPad` / `sellZone`; the zone is 28 x 12 x 52 (z 85 to
  137) so a truck backed in from the street has its whole bed in it. The town,
  spawn, Murph's camp and the sawmill did not move. The Dealership's loading pad
  (x 70 to 84) stays clear.
- **What is on it (`BuildingArt.SellStation`):** a lane for trucks between two
  painted lines; three marked LOGS slots (west) and two PLANKS slots (east) for
  hand-dragged logs and plank piles (paint only: the sell logic still sells
  whatever rests anywhere in the zone); a platform scale with a dial; a log rack
  across the back (lanterns on its stakes); a Weigh House on the east side with
  Millie at its window; split rails behind; lamps at the four corners and over
  the SELL LOGS HERE signpost at the gate (67, 90). The Sky Bin moved into the
  pad's north-west corner.
- **Unchanged, server side:** SellService, the Sell remote, truck-bed selling
  (`SellTruckRange` measures from the zone's middle, now (53, 111)), hand-drag
  selling, plank sales. The tutorial's `sellPad` beacon, the quest arrow
  (QuestUI) and the SELL LOGS marker (TownMarkers) all read the SellZone part.
- **Economy:** the walk from the nearest grove oak to the pad grew from 44 to 97
  studs. Headlines 61 s / 7.3 min / 13.1 min / 50.7 min / 30.4 h became 68 s /
  7.9 min / 13.7 min / 51.4 min / 30.5 h (all in the CI ranges; Steel Axe is 7 s
  under its 8-minute ceiling). ECONOMY.md regenerated, ECONOMY_V1.md unchanged.
- **Moved to make room:** the street lamp at (58, 92) (now the station's lamps),
  the crate at (71, 93) to (86, 92.5), the log piles east of the mill from x 39
  to 35.5, a few bushes, one birch, one maple.

### Studio checks
- [ ] Spawn and look at the mill: its front (the saw, the ramp) is open and
      clear now, no pad in front of it. The TIMBERLINE SAWMILL board still reads.
- [ ] Walk east along the main street: the "SELL LOGS HERE" signpost stands north
      of the street at x about 67, lit at night, and the SELL LOGS chip floats
      over the station. The station is the big plank pad east of the mill.
- [ ] The station has: painted lane, LOGS and PLANKS slots with labels, a scale
      with a dial, a log rack across the back with two lanterns, the Weigh House
      (WEIGH HOUSE board, two lanterns) with Millie at its window, rails, the
      Sky Bin in the north-west corner, a lamp at each corner. At night the
      lanterns and lamps are lit.
- [ ] Fresh save: the quest arrow and beacon point at the station (not the old
      spot), and arrive there after the first oak. Drag the log onto the pad
      (anywhere on it): it sells, the $25 lands, the plot card follows.
- [ ] Back a loaded truck (Logging Rig too) in from the street down the lane:
      stop short of the rack. Press the sell prompt ("Sell logs", over the pad's
      middle): the whole bed sells. Planks dragged onto a PLANKS slot sell too.
- [ ] The Sky Bin's "Sell Sky Bin" prompt still works at its new corner.
- [ ] Nothing blocks the drive in from the street: no lamp or crate in the lane.
      The Dealership's boxes and the mill road beside the station are not in the
      way. Walk Millie's side: she stands by the Weigh House window.
- [ ] Sound and feel: the sell toast, sale FX and figure reveal still show.
## Xbox navigation and rotation (6 October 2026, branch `claude/xbox-nav`)

Connor: "it's really hard to get to boxes like SAVES, STORE" with the Xbox
menu navigation, and "when rotating things it should be the left stick (the
movement stick) that rotates, not the right stick".

- **Quick menu (View button).** One always-available gamepad button opens a
  panel with a big tile for every HUD destination in a grid: SAVES, STORE,
  BADGES, DAILY GOALS, FIELD GUIDE, SETTINGS, PLANS and LAND (hammer out),
  HAMMER, SKIP TUTORIAL (while it runs), SEND TRUCK HOME, DROP AXE, SELL HERE,
  OWNER (owner only) and HUD BUTTONS. The stick or D-pad moves one tile at a
  time and wraps, A opens it, B (or View again) closes. A tile closes the menu,
  does what its HUD button does, and the panel it opens hands the selection
  back to that HUD button when it closes. View was Badges' button; Badges is a
  tile now (`BadgeData.OpenGamepad` is gone, InputKit lists `QuickMenu` on
  ButtonSelect). A MENU button with the View glyph shows in the side column on
  a gamepad. Tiles are whatever HUD buttons register (`HudNav.Add`), so a new
  HUD button joins by registering. Rules: `Shared/QuickMenuLogic`,
  `Shared/GamepadNavLogic`; UI: `QuickMenuUI`.
- **HUD buttons wired for the stick (`HudNav`).** Every persistent HUD button
  registers; whenever the selection lands on one, the visible ones are linked
  with NextSelectionUp/Down/Left/Right by where they are on screen now
  (nearest neighbour inside a cone, wrapping round the edges), and the HUD
  BUTTONS tile (or `HudNav.Focus`) starts on the first one in reading order.
  B on a HUD button lets go (walking again). Side buttons are 160 x 48 on a
  gamepad; the selection ring is a 4 px ink and 4 px amber ring with a soft
  glow. Roblox's own hotbar is core UI and is not part of this chain.
- **Panels share one helper (`GamepadNav.Focus / Trap / Restore`, behind
  `MenuPad` and `HUD.Popup`).** Opening selects the first control, traps the
  stick in the panel (SelectionGroup, Stop on every side) and remembers the HUD
  button that opened it; closing goes back to it (or lets go when none). Used by
  Store, Saves, Field Guide / Plans (ShopUI), Daily, Settings, Badges, Land,
  the shopkeeper card and the owner menu.
- **Rotation.** While LT is held, the LEFT stick turns a held piece (left/right
  spins it, up/down tips it) or flicks the build ghost (left/right a quarter,
  up/down raise and lower); the right stick stays the camera. The left stick is
  sunk (CAS, Thumbstick1) and the humanoid held still while LT is down, and the
  lock lets go the instant LT is up (also polled), the piece is dropped or
  placed, the tool goes away, you die or sit, a menu opens, or the window loses
  focus (`GrabLogic.LockStays`). Unchanged: RB/LB push and pull, keyboard R,
  D-pad right in the placer, D-pad turns while dragging, flick behaviour. Hints
  now say "LT + left stick: turn".

### Studio checks: Xbox navigation and rotation
- [ ] Press View on a controller (walking, nothing open): the QUICK MENU opens
      centred, tiles in a grid, the first tile ringed in amber. Stick and D-pad
      move one tile at a time and wrap round the edges; A opens the tile; B and
      View close it. Output: no red lines
- [ ] Tiles: SAVES, STORE, BADGES, DAILY GOALS (after the tutorial), FIELD GUIDE
      (once you have it), SETTINGS, HUD BUTTONS; HAMMER on foot; PLANS and LAND
      with the hammer out on your plot; SEND TRUCK HOME / DROP AXE when they show;
      OWNER only on Connor's account
- [ ] SAVES tile: the Saves panel opens with its first slot selected; the stick
      cannot drift onto the HUD behind it; B closes it and the cursor is on the
      SAVES side button (B again: back to walking). Same for STORE, BADGES,
      DAILY, FIELD GUIDE, SETTINGS and the Land panel
- [ ] HUD BUTTONS tile: the cursor lands on the first HUD button (top left),
      D-pad / stick walks them in on-screen order, wrapping round; A presses;
      B lets go and the stick walks you again
- [ ] A MENU button with the View glyph shows at the top of the side column
      only on a gamepad (not with mouse or touch)
- [ ] View does the same while a shop or the Field Guide is open (the menu goes
      over it; B returns you to it) and not while typing in chat. It does not
      also open Roblox's player list or menu (report if it does)
- [ ] Rotation: hold RT on a log, hold LT: the log hangs; the LEFT stick spins
      it (left/right) and tips it (up/down) and the character does NOT walk; the
      right stick still turns the camera. Let go of LT: the left stick walks you
      again at once. Drop the log while LT is down: you can walk
- [ ] Hammer, pick a Wall: hold LT, flick the LEFT stick left/right: quarter
      turns; up/down: raise / lower. The character stands still while LT is
      down; RB/LB still slide the ghost; D-pad right still rotates; R on a
      keyboard still rotates
- [ ] Hold LT then: open the quick menu, put the hammer away, die (/kill),
      alt-tab away and back: you are never stuck unable to walk
- [ ] The hint line reads "LT + left stick: turn" while dragging and "RT place ·
      LT+left stick turn · B stop" while placing
## NPC heads face the player (claude/npc-heads)

- Heads look at you through `Shared/HeadLook.Aim` (clamped 70 degrees side to
  side, 35 up and down, eased; behind them they look ahead). Part-built faces
  are on -Z for every NPC (`tests/HeadLook.spec`). The uploaded NPC meshes are
  assumed to face +Z, so `NPCMeshes` turns each piece by `TownModels.NpcMeshYaw`
  (pi). That part is a best inference without the assets: please check it.

### Studio checks
- [ ] Walk up to Murph, Old Hank, Old Tolly, Cap'n Moss, Gus, a shopkeeper and
      a walker (Rosa, Pip, Bram): their faces (eyes, nose, beard) look at you,
      and their heads follow you as you circle, up to about 70 degrees, no snap
- [ ] Stand behind one: the head settles looking straight ahead, no twist
- [ ] Walkers still walk face first with the face and the toes on the same side
- [ ] If the NPCs are Blender meshes and their faces or toes now point AWAY,
      set `TownModels.NpcMeshYaw = 0` (the meshes were already facing -Z) and
      tell Claude; if it was backwards before and is right now, nothing to do
- [ ] Held items (Murph's lantern, Millie's clipboard) are still in the hand

## The Sky Bin is an item (claude/sky-bin-item, 6 October 2026)

Connor: "remove the skybox that collects dropped wood at the sawmill and make it an item sold with a box."

- The fixed Sky Bin is gone from the sell station (art placement, `town.skyBin`, MapBuilder step, the sell prompt on it, the preview scenes). `BuildingArt.SkyBin` is kept as the item's art.
- It is a boxed Tool Shed machine, **$400, one per player** (`ItemCatalog.Machines.SkyBin`, `Shared/SkyBinLogic`). Buying hands over a box; opening it puts the bin in your stock (`sawmillStock`, like the chop saw) and sets `profile.skyBinOwned`; the hammer places it on **your** plot (`MachineArt.BuildSkyBin`, 8 x 8 footprint, owner only, **one per plot**). The hammer sheet says **Take back** (free, back to stock; what is inside stays in the save).
- **The Cloud Chute is locked until a bin is placed on your plot.** A locked chute takes nothing (the piece stays where it lies, so nothing is lost) and toasts "...Buy one at the Tool Shed ($400)..." or, if you own one that is not placed yet, "...place it with your hammer".
- "Sell Sky Bin" is a prompt on the placed bin: only its owner, from beside it (`SkyBinLogic.CanSell`, RateLimiter `SellSkyBin`), paid through `SellService.PayEntries` as before. Capacity is still `BiomeData sky.skyBinVolume` (120 u³).
- **Old saves:** `ProfileSchema.Migrate` (`SkyBinLogic.Migrate`, idempotent) sets `skyBinOwned` for any save with wood in `skyWood` (or a bin already in stock or on the plot) and, if no bin exists anywhere, hands over one **free in stock** to place. Nothing is paid out and no wood is lost. (v1 logs in the old `skyBin` list are still bought back into `v2Credit` by `MigrateV2`, as before.) The v1 rollback loop is untouched and knows nothing of the bin item.
- Economy: `tools/economy` and `tools/economy1` regenerated, no change (the $400 is not modelled; the ranges hold).
- Tool Shed shelf: the bin's box is a small one (sized from a 4 x 4 footprint), riding the axe table's spare room (`StoreStock` lane kinds).

### Studio checks
- [ ] The sell station beside the mill has no blue Sky Bin or flume any more; selling logs on the pad is unchanged
- [ ] Tool Shed (open 6 AM to 8 PM): a small blue-ish box "Sky Bin" on the shelves, $400. Put it on the counter: "Buy this Sky Bin for $400?" Pay: "Paid for the Sky Bin. Open the box."
- [ ] Try to buy a second one while the first box is unopened, then after opening it, then after placing it: "You already have that one..." at the counter and "You already own a Sky Bin." toast each time, nothing charged
- [ ] Open the box on your plot: it unpacks to your stock ("Unpacked the Sky Bin. Place it with your hammer...")
- [ ] Hammer, PLANS: the Sky Bin is listed under Machines ("Box from the Tool Shed" until you hold one). Place it: a blue bin with a flume and a cloud, "SKY BIN 0/120 u3" on its faces
- [ ] A second place attempt (another box via /gift Machine SkyBin or the second bin of a friend): "You already have a Sky Bin on your plot..."; a friend with build rights cannot place one on your plot
- [ ] Hammer on the bin: Move, Turn, **Take back**. Take back returns it to stock (no cash); place it again; any wood in it is still there
- [ ] With NO bin (new save): on the Aether Isles lay wood in a Cloud Chute: it stays on the chute, a toast says to buy a Sky Bin at the Tool Shed; the "Check Sky Bin" prompt says the same
- [ ] With a bought but unplaced bin: the toast says to place it on your plot instead
- [ ] With the bin placed: the same wood goes down after a moment, "Sent 1 piece down the Cloud Chute. Sky Bin X/120 u3."; the bin's label updates; a full bin refuses with "Sell it from the bin on your plot."
- [ ] Walk to your bin: **Sell Sky Bin** shows only while it has wood; it pays with the usual sale toast; from far away it does nothing ("Walk closer to your Sky Bin."); a friend visiting your plot does not see the prompt, and cannot sell your wood
- [ ] Old save with wood in the Sky Bin (use a save from before this change, or set `skyWood` in Studio): you join with a Sky Bin in your stock and the wood still in it; place it, sell the wood. Rejoin: still exactly one bin
- [ ] Preview: `bash tools/preview/shoot.sh town` shows the sell station with nothing in the north-west corner

## Mill and planer tiers, belts, boxes that place once (claude/mill-tiers, 6 October 2026)

Connor: "create different versions of the sawmill ... they progress in cost but also upgrade how much you get from the sold items", the same for a planer, a plank size you can set on both, conveyors "so players can build automated systems (log in -> sawmill -> plank belt -> planer -> board out)", and "an object in a box: you buy the box, open it, and the object is placed down as a one-time use". The tables and the reasoning are in V2_PLAN.md section 2h and 10a; this is what to check in Studio.

**What changed**
- **Five sawmill tiers** (ids and prices unchanged): Rickety $130 x1.00, Sturdy $1,600 x1.10, Mill (Millmaster 100) $11,000 x1.22, Steam (Millmaster 200) $22,500 x1.36, Industrial (Millmaster 200 Long) $86,500 x1.50. The multiplier is `plankBonus`, stamped on each plank the mill cuts and applied in `SellLogic.PieceValue` (server only; a piece with no stamp is 1.0).
- **Four planer tiers** (new, `PlanerLogic`, `PlanerService`): Hand $2,500 x1.20, Bench $9,000 x1.40, Steam $30,000 x1.65, Industrial $95,000 x2.00 (`boardBonus`). A plank in, the same piece out as a finished board, planed down to the setting; at most **2 planers per plot**, the owner's only.
- **A belt kit** (new): Straight Belt $80, Turn Belt $100, Funnel Belt $60, at most 150 belt pieces per plot. Belts carry loose logs and planks into a mill or planer and take their output away.
- **Size panel on every mill and planer** shows the size AND the limit ("1.00 x 0.60 u / up to 1.8 x 1.2 u, steps of 0.2"); higher tiers have a wider range and finer steps (Industrial steps by 0.05). Plank length is not adjustable.
- **One-time boxes.** Sawmills, planers and belt pieces: buy the box, OPEN it (the same Interact as every box), and a placement ghost starts on your plot; click or PLACE to put it down (the box is used up), Q or CANCEL keeps the box. No hammer stock, no blueprint book entry. The hammer still moves and turns what you placed and sells it back for half (it is gone, not boxed). Old saves with a sawmill in `sawmillStock` still place it from stock. The chop saw and the Sky Bin are unchanged.
- **Tier labels**: on the box ("MILL, TIER 3 OF 5"), in the Tool Shed's "Browse saws" list, on the machine's sign, and on the placing bar ("Place the Millmaster 100 (Mill (tier 3 of 5)) from your box").
- **Automation rules (GAME_DESIGN section 9):** belts run only while you are online; belt-fed wood must be yours and ordinary (no Lumenwood, Phantomwood, figured, Elder or Lux wood: those stay hand work); a mill or planer takes belt-fed pieces at its tier's rate only (Rickety 6 u3/min up to Industrial 110; planers 8 to 80); hand-fed pieces are never capped; belts stop while you have 60 or more loose planks and boards (the Warehouse stand-in) and start again when you clear the floor.
- **Economy:** the early ladder is untouched. The model does not buy planers or belts and does not model `plankBonus` (modelling it shortens the full plot to 20.8 h, outside 28-36 h; see ECONOMY.md and V2_PLAN 2h). All headline ranges still hold: 68 s / 7.9 min / 13.7 min / 51.4 min / 30.5 h.
- Tool Shed shelves: the tables run to z 16.8 (the back corners beside the counter) so every new box has a place; planer boxes are sized by tier (S, M, M, M), belt boxes are small (S).
- Saves: no new profile field. Planks in the Sky Bin and on the truck gain optional short keys `m` (mill bonus) and `d` (planer bonus); old entries read as 1.0. A placed mill keeps its cut (a cut on the 0.2 grid is legal on every finer grid); a planer's saved setting is clamped to its tier on every load.

**Not done (follow-ups):** the logic network (levers, sensors, sorting, wires into belts), the sweeper, tilted belts and switches, a real Warehouse inventory (so the 60-piece cap becomes a capacity), saving loose wood on a plot, belts that cross plots, a planer/mill output bin, adjustable plank length. Nothing here has been seen in Studio.

### Studio checks
Buying and placing (do each tier you can afford, `/cash` or the owner hub helps)
- [ ] Tool Shed: boxes for every Rickety to Industrial mill, four planers and three belt pieces are all on the tables, none floating, none overlapping; each mill and planer label has a second line ("RICKETY, TIER 1 OF 5" ... "INDUSTRIAL, TIER 4 OF 4"); the back corners beside the counter now have tables under the boxes
- [ ] Buy a Sturdy Sawmill: "Paid for the Sturdy Sawmill. Open the box." Open it ON your plot: a see-through mill ghost appears with "Place the Sturdy Sawmill (Sturdy (tier 2 of 5)) · from your box (Q keeps it)"; rotate (R), aim, click: it is built, the box folds away, no cash is taken. Open a box away from your plot: "Walk onto your plot, then open the box again. It is still yours."
- [ ] Cancel with Q: the box is still there and still opens. Place somewhere blocked: a red ghost with the reason; the box is not spent
- [ ] Walk off and rejoin with an unopened box: it is back on the Tool Shed counter, still owed, still opens
- [ ] The hammer on a placed mill/planer/belt: Move and Turn work, Sell pays half and the thing is gone (no box, no stock entry). The hammer's PLANS list no longer lists mills, planers or belts
- [ ] An old save with a sawmill in stock: it is still in the hammer list under Machines and places for free as before
- [ ] Planers: buy a Hand Planer and a Bench Planer, place both. Try to buy a third: the counter says "You already have 2 planers (placed or waiting in a box)..." and takes nothing. With two placed and a box in hand, placing the third says "A plot has room for 2 planers. Take one apart first." and keeps the box. A friend with build rights cannot place a planer or a belt on your plot ("Only the plot's owner can put a planer down.")
- [ ] Belts: place Straight, Turn and Funnel pieces; the 151st is refused ("A plot has room for 150 belt pieces.")

Art (each tier looks different)
- [ ] Mills: Rickety (plain wood shed) then Sturdy (corner posts), Mill (metal roof and a stack), Steam (a brass boiler with a dome on the roof), Industrial (diamond-plate walls, a yellow gantry with two lamps); every one has its TIER sign on the roof lip. No mill's detail blocks a log or a player
- [ ] Planers: Hand (wood), Bench (planks and posts), Steam (metal, a brass pipe), Industrial (diamond plate, gantry and lamps); rollers and a cutter head over the belt, a size board on the east side
- [ ] Belts: a straight trough with rails and legs; the turn bends to the right when you look along it; the funnel has a wide mouth narrowing to a belt

Cut and plane, compare the payout
- [ ] Cut the same oak with a Rickety (plank x1.00) and a Millmaster 200L (x1.50) at the same cut: sell one plank of each; the Industrial plank pays 1.5 times as much per u3 (hold a plank: the tooltip value shows the bonus)
- [ ] A Hand Planer at 1.0 x 0.6: put a 1.0 x 0.6 plank in: it rides through and comes out a finished board (pays 1.2 times the plank). Put in a 1.8 x 1.2 plank: it comes out 1.0 x 0.6 (planed down, smaller, same length). Set the planer to 1.4 x 0.8 and put in a 1.0 x 0.6 plank: it stays in the mouth with "That plank is smaller than the planer's setting. Lower the setting."
- [ ] A finished board fed in again: "That board is already finished." A log: "The planer only takes planks, not logs."
- [ ] A Sturdy plank (x1.10) through a Hand Planer (x1.20) sells for 1.32 times a plain plank; the same plank through an Industrial Planer, 2.2 times
- [ ] Sky Bin and truck: send stamped planks down a Cloud Chute and sell the bin: it pays the stamped value; park a truck with stamped planks, rejoin: they are still stamped (the tooltip value is unchanged)
- [ ] Old save (planks with no stamp in the Sky Bin or on a truck): they sell at the plain plank price, exactly as before

Sizes
- [ ] The board on a mill shows "1.00 x 0.60 u" and under it "up to 1.8 x 1.2 u, steps of 0.2" (Rickety); the screen panel (E, X, tap) shows the tier name, the size and the limit. X+ / Y+ stop at the limit and X- / Y- at 0.6 / 0.4
- [ ] The Industrial mill steps by 0.05 (1.00, 1.05, 1.10 ...), the Mill and Steam by 0.1, the others by 0.2. A placed mill from before keeps its cut
- [ ] A friend cannot change your mill's or planer's size; from far away nothing changes

Belts and automation (build log in -> sawmill -> plank belt -> planer -> board out)
- [ ] Lay straight belts behind a sawmill (same turn, the belt's far end at the mill's back) and drop an oak log on the near end: it rides into the mill's mouth and is cut. Put a straight belt in front of the mill's outfeed: the planks ride along it
- [ ] Run the planks round a turn belt and into a planer's back: a finished board comes out of the planer's front and rides the next belt. Try a funnel at the start: logs dropped across its wide mouth are squeezed onto one belt
- [ ] Hand-feed the same mill quickly several times: it takes every one (no cap). Feed it from the belt: it takes about one log per (volume / rate) minutes; the Rickety is slow, the Industrial is fast; a very big log still goes in and the next one waits
- [ ] A Lumenwood or figured log on a belt is refused with "Rare and figured wood only goes through by hand."; a log of another player's on your belt: "A belt only feeds its owner's own wood."; dropped by hand into the same mill, either works
- [ ] Leave the game with a belt running (a second player stays): the belt stops moving wood; rejoin: it runs again. Two players, two plots: each plot's belts follow their own owner
- [ ] Let 60 planks or boards pile up on the plot: belts stop and the next belt-fed piece is refused ("Your plot is full of planks..."); sell or load some and the line starts again. A belt loop just circulates (it never jams a mill)
- [ ] Rejoin with machines placed: they come back with their settings; wood lying on belts is not saved (the follow-up)

Sizes, shelves and the placer on phone and Xbox
- [ ] Phone: the placement ghost, PLACE and CANCEL buttons work for a box; the size panel's buttons are at least 44 px. Xbox: the box opens with X, the ghost with LT/stick as for blueprints, B cancels (the box stays)

### What it would take to make the Sky Bin (merged earlier) one-time boxed too
Mark it `placeFromBox = true` in `ItemCatalog.Machines` (`BoxUnpack.Mode`, `AutomationLogic.PlacedFromBox` and `PlotService.Place` then do the rest), drop its entries from the stock paths (`ShopService.deliver`, `SkyBinLogic.Migrate` would hand an old owner a pending box in `profile.storage` instead of a stock id), and replace "Take back" (`HammerLogic.PieceActions`, `PlotService.Sell`'s Sky Bin branch, `SkyBinLogic.BackInStockLine`) with the sell-for-half rule. The one real decision: the bin holds wood (`profile.skyWood`), so selling or taking it apart must either be refused while it has wood in it or pay the wood out first (as "Sell Sky Bin" does); and the one-per-player rule (`skyBinOwned`) would count the box, the placed bin and nothing else. Specs to touch: SkyBinLogic, PlotService, ShopService, ProfileSchema, AetherServiceV2.

## Store fixes: one grab, the carry cap, door flicker, one price (claude/store-fixes, 7 October 2026)

What Connor saw, and the cause of each (all found in code; none needs a Studio reproduction to explain):

1. **Grabbing a box off the shelf took two tries.** A shelf box is anchored, and the client sized its pull from `part.AssemblyMass` at the moment of the grab: an anchored assembly reports 0, so the pull had no force. The server freed the box (unanchored it and handed over its physics) but the client dragged with nothing; the second grab, on the freed box, worked. `GrabLogic.PullMass` now takes the larger of the assembly mass and the sum of the parts' masses, and `DragController` re-sizes the pull when the piece's assembly changes (the moment the server frees it). A grab the server refuses after freeing the box (`stuck`) now calls the new `Hooks.onRefused`, and `BoxService.NoteRefused` anchors the box back on its shelf.
2. **"You can only carry 3 unpaid boxes" on the first pickup.** `BoxService.UnpaidOffShelf` counted every unpaid box off the shelf that the player had ever claimed, not only the ones in their hands: boxes dropped on the floor, put back on a shelf by hand (never marked back on the shelf), or left by a first grab that did nothing all counted until they walked outside the shop. Now `BoxLogic.CountUnpaid` counts a box for a player only while `heldBy` is them (set in `NoteGrab`, cleared in `NoteRelease`); a box let go within `BoxLogic.PutBackRadius` (3.5) of its shelf spot goes back onto the shelf (`NoteRelease` calls `ReturnHome`), and the server-wide cap (30) still counts loose boxes. The message only shows when you really hold the third (a player holds one box at a time today, so in practice it no longer fires).
3. **Every door flashed two textures.** Z-fighting: faces of different parts on the same plane. Barn leaves (Tool Shed): the trim ring overlapped itself at the corners, both braces crossed on one plane, and the two leaves overlapped 0.6 stud when shut on identical planes; shop door headers and jambs were level with each other and with the wall's inside face; the back-room doors had a frame slab level with the door's face; the Dealership's roll-up slats stacked 0.01 stud apart; the Sawmill's plank door had its frame overlapping it. Each is now stepped by at least 0.03 stud, or the frame is a ring of pieces that only touch edge to edge (`ShopDoor.FaceStep`, `ShopDoor.LeafStep`, `ShopInterior.backDoor`, `BuildingArt.door`). `tests/ZFight.spec.luau` scans every shop door (open and closed pose), the building around it, the Sawmill door and the back-room doors for same-plane faces; the Tool Shed's first measure was dozens of pairs, now none.
4. **Two prices over each other on shelves.** A shop box had a floating `BillboardGui` price (screen-size, so neighbours collided) AND a plaque on the table's aisle face; side-by-side boxes in one row put their two plaques at the same spot. Now the price is one line under the name on the box's own label (`BoxArt` `price`, world-space text that moves with the box), the billboard and the aisle plaques are gone, a vehicle's box shows none (the showroom price sign is its price), a Robux box shows "R$" and then its real price. The Tool Shed's axe rack plates and the General Store's back-wall offer boards still print a price (a display list, not a shelf label); say if those should go too. `tests/ShelfPrices.spec.luau`: every box on both shops' shelves shows exactly one price, the real one, no billboards, no stand-alone plaque text, and no two labels overlap.

Studio checks (Xbox, then phone, then mouse):
- [ ] Tool Shed, walk to the axe table, aim at a box, press RT once: the box lifts and follows on the FIRST press (mouse: press and hold; phone: rest a finger 0.25 s). Repeat on the General Store shelves and the sawmill table.
- [ ] Let go over the shelf spot: the box settles back on the shelf (same spot, anchored, no stray box left). Let go in the aisle: it stays on the floor.
- [ ] Take four boxes off the shelves one after another, dropping each on the floor: the fourth lifts too, no "You can only carry 3" message. Pay for one at the counter, open it: still fine.
- [ ] Carry a box out of the shop and let go: it returns to its shelf after a second or two, as before.
- [ ] Doors: stand 5 to 10 studs from each door and walk across it (Tool Shed barn doors, General Store double doors, the Dealership shutter, the back-room doors inside both shops, the Sawmill cabin door): no two wood textures flickering on a door or its frame, open or closed; wait for night to see the closed pose with its sign.
- [ ] Shelves: every box shows its name and ONE price under it on its front label; nothing floats over the shelf; no price plaques on the table edges. Gold Robux boxes show "R$" (the number appears a moment later). Prices equal what the keeper charges at the counter. Dealership: the price is on the sign beside each vehicle, not on its box.
- [ ] Read the prices from the doorway and from the aisle on a phone: if the label's price is too small to read at your usual distance, tell me the distance and I will size it up (`BoxArt.Layout.pricedLabelH`, `priceShare`).
## The dialogue box, text that stays out of walls, bigger rabbits (branch `claude/npc-dialogue-box`)

Connor's playtest (Xbox, phone, PC): "the bunnies are super small", "sometimes the text pops up in walls still", and "instead of chat bubble pop ups, if someone talks to a NPC it pops up with a chat box they have to press X again to continue or end talking".

What changed
- **Dialogue box** (`DialogueUI`, rules in `Shared/DialogueFlow`): a Talk press (E, X, tap on the prompt) opens a box above the hotbar, 40% of the screen wide (300 to 560 px), wood and parchment colours: the speaker's name and role, the line (2 to 3 lines; a longer line is split into pages at a sentence), and a Continue prompt with the right key (E on a keyboard, the pad's X glyph on a gamepad, nothing but the word on a phone). Each press (E, X, a click or tap on the box, or the Continue button) shows the next line; the press on the last line (the word turns to Close) ends it. B or Esc closes at once. Walking is never locked; the box closes when you are more than 24 studs from the speaker, the speaker is gone or lies down, you go down, or the plot picker opens.
- Who talks through it: Millie, Rosa, Bram, Pip and the other townsfolk (a greeting, then one line from their pool: the hour, the weather, a first sale, a better axe, a sawmill, a general line); the shopkeepers Tink, Hazel and Dale and the Hermit, whose line the SERVER picks (`DialogueService`, `HermitService`) and sends to the same box, with their Yes / No offers intact (E or X is Yes, B is No, same as before); Murph's Talk press (his tutorial line for your step, or the farewell: `QuestUI`); Old Hank when you already own a plot (with no plot his Talk opens the plot picker, as before).
- While it is open: that NPC says no bubble lines; every other prompt is off (so the press that continues cannot also buy, open or talk to something else) and returns 0.3 s after it closes; toasts wait (errors still show: `NoticePolicy` hold; a Low toast is dropped, a Normal one comes after); on a gamepad the selection sits on the box and goes back to the HUD button it came from (`GamepadNav`).
- **Bubbles that stay** (small, nothing to press, unchanged apart from the wall fix): the wave hello's greeting, Murph's first-meeting tip, and the chatter line the nearest NPC says now and then (the hour, the weather, "sale" and other world reactions). `NPCDialogue.AutoBubbles = false` turns those off too if you want no bubbles anywhere.
- **Text and walls** (`Shared/TextAnchor`, used by `NPCController` and `PromptUI`): four times a second a ray from the camera to the NPC's head hides the bubble and the name tag when a wall is in between (back after two clear checks); a ray up from the head finds a ceiling and brings the tail and the name tag down so the card is not clipped by a shop roof (never into the hat; with no room at all a bubble stays off); a ray sideways puts a bubble that has a wall beside it straight above the head. The Talk prompt card over an NPC's head is no longer `AlwaysOnTop` (it used to draw through every wall), with the same wall hide and ceiling clamp. Cards on a counter or box stay on top (their anchor is the object's own middle). Left on purpose: the tutorial beacon arrow, tree health bars, floating "+$" numbers and the Elder's distant marker (they are meant to read through things); the price tags, the limited-stock sign and the Zzz were already depth-tested.
- **Rabbits** 2.25x their old size (`CritterArt.RabbitScale`): body, haunch, head, ears, tail, nose, eyes and paws scale together and the head's nod hinge with them; the hop's arc grows with the body and its stride by the square root, so a bunny still bounds away slower than a deer. They still spawn 30 to 70 studs out, bolt at 25, never collide or get clicked.

Studio checks (nothing here has been seen in Studio)
- [ ] Talk to **Murph** (E / X / tap his prompt): the box shows his line for your step with his name and role; the amber arrow and tracker are unchanged; one press closes it. During the tutorial's first steps his step card still appears when a step starts and does not stack with the box
- [ ] Talk to **Millie**: a greeting, a press, a second line, a press closes it. The box shows "1/2" then "2/2", the word turns from Continue to Close. Press X (Xbox) / E (PC) / tap the box or Continue (phone): each one works
- [ ] A **shop keeper** (Tink, Hazel, Dale): the server's greeting shows with the keeper's name; put a box on the counter: the offer shows Yes / No, E or X is Yes, B is No and buys nothing; a closed shop: the keeper's sleepy line in the same box. Nothing is bought by Continue
- [ ] **Old Hank** with no plot: the plot picker opens, no box. With a plot: his greeting and a line in the box (the server's "you've got your plot" toast waits until you close it)
- [ ] The **Hermit**: his quest line in the box, with his name; the Maul still arrives when it should
- [ ] Walk 25+ studs away mid-talk: the box closes by itself. Walk 10 studs back and forth within range: it stays. Open the plot picker or die while it is up: it closes
- [ ] **Xbox**: the selection sits on Continue (A also continues); after it closes the HUD gets the selection back (the stick moves the HUD buttons, not a stale ring). The stick still walks you
- [ ] Press X on the last line: it closes and does not re-open (no instant second talk); a second Talk right after works about a second later
- [ ] **Two lines in a row**: talk to the same NPC twice, you get different lines (the shuffle bag); talk to two NPCs one after the other, each box is its own
- [ ] While the box is open the NPC says no bubble; other NPCs further away still may. A toast that arrives while it is open (a sale, a goal) shows after it closes; an error ("too far") shows at once
- [ ] The **tutorial** still completes start to finish with talking to Murph in the middle of it; no step is skipped or double-counted by pressing Continue (the box never sends the server anything but an offer's Yes or No)
- [ ] On a **phone** (portrait and landscape): the box is readable (17 px text), clear of the hotbar and the jump button, never wider than the 40% rule allows (300 px floor); tapping it advances
- [ ] **Text in walls**: stand inside the Tool Shed, Hearth and Home and the Dealership hall and watch the keeper: no half-hidden line in a wall or the ceiling (a bubble either shows whole, lower under the roof, or not at all); the name tag is above the hat, not in the roof. Walk round the outside of the shop: the keeper's name tag, bubble and the Talk card go when the wall is between you and them, and come back when it is not. A NPC at the counter next to a side wall: the bubble sits straight above the head
- [ ] **Rabbits**: they are about the height of your hip next to your character, not a loaf. They hop, sit and nibble as before, with ears, tail and eyes in proportion; they flee when you get near (the same distance as before) and none appears on top of you. Winter hare too (snow biome)

## Modern kit: paint, glass, overhang roofs, stairs, balcony, sample builds (branch `claude/kit-modern`, 7 October 2026)

Connor showed Lumber Tycoon 2 houses (white and dark-brown boxes, big glass, flat overhanging roofs, balconies, stairs, boxy shops) and asked for the same. What the kit already had: walls (Wall4/8/12, TallWall4/8, HalfWall8), DoorWall8 + Door, WindowWall8 + Window (one 4x3 pane), Floor/Floor4, Foundation8, Ramp8, the old Stairs (a 4x8 wedge rising 4), FlatRoof8 (0.5 overhang), SlopedRoof8, RoofCorner, RoofRidge8, FenceGate4, Post, Beam8, Railing8; planks fill a piece and the wood sets the look (`BlueprintModels.ApplyWood`); resize (walls, beams, floors), rotate, move, copy; caps MaxKit 400 and MaxItems 200 (kept, see below). What was missing: paint, a real glass wall, a roof that overhangs, stairs to a second storey, a balcony, and any way to see a finished building.

What is new
- **Paint** (`Shared/KitPaint`): 12 choices, `natural` (the wood, the current look), white, off-white, charcoal, black, dark brown, red-brown, tan, slate blue, sage green, brick red, mustard. Hold the Hammer, aim at a kit piece, the sheet now reads Move / Turn / Paint / Sell; Paint opens the palette (the same list screen as the plans, so gamepad focus, touch and mouse work as everywhere; it starts on the colour the piece wears and stays open so you can try a few). Free, looks only: no cash moves, the fee paid, planks, size and sell value do not change. Server (`PlotService.Paint`, remote `PaintPiece`): owner or a visitor with the `build` permission, within 40 studs, a real palette id, rate limited (RateLimiter `PaintPiece`); the piece is rebuilt from its saved data. Saved as `paint` on the placed piece (ProfileSchema cleans it: unknown or missing = natural, non-kit pieces drop it). Paint covers Wood, Door and Trim parts, never glass; a roof's dark edge (role `Edge`) stays dark. Copies and undo keep the paint. Prebuilt pieces (Shed, Cabin, decor) are not paintable: their look is a model, not tintable parts.
- **Glass**: pale blue-grey `Glass` panes (0.4 transparent, 0.45 as a ghost), 0.25 thick in a 1.0 frame (no shared planes), they collide like a wall. Six pieces: Picture Window Wall (8 x 6), Long Picture Window (12 x 6), Tall Picture Window (8 x 10), Tall Long Picture Window (12 x 10), Glass Door Wall (8, 4x6 doorway), Shop Front (12, doorway, 1.4 stall riser, big panes). Frames and risers are wood (planks and paint change them). Wood units 5, 8, 8, 12, 5, 9 (fee $4 each unit): fewer than a solid wall. They are sold by ONE General Store plan, "Picture Window Wall", $500 (using it teaches all six; the shelf had one free slot). Doors hang in the Glass Door Wall and the Shop Front like the Door Wall. Taps and RT look through glass at a piece behind it (`BuilderTools.Aim`).
- **Roofs and trim** (starter plans): Overhang Roof 8x8 / 12x8 / 12x12 (14 / 20 / 28 units; the slab sticks out 1.5 studs each side; a thin darker edge that paint leaves dark), Roof Edge (fascia band, resizes 4 to 16, 2 units), Awning (striped canopy, 3 units).
- **Stairs and balcony** (starter plans): Storey Stairs, 4 x 8, eight real steps of 0.8 rise and 1.0 run to 6.4 studs (one storey: a floor slab 0.4 plus a wall 6), 22 units. Balcony, 8 x 4 slab with a railing on the front and ends, 10 units.
- **Samples** (`Shared/SampleBuilds`): `modern` (two storeys 12x16), `shop`, `barn`, all passing `PlotLogic.Check` on an empty plot at every turn. `/sample <name>` (owner only, never delegable, not even TESTER) places one free on your own plot in front of you facing you (tries nearby spots; all or nothing); `/sample clear` takes them down. Sample pieces are built, `paid` 0 (they sell for nothing), uids start `sample-`.
- Limits: MaxKit 400 and MaxItems 200 kept. The modern sample is 25 kit pieces; the most boxes in a new piece is 10; the worst plot (400 pieces at 10 boxes) is 4,000 parts, each model streams Atomic as before, and a placed piece adds about 25 bytes (`paint`) to the save. Economy tools unchanged (no balance number moved): headlines still 61 s / 7.3 min / 13.1 min / 50.7 min / 30.4 h.
- Not done: "paint all of this type"; painting prebuilt pieces; a glass door leaf (the Door piece is wood); stairs cannot yet be resized.

Studio checks (nothing here has been seen in Studio)
- [ ] General Store: a box "Picture Window Wall" at $500. Buy, use the rolled plan with the hammer: the toast says you learned it and 5 more. The hammer list now has the six glass pieces (Buildings filter)
- [ ] Place each new piece: the six glass pieces, the three overhang roofs, Roof Edge, Awning, Storey Stairs, Balcony. Fill one with planks: wood units match the list
- [ ] Glass: you can see through the panes, but walking into one stops you like a wall; no flicker where the pane meets its frame; from a phone, tap a ghost wall behind a glass wall: it selects the ghost, tapping bare glass selects the glass wall
- [ ] Door: hang a Door in a Glass Door Wall and a Shop Front; it opens and shuts
- [ ] Paint: hammer on a wall: sheet shows Move, Turn, Paint, Sell. Paint opens the palette; pick Charcoal: it changes at once; pick Wood (natural): the wood comes back. Try on a half-filled ghost, a filled wall, a door, a glass wall (frame changes, pane does not), a roof (top changes, edge stays dark). Xbox: D-pad/stick moves the list, A picks, B closes. Phone: tap rows. Sell it after painting: the same cash as unpainted
- [ ] Rejoin: painted pieces come back painted; an old plot loads with everything natural
- [ ] A friend with Build permission on your plot can paint; one without cannot ("You can't build on this plot.")
- [ ] Stairs: walk up and down the Storey Stairs on Xbox (stick), phone (thumb stick) and PC; no sticking on treads, no sliding off; jump on them; a truck driven at them stops like a wall
- [ ] Stack a second storey: floor, walls, floor on the walls, walls, roof: the ghost goes green at 6.4 and 6.8 and 12.8; the balcony sits on the upstairs floor edge
- [ ] `/sample modern` on your plot facing open ground: the house stands in front of you, front toward you; walk in, climb the stairs, go through the glass door onto the balcony. View it from the road. `/sample shop`, `/sample barn`. `/sample clear` removes all. As a delegated TESTER, `/sample modern` is refused
- [ ] Save and rejoin with a sample placed: it is all still there, painted
- [ ] Trucks and storage unaffected: load and haul as before; the Sky Bin, sawmills and belts still place
## The Sky Bin opens and places once; prices show when you aim (branch `claude/hover-prices-skybin`, 7 October 2026)

Two decisions from Connor. **A, the Sky Bin:** "open and place", a one-time box exactly like the sawmills, planers and belts. **B, prices:** "not lose prices, just show prices when hovering over an item".

What changed (A)
- `ItemCatalog.Machines.SkyBin.placeFromBox = true`: buying hands over a box; opening it starts the placement ghost on your plot (WorldFX `PlaceBox`); placing spends the box (`PlotService.Place` takes the box uid, spends it only after every check passed); cancelling keeps the box. No stock, no hammer list entry. One bin per player (a second box is refused at the counter, one unopened box at a time) and one per plot (owner only), as before. A bin already in `sawmillStock` (an old save) still places from stock.
- `profile.skyBinOwned` is set when the box is paid for and when the bin is placed, and cleared when the placed bin is sold; `SkyBinLogic.Owns/Exists` also count a bin box kept in `profile.storage`.
- **Old saves** (`SkyBinLogic.Migrate`, idempotent): wood waiting or a flag with no bin anywhere hands over a **pending Sky Bin box in `profile.storage`** (free; falls back to the stock list if storage is full). A stocked or placed bin, or a kept box, is left alone: nothing lost, no free duplicate.
- **Hammer:** the sheet is the mills': Move, Turn, **Sell +$200** (half of $400; the full $400 inside the one-minute undo window). "Take back" (`SkyBinLogic.BackInStockLine`, the Sky Bin branch of `PlotService.Sell`) is gone: no re-boxing.
- **The wood inside:** selling the placed bin pays `profile.skyWood` out FIRST (`AetherService.PayOutBin`, the same sale as the "Sell Sky Bin" prompt, through `SellService.PayEntries`) and only then removes the bin. If the payout is impossible (the wallet has no room for the wood plus the sell-back, `SellService.CanPayEntries`, or the sale service is not running) the sale is refused with a toast and the bin and its wood stay. Only the plot's owner may sell the bin. The "Sell Sky Bin" prompt and the chute lock without a placed bin are unchanged.
- `ShopService.deliver` keeps the old stock path for a Sky Bin only as the fallback (an owner gift or a full storage), guarded by `SkyBinLogic.Exists`.

What changed (B)
- **Nothing prints a price any more:** shelf box labels (`BoxArt` has no price line), the Tool Shed axe-rack plates, the General Store offer boards (names only), and, by Connor's follow-up, the **showroom price signs beside the vehicles** (the sign is now a name sign, `NameSign`; the vehicle boxes carry no price either). Keeper offers in the shop UI still show prices.
- **The hover tag** (`Shared/HoverTag` rules, `HoverTagUI` client): everything that can be priced is marked (`HoverTag.Mark`: `HoverKind`, `HoverId`, `HoverShop`, `HoverName`, tag `HoverItem`). One small wood card with the name and the price in amber follows the item you aim at: **mouse** the item under the cursor; **gamepad** the item under the screen-centre aim within 12 studs; **touch** the item you last tapped for 4 seconds, else the nearest item within 6 studs in front of you. States: `Closed, opens ...` (the shop's hours), `You already own this` (gear, blueprints, the Sky Bin), `Out of stock` (a showroom vehicle whose box is off its plinth). Robux boxes show `R$` (the number once Roblox has said it). Only one tag exists at a time; a new target waits 0.08 s, a lost one lingers 0.3 s, pressing E / X or clicking on the item hides its tag for 1.5 s.
- **The price shown is the real one:** `HoverTag.Price` is `StoreStock.UnitPrice` (the function the counter charges with; `ShopLogic.Price` for axes, vehicles and gear).
- **Walls:** the tag is a depth-tested BillboardGui (never AlwaysOnTop); the aim tests the item's bounding box and then a real ray, so a wall in front of an item stops it from being targeted; a 4 Hz ray from the camera hides the tag when a wall is between (`TextAnchor.NextHidden`), and a low ceiling lowers it (`TextAnchor.Lift`). A tag on a box with a Buy / Open card sits 52 px higher so the two never overlap.
- Specs: `tests/HoverTag.spec.luau` (target per device, text per state, one at a time, cooldown, the ray test), `tests/ShelfPrices.spec.luau` (no printed price on boxes, rack plates, offer boards, tables; the tag's price equals the real price for every shelf item), BoxArt, BoxService, DealershipLot, TownMesh. The stores preview scene no longer prints prices.
- Left as it is: the price sign on a PLACED chop saw on your plot (`MachineArt` `PriceSign`). It is not a shop item; say if it should go too.

### Studio checks (nothing here has been seen in Studio)
Sky Bin
- [ ] Tool Shed: buy the Sky Bin box ($400), pay at the counter, "Paid for the Sky Bin. Open the box." Buying a second one is refused
- [ ] Open the box on your plot (E / X / tap): a placement ghost starts ("Place the Sky Bin on your plot: click to put it down, Q to cancel. The box is used up when you place it."); the box stays where it is
- [ ] Cancel (Q / B): the box is still there and can be opened again. Put the ghost somewhere blocked: refused, the box is kept. Place it: the bin appears, the box folds away, no hammer stock, no charge
- [ ] A second box (owner gift) placed on the same plot: "You already have a Sky Bin on your plot", box kept. A friend with build rights cannot place or sell it
- [ ] Hammer on the bin: Move, Turn, Sell +$200 (no "Take back"). Sell it empty: $200 and it is gone, you can buy a new box
- [ ] Fill it from a Cloud Chute, then hammer-Sell it: the wood is paid out first (the sale toast and the cash), then the bin goes and the $200 comes. Fill your wallet to the cap first: the sale is refused with a toast, the bin and wood are still there
- [ ] Old save with wood in the bin and no bin (or `skyBinOwned` with none): on join a boxed Sky Bin is waiting (open it as above); join again: no second one. An old save with a bin in stock still places it from the hammer's list; one with a bin on the plot keeps it
- [ ] The Cloud Chute with no placed bin: locked, "...Open its box and place it..." if you hold the box
Hover tags (check on a PC, an Xbox pad and a phone)
- [ ] Tool Shed: no price on any box label, none on the axe-rack plates (names only). Mouse over a shelf box: ONE card with its name and price; over a rack axe: its name and price; move to another box: the card moves, never two at once
- [ ] The price on the card equals what the counter asks for that box (Steel Axe, a sawmill, the Sky Bin, a gold R$ box shows R$)
- [ ] General Store: the four offer boards on the back wall name the item; aiming at a board or the sample under it shows the price. Gear/blueprint you own: "You already own this"
- [ ] Dealership: the signs beside the vehicles show only names; aim at a vehicle, its plinth or its box: the card shows its price. Take a box off its plinth: aiming at the vehicle says "Out of stock" until the box comes back
- [ ] Shop closed (set the clock outside its hours): the card says "Closed, opens ..." instead of a price
- [ ] Walls: aim at a box from outside a shop through the wall or window frame: nothing; walk so a shelf or wall comes between the camera and a tag: it hides and returns without flicker; under the Tool Shed's low roof the card sits under the ceiling
- [ ] Xbox: aim the centre dot at a box within about 12 studs: the card; look away: it goes after a moment. Press X on it (buy / open): it steps aside for a second and a half
- [ ] Phone: tap a box: the card stays about 4 seconds; with no tap, walk up to a box (within 6 studs, facing it): its card; a box behind you or past a wall shows none
- [ ] A Buy / Open prompt card on a box and its price card do not overlap
## LT2 ground and plot platforms (claude/lt2-ground, 7 October 2026)

Connor, with Lumber Tycoon 2 screenshots: "I mean the actual ground, look at this with LT2, then for plots make it normal grass with a raised dark grey platform for players to build on, very slightly raised like 1 stud." Nothing here has been seen in Studio; the Lune preview (`bash tools/preview/shoot.sh plot`, `terrain`, `town`) shows colours and shapes only, not terrain textures.

What changed
- **The ground (TerrainGen, WorldLayout.TownPaint, EnvironmentData, BiomeData, project file):** Grass is a flat, vivid, almost cartoon-bright green 100,184,56 (was a dark muted 84,125,55) and LeafyGrass, the forest floor and the darker patches, 82,158,48 (was 66,104,46). `Terrain.Decoration` is now FALSE (default.project.json, `PlaceCheck`; GrassLength stays 0.5): the engine's grass blades are what made the ground look tall and dull, and they would poke through a 1-stud platform. Every road, path, street, the parking lot and the sell yard is light grey speckled gravel: `TerrainGen.GravelMaterial` = `WorldLayout.RoadMaterial` = **Asphalt**, tinted 176,176,172 (it was brown Ground everywhere but the haul roads, which were Pavement; the whole width is gravel, no dirt edge). Earth, cliff and hill faces are warm red-brown: Ground 156,94,64 (was a yellow-brown 150,116,78) and Rock 128,86,64 (was 114,92,74); under every grass voxel is still Ground, so cliff faces show it. Snow, Glacier, Sand, Basalt, Slate, CrackedLava, the Gloam Hollow's Mud and the plaza's Cobblestone are unchanged; shop and building floors stay Ground (`WorldLayout.TownFloors`), except the sell yard, which is gravel like the mill yard beside it. Midday's saturation is 0.2 (was 0.12) so the grass reads vivid at noon; the sky's pale blue air is unchanged. `BiomeData` starter and hills ground colours follow (data only). Trails (MapBuilder) use the new Ground.
- **Plots (PlotData, Shared/PlotPlatform, PlotService):** no more bare-dirt pads, aprons or tiles. The pad area and `TerrainGen.PlotLawn` (40) studs past it are Grass in every region (the lawn's edge is dithered, never on a cliff, a road or water). On each homestead stands a **dark grey concrete platform**: the "Pad" slab (the tier's square, 80/110/140/170/200) plus a "Land" slab for each bought 40-stud square sticking out past the tier (disjoint rectangles, so no two faces share a plane), each `PlatformThick` = 3 studs thick with its top **1 stud (`PlatformHeight`) above the grass**; a **ramp** (WedgePart, a darker grey) along every exposed edge: 6 studs (`PlatformRamp`) long, 0.97 high, a 9.5 degree slope (a Humanoid walks anything under 89; trucks drive on ground rays and have wheels 1.25 to 1.75 times the truck scale in radius). Convex corners stay open (nobody drives a corner). The slabs are CanCollide, anchored, in the plot's Atomic model like the old Pad (the Pad is still its PrimaryPart; Land and Ramp are in a "Platform" folder rebuilt on every claim, upgrade or expansion). Rails and corner posts still mark the base yard, a hair above the top (the posts are sunk 0.1); the sign stands on the grass past the ramps. Six looks (Charcoal, Slate, Graphite, Iron, Basalt, Ash) vary the grey and the rail colour.
- **Saves are untouched.** Layouts are plot-local studs and plot-local y = 0 now means the platform's top (the plot's origin moved up 1 stud, `HeightAt + PlatformHeight`), so every saved piece loads exactly as before relative to the floor it was built on. Nothing is migrated.
- **A bug found on the way:** `BlueprintPlacer.PlotCFrame` (the client's ghost, hammer, wire and copy tool origin) used world y = 0 for the plot, which is only right where the ground is level with y = 0; the homesteads' grounds run from -3.2 (East Field) to +7.2 (Orchard Edge). The placing ghost's aim (`BlueprintPlacer`) and the copy tool's (`BuilderTools`) also intersected the world plane y = 0, so on a raised plot the ghost slid sideways with the camera angle; both now aim at the plane of the platform's top. Client and server now share `PlotPlatform.Origin(index)`.
- Trees (`TreeFill.PlotRings`) are unchanged: they stand at least 62 studs off the pad, past the lawn and the ramps. `EnvironmentData.DecorBlocked` already covers the whole shelf and its blend (flat weight over 0), so no tufts, flowers or rocks on the platform or its ramps. The Climb and every other biome keep their own looks; only the home meadow, the Starter Forest, the town and every road changed.
- Economy: the model is unchanged (`lune run tools/economy` and `economy1` still pass their ranges): no walk or haul path moved, the sell station keep-out and the 14 pad centres did not move.

If something is off
- Roads look too dark or too flat: `TerrainGen.GravelMaterial` is one name (try "Pavement" or "Limestone", then set its colour in `MaterialColors`). Grass too neon or too pale: `TerrainGen.MaterialColors.Grass` / `LeafyGrass`. Blades wanted back: Terrain.Decoration = true in Studio (and `PlaceCheck`, default.project.json).

Studio checks
- [ ] Open the place with a fresh `rojo serve`. In the Output the `[PlaceCheck]` line wants Terrain.Decoration = false. If it says set it to false in the Properties panel, do that and save: the grass blades are gone and the meadow is flat.
- [ ] Spawn and look round the town in daylight: the meadow is a bright, flat green like Lumber Tycoon 2 (not dull, not neon), the street, paths, plaza edges, the parking lot and the sell yard are light grey speckled gravel, the plaza is still cobbles, the shop floors under the shops are red-brown earth. Compare with your LT2 screenshots; tell me which of green, grey and brown to move.
- [ ] Walk the Forest Path and the haul roads: grey the whole width (no brown verge). Hills, Snowfields, Volcano, Aether Isles and the Gloam Hollow keep their own looks. Look at a cliff or a steep hill side: red-brown, not yellow-brown.
- [ ] Noon, golden hour, dusk and night, and a rain or fog weather: the ground stays readable (nothing too bright at noon, grass not black at night).
- [ ] Walk onto a platform from the grass on all four sides, on foot, on the Xbox stick and on a phone: it is a smooth walk up a short ramp, no hop and no snag, at the middle of an edge and near a corner (a corner is a 1-stud step: you should still step up it). Jump on it, run along its edge.
- [ ] Drive a truck (Rustbucket, then a Logging Rig with a trailer) onto the platform from the road side and off again, slowly and at speed: it climbs the ramp without bouncing out, no wheel stuck, the trailer follows. Park a truck on a vehicle pad on the platform and respawn it: it sits on the pad, not under the platform. Drive along the edge on the ramp: fine, nothing flips.
- [ ] Place a hut (floor, walls, door, roof), a Sawmill, a belt and a wire: everything snaps to the platform top and sits ON it (not 1 stud in, not floating) and the ghost lines up with where the piece lands. Do this on a hilly homestead (Orchard Edge is 7 studs up, East Field is 3 down) as well as a flat one.
- [ ] Save and rejoin (or switch save slot and back): the layout comes back in the same places, and on a different pad too. An old save's plot loads on the platform, nothing buried, nothing floating.
- [ ] Buy a 40-stud square (Land panel): a new slab appears with the platform's ramps moving out to its edge, the same grey, flush with the old one (no seam you can feel, no flicker, no gap). Upgrade the tier: the slab grows and the squares keep their ground. Build on the new square.
- [ ] Look at the platform from the air and from the ground at several angles: no flickering faces on the top, the ramp edges or the slab's seams; the rails and corner posts sit above it; the sign stands on the grass past the ramp with its text readable.
- [ ] Grass right round the plot: plain green lawn out to about 40 studs past the platform, then the country; trees in clumps beyond it (they should not grow on the ramps or on the lawn). No tufts, flowers or rocks on the shelf.
- [ ] Visit another player's plot, and set a visitor down past the north edge: lands on the grass past the ramp, not inside the platform.
- [ ] Phone on Low quality: frame rate in the plot district is no worse than before (a plot is 5 to 40 anchored parts).

## LT2 window boxes and stepped display shelves (branch `claude/lt2-boxes`, 7 October 2026)

Connor sent two Lumber Tycoon 2 pictures: "Look at the Boxes in this image, I want our boxes to reflect closer to this" (a shop display case: items stand whole on stepped shelves, each on a solid colour block with its name) and "keep the box size accurate to the item inside" (a dark, near-black box with a see-through window face showing the real item model). Nothing here changes a price, a recipe or the economy (`lune run tools/economy` and `economy1` are unchanged).

**The box (`Shared/Art/BoxArt`, colours in `Shared/BoxLook`).** A dark charcoal box (walls 34,36,41) with the item seen through glass:
- `Box` is still the body (collision, grab, hover, prompts, the carried assembly) but is invisible; the dark `Back`, `Left`, `Right` walls and the `Base` floor are what you see. `Window` (front) and `WindowTop` are Glass at Transparency 0.5, they collide like the box, can be aimed through, and stand 0.03 stud off the walls and the box (no coplanar faces; a spec scans for it). The side that faces the aisle gets a `SideWindow` instead of a wall. The `Strip` across the top of the front is the accent colour with the item's name (no price, no billboard anywhere); the `Base` is the accent colour too, a hair wider than the box, with the sawmill/planer tier line on its front ("MILL, TIER 3 OF 5").
- `Contents` is a model of the item itself (`Shared/Art/ItemModel`): the real art (`AxeArt.Build`, `MachineArt.BuildAny`, `TruckArt` for vehicles, `BlueprintModels.Build` for furniture and buildings; small icons for gear, the lamp post and the Robux coins; a wrapped parcel for anything unknown), cut down to a low-detail copy (biggest parts by surface area, no scripts, lights, text, welds or seats), scaled to fit, welded and weightless: CanCollide, CanQuery and CanTouch all off, Massless, so a carried, dropped or loaded box behaves as before and the hover and grab rays hit the glass and the box, never the item.
- Accent colours (`BoxLook`): axes by TIER (Steel grey, Hardened green, Silver white, Cobalt blue, Gold, Obsidian violet, Inferno orange, Starfall cyan; Rusty brown), sawmills orange, planers pink, belts lime, chop saw and Sky Bin yellow, gear teal, blueprints blue, the lamp purple, trucks green, trailers slate, Robux gold (with a dark gold body and gold coins inside).
- Axes lie on their side (handle along X, blade up, broad side to the front window); vehicles lie along X, nose west, as the showroom parks them. The chop saw shows its head and the first 9 studs of table, not the 50-stud log infeed.

**The size rule (`Shared/BoxSize`, `Shared/ItemBox`).** A box is the item's real bounding box (`ItemModel.Extent`, measured from the model that is drawn) plus 0.6 stud each side and over the top and a 0.3 floor, never smaller than 2.4 x 1.9 x 1.7 (the name strip stays readable) and never bigger than a maximum: shelf boxes 3.1 x 4.6 x 3.6 (two stand side by side in a 7.2-stud row), sawmills 6.4 x 4.8 x 4.8, other machines 5.2 x 4.6 x 4.4, axes 5.2 x 4.6 x 2.6 (shown at real size), vehicles 15.5 x 7.4 x 8.4 (the old biggest). A thing bigger than its maximum is shown smaller, never squashed. Families share one scale, so the bigger sawmill, planer or truck is a bigger box (sawmills at 0.20 of real, planers 0.26, belts 0.40, vehicles 0.31); axes, plans, gear, the chop saw and the Sky Bin are fitted one by one. Examples: Steel Axe 4.5 x 2.7 x 1.7 (long and thin), Rickety Mill 3.6 x 2.2 x 2.8 up to Millmaster 200 Long 6.4 x 3.1 x 3.2, Sky Bin 3.0 x 4.6 x 3.8, Rustbucket 8.4 x 3.3 x 4.5, Logging Rig 15.5 x 5.7 x 5.1. The size classes are gone except three fixed classes for a box with no model (`BoxSize.Class`).
- Parts per box: a shell of at most 9 (`BoxLogic.ShellPartCap`) plus the item's copy (`ItemModel.ModelBudget`: axe 14, sawmill 18, machine 16, plan 8, gear and lamp 8, truck 32, trailer 28, Robux coins 3), so no box is over `BoxLogic.BoxPartCap` = 42 and an axe in the hand is 23 parts. `GameConfig.StorePartBudget` is raised 900 to 1200: the Tool Shed now shows 21 real items through glass (about 465 box parts) on top of its 630 shop parts, about 1,130 in all; the General Store is about 590.

**The shelves (`StoreStock` lanes, `ShelfLayout` rows, `ShopInterior.SteppedUnit`).** The flat tables are stepped display units: each row of boxes stands 0.22 stud higher than the row in front (to the back, at most 1.3 up), on a solid step, and every box stands on a PLINTH, a 0.3-high block in its accent colour. The Tool Shed's two units and the General Store's four are the same lanes as before except that the Tool Shed's aisle is 10 studs (the lanes grew 0.8 inward) and the General Store's two plan islands grew 2 studs inward (aisle 10), so two shelf-size boxes fit a row; the aisle spec still asks for 10. Machines that did not fit the east table spill onto the west table behind the axes; the General Store's gear, lamp and plan boxes all have a lane. The Tool Shed axe rack is a stepped wall shelf: every axe (the real `AxeArt` model) stands whole on its own step, each a little higher than the last, in front of a backing block in its tier colour with its name plate, and it still tags its real price when aimed at. The dealership: each vehicle's box shows the vehicle through its window, stands on an accent block on the plinth (`BoxBlock`), and the front row's boxes are turned round so their window faces the walkway; one vehicle per plinth with its sign, as before.

**Carry, truck, storage, open.** Nothing about carrying looks at a box's size except the aisle (the biggest shelf box is 6.4 wide in a 10-stud aisle). Opening a box: the whole model folds away (`BoxPoof` fades every part, window and item included, and the server destroys it) and the pickup, the placement ghost or the plot stock appears as before. A sawmill, planer, belt or Sky Bin box opened for placement loses its window and its item at once (an open dark box, `BoxArt.Open`) and shows the placement ghost; it is not spent until you place, cancelling keeps it (it just looks open) and you can press Open again, as before.

**Specs** (all new or updated, `lune run tests/run Box`): `BoxSize` (the rule and the margins; every shop item and vehicle: the box encloses what is in its window with 0.6 across and deep, 0.6 over the top and a 0.3 floor, the box dimensions equal the item's bounds plus margin or the minimum, shapes and sizes, maximums, part budgets), `BoxArt` (dark body, accent per category and tier, window flags Glass / 0.4 to 0.5 / collides like the body / 0.03 off, the item is weightless welded decor, no coplanar shell faces, no price text, BoxService boxes), `ShelfLayout` (no two boxes or plinths overlap and none leaves its lane or its step, for both shops; rows rise toward the back; the tallest box stays under the lamps), `StoreStock`, `DealershipLot` (box from the vehicle's bounds, on its block, out of the aisle), `BoxService`, `Foundations` (the budget), `AutomationLogic`.

**Studio checks (Connor):**
- [ ] Tool Shed from the door: dark boxes with a glass window on the front, the top and the aisle side, each showing the real item (axes lying whole, miniature sawmills, planers, belts, chop saw and Sky Bin), an accent band with the name, an accent plinth under each, rows stepping up toward the counter. The aisle is clear and the counter is at the back. The keeper still serves; the doors and hours behave as before.
- [ ] The axe rack at the back: seven or eight axes standing whole on their steps, each in front of a block in its tier colour with its name; aiming at an axe, its block or its plate shows the hover tag with the price.
- [ ] General Store (gear, plans, the lamp): every box shows its item (a lantern, a coat, a table, a barrel, the Small Shed in miniature); all boxes reachable; the lamp shelf shows three boxes in a row.
- [ ] Dealership: each vehicle on its plinth with its sign, its box on a coloured block at the aisle edge with the little vehicle visible through the window and the strip naming it; you can see the strip from the walkway; the vehicle beside it is unchanged.
- [ ] Hover: aim at a box through its window (mouse, Xbox screen-centre aim, phone tap): the name and price tag appears, and shows Closed / Out of stock / You already own this as before. No price is printed on any box.
- [ ] Grab with one press (mouse click, Xbox, phone tap) on the glass and on the strip: the box lifts at once, carried in the hand it moves as one piece, the item in it moves with it; carry three unpaid boxes (the fourth is refused as before); drop one on the floor and put one back on its shelf spot; walk it down the aisle and through the door.
- [ ] Pay at the counter: the box stays dark with the item in it; press Open (E / X / tap): the whole box, window and item together, folds away and the item appears (axe pickup, chop saw and plans into your stock, a vehicle on your pad). A sawmill, planer, belt or Sky Bin box opens to the placement ghost with its window and item gone and the empty dark box left in your hands; place it and it folds away, cancel and you keep the open box and can press Open again.
- [ ] Drive a boxed truck or carry a box onto a truck bed and off again; leave the game with a paid box (it is kept in storage) and rejoin: it comes back dark with its item in it and opens normally.
- [ ] Performance in the busiest shop (the Tool Shed with 21 boxes, the rack and a few players, on a phone at Low): the frame rate is no worse than before the change (about 500 more parts than the cardboard boxes).
- [ ] If an item looks wrong in its window (a model with stray parts, upside down, too small to read), send me the box's name: each item's look is one entry in `ItemModel` (turn, crop, part budget).

## Spaced-out shelves and the Lower / Higher quality choice (branch `claude/quality-picker`, 7 October 2026)

Connor, after the window boxes (#102): "space them out more, and to avoid issues with the phone vs higher end models like xbox and pc, just let them pick between lower quality (Phone) or higher quality at launch." Nothing here changes a price, a recipe or the economy (`lune run tools/economy` and `economy1` are unchanged).

### 1. Boxes spaced out

- **The rule** (`Shared/BoxSize`, used by `ShelfLayout`): `BoxSize.Gap` 1 to **1.5** studs between boxes side by side, new `BoxSize.RowGap` **2.5** studs between rows (it was the same 1 for both), and `BoxSize.Pitch` (boxes stacked front to back, the limited lamp's three) uses the row gap. The accent plinths are a quarter stud bigger all round, so they are still 1.0 apart side by side and 2.0 front to back. The Robux table's boxes (`RobuxShelf.Step`) follow the Gap, 4.3 centre to centre. Boxes and windows are not smaller: the size rule is untouched.
- **Tool Shed**: **wider, not longer.** The tables were 8.7 wide, one box a row; at 2.5 between rows they would have needed a 57-stud shop and pushed the General Store back across the town's flat zone (the terrain, forest and decor specs pin that ground). Now each table is **12.1 wide** (x 5 to 17.1 and -17.1 to -5; the aisle between is still exactly 10) so most rows hold two boxes with 1.5 studs between them, and the 45-stud-deep shop (z 95.2 to 140.2 at the same place) has room to spare at the back. The shop is **35.7 wide (was 29.1)**: `BuildingArt.ToolShedHalfWidth` 9.7 to 11.9, x -101.9 to -66.1 (the sell station keep-out starts at x -60); the roof's knee moves out with it (`KX = HX - 4.1`, the lower slope keeps its steepness), the lamps and the AXES / SAWMILLS signs hang over the new table middles (x +-11.05). The counter stays at the back wall, the Robux table behind it, the door and hours are as before. The belt kit and the Sky Bin now ride the axe table (lane kind `Fitting`) and the chop saw and planers the machine table, so both tables end about the same place (z 11 and 12 of 16.8). The rack on the back wall: 8 axes, each block 2.4 wide with **1.5 clear studs** between blocks (was 0.3), the name plates 3.0 wide, the axes centred on their blocks (the rack is 31 wide in a 34.5-wide wall). The firewood stack moved from the east wall to the **west** wall (the east side now faces the sell station keep-out, x -60); one planter (-103.5, 88) moved to (-105, 85.5) because the wider west wall reaches it, and `ToolShedFloor` is 4.5 studs wider on the west (x -106.5, so the grass does not grow under the logs).
- **General Store**: the two plan islands are now 9 studs wide (x 5 to 14 and -14 to -5; the aisle is still 10) and the plans are split between them, the first half west and the rest east (`BlueprintW` / `BlueprintE` lane kinds; the east island used to hold one box and the west one 16), so each has 2 boxes a row and 4 or 5 rows. The shop did not need to grow or move.
- **Dealership**: no change needed. The showroom's boxes are 10.9 studs or more apart side by side (the plinths are `BayGap` 1.5 apart, and a box is narrower than its plinth), the rows are a 14-stud walkway apart; `ShelfLayout.spec` now pins it.
- **Specs changed on purpose**: `BoxSize.spec` (Pitch uses RowGap), `ShelfLayout.spec` (the lane in the first test is longer, the overlap check is the new `ShelfLayout.Apart` rule; new tests: 1.5 / 2.5 between boxes on both real shops and 1.0 / 2.0 between plinths, aisle 10, nothing overflows, every lane is inside the walls, the Robux row fits, the rack's blocks are 1.5 apart and inside the walls, the showroom's gaps), `QualityBudgets.spec` (three new budget keys). No town layout number moved: `WorldPlan.spec`, `StoreLayout.spec`, `Foundations.spec`, `TownMarkers.spec`, `Terrain.spec` and the forest specs are as they were.

### 2. Lower / Higher quality

- **Where it lives.** The choice is `profile.settings.quality`, `"unset"` | `"low"` | `"high"` (`SettingsLogic`, so `ProfileSchema`'s template has it and `Migrate` fills and validates it, idempotent: every existing save and every new one starts `"unset"` and is asked once). It is account-wide (a save-slot swap keeps it), mirrored on the player attribute `SettingQuality`. The old four-way `settings.graphics` key still loads and is otherwise ignored (its Settings row is gone; a save that had picked `low` is recommended Lower on the first screen).
- **The join screen** (`QualityPickerUI`, UITheme parchment, layer 90 over everything): when the save has loaded (`ProfileLoaded`) and `SettingQuality` is `"unset"`: "How should the game look?", two big cards, **Lower quality (best for phones)** and **Higher quality (Xbox, PC, tablets)**, each with a one-line description, the device's recommendation pre-selected and tagged RECOMMENDED FOR THIS DEVICE (a touch-only screen: Lower; a console or a PC: Higher). A tap, a click, or A on the gamepad (it lands on the recommendation; the stick stays inside the panel; `GamepadNav`) chooses and plays. The character cannot walk while it is up. It sends `SetQuality` and tells `Quality` at once.
- **The server** (`QualityService`, remote `SetQuality`, `RateLimiter` 2 a second): drops it before the save has loaded, accepts only `"low"` or `"high"` (never `"unset"`, never anything else), writes the one setting and the attribute. Nothing else on the server reads it (a spec scans).
- **Settings** has `Graphics: Lower` / `Graphics: Higher`, one press switches (it replaced the Auto / Low / Medium / High row); the world follows at once.
- **The tier** (`QualityProfile.TierFor`, `Quality`): Lower is always the `low` budget; Higher is the device's own tier (Roblox's graphics level and touch-only detection, as before, `QualityBudgets.TierFor`) and never a heavier one than it reports, except a device that reports `low` (a phone, a bare tablet, graphics level 1 to 4) is allowed `medium`: the high world with the calmer motion. An unchosen save follows the device exactly as before. The Roblox `GraphicsQualityLevel` logic is not touched.
- **What Lower changes versus Higher** (all client-side, all `QualityBudgets`): (1) **no item copies in the shop boxes' windows** (3 to 32 parts a box): `QualityDressing` takes the `Contents` model out of every tagged shop box on the player's own client and tints the glass in the item's accent colour (`Shared/BoxWindows`; the server builds ONE box for everybody, so there is no second version per player and the server geometry stays the authority; switching back puts the same model back); (2) fewer decor models (148 vs 560), tufts only 90 vs 150 studs out, fillers 340 / 520 vs 480 / 600, fewer critters (8 vs 16), fewer swaying canopies, half the weather, no sun rays, no far blur, softer bloom, no leaf shadows (these were already `low`'s); (3) **shop lights reach 60%** as far with their shadows off (`LightScale`, lights inside the shop models); (4) **townsfolk animate within 70 studs** instead of 120 (`NpcAnimateRange`; talking and prompts are unchanged). **The streaming radius** (`StreamingTargetRadius` 640) is a place setting for everyone and cannot be changed per player; Lower lowers the client-built content radii instead (above). Prices, hover tags, grabbing, opening, hitboxes, collisions, attributes and sizes of a box are identical on both (`BoxWindows.spec` compares a real BoxService box before and after).
- **Specs**: `QualityProfile.spec` (wording, recommendation, picker once, tier table, the budgets), `SettingsLogic.spec` and `ProfileSchema.spec` (the saved setting: default, validation, migration idempotent), `QualityService.spec` (rate limit, bad values refused and the save untouched, needs a save), `RateLimiter.spec`, `Quality.spec` (the choice caps the device, live change), `BoxWindows.spec` (Lower strips the window contents, Higher keeps them, the same hover marks and attributes on both), `QualityPickerUI.spec` (shows once after the save loads, recommendation, tap / gamepad choice, sends the remote).

### Studio checks (Connor, nothing here has been seen in Studio)

**Spacing**
- [ ] Tool Shed from the door and from above: every box clearly apart from its neighbours (at least 1.5 studs of table between two side by side, 2.5 between rows), the window, the coloured plinth and the name strip of each readable on its own; the axes table (axes two to a row for the first four, then the belt boxes and the Sky Bin) and the machine table (sawmills, then the chop saw and the Hand Planer side by side, the other planers) both have room to spare at the back; the aisle between them is wide (10 studs, the red runner), the counter and the keeper at the back, the gold Robux boxes behind the counter, the barn door and hours as before; the roof is a gambrel as before, only wider.
- [ ] Aim at one box with the mouse, the Xbox screen-centre aim and a phone tap: you get that box's tag (name and price), never its neighbour's. Grab, carry one down the aisle and out of the door, put it back on its shelf spot.
- [ ] The axe rack: eight blocks with a clear gap between, each axe standing on its block and not hanging over its neighbour; the back room door on the east wall is clear of the rack and of the table.
- [ ] General Store: gear on the west wall, the lamp on the east, two islands of plans each 2 boxes a row, none overflowing; the aisle between the islands is wide; the counter at the back.
- [ ] Dealership: each box on its plinth with its vehicle behind it, unchanged.
- [ ] The town: the Tool Shed is a barn 6.6 studs wider (its east wall at x -66, west at x -102; its firewood stack now beside the west wall); walk from the spawn up the shop path: the path, the grass, the shop floors and the planters and flower beds near it look right, nothing clipped by the wider walls or roof, the planter that moved is not in the shop, the firewood is on the west side with ground under it, the AXES chip still floats over the shop and is readable on a phone from the spawn.

**Quality**
- [ ] New save, or an old one (every old save is asked once): after the loading screen the screen "How should the game look?" appears with Lower quality (best for phones) and Higher quality (Xbox, PC, tablets). On the **Xbox**: Higher is selected and marked RECOMMENDED, A chooses it, the stick moves between the two cards and stays on them. On a **phone**: Lower is marked, a tap on either chooses. On **PC**: Higher is marked, a click chooses. You cannot walk while it is up. After choosing, the screen is gone and never returns.
- [ ] Settings (the round button left of the cash): "Graphics: Lower" or "Higher" (what you chose); press it, the other shows; the Tool Shed boxes change straight away with no rejoin.
- [ ] **Phone on Lower in the Tool Shed**: every box is a dark box with a plain accent-tinted window and its name strip (no item inside); aiming and tapping a box still shows its name and price; grabbing, carrying, paying and opening work exactly as on Higher; the frame rate is clearly better than before (try the same shop on Higher on the phone).
- [ ] Higher on the PC / Xbox: the boxes show their items as before.
- [ ] Choose on one device (say the phone: Lower), join the same account on the PC: no screen; it is Lower there too until you change it in Settings. Change it in Settings on the PC to Higher and rejoin on the phone: Higher there.
- [ ] Pick Higher on a phone: the world has the boxes' items and all the scenery; the Output says `[Quality] medium (..., chose high)`. Pick Lower on a PC: `[Quality] low (QualityLevel10, chose low)`.
- [ ] Send me the Output `[Quality]` lines if a tier does not match what you picked.
## Load time 2 (LOAD-02, 7 October 2026): meshes side by side, a deferred build, a loading bar

Connor: "loading is still very slow too so try to speed that up."

**Before (his Studio Output of 7 October, a fresh server, Studio, no DataStore). Compare your next run to these:**

| Where | Before |
|---|---|
| `[MapBuilder] World built in` | 35.6 s (terrain 13.3 s; the town 13.81 s of which the shops 4.8 s and trees 1.6 s; points of interest 2.5 s; Skyroot and isles 3.07 s of which the Lumenwood 3.0 s) |
| `[Load] GameServer waited ... for the world (SellArea)` | 35.5 s |
| `PlotService.Init` | 10.71 s |
| `NPCService.Init` | **60.00 s** |
| `[Load] GameServer init done in` | 70.8 s |
| First player could play | server up 97 s |
| Client `HUD Start took` | 34.81 s (it waited for the world, and held every other controller) |
| Client `ForestFiller plan` | 11.5 s on the main thread after joining, then 1,322 section trees planted in 23 s |

**The 60 s was not a timer. It was 153 mesh loads, one after another.** `NPCMeshes.Dress` (called from `CharacterArt.Build`) asks `MeshKit.Create` for every piece of each townsperson (17 pieces for each of the nine uploaded NPCs, 153 pieces, 146 distinct mesh ids), and `MeshKit` loaded each with `AssetService:CreateMeshPartAsync`, a network yield of about 0.4 s, serially. 153 x 0.4 s = 60 s. `PlotService.Init`'s 10.7 s was the same thing: `ItemMeshes.LoadAsync` loading the plot kit's 32 meshes one at a time (about 0.33 s each), not building the 14 pads. The "61 loaded" in the build check were the ones loaded by then (axes, trees, vehicles). The meshes always loaded fine; they were just never loaded side by side.

**What changed, and the expected saving:**

| # | Change | Expected saving |
|---|---|---|
| 1 | `MeshKit.Preload` + `Art/MeshManifest`: at the first line of `MapBuilder` every uploaded mesh the server will ask for (356 distinct ids: vehicles, axes, NPCs, the plot kit, trees, the building kit; plus the 105 town meshes only if `TownMeshes` is on) starts loading 24 at a time in a background thread (`Shared/WorkPool`, a join barrier), while the terrain is written (network time and CPU overlap). A `Create` for an id that is being loaded waits for that load instead of loading twice. A wheel or Hull kit piece keeps its collision (the manifest carries it). | NPCService.Init 60 s to under 1 s (everything is cached by then); PlotService.Init -10 s; the dealership lot, axes on the racks, Lumenwood and the first trees stop loading meshes one at a time inside the town and sky build: most of the 3 s Lumenwood and a good part of the town's 13.8 s |
| 2 | `NPCService.Init(map, { defer, onBuilt, onDone })`: Murph is built at once (his camp is the tutorial's first stop), every other townsperson is a tier-1 step of the deferred queue, nearest the player first; shop doors, hours signs and the hours clock do not wait for them. Old Hank's Talk prompt is hooked the moment he is built (`onBuilt`), not after all of them. | Init 60 s to about 0 s; the townsfolk appear within the first seconds after joining |
| 3 | `PlotService.Init` no longer waits on the plot kit's meshes: they load in a background thread, Init waits at most 3 s on the `itemMeshes` gate, builds the pads part-built if they are late and dresses them (redraws every pad) when the meshes land | 10.7 s to about 0 s (the preload has them cached) |
| 4 | Deferred build (`Shared/LoadQueue`, `ServerScriptService/LoadState`, `MapBuilder`): after SellArea goes in, the town's lamps, fences, props, signs, path rounds, greenery and dealership lot (tier 1), the boulders, mushrooms, points of interest, trails, road signs, scenery, boulder clusters, landmarks and backdrop (tier 2, split into 400 to 500-stud cells), the volcano's crater and the whole sky (tier 3) are built a time slice at a time (12 ms a frame), lower tier first, nearest the players first (asked again before every step). The shops, parking lot, gondola stations, the tutorial grove, the north strip, the edge walls and the clock stay in the ready path. | World built about 35.6 s to roughly terrain 13 s + sawmill, shops, sell area, lot and camp about 6 s; the 2.5 s of points of interest, 3 s of Lumenwood and isles, 1 to 3 s of scenery, the greenery, props, boulders and the rest move behind the player |
| 5 | The forest plan (`WorldPlan.Trees`, 6.7 s of one block in Lune, the 11.5 s on Connor's client) takes a `pause`: `TreeFill.Extra` offers the frame back after every placement attempt (same trees, spec-checked). The server's planter and the client's ForestFiller pass a time slice (12 ms and 8 ms a frame). The planner calls that are still one block (`Scenery`, about 1.2 s in Lune) are their own queue steps. | No more 5 to 11 s freeze right when the player joins, on the server or the client |
| 6 | Client: `HUD.Start` returns as soon as the HUD is drawn (the wait for the server's `Remotes` runs in its own thread), so every other controller starts at once instead of 35 s late; `Net.Remote` waits in short tries (no "infinite yield" warning per controller). The loading card has a bar and a line driven by the server's milestones (`workspace.LoadStage`: starting, terrain, town, world, services; then "Loading your save..."), e.g. "Shaping the land... 40%". The "Loading your save..." card and the tutorial are unchanged. | The client shows progress from the first second and its lighting, wind, ambient, NPC and town controllers run during the wait |
| 7 | One summary line and per-step lines (below) | - |

**Not changed, on purpose:** terrain writing (13.3 s). It is CPU on one thread (a chunk's heights, materials and `WriteVoxels`), the terrain and the town cannot overlap in a single Luau VM, and the town's ground check needs the chunks. The terrain prebake (HANDOFF.md section 12) is still the next win and is Connor's one manual step; it was not done here because it needs Studio. The shops (4.8 s) stay in the ready path, because ShopService, NPCService and the doors read them at Init; most of their time was mesh loading (now overlapped). Nothing was moved out of the terrain pass, so a player is never in a world without ground. Plot pads are not built lazily: by the mesh numbers above the pads were not the cost, and every slot is looked up by index all over `PlotService`.

**Readiness gates** (`Shared/ReadyGates`, one instance in `LoadState.Gates`): `meshes` (the start-up preload is done), `terrain`, `town`, `world` (SellArea in; GameServer starts), `services` (every service Init has run, GameServer listens for players), `firstPlayer` (a save is loaded and someone can play), `npcs` (the last townsperson is in), `itemMeshes` (PlotService's kit meshes; PlotService.Init waits at most 3 s, then builds part-built and dresses the pads when it opens), `deferred` (the queue and every tracked job are done). Remotes: no deferred system has a remote. Every handler connected before `Players.PlayerAdded` already refuses a player without a loaded profile, and `PlayerAdded` is connected only after `services`, so a remote before the services are up is refused, never an error. `ReadyGates.Guard(name, fn, onRefuse)` is the refuse-while-shut wrapper for any future handler of a deferred system (spec'd).

**Output lines.** Every old `[Load]` line is kept. New: `[Load] +Xs stage terrain|town|world|services` (the loading bar's milestones), `[Load] +Xs meshes: N of M loaded, F failed in Ts`, `[Load] +Xs deferred build starts: N steps queued`, one `[Load] deferred <step> took Ts (done at +Xs)` for each step (many small steps of one job, such as the boulder cells, print one `deferred <job>: N steps took Ts in all` line), `[Load] NPCService.Init built Murph ...` and `all townsfolk built ...`, `[Load] PlotService: ...` if the kit meshes were late, `[Load] +Xs first player <name> can play`, `[Load] +Xs everything is built: N deferred steps (F failed) in Ts of work`, and the one to read first:

`[Load] ready for play at +X s; fully built at +Y s`

X is the first player's `can play` (their save loaded); Y is when the deferred queue and the forest are both done. Both count from the server scripts' start.

**What I could not measure** (no Studio here): the real numbers. Expected on a cold Studio Play, from the figures above: terrain 13 s, the ready path done at about 20 to 22 s (was 35.5), NPC and Plot Init about 1 s each (were 70.7 together), the first player able to play near 25 s instead of 97 s, and everything built (townsfolk, forest, scenery, isles) a minute or so later. If `CreateMeshPartAsync` turns out to be serialised by the engine, the preload will not be 24 wide and the numbers will say so (`meshes: ... in Ts`); the server is still never blocked by it.

### Studio checks (Connor)
Copy the whole `[Load]` output (server and client) and compare with the table above.
- [ ] Cold Play in Studio: Output has `[Load] ready for play at +X s; fully built at +Y s`. X is far under the old 97 s. Note X and Y
- [ ] `[Load] +Xs meshes: N of M loaded, F failed`: F is 0 (it was 0 before). `NPCService.Init built Murph` and `PlotService.Init` are each under about 2 s in the `[Load] GameServer ... took` lines
- [ ] On a phone (or Device Emulator) the card shows a bar and "Shaping the land..." then "Building the town..." then "Loading your save...", not a frozen "Building the world..."; note the time from tap to first playable frame on Studio and on the phone
- [ ] First minute in the town: Murph is at his camp at once; the other townsfolk (Millie, Old Hank, the keepers, the walkers) appear one by one within a few seconds (nearest you first); shop doors, signs and the hours still work; talk to Old Hank at the Land Office: he opens the plot sale
- [ ] The frame rate stays smooth while the deferred build runs (you can walk, chop and sell from the first second); no hitch of a second or more when the forest plan runs (it was 6 to 11 s)
- [ ] After the deferred steps finish (Y), nothing is missing compared with the old build: all three shops with their keepers, every NPC, the lamps, fences, props, signs and greenery, the dealership lot, boulders, scenery, points of interest (lookout, cabin, cave), trails, the lighthouse, docks and footbridge, the backdrop mountains and the volcano's crater, the Skyroot with its isles, bridges, clouds and Lumenwood, the Sky Shards, the Cloud Chutes and the forge, the waterfall, the gondola cable, trees everywhere, 14 plots with signs, platforms and rails
- [ ] Walk or run toward a far biome in the first minute (the volcano, the isles): its decor is built nearer first as you go (the queue follows the player); nothing is missing at the end
- [ ] Gondola: stand at the town station right after joining and press Ride: it works (the stations are in the first build; the cable comes later)
- [ ] Join with a saved game (a plot with buildings): the plot loads with its meshes; the sign, rails and corner posts have their meshes (if Output says `PlotService: the plot kit's meshes landed late`, the pads were dressed afterwards and your placed pieces may be part-built until you rejoin: tell me)
- [ ] Join with two players (Test, Clients and Servers): both can play; the second one's join is not slower; both see the townsfolk, Murph, the isles
- [ ] Leave and rejoin the same server: your save, plot and truck are back; no errors
- [ ] Sell and buy right after joining: sell logs at the pad, buy an axe at the Tool Shed in the first minute; the keeper serves
- [ ] The plot picker right after joining (Old Hank, or the Land Office counter, or a returning owner's picker): it opens, all 14 pads are listed and claimable; claiming works
- [ ] The tutorial: Murph's steps still run in order, the "Loading your save..." line is shown while the save loads and then goes, and no tutorial step waits on the deferred build
- [ ] No red lines in Output; `[MapBuilder] ... failed` lines, if any, name the step (a deferred step's failure is warned once, with a traceback, and the rest still builds)


### Join race fix (branch `claude/join-race-fix`, 7 October 2026)

Connor, after the faster-load merge (#103): "Now it loads the player so fast it glitches and won't let you move, but loads the plot and won't let you select one." His Output (fresh server): world ready +6.4 s, the deferred build starts +6.6 s, `GameServer init done`, `Elucidhealer618: loading the save`, ten client controllers each `Start took 6.35s`, save loaded +8.4 s, `first player can play`, `joined (cash $83)`, deferred steps run to +11.9 s.

**Root causes (read from the code; not reproduced, there is no Studio here):**

1. `MapBuilder.server.luau` (the end of the script, `Players.CharacterAutoLoads = true` and the `LoadCharacter` loop) let every player in the instant the terrain and town were built (+6.5 s). That was before GameServer had started its services (`services` at +6.8 s), before the save had loaded (+8.4 s), before `PlotService.Init` made the 14 pads and the Land Office, before Murph, and just as the deferred build began to fill the town around the spawn. Nothing asked the client to stream the spawn area in (`StreamingEnabled`, `PauseOutsideLoadedArea`, radius 640; only the gondola, vehicles and the plot picker ever call `RequestStreamAroundAsync`). So the character stood in a half-streamed, still-changing world (a paused or jittering character) and the loading card stayed until the save arrived. Before #103 the whole world existed before anyone spawned, which hid this.
2. The client controllers now start at +0.2 s (`Client.client`), but most block in `Net.Remote` until the server makes `Remotes` (+6.6 s). Nothing told the server that they were listening. The server fires one-shots (the plot offer, the save slots, cash) and sets `ProfileLoaded`; any fired before a handler was connected is lost for good, and the client never asked again. `PlotPickerUI` is driven only by the `PlotOffer` event.
3. The quality picker and the plot picker opened together on a first join of an old save (every save starts `SettingQuality = "unset"`, and a returning owner gets the plot picker at join): `QualityPickerUI` (layer 90, full-screen backdrop that eats input, `controls:Disable()`) sat over `PlotPickerUI` (layer 80, `WalkSpeed = 0`, scriptable camera). The plot picker was drawn but its buttons were under the quality backdrop, and two movement locks were held at once. `PlotPickerUI.unlock` also restored whatever speed it had saved, with no guard against a saved zero.
4. `PlotService`'s late-mesh redraw (`redrawSlot` over all 14 pads) calls `drawBounds`, which `ClearAllChildren`s the pad's platform slabs and ramps and rebuilds them: a player standing on a pad when the plot kit's meshes land late falls through it for a frame. (Not seen in his Output, which has no "meshes landed late" line, but it is the same kind of race.)

**Fixes:**

- `Shared/JoinFlow` (pure, `tests/JoinFlow.spec`): the order a player is let in. `MapBuilder` now never turns `CharacterAutoLoads` on and loads nobody. `GameServer`'s `enterWorld` (called after the save is loaded and the account is set up) waits for `JoinFlow.FirstPlayerGates` = terrain, town, world, services, plots, murph (`LoadState.Gates.WaitAll`, 90 s at most), asks the client to stream the spawn (`RequestStreamAroundAsync`, 8 s at most), loads the character, waits until it has stood on the ground for 0.3 s (4 s at most, `JoinFlow.Settled`), then waits for the client's `ClientReady` (12 s at most). Only then `ProfileLoaded` is set and `LoadState.PlayerCanPlay` runs. Every wait is bounded and a failure still loads the character. GameServer respawns the dead itself (`JoinFlow.RespawnDelay`, `Players.RespawnTime`), because auto-loading stays off.
- New gates `plots` (the pads, Land Office counter and picker data, set after `PlotService.Init`) and `murph` (set after `NPCService.Init`, which builds him before it returns). The rest of the townsfolk (Old Hank included), the decor, the scenery and the sky stay deferred.
- Handshake: new remote `ClientReady` (client to server, budget 2/s). `Client.client` fires it once every controller's `Start` has returned (or after 20 s), repeating every 3 s until the save is in. `ServerScriptService/JoinSync` records it and resends state through registered resends (cash, `PlotService.Resend` for a waiting picker, the save slots); the resend also runs right after the release. Each is state the client applies, so hearing it twice is harmless.
- `Shared/PickerSequence`: quality screen first, plot picker second, never both. `QualityPickerUI` and `PlotPickerUI` ask for their turn and give it back; the plot picker keeps the newest offer while it waits (`pendingOffer`) and opens when the quality screen is done. `PlotPickerLogic.SafeSpeed` stops a saved zero ever being restored; the picker waits for the humanoid on a new character; the quality screen gives the controls back on any respawn.
- `Shared/PlotRedraw` + `PlotService.RedrawLate`: a pad with a player within 90 studs is not redrawn; it is tried again every 2 s.
- Output lines kept; new: `[Load] +Xs character spawned at +Xs for <name> (world ready, area streamed, standing on the ground)` (server), `[Load] +Xs client ready handshake from <name> (Ns after it joined)` (server), `[Load] client ready handshake Ns after the client started (N/N controllers started)` (client), `[Load] <name>: state sent again to the client (N resends)`, `[GameServer] <name>: world gates open / spawn area streamed / client ready` laps.
- Expected: the first player can play at about +10 s (world ready ~6.5 s, then the save ~1.7 s, a stream and a landing under a second), not 97 s. No economy change (`lune run tools/economy` and `economy1` are unchanged).

### Studio checks (Connor), join race fix
Copy the `[Load]` lines (server and client) if anything is off.
- [ ] Fresh server: join and move at once (WASD, Xbox stick, phone thumbstick, jump): the character walks normally the first moment the loading card goes. Output has `character spawned at +X s ... (world ready, area streamed, standing on the ground)`, then `client ready handshake`, then `first player ... can play`, and `ready for play at +X s` is near 10 s.
- [ ] No falling, no teleport or jitter in the first second; the ground, the sawmill, Murph's camp and the Land Office are there when you can move.
- [ ] First join of a save that never chose a quality: the Lower / Higher screen shows alone, you can choose; right after, the plot picker (if your save owns a plot) opens on its own with all 14 pads, and pressing BUY / CLAIM claims the plot you are looking at; Next and Previous work; you can then walk.
- [ ] Choose Lower, then plot; rejoin and choose Higher, then plot; a save that already chose (rejoin): no quality screen, the plot picker opens at once.
- [ ] Pass ("Not now" / B) on the plot picker: it closes, you can walk.
- [ ] A save with no plot: walk to the Land Office counter (or talk to Old Hank once he appears): the picker opens and BUY PLOT works.
- [ ] Two players (Test, Clients and Servers): both can move and claim; the second join prints its own `character spawned` and `client ready handshake` lines.
- [ ] Leave and rejoin during the deferred build (while `[Load] deferred ...` lines are still printing): you can move at once, the picker opens, nothing is missing at the end.
- [ ] Die (reset character): you respawn after about five seconds, with your axe and hammer.
- [ ] If Output says `still waiting on ... after 90s; letting them in anyway` or `no ClientReady after 12s`, send those lines: they name the gate or the client that never answered.


## Owner hub 2: Paid items, and a calmer panel (branch `claude/owner-panel-2`, 7 October 2026)

Connor: "the owner panel needs more refinement, and a way for me to give them paid items such as 2x and lux axe, plus any future ones we create."

**Paid items.** New PAID ITEMS tab (owner, or a CUSTOM role with the new **Gifts** power, themself only). The list is `Shared/PaidItems.All()`, built from `Shared/StoreData` (the same passes and products the Robux store uses), so a pass or product added to StoreData is in the owner's list at once, with its name, kind (Permanent pass, Tool / axe, Cosmetic, Timed booster, Consumable), how it is given and what a revoke does. Optional StoreData fields `kind` and `revocable` override the guess. Items with no Creator Hub id yet (Tow Service, Timber Classic, Paint Shop, 2x Wood, Instant Delivery) are listed too, and can be given.

How a grant works: `MonetizationService.OwnerGrant` runs the same effects as a purchase (the pass switch and its listener, which gives the Lux Axe and the Timber Classic truck; the cash pack through `EconomyService.AddCash`; the boost and Instant Delivery helpers) with no Robux prompt, no receipt and no purchase analytics. A pass grant is saved in the new `profile.ownerGrants` (apart from `profile.passes`), the join check ORs it in and never strips it, and a revoke only ever removes the grant (a pass they also bought stays). Every give and revoke is also written to `profile.ownerGrantLog` (last 30: who, what, when) and to the hub's LAST ACTIONS and the `[Admin]` Output line.

- [ ] Studio, you alone: OWNER, tab PAID ITEMS. Every store item is listed with what you own ("NOT OWNED" at first). Tap 2x Cash: the page names it, says how it is given; GIVE 2x CASH TO <you> asks "SURE?", press again: the strip says "Gave 2x Cash to <you>." and the row now says OWNED (granted). Sell some logs: the sale is doubled.
- [ ] Same for Lux Axe: the axe is in your hotbar once (not twice if you press again: the button is off with "They already have Lux Axe from an owner grant."). Rejoin: still there. Reset or switch save slot: still there.
- [ ] 2x Wood: pick a length (1 hour, 1 day, 2 days, 7 days), give it: trees drop twice the logs; the row says ACTIVE (n h left); giving again is refused ("already running"); REVOKE ends it. $1,000 and $10,000: cash arrives; near the cap it says the wallet can't hold it. Instant Delivery: one use; REVOKE takes it back.
- [ ] REVOKE the Lux Axe: the axe leaves your hotbar (a Rusty Axe is there if it was your only axe); 2x Cash revoke: sales are single again. Rejoin: they stay gone. Timber Classic: give works (the truck box arrives), REVOKE is off with "can't be taken back".
- [ ] A friend (Test, 2 players): pick them in the player bar, give 2x Cash and Lux Axe: they get a toast "The owner gave you ...". They leave and rejoin: both are still theirs (`OWNED (granted)` on your list). REVOKE one: it is gone for them at once and after a rejoin. A friend who really owns a pass (or you buy it as them) shows "OWNED (bought)": REVOKE says only an owner grant can be revoked.
- [ ] A second test player made HELPER, MODERATOR, BUILDER and then TESTER: none of them has the PAID ITEMS tab, and typing `/paidgive Bob pass_LuxAxe` as them does nothing (the red line says the Gifts power is needed). As CUSTOM with only "Gifts: paid items for themself": the tab is there, giving to themself works, picking anyone else shows "Your Gifts power only gives to you", and there is no REVOKE.
- [ ] A new store item shows up: in `Shared/StoreData` add a pass (copy an entry, change `key`, `name`, leave `id = 0`) and press Play: it is in PAID ITEMS with its name and kind, and GIVE works. Remove it again.
- [ ] Chat: `/paidlist <player>` (the item ids), `/paidgive <player> <id> [hours]`, `/paidrevoke <player> <id>`.

**The panel.** Tabs now run PLAYERS, GIFTS, PAID ITEMS, WORLD, ROLES, LOG (SELF moved into PLAYERS under ON YOURSELF; DELEGATES is ROLES; the last actions and the chat command list are in LOG). A header that does not scroll says who you are and your role ("Connor | OWNER", "Bob | DELEGATE (MODERATOR) | 42 min left"). Search boxes on the players list, the items list, the paid items list and the commands list. Players and items you used lately come first (a star). B / Esc go back ONE level: cancel a pending confirmation, clear the tool search, leave a paid item for its list, clear a list's filter, and only then close; the X closes at once. LB/RB and LT/RT change tab. Rows are taller on a pad (64) and a phone (56). On a narrow panel the six tabs wrap onto two rows of three. A button that can't go is dim and says why under it ("Can't yet: ..."). Kick, ban, take and set cash, reset tutorial, revoke (hub and the delegate list), unban, giving and revoking paid items and shut down all use the same second press. The strip says what happened ("Gave Lux Axe to Catman9732."). Every power in the CUSTOM list has a help line. New: UNBAN (owner only; type the numeric UserId; it was chat-only).

- [ ] Xbox (or the pad in Studio): OWNER opens on the first tab; LB/RB and LT/RT change tab; stick walks header, tabs, list rows (big, ringed), the list scrolls to keep the ring in view; in PAID ITEMS, A on an item opens it, B goes back to the list, B again closes the hub. B with a SURE? button showing cancels it ("Cancelled. Nothing was done.") and keeps the hub open. B with a search typed clears it first.
- [ ] Phone emulator (a small phone, portrait and landscape): no sideways scrolling anywhere; tabs in two rows of three; chips (roles, amounts) wrap instead of squeezing; every row is a thumb tall; the header strip and the status strip stay on screen.
- [ ] PC: PLAYERS: type part of a name in "Find a player": the list narrows; a star marks players you used lately and they sit at the top. GIFTS: recent gifts have a star and sit first in All. LOG: type `ban` in "Find a command".
- [ ] The tool search (title box) still finds tools across tabs, now including paid items and unban; a delegate only finds what they may use.
- [ ] Everything old still works: GO TO, BRING, HEAL, FREEZE, STATS, RESET TUTORIAL (now asks twice), KICK, BAN, GIVE/TAKE/SET CASH, UNLOCK ALL BUILDINGS, GIFT, the clock tools, ANNOUNCE, SHUT DOWN, SUPER RUN, GOD MODE, GO TO SPAWN, GRANT/REVOKE roles (REVOKE now asks twice).

## Plot picker: you can see which pad you are choosing (branch `claude/plot-picker-view`, 7 October 2026)

Connor, after the join race fix: "when I load it's not showing me which plot it's selecting, it's just letting me pick one and then teleports me when it loads."

Not one guessed cause; the picker now has three independent ways to show the choice, and a fade for the claim:
- **Camera held every frame** (`PlotPickerUI`): while the picker is open a render-step (`BindToRenderStep`, priority just after Camera) sets the camera Scriptable and glides it to the pad's shot each frame, so a respawn, the default camera script or another screen cannot take it back (this was the likely cause of seeing only your spawn). Unbound on close; the camera type goes back to Custom (never left Scriptable).
- **Streaming**: `RequestStreamAroundAsync` now waits up to 12 s per request (in its own thread), is asked again every 5 s, and the panel shows "Loading view..." until it returns. Previous / Next / Claim never wait on it.
- **Map card** (`Shared/PlotPickerMap`, spec `PlotPickerMap.spec`): a 112 px card inside the panel with every pad from the offer's x / z (north up): chosen pad big and gold, open pads green, taken pads grey. Needs no streaming. Tapping the card picks the nearest pad.
- **In-world marker**: a client-only tall translucent neon pillar with an always-on-top outline and a name tag ("Pine Ridge", "(taken)" when taken) at the offer's coordinates. Moves with Next / Previous, destroyed on close. Needs no real pad.
- **Claim fade**: when PlotSlot is set while the picker is open, the screen fades to black over 0.2 s showing "Claimed <pad>!", the picker closes behind the black (camera back on your character), holds 0.4 s, fades back over 0.2 s.
No new remotes, no server change, no economy change.

### Studio checks (Connor), plot picker view
- [ ] Join (or Old Hank / Land Office): the picker opens and the camera swings from your spawn to the chosen pad, looking at it from up and behind; the panel's map card shows 14 dots, the chosen one big and gold.
- [ ] A tall coloured pillar with the pad's name stands on that pad and shows through trees and buildings. Green for open, grey for taken (name says "(taken)").
- [ ] Next / Previous: the camera glides to the next pad, the pillar jumps there, the gold dot moves, the title and the price update together. Tap a dot on the card (phone, mouse): it selects that pad.
- [ ] A far pad: "Loading view..." shows under the panel until the ground is there; the buttons work the whole time. If the ground never fills in, the card and pillar still tell you which pad.
- [ ] Respawn or reset while the picker is open: the camera stays on the pad shot.
- [ ] Claim: the screen fades to black with "Claimed <pad>!", then fades into your plot (no hard cut). "Not now" / B closes with no fade and the camera returns to your character.
- [ ] Phone: the card does not touch the thumbstick or jump corners; Xbox: D-pad still walks Previous / Claim / Next (the card is not selectable).

## Final pass over everything not yet seen in Studio (branch `claude/final-pass`, 7 October 2026)

A read-through of the join flow, boxes and store, owner hub and paid items, mill tiers, planers and belts, plot platforms and the load pipeline, looking only for real bugs. Fixed:
- **No character after one failed load** (`GameServer`): `LoadCharacterAsync` was one pcall; a failure at join left the player with no character and a dead player's respawn failure left them dead for good. Now `JoinFlow.LoadWithRetry` (3 tries, 1 s apart, stops when the player leaves) for the join, the respawn, the save-slot swap and the fallback.
- **ClientReady could be lost** (`Client.client`, `JoinFlow`): the client fired 6 times over 18 s, the server only listens once its services have started. Now it fires every 3 s for up to 90 s (`JoinFlow.ClientReadyTries`) until the save is in; the server still releases after its own bounded wait.
- **Plot picker lock after a close** (`PlotPickerUI`): a respawn that finished after the picker closed locked WalkSpeed and the camera with nothing to undo it. It checks `open` again after waiting for the humanoid. Its three buttons also shrink their text on a narrow phone panel instead of spilling.
- **Quality screen** (`QualityPickerUI`): closes (controls back on) before it talks to the server.
- **Hover tag** (`HoverTagUI`): placing the tag no longer errors on an item destroyed since the last aim check.

### Studio checks (Connor), final pass
- [ ] Join on a cold server: Output shows `client ready handshake` and `state sent again to the client`; the plot picker (returning owner) and the cash show without a rejoin.
- [ ] Die and reset a few times, in town and on your plot: you always come back with a character.
- [ ] Plot picker open, then claim while resetting: you can walk and the camera is yours afterwards.
- [ ] Phone (or the phone emulator, narrow): PREVIOUS / CLAIM FOR $... / NEXT stay inside their buttons.
- [ ] Quality screen: tap a card; movement works at once.
- [ ] Aim at a shelf box, then buy and open it quickly: no red error in Output.

Left alone, for Connor to decide: a log hand-dropped at a sawmill or planer that is busy waits; after `AutomationLogic.HandWindow` (4 s) untouched it counts as belt-fed, so rare or figured wood hand-fed behind another job is refused ("rare") and the throughput cap applies. Picking it up and dropping it again resets the clock.

## NPCs turn to face you while you talk, and every NPC speaks in the dialogue box (branch `claude/npc-talk-lock`, 8 October 2026)

Connor's playtest: "Dale the NPC doesn't have our new chat box system and when you talk to NPCs they should lock on you until the chat goes away."

- **Dale and the other keepers.** Reading the code, Dale was already routed to the box like Tink and Hazel (`DialogueService` -> `DialogueUI`), but a keeper's plain hello was a single line (the shop's "Trucks are on the board..."), while everyone else gives a greeting plus a line of their own. A keeper's hello is now the same multi-line press-to-continue talk: their greeting, the shop's line, one of their own lines (`DialogueFlow.KeeperExtras`, `DialogueFlow.ServerLines`; offers and replies stay one short card with Yes / No). If Dale still shows only a small bubble in Studio, that is the walk-up chatter (`NPCDialogue.AutoBubbles`, left on by Connor's decision); tell Claude.
- **Still on the old one-off path, now in the box:** Old Hank (with a plot, or the Land Office "come up to the counter" line, were server toasts: `PlotService.Speak`) and the Hermit's "too far to hear you" (was a toast). Murph, Millie, Gus, Rosa, Pip, Bram, Old Tolly and Cap'n Moss already used the box (generic client talk); Tink, Hazel, Dale and the Hermit's quest lines already came through the server's box.
- **Lock on.** `NPCTalkService` (server) records who is talking to each NPC: set by the Talk prompt (in reach), ended by the box closing (new `"end"` intent on the Dialogue remote, rate limited, names an NPC id), or by itself when the player walks 30+ studs off, dies, leaves, the NPC is removed or lies down, or a box is left up past its 90 s timeout. While anyone is talking the NPC carries the attribute `TalkWith` (the UserId to face). Rules in `Shared/TalkLock` (specs `TalkLock.spec`, `NPCTalkService.spec`): the most recent talker wins, the nearer on a tie, the NPC lets go only when nobody is talking.
- **Visual only.** NPC poses were already client-driven (standing NPCs turn toward you on each screen; walkers follow the shared clock), so the server only publishes the attribute. `NPCController` turns the body toward the partner at any distance (yaw about Y at the usual turn rate, head following), keeps all idle, work and wave animations running, and a walker holds where it stands while its partner talks (no sliding). When the attribute goes away it turns back to its normal facing; a walker eases back onto the clock like after any lag. This screen's own open box counts at once, before the attribute arrives.

### Studio checks (Connor), talk lock
- [ ] Talk to Dale at the Dealership: a box with "Hey hey!" (or another greeting), then the shop line, then one of his own lines, a press each; B or the last press closes it. Same for Tink and Hazel.
- [ ] While the box is open Dale turns to face you (smooth, no tipping) even if you shuffle to either side, and keeps his idle (wiping his brow) going. Close the box: he turns back to the way he was standing within a second or two.
- [ ] Do it with Millie, Gus (stand 10 studs off) and Murph: same turn, same return.
- [ ] A walker (Rosa, Pip or Bram): talk to one mid-stroll. She stops where she stands and faces you; close the box and she resumes (she may step quickly back onto her route if you talked for a while).
- [ ] Walk away mid-talk (past about 24 studs): the box closes and the NPC goes back to normal. Same if you die or reset mid-talk, or leave the game.
- [ ] Two players on one NPC (Studio "Start Server" with 2 players): the NPC faces whoever pressed Talk last; the first player closes their box and it turns to the second; when both have closed it returns to normal.
- [ ] Dale at night (shop closed): he is lying down, talking shows his sleepy line, and he does not stand up or turn.
- [ ] Say Yes or No on a Dealership offer: Dale answers in a box and keeps facing you until you close that one too.
- [ ] Old Hank with a plot: "You've got your plot, partner..." appears in the box (no toast). Without a plot he still opens the plot picker. The Hermit from afar says "too far to hear you" in the box.
- [ ] Output shows no errors from `NPCTalkService`.

Not verifiable without Studio: the exact feel of the turn and the walker's resume, and that a Talk press from the Xbox pad reaches the server prompt the same way (the existing Talk path).

## Vehicle meshes (branch `claude/vehicle-models`)

Connor, Xbox playtest after #108: "The vehicle models are messed up as well". His picture is the dealership's back row: a red Logging Rig with a long plank deck lying at the plinth, black lumps, huge black tyres and pale poles, and a blue block.

**What it was.** The showroom, plinths, boxes, `ItemBox` sizes and `PlotPlatform` are fine: the part-built vehicles render correctly in `dealership` and `trucks`. The mess is the uploaded-mesh path (Studio only, Lune cannot load meshes). `VehicleModels` holds each vehicle piece (Body, Glass, Lights, Bed, Hitch; Wheels go on the part-built wheels) as its own asset and its size. An asset has no pivot, so the piece arrives centred on its own bounds, and `VehicleMeshes.placeAtRoot` stood every piece's bottom-centre on the ground centre. That is right for the Body only. The Bed (3 to 7 studs tall) went to the road, under the kept part-built bed boards; Glass and Lights sank to the ground; the Hitch sat mid-truck; a trailer's pieces were all at its average. The part-built cab, hood and fenders are dropped when meshes are used, so nothing hid it.

**Fix.** `VehicleMeshes.Place` takes each piece's centre from the part-built hull it replaces (read before the cab and bed are dropped): Body on the ground as before; Bed from the chassis bottom, over the BedFloor; Glass at the cab glass (the Scout: by its seat); Lights from the lowest lamp up, centred between the head and tail lamps and never above the cab roof; Hitch at the chassis end. Trailer pieces stand on `TrailerBed` (Body with its top at the bed top, Bed and Lights from its bottom, Hitch between the coupler and the bed front). A mesh whose pivot did survive (`MeshPivot = "authored"`) is used only if it lands within `VehicleMeshes.PivotTolerance` (2 studs) of that place. Wheels, collision, welds, part caps and handling are untouched; a mesh that fails to load still leaves the part-built vehicle. `tests/VehicleMeshPlace.spec.luau`: every truck and trailer piece stands on its hull. Preview: `bash tools/preview/shoot.sh vehiclemesh` draws each mesh as a block of its real size (body red, glass cyan, lights yellow, bed brown, hitch magenta) so the places can be compared.

**Not verified.** The mesh shapes themselves (which way the nose faces, how a Lights mesh fills its box, the tyre axis) can only be seen in Studio.

### Studio checks (Connor), vehicle meshes
- [ ] Dealership, back and front row: every vehicle's bed sits on its frame behind the cab at truck height, glass in the cab, no plank deck at the plinth, no floating poles or lumps, tyres under the arches.
- [ ] Spawn the Rustbucket, Pickup, Scout ATV, Flatbed and Logging Rig on your pad, each with and without a trailer: same checks, hitch at the back, the trailer's bed on its frame, tow and load logs as before.
- [ ] Look at the vehicle through its box window: the little copy looks like the real one.
- [ ] If a vehicle still looks wrong, send the vehicle and a side view: which piece (bed, glass, lights, hitch) is out tells which anchor to move.
## Box hold: a grabbed shop box hangs steady (branch `claude/box-hold-axes`, 8 October 2026)

Connor's Xbox video: a grabbed shop box (the Millmaster 100, a shelf box) tilts and swings round the grip. Cause: the pull was sized for wood (mass x 400, capped at 4000), but a big box weighs about 6900 (35 mass x 196), so it could not be lifted, and the grip is off-centre (`ApplyAtCenterOfMass = false`) with a torque of only 2 x the pull, less than the pull's lever on a box. Fix (box only, tag `ShopBox`; wood is unchanged): `GrabLogic.HoldForce` (never less than 1.6 x the box's weight), the pull taken at the centre of mass (`PullsAtCentre`), `GrabLogic.HoldTorque` (at least force x 2 x the box's radius), the hold orientation started upright at the box's yaw (`GrabLogic.Upright`), and the box's angular velocity zeroed when the server confirms the grab.

### Studio checks (Connor), box hold
- [ ] Grab the Millmaster 100 and a shelf box (Hearth & Home): it lifts and hangs level in front of you, no swinging or tumbling, from any grip point (corner, strip, glass).
- [ ] Q/E (or D-pad) still turn it, the left trigger + left stick still tips it; drop it and it falls normally.
- [ ] A log still swings from the grip as before (not changed).
- [ ] A box held while you walk and look around stays level; carry one to the till and buy it as before.

### "Custom axes not working either" (looked at, not changed)
- Buy -> box -> open -> equip (`BoxService` -> `ShopService.GrantItem` -> `AxeService.Grant` -> `EquipTool`) and owner grant -> equip (`MonetizationService.OwnerGrant` -> pass listener -> `AxeService.Ensure`) read correctly; no nil field or wrong tool name found. The rack on the Tool Shed wall builds each axe with `AxeArt.Build`, which uses the uploaded meshes only when they load (asset permissions, open item 3 in STATUS.md); if they do not, the part-built axe shows. Send the `[MapBuilder] build check:` and `[MeshKit]` Output lines to settle it.

## Hotfix: Talk and Buy prompts dead after #107-#111 (branch `claude/fix-shop-talk-buy`, 8 October 2026)

Connor, Xbox: "talking to most shop NPCs is broken" and "can't buy anything". Both are ProximityPrompts (Talk, Buy at the counter), and `ProximityPromptService.Enabled` is one global switch that four client scripts flipped by saving "what it was" and putting that back: the dialogue box (`DialogueUI`), a held piece (`DragController`, which includes every shop box), the build placer and the wire tool. When two overlapped (a box grabbed while a keeper's box was up, or the 0.3 s re-enable window after a close), the later one saved "off" and put "off" back when it ended, with nothing left to turn prompts on. #111 made the keeper's box longer (greeting, shop line, own line) and #109 made boxes carried for the whole trip to the counter, so the overlap became easy to hit. Fix: `Shared/PromptGate` (pure) and `PromptSwitch` (client): each holder Holds and Releases under its own name, prompts are on exactly when nobody holds them. `DragController.grab` guards everything after the hold is recorded (a throw there used to leave `hold` set, so nothing could be grabbed again) and `drop` releases prompts first. `DialogueUI.hide` schedules the release before anything that can throw, and a server `Picking` left set only closes a box while the plot picker is really on screen. `DialogueService.Say` can no longer be stopped by the keeper-facing code (extras and `NPCTalkService.BeginById` are guarded). New output tags: server `[Talk]` (press, rate-limit drop, failures), client `[Talk]` (box open / box closed with the reason), client `[PromptSwitch]` (a hold over a minute, or the switch moved by something else), `[Drag]` (a hold that failed to start). Specs: `PromptGate.spec` (the old sequence reproduced and fixed, every order of four holders), `TalkFlow.spec` (Talk on each keeper, `end` costs no Dialogue budget, offer then end then Yes pays).

### Studio checks (Connor), hotfix
- [ ] Press Talk on Tink, Hazel and Dale: the box opens each time (three pages), E / X continues, the last press closes; talk again straight away: opens again.
- [ ] Carry a shop box to the counter, say Yes: it is bought. Grab a shelf box while a keeper's box is still up, close the box, drop the box: Talk and Buy prompts are still there.
- [ ] Talk to Millie, Gus, Pip and Old Hank: box opens, no stuck prompts afterwards.
- [ ] If it still fails, send the Output lines tagged `[Talk]`, `[PromptSwitch]`, `[Drag]`, `[BootReport]` and any red error text, plus what you pressed.
## Drop axe controls (branch `claude/drop-axe-controls`, 8 October 2026)

Connor: "why is there a drop axe button, just make it B on Xbox and a similar button on PC and however you wanna do it on phone."

**What changed.** The "Drop axe" / "Drop plan" side button is removed. `Shared/DropControls` (pure, `tests/DropControls.spec.luau`) holds the rules; `AxeController` binds them:
- Xbox: **B**. PC: **Q**, and **Backspace** still works. Phone: **long press on the hotbar strip** (bottom centre, clear of the thumbstick and jump button). Roblox's hotbar is CoreGui, so a per-slot button or menu is not possible; a tap on the equipped slot still puts the item away (Roblox does that), and the long press drops what is in hand. A long press also toggles that slot, so a phone press counts an item put away in the last 3 s (`DropControls.RecentSeconds`).
- Same conditions as the button: an axe only with a spare or better one (`HudRules.DropAxe`; never the lone Rusty Axe, pass and quest axes), any rolled plan, two presses 0.3 to 3 s apart (`HudRules.DropPress`), server ownership check, `RateLimiter` `DropAxe`/`DropBlueprint`, server keeps your last axe. The first press says "Press B again to drop the Steel Axe." in a toast (it was the amber "Confirm drop" button).
- The first time you hold something you may drop, one toast says how ("Press B twice to drop it", Q, or "Long-press its slot twice to drop it").
- Removed: D-pad Down as a drop (and its `HudRules.PadKeys.dropAxe`), the quick-menu "dropaxe" tile, `InputKit.Target.menu` DropAxe. Added `InputKit.DropBind`.

**B audit.** B is also Cancel/back in: `HUD.Popup` (High, sinks), `QuickMenuUI` close (High+201, sinks) and HUD back (High+10), `DialogueUI` (High, sinks), `SettingsUI` nav (High+20, sinks), `PlotUI` land panel (High+20), `SaveSlotUI` (High), `AdminUI`, `ShopUI` CloseShop (plain BindAction), `BlueprintPlacer` PlacerCancel (Q and B, plain), `WireTool` WireDone (High+100, Q and B), `DragController` (Q is yaw while a piece is held; HOLD_PRIORITY), and `MenuPad.Closes` through plain `InputBegan` in Daily, Forest, Store, World, Quest, PlotPicker, FieldGuide, Tree. The drop is a CAS action at `ContextActionPriority.Low` (1000), under every one of those, and the handler passes (never sinks) unless `DropControls.Decide` says drop. The `InputBegan` closers do not sink, so Decide also refuses while: `GuiService.SelectedObject` or `SelectedCoreObject` is set (every pad menu selects a control through `MenuPad`/`GamepadNav`), `GuiService.MenuIsOpen`, `UserInputService.ModalEnabled`, `HUD.Overlay()` (shop/store/guide modal rect, corner popups), `DialogueUI.IsOpen()`, the placer or wiring tool is up, `DragController.Holding()`, seated, or typing. Because CAS runs before `InputBegan`, a B that closes a panel finds it open and does not drop; the next B drops. `AxeController` has no `InputBegan` handler, so nothing handles a press twice. `tests/DropControls.spec.luau` scans the source: nothing else binds B below the drop, and the old button is gone.
**Residual.** On a keyboard, Q while the Land, Saves, Badges or Plot picker panel is open (no pad selection, not in `HUD.Overlay`) would still start the two-press drop; Escape closes those and Q does nothing else there.

### Studio checks (Connor), drop axe controls
- [ ] No Drop axe / Drop plan button on screen on PC, phone emulator or Xbox; the right-hand column has no gap where it was.
- [ ] Xbox: hold a Steel Axe (or any axe with a spare in the hotbar): B once shows "Press B again to drop the Steel Axe."; B again within 3 s lays it on the ground with a Pick up prompt. A lone Rusty Axe: B does nothing.
- [ ] Xbox: open Settings, Daily Goals, a shop, the Store, the quick menu (View), a Murph/NPC dialogue, the plot picker, the Land panel with an axe in hand: B only closes each; the axe is never dropped by that press. Close, then B twice drops it.
- [ ] Xbox: with a hammer-placer or wiring tool up, B stops it and does not drop; while holding a log (RT grab) B does not drop; sitting in a truck B does nothing.
- [ ] Xbox: D-pad Down no longer drops anything (while holding a log it still pulls it nearer).
- [ ] PC: Q twice (and Backspace twice) drops the axe; Q in the placer still cancels; Q/E turns a held log; typing "q" in chat drops nothing; Q with a panel open does not drop.
- [ ] Hold a rolled plan: B / Q twice drops it, server still says only you can pick it up.
- [ ] Phone (device emulator or a phone): long-press the hotbar twice, about a second apart, with an axe equipped: it lands on the ground. A long press up in the world, or on the thumbstick or jump button, does nothing. A tap on the equipped slot still puts it away. Watch whether the first long press also unequips it (expected; the second press still drops it).
- [ ] The one-time hint appears the first time you hold a droppable axe, with the right control for the device.

## No floating speech bubbles (branch `claude/remove-bubbles`, 8 October 2026)

Connor: "If we have the pop up chats you can remove the floating chat bubbles."

**What changed.** The speech bubble over an NPC's head is gone everywhere: the wave hello, the idle chatter, Murph's first-tip bubble, and the bubble code in `NPCController` plus its helpers in `NPCDialogue` (`AutoBubbles`, `Bubble*`, `AmbientGap`, the bubble layout sizes) and `TextAnchor` (`CardPx`, `Side`, `SideProbe`). Kept: name tags and role labels (still wall-safe and lowered under a roof by `TextAnchor`), the Talk prompt, the dialogue box, the wave gesture (animation only), a talking gesture while the box is open for that NPC, and the `NPCChatter` murmur, now played as the box opens. `QuestUI`'s "bubble" is Murph's tutorial card on the HUD, not an NPC bubble, so it stays.

**Where each bubble-only message went.**
- Murph's first-hello tips (amber arrow, F for the Field Guide, the little oaks): the first Talk on tutorial step one opens them in the box ahead of the step line (`QuestUI`). The step card, arrow and Skip still appear on their own, so nobody is stranded without Talk.
- Progress and weather chatter (sell your first load, a better axe, a sawmill, rain): drawn into the box on every Talk (`NPCDialogue.PoolFor`, as before).
- Ferry fare and timetable, toll fee, plot price (Old Hank): in each NPC's greeting and lines in the box, and in the prompts (`Board ($x)`, `Pay toll ($x)`, the Land Office offer) and the paid / refused toasts.
- Shop open / closed: the keeper lies down and the hours sign changes (server); a Talk to a sleeping keeper opens the box with their SleepLine.

### Studio checks (Connor), no bubbles
- [ ] Walk past every NPC (town, Aether Isles, ferry, toll gate, cave, plots): no speech bubble ever appears; name tags still show and hide behind walls and shop roofs.
- [ ] Come near Murph as a new player: he waves, no text. His step card and the amber arrow appear as before.
- [ ] Press Talk on Murph on step one: three tips, then the step line, one press each. Talk again: only the step line.
- [ ] Press Talk on each NPC (Millie, Tink, Hazel, Dale, Gus, Rosa, Pip, Bram, Old Hank, Old Tolly, Cap'n Moss, the Hermit): the box opens, the NPC turns to you and gestures, and prompts work afterwards. Hear the murmur as it opens.
- [ ] Ferry and toll: the Board / Pay toll prompts show the price; Cap'n Moss and Old Tolly mention it when talked to.
- [ ] Talk to a keeper after closing time: the box opens with their sleep line.

## Lane A2: end game (branch `phase-2/v1-a2-end-game`, 8 October 2026)

Gus's Charter, the Gondola Pass gate, the Sky Forge window (Starfall, relics, Old Bram's weekly order, tempering) and tempering in swings and sales. Built off `main` at `ae2c3f9`.

**How it fits together.**
- `Shared/SkyQuestLogic` (pure): the Designer's steps (own the Obsidian Axe; lay 120 Frostwood, 120 Emberwood, 40 Gloamwood planks by the town station; Gus gives the pass). `SkyQuestService` (server) adds Gus's "Gus's Charter" prompt on the town platform (F / ButtonY, hold 0.3 s), takes the laid planks (used up, pay nothing), saves `profile.skyQuest`, grants `gondolaPass` and the `GondolaPass` gear once, and publishes `SkyQuestStep` / `GondolaPass` attributes. No cash fee.
- `GondolaService`: Ride up from GondolaTown and GondolaBase checks `gondolaPass` (or the older `skyPass`) and toasts "Gondola Pass needed. Ask Gus about his charter." The ride down is never gated; the $250 fare and the 40 s ride are unchanged. A Signpost by each up station reads "SKYROOT GONDOLA / Obsidian Axe + Gondola Pass from Gus" (no price on the sign; the fare is in the prompt).
- `SkyForgeService` (server, new; `AetherService.V1Init` / `OpenForge` start it): "Open the Sky Forge" on the isle Starfall anvil and on the town court anvil (`TemperSpot`), the `ForgeOpen` / `ForgeAction` handlers (range 20 studs, RateLimiter), tempering, relics (once each; their trophies stand by your plot sign and the court's `Socket_<Relic>` gems light for you), and the weekly order (pays $18,000 + 4 Sky Shards once per UTC week from Monday 00:00).
- `Shared/TemperLogic`: Keen (cooldown -8/-15/-22%), Heavy (damage +10/+20/+30%), Prosperous (sale +4/+7/+10%, stamp `t`, inside BonusCap 3). One family per axe; grades in order; re-tempering a new family replaces it; no random rolls, no Robux. Costs: I $20,000 + 6 Sky Shards + 30 Gloamwood planks; II $50,000 + 10 + 40 Lumenwood; III $120,000 + 16 + 80 Lumenwood. The Lux Axe can't be tempered. `AxeService.GetEquippedAxe` returns the tempered copy.
- `ForgeUI` (client, new): four tabs; every button 44 px; picking a temper shows "Result", "Costs", "Replaces" and any refusal before Temper is sent. On a phone the window stays right of the thumbstick, left of the HUD column and jump button, under the cash plaque, and the temper choices stack one per line. B / Escape / X close it; the gamepad lands on the first button; you can't walk while it is open. Nothing binds ButtonR2.
- `V1Boot` starts the services (it was `EndGameBoot`, folded in): `AetherService.V1Init` (Sky Forge) first, then `SkyQuestService.V1Init` once the town gondola station is built.
- ShopUI: the forge rows moved to ForgeUI; its last hardcoded colours use UITheme names.

**Previews** (`previews/v1-a2/`, real meshes; the court, isle forge and cabin GLBs are loaded through a preview-only manifest because job 17 wires them in game):
- `court-bram.png`: the Sky Forge Court (uploaded SkyForgeCourt meshes) with Old Bram.
- `gondola-gate-gus.png`: the town station (GondolaStation meshes), Gus, and the gate sign.
- `isle-starfall-forge.png`: the isle Starfall Forge (uploaded meshes).
- `relic-trophies.png`: four relic trophies by a plot sign (PlotSign mesh).
- `forge-phone-temper.png`, `forge-phone-confirm.png`, `forge-phone-starfall.png` (667x375), `forge-pc-temper.png`, `forge-pc-confirm.png`, `forge-pc-relics.png`, `forge-pc-order.png` (1280x720): ForgeUI's own instance tree over the court with the round-3 HUD.
- Remake: `python3 tools/preview/v1_a2_meshes.py`, `PREVIEW_MESHES=preview/a2-meshes.json bash tools/preview/shoot.sh v1-a2-endgame`, then the steps at the top of `tools/preview/v1_a2_ui.py`.

**Renderer fixes in this branch (preview only).** `viewer.html` drew every rigged NPC (Old Bram and others) as magenta boxes: the GLB names its bones and its skinned meshes alike, and the viewer picked the bone. It now picks the node holding the mesh and draws a skinned mesh in its bind pose. In Lune, TownMeshes stands every piece of a multi-piece town model on the ground (no pivots outside Studio), so the station roof and the Signpost board lay in the grass; the A2 scene puts those pieces where the GLB has them (as Studio does when the pivot survives). Needs a Studio look (check 4 below).

### Studio checks (Connor), end game
1. **Gus's charter, PC.** New save with the Obsidian Axe: walk to the town gondola platform. Gus stands beside it. "Gus's Charter" (F) opens the charter; it says to lay 120 Frostwood planks by the station. Lay some, press F again: the progress moves and those planks vanish, no cash paid. Good: each step shows progress; after the Gloamwood step a toast says you got the Gondola Pass, and it is in your inventory once.
2. **The gate.** Before the pass, "Ride up" (E) at the town station toasts "Gondola Pass needed. Ask Gus about his charter." and charges nothing. With the pass it charges $250 once and rides 40 s. From the top, "Ride down" always works, pass or not.
3. **The gate sign.** Off the platform's front-left corner, past the steps: "SKYROOT GONDOLA / Obsidian Axe + Gondola Pass from Gus", readable from the steps, standing on the ground, and you walk through it. No price on it.
4. **Town meshes in place.** At the station: the roof sits on the posts, the GONDOLA crest on top, and the gate sign's board is between its posts (not in the grass). If any piece lies on the ground, set the workspace attribute `TownMeshes` false and tell us which model.
5. **The Sky Forge, PC.** On the isle (or the town court anvil), "Open the Sky Forge" (F) opens the window. Starfall shows the recipe and what's missing. Relics shows four rows with their pay. Order shows this week's woods and "New order in ...". Temper lists each axe you own except the Lux Axe.
6. **Tempering.** With $20,000+, 6 Sky Shards and 30 Gloamwood planks laid by the anvil: Temper, pick Keen I. The card shows Result, Costs (and Replaces when it changes family). Temper: cash, shards and those planks go; the axe now swings faster (watch the swing pace) and the row says "Keen I". Rejoin and switch save slots: it stays.
7. **Prosperous.** Temper an axe Prosperous I, fell and sell a log: the sale is about 4% more than the same log felled by an untempered axe.
8. **Relics.** Lay a figured Frostwood log or plank by the anvil with 4 Sky Shards, Relics, Forge on Frost: $22,500 paid once, the Frost gem on the court altar glows for you, and a trophy (a slate stand with a glowing gem) appears beside your plot sign. Rejoin: still there. Forge again: "Done".
9. **Weekly order.** Lay the order's planks by the anvil, Deliver: they are used up; when complete it pays $18,000 + 4 Sky Shards once. It turns over Monday 00:00 UTC (Sunday 6 PM MT).
10. **Phone (emulator, 667x375 or a small phone).** Open the forge: the window sits right of the thumbstick and left of the HUD column and jump button, under the cash plaque. Tabs and buttons are easy to tap; the temper choices are one per line; the list scrolls. X closes it.
11. **Xbox.** The charter prompt shows Y, Ride up shows X. In the forge the selection starts on the first button; the D-pad moves between tabs and buttons; A presses; B closes the window. RT still swings the axe after closing.

## End game follow-ups (branch `phase-2/v1-end-game-followups`, 10 October 2026)

Small fixes after the end game PR (#132).

- **Plot sign.** The PlotSign mesh's post runs up in front of the board to about 1.25 studs above the board's bottom edge, and the old three-line text (plot, tier, owner) put the owner's name on the bottom line, behind it. The sign now has two lines above the post: the owner's name (big) and "PLOT 3 · HOMESTEAD" under it (`PlotData.SignText`, fractions of the board's height from its top; `PlotData.SignPostTop` is the post's reach). An open plot shows its place name and "OPEN PLOT". `PlotService.spec` checks both lines clear the post. The preview exporter (`tools/preview/export.luau`) now draws a label that has its own place on a SurfaceGui in its own box, so the two lines show where they sit; `tools/preview/scenes/plot-sign.luau` renders the sign front, back, side, with a long name, and from the street.
- **Gondola Pass.** "Sky Pass" is gone from every player-facing word, comment and doc. Save keys stay: `profile.gondolaPass` and the old `profile.skyPass` (kept in step by `Migrate`), the `GondolaPass` gear id, the `SkyQuest` remote and `SkyQuestService`.
- **`BiomeData.Gate(biomeId)`.** `{ needs: string?, words: string }`. Sky: `needs = "GondolaPass"`, `words = "Obsidian Axe + Gondola Pass from Gus"`. Gear-gated biomes name their gear (snow `InsulatedCoat`, volcano `HeatBoots`, grove `Lantern`) with no sign words; an open or unknown biome is `{ needs = nil, words = "" }`. `SkyQuestLogic.GateWords` now reads the sky's words from here, so the sign and the gate cannot drift (spec).
- **Keen.** The server already shortened the tempered axe's cooldown (`AxeService.GetEquippedAxe` returns `TemperLogic.Apply`), but `CutController` paced the client's swings with the catalog axe, so the swing you felt did not speed up. `AxeService.StampTemper` puts `TemperPrefix` / `TemperTier` on the axe's tool (when it is built, and right after a temper at the anvil), and `CutController` multiplies its swing cooldown by `TemperLogic.CooldownMultiplier` (Keen I, II, III: 0.92, 0.85, 0.78; anything else 1). This is the one `CutController` edit Connor allowed; it is the speed math only, no input or ButtonR2 code.
- **`EndGameBoot` is gone.** `V1Boot.StartEndGame` starts `AetherService.V1Init` (the Sky Forge) first, then `SkyQuestService.V1Init` once the town gondola station (`TimberlineMap.GondolaTown.Platform`) is built, in its own task so the server start does not wait for the map. Same order and same remotes as before; the Notify remote carries toasts.
- **Town model check** (part-built town, as the game ships it with `GameConfig.TownMeshes = false`; `tools/preview/scenes/town-pieces.luau` shows each shop, the sawmill and the station on their own ground). Nothing floating, sunk, backwards or misfacing: the Tool Shed, Hearth & Home and Dealership signs stand on their posts with the board inside its frame, facing -Z; the sawmill's sign, roof and crest sit on their posts; the gondola station roof sits on its posts. Not problems: the earlier `town` and `buildings` scene renders put the uploaded town meshes on (the module's default in Lune), and Lune has no model pivots, so lamp glows land on the ground and the Tool Shed and Hearth sign frames look empty with the board offset; the game keeps the mesh switch off. The `buildings` overview scene also overlaps the Dealership hall over the shops (scene layout only). If the switch is turned on (job 17), re-check the shop sign boards against their frames.

### Studio checks (Connor), follow-ups
1. **Plot sign, PC and phone.** Claim a plot and walk up to its sign from the front and from behind. The owner's name is on the top line, clear of the post, with "PLOT n · TIER" under it. Try a long display name: it shrinks to fit the board.
2. **Gondola Pass words.** Search the game for "Sky Pass": the inventory item, Gus's talk, the gate sign and the refusal toast all say "Gondola Pass". An old save that had `skyPass` still rides up.
3. **Keen.** Temper an axe Keen I and chop a tree: the swings come about 8% faster than the same axe before (III about 22%). Keen on one axe does not speed another axe. Swap axes in the hotbar and back. Hold the chop button (PC mouse, phone, Xbox RT is unchanged) to check the pace.
4. **Boot.** Join: the Sky Forge opens at the anvil, Gus's "Gus's Charter" prompt is on the town station, and the Output has no "[V1Boot]" warnings.

