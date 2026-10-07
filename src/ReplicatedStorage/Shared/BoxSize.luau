--!strict
-- BoxSize: how big a shop box is. Pure.
--
-- THE RULE (Connor, 7 October 2026: "keep the box size accurate to the item
-- inside"): a box is the item's real bounding box plus a fixed margin. The
-- item is measured from the model the box shows (Art/ItemModel.Extent), never
-- guessed from a size class or a price.
--
--   inner  = extent * scale              the item as shown in the window
--   width  = inner.X + 2 * Margin        (x), and the same for depth (z)
--   height = inner.Y + Margin + Floor    Floor under the item, Margin above it
--   box    = max(Min, those)             so the name strip stays readable
--
-- `scale` is 1 for anything that fits. An item bigger than the box may be
-- (a sawmill is 26 studs long, a logging rig 47) is shrunk uniformly, never
-- squashed, until it fits inside Max (a shelf box) or VehicleMax (a vehicle,
-- the biggest thing in a store). So an axe is long and thin, a truck is long
-- and wide, a sawmill keeps its real footprint's shape, the Sky Bin is small
-- and tall, and nothing is a different shape from what is inside it.
--
-- ShelfLayout spaces boxes by the width and depth they have (Gap between
-- them), so a bigger box never overlaps its neighbours; the specs measure
-- every shop item against this rule.
--
-- A box with no model of its own (the Robux boxes, an unknown id) uses the
-- fixed stock sizes below.

local BoxSize = {}

export type Class = {
	id: string,
	rank: number,
	size: Vector3, -- width x height x depth; the front faces -Z
}

export type Fit = {
	size: Vector3, -- the box
	scale: number, -- the item's scale in the window (1 = real size)
	inner: Vector3, -- the item as shown: extent * scale
}

-- Clear studs between neighbouring boxes on a shelf, and between a box and
-- the edge of the shelf. Connor (7 October 2026, on the window boxes: "space
-- them out more"): at least 1.5 studs between boxes side by side (Gap) and
-- about 2.5 between rows (RowGap), so a box with its glass window, accent
-- plinth (a quarter stud bigger all round) and name strip reads on its own and
-- a player can aim at one without the cursor landing on the next.
BoxSize.Gap = 1.5
BoxSize.RowGap = 2.5
BoxSize.EdgeGap = 0.6

-- Margin round the item: each side (x, z) and over the top, and the floor
-- the item stands on.
BoxSize.Margin = 0.6
BoxSize.Floor = 0.3

-- Never smaller than this (width x height x depth), so the name strip reads.
BoxSize.Min = Vector3.new(2.4, 1.9, 1.7)

-- Never bigger than this on a shelf (width x height x depth). A shelf row
-- is 7.2 to 7.5 studs wide, so two boxes of 3.1 stand side by side; a bigger
-- thing is shrunk to a tile of its shape (a sawmill is 12 to 26 studs long,
-- so a shelf box can only ever be a miniature of it). The carry rules (a
-- person holding a box, an aisle at least 7.6 wide) and the truck bed were
-- all set for boxes about this size.
BoxSize.Max = Vector3.new(3.1, 4.6, 3.6)

-- Axes are long and thin: the same shelf may take them unscaled, one to a
-- row (an axe is 3.3 to 4 studs long and under half a stud thick).
BoxSize.KindMax = {
	Axe = Vector3.new(5.2, 4.6, 2.6),
	Sawmill = Vector3.new(6.4, 4.8, 4.8),
	Machine = Vector3.new(5.2, 4.6, 4.4),
} :: { [string]: Vector3 }

-- A vehicle's box (the dealership's plinths have room for it).
BoxSize.VehicleMax = Vector3.new(15.5, 7.4, 8.4)

-- Fixed sizes for a box with no model of its own.
BoxSize.Classes = {
	{ id = "XS", rank = 1, size = Vector3.new(2.4, 2, 2) },
	{ id = "S", rank = 2, size = Vector3.new(2.8, 2.2, 2.2) },
	{ id = "M", rank = 3, size = Vector3.new(3.6, 2.9, 2.9) },
} :: { Class }

-- The class a box with no model falls back to.
BoxSize.DefaultClass = "S"

local byId: { [string]: Class } = {}
for _, class in ipairs(BoxSize.Classes) do
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

-- The biggest box allowed for a kind of item.
function BoxSize.MaxFor(kind: string): Vector3
	if BoxSize.IsVehicleKind(kind) then
		return BoxSize.VehicleMax
	end
	return BoxSize.KindMax[kind] or BoxSize.Max
end

-- The box for an item of bounding box `extent` (studs, display orientation:
-- x across the front, y up, z deep) of kind `kind`. `groupScale` (ItemBox)
-- shows a whole family at one scale. See the header.
function BoxSize.Fit(extent: Vector3, kind: string, groupScale: number?): Fit
	local max = BoxSize.MaxFor(kind)
	local roomX = max.X - 2 * BoxSize.Margin
	local roomY = max.Y - BoxSize.Margin - BoxSize.Floor
	local roomZ = max.Z - 2 * BoxSize.Margin
	local scale = 1
	if extent.X > 0 then
		scale = math.min(scale, roomX / extent.X)
	end
	if extent.Y > 0 then
		scale = math.min(scale, roomY / extent.Y)
	end
	if extent.Z > 0 then
		scale = math.min(scale, roomZ / extent.Z)
	end
	if groupScale ~= nil then
		scale = math.min(scale, groupScale)
	end
	local inner = extent * scale
	local min = BoxSize.Min
	local size = Vector3.new(
		math.max(min.X, inner.X + 2 * BoxSize.Margin),
		math.max(min.Y, inner.Y + BoxSize.Margin + BoxSize.Floor),
		math.max(min.Z, inner.Z + 2 * BoxSize.Margin)
	)
	return { size = size, scale = scale, inner = inner }
end

-- Where the item's middle goes in its box, from the box's middle: centred
-- across and deep, standing on the floor.
function BoxSize.ItemOffset(box: Vector3, inner: Vector3): Vector3
	local floorY = -box.Y / 2 + BoxSize.Floor
	return Vector3.new(0, floorY + inner.Y / 2, 0)
end

-- The distance one box needs along z (front to back): its own length plus the
-- row gap. (Boxes stacked along z are rows, however they are shown.)
function BoxSize.Pitch(length: number): number
	return length + BoxSize.RowGap
end

-- Every fixed class in rank order.
function BoxSize.All(): { Class }
	local out: { Class } = {}
	for _, class in ipairs(BoxSize.Classes) do
		table.insert(out, class)
	end
	return out
end

return BoxSize
