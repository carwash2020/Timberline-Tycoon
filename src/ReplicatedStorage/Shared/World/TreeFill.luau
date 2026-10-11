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
local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Parent.Art.Kit)
local PlotData = require(script.Parent.Parent.PlotData)
local TownTreeData = require(script.Parent.Parent.TownTreeData)
local TerrainGen = require(script.Parent.TerrainGen)
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
-- plain numbers (reading a Vector3's fields is slow), extended on use.
type Flat = { n: number, xs: { number }, zs: { number } }
local flats: { [{ Vector3 }]: Flat } = setmetatable({}, { __mode = "k" }) :: any
local function takenNear(taken: { Vector3 }, x: number, z: number, gap: number): boolean
	local g2 = gap * gap
	local flat = flats[taken]
	if not flat then
		flat = { n = 0, xs = {}, zs = {} }
		flats[taken] = flat
	end
	local xs, zs = flat.xs, flat.zs
	local count = #taken
	if flat.n > count then -- (shrunk: start over)
		table.clear(xs)
		table.clear(zs)
		flat.n = 0
	end
	for i = flat.n + 1, count do
		local p = taken[i]
		xs[i], zs[i] = p.X, p.Z
	end
	flat.n = count
	for i = 1, count do
		local dx, dz = xs[i] - x, zs[i] - z
		if dx * dx + dz * dz < g2 then
			return true
		end
	end
	return false
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
					half = road.width / 2,
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
	gap: number
): Spot?
	local function free(px: number, pz: number): boolean
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
function TreeFill.Extra(existing: { Spot }, pause: (() -> ())?): { Spot }
	local function tick()
		if pause then
			pause()
		end
	end
	local out: { Spot } = {}
	local taken: { Vector3 } = {}
	for _, s in ipairs(existing) do
		table.insert(taken, s.position)
	end
	local rng = Kit.rng(hashString("tree fill"))

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
					local spot = placeOne(area.x, area.z, area.radius - 6, woodId, biome.id, zone, taken, rng, TREE_GAP)
					if spot then
						table.insert(out, spot)
						left -= 1
					end
				end
			end
		end
	end

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
			local spot = placeOne(disc.cx, disc.cz, disc.radius, woodId, "wild", zone, taken, rng, TREE_GAP)
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
				local spot =
					placeOne(stand.center.X, stand.center.Y, stand.radius, woodId, "wild", zone, taken, rng, TREE_GAP)
				if spot then
					table.insert(out, spot)
					left -= 1
				end
			end
		end
	end

	local clumps = TreeFill.Clumps(taken, rng, pause)
	for _, spot in ipairs(clumps) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
	end
	-- Last, with their own rng, so nothing above moves: trees round each pad.
	for _, spot in ipairs(TreeFill.PlotRings(taken, pause)) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
	end
	-- And last of all, the trees in and round the town (its own rng too).
	for _, spot in ipairs(TreeFill.TownRings(taken, pause)) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
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
	-- The gondola leaves the town station toward the isles.
	local sky = BiomeData.Get("sky")
	local area = if sky then sky.area else nil
	if area then
		local from = Vector2.new(TownTreeData.GondolaStation.x, TownTreeData.GondolaStation.z)
		local dir = (Vector2.new(area.x, area.z) - from).Unit
		local to = from + dir * TownTreeData.GondolaLaneLength
		table.insert(
			lanes,
			{ name = "gondola", ax = from.X, az = from.Y, bx = to.X, bz = to.Y, half = TownTreeData.GondolaLaneHalf }
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

-- The ground test for a tree of `zone`: a town zone ("town:...") uses
-- TownGround; every other zone the general one.
function TreeFill.GroundFor(zone: TreeZone?, x: number, z: number): boolean
	if zone and string.sub(zone.id, 1, 5) == "town:" then
		return TreeFill.TownGround(x, z)
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
local function ring(c: Vector2, n: number, taken: { Vector3 }, rng: any): { Spot }?
	local zone: TreeZone = { id = "wild", cx = c.X, cz = c.Y, radius = 20, cap = 120 }
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

return TreeFill
