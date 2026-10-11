--!strict
-- Kit pieces that did not exist before the building kit. The six originals
-- (Wall, Floor, Door, Window, Stairs, Fence) stay in PlotData so their ids
-- and legacy priceCash do not move. Fee is woodUnits × PlotData.KitCashPerUnit.
-- Lengths are multiples of 4. Roofs are drawn 0.5 studs past the footprint;
-- PlotLogic ignores that overhang.

local V2 = Vector2.new
local V3 = Vector3.new

local WOOD = "#654321"
local WOOD_LIGHT = "#825A32"
-- Lane F (V1 building). Game Art Director palette is still PENDING; these
-- are the brief's defaults (Awaiting Connor).
local SANDSTONE = "#C8643C"
local COPPER = "#B87333"
-- Paid in sandstone slabs or ingots, not planks: PlotFill takes them from the
-- loose parts dropped on the ghost (BuildCost has the numbers).

local function piece(def: { [string]: any }): { [string]: any }
	def.category = def.category or "Buildings"
	def.tier = 1
	def.kit = true
	return def
end

return {
	piece({
		id = "Wall4",
		displayName = "Short Wall",
		priceCash = 16,
		woodUnits = 4,
		edge = true,
		footprint = V2(4, 1),
		boxes = { { size = V3(4, 6, 1), offset = V3(0, 3, 0), color = WOOD, material = "WoodPlanks" } },
		note = "A straight wall, 4 studs",
	}),
	piece({
		id = "Wall12",
		displayName = "Long Wall",
		priceCash = 48,
		woodUnits = 12,
		edge = true,
		footprint = V2(12, 1),
		boxes = { { size = V3(12, 6, 1), offset = V3(0, 3, 0), color = WOOD, material = "WoodPlanks" } },
		note = "A straight wall, 12 studs",
	}),
	piece({
		id = "TallWall4",
		displayName = "Tall Short Wall",
		priceCash = 28,
		woodUnits = 7,
		edge = true,
		footprint = V2(4, 1),
		boxes = { { size = V3(4, 10, 1), offset = V3(0, 5, 0), color = WOOD, material = "WoodPlanks" } },
		note = "A 10-stud wall, 4 wide",
	}),
	piece({
		id = "TallWall8",
		displayName = "Tall Wall",
		priceCash = 56,
		woodUnits = 14,
		edge = true,
		footprint = V2(8, 1),
		boxes = { { size = V3(8, 10, 1), offset = V3(0, 5, 0), color = WOOD, material = "WoodPlanks" } },
		note = "A 10-stud wall, 8 wide",
	}),
	piece({
		id = "HalfWall8",
		displayName = "Half Wall",
		priceCash = 16,
		woodUnits = 4,
		edge = true,
		footprint = V2(8, 1),
		boxes = { { size = V3(8, 3, 1), offset = V3(0, 1.5, 0), color = WOOD, material = "WoodPlanks" } },
		note = "A 3-stud wall",
	}),
	piece({
		id = "DoorWall8",
		displayName = "Door Wall",
		priceCash = 24,
		woodUnits = 6,
		edge = true,
		footprint = V2(8, 1),
		slot = { size = V3(4, 6, 1), offset = V3(0, 3, 0) },
		boxes = {
			{ size = V3(2, 6, 1), offset = V3(-3, 3, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(2, 6, 1), offset = V3(3, 3, 0), color = WOOD, material = "WoodPlanks" },
		},
		note = "A wall with a 4×6 doorway",
	}),
	piece({
		id = "WindowWall8",
		displayName = "Window Wall",
		priceCash = 24,
		woodUnits = 6,
		edge = true,
		footprint = V2(8, 1),
		slot = { size = V3(4, 3, 1), offset = V3(0, 3.5, 0) },
		boxes = {
			{ size = V3(2, 6, 1), offset = V3(-3, 3, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(2, 6, 1), offset = V3(3, 3, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(4, 2, 1), offset = V3(0, 1, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(4, 1, 1), offset = V3(0, 5.5, 0), color = WOOD, material = "WoodPlanks" },
		},
		note = "A wall with a 4×3 window, sill at 2",
	}),
	piece({
		id = "Floor4",
		displayName = "Small Floor",
		priceCash = 12,
		woodUnits = 3,
		footprint = V2(4, 4),
		boxes = { { size = V3(4, 0.4, 4), offset = V3(0, 0.2, 0), color = WOOD_LIGHT, material = "WoodPlanks" } },
		note = "A 4×4 floor",
	}),
	piece({
		id = "Foundation8",
		displayName = "Foundation",
		priceCash = 80,
		woodUnits = 20,
		footprint = V2(8, 8),
		boxes = { { size = V3(8, 2, 8), offset = V3(0, 1, 0), color = "#8C8680", material = "Slate", role = "Trim" } },
		note = "An 8×8 base, 2 studs tall",
	}),
	piece({
		id = "Ramp8",
		displayName = "Ramp",
		priceCash = 32,
		woodUnits = 8,
		footprint = V2(4, 8),
		boxes = {
			{ size = V3(4, 2, 8), offset = V3(0, 1, 0), color = WOOD, material = "WoodPlanks", shape = "Wedge" },
		},
		note = "Rises 2 studs over 8, toward the back",
	}),
	piece({
		id = "FlatRoof8",
		displayName = "Flat Roof",
		priceCash = 48,
		woodUnits = 12,
		roof = true,
		footprint = V2(8, 8),
		boxes = { { size = V3(9, 0.4, 9), offset = V3(0, 0.2, 0), color = WOOD, material = "Wood" } },
		note = "An 8×8 roof with a short overhang",
	}),
	piece({
		id = "SlopedRoof8",
		displayName = "Sloped Roof",
		priceCash = 40,
		woodUnits = 10,
		roof = true,
		footprint = V2(8, 4),
		boxes = {
			{ size = V3(9, 3, 5), offset = V3(0, 1.5, 0), color = WOOD, material = "Wood", shape = "Wedge" },
		},
		note = "8 along the eave, 4 deep, rises 3 toward the back",
	}),
	piece({
		id = "RoofCorner",
		displayName = "Roof Corner",
		priceCash = 20,
		woodUnits = 5,
		roof = true,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(5, 3, 5), offset = V3(0, 1.5, 0), color = WOOD, material = "Wood", shape = "Wedge" },
		},
		note = "A hip corner, 4×4, rises 3",
	}),
	piece({
		id = "RoofRidge8",
		displayName = "Roof Ridge",
		priceCash = 24,
		woodUnits = 6,
		roof = true,
		footprint = V2(8, 1),
		boxes = { { size = V3(9, 0.8, 2), offset = V3(0, 3.4, 0), color = WOOD, material = "Wood" } },
		note = "The cap where two slopes meet. Place it on the roof base; the mesh pivot is 2.475 up",
	}),
	piece({
		id = "FenceGate4",
		displayName = "Fence Gate",
		category = "Decor",
		priceCash = 12,
		woodUnits = 3,
		edge = true,
		opens = true,
		hinge = -1.6,
		footprint = V2(4, 1),
		boxes = {
			{ size = V3(0.4, 3, 0.6), offset = V3(-1.8, 1.5, 0), color = WOOD, material = "Wood" },
			{ size = V3(0.4, 3, 0.6), offset = V3(1.8, 1.5, 0), color = WOOD, material = "Wood" },
			{
				size = V3(3.2, 3, 0.4),
				offset = V3(0, 1.5, 0),
				color = WOOD_LIGHT,
				material = "Wood",
				role = "Door",
				leaf = true,
			},
		},
		note = "A gate that swings open",
	}),
	piece({
		id = "Post",
		displayName = "Post",
		priceCash = 4,
		woodUnits = 1,
		footprint = V2(1, 1),
		boxes = { { size = V3(1, 6, 1), offset = V3(0, 3, 0), color = WOOD, material = "Wood" } },
		note = "A 6-stud post",
	}),
	piece({
		id = "Beam8",
		displayName = "Beam",
		priceCash = 8,
		woodUnits = 2,
		edge = true,
		footprint = V2(8, 1),
		boxes = { { size = V3(8, 1, 1), offset = V3(0, 0.5, 0), color = WOOD, material = "Wood" } },
		note = "An 8-stud beam",
	}),
	piece({
		id = "Railing8",
		displayName = "Railing",
		priceCash = 12,
		woodUnits = 3,
		edge = true,
		footprint = V2(8, 1),
		boxes = { { size = V3(8, 3, 1), offset = V3(0, 1.5, 0), color = WOOD, material = "WoodPlanks" } },
		note = "An 8-stud railing",
	}),
	-- Lane F V1 pieces. Sizes match the uploaded meshes' bounding boxes
	-- (assets/models/backlog/furniture/<Name>/stats.json) so job 17 can
	-- swap the mesh in. woodUnits 0: BuildCost.Of reads slabUnits/ingots.
	piece({
		id = "CopperTrim4",
		displayName = "Copper Trim",
		category = "Decor",
		priceCash = 4, -- PROPOSAL
		woodUnits = 0,
		ingots = { Copper = 1 }, -- PROPOSAL
		gated = true,
		edge = true,
		footprint = V2(4, 1),
		boxes = {
			{ size = V3(4, 0.72, 0.44), offset = V3(0, 0.36, 0), color = COPPER, material = "Metal", role = "Trim" },
		},
		note = "A copper band for a wall top or a floor edge",
	}),
	piece({
		id = "SandWall4",
		displayName = "Sandstone Wall",
		priceCash = 8, -- PROPOSAL
		woodUnits = 0,
		slabUnits = 2, -- PROPOSAL
		gated = true,
		edge = true,
		footprint = V2(4, 1),
		boxes = {
			{ size = V3(4, 6.6, 0.65), offset = V3(0, 3.3, 0), color = SANDSTONE, material = "Sandstone" },
		},
		note = "A straight sandstone wall, 4 studs",
	}),
	piece({
		id = "SandFloor4",
		displayName = "Sandstone Floor",
		priceCash = 8, -- PROPOSAL
		woodUnits = 0,
		slabUnits = 2, -- PROPOSAL
		gated = true,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(4, 0.3, 4), offset = V3(0, 0.15, 0), color = SANDSTONE, material = "Sandstone" },
		},
		note = "A 4×4 sandstone floor",
	}),
	piece({
		id = "SandArch8",
		displayName = "Sandstone Arch",
		priceCash = 16, -- PROPOSAL
		woodUnits = 0,
		slabUnits = 4, -- PROPOSAL
		gated = true,
		edge = true,
		footprint = V2(8, 2),
		slot = { size = V3(4, 6, 1.4), offset = V3(0, 3, 0) },
		boxes = {
			{ size = V3(2, 7.6, 1.4), offset = V3(-3, 3.8, 0), color = SANDSTONE, material = "Sandstone" },
			{ size = V3(2, 7.6, 1.4), offset = V3(3, 3.8, 0), color = SANDSTONE, material = "Sandstone" },
			{ size = V3(4, 1.6, 1.4), offset = V3(0, 6.8, 0), color = SANDSTONE, material = "Sandstone" },
		},
		note = "An arch with a 4×6 opening",
	}),
}
