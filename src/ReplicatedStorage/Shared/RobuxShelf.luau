--!strict
-- RobuxShelf: the gold-trimmed shelf at the back of the Tool Shed. One
-- box for every pass and pack StoreData lists (the ids set in Creator
-- Hub). It sells nothing for cash and changes no price: StoreData stays
-- the only place an id or a name is written, and MonetizationService is
-- still what shows Roblox's prompt and grants the item.
--
-- The flow is the shelves' flow. Carry the box to the counter; the
-- shopkeeper asks; on Yes the server tells the client which item it is,
-- the client sends the same BuyRobuxItem intent the Store screen sends,
-- and MonetizationService checks it and shows Roblox's own dialog. The
-- box goes back to its shelf (it is a display, there is no cash unit).
--
-- Positions are final studs from the shop's origin, like StoreStock: a
-- table along the back wall, centred on x = 0. Its boxes are class S.
--
-- Lane P: only items Roblox says are for sale get a box. The table has a
-- slot for every item with a real id (StoreData order); the server's sale
-- cache (StoreSaleService) is installed with SetSaleCheck, and an item it
-- knows is off sale has no box and is refused at the counter. No price is
-- read here or on the server: the hover tag asks the player's own client
-- (StorePrices), because regional prices differ per player.

local BoxSize = require(script.Parent.BoxSize)
local StoreData = require(script.Parent.StoreData)
local StoreSale = require(script.Parent.Store.StoreSale)

local RobuxShelf = {}

export type Entry = {
	slotId: string,
	kind: string, -- "Pass" | "Product", what BuyRobuxItem takes
	key: string,
	displayName: string,
	color: string,
}

export type Placement = {
	slotId: string,
	x: number,
	y: number,
	z: number,
}

-- The box colour (gold) and the ink on its marks.
RobuxShelf.Gold = "#E3B73C"
RobuxShelf.GoldInk = "#6B4A12"

-- The table: where it stands (final studs). Two rows: the passes on the
-- table top at the front, the products on a riser behind them, so nine
-- boxes fit the shed's back wall (one row of nine would be 40 studs).
RobuxShelf.Class = "S"
RobuxShelf.TableZ = 19.1 -- the table's middle: its front edge behind the lanes (16.8), the back row clear of the axe rack (21.36)
RobuxShelf.TableDepth = 4.5
RobuxShelf.TableTop = 3.9 -- the table top, above the model origin (the counter top height)
RobuxShelf.RiserH = 1.0 -- the back row stands this much higher
RobuxShelf.FrontZ = RobuxShelf.TableZ - 1.15
RobuxShelf.BackZ = RobuxShelf.TableZ + 1.15
RobuxShelf.Gap = BoxSize.Gap -- between boxes in a row (the shelves' gap)
RobuxShelf.Step = BoxSize.Class(RobuxShelf.Class).size.X + RobuxShelf.Gap -- centre to centre along x
RobuxShelf.BoxHalfHeight = BoxSize.Class(RobuxShelf.Class).size.Y / 2

function RobuxShelf.SlotId(kind: string, key: string): string
	return "robux-" .. kind .. "-" .. key
end

-- Roblox's sale answer for an item (true, false, or nil while unknown).
-- The server installs its cache; until then (and in tests) nothing is known.
local saleCheck: (kind: string, key: string) -> boolean? = function(_kind: string, _key: string): boolean?
	return nil
end

function RobuxShelf.SetSaleCheck(fn: (kind: string, key: string) -> boolean?)
	saleCheck = fn
end

-- Every item with a real id, in StoreData's order (passes, then products):
-- the table's slots. Whether a slot holds a box is OnSale's.
function RobuxShelf.List(): { Entry }
	local out: { Entry } = {}
	for _, entry in ipairs(StoreData.Ordered()) do
		if StoreData.IsForSale(entry.item.id) then
			table.insert(out, {
				slotId = RobuxShelf.SlotId(entry.kind, entry.key),
				kind = entry.kind :: string,
				key = entry.key,
				displayName = entry.item.name,
				color = RobuxShelf.Gold,
			})
		end
	end
	return out
end

-- Whether a listed entry shows a box: Roblox says it's for sale, or hasn't
-- answered yet. A known "no" has no box.
function RobuxShelf.OnSale(entry: Entry): boolean
	return StoreSale.ShowInWorld(StoreData.IdOf(entry.kind, entry.key), saleCheck(entry.kind, entry.key))
end

-- The entry for a slot, only while it is on sale (BoxService stocks and
-- sells through this).
function RobuxShelf.Get(slotId: string): Entry?
	for _, entry in ipairs(RobuxShelf.List()) do
		if entry.slotId == slotId then
			return if RobuxShelf.OnSale(entry) then entry else nil
		end
	end
	return nil
end

-- What the server may forward as a BuyRobuxItem intent for a box: only a
-- kind and key the shelf lists.
function RobuxShelf.Find(kind: string, key: string): Entry?
	return RobuxShelf.Get(RobuxShelf.SlotId(kind, key))
end

-- Two rows, each evenly spaced and centred: passes at the front on the
-- table top, products behind on the riser.
function RobuxShelf.Placements(): { Placement }
	local rows: { [string]: { Entry } } = { Pass = {}, Product = {} }
	for _, entry in ipairs(RobuxShelf.List()) do
		table.insert(rows[entry.kind], entry)
	end
	local out: { Placement } = {}
	for _, kind in ipairs({ "Pass", "Product" }) do
		local row = rows[kind]
		local back = kind == "Product"
		for i, entry in ipairs(row) do
			table.insert(out, {
				slotId = entry.slotId,
				x = (i - (#row + 1) / 2) * RobuxShelf.Step,
				y = RobuxShelf.TableTop + (if back then RobuxShelf.RiserH else 0) + RobuxShelf.BoxHalfHeight,
				z = if back then RobuxShelf.BackZ else RobuxShelf.FrontZ,
			})
		end
	end
	return out
end

-- How wide the table is: the longer row, plus a margin.
function RobuxShelf.RowWidth(): number
	local passes, products = 0, 0
	for _, entry in ipairs(RobuxShelf.List()) do
		if entry.kind == "Pass" then
			passes += 1
		else
			products += 1
		end
	end
	return math.max(1, passes, products) * RobuxShelf.Step + 1.0
end

-- The tag over a box. Roblox owns the price, read by this player's client;
-- until it is back the tag says only R$.
function RobuxShelf.Tag(price: number?): string
	if type(price) == "number" and price > 0 then
		return "R$ " .. tostring(math.floor(price))
	end
	return "R$"
end

return RobuxShelf
