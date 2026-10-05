--!strict
-- DecorData: furniture and decor for a plot (V2_PLAN.md, "Today's PlotData
-- blueprints become Furniture"). PlotData appends this list to its
-- blueprints, so PlotLogic places them, PlotService charges for them and
-- ProfileSchema saves them like any other piece.
--
-- Every piece is cash only. No gathered material goes into any of them, so
-- none needs a recipe job or a home biome (GAME_DESIGN §15).
-- Prices stay in the range of the older decor: $50 to $140.
--
-- `unlock = true` pieces are bought once, boxed, at Hearth & Home, and then
-- placed free (StoreStock stocks them from this flag). Every piece here
-- carries it: the Hearth & Home shelves run 20 boxes long. Only kit pieces
-- (walls, floors) are still paid for each time you place one.
-- Pieces stay at five boxes or fewer (DecorData.spec holds the budget).

local V2 = Vector2.new
local V3 = Vector3.new

local WOOD = "#654321"
local WOOD_LIGHT = "#825A32"
local WOOD_DARK = "#4E3320"

local function piece(def: { [string]: any }): { [string]: any }
	def.category = "Decor"
	def.tier = 1
	return def
end

return {
	piece({
		id = "Table",
		displayName = "Table",
		priceCash = 90,
		unlock = true,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(4, 0.4, 4), offset = V3(0, 2.6, 0), color = WOOD_LIGHT, material = "WoodPlanks" },
			{ size = V3(0.4, 2.4, 3.4), offset = V3(-1.6, 1.2, 0), color = WOOD, material = "Wood" },
			{ size = V3(0.4, 2.4, 3.4), offset = V3(1.6, 1.2, 0), color = WOOD, material = "Wood" },
		},
		note = "A plain table for the cabin",
	}),
	piece({
		id = "Chair",
		displayName = "Chair",
		priceCash = 50,
		unlock = true,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.6, 0.3, 1.6), offset = V3(0, 1.45, 0), color = WOOD_LIGHT, material = "WoodPlanks" },
			{ size = V3(1.6, 1.6, 0.3), offset = V3(0, 2.4, 0.65), color = WOOD_LIGHT, material = "WoodPlanks" },
			{ size = V3(0.3, 1.3, 1.4), offset = V3(-0.65, 0.65, 0), color = WOOD, material = "Wood" },
			{ size = V3(0.3, 1.3, 1.4), offset = V3(0.65, 0.65, 0), color = WOOD, material = "Wood" },
		},
		note = "A chair. The back is at the rear",
	}),
	piece({
		id = "Bookshelf",
		displayName = "Bookshelf",
		priceCash = 140,
		unlock = true,
		footprint = V2(4, 2),
		boxes = {
			{ size = V3(4, 5.6, 0.3), offset = V3(0, 2.8, 0.7), color = WOOD, material = "WoodPlanks" },
			{ size = V3(0.3, 5.6, 1.6), offset = V3(-1.85, 2.8, 0), color = WOOD_DARK, material = "Wood" },
			{ size = V3(0.3, 5.6, 1.6), offset = V3(1.85, 2.8, 0), color = WOOD_DARK, material = "Wood" },
			{ size = V3(3.4, 0.3, 1.4), offset = V3(0, 1.9, 0), color = WOOD_LIGHT, material = "WoodPlanks" },
			{ size = V3(3.4, 1.2, 1), offset = V3(0, 3.8, 0), color = "#9C4A3C", material = "Fabric" },
		},
		note = "A shelf of books",
	}),
	piece({
		id = "Rug",
		displayName = "Rug",
		priceCash = 60,
		unlock = true,
		footprint = V2(6, 4),
		boxes = {
			{ size = V3(6, 0.15, 4), offset = V3(0, 0.075, 0), color = "#8E3B3B", material = "Fabric" },
		},
		note = "A flat rug. Walk right over it",
	}),
	piece({
		id = "Barrel",
		displayName = "Barrel",
		priceCash = 70,
		unlock = true,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.6, 2.2, 1.6), offset = V3(0, 1.1, 0), color = WOOD_LIGHT, material = "Wood" },
			{ size = V3(1.75, 0.3, 1.75), offset = V3(0, 1.1, 0), color = "#3C3C41", material = "Metal" },
		},
	}),
	piece({
		id = "Crate",
		displayName = "Crate",
		priceCash = 60,
		unlock = true,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.8, 1.8, 1.8), offset = V3(0, 0.9, 0), color = WOOD, material = "WoodPlanks" },
			{ size = V3(2, 0.2, 2), offset = V3(0, 1.9, 0), color = WOOD_DARK, material = "Wood" },
		},
	}),
	piece({
		id = "FirePit",
		displayName = "Fire Pit",
		priceCash = 110,
		unlock = true,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(3.6, 0.6, 3.6), offset = V3(0, 0.3, 0), color = "#8C8680", material = "Slate" },
			{
				size = V3(1.4, 0.6, 1.4),
				offset = V3(0, 0.9, 0),
				color = "#FF8A3C",
				material = "Neon",
				light = true,
			},
			{
				size = V3(2.4, 0.4, 0.4),
				offset = V3(0, 1.3, -0.5),
				color = "#7A5230",
				material = "Wood",
				shape = "Cylinder",
			},
			{
				size = V3(2.4, 0.4, 0.4),
				offset = V3(0, 1.3, 0.5),
				color = "#7A5230",
				material = "Wood",
				shape = "Cylinder",
			},
		},
		note = "A fire pit that glows all night",
	}),
}
