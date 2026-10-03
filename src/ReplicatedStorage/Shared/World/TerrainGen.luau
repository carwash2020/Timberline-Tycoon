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

local TerrainGen = {}

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
local GROVE_GAP = math.atan2(110 - GROVE.z, 0 - GROVE.x)

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

-- Features that override everything: the volcano cone, the grove hollow,
-- mountains, coast, island.
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

	-- The palm island offshore.
	dx, dz = x - ISLAND.x, z - ISLAND.z
	d = sqrt(dx * dx + dz * dz)
	if d < ISLAND.radius then
		local t = 1 - d / ISLAND.radius
		h = math.max(h, -12 + (ISLAND.height + 12) * smoothstep(t * 1.6) + noise(x / 20, z / 20, 5.5) * 1.5 * t)
	end
	return h
end

-- Water channels: returns (bed height or nil, water surface or nil, how
-- close to a bank 0..1 for the banks' sand).
type Channel = { line: WorldLayout.FastLine, width: number, depth: number }
local CHANNELS: { Channel } = {
	{ line = WorldLayout.FastLine(RIVER.points), width = RIVER.width, depth = RIVER.depth },
	{ line = WorldLayout.FastLine(OUTFLOW.points), width = OUTFLOW.width, depth = OUTFLOW.depth },
}
local POOLS = { LAKE, POND }

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
	return bestBed, surface, bank
end

-- How near (0..1) the nearest road is: 1 on it, fading over its shoulder;
-- and 1 if (x, z) is on the road surface itself.
type FastRoad = { line: WorldLayout.FastLine, half: number }
local ROADS: { FastRoad } = {}
for _, road in ipairs(WorldLayout.Roads) do
	table.insert(ROADS, { line = WorldLayout.FastLine(road.points), half = road.width / 2 })
end

local function roadWeight(x: number, z: number): (number, number)
	local best = 0
	local onRoad = 0
	for _, road in ipairs(ROADS) do
		local cap = road.half + 23
		local d = WorldLayout.FastDistance(road.line, x, z, cap)
		if d < cap then
			best = math.max(best, smoothstep(1 - (d - road.half) / 22))
			if d < road.half + noise(x / 9, z / 9, 6.6) * 1.2 then
				onRoad = 1
			end
		end
	end
	return best, onRoad
end

-- The haul roads (STY-02): out in the country each haul road is pale grey
-- road its whole width (TerrainGen.GravelMaterial, a terrain material
-- nothing else uses; phase 12 widened phase 10's gravel crown to the whole
-- road), its edge fraying into dirt for GRAVEL_EDGE studs or so at most.
-- In town and the plot district every road stays dirt: the pale road frays
-- into it where the town's flat ground begins. The plot road and lanes and
-- the forest path are dirt too. Material only: no height reads it.
TerrainGen.HaulRoads = { "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }
TerrainGen.GravelMaterial = "Pavement"
local GRAVEL_EDGE = 1 -- studs in from a haul road's edge where its pale surface ends (dirt beyond)
TerrainGen.GravelEdge = GRAVEL_EDGE
local HAUL: { FastRoad } = {}
for _, road in ipairs(WorldLayout.Roads) do
	if table.find(TerrainGen.HaulRoads, road.name) then
		table.insert(HAUL, { line = WorldLayout.FastLine(road.points), half = road.width / 2 })
	end
end

-- Whether (x, z) is on a haul road's pale surface (its edge frayed a
-- little, as the road's own is).
local function onGravel(x: number, z: number): boolean
	for _, road in ipairs(HAUL) do
		local half = road.half - GRAVEL_EDGE
		local d = WorldLayout.FastDistance(road.line, x, z, half + 1)
		if d < half + noise(x / 7, z / 7, 8.2) * 0.8 then
			return true
		end
	end
	return false
end

-- How far (x, z) is from the edge of the nearest road (negative = on it).
function TerrainGen.RoadClearance(x: number, z: number): number
	local best = math.huge
	for _, road in ipairs(ROADS) do
		local d = WorldLayout.FastDistance(road.line, x, z, road.half + 60) - road.half
		if d < best then
			best = d
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

-- Ground height at (x, z), in studs.
function TerrainGen.HeightAt(x: number, z: number): number
	local low = lowHeight(x, z)
	local detail = detailHeight(x, z)
	local rw = roadWeight(x, z)
	local h = low + detail * (1 - rw)
	h = landmarks(x, z, h)

	-- Banks sit just above the water; channels are cut below it.
	local bed, surface, bank = water(x, z)
	if bank > 0 then
		local banked = math.max(LAKE_LEVEL + 0.7, math.min(h, LAKE_LEVEL + 2.5))
		h = h * (1 - bank) + banked * bank
	end
	if bed and surface then
		h = math.min(h, bed)
	end

	-- Building zones are perfectly flat at 0.
	local flat = WorldLayout.FlatWeight(x, z)
	if flat > 0 then
		h = h * (1 - flat)
	end
	return h
end

-- Water surface above (x, z), or nil if the column is dry.
function TerrainGen.WaterLevelAt(x: number, z: number): number?
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
	-- Coast and island.
	if z < COAST.northZ and x > shoreX(z) - COAST.beachWidth - 6 then
		return "Sand"
	end
	if (x - ISLAND.x) ^ 2 + (z - ISLAND.z) ^ 2 < ISLAND.radius ^ 2 then
		return if h > 3 then "LeafyGrass" else "Sand"
	end
	if bank > 0.55 and h < LAKE_LEVEL + 2 then
		return "Sand"
	end

	local _, onRoad = roadWeight(x, z)
	local flat = WorldLayout.FlatWeight(x, z)
	-- Town: the plaza, street and paths (WorldLayout.TownPaint), then dirt
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
	end
	if onRoad > 0 then
		-- Out in the country a haul road is pale road its whole width
		-- (STY-02), fraying into dirt where the town's flat ground begins.
		if flat < 0.35 + 0.2 * dither(x, z) and onGravel(x, z) then
			return TerrainGen.GravelMaterial
		end
		return "Ground"
	end
	local lot = WorldLayout.ParkingLot
	if x > lot.x0 and x < lot.x1 and z > lot.z0 and z < lot.z1 then
		return "Ground"
	end

	-- The volcano's cone: dark rock, a lava-filled crater (checked before
	-- the mountains, so its peak never gets a snow cap).
	local dcone = sqrt((x - CONE.x) ^ 2 + (z - CONE.z) ^ 2)
	if dcone < CONE.radius + 10 then
		if dcone < CONE.crater then
			return "CrackedLava"
		end
		return if slope > 0.6 then "Slate" else "Basalt"
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

-- Colours for each terrain material in the cozy palette (GAME_DESIGN §13).
-- TerrainBuilder applies them with Terrain:SetMaterialColor; the preview
-- tool paints with them. STY-01 (phase 10) moved the land a little toward
-- the classic lumber-game look: a deeper meadow green (Grass was 116,170,74 and
-- LeafyGrass 86,140,62) and brown rock for the mountains, cliffs and
-- snowline (Rock was a grey 128,122,114). Phase 12 (ATMOS) took the meadow
-- on to a dark, muted green (Grass was 100,152,64 and LeafyGrass 76,126,54;
-- both about 17% darker and a little less saturated now, the same hue) and
-- the rock a touch darker (it was 122,98,78), so the cliffs still read
-- against the darker grass.
TerrainGen.MaterialColors = {
	Grass = Color3.fromRGB(84, 125, 55),
	LeafyGrass = Color3.fromRGB(66, 104, 46),
	Ground = Color3.fromRGB(150, 116, 78),
	Mud = Color3.fromRGB(64, 50, 72), -- the Gloam Hollow's violet floor
	Sand = Color3.fromRGB(226, 205, 150),
	Rock = Color3.fromRGB(114, 92, 74),
	Snow = Color3.fromRGB(238, 244, 250),
	Glacier = Color3.fromRGB(172, 214, 236),
	Basalt = Color3.fromRGB(52, 46, 44),
	Slate = Color3.fromRGB(74, 66, 62),
	CrackedLava = Color3.fromRGB(255, 108, 30),
	Cobblestone = Color3.fromRGB(170, 160, 146),
	-- The haul roads' pale road (GravelMaterial, STY-02): a light, cool grey
	-- (phase 12; it was a beige 182,174,158).
	Pavement = Color3.fromRGB(170, 169, 165),
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
