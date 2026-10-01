--!strict
-- WorldLayout: where things are in the 3,000-stud world (GAME_DESIGN §10),
-- shared by the terrain generator (TerrainGen), MapBuilder, the ambient
-- life on clients and the preview tool. Biome centres and radii stay in
-- BiomeData (the economy model reads their haul distances); this adds the
-- shapes between them: flat building zones, roads, the river and lake,
-- the coast, and the mountains that frame the map.
--
-- Axes: +X is east, +Z is north. The sawmill hub is at (0, 110).

local BiomeData = require(script.Parent.Parent.BiomeData)
local PlotData = require(script.Parent.Parent.PlotData)

local WorldLayout = {}

WorldLayout.WorldHalf = 1500 -- the world runs from -1500 to 1500 on both axes
WorldLayout.Sawmill = Vector3.new(0, 0, 110)
WorldLayout.SeaLevel = -3 -- ocean surface
WorldLayout.LakeLevel = -2 -- river and lake surface

-- A rectangle (x0..x1, z0..z1) the terrain keeps perfectly flat at y = 0,
-- blending back to the countryside over `blend` studs.
export type FlatZone = { name: string, x0: number, x1: number, z0: number, z1: number, blend: number }

-- A road: a dirt track along these points, `width` studs wide; the terrain
-- under it is smoothed so trucks have an easy ride.
export type Road = { name: string, points: { Vector2 }, width: number }

local function plotBounds(): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, slot in ipairs(PlotData.Slots) do
		minX, maxX = math.min(minX, slot.X), math.max(maxX, slot.X)
		minZ, maxZ = math.min(minZ, slot.Y), math.max(maxZ, slot.Y)
	end
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	return minX - half, maxX + half, minZ - half, maxZ + half
end

local px0, px1, pz0, pz1 = plotBounds()

WorldLayout.FlatZones = {
	-- Town: spawn, sawmill, shops, parking, gondola station.
	{ name = "Town", x0 = -125, x1 = 140, z0 = -32, z1 = 205, blend = 45 },
	-- The plot district east of town, with its roads and lanes.
	{ name = "Plots", x0 = px0 - 24, x1 = px1 + 24, z0 = pz0 - 24, z1 = pz1 + 34, blend = 50 },
} :: { FlatZone }

-- Biome centres, for the roads below.
local function center(id: string): Vector2
	local def = BiomeData.Get(id)
	local area = if def then def.area else nil
	return if area then Vector2.new(area.x, area.z) else Vector2.zero
end

local hills, snow, volcano, sky = center("hills"), center("snow"), center("volcano"), center("sky")

WorldLayout.Roads = {
	-- Town to the Starter Forest (south, a short walk).
	{ name = "ForestPath", points = { Vector2.new(0, 20), Vector2.new(-6, -30) }, width = 10 },
	-- West to the Hills, curving past Hearth & Home.
	{
		name = "HillsRoad",
		points = { Vector2.new(-20, 20), Vector2.new(-140, 40), Vector2.new(-230, 90), hills + Vector2.new(120, 0) },
		width = 14,
	},
	-- North from behind the sawmill, up onto the Snowfields plateau.
	{
		name = "SnowRoad",
		points = { Vector2.new(0, 205), Vector2.new(30, 450), Vector2.new(-20, 760), snow - Vector2.new(0, 160) },
		width = 14,
	},
	-- North-east to the Volcano, branching off the snow road.
	{
		name = "VolcanoRoad",
		points = { Vector2.new(30, 450), Vector2.new(380, 640), Vector2.new(760, 900), volcano - Vector2.new(150, 120) },
		width = 14,
	},
	-- West-north-west from the snow road to the Skyroot's foot.
	{
		name = "SkyrootRoad",
		points = { Vector2.new(-20, 760), Vector2.new(-420, 860), Vector2.new(-760, 960), sky + Vector2.new(120, -40) },
		width = 12,
	},
	-- The road along the north side of the plot district.
	{ name = "PlotRoad", points = { Vector2.new(110, pz1 + 10), Vector2.new(px1, pz1 + 10) }, width = 10 },
} :: { Road }

-- Lanes between the plots (in the gaps the biggest tier leaves).
do
	local xs, zs = {}, {}
	for _, slot in ipairs(PlotData.Slots) do
		xs[slot.X], zs[slot.Y] = true, true
	end
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	local minX = px0 + half
	for x in pairs(xs) do
		if x > minX then
			local laneX = x - PlotData.SlotSpacing / 2
			table.insert(
				WorldLayout.Roads,
				{ name = "PlotLane", points = { Vector2.new(laneX, pz1 + 10), Vector2.new(laneX, pz0) }, width = 8 }
			)
		end
	end
	for z in pairs(zs) do
		if z < pz1 - half then
			local laneZ = z + PlotData.SlotSpacing / 2
			table.insert(
				WorldLayout.Roads,
				{ name = "PlotLane", points = { Vector2.new(px0, laneZ), Vector2.new(px1, laneZ) }, width = 8 }
			)
		end
	end
end

-- The parking lot east of the spawn (a gravel lot; MapBuilder paints the
-- slots on it).
WorldLayout.ParkingLot = { x0 = 8, x1 = 112, z0 = -18, z1 = 68 }

-- The town's ground (TerrainGen paints it): a cobbled plaza round the sell
-- pad, packed dirt for the main street, the shop paths, the spawn walk, the
-- mill yard and the gondola path. Edges get a little noise. The first
-- that covers a spot paints it (the plaza's cobbles run across the
-- street). `name` is for the specs: nothing that collides stands on the
-- street, plaza, paths or walk (WorldPlan.spec).
export type Paint = { name: string, x0: number, x1: number, z0: number, z1: number, material: string }
WorldLayout.TownPaint = {
	{ name = "Plaza", x0 = -26, x1 = 26, z0 = 64, z1 = 97, material = "Cobblestone" },
	{ name = "MainStreet", x0 = -96, x1 = 64, z0 = 70, z1 = 84, material = "Ground" },
	{ name = "HearthAndHomePath", x0 = -86, x1 = -74, z0 = 84, z1 = 93, material = "Ground" },
	{ name = "ToolShedPath", x0 = -51, x1 = -39, z0 = 84, z1 = 93, material = "Ground" },
	{ name = "DealershipPath", x0 = 39, x1 = 51, z0 = 84, z1 = 93, material = "Ground" },
	{ name = "SpawnWalk", x0 = -6, x1 = 6, z0 = 34, z1 = 64, material = "Ground" },
	{ name = "MillYard", x0 = -22, x1 = 24, z0 = 97, z1 = 126, material = "Ground" },
	{ name = "GondolaPath", x0 = -31, x1 = -25, z0 = 97, z1 = 142, material = "Ground" },
	{ name = "GondolaPath", x0 = -46, x1 = -25, z0 = 136, z1 = 142, material = "Ground" },
} :: { Paint }

-- The river runs from the pool under the Aether Isles' waterfall, south
-- past the Hills' west side, into Mirror Lake, then out to the west edge.
WorldLayout.River = {
	points = {
		sky + Vector2.new(-20, -110),
		Vector2.new(-930, 760),
		Vector2.new(-820, 480),
		Vector2.new(-770, 200),
		Vector2.new(-800, -60),
	},
	width = 26,
	depth = 7,
}
WorldLayout.Lake = { x = -830, z = -190, radius = 135, depth = 12 }
WorldLayout.LakeOutflow = {
	points = { Vector2.new(-930, -250), Vector2.new(-1200, -320), Vector2.new(-1520, -300) },
	width = 24,
	depth = 6,
}
-- A little pond at the Starter Forest's edge (ducks, lily pads).
WorldLayout.Pond = { x = 78, z = -182, radius = 16, depth = 4 }

-- The east coast: beach then ocean. The coastline wanders with noise; the
-- ocean starts east of `shoreX` south of the volcano.
WorldLayout.Coast = { shoreX = 1190, beachWidth = 70, northZ = 820 }

-- An island offshore (the palmwood teaser; boats come after V1).
WorldLayout.Island = { x = 1395, z = -760, radius = 70, height = 9 }

-- The Volcano's cone sits on the far side of its biome, away from town. Its
-- crater (radius `crater`) has a level lava pool (radius `pool`) in the
-- middle of its floor.
WorldLayout.VolcanoCone =
	{ x = volcano.X + 105, z = volcano.Y + 115, radius = 150, height = 175, crater = 30, pool = 14 }

-- The Phantom Grove sits in a hollow ringed by ridges (no road in).
WorldLayout.GroveRidge = { inner = 132, outer = 205, height = 34, gapAngle = math.rad(35) }

-- Mountains frame the map's north and west edges (a backdrop; the world
-- walls stop players before the steep part).
WorldLayout.Mountains = { start = 1180, peak = 210 }

-- Distance from point p to segment a-b, and how far along it (0..1).
function WorldLayout.SegmentDistance(p: Vector2, a: Vector2, b: Vector2): (number, number)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude, 0
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude, t
end

-- A polyline flattened to numbers for fast distance checks (the terrain
-- asks millions of times while the world builds; Vector2s are slow there).
export type FastLine = {
	segs: { number }, -- ax, az, bx, bz, ... per segment
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

function WorldLayout.FastLine(points: { Vector2 }): FastLine
	local segs: { number } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, #points do
		local p = points[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
		if i < #points then
			local q = points[i + 1]
			table.insert(segs, p.X)
			table.insert(segs, p.Y)
			table.insert(segs, q.X)
			table.insert(segs, q.Y)
		end
	end
	return { segs = segs, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- Distance from (x, z) to a FastLine, or `cap` if it's farther than cap
-- (cheap rejection by bounding box).
function WorldLayout.FastDistance(line: FastLine, x: number, z: number, cap: number): number
	if x < line.minX - cap or x > line.maxX + cap or z < line.minZ - cap or z > line.maxZ + cap then
		return cap
	end
	local best = cap * cap
	local segs = line.segs
	for i = 1, #segs, 4 do
		local ax, az, bx, bz = segs[i], segs[i + 1], segs[i + 2], segs[i + 3]
		local abx, abz = bx - ax, bz - az
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
		local dx, dz = x - (ax + abx * t), z - (az + abz * t)
		local d2 = dx * dx + dz * dz
		if d2 < best then
			best = d2
		end
	end
	return math.sqrt(best)
end

-- Distance from p to a polyline.
function WorldLayout.PolylineDistance(p: Vector2, points: { Vector2 }): number
	local best = math.huge
	for i = 1, #points - 1 do
		local d = WorldLayout.SegmentDistance(p, points[i], points[i + 1])
		if d < best then
			best = d
		end
	end
	return best
end

-- The flat zone containing (x, z), if any, with how deep inside it is
-- (0 at its edge, growing inward), or the nearest zone's outside distance.
function WorldLayout.FlatWeight(x: number, z: number): number
	local weight = 0
	for _, zone in ipairs(WorldLayout.FlatZones) do
		local dx = math.max(zone.x0 - x, 0, x - zone.x1)
		local dz = math.max(zone.z0 - z, 0, z - zone.z1)
		local outside = math.sqrt(dx * dx + dz * dz)
		local w = 1 - math.clamp(outside / zone.blend, 0, 1)
		w = w * w * (3 - 2 * w) -- smoothstep
		if w > weight then
			weight = w
		end
	end
	return weight
end

return WorldLayout
