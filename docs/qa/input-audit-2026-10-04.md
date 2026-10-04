# Input and device audit, 2026-10-04

Static audit of `main` at `da12efc` (and this branch, which adds only `InputKit`). No Studio playtest. Grades are from the source against the target map in `Shared/InputKit.luau`.

**Target map.** Keys are unique inside one context, not across the game. The contexts are world prompts, the placer, drag, and menus.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Interact, Talk, Buy | E | ButtonX |
| Open, forest plant | F | ButtonY |
| Cancel (menus) | Escape | ButtonB |
| Placer rotate (target) | R | DPadRight |

ButtonX is only those three actions. Open and the forest prompt may share ButtonY only when `InputKit.OpenForestApart` is true (no spot inside both discs). `PromptDefaults` writes `KeyboardKeyCode`, `GamepadKeyCode`, and `RequiresLineOfSight` (false). Touch targets are 44 px or more at 667×375. Tags (text) are 14 px or more. The safe area is `ScreenInsets.CoreUISafeInsets`, not a percent of the screen.

Engine defaults, read here and not assigned in source: `KeyboardKeyCode` E, `GamepadKeyCode` ButtonX, `ClickablePrompt` true, `RequiresLineOfSight` true, `ScreenGui.ScreenInsets` CoreUISafeInsets. A prompt column fails "set" when the source never assigns the property.

`GameConfig.CustomPrompts` is true (`GameConfig.luau:53`). `PromptUI` draws every prompt. The card is 72 px tall (`PromptUI.luau:29`) and is the hit target (`PromptUI.luau:204`). The key cap is 40×43 (`PromptUI.luau:103`), under 44, and is not the hit target.

## Prompt call sites

`rg -c 'Instance.new\("ProximityPrompt"\)|ProximityPrompt' src` is 67 hits in 27 files. 14 of those hits are `Instance.new("ProximityPrompt")` call sites. One row per call site. Two hits are this branch's `InputKit` (the `PromptDefaults` parameter and one comment). The rest are types, finds, and comments.

| # | Call site | What it creates | KB | Touch 667×375 | Pad | TV | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `StoreBoard.luau:159` | Browse / Store | Pass. E is assigned (`:163`). Mouse uses the default clickable card. | Pass. Card is the button. | Fail. `GamepadKeyCode` is not assigned (`:159`). | Pass. World billboard, not a ScreenGui. | X2 |
| 2 | `DealershipLot.luau:128` | Buy | Pass. Default E matches Buy. | Pass. Card. | Fail. Gamepad key not assigned (`:128`). | Pass. Billboard. | X2 |
| 3 | `VehicleService.luau:828` | Drive | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:828`). | Pass. Billboard. | X2 |
| 4 | `AetherService.luau:870` | Chute (`:915`), forge check (`:925`), forge the axe (`:937`), sell Sky Bin (`:984`) | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:870`). | Pass. Billboard. | X2 |
| 5 | `GondolaService.luau:365` | Ride up town (`:374`), ride up base (`:377`), ride down (`:380`) | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:365`). | Pass. Billboard. | X2 |
| 6 | `NPCService.luau:88` | Talk | Fail. Source sets F (`NPCData.luau:583`). Target Talk is E. | Pass. Card. `ClickablePrompt` is set (`NPCService.luau:95`). | Fail. Source sets ButtonY (`NPCData.luau:584`). Target Talk is ButtonX. | Pass. Billboard. | B08 |
| 7 | `PlotService.luau:337` | Claim this plot | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:337`). | Pass. Billboard. | B11 |
| 8 | `PlotService.luau:478` | Open (door) | Fail. Default E. Target Open is F. | Pass. Card. | Fail. Default ButtonX. Target Open is ButtonY (`:478`). | Pass. Billboard. | B11 |
| 9 | `AxeService.luau:392` | Pick up a dropped axe | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:392`). | Pass. Billboard. | X2 |
| 10 | `TreeService.luau:145` | Pick up a log | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:145`). | Pass. Billboard. | X2 |
| 11 | `CarryController.luau:68` | Load (`:122`) and Sell logs (`:174`) | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:68`). | Pass. Billboard. | X2 |
| 12 | `ForestUI.luau:331` | Plant Heartseed | Pass. F is assigned (`:334`). | Pass. Card. | Pass. ButtonY is assigned (`:335`). | Pass. Billboard. | — |
| 13 | `ShopUI.luau:923` | Shop browse | Pass. Default E matches Interact. | Pass. Card. | Fail. Gamepad key not assigned (`:923`). | Pass. Billboard. | X2 |
| 14 | `PlotUI.luau:287` | Move (`:299`) and Sell placed (`:305`) | Fail for Sell. Move's E matches Interact. Sell's F (`:307`) is Open's key on a Sell action. | Pass. Card. | Fail for Sell. Move's ButtonX (`:299`) matches Interact. Sell's ButtonY (`:308`) shares Open's key. See the range note. | Pass. Billboard. | X2 |

Rows 3, 9, 11, and 13 are the four the scripter listed. Rows 1, 2, 4, 5, 7, and 10 are the same gap: the gamepad key is left at the engine default.

**Open and forest, same spot.** Door range is 10 (`PlotService.luau:482`, `InputKit.OpenRange`). Forest range is `ForestData.PlantRange - 2` = 10 (`ForestUI.luau:337`, `InputKit.ForestRange`). A spot is in both when the stump is at most 20 studs outside a homestead square. The largest tier is 200 (`PlotData.luau:102`), the same square as the pad. Measured from `WorldPlan.Trees()` against those squares, 9 trees are inside 20 studs. Closest: a pine at about (-89.4, 454.2), 0.57 studs outside North Bend's square. `InputKit.OpenForestApart` is false for that set, so the ButtonY share is not proven. Owner: W2 (`WorldPlan.luau:108`, `firstTrees`, placed on the old lawn and never moved). Do not treat Open and Forest as free to share ButtonY until that gap is over 20.

**Sell is also ButtonY.** `PlotUI.luau:305` sells a placed item on ButtonY while build mode is on. A built door on the same model (`PlotService.luau:478`) will use ButtonY once Open is mapped. Those two are on one building. X2 needs a key for Sell that is not ButtonX (Move) and not ButtonY (Open and Forest).

## Menus, gamepad

Pass means `GuiService.SelectedObject` is set to a control inside the menu on open, and B closes it. Escape is not bound anywhere in `src/` (no `KeyCode.Escape`). Every closable menu fails Esc. That is one X2 item, listed once here, and not repeated on every row.

| Menu | Pad | File:line | Owner |
| --- | --- | --- | --- |
| StoreUI | Fail. `openStore` shows the panel and never sets `SelectedObject`. Close is a click (`:340`). No B bind. | `StoreUI.luau:272` | X2 |
| SaveSlotUI | Fail. `setOpen` toggles visibility only. Close is a click (`:225`). No B bind. | `SaveSlotUI.luau:169` | X2 |
| PlotPickerUI | Fail. Buttons are built (`:248`) and never selected. No B bind. Closing is the server clearing `Picking`. | `PlotPickerUI.luau:179` | X2 |
| PlotUI | Fail. The build bar's BLUEPRINTS and DONE (`:377`, `:382`) are not selected, and B does not leave build mode. The blueprint list itself is ShopUI, which does select and does close on B. | `PlotUI.luau:377` | X2 |
| DailyUI | Fail. `HUD.Popup` is called with no first button (`:231`), so nothing is selected. B does close, via `HUD.luau:509`. | `DailyUI.luau:231` | X2 |
| FieldGuideUI | Pass. `ShopUI.OpenCustom` (`:188`) selects the first row and B closes the shop. | `FieldGuideUI.luau:188` | — |
| QuestUI | Fail. The tracker and Skip are not selected on open. B does not dismiss the card. Skip is a tap (`:768`). | `QuestUI.luau:727` | X2 |
| SettingsUI | Pass. `HUD.Popup(card.outer, firstFace)` (`:239`) selects the first control on a pad, and B closes. | `SettingsUI.luau:239` | — |
| ShopUI | Pass. The first buy row is selected when a pad is connected (`:710`). B is bound to close (`:698`). | `ShopUI.luau:710` | — |
| HUD | Pass for popups that pass a first control. `HUD.Popup` selects it and binds B (`:498`, `:509`). Callers that omit the first control fail on their own row. | `HUD.luau:498` | — |
| ForestUI | Fail. The pouch list is `HUD.Popup` with no first control (`:250`). B closes it. The figure reveal is not a menu. | `ForestUI.luau:250` | X2 |
| TreeUI | Pass. Not a menu. HP is a BillboardGui (`:44`). Nothing opens, so there is no selection to land and no B to bind. | `TreeUI.luau:44` | — |
| WorldUI | Pass. Not a menu. Toasts and the clock (`:105`) have no selection. | `WorldUI.luau:105` | — |

## ScreenGui safe area

Pass means `ScreenInsets` is `CoreUISafeInsets`. The property's engine default is that value. Callers of `UITheme.Screen` without `"device"` get it (`UITheme.luau:524`). `"device"` switches to `DeviceSafeInsets` (`UITheme.luau:523`).

| Screen | Insets | File:line | Result | Owner |
| --- | --- | --- | --- | --- |
| UITheme.Screen default (Settings, Saves, Daily, Store, Plot bar, Heartseed pouch, BlueprintPlacer, DragControls, Corner, TimberlineHUD, LeftColumn) | CoreUISafeInsets | `UITheme.luau:524` | Pass | — |
| ShopUI | DeviceSafeInsets | `ShopUI.luau:749` | Fail | X2 |
| PlotPicker | DeviceSafeInsets | `PlotPickerUI.luau:180` | Fail | X2 |
| HUD SideButtons | DeviceSafeInsets | `HUD.luau:1736` | Fail | X2 |
| ForestUI FigureReveal | DeviceSafeInsets | `ForestUI.luau:1046` | Fail | X2 |
| HUD TimberlineTop (cash row) | None | `HUD.luau:1392` | Fail | X2 |
| HUD safe-area probe | DeviceSafeInsets | `HUD.luau:1410` | Fail | X2 |
| DragController reticle | None | `DragController.luau:435` | Fail | X2 |
| BuilderTools | Default CoreUISafeInsets. Also sets `IgnoreGuiInset` (`:562`), which ScreenInsets overrides. | `BuilderTools.luau:559` | Pass | — |
| LoadingScreen | Default CoreUISafeInsets. Also sets `IgnoreGuiInset` (`:102`). | `LoadingScreen.client.luau:100` | Pass | — |

`HudLayout` places the cash row in screen pixels for a gui whose insets are None (`HudLayout.luau:355`). It has no CoreUISafeInsets term. Owner X2, same cash-row fail.

## Checklist

1. **Axe.** Swing on a pad is R2 (`CutController.luau:763`). v1 chop is `Tool.Activated` (`ChopController.luau:389`). Drop is Backspace and DPadDown (`AxeController.luau:130`, `:135`). Touch swing is a world tap (`CutController.luau:770`), not a 44 px button. **Fail** the 44 px swing button. Owner X2. Drop's side button is 116×44 on a phone (`UITheme.luau:221`). That part passes.

2. **Carry and drag.** Pick up, rotate, and drop exist (`DragController.luau:819` mouse, `:825` ButtonL2, pad turns at `:490`). Touch grab is sunk outside the thumbstick (`:738`) so the camera does not follow that finger. The hold buttons are 60×44 (`:71`). There is no throw. **Fail** throw: no action in `DragController` or `GrabLogic`. Owner X2. Prompts are turned off while a hold is active (`:351`), so drag keys do not share a live prompt key.

3. **Truck.** Enter is the Drive prompt, row 3, gamepad key unset. Drive is the seat: WASD, the stick, the touch thumbstick (`VehicleController.luau:1`). Exit is Jump (`HintLogic` driving line). Recall is ButtonY on the side button (`VehicleController.luau:214`), a menu-context key, unique there. **Fail** the Drive prompt's unset gamepad key. Owner X2.

4. **Build.** Place is R2 (`BlueprintPlacer.luau:367`). Cancel is Q and B (`:372`). Rotate is R and ButtonX (`:360`). That ButtonX is Interact's key, and world prompts stay on while the placer is up. **Fail.** X2 moves `PlacerRotate` from ButtonX to DPadRight and keeps R. `InputKit.Target.placer` is already that map. `InputKit.PlacerSafe` is false for today's bind while prompts are on. Select, copy, move, and delete on the build bar are mouse and touch only (`BuilderTools.luau:666` and `:684`). **Fail** pad select. Owner X2. Bar buttons stay at least 44 (`BuilderBar.luau:18`).

5. **Shops.** Browse, buy, and close exist (`ShopUI`). The menu's pad row passes. The world prompt's gamepad key fails (row 13). Pay-at-counter, open-box, spawn-pad, and chop-saw are not in this build. Sawmill cut size is a prompt-less server path. No extra owner until those batches add the prompts. They should call `PromptDefaults`.

6. **NPCs.** Talk's key fails (row 6). Owner B08. The phone bubble text is 14 (`NPCDialogue.luau:259`). The phone role tag is 11 (`:264`). **Fail** the 14 px tag. Owner B08.

7. **Menus.** The pad table above. Eight fail (Store, Saves, Plot picker, Plot bar, Daily, Quest, Forest pouch, and Esc on every closer). Field Guide, Settings, Shop, HUD's popup path, TreeUI, and WorldUI pass the pad rule. Esc fails for every closer. Owner X2 except where a row names another batch.

8. **Prompts.** The 14 rows above. Two prompts in range must not share a key with each other or with a held action. Drag turns prompts off while held. The placer does not, and its rotate bind is ButtonX (item 4). Sell and the forest prompt both use ButtonY and can overlap (the range note).

9. **Touch at 667×375.** Short side 375 is under `UITheme.CompactEdge` (500), so compact layout is on. Fails, all X2 unless noted:
   - Field Guide button becomes 40×43 (`FieldGuideUI.luau:226`).
   - Plot picker "Give me any open plot" is 18 px tall (`PlotPickerUI.luau:260`).
   - Plot build bar buttons are 36 px tall (`PlotUI.luau:377`, `:382`).
   - Store tabs are 36 px tall (`StoreUI.luau:349`). The panel is 520 px tall (`:317`) on a 375 px screen, so it clips in portrait 375×667.
   - World clock text drops to 13 while compact (`WorldUI.luau:120`).
   - NPC role tag is 11 (item 6), owner B08.
   Phone `UITheme.Sized` faces that declare `hit = 44` (Settings, Store, Daily, pouch, Skip) pass via `HitPad`. Side buttons are 116×44. Shop buy is 96×44. Shop close is 48×48.

10. **Console and TV safe area.** The ScreenGui table above. HUD, HudLayout, UITheme, and DragController are the files that read insets today, and three of those still emit `None` or `DeviceSafeInsets`.

11. **10-foot readability.** Not playtested. `UITheme.ScaleFor` grows a TV with height / 720. Contrast on snow and at night was not checked. Leave this open for Connor. No owner until a playtest fails a line.

12. **Pad equivalent for every action.** Fails: BuilderTools select and copy (item 4), the menus with no selection (the pad table), the unset prompt gamepad keys (the prompt table), placer rotate on ButtonX (item 4). Throw has no pad key because it does not exist (item 2).

13. **Keyboard.** PromptUI shows `KeyboardKeyCode`, so the shown key matches the key that works, including the engine default E. Esc does not close menus (no bind in `src/`). Shift lock and first person with the axe and the truck were not playtested.

## X2 (do not do these here)

- `BlueprintPlacer.luau:360`: change `PlacerRotate`'s gamepad key from ButtonX to DPadRight. Keep keyboard R. Until that lands, either that bind must not use ButtonX or world prompts must be off while the placer is active (`InputKit.PlacerSafe`).
- Assign `PromptDefaults` (or the same three properties) on every fail in the prompt table whose owner is X2.
- Set `SelectedObject` on open and bind B to close for every failed menu row whose owner is X2. Bind Escape to the same close.
- Raise the under-44 targets and the under-14 text listed in item 9.
- Switch the failed ScreenGuis to `CoreUISafeInsets`.
- Give Sell (`PlotUI.luau:305`) a key that is not ButtonX or ButtonY.

## Other batches

- B08: Talk is F / ButtonY in `NPCData.luau:583`. Target is E / ButtonX. Phone role tag is 11 (`NPCDialogue.luau:264`).
- B11: Claim and Open in `PlotService.luau:337` and `:478`. Open's target is F / ButtonY.
- W2: nine `WorldPlan.Trees()` stumps sit inside 20 studs of a max-tier pad (`WorldPlan.luau:108`). Open and Forest cannot share ButtonY until `OpenForestApart` is true.
