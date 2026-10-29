# T413 Builder — Travel (bridges, ferry, Skyroot, signs)

Sources: vision.md §3 RULE 3 / §4 / audit 24–26; WorldPlanDraft (MainWidth 32 / Bridge / docks / Skyroot Road); WorldLayout BridgeWidth 28 / BridgeLength 52 / FerryDock (780,136); FerryLogic Deck 14×22 TravelSec 40; TruckLayout.Scale 1.3 LoggingRig + HeavyHauler; PlaceCheck StreamingMin 128 / Target 640; blender-roblox research-notes.md (20k tris hard cap); Art T413 palette; Connor locks.

## Vehicle clearances (design to these)

| Rig | Length | Width | Notes |
|---|---|---|---|
| LoggingRig alone | ≈46.7 | 10.14 | cab 9.4×S + bed 33.8 + TAIL 0.5×S, S=1.3 |
| + HeavyHauler trailer | ≈75.3 | ≥10.14 | Tongue 2×S + bed 26 |
| Two-way pass | — | need ≥32 road | vision main width; live roads still 28 |

Live `FerryLogic.DeckWidth×DeckLength` **14×22 cannot fit** LoggingRig. Grow deck and docks this ticket.

## Roads

- Promote `WorldPlanDraft.MainWidth=32`, `BranchWidth=24`, `FootWidth=8` into live MapBuilder / WorldLayout road widths (replace 28 on travel mains).
- Junction radius stay **≥32** (haul).
- Trees / props: keep `StripRoadClear` 20 off bridge decks; door/path clearance lint whole-world.

## Lift bridge (paid $100) + free town bridge

**Paid lift (Dealership side):**
- Pin: WorldPlanDraft.Bridge ≈ **x=113** (`sellFloor.x1 87 + RIVER_PAST_SELL 26`), **z=80** (EastLink), `CHANNEL_HALF=18` (channel ≈36).
- Deck footprint: **Width 32 × Length 56** (span + abutments; 52 live min OK if abutments sit on bank).
- Twin IronBlack towers + StoneBase abutments outside the 32 drive lane; booth on approach (south), not in lane.
- TollLine / TollPush retarget onto this bridge only (Script). Free town/main bridge: **no** TollLine, **no** booth.
- Dealership Spur: bridgeZ → MustKeep door **(189.25, 100.3)**; do not pave Land Office (z≈100). Origin DealershipLot 207/100.2 untouched.
- Clearance: truck+trailer straight across; rails BridgeRailHeight 3; no solid in door/path/log lane.

**Town/main free bridge:** same plank/stone language, deck width 32, no booth/StopRed.

**Stone branch:** width 24. **Gloam foot / rope:** KEEP BuildingArt.Bridge / Footbridge width **8**; trucks must not fit.

## Ferry + docks (Sparkworks harbour)

- Deck grow: **DeckWidth 18 × DeckLength 84** (one drive-on lane; fits combo ≈75.3 + margins). TravelSec stays **40**.
- Dock berths: grow past live DOCK 16×10 → apron **≥20 wide × ≥16 deep** each side, flush HeightAt, ramp grade **≤12%**.
- Promote pins to draft: MainlandDock **(920, −640)**, IslandDock **(1100, −700)** next to Sparkworks harbour **(1115, −700)**. Move `WorldLayout.FerryDock` / isle tags with them; live (780,136)/(930,−50) stop being the play route.
- Clear `FerryRequired` only when Script Ready (Builder: berths tagged FerryDock, boat PrimaryPart Deck, no overlap with Sparkworks pad).
- Boat: LandmarkArt.FerryBoat greybox resized to new deck; cabin/rails aft so truck path is clear bow→stern; drop ornamental Mast if it blocks the lane.
- Streaming: FerryBoat **Persistent** (already); `RequestStreamAroundAsync` on arrival (vision §10).

## Skyroot switchback

- Replace live SkyrootRoad `(600,80)→(800,200)→(700,320)` with draft path to GateLodge **(−40, 720)** facing north: `(−36,520) → (−180,600) → (−50,660) → frostFoot (−178,691) → lodge`.
- Width **32**; TrailDirt shoulders; outer TimberBrown rail on drop side.
- **Grade ≤12%** on every segment (vision acceptance); hairpin radius ≥32 at frostFoot.
- Lodge Path foot **8**: lodge → Skyroot summit (−60, 800). No road toll on the climb (Sky Pass at lodge is Designer/Script).

## Junction signs

- KEEP Signpost kit. Boards at: trunk↔lift, Bay Road→ferry, Skyroot climb start, free town bridge. Copy from Designer lock only. Boards outside the 32 drive lane (shoulder ≥ SHOULDER 28 from centre where kiosks sit).

## Streaming / parts

- PlaceCheck stay MinRadius **128** / Target **640**.
- Persistent: lift towers model, FerryBoat, GateLodge, mainland+isle docks.
- Road gravel / stone bridges: Default or Atomic; no phone part-budget invent; quality-first, split meshes instead.
- MeshId **0** greybox OK until turntables (ticket Done-when).

## Blender mesh specs (bridges + ferry)

Cite: create.roblox.com art/modeling/specifications + research-notes.md — hard cap **20,000 tris per MeshPart**; split, never simplify. 1 Blender unit = 1 stud (= 28 cm). STYLE LOCK warm stylized realism (Art hex table).

| Asset | MeshParts (split at 20k) | Stud size target | Collision | Notes |
|---|---|---|---|---|
| Lift bridge | Deck, TowerL, TowerR, AbutL, AbutR, Booth | deck 32×56; towers spawn-readable | Deck Hull/Default drive; towers Box | MeshId 0 greybox shippable |
| Town free bridge | Deck, AbutL/R | deck 32 × span | same | no booth mesh |
| Stone branch | Deck, FaceL/R | width 24 | Hull | quieter silhouette |
| Car ferry | Hull, Deck, Cabin, Rails | deck **18×84** | Deck driveable; Hull non-block or separate | no mast in drive lane |
| Dock pair | Deck, Piles, Bollards | ≥20×16 apron | Deck Hull | bollards every 8 (Art) |

Export FBX/glTF per blender-roblox checklist; Studio Import 3D; Connor sets MeshIds. Do not claim meshes live without MeshId/screenshot.

## MustKeep / do not touch

Spawn; TollBooth model (pin retarget OK); FerryDock tags (relocate OK); T411/T412 shops + pads; Dealership door + Origin; Weigh/mill; Block wood; no StoreData/Cap/catalog. Soft bay-stack parked.

## Risks

1. Leave ferry deck 14×22 → truck weld clears world / fails lint.
2. Road width stays 28 → two trucks jam on lift.
3. Bay Road / spur at wrong Z paves Land Office.
4. Skyroot grade >12% or hairpin <32.
5. Harbour berth overlaps Sparkworks floor before Ready.

## PR must show (Builder)

(1) Lift 32×56 + free town bridge top-down (2) Dealership spur clear of Land Office (3) Ferry deck overlay vs LoggingRig+trailer footprint (4) Dock pins at (920,−640)/(1100,−700) vs Sparkworks (5) Skyroot path to (−40,720) + grade probe ≤12% (6) Junction Signposts off-lane (7) whole-world overlap + door/path clear (8) no gondola leftovers.
