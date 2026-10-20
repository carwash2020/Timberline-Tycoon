--!strict
-- TreeSpread (WORLD-SPREAD, T356): the plan for spreading trees over the whole
-- map. Pure plan code: no services, no instances.
--
-- WoodsNear(x, z) is the wood mix for a new wild tree at a point:
--   * within SpawnOak studs of the spawn pad: oak only (the tutorial's wood);
--   * otherwise the nearest zone by edge distance (centre distance minus the
--     disc's radius) among every zone with a BiomeData tree table: starter,
--     hills, snow, volcano, grove, bayou, mesa;
--   * inside that zone's disc: its own woods, about 73 / 22 / 5 percent
--     (dominant, second, accent); outside the disc: the zone's plain woods
--     (the special woods, frostwood, emberwood, ironwood, bog cypress and the
--     glow woods, stay in their own discs);
--   * inside a 15 stud border band of another zone's disc, that zone's plain
--     woods join at 25 percent.
-- Skipped(): the thinned trees (TreeSpreadData.Skipped) and the relocated ones
-- (TreeSpreadData.Relocated, T400: TreeCover pays for each with a cover tree),
-- applied where MapBuilder plants WorldPlan.Trees(). The spread itself is
-- TreeCover's (WorldPlan.SpreadTrees reads TreeSpreadData.Cover). PlanSkip is the rule that produced that data (the
-- spec runs it again and compares, so the data cannot go stale).
-- (The old wildWoodsNear only knew starter, hills, snow and volcano, so Bayou
-- and Mesa filler would have got oak or birch.) Deterministic: PickWood hashes
-- the seed and the point.

local BiomeData = require(script.Parent.Parent.BiomeData)
local Clearance = require(script.Parent.Clearance)
local TreeSpreadData = require(script.Parent.TreeSpreadData)

local TreeSpread = {}

export type Mix = { { woodId: string, weight: number } }

TreeSpread.SpawnX = 0
TreeSpread.SpawnZ = 40 -- the spawn pad
TreeSpread.SpawnOak = 70 -- studs from the pad where only oak grows
TreeSpread.BorderBand = 15 -- studs of a neighbour's disc where its plain woods join
TreeSpread.BorderShare = 0.25

type ZoneWoods = {
	inner: { { string | number } }, -- { woodId, weight } inside the disc
	outer: { { string | number } }, -- the plain woods outside it
}

-- Weights sum to 1. Wood ids are WoodData's (append-only).
local ZONES: { [string]: ZoneWoods } = {
	starter = {
		inner = { { "oak", 0.78 }, { "birch", 0.22 } },
		outer = { { "oak", 0.78 }, { "birch", 0.22 } },
	},
	hills = {
		inner = { { "pine", 0.73 }, { "maple", 0.22 }, { "oak", 0.05 } },
		outer = { { "pine", 0.73 }, { "maple", 0.22 }, { "oak", 0.05 } },
	},
	snow = {
		inner = { { "frostwood", 0.73 }, { "pine", 0.22 }, { "birch", 0.05 } },
		outer = { { "pine", 0.78 }, { "birch", 0.22 } },
	},
	volcano = {
		inner = { { "emberwood", 0.73 }, { "pine", 0.22 }, { "birch", 0.05 } },
		outer = { { "pine", 0.78 }, { "birch", 0.22 } },
	},
	grove = {
		inner = { { "phantomwood", 0.78 }, { "oak", 0.22 } },
		outer = { { "oak", 0.78 }, { "birch", 0.22 } },
	},
	bayou = {
		inner = { { "bogcypress", 0.73 }, { "willow", 0.22 }, { "oak", 0.05 } },
		outer = { { "oak", 0.78 }, { "birch", 0.22 } },
	},
	mesa = {
		inner = { { "ironwood", 0.73 }, { "oak", 0.22 }, { "birch", 0.05 } },
		outer = { { "oak", 0.78 }, { "birch", 0.22 } },
	},
}

-- Zone ids in a fixed order (so a tie is broken the same way every run).
TreeSpread.ZoneIds = { "starter", "hills", "snow", "volcano", "grove", "bayou", "mesa" } :: { string }

type Disc = { x: number, z: number, radius: number }

local function discOf(id: string): Disc?
	local region = BiomeData.RegionDiscs[id]
	if region then
		return region
	end
	local def = BiomeData.Get(id)
	local area = if def then def.area else nil
	if area then
		return { x = area.x, z = area.z, radius = area.radius }
	end
	return nil
end

-- Every zone's disc and its edge distance from (x, z), nearest first (negative
-- inside the disc).
function TreeSpread.ZonesNear(x: number, z: number): { { id: string, edge: number } }
	local out: { { id: string, edge: number } } = {}
	for _, id in ipairs(TreeSpread.ZoneIds) do
		local disc = discOf(id)
		if disc then
			table.insert(out, { id = id, edge = math.sqrt((x - disc.x) ^ 2 + (z - disc.z) ^ 2) - disc.radius })
		end
	end
	table.sort(out, function(a, b)
		if a.edge ~= b.edge then
			return a.edge < b.edge
		end
		return a.id < b.id
	end)
	return out
end

local function addMix(into: { [string]: number }, order: { string }, list: { { string | number } }, scale: number)
	for _, entry in ipairs(list) do
		local id = entry[1] :: string
		if into[id] == nil then
			into[id] = 0
			table.insert(order, id)
		end
		into[id] += (entry[2] :: number) * scale
	end
end

function TreeSpread.WoodsNear(x: number, z: number): Mix
	if math.sqrt((x - TreeSpread.SpawnX) ^ 2 + (z - TreeSpread.SpawnZ) ^ 2) <= TreeSpread.SpawnOak then
		return { { woodId = "oak", weight = 1 } }
	end
	local zones = TreeSpread.ZonesNear(x, z)
	local nearest = zones[1]
	local weights: { [string]: number } = {}
	local order: { string } = {}
	local own = ZONES[nearest.id]
	local border = zones[2]
	local share = 0
	if border and border.edge <= TreeSpread.BorderBand and border.edge > -1e9 then
		share = TreeSpread.BorderShare
	end
	addMix(weights, order, if nearest.edge <= 0 then own.inner else own.outer, 1 - share)
	if share > 0 then
		addMix(weights, order, ZONES[border.id].outer, share)
	end
	local out: Mix = {}
	for _, id in ipairs(order) do
		table.insert(out, { woodId = id, weight = weights[id] })
	end
	table.sort(out, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.woodId < b.woodId
	end)
	return out
end

-- A deterministic number in [0, 1) from a seed and a point.
function TreeSpread.Roll(seed: number, x: number, z: number): number
	local h = (math.floor(x * 10) * 73856093 + math.floor(z * 10) * 19349663 + seed * 83492791) % 2147483647
	h = (h * 1103515245 + 12345) % 2147483648
	h = (h * 1103515245 + 12345) % 2147483648
	return h / 2147483648
end

-- The wood of the tree at (x, z): the mix's pick for this seed's roll.
function TreeSpread.PickWood(x: number, z: number, seed: number): string
	local mix = TreeSpread.WoodsNear(x, z)
	local roll = TreeSpread.Roll(seed, x, z)
	local acc = 0
	for _, entry in ipairs(mix) do
		acc += entry.weight
		if roll < acc then
			return entry.woodId
		end
	end
	return mix[#mix].woodId
end

---------------------------------------------------------------------------
-- Thinning
---------------------------------------------------------------------------

TreeSpread.Cell = 100 -- the density grid
TreeSpread.Cap = 25 -- no cell holds more (the spec's ceiling)
TreeSpread.Target = 14 -- movable trees are thinned toward this where the cell can reach it

export type Item = {
	x: number,
	z: number,
	index: number?, -- the tree's place in WorldPlan.Trees(); nil for trees of other lists
	movable: boolean, -- a wild tree of a stand, the forest ring, a clump or a grove clump
	anchor: boolean?, -- a clump's largest size class (never dropped for density)
	r: number?, -- the trunk's disc (trunk radius plus 1), for the overlap rule
}

-- Something a tree may not stand in: a boulder (gap 2), a cluster rock or a
-- scenery piece (gap 0).
export type Obstacle = { x: number, z: number, r: number, gap: number }

local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

-- Which movable trees to drop: for every 100 stud cell holding more than
-- Target trees (all lists counted), movable non-anchor trees go, lowest seeded
-- hash rank first, until the cell is at Target or the movable trees run out.
-- Cells are walked in order of x, then z. Fixed trees (supply, the first 331,
-- the town and plot rings, the added trees, the strip, palms, Lanternwood and
-- the Reach) and anchors never go. Returns the dropped items' indices, sorted.
function TreeSpread.PlanSkip(items: { Item }, obstacles: { Obstacle }?): { number }
	local cells: { [string]: { total: number, movable: { Item }, cx: number, cz: number } } = {}
	for _, item in ipairs(items) do
		local cx, cz = math.floor(item.x / TreeSpread.Cell), math.floor(item.z / TreeSpread.Cell)
		local key = cx .. "," .. cz
		local cell = cells[key]
		if not cell then
			cell = { total = 0, movable = {}, cx = cx, cz = cz }
			cells[key] = cell
		end
		cell.total += 1
		if item.movable and not item.anchor and item.index ~= nil then
			table.insert(cell.movable, item)
		end
	end
	local order: { string } = {}
	for key in pairs(cells) do
		table.insert(order, key)
	end
	table.sort(order, function(a, b)
		local ca, cb = cells[a], cells[b]
		if ca.cx ~= cb.cx then
			return ca.cx < cb.cx
		end
		return ca.cz < cb.cz
	end)
	local dropped: { number } = {}
	for _, key in ipairs(order) do
		local cell = cells[key]
		if cell.total > TreeSpread.Target and #cell.movable > 0 then
			table.sort(cell.movable, function(a, b)
				local ra, rb =
					hashString("T356 thin " .. tostring(a.index)), hashString("T356 thin " .. tostring(b.index))
				if ra ~= rb then
					return ra < rb
				end
				return (a.index :: number) < (b.index :: number)
			end)
			local drop = math.min(#cell.movable, cell.total - TreeSpread.Target)
			for i = 1, drop do
				table.insert(dropped, cell.movable[i].index :: number)
			end
		end
	end
	-- Then the overlap rule: a movable tree whose trunk meets a rock or scenery
	-- piece, or another tree's trunk (closer than 2 studs; a fixed tree wins, and
	-- of two movable trees the higher index goes) is dropped, anchors too.
	if obstacles then
		local gone: { [number]: boolean } = {}
		for _, index in ipairs(dropped) do
			gone[index] = true
		end
		local grid = Clearance.NewGrid()
		for _, o in ipairs(obstacles) do
			Clearance.Add(grid, "o", "obstacle", Clearance.Disc(o.x, o.z, o.r), o.gap)
		end
		local trees = Clearance.NewGrid()
		for i, item in ipairs(items) do
			if not (item.index ~= nil and gone[item.index]) then
				Clearance.Add(trees, tostring(i), "tree", Clearance.Disc(item.x, item.z, item.r or 1.8), i)
			end
		end
		for i, item in ipairs(items) do
			local index = item.index
			if item.movable and index ~= nil and not gone[index] then
				local disc = Clearance.Disc(item.x, item.z, item.r or 1.8)
				local hit = false
				for _, e in ipairs(Clearance.Near(grid, disc, 2, "obstacle")) do
					if Clearance.Closer(disc, e.shape, e.tag :: number) then
						hit = true
					end
				end
				if not hit then
					for _, e in ipairs(Clearance.Near(trees, disc, 2, "tree")) do
						local other = items[e.tag :: number]
						if e.tag ~= i and Clearance.Closer(disc, e.shape, 2) then
							-- A fixed neighbour wins; of two movable trees the higher index goes.
							if not other.movable or other.index == nil or (other.index :: number) < index then
								hit = true
							end
						end
					end
				end
				if hit then
					table.insert(dropped, index)
					gone[index] = true
				end
			end
		end
	end
	table.sort(dropped)
	return dropped
end

local skipSet: { [string]: boolean }? = nil
local relocSet: { [string]: boolean }? = nil

local function posKey(x: number, z: number): string
	return string.format("%.2f,%.2f", x, z)
end

-- Whether the tree at (x, z) of WorldPlan.Trees() is thinned by PlanSkip (not planted).
function TreeSpread.SkippedBase(x: number, z: number): boolean
	local set: { [string]: boolean } = skipSet or {}
	if skipSet == nil then
		for _, entry in ipairs(TreeSpreadData.Skipped) do
			set[posKey(entry.x, entry.z)] = true
		end
		skipSet = set
	end
	return set[posKey(x, z)] == true
end

-- Whether the tree at (x, z) of WorldPlan.Trees() was relocated by TreeCover
-- (a broken gap, buffer or keep-out, or the densest places): it is paid for by
-- a cover tree somewhere that lacked one.
function TreeSpread.Relocated(x: number, z: number): boolean
	local set: { [string]: boolean } = relocSet or {}
	if relocSet == nil then
		for _, entry in ipairs(TreeSpreadData.Relocated) do
			set[posKey(entry.x, entry.z)] = true
		end
		relocSet = set
	end
	return set[posKey(x, z)] == true
end

-- Whether the tree at (x, z) of WorldPlan.Trees() is not planted: thinned or relocated.
function TreeSpread.Skipped(x: number, z: number): boolean
	return TreeSpread.SkippedBase(x, z) or TreeSpread.Relocated(x, z)
end

-- How many trees of WorldPlan.Trees() are not planted.
function TreeSpread.SkipCount(): number
	return #TreeSpreadData.Skipped + #TreeSpreadData.Relocated
end

return TreeSpread
