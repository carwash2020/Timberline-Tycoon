--!strict
-- PlotData: plots and blueprints (GAME_DESIGN §9, §10). Where the plots
-- are, the base tiers that grow a plot, and every blueprint you can place.
-- Tuning = editing this table (placement rules are in PlotLogic).
--
-- Placed items are saved in plot-local studs: (x, z) is the item's centre
-- relative to the plot's centre, rot is 0-3 quarter turns. A plot's area is
-- `size` x `size` around its centre.

local GameConfig = require(script.Parent.GameConfig)

local PlotData = {}

-- Homesteads spread around the map, not a grid beside town. One server
-- holds MaxPlayers people; two extra pads stay open so the last arrival
-- still has a choice. The flat shelf is Pad studs on a side (the biggest
-- tier). Each pad gets a lane (LaneWidth, a Logging Rig wide) to the
-- nearest road, and a clear delivery pad on that edge for the truck.
-- Builds stay in plot-local studs, so a layout loads on whichever pad
-- you pick this visit. The picker opens on Birch Side, then Orchard
-- Edge and Oak Side (the Starter Forest), then The Climb. The rest are
-- nearest the sawmill first. East Meadow stays east of the lot.
export type Home = {
	id: string,
	name: string,
	region: string, -- what the plot picker calls the place
	x: number,
	z: number,
}

PlotData.LaneWidth = 22
PlotData.Pad = 200
PlotData.Blend = 56 -- the shelf eases into the country over at least 50 studs
PlotData.DeliveryWidth = 16 -- studs back from the road edge into the yard
PlotData.DeliveryLength = 80 -- along that edge: a Logging Rig plus a Heavy Hauler
PlotData.MinSpacing = 248
PlotData.NearHaul = 500 -- the homes listed first sit inside this of the sawmill
PlotData.GroveReach = 640
-- Everyone online, plus two spare pads.
PlotData.Count = GameConfig.MaxPlayers + 2

-- Centres chosen clear of the river, the lake, the coast, the lava, the
-- gondola and the haul roads. Shelves stay 48 studs apart on the wider
-- axis (MinSpacing minus Pad). Each is within GroveReach of a grove.
-- The first four are the opening offer. After that, nearest the sawmill.
PlotData.Homes = {
	{ id = "birch", name = "Birch Side", region = "Starter Forest", x = 0, z = -350 },
	{ id = "orchard", name = "Orchard Edge", region = "Starter Forest", x = -360, z = -160 },
	-- South of East Meadow, and far enough west that the two shelves
	-- don't meet. About (230, -350); a little further so the gap holds.
	{ id = "oak", name = "Oak Side", region = "Starter Forest", x = 248, z = -380 },
	-- Ten studs north of the old spot, so the blend clears the display
	-- lot's north edge (z 123) by more than 10 studs.
	{ id = "climb", name = "The Climb", region = "the north road", x = 330, z = 290 },
	{ id = "north", name = "North Bend", region = "the north road", x = -190, z = 530 },
	-- East of the display lot (x 184-296). The shelf and its blend stay
	-- south of the lot and the path from the showroom.
	{ id = "mill", name = "East Meadow", region = "east of town", x = 450, z = -130 },
	{ id = "meadow", name = "North Meadow", region = "the north road", x = 130, z = 680 },
	{ id = "west", name = "West Shelf", region = "west country", x = -250, z = -420 },
	{ id = "pine", name = "Pine Bend", region = "The Hills", x = -580, z = 380 },
	{ id = "east", name = "East Field", region = "east country", x = 698, z = 100 },
	{ id = "ridge", name = "Lower Ridge", region = "south country", x = 520, z = -430 },
	{ id = "high", name = "High Meadow", region = "the north road", x = -460, z = 720 },
	{ id = "ash", name = "Ash Gate", region = "the east road", x = 720, z = -180 },
	{ id = "long", name = "Long Meadow", region = "south country", x = 200, z = -650 },
} :: { Home }

PlotData.Slots = {} :: { Vector2 }
for _, home in ipairs(PlotData.Homes) do
	table.insert(PlotData.Slots, Vector2.new(home.x, home.z))
end

function PlotData.Home(index: number): Home?
	return PlotData.Homes[index]
end

PlotData.Grid = 2 -- studs: item centres snap to this (GAME_DESIGN §14.6)
PlotData.HeightStep = 0.2 -- studs: stacked pieces sit on this (ground 0, floor top 0.4, foundation top 2)
PlotData.MaxBuildY = 40 -- studs above the plot: the tallest a piece's base may sit
PlotData.MaxItems = 200 -- prebuilt pieces per plot (sheds, decor, sawmills)
PlotData.MaxKit = 400 -- kit pieces per plot, counted apart from MaxItems
PlotData.KitCashPerUnit = 4 -- blueprint fee. The old fee was 10; that stays in priceCash for saves with no `paid`
PlotData.EdgeTrim = 0.5 -- studs cut off each end of an edge piece, along its length only
PlotData.RoofOverhang = 0.5 -- visual only: roofs stick out this far and the overlap test ignores it
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
	shape: string?, -- "Cylinder" (axis X), "Ball", or "Wedge" (low end at -Z); default a block
	role: string?, -- "Wood", "Glass", "Glow", "Sign", "Flag", "Metal", "Prop"; tint only Wood and Door
	leaf: boolean?, -- the part that swings; posts and jambs do not
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
	unlock: boolean?, -- bought once at the General Store; placing copies is free
	woodUnits: number?, -- kit: plank units to fill, and the fee is KitCashPerUnit each. Others: $10 a unit
	kit: boolean?, -- pay the fee on every place, then fill it with planks of one wood
	edge: boolean?, -- overlap trims EdgeTrim off each end, along local X only
	roof: boolean?, -- overlap ignores RoofOverhang on local X and Z
	fits: string?, -- "Door" or "Window": may only sit inside that opening
	opens: boolean?, -- a door or a gate: the owner toggles it
	hinge: number?, -- local X the leaf swings around (toward +Z)
	slot: { size: Vector3, offset: Vector3 }?, -- the opening a Door or Window must sit inside
}

-- What placing charges now. A kit piece is KitCashPerUnit per wood unit.
-- Anything else priced in wood units is still the old $10 a unit. `priceCash`
-- on an existing kit id is that old price, kept so a save with no `paid`
-- sells back at the old rate.
function PlotData.Price(bp: Blueprint): number
	if bp.kit == true and type(bp.woodUnits) == "number" then
		return bp.woodUnits * PlotData.KitCashPerUnit
	end
	if type(bp.woodUnits) == "number" then
		return bp.woodUnits * 10
	end
	return bp.priceCash
end

-- The price a save from before `paid` sells against (half of this).
function PlotData.LegacyPrice(bp: Blueprint): number
	return bp.priceCash
end

local WOOD = "#654321"
local WOOD_LIGHT = "#825A32"
local STONE = "#8C8680"

PlotData.Blueprints = {
	{
		id = "Wall",
		displayName = "Wall",
		category = "Buildings",
		priceCash = 80, -- legacy ×10; the fee you pay now is woodUnits × 4
		woodUnits = 8,
		kit = true,
		edge = true,
		tier = 1,
		footprint = Vector2.new(8, 1),
		boxes = {
			{ size = Vector3.new(8, 6, 1), offset = Vector3.new(0, 3, 0), color = WOOD, material = "WoodPlanks" },
		},
		note = "A straight wall, 8 studs",
	},
	{
		id = "Floor",
		displayName = "Floor",
		category = "Buildings",
		priceCash = 120,
		woodUnits = 12,
		kit = true,
		tier = 1,
		footprint = Vector2.new(8, 8),
		boxes = {
			{
				size = Vector3.new(8, 0.4, 8),
				offset = Vector3.new(0, 0.2, 0),
				color = WOOD_LIGHT,
				material = "WoodPlanks",
			},
		},
		note = "A square of floor",
	},
	{
		id = "Door",
		displayName = "Door",
		category = "Buildings",
		priceCash = 40,
		woodUnits = 4,
		kit = true,
		fits = "Door",
		opens = true,
		hinge = -1.6,
		tier = 1,
		footprint = Vector2.new(4, 1),
		boxes = {
			{
				size = Vector3.new(3.2, 6, 0.4),
				offset = Vector3.new(0, 3, 0),
				color = WOOD_LIGHT,
				material = "Wood",
				role = "Door",
				leaf = true,
			},
		},
		note = "Hangs in a door wall and swings open",
	},
	{
		id = "Window",
		displayName = "Window",
		category = "Buildings",
		priceCash = 60,
		woodUnits = 6,
		kit = true,
		fits = "Window",
		tier = 1,
		footprint = Vector2.new(4, 1),
		boxes = {
			{
				size = Vector3.new(4, 3, 0.3),
				offset = Vector3.new(0, 3.5, 0),
				color = "#C9E4F2",
				material = "Glass",
				role = "Glass",
			},
		},
		note = "Glass for a window wall. The glass stays clear",
	},
	{
		id = "Stairs",
		displayName = "Stairs",
		category = "Buildings",
		priceCash = 180,
		woodUnits = 18,
		kit = true,
		tier = 1,
		footprint = Vector2.new(4, 8),
		boxes = {
			-- WedgePart: full height at +Z, ground at -Z. Matches the stair mesh (rise 4 over 8).
			{
				size = Vector3.new(4, 4, 8),
				offset = Vector3.new(0, 2, 0),
				color = WOOD,
				material = "WoodPlanks",
				shape = "Wedge",
			},
		},
		note = "A flight of stairs, rising toward the back",
	},
	{
		id = "Shed",
		displayName = "Small Shed",
		category = "Buildings",
		priceCash = 600,
		woodUnits = 60,
		unlock = true,
		tier = 1,
		footprint = Vector2.new(10, 8),
		boxes = {
			{
				size = Vector3.new(10, 0.4, 8),
				offset = Vector3.new(0, 0.2, 0),
				color = WOOD_LIGHT,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(10, 5, 0.4),
				offset = Vector3.new(0, 2.7, 3.8),
				color = WOOD,
				material = "WoodPlanks",
			},
			{
				size = Vector3.new(0.4, 5, 8),
				offset = Vector3.new(-4.8, 2.7, 0),
				color = WOOD,
				material = "WoodPlanks",
			},
			{ size = Vector3.new(0.4, 5, 8), offset = Vector3.new(4.8, 2.7, 0), color = WOOD, material = "WoodPlanks" },
			{ size = Vector3.new(10, 0.4, 8), offset = Vector3.new(0, 5.2, 0), color = "#6B4423", material = "Wood" },
		},
		note = "A starter shed",
	},
	{
		id = "WoodSign",
		displayName = "Wood Sign",
		category = "Decor",
		priceCash = 40,
		unlock = true,
		tier = 1,
		footprint = Vector2.new(4, 1),
		boxes = {
			{ size = Vector3.new(0.3, 3, 0.3), offset = Vector3.new(0, 1.5, 0), color = WOOD, material = "Wood" },
			{
				size = Vector3.new(3.2, 1.4, 0.2),
				offset = Vector3.new(0, 3.2, 0),
				color = WOOD_LIGHT,
				material = "Wood",
			},
		},
		note = "A sign for your plot",
	},
	{
		id = "PaintCan",
		displayName = "Paint Can",
		category = "Decor",
		priceCash = 60,
		unlock = true,
		tier = 1,
		footprint = Vector2.new(2, 2),
		boxes = {
			{
				size = Vector3.new(1.2, 1.4, 1.2),
				offset = Vector3.new(0, 0.7, 0),
				color = "#C8402F",
				material = "Metal",
			},
		},
		note = "A can of barn-red paint",
	},
	{
		id = "Mailbox",
		displayName = "Mailbox",
		category = "Decor",
		priceCash = 80,
		unlock = true,
		tier = 1,
		footprint = Vector2.new(2, 2),
		boxes = {
			{ size = Vector3.new(0.3, 3, 0.3), offset = Vector3.new(0, 1.5, 0), color = WOOD, material = "Wood" },
			{
				size = Vector3.new(1.4, 0.8, 0.8),
				offset = Vector3.new(0, 3.2, 0),
				color = "#3A6FD8",
				material = "Metal",
			},
		},
		note = "A mailbox by the path",
	},
	{
		id = "Fence",
		displayName = "Fence",
		category = "Decor",
		priceCash = 30,
		woodUnits = 3,
		kit = true,
		edge = true,
		tier = 1,
		footprint = Vector2.new(8, 1),
		boxes = {
			{ size = Vector3.new(8, 3, 1), offset = Vector3.new(0, 1.5, 0), color = WOOD, material = "WoodPlanks" },
		},
		note = "A run of fence, 8 studs",
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

local KitPieces = require(script.Parent.KitPieces) :: { any }
for _, extra in ipairs(KitPieces) do
	table.insert(PlotData.Blueprints, extra :: Blueprint)
end

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
