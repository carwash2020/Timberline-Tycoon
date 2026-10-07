--!strict
-- ModernKit: the glass, roof, stair and balcony pieces that let a plot hold
-- a modern house or a boxy shop (white and dark walls, big windows, flat
-- roofs that overhang, balconies, stairs). PlotData appends this list to its
-- blueprints, so PlotLogic places them, PlotService charges the kit fee for
-- them, FillLogic fills them with planks and ProfileSchema saves them like
-- any other kit piece. BUILD_SYSTEM.md and PHASE2_NOTES.md say how they are
-- bought and what to check in Studio.
--
-- Sizes follow the older kit: lengths in multiples of 4, walls 6 or 10
-- studs tall and 1 thick, floors 0.4 thick, heights on the 0.2 stack grid.
-- A storey is StoreyHeight: a floor slab and a wall on top of it (0.4 + 6).
--
-- Glass:
--   * Six pieces (the picture window walls, the glass door wall, the shop
--     front) are sold by ONE General Store plan, "Picture Window Wall"
--     (`family`): using it teaches all six. The General Store's shelf has
--     one free slot; this keeps it. Each costs the kit fee on every place
--     and takes planks like any wall, but needs fewer wood units than a solid
--     wall of its size (the glass is free; the frame and the riser are wood).
--   * A pane is a Glass box: GlassMaterial, pale blue-grey, translucent
--     (BlueprintModels makes it 0.4 transparent; the ghost 0.45) and it
--     COLLIDES like any wall part. A pane is 0.25 thick in a 1.0 frame, so
--     no face of the pane shares a plane with a face of the frame.
--   * The frame and riser are Wood role, so the planks you fill with and the
--     paint you pick change them. The pane never takes either.
-- Roofs, trim, stairs and balcony are plain wood pieces: starter plans.

local V2 = Vector2.new
local V3 = Vector3.new

local ModernKit = {}

ModernKit.StoreyHeight = 6.4 -- floor slab (0.4) plus a wall (6): what one storey adds
ModernKit.WallHeight = 6
ModernKit.TallWallHeight = 10
ModernKit.StairSteps = 8
ModernKit.StairRise = 0.8 -- per step; a Humanoid steps up 1 stud easily, so no tread is a wall
ModernKit.StairRun = 1 -- per step: a boot's length, so a foot always lands on a tread
ModernKit.MaxStepRise = 1 -- the most one tread may rise (tests hold the stairs to it)
ModernKit.MinStepRun = 1
-- The default Humanoid.MaxSlopeAngle is 89 degrees; a stair this steep is
-- not a slope the character has to climb, it is steps. Comfortable pitch
-- for stairs is under 45 degrees (tests).
ModernKit.MaxStairPitch = 45
ModernKit.RoofOverhang = 1.5 -- a modern roof's overhang past its footprint, each side
ModernKit.GlassColor = "#BCD3DF"
ModernKit.GlassStoreKey = "PictureWall8"

local WOOD = "#654321"
local WOOD_LIGHT = "#825A32"
local EDGE = "#3A3D42" -- the thin darker edge of a flat roof

local function frame(size: Vector3, offset: Vector3): { [string]: any }
	return { size = size, offset = offset, color = WOOD, material = "Wood" }
end

-- A post at the very end of a wall. PlotLogic trims every edge piece's boxes
-- by half a stud a side to let two walls meet at a corner, but a post only
-- half a stud wide cannot be trimmed back from the end, so the overlap test
-- skips it (`look`). Its solid is still there to see and to stop you.
local function endPost(size: Vector3, offset: Vector3): { [string]: any }
	local box = frame(size, offset)
	box.look = true
	return box
end

local function glass(size: Vector3, offset: Vector3): { [string]: any }
	return { size = size, offset = offset, color = ModernKit.GlassColor, material = "Glass", role = "Glass" }
end

local function planks(size: Vector3, offset: Vector3, color: string?): { [string]: any }
	return { size = size, offset = offset, color = color or WOOD, material = "WoodPlanks" }
end

local function piece(def: { [string]: any }): { [string]: any }
	def.category = def.category or "Buildings"
	def.tier = 1
	def.kit = true
	def.priceCash = def.priceCash or def.woodUnits * 10 -- legacy field: a kit piece pays woodUnits x KitCashPerUnit
	return def
end

-- A wall of glass: a slim frame (posts, a sill rail and a head rail) round
-- panes, with a mullion down the middle of a 12. The pane overlaps the frame
-- by 0.05 on each side so no edge is bare.
local function pictureWall(width: number, height: number): { { [string]: any } }
	local inner = width - 1 -- between the two posts
	local boxes = {
		endPost(V3(0.5, height, 1), V3(-(width / 2 - 0.25), height / 2, 0)),
		endPost(V3(0.5, height, 1), V3(width / 2 - 0.25, height / 2, 0)),
		frame(V3(inner, 0.6, 1), V3(0, 0.3, 0)),
		frame(V3(inner, 0.6, 1), V3(0, height - 0.3, 0)),
	}
	local paneHigh = height - 1.2 + 0.1
	if width >= 12 then
		table.insert(boxes, frame(V3(0.4, height - 1.2, 1), V3(0, height / 2, 0)))
		local pane = (inner - 0.4) / 2 + 0.1
		local at = 0.2 + (inner - 0.4) / 4
		table.insert(boxes, glass(V3(pane, paneHigh, 0.25), V3(-at, height / 2, 0)))
		table.insert(boxes, glass(V3(pane, paneHigh, 0.25), V3(at, height / 2, 0)))
	else
		table.insert(boxes, glass(V3(inner + 0.1, paneHigh, 0.25), V3(0, height / 2, 0)))
	end
	return boxes
end

-- A flat roof slab that overhangs on every side: a thin darker slab (role
-- "Edge", so paint leaves it dark) under the top slab, so the edge reads as a
-- dark line whatever colour the roof is painted. PlotLogic ignores the
-- overhang (`overhang`) when it checks for overlap.
local function overhangRoof(w: number, d: number): { { [string]: any } }
	local over = ModernKit.RoofOverhang * 2
	return {
		{
			size = V3(w + over, 0.2, d + over),
			offset = V3(0, 0.1, 0),
			color = EDGE,
			material = "Concrete",
			role = "Edge", -- the dark line: paint does not cover it
		},
		{
			size = V3(w + over - 0.4, 0.2, d + over - 0.4),
			offset = V3(0, 0.3, 0),
			color = WOOD,
			material = "Wood",
		},
	}
end

-- Straight stairs: one block per tread, each solid down to the floor, so the
-- collision is real steps (no wedge to slide down) and the overlap test sees
-- the true shape. Low end at -Z, the top tread at +Z, like the older Stairs.
local function staircase(): { { [string]: any } }
	local boxes = {}
	local run, rise, steps = ModernKit.StairRun, ModernKit.StairRise, ModernKit.StairSteps
	for i = 1, steps do
		table.insert(
			boxes,
			planks(V3(4, rise * i, run), V3(0, rise * i / 2, -steps * run / 2 + (i - 0.5) * run), WOOD_LIGHT)
		)
	end
	return boxes
end

ModernKit.Pieces = {
	-- Glass (sold by the General Store as one plan, `family`) -----------------
	piece({
		id = "PictureWall8",
		displayName = "Picture Window Wall",
		woodUnits = 5,
		edge = true,
		unlock = true, -- the General Store's plan: using it teaches the whole `family`
		storePrice = 500,
		family = {
			"PictureWall8",
			"PictureWall12",
			"TallPictureWall8",
			"TallPictureWall12",
			"GlassDoorWall8",
			"ShopFront12",
		},
		footprint = V2(8, 1),
		boxes = pictureWall(8, 6),
		note = "A wall that is mostly glass, 8 wide. Glass shows through but stops you",
	}),
	piece({
		id = "PictureWall12",
		displayName = "Long Picture Window",
		woodUnits = 8,
		edge = true,
		gated = true,
		footprint = V2(12, 1),
		boxes = pictureWall(12, 6),
		note = "A glass wall, 12 wide, with a mullion in the middle",
	}),
	piece({
		id = "TallPictureWall8",
		displayName = "Tall Picture Window",
		woodUnits = 8,
		edge = true,
		gated = true,
		footprint = V2(8, 1),
		boxes = pictureWall(8, 10),
		note = "A 10-stud glass wall, 8 wide",
	}),
	piece({
		id = "TallPictureWall12",
		displayName = "Tall Long Picture Window",
		woodUnits = 12,
		edge = true,
		gated = true,
		footprint = V2(12, 1),
		boxes = pictureWall(12, 10),
		note = "A 10-stud glass wall, 12 wide",
	}),
	piece({
		id = "GlassDoorWall8",
		displayName = "Glass Door Wall",
		woodUnits = 5,
		edge = true,
		gated = true,
		footprint = V2(8, 1),
		slot = { size = V3(4, 6, 1), offset = V3(0, 3, 0) },
		boxes = {
			-- Two glass side lights either side of a 4x6 doorway.
			endPost(V3(0.4, 6, 1), V3(-3.8, 3, 0)),
			frame(V3(0.4, 6, 1), V3(-2.2, 3, 0)),
			frame(V3(0.4, 6, 1), V3(2.2, 3, 0)),
			endPost(V3(0.4, 6, 1), V3(3.8, 3, 0)),
			frame(V3(1.2, 0.6, 1), V3(-3, 0.3, 0)),
			frame(V3(1.2, 0.6, 1), V3(3, 0.3, 0)),
			frame(V3(1.2, 0.6, 1), V3(-3, 5.7, 0)),
			frame(V3(1.2, 0.6, 1), V3(3, 5.7, 0)),
			glass(V3(1.3, 4.9, 0.25), V3(-3, 3, 0)),
			glass(V3(1.3, 4.9, 0.25), V3(3, 3, 0)),
		},
		note = "A glass wall with a 4x6 doorway. Hang a Door in it",
	}),
	piece({
		id = "ShopFront12",
		displayName = "Shop Front",
		woodUnits = 9,
		edge = true,
		gated = true,
		footprint = V2(12, 1),
		slot = { size = V3(4, 6, 1), offset = V3(0, 3, 0) },
		boxes = {
			-- A stall riser (solid, 1.4 high), a big pane over it, a head rail,
			-- and a 4x6 doorway in the middle.
			endPost(V3(0.5, 6, 1), V3(-5.75, 3, 0)),
			endPost(V3(0.5, 6, 1), V3(5.75, 3, 0)),
			frame(V3(0.4, 6, 1), V3(-2.2, 3, 0)),
			frame(V3(0.4, 6, 1), V3(2.2, 3, 0)),
			planks(V3(3.1, 1.4, 1), V3(-3.95, 0.7, 0)),
			planks(V3(3.1, 1.4, 1), V3(3.95, 0.7, 0)),
			frame(V3(3.1, 0.6, 1), V3(-3.95, 5.7, 0)),
			frame(V3(3.1, 0.6, 1), V3(3.95, 5.7, 0)),
			glass(V3(3.2, 4.1, 0.25), V3(-3.95, 3.4, 0)),
			glass(V3(3.2, 4.1, 0.25), V3(3.95, 3.4, 0)),
		},
		note = "A wide glass front, 12 long, with a doorway and a solid stall riser",
	}),
	-- Roofs and trim -------------------------------------------------------
	piece({
		id = "FlatRoofOver8",
		displayName = "Overhang Roof",
		woodUnits = 14,
		roof = true,
		overhang = ModernKit.RoofOverhang,
		footprint = V2(8, 8),
		boxes = overhangRoof(8, 8),
		note = "A flat 8x8 roof that overhangs 1.5 studs each side, with a dark edge",
	}),
	piece({
		id = "FlatRoofOver12x8",
		displayName = "Wide Overhang Roof",
		woodUnits = 20,
		roof = true,
		overhang = ModernKit.RoofOverhang,
		footprint = V2(12, 8),
		boxes = overhangRoof(12, 8),
		note = "A flat 12x8 roof that overhangs 1.5 studs each side",
	}),
	piece({
		id = "FlatRoofOver12",
		displayName = "Big Overhang Roof",
		woodUnits = 28,
		roof = true,
		overhang = ModernKit.RoofOverhang,
		footprint = V2(12, 12),
		boxes = overhangRoof(12, 12),
		note = "A flat 12x12 roof that overhangs 1.5 studs each side",
	}),
	piece({
		id = "Fascia8",
		displayName = "Roof Edge",
		woodUnits = 2,
		edge = true,
		footprint = V2(8, 2),
		-- Hung on a roof's edge: its centre line sits 0.5 stud inside the piece's
		-- own centre, so the band lands on a slab edge that is 1.5 out from
		-- the roof's footprint (the footprint's half-width is even, so the
		-- piece stays on the 2-stud grid).
		boxes = { { size = V3(8, 1.4, 0.4), offset = V3(0, 0.7, -0.5), color = WOOD, material = "Wood" } },
		note = "A trim band for a roof's edge. Resizes. Face it in, toward the roof",
	}),
	piece({
		id = "Awning8",
		displayName = "Awning",
		woodUnits = 3,
		footprint = V2(8, 3),
		boxes = {
			{
				size = V3(2, 1, 3),
				offset = V3(-3, 0.5, 0),
				color = "#B23A26",
				material = "Fabric",
				shape = "Wedge",
				role = "Trim",
			},
			{
				size = V3(2, 1, 3),
				offset = V3(-1, 0.5, 0),
				color = "#EDE8DC",
				material = "Fabric",
				shape = "Wedge",
				role = "Trim",
			},
			{
				size = V3(2, 1, 3),
				offset = V3(1, 0.5, 0),
				color = "#B23A26",
				material = "Fabric",
				shape = "Wedge",
				role = "Trim",
			},
			{
				size = V3(2, 1, 3),
				offset = V3(3, 0.5, 0),
				color = "#EDE8DC",
				material = "Fabric",
				shape = "Wedge",
				role = "Trim",
			},
		},
		note = "A striped canopy for a shop front. High at the wall, low at the edge",
	}),
	-- Stairs and balcony -----------------------------------------------------
	piece({
		id = "Staircase8",
		displayName = "Storey Stairs",
		woodUnits = 22,
		footprint = V2(4, 8),
		boxes = staircase(),
		note = "Eight steps up one storey (6.4 studs), 8 long. The top is at the back",
	}),
	piece({
		id = "Balcony8",
		displayName = "Balcony",
		woodUnits = 10,
		footprint = V2(8, 4),
		boxes = {
			planks(V3(8, 0.4, 4), V3(0, 0.2, 0), WOOD_LIGHT),
			planks(V3(8, 3, 0.3), V3(0, 1.9, -1.85)),
			-- The end rails stop short of the house wall (the back, +Z), so they
			-- never poke into a wall whose face is half a stud past the slab.
			planks(V3(0.3, 3, 3.2), V3(-3.85, 1.9, -0.2)),
			planks(V3(0.3, 3, 3.2), V3(3.85, 1.9, -0.2)),
		},
		note = "An 8x4 balcony slab with a railing on the front and both ends. The open side is the back",
	}),
}

ModernKit.ById = {} :: { [string]: { [string]: any } }
for _, def in ipairs(ModernKit.Pieces) do
	ModernKit.ById[def.id] = def
end

return ModernKit
