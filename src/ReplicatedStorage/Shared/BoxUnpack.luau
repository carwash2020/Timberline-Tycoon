--!strict
-- BoxUnpack: what happens when a shop box is opened. Pure. BoxService and
-- ShopService apply it.
--
-- Paying at the counter charges once and hands the buyer the BOX (the
-- physical, designed box); nothing goes to the inventory yet. The buyer
-- opens it (Interact: E on a keyboard, X on a gamepad, tap on a phone,
-- near it or holding it) and the item comes out:
--   "pickup"  small things (axes, gear, a cosmetic, goods) come out as a
--             physical object on the spot; the buyer picks it up (Interact
--             again) and it goes to the hotbar or the inventory.
--   "stock"   plot items (the chop saw, blueprints) unpack into
--             the buyer's stock to place with the hammer, as before.
--   "place"   sawmills, planers, conveyor pieces and the Sky Bin (Connor, 6 October 2026):
--             opening the box starts a placement ghost on your plot. The box
--             stays where it is until you CONFIRM: placing spends it (one-time
--             use, no stock list, no blueprint book entry); cancelling keeps
--             it. PlotService.Place checks the box uid and BoxService spends it.
--   "vehicle" a truck or trailer unpacks onto the buyer's pad on their
--             plot (the pad rule: vehicles only exist on a pad).
-- The empty box then folds away (PoofSeconds) and is destroyed.
--
-- Nothing is lost or doubled: a paid box that is not yet opened is kept in
-- the save with `pending = true` (the item is still owed); an unclaimed
-- pickup is converted into the inventory after PickupSeconds or when its
-- owner leaves. A box saved before this change has no `pending` mark: its
-- item was granted at the counter, so opening it only unpacks it.

local ItemCatalog = require(script.Parent.ItemCatalog)

local BoxUnpack = {}

BoxUnpack.TakeRange = 12 -- studs, buyer to the pickup
BoxUnpack.PickupSeconds = 300 -- an unclaimed pickup converts to inventory after this
BoxUnpack.PoofSeconds = 0.6 -- how long the empty box takes to fold away
BoxUnpack.PickupLift = 1.6 -- studs the item floats over where the box stood

export type Mode = "pickup" | "stock" | "vehicle" | "place"

-- How an item kind comes out of its box.
function BoxUnpack.Mode(kind: string, itemId: string?): Mode
	if kind == "Truck" or kind == "Trailer" then
		return "vehicle"
	elseif kind == "Sawmill" then
		return "place"
	elseif kind == "Machine" then
		local machine = if itemId then ItemCatalog.GetMachine(itemId) else nil
		return if machine and machine.placeFromBox == true then "place" else "stock"
	elseif kind == "Blueprint" then
		return "stock"
	end
	return "pickup"
end

-- Whether the item is still owed when the box is opened (see the header).
function BoxUnpack.Owed(pending: boolean?): boolean
	return pending == true
end

export type TakeFacts = {
	userId: number,
	buyerId: number,
	distance: number,
	taken: boolean?,
}

export type TakeReason = "owner" | "far" | "taken"

function BoxUnpack.CanTake(facts: TakeFacts): (boolean, TakeReason?)
	if facts.taken == true then
		return false, "taken"
	end
	if facts.buyerId ~= facts.userId then
		return false, "owner"
	end
	if facts.distance > BoxUnpack.TakeRange then
		return false, "far"
	end
	return true, nil
end

function BoxUnpack.TakeMessage(reason: string?): string?
	if reason == "owner" then
		return "That isn't yours."
	elseif reason == "far" then
		return "Walk closer to pick it up."
	end
	return nil
end

-- True once an unclaimed pickup has waited long enough to be converted.
function BoxUnpack.Expired(now: number, madeAt: number): boolean
	return now - madeAt >= BoxUnpack.PickupSeconds
end

-- The line shown when the box opens.
function BoxUnpack.OpenedLine(mode: string, name: string): string
	if mode == "pickup" then
		return string.format("Opened! Pick up the %s.", name)
	elseif mode == "stock" then
		return string.format("Unpacked the %s. Place it with your hammer on your plot.", name)
	elseif mode == "place" then
		return string.format(
			"Place the %s on your plot: click to put it down, Q to cancel. The box is used up when you place it.",
			name
		)
	end
	return string.format("Unpacked the %s.", name)
end

-- The storage entry for a paid box that is kept in the save.
export type Stored = { uid: string, itemId: string, shop: string, pending: boolean? }

function BoxUnpack.StoredEntry(uid: string, itemId: string, shop: string, owed: boolean): Stored
	return { uid = uid, itemId = itemId, shop = shop, pending = if owed then true else nil }
end

-- Kinds that may only be bought once while a copy is still in a box: two
-- unopened boxes of the same gear or blueprint would grant it twice. So
-- would two Sky Bins (one per player); the other machines are not limited.
function BoxUnpack.OneAtATime(kind: string, itemId: string?): boolean
	return kind == "Gear" or kind == "Blueprint" or (kind == "Machine" and itemId == "SkyBin")
end

return BoxUnpack
