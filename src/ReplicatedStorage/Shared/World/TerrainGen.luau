--!strict
--!native
-- TerrainGen: the shape and surface of the world, as pure functions of
-- (x, z). Deterministic (math.noise, fixed seeds), so the server's
-- TerrainBuilder, every client (ambient life finds the ground without
-- raycasts) and the preview tool all agree on every height.
--
--   HeightAt(x, z)          ground height in studs (y)
--   Sample(x, z)            height, surface material name, water surface?
--   WaterLevelAt(x, z)      water surface over this column, or nil
--
-- What shapes the land (WorldLayout has the places, BiomeData the biomes):
--   * rolling countryside everywhere, a few studs of gentle noise;
--   * flat building zones (town, plot district) at exactly y = 0;
--   * roads smoothed to an easy grade with the bumps taken out;
--   * per biome: gentle Starter Forest, rolling Hills, the raised
--     Snowfields plateau, the Volcano's basalt shelf and cone (a level lava
--     pool in its crater), the Gloam Hollow's hidden hollow behind a ring
--     of ridges;
--   * the river, Mirror Lake, the pond and the east coast cut below water;
--   * mountains framing the north, west and south edges.

local BiomeData = require(script.Parent.Parent.BiomeData)
local WorldLayout = require(script.Parent.WorldLayout)
local UndergroundData = require(script.Parent.UndergroundData)

local TerrainGen = {}

-- True only while the first 322 trees are placed, so they keep the roads
-- and the land they were saved against. The live world (wider roads, the
-- mill road and lot loop, junction flares, cliff rings, hollow pools) is
-- what everything else sees.
local legacyLayout = false

function TerrainGen.SetLegacyLayout(on: boolean)
	legacyLayout = on
	WorldLayout.SetLegacyLayout(on)
end

local noise = math.noise
local clamp = math.clamp
local sqrt = math.sqrt

local function smoothstep(t: number): number
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Fractal noise, roughly -1..1.
local function fbm(x: number, z: number, freq: number, octaves: number, seed: number): number
	local sum, amp, f, norm = 0, 1, freq, 0
	for i = 1, octaves do
		sum += noise(x * f + seed * 17.3, z * f - seed * 9.1, seed * 0.731 + i * 0.37) * amp
		norm += amp
		amp *= 0.5
		f *= 2.03
	end
	return sum / norm * 2
end

-- 1 inside radius r of (cx, cz), fading to 0 over `falloff` studs beyond.
local function circleWeight(x: number, z: number, cx: number, cz: number, r: number, falloff: number): number
	local dx, dz = x - cx, z - cz
	local d = sqrt(dx * dx + dz * dz)
	return smoothstep(1 - (d - r) / falloff)
end

type Area = { x: number, z: number, radius: number }
local function area(id: string): Area
	local def = BiomeData.Get(id)
	local a = if def then def.area else nil
	return if a then { x = a.x, z = a.z, radius = a.radius } else { x = 1e6, z = 1e6, radius = 1 }
end

local STARTER, HILLS, SNOW, VOLCANO, GROVE, SKY =
	area("starter"), area("hills"), area("snow"), area("volcano"), area("grove"), area("sky")

local HALF = WorldLayout.WorldHalf
local CONE = WorldLayout.VolcanoCone
local RIDGE = WorldLayout.GroveRidge
local MOUNT = WorldLayout.Mountains
local COAST = WorldLayout.Coast
local ISLAND = WorldLayout.Island
local LAKE = WorldLayout.Lake
local POND = WorldLayout.Pond
local RIVER = WorldLayout.River
local OUTFLOW = WorldLayout.LakeOutflow
local LAKE_LEVEL = WorldLayout.LakeLevel
local SEA_LEVEL = WorldLayout.SeaLevel

-- Where the grove's ridge opens (toward town, so the curious can find it).
local GROVE_GAP = WorldLayout.GroveGap

local function angleDiff(a: number, b: number): number
	local d = (a - b + math.pi) % (math.pi * 2) - math.pi
	return math.abs(d)
end

-- How far east the shoreline is at this z (it wanders a little).
local function shoreX(z: number): number
	return COAST.shoreX + noise(z / 260, 3.7, 1.9) * 70
end

-- The broad, gentle shape of the land: what roads follow.
local function lowHeight(x: number, z: number): number
	local h = 6 * fbm(x, z, 1 / 720, 2, 23)

	-- Starter Forest: almost flat, a hair above the meadow.
	local ws = circleWeight(x, z, STARTER.x, STARTER.z, STARTER.radius, 70)
	h = h * (1 - ws * 0.8) + ws * 0.6

	-- Hills: raised ground.
	local wh = circleWeight(x, z, HILLS.x, HILLS.z, HILLS.radius, 170)
	h += wh * 10

	-- Snowfields: a plateau, ramping up over a long, drivable approach.
	local wsn = circleWeight(x, z, SNOW.x, SNOW.z, SNOW.radius + 40, 330)
	h += wsn * 26

	-- Volcano: a basalt shelf.
	local wv = circleWeight(x, z, VOLCANO.x, VOLCANO.z, VOLCANO.radius, 220)
	h += wv * 12

	-- The Skyroot's foot: gentle, a little low (the river starts here).
	local wsk = circleWeight(x, z, SKY.x, SKY.z, 150, 160)
	h = h * (1 - wsk * 0.6) + wsk * 1

	return h
end

-- Homestead shelves sit on the broad shape, not in a hole at y = 0.
for _, zone in ipairs(WorldLayout.FlatZones) do
	if zone.terrace and zone.cx and zone.cz then
		zone.y = lowHeight(zone.cx, zone.cz)
	end
end

-- Bumps and ridges on top of the broad shape (roads smooth these away).
local function detailHeight(x: number, z: number): number
	local h = 3.2 * fbm(x, z, 1 / 190, 3, 11)

	local ws = circleWeight(x, z, STARTER.x, STARTER.z, STARTER.radius, 70)
	h *= 1 - ws * 0.75

	local wh = circleWeight(x, z, HILLS.x, HILLS.z, HILLS.radius, 140)
	if wh > 0 then
		-- Rounded hills: the absolute value of noise folds it into domes.
		local domes = 1 - math.abs(noise(x / 150, z / 150, 5.5)) * 2
		h += wh * (34 * math.max(0, domes) + 8 * fbm(x, z, 1 / 60, 2, 6))
	end

	local wsn = circleWeight(x, z, SNOW.x, SNOW.z, SNOW.radius, 200)
	if wsn > 0 then
		h += wsn * 5 * fbm(x, z, 1 / 110, 2, 31)
	end

	local wv = circleWeight(x, z, VOLCANO.x, VOLCANO.z, VOLCANO.radius, 160)
	if wv > 0 then
		h += wv * 4 * fbm(x, z, 1 / 70, 2, 41)
	end
	return h
end

-- How much the mountains framing the north, west and south edges lift
-- (x, z).
local function mountainLift(x: number, z: number): number
	local north = (z - MOUNT.start) / (HALF - MOUNT.start)
	local west = (-x - MOUNT.start) / (HALF - MOUNT.start)
	local south = (-z - MOUNT.start) / (HALF - MOUNT.start)
	local east = if z > COAST.northZ + 150 then (x - MOUNT.start) / (HALF - MOUNT.start) else -1
	local m = math.max(north, west, south, east)
	if m <= 0 then
		return 0
	end
	local rough = 0.62 + 0.38 * fbm(x, z, 1 / 160, 3, 61)
	-- Lower behind the volcano, so its cone stands out against the sky.
	local dcx, dcz = x - CONE.x, z - CONE.z
	local nearCone = 1 - smoothstep((sqrt(dcx * dcx + dcz * dcz) - CONE.radius) / 260)
	return smoothstep(m) * MOUNT.peak * rough * (1 - nearCone * 0.65)
end

-- The crater's lava pool: level, at the height the bowl's lowest point
-- (its centre) had, mountains and all.
local POOL_Y = 12
	+ CONE.height * ((1 - CONE.crater / CONE.radius) ^ 1.6)
	- CONE.crater * 1.1
	+ mountainLift(CONE.x, CONE.z)

-- Which ring, if any, is holding (x, z) up, and by how much. Zero inside
-- the pass and off the ring.
local function rimAt(x: number, z: number): (string?, number)
	local kind: string? = nil
	local lift = 0
	for _, rim in ipairs(WorldLayout.Rims) do
		local dx, dz = x - rim.cx, z - rim.cz
		local d = sqrt(dx * dx + dz * dz)
		if d >= rim.inner and d <= rim.outer then
			local t = (d - rim.inner) / (rim.outer - rim.inner)
			local ridge = math.sin(clamp(t, 0, 1) * math.pi) * rim.height
			local open = smoothstep((angleDiff(math.atan2(dz, dx), rim.gap) - rim.half) / (rim.half * 0.45))
			local here = math.max(0, ridge) * open
			if here > lift then
				lift = here
				kind = rim.kind
			end
		end
	end
	return kind, lift
end

local function rimLift(x: number, z: number): number
	local _, lift = rimAt(x, z)
	return lift
end

-- Lane R's reserved pads. The Bayou is a flat basin sunk `sink` studs
-- (7, inside 6–8) below the broad ground on the road just outside the
-- rim, which is the drop a truck drives. Red Mesa is the broad ground at
-- its centre, flattened, with no sink. The rim eases back over 36 studs
-- so the climb stays under 0.2. smoothstep's steepest slope is 1.5, so
-- 7 studs needs more than 7/0.2 studs of run.
local BAYOU_REGION = WorldLayout.Bayou
local MESA_REGION = WorldLayout.RedMesa
local RESERVE_BLEND = 80
TerrainGen.ReserveBlend = RESERVE_BLEND

local function outsideRoad(region: WorldLayout.ReservedRegion): (number, number)
	local roadName = if region.id == "bayou" then "BayouRoad" else "MesaRoad"
	local points: { Vector2 } = {}
	for _, road in ipairs(WorldLayout.Roads) do
		if road.name == roadName then
			points = road.points
		end
	end
	local a, b = points[1], points[#points]
	local want = region.radius + RESERVE_BLEND + 8
	local lo, hi = 0, 1
	for _ = 1, 24 do
		local mid = (lo + hi) / 2
		local x = a.X + (b.X - a.X) * mid
		local z = a.Y + (b.Y - a.Y) * mid
		local d = sqrt((x - region.x) ^ 2 + (z - region.z) ^ 2)
		if d > want then
			lo = mid
		else
			hi = mid
		end
	end
	return a.X + (b.X - a.X) * hi, a.Y + (b.Y - a.Y) * hi
end

local bayouApproachX, bayouApproachZ = outsideRoad(BAYOU_REGION)
local bayouFloor = lowHeight(bayouApproachX, bayouApproachZ) - BAYOU_REGION.sink
local mesaFloor = lowHeight(MESA_REGION.x, MESA_REGION.z) - MESA_REGION.sink

local function applyReserve(
	x: number,
	z: number,
	h: number,
	cx: number,
	cz: number,
	radius: number,
	floor: number
): number
	local dx, dz = x - cx, z - cz
	local d = sqrt(dx * dx + dz * dz)
	if d <= radius then
		return floor
	end
	if d >= radius + RESERVE_BLEND then
		return h
	end
	local w = smoothstep((d - radius) / RESERVE_BLEND)
	return floor * (1 - w) + h * w
end

-- Features that override everything: the volcano cone, the grove hollow,
-- mountains, coast, island.
local TUNNEL_LINE = WorldLayout.FastLine(WorldLayout.TunnelPoints)
local RAVINE_LINE: WorldLayout.FastLine = TUNNEL_LINE
for _, road in ipairs(WorldLayout.Roads) do
	if road.name == "RavineRoad" then
		RAVINE_LINE = WorldLayout.FastLine(road.points)
	end
end

-- Rock over the truck tunnel. The bore stays at least TunnelOverhead above
-- the ceiling. Mouths (the first and last 40 studs) stay open, and both
-- the mouth and the sides ease back over 280 studs so a road that crosses
-- the ridge climbs under 20% instead of hitting a wall.
local function tunnelRidge(x: number, z: number, h: number): number
	local cap = WorldLayout.TunnelWidth / 2
	local shoulder = 280
	local reach = cap + shoulder
	local d = WorldLayout.FastDistance(TUNNEL_LINE, x, z, reach)
	if d >= reach then
		return h
	end
	local pts = WorldLayout.TunnelPoints
	local a, b = pts[1], pts[#pts]
	local da = sqrt((x - a.X) ^ 2 + (z - a.Y) ^ 2)
	local db = sqrt((x - b.X) ^ 2 + (z - b.Y) ^ 2)
	-- The first and last 40 studs are open mouths. Past that the bore is
	-- full height; only the sides ease down, so a crossing road can climb.
	if math.min(da, db) < 40 then
		return h
	end
	local roof = WorldLayout.TunnelFloorY + WorldLayout.TunnelHeight + WorldLayout.TunnelOverhead
	local sideW = if d <= cap then 1 else 1 - smoothstep((d - cap) / shoulder)
	if sideW <= 0 then
		return h
	end
	return h * (1 - sideW) + math.max(h, roof) * sideW
end

local function ravineAlong(x: number, z: number): number
	local pts = RAVINE_LINE.segs
	local bestD, bestAlong, acc = 1e12, 0, 0
	local total = 0
	for i = 1, #pts, 4 do
		local ax, az, bx, bz = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
		local abx, abz = bx - ax, bz - az
		local len = math.sqrt(abx * abx + abz * abz)
		local len2 = len * len
		local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
		local dx, dz = x - (ax + abx * t), z - (az + abz * t)
		local d2 = dx * dx + dz * dz
		if d2 < bestD then
			bestD = d2
			bestAlong = acc + len * t
		end
		acc += len
		total = acc
	end
	if total < 1 then
		return 0
	end
	return math.clamp(bestAlong / total, 0, 1)
end

-- The Gloam ravine: 72 wide, 48 deep. The road down wins over the floor cut
-- so a truck can grade into it (under 12 degrees on this length).
local function ravineCut(x: number, z: number, h: number): number
	local dx, dz = x - GROVE.x, z - GROVE.z
	if dx * dx + dz * dz < 36 * 36 then
		h = math.min(h, -48)
	end
	local half = 14
	local shoulder = 28
	local dRoad = WorldLayout.FastDistance(RAVINE_LINE, x, z, half + shoulder)
	if dRoad < half + shoulder then
		local along = ravineAlong(x, z)
		local ramp = 6 + (-48 - 6) * along
		-- The first stretch eases out of the ground the road arrives on,
		-- so the south link doesn't fall off a step where the ravine starts.
		local ease = smoothstep(clamp(along / 0.18, 0, 1))
		ramp = h * (1 - ease) + ramp * ease
		local w = if dRoad <= half then 1 else 1 - smoothstep((dRoad - half) / shoulder)
		h = h * (1 - w) + ramp * w
	end
	return h
end

-- Rock over a covered cave. Mouths and the grotto skylight stay open.
local function caveRoof(x: number, z: number, h: number): number
	local mouth = UndergroundData.MineMouth
	if (x - mouth.x) ^ 2 + (z - mouth.z) ^ 2 < 24 * 24 then
		return h
	end
	for _, rubble in ipairs(UndergroundData.Rubble) do
		if rubble.y > -8 and (x - rubble.x) ^ 2 + (z - rubble.z) ^ 2 < 22 * 22 then
			return h
		end
	end
	local grotto = UndergroundData.Cave("grotto")
	for _, c in ipairs(UndergroundData.Caves) do
		local covered = math.abs(x - c.x) <= c.sx / 2 and math.abs(z - c.z) <= c.sz / 2
		local skylight = grotto ~= nil and c.id == grotto.id and (x - c.x) ^ 2 + (z - c.z) ^ 2 < 14 * 14
		if covered and not skylight then
			h = math.max(h, c.floorY + c.height + UndergroundData.CeilingRock)
		end
	end
	return h
end

local function landmarks(x: number, z: number, h: number): number
	-- Volcano cone with a crater.
	local dx, dz = x - CONE.x, z - CONE.z
	local d = sqrt(dx * dx + dz * dz)
	if d < CONE.radius then
		local t = 1 - d / CONE.radius
		local cone = 12 + CONE.height * (t ^ 1.6) + noise(x / 30, z / 30, 4.2) * 6 * t
		if d < CONE.crater then
			cone = 12 + CONE.height * ((1 - CONE.crater / CONE.radius) ^ 1.6) - (CONE.crater - d) * 1.1
		end
		h = math.max(h, cone)
	end

	-- Gloam Hollow: a hollow behind a ring of ridges, open toward town.
	dx, dz = x - GROVE.x, z - GROVE.z
	d = sqrt(dx * dx + dz * dz)
	if d < GROVE.radius + 10 then
		local w = smoothstep((GROVE.radius + 10 - d) / 30)
		h = h * (1 - w) + (-3 + noise(x / 40, z / 40, 7.7) * 1.5) * w
	elseif d < RIDGE.outer then
		local t = (d - RIDGE.inner) / (RIDGE.outer - RIDGE.inner)
		local ridge = math.sin(clamp(t, 0, 1) * math.pi) * RIDGE.height * (0.75 + 0.35 * noise(x / 35, z / 35, 2.2))
		local gap = smoothstep((angleDiff(math.atan2(dz, dx), GROVE_GAP) - RIDGE.gapAngle * 0.5) / RIDGE.gapAngle)
		h += math.max(0, ridge) * gap
	end

	-- Snowfields and Volcano: a ring of cliffs outside the trees, with one
	-- gap where the road comes in. Skipped while the first trees are placed
	-- (they were laid out before the rings existed).
	if not legacyLayout then
		h += rimLift(x, z)
	end

	-- Mountains framing the north, west and south edges.
	h += mountainLift(x, z)

	-- The crater's floor: the level lava pool (MapBuilder's CraterLava
	-- fills it), then a wall climbing to meet the rim, however much the
	-- mountains behind tipped the bowl.
	dx, dz = x - CONE.x, z - CONE.z
	d = sqrt(dx * dx + dz * dz)
	if d < CONE.crater then
		local t = math.max(0, d - CONE.pool) / (CONE.crater - CONE.pool)
		h = POOL_Y + (h - POOL_Y) * t
	end

	-- East coast: beach sloping into the ocean (south of the volcano).
	if z < COAST.northZ then
		local s = shoreX(z)
		local beachStart = s - COAST.beachWidth
		if x > beachStart then
			local fade = smoothstep((COAST.northZ - z) / 120) -- the coast curls in north
			local t = clamp((x - beachStart) / COAST.beachWidth, 0, 1.6)
			local beach = 1 - t * 2.2 - math.max(0, t - 1) * 18
			local seabed = math.max(beach, -16)
			h = h * (1 - fade) + math.min(h, seabed) * fade
		end
	end

	-- The palm island offshore. A solid disc, not a shell: the height is
	-- the crown, and the crust under it (plus the sea bed) fills the bottom.
	dx, dz = x - ISLAND.x, z - ISLAND.z
	d = sqrt(dx * dx + dz * dz)
	if d < ISLAND.radius then
		local t = 1 - d / ISLAND.radius
		h = math.max(h, -12 + (ISLAND.height + 12) * smoothstep(t * 1.6) + noise(x / 20, z / 20, 5.5) * 1.5 * t)
	end

	h = tunnelRidge(x, z, h)
	h = ravineCut(x, z, h)
	h = caveRoof(x, z, h)
	h = applyReserve(x, z, h, BAYOU_REGION.x, BAYOU_REGION.z, BAYOU_REGION.radius, bayouFloor)
	h = applyReserve(x, z, h, MESA_REGION.x, MESA_REGION.z, MESA_REGION.radius, mesaFloor)
	return h
end

-- Roofs again, after a shelf or a blend has had its say. Idempotent: it
-- only lifts, and mouths stay open.
local function cover(x: number, z: number, h: number): number
	return caveRoof(x, z, h)
end

-- Water channels: returns (bed height or nil, water surface or nil, how
-- close to a bank 0..1 for the banks' sand).
type Channel = { line: WorldLayout.FastLine, width: number, depth: number }
local CHANNELS: { Channel } = {
	{ line = WorldLayout.FastLine(RIVER.points), width = RIVER.width, depth = RIVER.depth },
	{ line = WorldLayout.FastLine(OUTFLOW.points), width = OUTFLOW.width, depth = OUTFLOW.depth },
}
local POOLS = { LAKE, POND }
for _, pool in ipairs(WorldLayout.Pools) do
	table.insert(POOLS, pool)
end

local function water(x: number, z: number): (number?, number?, number)
	local bestBed: number? = nil
	local surface: number? = nil
	local bank = 0
	for _, ch in ipairs(CHANNELS) do
		local cap = ch.width / 2 + 14
		local d = WorldLayout.FastDistance(ch.line, x, z, cap)
		if d < cap then
			local half = ch.width / 2 + noise(x / 50, z / 50, 9.3) * 3
			if d < half then
				local t = d / half
				local bed = LAKE_LEVEL - ch.depth * (1 - t * t)
				bestBed = if bestBed then math.min(bestBed, bed) else bed
				surface = LAKE_LEVEL
			end
			bank = math.max(bank, 1 - clamp((d - half) / 8, 0, 1))
		end
	end
	for _, pool in ipairs(POOLS) do
		local dx, dz = x - pool.x, z - pool.z
		local reach = pool.radius * 1.15 + 9
		if dx * dx + dz * dz < reach * reach then
			local d = sqrt(dx * dx + dz * dz)
			local r = pool.radius * (1 + noise(x / 60, z / 60, 3.1) * 0.12)
			if d < r then
				local t = d / r
				local bed = LAKE_LEVEL - pool.depth * (1 - t * t)
				bestBed = if bestBed then math.min(bestBed, bed) else bed
				surface = LAKE_LEVEL
			end
			bank = math.max(bank, 1 - clamp((d - r) / 7, 0, 1))
		end
	end
	-- Shallow bowls in the Gloam Hollow. Their surface sits under the
	-- hollow's floor, so the banks stay dry and Mud (no lake-bank lift).
	if not legacyLayout then
		for _, pool in ipairs(WorldLayout.GrovePools) do
			local dx, dz = x - pool.x, z - pool.z
			local reach = pool.radius
			if dx * dx + dz * dz < reach * reach then
				local d = sqrt(dx * dx + dz * dz)
				local t = d / reach
				local surfaceY = -4.2
				local bed = surfaceY - pool.depth * (1 - t * t)
				bestBed = if bestBed then math.min(bestBed, bed) else bed
				surface = surfaceY
			end
		end
	end
	return bestBed, surface, bank
end

-- How near (0..1) the nearest road is: 1 on it, fading over its shoulder;
-- and 1 if (x, z) is on the road surface itself.
type FastRoad = { line: WorldLayout.FastLine, half: number }
local ROADS: { FastRoad } = {}
for _, road in ipairs(WorldLayout.Roads) do
	table.insert(ROADS, { line = WorldLayout.FastLine(road.points), half = road.width / 2 })
end

-- Widths from before phase 12's roads. The mill road, the lot loop and the
-- junction flares are new, so they are absent here.
local LEGACY_WIDTH: { [string]: number } = {
	ForestPath = 10,
	HillsRoad = 14,
	SnowRoad = 14,
	VolcanoRoad = 14,
	SkyrootRoad = 12,
	PlotRoad = 10,
	PlotLane = 8,
}
local LEGACY_ROADS: { FastRoad } = {}
for _, road in ipairs(WorldLayout.Roads) do
	local width = LEGACY_WIDTH[road.name]
	-- Plot roads moved with the 3×4 district. The first trees still see the
	-- old polylines (WorldLayout.LegacyPlotRoads), not these.
	if width and road.name ~= "PlotRoad" and road.name ~= "PlotLane" then
		table.insert(LEGACY_ROADS, { line = WorldLayout.FastLine(road.points), half = width / 2 })
	end
end
for _, road in ipairs(WorldLayout.LegacyPlotRoads) do
	table.insert(LEGACY_ROADS, { line = WorldLayout.FastLine(road.points), half = road.width / 2 })
end

local function roadsNow(): { FastRoad }
	return if legacyLayout then LEGACY_ROADS else ROADS
end

local function considerRoad(
	best: number,
	onRoad: number,
	half: number,
	d: number,
	x: number,
	z: number
): (number, number)
	local cap = half + 23
	if d < cap then
		best = math.max(best, smoothstep(1 - (d - half) / 22))
		if d < half + noise(x / 9, z / 9, 6.6) * 1.2 then
			onRoad = 1
		end
	end
	return best, onRoad
end

local function roadWeight(x: number, z: number): (number, number)
	local best = 0
	local onRoad = 0
	for _, road in ipairs(roadsNow()) do
		local cap = road.half + 23
		local d = WorldLayout.FastDistance(road.line, x, z, cap)
		best, onRoad = considerRoad(best, onRoad, road.half, d, x, z)
	end
	if not legacyLayout then
		for _, junction in ipairs(WorldLayout.Junctions) do
			local dx, dz = x - junction.at.X, z - junction.at.Y
			local d = sqrt(dx * dx + dz * dz)
			best, onRoad = considerRoad(best, onRoad, junction.radius, d, x, z)
		end
	end
	return best, onRoad
end

-- Every road, path and street is light grey gravel its whole width (the
-- Lumber Tycoon 2 look Connor asked for, 7 October 2026: grey speckled
-- gravel, never brown dirt). GravelMaterial is a terrain material of its
-- own that nothing else uses, so its colour (MaterialColors) belongs to
-- the roads alone. Asphalt, not Pavement: its fine, flecked grain reads as
-- gravel where Pavement reads as slabs. It is one name to change if Studio
-- shows it too dark. Material only: no height reads it.
TerrainGen.GravelMaterial = WorldLayout.RoadMaterial

-- How far (x, z) is from the edge of the nearest road (negative = on it).
function TerrainGen.RoadClearance(x: number, z: number): number
	local best = math.huge
	for _, road in ipairs(roadsNow()) do
		local d = WorldLayout.FastDistance(road.line, x, z, road.half + 60) - road.half
		if d < best then
			best = d
		end
	end
	if not legacyLayout then
		for _, junction in ipairs(WorldLayout.Junctions) do
			local dx, dz = x - junction.at.X, z - junction.at.Y
			local d = sqrt(dx * dx + dz * dz) - junction.radius
			if d < best then
				best = d
			end
		end
	end
	return best
end

-- Rise over run at (x, z), from the heights 3 studs either side.
function TerrainGen.SlopeAt(x: number, z: number): number
	local h = TerrainGen.HeightAt(x, z)
	return math.max(
		math.abs(TerrainGen.HeightAt(x + 3, z) - h),
		math.abs(TerrainGen.HeightAt(x, z + 3) - h),
		math.abs(TerrainGen.HeightAt(x - 3, z) - h),
		math.abs(TerrainGen.HeightAt(x, z - 3) - h)
	) / 3
end

-- Ground height before a homestead lane is graded. A lane is a ramp from
-- the shelf to the road it meets: the country under it can bump, and a
-- truck still climbs at the ramp's slope.
local LAKE_BASIN = 90

local function groundHeight(x: number, z: number): (number, number?)
	local low = lowHeight(x, z)
	local detail = detailHeight(x, z)
	local rw = roadWeight(x, z)
	local h = low + detail * (1 - rw)
	h = landmarks(x, z, h)

	-- Mirror Lake sits in a gentle bowl on the Hills' west slope (ring
	-- map), so its shore is a walkable bank and its dock a step, not a cliff.
	local ldx, ldz = x - LAKE.x, z - LAKE.z
	local lakeEdge = LAKE.radius * 1.15 + 9
	local ld2 = ldx * ldx + ldz * ldz
	if ld2 < (lakeEdge + LAKE_BASIN) ^ 2 then
		local w = 1 - smoothstep((sqrt(ld2) - lakeEdge) / LAKE_BASIN)
		h = h * (1 - w) + (LAKE_LEVEL + 2.5) * w
	end

	-- Banks sit just above the water; channels are cut below it.
	local bed, surface, bank = water(x, z)
	if bank > 0 then
		local banked = math.max(LAKE_LEVEL + 0.7, math.min(h, LAKE_LEVEL + 2.5))
		h = h * (1 - bank) + banked * bank
	end
	if bed and surface then
		h = math.min(h, bed)
	end

	-- Building zones are perfectly flat. Town pulls to 0; a homestead
	-- pulls to its shelf. A shelf's blend must not fill a pond or a river.
	local flat, target = WorldLayout.FlatAt(x, z)
	local coneDx, coneDz = x - CONE.x, z - CONE.z
	local inCone = coneDx * coneDx + coneDz * coneDz < CONE.radius * CONE.radius
	-- A yard's blend must not tip the lava pool or pave the cone.
	if flat > 0 and not (bed and surface) and not inCone then
		h = h * (1 - flat) + target * flat
	end
	return h, bed
end

type SpurGrade = {
	points: { Vector2 },
	half: number,
	ha: number,
	hb: number,
	total: number,
	-- The same points as plain numbers (x, z, x, z, ...) and their box, so
	-- the per-sample chord test doesn't read Vector2s (slow) or run when
	-- the point is nowhere near.
	flat: { number },
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
local SPUR_GRADE: { SpurGrade } = {}
for _, road in ipairs(WorldLayout.Roads) do
	if road.name == "PlotSpur" and #road.points >= 2 then
		local total = 0
		for i = 1, #road.points - 1 do
			total += (road.points[i + 1] - road.points[i]).Magnitude
		end
		local a, b = road.points[1], road.points[#road.points]
		if total > 1 then
			local flat: { number } = {}
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(road.points) do
				table.insert(flat, p.X)
				table.insert(flat, p.Y)
				minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
				minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
			end
			table.insert(SPUR_GRADE, {
				points = road.points,
				half = road.width / 2,
				ha = groundHeight(a.X, a.Y),
				hb = groundHeight(b.X, b.Y),
				total = total,
				flat = flat,
				minX = minX,
				maxX = maxX,
				minZ = minZ,
				maxZ = maxZ,
			})
		end
	end
end

local function spurChord(x: number, z: number): number?
	local bestH: number? = nil
	local bestD = math.huge
	for _, spur in ipairs(SPUR_GRADE) do
		local along, dist = 0, math.huge
		local acc = 0
		local half = spur.half
		-- Outside the box grown by half, no point of the spur is within it.
		if x < spur.minX - half or x > spur.maxX + half or z < spur.minZ - half or z > spur.maxZ + half then
			continue
		end
		local pts = spur.flat
		for i = 1, #pts - 2, 2 do
			local ax, az, bx, bz = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
			local abx, abz = bx - ax, bz - az
			local len2 = abx * abx + abz * abz
			local len = math.sqrt(len2)
			local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (ax + abx * t), z - (az + abz * t)
			local d2 = dx * dx + dz * dz
			if d2 < dist then
				dist = d2
				along = acc + len * t
			end
			acc += len
		end
		if dist < spur.half * spur.half and dist < bestD then
			bestD = dist
			bestH = spur.ha + (spur.hb - spur.ha) * (along / spur.total)
		end
	end
	return bestH
end

-- The strip copies the height of the last surveyed column so the entrance
-- at z = 1500 doesn't grow a cliff, and nothing at z <= 1500 moves.
local STRIP_SHELF: number? = nil
local function stripShelf(): number
	local known = STRIP_SHELF
	if known then
		return known
	end
	local shelf = groundHeight(0, WorldLayout.ShelfProbeZ)
	STRIP_SHELF = shelf
	return shelf
end

-- Height of the graded spur, or nil off it. The climb holds SpurCutHeight
-- at the shelf turn so the cut through the north wall stays under the
-- skirt beside it, then rises to the deck top and stays there. The last
-- SpurMeet studs are part of that flat. Nothing past the deck's south end
-- is lifted, so the deck itself stays on the shelf. The approach south of
-- gradeFrom is the existing ground, untouched, which keeps the height
-- fingerprint.
local SPUR_H0: number? = nil
local function spurStartHeight(): number
	local known = SPUR_H0
	if known then
		return known
	end
	local spur = WorldLayout.TollSpur
	local p = spur.points[spur.gradeFrom]
	local h = groundHeight(p.X, p.Y)
	SPUR_H0 = h
	return h
end

local SPUR_ALONG: { number }? = nil
local function spurAlong(): { number }
	local known = SPUR_ALONG
	if known then
		return known
	end
	local spur = WorldLayout.TollSpur
	local pts = spur.points
	local marks: { number } = {}
	local acc = 0
	marks[spur.gradeFrom] = 0
	for i = spur.gradeFrom, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dz = b.X - a.X, b.Y - a.Y
		acc += math.sqrt(dx * dx + dz * dz)
		marks[i + 1] = acc
	end
	SPUR_ALONG = marks
	return marks
end

local function spurHeightAt(along: number): number
	local marks = spurAlong()
	local spur = WorldLayout.TollSpur
	local h0 = spurStartHeight()
	local low = WorldLayout.SpurCutHeight
	local top = stripShelf() + WorldLayout.BridgeDeckThick
	local aLow = marks[spur.lowAt]
	local aTop = marks[spur.topAt]
	if along >= aTop or aTop - aLow <= 1e-6 then
		return top
	elseif along >= aLow then
		return low + (top - low) * ((along - aLow) / (aTop - aLow))
	elseif aLow <= 1e-6 then
		return low
	end
	return h0 + (low - h0) * (along / aLow)
end

-- The graded suffix of the toll spur as plain numbers (x, z, ...) and its
-- box, built on first use (the spur never changes once WorldLayout loads).
local TOLL_FLAT: { number }? = nil
local TOLL_BOX = { minX = 0, maxX = 0, minZ = 0, maxZ = 0 }
local function tollFlat(): { number }
	local known = TOLL_FLAT
	if known then
		return known
	end
	local spur = WorldLayout.TollSpur
	local pts = spur.points
	local flat: { number } = {}
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for i = spur.gradeFrom, #pts do
		local p = pts[i]
		table.insert(flat, p.X)
		table.insert(flat, p.Y)
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
	end
	TOLL_BOX = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
	TOLL_FLAT = flat
	return flat
end

local function tollChord(x: number, z: number): number?
	local spur = WorldLayout.TollSpur
	local half = spur.width / 2
	local south = WorldLayout.BridgeCenterZ - WorldLayout.BridgeLength / 2
	if z > south + 1e-3 then
		return nil
	end
	local pts = tollFlat()
	local box = TOLL_BOX
	if x < box.minX - half or x > box.maxX + half or z < box.minZ - half or z > box.maxZ + half then
		return nil
	end
	local bestD = math.huge
	local bestAlong = 0
	local acc = 0
	for i = 1, #pts - 2, 2 do
		local ax, az, bx, bz = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
		local abx, abz = bx - ax, bz - az
		local len2 = abx * abx + abz * abz
		local len = math.sqrt(len2)
		local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
		local dx = x - (ax + abx * t)
		local dz = z - (az + abz * t)
		local d2 = dx * dx + dz * dz
		if d2 < bestD then
			bestD = d2
			bestAlong = acc + len * t
		end
		acc += len
	end
	if bestD > half * half then
		return nil
	end
	return spurHeightAt(bestAlong)
end

-- Haul roads (not the homestead lanes, which spurChord already ramps) are
-- held to a grade under 20%. Sampled from the shaped ground, then relaxed
-- so a cliff the road crosses becomes a cut instead of a wall.
local GRADE_CAP = 0.18
type GradedRoad = {
	xs: { number },
	zs: { number },
	hs: { number },
	along: { number },
	half: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
local HAUL_GRADE: { GradedRoad } = {}
local haulHeight: (number, number) -> number?

local function buildHaulGrades()
	for _, road in ipairs(WorldLayout.Roads) do
		local pts = road.points
		local xs: { number } = {}
		local zs: { number } = {}
		local hs: { number } = {}
		local pinned: { [number]: boolean } = {}
		local function push(x: number, z: number)
			local n = #xs
			if n > 0 and math.abs(xs[n] - x) < 1e-3 and math.abs(zs[n] - z) < 1e-3 then
				return
			end
			table.insert(xs, x)
			table.insert(zs, z)
			-- A lane that ends on a haul road takes that road's height, and
			-- the pin keeps the join from stepping off it.
			local onHaul = if road.name == "PlotSpur" then haulHeight(x, z) else nil
			local height = if onHaul then onHaul else groundHeight(x, z)
			local bore = WorldLayout.TunnelWidth / 2
			local td = WorldLayout.FastDistance(TUNNEL_LINE, x, z, bore + 20)
			local pin = onHaul ~= nil
			if td < bore + 20 then
				local ends = WorldLayout.TunnelPoints
				local a, b = ends[1], ends[#ends]
				local da = sqrt((x - a.X) ^ 2 + (z - a.Y) ^ 2)
				local db = sqrt((x - b.X) ^ 2 + (z - b.Y) ^ 2)
				if da >= 40 and db >= 40 then
					local roof = WorldLayout.TunnelFloorY + WorldLayout.TunnelHeight + WorldLayout.TunnelOverhead
					if height < roof then
						height = roof
						pin = true
					end
				end
			end
			table.insert(hs, height)
			if pin then
				pinned[#hs] = true
			end
		end
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			local steps = math.max(1, math.ceil(len / 12))
			for s = 0, steps - 1 do
				local p = a:Lerp(b, s / steps)
				push(p.X, p.Y)
			end
		end
		push(pts[#pts].X, pts[#pts].Y)
		local closed = (pts[1] - pts[#pts]).Magnitude < 1
		local function segLen(i: number): number
			local dx, dz = xs[i + 1] - xs[i], zs[i + 1] - zs[i]
			return math.sqrt(dx * dx + dz * dz)
		end
		local function relax()
			for i = 1, #hs - 1 do
				if not pinned[i + 1] then
					local cap = GRADE_CAP * segLen(i)
					local delta = hs[i + 1] - hs[i]
					if delta > cap then
						hs[i + 1] = hs[i] + cap
					elseif delta < -cap then
						hs[i + 1] = hs[i] - cap
					end
				end
			end
			for i = #hs - 1, 1, -1 do
				if not pinned[i] then
					local cap = GRADE_CAP * segLen(i)
					local delta = hs[i] - hs[i + 1]
					if delta > cap then
						hs[i] = hs[i + 1] + cap
					elseif delta < -cap then
						hs[i] = hs[i + 1] - cap
					end
				end
			end
		end
		for _ = 1, 6 do
			relax()
			if closed and hs[1] ~= nil and hs[#hs] ~= nil then
				local mid = (hs[1] + hs[#hs]) * 0.5
				hs[1] = mid
				hs[#hs] = mid
			end
		end
		relax()
		local along = { 0 }
		local acc = 0
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for i = 1, #xs do
			minX, maxX = math.min(minX, xs[i]), math.max(maxX, xs[i])
			minZ, maxZ = math.min(minZ, zs[i]), math.max(maxZ, zs[i])
			if i > 1 then
				acc += segLen(i - 1)
				along[i] = acc
			end
		end
		table.insert(HAUL_GRADE, {
			xs = xs,
			zs = zs,
			hs = hs,
			along = along,
			half = road.width / 2,
			minX = minX,
			maxX = maxX,
			minZ = minZ,
			maxZ = maxZ,
		})
	end
end

haulHeight = function(x: number, z: number): number?
	local bestH: number? = nil
	local bestD = math.huge
	for _, g in ipairs(HAUL_GRADE) do
		local half = g.half
		if x < g.minX - half or x > g.maxX + half or z < g.minZ - half or z > g.maxZ + half then
			continue
		end
		local dist = math.huge
		local alongAt = 0
		local xs, zs = g.xs, g.zs
		for i = 1, #xs - 1 do
			local ax, az, bx, bz = xs[i], zs[i], xs[i + 1], zs[i + 1]
			local abx, abz = bx - ax, bz - az
			local len2 = abx * abx + abz * abz
			local len = math.sqrt(len2)
			local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (ax + abx * t), z - (az + abz * t)
			local d2 = dx * dx + dz * dz
			if d2 < dist then
				dist = d2
				alongAt = g.along[i] + len * t
			end
		end
		if dist < half * half and dist < bestD then
			bestD = dist
			local hs, along = g.hs, g.along
			local hAt = hs[#hs]
			for i = 1, #along - 1 do
				if alongAt <= along[i + 1] then
					local span = along[i + 1] - along[i]
					local u = if span > 1e-6 then (alongAt - along[i]) / span else 0
					hAt = hs[i] + (hs[i + 1] - hs[i]) * u
					break
				end
			end
			bestH = hAt
		end
	end
	return bestH
end

buildHaulGrades()

-- Ground height at (x, z), in studs.
function TerrainGen.HeightAt(x: number, z: number): number
	-- Only past the square, and only inside the strip. The fingerprint
	-- grid and every road sample stay on the old heights. The spur's
	-- graded suffix is the one exception, and it misses those samples.
	if WorldLayout.InNorthStrip(x, z) then
		local shelf = stripShelf()
		local graded = haulHeight(x, z)
		if graded then
			return cover(x, z, graded)
		end
		if WorldLayout.InGorge(x, z) then
			return cover(x, z, shelf - WorldLayout.GorgeDepth)
		end
		local spur = tollChord(x, z)
		if spur then
			return cover(x, z, spur)
		end
		return cover(x, z, shelf)
	end
	local h, bed = groundHeight(x, z) -- (its channel bed: water(x, z)'s first value)
	local graded = haulHeight(x, z)
	if graded then
		h = graded
		-- A graded road that clips the bore can land a hair under the roof.
		-- Snap that dust back up so the 16 studs of rock stay put.
		local bore = WorldLayout.TunnelWidth / 2
		local td = WorldLayout.FastDistance(TUNNEL_LINE, x, z, bore)
		if td < bore then
			local ends = WorldLayout.TunnelPoints
			local a, b = ends[1], ends[#ends]
			local da = sqrt((x - a.X) ^ 2 + (z - a.Y) ^ 2)
			local db = sqrt((x - b.X) ^ 2 + (z - b.Y) ^ 2)
			local roof = WorldLayout.TunnelFloorY + WorldLayout.TunnelHeight + WorldLayout.TunnelOverhead
			if da >= 40 and db >= 40 and h < roof then
				h = roof
			end
		end
	end
	if bed and not graded then
		return cover(x, z, h)
	end
	local toll = tollChord(x, z)
	if toll and not graded then
		return cover(x, z, toll)
	end
	local chord = spurChord(x, z)
	if chord and not graded then
		return cover(x, z, chord)
	end
	return cover(x, z, h)
end

-- Water surface above (x, z), or nil if the column is dry.
function TerrainGen.WaterLevelAt(x: number, z: number): number?
	if WorldLayout.InNorthStrip(x, z) then
		return nil
	end
	local h = TerrainGen.HeightAt(x, z)
	local _, surface = water(x, z)
	if surface and h < surface then
		return surface
	end
	if z < COAST.northZ and x > shoreX(z) - COAST.beachWidth * 0.6 and h < SEA_LEVEL then
		return SEA_LEVEL
	end
	if (x - ISLAND.x) ^ 2 + (z - ISLAND.z) ^ 2 < (ISLAND.radius + 90) ^ 2 and h < SEA_LEVEL then
		return SEA_LEVEL
	end
	return nil
end

-- Studs of plain Grass past a homestead's pad (see SurfaceMaterial).
local PLOT_LAWN = 40
TerrainGen.PlotLawn = PLOT_LAWN

-- Surface materials. This runs once per 4-stud column of the whole map
-- (about 560,000 times a build), so it stays cheap: a few math.noise calls,
-- no allocation. Heights never depend on it.

-- Studs over which a biome's edge dithers into the land around it (WLD-13).
local BAND = 80

-- Fine noise for dithering edges: specks a voxel or two across, roughly -1..1.
local function dither(x: number, z: number): number
	return noise(x / 9, z / 9, 21.7) * 0.75 + noise(x / 3.7, z / 3.7, 4.9) * 0.45
end

-- How far inside a biome's edge (r studs from its centre) (x, z) is: 1 at
-- half a band inside the edge or deeper, 0 at half a band outside or
-- further, 0.5 on the edge. Between, the biome's material wins the voxels
-- whose dither is under 0.9w - 0.45 (the dither spreads about +-0.45), a
-- transition material the ones under 1.2w - 0.45, and the land outside the
-- rest: a frayed edge across the whole band, no ring where it ends.
local function inwardness(x: number, z: number, a: Area, r: number): number
	local dx, dz = x - a.x, z - a.z
	local reach = r + BAND / 2
	local d2 = dx * dx + dz * dz
	if d2 >= reach * reach then
		return 0
	end
	return clamp(0.5 - (sqrt(d2) - r) / BAND, 0, 1)
end

-- Grass and LeafyGrass in broad swaths, a finer layer breaking up their
-- edges (so it reads from above and at eye level).
local function swaths(x: number, z: number): string
	local v = noise(x / 90, z / 90, 5.1) + noise(x / 28, z / 28, 7.9) * 0.45
	return if v > 0.22 then "LeafyGrass" else "Grass"
end

local PLOTS: WorldLayout.FlatZone? = nil
for _, zone in ipairs(WorldLayout.FlatZones) do
	if zone.name == "Plots" then
		PLOTS = zone
	end
end

-- The open meadow: swaths of grass, sparse worn patches of bare Ground and
-- a little bare earth at the water's edge. The plot district keeps a plain Grass
-- lawn (its edge dithered into the meadow), and the town's lawn gets the
-- swaths but no bare patches, so its paths stay the only dirt there.
local RIVER_LINE = WorldLayout.FastLine(RIVER.points)

local function meadow(x: number, z: number, flat: number, bank: number): string
	if flat > 0 then
		local plots = PLOTS
		if plots then
			local dx = math.max(plots.x0 - x, 0, x - plots.x1)
			local dz = math.max(plots.z0 - z, 0, z - plots.z1)
			if dx * dx + dz * dz < (plots.blend * (0.55 + 0.4 * dither(x, z))) ^ 2 then
				return "Grass"
			end
		end
		if flat > 0.2 then
			return swaths(x, z)
		end
	end
	if bank > 0.15 and noise(x / 6, z / 6, 2.9) > -0.2 then
		return "Ground" -- damp earth at the water's edge (Mud is the Grove's violet)
	end

	if noise(x / 80, z / 80, 10.3) > 0.45 and dither(x, z) > -0.1 then
		return "Ground"
	end
	-- Under the forest's canopy (FOR-04: WorldLayout.ForestCover over 0.5,
	-- its edge dithered) the floor is LeafyGrass, which grows no grass
	-- blades: cheaper, and no blades poking through the trees. Its worn
	-- patches stay Ground (bare earth under the trees), so whatever stood
	-- on grass before still does (the boulder clusters, the landmarks).
	-- (Only a Grass swath asks: a LeafyGrass one is the forest floor anyway.)
	local swath = swaths(x, z)
	if swath == "Grass" and WorldLayout.ForestCover(x, z) > 0.5 + dither(x, z) * 0.12 then
		return "LeafyGrass"
	end
	return swath
end

-- The surface material (an Enum.Material name) for a column of height h
-- and slope (rise over run).
function TerrainGen.SurfaceMaterial(x: number, z: number, h: number, slope: number): string
	local _, surface, bank = water(x, z)
	if surface and h < surface then
		return if bank > 0.5 then "Sand" else "Mud"
	end
	-- Coast and island. A homestead on the coast keeps its lawn (the pad
	-- and PlotLawn round it) down to the water; the beach runs either side.
	if z < COAST.northZ and x > shoreX(z) - COAST.beachWidth - 6 then
		if not WorldLayout.NearPlotPad(x, z, PLOT_LAWN) then
			return "Sand"
		end
	end
	if (x - ISLAND.x) ^ 2 + (z - ISLAND.z) ^ 2 < ISLAND.radius ^ 2 then
		return if h > 3 then "LeafyGrass" else "Sand"
	end
	if bank > 0.55 and h < LAKE_LEVEL + 2 then
		return "Sand"
	end

	local _, onRoad = roadWeight(x, z)
	local flat = WorldLayout.FlatWeight(x, z)
	-- Town: the plaza, street and paths (WorldLayout.TownPaint), then gravel
	-- on every road.
	if flat > 0.5 then
		local wobble = noise(x / 6, z / 6, 1.1) * 1.5
		for _, paint in ipairs(WorldLayout.TownPaint) do
			if x > paint.x0 - wobble and x < paint.x1 + wobble and z > paint.z0 - wobble and z < paint.z1 + wobble then
				return paint.material
			end
		end
		for _, floor in ipairs(WorldLayout.TownFloors) do
			if x > floor.x0 - wobble and x < floor.x1 + wobble and z > floor.z0 - wobble and z < floor.z1 + wobble then
				return floor.material
			end
		end
		-- A homestead's pad is plain Grass, whichever region it sits in (flat
		-- over 0.85 reaches a few studs past the pad). The raised dark grey
		-- build platform (PlotService, Art/PlotPlatform) stands on it.
		if flat > 0.85 and WorldLayout.OnPlotPad(x, z) then
			return "Grass"
		end
	end
	if onRoad > 0 then
		return TerrainGen.GravelMaterial
	end
	local lot = WorldLayout.ParkingLot
	if x > lot.x0 and x < lot.x1 and z > lot.z0 and z < lot.z1 then
		return TerrainGen.GravelMaterial
	end
	-- The cone stays lava and basalt where a yard's lawn reaches it.
	local coneDx, coneDz = x - CONE.x, z - CONE.z
	local dcone = sqrt(coneDx * coneDx + coneDz * coneDz)
	if dcone < CONE.radius + 10 then
		if dcone < CONE.crater then
			return "CrackedLava"
		end
		return if slope > 0.6 then "Slate" else "Basalt"
	end
	-- Mirror Lake's shore and the river's banks are worn earth (whatever the
	-- biome or a yard's lawn), so the lake dock's and the footbridge's ends
	-- never rest on bladed grass.
	local ldx, ldz = x - LAKE.x, z - LAKE.z
	if ldx * ldx + ldz * ldz < (LAKE.radius * 1.15 + 16) ^ 2 then
		return "Ground"
	end
	local riverReach = RIVER.width / 2 + 12
	if WorldLayout.FastDistance(RIVER_LINE, x, z, riverReach) < riverReach then
		return "Ground"
	end
	-- The lawn round every homestead: plain Grass for PlotLawn studs past
	-- the pad (its edge dithered), whatever the biome. Not on a cliff.
	if slope <= 0.6 and WorldLayout.NearPlotPad(x, z, PLOT_LAWN + dither(x, z) * 6) then
		return "Grass"
	end

	-- Cliff rings: brown rock round the Snowfields, dark stone round the
	-- Volcano. The pass (no lift) keeps whatever the biome paints.
	if not legacyLayout then
		local kind, lift = rimAt(x, z)
		if lift > 8 then
			if kind == "snow" then
				return "Rock"
			elseif kind == "volcano" then
				return if slope > 0.6 then "Slate" else "Basalt"
			end
		end
	end

	-- Mountains: rock, snow on the high north and west peaks.
	if h > 70 and flat <= 0 then
		local north = z > MOUNT.start - 100 or x < -MOUNT.start + 100
		if north and h > 115 + noise(x / 40, z / 40, 8.8) * 20 then
			return "Snow"
		end
		return if slope > 0.55 then "Rock" else swaths(x, z)
	end

	-- Biome edges wander with noise instead of ending in a hard circle,
	-- and dither into their neighbour across a BAND-stud transition.
	local edge = noise(x / 70, z / 70, 13.7) * 60
	local w = inwardness(x, z, SNOW, SNOW.radius + 150 + edge)
	if w > 0 then
		local d = dither(x, z)
		if w >= 1 or d < 0.9 * w - 0.45 then
			return if slope > 0.7 then "Glacier" else "Snow"
		elseif d < 1.2 * w - 0.45 then
			-- The snowline: grass breaking through, rock showing.
			return if noise(x / 16, z / 16, 15.2) > 0.2 then "Rock" else "LeafyGrass"
		end
	end
	w = inwardness(x, z, VOLCANO, VOLCANO.radius + 40 + edge)
	if w > 0 then
		local d = dither(x, z)
		if w >= 1 or d < 0.9 * w - 0.45 then
			if w > 0.5 and noise(x / 55, z / 55, 12.5) > 0.32 then
				return "CrackedLava"
			end
			return if slope > 0.6 then "Slate" else "Basalt"
		elseif d < 1.2 * w - 0.45 then
			-- Scorched earth between the basalt and the grass.
			return "Ground"
		end
	end
	local gdx, gdz = x - GROVE.x, z - GROVE.z
	local gr = GROVE.radius + 6 + edge
	if gdx * gdx + gdz * gdz < gr * gr then
		return if noise(x / 25, z / 25, 3.3) > 0.25 then "Ground" else "Mud"
	end
	w = inwardness(x, z, HILLS, HILLS.radius + 70 + edge)
	if w > 0 and (w >= 1 or dither(x, z) < 0.9 * w - 0.45) then
		if slope > 0.75 then
			return "Rock"
		end
		-- Worn trails, not blotches.
		return if noise(x / 30, z / 30, 2.8) > 0.55 then "Ground" else "LeafyGrass"
	end
	if slope > 0.9 then
		return "Rock"
	end
	local sdx, sdz = x - STARTER.x, z - STARTER.z
	local sr = STARTER.radius + 10 + edge
	if sdx * sdx + sdz * sdz < sr * sr then
		return if noise(x / 30, z / 30, 4.4) > 0.2 then "LeafyGrass" else "Grass"
	end
	return meadow(x, z, flat, bank)
end

-- Height, surface material and water surface (if any) at (x, z).
function TerrainGen.Sample(x: number, z: number): (number, string, number?)
	local h = TerrainGen.HeightAt(x, z)
	local hx = TerrainGen.HeightAt(x + 3, z)
	local hz = TerrainGen.HeightAt(x, z + 3)
	local slope = math.max(math.abs(hx - h), math.abs(hz - h)) / 3
	return h, TerrainGen.SurfaceMaterial(x, z, h, slope), TerrainGen.WaterLevelAt(x, z)
end

-- What one 4-stud voxel of a column holds: solid ground (with how much of
-- it is filled, which is what makes smooth terrain smooth), water, or air.
-- `bottom` is the voxel's lowest y; the column's ground is at `h` and its
-- water surface (if any) at `surface`. A voxel holds one material, so a
-- partly filled bed voxel would leave air between the bed and the water:
-- under water the bed rounds to the voxel grid instead (at least half
-- ground is all ground, less is all water).
function TerrainGen.Voxel(h: number, surface: number?, bottom: number): (string, number)
	local solid = math.clamp((h - bottom) / 4, 0, 1)
	if surface and h < surface then
		if solid >= 0.5 then
			return "solid", 1
		elseif bottom < surface then
			return "water", math.clamp((surface - bottom) / 4, 0, 1)
		end
		return "air", 0
	end
	if solid > 0.02 then
		return "solid", solid
	end
	return "air", 0
end

-- Colours for each terrain material. TerrainBuilder applies them with
-- Terrain:SetMaterialColor; the preview tool paints with them.
-- 7 October 2026 (Connor, from Lumber Tycoon 2 screenshots): the ground
-- reads as LT2's. A flat, vivid, almost cartoon-bright mid-green meadow
-- (phase 12's dark, muted green is gone: Grass was 84,125,55 and LeafyGrass
-- 66,104,46), the forest floor only a step darker, roads and paths in light
-- grey speckled gravel (GravelMaterial), and every earth, cliff and hill
-- face in warm red-brown (Ground was a yellow-brown 150,116,78, Rock a dull
-- 114,92,74). Terrain textures darken their colour in game, so these are
-- brighter than the green they should look. Snow, the volcano, the sand and
-- the Gloam Hollow keep their own colours.
TerrainGen.MaterialColors = {
	Grass = Color3.fromRGB(100, 184, 56),
	LeafyGrass = Color3.fromRGB(82, 158, 48),
	Ground = Color3.fromRGB(142, 108, 74), -- #8E6C4A
	Mud = Color3.fromRGB(90, 74, 62), -- #5A4A3E
	Sand = Color3.fromRGB(216, 198, 154), -- #D8C69A
	Rock = Color3.fromRGB(126, 118, 108), -- #7E766C
	Snow = Color3.fromRGB(238, 243, 247), -- #EEF3F7
	Glacier = Color3.fromRGB(169, 211, 230), -- #A9D3E6
	Basalt = Color3.fromRGB(58, 52, 51), -- #3A3433
	Slate = Color3.fromRGB(91, 86, 80), -- #5B5650
	CrackedLava = Color3.fromRGB(255, 106, 30), -- #FF6A1E
	Cobblestone = Color3.fromRGB(156, 149, 138), -- #9C958A
	-- Every road, path and street (GravelMaterial).
	Asphalt = Color3.fromRGB(168, 164, 156), -- #A8A49C
} :: { [string]: Color3 }

-- What lies under a surface material (cliff faces, the voxels below).
function TerrainGen.SubMaterial(surface: string): string
	if surface == "Grass" or surface == "LeafyGrass" or surface == "Cobblestone" then
		return "Ground"
	elseif surface == "Snow" or surface == "Glacier" then
		return "Rock"
	elseif surface == "CrackedLava" or surface == "Slate" then
		return "Basalt"
	end
	return surface
end

return TerrainGen
