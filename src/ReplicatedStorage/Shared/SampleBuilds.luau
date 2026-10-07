--!strict
-- SampleBuilds: three finished buildings, as data, for testing and for show:
--   modern  a two-storey white and charcoal house, flat overhanging roof,
--           picture windows, a balcony and stairs
--   shop    a boxy single-storey shop: shop front, striped awning, roof edge,
--           a sign post
--   barn    a wooden house with a sloped roof, all older pieces
-- The owner loads one with `/sample <name>` (AdminService), free, at the
-- spot they face. Nothing here touches the world: it is the plan, a way to
-- stand it on a plot (Items), and the one rule that decides whether it fits
-- (Fit): every piece must pass PlotLogic.Check, in order, on the plot as it is
-- with the pieces before it already down.
--
-- Pieces are listed bottom up and hosts before what hangs in them (a door
-- after its wall). Coordinates are plot-local studs from the sample's own
-- centre, on the 2-stud grid; heights are on the 0.2 stack grid. A storey is
-- 6.4: a floor slab (0.4) and a wall (6). Fronts face -Z.

local PieceSize = require(script.Parent.PieceSize)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)

local SampleBuilds = {}

export type Piece = {
	id: string,
	x: number,
	z: number,
	rot: number?,
	y: number?,
	paint: string?, -- a KitPaint id
	len: number?, -- a resized wall, beam or trim
	lenX: number?, -- a resized floor
	lenZ: number?,
}

export type Sample = {
	id: string,
	displayName: string,
	wood: string, -- the wood the pieces are "filled" with
	note: string,
	reach: number, -- studs in front of the owner that its centre goes
	pieces: { Piece },
}

SampleBuilds.UidPrefix = "sample-" -- every placed piece's uid starts with this, so /sample clear can find them
SampleBuilds.Search = { 0, 4, -4, 8, -8, 12, -12, 16, -16, 24, -24 } -- offsets tried when the first spot is taken

local WHITE = "white"
local OFF = "offwhite"
local CHAR = "charcoal"
local BROWN = "darkbrown"
local DARKBROWN = "darkbrown"
local REDBROWN = "redbrown"

local B = 0.4 -- a floor slab
local UP = 6.4 -- the first storey's wall tops; the upstairs floor sits here
local UPWALL = 6.8 -- upstairs walls sit on the upstairs floor (6.4 + 0.4)
local ROOF = 12.8 -- upstairs wall tops

SampleBuilds.Samples = {
	modern = {
		id = "modern",
		displayName = "Modern house",
		wood = "birch",
		note = "Two storeys, 12x16: picture windows, a balcony, stairs inside, a flat overhanging roof",
		reach = 16,
		pieces = {
			-- Ground floor slab and walls: front (a glass door wall and a solid wall), back (all glass), sides
			{ id = "Floor", x = 0, z = 0, y = 0, lenX = 12, lenZ = 16, paint = OFF },
			{ id = "GlassDoorWall8", x = 2, z = -8, y = B, paint = CHAR },
			{ id = "Door", x = 2, z = -8, y = B, paint = CHAR },
			{ id = "Wall4", x = -4, z = -8, y = B, paint = WHITE },
			{ id = "PictureWall12", x = 0, z = 8, y = B, paint = CHAR },
			{ id = "Wall12", x = -6, z = -2, rot = 1, y = B, paint = WHITE },
			{ id = "Wall4", x = -6, z = 6, rot = 1, y = B, paint = WHITE },
			{ id = "PictureWall12", x = 6, z = -2, rot = 1, y = B, paint = CHAR },
			{ id = "Wall4", x = 6, z = 6, rot = 1, y = B, paint = WHITE },
			-- Stairs inside, rising toward the back, to the hole in the upstairs floor
			{ id = "Staircase8", x = 0, z = 0, y = B, paint = BROWN },
			-- Upstairs floor round the stairwell
			{ id = "Floor", x = 0, z = -6, y = UP, lenX = 12, lenZ = 4, paint = BROWN },
			{ id = "Floor", x = 0, z = 6, y = UP, lenX = 12, lenZ = 4, paint = BROWN },
			{ id = "Floor", x = -4, z = 0, y = UP, lenX = 4, lenZ = 8, paint = BROWN },
			{ id = "Floor", x = 4, z = 0, y = UP, lenX = 4, lenZ = 8, paint = BROWN },
			-- Upstairs walls: front with a glass door onto the balcony, glass back and right side
			{ id = "GlassDoorWall8", x = -2, z = -8, y = UPWALL, paint = CHAR },
			{ id = "Door", x = -2, z = -8, y = UPWALL, paint = CHAR },
			{ id = "Wall4", x = 4, z = -8, y = UPWALL, paint = BROWN },
			{ id = "PictureWall12", x = 0, z = 8, y = UPWALL, paint = CHAR },
			{ id = "Wall12", x = -6, z = -2, rot = 1, y = UPWALL, paint = BROWN },
			{ id = "Wall4", x = -6, z = 6, rot = 1, y = UPWALL, paint = BROWN },
			{ id = "PictureWall12", x = 6, z = -2, rot = 1, y = UPWALL, paint = CHAR },
			{ id = "Wall4", x = 6, z = 6, rot = 1, y = UPWALL, paint = BROWN },
			-- The balcony hangs off the upstairs front, in front of the glass door
			{ id = "Balcony8", x = -2, z = -10, y = UP, paint = WHITE },
			-- Flat roof: two wide slabs side by side
			{ id = "FlatRoofOver12x8", x = 0, z = -4, y = ROOF, paint = WHITE },
			{ id = "FlatRoofOver12x8", x = 0, z = 4, y = ROOF, paint = WHITE },
		},
	},
	shop = {
		id = "shop",
		displayName = "Corner shop",
		wood = "oak",
		note = "One storey, 12x8: a shop front with a door, a striped awning, a roof edge and a sign post",
		reach = 12,
		pieces = {
			{ id = "Floor", x = 0, z = 0, y = 0, lenX = 12, lenZ = 8, paint = CHAR },
			{ id = "ShopFront12", x = 0, z = -4, y = B, paint = CHAR },
			{ id = "Door", x = 0, z = -4, y = B, paint = BROWN },
			{ id = "Wall12", x = 0, z = 4, y = B, paint = WHITE },
			{ id = "Wall", x = -6, z = 0, rot = 1, y = B, paint = WHITE },
			{ id = "Wall", x = 6, z = 0, rot = 1, y = B, paint = WHITE },
			{ id = "FlatRoofOver12x8", x = 0, z = 0, y = UP, paint = BROWN },
			{ id = "Awning8", x = 0, z = -6, y = 5.4 },
			{ id = "Fascia8", x = 0, z = -6, rot = 2, y = UP + B, len = 16, paint = WHITE },
			{ id = "WoodSign", x = 10, z = -8 },
		},
	},
	barn = {
		id = "barn",
		displayName = "Barn house",
		wood = "pine",
		note = "One storey, 16x8: a door, a window and a sloped roof with a ridge; every piece is an older one",
		reach = 12,
		pieces = {
			{ id = "Floor", x = 0, z = 2, y = 0, lenX = 16, lenZ = 8 },
			{ id = "DoorWall8", x = -4, z = -2, y = B },
			{ id = "Door", x = -4, z = -2, y = B, paint = REDBROWN },
			{ id = "WindowWall8", x = 4, z = -2, y = B },
			{ id = "Window", x = 4, z = -2, y = B },
			{ id = "Wall", x = -4, z = 6, y = B },
			{ id = "Wall", x = 4, z = 6, y = B },
			{ id = "Wall", x = -8, z = 2, rot = 1, y = B },
			{ id = "Wall", x = 8, z = 2, rot = 1, y = B },
			{ id = "SlopedRoof8", x = -4, z = 0, y = UP, rot = 0, paint = REDBROWN },
			{ id = "SlopedRoof8", x = 4, z = 0, y = UP, rot = 0, paint = REDBROWN },
			{ id = "SlopedRoof8", x = -4, z = 4, y = UP, rot = 2, paint = REDBROWN },
			{ id = "SlopedRoof8", x = 4, z = 4, y = UP, rot = 2, paint = REDBROWN },
			{ id = "RoofRidge8", x = -4, z = 2, y = UP, paint = DARKBROWN },
			{ id = "RoofRidge8", x = 4, z = 2, y = UP, paint = DARKBROWN },
		},
	},
} :: { [string]: Sample }

SampleBuilds.List = { "modern", "shop", "barn" } :: { string }

function SampleBuilds.Get(name: unknown): Sample?
	if type(name) ~= "string" then
		return nil
	end
	return SampleBuilds.Samples[string.lower(name)]
end

-- Quarter turns about Y, the way PlotLogic turns a piece.
local function turn(x: number, z: number, rot: number): (number, number)
	if rot == 1 then
		return z, -x
	elseif rot == 2 then
		return -x, -z
	elseif rot == 3 then
		return -z, x
	end
	return x, z
end

-- The quarter turn that points the sample's front (-Z) back at someone who
-- looks along (dx, dz): the house faces the person who aimed it.
function SampleBuilds.FacingRot(dx: number, dz: number): number
	local best, bestDot = 0, -math.huge
	for rot = 0, 3 do
		local fx, fz = turn(0, -1, rot)
		local dot = fx * -dx + fz * -dz
		if dot > bestDot + 1e-9 then
			best, bestDot = rot, dot
		end
	end
	return best
end

-- The sample's pieces as placed items, turned by `rot` about its centre and
-- moved so the centre is at (ox, oz) (snapped to the grid). Built and free:
-- no fill, `paid` 0 (so a sample piece sells for nothing), the sample's wood.
-- `uid(i)` makes each piece's id.
function SampleBuilds.Items(
	sample: Sample,
	rot: number,
	ox: number,
	oz: number,
	uid: (number) -> string
): { PlotLogic.Placed }
	local out: { PlotLogic.Placed } = {}
	local cx, cz = PlotLogic.Snap(ox), PlotLogic.Snap(oz)
	local r = rot % 4
	for i, piece in ipairs(sample.pieces) do
		local bp = PlotData.Blueprint(piece.id)
		local x, z = turn(piece.x, piece.z, r)
		local item: PlotLogic.Placed = {
			uid = uid(i),
			blueprintId = piece.id,
			x = cx + x,
			z = cz + z,
			rot = ((piece.rot or 0) + r) % 4,
			y = if piece.y ~= nil and piece.y ~= 0 then piece.y else nil,
			len = piece.len,
			lenX = piece.lenX,
			lenZ = piece.lenZ,
		}
		if bp and bp.kit == true then
			item.wood = sample.wood
			item.paid = 0
			item.paint = piece.paint
		end
		table.insert(out, item)
	end
	return out
end

-- Whether `items` all fit on a plot of `tier` (with its bought `squares`) that
-- already holds `placed`: each piece must pass PlotLogic.Check, in order, with
-- the pieces before it down. (true, nil) or (false, why, which piece).
function SampleBuilds.Fits(
	items: { PlotLogic.Placed },
	tier: number,
	placed: { PlotLogic.Placed },
	squares: { string }?
): (boolean, string?, string?)
	local world: { PlotLogic.Placed } = table.clone(placed)
	for _, item in ipairs(items) do
		local bp = PlotLogic.Blueprint(item.blueprintId)
		if not bp then
			return false, "unknown piece", item.blueprintId
		end
		local shaped = PieceSize.Shape(bp, item)
		local ok, why = PlotLogic.Check(shaped, item.x, item.z, item.rot, tier, world, nil, item.y or 0, squares)
		if not ok then
			return false, why or "doesn't fit", item.blueprintId
		end
		table.insert(world, item)
	end
	return true, nil, nil
end

-- The first spot near (ox, oz) where the whole sample fits: the aimed spot,
-- then steps to either side and back. Returns the items, or nil and why.
function SampleBuilds.Find(
	sample: Sample,
	rot: number,
	ox: number,
	oz: number,
	tier: number,
	placed: { PlotLogic.Placed },
	squares: { string }?,
	uid: (number) -> string
): ({ PlotLogic.Placed }?, string?)
	local lastWhy: string? = nil
	for _, dz in ipairs(SampleBuilds.Search) do
		for _, dx in ipairs({ 0, 8, -8 }) do
			local items = SampleBuilds.Items(sample, rot, ox + dx, oz + dz, uid)
			local ok, why = SampleBuilds.Fits(items, tier, placed, squares)
			if ok then
				return items, nil
			end
			lastWhy = lastWhy or why
		end
	end
	return nil, lastWhy
end

-- How many kit pieces and other pieces a sample adds, for the plot's caps.
function SampleBuilds.Counts(sample: Sample): (number, number)
	local kit, other = 0, 0
	for _, piece in ipairs(sample.pieces) do
		local bp = PlotData.Blueprint(piece.id)
		if bp and bp.kit == true then
			kit += 1
		else
			other += 1
		end
	end
	return kit, other
end

function SampleBuilds.IsSampleUid(uid: unknown): boolean
	return type(uid) == "string" and string.sub(uid, 1, #SampleBuilds.UidPrefix) == SampleBuilds.UidPrefix
end

return SampleBuilds
