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
-- (The old wildWoodsNear only knew starter, hills, snow and volcano, so Bayou
-- and Mesa filler would have got oak or birch.) Deterministic: PickWood hashes
-- the seed and the point.

local BiomeData = require(script.Parent.Parent.BiomeData)

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

return TreeSpread
