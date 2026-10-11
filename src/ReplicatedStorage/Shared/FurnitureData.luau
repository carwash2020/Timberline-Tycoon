--!strict
-- FurnitureData: the two crafted furniture pieces (Lane M's bench recipes:
-- Copper Lamp Post and Gold-banded Chest). PlotData appends this list to its
-- blueprints, so PlotLogic places them, ProfileSchema saves them and
-- BlueprintModels draws them like any decor.
--
-- They are not for sale and not learned from a plan. Crafting one at the
-- bench GRANTS one (PlotService.GrantPiece): a from-stock entry in the book,
-- like a boxed machine, spent when it is placed. Placing it costs no cash.
--
-- Look (PROPOSAL, Awaiting Connor; the Game Art Director palette is still
-- pending): copper #B87333 Metal for the post, gold bands #D4A92E Metal and
-- planks for the chest. Part-built with at most 12 boxes each, sized to the
-- uploaded meshes' bounding boxes (backlog/furniture/<Name>/stats.json) so
-- job 17 can swap the mesh in. Parts under one stud do not cast a shadow
-- (BlueprintModels).

local V2 = Vector2.new
local V3 = Vector3.new

local COPPER = "#B87333"
local GOLD = "#D4A92E"
local WOOD = "#654321"
local WOOD_DARK = "#4E3320"

local function piece(def: { [string]: any }): { [string]: any }
	def.category = "Decor"
	def.tier = 1
	def.granted = true -- placed from stock a craft grants; never sold, never learned
	def.priceCash = 0
	return def
end

local FurnitureData = {}

FurnitureData.MaxBoxes = 12
-- How many crafted pieces may wait in stock at once (PROPOSAL). A craft that
-- would go over is refused before it takes anything.
FurnitureData.MaxStock = 20

FurnitureData.Pieces = {
	-- 2 x 3 footprint. The post stands at the back, the arm reaches forward
	-- (toward -Z) and carries the lantern.
	piece({
		id = "CopperLampPost",
		displayName = "Copper Lamp Post",
		footprint = V2(2, 3),
		boxes = {
			{ size = V3(1.4, 0.4, 1.4), offset = V3(0, 0.2, 0.55), color = COPPER, material = "Metal" },
			{ size = V3(0.8, 0.3, 0.8), offset = V3(0, 0.55, 0.55), color = COPPER, material = "Metal" },
			{ size = V3(0.4, 6.4, 0.4), offset = V3(0, 3.6, 0.55), color = COPPER, material = "Metal" },
			{ size = V3(0.3, 0.3, 1.7), offset = V3(0, 6.6, -0.3), color = COPPER, material = "Metal" },
			{ size = V3(0.5, 0.3, 0.5), offset = V3(0, 6.95, 0.55), color = COPPER, material = "Metal" },
			{ size = V3(0.8, 0.2, 0.8), offset = V3(0, 6.45, -0.85), color = COPPER, material = "Metal" },
			{ size = V3(0.7, 0.2, 0.7), offset = V3(0, 5.55, -0.85), color = COPPER, material = "Metal" },
			{
				size = V3(0.5, 0.7, 0.5),
				offset = V3(0, 6, -0.85),
				color = "#FFD27A",
				material = "Neon",
				light = true,
			},
		},
		note = "A copper lamp post that glows all night",
	}),
	-- 4 x 3 footprint, 2.7 tall: a planked chest with gold bands and a lock.
	piece({
		id = "GoldChest",
		displayName = "Gold-banded Chest",
		footprint = V2(4, 3),
		boxes = {
			{ size = V3(3.35, 1.7, 2.2), offset = V3(0, 0.85, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(3.35, 0.9, 2.2), offset = V3(0, 2.15, 0), color = WOOD_DARK, material = "WoodPlanks" },
			{ size = V3(0.35, 2.68, 2.3), offset = V3(-1.3, 1.34, 0), color = GOLD, material = "Metal" },
			{ size = V3(0.35, 2.68, 2.3), offset = V3(1.3, 1.34, 0), color = GOLD, material = "Metal" },
			{ size = V3(3.4, 0.25, 2.3), offset = V3(0, 1.72, 0), color = GOLD, material = "Metal" },
			{ size = V3(0.5, 0.6, 0.2), offset = V3(0, 1.6, -1.2), color = GOLD, material = "Metal" },
			{ size = V3(0.2, 0.2, 0.06), offset = V3(0, 1.5, -1.3), color = "#7FE0FF", material = "Neon" },
		},
		note = "A chest with gold bands. For show",
	}),
}

local BY_ID: { [string]: boolean } = {}
for _, p in ipairs(FurnitureData.Pieces) do
	BY_ID[p.id] = true
end

-- Is this id one of the granted furniture pieces?
function FurnitureData.IsGranted(id: unknown): boolean
	return type(id) == "string" and BY_ID[id] == true
end

-- The craft recipe's `gives.furniture` names a piece. True when it is one of
-- ours (so CraftData can enable the recipe once the grant exists).
function FurnitureData.Known(id: unknown): boolean
	return FurnitureData.IsGranted(id)
end

return FurnitureData
