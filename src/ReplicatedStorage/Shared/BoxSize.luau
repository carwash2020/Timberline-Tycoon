--!strict
-- BoxSize: how big a shop box is. Pure. The size follows the item inside
-- (a hatchet is small, a sawmill or the chop saw is big, a vehicle is
-- biggest) from data the item already has: its plot footprint when it has
-- one, otherwise its kind and price tier. Nothing here is a second price
-- table: prices are only read to pick a step, never shown.
--
-- THE SIZE CLASS TABLE (studs, final, width x height x depth; a box's front
-- faces -Z like the shop). Add a class by inserting a row in rank order:
-- ShelfLayout spaces boxes by the width and depth they have, so a bigger
-- class never overlaps its neighbours, and the specs measure that.
--
--   id     size (W x H x D)    plot footprint area (studs^2)   used by now
--   XS     2.2 x 1.8 x 1.8     up to 6                         lanterns, small gear, a chair
--   S      2.8 x 2.2 x 2.2     up to 24                        hatchet-class axes, Robux boxes
--   M      3.6 x 2.9 x 2.9     up to 64                        better axes, a small shed kit
--   L      4.6 x 3.7 x 3.7     up to 130                       cheaper sawmills, the chop saw
--   XL     5.8 x 4.5 x 4.6     up to 270                       the Millmasters
--   XXL    7.4 x 5.6 x 5.8     up to 520                       (free: the first Large item)
--   XXXL   9.4 x 7.0 x 7.4     bigger                          (free)
--
-- Vehicles use their own, bigger, wide and low crate classes (a vehicle box
-- is always the biggest thing in the store; the long side is the width, the
-- front label's side), picked by the vehicle's floor area (width x length):
--
--   V1     9.0 x 4.4 x 5.0     up to 200                       Scout ATV, Pony Trailer
--   V2     11.0 x 5.0 x 5.6    up to 300                       Rustbucket, Ranch Trailer
--   V3     13.0 x 5.8 x 6.2    up to 400                       Pickup, Heavy Hauler
--   V4     15.5 x 6.6 x 6.8    bigger                          Flatbed, Logging Rig
--
-- Anything that has no footprint (axes, gear, a cosmetic, a Robux pass)
-- starts at its kind's base rank and steps up one rank for each PriceStep
-- it reaches, never past the kind's cap.

local BoxSize = {}

export type Class = {
	id: string,
	rank: number,
	size: Vector3,
	maxArea: number, -- footprint area (studs^2) this class takes, inclusive
	vehicle: boolean,
}

export type Spec = {
	kind: string, -- "Axe" | "Gear" | "Sawmill" | "Machine" | "Blueprint" | "Cosmetic" | "Robux" | "Truck" | "Trailer"
	price: number?, -- cash price, only to pick a tier
	footprint: Vector2?, -- width (x) and depth (z) in studs, when the item has one
}

-- Clear studs between neighbouring boxes on a shelf, and between a box and
-- the edge of the shelf.
BoxSize.Gap = 1
BoxSize.EdgeGap = 0.6

BoxSize.Classes = {
	{ id = "XS", rank = 1, size = Vector3.new(2.2, 1.8, 1.8), maxArea = 6, vehicle = false },
	{ id = "S", rank = 2, size = Vector3.new(2.8, 2.2, 2.2), maxArea = 24, vehicle = false },
	{ id = "M", rank = 3, size = Vector3.new(3.6, 2.9, 2.9), maxArea = 64, vehicle = false },
	{ id = "L", rank = 4, size = Vector3.new(4.6, 3.7, 3.7), maxArea = 130, vehicle = false },
	{ id = "XL", rank = 5, size = Vector3.new(5.8, 4.5, 4.6), maxArea = 270, vehicle = false },
	{ id = "XXL", rank = 6, size = Vector3.new(7.4, 5.6, 5.8), maxArea = 520, vehicle = false },
	{ id = "XXXL", rank = 7, size = Vector3.new(9.4, 7, 7.4), maxArea = math.huge, vehicle = false },
} :: { Class }

BoxSize.VehicleClasses = {
	{ id = "V1", rank = 11, size = Vector3.new(9, 4.4, 5), maxArea = 200, vehicle = true },
	{ id = "V2", rank = 12, size = Vector3.new(11, 5, 5.6), maxArea = 300, vehicle = true },
	{ id = "V3", rank = 13, size = Vector3.new(13, 5.8, 6.2), maxArea = 400, vehicle = true },
	{ id = "V4", rank = 14, size = Vector3.new(15.5, 6.6, 6.8), maxArea = math.huge, vehicle = true },
} :: { Class }

-- Item kinds with no footprint: the class they start at, the biggest class
-- they may reach, and the price steps that move them up.
BoxSize.KindBase = {
	Axe = "S",
	Gear = "XS",
	Cosmetic = "S",
	Robux = "S",
	Blueprint = "XS",
	Sawmill = "L",
	Machine = "L",
} :: { [string]: string }

BoxSize.KindCap = {
	Axe = "M",
	Gear = "S",
	Cosmetic = "S",
	Robux = "S",
	Blueprint = "L",
	Sawmill = "XL",
	Machine = "L",
} :: { [string]: string }

BoxSize.PriceSteps = { 1000, 10000 }

-- The class a plain item falls back to when its kind is not in the tables.
BoxSize.DefaultClass = "S"

local byId: { [string]: Class } = {}
for _, class in ipairs(BoxSize.Classes) do
	byId[class.id] = class
end
for _, class in ipairs(BoxSize.VehicleClasses) do
	byId[class.id] = class
end

function BoxSize.Class(id: string): Class
	local class = byId[id]
	if class == nil then
		class = byId[BoxSize.DefaultClass]
	end
	return class :: Class
end

function BoxSize.IsVehicleKind(kind: string): boolean
	return kind == "Truck" or kind == "Trailer"
end

local function byArea(list: { Class }, area: number): Class
	for _, class in ipairs(list) do
		if area <= class.maxArea then
			return class
		end
	end
	return list[#list]
end

local function steps(price: number): number
	local n = 0
	for _, step in ipairs(BoxSize.PriceSteps) do
		if price >= step then
			n += 1
		end
	end
	return n
end

local function shifted(baseId: string, up: number, capId: string): Class
	local base = BoxSize.Class(baseId)
	local cap = BoxSize.Class(capId)
	local rank = math.min(base.rank + up, cap.rank)
	for _, class in ipairs(BoxSize.Classes) do
		if class.rank == rank then
			return class
		end
	end
	return base
end

-- The class for an item. A vehicle is picked by floor area (its footprint,
-- width x length); anything else with a footprint by that area; the rest by
-- kind and price tier.
function BoxSize.ClassFor(spec: Spec): Class
	local fp = spec.footprint
	if BoxSize.IsVehicleKind(spec.kind) then
		local area = if fp then math.abs(fp.X * fp.Y) else 0
		return byArea(BoxSize.VehicleClasses, area)
	end
	if fp ~= nil then
		return byArea(BoxSize.Classes, math.abs(fp.X * fp.Y))
	end
	local baseId = BoxSize.KindBase[spec.kind] or BoxSize.DefaultClass
	local capId = BoxSize.KindCap[spec.kind] or baseId
	return shifted(baseId, steps(spec.price or 0), capId)
end

function BoxSize.SizeFor(spec: Spec): Vector3
	return BoxSize.ClassFor(spec).size
end

-- The distance one box needs along an axis: its own length plus the gap.
function BoxSize.Pitch(length: number): number
	return length + BoxSize.Gap
end

-- Every class in rank order, the shop classes then the vehicle classes.
function BoxSize.All(): { Class }
	local out: { Class } = {}
	for _, class in ipairs(BoxSize.Classes) do
		table.insert(out, class)
	end
	for _, class in ipairs(BoxSize.VehicleClasses) do
		table.insert(out, class)
	end
	return out
end

return BoxSize
