# T414c plan: Land Office and Sparkworks look like timber-town buildings

Branch `cursor/t414c-landoffice-sparkworks`, from main 9b2a43f. Art only; no economy, StoreData or world-pin change.

## What main actually has (checked)
- The ground SkyForgeCourt is already gone (T412). `MapBuilder` builds 4 meadow scenes and `spot.kind == "forge"` never occurs in `town.scenes`; `MapBuilder.spec` and `T412Shops.spec` already assert it. Only the cloud-Y 840 `TimberlineMap/SkyForge` socket remains (MustKeep). So: no removal, no `mustkeep.json` edit; add one spec that keeps it absent.
- `BuildingArt.LandOffice` and `BuildingArt.Sparkworks` (the functions the brief names) are not what the world places. The world builds the Land Office cottage with `ShopPlace.office()` and Sparkworks with `BuildingArt.Shop("Sparkworks")` (the local `sparkworks()` builder). The two named functions are used by `BacklogModels.spec`, `BuildingArt.spec` and preview scenes only.
- Old Hank (PlotSalesmanData.Office 153.5, 100) stays unmoved; the `PlotService` no-LandOffice spec is not touched.

## Files
- `src/ReplicatedStorage/Shared/Art/BuildingArt.luau`: only `BuildingArt.LandOffice` and `BuildingArt.Sparkworks` bodies.
- `tests/Buildings.spec.luau` (new): the acceptance specs.
- `preview/t414c/*`: before/after renders; `tools/preview/scenes/t414c.luau` (new scene).
- This plan, STATUS.md and PHASE2_NOTES.md lines.
- Not touched: ShopPlace, ShopKit, ShopInterior, ShelfLayout, ShopBounds, TownGround, Palette, WorldPlan, mustkeep.json, geometry_allow.json, StoreData.

## Approach
Both builders keep names, return type, `Kit.model` names and the `TownMeshes.Dress` call, and the part names code or specs read (Pad, Floor, Wall, Roof, Sign, Counter, DemoBoard, GlowStrip, Lamp, Switch, Wire).
- Doors: 8 wide x 10 tall opening in the front wall, a header and sign above y 10, wall shoulders at least 3 each side, floor flush, nothing solid in the opening or the 6-deep apron. (Today Sparkworks' opening is 2 wide and the Land Office sign sits in its 6-wide gap.)
- Land Office: PlankHoney board-and-batten (batten parts), PineTrim corner posts and door frame, RoofSlate gabled roof, StoneBase foundation, SignCream board with SignInk text, porch with posts, a deed map (framed, non-colliding) on the back wall, a counter. Slight wear: a patch board and a small lean on the porch post.
- Sparkworks: TimberBrown walls with batten, RoofSlate gabled roof, Brass band and fittings, Lantern #FFC45C small PointLights, no Neon walls (lamp bulbs are small glass/Neon-free), brass sign.
- Footprint stays inside the old lots (Sparkworks 20 x 16, Land Office 19 x 15).

## Specs (written first, shown red, then green)
1. Both doors 8w x 10h clear, 3 studs of wall each side, apron clear; names, tags, attributes unchanged; Land Office pin (153.5, 100) and Sparkworks pin (1115, -700) unmoved (ShopPins, PlotSalesmanData).
2. Old Hank stands at the pin and faces the street (plot flow specs untouched and green); the Land Office builder has a counter facing the door.
3. Sparkworks still on the Lantern Isle harbour, `FerryRequired` true until the ferry binds.
4. No SkyForgeCourt at ground level; the summit socket stays.
5. World overlap lint, Clearance, GeometryLint, MustKeep green, no new allowlist entries.

## Known gap to rule on
The builders the player sees are `ShopPlace.office()` and `BuildingArt.sparkworks()`, both outside this brief's file scope. If the Manager wants the in-world look changed, that is a follow-up (or a scope ruling) and I will not edit them in this PR.
