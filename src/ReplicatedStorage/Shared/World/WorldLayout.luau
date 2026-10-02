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
-- street, plaza, paths or walk (WorldPlan.spec). Patches that meet overlap
-- by a stud or two: edge noise can pull both back, and a seam would grow
-- a strip of grass between them.
export type Paint = { name: string, x0: number, x1: number, z0: number, z1: number, material: string }
WorldLayout.TownPaint = {
	{ name = "Plaza", x0 = -26, x1 = 26, z0 = 64, z1 = 97, material = "Cobblestone" },
	{ name = "MainStreet", x0 = -104, x1 = 64, z0 = 70, z1 = 84, material = "Ground" },
	-- The shop paths lead to each counter (TWN-13: the shops grew 1.5x).
	{ name = "HearthAndHomePath", x0 = -99.5, x1 = -87.5, z0 = 82, z1 = 93, material = "Ground" },
	{ name = "ToolShedPath", x0 = -63, x1 = -51, z0 = 82, z1 = 93, material = "Ground" },
	{ name = "DealershipPath", x0 = 42, x1 = 54, z0 = 82, z1 = 93, material = "Ground" },
	{ name = "SpawnWalk", x0 = -6, x1 = 6, z0 = 34, z1 = 66, material = "Ground" },
	{ name = "MillYard", x0 = -32, x1 = 33, z0 = 95, z1 = 140, material = "Ground" },
	{ name = "GondolaPath", x0 = -39, x1 = -33, z0 = 82, z1 = 142, material = "Ground" },
	{ name = "GondolaPath", x0 = -46, x1 = -33, z0 = 136, z1 = 142, material = "Ground" },
} :: { Paint }

-- Packed dirt under each building, a stud or two past its walls, so the
-- engine's grass (Terrain.Decoration grows on Grass) never pokes up through
-- a shop floor or hides its front (TER-02). The sawmill stands on the
-- MillYard. TerrainGen paints these after TownPaint.
WorldLayout.TownFloors = {
	{ name = "ToolShedFloor", x0 = -73.5, x1 = -38.5, z0 = 88.5, z1 = 119.5, material = "Ground" },
	{ name = "HearthAndHomeFloor", x0 = -110.5, x1 = -74, z0 = 88.5, z1 = 120.5, material = "Ground" },
	{ name = "DealershipFloor", x0 = 35, x1 = 69.5, z0 = 89, z1 = 118, material = "Ground" },
	{ name = "GondolaStationFloor", x0 = -50.5, x1 = -29, z0 = 139, z1 = 160.5, material = "Ground" },
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

---------------------------------------------------------------------------
-- The forest (phase 10, FOR-01): "a forest with the main area open and
-- then the wild landscapes" (Connor). Three bands, as data:
--   * the hub: open lawn round the town (spawn, sawmill, shops, parking)
--     and the plot district, `hub` studs past each side of their flat
--     zones, its edge wandering `hubNoise` either way. The town's own
--     ornamental trees stand in it; nothing else grows there.
--   * the forest ring: canopy from the lawn's edge out to `ring` (give or
--     take `ringNoise`) past it, thickening over `edge` studs at every
--     edge. Noise opens clearings in it (`clearing`), roads cut through it
--     as clear corridors (WorldPlan keeps its trees off them), and the
--     Starter Forest is its front step south of the spawn.
--   * the wild landscapes beyond, and the biomes the ring wraps round:
--     each biome keeps its own ground `wild[id]` studs past its edge (the
--     Phantom Grove past its ridge), so the Hills stay rolling stands, the
--     Snowfields, the Volcano, the grove's hollow and the Skyroot's foot
--     stay themselves; out here only small copses (`copse`) grow. The
--     forest also stops short of the water (`water`), the beach
--     (`coast`) and the mountains (`mountains`), and leaves `lanes` open:
--     the view from the spawn to the lighthouse, and a trail out of the
--     grove's ridge gap toward town.
-- WorldLayout.ForestCover reads it (TerrainGen paints the forest floor,
-- WorldPlan grows the trees). tests/Forest.spec.luau.
---------------------------------------------------------------------------

export type HubPad = { zone: string, west: number, east: number, south: number, north: number }
export type Lane = { name: string, a: Vector2, b: Vector2, half: number }
export type ForestPlan = {
	hub: { HubPad },
	hubNoise: number,
	edge: number,
	ring: number,
	ringNoise: number,
	clearing: { scale: number, fine: number, from: number, soft: number, keep: number },
	wild: { [string]: number },
	water: number,
	coast: number,
	mountains: number,
	lanes: { Lane },
	copse: { scale: number, from: number, soft: number },
}

local grove = center("grove")
-- The grove's ridge opens toward the sawmill (TerrainGen's GROVE_GAP).
local toTown = (Vector2.new(WorldLayout.Sawmill.X, WorldLayout.Sawmill.Z) - grove).Unit
local gapFoot = grove + toTown * (WorldLayout.GroveRidge.inner - 10)

WorldLayout.Forest = {
	hub = {
		-- North of the town the lawn runs past the pine band to about z 315;
		-- west to the Hills' edge; south a strip past the town's edge (the
		-- Starter Forest starts there); east it meets the plot district.
		-- Every pad is at least hubNoise, so the wander never eats a zone.
		{ zone = "Town", west = 80, east = 30, south = 30, north = 110 },
		-- The plot district's lawn: a strip round it, out to the beach east.
		{ zone = "Plots", west = 40, east = 130, south = 50, north = 45 },
	},
	hubNoise = 30,
	edge = 50,
	ring = 600,
	ringNoise = 90,
	-- Noise above `from` opens a clearing (fully open `soft` above it), but
	-- not within `keep` studs of the hub's lawn: the edge facing the town
	-- and the plots stays a wall of trees.
	clearing = { scale = 110, fine = 40, from = 0.1, soft = 0.14, keep = 70 },
	-- Studs past each biome's area the forest keeps off (the grove's from its
	-- ridge's outer foot). The Starter Forest's own trees are its edge.
	wild = { starter = 8, hills = 40, snow = 170, volcano = 140, grove = 25, sky = 90 },
	water = 16, -- studs off the river, its outflow, the lake and the pond
	coast = 130, -- studs inland of the shore line (its wander and the beach inside it)
	mountains = 1170, -- the forest fades out by here (|x| or |z|; the mountains rise at 1180)
	lanes = {
		-- From the spawn to the lighthouse on the coast's headland
		-- (WorldPlan.Lighthouse): its lamp stays in sight (Forest.spec).
		{ name = "LighthouseVista", a = Vector2.new(0, 40), b = Vector2.new(1194, 188), half = 45 },
		-- A trail out of the Phantom Grove's ridge gap toward town, so the
		-- curious still find it.
		{ name = "GroveTrail", a = gapFoot, b = gapFoot + toTown * 300, half = 18 },
	},
	-- Out in the wild landscapes: small copses where this noise is high.
	copse = { scale = 95, from = 0.2, soft = 0.08 },
} :: ForestPlan

local FOREST = WorldLayout.Forest
local noise = math.noise

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The hub's padded rectangles, flattened (x0, x1, z0, z1 each).
local HUB_RECTS: { { number } } = {}
for _, pad in ipairs(FOREST.hub) do
	for _, zone in ipairs(WorldLayout.FlatZones) do
		if zone.name == pad.zone then
			table.insert(
				HUB_RECTS,
				{ zone.x0 - pad.west, zone.x1 + pad.east, zone.z0 - pad.south, zone.z1 + pad.north }
			)
		end
	end
end

-- Each wild biome's disc (x, z, the radius the forest keeps out of).
local WILD_DISCS: { { number } } = {}
for id, margin in pairs(FOREST.wild) do
	local def = BiomeData.Get(id)
	local a = if def then def.area else nil
	if a then -- (the sky's is the Skyroot's foot, under its isles)
		local r = if id == "grove" then WorldLayout.GroveRidge.outer + margin else a.radius + margin
		table.insert(WILD_DISCS, { a.x, a.z, r })
	end
end
table.sort(WILD_DISCS, function(p: { number }, q: { number }): boolean
	return p[1] * 7 + p[2] < q[1] * 7 + q[2] -- a fixed order (pairs isn't)
end)

local WATER_LINES = {
	{ line = WorldLayout.FastLine(WorldLayout.River.points), half = WorldLayout.River.width / 2 + 4 },
	{ line = WorldLayout.FastLine(WorldLayout.LakeOutflow.points), half = WorldLayout.LakeOutflow.width / 2 + 4 },
}
local WATER_POOLS = { WorldLayout.Lake, WorldLayout.Pond }
local LANE_LINES: { { number } } = {}
for _, lane in ipairs(FOREST.lanes) do
	table.insert(LANE_LINES, { lane.a.X, lane.a.Y, lane.b.X, lane.b.Y, lane.half })
end

-- How far (x, z) is outside the hub's lawn (negative inside), before its
-- edge's wander.
function WorldLayout.HubDistance(x: number, z: number): number
	local best = math.huge
	for _, r in ipairs(HUB_RECTS) do
		local dx = math.max(r[1] - x, 0, x - r[2])
		local dz = math.max(r[3] - z, 0, z - r[4])
		local d
		if dx > 0 or dz > 0 then
			d = math.sqrt(dx * dx + dz * dz)
		else
			d = -math.min(x - r[1], r[2] - x, z - r[3], r[4] - z)
		end
		if d < best then
			best = d
		end
	end
	return best
end

-- Distance from (x, z) to segment (ax, az)-(bx, bz), as plain numbers.
local function segment(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
	local dx, dz = x - (ax + abx * t), z - (az + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- The forest's canopy over (x, z), 0 (open) to 1 (deep forest); 0.5 is a
-- forest edge. Also how much (x, z) belongs to the forest ring, clearings
-- and all (0 out in the wild landscapes and in the hub; there `cover`
-- comes from the copses alone). Pure and cheap: TerrainGen asks once per
-- terrain column that reaches the meadow. Roads aren't in it (WorldPlan
-- keeps the trees off them; TerrainGen paints them first).
function WorldLayout.ForestCover(x: number, z: number): (number, number)
	local edge = FOREST.edge
	local wander = noise(x / 130, z / 130, 31.7) * FOREST.hubNoise * 2
	-- The world's edge and the beach first: cheap and often enough final.
	local far = math.max(math.abs(x), math.abs(z))
	local w = smooth((FOREST.mountains - far) / edge)
	if w <= 0 then
		return 0, 0
	end
	local coast = WorldLayout.Coast
	if z < coast.northZ + 150 then
		w = math.min(w, smooth((coast.shoreX - FOREST.coast - x + wander) / edge))
		if w <= 0 then
			return 0, 0
		end
	end
	-- The hub's lawn, then the ring's outer edge.
	local hub = WorldLayout.HubDistance(x, z) + wander
	if hub <= 0 then
		return 0, 0
	end
	local ringEdge = FOREST.ring + noise(x / 320, z / 320, 7.3) * FOREST.ringNoise * 2
	local ring = math.min(smooth(hub / edge), smooth((ringEdge - hub) / edge))
	-- The wild biomes, the water and the lanes stay open.
	local open = w
	for _, d in ipairs(WILD_DISCS) do
		local dx, dz = x - d[1], z - d[2]
		local reach = d[3] + edge
		if dx * dx + dz * dz < reach * reach then
			open = math.min(open, smooth((math.sqrt(dx * dx + dz * dz) - d[3] + wander) / edge))
			if open <= 0 then
				return 0, 0
			end
		end
	end
	local margin = FOREST.water
	for _, water in ipairs(WATER_LINES) do
		local cap = water.half + margin + 20
		local d = WorldLayout.FastDistance(water.line, x, z, cap)
		if d < cap then
			open = math.min(open, smooth((d - water.half - margin) / 20))
		end
	end
	for _, pool in ipairs(WATER_POOLS) do
		local dx, dz = x - pool.x, z - pool.z
		local r = pool.radius * 1.15 + margin
		if dx * dx + dz * dz < (r + 20) ^ 2 then
			open = math.min(open, smooth((math.sqrt(dx * dx + dz * dz) - r) / 20))
		end
	end
	for _, lane in ipairs(LANE_LINES) do
		local d = segment(x, z, lane[1], lane[2], lane[3], lane[4])
		if d < lane[5] + 30 then
			open = math.min(open, smooth((d - lane[5]) / 30))
		end
	end
	if open <= 0 then
		return 0, 0
	end
	ring = math.min(ring, open)
	if ring > 0 then
		local c = FOREST.clearing
		local n = noise(x / c.scale, z / c.scale, 3.9) + noise(x / c.fine, z / c.fine, 9.1) * 0.35
		local wall = smooth((hub - c.keep) / c.keep)
		return ring * (1 - smooth((n - c.from) / c.soft) * wall), ring
	end
	-- Out in the wild landscapes: a copse here and there.
	local k = FOREST.copse
	local n = noise(x / k.scale, z / k.scale, 17.3) + noise(x / 31, z / 31, 2.1) * 0.25
	return open * smooth((n - k.from) / k.soft), 0
end

return WorldLayout
