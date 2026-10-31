# T414b plan: the Dealership lot shows the working fleet

Branch `cursor/t414b-dealership-fleet`, base main `9b2a43f`. Plan first; specs red then green; then code.

## What main already does (T421, #265)

78 custom MeshIds (all filled), the 15 trailer and truck axle combos, the 20.5 hall, COMING SOON plinths, the missing-mesh
rule (VehicleMeshGate) and the Timber Classic as a pass vehicle. Colours are baked in the GLBs and code never recolours a
mesh. In a meshed vehicle only the parts in `VehicleMeshes.KEEP` (hull, stakes, rails, wheels, lamps) stay part-built, so the
colour table below reaches the player through those parts and through every part-built vehicle (a mesh that has not
loaded, and the preview tool, which cannot load uploaded Roblox meshes).

## Files

- `Art/TruckArt.luau` (colours, wear, glass; no names, sizes or attributes change)
- `Art/DealershipLot.luau` only if a lot spec below fails on main
- `tests/TruckArt.spec.luau`, `tests/DealershipLot.spec.luau` (new tests); `DealershipOverlap`, `VehicleWheelClearance`
  stay green and unedited
- `tools/preview/scenes/t414b-*.luau` and `preview/t414b/` renders
- `STATUS.md`, `PHASE2_NOTES.md` (Studio checks)

Not touched: VehicleService, PassService, PaintShop/PaintService, prices, truck stats, ItemCatalog, StoreData, Vendor.
`Art/VehicleMeshes`, `VehicleMeshIds`, `VehicleModels` stay as they are (see "MeshId 0" below).

## Approach: the colour table, part by part

Shared (every part-built vehicle): tyres #2A2624, headlight #FFE9B0, taillight #B0241C, amber markers #FFB23F, glass #9CCBE0
at transparency 0.4 (was 0.45 and the Rustbucket's cracked 0.6), coupler #B0241C, hub and lug bolts #9AA1A8, trailer and
Flatbed tandem fenders #8E949A. Truck cab fenders stay body paint (a pontoon fender is part of the body).

| Vehicle | Change in the part-built art |
| --- | --- |
| Rustbucket | body #964830, primer door, cream grille and rims, bare metal #6E5D50 already; wood (bed, boards, tailgate) becomes PlankHoney, running boards and bumper blocks TimberBrown; a primer patch on a fender and dirt on the lower panels |
| Pickup | chrome parts #D3D8DC (grille, trim, mirrors, caps); dirt on the lower panels |
| ScoutATV | frame #33302D, front basket rack TimberBrown #7A5230, handlebar stays frame colour |
| Flatbed | deck PlankHoney (was black), stakes TimberBrown, stake rails PlankHoney, red #B0241C accent stripe on the cab and bumper, tandem fenders #8E949A |
| LoggingRig | Brass #C9A24A headache rack and a Brass cap on every stanchion; deck TimberBrown |
| TimberClassic (the Pickup builder, `def.classic`) | chrome #EEF0F2, trim and rims #5A3B26, stake posts and rails PlankHoney #C49A63 |
| Pony Trailer | body #7A5A3A, deck PlankHoney |
| Ranch Trailer | #6E7F46 open stake side (stakes and two rails, no side boards), 2 axles (TrailerAxleData, already), rails PlankHoney |
| Heavy Hauler | #4A4F57, bunks (stanchions) #242321, bolts #9AA1A8, fenders #8E949A |

Wood is only PlankHoney or TimberBrown (via `Palette`), with the existing small `Kit.vary` kept so boards stay hand
painted. The colours the table pins for part-built parts are checked in the spec.

Which colours are baked in meshes (not recoloured by code, verified in Studio only): every truck's Body, Glass, Lights, Bed
and Hitch, and every trailer's Body, Bed, Lights and Hitch. The four recoloured trucks and all 48 trailer meshes were exported
for the table; the ScoutATV and the Timber Classic mesh colours cannot be checked here.

## The lot (acceptance 2, 3, 5)

Checked by new specs; code changes only if a spec is red on main:

- each bay's plinth is at least its vehicle's width + 4 deep and its length + 4 wide, bays keep their gap and do not overlap
- every vehicle stands wholly on its plinth and inside the hall; trailers sit inside the lot
- a trailer's hitch point is on the plinth, within arm's reach of walkable plinth top, nothing solid within 4 studs of it
  (display copies are decor: no collision), so the hitch can be walked up to
- Dealership door (189.25, 100.3) and lot origin (207, 100.2) unmoved; no price or stock change
- no display vehicle has a MeshPart with MeshId 0 at Transparency 1, and each shows visible parts

Hitched on the lot: trailers keep their own bays (T421). A trailer hitched to a truck is shown in the renders (the same
`TruckArt.Build` the player's vehicle uses). Putting a hitched trailer in every truck bay would lengthen the hall; that is a
follow-up, listed in the PR body.

## MeshId 0 and stale ids

None is changed. The ids that ASSETS.md marks "needs re-upload" (the pre-T421 ScoutATV, and the base set the four recoloured
trucks fall back on) are live and loading; zeroing them would make those vehicles lose their meshes. If Connor says an id is
stale, the numbered upload steps go in the PR body for that vehicle.

## Specs (written first, shown red)

1. `TruckArt`: colour table per vehicle for part-built parts (new test, one per vehicle plus shared)
2. `TruckArt`: all glass is #9CCBE0 at 0.4 and never collides; the Rustbucket's cracked-windshield line (pinned 0.6) moves to 0.4
   because the brief sets the glass for every vehicle
3. `TruckArt`: wood parts are PlankHoney or TimberBrown (within the vary band)
4. `TruckArt`: Ranch Trailer has two axles and no side boards (open stake side)
5. `DealershipLot`: bay >= width + 4, hitch reachable, door and origin unmoved, no invisible vehicle
6. Existing: VehicleWheelClearance, DealershipOverlap, GeometryLint, MustKeep, Clearance, PipelineE2E stay green

## Renders (`preview/t414b/`, Midday)

Before (main) and after: lot top-down, lot 3/4, a turntable of each truck, each truck with its trailer hitched, a 667x375
phone crop. Three.js previews, not Studio or Roblox lighting; the tool cannot load uploaded Roblox meshes, so these show the
part-built art.
