--!strict
-- WireSupply: wire as a single-use item (T420). Pure, so the server (which
-- decides), the wire tool (which shows the price as you stretch) and the tests
-- run the same rules.
--
--   * Wire is bought by the amount needed, in units (one unit is one stud), at
--     the price in ItemCatalog.Wire (no price lives here).
--   * A wire is placed at an output and stretched to an input up to MaxLength
--     (WireLogic.Span, the longest wire the server accepts).
--   * Stretching it uses up its length, rounded up, from your box. Cutting a
--     wire gives nothing back.
--   * The box holds at most MaxStock; one purchase is at most MaxBuy.

local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)
local WireLogic = require(script.Parent.WireLogic)

local WireSupply = {}

WireSupply.MaxLength = WireLogic.Span -- studs in one wire
WireSupply.StudsPerUnit = 1
WireSupply.MaxStock = 200 -- units the box holds
WireSupply.MaxBuy = 100 -- units in one purchase

export type Quote = {
	state: string, -- "ok" | "short" | "far"
	length: number,
	units: number, -- what the wire uses (0 for a bad length)
	cost: number, -- what those units cost at the shop price
	short: number, -- units missing from the box (0 unless "short")
	buyCost: number, -- what the missing units cost
	left: number, -- units left in the box after the wire (ok only)
}

function WireSupply.UnitPrice(): number
	return ItemCatalog.GetWire().unitPrice
end

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function whole(n: unknown): boolean
	return finite(n) and (n :: number) == math.floor(n :: number)
end

-- A box count from a save or an attribute: a whole number from 0 to MaxStock.
function WireSupply.Clean(value: unknown): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.min(math.floor(value), WireSupply.MaxStock)
end

-- The ground distance between two pieces (plot-local x and z).
function WireSupply.Length(a: { x: number, z: number }, b: { x: number, z: number }): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Whether a wire this long may be stretched.
function WireSupply.Fits(length: number): boolean
	return finite(length) and length >= 0 and length <= WireSupply.MaxLength
end

-- Units a wire of `length` uses: one per stud, rounded up, at least one. A
-- length that is not a number, or is negative, uses nothing (it is refused).
function WireSupply.UnitsFor(length: number): number
	if not finite(length) or length < 0 then
		return 0
	end
	return math.max(1, math.ceil(length / WireSupply.StudsPerUnit - 1e-9))
end

function WireSupply.Quote(stock: number?, length: number): Quote
	local have = WireSupply.Clean(stock)
	if not WireSupply.Fits(length) then
		return {
			state = "far",
			length = length,
			units = WireSupply.UnitsFor(length),
			cost = 0,
			short = 0,
			buyCost = 0,
			left = have,
		}
	end
	local units = WireSupply.UnitsFor(length)
	local price = WireSupply.UnitPrice()
	if units > have then
		local missing = units - have
		return {
			state = "short",
			length = length,
			units = units,
			cost = units * price,
			short = missing,
			buyCost = missing * price,
			left = have,
		}
	end
	return {
		state = "ok",
		length = length,
		units = units,
		cost = units * price,
		short = 0,
		buyCost = 0,
		left = have - units,
	}
end

-- The box after using `units`, or nil when the box cannot give that many (and
-- nothing is taken).
function WireSupply.Use(stock: number?, units: number): number?
	if not whole(units) or units < 1 then
		return nil
	end
	local have = WireSupply.Clean(stock)
	if units > have then
		return nil
	end
	return have - units
end

-- A purchase of `units`: (true, nil, cost, newStock) or (false, reason). The
-- reasons are "amount" (not a whole number from 1 to MaxBuy), "full" (the box
-- would pass MaxStock) and "cash".
function WireSupply.Buy(cash: number, stock: number?, units: unknown): (boolean, string?, number?, number?)
	if not whole(units) or (units :: number) < 1 or (units :: number) > WireSupply.MaxBuy then
		return false, "amount", nil, nil
	end
	local n = units :: number
	local have = WireSupply.Clean(stock)
	if have + n > WireSupply.MaxStock then
		return false, "full", nil, nil
	end
	local cost = n * WireSupply.UnitPrice()
	if not finite(cash) or cash < cost then
		return false, "cash", nil, nil
	end
	return true, nil, cost, have + n
end

-- How many units to buy for a wire that needs `needed` when the box holds
-- `stock`: the shortfall, and never more than the box has room for.
function WireSupply.BuyAmount(stock: number?, needed: number): number
	local have = WireSupply.Clean(stock)
	if not finite(needed) then
		return 0
	end
	local missing = math.max(0, math.floor(needed) - have)
	local room = WireSupply.MaxStock - have
	return math.max(0, math.min(missing, room, WireSupply.MaxBuy))
end

-- What the player is told. `a` and `b` are the numbers a message names ("short":
-- what the box holds, then what the wire needs).
function WireSupply.Message(key: string, a: number?, b: number?): string
	if key == "bought" then
		return string.format("Bought %d wire.", a or 0)
	elseif key == "short" then
		local have, need = a or 0, b or 0
		return string.format("That wire needs %d and you have %d. Buy %d more.", need, have, math.max(0, need - have))
	elseif key == "cash" then
		return "Not enough cash for that wire."
	elseif key == "full" then
		return string.format("Your box holds %d wire.", WireSupply.MaxStock)
	elseif key == "far" then
		return string.format("Too long. A wire reaches %d studs at most.", WireSupply.MaxLength)
	end
	return "Pick a whole amount of wire."
end

-- "$14", for the price on a button.
function WireSupply.PriceText(cost: number): string
	return Util.formatCash(cost)
end

return WireSupply
