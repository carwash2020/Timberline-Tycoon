--!strict
-- PlotData: plots and blueprints (GAME_DESIGN §9, §10). Where the plots
-- are, the base tiers that grow a plot, and every blueprint you can place.
-- Tuning = editing this table (placement rules are in PlotLogic).
--
-- Placed items are saved in plot-local studs: (x, z) is the item's centre
-- relative to the plot's centre, rot is 0-3 quarter turns. A plot's area is
-- `size` x `size` around its centre.

local PlotData = {}

-- The plot district, east of town: 12 plots, 3 columns by 4 rows. One
-- server holds up to 12 players, so everyone fits. The biggest tier is
-- 200 x 200. The gap between those pads is wide enough for a lane a
-- Logging Rig can drive (LaneWidth) with grass either side. The north
-- road stays on the town's plot-road mouth (its centre is RoadSetback
-- studs north of the biggest pad, so the claim sign is not in the
-- roadway). The west edge stays east of the parking-lot loop; the east
-- edge stays off the beach.
PlotData.Columns = 3
PlotData.Rows = 4
PlotData.SlotSpacing = 248
PlotData.LaneWidth = 22
PlotData.RoadSetback = 28
PlotData.Slots = {} :: { Vector2 }
-- Row 0's north edge lands RoadSetback south of the plot road at z = 50.
-- Column 0's west edge (200) clears the lot loop, whose east fence is at x = 180.
local ORIGIN_X, ORIGIN_Z = 300, -78
for row = 0, PlotData.Rows - 1 do
	for col = 0, PlotData.Columns - 1 do
		table.insert(
			PlotData.Slots,
			Vector2.new(ORIGIN_X + col * PlotData.SlotSpacing, ORIGIN_Z - row * PlotData.SlotSpacing)
		)
	end
end

PlotData.Grid = 2 -- studs: item centres snap to this (GAME_DESIGN §14.6)
PlotData.MaxItems = 200 -- per plot, to keep saves small
PlotData.SellBack = 0.5 -- selling a placed item returns this share of its price

export type Tier = {
	name: string,
	size: number, -- studs on a side
	priceCash: number, -- to reach this tier from the one before
	stone: number, -- Stone (a later slice; 0 until it exists)
	planks: number, -- your own planks (a later slice; 0 until they exist)
}

-- Prices are a first pass for Connor to tune (not in the economy model yet).
PlotData.Tiers = {
	{ name = "Campsite", size = 120, priceCash = 0, stone = 0, planks = 0 },
	{ name = "Homestead", size = 140, priceCash = 2500, stone = 0, planks = 0 },
	{ name = "Lumber Yard", size = 160, priceCash = 10000, stone = 0, planks = 0 },
	{ name = "Timber Works", size = 180, priceCash = 30000, stone = 0, planks = 0 },
	{ name = "Timber Empire", size = 200, priceCash = 60000, stone = 0, planks = 0 },
} :: { Tier }

export type Box = {
	size: Vector3,
	offset: Vector3, -- centre, relative to the item's ground centre
	color: string, -- hex
	material: string, -- Enum.Material name
	shape: string?, -- "Cylinder" (axis X) or "Ball"; default a block
	light: boolean?, -- a warm PointLight in it
	smoke: boolean?, -- a chimney: the client puffs smoke here (not on Low)
}

export type Blueprint = {
	id: string,
	displayName: string,
	category: string, -- "Buildings" | "Decor"
	priceCash: number,
	tier: number, -- the plot tier it needs
	footprint: Vector2, -- width (x) and depth (z) in studs at rot 0
	boxes: { Box },
	note: string?, -- what it does (buildings that work come in later slices)
}

local WOOD = "#654321"
local WOOD_LIGHT = "#825A32"
local STONE = "#8C8680"

PlotData.Blueprints = {
	{
		id = "Fence",
		displayName = "Fence",
		category = "Decor",
		priceCash = 40,
		tier = 1,
		footprint = Vector2.new(8, 1),
		boxes = {
			{ size = Vector3.new(8, 0.4, 0.3), offset = Vector3.new(0, 2.2, 0), color = WOOD_LIGHT, material = "Wood" },
			{ size = Vector3.new(8, 0.4, 0.3), offset = Vector3.new(0, 1.2, 0), color = WOOD_LIGHT, material = "Wood" },
			{ size = Vector3.new(0.5, 3, 0.5), offset = Vector3.new(-3.75, 1.5, 0), color = WOOD, material = "Wood" },
			{ size = Vector3.new(0.5, 3, 0.5), offset = Vector3.new(3.75, 1.5, 0), color = WOOD, material = "Wood" },
		},
	},
	{
		id = "FlowerBed",
		displayName = "Flower Bed",
		category = "Decor",
		priceCash = 60,
		tier = 1,
		footprint = Vector2.new(4, 4),
		boxes = {
			{ size = Vector3.new(4, 0.6, 4), offset = Vector3.new(0, 0.3, 0), color = "#5A3C28", material = "Ground" },
			{ size = Vector3.new(3, 0.8, 3), offset = Vector3.new(0, 0.9, 0), color = "#E07AA0", material = "Grass" },
		},
	},
	{
		id = "Bench",
		displayName = "Bench",
		category = "Decor",
		priceCash = 80,
		tier = 1,
		footprint = Vector2.new(4, 2),
		boxes = {
			{
				size = Vector3.new(4, 0.3, 1.4),
				offset = Vector3.new(0, 1.3, 0),
				color = WOOD_LIGHT,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(4, 1.2, 0.3),
				offset = Vector3.new(0, 2, 0.6),
				color = WOOD_LIGHT,
				material = "WoodPlanks",
			},
			{ size = Vector3.new(0.4, 1.2, 1.2), offset = Vector3.new(-1.7, 0.6, 0), color = WOOD, material = "Wood" },
			{ size = Vector3.new(0.4, 1.2, 1.2), offset = Vector3.new(1.7, 0.6, 0), color = WOOD, material = "Wood" },
		},
	},
	{
		id = "LampPost",
		displayName = "Lamp Post",
		category = "Decor",
		priceCash = 120,
		tier = 1,
		footprint = Vector2.new(2, 2),
		boxes = {
			{ size = Vector3.new(0.5, 7, 0.5), offset = Vector3.new(0, 3.5, 0), color = "#3C3C41", material = "Metal" },
			{
				size = Vector3.new(1.2, 1.2, 1.2),
				offset = Vector3.new(0, 7.4, 0),
				color = "#FFD78C",
				material = "Neon",
				light = true,
			},
		},
	},
	{
		id = "LogPile",
		displayName = "Log Pile",
		category = "Decor",
		priceCash = 150,
		tier = 1,
		footprint = Vector2.new(6, 4),
		boxes = {
			{
				size = Vector3.new(6, 1.2, 1.2),
				offset = Vector3.new(0, 0.6, -1.2),
				color = "#7A5230",
				material = "Wood",
				shape = "Cylinder",
			},
			{
				size = Vector3.new(6, 1.2, 1.2),
				offset = Vector3.new(0, 0.6, 0),
				color = "#7A5230",
				material = "Wood",
				shape = "Cylinder",
			},
			{
				size = Vector3.new(6, 1.2, 1.2),
				offset = Vector3.new(0, 0.6, 1.2),
				color = "#7A5230",
				material = "Wood",
				shape = "Cylinder",
			},
			{
				size = Vector3.new(6, 1.2, 1.2),
				offset = Vector3.new(0, 1.65, -0.6),
				color = "#8A6038",
				material = "Wood",
				shape = "Cylinder",
			},
			{
				size = Vector3.new(6, 1.2, 1.2),
				offset = Vector3.new(0, 1.65, 0.6),
				color = "#8A6038",
				material = "Wood",
				shape = "Cylinder",
			},
		},
	},
	{
		id = "Flag",
		displayName = "Flag",
		category = "Decor",
		priceCash = 200,
		tier = 1,
		footprint = Vector2.new(2, 4),
		boxes = {
			{
				size = Vector3.new(0.4, 12, 0.4),
				offset = Vector3.new(0, 6, -1.6),
				color = "#DCDCDC",
				material = "Metal",
			},
			{
				size = Vector3.new(0.1, 2.4, 3.4),
				offset = Vector3.new(0, 10.6, 0.3),
				color = "#B23A26",
				material = "Fabric",
			},
		},
	},
	{
		id = "Cabin",
		displayName = "Cabin",
		category = "Buildings",
		priceCash = 2000,
		tier = 1,
		footprint = Vector2.new(12, 10),
		boxes = {
			{ size = Vector3.new(12, 1, 10), offset = Vector3.new(0, 0.5, 0), color = STONE, material = "Slate" },
			{
				size = Vector3.new(12, 7, 0.8),
				offset = Vector3.new(0, 4.5, 4.6),
				color = WOOD,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(0.8, 7, 10),
				offset = Vector3.new(-5.6, 4.5, 0),
				color = WOOD,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(0.8, 7, 10),
				offset = Vector3.new(5.6, 4.5, 0),
				color = WOOD,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(4, 7, 0.8),
				offset = Vector3.new(-4, 4.5, -4.6),
				color = WOOD,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(4, 7, 0.8),
				offset = Vector3.new(4, 4.5, -4.6),
				color = WOOD,
				material = "WoodPlanks",
			},
			{ size = Vector3.new(13, 1, 11), offset = Vector3.new(0, 8.5, 0), color = "#963C2C", material = "Wood" },
			{
				size = Vector3.new(1.6, 3.2, 1.6),
				offset = Vector3.new(3.6, 10.4, 2.4),
				color = STONE,
				material = "Slate",
				smoke = true,
			},
		},
	},
	{
		id = "Warehouse",
		displayName = "Warehouse",
		category = "Buildings",
		priceCash = 4000,
		tier = 2,
		footprint = Vector2.new(16, 12),
		note = "Will store logs and materials (a later update)",
		boxes = {
			{ size = Vector3.new(16, 1, 12), offset = Vector3.new(0, 0.5, 0), color = STONE, material = "Slate" },
			{
				size = Vector3.new(16, 9, 0.8),
				offset = Vector3.new(0, 5.5, 5.6),
				color = "#6E7F46",
				material = "CorrodedMetal",
			},
			{
				size = Vector3.new(0.8, 9, 12),
				offset = Vector3.new(-7.6, 5.5, 0),
				color = "#6E7F46",
				material = "CorrodedMetal",
			},
			{
				size = Vector3.new(0.8, 9, 12),
				offset = Vector3.new(7.6, 5.5, 0),
				color = "#6E7F46",
				material = "CorrodedMetal",
			},
			{ size = Vector3.new(17, 1, 13), offset = Vector3.new(0, 10.5, 0), color = "#4A4F57", material = "Metal" },
		},
	},
	{
		id = "AxeRack",
		displayName = "Axe Rack",
		category = "Buildings",
		priceCash = 500,
		tier = 2,
		footprint = Vector2.new(6, 2),
		note = "Will show off your axes (a later update)",
		boxes = {
			{ size = Vector3.new(6, 4, 0.5), offset = Vector3.new(0, 2.5, 0.6), color = WOOD, material = "WoodPlanks" },
			{
				size = Vector3.new(0.5, 4.5, 1.6),
				offset = Vector3.new(-2.75, 2.25, 0),
				color = WOOD_LIGHT,
				material = "Wood",
			},
			{
				size = Vector3.new(0.5, 4.5, 1.6),
				offset = Vector3.new(2.75, 2.25, 0),
				color = WOOD_LIGHT,
				material = "Wood",
			},
		},
	},
} :: { Blueprint }

local byId: { [string]: Blueprint } = {}
for _, bp in ipairs(PlotData.Blueprints) do
	byId[bp.id] = bp
end

function PlotData.Blueprint(id: string): Blueprint?
	return byId[id]
end

function PlotData.Tier(index: number): Tier?
	return PlotData.Tiers[index]
end

return PlotData
