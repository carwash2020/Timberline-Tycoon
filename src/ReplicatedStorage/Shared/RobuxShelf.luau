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

local BoxSize = require(script.Parent.BoxSize)
local StoreData = require(script.Parent.StoreData)

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

-- The table: where it stands (final studs) and how wide a box needs.
RobuxShelf.Class = "S"
RobuxShelf.TableZ = 16.4
RobuxShelf.TableDepth = 3.8
RobuxShelf.TableTop = 3.9 -- the table top, above the model origin (the counter top height)
RobuxShelf.Step = BoxSize.Class(RobuxShelf.Class).size.X + BoxSize.Gap -- centre to centre along x
RobuxShelf.BoxHalfHeight = BoxSize.Class(RobuxShelf.Class).size.Y / 2

function RobuxShelf.SlotId(kind: string, key: string): string
	return "robux-" .. kind .. "-" .. key
end

-- Every listed pass, then every listed product, in StoreData's order.
function RobuxShelf.List(): { Entry }
	local out: { Entry } = {}
	for _, pass in ipairs(StoreData.ListedPasses()) do
		table.insert(out, {
			slotId = RobuxShelf.SlotId("Pass", pass.key),
			kind = "Pass",
			key = pass.key :: string,
			displayName = pass.name,
			color = RobuxShelf.Gold,
		})
	end
	for _, product in ipairs(StoreData.ListedProducts()) do
		table.insert(out, {
			slotId = RobuxShelf.SlotId("Product", product.key),
			kind = "Product",
			key = product.key :: string,
			displayName = product.name,
			color = RobuxShelf.Gold,
		})
	end
	return out
end

function RobuxShelf.Get(slotId: string): Entry?
	for _, entry in ipairs(RobuxShelf.List()) do
		if entry.slotId == slotId then
			return entry
		end
	end
	return nil
end

-- What the server may forward as a BuyRobuxItem intent for a box: only a
-- kind and key the shelf lists.
function RobuxShelf.Find(kind: string, key: string): Entry?
	return RobuxShelf.Get(RobuxShelf.SlotId(kind, key))
end

-- One row along the back wall, evenly spaced.
function RobuxShelf.Placements(): { Placement }
	local list = RobuxShelf.List()
	local out: { Placement } = {}
	for i, entry in ipairs(list) do
		table.insert(out, {
			slotId = entry.slotId,
			x = (i - (#list + 1) / 2) * RobuxShelf.Step,
			y = RobuxShelf.TableTop + RobuxShelf.BoxHalfHeight,
			z = RobuxShelf.TableZ,
		})
	end
	return out
end

-- How wide the row is, so the table can be built to fit.
function RobuxShelf.RowWidth(): number
	local n = #RobuxShelf.List()
	return math.max(1, n) * RobuxShelf.Step + 1.2
end

-- The tag over a box. Roblox owns the price; until the server has it the
-- tag says only R$.
function RobuxShelf.Tag(price: number?): string
	if type(price) == "number" and price > 0 then
		return string.format("R$ %d", math.floor(price))
	end
	return "R$"
end

return RobuxShelf
