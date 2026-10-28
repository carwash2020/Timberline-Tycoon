# T413 Travel — Art Director look lock

**Lane:** Game Art Director  
**Sources:** vision.md §3 + §14 audit (Bridge REDO, Ferry REDO, Gondola REMOVE, Signpost KEEP); style-guide.md Midday palette + §4 materials + §7 signs; model-recipes.md §6 roads, §8.2 plank bridge, §8.3 dock; LandmarkArt TollBridge/TollBooth/FerryBoat/FerryDock; BuildingArt.Bridge / Signpost.

**Look target:** Warm stylized realism (style Midday). Travel reads as custom Timberline infrastructure from spawn: one bold lift-bridge silhouette over the river cut, stone-faced road bridges on branches, a chunky car ferry with walkable deck, weathered dock piles, and cream junction boards. No gondola mast, cable, or cabin anywhere. Greybox MeshId 0 OK until turntables; silhouettes and palette must still match this lock.

## Palette (Luau-ready)

| Role | Name | Hex | Material / notes |
|---|---|---|---|
| Road deck / gravel | RoadGravel | #A8A49C | Concrete or Asphalt; main 32 / branch 24 / foot 8 (vision) |
| Trail / switchback dirt | TrailDirt | #8E6C4A | Ground / dirt shoulders on Skyroot grades |
| Plank deck (town + foot) | PlankHoney | #C49A63 | WoodPlanks; alternate with WeatheredPlank |
| Weathered dock / ferry deck | WeatheredPlank | #9C8466 | WoodPlanks; dock piles WeatheredPlank or TimberBrown |
| Stringers / posts | TimberBrown | #7A5230 | Wood |
| Stone abutments / piers / stone bridge face | StoneBase | #8C877E | Cobblestone or Slate |
| Lift towers, rails, bollards, ferry hull trim | IronBlack | #2B2B2E | Metal |
| Bridge / toll lamps | Brass | #C9A24A | Metal; PointLight warm #FFC45C range ~14 |
| Sign board | SignCream | #F3E7C9 | SmoothPlastic |
| Sign ink | SignInk | #2A2420 | text / carved edge |
| Toll closed / PAY cue | StopRed | #D9534F | Neon or SmoothPlastic stripe on arm / booth window |
| Harbour sand | ShoreSand | #D8C69A | Sand at Sparkworks berth |
| Ferry night accent (Isle) | Lantern | #FFC45C | Neon trim on ferry cabin only, soft |

## Silhouettes

1. **Lift bridge (out-of-town toll, $100)** — Twin IronBlack towers with cross-brace, deck that reads raisable (even if animation is later). StoneBase abutments each bank. Deck width matches main road (32). From spawn the towers must read as the river landmark. Toll booth small timber shed (PlankHoney + RoofSlate) with SignCream board “TOLL $100” SignInk; StopRed stripe on the arm or booth face when closed. No gondola tower silhouette.

2. **Town / main bridge (free)** — Plank or stone-faced road bridge, no toll booth, no StopRed. Same palette as plank recipe: alternating PlankHoney / WeatheredPlank deck, StoneBase abutments, IronBlack rail posts. Clean readable span; must not look gated.

3. **Stone bridges (branch roads)** — Low arch or piered stone faces (StoneBase Cobblestone), RoadGravel deck, IronBlack rails. Heavier and quieter than the lift bridge so the lift stays the hero.

4. **Rope / timber footbridge (Gloam foot path)** — Existing BuildingArt.Bridge / Footbridge silhouette KEEP: thin plank run, rope rails, BridgeGuardHeight 3.2. Foot width 8 only; trucks must not fit visually.

5. **Car ferry** — Chunky workboat, not a yacht. Hull IronBlack waterline + WeatheredPlank deck **18×84** (Builder/QA lock; replaces live FerryLogic 14×22). Low cabin aft with Brass lamp and optional Lantern trim. Bollards IronBlack; rope coils Fabric #C2B280. Deck must look drive-on for truck + trailer. Name board SignCream optional “LANTERN FERRY”.

6. **Ferry dock (Sparkworks harbour + Isle berth)** — model-recipes §8.3: WeatheredPlank deck ~10 wide on piles, bollards every 8, ShoreSand bank. Clear berth gap. Cap’n Moss stand can reuse town NPC kit scale; no gondola landing.

7. **Skyroot switchback road** — RoadGravel ribbon with TrailDirt shoulders, hairpin pull-outs, TimberBrown post-and-rail on outer edge only. Grade readable from afar; no tunnel-of-neon. Landmarks along climb stay Midday greens / stone, not sky-forge glow until the isle itself.

8. **Junction signs** — BuildingArt.Signpost KEEP: two TimberBrown posts, framed SignCream board, SignInk copy. Arrow cutouts OK. Copy examples for Designer to finalize: “DEALERSHIP →”, “FERRY / LANTERN ISLE”, “SKYROOT ↑”, “TOWN (free bridge)”. Price on toll/ferry boards only: “TOLL $100”, “FERRY $350”. No Robux glyph, no gondola arrow.

## Avoid

- Any gondola mast, cable, cabin, or “sky tram” leftover mesh or sign.
- Neon highways, cyber metal, glass curtain walls on bridges.
- Flat grey default Plastic decks; unpainted neon-green Terrain seams.
- Tiny ferry that reads as a rowboat; deck must read truck-scale.
- Paid fast-travel portal kiosks or glowing teleport pads.
- Hardcoded Robux $ in UI art (fare boards use in-game $ only).
- Copying LT2 / Oaklands bridge or ferry meshes.

## PR screenshots must show

1. Spawn or town approach: lift-bridge towers readable; town bridge free (no booth).
2. Toll booth + SignCream “TOLL $100” + StopRed cue; out-of-town bridge stone/Iron silhouette.
3. Ferry dock berth + ferry boat deck scale vs a truck footprint (or truck ghost box).
4. Stone branch bridge + rope/timber footbridge for contrast.
5. One Skyroot switchback segment with TrailDirt shoulders and outer rail.
6. Junction Signpost set (Dealership / Ferry / Skyroot / Town) SignCream + SignInk.
7. Top-down travel pin map: no gondola assets; MustKeep T411/T412 shops untouched.
8. Phone-width crop of a junction sign and the ferry name board (readable).

**Greybox OK:** MeshId 0 for ferry + bridge meshes until turntables; part colors/materials above still apply. Dress hooks: LandmarkArt.TollBridge / TollBooth / FerryBoat / FerryDock; BuildingArt.Bridge / Signpost; TownMeshes Footbridge / RopeBridge / Signpost when meshes land.
