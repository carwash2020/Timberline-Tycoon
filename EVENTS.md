# EVENTS: how to schedule a store event

Each of the four stores (Tool Shed, Hearth & Home, Sparkworks, Dealership) has an empty, roped-off **event area** and a
**banner** by the door. They are closed and hidden until you schedule an event. Scheduling one needs no code change: you fill in
one small table.

**Nothing goes on sale and nothing is priced by this system.** An event on its own only opens the roped-off area and shows the
banner (it says COMING SOON unless you give it words). An item can be bought during an event only if you have done all three
of these on purpose: (1) approved the item, (2) set its price, (3) listed its slot in the event. Until then the event area is
just an empty, lit floor with a sign. A slot with no price can never be bought.

## 1. What an event looks like

| Field | What to put | Notes |
| --- | --- | --- |
| `store` | `"ToolShed"`, `"HearthAndHome"`, `"Sparkworks"` or `"Dealership"` | Exactly this spelling, in quotes. |
| `startsAt` | `"2026-12-01"` or `"2026-12-01 18:00"` | UTC time (not your local time). A date alone means the start of that day. |
| `endsAt` | `"2026-12-15"` | The first moment it is **over**. Must be after `startsAt`. No longer than **60 days** after it, or the whole event is ignored. |
| `enabled` | `true` or `false` | `false` switches it off without deleting it. Leave it out and it is off. |
| `items` | `{}` | **Leave empty** until you have approved an item and set its price (section 3). |
| `bannerText` | `"WINTER FAIR"` | Optional. Up to 24 characters. Leave it out and the banner says COMING SOON. |

If a date does not exist (like `2026-02-30`), the end is before the start, or the store name is misspelled, that event is
ignored and everything stays closed. Nothing breaks.

## 2. Schedule it (the committed way, goes live on your next publish)

1. Open `src/ReplicatedStorage/Shared/StoreEventData.luau` (in your Timberline-Tycoon folder, in VS Code or Notepad).
2. The table starts empty: `StoreEventData.Events = {} :: ...`. Put your event between the braces, so it looks like this:

```lua
StoreEventData.Events = {
	{
		store = "HearthAndHome",
		startsAt = "2026-12-01",
		endsAt = "2026-12-15",
		enabled = true,
		items = {},
		bannerText = "WINTER FAIR",
	},
} :: { { [string]: any } }
```

3. Save the file. To add a second event, add another `{ ... },` block under the first. Several events can overlap, even for the same
   store: it stays open until the last one ends.
4. To check it without opening Studio, in PowerShell in your Timberline-Tycoon folder:

```powershell
lune run tests/run StoreEvent
```

   It should print `passed` and `0 failed`. (If you do not have `lune`, run `./scripts/check.sh` as usual or let CI do it on the pull request.)
5. Commit and open a pull request as usual. The event turns itself on at `startsAt` and off at `endsAt` on every server, even
   if a server restarts. To end one early, set `enabled = false` and publish.

## 3. Putting an item in an event (do this only when you mean to sell something)

Each store has three event slots in `src/ReplicatedStorage/Shared/StoreData.luau`, under `StoreData.EventSlots`
(for example `event-hearth-1`, `event-hearth-2`, `event-hearth-3`). They start with `approved = false`, no item and no price.
To sell something in a slot, fill in that one row:

```lua
{ id = "event-hearth-1", store = "HearthAndHome", index = 1, eventSlot = true, visible = false,
  approved = true, itemKind = "Cosmetic", itemId = "TheItemId", price = 250 },
```

then add `"event-hearth-1"` to that event's `items = { ... }`. All of these must be true at the same time or the slot cannot be
bought: the event is running, the slot is listed in `items`, `approved = true`, an `itemKind` and `itemId` are set, and `price` is a
whole number above 0. Taking an event down (`enabled = false`, or its end date) pulls its items off sale at once. People who already
bought one keep it. This is not a sale of anything for Robux: the price is in-game cash.

## 4. Test it in Studio without publishing

You do not need to edit any file for this.

1. Open the game in Studio and press Play (a Play Solo test is fine).
2. In the **Explorer**, click **Workspace**. In the **Properties** panel scroll to **Attributes** and add a new attribute:
   name `StoreEventConfig`, type **String**.
3. Paste the event as one line of JSON as its value (use today's dates so it is running now), for example:

```json
{"store":"HearthAndHome","startsAt":"2026-12-01","endsAt":"2026-12-15","enabled":true,"items":[],"bannerText":"Test Day"}
```

   (Pasting it before pressing Play also works. A list of events in `[ ... ]` is fine too.)
4. Within a minute the Hearth & Home event area opens (the rope comes down and the lamp turns on) and the banner by the door
   shows TEST DAY. Clear the attribute, or set `"enabled":false`, and it closes again within a minute.
5. This attribute is read **only in Studio**. A live server ignores it, so nothing you type there can reach players.

If nothing happens, the dates are probably not covering today, the store name is misspelled, or the JSON has a missing quote
or comma. The Output window shows `[StoreEventService] StoreEventConfig is not valid JSON` for broken JSON.

## 5. For the people building the stores

- `ShopEventKit.BuildZone(parent, kind, anchor, size?)` builds the roped-off area (about 26 parts). `anchor` is the middle of the
  zone's floor footprint on the floor surface; its **-Z side is the open front** (toward the aisle) and +Z is the back (a wall or
  a shelf run). `size` is the footprint (x wide, z deep); the default is 16 x 9, the least 12 x 8 (the Sparkworks' back corner is 12 wide, so its three table spots come out about 2.3 wide). It makes the tag
  `EventExpansion`, attributes `Store` and `Active = false`, three table spots `EventTable1..3` (invisible parts, each with an
  Attachment `TableAttachment`) and one lamp. Nothing in it collides.
- `ShopEventKit.BuildBanner(parent, kind, anchor, width?)` builds the banner by the door (about 8 parts). `anchor` is the middle of
  its base on the floor, facing -Z. Its board is `EventBanner`, tagged `EventBanner`, attributes `Store`, `Active`, `Text`.
  Keep it off the doorway.
- Place both inside the store's interior with a free floor area of the zone's size, clear of the counter, tables and the aisle.
  `StoreEventService` finds them by tag and flips them; the store builder never has to.
- The part budget for both together is `ShopEventKit.PartBudget` (36), a tenth of a store's 400.
