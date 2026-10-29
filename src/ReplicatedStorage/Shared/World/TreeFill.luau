--!strict
-- TreeFill: the extra trees Connor asked for, appended after every tree
-- WorldPlan already placed. Nothing here moves an existing trunk.
--
-- Biome discs grow to the boot counts in BiomeData (meadow 96, hills 130,
-- frostwood 70, emberwood 60, phantomwood 22). Each wild grove and each
-- country stand grows to 1.5x, rounded down, inside its own disc. Then
-- exactly 120 wild trees, in 30 clumps of 3, 4 and 5, one Wild zone.

local BiomeData = require(script.Parent.Parent.BiomeData)
local ForestLogic = require(script.Parent.Parent.ForestLogic)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local StageOf = require(script.Parent.Parent.StageOf)
local WoodData = require(script.Parent.Parent.WoodData)
local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Parent.Art.Kit)
local PlotData = require(script.Parent.Parent.PlotData)
local TownTreeData = require(script.Parent.Parent.TownTreeData)
local TerrainGen = require(script.Parent.TerrainGen)
local TreeSpreadData = require(script.Parent.TreeSpreadData)
local WorldLayout = require(script.Parent.WorldLayout)

local TreeFill = {}

-- Same shape as WorldPlan.TreeSpot / TreeZone. Defined here so this module
-- does not require WorldPlan (WorldPlan.Trees requires this module).
export type TreeZone = {
	id: string,
	cx: number,
	cz: number,
	radius: number,
	fixed: boolean?,
	cap: number?,
}
export type Spot = {
	woodId: string,
	position: Vector3,
	biome: string,
	zone: TreeZone?,
}

type Shop = { cframe: CFrame }
type SceneryPad = { center: Vector3, radius: number }
type GroveDisc = { cx: number, cz: number, radius: number, count: number }
type Stand = { center: Vector2, radius: number, trees: { Spot } }
type Rock = { position: Vector3, size: number }
type Sign = { cframe: CFrame }

-- Returns are `any`: WorldPlan's tables carry extra fields, and a narrower
-- return type here is not a subtype of those functions.
export type Deps = {
	GoodGround: (x: number, z: number, roadClearance: number?, maxSlope: number?) -> boolean,
	Town: () -> any,
	Scenery: () -> any,
	GroveDiscs: () -> any,
	CountryStands: () -> any,
	Boulders: () -> any,
	MeadowBoulders: () -> any,
	RoadSigns: (text: (biomeId: string) -> string) -> any,
	GateSigns: (text: (biomeId: string) -> string) -> any,
	LandmarkDiscs: () -> any,
	BoulderClusters: () -> any,
}

local deps: Deps? = nil

function TreeFill.Bind(d: Deps)
	deps = d
end

local function world(): Deps
	local d = deps
	if not d then
		error("TreeFill.Bind has not run", 2)
	end
	return d
end

local SCENERY_EDGE = 1150 -- WorldPlan's scenery stays inside this
local TREE_GAP = 10
local ROAD_GAP = 8
local PLOT_GAP = 12
local DOOR_GAP = 20
local HAUL = { HillsRoad = true, SnowRoad = true, VolcanoRoad = true, SkyrootRoad = true }

-- Phone budget: wild clumps stay outside these discs so the trees within
-- 640 studs of spawn, the meadow and the pines don't grow past 1.7x.
local QUIET = {
	{ 0, 40, 640 },
	{ 0, -110, 640 },
	{ -420, 110, 640 },
}

local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local function dist(x: number, z: number, ox: number, oz: number): number
	local dx, dz = x - ox, z - oz
	return math.sqrt(dx * dx + dz * dz)
end

local function outsideBox(x: number, z: number, x0: number, z0: number, x1: number, z1: number): number
	local dx = math.max(x0 - x, 0, x - x1)
	local dz = math.max(z0 - z, 0, z - z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- Shop doors, read once. Town() builds the whole square; don't call it per spot.
local shopDoors: { { number } }? = nil -- x, z
local function shopDoorsOf(): { { number } }
	if shopDoors then
		return shopDoors
	end
	local list: { { number } } = {}
	local town = world().Town() :: { shops: { Shop } }
	for _, shop in ipairs(town.shops) do
		local p = shop.cframe.Position
		table.insert(list, { p.X, p.Z })
	end
	shopDoors = list
	return list
end

-- 12 studs off every plot's biggest footprint, and 20 off the spawn pad
-- and each shop door. Roads are GoodGround's.
-- Each plot's biggest footprint (x0, z0, x1, z1), as plain numbers.
local plotBoxList: { { number } }? = nil
local function plotBoxes(): { { number } }
	local cached = plotBoxList
	if cached then
		return cached
	end
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	local built: { { number } } = {}
	for _, slot in ipairs(PlotData.Slots) do
		table.insert(built, { slot.X - half, slot.Y - half, slot.X + half, slot.Y + half })
	end
	plotBoxList = built
	return built
end

function TreeFill.Clear(x: number, z: number): boolean
	for _, box in ipairs(plotBoxes()) do
		if outsideBox(x, z, box[1], box[2], box[3], box[4]) < PLOT_GAP then
			return false
		end
	end
	if dist(x, z, 0, 40) < DOOR_GAP + 3 then
		return false
	end
	for _, p in ipairs(shopDoorsOf()) do
		if dist(x, z, p[1], p[2]) < DOOR_GAP then
			return false
		end
	end
	return true
end

-- The lists of taken spots only ever grow, so each keeps its X and Z as
-- plain numbers (reading a Vector3's fields is slow), extended on use, and
-- a hash grid of CELL-stud squares (cell key -> the indices inside), so a
-- query looks only at the few squares a `gap`-disc touches instead of at
-- every taken spot. The answer is exactly the linear scan's (TakenNearScan,
-- kept as the reference the spec compares against).
type Flat = { n: number, xs: { number }, zs: { number }, grid: { [number]: { number } } }
local flats: { [{ Vector3 }]: Flat } = setmetatable({}, { __mode = "k" }) :: any
local CELL = 16
local KEY_SPAN = 4096 -- cells per row in the hash key; the world is far smaller
local KEY_BIAS = 2048

-- Work counters (read by the specs, never by the game): how many queries ran,
-- how many spot-to-point distances they measured, and how many times the
-- whole fill was planned (once per world: WorldPlan.Trees caches it).
TreeFill.Stats = { takenNearCalls = 0, takenNearChecks = 0, extraRuns = 0 }

local function cellKey(cx: number, cz: number): number
	return (cx + KEY_BIAS) * KEY_SPAN + (cz + KEY_BIAS)
end

-- The reference: every spot, in order, no grid.
function TreeFill.TakenNearScan(taken: { Vector3 }, x: number, z: number, gap: number): boolean
	local g2 = gap * gap
	for _, p in ipairs(taken) do
		local dx, dz = p.X - x, p.Z - z
		if dx * dx + dz * dz < g2 then
			return true
		end
	end
	return false
end

local function takenNear(taken: { Vector3 }, x: number, z: number, gap: number): boolean
	local g2 = gap * gap
	local flat = flats[taken]
	if not flat then
		flat = { n = 0, xs = {}, zs = {}, grid = {} }
		flats[taken] = flat
	end
	local xs, zs, grid = flat.xs, flat.zs, flat.grid
	local count = #taken
	if flat.n > count then -- (shrunk: start over)
		table.clear(xs)
		table.clear(zs)
		table.clear(grid)
		flat.n = 0
	end
	for i = flat.n + 1, count do
		local p = taken[i]
		local px, pz = p.X, p.Z
		xs[i], zs[i] = px, pz
		local key = cellKey(math.floor(px / CELL), math.floor(pz / CELL))
		local bucket = grid[key]
		if bucket then
			table.insert(bucket, i)
		else
			grid[key] = { i }
		end
	end
	flat.n = count
	local stats = TreeFill.Stats
	stats.takenNearCalls += 1
	local c0x, c1x = math.floor((x - gap) / CELL), math.floor((x + gap) / CELL)
	local c0z, c1z = math.floor((z - gap) / CELL), math.floor((z + gap) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local bucket = grid[cellKey(cx, cz)]
			if bucket then
				stats.takenNearChecks += #bucket
				for _, i in ipairs(bucket) do
					local dx, dz = xs[i] - x, zs[i] - z
					if dx * dx + dz * dz < g2 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Exposed for the specs: the grid's answer on a list.
function TreeFill.TakenNear(taken: { Vector3 }, x: number, z: number, gap: number): boolean
	return takenNear(taken, x, z, gap)
end

-- Scenery was laid out against the original trees. New trunks stay 8 studs
-- off every piece, the same gap the scenery test asks for.
local sceneryPads: { { number } }? = nil
local function sceneryList(): { { number } }
	local cached = sceneryPads
	if cached then
		return cached
	end
	local built: { { number } } = {}
	local spots = world().Scenery() :: { SceneryPad }
	for _, spot in ipairs(spots) do
		table.insert(built, { spot.center.X, spot.center.Z, spot.radius + 8 })
	end
	sceneryPads = built
	return built
end
-- dist(x, z, cx, cz) < r, skipping the square root when a coordinate alone
-- puts the point past r.
local function within(x: number, z: number, cx: number, cz: number, r: number): boolean
	local dx, dz = x - cx, z - cz
	local far = r + 1e-6
	if dx > far or dx < -far or dz > far or dz < -far then
		return false
	end
	return math.sqrt(dx * dx + dz * dz) < r
end

local function sceneryClear(x: number, z: number): boolean
	for _, pad in ipairs(sceneryList()) do
		if within(x, z, pad[1], pad[2], pad[3]) then
			return false
		end
	end
	return true
end

local landmarkPads: { { number } }? = nil
local function landmarkList(): { { number } }
	local cached = landmarkPads
	if cached then
		return cached
	end
	local built = world().LandmarkDiscs() :: { { number } }
	landmarkPads = built
	return built
end

local function landmarkClear(x: number, z: number, extra: number): boolean
	for _, pad in ipairs(landmarkList()) do
		if within(x, z, pad[1], pad[2], pad[3] + extra) then
			return false
		end
	end
	return true
end

-- Loading pads and each homestead's grid of squares (PlotSquare by PlotGrid).
local function yardsClear(x: number, z: number): boolean
	local pads = { WorldLayout.DealershipLoadingPad, WorldLayout.ToolShedLoadingPad }
	for _, pad in ipairs(pads) do
		if outsideBox(x, z, pad.x0, pad.z0, pad.x1, pad.z1) < 1 then
			return false
		end
	end
	local half = GameConfig.PlotSquare * GameConfig.PlotGrid / 2
	for _, home in ipairs(PlotData.Homes) do
		if outsideBox(x, z, home.x - half, home.z - half, home.x + half, home.z + half) < PLOT_GAP then
			return false
		end
	end
	return true
end

-- Boulder clusters (placed against the first trees, so the rocks cannot move:
-- every new trunk gives way, in the rings and everywhere else).
local clusterDiscs: { { number } }? = nil
local function clusterList(): { { number } }
	local cached = clusterDiscs
	if cached then
		return cached
	end
	local built: { { number } } = {}
	local clusters = world().BoulderClusters() :: { { center: Vector3, radius: number } }
	for _, c in ipairs(clusters) do
		table.insert(built, { c.center.X, c.center.Z, c.radius + 10 })
	end
	clusterDiscs = built
	return built
end
local function clusterClear(x: number, z: number): boolean
	for _, d in ipairs(clusterList()) do
		if within(x, z, d[1], d[2], d[3]) then
			return false
		end
	end
	return true
end

-- Boot placement and regrowth share this. A point on a widened haul road,
-- in a loading pad, or on a homestead square is not ground.
function TreeFill.Ground(x: number, z: number): boolean
	if WorldLayout.TreeBlocked(x, z) then
		return false
	end
	-- The forest's lanes stay open: the spawn's view of the lighthouse (the
	-- ring map's lamp is nearer, so a trunk beside the line may no longer hide
	-- under it) and the grove's trail.
	for _, lane in ipairs(WorldLayout.Forest.lanes) do
		if WorldLayout.SegmentDistance(Vector2.new(x, z), lane.a, lane.b) < lane.half then
			return false
		end
	end
	-- Every test is a pure yes or no; the cheap ones go first and the
	-- terrain's (GoodGround) last, since most points fail something cheap.
	return TreeFill.Clear(x, z)
		and clusterClear(x, z)
		and sceneryClear(x, z)
		and landmarkClear(x, z, 0)
		and yardsClear(x, z)
		and world().GoodGround(x, z, ROAD_GAP, 0.75)
end

-- The trunk's plan position sits inside a haul road's paved width.
-- Every haul road's segments with their boxes, so the tests below only
-- measure (the exact way, with Vector2s) the segments the point is near.
type HaulSeg = { a: Vector2, b: Vector2, half: number, minX: number, maxX: number, minZ: number, maxZ: number }
local haulSegs: { HaulSeg }? = nil
local function haulSegments(): { HaulSeg }
	local cached = haulSegs
	if cached then
		return cached
	end
	local built: { HaulSeg } = {}
	for _, road in ipairs(WorldLayout.Roads) do
		if HAUL[road.name] then
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				table.insert(built, {
					a = a,
					b = b,
					half = WorldLayout.PlanWidth(road) / 2,
					minX = math.min(a.X, b.X),
					maxX = math.max(a.X, b.X),
					minZ = math.min(a.Y, b.Y),
					maxZ = math.max(a.Y, b.Y),
				})
			end
		end
	end
	haulSegs = built
	return built
end

-- Whether (x, z) is within `gap` of a haul road's edge (`gap` nil: inside
-- its paved width, 1e-3 in). A segment whose box is farther than
-- half + gap + 1 can't be that close, so only the others are measured.
local function nearHaul(x: number, z: number, gap: number?): boolean
	local p: Vector2? = nil
	for _, seg in ipairs(haulSegments()) do
		local reach = seg.half + (gap or 0) + 1
		if x >= seg.minX - reach and x <= seg.maxX + reach and z >= seg.minZ - reach and z <= seg.maxZ + reach then
			local q = p or Vector2.new(x, z)
			p = q
			local d = WorldLayout.SegmentDistance(q, seg.a, seg.b)
			if if gap then d - seg.half < gap else d < seg.half - 1e-3 then
				return true
			end
		end
	end
	return false
end

function TreeFill.InHaulLane(x: number, z: number): boolean
	return nearHaul(x, z, nil)
end

local function placeOne(
	cx: number,
	cz: number,
	radius: number,
	woodId: string,
	biome: string,
	zone: TreeZone,
	taken: { Vector3 },
	rng: any,
	gap: number,
	pause: (() -> ())?
): Spot?
	local function free(px: number, pz: number): boolean
		-- A spot that cannot be filled walks a whole grid of candidates (a disc
		-- of hundreds of studs at 4 apart): the frame goes back from in here.
		if pause then
			pause()
		end
		return not takenNear(taken, px, pz, gap) and TreeFill.Ground(px, pz)
	end
	local x, z = ForestLogic.FindSpot(cx, cz, radius, 80, function()
		return rng:next()
	end, free)
	if not x or not z then
		-- A last pass on a grid, for a disc the random samples missed.
		local step = 4
		local x0 = cx - radius
		while not x and x0 <= cx + radius do
			local z0 = cz - radius
			while not x and z0 <= cz + radius do
				if dist(x0, z0, cx, cz) <= radius and free(x0, z0) then
					x, z = x0, z0
				end
				z0 += step
			end
			x0 += step
		end
	end
	if not x or not z then
		return nil
	end
	local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
	table.insert(taken, p)
	return { woodId = woodId, position = p, biome = biome, zone = zone }
end

local function woodsNear(c: Vector2): { string }
	local nearest, best = "starter", math.huge
	for _, id in ipairs({ "starter", "hills", "snow", "volcano" }) do
		local def = BiomeData.Get(id)
		local area = if def then def.area else nil
		if area then
			local d = Vector2.new(c.X - area.x, c.Y - area.z).Magnitude - area.radius
			if d < best then
				nearest, best = id, d
			end
		end
	end
	if nearest == "hills" then
		return { "pine", "pine", "maple", "oak" }
	elseif nearest == "snow" or nearest == "volcano" then
		return { "pine", "pine", "birch" }
	end
	return { "oak", "oak", "birch" }
end

local function countOf(spots: { Spot }, zoneId: string, woodId: string?): number
	local n = 0
	for _, s in ipairs(spots) do
		local zone = s.zone
		if zone and zone.id == zoneId and (woodId == nil or s.woodId == woodId) then
			n += 1
		end
	end
	return n
end

-- Extra biome, grove and stand trees, then the 120 wild clumps.
-- `pause` (optional) is called after every placement attempt: a caller that
-- must not freeze a frame (the server planting the forest after players are
-- in, the client's filler plan) passes a time slice that yields when its
-- budget is spent. It changes nothing about the result.
-- `emit` (optional) is handed each batch of spots the moment it is planned,
-- nearest-the-spawn batch first (the town's trees, planned before the slow
-- ones: they were always placed against the existing trees only, so planning
-- them first moves nothing, tests/ClientFreeze.spec), so the server can plant
-- the starter area while the rest of the plan is still being worked out.
function TreeFill.Extra(existing: { Spot }, pause: (() -> ())?, emit: (({ Spot }) -> ())?): { Spot }
	local function tick()
		if pause then
			pause()
		end
	end
	TreeFill.Stats.extraRuns += 1
	local function announce(batch: { Spot })
		if emit and #batch > 0 then
			emit(batch)
		end
	end
	local out: { Spot } = {}
	local taken: { Vector3 } = {}
	for _, s in ipairs(existing) do
		table.insert(taken, s.position)
	end
	local rng = Kit.rng(hashString("tree fill"))
	-- The town's trees first (own rng per site; placed against the existing
	-- trees and each other only, the same trunks as when they came last),
	-- but they join `out` last, so the list's order is as it always was.
	local townSpots = TreeFill.TownRings(taken, pause)
	for _, spot in ipairs(townSpots) do
		table.insert(taken, spot.position)
	end
	announce(townSpots)

	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		local counts = biome.trees
		if area and area.y == nil and counts then
			local woods: { string } = {}
			for woodId in pairs(counts) do
				table.insert(woods, woodId)
			end
			table.sort(woods)
			for _, woodId in ipairs(woods) do
				local have = 0
				for _, s in ipairs(existing) do
					if s.biome == biome.id and s.woodId == woodId then
						have += 1
					end
				end
				for _, s in ipairs(out) do
					if s.biome == biome.id and s.woodId == woodId then
						have += 1
					end
				end
				local zone: TreeZone = {
					id = biome.id,
					cx = area.x,
					cz = area.z,
					radius = area.radius - 6,
				}
				local left = counts[woodId] - have
				local tries = 0
				while left > 0 and tries < left * 40 do
					tries += 1
					tick()
					local spot =
						placeOne(area.x, area.z, area.radius - 6, woodId, biome.id, zone, taken, rng, TREE_GAP, pause)
					if spot then
						table.insert(out, spot)
						left -= 1
					end
				end
			end
		end
	end

	-- WORLD-SPREAD (T366): a few supply trees stand elsewhere in their own zone
	-- (TreeSpreadData.Moved: same wood, biome and zone, same size class), so no
	-- cell holds a blob. `taken` keeps their old spots, so nothing planted after
	-- them moves.
	for _, move in ipairs(TreeSpreadData.Moved) do
		local spot = out[move.index - #existing]
		if spot and spot.zone and spot.biome == spot.zone.id then
			spot.position = Vector3.new(move.x, TerrainGen.HeightAt(move.x, move.z) - 0.3, move.z)
		end
	end
	announce(table.move(out, 1, #out, 1, {}))
	local announced = #out
	local discs = world().GroveDiscs() :: { GroveDisc }
	for index, disc in ipairs(discs) do
		local id = "grove:" .. tostring(index)
		local have = countOf(existing, id, nil) + countOf(out, id, nil)
		local want = math.floor(disc.count * 1.5)
		local zone: TreeZone = { id = id, cx = disc.cx, cz = disc.cz, radius = disc.radius }
		local left = want - have
		local tries = 0
		while left > 0 and tries < left * 40 do
			tries += 1
			tick()
			local woodId = rng:pick(woodsNear(Vector2.new(disc.cx, disc.cz)))
			local spot = placeOne(disc.cx, disc.cz, disc.radius, woodId, "wild", zone, taken, rng, TREE_GAP, pause)
			if spot then
				table.insert(out, spot)
				left -= 1
			end
		end
	end

	local stands = world().CountryStands() :: { Stand }
	for _, stand in ipairs(stands) do
		local sample = stand.trees[1]
		local zone = if sample then sample.zone else nil
		if zone then
			local have = #stand.trees
			for _, s in ipairs(out) do
				if s.zone == zone then
					have += 1
				end
			end
			local want = math.floor(#stand.trees * 1.5)
			local left = want - have
			local tries = 0
			while left > 0 and tries < left * 40 do
				tries += 1
				tick()
				local woodId = rng:pick(woodsNear(stand.center))
				local spot = placeOne(
					stand.center.X,
					stand.center.Y,
					stand.radius,
					woodId,
					"wild",
					zone,
					taken,
					rng,
					TREE_GAP,
					pause
				)
				if spot then
					table.insert(out, spot)
					left -= 1
				end
			end
		end
	end

	announce(table.move(out, announced + 1, #out, 1, {}))
	announced = #out
	local clumps = TreeFill.Clumps(taken, rng, pause)
	for _, spot in ipairs(clumps) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
	end
	announce(clumps)
	-- Last, with their own rng, so nothing above moves: trees round each pad.
	local rings = TreeFill.PlotRings(taken, pause)
	for _, spot in ipairs(rings) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
	end
	announce(rings)
	-- And last of all in the list, the trees in and round the town (planned
	-- first, above).
	for _, spot in ipairs(townSpots) do
		table.insert(out, spot)
	end
	return out
end

-- Trees round each homestead: a few clusters just past the pad's blend
-- (PlotData.Blend, 56), leaning toward the side with the most forest. They
-- are ordinary choppable trees of the region's woods, one regrow zone per
-- cluster, kept off the pad, its blend, lanes and haul roads.
TreeFill.PlotRingNear = 62 -- studs a ring tree keeps off a pad's edge (blend 56 + 6)
TreeFill.PlotRingFar = 100 -- and the farthest a cluster's middle stands
TreeFill.PlotRingMax = 12 -- trees round one pad, all clusters together
TreeFill.PlotRingClusterRadius = 13
local RING_CANDIDATES = 20
local RING_APART = 34

local function quiet(x: number, z: number, pad: number): boolean
	for _, q in ipairs(QUIET) do
		if dist(x, z, q[1], q[2]) < q[3] + pad then
			return false
		end
	end
	return true
end

local function haulClear(x: number, z: number, gap: number): boolean
	return not nearHaul(x, z, gap)
end

local function plotClear(x: number, z: number, gap: number): boolean
	for _, box in ipairs(plotBoxes()) do
		if outsideBox(x, z, box[1], box[2], box[3], box[4]) < gap then
			return false
		end
	end
	return true
end

local function townClear(x: number, z: number): boolean
	if WorldLayout.FlatWeight(x, z) > 0.35 then
		return false
	end
	for _, zone in ipairs(WorldLayout.FlatZones) do
		if zone.name == "Town" and outsideBox(x, z, zone.x0, zone.z0, zone.x1, zone.z1) < 40 then
			return false
		end
	end
	return true
end

local function biomeClear(x: number, z: number): boolean
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		if area and dist(x, z, area.x, area.z) < area.radius + 30 then
			return false
		end
	end
	return true
end

local obstacles: { { number } }? = nil
local function obstacleList(): { { number } }
	local cached = obstacles
	if cached then
		return cached
	end
	local built: { { number } } = {}
	local rocks = world().Boulders() :: { Rock }
	for _, b in ipairs(rocks) do
		table.insert(built, { b.position.X, b.position.Z, b.size / 2 + 8 })
	end
	local meadow = world().MeadowBoulders() :: { Rock }
	for _, b in ipairs(meadow) do
		table.insert(built, { b.position.X, b.position.Z, b.size / 2 + 8 })
	end
	local roads = world().RoadSigns(function(): string
		return ""
	end) :: { Sign }
	for _, sign in ipairs(roads) do
		local p = sign.cframe.Position
		table.insert(built, { p.X, p.Z, 8 })
	end
	local gates = world().GateSigns(function(): string
		return ""
	end) :: { Sign }
	for _, sign in ipairs(gates) do
		local p = sign.cframe.Position
		table.insert(built, { p.X, p.Z, 8 })
	end
	obstacles = built
	return built
end
local function obstacleClear(x: number, z: number): boolean
	for _, o in ipairs(obstacleList()) do
		if within(x, z, o[1], o[2], o[3]) then
			return false
		end
	end
	return true
end

-- Up to PlotRingMax trees round each homestead pad, deterministic (its
-- own Kit.rng). Returns them without touching `taken`.
-- Ring trees also keep off the boulder clusters (placed against the first
-- trees, so the rocks can't move: the trees give way).
function TreeFill.PlotRings(taken: { Vector3 }, pause: (() -> ())?): { Spot }
	local rng = Kit.rng(hashString("plot rings"))
	local out: { Spot } = {}
	local mine: { Vector3 } = {}
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	local r = TreeFill.PlotRingClusterRadius
	for index, slot in ipairs(PlotData.Slots) do
		local cands: { { c: Vector2, score: number } } = {}
		for _ = 1, RING_CANDIDATES do
			if pause then
				pause()
			end
			local a = rng:range(0, math.pi * 2)
			local dx, dz = math.cos(a), math.sin(a)
			local reach = half + rng:range(TreeFill.PlotRingNear + r, TreeFill.PlotRingFar)
			local s = reach / math.max(math.abs(dx), math.abs(dz))
			local x, z = slot.X + dx * s, slot.Y + dz * s
			if
				math.abs(x) <= SCENERY_EDGE
				and math.abs(z) <= SCENERY_EDGE
				and quiet(x, z, 0)
				and plotClear(x, z, TreeFill.PlotRingNear + 4)
				and haulClear(x, z, 20)
				and obstacleClear(x, z)
				and clusterClear(x, z)
				and TreeFill.Ground(x, z)
			then
				local cover = WorldLayout.ForestCover(x, z)
				table.insert(cands, { c = Vector2.new(x, z), score = 0.3 + cover + rng:next() * 0.3 })
			end
		end
		table.sort(cands, function(a, b)
			return a.score > b.score
		end)
		local left = TreeFill.PlotRingMax
		local centers: { Vector2 } = {}
		for _, cand in ipairs(cands) do
			if left <= 0 or #centers >= 4 then
				break
			end
			local near = false
			for _, c in ipairs(centers) do
				if (c - cand.c).Magnitude < RING_APART then
					near = true
				end
			end
			if not near then
				table.insert(centers, cand.c)
				local want = math.min(left, math.clamp(math.floor(1.5 + cand.score * 2.5), 2, 5))
				local zone: TreeZone = {
					id = string.format("plot:%d:%d", index, #centers),
					cx = cand.c.X,
					cz = cand.c.Y,
					radius = r,
					cap = want,
				}
				local woods = woodsNear(cand.c)
				local tries, placed = 0, 0
				while placed < want and tries < want * 25 do
					tries += 1
					if pause then
						pause()
					end
					local a = rng:range(0, math.pi * 2)
					local rr = math.sqrt(rng:next()) * r
					local x, z = cand.c.X + math.cos(a) * rr, cand.c.Y + math.sin(a) * rr
					if
						quiet(x, z, 0) -- the phone discs' tree budget (see QUIET)
						and plotClear(x, z, TreeFill.PlotRingNear)
						and not takenNear(taken, x, z, TREE_GAP)
						and clusterClear(x, z)
						and not takenNear(mine, x, z, TREE_GAP)
						and TreeFill.Ground(x, z)
					then
						local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
						table.insert(mine, p)
						table.insert(out, { woodId = rng:pick(woods), position = p, biome = "wild", zone = zone })
						placed += 1
					end
				end
				left -= placed
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Town trees: choppable trees in and round the spawn area
---------------------------------------------------------------------------

-- Connor (8 October 2026): "we need more choppable trees in the spawn area
-- too, near the pad, by the dealership ... it's a lumberjack game". A site
-- (TownTreeData.Sites) is a small disc: a cluster of ordinary felling trees
-- of the region's woods, biome 'wild', and the regrow zone "town:<site>"
-- with a cap of the cluster's size. They are not in BiomeData's counts (the
-- economy model is unchanged). The town sits inside the phone discs (QUIET
-- does not apply), so TownTreeData's tier counts are its budget.
-- Trees keep off every road, path, floor, building, the parking lot and its
-- pull-outs, the sell area, the spawn lane, shop doors, the Land Office
-- queue, the gondola's lane, the ornamental greenery, the props, lamps,
-- signs and fences, the townsfolk's walks, plots, and steep or wet ground.
-- The same test (TownGround) picks a regrow spot, so a felled tree never
-- grows back onto any of those either.

type Disc = { x: number, z: number, r: number, name: string }
type TownObs = { rects: { TownTreeData.Rect }, discs: { Disc }, lanes: { TownTreeData.Lane } }

local townObs: TownObs? = nil

local function grown(r: TownTreeData.Rect, m: number): TownTreeData.Rect
	return { name = r.name, x0 = r.x0 - m, z0 = r.z0 - m, x1 = r.x1 + m, z1 = r.z1 + m }
end

local function townObstacles(): TownObs
	local cached = townObs
	if cached then
		return cached
	end
	local M = TownTreeData.Margin
	local rects: { TownTreeData.Rect } = {}
	local discs: { Disc } = {}
	local lanes: { TownTreeData.Lane } = {}
	for _, r in ipairs(TownTreeData.Empty) do
		table.insert(rects, r)
	end
	for _, r in ipairs(TownTreeData.Buildings) do
		table.insert(rects, grown(r, M.building))
	end
	table.insert(rects, grown(TownTreeData.Camp, M.camp))
	table.insert(rects, grown(TownTreeData.ParkingLot, M.lot))
	table.insert(rects, grown(TownTreeData.PullOut, M.pullout))
	for _, pad in ipairs({ WorldLayout.DealershipLoadingPad, WorldLayout.ToolShedLoadingPad }) do
		table.insert(
			rects,
			grown({ name = "LoadingPad", x0 = pad.x0, z0 = pad.z0, x1 = pad.x1, z1 = pad.z1 }, M.loading)
		)
	end
	for _, p in ipairs(WorldLayout.TownPaint) do
		table.insert(rects, grown({ name = p.name, x0 = p.x0, z0 = p.z0, x1 = p.x1, z1 = p.z1 }, M.paint))
	end
	for _, p in ipairs(WorldLayout.TownFloors) do
		table.insert(rects, grown({ name = p.name, x0 = p.x0, z0 = p.z0, x1 = p.x1, z1 = p.z1 }, M.floor))
	end

	local town = world().Town() :: any
	for _, cf in ipairs(town.lamps) do
		table.insert(discs, { x = cf.X, z = cf.Z, r = M.lamp, name = "lamp" })
	end
	for _, prop in ipairs(town.props) do
		table.insert(discs, { x = prop.cframe.X, z = prop.cframe.Z, r = M.prop, name = "prop " .. prop.name })
	end
	for _, sign in ipairs(town.signs) do
		table.insert(discs, { x = sign.cframe.X, z = sign.cframe.Z, r = M.sign, name = "sign" })
	end
	for _, fence in ipairs(town.fences) do
		table.insert(discs, { x = fence.cframe.X, z = fence.cframe.Z, r = fence.length / 2 + M.fence, name = "fence" })
	end
	for _, g in ipairs(town.greenery) do
		local r = M.greenery
		if g.kind ~= "tree" then
			r = g.size / 2 + 5
		end
		table.insert(discs, { x = g.cframe.X, z = g.cframe.Z, r = r, name = "greenery " .. g.kind })
	end

	for _, lane in ipairs(TownTreeData.Lanes) do
		table.insert(lanes, lane)
	end
	for _, walk in ipairs(TownTreeData.Walks) do
		local points = walk.points
		local n = #points
		for i = 1, n do
			local a, b = points[i], points[i % n + 1]
			table.insert(
				lanes,
				{ name = "walk " .. walk.id, ax = a[1], az = a[2], bx = b[1], bz = b[2], half = M.walk }
			)
		end
	end
	-- The north yard lane: the old cable's first stretch, same numbers.
	local sky = BiomeData.Get("sky")
	local area = if sky then sky.area else nil
	if area then
		local from = Vector2.new(TownTreeData.NorthYard.x, TownTreeData.NorthYard.z)
		local dir = (Vector2.new(area.x, area.z) - from).Unit
		local to = from + dir * TownTreeData.NorthLaneLength
		table.insert(
			lanes,
			{ name = "north yard", ax = from.X, az = from.Y, bx = to.X, bz = to.Y, half = TownTreeData.NorthLaneHalf }
		)
	end
	local built: TownObs = { rects = rects, discs = discs, lanes = lanes }
	townObs = built
	return built
end

-- The name of what a town tree at (x, z) would stand in the way of, or nil.
function TreeFill.TownBlocker(x: number, z: number): string?
	local obs = townObstacles()
	for _, r in ipairs(obs.rects) do
		if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
			return r.name
		end
	end
	for _, d in ipairs(obs.discs) do
		if within(x, z, d.x, d.z, d.r) then
			return d.name
		end
	end
	local p = Vector2.new(x, z)
	for _, lane in ipairs(obs.lanes) do
		local d = WorldLayout.SegmentDistance(p, Vector2.new(lane.ax, lane.az), Vector2.new(lane.bx, lane.bz))
		if d < lane.half then
			return lane.name
		end
	end
	return nil
end

-- What stops a town tree standing at (x, z), or nil: everything above, the
-- general tree rules except the flat-town exclusion (GoodGround), and gentle,
-- dry ground clear of the roads.
function TreeFill.TownWhy(x: number, z: number): string?
	local blocker = TreeFill.TownBlocker(x, z)
	if blocker then
		return blocker
	end
	if WorldLayout.TreeBlocked(x, z) then
		return "tree-blocked ground"
	elseif not plotClear(x, z, TownTreeData.Margin.plot) then
		return "plot"
	elseif not obstacleClear(x, z) then
		return "boulder or road sign"
	elseif not clusterClear(x, z) then
		return "boulder cluster"
	elseif not sceneryClear(x, z) then
		return "scenery"
	elseif not landmarkClear(x, z, 6) then
		return "landmark"
	elseif not yardsClear(x, z) then
		return "loading pad or plot square"
	elseif TerrainGen.RoadClearance(x, z) < TownTreeData.Margin.road then
		return "road"
	elseif TerrainGen.WaterLevelAt(x, z) ~= nil then
		return "water"
	elseif TerrainGen.SlopeAt(x, z) >= 0.5 then
		return "steep ground"
	end
	return nil
end

function TreeFill.TownGround(x: number, z: number): boolean
	return TreeFill.TownWhy(x, z) == nil
end

-- The ground test for a tree of `zone`: a town zone ("town:...") or the
-- spawn's oak clumps ("neargrove:...", NearGrove) use TownGround; every other zone the general one.
function TreeFill.GroundFor(zone: TreeZone?, x: number, z: number): boolean
	if zone and (string.sub(zone.id, 1, 5) == "town:" or string.sub(zone.id, 1, 10) == "neargrove:") then
		return TreeFill.TownGround(x, z)
	end
	-- Lane R: the Bayou's and Red Mesa's trees keep off those regions' own builds.
	if
		zone
		and (zone.id == "bayou" or zone.id == "mesa" or string.sub(zone.id, 1, 12) == "added:bayou:" or string.sub(
			zone.id,
			1,
			11
		) == "added:mesa:")
		and WorldLayout.RegionBuildBlocked(x, z)
	then
		return false
	end
	return TreeFill.Ground(x, z)
end

-- The town's trees: for each site of `tier` (default: the shipped tier), up
-- to `want` trunks scattered in its disc, a TownTreeData.Gap apart and on
-- TownGround. Deterministic: each site has its own rng from its id, so a
-- site's trees do not depend on which other sites a tier plants. Returns them
-- without touching `taken`.
function TreeFill.TownRings(taken: { Vector3 }, pause: (() -> ())?, tier: string?): { Spot }
	local out: { Spot } = {}
	local mine: { Vector3 } = {}
	for _, site in ipairs(TownTreeData.SitesFor(tier or TownTreeData.ShippedTier)) do
		local rng = Kit.rng(hashString("town ring " .. site.id))
		local zone: TreeZone = {
			id = "town:" .. site.id,
			cx = site.cx,
			cz = site.cz,
			radius = site.radius,
			cap = site.want,
		}
		local woods = woodsNear(Vector2.new(site.cx, site.cz))
		local tries, placed = 0, 0
		while placed < site.want and tries < site.want * 60 do
			tries += 1
			if pause then
				pause()
			end
			local a = rng:range(0, math.pi * 2)
			local rr = math.sqrt(rng:next()) * site.radius
			local x, z = site.cx + math.cos(a) * rr, site.cz + math.sin(a) * rr
			if
				not takenNear(taken, x, z, TownTreeData.Gap)
				and not takenNear(mine, x, z, TownTreeData.Gap)
				and TreeFill.TownGround(x, z)
			then
				local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
				table.insert(mine, p)
				table.insert(out, { woodId = rng:pick(woods), position = p, biome = "wild", zone = zone })
				placed += 1
			end
		end
	end
	return out
end

function TreeFill.ClumpCenterOk(x: number, z: number, centers: { Vector2 }): boolean
	if math.abs(x) > SCENERY_EDGE or math.abs(z) > SCENERY_EDGE then
		return false
	end
	if not quiet(x, z, 20) or not townClear(x, z) or not biomeClear(x, z) then
		return false
	end
	-- 40 off a haul road and 50 off a plot, so a regrow inside the 20-stud
	-- zone stays 20 and 30 clear.
	if not plotClear(x, z, 50) or not haulClear(x, z, 40) or not obstacleClear(x, z) or not sceneryClear(x, z) then
		return false
	end
	-- The clump's zone is 20 studs, so a regrow stays off the bridge and docks.
	if not landmarkClear(x, z, 20) then
		return false
	end
	if not world().GoodGround(x, z, ROAD_GAP, 0.6) then
		return false
	end
	for _, c in ipairs(centers) do
		if (c - Vector2.new(x, z)).Magnitude < 60 then
			return false
		end
	end
	return true
end

-- Tries to stand `n` trees (3 to 5) on a ring around `c`. Returns them
-- only when every one of them fits; nothing is reserved otherwise.
local function ring(c: Vector2, n: number, taken: { Vector3 }, rng: any, zoneId: string?, cap: number?): { Spot }?
	local zone: TreeZone = { id = zoneId or "wild", cx = c.X, cz = c.Y, radius = 20, cap = cap or 120 }
	local spin = rng:next() * math.pi * 2
	local rad = 12 / (2 * math.sin(math.pi / n))
	local batch: { Spot } = {}
	local reserved: { Vector3 } = {}
	for k = 1, n do
		local ang = spin + (k - 1) * math.pi * 2 / n
		local found = false
		for nudge = 0, 16 do
			local rr = rad + (nudge % 5 - 2) * 1.1
			local aa = ang + nudge * 0.18
			local x, z = c.X + math.cos(aa) * rr, c.Y + math.sin(aa) * rr
			if
				dist(x, z, c.X, c.Y) <= 16
				and quiet(x, z, 0)
				and not takenNear(taken, x, z, TREE_GAP)
				and not takenNear(reserved, x, z, TREE_GAP)
				and TreeFill.Ground(x, z)
			then
				local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
				table.insert(reserved, p)
				table.insert(batch, {
					woodId = rng:pick(woodsNear(c)),
					position = p,
					biome = "wild",
					zone = zone,
				})
				found = true
				break
			end
		end
		if not found then
			return nil
		end
	end
	return batch
end

-- Exactly 120 trees: 10 clumps of 3, 10 of 4 and 10 of 5.
function TreeFill.Clumps(taken: { Vector3 }, rng: any, pause: (() -> ())?): { Spot }
	local sizes: { number } = {}
	for _ = 1, 10 do
		table.insert(sizes, 3)
		table.insert(sizes, 4)
		table.insert(sizes, 5)
	end
	local centers: { Vector2 } = {}
	local out: { Spot } = {}
	local half = SCENERY_EDGE - 40
	local guard = 0
	local nextSize = 1
	while #out < 120 and nextSize <= #sizes and guard < 25000 do
		guard += 1
		if pause then
			pause()
		end
		local x, z = rng:range(-half, half), rng:range(-half, half)
		if TreeFill.ClumpCenterOk(x, z, centers) then
			local c = Vector2.new(x, z)
			local batch = ring(c, sizes[nextSize], taken, rng)
			if batch then
				table.insert(centers, c)
				for _, spot in ipairs(batch) do
					table.insert(out, spot)
					table.insert(taken, spot.position)
				end
				nextSize += 1
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The added trees (WORLD-T323): 100 trees and up to 4 teasers, planned after
-- everything else. They are NOT in BiomeData.trees (that would move the
-- economy's supply caps and the region budgets): like the town trees they stay
-- out of the economy model. Nothing existing moves; every group has its own
-- fixed seed and its own regrow zone `added:<biome>:<wood>` (cap = its count).
---------------------------------------------------------------------------

export type AddedRow = {
	biome: string, -- the biome (or region) disc the group stands in
	wood: string,
	count: number,
	rim: { number }?, -- stand between these fractions of the disc radius
	arc: number?, -- and within this many degrees of +X
	region: boolean?, -- a Lane R region: planned against the region's own trees only
	landing: boolean?, -- the Bayou: within BayouData.Budgets.treesNearLanding of the landing
	teaser: { road: string, stage: number }?, -- one lone tree beside a road
}

TreeFill.AddedRows = {
	-- The Starter Forest and the Hills are full inside their discs (the ground test
	-- and the 10 stud gap leave under 100 free square studs in the Starter disc),
	-- so their rims reach past the disc edge (hi above 1): the first free ground
	-- just outside it. Cherry's outer ring is 0.70 and out; its Hills share keeps
	-- to the east edge, 0.55 and out, within 60 degrees of +X.
	{ biome = "starter", wood = "oak", count = 4, rim = { 0, 1.25 } },
	{ biome = "starter", wood = "birch", count = 2, rim = { 0, 1.25 } },
	{ biome = "starter", wood = "cherry", count = 7, rim = { 0.70, 1.25 } },
	{ biome = "hills", wood = "pine", count = 8, rim = { 0, 1.15 } },
	{ biome = "hills", wood = "maple", count = 7, rim = { 0, 1.15 } },
	{ biome = "hills", wood = "cherry", count = 7, rim = { 0.55, 1.15 }, arc = 60 },
	{ biome = "snow", wood = "frostwood", count = 9 },
	{ biome = "volcano", wood = "emberwood", count = 8 },
	{ biome = "grove", wood = "phantomwood", count = 4 },
	{ biome = "bayou", wood = "bogcypress", count = 8, region = true, landing = true },
	{ biome = "bayou", wood = "willow", count = 12, region = true, landing = true },
	{ biome = "mesa", wood = "ironwood", count = 6, region = true },
} :: { AddedRow }

-- Three clumps of six, on the wild clumps' ground rules.
TreeFill.AddedClumps = { count = 3, size = 6 }

-- One lone tree of the next wood beside each haul road, seen and not cut.
-- `stage` is the stage its wood needs (BiomeData.needsStage; the Snowfields
-- and the Volcano are gated by their gear and axe: S3 and S4).
TreeFill.AddedTeasers = {
	{ biome = "bayou", wood = "bogcypress", count = 1, teaser = { road = "BayouRoad", stage = 2 } },
	{ biome = "snow", wood = "frostwood", count = 1, teaser = { road = "SnowRoad", stage = 3 } },
	{ biome = "volcano", wood = "emberwood", count = 1, teaser = { road = "VolcanoRoad", stage = 4 } },
	{ biome = "mesa", wood = "ironwood", count = 1, teaser = { road = "MesaRoad", stage = 4 } },
} :: { AddedRow }

TreeFill.TeaserOffset = { 24, 30 } -- studs off the road's centreline
TreeFill.TeaserAlong = { 0.35, 0.60 } -- of the road's length

-- The best axe a player at `stage` can own (StageOf.AxeStage by ladder rung).
function TreeFill.BestAxeAt(stage: number): ItemCatalog.AxeDef?
	local best: ItemCatalog.AxeDef? = nil
	for rung, axe in ipairs(ItemCatalog.AxeLadder()) do
		local rungStage = StageOf.AxeStage[rung]
		if rungStage ~= nil and rungStage <= stage then
			best = axe
		end
	end
	return best
end

-- Whether a lone `woodId` tree is "seen, not cut" for a wood whose stage is
-- `stage`: the best axe of the stage before it deals no damage to it, by the
-- rule ItemCatalog.AxeDamage applies (damage minus the wood's hardness).
function TreeFill.TeaserHidden(woodId: string, stage: number): boolean
	local wood = WoodData.Get(woodId)
	local axe = TreeFill.BestAxeAt(stage - 1)
	if wood == nil or axe == nil then
		return false
	end
	return ItemCatalog.AxeDamage(axe, wood) <= 0
end

-- The teaser rows that pass TeaserHidden (the others are dropped).
function TreeFill.TeasersKept(): { AddedRow }
	local kept: { AddedRow } = {}
	for _, row in ipairs(TreeFill.AddedTeasers) do
		local info = row.teaser
		if info and TreeFill.TeaserHidden(row.wood, info.stage) then
			table.insert(kept, row)
		end
	end
	return kept
end

local function discOf(biomeId: string): { x: number, z: number, radius: number }?
	local region = BiomeData.RegionDiscs[biomeId]
	if region then
		return region
	end
	local def = BiomeData.Get(biomeId)
	local area = if def then def.area else nil
	if area then
		return { x = area.x, z = area.z, radius = area.radius }
	end
	return nil
end

local function addedZone(row: AddedRow): TreeZone
	local id = if row.teaser then "added:teaser:" .. row.wood else "added:" .. row.biome .. ":" .. row.wood
	return { id = id, cx = 0, cz = 0, radius = 1, cap = row.count, fixed = if row.teaser then true else nil }
end

-- Points `at` of the way along a road's centreline, and its unit normal.
local function roadPoint(points: { Vector2 }, at: number): (Vector2, Vector2)
	local total = 0
	for i = 1, #points - 1 do
		total += (points[i + 1] - points[i]).Magnitude
	end
	local want = total * at
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		if want <= len or i == #points - 1 then
			local f = math.clamp(want / math.max(len, 1e-6), 0, 1)
			local dir = (b - a).Unit
			return a + (b - a) * f, Vector2.new(-dir.Y, dir.X)
		end
		want -= len
	end
	return points[1], Vector2.new(0, 1)
end

local function bayouNear(x: number, z: number): boolean
	local BayouData = require(script.Parent.Parent.Regions.BayouData)
	local l = BayouData.Landing
	return (x - l.x) ^ 2 + (z - l.z) ^ 2 <= BayouData.Budgets.treesNearLanding ^ 2
end

local function planGroup(row: AddedRow, taken: { Vector3 }, pause: (() -> ())?): { Spot }
	local out: { Spot } = {}
	local zone = addedZone(row)
	local rng = Kit.rng(hashString("added " .. row.biome .. row.wood))
	local tries = 0
	local limit = row.count * 40
	local function tick()
		if pause then
			pause()
		end
	end
	local function accept(x: number, z: number): boolean
		if takenNear(taken, x, z, TREE_GAP) then
			return false
		end
		if not TreeFill.GroundFor(zone, x, z) then
			return false
		end
		if (row.biome == "bayou" or row.biome == "mesa") and WorldLayout.RegionBuildBlocked(x, z) then
			return false
		end
		if row.landing and not bayouNear(x, z) then
			return false
		end
		return true
	end
	if row.teaser then
		local road = nil
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == row.teaser.road then
				road = r
			end
		end
		if road == nil then
			return out
		end
		limit = 120
		while #out < row.count and tries < limit do
			tries += 1
			tick()
			local at = rng:range(TreeFill.TeaserAlong[1], TreeFill.TeaserAlong[2])
			local off = rng:range(TreeFill.TeaserOffset[1], TreeFill.TeaserOffset[2])
				* (if rng:next() < 0.5 then -1 else 1)
			local centre, normal = roadPoint(road.points, at)
			local x, z = centre.X + normal.X * off, centre.Y + normal.Y * off
			if accept(x, z) then
				zone.cx, zone.cz = x, z
				local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
				table.insert(taken, p)
				table.insert(out, { woodId = row.wood, position = p, biome = "wild", zone = zone })
			end
		end
		return out
	end
	local disc = discOf(row.biome)
	if disc == nil then
		return out
	end
	local radius = disc.radius - 6
	local lo, hi = 0, 1
	if row.rim then
		lo, hi = row.rim[1], row.rim[2]
	end
	while #out < row.count and tries < limit do
		tries += 1
		tick()
		local angle = rng:next() * math.pi * 2
		if row.arc then
			angle = rng:range(-row.arc, row.arc) * math.pi / 180
		end
		local r = radius * math.sqrt(lo * lo + rng:next() * (hi * hi - lo * lo))
		local x, z = disc.x + math.cos(angle) * r, disc.z + math.sin(angle) * r
		if accept(x, z) then
			local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
			table.insert(taken, p)
			table.insert(out, { woodId = row.wood, position = p, biome = row.biome, zone = zone })
		end
	end
	-- A last pass on a grid, for a crowded disc the random samples missed (the
	-- Hills): the first free spots from the disc's far side in, 4 studs apart.
	if #out < row.count then
		local step = 4
		local reach = radius * math.max(hi, 1)
		local x0 = disc.x - reach
		while #out < row.count and x0 <= disc.x + reach do
			local z0 = disc.z - reach
			while #out < row.count and z0 <= disc.z + reach do
				tick()
				local d = dist(x0, z0, disc.x, disc.z) / radius
				local inArc = true
				if row.arc then
					inArc = math.abs(math.deg(math.atan2(z0 - disc.z, x0 - disc.x))) <= row.arc
				end
				if d >= lo and d <= hi and inArc and accept(x0, z0) then
					local p = Vector3.new(x0, TerrainGen.HeightAt(x0, z0) - 0.3, z0)
					table.insert(taken, p)
					table.insert(out, { woodId = row.wood, position = p, biome = row.biome, zone = zone })
				end
				z0 += step
			end
			x0 += step
		end
	end
	-- The zone is a disc round its own spots (a felled tree grows back inside it).
	if #out > 0 then
		local sx, sz = 0, 0
		for _, spot in ipairs(out) do
			sx += spot.position.X
			sz += spot.position.Z
		end
		zone.cx, zone.cz = sx / #out, sz / #out
		local far = 0
		for _, spot in ipairs(out) do
			far = math.max(far, dist(spot.position.X, spot.position.Z, zone.cx, zone.cz))
		end
		zone.radius = far + 12
	end
	return out
end

local function planAddedClumps(taken: { Vector3 }, pause: (() -> ())?): { Spot }
	local rng = Kit.rng(hashString("added wild clumps"))
	local out: { Spot } = {}
	local centers: { Vector2 } = {}
	local half = SCENERY_EDGE - 40
	local guard = 0
	local want = TreeFill.AddedClumps.count
	while #centers < want and guard < 25000 do
		guard += 1
		if pause then
			pause()
		end
		local x, z = rng:range(-half, half), rng:range(-half, half)
		if TreeFill.ClumpCenterOk(x, z, centers) then
			local c = Vector2.new(x, z)
			local batch = ring(
				c,
				TreeFill.AddedClumps.size,
				taken,
				rng,
				"added:wild:" .. tostring(#centers + 1),
				TreeFill.AddedClumps.size
			)
			if batch then
				table.insert(centers, c)
				for _, spot in ipairs(batch) do
					table.insert(out, spot)
					table.insert(taken, spot.position)
				end
			end
		end
	end
	return out
end

-- The added trees, in this order: the Lane R region groups (`only` = "region"),
-- then the rest and the clumps and the teasers (`only` = "land"); nil plans
-- both. `taken` is every tree already standing that these keep 10 studs from;
-- it grows by each tree planned. Deterministic: fixed seeds, bounded tries,
-- `pause` after every attempt.
function TreeFill.PlanAdded(taken: { Vector3 }, pause: (() -> ())?, only: string?): { Spot }
	local out: { Spot } = {}
	if only ~= "land" then
		for _, row in ipairs(TreeFill.AddedRows) do
			if row.region then
				for _, spot in ipairs(planGroup(row, taken, pause)) do
					table.insert(out, spot)
				end
			end
		end
		for _, row in ipairs(TreeFill.TeasersKept()) do
			if row.biome == "bayou" or row.biome == "mesa" then
				for _, spot in ipairs(planGroup(row, taken, pause)) do
					table.insert(out, spot)
				end
			end
		end
	end
	if only ~= "region" then
		for _, row in ipairs(TreeFill.AddedRows) do
			if not row.region then
				for _, spot in ipairs(planGroup(row, taken, pause)) do
					table.insert(out, spot)
				end
			end
		end
		for _, spot in ipairs(planAddedClumps(taken, pause)) do
			table.insert(out, spot)
		end
		for _, row in ipairs(TreeFill.TeasersKept()) do
			if row.biome ~= "bayou" and row.biome ~= "mesa" then
				for _, spot in ipairs(planGroup(row, taken, pause)) do
					table.insert(out, spot)
				end
			end
		end
	end
	return out
end

return TreeFill
