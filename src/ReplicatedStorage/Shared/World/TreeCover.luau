--!strict
-- TreeCover (T400): the plan that spreads real trees over the map, so every
-- tree a player sees is a TreeService tree (the client's stand-in forest is
-- gone). Pure plan code: no services, no instances; the world is handed in as
-- functions (Env). It runs in tools/tree_cover and the specs, never at boot:
-- the boot reads its answer from TreeSpreadData (Cover and Relocated).
--
-- The rules (the numbers are Connor's):
--   * Trunk-edge gap: two trunks keep Gap (10) studs between their edges.
--   * Buffers: no trunk within RoadBuffer (8) of a road's edge or PathBuffer (4)
--     of a footpath; the POI keep-outs (KeptOut): the town square, plot pads
--     plus PlotLawn (40), store pads plus 12, the sawmill and sell yard plus 16,
--     the ferry dock plus 20, and (TreeFill.Ground) the spawn-to-lighthouse sight line.
--   * Coverage: on the 32 stud grid, off the roads, no empty square of cells
--     bigger than Limits (2 in the Starter Forest, 3 in the meadow, Hills and
--     the Bayou, 4 in the late biomes); and every road sample (every 8 studs)
--     has a trunk within RoadReach (40).
--   * Clumps of 3 to 5, each with a straight LaneWidth (20) lane from the road
--     buffer's edge to it (a straight lane has no turn; the Heavy Hauler needs 40).
--   * Mix per biome: 80 percent common, 15 second, 5 rare; sizes small, normal
--     and large at 3 : 4 : 1 (the position picks the size class, so the plan
--     nudges each trunk by a stud or two to get the one it wants).
--   * The count does not move: every tree the plan adds is paid for by one
--     movable wild tree it relocates (an overlap, a buffer or a gap broken, or
--     the densest places).

local BiomeData = require(script.Parent.Parent.BiomeData)
local TreeSpread = require(script.Parent.TreeSpread)
local WorldLayout = require(script.Parent.WorldLayout)

local TreeCover = {}

TreeCover.Gap = 10 -- trunk edge to trunk edge (TreeFill's TREE_GAP)
TreeCover.RoadBuffer = 8
TreeCover.PathBuffer = 4
TreeCover.PlotLawn = 40
TreeCover.StorePad = 12
TreeCover.YardPad = 16
TreeCover.DockPad = 20
TreeCover.Cell = 32
TreeCover.RoadStep = 8
TreeCover.RoadReach = 40
TreeCover.LaneWidth = 20
TreeCover.LaneRadius = 40
TreeCover.LaneMargin = 2 -- the planner keeps this much more than LaneWidth clear
TreeCover.MixShares = { 0.80, 0.15, 0.05 }
TreeCover.SizeCycle = { "small", "normal", "small", "normal", "large", "normal", "small", "normal" }
TreeCover.ClumpSizes = { 3, 4, 3, 5 }
TreeCover.CrowdLimit = 16 -- a 100 stud cell this full takes no new trunk (the cap is 25)
TreeCover.TruckReach = 60 -- a clump this close to a road's edge is in reach of a truck

-- The biggest empty square of cells each place may keep.
TreeCover.Limits = {
	starter = 2,
	meadow = 3,
	hills = 3,
	bayou = 3,
	snow = 4,
	volcano = 4,
	mesa = 4,
	grove = 4,
	ferryisle = 4,
} :: { [string]: number }

-- Trees per 10,000 sq studs (Connor's table); the Phantom Grove and the
-- ferry isle take the late biomes' number.
TreeCover.Density = {
	starter = 4,
	hills = 3,
	bayou = 4,
	snow = 2,
	volcano = 1.5,
	mesa = 1,
	meadow = 1,
	grove = 1.5,
	ferryisle = 1.5,
} :: { [string]: number }

-- What a place grows: common, second, rare (80 / 15 / 5). Inside a zone's disc
-- its own woods; outside it the plain woods (the special woods stay home).
local WOODS: { [string]: { inside: { string }, outside: { string } } } = {
	starter = { inside = { "oak", "birch", "cherry" }, outside = { "oak", "birch", "cherry" } },
	hills = { inside = { "pine", "maple", "oak" }, outside = { "pine", "maple", "oak" } },
	snow = { inside = { "frostwood", "pine", "birch" }, outside = { "pine", "birch", "oak" } },
	volcano = { inside = { "emberwood", "pine", "birch" }, outside = { "pine", "birch", "oak" } },
	grove = { inside = { "phantomwood", "oak", "birch" }, outside = { "oak", "birch", "cherry" } },
	bayou = { inside = { "bogcypress", "willow", "oak" }, outside = { "oak", "birch", "cherry" } },
	mesa = { inside = { "ironwood", "oak", "birch" }, outside = { "oak", "birch", "cherry" } },
}

export type Tree = {
	x: number,
	z: number,
	r: number, -- trunk radius
	wood: string?,
	index: number?, -- the place in WorldPlan.Trees() (movable trees only)
	movable: boolean?,
	anchor: boolean?,
}

export type NewTree = { x: number, z: number, wood: string, clump: number, size: string }

export type Env = {
	ground: (x: number, z: number) -> boolean, -- TreeFill.Ground, dry land, lowland
	roadClear: (x: number, z: number) -> number, -- studs from the nearest road's edge
	roads: { { Vector2 } }, -- the roads' centrelines (not the plot spurs)
	roadHalf: { number }, -- half width of each
	trunkRadius: (wood: string, x: number, z: number) -> number,
	sizeAt: (x: number, z: number) -> string, -- "small", "normal" or "large" for a tree standing there
	blocked: ((x: number, z: number, r: number) -> boolean)?, -- a rock, boulder or scenery piece in the way
	total: number, -- the tree count the plan keeps
	pause: (() -> ())?,
	log: ((message: string) -> ())?,
}

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------

-- The place a point belongs to: a biome disc, a Lane R region, or "meadow".
function TreeCover.ClassOf(x: number, z: number): string
	local biome = BiomeData.At(x, z)
	if biome and biome.id ~= "island" and biome.id ~= "sky" then
		return biome.id
	end
	return BiomeData.RegionAt(x, z) or "meadow"
end

-- { common, second, rare } woods at a point.
function TreeCover.WoodsFor(x: number, z: number): { string }
	local near = TreeSpread.ZonesNear(x, z)[1]
	local woods = WOODS[near.id] or WOODS.starter
	return if near.edge <= 0 then woods.inside else woods.outside
end

-- The wood of the n-th tree (0 based) of a place's tally: 16 common, 3 second,
-- 1 rare in every 20.
function TreeCover.WoodAt(x: number, z: number, n: number): string
	local woods = TreeCover.WoodsFor(x, z)
	local k = n % 20
	if k == 19 then
		return woods[3]
	elseif k == 6 or k == 12 or k == 16 then
		return woods[2]
	end
	return woods[1]
end

---------------------------------------------------------------------------
-- Keep-outs
---------------------------------------------------------------------------

local function rectDistance(x: number, z: number, r: { x0: number, x1: number, z0: number, z1: number }): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- Why a trunk of radius `r` may not stand at (x, z) (a point of interest's
-- keep-out or a footpath), or nil. Roads and the rest of the ground are the
-- Env's.
function TreeCover.KeptOut(x: number, z: number, r: number): string?
	for _, paint in ipairs(WorldLayout.TownPaint) do
		local name = paint.name
		if paint.name == "Plaza" and rectDistance(x, z, paint) < 12 + r then
			return "the town square"
		elseif paint.name == "MillYard" and rectDistance(x, z, paint) < TreeCover.YardPad + r then
			return "the sawmill yard"
		elseif
			(string.find(name, "Path$") or string.find(name, "Walk$") or string.find(name, "Mouth$"))
			and rectDistance(x, z, paint) < TreeCover.PathBuffer + r
		then
			return "a footpath (" .. name .. ")"
		end
	end
	for _, floor in ipairs(WorldLayout.TownFloors) do
		local pad = if floor.name == "SellStationFloor" then TreeCover.YardPad else TreeCover.StorePad
		if rectDistance(x, z, floor) < pad + r then
			return if floor.name == "SellStationFloor" then "the sell yard" else "a store pad (" .. floor.name .. ")"
		end
	end
	if WorldLayout.NearPlotPad(x, z, TreeCover.PlotLawn) then
		return "a plot pad's lawn"
	end
	local dock = WorldLayout.FerryDock
	local dx, dz = x - dock.x, z - dock.z
	local reach = WorldLayout.DockClear + TreeCover.DockPad + r
	if dx * dx + dz * dz < reach * reach then
		return "the ferry dock"
	end
	return nil
end

---------------------------------------------------------------------------
-- A hash of trees, for the gap and the lane
---------------------------------------------------------------------------

export type Grid = { cell: number, buckets: { [number]: { Tree } }, count: number }

local GRID_CELL = 16
local MAX_R = 3

local function bucketKey(cx: number, cz: number): number
	return (cx + 4096) * 8192 + (cz + 4096)
end

function TreeCover.NewGrid(): Grid
	return { cell = GRID_CELL, buckets = {}, count = 0 }
end

function TreeCover.GridAdd(grid: Grid, tree: Tree)
	local key = bucketKey(math.floor(tree.x / GRID_CELL), math.floor(tree.z / GRID_CELL))
	local bucket = grid.buckets[key]
	if not bucket then
		bucket = {}
		grid.buckets[key] = bucket
	end
	table.insert(bucket, tree)
	grid.count += 1
end

-- Calls `fn` for every tree whose bucket touches the square of half-side `reach` round (x, z).
local function eachNear(grid: Grid, x: number, z: number, reach: number, fn: (Tree) -> boolean?)
	for cx = math.floor((x - reach) / GRID_CELL), math.floor((x + reach) / GRID_CELL) do
		for cz = math.floor((z - reach) / GRID_CELL), math.floor((z + reach) / GRID_CELL) do
			local bucket = grid.buckets[bucketKey(cx, cz)]
			if bucket then
				for _, tree in ipairs(bucket) do
					if fn(tree) then
						return
					end
				end
			end
		end
	end
end

-- Whether a trunk of radius `r` at (x, z) keeps Gap studs (edge to edge) off every tree in `grid`.
function TreeCover.GapOk(grid: Grid, x: number, z: number, r: number): boolean
	local ok = true
	eachNear(grid, x, z, TreeCover.Gap + r + MAX_R, function(o: Tree): boolean?
		local dx, dz = o.x - x, o.z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d - r - o.r < TreeCover.Gap - 1e-6 then
			ok = false
			return true
		end
		return nil
	end)
	return ok
end

-- The nearest tree centre to (x, z) within `reach`, or nil.
function TreeCover.NearestDistance(grid: Grid, x: number, z: number, reach: number): number?
	local best: number? = nil
	eachNear(grid, x, z, reach, function(o: Tree): boolean?
		local dx, dz = o.x - x, o.z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= reach and (best == nil or d < best) then
			best = d
		end
		return nil
	end)
	return best
end

---------------------------------------------------------------------------
-- The roads
---------------------------------------------------------------------------

export type RoadSample = { x: number, z: number, dx: number, dz: number }

-- Points along every road, every RoadStep studs.
function TreeCover.RoadSamples(roads: { { Vector2 } }): { RoadSample }
	local out: { RoadSample } = {}
	for _, points in ipairs(roads) do
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local len = (b - a).Magnitude
			if len > 0 then
				local dir = (b - a) / len
				local d = 0
				while d <= len do
					local p = a + dir * d
					table.insert(out, { x = p.X, z = p.Y, dx = dir.X, dz = dir.Y })
					d += TreeCover.RoadStep
				end
			end
		end
	end
	return out
end

-- The distance from (x, z) to the nearest road centreline, and that point.
local function nearestRoadPoint(roads: { { Vector2 } }, x: number, z: number): (number, Vector2?)
	local best, at = math.huge, nil :: Vector2?
	local p = Vector2.new(x, z)
	for _, points in ipairs(roads) do
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local ab = b - a
			local len2 = ab:Dot(ab)
			local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
			local q = a + ab * t
			local d = (p - q).Magnitude
			if d < best then
				best, at = d, q
			end
		end
	end
	return best, at
end

-- A straight lane (LaneWidth wide) from the road buffer's edge to (cx, cz): the
-- ray from the clump's middle that reaches a road's buffer first, with no
-- trunk (but the clump's own, `own`) within half the lane's width of it.
-- Returns the angle (radians) and the length, or nil.
function TreeCover.Lane(
	env: Env,
	grid: Grid,
	cx: number,
	cz: number,
	own: { [Tree]: boolean },
	margin: number?
): (number?, number?)
	local reach = TreeCover.LaneWidth / 2 + (margin or 0)
	local roadBuffer = TreeCover.RoadBuffer
	local _, at = nearestRoadPoint(env.roads, cx, cz)
	if not at then
		return nil, nil
	end
	local base = math.atan2(at.Y - cz, at.X - cx)
	for _, turn in ipairs({ 0, 0.26, -0.26, 0.52, -0.52, 0.78, -0.78, 1.05, -1.05, 1.57, -1.57 }) do
		local a = base + turn
		local ux, uz = math.cos(a), math.sin(a)
		-- March out until a road's buffer, at most 1200 studs.
		local length: number? = nil
		local s = 6
		while s <= 1200 do
			if env.roadClear(cx + ux * s, cz + uz * s) <= roadBuffer then
				length = s
				break
			end
			s += if s < 100 then 4 else 12
		end
		if length then
			local clear = true
			local len: number = length
			eachNear(grid, cx + ux * len / 2, cz + uz * len / 2, len / 2 + reach + MAX_R, function(o: Tree): boolean?
				if own[o] then
					return nil
				end
				local ox, oz = o.x - cx, o.z - cz
				local along = ox * ux + oz * uz
				if along < 0 or along > len then
					return nil -- behind the grove, or past the road's buffer
				end
				local side = math.abs(-ox * uz + oz * ux)
				if side < reach + o.r then
					clear = false
					return true
				end
				return nil
			end)
			if clear then
				return a, length
			end
		end
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- The planner
---------------------------------------------------------------------------

export type Result = {
	trees: { NewTree },
	relocated: { { index: number, x: number, z: number } },
	report: { [string]: any },
}

local function cellOf(v: number): number
	return math.floor(v / TreeCover.Cell)
end

local function hashPos(x: number, z: number): number
	return math.floor(x * 10 + 0.5) * 7919 + math.floor(z * 10 + 0.5)
end

-- Plans the new trees for the standing `items` (see Tree: `movable` ones may be
-- relocated). `env.total` is the count that must stand at the end.
function TreeCover.Plan(env: Env, items: { Tree }): Result
	local gone: { [Tree]: boolean } = {}
	local relocated: { { index: number, x: number, z: number } } = {}

	local function pause()
		if env.pause then
			env.pause()
		end
	end
	local function log(message: string)
		if env.log then
			env.log(message)
		end
	end

	-- Whether a trunk of radius r may stand here as far as the ground goes
	-- (no trees asked): memoised on a 2 stud lattice for the lattice walks.
	local groundMemo: { [number]: boolean } = {}
	local function groundOk(x: number, z: number, r: number): boolean
		pause()
		if env.roadClear(x, z) - r < TreeCover.RoadBuffer + 3 then
			return false
		end
		if TreeCover.KeptOut(x, z, r) ~= nil then
			return false
		end
		if env.blocked and env.blocked(x, z, r + 1) then
			return false
		end
		return env.ground(x, z)
	end
	local function latticeOk(x: number, z: number): boolean
		local key = bucketKey(math.floor(x / 2), math.floor(z / 2))
		local hit = groundMemo[key]
		if hit == nil then
			hit = groundOk(math.floor(x / 2) * 2 + 1, math.floor(z / 2) * 2 + 1, 1.3)
			groundMemo[key] = hit
		end
		return hit
	end

	-- 1. Legacy: a movable tree that breaks the gap, a buffer or a keep-out goes.
	local all = TreeCover.NewGrid()
	for _, tree in ipairs(items) do
		TreeCover.GridAdd(all, tree)
	end
	local ordered: { Tree } = {}
	for _, tree in ipairs(items) do
		if tree.movable and tree.index then
			table.insert(ordered, tree)
		end
	end
	table.sort(ordered, function(a: Tree, b: Tree): boolean
		return (a.index :: number) < (b.index :: number)
	end)
	local legacy: { [string]: number } = { gap = 0, road = 0, keepout = 0 }
	for _, tree in ipairs(ordered) do
		pause()
		local why: string? = nil
		if env.roadClear(tree.x, tree.z) - tree.r < TreeCover.RoadBuffer then
			why = "road"
		elseif TreeCover.KeptOut(tree.x, tree.z, tree.r) ~= nil then
			why = "keepout"
		else
			eachNear(all, tree.x, tree.z, TreeCover.Gap + tree.r + MAX_R, function(o: Tree): boolean?
				if o == tree or gone[o] then
					return nil
				end
				local dx, dz = o.x - tree.x, o.z - tree.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d - tree.r - o.r < TreeCover.Gap - 1e-6 then
					-- A fixed neighbour wins; of two movable trees the higher index goes.
					if not o.movable or o.index == nil or (o.index :: number) < (tree.index :: number) then
						why = "gap"
						return true
					end
				end
				return nil
			end)
		end
		if why then
			gone[tree] = true
			legacy[why] += 1
		end
	end
	local legacyDropped = 0
	for _ in pairs(gone) do
		legacyDropped += 1
	end

	local trees: { NewTree } = {}

	local function plan(): ({ NewTree }, { [string]: any })
		-- The standing trees.
		local grid = TreeCover.NewGrid()
		local counts: { [string]: number } = {}
		for _, tree in ipairs(items) do
			if not gone[tree] then
				TreeCover.GridAdd(grid, tree)
				local k = cellOf(tree.x) .. "," .. cellOf(tree.z)
				counts[k] = (counts[k] or 0) + 1
			end
		end
		local made: { NewTree } = {}
		-- Trees per 100 stud cell (TreeSpread.Cap is 25): a new trunk keeps off a full one.
		local crowd: { [string]: number } = {}
		local function crowdKey(x: number, z: number): string
			return math.floor(x / 100) .. "," .. math.floor(z / 100)
		end
		for _, tree in ipairs(items) do
			if not gone[tree] then
				local key = crowdKey(tree.x, tree.z)
				crowd[key] = (crowd[key] or 0) + 1
			end
		end
		local function crowded(x: number, z: number): boolean
			return (crowd[crowdKey(x, z)] or 0) >= TreeCover.CrowdLimit
		end
		-- The drive lanes of the clumps placed so far: no later trunk blocks one.
		local lanes: { { x: number, z: number, ux: number, uz: number, len: number } } = {}
		local function laneBlocks(x: number, z: number, r: number): boolean
			local reach = TreeCover.LaneWidth / 2 + r + 1
			for _, lane in ipairs(lanes) do
				local ox, oz = x - lane.x, z - lane.z
				local along = ox * lane.ux + oz * lane.uz
				if along >= 0 and along <= lane.len then
					if math.abs(-ox * lane.uz + oz * lane.ux) < reach then
						return true
					end
				end
			end
			return false
		end
		local clumpNo = 0
		local sizeNo = 0
		local woodTally: { [string]: number } = {}
		local clumpPick = 0
		local singles = 0
		local noLane = 0

		-- Places one clump of `n` round (cx, cz), or nil. Each trunk's wood comes
		-- from its place's tally, its size class from the cycle (the position is
		-- nudged to give it).
		local function clumpAt(cx: number, cz: number, n: number, pred: (({ Tree }) -> boolean)?): { Tree }?
			local base = ({ [3] = 8.6, [4] = 10.2, [5] = 11.9 })[n] or 8.6
			for _, wider in ipairs({ 0, 2.2 }) do
				local radius = base + wider
				for step = 0, 5 do
					local a0 = step * (math.pi * 2 / n) / 6
					local placed: { Tree } = {}
					local picked: { { x: number, z: number, wood: string, size: string } } = {}
					local ok = true
					local sNo, tallyCopy = sizeNo, table.clone(woodTally)
					for i = 1, n do
						local a = a0 + (i - 1) * math.pi * 2 / n
						local x0, z0 = cx + math.cos(a) * radius, cz + math.sin(a) * radius
						local place = TreeCover.ClassOf(x0, z0)
						if place == "ferryisle" then
							ok = false
							break
						end
						if not latticeOk(x0, z0) then
							ok = false
							break
						end
						local tally = tallyCopy[place] or 0
						local wood = TreeCover.WoodAt(x0, z0, tally)
						local want = TreeCover.SizeCycle[sNo % #TreeCover.SizeCycle + 1]
						local found = false
						for _, off in ipairs({
							{ 0, 0 },
							{ 0.6, 0 },
							{ -0.6, 0 },
							{ 0, 0.6 },
							{ 0, -0.6 },
							{ 1.1, 1.1 },
							{ -1.1, -1.1 },
							{ 1.1, -1.1 },
							{ -1.1, 1.1 },
							{ 1.8, 0 },
							{ -1.8, 0 },
							{ 0, 1.8 },
							{ 0, -1.8 },
							{ 1.5, 1.5 },
							{ -1.5, -1.5 },
							{ 1.5, -1.5 },
							{ -1.5, 1.5 },
						}) do
							local x = math.floor((x0 + off[1]) * 100 + 0.5) / 100
							local z = math.floor((z0 + off[2]) * 100 + 0.5) / 100
							local r = env.trunkRadius(wood, x, z)
							if
								env.sizeAt(x, z) == want
								and TreeCover.GapOk(grid, x, z, r)
								and not laneBlocks(x, z, r)
								and not crowded(x, z)
								and groundOk(x, z, r)
							then
								local clear = true
								for _, other in ipairs(placed) do
									local dx, dz = other.x - x, other.z - z
									if math.sqrt(dx * dx + dz * dz) - r - other.r < TreeCover.Gap then
										clear = false
									end
								end
								if clear then
									table.insert(placed, { x = x, z = z, r = r, wood = wood })
									table.insert(picked, { x = x, z = z, wood = wood, size = want })
									tallyCopy[place] = tally + 1
									sNo += 1
									found = true
									break
								end
							end
						end
						if not found then
							ok = false
							break
						end
					end
					if ok and pred and not pred(placed) then
						ok = false
					end
					if ok then
						-- The lane: the clump's own trees do not block it.
						local own: { [Tree]: boolean } = {}
						for _, t in ipairs(placed) do
							own[t] = true
						end
						local trial = grid
						local angle, length = TreeCover.Lane(env, trial, cx, cz, own, TreeCover.LaneMargin)
						if angle ~= nil and length ~= nil then
							table.insert(
								lanes,
								{ x = cx, z = cz, ux = math.cos(angle), uz = math.sin(angle), len = length }
							)
							clumpNo += 1
							sizeNo = sNo
							woodTally = tallyCopy
							for i, p in ipairs(picked) do
								table.insert(made, { x = p.x, z = p.z, wood = p.wood, clump = clumpNo, size = p.size })
								local tree: Tree = placed[i]
								TreeCover.GridAdd(grid, tree)
								local k = cellOf(p.x) .. "," .. cellOf(p.z)
								counts[k] = (counts[k] or 0) + 1
								local ck = crowdKey(p.x, p.z)
								crowd[ck] = (crowd[ck] or 0) + 1
							end
							return placed
						end
						noLane += 1
					end
				end
			end
			return nil
		end

		local function nextSize(): number
			clumpPick += 1
			return TreeCover.ClumpSizes[(clumpPick - 1) % #TreeCover.ClumpSizes + 1]
		end

		-- A clump (the cycle's size, then smaller, then a lone tree) as near (x, z)
		-- as it fits; `pred` (optional) says whether it does what it was asked
		-- for. The search widens once (twice the reach, a coarser lattice) before
		-- it settles for a lone tree.
		local function placeNear(
			x: number,
			z: number,
			spread: number,
			step: number,
			limit: number?,
			pred: (({ Tree }) -> boolean)?,
			loneOnly: boolean?
		): boolean
			local want = math.min(nextSize(), limit or 5)
			local function spotsWithin(reach: number, gap: number): { { x: number, z: number, d: number } }
				local spots: { { x: number, z: number, d: number } } = {}
				for dx = -reach, reach, gap do
					for dz = -reach, reach, gap do
						local px, pz = x + dx, z + dz
						if dx * dx + dz * dz <= reach * reach and latticeOk(px, pz) then
							table.insert(spots, { x = px, z = pz, d = dx * dx + dz * dz })
						end
					end
				end
				table.sort(spots, function(a, b)
					if a.d ~= b.d then
						return a.d < b.d
					end
					if a.x ~= b.x then
						return a.x < b.x
					end
					return a.z < b.z
				end)
				return spots
			end
			local spots = spotsWithin(spread, step)
			local wide: { { x: number, z: number, d: number } }? = nil
			for _, pass in ipairs(if loneOnly then {} else { 1, 2 }) do
				local list = spots
				if pass == 2 then
					if spread == 0 then
						break
					end
					wide = spotsWithin(spread * 2, step * 2)
					list = wide :: { { x: number, z: number, d: number } }
				end
				for n = want, 3, -1 do
					for i = 1, math.min(#list, 60) do
						if clumpAt(list[i].x, list[i].z, n, pred) then
							return true
						end
					end
				end
			end
			-- A lone tree (a corner of the map where no clump fits).
			local list = wide or spots
			for i = 1, #list do
				local s = list[i]
				local place = TreeCover.ClassOf(s.x, s.z)
				if place ~= "ferryisle" then
					local wood = TreeCover.WoodAt(s.x, s.z, woodTally[place] or 0)
					local r = env.trunkRadius(wood, s.x, s.z)
					local tree: Tree = { x = s.x, z = s.z, r = r, wood = wood }
					if
						TreeCover.GapOk(grid, s.x, s.z, r)
						and not laneBlocks(s.x, s.z, r)
						and not crowded(s.x, s.z)
						and groundOk(s.x, s.z, r)
						and (pred == nil or pred({ tree }))
					then
						clumpNo += 1
						woodTally[place] = (woodTally[place] or 0) + 1
						table.insert(
							made,
							{ x = s.x, z = s.z, wood = wood, clump = clumpNo, size = env.sizeAt(s.x, s.z) }
						)
						TreeCover.GridAdd(grid, tree)
						local k = cellOf(s.x) .. "," .. cellOf(s.z)
						counts[k] = (counts[k] or 0) + 1
						local ck = crowdKey(s.x, s.z)
						crowd[ck] = (crowd[ck] or 0) + 1
						singles += 1
						return true
					end
				end
			end
			return false
		end

		-- 2. Coverage: no empty square bigger than a place's limit.
		log("coverage: cells")
		local treeable: { [string]: string } = {}
		local half = WorldLayout.WorldHalf
		local cells = math.ceil(half / TreeCover.Cell)
		for i = -cells, cells - 1 do
			for j = -cells, cells - 1 do
				local found = false
				for _, a in ipairs({ 5, 16, 27 }) do
					for _, b in ipairs({ 5, 16, 27 }) do
						if not found and latticeOk(i * TreeCover.Cell + a, j * TreeCover.Cell + b) then
							found = true
						end
					end
				end
				if found then
					treeable[i .. "," .. j] = TreeCover.ClassOf((i + 0.5) * TreeCover.Cell, (j + 0.5) * TreeCover.Cell)
				end
			end
		end
		local function firstViolation(): (number?, number?, number?)
			for i = -cells, cells - 1 do
				for j = -cells, cells - 1 do
					local key = i .. "," .. j
					local place = treeable[key]
					if place and not counts[key] then
						local k = (TreeCover.Limits[place] or 3) + 1
						local empty = true
						for a = 0, k - 1 do
							for b = 0, k - 1 do
								local kk = (i + a) .. "," .. (j + b)
								if not treeable[kk] or counts[kk] then
									empty = false
									break
								end
							end
							if not empty then
								break
							end
						end
						if empty then
							return i, j, k
						end
					end
				end
			end
			return nil, nil, nil
		end
		log("coverage: squares")
		local unfilled = 0
		for _ = 1, 4000 do
			local i, j, k = firstViolation()
			if i == nil or j == nil or k == nil then
				break
			end
			local cx, cz = (i + k / 2) * TreeCover.Cell, (j + k / 2) * TreeCover.Cell
			local x0, z0 = i * TreeCover.Cell, j * TreeCover.Cell
			local x1, z1 = (i + k) * TreeCover.Cell, (j + k) * TreeCover.Cell
			local function inside(list: { Tree }): boolean
				for _, tree in ipairs(list) do
					if tree.x >= x0 and tree.x < x1 and tree.z >= z0 and tree.z < z1 then
						return true
					end
				end
				return false
			end
			if not placeNear(cx, cz, k * TreeCover.Cell / 2, 4, nil, inside) then
				-- Nothing fits: the square's cells are left out of the count.
				unfilled += 1
				for a = 0, k - 1 do
					for b = 0, k - 1 do
						treeable[(i + a) .. "," .. (j + b)] = nil
					end
				end
			end
		end

		-- 3. Roads: a trunk within RoadReach of every sample that has any ground near it.
		log(string.format("roads: %d new trees so far, %d clumps", #made, clumpNo))
		local samples = TreeCover.RoadSamples(env.roads)
		local live: { RoadSample } = {}
		for _, s in ipairs(samples) do
			local any = false
			for dx = -TreeCover.RoadReach, TreeCover.RoadReach, 8 do
				for dz = -TreeCover.RoadReach, TreeCover.RoadReach, 8 do
					if not any and dx * dx + dz * dz <= TreeCover.RoadReach ^ 2 and latticeOk(s.x + dx, s.z + dz) then
						any = true
					end
				end
			end
			if any then
				table.insert(live, s)
			end
		end
		local covered: { [RoadSample]: boolean } = {}
		local function refresh()
			for _, s in ipairs(live) do
				if not covered[s] and TreeCover.NearestDistance(grid, s.x, s.z, TreeCover.RoadReach) ~= nil then
					covered[s] = true
				end
			end
		end
		refresh()
		local roadUnfilled = 0
		for _ = 1, 4000 do
			local first: RoadSample? = nil
			for _, s in ipairs(live) do
				if not covered[s] then
					first = s
					break
				end
			end
			if not first then
				break
			end
			-- Nothing can stand within reach (no legal spot clear of every tree): leave it.
			local room = false
			for dx = -TreeCover.RoadReach, TreeCover.RoadReach, 2 do
				for dz = -TreeCover.RoadReach, TreeCover.RoadReach, 2 do
					if
						not room
						and dx * dx + dz * dz <= TreeCover.RoadReach ^ 2
						and latticeOk(first.x + dx, first.z + dz)
						and TreeCover.GapOk(grid, first.x + dx, first.z + dz, 1.3)
					then
						room = true
					end
				end
			end
			if not room then
				covered[first] = true
				roadUnfilled += 1
				continue
			end
			-- The clump whose trees cover the most uncovered samples.
			local bestScore, bestFrom = 0, nil :: { number }?
			local before = #made
			for side = -1, 1, 2 do
				for _, lat in ipairs({ 26, 30, 34, 38 }) do
					for along = -16, 48, 8 do
						local cx = first.x - first.dz * side * lat + first.dx * along
						local cz = first.z + first.dx * side * lat + first.dz * along
						if latticeOk(cx, cz) then
							-- Score the spot by what a ring of trunks round it would cover.
							local score = 0
							for _, s in ipairs(live) do
								if not covered[s] then
									local dx, dz = s.x - cx, s.z - cz
									if dx * dx + dz * dz <= (TreeCover.RoadReach + 8) ^ 2 then
										score += 1
									end
								end
							end
							if score > bestScore then
								bestScore, bestFrom = score, { cx, cz }
							end
						end
					end
				end
			end
			local sample = first
			local function reaches(list: { Tree }): boolean
				for _, tree in ipairs(list) do
					local dx, dz = tree.x - sample.x, tree.z - sample.z
					if dx * dx + dz * dz <= TreeCover.RoadReach * TreeCover.RoadReach then
						return true
					end
				end
				return false
			end
			local done = false
			if bestFrom then
				done = placeNear(bestFrom[1], bestFrom[2], 10, 2, nil, reaches)
			end
			if not done then
				done = placeNear(first.x - first.dz * 28, first.z + first.dx * 28, 14, 2, nil, reaches)
			end
			if not done then
				done = placeNear(first.x + first.dz * 28, first.z - first.dx * 28, 14, 2, nil, reaches)
			end
			if not done then
				-- Anything within reach that fits at all.
				done = placeNear(first.x, first.z, TreeCover.RoadReach, 2, nil, reaches, true)
			end
			if not done then
				covered[first] = true
				roadUnfilled += 1
			else
				refresh()
				if #made == before then
					covered[first] = true
				end
			end
		end

		return made,
			{
				legacyGap = legacy.gap,
				legacyRoad = legacy.road,
				legacyKeepout = legacy.keepout,
				unfilledSquares = unfilled,
				unfilledRoad = roadUnfilled,
				singles = singles,
				noLane = noLane,
				grid = grid,
				counts = counts,
				woodTally = woodTally,
				sizeNo = sizeNo,
				clumps = clumpNo,
				placeNear = placeNear,
				live = live,
			}
	end

	-- 4. The count: new trees = relocated trees + (total - items). The movable
	-- trees in the densest places that nothing needs (their cell holds another
	-- tree, and so does every road sample's 40 studs) pay for a surplus; a
	-- padding pass spends a deficit.
	log("legacy drops: " .. legacyDropped)
	local made, info = plan()
	log(string.format("planned %d trees", #made))
	local want = env.total - #items + legacyDropped
	local extraGone: { [Tree]: boolean } = {}
	local extraDrops = 0
	if #made > want then
		local grid = info.grid :: Grid
		local counts = info.counts :: { [string]: number }
		local live = info.live :: { RoadSample }
		local removed: { [Tree]: boolean } = {}
		local function otherNear(x: number, z: number, reach: number, skip: Tree): boolean
			local found = false
			eachNear(grid, x, z, reach, function(o: Tree): boolean?
				if o ~= skip and not removed[o] then
					local dx, dz = o.x - x, o.z - z
					if dx * dx + dz * dz <= reach * reach then
						found = true
						return true
					end
				end
				return nil
			end)
			return found
		end
		local scored: { { tree: Tree, n: number } } = {}
		for _, tree in ipairs(ordered) do
			if not gone[tree] and not tree.anchor then
				local n = 0
				eachNear(grid, tree.x, tree.z, 30, function(o: Tree): boolean?
					if o ~= tree then
						local dx, dz = o.x - tree.x, o.z - tree.z
						if dx * dx + dz * dz < 900 then
							n += 1
						end
					end
					return nil
				end)
				table.insert(scored, { tree = tree, n = n })
			end
		end
		table.sort(scored, function(a, b)
			if a.n ~= b.n then
				return a.n > b.n
			end
			return (a.tree.index :: number) < (b.tree.index :: number)
		end)
		-- Pass 1: a tree whose cell holds another. Pass 2 (only if that was not
		-- enough, the ground having moved): a lone tree whose eight neighbouring
		-- cells all hold trees, so the hole it leaves is one cell, inside every limit.
		for pass = 1, 2 do
			for _, entry in ipairs(scored) do
				if extraDrops >= #made - want then
					break
				end
				local tree = entry.tree
				if extraGone[tree] then
					continue
				end
				local cx, cz = cellOf(tree.x), cellOf(tree.z)
				local key = cx .. "," .. cz
				local ok = (counts[key] or 0) > 1
				if not ok and pass == 2 and (counts[key] or 0) == 1 then
					ok = true
					for dx = -1, 1 do
						for dz = -1, 1 do
							if (dx ~= 0 or dz ~= 0) and (counts[(cx + dx) .. "," .. (cz + dz)] or 0) < 1 then
								ok = false
							end
						end
					end
				end
				if ok then
					for _, s in ipairs(live) do
						local dx, dz = s.x - tree.x, s.z - tree.z
						if
							dx * dx + dz * dz <= TreeCover.RoadReach * TreeCover.RoadReach
							and not otherNear(s.x, s.z, TreeCover.RoadReach, tree)
						then
							ok = false
							break
						end
					end
				end
				if ok then
					counts[key] -= 1
					removed[tree] = true
					extraGone[tree] = true
					extraDrops += 1
				end
			end
		end
		log(string.format("extra drops: %d of %d wanted", extraDrops, #made - want))
		-- Pass 3 (only if the standing trees could not pay for all of it): the plan
		-- is a tree or two over, so the planned tree in the densest place that
		-- nothing needs goes, under the same rules (its cell holds another or all
		-- eight neighbouring cells do, its clump keeps 3, every road sample's 40
		-- studs keeps a tree).
		local madeGone: { [NewTree]: boolean } = {}
		local madeDrops = 0
		if extraDrops < #made - want then
			local clumpSize: { [number]: number } = {}
			for _, m in ipairs(made) do
				clumpSize[m.clump] = (clumpSize[m.clump] or 0) + 1
			end
			local function gridTree(m: NewTree): Tree?
				local found: Tree? = nil
				eachNear(grid, m.x, m.z, 1, function(o: Tree): boolean?
					if o.x == m.x and o.z == m.z then
						found = o
						return true
					end
					return nil
				end)
				return found
			end
			local crowded: { { m: NewTree, n: number, i: number } } = {}
			for i, m in ipairs(made) do
				local n = 0
				eachNear(grid, m.x, m.z, 30, function(o: Tree): boolean?
					local dx, dz = o.x - m.x, o.z - m.z
					if (dx ~= 0 or dz ~= 0) and dx * dx + dz * dz < 900 then
						n += 1
					end
					return nil
				end)
				table.insert(crowded, { m = m, n = n, i = i })
			end
			table.sort(crowded, function(a, b)
				if a.n ~= b.n then
					return a.n > b.n
				end
				return a.i > b.i
			end)
			for _, entry in ipairs(crowded) do
				if extraDrops + madeDrops >= #made - want then
					break
				end
				local m = entry.m
				local g = gridTree(m)
				local cx, cz = cellOf(m.x), cellOf(m.z)
				local key = cx .. "," .. cz
				local ok = g ~= nil and (clumpSize[m.clump] == 1 or clumpSize[m.clump] > 3)
				if ok and (counts[key] or 0) <= 1 then
					ok = (counts[key] or 0) == 1
					for dx = -1, 1 do
						for dz = -1, 1 do
							if (dx ~= 0 or dz ~= 0) and (counts[(cx + dx) .. "," .. (cz + dz)] or 0) < 1 then
								ok = false
							end
						end
					end
				end
				if ok and g then
					for _, sample in ipairs(live) do
						local dx, dz = sample.x - m.x, sample.z - m.z
						if
							dx * dx + dz * dz <= TreeCover.RoadReach * TreeCover.RoadReach
							and not otherNear(sample.x, sample.z, TreeCover.RoadReach, g)
						then
							ok = false
							break
						end
					end
				end
				if ok and g then
					counts[key] -= 1
					removed[g] = true
					madeGone[m] = true
					clumpSize[m.clump] -= 1
					madeDrops += 1
				end
			end
			local kept: { NewTree } = {}
			for _, m in ipairs(made) do
				if not madeGone[m] then
					table.insert(kept, m)
				end
			end
			made = kept
		end
		log(string.format("planned-tree drops: %d", madeDrops))
	end
	local relocatedTrees: { Tree } = {}
	for tree in pairs(gone) do
		table.insert(relocatedTrees, tree)
	end
	for tree in pairs(extraGone) do
		table.insert(relocatedTrees, tree)
	end
	table.sort(relocatedTrees, function(a: Tree, b: Tree): boolean
		return (a.index :: number) < (b.index :: number)
	end)
	for _, tree in ipairs(relocatedTrees) do
		table.insert(relocated, { index = tree.index :: number, x = tree.x, z = tree.z })
	end
	trees = made

	-- Padding: clumps in the emptiest ground (farthest from any tree, weighted by
	-- the density table) until the count is whole.
	local function needed(): number
		return env.total - (#items - #relocated) - #trees
	end
	local padded = 0
	if needed() > 0 then
		local grid = info.grid :: Grid
		local candidates: { { x: number, z: number, score: number } } = {}
		local half = WorldLayout.WorldHalf
		for x = -half + 8, half - 8, 16 do
			for z = -half + 8, half - 8, 16 do
				if latticeOk(x, z) then
					local place = TreeCover.ClassOf(x, z)
					if place ~= "ferryisle" then
						local d = TreeCover.NearestDistance(grid, x, z, 120) or 120
						table.insert(candidates, {
							x = x,
							z = z,
							score = d * math.sqrt(TreeCover.Density[place] or 1) + (hashPos(x, z) % 7) * 0.01,
						})
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			if a.x ~= b.x then
				return a.x < b.x
			end
			return a.z < b.z
		end)
		local placeNear = info.placeNear :: (number, number, number, number, number?, any?, boolean?) -> boolean
		local k = 1
		while needed() > 0 and k <= #candidates do
			local c = candidates[k]
			k += 1
			if (TreeCover.NearestDistance(grid, c.x, c.z, 60) or 60) >= 40 then
				local before = #trees
				if placeNear(c.x, c.z, 0, 4, needed()) then
					padded += #trees - before
				end
			end
		end
	end
	return {
		trees = trees,
		relocated = relocated,
		report = {
			legacyDropped = legacyDropped,
			legacy = legacy,
			extraDrops = extraDrops,
			padded = padded,
			unfilledSquares = info.unfilledSquares,
			unfilledRoad = info.unfilledRoad,
			singles = info.singles,
			noLane = info.noLane,
			clumps = info.clumps,
		},
	}
end

return TreeCover
