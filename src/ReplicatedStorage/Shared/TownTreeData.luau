--!strict
-- TownTreeData: the numbers behind the choppable trees in and around the
-- spawn area (Connor, 8 October 2026: "we need more choppable trees in the
-- spawn area too, near the pad, by the dealership ... it's a lumberjack
-- game"). Pure data and two tiny helpers: no services, no terrain, so the
-- specs, the planner (TreeFill.TownRings) and the Studio notes all read the
-- same constants.
--
-- These are ordinary felling trees (SectionTrees): the stump stays and the
-- tree grows back inside its cluster's small regrow zone ("town:<site>"),
-- the woods follow the region (TreeFill.woodsNear), biome "wild". They are
-- NOT in BiomeData's counts, so the economy model is unchanged (the same
-- way TreeFill.PlotRings' trees are not).
--
-- A site is a disc: a cluster of trees and the regrow zone for them. The
-- list is in priority order and each site names the lowest quality tier that
-- plants it (see Counts). Trees are server-wide, so one server cannot plant
-- a different forest for each player's quality choice: TreeFill plants the
-- `ShippedTier` list for everyone (a phone's budget), and the Medium / High
-- lists exist so the spec pins what a roomier tier would add and so
-- ShippedTier is the one word to change.

local TownTreeData = {}

export type Tier = "low" | "medium" | "high"

export type Site = {
	id: string,
	cx: number,
	cz: number,
	radius: number, -- the cluster's disc, and its regrow zone's
	want: number, -- trees planted (and the zone's cap)
	tier: Tier, -- the lowest tier that plants this site
	why: string, -- where it is, for the notes and the failure messages
}

-- Quality tiers, lowest first (QualityBudgets.Tier's names).
TownTreeData.Tiers = { "low", "medium", "high" } :: { Tier }

-- The list TreeFill plants on every server. "low": the budget a phone can
-- carry, because the trees are the same for every player.
TownTreeData.ShippedTier = "low" :: Tier

-- The most trees each tier may plant (Count(tier) is checked against it).
-- Low is the phone's: the three phone discs (QualityBudgets, TreeFill.spec)
-- grew to 1.7x with the forest fill; the town's trees take the spawn disc
-- to about 1.95x, and PhoneDiscMax is the ceiling for trees and parts there.
TownTreeData.Budget = { low = 60, medium = 90, high = 100 } :: { [string]: number }
TownTreeData.PhoneDiscMax = 2.0

-- Trunk to trunk, town trees keep this much apart (a player and a truck walk
-- and drive between them): the forest's TREE_GAP is 10, this is a stud more.
TownTreeData.Gap = 12
TownTreeData.MaxClusterRadius = 16

-- Studs a trunk keeps off each kind of thing.
TownTreeData.Margin = {
	paint = 7, -- the street, plaza, paths, spawn walk, mill yard
	floor = 7, -- shop floors and the sell station's gravel
	road = 11, -- a road's edge (TerrainGen.RoadClearance)
	building = 9, -- a shop, the mill, the sell station, the gondola station
	camp = 14, -- Murph's camp
	lot = 12, -- the parking lot
	pullout = 8, -- the lot's pull-out lanes
	loading = 12, -- the boxed-vehicle loading pads
	greenery = 11, -- the ornamental trees, bushes, beds and rocks
	prop = 7,
	lamp = 6,
	sign = 12,
	fence = 7,
	walk = 7, -- an NPC's walking route
	stand = 11, -- where an NPC stands
	plot = 30, -- a homestead's biggest footprint
	queue = 0, -- (a queue lane carries its own half width)
}

export type Rect = { name: string, x0: number, z0: number, x1: number, z1: number }
export type Lane = { name: string, ax: number, az: number, bx: number, bz: number, half: number }

-- Whole rectangles that stay empty of town trees, margin included.
-- The sell area (x -60 to 60, z 80 to 140) is Connor's and stays empty; the
-- spawn lane is the pad, its walk and the view up it to the mill.
TownTreeData.Empty = {
	{ name = "SellArea", x0 = -60, z0 = 80, x1 = 60, z1 = 140 },
	{ name = "SpawnLane", x0 = -18, z0 = 8, x1 = 18, z1 = 100 },
	-- A few steps clear of every shop door: the front of each one.
	{ name = "DealershipDoor", x0 = 170, z0 = 62, x1 = 210, z1 = 107.4 },
	{ name = "ToolShedDoor", x0 = -108, z0 = 78, x1 = -60, z1 = 94 },
	{ name = "GeneralStoreDoor", x0 = -126, z0 = 148, x1 = -74, z1 = 166 },
} :: { Rect }

-- Buildings (their widest outline, roofs and eaves included), measured from
-- the art as MapBuilder builds it (tests/TownTrees.spec checks every
-- collidable part of the town against these and the trees).
TownTreeData.Buildings = {
	{ name = "ToolShed", x0 = -125, z0 = 87, x1 = -43, z1 = 149 },
	{ name = "GeneralStore", x0 = -147, z0 = 158, x1 = -53, z1 = 211 },
	{ name = "Showroom", x0 = 178, z0 = 93.4, x1 = 337, z1 = 163.4 },
	{ name = "Sawmill", x0 = -32, z0 = 95, x1 = 33, z1 = 139 },
	{ name = "SellStation", x0 = 37, z0 = 94, x1 = 84, z1 = 129 },
	{ name = "GondolaStation", x0 = -49, z0 = 140, x1 = -30, z1 = 159 },
	-- The Land Office counter (PlotService.LandOfficeAt) and its sign.
	{ name = "LandOffice", x0 = 134, z0 = 72, x1 = 162, z1 = 98 },
} :: { Rect }

TownTreeData.Camp = { name = "MurphsCamp", x0 = -40, z0 = 38, x1 = -23, z1 = 53 } :: Rect

-- The parking lot and its south pull-out lanes (WorldPlan.ParkingPullOut).
TownTreeData.ParkingLot = { name = "ParkingLot", x0 = 8, z0 = -18, x1 = 146, z1 = 68 } :: Rect
TownTreeData.PullOut = { name = "PullOut", x0 = 8, z0 = -46, x1 = 140, z1 = -18 } :: Rect

-- Lanes people queue or ride in: Old Hank's counter faces the spawn, and the
-- gondola leaves its station toward the isles (its cable and cabins pass
-- over the first stretch).
TownTreeData.Lanes = {
	{ name = "LandOfficeQueue", ax = 147, az = 86, bx = 112, bz = 74, half = 14 },
	-- The lighthouse's lamp stays in view from the spawn pad (WorldPlan.Lighthouse,
	-- tests/WorldPlan.spec): no trunk within 10 studs of the line from the pad's
	-- eye to the lamp. 11 here; the spec compares the lamp's place.
	{ name = "LighthouseSight", ax = 0, az = 40, bx = 780, bz = -240, half = 11 },
} :: { Lane }
TownTreeData.GondolaStation = { x = -40, z = 150 } -- WorldPlan.TownGondolaSpot (the spec compares)
TownTreeData.GondolaLaneLength = 280
TownTreeData.GondolaLaneHalf = 22

-- Where NPCs walk and stand (NPCData is the source; the spec compares).
TownTreeData.Walks = {
	{
		id = "Rosa",
		points = {
			{ -32, 58 },
			{ -50, 66 },
			{ -78, 84 },
			{ -60, 82 },
			{ -45, 84 },
			{ -38, 85 },
			{ -24, 76 },
			{ -22, 64 },
		},
	},
	{ id = "Pip", points = { { 20, 70 }, { 36, 76 }, { 45, 85 }, { 38, 80 }, { 20, 82 } } },
	{ id = "Bram", points = { { -17, 50 }, { -18, 66 }, { -16, 64 }, { -15, 52 } } },
} :: { { id: string, points: { { number } } } }

-- The sites, in priority order (a tier plants its own and every lower tier's;
-- see Count). Picked from the ground TreeFill.TownGround leaves free (the
-- spec checks that every one plants all of its trees), centres worked out on
-- 8 October 2026 from the town's layout: nearest the spawn pad first, then the
-- dealership and the Land Office, then the town's edges and the roads out.
local function cluster(id: string, cx: number, cz: number, radius: number, want: number, tier: Tier, why: string): Site
	return { id = id, cx = cx, cz = cz, radius = radius, want = want, tier = tier, why = why }
end

-- Ring map (10 October): twelve centres moved (12 to 107 studs) off the new East Link,
-- the yards of Birch Side and East Meadow, and the gondola's east run, to the nearest
-- ground that plants every tree.
TownTreeData.Sites = {
	-- low: the budget every server plants.
	cluster("padSW1", -59, 25, 16, 4, "low", "south-west of the spawn pad, west of the Forest Path"),
	cluster("padSW3", -106, 10, 16, 3, "low", "the meadow between the Forest Path and the Hills Road"),
	cluster("strip1", 149, 129, 16, 4, "low", "west of the showroom hall, past the Land Office, by the loading pad"),
	cluster("strip2", 152, 205, 16, 3, "low", "west of the showroom hall, its north-west corner"),
	cluster("forecourt", 316, 67, 16, 2, "low", "in front of the showroom, by its east end"),
	cluster("west1", -152, 145, 16, 3, "low", "the town's west edge, by the Tool Shed and the General Store"),
	cluster("west2", -172, 172, 16, 4, "low", "the town's west edge, north of the Hills Road"),
	cluster("west4", -167, 121, 16, 3, "low", "the town's west edge, by the Hills Road"),
	cluster("mill", 106, 234, 16, 3, "low", "behind the sawmill, in the gap in the pine band"),
	cluster("north1", -93, 233, 16, 4, "low", "north of the General Store, west of the Snow Road"),
	cluster("north2", -60, 230, 16, 3, "low", "north of the gondola station, along the Snow Road"),
	cluster("snowE", 39, 218, 16, 4, "low", "east of the Snow Road where the Mill Road meets it"),
	cluster("back1", 257, 179, 16, 4, "low", "behind the showroom hall"),
	cluster("back2", 288, 190, 16, 4, "low", "behind the showroom hall, east of the middle"),
	cluster("east1", 389, 125, 16, 3, "low", "east of the showroom hall"),
	cluster("roadS", 246, -76, 16, 3, "low", "south of the plot road, east of the lot"),
	-- medium: a roomier device.
	cluster("west3", -210, 141, 16, 3, "medium", "the town's west edge, further out"),
	cluster("north3", -140, 245, 16, 3, "medium", "north-west of the General Store"),
	cluster("snowE2", 66, 209, 16, 2, "medium", "east of the Snow Road, north of the Mill Road"),
	cluster("back3", 226, 216, 16, 3, "medium", "behind the showroom hall, west end"),
	cluster("east2", 351, 156, 16, 3, "medium", "behind the showroom hall's east end"),
	cluster("roadS2", 239, -31, 16, 3, "medium", "south of the plot road"),
	cluster("roadS3", 201, -59, 16, 3, "medium", "south of the plot road, further east"),
	-- high: the fullest town.
	cluster("ne", 385, 48, 16, 3, "high", "the north-east, past the showroom"),
	cluster("eastLotA", 256, 23, 16, 2, "high", "east of the lot, beside the plot road"),
	cluster("eastLotB", 217, 23, 16, 2, "high", "east of the lot, by the turnaround"),
	cluster("northFar2", 61, 294, 16, 4, "high", "north, east of the Snow Road"),
}

-- How many trees each tier plants: a tier plants its own sites and every
-- lower tier's.
function TownTreeData.TierIndex(tier: string): number
	for i, name in ipairs(TownTreeData.Tiers) do
		if name == tier then
			return i
		end
	end
	return 1
end

function TownTreeData.SitesFor(tier: string): { Site }
	local limit = TownTreeData.TierIndex(tier)
	local out: { Site } = {}
	for _, site in ipairs(TownTreeData.Sites) do
		if TownTreeData.TierIndex(site.tier) <= limit then
			table.insert(out, site)
		end
	end
	return out
end

function TownTreeData.Count(tier: string): number
	local n = 0
	for _, site in ipairs(TownTreeData.SitesFor(tier)) do
		n += site.want
	end
	return n
end

return TownTreeData
