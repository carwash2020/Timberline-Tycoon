# Designer — T413 Travel (2026-10-28 ~3:45 PM MT)

Sources: vision.md §2 LT2 lessons (W7 ferry, W8 bridge), §3 travel (no gondola), §4 travel times; LT2 wiki Bridge / Ferry / Bridge Booths (read 2026-10-28); GameConfig main `a66c562` TollFee 100 TollSeconds 180 FerryFare 400 FerryIntervalSec 360 StartingCash 20 PlotPrice 150 DynamitePrice 220; FerryLogic TravelSec 40 BoardCloseSec 3 Deck 14×22; Connor locks via Manager T413 (town/main bridge free, out-of-town bridge $100, ferry $350, no paid fast travel); T412 Designer fees table. Square Block wood stays. No StoreData / Cap / catalog edits.

## Findings (LT2 → Timberline)

| LT2 fact | Principle we keep | Timberline beat |
|---|---|---|
| Lift bridge to Safari: pay **$100**, stays down **3 min**, extend +$100 [wiki Bridge] | First big-ticket outing is one paid river crossing | Same numbers (`TollFee` / `TollSeconds`). Town/main bridge is **free** so early loop never pays a toll |
| Bridge booth NPC both sides; Super Bridge pass skips cash | Clear booth + pay once to open a timed window | Keep booth only on the **out-of-town** lift. No Robux pass required for V1 toll (cash only). Southbound free (REPO) |
| Ferry to Tropics: **$400** one-way ticket, every **~6 min**, long sail (~2+ min), seat/ticket friction [wiki Ferry] | Specialist shops sit across water; fare is a mid-game cash gate | Fare **$350** (Connor). Crossing **≤40 s** (`TravelSec`). Player **walks the deck**. Truck + trailer ride with the boat (CarFerry). Charge at cast-off, step-off = free |

## Player flow (Dealership → Isle → Skyroot)

1. **Town (free).** Spawn → Tool Shed → woods → mill / Weigh House. Town/main bridge has **no** TollLine. First 5 minutes stay $0 travel.
2. **Dealership (first paid gate).** Drive across the **out-of-town lift bridge**: pay **$100** once → open **180 s**. Unpaid Crossed strip pushes back. Teaches driving; Dale’s lot is the reward (T412 pin).
3. **Ferry dock (~30 s from mill, vision §4).** Cap’n Moss board. Fare shown as **$350**. Board on foot or drive truck onto deck. Boarding closes **3 s** before cast-off. Fare taken **once per rider** at depart (seated driver = one rider, not driver+truck). Short cash → stay on dock, uncharged.
4. **Crossing (~40 s).** Walk the deck (views, no seat lock). Arrive Isle / Sparkworks harbour. Clear T412 `FerryRequired` only when ferry Ready (Scripter). Sparkworks is the late wiring shop (Link’s Logic lesson).
5. **Return.** Same ferry, another **$350** one-way. No round-trip discount V1 (keeps Isle trips intentional).
6. **Skyroot.** Switchback road from the valley; climb is the content (~70 s vision). GateLodge sells **Sky Pass** (progression, not a road toll). No gondola, no paid fast travel, no second cash toll invented on the climb unless Connor asks later.

## Fare feel at $350

| Cash gate | Amount | When it hits |
|---|---|---|
| StartingCash | $20 | spawn |
| PlotPrice | $150 | first land |
| Toll (Dealership side) | $100 / 180 s | first trip out |
| DynamitePrice | $220 | Odds charges before Gloam |
| **Ferry** | **$350** one-way | Isle / Sparkworks |
| REPO was | $400 | flip to $350 this ticket |

$350 sits above dynamite and plot, below late vehicles / full-plot grind. It is a deliberate specialist gate, not an early soft-lock. Slightly under LT2’s $400 matches Connor’s lock and still feels like a trip you plan for. **Do not** add a Robux “skip ferry” pass in T413 (V1 cash gates only; Super Hoove-style pass is Needs Connor later).

## Toll UX (player-facing)

- One paid lift only: Dealership-side out-of-town bridge.
- Booth prompt: pay **$100** → bridge open **3 minutes**; “already paid” if window active; extend = pay again for another 180 s (matches LT2 + REPO).
- Free town/main bridge: no booth, no StopRed, no SpendCash.
- Fail: unpaid drive into Crossed → push back with clear reason (existing TollLogic).

## Ferry timetable / deck (player-facing)

- Keep interval **6 min** per dock (`FerryIntervalSec` 360) and **40 s** sail (vision “under 40 s”).
- Board prompt: `Board ($350)` from GameConfig (no hardcode).
- Timetable board at each dock + Cap’n Moss TalkLines (already fare/interval/TravelSec driven).
- Deck must read truck-scale (Builder/Art grow deck if 14×22 is tight; Designer wants truck + trailer on, not foot-only).
- Fail-closed: no docks / not Ready → no Board, Sparkworks stays closed.

## Sign copy (lock these strings)

| Sign | Copy |
|---|---|
| Town / main bridge | `TOWN` or omit toll; never show a price |
| Out-of-town lift booth | `TOLL $100` |
| Junction toward Dale | `DEALERSHIP →` |
| Junction toward harbour | `FERRY / LANTERN ISLE` |
| Ferry dock board | `LANTERN FERRY` + `FERRY $350 · every 6 min · ~40 s` |
| Junction toward summit | `SKYROOT ↑` |
| GateLodge (existing Sky Pass) | keep Sky Pass copy; **no** gondola arrow |
| Return to valley | `TOWN (free bridge)` |

No Robux glyph. No gondola / sky-tram wording. Prices only on toll booth and ferry board.

## Risks

1. Leaving `FerryFare` 400 or `$400` UI/tests → misses Connor lock.
2. Keeping truck refuse while Dealership→Isle needs a loaded truck → broken loop.
3. Opening Sparkworks before ferry Ready → soft buys with no travel.
4. Putting a TollLine on the free town bridge → false early gate.
5. Deck too small for truck+trailer → stuck / overlap (Builder clearance owns sizes).
6. Adding paid fast travel or a Robux skip → violates V1 lock.

## Tests a player would notice (for QA paste)

1. Town/main bridge: cross with $0; no booth / no cash prompt.
2. Dealership approach: first pay is exactly **$100**; window **180 s**; second tap while open = already; unpaid Crossed pushes back.
3. Ferry dock board and Board prompt show **$350** (not $400).
4. Step on deck, step off before cast-off → $0 charged.
5. Stay aboard at cast-off with enough cash → **$350** once; Paid text; arrive Isle; walk during the ~40 s sail.
6. Drive a truck onto the deck, sail, drive off far dock (loaded or empty).
7. Short cash at cast-off → remain on dock, uncharged, ShortText.
8. Sparkworks buy fails until ferry Ready; succeeds after first successful Bind/Ready.
9. No gondola station, cable, cabin, or sign anywhere on the travel path.
10. Junction signs match the copy table; Skyroot climb has no invented cash toll.
11. Diff: `FerryFare` 350; no StoreData / Cap / ItemCatalog price edits; Block wood unchanged.

File: `/workspace/roblox/briefs/t413-sections/designer.md`
