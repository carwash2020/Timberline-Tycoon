--!strict
-- Scatter (T414d-2): ground cover, shrubs, rocks, logged stumps, saplings and
-- snags along every road. Pure and seeded: the server and every client work
-- out the same plan from fixed data, so nothing is replicated.
--   * Corridor fill: each road is walked in 24-stud windows, both sides; each
--     window gets a cluster (grass, a shrub or fern, a pebble, a large rock or
--     a stump) 18 to 40 studs off the centreline. A keep-out that rejects a
--     spot sends the window on to other offsets.
--   * Meadow gaps: a Poisson-disc per region (ScatterZones) places saplings
--     and, in the far regions, the odd dead snag.
--   * Keep-outs (KeepOut): roads from the centreline (main 18, branch 14),
--     junctions, the town zone (its footpaths, mill lanes, belts, doors and
--     aprons), shop doors 10, docks, bridges and abutments, plot pads +4,
--     the regions' own builds, water, and slopes over 35 degrees.
--   * Tiers: "cover" (under 4 studs, client only, never collides) and "built"
--     (stumps, large rocks, saplings, snags: the server builds them once; only
--     stumps and rocks collide). Built() also keeps solids clear of every tree,
--     boulder and scenery piece, so the world overlap lint stays clean.
-- Seeded with Kit.rng (Lune has no Random), the same in the preview.

local BayouData = require(script.Parent.Parent.Regions.BayouData)
local BiomeData = require(script.Parent.Parent.BiomeData)
local Kit = require(script.Parent.Parent.Art.Kit)
local MesaData = require(script.Parent.Parent.Regions.MesaData)
local ScatterZones = require(script.Parent.ScatterZones)
local ShopPins = require(script.Parent.ShopPins)
local TerrainGen = require(script.Parent.TerrainGen)
local UndergroundData = require(script.Parent.UndergroundData)
local WorldLayout = require(script.Parent.WorldLayout)

local Scatter = {}

Scatter.Seed = 414
Scatter.Window = 24 -- studs of road per cluster
Scatter.BandNear = 18
Scatter.BandFar = 40
Scatter.MainKeep = 18 -- from a main road's centreline
Scatter.BranchKeep = 14
Scatter.FootKeep = 5
Scatter.DoorKeep = 10
Scatter.MaxSlope = 0.7 -- tan 35 degrees
Scatter.SolidSlope = 0.15 -- a stump or rock stands on near level ground
Scatter.CoverMax = 4 -- studs: cover is built on the client under this
Scatter.StumpSeat = 0.05
-- Studs round the camera the client builds cover within, per quality tier, and where it fades
-- (full to the first, thinning to nothing at the radius).
Scatter.CoverRadius = { high = 160, medium = 130, low = 100 } :: { [string]: number }
Scatter.FadeFrom = 0.75 -- of the radius

export type Item = {
	kind: string, -- grass fern shrub flower pebble reed scrub | rock stump sapling snag
	tier: string, -- "cover" or "built"
	solid: boolean,
	region: string,
	x: number,
	y: number, -- HeightAt (a rock's builder sinks it 30%)
	z: number,
	yaw: number,
	variant: number, -- 0 to 5: the look (one template per kind, region and variant)
	size: number, -- studs across (from the variant)
	seed: number,
	cluster: number, -- 0 for the meadow gaps
	road: string?,
}

Scatter.Variants = 6

-- Studs across for a kind's variant: a stump 2.2 to 3.2, a large rock 4.2 to 6.4, a sapling 3.4 to 4.8,
-- a snag 5 to 7 tall, cover under 4.
function Scatter.SizeOf(kind: string, variant: number): number
	if kind == "rock" then
		return 4.2 + variant * 0.44
	elseif kind == "stump" then
		return 2.2 + variant * 0.2
	elseif kind == "sapling" then
		return 3.4 + variant * 0.28
	elseif kind == "snag" then
		return 5 + variant * 0.4
	end
	return 1.4 + variant * 0.4
end

-- Docks, bridges, abutments and builds with no pin: centre and radius (footprint plus the 6 stud keep-out).
local SITES: { { x: number, z: number, r: number } } = {
	{ x = WorldLayout.FerryDockX, z = WorldLayout.FerryDockZ, r = 30 },
	{ x = WorldLayout.CarFerryMainlandX, z = WorldLayout.CarFerryMainlandZ, r = 54 }, -- deck 18 x 84, plus 6
	{ x = WorldLayout.CarFerryIslandX, z = WorldLayout.CarFerryIslandZ, r = 54 },
	{ x = WorldLayout.BridgeCenterX, z = WorldLayout.BridgeCenterZ, r = 40 },
	{ x = WorldLayout.BoothX, z = WorldLayout.BoothZ, r = 22 },
	{ x = -40, z = 720, r = 30 }, -- the gate lodge
	{ x = WorldLayout.SecretCaveX, z = WorldLayout.SecretCaveZ, r = WorldLayout.SecretCaveRadius + 6 },
}

---------------------------------------------------------------------------
-- Keep-outs
---------------------------------------------------------------------------

type RoadLine = { name: string, line: WorldLayout.FastLine, keep: number }
local roadLines: { RoadLine } = {}
for _, road in ipairs(WorldLayout.Roads) do
	local keep = if road.width >= 32
		then Scatter.MainKeep
		elseif road.width > 16 then Scatter.BranchKeep
		else Scatter.BranchKeep
	table.insert(roadLines, { name = road.name, line = WorldLayout.FastLine(road.points), keep = keep })
end
local tunnelLine = WorldLayout.FastLine(WorldLayout.TunnelPoints)

-- HeightAt of the last point asked: a candidate asks for its height twice (water, then the item).
local lastX, lastZ, lastY = math.huge, math.huge, 0
local function heightAt(x: number, z: number): number
	if x ~= lastX or z ~= lastZ then
		lastX, lastZ, lastY = x, z, TerrainGen.HeightAt(x, z)
	end
	return lastY
end

local function inDisc(x: number, z: number, cx: number, cz: number, r: number): boolean
	return (x - cx) ^ 2 + (z - cz) ^ 2 <= r * r
end

-- Why (x, z) may not carry anything, or nil. `pad` grows every rule (a solid asks for more room).
function Scatter.KeepOut(x: number, z: number, pad: number?): string?
	local g = pad or 0
	local half = WorldLayout.WorldHalf - 60
	if math.abs(x) > half or math.abs(z) > half then
		return "edge"
	end
	for _, r in ipairs(roadLines) do
		if WorldLayout.FastDistance(r.line, x, z, r.keep + g + 1) < r.keep + g then
			return "road " .. r.name
		end
	end
	for _, j in ipairs(WorldLayout.Junctions) do
		if inDisc(x, z, j.at.X, j.at.Y, j.radius + 4 + g) then
			return "junction"
		end
	end
	local tz = WorldLayout.TownZone
	if x > tz.x0 - 6 - g and x < tz.x1 + 6 + g and z > tz.z0 - 6 - g and z < tz.z1 + 6 + g then
		return "town"
	end
	if WorldLayout.NearPlotPad(x, z, 4 + g) or WorldLayout.FlatWeight(x, z) > 0 then
		return "plot or flat ground"
	end
	for _, pin in ipairs(ShopPins.All()) do
		if not pin.cloud and inDisc(x, z, pin.x, pin.z, Scatter.DoorKeep + g) then
			return "shop door " .. pin.id
		end
	end
	for _, s in ipairs(SITES) do
		if inDisc(x, z, s.x, s.z, s.r + g) then
			return "dock, bridge or lodge"
		end
	end
	if
		WorldLayout.TreeBlocked(x, z)
		or WorldLayout.OnTollSpur(x, z)
		or BayouData.Blocked(x, z, 4 + g)
		or MesaData.Blocked(x, z, 4 + g)
	then
		return "build"
	end
	if WorldLayout.FastDistance(tunnelLine, x, z, 40) < WorldLayout.TunnelWidth / 2 + 16 + g then
		return "tunnel"
	end
	for _, cave in ipairs(UndergroundData.Caves) do
		if math.abs(x - cave.x) < 12 + g and math.abs(z - cave.z) < cave.sz / 2 + 4 + g then
			return "cave"
		end
	end
	if TerrainGen.WaterLevelAt(x, z) ~= nil then
		return "water"
	end
	return nil
end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------

function Scatter.RegionOf(x: number, z: number): string
	local special = BiomeData.RegionAt(x, z)
	if special then
		return special
	end
	for _, zone in ipairs(ScatterZones.Zones) do
		if zone.kind ~= "town" and zone.kind ~= "cave" and inDisc(x, z, zone.center.X, zone.center.Y, zone.radius) then
			return zone.id
		end
	end
	return "country"
end

-- Where no loggers have been: the beach, the isles and the two reserved regions keep their own look.
local STUMP_REGIONS: { [string]: boolean } = { shore = false, isle = false, bayou = false, mesa = false }
local FAR_REGIONS: { [string]: boolean } =
	{ hills = true, snow = true, volcano = true, gloam = true, mesa = true, bayou = true }
Scatter.Regions =
	{ "starter", "hills", "meadow-east", "snow", "volcano", "gloam", "shore", "isle", "bayou", "mesa", "country" }

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------

local planned: { Item }? = nil
local slice: (() -> ())? = nil -- called between windows so a client can yield (set by generate)
local builtCache: { Item }? = nil

-- Height and TerrainGen.SlopeAt's rise over 3 studs, reusing the height already asked.
local function level(x: number, z: number): (number, number)
	local y = heightAt(x, z)
	local rise = math.max(
		math.abs(TerrainGen.HeightAt(x + 3, z) - y),
		math.abs(TerrainGen.HeightAt(x, z + 3) - y),
		math.abs(TerrainGen.HeightAt(x - 3, z) - y),
		math.abs(TerrainGen.HeightAt(x, z - 3) - y)
	)
	return y, rise / 3
end

-- One cluster at (ax, az): grass, a shrub or fern, one accent, sometimes a flower.
local function cluster(
	items: { Item },
	id: number,
	ax: number,
	az: number,
	road: string?,
	flowers: { [string]: boolean }
)
	local rng = Kit.rng(Scatter.Seed * 31 + id * 7 + 1)
	local region = Scatter.RegionOf(ax, az)
	local function add(kind: string, tier: string, solid: boolean, dx: number, dz: number)
		local x, z = ax + dx, az + dz
		local pad = if solid then 2 else 0
		if Scatter.KeepOut(x, z, pad) then
			return
		end
		local y, slope = level(x, z)
		if slope > (if solid then Scatter.SolidSlope else Scatter.MaxSlope) then
			return
		end
		local variant = rng:int(0, Scatter.Variants - 1)
		table.insert(items, {
			kind = kind,
			tier = tier,
			solid = solid,
			region = region,
			x = x,
			y = y,
			z = z,
			yaw = rng:range(0, math.pi * 2),
			variant = variant,
			size = Scatter.SizeOf(kind, variant),
			seed = Scatter.Seed + id * 13 + #items,
			cluster = id,
			road = road,
		})
	end
	local function around(r: number): (number, number)
		local a = rng:range(0, math.pi * 2)
		local d = rng:range(0.8, r)
		return math.cos(a) * d, math.sin(a) * d
	end
	-- The first piece sits on the anchor itself, so an open anchor always yields a cluster.
	add(if region == "bayou" then "reed" else "grass", "cover", false, 0, 0)
	local gx, gz = around(3)
	add("grass", "cover", false, gx, gz)
	local pick = rng:next()
	gx, gz = around(3)
	if region == "mesa" then
		add("scrub", "cover", false, gx, gz)
	elseif pick < 0.6 then
		add("shrub", "cover", false, gx, gz)
	else
		add("fern", "cover", false, gx, gz)
	end
	local accent = rng:next()
	gx, gz = around(4)
	if accent >= 0.3 and accent < 0.55 then
		add("rock", "built", true, gx, gz)
	elseif accent >= 0.55 and accent < 0.85 and STUMP_REGIONS[region] ~= false then
		add("stump", "built", true, gx, gz)
	else
		add("pebble", "cover", false, gx, gz)
	end
	-- At most one flower accent per 20 x 20 square (the square of the flower's own spot).
	if rng:next() < 0.35 and region ~= "snow" then
		gx, gz = around(3)
		local key = math.floor((ax + gx) / 20) .. "," .. math.floor((az + gz) / 20)
		if not flowers[key] then
			local before = #items
			add("flower", "cover", false, gx, gz)
			if #items > before then
				flowers[key] = true
			end
		end
	end
end

-- Every road, both sides, a cluster per window.
local function corridor(items: { Item }, flowers: { [string]: boolean }): number
	local id = 0
	for _, road in ipairs(WorldLayout.Roads) do
		local pts = road.points
		local walked = 0
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			if len > 1e-3 then
				local dir = (b - a) / len
				local nx, nz = -dir.Y, dir.X
				-- Windows start where the previous segment's leftover ended.
				local s = Scatter.Window / 2 - (walked % Scatter.Window)
				if s < 0 then
					s += Scatter.Window
				end
				while s < len do
					if slice then
						slice()
					end
					for _, side in ipairs({ -1, 1 }) do
						id += 1
						local rng = Kit.rng(Scatter.Seed * 17 + id)
						local before = #items
						-- Random offsets first, then a sweep of the whole band.
						for attempt = 1, 18 do
							local off, along
							if attempt <= 5 then
								off = rng:range(Scatter.BandNear + 1, Scatter.BandFar - 4)
								along = rng:range(-8, 8)
							else
								off = Scatter.BandNear + 2 * (attempt - 5) % 22 + 1
								along = 0
							end
							local px = a.X + dir.X * (s + along) + nx * side * off
							local pz = a.Y + dir.Y * (s + along) + nz * side * off
							cluster(items, id, px, pz, road.name, flowers)
							if #items > before then
								break
							end
						end
					end
					s += Scatter.Window
				end
				walked += len
			end
		end
	end
	return id
end

-- Bridson's Poisson-disc over a disc: saplings, and snags in the far regions. The Bayou and Red Mesa
-- discs get full clusters instead (reeds, dry scrub), since their roads only just reach them.
local function meadow(items: { Item }, firstId: number, flowers: { [string]: boolean })
	local id = firstId
	local fields: { { id: string, x: number, z: number, r: number, gap: number, clusters: boolean } } = {}
	for _, zone in ipairs(ScatterZones.Zones) do
		if zone.kind ~= "town" and zone.kind ~= "cave" and zone.kind ~= "shore" and zone.kind ~= "isle" then
			table.insert(fields, {
				id = zone.id,
				x = zone.center.X,
				z = zone.center.Y,
				r = zone.radius - 8,
				gap = 36 / math.sqrt(zone.density),
				clusters = false,
			})
		end
	end
	for _, name in ipairs({ "bayou", "mesa" }) do
		local d = BiomeData.RegionDiscs[name]
		table.insert(fields, { id = name, x = d.x, z = d.z, r = d.radius - 8, gap = 34, clusters = true })
	end
	for fi, field in ipairs(fields) do
		local rng = Kit.rng(Scatter.Seed * 101 + fi)
		local cx, cz, R, minDist = field.x, field.z, field.r, field.gap
		local points: { Vector2 } = {}
		local active: { Vector2 } = {}
		local function ok(p: Vector2): boolean
			if (p.X - cx) ^ 2 + (p.Y - cz) ^ 2 > R * R then
				return false
			end
			for _, q in ipairs(points) do
				if (q - p).Magnitude < minDist then
					return false
				end
			end
			return true
		end
		local first = Vector2.new(cx, cz)
		table.insert(points, first)
		table.insert(active, first)
		while #active > 0 and #points < 60 do
			local at = rng:int(1, #active)
			local base = active[at]
			local found = false
			for _ = 1, 20 do
				local a = rng:range(0, math.pi * 2)
				local d = rng:range(minDist, minDist * 2)
				local p = Vector2.new(base.X + math.cos(a) * d, base.Y + math.sin(a) * d)
				if ok(p) then
					table.insert(points, p)
					table.insert(active, p)
					found = true
					break
				end
			end
			if not found then
				table.remove(active, at)
			end
		end
		for _, p in ipairs(points) do
			id += 1
			local x, z = p.X, p.Y
			if field.clusters then
				cluster(items, id, x, z, nil, flowers)
			elseif not Scatter.KeepOut(x, z, 0) then
				local y, slope = level(x, z)
				if slope <= Scatter.MaxSlope then
					local snag = FAR_REGIONS[field.id] == true and rng:next() < 0.4
					local variant = rng:int(0, Scatter.Variants - 1)
					table.insert(items, {
						kind = if snag then "snag" else "sapling",
						tier = "built",
						solid = false,
						region = field.id,
						x = x,
						y = y,
						z = z,
						yaw = rng:range(0, math.pi * 2),
						variant = variant,
						size = Scatter.SizeOf(if snag then "snag" else "sapling", variant),
						seed = Scatter.Seed + id * 13,
						cluster = 0,
					})
				end
			end
		end
	end
end

local function generate(pause: (() -> ())?): { Item }
	if planned then
		return planned
	end
	slice = pause
	local items: { Item } = {}
	local flowers: { [string]: boolean } = {}
	local last = corridor(items, flowers)
	meadow(items, last, flowers)
	planned = items
	slice = nil
	return items
end

-- Everything under 4 studs: the client builds it, nothing collides.
-- `pause` (optional) is called between windows: a client passes its yield.
function Scatter.Cover(pause: (() -> ())?): { Item }
	local out: { Item } = {}
	for _, item in ipairs(generate(pause)) do
		if item.tier == "cover" then
			table.insert(out, item)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Built items: the server's, kept clear of trees, boulders and scenery
---------------------------------------------------------------------------

-- Radii the world overlap lint (OverlapCheck) uses.
function Scatter.Radius(item: Item): number
	if item.kind == "rock" then
		return item.size * 0.7
	elseif item.kind == "stump" then
		return item.size * 0.5 * 1.42
	end
	return item.size * 0.25
end

-- Discs a built item must stay clear of: { x, z, r, gap }.
local function obstacles(): { { number } }
	local WorldPlan = require(script.Parent.WorldPlan)
	local BuiltMoves = require(script.Parent.BuiltMoves)
	local TreeSpread = require(script.Parent.TreeSpread)
	local WoodData = require(script.Parent.Parent.WoodData)
	local out: { { number } } = {}
	local function trees(list: { any })
		for _, spot in ipairs(list) do
			local p = spot.position
			if not TreeSpread.Skipped(p.X, p.Z) then
				local wood = WoodData.Get(spot.woodId or "palmwood")
				local shape = if wood and wood.v2 then wood.v2.shape else nil
				table.insert(out, { p.X, p.Z, (if shape then shape.trunkThickness else 1.6) / 2 + 1, 2 })
			end
		end
	end
	trees(WorldPlan.Trees())
	trees(WorldPlan.StripTrees())
	trees(WorldPlan.FerryPalms())
	trees(WorldPlan.Lanternwood())
	trees(WorldPlan.RegionTrees())
	trees(WorldPlan.ReachTrees())
	trees(WorldPlan.AddedTrees())
	trees(WorldPlan.NearGrove())
	trees(WorldPlan.SpreadTrees())
	for _, b in ipairs(BuiltMoves.Boulders(WorldPlan, TerrainGen)) do
		table.insert(out, { b.position.X, b.position.Z, b.size * 0.86, 2 })
	end
	for _, b in ipairs(BuiltMoves.MeadowBoulders(WorldPlan, TerrainGen)) do
		table.insert(out, { b.position.X, b.position.Z, b.size * 0.86, 2 })
	end
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		for _, rock in ipairs(c.rocks) do
			table.insert(out, { rock.position.X, rock.position.Z, rock.size * 0.5, 1 })
		end
	end
	for _, s in ipairs(BuiltMoves.Scenery(WorldPlan, TerrainGen)) do
		table.insert(out, { s.center.X, s.center.Z, s.radius, 1 })
	end
	return out
end

-- The server's items: stumps, large rocks, saplings, snags. A solid or a sapling clear of every tree,
-- boulder and scenery piece; a stump or rock also 2 studs clear of the others.
function Scatter.Built(pause: (() -> ())?): { Item }
	if builtCache then
		return builtCache
	end
	local plan = generate(pause)
	local grid: { [string]: { { number } } } = {}
	local cell = 24
	for _, o in ipairs(obstacles()) do
		for cx = math.floor((o[1] - o[3] - 8) / cell), math.floor((o[1] + o[3] + 8) / cell) do
			for cz = math.floor((o[2] - o[3] - 8) / cell), math.floor((o[2] + o[3] + 8) / cell) do
				local key = cx .. "," .. cz
				local list = grid[key] or {}
				grid[key] = list
				table.insert(list, o)
			end
		end
	end
	local out: { Item } = {}
	local solids: { Item } = {}
	for _, item in ipairs(plan) do
		if item.tier == "built" then
			local r = Scatter.Radius(item)
			local clear = true
			for _, o in ipairs(grid[math.floor(item.x / cell) .. "," .. math.floor(item.z / cell)] or {}) do
				local gap = math.sqrt((item.x - o[1]) ^ 2 + (item.z - o[2]) ^ 2) - r - o[3]
				if gap < (if item.solid then o[4] else 0) + (if item.kind == "sapling" then 3 else 0) then
					clear = false
					break
				end
			end
			if clear and item.solid then
				for _, other in ipairs(solids) do
					if math.sqrt((item.x - other.x) ^ 2 + (item.z - other.z) ^ 2) - r - Scatter.Radius(other) < 2 then
						clear = false
						break
					end
				end
			end
			if clear then
				table.insert(out, item)
				if item.solid then
					table.insert(solids, item)
				end
			end
		end
	end
	builtCache = out
	return out
end

-- Items per region and kind, cover and built together (the PR and the spec state these).
function Scatter.Counts(): { [string]: { [string]: number } }
	local counts: { [string]: { [string]: number } } = {}
	local function tally(list: { Item })
		for _, item in ipairs(list) do
			local row = counts[item.region] or {}
			counts[item.region] = row
			row[item.kind] = (row[item.kind] or 0) + 1
		end
	end
	tally(Scatter.Cover())
	tally(Scatter.Built())
	return counts
end

return Scatter
