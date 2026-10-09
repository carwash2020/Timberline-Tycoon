--!strict
-- WorldPlan: where everything in the world goes, worked out from BiomeData,
-- WorldLayout and the terrain (TerrainGen). Pure and deterministic, so the
-- server's MapBuilder builds exactly what the preview tool draws, and every
-- server builds the same world.
--
-- The town keeps the coordinates the rest of the game was tuned to (the
-- sawmill hub at (0, 110), the spawn at (0, 40), the shops at z 100, the
-- parking lot east of the spawn); BiomeData's haul distances are measured
-- from the sawmill.

local BiomeData = require(script.Parent.Parent.BiomeData)
local DealershipLot = require(script.Parent.Parent.Art.DealershipLot)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Parent.Art.Kit)
local LandmarkArt = require(script.Parent.Parent.Art.LandmarkArt)
local RegionLogic = require(script.Parent.Parent.RegionLogic)
local TerrainGen = require(script.Parent.TerrainGen)
local UndergroundData = require(script.Parent.UndergroundData)
local WoodData = require(script.Parent.Parent.WoodData)
local WorldLayout = require(script.Parent.WorldLayout)

local WorldPlan = {}

-- Where a felled tree may grow back (SectionTrees). `fixed` keeps the
-- spot (Sky Lumenwood). `cap` is the boot count for that zone (the Wild
-- zone's is 120, not per wood).
export type TreeZone = {
	id: string,
	cx: number,
	cz: number,
	radius: number,
	fixed: boolean?,
	cap: number?,
}
export type TreeSpot = {
	woodId: string,
	position: Vector3,
	biome: string, -- "wild": a meadow grove, a country stand, or the forest ring
	zone: TreeZone?,
}
export type Placement = { name: string, cframe: CFrame, seed: number }
export type Sign = { text: string, cframe: CFrame, lit: boolean? } -- lit: gooseneck lamps (TWN-07)
export type Fence = { length: number, cframe: CFrame }

local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

-- The CFrame standing at (x, z) on the ground, facing (tx, tz).
local function standing(x: number, z: number, tx: number, tz: number): CFrame
	local y = TerrainGen.HeightAt(x, z)
	return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(tx, y, tz))
end

-- Standing at `at` with the model's +Z pointing toward `toward` (flat).
local function facingZ(at: Vector3, toward: Vector3): CFrame
	local dx, dz = toward.X - at.X, toward.Z - at.Z
	return CFrame.new(at) * CFrame.Angles(0, math.atan2(dx, dz), 0)
end

---------------------------------------------------------------------------
-- Trees
---------------------------------------------------------------------------

-- Ground a tree may grow on: dry, `roadClearance` (6) studs off the roads,
-- flatter than `maxSlope` (0.75), not in town or the volcano's crater.
-- ForestService asks a little more of it for a giant Elder.
function WorldPlan.GoodGround(x: number, z: number, roadClearance: number?, maxSlope: number?): boolean
	if WorldLayout.FlatWeight(x, z) > 0.9 then
		return false
	end
	-- Pure yes or no tests, the cheapest first.
	local cone = WorldLayout.VolcanoCone
	local dx, dz = x - cone.x, z - cone.z
	if dx * dx + dz * dz < (cone.radius * 0.55) ^ 2 then
		return false
	end
	if TerrainGen.RoadClearance(x, z) < (roadClearance or 6) then
		return false
	end
	if TerrainGen.WaterLevelAt(x, z) ~= nil then
		return false
	end
	return TerrainGen.SlopeAt(x, z) < (maxSlope or 0.75)
end
local goodGround = WorldPlan.GoodGround

local cachedTrees: { TreeSpot }? = nil

local WILD_GROVES = 22 -- stands of trees in the open country
local WILD_NEAREST = 300 -- studs from the sawmill (the Starter Forest is 190)

-- The first 322 were placed from these counts. BiomeData.trees is the
-- live boot target (denser); new trees are appended, so these never move.
local LEGACY_TREES: { [string]: { [string]: number } } = {
	starter = { oak = 40, birch = 15 },
	hills = { pine = 40, maple = 25 },
	snow = { frostwood = 35 },
	volcano = { emberwood = 30 },
	grove = { phantomwood = 15 },
}

export type GroveDisc = { cx: number, cz: number, radius: number, count: number }
local groveDiscs: { GroveDisc } = {}
local firstTrees: () -> { TreeSpot }

function WorldPlan.GroveDiscs(): { GroveDisc }
	firstTrees()
	return groveDiscs
end

-- The woods of a wild grove at `c`, by the nearest biome: pine and maple
-- toward the Hills, pine and birch toward the Snowfields and the Volcano,
-- oak and birch everywhere else. (Repeats weight the pick.)
local function wildWoodsNear(c: Vector2): { string }
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

-- The first 322 trees, in the order every server has always spawned them
-- (saves and planted stakes may point at them): each biome's trees
-- (BiomeData counts), then the wild groves between them. Never change
-- what this returns; new trees go after it (WorldPlan.Trees).
local cachedFirst: { TreeSpot }? = nil
function firstTrees(): { TreeSpot }
	if cachedFirst then
		return cachedFirst
	end
	-- These 322 were placed on the narrower roads, before the mill road,
	-- the lot loop, the junction flares, the cliff rings and the hollow
	-- pools. Place them that way, then sit each trunk on the ground as it
	-- is now. X and Z never move (saves and stakes may point at them).
	TerrainGen.SetLegacyLayout(true)
	local out: { TreeSpot } = {}
	local taken: { Vector3 } = {}
	local function build(): any
		for _, biome in ipairs(BiomeData.All()) do
			local area = biome.area
			local counts = LEGACY_TREES[biome.id]
			if area and area.y == nil and counts then
				local rng = Kit.rng(hashString(biome.id))
				local woodIds: { string } = {}
				for woodId in pairs(counts) do
					table.insert(woodIds, woodId)
				end
				table.sort(woodIds) -- the same mix on every server
				for _, woodId in ipairs(woodIds) do
					local want = counts[woodId]
					local placed, tries = 0, 0
					while placed < want and tries < want * 60 do
						tries += 1
						local angle = rng:range(0, math.pi * 2)
						local r = math.sqrt(rng:next()) * (area.radius - 6) -- even spread over the disc
						local x, z = area.x + math.cos(angle) * r, area.z + math.sin(angle) * r
						local ok = goodGround(x, z)
						if ok then
							for _, q in ipairs(taken) do
								local ddx, ddz = x - q.X, z - q.Z
								if ddx * ddx + ddz * ddz < 10 * 10 then
									ok = false
									break
								end
							end
						end
						if ok then
							local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
							table.insert(taken, p)
							table.insert(out, {
								woodId = woodId,
								position = p,
								biome = biome.id,
								zone = {
									id = biome.id,
									cx = area.x,
									cz = area.z,
									radius = area.radius - 6,
								},
							})
							placed += 1
						end
					end
				end
			end
		end
		-- Wild groves: small stands of the common woods out in the open country
		-- between the biomes, so the land between them is never bare. Never
		-- nearer the sawmill than WILD_NEAREST (past the Starter Forest, so they
		-- don't shorten the first haul), clear of every biome, the town and the
		-- plots, the roads, the beach and the mountains. Their woods follow the
		-- nearest biome; each counts toward its wood's grove like any tree.
		local wildRng = Kit.rng(hashString("wild groves"))
		local mill = WorldLayout.Sawmill
		local half = WorldLayout.WorldHalf - 120
		local coast = WorldLayout.Coast
		local centers: { Vector2 } = {}
		local tries = 0
		while #centers < WILD_GROVES and tries < 6000 do
			tries += 1
			local x, z = wildRng:range(-half, half), wildRng:range(-half, half)
			local ok = Vector2.new(x - mill.X, z - mill.Z).Magnitude > WILD_NEAREST
				and WorldLayout.FlatWeight(x, z) <= 0
				and not (z < coast.northZ and x > coast.shoreX - coast.beachWidth - 40)
				and goodGround(x, z, 12, 0.55)
				and TerrainGen.HeightAt(x, z) < 70
			if ok then
				for _, biome in ipairs(BiomeData.All()) do
					local area = biome.area
					if area and Vector2.new(x - area.x, z - area.z).Magnitude < area.radius + 60 then
						ok = false
						break
					end
				end
			end
			if ok then
				for _, c in ipairs(centers) do
					if (c - Vector2.new(x, z)).Magnitude < 170 then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(centers, Vector2.new(x, z))
			end
		end
		for index, c in ipairs(centers) do
			local woods = wildWoodsNear(c)
			local want = wildRng:int(4, 8)
			local placed, attempts = 0, 0
			local groveZone: TreeZone = {
				id = "grove:" .. index,
				cx = c.X,
				cz = c.Y,
				radius = 26,
			}
			while placed < want and attempts < want * 30 do
				attempts += 1
				local angle = wildRng:range(0, math.pi * 2)
				local r = math.sqrt(wildRng:next()) * 26
				local x, z = c.X + math.cos(angle) * r, c.Y + math.sin(angle) * r
				local ok = goodGround(x, z, 10, 0.6)
				if ok then
					for _, q in ipairs(taken) do
						local ddx, ddz = x - q.X, z - q.Z
						if ddx * ddx + ddz * ddz < 10 * 10 then
							ok = false
							break
						end
					end
				end
				if ok then
					local woodId = wildRng:pick(woods)
					local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
					table.insert(taken, p)
					table.insert(out, { woodId = woodId, position = p, biome = "wild", zone = groveZone })
					placed += 1
				end
			end
			table.insert(groveDiscs, { cx = c.X, cz = c.Y, radius = 26, count = placed })
		end
		return nil
	end
	local placedOk, placedErr = pcall(build)
	TerrainGen.SetLegacyLayout(false)
	if not placedOk then
		error(placedErr)
	end
	for _, spot in ipairs(out) do
		local p = spot.position
		spot.position = Vector3.new(p.X, TerrainGen.HeightAt(p.X, p.Z) - 0.3, p.Z)
	end
	cachedFirst = out
	return out
end

-- Country stands: more wild stands out in the open country, so the land
-- between the places is never empty (Connor asked for many more trees).
-- First one about every STAND_ROAD_STEP along each haul road, sides
-- alternating, set back so its trees stand STAND_SET_BACK to STAND_ROADSIDE
-- studs off the road's edge; then one in each STAND_CELL square of open
-- country that has no tree yet. 4-9 trees each, spread like the Starter
-- Forest (one per 400 sq studs, STAND_SPACING apart). Every tree is on
-- good ground (dry, flat enough, lowland), out of town, the plots, the
-- beach and every biome (they have their own forests), off the gondola's
-- routes, the boulders, the road signs, the scenery (WLD-01) and every
-- other tree, and WILD_NEAREST from the sawmill (pine and maple STAND_FAR).
-- Their woods follow the nearest biome, as the wild groves' do. They come
-- after the first 322 trees and draw their own rng, so those never move.
-- Boulders() and Scenery() see only those 322, and the stands keep off
-- both (so nothing goes round in a circle, and neither moves).
local STAND_ROADS = { "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }
local STAND_ROAD_STEP = 150 -- a roadside stand about this far along each haul road
local STAND_CELL = 200 -- then one per square this big with no tree in it
local STAND_EDGE = 1150 -- clear of the mountains at the world's edge (as the scenery)
local STAND_LOW = 70 -- lowland only
local STAND_SET_BACK = 20 -- studs every stand tree keeps off a road's edge
local STAND_ROADSIDE = 80 -- a roadside stand's trees stand at most this far off its road's edge
local STAND_SPACING = 12 -- studs between two trees
local STAND_APART = 100 -- studs between two stands' middles
local STAND_CLEAR = 20 -- studs between a stand's edge and the trees already there
local STAND_GONDOLA = 30 -- studs off the gondola's routes (seen from above)
local STAND_ROCK = 6 -- studs off a boulder's side
local STAND_SIGN = 12 -- studs off a road sign
local STAND_SCENERY = 8 -- studs off a scenery piece's footprint (the scenery's own gap to a tree)
local STAND_FAR = 400 -- pine and maple stand at least this far from the sawmill
local STAND_MAX = 178 -- cap. Shelves and the lighthouse vista take some, so the live count is under this.
local STAND_OPEN_MOST = 6 -- trees in an open-country stand (4 to this; roadside ones 4-9)

-- A country stand: `trees` round `center` (all within `radius`); `road`
-- names the haul road it lines (nil out in the open country).
export type Stand = { center: Vector2, radius: number, road: string?, trees: { TreeSpot } }
WorldPlan.StandRoadside = STAND_ROADSIDE
WorldPlan.StandSetBack = STAND_SET_BACK
WorldPlan.StandSpacing = STAND_SPACING

local cachedStands: { Stand }? = nil

function WorldPlan.CountryStands(): { Stand }
	if cachedStands then
		return cachedStands
	end
	local stands: { Stand } = {}
	local rng = Kit.rng(hashString("country stands"))
	local mill = Vector2.new(WorldLayout.Sawmill.X, WorldLayout.Sawmill.Z)
	local coast = WorldLayout.Coast
	local beachX = coast.shoreX - coast.beachWidth - 40
	local boulders = WorldPlan.Boulders()
	local scenery = WorldPlan.Scenery()
	local signs = WorldPlan.RoadSigns(function(): string
		return ""
	end)
	local routes: { { Vector2 } } = {}
	local sky = WorldPlan.Sky()
	if sky then
		local top = sky.gondolaTop.Position
		local town = WorldPlan.TownGondolaSpot
		local base = sky.gondolaBase.Position
		table.insert(routes, { Vector2.new(town.X, town.Z), Vector2.new(top.X, top.Z) })
		table.insert(routes, { Vector2.new(base.X, base.Z), Vector2.new(top.X, top.Z) })
	end
	local discs: { { x: number, z: number, r: number } } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		if area then
			local r = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 else area.radius + 30
			table.insert(discs, { x = area.x, z = area.z, r = r })
		end
	end
	-- Every tree so far, binned by 32-stud squares for the spacing checks.
	local bins: { [string]: { Vector3 } } = {}
	local all: { Vector3 } = {}
	local function addTree(p: Vector3)
		local k = (p.X // 32) .. "," .. (p.Z // 32)
		local bin = bins[k] or {}
		bins[k] = bin
		table.insert(bin, p)
		table.insert(all, p)
	end
	local function crowded(x: number, z: number, d: number): boolean
		local reach = math.ceil(d / 32)
		local bx, bz = x // 32, z // 32
		for ix = bx - reach, bx + reach do
			for iz = bz - reach, bz + reach do
				for _, p in ipairs(bins[ix .. "," .. iz] or {}) do
					local dx, dz = x - p.X, z - p.Z
					if dx * dx + dz * dz < d * d then
						return true
					end
				end
			end
		end
		return false
	end
	for _, spot in ipairs(firstTrees()) do
		addTree(spot.position)
	end
	for _, spot in ipairs(scenery) do -- a square with a set piece in it isn't bare
		table.insert(all, spot.center)
	end

	-- Whether a stand tree could grow at (x, z).
	local function ground(x: number, z: number): boolean
		if math.abs(x) > STAND_EDGE or math.abs(z) > STAND_EDGE or (z < coast.northZ and x > beachX) then
			return false
		end
		if Vector2.new(x - mill.X, z - mill.Y).Magnitude <= WILD_NEAREST or WorldLayout.FlatWeight(x, z) > 0 then
			return false
		end
		for _, d in ipairs(discs) do
			local dx, dz = x - d.x, z - d.z
			if dx * dx + dz * dz < d.r * d.r then
				return false
			end
		end
		for _, route in ipairs(routes) do
			if WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) < STAND_GONDOLA then
				return false
			end
		end
		for _, b in ipairs(boulders) do
			local dx, dz = x - b.position.X, z - b.position.Z
			if dx * dx + dz * dz < (b.size / 2 + STAND_ROCK) ^ 2 then
				return false
			end
		end
		for _, sign in ipairs(signs) do
			local p = sign.cframe.Position
			if Vector2.new(x - p.X, z - p.Z).Magnitude < STAND_SIGN then
				return false
			end
		end
		for _, spot in ipairs(scenery) do
			local dx, dz = x - spot.center.X, z - spot.center.Z
			if dx * dx + dz * dz < (spot.radius + STAND_SCENERY) ^ 2 then
				return false
			end
		end
		-- The spawn's view of the lighthouse, and the trail out of the hollow.
		for _, lane in ipairs(WorldLayout.Forest.lanes) do
			if WorldLayout.SegmentDistance(Vector2.new(x, z), lane.a, lane.b) < lane.half + 10 then
				return false
			end
		end
		return TerrainGen.HeightAt(x, z) < STAND_LOW and goodGround(x, z, STAND_SET_BACK, 0.6)
	end

	local planted = 0
	-- A stand of `most` (4-9) trees round the middle `at(radius)` gives, if 4+ fit.
	local function plant(at: (radius: number) -> Vector2, road: WorldLayout.Road?, most: number): Stand?
		local want = math.min(rng:int(4, most), STAND_MAX - planted)
		if want < 4 then
			return nil
		end
		local radius = math.sqrt(400 * want / math.pi) -- the Starter Forest's one tree per 400 sq studs
		local c = at(radius)
		if not ground(c.X, c.Y) or crowded(c.X, c.Y, radius + STAND_CLEAR) then
			return nil
		end
		for _, s in ipairs(stands) do
			if (s.center - c).Magnitude < STAND_APART then
				return nil
			end
		end
		local woods = wildWoodsNear(c)
		if (c - mill).Magnitude < STAND_FAR + radius then
			woods = { "oak", "oak", "birch" }
		end
		local trees: { TreeSpot } = {}
		local attempts = 0
		while #trees < want and attempts < want * 30 do
			attempts += 1
			local angle = rng:range(0, math.pi * 2)
			local r = math.sqrt(rng:next()) * radius
			-- Rounded the way a Vector3 stores it, so what's checked is what's spawned.
			local flat = Vector3.new(c.X + math.cos(angle) * r, 0, c.Y + math.sin(angle) * r)
			local x, z = flat.X, flat.Z
			local ok = ground(x, z) and not crowded(x, z, STAND_SPACING)
			if ok and road then -- a roadside stand stays beside its road
				ok = WorldLayout.PolylineDistance(Vector2.new(x, z), road.points) - road.width / 2 <= STAND_ROADSIDE
			end
			if ok then
				for _, q in ipairs(trees) do
					local dx, dz = x - q.position.X, z - q.position.Z
					if dx * dx + dz * dz < STAND_SPACING * STAND_SPACING then
						ok = false
						break
					end
				end
			end
			if ok then
				local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
				table.insert(trees, { woodId = rng:pick(woods), position = p, biome = "wild" })
			end
		end
		if #trees < 4 then
			return nil
		end
		for _, spot in ipairs(trees) do
			addTree(spot.position)
		end
		planted += #trees
		local stand: Stand = { center = c, radius = radius, road = if road then road.name else nil, trees = trees }
		table.insert(stands, stand)
		local zone: TreeZone = {
			id = "stand:" .. tostring(#stands),
			cx = c.X,
			cz = c.Y,
			radius = radius,
		}
		for _, spot in ipairs(trees) do
			spot.zone = zone
		end
		return stand
	end

	-- Along the haul roads, every STAND_ROAD_STEP, sides alternating.
	for _, name in ipairs(STAND_ROADS) do
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				local pts = road.points
				local side = if rng:next() < 0.5 then 1 else -1
				local walked, nextAt = 0, rng:range(0, STAND_ROAD_STEP)
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = (b - a).Magnitude
					local dir = (b - a).Unit
					local normal = Vector2.new(-dir.Y, dir.X)
					while nextAt <= walked + len do
						local along = a + dir * (nextAt - walked)
						local done = false
						for _, s in ipairs({ side, -side }) do
							for _, shift in ipairs({ 0, 30, -30, 60, -60 }) do
								local function at(radius: number): Vector2
									-- Its far edge STAND_ROADSIDE off the road's edge.
									return along
										+ dir * shift
										+ normal * (s * (road.width / 2 + STAND_ROADSIDE - radius))
								end
								if plant(at, road, 9) then
									done = true
									break
								end
							end
							if done then
								break
							end
						end
						side = -side
						nextAt += STAND_ROAD_STEP
					end
					walked += len
				end
			end
		end
	end

	-- Then one stand per square of open country with no tree or set piece in it yet, the
	-- squares in a shuffled order (so STAND_MAX doesn't leave one side bare).
	local cells: { Vector2 } = {}
	for cx = -STAND_EDGE, STAND_EDGE - 1, STAND_CELL do
		for cz = -STAND_EDGE, STAND_EDGE - 1, STAND_CELL do
			table.insert(cells, Vector2.new(cx, cz))
		end
	end
	for i = #cells, 2, -1 do
		local j = rng:int(1, i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	for _, cell in ipairs(cells) do
		local cx, cz = cell.X, cell.Y
		local bare = true
		for _, p in ipairs(all) do
			if p.X >= cx and p.X < cx + STAND_CELL and p.Z >= cz and p.Z < cz + STAND_CELL then
				bare = false
				break
			end
		end
		if bare then
			for _ = 1, 16 do
				local x, z = rng:range(cx + 30, cx + STAND_CELL - 30), rng:range(cz + 30, cz + STAND_CELL - 30)
				if plant(function(): Vector2
					return Vector2.new(x, z)
				end, nil, STAND_OPEN_MOST) then
					break
				end
			end
		end
	end
	cachedStands = stands
	return stands
end

-- The first 322 and the country stands' trees, in spawn order: every tree
-- there was before the forest's (FOR-03). The boulder clusters, the
-- landmarks and the lighthouse's line of sight were placed round these
-- and keep using them, so the forest's trees move none of them (they keep
-- off all of it instead).
local cachedBase: { TreeSpot }? = nil
local function baseTrees(): { TreeSpot }
	if cachedBase then
		return cachedBase
	end
	local out = table.clone(firstTrees())
	for _, stand in ipairs(WorldPlan.CountryStands()) do
		for _, spot in ipairs(stand.trees) do
			table.insert(out, spot)
		end
	end
	cachedBase = out
	return out
end

-- Every tree on the ground, in spawn order: the first 322 (each biome's
-- trees, then the wild groves), then the country stands', then the
-- forest's (WorldPlan.ForestTrees; the sky's Lumenwood is in WorldPlan.Sky).
-- This is the one planner that costs seconds (about 6 s in Lune, 11 s in
-- Studio's client): a caller that is not allowed to freeze a frame (the
-- server planting after players are in, the client's filler) passes `pause`,
-- a time slice's step, called after every placement attempt. The trees are
-- the same with or without it.
function WorldPlan.Trees(pause: (() -> ())?): { TreeSpot }
	if cachedTrees then
		return cachedTrees
	end
	local out = table.clone(baseTrees())
	for _, spot in ipairs(WorldPlan.ForestTrees()) do
		table.insert(out, spot)
	end
	-- Denser biomes, groves and stands, then the wild clumps. Appended, so
	-- every tree above keeps its X and Z.
	local TreeFill = require(script.Parent.TreeFill)
	for _, spot in ipairs(TreeFill.Extra(out, pause)) do
		table.insert(out, spot)
	end
	-- Another caller may have finished while this one was paused: keep theirs.
	if cachedTrees then
		return cachedTrees
	end
	cachedTrees = out
	return out
end

-- The Petrified Reach: a few gloamwood on the far side of the hollow's
-- ridge. Appended nowhere in Trees() — the first 322 and everything
-- placed against them stay put. Night-only, because the wood's biome is
-- the grove (SectionTrees.SetBiomeDormant). Same price as the hollow's.
local cachedReach: { TreeSpot }? = nil

local function nearTree(x: number, z: number, gap: number): boolean
	for _, spot in ipairs(WorldPlan.Trees()) do
		local p = spot.position
		local dx, dz = p.X - x, p.Z - z
		if dx * dx + dz * dz < gap * gap then
			return true
		end
	end
	return false
end

function WorldPlan.ReachTrees(): { TreeSpot }
	if cachedReach then
		return cachedReach
	end
	local out: { TreeSpot } = {}
	local cx, cz, radius = RegionLogic.ReachCenter()
	local rng = Kit.rng(hashString("petrified reach"))
	local placed: { Vector2 } = {}
	local tries = 0
	local reachCap = 6 -- 1.5x the original 4, rounded down
	while #out < reachCap and tries < 800 do
		tries += 1
		local ang = rng:range(0, math.pi * 2)
		local rad = math.sqrt(rng:next()) * math.max(radius - 6, 8)
		local x, z = cx + math.cos(ang) * rad, cz + math.sin(ang) * rad
		local apart = true
		for _, q in ipairs(placed) do
			if (q - Vector2.new(x, z)).Magnitude < 14 then
				apart = false
				break
			end
		end
		if apart and goodGround(x, z, 8, 0.7) and not nearTree(x, z, 14) and TerrainGen.HeightAt(x, z) < 80 then
			table.insert(placed, Vector2.new(x, z))
			table.insert(out, {
				woodId = "phantomwood",
				position = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z),
				biome = "reach",
				zone = {
					id = "reach",
					cx = cx,
					cz = cz,
					radius = math.max(radius - 6, 8),
				},
			})
		end
	end
	cachedReach = out
	return out
end

export type PointOfInterest = {
	id: string,
	name: string,
	kind: string,
	region: string,
	cframe: CFrame,
	seed: number,
	secret: string?,
	text: string?,
}

local cachedPoints: { PointOfInterest }? = nil

function WorldPlan.PointsOfInterest(): { PointOfInterest }
	if cachedPoints then
		return cachedPoints
	end
	local out: { PointOfInterest } = {}
	local taken: { Vector2 } = {}
	for index, anchor in ipairs(RegionLogic.Anchors()) do
		local rng = Kit.rng(hashString("poi " .. anchor.id))
		local found: Vector2? = nil
		local slope = if anchor.kind == "Cave" then 1.05 else 0.72
		for _ = 1, 90 do
			local ang = rng:range(0, math.pi * 2)
			local rad = rng:next() * anchor.search
			local x = anchor.x + math.cos(ang) * rad
			local z = anchor.z + math.sin(ang) * rad
			local clear = WorldLayout.FlatWeight(x, z) < 0.35
				and TerrainGen.WaterLevelAt(x, z) == nil
				and TerrainGen.RoadClearance(x, z) >= 8
				and TerrainGen.SlopeAt(x, z) < slope
				and TerrainGen.HeightAt(x, z) < 96
				and not nearTree(x, z, 11)
			if clear then
				for _, q in ipairs(taken) do
					if (q - Vector2.new(x, z)).Magnitude < 22 then
						clear = false
						break
					end
				end
			end
			if clear then
				found = Vector2.new(x, z)
				break
			end
		end
		local at = found
		if at then
			table.insert(taken, at)
			local y = TerrainGen.HeightAt(at.X, at.Y)
			local dirx, dirz = anchor.x - at.X, anchor.z - at.Y
			if dirx * dirx + dirz * dirz < 4 then
				dirx, dirz = 0, -1
			end
			table.insert(out, {
				id = anchor.id,
				name = anchor.name,
				kind = anchor.kind,
				region = anchor.region,
				cframe = CFrame.lookAt(Vector3.new(at.X, y, at.Y), Vector3.new(at.X + dirx, y, at.Y + dirz)),
				seed = 7000 + index * 17,
				secret = anchor.secret,
				text = anchor.text,
			})
		end
	end
	cachedPoints = out
	return out
end

export type TrailSlab = { name: string, cframe: CFrame }

local cachedSlabs: { TrailSlab }? = nil

-- Worn slabs along the footpaths. Anything on a road, in town, on the
-- plots or in the water is dropped, so a trail never plants a tree's spot
-- and never paves the haul roads.
function WorldPlan.TrailSlabs(): { TrailSlab }
	if cachedSlabs then
		return cachedSlabs
	end
	local out: { TrailSlab } = {}
	for _, trail in ipairs(RegionLogic.Trails()) do
		local dx, dz = trail.bx - trail.ax, trail.bz - trail.az
		local len = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(math.floor(len / 12), 1)
		local yaw = math.atan2(dx, dz)
		for i = 0, steps do
			local t = i / steps
			local x = trail.ax + dx * t
			local z = trail.az + dz * t
			if
				WorldLayout.FlatWeight(x, z) < 0.4
				and TerrainGen.WaterLevelAt(x, z) == nil
				and TerrainGen.RoadClearance(x, z) > 7
				and TerrainGen.SlopeAt(x, z) < 0.85
			then
				local y = TerrainGen.HeightAt(x, z)
				table.insert(out, {
					name = trail.name,
					cframe = CFrame.new(x, y + 0.12, z) * CFrame.Angles(0, yaw, 0),
				})
			end
		end
	end
	cachedSlabs = out
	return out
end

---------------------------------------------------------------------------
-- Boulders and nature landmarks
---------------------------------------------------------------------------

export type Boulder = { position: Vector3, size: number, seed: number, snowy: boolean, dark: boolean }

-- Boulders out in the country: dry, off the roads, below the high peaks,
-- and on ground gentle enough (slope under 0.6) that sinking them 0.6
-- leaves no gap under their downhill side.
function WorldPlan.Boulders(): { Boulder }
	local out: { Boulder } = {}
	local rng = Kit.rng(4242)
	local trees = firstTrees() -- not the country stands: they keep off the boulders
	local tries = 0
	while #out < 90 and tries < 2000 do
		tries += 1
		local x, z = rng:range(-1350, 1350), rng:range(-1350, 1350)
		local ok = WorldLayout.FlatWeight(x, z) <= 0
			and TerrainGen.WaterLevelAt(x, z) == nil
			and TerrainGen.RoadClearance(x, z) > 10
			and TerrainGen.HeightAt(x, z) < 90
			and TerrainGen.SlopeAt(x, z) < 0.6
		if ok then
			for _, t in ipairs(trees) do
				local dx, dz = x - t.position.X, z - t.position.Z
				if dx * dx + dz * dz < 64 then
					ok = false
					break
				end
			end
		end
		if ok then
			local biome = BiomeData.At(x, z)
			local id = if biome then biome.id else ""
			table.insert(out, {
				position = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.6, z),
				size = rng:range(2.5, 7),
				seed = tries,
				snowy = id == "snow",
				dark = id == "volcano" or id == "grove",
			})
		end
	end
	return out
end

-- Brown rocks on the open lawn round the town (phase 12). Not part of
-- Boulders(): those 90 are a fingerprint the country stands keep off, and
-- these sit inside 300 studs of the sawmill where the stands never grow.
function WorldPlan.MeadowBoulders(): { Boulder }
	local out: { Boulder } = {}
	local rng = Kit.rng(hashString("meadow boulders"))
	local mill = WorldLayout.Sawmill
	local tries = 0
	while #out < 32 and tries < 5000 do
		tries += 1
		local ang = rng:range(0, math.pi * 2)
		local dist = rng:range(155, 265)
		local x = mill.X + math.cos(ang) * dist
		local z = mill.Z + math.sin(ang) * dist
		local ok = WorldLayout.FlatWeight(x, z) == 0
			and WorldLayout.ForestCover(x, z) == 0
			and TerrainGen.WaterLevelAt(x, z) == nil
			and TerrainGen.RoadClearance(x, z) > 16
			and TerrainGen.SlopeAt(x, z) < 0.35
			and TerrainGen.HeightAt(x, z) < 8
		if ok then
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and Vector2.new(x - area.x, z - area.z).Magnitude < area.radius + 16 then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, b in ipairs(out) do
				local dx, dz = x - b.position.X, z - b.position.Z
				if dx * dx + dz * dz < 28 * 28 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(out, {
				position = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.6, z),
				size = rng:range(3.2, 6.4),
				seed = tries,
				snowy = false,
				dark = false,
			})
		end
	end
	return out
end

-- Glowing mushrooms in the Gloam Hollow (its tell at night).
function WorldPlan.GroveMushrooms(): { CFrame }
	local def = BiomeData.Get("grove")
	local area = if def then def.area else nil
	local out: { CFrame } = {}
	if not area then
		return out
	end
	local rng = Kit.rng(777)
	for _ = 1, 18 do
		local a, r = rng:range(0, math.pi * 2), rng:range(10, area.radius - 10)
		local x, z = area.x + math.cos(a) * r, area.z + math.sin(a) * r
		table.insert(out, CFrame.new(x, TerrainGen.HeightAt(x, z) - 0.1, z) * CFrame.Angles(0, rng:range(0, 6), 0))
	end
	return out
end

-- Ferry Island sites. Palms and Lanternwood share one zone. They are not
-- biome.trees, so the economy supply table does not grow a row.
type FerrySites = { palms: { TreeSpot }, lantern: { TreeSpot } }
local cachedFerry: FerrySites? = nil

local function ferrySites(): FerrySites
	local cached = cachedFerry
	if cached then
		return cached
	end
	local island = WorldLayout.Island
	local function yOf(x: number, z: number): number
		return TerrainGen.HeightAt(x, z) - 0.3
	end
	local zone: TreeZone = {
		id = "ferryisle",
		cx = island.x,
		cz = island.z,
		radius = island.radius - WorldLayout.FerryLandingInset,
		cap = BiomeData.PalmCount,
	}
	local palms: { TreeSpot } = {}
	local step = WorldLayout.PalmGridStep
	local limit = WorldLayout.PalmMaxRadius
	local n = math.floor(limit / step)
	local candidates: { { x: number, z: number } } = {}
	for ix = -n, n do
		for iz = -n, n do
			local x = island.x + ix * step
			local z = island.z + iz * step
			local dx, dz = x - island.x, z - island.z
			if dx * dx + dz * dz <= limit * limit and not WorldLayout.OnFerryPath(x, z) then
				table.insert(candidates, { x = x, z = z })
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)
	for _, spot in ipairs(candidates) do
		if #palms >= BiomeData.PalmCount then
			break
		end
		table.insert(palms, {
			woodId = "palmwood",
			position = Vector3.new(spot.x, yOf(spot.x, spot.z), spot.z),
			biome = "ferryisle",
			zone = zone,
		})
	end
	local made = { palms = palms, lantern = {} }
	cachedFerry = made
	return made
end

function WorldPlan.FerryPalms(): { TreeSpot }
	return ferrySites().palms
end

-- Six Lanternwood in the grotto. The chamber is 36 tall; the tallest tree
-- is 28. The wood's row stays ferryisle (the badge and the economy).
local cachedLantern: { TreeSpot }? = nil
function WorldPlan.Lanternwood(): { TreeSpot }
	local cached = cachedLantern
	if cached then
		return cached
	end
	local cave = UndergroundData.Cave("grotto")
	local spots: { TreeSpot } = {}
	if cave then
		local zone: TreeZone = {
			id = "grotto",
			cx = cave.x,
			cz = cave.z,
			radius = math.min(cave.sx, cave.sz) / 2,
			cap = BiomeData.LanternwoodCount,
		}
		local count = BiomeData.LanternwoodCount
		local cols = 3
		for i = 1, count do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local x = cave.x + (col - 1) * 10
			local z = cave.z + (row - 0.5) * 12
			table.insert(spots, {
				woodId = "lanternwood",
				position = Vector3.new(x, cave.floorY + 0.5, z),
				biome = "ferryisle",
				zone = zone,
			})
		end
	end
	cachedLantern = spots
	return spots
end

-- The old palm list, now the thirty ferry palms (the preview still calls this).
function WorldPlan.IslandPalms(): { Vector3 }
	local out: { Vector3 } = {}
	for _, spot in ipairs(WorldPlan.FerryPalms()) do
		table.insert(out, spot.position)
	end
	return out
end

-- Maple and birch on the north strip, in their own regrow zone. Not spruce:
-- that row is not in WoodData yet, and these stands are not biome.trees.
local cachedStrip: { TreeSpot }? = nil

function WorldPlan.StripTrees(): { TreeSpot }
	local cached = cachedStrip
	if cached then
		return cached
	end
	local zone: TreeZone = {
		id = "northstrip",
		cx = WorldLayout.StripZoneCx,
		cz = WorldLayout.StripZoneCz,
		radius = WorldLayout.StripZoneRadius,
		cap = WorldLayout.StripZoneCap,
	}
	local out: { TreeSpot } = {}
	local per = WorldLayout.StripTreesPerClump
	local ring = WorldLayout.StripClumpRadius
	for _, clump in ipairs(WorldLayout.StripClumps) do
		for i = 1, per do
			local angle = (i - 1) * math.pi * 2 / per
			local x = clump.x + math.cos(angle) * ring
			local z = clump.z + math.sin(angle) * ring
			local woodId = if #out < WorldLayout.StripMapleCount then "maple" else "birch"
			table.insert(out, {
				woodId = woodId,
				position = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z),
				biome = "northstrip",
				zone = zone,
			})
		end
	end
	cachedStrip = out
	return out
end

-- The volcano's crater: where the lava glows and the smoke rises. Returns
-- the centre of the level lava pool on its floor and the pool's radius.
function WorldPlan.Crater(): (Vector3, number)
	local cone = WorldLayout.VolcanoCone
	return Vector3.new(cone.x, TerrainGen.HeightAt(cone.x, cone.z), cone.z), cone.pool
end

---------------------------------------------------------------------------
-- Open-country scenery (WLD-01)
---------------------------------------------------------------------------

-- One thing a set piece is made of. `builder` is a PropArt set piece
-- ("Outcrop", "RuinedCabin", "Windmill", "LookoutTower", from `seed`), a
-- BuildingArt prop ("LogPile", "Haybale", from `seed`) or a BuildingArt
-- fence ("Fence", `size` studs long). Its origin goes on `cframe`.
export type SceneryItem = { builder: string, cframe: CFrame, seed: number, size: number }
-- A set piece: MapBuilder builds each as one Atomic model named `kind`
-- under TimberlineMap.Scenery. `center` is its base on the ground,
-- `radius` its footprint (everything in it stands inside).
export type ScenerySpot = { kind: string, center: Vector3, radius: number, items: { SceneryItem } }

WorldPlan.SceneryGrade = 0.22 -- the steepest ground a piece stands on (rise over run across it)
WorldPlan.ScenerySink = 2.5 -- the most its uphill side sits in the ground
WorldPlan.SceneryRadius = {
	Outcrop = 15,
	LogPile = 7,
	FenceLine = 13,
	HayLine = 9,
	RuinedCabin = 11,
	Windmill = 10,
	LookoutTower = 5,
} :: { [string]: number }
local SCENERY_CELL = 250 -- one group of pieces per cell of open country
local SCENERY_ROAD_STEP = 150 -- and one every this far along the haul roads
local SCENERY_ROADS = { "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }
local SCENERY_EDGE = 1150 -- clear of the mountains at the world's edge
local SCENERY_LOW = 75 -- lowland only
-- Along a road, in turn (a random start per road), and what stands with each.
local SCENERY_CYCLE =
	{ "Outcrop", "FenceLine", "RuinedCabin", "LogPile", "Windmill", "Outcrop", "HayLine", "LookoutTower" }
local SCENERY_COMPANIONS: { [string]: { string } } = {
	Outcrop = { "Outcrop" },
	LogPile = { "Outcrop" },
	FenceLine = { "HayLine" },
	HayLine = { "FenceLine" },
	RuinedCabin = { "LogPile", "FenceLine" },
	Windmill = { "HayLine", "FenceLine" },
	LookoutTower = { "Outcrop", "LogPile" },
}

-- The items of a `kind` piece with its base at `base` (turned already).
local function sceneryItems(kind: string, base: CFrame, rng: Kit.Rng): { SceneryItem }
	local items: { SceneryItem } = {}
	local function add(builder: string, offset: CFrame, size: number?)
		table.insert(items, { builder = builder, cframe = base * offset, seed = rng:int(1, 99999), size = size or 0 })
	end
	if kind == "LogPile" then
		add("LogPile", CFrame.Angles(0, rng:range(-0.2, 0.2), 0)) -- about 20 parts on its own
	elseif kind == "FenceLine" then
		local length = rng:range(16, 22)
		add("Fence", CFrame.Angles(0, rng:range(-0.1, 0.1), 0), length)
		for _ = 1, rng:int(1, 2) do
			add(
				"Haybale",
				CFrame.new(rng:range(-length / 3, length / 3), 0, -rng:range(2.4, 3.4))
					* CFrame.Angles(0, rng:range(-0.4, 0.4), 0)
			)
		end
	elseif kind == "HayLine" then
		local count = rng:int(3, 4)
		for i = 1, count do
			add(
				"Haybale",
				CFrame.new((i - (count + 1) / 2) * 3.4, 0, rng:range(-0.5, 0.5))
					* CFrame.Angles(0, rng:range(-0.25, 0.25), 0)
			)
		end
	else
		add(kind, CFrame.identity)
	end
	return items
end

-- Where the lighthouse lamp will stand: the furthest-east headland the
-- coast offers, set back on the sand. Scenery keeps off the line from the
-- spawn to it. Not Lighthouse() itself (that reads the scenery).
local cachedSight: { Vector3 }? = nil
local function sightOfLamp(): (Vector3, Vector3)
	local cached = cachedSight
	if cached then
		return cached[1], cached[2]
	end
	local eye = WorldPlan.Town().spawn + Vector3.new(0, 6, 0)
	local radius = LandmarkArt.LIGHTHOUSE_RADIUS
	local tips: { { x: number, z: number } } = {}
	for z = 120, 460, 4 do
		local coast = WorldLayout.Coast
		for x = coast.shoreX - coast.beachWidth, WorldLayout.WorldHalf + WorldLayout.TerrainSkirt do
			if TerrainGen.WaterLevelAt(x, z) ~= nil then
				table.insert(tips, { x = x, z = z })
				break
			end
		end
	end
	table.sort(tips, function(p, q)
		if p.x ~= q.x then
			return p.x > q.x
		end
		return p.z < q.z
	end)
	local lamp = Vector3.new(1203, 48, 236)
	for _, tip in ipairs(tips) do
		local x, z = tip.x - 26, tip.z
		local lowest = math.huge
		local dry = true
		for _, q in ipairs(WorldPlan.SceneryFootprint(x, z, radius)) do
			if TerrainGen.WaterLevelAt(q.X, q.Y) ~= nil then
				dry = false
				break
			end
			lowest = math.min(lowest, TerrainGen.HeightAt(q.X, q.Y))
		end
		if dry and TerrainGen.HeightAt(x, z) - lowest < 1.5 then
			lamp = Vector3.new(x, lowest - 0.2 + LandmarkArt.LIGHTHOUSE_LAMP, z)
			break
		end
	end
	cachedSight = { eye, lamp }
	return eye, lamp
end

local cachedScenery: { ScenerySpot }? = nil

-- Decor-only set pieces out in the open country (WLD-01): outcrops, log
-- piles, fence and hay lines, ruined cabins, windmills, lookout towers.
-- About one group per SCENERY_CELL square of open country, and one every
-- SCENERY_ROAD_STEP along the haul roads, 18-60 studs off the road's edge,
-- sides alternating. Each stands on dry lowland no steeper than
-- SceneryGrade, its base at the lowest ground under its footprint (so
-- nothing floats, and its uphill side sinks at most ScenerySink), 4+ studs
-- off the roads, 8+ off any tree, clear of the boulders, the signs, the
-- gondola's route, the town, the plots and every biome. Looks only:
-- nothing there is chopped, collides or changes the balance.
function WorldPlan.Scenery(): { ScenerySpot }
	if cachedScenery then
		return cachedScenery
	end
	local out: { ScenerySpot } = {}
	local rng = Kit.rng(hashString("open-country scenery"))
	-- The first 322 trees: the country stands come after the scenery and
	-- keep off it, so it is 8+ studs off every tree all the same.
	local trees = firstTrees()
	local boulders = WorldPlan.Boulders()
	local signs = WorldPlan.RoadSigns(function(): string
		return ""
	end)
	local coast = WorldLayout.Coast
	local beachX = coast.shoreX - coast.beachWidth - 40
	-- The gondola's route (from town and from the Skyroot's foot to the top station).
	local routes: { { Vector2 } } = {}
	local sky = WorldPlan.Sky()
	if sky then
		local top = sky.gondolaTop.Position
		local town = WorldPlan.Town().gondola.Position
		local base = sky.gondolaBase.Position
		table.insert(routes, { Vector2.new(town.X, town.Z), Vector2.new(top.X, top.Z) })
		table.insert(routes, { Vector2.new(base.X, base.Z), Vector2.new(top.X, top.Z) })
	end
	local discs: { { x: number, z: number, r: number } } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		if area then
			local margin = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 - area.radius else 20
			table.insert(discs, { x = area.x, z = area.z, r = area.radius + margin })
		end
	end

	-- Where a piece of footprint `r` could stand at (x, z): its base height,
	-- or nil.
	local function fits(x: number, z: number, r: number): number?
		if math.abs(x) > SCENERY_EDGE or math.abs(z) > SCENERY_EDGE or x > beachX then
			return nil
		end
		for _, d in ipairs(discs) do
			local dx, dz = x - d.x, z - d.z
			if dx * dx + dz * dz < (d.r + r) ^ 2 then
				return nil
			end
		end
		if TerrainGen.RoadClearance(x, z) < r + 4 then
			return nil
		end
		for _, route in ipairs(routes) do
			if WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) < r + 30 then
				return nil
			end
		end
		for _, t in ipairs(trees) do
			local dx, dz = x - t.position.X, z - t.position.Z
			if dx * dx + dz * dz < (r + 8) ^ 2 then
				return nil
			end
		end
		for _, b in ipairs(boulders) do
			local dx, dz = x - b.position.X, z - b.position.Z
			if dx * dx + dz * dz < (r + b.size / 2 + 4) ^ 2 then
				return nil
			end
		end
		for _, sign in ipairs(signs) do
			local p = sign.cframe.Position
			if (Vector2.new(x - p.X, z - p.Z)).Magnitude < r + 12 then
				return nil
			end
		end
		for _, q in ipairs(out) do
			local dx, dz = x - q.center.X, z - q.center.Z
			if dx * dx + dz * dz < (r + q.radius + 4) ^ 2 then
				return nil
			end
		end
		local lo, hi = math.huge, -math.huge
		for _, sample in ipairs(WorldPlan.SceneryFootprint(x, z, r)) do
			local sx, sz = sample.X, sample.Y
			if TerrainGen.WaterLevelAt(sx, sz) ~= nil or WorldLayout.FlatWeight(sx, sz) > 0 then
				return nil
			end
			local h = TerrainGen.HeightAt(sx, sz)
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
		if hi > SCENERY_LOW or hi - lo > math.min(WorldPlan.SceneryGrade * 2 * r, WorldPlan.ScenerySink) then
			return nil
		end
		-- The spawn's view of the lighthouse lamp. A piece within its
		-- footprint of that line, and not 30 studs under it, hides the lamp
		-- (WorldPlan.spec). The lamp is the coast's headland; asking
		-- Lighthouse() here would ask for the scenery again.
		local eye, lamp = sightOfLamp()
		local d, along =
			WorldLayout.SegmentDistance(Vector2.new(x, z), Vector2.new(eye.X, eye.Z), Vector2.new(lamp.X, lamp.Z))
		local lineY = eye.Y + (lamp.Y - eye.Y) * along
		if d < r + 4 and lineY - (lo - 0.1) <= 30 then
			return nil
		end
		return lo - 0.1
	end

	-- Puts a `kind` piece at (x, z) facing `yaw` if it fits there.
	local function try(kind: string, x: number, z: number, yaw: number): ScenerySpot?
		local r = WorldPlan.SceneryRadius[kind]
		local y = fits(x, z, r)
		if not y then
			return nil
		end
		local center = Vector3.new(x, y, z)
		local spot = {
			kind = kind,
			center = center,
			radius = r,
			items = sceneryItems(kind, CFrame.new(center) * CFrame.Angles(0, yaw, 0), rng),
		}
		table.insert(out, spot)
		return spot
	end

	-- A few companions round a piece (a homestead, a pair of outcrops).
	local function companions(main: ScenerySpot)
		for _, kind in ipairs(SCENERY_COMPANIONS[main.kind] or {}) do
			local r = WorldPlan.SceneryRadius[kind]
			local start = rng:range(0, math.pi * 2)
			for k = 0, 7 do
				local a = start + k * math.pi / 4
				local d = main.radius + r + rng:range(6, 18)
				local x, z = main.center.X + math.cos(a) * d, main.center.Z + math.sin(a) * d
				if try(kind, x, z, a + math.pi / 2 + rng:range(-0.4, 0.4)) then
					break
				end
			end
		end
	end

	-- Along the haul roads, every SCENERY_ROAD_STEP, sides alternating.
	local mains: { Vector3 } = {}
	for _, name in ipairs(SCENERY_ROADS) do
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				local pts = road.points
				local turn = rng:int(1, #SCENERY_CYCLE)
				local side = if rng:next() < 0.5 then 1 else -1
				local walked, nextAt = 0, SCENERY_ROAD_STEP / 2
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = (b - a).Magnitude
					local dir = (b - a).Unit
					local normal = Vector2.new(-dir.Y, dir.X)
					while nextAt <= walked + len do
						local along = a + dir * (nextAt - walked)
						local kind = SCENERY_CYCLE[(turn - 1) % #SCENERY_CYCLE + 1]
						local placed: ScenerySpot? = nil
						for _, s in ipairs({ side, -side }) do
							for _, shift in ipairs({ 0, 25, -25, 50, -50 }) do
								for _, off in ipairs({ 18, 26, 36, 48, 60 }) do
									local at = along + dir * shift + normal * (s * (road.width / 2 + off))
									-- Its front (-Z) toward the road.
									local yaw = math.atan2(normal.X * s, normal.Y * s)
									placed = try(kind, at.X, at.Y, yaw)
									if placed then
										break
									end
								end
								if placed then
									break
								end
							end
							if placed then
								break
							end
						end
						if placed then
							table.insert(mains, placed.center)
							companions(placed)
						end
						turn += 1
						side = -side
						nextAt += SCENERY_ROAD_STEP
					end
					walked += len
				end
			end
		end
	end

	-- Then one group per cell of open country that has none yet.
	local kinds = { "Outcrop", "Outcrop", "LogPile", "FenceLine", "HayLine", "RuinedCabin", "Windmill", "LookoutTower" }
	for cx = -SCENERY_EDGE, SCENERY_EDGE - 1, SCENERY_CELL do
		for cz = -SCENERY_EDGE, SCENERY_EDGE - 1, SCENERY_CELL do
			local taken = false
			for _, m in ipairs(mains) do
				if m.X >= cx and m.X < cx + SCENERY_CELL and m.Z >= cz and m.Z < cz + SCENERY_CELL then
					taken = true
					break
				end
			end
			if not taken then
				local kind = rng:pick(kinds)
				for _ = 1, 24 do
					local x, z = rng:range(cx + 20, cx + SCENERY_CELL - 20), rng:range(cz + 20, cz + SCENERY_CELL - 20)
					local placed = try(kind, x, z, rng:range(0, math.pi * 2))
					if placed then
						table.insert(mains, placed.center)
						companions(placed)
						break
					end
				end
			end
		end
	end
	cachedScenery = out
	return out
end

-- The ground samples a piece of footprint `r` at (x, z) stands on: its
-- middle and rings at r / 2 and r (x, z in a Vector2's X, Y).
function WorldPlan.SceneryFootprint(x: number, z: number, r: number): { Vector2 }
	local out = { Vector2.new(x, z) }
	for k = 0, 7 do
		local a = k * math.pi / 4
		table.insert(out, Vector2.new(x + math.cos(a) * r, z + math.sin(a) * r))
		table.insert(out, Vector2.new(x + math.cos(a + math.pi / 8) * r / 2, z + math.sin(a + math.pi / 8) * r / 2))
	end
	return out
end

---------------------------------------------------------------------------
-- The town
---------------------------------------------------------------------------

export type ShopSpot = { kind: string, title: string, accent: Color3, cframe: CFrame }

-- A piece of the town's greenery (BuildingArt.Greenery builds it): kind
-- "tree" (`woodId` at scale `size`, in a stone ring), "bush" or "rock"
-- (`size` studs across) or "flowers" (a bed `size` studs across), standing
-- at `cframe` (on the ground, turned).
export type Greenery = { kind: string, woodId: string?, cframe: CFrame, size: number, seed: number }

export type SceneSpot = {
	kind: string, -- "forge" | "fishing" | "campfire" | "lookout" | "bench"
	cframe: CFrame,
}

export type Town = {
	spawn: Vector3,
	spawnFacing: CFrame, -- the SpawnLocation's CFrame: at `spawn`, its front toward the sawmill
	sawmill: CFrame,
	sellZone: CFrame, -- centre of the sell volume (WorldPlan.SellZoneSize)
	sellPad: CFrame,
	shops: { ShopSpot },
	gondola: CFrame,
	campsite: CFrame,
	murph: CFrame, -- where Murph stands, facing the spawn
	parkingSlots: { CFrame }, -- in claim order (Index 1, 2, ...)
	parkingSizes: { Vector3 }, -- each slot's size, in the same order (WorldPlan.ParkingBays)
	lamps: { CFrame },
	fences: { Fence },
	props: { Placement },
	signs: { Sign },
	greenery: { Greenery }, -- ornamental: never choppable
	-- Saw-cut rounds down the middle of each shop path (looks only).
	pathRounds: { CFrame },
	-- Open display lot: trucks and trailers for sale, north of the plot road.
	displayLot: CFrame,
	-- The buildings and props Connor was shown, on the town layout (Lane B's
	-- map has not merged, so these use the town we already have).
	scenes: { SceneSpot },
}

local FACING_SOUTH = CFrame.Angles(0, 0, 0) -- builders face -Z already

-- The sell station (Connor: "move the sell logs here pad to the side of the
-- sawmill, and add more to it"). It stands EAST of the mill, beside the
-- lean-to, between the mill yard and the mill road, so the spawn walk to
-- the mill's front is clear and trucks reach it straight off the main
-- street. The pad is SellPadWidth x SellPadDepth (BuildingArt.SellStation:
-- three lanes, a weigh house, a log rack, rails and lamps round it). The
-- sell volume (MapBuilder's SellZone) is the pad's width and 52 deep, z 85
-- to 137, so a truck backed in from the street up to the log rack has its
-- whole bed in it, the Logging Rig's 33.8-stud deck too (phase 12). Its
-- middle is the pad's
-- middle, (53, 111): Millie, the SELL LOGS marker and the quest beacon are
-- placed from it.
WorldPlan.SellPadWidth = 28
WorldPlan.SellPadDepth = 32
WorldPlan.SellZoneSize = Vector3.new(28, 12, 52)

-- Parking bays (phase 12; M1.5's were all 10 x 60, so a Rustbucket sat in
-- a runway): each painted bay (MapBuilder builds a ParkingSlot part this
-- size; BuildingArt.ParkingBay paints its edges) is the size of the rigs
-- it's for, about 3 studs wider and 4 longer (TruckLayout.RigSize;
-- WorldPlan.spec). VehicleService gives each rig the smallest free bay it
-- fits (VehicleLogic.BayChoices).
WorldPlan.ParkingBays = {
	small = Vector3.new(14.25, 0.2, 30), -- the Rustbucket, the Pickup, the Scout ATV
	flatbed = Vector3.new(15, 0.2, 38.75), -- the Flatbed, or the Rustbucket with the Pony trailer (38.7 bumper to bumper)
	long = Vector3.new(16, 0.2, 51), -- pull-through: the Logging Rig, a small truck with a trailer, the Flatbed with the Pony
	longest = Vector3.new(16, 0.2, 80), -- pull-through: the Logging Rig with any trailer (the Heavy Hauler: 75.4)
}
-- The standard bay (most of the lot's).
WorldPlan.ParkingSlotSize = WorldPlan.ParkingBays.small
-- Each bay keeps this many studs clear past its head (where the trucks'
-- noses point, the way they drive out) and, for a pull-through bay, past
-- its tail too (WorldPlan.spec). A rig longer than any free bay parks with
-- its tail at a bay's tail and its nose out over this lane (VehicleService).
WorldPlan.ParkingPullOut = 26

-- The town's gondola station; it turns its open back (+Z) toward the top
-- station on the isles, along the cable.
WorldPlan.TownGondolaSpot = Vector3.new(-40, 0, 150)
local function townGondola(): CFrame
	local def = BiomeData.Get("sky")
	local area = if def then def.area else nil
	if not area then
		return CFrame.new(WorldPlan.TownGondolaSpot)
	end
	return facingZ(WorldPlan.TownGondolaSpot, Vector3.new(area.x, 0, area.z))
end

function WorldPlan.Town(): Town
	local mill = WorldLayout.Sawmill
	-- At (x, z), turned by `yaw`.
	local function at(x: number, z: number, yaw: number?): CFrame
		return CFrame.new(x, 0, z) * CFrame.Angles(0, yaw or 0, 0)
	end
	-- At (x, z) with the front (-Z) toward (tx, tz).
	local function facing(x: number, z: number, tx: number, tz: number): CFrame
		return at(x, z, math.atan2(x - tx, z - tz))
	end

	-- Lamps (the layout from tools/preview/scenes/town.luau): along the
	-- main street (z 70 to 84) with their arms over it, at the head of the
	-- spawn walk, by the gondola path and the mill yard, and by the lot.
	-- None stand where trucks pull out of the parking bays (x 9 to 138),
	-- and none on a road (like every colliding thing in town: WorldPlan.spec).
	-- The lot's two lamps stand past its east rail (M1.5: the lot grew east),
	-- one south of the Plot Road's mouth, its arm toward it, one with its
	-- arm over the lot.
	local lamps: { CFrame } = {}
	for _, x in ipairs({ -92, -64, -30 }) do
		table.insert(lamps, at(x, 54, math.pi)) -- south side, set back off the widened street
	end
	-- The east one sits further south: Old Bram walks the corner, and the
	-- flower bed sits just east of where a closer lamp would stand.
	table.insert(lamps, at(-14, 38, math.pi))
	table.insert(lamps, at(30, 92, 0)) -- north side, set back off the street
	table.insert(lamps, at(-8, 60, -math.pi / 2))
	table.insert(lamps, at(8, 60, math.pi / 2))
	table.insert(lamps, at(-41, 134, -math.pi / 2)) -- west of the gondola path, arm east over it
	table.insert(lamps, at(36, 124, 0)) -- east of the mill's lean-to
	-- The sell station's four corner lamps, outside its rails (WorldPlan.spec
	-- keeps them off the pad, its lane and the roads).
	-- (The north-west one is the mill yard's lamp at (36, 124), below.)
	table.insert(lamps, at(36, 95, 0))
	table.insert(lamps, at(70, 95, 0))
	table.insert(lamps, at(70, 127, 0))
	table.insert(lamps, at(147.5, 36, math.pi)) -- south of the wider Plot Road
	table.insert(lamps, at(147.5, 0, math.pi / 2))

	-- Fences: a paddock behind Hearth & Home, a rail along the lot's east
	-- edge (z 6 to 42, ending short of the Plot Road).
	local fences: { Fence } = {
		{ length = 20, cframe = at(-118, 192) },
		{ length = 20, cframe = at(-118, 204) },
		{ length = 12, cframe = at(-128, 198, math.pi / 2) },
		{ length = 28, cframe = at(145, 20, math.pi / 2) }, -- ends short of the wider Plot Road
	}

	-- Murph's camp west of the spawn, behind the TO THE WOODS sign and clear
	-- of the Hills Road: the campfire at its origin, the tent behind (+Z),
	-- facing the spawn; Murph stands at camp-local (0, 0, -3), his lantern
	-- on its hook beside the camp, turned with it.
	local campsite = facing(-28, 45, 0, 40) -- north of the widened Hills Road
	local _, campYaw = campsite:ToEulerAnglesYXZ()
	local lantern = campsite * Vector3.new(9, 0, 2)

	local propSpots: { { any } } = { -- { name, x, z, yaw? }
		{ "Haybale", -142, 200, 0.3 },
		{ "Haybale", -137, 198, -0.5 },
		{ "Haybale", -147, 197, 1.2 },
		{ "Cart", -66, 200, -0.4 },
		{ "WaterTower", -56, 188 }, -- it stood inside the Tool Shed
		{ "ToolRack", 34.4, 100, math.pi / 2 }, -- between the mill and the Dealership
		{ "Well", -49, 54 }, -- on the green south of the widened street, between the benches
		{ "Bench", -58, 56, math.pi },
		{ "Bench", -40, 56, math.pi },
		{ "Barrel", -30.5, 92 },
		{ "Crate", -30.5, 88.6, 0.3 },
		{ "Barrel", 32, 93 },
		{ "Crate", 86, 92.5, -0.2 }, -- the station's sign took the old spot (71, 93)
		{ "Crate", 80, 102, 0.5 }, -- clear of the mill road's east leg
		{ "Planter", -61, 98 },
		{ "Planter", -105, 85.5 }, -- (was -103.5, 88: the Tool Shed grew 6.6 wider, its west wall now reaches it)
		{ "Mailbox", -121, 94, 0 },
		{ "FlowerBox", -97, 85.3, 0 },
		{ "LogPile", 35.5, 131, 0 }, -- east of the mill, clear of the yard lamp and the sell station
		{ "LogPile", 35.5, 137, 0.1 },
		{ "Wheelbarrow", 20, 93, -0.6 },
		{ "SawdustPile", 40, 125 }, -- by the lean-to, clear of the yard lamp
		{ "SawdustPile", -29.5, 91 },
		{ "Lantern", lantern.X, lantern.Z, campYaw },
		{ "Barrel", 34.5, 105 }, -- between the mill's lean-to and the Dealership
		{ "Barrel", 34.5, 107.2 },
		-- The grove gate's bell, west of the exit sign and the Forest Path.
		{ "MillBell", -28, -16 },
	}
	local props: { Placement } = {}
	for i, p in ipairs(propSpots) do
		local name: string, x: number, z: number, yaw: number? = p[1], p[2], p[3], p[4]
		table.insert(props, { name = name, cframe = at(x, z, yaw), seed = i * 13 })
	end

	-- Parking (phase 12): 13 bays on the lot's gravel (WorldLayout.ParkingLot,
	-- x 8 to 146, z -18 to 68; a server holds 12 players), each the size of
	-- its rigs (WorldPlan.ParkingBays), a stud apart so their stop bars meet.
	-- West to east, in claim order (Index 1 first: VehicleService gives a
	-- rig the smallest free bay it fits, the lowest Index on a tie):
	--   1-4   small, facing the forest (-Z), heads on z -17;
	--   5-8   small, back to back with them, facing the street (+Z), heads
	--         on z 44 (the lot's north end and the street beyond, to drive
	--         out on);
	--   9-10  the Flatbed's, 9 facing the forest, 10 the street;
	--   11    the longest (80), pull-through, facing the forest;
	--   12-13 long (51), pull-through, facing the forest.
	-- The pull-through bays stand where nothing grows south of the lot (east
	-- of x 77), so a long rig drives out straight; 11 stops 2 studs short
	-- of the Plot Road's mouth (x 110, z 50), 12 and 13 end at z 34. Every
	-- head (and pull-through tail) keeps ParkingPullOut clear; the westmost
	-- lane passes the spawn walk's lamp at (8, 60) (WorldPlan.spec).
	local bays = WorldPlan.ParkingBays
	local slots: { CFrame } = {}
	local sizes: { Vector3 } = {}
	local toStreet = CFrame.Angles(0, math.pi, 0)
	local function bay(x: number, z: number, size: Vector3, north: boolean?)
		local cf = CFrame.new(x, size.Y / 2, z)
		table.insert(slots, if north then cf * toStreet else cf)
		table.insert(sizes, size)
	end
	local smallX: { number } = {}
	for col = 0, 3 do
		table.insert(smallX, 10 + col * (bays.small.X + 1) + bays.small.X / 2)
	end
	for _, x in ipairs(smallX) do
		bay(x, -17 + bays.small.Z / 2, bays.small)
	end
	for _, x in ipairs(smallX) do
		bay(x, 44 - bays.small.Z / 2, bays.small, true)
	end
	local flatbedX = 71 + bays.flatbed.X / 2
	bay(flatbedX, -17 + bays.flatbed.Z / 2, bays.flatbed)
	bay(flatbedX, -17 + bays.flatbed.Z * 1.5 + 1, bays.flatbed, true) -- tail a stud past 9's
	bay(87 + bays.longest.X / 2, -17 + bays.longest.Z / 2, bays.longest)
	for _, x0 in ipairs({ 104, 121 }) do
		bay(x0 + bays.long.X / 2, -17 + bays.long.Z / 2, bays.long)
	end

	-- Signs: one by the spawn with every destination, the plots, and SELL
	-- LOGS HERE by the pad.
	local distances: { string } = {}
	for _, id in ipairs({ "starter", "hills", "snow", "volcano" }) do
		local def = BiomeData.Get(id)
		if def then
			table.insert(distances, string.format("%s  %d", def.displayName, def.haulStuds or 0))
		end
	end
	-- SELL LOGS HERE (TWN-04) stands upright at the station's south-east
	-- gate, facing the street: its posts east of the trucks' lane in, north
	-- of the street, clear of Millie and the props, so the main street's
	-- drivers and walkers read it. Like the corner lamps, it never stands on
	-- the street, the pad or a path (WorldPlan.spec).
	local signs: { Sign } = {
		{ text = "TO THE WOODS\n" .. table.concat(distances, "\n"), cframe = facing(-16, 44, 0, 40) },
		-- Just north of the truck-lot path (the apron ends at z=70 and the
		-- posts reach about five studs south), past the lot's east rail,
		-- facing the plot road (M1.5: it stood at (124, 64), then on the
		-- apron at (148.5, 67)). Clear of that apron, the next headland is
		-- in sight, so the lighthouse stands at (1203, 236).
		{ text = "PLOT DISTRICT\nLand Office: buy a plot\nand build on it", cframe = standing(148.5, 76, 0, 40) },
		-- The turn off the street's east end, just north of PlazaEastMouth,
		-- facing back down the path to the truck lot.
		{ text = "TRUCK LOT", cframe = standing(82, 100, 82, 70) },
		{ text = "SELL LOGS HERE", cframe = at(67, 90) * FACING_SOUTH, lit = true }, -- lamps over its face (TWN-07)
		-- The south exit, where the Forest Path leaves town for the Starter
		-- Forest. West of the road (the lot is to the east), lit, and well
		-- south of the spawn so the tutorial grove can
		-- still land there. The board faces the path.
		{
			text = "SAWMILL\nnorth, back to town\n\nFIRST GROVE\nsouth, down this road",
			cframe = facing(-22, -16, -5, -16),
			lit = true,
		},
	}

	-- One round every few studs, on the shop paths and north of the street,
	-- so a truck on the street never rolls over them. Not on the spawn walk.
	local pathRounds: { CFrame } = {}
	local function rounds(x: number)
		for _, z in ipairs({ 86.5, 89.5, 92.2 }) do
			table.insert(pathRounds, CFrame.new(x, 0, z))
		end
	end
	rounds(-110) -- General Store path (the lane west of the Tool Shed)
	rounds(-84) -- Tool Shed

	-- Greenery (TWN-01): ornamental trees seated in stone rings, framing the
	-- town (birch and maple round the edges, a pine band behind the mill
	-- and the gondola), bushes along the shops' and the station's sides,
	-- flower beds by the plaza, the spawn walk and the shop paths' mouths,
	-- and a few rocks. Looks only, but for the trees' trunks, which collide
	-- (MapBuilder never tags them Tree or puts them in the Trees folder, so
	-- nobody can chop them). No oaks, so Murph's "find an oak" always means
	-- a tree you can chop. All of it stays off the paint, the lot, the
	-- sell pad and the parking pull-outs, 2 studs off the roads, 4 studs
	-- from the colliding props, off the townsfolk's walks and out of the
	-- gondola's way (WorldPlan.spec). No trunk stands east of the mill at x
	-- 22 to 42 or between there and the Snow Road's start at (0, 205): room
	-- for the lane north (TWN-05). Seeds come from the spot.
	local greenery: { Greenery } = {}
	local greenSpots: { { any } } = { -- { kind, x, z, size, woodId? }
		-- The pine band behind the mill and the gondola (z 140 to 200).
		{ "tree", -12, 146, 1.22, "pine" },
		{ "tree", 4, 153, 1, "pine" },
		{ "tree", -2, 169, 1.22, "pine" },
		{ "tree", 9, 180, 1, "pine" },
		{ "tree", -20, 164, 1, "pine" },
		{ "tree", -30, 184, 1.22, "pine" },
		{ "tree", -44, 177, 1, "pine" },
		{ "tree", -26, 196, 1, "pine" },
		{ "tree", -150, 160, 1, "pine" },
		{ "tree", -40, 198, 1.22, "pine" },
		{ "tree", -134, 150, 1, "pine" },
		{ "tree", -146, 176, 1.22, "pine" },
		-- Birch and maple round the edges.
		{ "tree", -148, 80, 1.22, "maple" },
		{ "tree", -132, 112, 1, "birch" },
		{ "tree", -140, 96, 1.22, "birch" },
		{ "tree", -146, 128, 1, "maple" },
		{ "tree", -88, 4, 1, "maple" },
		{ "tree", -62, 6, 1, "birch" },
		{ "tree", -112, 0, 1.22, "birch" },
		{ "tree", -72, 232, 1, "birch" },
		{ "tree", 82, 144, 1.22, "birch" },
		{ "tree", 78, 136, 1.22, "maple" },
		{ "tree", 128, 134, 1, "birch" },
		{ "tree", 124, 150, 1, "maple" },
		{ "tree", 136, 168, 1.22, "birch" },
		{ "tree", 78, 200, 1.22, "maple" },
		-- By the lot (M1.5: off it and its pull-outs since it grew east): one
		-- north of the Plot Road's mouth (and of the lighthouse's line from
		-- the spawn), one past the south pull-outs.
		{ "tree", 346, 128, 1, "birch" },
		{ "tree", 132, -80, 1.22, "maple" },
		-- Bushes along the shops' sides, the mill's back and the station.
		{ "bush", -138, 108, 2.8 },
		{ "bush", -136, 118, 2.4 },
		{ "bush", 86, 112, 2.6 }, -- east of the station
		{ "bush", 86, 131, 3 },
		{ "bush", 48, 140, 2.8 }, -- behind it
		{ "bush", 66, 141, 2.6 },
		{ "bush", -6, 143, 2.6 },
		{ "bush", 10, 142.5, 2.8 },
		{ "bush", -51.5, 146, 2.8 },
		{ "bush", -28, 148, 2.6 },
		{ "bush", -28.5, 154, 2.4 },
		-- Flower beds: off the plaza's south-west corner, by the spawn walk,
		-- at the mouths of the Hearth & Home path, by the well. (None where
		-- the townsfolk walk: NPCData's routes pass 3 studs or more away.)
		{ "flowers", -108, 54, 2.4 },
		{ "flowers", -8.4, 44, 2 },
		{ "flowers", -61.5, 90, 2.2 },
		{ "flowers", -123, 90, 1.8 },
		{ "flowers", -57.5, 46, 2.4 },
		-- Rocks.
		{ "rock", -55, 150, 1.8 },
		{ "rock", 84, 135, 2 },
		{ "rock", -126, 102, 1.6 },
		{ "rock", 352, 118, 1.8 },
	}
	for _, g in ipairs(greenSpots) do
		local kind: string, x: number, z: number, size: number, woodId: string? = g[1], g[2], g[3], g[4], g[5]
		local seed = Kit.seedAt(x, z)
		table.insert(greenery, {
			kind = kind,
			woodId = woodId,
			cframe = CFrame.new(x, TerrainGen.HeightAt(x, z), z) * CFrame.Angles(0, (seed % 628) / 100, 0),
			size = size,
			seed = seed,
		})
	end

	-- The five models shown in the town previews, on this town (Lane B has not
	-- merged). The sky forge court sits on the south-west meadow, its front
	-- (-Z) turned north toward the mill, on SkyForgeFloor. The lookout stands
	-- just west of it, telescope toward town. The park bench and the campfire
	-- sit on the green south of MainStreet, west of the well's benches. The
	-- fishing dock stands on the Starter Forest pond's north bank, its -Z
	-- out over the water; the deck's underside (1.06 above the model's
	-- origin, PropArt.Scene) rests on that bank so the posts reach the pond.
	local pond = WorldLayout.Pond
	local bankX, bankZ = pond.x, pond.z + pond.radius + 3
	local bankY = TerrainGen.HeightAt(bankX, bankZ)
	local DECK_BOTTOM = 1.06
	local scenes: { SceneSpot } = {
		{ kind = "forge", cframe = at(-112, -20, math.pi) },
		{ kind = "lookout", cframe = at(-136, -20, math.pi) },
		{ kind = "bench", cframe = at(-84, 56, math.pi) },
		{ kind = "campfire", cframe = at(-72, 56, math.pi) },
		{ kind = "fishing", cframe = CFrame.new(bankX, bankY - DECK_BOTTOM, bankZ) },
	}

	-- A character spawns facing its SpawnLocation's front (LookVector), so
	-- turn the pad's front (-Z) half a turn to +Z: the sawmill is due north
	-- of the spawn, framed by the walk's two lamps. (Angles, not
	-- CFrame.lookAt: Lune gets lookAt wrong, and Shared code runs there.)
	local spawn = Vector3.new(0, 0.5, 40)
	local spawnFacing = CFrame.new(spawn) * CFrame.Angles(0, math.pi, 0)

	return {
		spawn = spawn,
		spawnFacing = spawnFacing,
		-- The sawmill and the shops are built 1.5x their design size
		-- (BuildingArt.Scale, TWN-13), placed so their fronts stay where they
		-- were: the mill's at z 97, centred on the spawn walk (the sell
		-- station is beside it now); the shops' on their paths. They grew back and sideways
		-- (the Tool Shed and Hearth & Home west, the Dealership east).
		sawmill = CFrame.new(mill.X, 0, mill.Z + 6.5) * FACING_SOUTH,
		-- The sell station beside the mill's east lean-to (WorldPlan.SellZoneSize:
		-- 28 x 52, z 85 to 137, over the pad's middle). It stays west of the
		-- Dealership's loading pad (WorldLayout, x 70 to 84). The offsets are
		-- the station's place: the map remake keeps the sawmill, and these
		-- two stay 53 east and 1 north of it. Trucks back straight north off
		-- MainStreet into the lane. Lane C may restyle the pad as a furnace
		-- joined to the mill; the zone stays this box.
		sellZone = CFrame.new(mill.X + 53, 6, mill.Z + 1),
		sellPad = CFrame.new(mill.X + 53, 0, mill.Z + 1),
		shops = {
			{
				kind = "ToolShed",
				title = "TOOL SHED",
				accent = Color3.fromRGB(150, 62, 44),
				cframe = CFrame.new(-84, 0, 117.7), -- 45 deep (it was 38.4): the front stays at z 95.2, west of the sell pad keep-out (x -60 to 60)
			},
			{
				kind = "Dealership",
				title = "DEALERSHIP",
				accent = Color3.fromRGB(47, 109, 181),
				cframe = CFrame.new(DealershipLot.Hall().cx, 0, DealershipLot.Hall().cz), -- the showroom hall on the old lot
			},
			{
				kind = "HearthAndHome",
				title = "GENERAL STORE",
				accent = Color3.fromRGB(122, 90, 60),
				cframe = CFrame.new(-100, 0, 187.5), -- 43.5 deep, behind the Tool Shed with a 20-stud lane between (its path runs up the lane west of the shed)
			},
		},
		gondola = townGondola(),
		campsite = campsite,
		murph = campsite * CFrame.new(0, 0, -3),
		parkingSlots = slots,
		parkingSizes = sizes,
		lamps = lamps,
		fences = fences,
		props = props,
		signs = signs,
		greenery = greenery,
		pathRounds = pathRounds,
		scenes = scenes,
		-- Open display lot on the lawn north of the plot road. Trucks face
		-- -Z, toward that road. The corner is the zone in WorldLayout.
		displayLot = CFrame.new(
			DealershipLot.OriginX + DealershipLot.Size() / 2,
			DealershipLot.FloorY, -- the hall's floor top: the plinths and boxes stand on it
			DealershipLot.OriginZ + select(2, DealershipLot.Size()) / 2
		),
	}
end

-- Signposts where the roads reach each biome: facing back down the road,
-- listing the woods and the gear you need. (The Gloam Hollow has none.)
-- Each stands beside the road's last stretch, its near post a little over
-- SIGN_CLEAR studs off the road, where the ground under both posts is
-- level within a stud: from 6 studs before the road's end, stepping back
-- down the road and trying both sides until it is. Where the road is cut
-- into a hillside and nowhere is, it stands along the road instead, close
-- in, where the road's grading keeps the ground level. Either way it's set
-- on the lower post's ground, so neither post floats.
-- (BuildingArt.Signpost's posts' outer faces are SIGN_POST either side of
-- its middle.)
local SIGN_POST = 4.95 + 0.35
local SIGN_CLEAR = 2

-- What a biome's road sign says (MapBuilder's road signs and the world
-- preview both use it): the biome's name, its woods (in WoodData's order),
-- the gear it asks for (the gear it needs, or the gear that takes its
-- slowdown away) and, for the sky, the gondola. An unknown id is shown as
-- it is.
function WorldPlan.BiomeSignText(biomeId: string): string
	local biome = BiomeData.Get(biomeId)
	if not biome then
		return biomeId
	end
	local woods: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		if (biome.trees or {})[wood.id] then
			table.insert(woods, string.lower(wood.displayName))
		end
	end
	local text = string.upper(biome.displayName) .. "\n" .. table.concat(woods, " · ")
	local gearId = biome.requiresGear or (if biome.slowdown then biome.slowdown.removedBy else nil)
	local gear = if gearId then ItemCatalog.GetGear(gearId) else nil
	if gear then
		text ..= "\nBring: " .. gear.displayName
	end
	if biome.gondola then
		text ..= "\nGondola to the Aether Isles"
	end
	return text
end

function WorldPlan.RoadSigns(text: (biomeId: string) -> string): { Sign }
	local out: { Sign } = {}
	local roadFor = {
		HillsRoad = "hills",
		SnowRoad = "snow",
		VolcanoRoad = "volcano",
		SkyrootRoad = "sky",
		BayouRoad = "bayou",
		MesaRoad = "redmesa",
	}
	-- Reserved regions are not biomes yet. The post names the place; Lane R
	-- adds the woods later.
	local reservedSign = { bayou = "BAYOU", redmesa = "RED MESA" }
	-- `flat` (at y = 0) set down on the lower post's ground, and whether the
	-- ground under its posts and middle is level within a stud.
	local function setDown(flat: CFrame): (CFrame, boolean)
		local a, b, m = flat * Vector3.new(-SIGN_POST, 0, 0), flat * Vector3.new(SIGN_POST, 0, 0), flat.Position
		local ha, hb, hm = TerrainGen.HeightAt(a.X, a.Z), TerrainGen.HeightAt(b.X, b.Z), TerrainGen.HeightAt(m.X, m.Z)
		local level = math.max(ha, hb, hm) - math.min(ha, hb, hm) < 1
			and TerrainGen.RoadClearance(a.X, a.Z) >= SIGN_CLEAR
			and TerrainGen.RoadClearance(b.X, b.Z) >= SIGN_CLEAR
			and TerrainGen.WaterLevelAt(m.X, m.Z) == nil
		return flat + Vector3.new(0, math.min(ha, hb), 0), level
	end
	for _, road in ipairs(WorldLayout.Roads) do
		local biomeId = roadFor[road.name]
		if biomeId then
			local pts = road.points
			local last, prev = pts[#pts], pts[#pts - 1]
			local dir = (last - prev).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			local toward = Vector3.new(prev.X, 0, prev.Y)
			local spot: CFrame? = nil
			for back = 6, math.max(6, (last - prev).Magnitude - 6), 4 do
				for _, s in ipairs({ 1, -1 }) do
					for extra = 0, 18, 6 do
						local at = last
							- dir * back
							+ side * (s * (road.width / 2 + SIGN_POST + SIGN_CLEAR + 0.5 + extra))
						local cf, level = setDown(CFrame.lookAt(Vector3.new(at.X, 0, at.Y), toward))
						if level then
							spot = cf
							break
						end
					end
					if spot then
						break
					end
				end
				if spot then
					break
				end
			end
			if not spot then
				local at = last - dir * 6 + side * (road.width / 2 + 0.35 + SIGN_CLEAR + 0.5)
				local roadSide = Vector3.new(at.X - side.X, 0, at.Y - side.Y) -- its face toward the road
				spot = setDown(CFrame.lookAt(Vector3.new(at.X, 0, at.Y), roadSide))
			end
			local label = reservedSign[biomeId]
			table.insert(out, { text = if label then label else text(biomeId), cframe = spot :: CFrame })
		end
	end
	return out
end

-- A sign at each region's gate: beside the Snow Road and the Volcano Road
-- where they cross the cliff ring, and beside the trail into the hollow.
-- Separate from RoadSigns, which stay at the road's end.
function WorldPlan.GateSigns(text: (biomeId: string) -> string): { Sign }
	local out: { Sign } = {}
	local function setDown(flat: CFrame): (CFrame, boolean)
		local a, b, m = flat * Vector3.new(-SIGN_POST, 0, 0), flat * Vector3.new(SIGN_POST, 0, 0), flat.Position
		local ha, hb, hm = TerrainGen.HeightAt(a.X, a.Z), TerrainGen.HeightAt(b.X, b.Z), TerrainGen.HeightAt(m.X, m.Z)
		local level = math.max(ha, hb, hm) - math.min(ha, hb, hm) < 1
			and TerrainGen.RoadClearance(a.X, a.Z) >= SIGN_CLEAR
			and TerrainGen.RoadClearance(b.X, b.Z) >= SIGN_CLEAR
			and TerrainGen.WaterLevelAt(m.X, m.Z) == nil
		return flat + Vector3.new(0, math.min(ha, hb), 0), level
	end
	local function besideRoad(roadName: string, rimKind: string, biomeId: string)
		local road: WorldLayout.Road? = nil
		local rim: WorldLayout.Rim? = nil
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == roadName then
				road = r
			end
		end
		for _, r in ipairs(WorldLayout.Rims) do
			if r.kind == rimKind then
				rim = r
			end
		end
		if not road or not rim then
			return
		end
		local pts = road.points
		local mid = (rim.inner + rim.outer) / 2
		local bestP, bestDir, bestErr = pts[1], (pts[2] - pts[1]).Unit, math.huge
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			local steps = math.max(2, math.floor(len / 6))
			for s = 0, steps do
				local p = a:Lerp(b, s / steps)
				local err = math.abs((p - Vector2.new(rim.cx, rim.cz)).Magnitude - mid)
				if err < bestErr then
					bestErr = err
					bestP = p
					bestDir = (b - a).Unit
				end
			end
		end
		local side = Vector2.new(-bestDir.Y, bestDir.X)
		local spot: CFrame? = nil
		for _, s in ipairs({ 1, -1 }) do
			local at = bestP + side * (s * (road.width / 2 + SIGN_POST + SIGN_CLEAR + 1))
			local cf, level = setDown(CFrame.lookAt(Vector3.new(at.X, 0, at.Y), Vector3.new(bestP.X, 0, bestP.Y)))
			if level then
				spot = cf
				break
			end
		end
		if spot then
			table.insert(out, { text = text(biomeId), cframe = spot })
		end
	end
	besideRoad("SnowRoad", "snow", "snow")
	besideRoad("VolcanoRoad", "volcano", "volcano")
	local grove = BiomeData.Get("grove")
	local area = if grove then grove.area else nil
	if area then
		local gap = WorldLayout.GroveGap
		local dir = Vector2.new(math.cos(gap), math.sin(gap))
		local side = Vector2.new(-dir.Y, dir.X)
		local foot = Vector2.new(area.x, area.z) + dir * (WorldLayout.GroveRidge.inner - 6)
		local spot: CFrame? = nil
		for _, s in ipairs({ 1, -1 }) do
			local at = foot + side * (s * 16)
			local town = Vector3.new(WorldLayout.Sawmill.X, 0, WorldLayout.Sawmill.Z)
			local cf, level = setDown(CFrame.lookAt(Vector3.new(at.X, 0, at.Y), town))
			if level then
				spot = cf
				break
			end
		end
		if spot then
			table.insert(out, { text = text("grove"), cframe = spot })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The Aether Isles and the Skyroot
---------------------------------------------------------------------------

export type Isle = { center: Vector3, radius: number, dir: Vector3 }

export type Sky = {
	root: Vector3, -- the Skyroot's foot on the ground
	trunkHeight: number,
	top: number, -- the main isle's surface height
	main: Isle,
	isles: { Isle },
	bridges: { { a: Vector3, b: Vector3 } },
	chutes: { CFrame }, -- each on an outer isle's edge, its +Z (the flume) outward
	forge: CFrame,
	gondolaTop: CFrame,
	gondolaBase: CFrame,
	lumenwood: { Vector3 },
	shards: { Vector3 },
	waterfall: { top: Vector3, bottom: Vector3, dir: Vector3, isle: number },
}

function WorldPlan.Sky(): Sky?
	local def = BiomeData.Get("sky")
	local area = if def then def.area else nil
	if not def or not area then
		return nil
	end
	local rootY = TerrainGen.HeightAt(area.x, area.z)
	local center = Vector3.new(area.x, 0, area.z)
	local top = (area.y or 650) + 50
	local mill = WorldLayout.Sawmill
	local toTown = Vector3.new(mill.X - center.X, 0, mill.Z - center.Z).Unit
	local townAngle = math.atan2(toTown.Z, toTown.X)
	local main: Isle = { center = center + Vector3.new(0, top, 0), radius = 50, dir = toTown }

	local rng = Kit.rng(1717)
	local isles: { Isle } = {}
	local bridges = {}
	local chutes: { CFrame } = {}
	local lumen: { Vector3 } = {}
	local shards: { Vector3 } = {}
	local treeCounts: { [string]: number } = def.trees or {}
	local nodeCounts: { [string]: number } = def.nodes or {}
	local treesPerIsle = math.max(1, math.floor((treeCounts.lumenwood or 12) / 3))
	local shardCount = nodeCounts.SkyShard or 8
	local outerShards = math.max(0, shardCount - 2)
	for i, turn in ipairs({ 70, 180, 290 }) do
		local angle = townAngle + math.rad(turn)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local height = top + ({ 5, -5, 10 })[i]
		local isle: Isle = { center = center + dir * 120 + Vector3.new(0, height, 0), radius = 40, dir = dir }
		table.insert(isles, isle)
		table.insert(bridges, { a = main.center + dir * 48, b = isle.center - dir * 38 })
		-- Lumenwood near the middle (a felled tree's logs stay on the isle).
		for k = 1, treesPerIsle do
			local a = (k - 1) / treesPerIsle * math.pi * 2 + rng:range(-0.3, 0.3)
			local r = rng:range(8, 18)
			table.insert(lumen, isle.center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		end
		-- Crystal nodes toward the rim, clear of the chute.
		local per = math.ceil(outerShards / 3)
		for k = 1, per do
			if #shards < outerShards then
				local a = angle + math.pi + (k - (per + 1) / 2) * 0.9
				table.insert(shards, isle.center + Vector3.new(math.cos(a) * 27, 0, math.sin(a) * 27))
			end
		end
		-- BuildingArt.CloudChute's flume runs out along its +Z: off the isle.
		local chutePos = isle.center + dir * 33
		table.insert(chutes, facingZ(chutePos, chutePos + dir))
	end
	-- The main isle: the forge to one side, two nodes on the other.
	local side = Vector3.new(-toTown.Z, 0, toTown.X)
	for k = 1, math.min(2, shardCount) do
		table.insert(shards, main.center - side * (14 + k * 8) - toTown * 10)
	end
	local forgeAt = main.center + side * 16
	local base = Vector3.new(
		center.X + toTown.X * 62,
		TerrainGen.HeightAt(center.X + toTown.X * 62, center.Z + toTown.Z * 62),
		center.Z + toTown.Z * 62
	)
	-- The waterfall pours off the outer isle nearest the river's spring.
	local spring = WorldLayout.River.points[1]
	local nearest, nearestIndex = isles[1], 1
	for i, isle in ipairs(isles) do
		local d = Vector2.new(isle.center.X - spring.X, isle.center.Z - spring.Y).Magnitude
		local best = Vector2.new(nearest.center.X - spring.X, nearest.center.Z - spring.Y).Magnitude
		if d < best then
			nearest, nearestIndex = isle, i
		end
	end
	local toSpring = Vector3.new(spring.X - nearest.center.X, 0, spring.Y - nearest.center.Z)
	local fallDir = if toSpring.Magnitude > 1 then toSpring.Unit else nearest.dir
	-- The lip, just past the isle's rim (IsleArt.Isle's spout runs to it).
	local fallTop = nearest.center + fallDir * (nearest.radius + 1) - Vector3.new(0, 0.4, 0)
	return {
		root = Vector3.new(area.x, rootY, area.z),
		trunkHeight = top - 12 - rootY,
		top = top,
		main = main,
		isles = isles,
		bridges = bridges,
		chutes = chutes,
		forge = CFrame.lookAt(forgeAt, forgeAt - side),
		-- Stations turn their open back (+Z) along the cable: the top one
		-- toward town, the foot one up toward the top.
		gondolaTop = facingZ(main.center + toTown * 44, WorldPlan.TownGondolaSpot),
		gondolaBase = facingZ(base, main.center + toTown * 44),
		lumenwood = lumen,
		shards = shards,
		waterfall = {
			top = fallTop,
			bottom = Vector3.new(fallTop.X, WorldLayout.LakeLevel, fallTop.Z),
			dir = fallDir, -- flat, away from the isle
			isle = nearestIndex, -- which of `isles` it pours off
		},
	}
end

-- The flume under a Cloud Chute at `cf` (one of Sky().chutes), as the two
-- ends of the beam MapBuilder and the previews draw: from the lip of
-- BuildingArt.CloudChute's own trough (FLUME_LIP, at its +Z end), out
-- along the chute's +Z (cf.LookVector * -FLUME_OUT: off the isle) and
-- FLUME_DROP down into the clouds.
local FLUME_LIP = Vector3.new(0, -2.6, 13.6)
local FLUME_OUT = 36
local FLUME_DROP = 60

function WorldPlan.ChuteFlume(cf: CFrame): (Vector3, Vector3)
	local from = cf * FLUME_LIP
	return from, from + cf.LookVector * -FLUME_OUT - Vector3.new(0, FLUME_DROP, 0)
end

-- The gondola's route from a station's Platform (its centre `from`, its
-- open back `back` facing along the cable) up to the top station's
-- Platform (`to`, its open back facing out over the main isle's rim):
-- level out of the station's back until the cabin is clear of its roof,
-- then up to a point level with the top platform just past the rim, then
-- level in under the top station's roof. The rides and the drawn cable
-- both follow it, each at its own height above it, so neither cuts through
-- a station's roof or the isle. (The cabin is 5.4 across; a station's roof,
-- its barge boards, reaches 5.2 behind its middle; the isle's grassy rim
-- 1.1 past its radius, and its rim stones' corners about 3.4 past it.)
local GONDOLA_OUT = 9
local GONDOLA_RIM = 7

function WorldPlan.GondolaPath(sky: Sky, from: Vector3, back: Vector3, to: Vector3): { Vector3 }
	local c = sky.main.center
	local out = Vector3.new(to.X - c.X, 0, to.Z - c.Z).Unit
	local rim = Vector3.new(c.X, to.Y, c.Z) + out * (sky.main.radius + GONDOLA_RIM)
	return { from, from + Vector3.new(back.X, 0, back.Z).Unit * GONDOLA_OUT, rim, to }
end

-- The point `alpha` (0 to 1) of the way along `path`, by length (so a
-- cabin moving along it keeps an even speed round the bends).
-- The drawn cable for a gondola route (GondolaPath): CABLE_UP above it,
-- except on a near-vertical stretch (the climb beside the Skyroot). A cable
-- straight above that would run down through the cabin itself, and any
-- piece crossing the column the cabin climbs through would cut it on the
-- way up. So the cable leaves the route CABLE_CLEAR before the climb,
-- steps CABLE_SIDE aside (across `back`, the station's back), runs up
-- beside the climb and comes back over at the top, above the highest
-- cabin. Pairs of points, one rod each.
local CABLE_UP = 8.5
local CABLE_SIDE = 4.5 -- the cabin reaches 2.7 from its middle (plus the rod)
local CABLE_CLEAR = 4
function WorldPlan.GondolaCable(path: { Vector3 }, back: Vector3): { { Vector3 } }
	local up = Vector3.new(0, CABLE_UP, 0)
	local flatBack = Vector3.new(back.X, 0, back.Z)
	local side = if flatBack.Magnitude > 1e-6
		then flatBack.Unit:Cross(Vector3.new(0, 1, 0)) * CABLE_SIDE
		else Vector3.new(CABLE_SIDE, 0, 0)
	local function steep(i: number): boolean
		local d = path[i + 1] - path[i]
		return math.abs(d.Y) > Vector3.new(d.X, 0, d.Z).Magnitude
	end
	local out: { { Vector3 } } = {}
	local start = path[1] + up -- where the next piece starts
	for i = 1, #path - 1 do
		local a, b = path[i] + up, path[i + 1] + up
		if steep(i) then
			table.insert(out, { start, start + side })
			table.insert(out, { start + side, a + side })
			table.insert(out, { a + side, b + side })
			table.insert(out, { b + side, b })
			start = b
		else
			local finish = b
			if i + 1 <= #path - 1 and steep(i + 1) then
				-- Stop short of the climb: the next pieces step aside from here.
				local d = b - a
				finish = if d.Magnitude > CABLE_CLEAR then b - d.Unit * CABLE_CLEAR else a
			end
			if (finish - start).Magnitude > 1e-6 then
				table.insert(out, { start, finish })
			end
			start = finish
		end
	end
	return out
end

function WorldPlan.AlongPath(path: { Vector3 }, alpha: number): Vector3
	local total = 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	local left = math.clamp(alpha, 0, 1) * total
	for i = 1, #path - 1 do
		local len = (path[i + 1] - path[i]).Magnitude
		if left <= len and len > 0 then
			return path[i]:Lerp(path[i + 1], left / len)
		end
		left -= len
	end
	return path[#path]
end

-- Points on an isle's top (relative to its centre `center`) that its
-- decoration keeps clear of: bridge ends, Cloud Chutes, the forge and the
-- top gondola station (IsleArt.Isle's `clear` option).
function WorldPlan.IsleClearPoints(sky: Sky, center: Vector3): { Vector3 }
	local out: { Vector3 } = {}
	for _, b in ipairs(sky.bridges) do
		table.insert(out, b.a - center)
		table.insert(out, b.b - center)
	end
	for _, cf in ipairs(sky.chutes) do
		table.insert(out, cf.Position - center)
	end
	table.insert(out, sky.forge.Position - center)
	table.insert(out, sky.gondolaTop.Position - center)
	return out
end

-- Every isle's centre relative to the Skyroot's foot, main isle first
-- (IsleArt.Skyroot reaches a limb up into each).
function WorldPlan.IslesFromRoot(sky: Sky): { Vector3 }
	local out = { sky.main.center - sky.root }
	for _, isle in ipairs(sky.isles) do
		table.insert(out, isle.center - sky.root)
	end
	return out
end

---------------------------------------------------------------------------
-- The backdrop beyond the world's edge (WLD-02, WLD-09)
---------------------------------------------------------------------------

-- Clients stream the world in about 1,024 studs round them, so from town
-- the mountains at the map's edges, the volcano and the ground under the
-- Skyroot are mostly not there; and from the isles and high ground the
-- world's cut edge at +-1500 shows. The backdrop fills the horizon all
-- round. It is looks only: MapBuilder builds it as one Persistent model of
-- decor parts, and the world previews draw the same pieces.
--   * A skirt of land beyond the north, west and south walls, out to
--     BackdropReach, its top just under the terrain along the wall, so it
--     never stands up as a cliff above the rim; its inner edge a bank
--     rising from the wall (no flat wall face toward town). The Lake's
--     outflow runs on into a canyon.
--   * A ring of low-poly mountains on it: a near row of mossy ridges and a
--     far row of grey, snow-capped peaks, every one a pitched gable whose
--     end faces the world. They stay low behind the volcano, as seen from
--     the town square, so its cone stands against the sky.
--   * The sea beyond the east wall (beyond the beach, and beyond the sea
--     cliffs north of it, so the volcano stands against sky and sea), and
--     south of the south wall from the coast, with a few far islands.
--   * An impostor of the volcano's cone, wholly inside and under the real
--     one: it shows only while the terrain there isn't streamed in.
--   * A footing under the Skyroot's roots, just under the ground.
-- Every piece is beyond a world wall, or under dry ground wherever it
-- reaches inside them (WorldPlan.spec proves both).

export type BackdropPiece = {
	name: string,
	kind: string, -- "Block", "Wedge" (Kit.wedge's shape) or "Cylinder" (along its X axis)
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number,
}

local HALF = WorldLayout.WorldHalf
local SEA_LEVEL = WorldLayout.SeaLevel
local BACKDROP_REACH = 3000 -- the skirt and the sea run out this far from the middle
WorldPlan.BackdropReach = BACKDROP_REACH
WorldPlan.BackdropSeaTop = SEA_LEVEL - 0.2 -- just under the terrain's own sea
-- The town square at eye height: the volcano's gap in the ring is cut for
-- this eye.
WorldPlan.BackdropEye = Vector3.new(0, 6, 90)

local SKIRT_STEP = 4 -- studs between the terrain samples along a wall
local SKIRT_IN = 2 -- the samples sit this far inside the wall
local SKIRT_BELOW = 4 -- a skirt block's top sits this far under the lowest of them
local SKIRT_LONG = 500 -- the longest skirt block along a wall
local SKIRT_CLIFF = 40 -- a jump this big between samples splits the skirt (cliffs, river banks)
local SKIRT_BOTTOM = SEA_LEVEL - 15 -- every skirt block reaches down to here
local BANK = 400 -- a skirt block's bank rises from SKIRT_BOTTOM at the wall to its top this far out
local FOOT_BELOW = 25 -- mountain feet sink this far under the skirt
local CAP_CLEAR = 10 -- a snow cap's faces stand this far off the rock's (no z-fighting far off)
local FACET = 3 -- the volcano impostor's facets are this thick, inward
local FOOTING_RADIUS = 85 -- the Skyroot's footing (its roots spread 110; the river's spring is 112 out)
local FOOTING_BELOW = 3 -- under the lowest ground over it

local BACKDROP_COLORS = {
	snow = Color3.fromRGB(222, 230, 240),
	moss = {
		Color3.fromRGB(98, 118, 88),
		Color3.fromRGB(106, 124, 92),
		Color3.fromRGB(92, 110, 84),
		Color3.fromRGB(112, 122, 102),
	},
	rock = {
		Color3.fromRGB(116, 116, 120),
		Color3.fromRGB(126, 124, 126),
		Color3.fromRGB(110, 112, 118),
		Color3.fromRGB(136, 134, 136),
		Color3.fromRGB(122, 120, 116),
	},
	island = { Color3.fromRGB(86, 132, 70), Color3.fromRGB(96, 140, 76), Color3.fromRGB(104, 128, 84) },
	skirt = Color3.fromRGB(104, 136, 78),
	sea = Color3.fromRGB(62, 140, 150),
	seabed = Color3.fromRGB(56, 108, 112),
	riverbed = Color3.fromRGB(70, 74, 62),
	basalt = Color3.fromRGB(52, 46, 44),
	slate = Color3.fromRGB(74, 66, 62),
}

local function backdropPiece(
	name: string,
	kind: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): BackdropPiece
	return {
		name = name,
		kind = kind,
		cframe = cframe,
		size = size,
		color = color,
		material = material,
		transparency = transparency or 0,
	}
end

-- A wall of the world: `out` points away from the middle, `along` runs
-- along it.
type Side = { name: string, out: Vector3, along: Vector3 }
local SIDE_N: Side = { name = "N", out = Vector3.new(0, 0, 1), along = Vector3.new(1, 0, 0) }
local SIDE_W: Side = { name = "W", out = Vector3.new(-1, 0, 0), along = Vector3.new(0, 0, 1) }
local SIDE_S: Side = { name = "S", out = Vector3.new(0, 0, -1), along = Vector3.new(1, 0, 0) }

-- The point `u` along a wall and `d` beyond it, on the ground plane.
local function sidePoint(side: Side, u: number, d: number): Vector3
	return side.out * (HALF + d) + side.along * u
end

-- A stretch beyond a wall, from u0 to u1 along it: a skirt block (its
-- top, and whether its inner edge is a bank), a river leaving the world
-- (its water's surface and bed) or a gap where the sea runs on.
type Stretch = { u0: number, u1: number, top: number, bed: number?, bank: boolean? }
type Wall = { side: Side, blocks: { Stretch }, rivers: { Stretch }, gaps: { Stretch } }

-- The terrain just inside a wall, every SKIRT_STEP studs, split into runs
-- where it jumps.
type Sample = { u: number, h: number, water: number? }
local function wallRuns(side: Side): { { Sample } }
	local runs: { { Sample } } = {}
	local current: { Sample } = {}
	local last: Sample? = nil
	for u = -HALF, HALF, SKIRT_STEP do
		local p = sidePoint(side, u, -SKIRT_IN)
		local s: Sample = { u = u, h = TerrainGen.HeightAt(p.X, p.Z), water = TerrainGen.WaterLevelAt(p.X, p.Z) }
		if last and math.abs(s.h - last.h) > SKIRT_CLIFF then
			table.insert(runs, current)
			current = {}
		end
		table.insert(current, s)
		last = s
	end
	table.insert(runs, current)
	-- A run of only a few samples (a ledge on a river's bank) joins the
	-- next one (the last joins the one before).
	local merged: { { Sample } } = {}
	for i, run in ipairs(runs) do
		if #run < 4 and i < #runs then
			local nextRun = runs[i + 1]
			for k = #run, 1, -1 do
				table.insert(nextRun, 1, run[k])
			end
		elseif #run < 4 and #merged > 0 then
			for _, s in ipairs(run) do
				table.insert(merged[#merged], s)
			end
		else
			table.insert(merged, run)
		end
	end
	return merged
end

-- One wall's skirt: blocks (at most SKIRT_LONG long) over its dry runs,
-- each SKIRT_BELOW under the lowest terrain along it; the rivers it
-- crosses; and gaps where the run dips to the sea.
local function wallSkirt(side: Side): Wall
	local wall: Wall = { side = side, blocks = {}, rivers = {}, gaps = {} }
	local runs = wallRuns(side)
	local lows: { number } = {}
	for r, run in ipairs(runs) do
		lows[r] = math.huge
		for _, s in ipairs(run) do
			lows[r] = math.min(lows[r], s.h)
		end
	end
	-- Where two runs meet (at a cliff), the stretch between their samples
	-- goes to the lower one: a block never overhangs the drop.
	local function cut(r: number): number
		local before, after = runs[r - 1], runs[r]
		return if lows[r - 1] < lows[r] then after[1].u else before[#before].u
	end
	for r, run in ipairs(runs) do
		local u0 = if r == 1 then -HALF else cut(r)
		local u1 = if r == #runs then HALF else cut(r + 1)
		local lowest = lows[r]
		local river: number? = nil
		for _, s in ipairs(run) do
			local w = s.water
			if w and w > SEA_LEVEL + 0.5 then
				river = math.max(river or w, w)
			end
		end
		if lowest - SKIRT_BELOW < SEA_LEVEL + 0.5 then
			if river then
				table.insert(wall.rivers, { u0 = u0, u1 = u1, top = river, bed = lowest })
			else
				table.insert(wall.gaps, { u0 = u0, u1 = u1, top = SEA_LEVEL })
			end
		else
			local n = math.ceil((u1 - u0) / SKIRT_LONG - 1e-6)
			for k = 0, n - 1 do
				local a, b = u0 + (u1 - u0) * k / n, u0 + (u1 - u0) * (k + 1) / n
				local low = math.huge
				for _, s in ipairs(run) do
					if s.u >= a - SKIRT_STEP and s.u <= b + SKIRT_STEP then
						low = math.min(low, s.h)
					end
				end
				table.insert(wall.blocks, { u0 = a, u1 = b, top = low - SKIRT_BELOW })
			end
		end
	end
	return wall
end

-- The block of `wall` at its +u end (`atEnd`) or its -u end, if it has one.
local function endBlock(wall: Wall, atEnd: boolean): Stretch?
	for _, b in ipairs(wall.blocks) do
		if (atEnd and b.u1 >= HALF - 1) or (not atEnd and b.u0 <= -HALF + 1) then
			return b
		end
	end
	return nil
end

-- The ground beyond `wall` from uLo to uHi along it, `depth` out: the
-- lowest skirt there (down its bank, if it has one), river beds and the sea
-- included (or the nearest, if none).
local function groundUnder(wall: Wall, uLo: number, uHi: number, depth: number): number
	local low = math.huge
	local nearest, nearestGap = 0, math.huge
	local function consider(top: number, u0: number, u1: number)
		if u1 >= uLo and u0 <= uHi then
			low = math.min(low, top)
		else
			local gap = math.max(u0 - uHi, uLo - u1)
			if gap < nearestGap then
				nearest, nearestGap = top, gap
			end
		end
	end
	for _, b in ipairs(wall.blocks) do
		local up = if b.bank then math.clamp(depth / BANK, 0, 1) else 1
		consider(SKIRT_BOTTOM + (b.top - SKIRT_BOTTOM) * up, b.u0, b.u1)
	end
	for _, r in ipairs(wall.rivers) do
		consider(r.bed or r.top, r.u0, r.u1)
	end
	for _, g in ipairs(wall.gaps) do
		consider(SEA_LEVEL - 10, g.u0, g.u1)
	end
	return if low < math.huge then low else nearest
end

-- The volcano's impostor: rings of { radius, y } from its foot up, under
-- the real cone's lowest flank (which is concave, so two straight tiers
-- hug it) and under its crater's floor.
local CONE = WorldLayout.VolcanoCone
local IMPOSTOR_RINGS = { { 126, 0 }, { 78, 58 }, { 36, 108 } }
local IMPOSTOR_SIDES = 8

-- The volcano's gap in the ring, as seen from BackdropEye: anything whose
-- azimuth comes within `half` of the cone's keeps under `elevation`, so the
-- impostor (or the real cone) stands against the sky.
local EYE = WorldPlan.BackdropEye
local VOLCANO_AZ = math.atan2(CONE.z - EYE.Z, CONE.x - EYE.X)
local VOLCANO_DIST = Vector2.new(CONE.x - EYE.X, CONE.z - EYE.Z).Magnitude
local IMPOSTOR_TOP = IMPOSTOR_RINGS[#IMPOSTOR_RINGS]
local GAP_HALF = math.atan(IMPOSTOR_RINGS[1][1] / VOLCANO_DIST) + math.rad(3)
local GAP_ELEVATION = 0.55 * math.atan((IMPOSTOR_TOP[2] - EYE.Y) / (VOLCANO_DIST - IMPOSTOR_TOP[1]))
WorldPlan.BackdropVolcanoGap = { azimuth = VOLCANO_AZ, half = GAP_HALF, elevation = GAP_ELEVATION }

-- a - b as an angle, -pi..pi.
local function angleFrom(a: number, b: number): number
	return (a - b + math.pi) % (math.pi * 2) - math.pi
end

-- Whether any of these points lies in the volcano's gap, and the nearest
-- of them to the eye (flat).
local function inVolcanoGap(points: { Vector3 }): (boolean, number)
	local lo, hi, nearest = math.huge, -math.huge, math.huge
	for _, p in ipairs(points) do
		local d = angleFrom(math.atan2(p.Z - EYE.Z, p.X - EYE.X), VOLCANO_AZ)
		lo, hi = math.min(lo, d), math.max(hi, d)
		nearest = math.min(nearest, Vector2.new(p.X - EYE.X, p.Z - EYE.Z).Magnitude)
	end
	return lo <= GAP_HALF and hi >= -GAP_HALF and hi - lo < math.pi, nearest
end

-- The highest anything `dist` from the eye may stand in the volcano's gap.
local function gapCeiling(dist: number): number
	return EYE.Y + dist * math.tan(GAP_ELEVATION)
end

-- A gable: two wedges back to back along `frame`'s X (`length` long),
-- `height` tall over `left` (toward the frame's -Z) and `right` (+Z).
local function gable(
	out: { BackdropPiece },
	name: string,
	frame: CFrame,
	height: number,
	left: number,
	right: number,
	length: number,
	color: Color3,
	material: Enum.Material
)
	table.insert(
		out,
		backdropPiece(
			name,
			"Wedge",
			frame * CFrame.new(length / 2, height / 2, -left / 2),
			Vector3.new(length, height, left),
			color,
			material
		)
	)
	table.insert(
		out,
		backdropPiece(
			name,
			"Wedge",
			frame * CFrame.new(length / 2, height / 2, right / 2) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(length, height, right),
			color,
			material
		)
	)
end

-- A mountain: a gable whose end (a triangle `left + right` wide standing
-- at `foot`, its peak at world height `peak`) faces back along `dir` and
-- leans back by `pitch`, its ridge running out along `dir` (flat) and down
-- into the ground. Above `snowLine` a snow cap rides its top.
type Mountain = {
	foot: Vector3, -- its y is the foot's height
	dir: Vector3,
	peak: number,
	left: number,
	right: number,
	pitch: number,
	color: Color3,
	snowLine: number,
}
local function mountainPieces(m: Mountain): { BackdropPiece }
	local out: { BackdropPiece } = {}
	local height = (m.peak - m.foot.Y) / math.cos(m.pitch)
	local length = math.min(2000, 1.15 * height / math.tan(m.pitch))
	local frame = CFrame.fromMatrix(m.foot, m.dir, Vector3.yAxis) * CFrame.Angles(0, 0, -m.pitch)
	gable(out, "BackdropRidge", frame, height, m.left, m.right, length, m.color, Enum.Material.Slate)
	if m.peak > m.snowLine + 60 then
		-- Lifted so its slopes stand CAP_CLEAR off the rock's, measured
		-- square to the steeper (narrower) one; its front CAP_CLEAR ahead.
		local steep = math.min(m.left, m.right)
		local lift = CAP_CLEAR * math.sqrt(height * height + steep * steep) / steep
		local cap = math.clamp((m.peak - m.snowLine) / math.cos(m.pitch), height * 0.18, height * 0.42) + lift
		local capFrame = frame * CFrame.new(-CAP_CLEAR, height + lift - cap, 0)
		gable(
			out,
			"BackdropSnow",
			capFrame,
			cap,
			cap * m.left / height,
			cap * m.right / height,
			length * 0.5 + CAP_CLEAR,
			BACKDROP_COLORS.snow,
			Enum.Material.Snow
		)
	end
	return out
end

-- Every corner of a piece's box, in the world.
local function pieceCorners(p: BackdropPiece): { Vector3 }
	local h = p.size / 2
	local out: { Vector3 } = {}
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				table.insert(out, (p.cframe * CFrame.new(h.X * x, h.Y * y, h.Z * z)).Position)
			end
		end
	end
	return out
end

-- Whether a mountain stands in the volcano's gap, and the nearest of its
-- corners to the eye.
local function mountainInGap(pieces: { BackdropPiece }): (boolean, number)
	local corners: { Vector3 } = {}
	for _, p in ipairs(pieces) do
		for _, c in ipairs(pieceCorners(p)) do
			table.insert(corners, c)
		end
	end
	return inVolcanoGap(corners)
end

-- A mountain's pieces into `out`, lowered (or left out: false) where it
-- would stand in the volcano's gap.
local function placeMountain(out: { BackdropPiece }, m: Mountain): boolean
	local pieces = mountainPieces(m)
	local inGap, nearest = mountainInGap(pieces)
	if inGap then
		local ceiling = gapCeiling(nearest)
		if ceiling < m.foot.Y + 60 then
			return false
		end
		m.peak = math.min(m.peak, ceiling)
		pieces = mountainPieces(m)
	end
	for _, p in ipairs(pieces) do
		table.insert(out, p)
	end
	return true
end

-- A row of mountains along a wall: `depth` beyond it, `width` across, each
-- the next `overlap` of its width along (so neighbours always overlap),
-- leaning `pitch` degrees back, turned up to `yaw` degrees off square, snow
-- above `snow`.
-- Their peaks stand `elevation` degrees over BackdropEye's horizon (so the
-- ring reads evenly from town, the far corners as well as the walls'
-- middles), in massifs: tall and low stretches follow a slow noise along
-- the wall.
type Row = {
	depth: { number },
	overlap: { number },
	width: { number },
	elevation: { number },
	pitch: { number },
	yaw: number,
	colors: { Color3 },
	snow: { number },
}
local NEAR_ROW: Row = {
	depth = { 20, 120 },
	overlap = { 0.75, 0.95 },
	width = { 380, 720 },
	elevation = { 8, 13 },
	pitch = { 28, 44 },
	yaw = 20,
	colors = BACKDROP_COLORS.moss,
	snow = { 360, 440 },
}
local FAR_ROW: Row = {
	depth = { 420, 800 },
	overlap = { 0.5, 0.72 },
	width = { 600, 1000 },
	elevation = { 10.5, 16.5 },
	pitch = { 28, 40 },
	yaw = 16,
	colors = BACKDROP_COLORS.rock,
	snow = { 380, 520 },
}
local PEAK_MAX = 1000 -- however far off

-- A row along `wall`: from u0 to u1 (or out both ways from `anchor`), or,
-- given `fill`, one mountain on the eye's line through each of its points
-- (another row's saddles: so this row's peaks fill the gaps between the
-- row in front, and its own saddles hide behind that row's peaks).
-- Returns its own saddles, and a point past each end.
local function placeRow(
	out: { BackdropPiece },
	wall: Wall,
	row: Row,
	seed: number,
	span: { u0: number, u1: number, anchor: number? }?,
	fill: { Vector3 }?
): { Vector3 }
	local rng = Kit.rng(seed)
	local side = wall.side
	local eye = Vector3.new(EYE.X, 0, EYE.Z)
	-- How far along the wall the eye's line through `p` is, `depth` out.
	local function alongRay(p: Vector3, depth: number): number
		local t = (HALF + depth - eye:Dot(side.out)) / (p:Dot(side.out) - eye:Dot(side.out))
		return (eye + (p - eye) * t):Dot(side.along)
	end
	-- How tall (0..1) the row stands at u: massifs along the wall, a little
	-- jitter on top; the taller, the wider.
	type Station = { u: number, tall: number, width: number, ray: Vector3? }
	local function station(u: number): Station
		local tall = math.clamp(0.5 + math.noise(u / 1100, seed * 1.37, 0.5) * 0.9 + rng:range(-0.25, 0.25), 0, 1)
		return {
			u = u,
			tall = tall,
			width = row.width[1] + (row.width[2] - row.width[1]) * (0.5 * tall + 0.5 * rng:next()),
		}
	end
	local stations: { Station } = {}
	if fill then
		for _, p in ipairs(fill) do
			local st = station(alongRay(p, (row.depth[1] + row.depth[2]) / 2))
			st.ray = p
			table.insert(stations, st)
		end
	elseif span then
		local anchor = span.anchor
		local s = station(if anchor then anchor else span.u0 + rng:range(0, row.width[1] / 2))
		while s.u <= span.u1 do
			table.insert(stations, s)
			s = station(s.u + s.width * rng:range(row.overlap[1], row.overlap[2]))
		end
		if anchor and #stations > 0 then
			s = stations[1]
			s = station(s.u - s.width * rng:range(row.overlap[1], row.overlap[2]))
			while s.u >= span.u0 do
				table.insert(stations, s)
				s = station(s.u - s.width * rng:range(row.overlap[1], row.overlap[2]))
			end
		end
	end
	type Placed = { u: number, width: number, depth: number }
	local placed: { Placed } = {}
	for _, st in ipairs(stations) do
		local tall, width = st.tall, st.width
		local split = rng:range(0.3, 0.7)
		local left, right = width * split, width * (1 - split)
		local yaw = math.rad(rng:range(-row.yaw, row.yaw))
		local dir = Vector3.new(
			side.out.X * math.cos(yaw) - side.out.Z * math.sin(yaw),
			0,
			side.out.X * math.sin(yaw) + side.out.Z * math.cos(yaw)
		)
		-- Deep enough that its near corners stay beyond the wall however
		-- it turns (and its snow cap's front with them).
		local depth = rng:range(row.depth[1], row.depth[2])
			+ math.max(left, right) * math.abs(math.sin(yaw))
			+ CAP_CLEAR
			+ 10
		local pitch = math.rad(rng:range(row.pitch[1], row.pitch[2]))
		local rise = math.tan(math.rad(row.elevation[1] + (row.elevation[2] - row.elevation[1]) * tall))
		local snowLine = rng:range(row.snow[1], row.snow[2])
		local color = Kit.vary(rng:pick(row.colors), rng, 0.03)
		-- The south is the sunny side: less snow.
		if side == SIDE_S then
			snowLine += 120
		end
		-- The mountain standing at `u` along the wall.
		local function at(u: number): Mountain
			local spot = sidePoint(side, u, depth)
			local footY = groundUnder(wall, u - width / 2, u + width / 2, depth) - FOOT_BELOW
			-- The peak sits (peak - footY) * tan(pitch) back from the foot,
			-- so for it to stand `rise` (a slope) over the eye's horizon:
			-- peak = eye + (away + (peak - footY) * back) * rise.
			local back = math.tan(pitch) * math.abs(dir:Dot(side.out))
			local away = Vector2.new(spot.X - EYE.X, spot.Z - EYE.Z).Magnitude
			return {
				foot = Vector3.new(spot.X, footY, spot.Z),
				dir = dir,
				peak = math.min(PEAK_MAX, (EYE.Y + away * rise - footY * back * rise) / (1 - back * rise)),
				left = left,
				right = right,
				pitch = pitch,
				color = color,
				snowLine = snowLine,
			}
		end
		local ray = st.ray
		local u = if ray then alongRay(ray, depth) else st.u
		-- One that would stand in the volcano's gap steps aside, out of it,
		-- if it can (else it is lowered, or left out).
		local m = at(u)
		if mountainInGap(mountainPieces(m)) then
			for k = 1, 12 do
				local moved: number? = nil
				for _, sign in ipairs({ -1, 1 }) do
					if not moved and not mountainInGap(mountainPieces(at(u + sign * 40 * k))) then
						moved = u + sign * 40 * k
					end
				end
				if moved then
					u = moved
					m = at(moved)
					break
				end
			end
		end
		if placeMountain(out, m) then
			table.insert(placed, { u = u, width = width, depth = depth })
		end
	end
	-- The saddles between neighbours (where their flanks meet, roughly),
	-- and a point past each end.
	table.sort(placed, function(a, b)
		return a.u < b.u
	end)
	local saddles: { Vector3 } = {}
	for i, a in ipairs(placed) do
		if i == 1 then
			table.insert(saddles, sidePoint(side, a.u - a.width * 0.45, a.depth))
		end
		local b = placed[i + 1]
		if b then
			local u = a.u + (b.u - a.u) * a.width / (a.width + b.width)
			table.insert(saddles, sidePoint(side, u, (a.depth + b.depth) / 2))
		else
			table.insert(saddles, sidePoint(side, a.u + a.width * 0.45, a.depth))
		end
	end
	return saddles
end

-- An axis-aligned block from (x0, y0, z0) to (x1, y1, z1).
local function slab(
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): BackdropPiece
	return backdropPiece(
		name,
		"Block",
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		color,
		material,
		transparency
	)
end

-- A block beyond a wall, from u0 to u1 along it and d0 to d1 out, from y0
-- up to y1.
local function beyondWall(
	name: string,
	side: Side,
	u0: number,
	u1: number,
	d0: number,
	d1: number,
	y0: number,
	y1: number,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): BackdropPiece
	local a, b = sidePoint(side, u0, d0), sidePoint(side, u1, d1)
	return slab(
		name,
		math.min(a.X, b.X),
		math.max(a.X, b.X),
		y0,
		y1,
		math.min(a.Z, b.Z),
		math.max(a.Z, b.Z),
		color,
		material,
		transparency
	)
end

-- The volcano's impostor: IMPOSTOR_SIDES facets per tier between its
-- rings, each an isosceles trapezoid plate FACET thick behind its face (a
-- block down its middle and a right-angled wedge each side), and a floor
-- a little down inside its crater.
local function impostor(out: { BackdropPiece })
	local center = Vector3.new(CONE.x, 0, CONE.z)
	local function ring(r: { number }, a: number): Vector3
		return Vector3.new(CONE.x + math.cos(a) * r[1], r[2], CONE.z + math.sin(a) * r[1])
	end
	for tier = 1, #IMPOSTOR_RINGS - 1 do
		local lo, hi = IMPOSTOR_RINGS[tier], IMPOSTOR_RINGS[tier + 1]
		for i = 1, IMPOSTOR_SIDES do
			local a0 = (i - 1) / IMPOSTOR_SIDES * math.pi * 2
			local a1 = i / IMPOSTOR_SIDES * math.pi * 2
			local b0, b1, t0, t1 = ring(lo, a0), ring(lo, a1), ring(hi, a0), ring(hi, a1)
			local mb, mt = (b0 + b1) / 2, (t0 + t1) / 2
			local u, v = (b1 - b0).Unit, (mt - mb).Unit
			local slant = (mt - mb).Magnitude
			local top = (t1 - t0).Magnitude
			local flare = ((b1 - b0).Magnitude - top) / 2
			local n = u:Cross(v)
			local outward = Vector3.new(mb.X - center.X, 0, mb.Z - center.Z)
			local inset = (if n:Dot(outward) > 0 then n else -n) * (-FACET / 2)
			local color = if (i + tier) % 2 == 0 then BACKDROP_COLORS.basalt else BACKDROP_COLORS.slate
			table.insert(
				out,
				backdropPiece(
					"VolcanoImpostor",
					"Block",
					CFrame.fromMatrix((mb + mt) / 2 + inset, u, v),
					Vector3.new(top, slant, FACET),
					color,
					Enum.Material.Basalt
				)
			)
			-- The side triangles, right-angled at the block's bottom corners.
			for _, sign in ipairs({ 1, -1 }) do
				local corner = mb + u * (sign * top / 2)
				local middle = corner + v * (slant / 2) + u * (sign * flare / 2)
				local cf = if sign > 0
					then CFrame.fromMatrix(middle + inset, u:Cross(v), v, -u)
					else CFrame.fromMatrix(middle + inset, v:Cross(u), v, u)
				table.insert(
					out,
					backdropPiece(
						"VolcanoImpostor",
						"Wedge",
						cf,
						Vector3.new(FACET, slant, flare),
						color,
						Enum.Material.Basalt
					)
				)
			end
		end
	end
	table.insert(
		out,
		backdropPiece(
			"VolcanoImpostor",
			"Cylinder",
			CFrame.new(CONE.x, IMPOSTOR_TOP[2] - 6, CONE.z) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(2, IMPOSTOR_TOP[1] * 2, IMPOSTOR_TOP[1] * 2),
			BACKDROP_COLORS.basalt,
			Enum.Material.Basalt
		)
	)
end

-- An island far out to sea: two pitched gables back to back, their peaks
-- meeting `peak` high over (x, z), the ridge running along `yaw` degrees.
local function island(out: { BackdropPiece }, x: number, z: number, peak: number, yaw: number, seed: number)
	local rng = Kit.rng(seed)
	local base = SEA_LEVEL - 11
	local pitch = math.rad(rng:range(17, 25))
	local height = (peak - base) / math.cos(pitch)
	local length = 1.15 * height / math.tan(pitch)
	local dir = Vector3.new(math.cos(math.rad(yaw)), 0, math.sin(math.rad(yaw)))
	local left, right = rng:range(130, 220), rng:range(130, 220)
	local color = rng:pick(BACKDROP_COLORS.island)
	for _, way in ipairs({ 1, -1 }) do
		local d = dir * way
		local foot = Vector3.new(x, base, z) - d * (height * math.sin(pitch))
		local frame = CFrame.fromMatrix(foot, d, Vector3.yAxis) * CFrame.Angles(0, 0, -pitch)
		-- Turned round, one gable's left is the other's right.
		local l = if way > 0 then left else right
		local r = if way > 0 then right else left
		gable(out, "BackdropIsland", frame, height, l, r, length, color, Enum.Material.Grass)
	end
end

local cachedBackdrop: { BackdropPiece }? = nil

function WorldPlan.Backdrop(): { BackdropPiece }
	if cachedBackdrop then
		return cachedBackdrop
	end
	local out: { BackdropPiece } = {}
	local reach = BACKDROP_REACH - HALF -- how far the skirt runs out beyond a wall
	-- No skirt east: the sea runs on beyond the coast, and beyond the
	-- mountains north of it (sea cliffs), so the volcano stands against the
	-- sky and the sea from town.
	local walls = { wallSkirt(SIDE_N), wallSkirt(SIDE_W), wallSkirt(SIDE_S) }
	local north, west, south = walls[1], walls[2], walls[3]

	-- The north-west and south-west corners, beyond two walls, take the
	-- lower of the skirts beside them (the eastern two are sea).
	local function lower(a: Stretch?, b: Stretch?): number?
		if a and b then
			return math.min(a.top, b.top)
		end
		return if a then a.top elseif b then b.top else nil
	end
	local nw = lower(endBlock(north, false), endBlock(west, true))
	local sw = lower(endBlock(south, false), endBlock(west, false))
	if nw then
		table.insert(north.blocks, 1, { u0 = -BACKDROP_REACH, u1 = -HALF, top = nw })
	end
	if sw then
		table.insert(south.blocks, 1, { u0 = -BACKDROP_REACH, u1 = -HALF, top = sw })
	end

	-- The skirt (lowered in the volcano's gap). A river leaving the world
	-- runs on into a canyon between its blocks, and a mountain closes it.
	for _, wall in ipairs(walls) do
		for _, b in ipairs(wall.blocks) do
			local inGap, nearest = inVolcanoGap({
				sidePoint(wall.side, b.u0, 0),
				sidePoint(wall.side, b.u1, 0),
				sidePoint(wall.side, b.u0, reach),
				sidePoint(wall.side, b.u1, reach),
			})
			if inGap then
				b.top = math.min(b.top, gapCeiling(nearest))
			end
			-- A bank along the wall, but not where the corners meet or beside
			-- a river (its canyon's walls).
			local corner = b.u1 <= -HALF + 1 or b.u0 >= HALF - 1
			local byRiver = false
			for _, r in ipairs(wall.rivers) do
				byRiver = byRiver or (b.u1 >= r.u0 - 1 and b.u0 <= r.u1 + 1)
			end
			b.bank = not corner and not byRiver
			if b.top > SKIRT_BOTTOM + 1 then
				local side = wall.side
				local from = if b.bank then BANK else 0
				if b.bank then
					-- Kit.wedge's slope runs down to its front (-Z): the wall.
					local up = Vector3.yAxis
					local middle = sidePoint(side, (b.u0 + b.u1) / 2, BANK / 2)
					table.insert(
						out,
						backdropPiece(
							"BackdropBank",
							"Wedge",
							CFrame.fromMatrix(
								Vector3.new(middle.X, (SKIRT_BOTTOM + b.top) / 2, middle.Z),
								up:Cross(side.out),
								up,
								side.out
							),
							Vector3.new(b.u1 - b.u0, b.top - SKIRT_BOTTOM, BANK),
							BACKDROP_COLORS.skirt,
							Enum.Material.Grass
						)
					)
				end
				table.insert(
					out,
					beyondWall(
						"BackdropSkirt",
						side,
						b.u0,
						b.u1,
						from,
						reach,
						SKIRT_BOTTOM,
						b.top,
						BACKDROP_COLORS.skirt,
						Enum.Material.Grass
					)
				)
			end
		end
		for _, r in ipairs(wall.rivers) do
			table.insert(
				out,
				beyondWall(
					"BackdropRiver",
					wall.side,
					r.u0,
					r.u1,
					0,
					400,
					r.top - 1.2,
					r.top - 0.2,
					BACKDROP_COLORS.sea,
					Enum.Material.SmoothPlastic,
					0.3
				)
			)
			table.insert(
				out,
				beyondWall(
					"BackdropRiverbed",
					wall.side,
					r.u0,
					r.u1,
					0,
					reach,
					SKIRT_BOTTOM,
					(r.bed or r.top) - 2,
					BACKDROP_COLORS.riverbed,
					Enum.Material.Slate
				)
			)
		end
	end

	-- The mountains: a near row and a far row on the north, west and south
	-- (the north's end where the sea begins, the south's at the coast).
	-- The west's near row closes the Lake's outflow canyon.
	local outflow = west.rivers[1]
	local riverAt = if outflow then (outflow.u0 + outflow.u1) / 2 else nil
	local function ring(wall: Wall, u0: number, u1: number, seed: number, anchor: number?)
		local saddles = placeRow(out, wall, NEAR_ROW, seed, { u0 = u0, u1 = u1, anchor = anchor })
		placeRow(out, wall, FAR_ROW, seed + 1, nil, saddles)
	end
	ring(north, -2900, 1300, 101)
	ring(west, -1450, 1450, 201, riverAt)
	ring(south, -2900, 1200, 301)

	-- The sea east of the coast (a part is at most 2,048 studs a side), its
	-- bed under it, and on south of the south wall from where the coast
	-- cuts it.
	local seaTop = WorldPlan.BackdropSeaTop
	local function sea(x0: number, x1: number, z0: number, z1: number)
		table.insert(
			out,
			slab(
				"BackdropSea",
				x0,
				x1,
				seaTop - 1,
				seaTop,
				z0,
				z1,
				BACKDROP_COLORS.sea,
				Enum.Material.SmoothPlastic,
				0.3
			)
		)
		table.insert(
			out,
			slab(
				"BackdropSeabed",
				x0,
				x1,
				SEA_LEVEL - 11,
				SEA_LEVEL - 10,
				z0,
				z1,
				BACKDROP_COLORS.seabed,
				Enum.Material.SmoothPlastic
			)
		)
	end
	for k = 0, 2 do
		sea(HALF, BACKDROP_REACH, -BACKDROP_REACH + k * 2000, -BACKDROP_REACH + (k + 1) * 2000)
	end
	local coast = math.huge
	for _, g in ipairs(south.gaps) do
		coast = math.min(coast, g.u0)
	end
	if coast < HALF then
		sea(math.max(coast - 20, -HALF), HALF, -BACKDROP_REACH, -HALF)
	end

	-- Far islands, so the east horizon isn't one flat line.
	for i, spot in ipairs({
		{ 2150, -520, 120, 80 },
		{ 2520, -1480, 92, 20 },
		{ 2760, 300, 140, 100 },
		{ 2380, -2300, 76, 60 },
	}) do
		island(out, spot[1], spot[2], spot[3], spot[4], 500 + i)
	end

	impostor(out)

	-- The Skyroot's footing: a disc of ground just under the terrain there,
	-- so the Skyroot (Persistent) never stands on nothing while the ground
	-- round it isn't streamed in.
	local sky = WorldPlan.Sky()
	if sky then
		local root = sky.root
		local lowest = math.huge
		local r = FOOTING_RADIUS + SKIRT_STEP
		for dx = -r, r, SKIRT_STEP do
			for dz = -r, r, SKIRT_STEP do
				if dx * dx + dz * dz <= r * r then
					lowest = math.min(lowest, TerrainGen.HeightAt(root.X + dx, root.Z + dz))
				end
			end
		end
		local top = lowest - FOOTING_BELOW
		table.insert(
			out,
			backdropPiece(
				"BackdropFooting",
				"Cylinder",
				CFrame.new(root.X, top - 1, root.Z) * CFrame.Angles(0, 0, math.pi / 2),
				Vector3.new(2, FOOTING_RADIUS * 2, FOOTING_RADIUS * 2),
				TerrainGen.MaterialColors.Grass,
				Enum.Material.Grass
			)
		)
	end

	cachedBackdrop = out
	return out
end

---------------------------------------------------------------------------
-- The landscape, a little toward the classic lumber-game look (phase 10, STY-03)
---------------------------------------------------------------------------

-- What everything here keeps clear of, binned by 64-stud squares so a
-- check looks at its neighbours only: every tree on the ground but the
-- forest's (baseTrees: those came after and keep off all this), the
-- boulders, the scenery and the road signs (each a disc: its middle and
-- how far it reaches), and the gondola's two routes seen from above.
type Disc = { x: number, z: number, r: number }
type Clutter = { bins: { [number]: { Disc } }, routes: { { Vector2 } }, biomes: { Disc } }
local CLUTTER_BIN = 64
local NO_DISCS: { Disc } = {}
local function binKey(bx: number, bz: number): number
	return (bx + 1000) * 4096 + (bz + 1000)
end
local cachedClutter: Clutter? = nil
local function clutter(): Clutter
	if cachedClutter then
		return cachedClutter
	end
	local bins: { [number]: { Disc } } = {}
	local function add(x: number, z: number, r: number)
		local disc = { x = x, z = z, r = r }
		-- Into every bin it overlaps, so a lookup only needs its own bin's neighbours.
		for bx = (x - r) // CLUTTER_BIN, (x + r) // CLUTTER_BIN do
			for bz = (z - r) // CLUTTER_BIN, (z + r) // CLUTTER_BIN do
				local key = binKey(bx, bz)
				local bin = bins[key]
				if not bin then
					bin = {}
					bins[key] = bin
				end
				table.insert(bin, disc)
			end
		end
	end
	for _, tree in ipairs(baseTrees()) do -- (not the forest's: they keep off all this)
		add(tree.position.X, tree.position.Z, 0)
	end
	for _, b in ipairs(WorldPlan.Boulders()) do
		add(b.position.X, b.position.Z, b.size / 2)
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		add(spot.center.X, spot.center.Z, spot.radius)
	end
	for _, sign in
		ipairs(WorldPlan.RoadSigns(function(): string
			return ""
		end))
	do
		local p = sign.cframe.Position
		add(p.X, p.Z, SIGN_POST)
	end
	local routes: { { Vector2 } } = {}
	local sky = WorldPlan.Sky()
	if sky then
		local top = sky.gondolaTop.Position
		local town = WorldPlan.TownGondolaSpot
		local base = sky.gondolaBase.Position
		table.insert(routes, { Vector2.new(town.X, town.Z), Vector2.new(top.X, top.Z) })
		table.insert(routes, { Vector2.new(base.X, base.Z), Vector2.new(top.X, top.Z) })
	end
	-- Each biome's own ground (its trees, its Elder): the Gloam Hollow's
	-- ridge and all, and the Skyroot's foot under the isles (its roots, its
	-- waterfall's pool, the gondola's foot station), as the scenery keeps.
	local biomes: { Disc } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		if area then
			local r = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 else area.radius + 20
			table.insert(biomes, { x = area.x, z = area.z, r = r })
		end
	end
	local made: Clutter = { bins = bins, routes = routes, biomes = biomes }
	cachedClutter = made
	return made
end

-- Whether a disc of radius `r` at (x, z) keeps `gap` studs off everything
-- in the clutter (trees, boulders, scenery, signs), `gondola` studs off
-- the gondola's routes, and out of every biome's own ground.
local function clearOfClutter(x: number, z: number, r: number, gap: number, gondola: number): boolean
	local c = clutter()
	for _, d in ipairs(c.biomes) do
		local dx, dz = x - d.x, z - d.z
		if dx * dx + dz * dz < (d.r + r) ^ 2 then
			return false
		end
	end
	for _, route in ipairs(c.routes) do
		if WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) < gondola + r then
			return false
		end
	end
	local reach = r + gap
	for bx = (x - reach) // CLUTTER_BIN, (x + reach) // CLUTTER_BIN do
		for bz = (z - reach) // CLUTTER_BIN, (z + reach) // CLUTTER_BIN do
			for _, d in ipairs(c.bins[binKey(bx, bz)] or NO_DISCS) do
				local dx, dz = x - d.x, z - d.z
				if dx * dx + dz * dz < (d.r + reach) ^ 2 then
					return false
				end
			end
		end
	end
	return true
end

-- Boulder clusters (STY-03): brown rocks scattered over
-- the open grass, three to five half-buried rocks of mixed sizes huddled
-- together, one cluster per CLUSTER_CELL square at most. MapBuilder builds
-- each rock with PropArt.Rock (as the lone boulders: it collides) in a
-- brown palette (LandmarkArt.BrownRock). Every rock stands on the open
-- meadow's grass (so never on a road, the beach, snow, the volcano or the
-- grove), dry lowland no steeper than ClusterSlope (the boulders' rule),
-- sunk ClusterSink(size) (a little deeper than a lone boulder, so the
-- ground under its footprint never drops below the rock's buried edge),
-- out of town, the plots and every biome's own ground, ClusterRoad studs
-- off the roads, ClusterWater off the water, ClusterGap off every tree,
-- boulder, scenery piece and road sign, ClusterGondola off the gondola's
-- routes. They come after everything else and draw their own rng, so
-- nothing that was already placed moves.
export type ClusterRock = { position: Vector3, size: number, seed: number, yaw: number, mossy: boolean }
export type BoulderCluster = { center: Vector3, radius: number, tone: number, rocks: { ClusterRock } }

WorldPlan.ClusterRoad = 4 -- studs between a rock's side and a road's edge
WorldPlan.ClusterWater = 4 -- studs between a rock's side and the water
WorldPlan.ClusterGap = 6 -- studs between a rock's side and a tree, boulder, scenery piece or sign
WorldPlan.ClusterGondola = 30 -- studs off the gondola's routes (seen from above)
WorldPlan.ClusterSlope = 0.6 -- the lone boulders' rule (SlopeAt)
WorldPlan.ClusterLow = 70 -- lowland only
WorldPlan.ClusterEdge = 1150 -- clear of the mountains at the world's edge
WorldPlan.ClusterReach = 0.86 -- a rock of size s reaches this x s from its middle (PropArt.Rock: 0.854 at most)
WorldPlan.ClusterMost = 36 -- clusters in all
WorldPlan.ClusterRocks = 150 -- rocks in all (PropArt.Rock is 5-6 parts)
WorldPlan.ClusterBig = { 6, 9.5 } -- the size (studs across) of each cluster's big rock
WorldPlan.ClusterSmall = { 2.4, 5.6 } -- and of the ones leaning on it
local CLUSTER_CELL = 200
local CLUSTER_NEAR = 700 -- squares this near the sawmill get theirs first
local CLUSTER_APART = 120 -- studs between two clusters' middles
local CLUSTER_GRASS = { Grass = true, LeafyGrass = true }

-- How deep a rock `size` studs across sits in the ground.
function WorldPlan.ClusterSink(size: number): number
	return 0.5 + 0.1 * size
end

-- The ground a rock of `size` at (x, z) stands on: its middle and a ring
-- at half its size (x, z in a Vector2's X, Y).
function WorldPlan.ClusterFootprint(x: number, z: number, size: number): { Vector2 }
	local out = { Vector2.new(x, z) }
	for k = 0, 7 do
		local a = k * math.pi / 4
		table.insert(out, Vector2.new(x + math.cos(a) * size * 0.5, z + math.sin(a) * size * 0.5))
	end
	return out
end

-- How far the ground under a rock may fall below its middle: what its
-- buried edge (its body's highest bottom corner, about a tenth of its size
-- over its base) still covers.
function WorldPlan.ClusterDrop(size: number): number
	return WorldPlan.ClusterSink(size) - 0.1 * size - 0.05
end

local cachedClusters: { BoulderCluster }? = nil

function WorldPlan.BoulderClusters(): { BoulderCluster }
	if cachedClusters then
		return cachedClusters
	end
	local out: { BoulderCluster } = {}
	local rng = Kit.rng(hashString("boulder clusters 3"))
	local coast = WorldLayout.Coast
	local beachX = coast.shoreX - coast.beachWidth - 40
	local edge = WorldPlan.ClusterEdge
	local rocks = 0

	-- Where a rock of `size` could stand at (x, z): its base, or nil.
	local function rockAt(x: number, z: number, size: number, others: { ClusterRock }): Vector3?
		local reach = size * WorldPlan.ClusterReach
		if math.abs(x) > edge or math.abs(z) > edge or x > beachX then
			return nil
		end
		for _, o in ipairs(others) do -- huddled, not stacked
			local dx, dz = x - o.position.X, z - o.position.Z
			if dx * dx + dz * dz < ((size + o.size) * 0.4) ^ 2 then
				return nil
			end
		end
		if not clearOfClutter(x, z, reach, WorldPlan.ClusterGap, WorldPlan.ClusterGondola) then
			return nil
		end
		if TerrainGen.RoadClearance(x, z) < reach + WorldPlan.ClusterRoad then
			return nil
		end
		for k = 0, 7 do -- the water, a little beyond its side
			local a = k * math.pi / 4
			local d = reach + WorldPlan.ClusterWater
			local sx, sz = x + math.cos(a) * d, z + math.sin(a) * d
			if TerrainGen.WaterLevelAt(sx, sz) ~= nil or WorldLayout.FlatWeight(sx, sz) > 0 then
				return nil
			end
		end
		local h, material = TerrainGen.Sample(x, z)
		if not CLUSTER_GRASS[material] or h > WorldPlan.ClusterLow then
			return nil
		end
		if TerrainGen.SlopeAt(x, z) >= WorldPlan.ClusterSlope then
			return nil
		end
		local lowest = h
		for _, p in ipairs(WorldPlan.ClusterFootprint(x, z, size)) do
			lowest = math.min(lowest, TerrainGen.HeightAt(p.X, p.Y))
		end
		if h - lowest > WorldPlan.ClusterDrop(size) then
			return nil
		end
		return Vector3.new(x, h - WorldPlan.ClusterSink(size), z)
	end

	-- A cluster round (x, z): a big rock, then two to four smaller ones
	-- leaning on it. Nil if fewer than three fit.
	local function cluster(x: number, z: number): BoulderCluster?
		local want = math.min(rng:int(3, 5), WorldPlan.ClusterRocks - rocks)
		if want < 3 then
			return nil
		end
		local big = rng:range(WorldPlan.ClusterBig[1], WorldPlan.ClusterBig[2])
		local list: { ClusterRock } = {}
		local first = rockAt(x, z, big, list)
		if not first then
			return nil
		end
		table.insert(list, {
			position = first,
			size = big,
			seed = rng:int(1, 999999),
			yaw = rng:range(0, 6.28),
			mossy = rng:next() < 0.4,
		})
		local start = rng:range(0, math.pi * 2)
		for i = 2, want do
			local size = rng:range(WorldPlan.ClusterSmall[1], WorldPlan.ClusterSmall[2])
			for _ = 1, 4 do
				local a = start + i * 2.3 + rng:range(-0.5, 0.5)
				local d = (big + size) * 0.5 * rng:range(0.85, 1.25)
				local at = rockAt(x + math.cos(a) * d, z + math.sin(a) * d, size, list)
				if at then
					table.insert(list, {
						position = at,
						size = size,
						seed = rng:int(1, 999999),
						yaw = rng:range(0, 6.28),
						mossy = false,
					})
					break
				end
			end
		end
		if #list < 3 then
			return nil
		end
		local radius = 0
		for _, r in ipairs(list) do
			local d = Vector2.new(r.position.X - x, r.position.Z - z).Magnitude
			radius = math.max(radius, d + r.size * WorldPlan.ClusterReach)
		end
		return {
			center = Vector3.new(x, first.Y + WorldPlan.ClusterSink(big), z),
			radius = radius,
			tone = rng:int(1, 2),
			rocks = list,
		}
	end

	-- One per square of open country at most: first the squares within
	-- CLUSTER_NEAR of the sawmill (the country every player crosses: round
	-- the Starter Forest, the Hills' grassland, the meadows by the roads
	-- out), then the rest, each lot in a shuffled order (so the caps don't
	-- leave one side bare).
	local near: { Vector2 } = {}
	local far: { Vector2 } = {}
	local mill = WorldLayout.Sawmill
	for cx = -edge, edge - 1, CLUSTER_CELL do
		for cz = -edge, edge - 1, CLUSTER_CELL do
			local mid = Vector2.new(cx + CLUSTER_CELL / 2 - mill.X, cz + CLUSTER_CELL / 2 - mill.Z)
			table.insert(if mid.Magnitude < CLUSTER_NEAR then near else far, Vector2.new(cx, cz))
		end
	end
	local cells: { Vector2 } = {}
	for _, lot in ipairs({ near, far }) do
		for i = #lot, 2, -1 do
			local j = rng:int(1, i)
			lot[i], lot[j] = lot[j], lot[i]
		end
		table.move(lot, 1, #lot, #cells + 1, cells)
	end
	for _, cell in ipairs(cells) do
		if #out >= WorldPlan.ClusterMost or rocks > WorldPlan.ClusterRocks - 3 then
			break
		end
		for _ = 1, 10 do
			local x = rng:range(cell.X + 20, cell.X + CLUSTER_CELL - 20)
			local z = rng:range(cell.Y + 20, cell.Y + CLUSTER_CELL - 20)
			local apart = true
			for _, o in ipairs(out) do
				if Vector2.new(o.center.X - x, o.center.Z - z).Magnitude < CLUSTER_APART then
					apart = false
					break
				end
			end
			local made = if apart then cluster(x, z) else nil
			if made then
				table.insert(out, made)
				rocks += #made.rocks
				break
			end
		end
	end
	cachedClusters = out
	return out
end

---------------------------------------------------------------------------
-- Landmarks (phase 10, STY-04): a timber footbridge over the river, plank
-- docks on Mirror Lake and on the east coast facing the Island, and a
-- lighthouse on the coast's headland. Each is found by a fixed search
-- (the same on every server), comes after everything else and keeps
-- LandmarkGap studs off it: every tree, boulder, scenery piece, road sign
-- and boulder cluster, the gondola's routes and every biome's own ground,
-- and LandmarkRoad studs off the roads (none of them is anywhere a truck
-- drives). Nil when no spot fits (MapBuilder then builds nothing there).
---------------------------------------------------------------------------

WorldPlan.LandmarkGap = 6
WorldPlan.LandmarkRoad = 30
WorldPlan.BridgeWidth = 7 -- inside the rails
WorldPlan.BridgeRise = 1.6 -- the arch over the line from bank to bank
WorldPlan.BridgeLand = 5 -- studs each end rests on its bank past the water
WorldPlan.BridgeStations = 5 -- post bents from end to end
WorldPlan.BridgeLongest = 46
WorldPlan.BridgeText = "TIMBER BRIDGE"
WorldPlan.DockWidth = 5
WorldPlan.DockStations = 4
WorldPlan.LakeDockText = "MIRROR LAKE"

-- Whether a disc of radius `r` at (x, z) keeps `gap` off every boulder cluster.
local function clearOfClusters(x: number, z: number, r: number, gap: number): boolean
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		local dx, dz = x - c.center.X, z - c.center.Z
		if dx * dx + dz * dz < (c.radius + r + gap) ^ 2 then
			return false
		end
	end
	return true
end

-- Whether a disc of radius `r` at (x, z) is clear for a landmark.
local function landmarkClear(x: number, z: number, r: number): boolean
	return clearOfClutter(x, z, r, WorldPlan.LandmarkGap, WorldPlan.LandmarkGap * 5)
		and clearOfClusters(x, z, r, WorldPlan.LandmarkGap)
		and TerrainGen.RoadClearance(x, z) >= WorldPlan.LandmarkRoad + r
end

-- Whether the terrain at (x, z) is grass, which grows the engine's grass
-- blades (Terrain.Decoration): they would poke up through a deck resting
-- on it (as WorldLayout.TownFloors keeps them out of the shops).
local function grassUnder(x: number, z: number): boolean
	local _, material = TerrainGen.Sample(x, z)
	return material == "Grass" or material == "LeafyGrass"
end

-- The CFrame at (x, y, z) whose -Z points along the flat direction `dir`.
local function facingAlong(x: number, y: number, z: number, dir: Vector2): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Y), 0)
end

-- A signpost (BuildingArt.Signpost: posts at +-SIGN_POST) beside `at`,
-- `off` studs to either side of `along`, its face toward `facing`: on
-- level, dry, clear ground, set down on its lower post. Nil if neither side fits.
local function signBeside(at: Vector2, along: Vector2, off: number, facing: Vector2): CFrame?
	local side = Vector2.new(-along.Y, along.X)
	for _, s in ipairs({ 1, -1 }) do
		local c = at + side * (s * off)
		local a, b = c - side * SIGN_POST, c + side * SIGN_POST
		local ha, hb, hm = TerrainGen.HeightAt(a.X, a.Y), TerrainGen.HeightAt(b.X, b.Y), TerrainGen.HeightAt(c.X, c.Y)
		local level = math.max(ha, hb, hm) - math.min(ha, hb, hm) < 1
			and TerrainGen.WaterLevelAt(a.X, a.Y) == nil
			and TerrainGen.WaterLevelAt(b.X, b.Y) == nil
			and TerrainGen.WaterLevelAt(c.X, c.Y) == nil
		if level and landmarkClear(c.X, c.Y, SIGN_POST + 1) then
			return facingAlong(c.X, math.min(ha, hb), c.Y, facing)
		end
	end
	return nil
end

-- The timber footbridge (STY-04a). No haul road crosses the river, so this
-- is a footbridge for players, across it from bank to bank at the first
-- spot down from its spring under the Skyroot that fits (the Skyroot in
-- view upstream): level, firm banks with no grass under the deck (the
-- engine's grass blades would poke through its planks). `cframe` is end a
-- on its bank, its -Z toward end b; the deck (LandmarkArt.DeckTop) clears
-- the banks and the water all along, and `beds` is the ground or bed
-- under each post station, over end a's ground. `sign` is the TIMBER
-- BRIDGE signpost by its head.
export type Footbridge = {
	cframe: CFrame,
	span: number,
	drop: number,
	width: number,
	rise: number,
	beds: { number },
	sign: CFrame?,
}

local cachedBridge: Footbridge? = nil
local bridgeSearched = false

local function bridgeAcross(p: Vector2, n: Vector2): Footbridge?
	if TerrainGen.WaterLevelAt(p.X, p.Y) == nil then
		return nil
	end
	local function edge(sign: number): number?
		for d = 0, 30, 0.5 do
			local q = p + n * (sign * d)
			if TerrainGen.WaterLevelAt(q.X, q.Y) == nil then
				return d
			end
		end
		return nil
	end
	local e1, e2 = edge(1), edge(-1)
	if not e1 or not e2 then
		return nil
	end
	local land = WorldPlan.BridgeLand
	local a, b = p - n * (e2 + land), p + n * (e1 + land)
	local span = (b - a).Magnitude
	if span > WorldPlan.BridgeLongest then
		return nil
	end
	local ha, hb = TerrainGen.HeightAt(a.X, a.Y), TerrainGen.HeightAt(b.X, b.Y)
	local lake = WorldLayout.LakeLevel
	if math.abs(ha - hb) > 1.2 or ha < lake + 1 or hb < lake + 1 then
		return nil
	end
	if TerrainGen.SlopeAt(a.X, a.Y) > 0.3 or TerrainGen.SlopeAt(b.X, b.Y) > 0.3 then
		return nil
	end
	local axis = (b - a).Unit
	local side = Vector2.new(-axis.Y, axis.X)
	local width, rise, drop = WorldPlan.BridgeWidth, WorldPlan.BridgeRise, hb - ha
	local reach = width / 2 + 1
	-- Its ends rest on the banks (level across), the deck's top clears the
	-- ground there, and out over the river its underside clears the ground
	-- and its top the water, right across.
	for k = 0, 40 do
		local t = k / 40
		local d = span * t
		local top = ha + LandmarkArt.DeckTop(t, drop, rise)
		local onBank = d < land or d > span - land
		for _, off in ipairs({ -reach, 0, reach }) do
			local q = a + axis * d + side * off
			local ground = TerrainGen.HeightAt(q.X, q.Y)
			local wet = TerrainGen.WaterLevelAt(q.X, q.Y)
			if k == 0 or k == 40 then
				if math.abs(ground - (if k == 0 then ha else hb)) > 0.6 then
					return nil -- a bank that falls away across the bridge's end
				end
			elseif ground > top - (if onBank then 0.1 else LandmarkArt.BRIDGE_UNDER) then
				return nil
			end
			if wet and top < wet + 1 then
				return nil
			end
			if not wet and grassUnder(q.X, q.Y) then
				return nil -- the engine's grass would poke up through its planks
			end
		end
	end
	-- Clear of everything, the approaches (8 studs on past each end) too.
	for k = -2, 10 do
		local q = a + axis * (span * k / 8)
		if not landmarkClear(q.X, q.Y, reach) then
			return nil
		end
	end
	for _, q in ipairs({ a - axis * 8, b + axis * 8 }) do
		if TerrainGen.WaterLevelAt(q.X, q.Y) ~= nil or TerrainGen.SlopeAt(q.X, q.Y) > 0.4 then
			return nil
		end
	end
	local beds: { number } = {}
	local stations = WorldPlan.BridgeStations
	for s = 1, stations do
		local q = a + axis * (span * (s - 1) / (stations - 1))
		local lowest = math.huge
		for _, off in ipairs({ -reach, reach }) do
			local o = q + side * off
			lowest = math.min(lowest, TerrainGen.HeightAt(o.X, o.Y))
		end
		table.insert(beds, lowest - ha)
	end
	local sign = signBeside(a - axis * 2, axis, reach + SIGN_POST + 1.5, -axis)
		or signBeside(b + axis * 2, axis, reach + SIGN_POST + 1.5, axis)
	return {
		cframe = facingAlong(a.X, ha, a.Y, axis),
		span = span,
		drop = drop,
		width = width,
		rise = rise,
		beds = beds,
		sign = sign,
	}
end

function WorldPlan.Footbridge(): Footbridge?
	if bridgeSearched then
		return cachedBridge
	end
	local found: Footbridge? = nil
	local pts = WorldLayout.River.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = Vector2.new(-dir.Y, dir.X)
		for s = 0, len, 6 do
			found = bridgeAcross(a + dir * s, n)
			if found then
				break
			end
		end
		if found then
			break
		end
	end
	cachedBridge, bridgeSearched = found, true
	return found
end

-- The plank docks (STY-04b): one on Mirror Lake's east shore pointing out
-- across the lake, one on the east coast pointing out to sea toward the
-- palm Island. `cframe` is the land end on the bank, its -Z out over the
-- water; the deck's top is `deck` over that ground (a step of a stud at
-- most), clears the ground under it and stands `deck - water` over the
-- water's surface (`water`, over the land end's ground, as `beds`). The
-- far end is deep enough for its ladder; `boat` is where the moored
-- rowboat floats (its waterline), alongside the dock's far half.
export type Dock = {
	kind: string, -- "lake" or "coast"
	cframe: CFrame,
	length: number,
	width: number,
	deck: number,
	water: number,
	beds: { number },
	boat: CFrame,
	sign: CFrame?,
}

local cachedDocks: { Dock }? = nil
local DOCK_ON_BANK = 3 -- a dock's first studs rest on its bank (its land end is 2.5 past the water's edge)

-- A dock from `land` out along `out` over water whose surface is at
-- `level`, `length` long, if it fits there.
local function dockAt(kind: string, land: Vector2, out: Vector2, length: number, level: number): Dock?
	if TerrainGen.WaterLevelAt(land.X, land.Y) ~= nil or TerrainGen.SlopeAt(land.X, land.Y) > 0.3 then
		return nil
	end
	local h = TerrainGen.HeightAt(land.X, land.Y)
	local deck = math.max(0.3, level + 1.2 - h)
	if deck > 1.0 then
		return nil -- the bank is too low: a step up onto the deck
	end
	local top = h + deck
	local width = WorldPlan.DockWidth
	local side = Vector2.new(-out.Y, out.X)
	-- Its first studs rest on the bank (the deck's top clears it), then its
	-- planks and stringers clear the ground under the water.
	for k = 0, math.floor(length) do
		for _, off in ipairs({ -width / 2, 0, width / 2 }) do
			local q = land + out * k + side * off
			local ground = TerrainGen.HeightAt(q.X, q.Y)
			if ground > top - (if k <= DOCK_ON_BANK then 0.05 else 0.9) then
				return nil
			end
			if TerrainGen.WaterLevelAt(q.X, q.Y) == nil and grassUnder(q.X, q.Y) then
				return nil -- the engine's grass would poke up through its planks
			end
		end
	end
	local far = land + out * length
	if TerrainGen.WaterLevelAt(far.X, far.Y) == nil or level - TerrainGen.HeightAt(far.X, far.Y) < 2.5 then
		return nil -- the far end must stand in water deep enough for the ladder
	end
	-- The rowboat, alongside its far half on the dock's -X side (its cleat's).
	local boatAt = land + out * (length - 6) - side * (width / 2 + 2)
	for _, q in ipairs({ boatAt, boatAt + out * 3, boatAt - out * 3 }) do
		if TerrainGen.WaterLevelAt(q.X, q.Y) == nil or level - TerrainGen.HeightAt(q.X, q.Y) < 1.2 then
			return nil
		end
	end
	for k = -1, 6 do
		local q = land + out * (length * k / 5)
		if not landmarkClear(q.X, q.Y, width / 2 + 3) then
			return nil
		end
	end
	local behind = land - out * 6
	if TerrainGen.WaterLevelAt(behind.X, behind.Y) ~= nil then
		return nil
	end
	local beds: { number } = {}
	local stations = WorldPlan.DockStations
	for s = 1, stations do
		local q = land + out * (0.6 + (length - 1.2) * (s - 1) / (stations - 1))
		local lowest = math.huge
		for _, off in ipairs({ -width / 2, width / 2 }) do
			local o = q + side * off
			lowest = math.min(lowest, TerrainGen.HeightAt(o.X, o.Y))
		end
		table.insert(beds, lowest - h)
	end
	local sign = if kind == "lake" then signBeside(land - out * 3, out, width / 2 + SIGN_POST + 2, -out) else nil
	-- The boat lies along the dock, bow toward the shore, turned a little.
	local boatDir = Vector2.new(-out.X, -out.Y)
	return {
		kind = kind,
		cframe = facingAlong(land.X, h, land.Y, out),
		length = length,
		width = width,
		deck = deck,
		water = level - h,
		beds = beds,
		boat = facingAlong(boatAt.X, level, boatAt.Y, boatDir) * CFrame.Angles(0, 0.12, 0),
		sign = sign,
	}
end

function WorldPlan.Docks(): { Dock }
	if cachedDocks then
		return cachedDocks
	end
	local docks: { Dock } = {}
	-- Mirror Lake: its east shore, out toward the middle (the river comes in
	-- from the north, the outflow leaves west).
	local lake = WorldLayout.Lake
	local centre = Vector2.new(lake.x, lake.z)
	local found: Dock? = nil
	for k = 0, 24 do
		local turn = math.rad(5) * math.ceil(k / 2) * (if k % 2 == 0 then 1 else -1)
		local away = Vector2.new(math.cos(turn), math.sin(turn))
		for r = lake.radius * 0.7, lake.radius * 1.4, 0.5 do
			local q = centre + away * r
			if TerrainGen.WaterLevelAt(q.X, q.Y) == nil then
				found = dockAt("lake", q + away * 2.5, -away, 20, WorldLayout.LakeLevel)
				break
			end
		end
		if found then
			break
		end
	end
	if found then
		table.insert(docks, found)
	end
	-- The east coast, facing the Island across the water.
	local isle = WorldLayout.Island
	found = nil
	for k = 0, 30 do
		local z = isle.z + 10 * math.ceil(k / 2) * (if k % 2 == 0 then 1 else -1)
		for x = 1080, 1400, 1 do
			if TerrainGen.WaterLevelAt(x, z) ~= nil then
				found = dockAt("coast", Vector2.new(x - 4, z), Vector2.new(1, 0), 26, WorldLayout.SeaLevel)
				break
			end
		end
		if found then
			break
		end
	end
	if found then
		table.insert(docks, found)
	end
	cachedDocks = docks
	return docks
end

-- The lighthouse (STY-04c) on the east coast's headland: where the shore
-- reaches furthest east between z LIGHTHOUSE_Z[1] and [2] (north of the
-- plot district, so from the spawn its line of sight runs over open
-- country) and its lamp is in sight of the spawn (inSightOfSpawn), set
-- back on the sand from the water. `cframe` is its base on the ground (the
-- lowest under its footprint), its door (-Z) toward town; `lamp` is the
-- lamp's middle.
export type Lighthouse = { cframe: CFrame, lamp: Vector3 }
local LIGHTHOUSE_Z = { 120, 460 }
local LIGHTHOUSE_BACK = 26 -- studs inland from the water's edge
WorldPlan.LighthouseSeen = Vector3.new(0, 30, 0) -- the spawn sees the tower from here up, not just its lamp

-- How tall each kind of scenery piece stands, with a stud or two to spare
-- (a fence line only hides a lighthouse's foot; a windmill hides more).
local SCENERY_TALL: { [string]: number } = {
	Outcrop = 13.5,
	LogPile = 5,
	FenceLine = 4.5,
	HayLine = 4,
	RuinedCabin = 9,
	Windmill = 23,
	LookoutTower = 18,
}

-- A player's eye on the spawn pad (MapBuilder's is a stud tall).
local cachedSpawnEye: Vector3? = nil
function WorldPlan.SpawnEye(): Vector3
	local eye = cachedSpawnEye or WorldPlan.Town().spawn + Vector3.new(0, 0.5 + 5.5, 0)
	cachedSpawnEye = eye
	return eye
end

-- Whether the line from a player's eye on the spawn pad to `lamp` clears
-- the land by 2+ studs (when `overLand`) and passes clear of what stands
-- near it: the
-- town's signs, lamps, props, greenery, fences and buildings, the trees,
-- the scenery and the boulder clusters (each a disc this wide and tall).
type Blocker = { at: Vector3, r: number, tall: number }
local cachedTownBlockers: { Blocker }? = nil
-- What stands in town that could hide something from the spawn (worked out once).
local function townBlockers(): { Blocker }
	if cachedTownBlockers then
		return cachedTownBlockers
	end
	local town = WorldPlan.Town()
	local discs: { Blocker } = {
		{ at = town.sawmill.Position, r = 45, tall = 45 },
		{ at = town.gondola.Position, r = 16, tall = 25 },
		{ at = town.campsite.Position, r = 12, tall = 9 },
	}
	for _, spot in ipairs(town.shops) do
		table.insert(discs, { at = spot.cframe.Position, r = 26, tall = 32 })
	end
	for _, sign in ipairs(town.signs) do
		table.insert(discs, { at = sign.cframe.Position, r = SIGN_POST + 3, tall = 11 })
	end
	for _, cf in ipairs(town.lamps) do
		table.insert(discs, { at = cf.Position, r = 3.5, tall = 11 })
	end
	for _, prop in ipairs(town.props) do
		table.insert(discs, { at = prop.cframe.Position, r = 6, tall = 8 })
	end
	for _, fence in ipairs(town.fences) do
		table.insert(discs, { at = fence.cframe.Position, r = fence.length / 2 + 1, tall = 4 })
	end
	for _, g in ipairs(town.greenery) do
		local tree = g.kind == "tree"
		table.insert(
			discs,
			{ at = g.cframe.Position, r = if tree then 10 else g.size / 2 + 2, tall = if tree then 30 else 5 }
		)
	end
	cachedTownBlockers = discs
	return discs
end

local function inSightOfSpawn(lamp: Vector3, overLand: boolean): boolean
	local eye = WorldPlan.SpawnEye()
	local a, b = Vector2.new(eye.X, eye.Z), Vector2.new(lamp.X, lamp.Z)
	local function hides(at: Vector3, r: number, tall: number): boolean
		local d, s = WorldLayout.SegmentDistance(Vector2.new(at.X, at.Z), a, b)
		return d < r and eye.Y + (lamp.Y - eye.Y) * s < at.Y + tall
	end
	for k = 1, if overLand then 199 else 0 do
		local q = eye:Lerp(lamp, k / 200)
		if q.Y - TerrainGen.HeightAt(q.X, q.Z) < 2 then
			return false
		end
	end
	for _, d in ipairs(townBlockers()) do
		if hides(d.at, d.r, d.tall) then
			return false
		end
	end
	for _, tree in ipairs(baseTrees()) do -- (the forest's keep out of its lane)
		if hides(tree.position, 10, 40) then
			return false
		end
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		if hides(spot.center, spot.radius + 4, SCENERY_TALL[spot.kind] or 30) then
			return false
		end
	end
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		if hides(c.center, c.radius + 2, 12) then
			return false
		end
	end
	return true
end
local cachedLighthouse: Lighthouse? = nil
local lighthouseSearched = false

function WorldPlan.Lighthouse(): Lighthouse?
	if lighthouseSearched then
		return cachedLighthouse
	end
	-- The water's edge every 4 studs up the coast, furthest east first.
	type Tip = { x: number, z: number }
	local tips: { Tip } = {}
	for z = LIGHTHOUSE_Z[1], LIGHTHOUSE_Z[2], 4 do
		local coast = WorldLayout.Coast
		for x = coast.shoreX - coast.beachWidth, WorldLayout.WorldHalf + WorldLayout.TerrainSkirt, 1 do
			if TerrainGen.WaterLevelAt(x, z) ~= nil then
				table.insert(tips, { x = x, z = z })
				break
			end
		end
	end
	table.sort(tips, function(p: Tip, q: Tip): boolean
		if p.x ~= q.x then
			return p.x > q.x
		end
		return p.z < q.z
	end)
	local radius = LandmarkArt.LIGHTHOUSE_RADIUS
	local found: Lighthouse? = nil
	local mill = WorldLayout.Sawmill
	for _, tip in ipairs(tips) do
		local x, z = tip.x - LIGHTHOUSE_BACK, tip.z
		local ok = landmarkClear(x, z, radius)
		local lowest = math.huge
		if ok then
			for _, q in ipairs(WorldPlan.SceneryFootprint(x, z, radius)) do
				if TerrainGen.WaterLevelAt(q.X, q.Y) ~= nil then
					ok = false
					break
				end
				lowest = math.min(lowest, TerrainGen.HeightAt(q.X, q.Y))
			end
		end
		if ok and TerrainGen.HeightAt(x, z) - lowest < 1.5 then
			local toTown = Vector2.new(mill.X - x, mill.Z - z).Unit
			local cf = facingAlong(x, lowest - 0.2, z, toTown)
			local lamp = (cf * CFrame.new(0, LandmarkArt.LIGHTHOUSE_LAMP, 0)).Position
			-- The lamp over the land, and the tower's top half beside it.
			if inSightOfSpawn(lamp, true) and inSightOfSpawn(cf.Position + WorldPlan.LighthouseSeen, false) then
				found = { cframe = cf, lamp = lamp }
				break
			end
		end
	end
	cachedLighthouse, lighthouseSearched = found, true
	return found
end

---------------------------------------------------------------------------
-- Trees to chop where the forest is (phase 10, FOR-03)
---------------------------------------------------------------------------
-- More choppable trees where players walk and drive past the forest ring
-- (Connor asked for more trees; their count isn't frozen for this), in
-- three kinds of place, each its own share of ForestMost:
--   * the verges of the haul roads through the ring: about every
--     ForestVergeStep along each, one each side, ForestVerge studs off
--     the road's edge (the filler's wall stands behind them);
--   * the forest's edges, on their open side (ForestCover 0.18 to 0.42
--     with canopy close by), ForestEdgeApart apart: facing the plot
--     district, the lanes, the Hills' and the grove's rooms;
--   * the ring's clearings: a group of three to five round a middle deep
--     in one, Starter Forest spacing.
-- They come after the first 322 and the country stands and draw their own
-- rng, so none of those move. Each is on good ground (dry, lowland, no
-- steeper than 0.6, reachable on foot), WILD_NEAREST from the sawmill
-- (pine and maple STAND_FAR), out of town, the plots, the beach and every
-- biome's own ground, ForestSpacing off every other tree, and clear of
-- the gondola's routes, the boulders, the road signs, the scenery, the
-- boulder clusters, the footbridge, the docks and the lanes (the spawn's
-- view of the lighthouse). Their woods follow the nearest biome, as the
-- country stands' do. Like every tree they are built by the server
-- (TreeService, through MapBuilder's "5. The trees").

-- Phase 12: the ring's trees stand about 1.5x further apart than before
-- (spacing 14 to 21, edge 30 to 45). The verge step is 40 rather than 45
-- so the wider forest still has at least 775 trees. The caps rose with it.
WorldPlan.ForestVergeStep = 40
WorldPlan.ForestVerge = { 11, 16 } -- studs off a road's edge (the trunk's middle)
WorldPlan.ForestEdgeApart = 45
WorldPlan.ForestSpacing = 21
WorldPlan.ForestMost = { verge = 110, edge = 150, clearing = 90 } -- 350 at most
local FOREST_ROADS = { "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }
local FOREST_CLEAR = 10 -- studs a forest tree keeps off a scenery piece, cluster or landmark

local cachedForestTrees: { TreeSpot }? = nil

-- Discs a new trunk stays out of: the footbridge (and its sign's rocks),
-- the docks and their signs. Same reach the forest ring already uses, so
-- those trees do not move.
local cachedLandmarkDiscs: { { number } }? = nil
local function landmarkDiscs(): { { number } }
	if cachedLandmarkDiscs then
		return cachedLandmarkDiscs
	end
	local discs: { { number } } = {}
	local bridge = WorldPlan.Footbridge()
	if bridge then
		local a, along = bridge.cframe.Position, bridge.cframe.LookVector
		for s = -10, bridge.span + 10, 4 do
			local p = a + along * s
			table.insert(discs, { p.X, p.Z, bridge.width / 2 + FOREST_CLEAR })
		end
		local sign = bridge.sign
		if sign then
			table.insert(discs, { sign.X, sign.Z, SIGN_POST + FOREST_CLEAR })
		end
	end
	for _, dock in ipairs(WorldPlan.Docks()) do
		local a, along = dock.cframe.Position, dock.cframe.LookVector
		for s = -8, dock.length + 4, 4 do
			local p = a + along * s
			table.insert(discs, { p.X, p.Z, dock.width / 2 + FOREST_CLEAR })
		end
		local sign = dock.sign
		if sign then
			table.insert(discs, { sign.X, sign.Z, SIGN_POST + FOREST_CLEAR })
		end
	end
	cachedLandmarkDiscs = discs
	return discs
end

function WorldPlan.LandmarkDiscs(): { { number } }
	return landmarkDiscs()
end

function WorldPlan.ForestTrees(): { TreeSpot }
	if cachedForestTrees then
		return cachedForestTrees
	end
	local out: { TreeSpot } = {}
	local rng = Kit.rng(hashString("forest trees"))
	local mill = Vector2.new(WorldLayout.Sawmill.X, WorldLayout.Sawmill.Z)
	local coast = WorldLayout.Coast
	local beachX = coast.shoreX - coast.beachWidth - 40

	-- What they keep clear of, as discs (x, z, reach).
	local discs: { { number } } = {}
	for _, b in ipairs(WorldPlan.Boulders()) do
		table.insert(discs, { b.position.X, b.position.Z, b.size / 2 + STAND_ROCK })
	end
	for _, sign in
		ipairs(WorldPlan.RoadSigns(function(): string
			return ""
		end))
	do
		local p = sign.cframe.Position
		table.insert(discs, { p.X, p.Z, STAND_SIGN })
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		table.insert(discs, { spot.center.X, spot.center.Z, spot.radius + FOREST_CLEAR })
	end
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		table.insert(discs, { c.center.X, c.center.Z, c.radius + FOREST_CLEAR })
	end
	for _, d in ipairs(landmarkDiscs()) do
		table.insert(discs, d)
	end
	local biomes: { { number } } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		if area then
			local r = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 else area.radius + 30
			table.insert(biomes, { area.x, area.z, r })
		end
	end
	local routes: { { Vector2 } } = {}
	local sky = WorldPlan.Sky()
	if sky then
		local top = sky.gondolaTop.Position
		local town = WorldPlan.TownGondolaSpot
		local base = sky.gondolaBase.Position
		table.insert(routes, { Vector2.new(town.X, town.Z), Vector2.new(top.X, top.Z) })
		table.insert(routes, { Vector2.new(base.X, base.Z), Vector2.new(top.X, top.Z) })
	end

	-- Every tree so far, binned by 32-stud squares for the spacing checks.
	local bins: { [number]: { Vector3 } } = {}
	local function addTree(p: Vector3)
		local key = binKey(p.X // 32, p.Z // 32)
		local bin = bins[key]
		if not bin then
			bin = {}
			bins[key] = bin
		end
		table.insert(bin, p)
	end
	local function crowded(x: number, z: number, d: number): boolean
		local reach = math.ceil(d / 32)
		for bx = x // 32 - reach, x // 32 + reach do
			for bz = z // 32 - reach, z // 32 + reach do
				for _, p in ipairs(bins[binKey(bx, bz)] or {}) do
					local dx, dz = x - p.X, z - p.Z
					if dx * dx + dz * dz < d * d then
						return true
					end
				end
			end
		end
		return false
	end
	for _, spot in ipairs(baseTrees()) do
		addTree(spot.position)
	end

	-- Whether a forest tree could grow at (x, z), `setBack` off the roads.
	local function ground(x: number, z: number, setBack: number): boolean
		if math.abs(x) > STAND_EDGE or math.abs(z) > STAND_EDGE or (z < coast.northZ and x > beachX) then
			return false
		end
		local p = Vector2.new(x, z)
		if (p - mill).Magnitude <= WILD_NEAREST or WorldLayout.FlatWeight(x, z) > 0 then
			return false
		end
		for _, d in ipairs(biomes) do
			local dx, dz = x - d[1], z - d[2]
			if dx * dx + dz * dz < d[3] * d[3] then
				return false
			end
		end
		for _, d in ipairs(discs) do
			local dx, dz = x - d[1], z - d[2]
			if dx * dx + dz * dz < d[3] * d[3] then
				return false
			end
		end
		for _, route in ipairs(routes) do
			if WorldLayout.SegmentDistance(p, route[1], route[2]) < STAND_GONDOLA then
				return false
			end
		end
		for _, lane in ipairs(WorldLayout.Forest.lanes) do
			if WorldLayout.SegmentDistance(p, lane.a, lane.b) < lane.half + 10 then
				return false
			end
		end
		return TerrainGen.HeightAt(x, z) < STAND_LOW and goodGround(x, z, setBack, 0.6)
	end

	local function plant(x: number, z: number, spacing: number): boolean
		local flat = Vector3.new(x, 0, z) -- rounded as a Vector3 stores it: what's checked is what's spawned
		x, z = flat.X, flat.Z
		if crowded(x, z, spacing) then
			return false
		end
		local c = Vector2.new(x, z)
		local woods = wildWoodsNear(c)
		if (c - mill).Magnitude < STAND_FAR then
			woods = { "oak", "oak", "birch" }
		end
		local p = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
		table.insert(out, {
			woodId = rng:pick(woods),
			position = p,
			biome = "wild",
			zone = { id = "forest:" .. tostring(#out + 1), cx = x, cz = z, radius = 40 },
		})
		addTree(p)
		return true
	end
	local most = WorldPlan.ForestMost

	-- 1. The verges of the haul roads where they run through the ring.
	local verge = 0
	for _, name in ipairs(FOREST_ROADS) do
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				local pts = road.points
				local walked, nextAt = 0, rng:range(0, WorldPlan.ForestVergeStep)
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = (b - a).Magnitude
					local dir = (b - a).Unit
					local normal = Vector2.new(-dir.Y, dir.X)
					while nextAt <= walked + len do
						local along = a + dir * (nextAt - walked)
						for _, s in ipairs({ 1, -1 }) do
							-- The same draws each side, planted or not.
							local off = road.width / 2 + rng:range(WorldPlan.ForestVerge[1], WorldPlan.ForestVerge[2])
							local at = along + dir * rng:range(-8, 8) + normal * (s * off)
							if verge < most.verge then
								local _, ring = WorldLayout.ForestCover(at.X, at.Y)
								if
									ring > 0.5
									and TerrainGen.RoadClearance(at.X, at.Y) >= WorldPlan.ForestVerge[1] - 0.5
									and ground(at.X, at.Y, WorldPlan.ForestVerge[1] - 1)
									and plant(at.X, at.Y, WorldPlan.ForestSpacing)
								then
									verge += 1
								end
							end
						end
						nextAt += WorldPlan.ForestVergeStep
					end
					walked += len
				end
			end
		end
	end

	-- Candidates on a grid over the ring, in a shuffled order (so the caps
	-- don't leave one side bare): forest edges and clearings' middles.
	local edges: { Vector2 } = {}
	local middles: { Vector2 } = {}
	local steps = (STAND_EDGE * 2) // 12
	for ix = 0, steps do
		for iz = 0, steps do
			local x, z = -STAND_EDGE + ix * 12, -STAND_EDGE + iz * 12
			local c, ring = WorldLayout.ForestCover(x, z)
			if c > 0.18 and c < 0.42 then
				local near = 0
				for _, o in ipairs({ { 18, 0 }, { -18, 0 }, { 0, 18 }, { 0, -18 } }) do
					near = math.max(near, (WorldLayout.ForestCover(x + o[1], z + o[2])))
				end
				if near > 0.65 then
					table.insert(edges, Vector2.new(x, z))
				end
			elseif ring > 0.6 and c < 0.08 and ix % 3 == 0 and iz % 3 == 0 then
				table.insert(middles, Vector2.new(x, z))
			end
		end
	end
	for _, list in ipairs({ edges, middles }) do
		for i = #list, 2, -1 do
			local j = rng:int(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	-- 2. The forest's edges, on their open side.
	local edge = 0
	local edgeAt: { Vector2 } = {}
	for _, p in ipairs(edges) do
		if edge >= most.edge then
			break
		end
		local x, z = p.X + rng:range(-4, 4), p.Y + rng:range(-4, 4)
		local apart = true
		for _, q in ipairs(edgeAt) do
			if (q - Vector2.new(x, z)).Magnitude < WorldPlan.ForestEdgeApart then
				apart = false
				break
			end
		end
		if apart and ground(x, z, STAND_SET_BACK) and plant(x, z, WorldPlan.ForestSpacing) then
			table.insert(edgeAt, Vector2.new(x, z))
			edge += 1
		end
	end

	-- 3. A group of three to five deep in a clearing, 150 studs apart at least.
	local clearing = 0
	local groupAt: { Vector2 } = {}
	for _, m in ipairs(middles) do
		if clearing > most.clearing - 3 then
			break
		end
		local apart = true
		for _, q in ipairs(groupAt) do
			if (q - m).Magnitude < 150 then
				apart = false
				break
			end
		end
		if apart and ground(m.X, m.Y, STAND_SET_BACK) then
			local want = math.min(rng:int(3, 5), most.clearing - clearing)
			local planted = 0
			for _ = 1, want * 12 do
				if planted >= want then
					break
				end
				local a, r = rng:range(0, math.pi * 2), math.sqrt(rng:next()) * 22
				local x, z = m.X + math.cos(a) * r, m.Y + math.sin(a) * r
				if ground(x, z, STAND_SET_BACK) and plant(x, z, STAND_SPACING) then
					planted += 1
				end
			end
			if planted > 0 then
				table.insert(groupAt, m)
				clearing += planted
			end
		end
	end

	cachedForestTrees = out
	return out
end

---------------------------------------------------------------------------
-- The forest's filler (phase 10, FOR-02)
---------------------------------------------------------------------------
-- The trees that make WorldLayout.Forest's ring a forest are built by each
-- client round its own camera (StarterPlayerScripts/ForestFiller), never
-- by the server: thousands of them would cost every player replication
-- and the server its part budget. They're looks only (PropArt.FillerTree:
-- no collisions, clicks or touches; a collider only one client has fights
-- the trucks, which the driver's client simulates), so where they stand
-- is planned here, the same on every client: the map is cut into
-- FillerCellSize-stud cells; each cell's trees come from its own rng.
--   * A jittered 3 x 3 grid of candidates per cell (about 10.7 studs
--     apart), each drawing the same rng numbers whether it grows or not.
--     A candidate grows by its spot's density: in the ring's canopy
--     (ForestCover over 0.5) FillerDensity.core (one tree per ~200 sq
--     studs), at the forest's edges (cover under FillerEdge) and along the
--     roads (within FillerWall of a road's edge) FillerDensity.edge (rows
--     8 to 12 apart: the view from the hub and the roads closes there), in
--     the wild band's copses FillerDensity.copse, on the hub's lawn
--     (outside the town's and the plots' flat ground) a lone ornamental
--     tree now and then (FillerDensity.ornament: conifers, birches,
--     maples, never an oak-like one, so Murph's "find an oak" still means
--     a tree you can chop). Round the Volcano they grow at half density.
--   * Every filler trunk keeps FillerRoad off a road's edge (the corridor),
--     FillerTreeGap off every choppable tree (WorldPlan.Trees), FillerGap
--     off every boulder, boulder cluster, scenery piece and road sign,
--     FillerGondola off the gondola's routes (seen from above), out of the
--     town's and the plots' flat ground, off the water (ForestCover keeps
--     its margin) and out of the mountains (lowland only).
--   * The woods round about choose the kind (FillerMix): broadleaf and
--     birch in the Starter Forest's ring, pine and maple round the Hills,
--     pines (snowy near the plateau) toward the Snowfields, darker pines
--     round the Phantom Grove, dead trees round the Volcano.
--   * Far off (past QualityBudgets' FillerNear) a cell of forest is one or
--     two dark canopy blocks instead (FillerFarCell), so the forest reads
--     from a distance; FillerPlanAround says which cells are which round
--     a camera.
-- tests/Forest.spec.luau proves the gaps and the budgets.

WorldPlan.FillerCellSize = 32
WorldPlan.FillerRoad = 14 -- studs a filler trunk keeps off a road's edge
WorldPlan.FillerWall = 26 -- within this of a road's edge, the forest grows its edge rows
WorldPlan.FillerEdge = 0.82 -- ForestCover under this (and over 0.5) is a forest edge
WorldPlan.FillerTreeGap = 9 -- studs off a choppable tree
WorldPlan.FillerGap = 6 -- studs off a boulder, cluster rock, scenery piece or road sign
WorldPlan.FillerGondola = 12 -- studs off the gondola's routes
WorldPlan.FillerHysteresis = 48 -- studs a loaded cell keeps its look past its radius
-- Thinner than phase 10 (0.55 / 0.85 / 0.4): the same draws, fewer trees.
WorldPlan.FillerDensity = { core = 0.4, edge = 0.6, copse = 0.28, ornament = 0.03 }
local FILLER_CELL = WorldPlan.FillerCellSize
local FILLER_GRID = 3
local FILLER_JITTER = 3.6
local FILLER_LOW = 70 -- lowland only (the mountains rise above it)

-- What grows round each place: kind = share, and how far from the place's
-- middle it reaches (first match wins; anything else is `default`).
type Mix = { { kind: string, share: number } }
local FILLER_MIX: { { biome: string?, reach: number, mix: Mix } } = {
	{
		biome = "volcano",
		reach = 560,
		mix = { { kind = "dead", share = 0.55 }, { kind = "conifer", share = 0.3 }, { kind = "broad", share = 0.15 } },
	},
	{
		biome = "snow",
		reach = 560,
		mix = {
			{ kind = "snowpine", share = 0.45 },
			{ kind = "conifer", share = 0.4 },
			{ kind = "birch", share = 0.15 },
		},
	},
	{
		biome = "snow",
		reach = 800,
		mix = { { kind = "conifer", share = 0.6 }, { kind = "birch", share = 0.2 }, { kind = "broad", share = 0.2 } },
	},
	{
		biome = "hills",
		reach = 470,
		mix = {
			{ kind = "conifer", share = 0.45 },
			{ kind = "maple", share = 0.25 },
			{ kind = "broad", share = 0.2 },
			{ kind = "birch", share = 0.1 },
		},
	},
	{
		biome = "grove",
		reach = 430,
		mix = { { kind = "conifer", share = 0.5 }, { kind = "broad", share = 0.35 }, { kind = "birch", share = 0.15 } },
	},
	{
		biome = "sky",
		reach = 450,
		mix = { { kind = "broad", share = 0.5 }, { kind = "birch", share = 0.3 }, { kind = "conifer", share = 0.2 } },
	},
	{
		biome = nil, -- the default: the Starter Forest's ring and the south
		reach = math.huge,
		mix = { { kind = "broad", share = 0.55 }, { kind = "birch", share = 0.25 }, { kind = "conifer", share = 0.2 } },
	},
}
local ORNAMENT_MIX: Mix =
	{ { kind = "conifer", share = 0.5 }, { kind = "birch", share = 0.3 }, { kind = "maple", share = 0.2 } }
local VOLCANO_SPARSE = 0.5 -- density there

-- The mix at (x, z): the first place whose reach (dithered a little, so
-- the change isn't a hard line) covers it.
local MIX_PLACES: { { x: number, z: number, reach: number, mix: Mix, id: string? } } = {}
for _, entry in ipairs(FILLER_MIX) do
	local def = if entry.biome then BiomeData.Get(entry.biome) else nil
	local area = if def then def.area else nil
	if area then
		table.insert(MIX_PLACES, { x = area.x, z = area.z, reach = entry.reach, mix = entry.mix, id = entry.biome })
	elseif entry.biome == nil then
		table.insert(MIX_PLACES, { x = 0, z = 0, reach = math.huge, mix = entry.mix, id = nil })
	end
end
local function mixAt(x: number, z: number): (Mix, string?)
	local wobble = math.noise(x / 60, z / 60, 12.9) * 60
	for _, place in ipairs(MIX_PLACES) do
		local dx, dz = x - place.x, z - place.z
		local reach = place.reach + wobble
		if dx * dx + dz * dz < reach * reach then
			return place.mix, place.id
		end
	end
	return FILLER_MIX[#FILLER_MIX].mix, nil
end
local function pickKind(mix: Mix, roll: number): string
	for _, entry in ipairs(mix) do
		roll -= entry.share
		if roll < 0 then
			return entry.kind
		end
	end
	return mix[#mix].kind
end

-- What every filler trunk keeps clear of (each a disc already widened by
-- its gap), binned by FILLER_CELL squares, and the gondola's routes.
type FillerClutter = { bins: { [number]: { Disc } }, routes: { { Vector2 } } }
local cachedFillerClutter: FillerClutter? = nil
local function fillerClutter(): FillerClutter
	if cachedFillerClutter then
		return cachedFillerClutter
	end
	local bins: { [number]: { Disc } } = {}
	local function add(x: number, z: number, r: number)
		local disc = { x = x, z = z, r = r }
		for bx = (x - r) // FILLER_CELL, (x + r) // FILLER_CELL do
			for bz = (z - r) // FILLER_CELL, (z + r) // FILLER_CELL do
				local key = binKey(bx, bz)
				local bin = bins[key]
				if not bin then
					bin = {}
					bins[key] = bin
				end
				table.insert(bin, disc)
			end
		end
	end
	for _, tree in ipairs(WorldPlan.Trees()) do
		add(tree.position.X, tree.position.Z, WorldPlan.FillerTreeGap)
	end
	for _, tree in ipairs(WorldPlan.ReachTrees()) do
		add(tree.position.X, tree.position.Z, WorldPlan.FillerTreeGap)
	end
	local gap = WorldPlan.FillerGap
	for _, b in ipairs(WorldPlan.Boulders()) do
		add(b.position.X, b.position.Z, b.size / 2 + gap)
	end
	for _, b in ipairs(WorldPlan.MeadowBoulders()) do
		add(b.position.X, b.position.Z, b.size / 2 + gap)
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		add(spot.center.X, spot.center.Z, spot.radius + gap)
	end
	for _, sign in
		ipairs(WorldPlan.RoadSigns(function(): string
			return ""
		end))
	do
		local p = sign.cframe.Position
		add(p.X, p.Z, SIGN_POST + gap)
	end
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		add(c.center.X, c.center.Z, c.radius + gap)
	end
	local routes: { { Vector2 } } = {}
	local sky = WorldPlan.Sky()
	if sky then
		local top = sky.gondolaTop.Position
		local town = WorldPlan.TownGondolaSpot
		local base = sky.gondolaBase.Position
		table.insert(routes, { Vector2.new(town.X, town.Z), Vector2.new(top.X, top.Z) })
		table.insert(routes, { Vector2.new(base.X, base.Z), Vector2.new(top.X, top.Z) })
	end
	local made: FillerClutter = { bins = bins, routes = routes }
	cachedFillerClutter = made
	return made
end

-- Whether the filler's plan is worked out (ForestFiller does it in steps
-- at start, so no one frame pays for all of it; AmbientLife waits for it).
function WorldPlan.FillerReady(): boolean
	return cachedFillerClutter ~= nil
end

-- The steps ForestFiller works the plan out in, one a frame: each is
-- cached, so the last (the filler's own index) finds the rest done.
WorldPlan.FillerSteps = {
	WorldPlan.Boulders,
	WorldPlan.Scenery,
	WorldPlan.CountryStands,
	WorldPlan.BoulderClusters,
	WorldPlan.Footbridge,
	WorldPlan.Docks,
	WorldPlan.ForestTrees,
	WorldPlan.Trees,
	function(): any
		return fillerClutter()
	end,
} :: { () -> any }

-- Whether a disc of radius `r` at (x, z) keeps clear of the filler's clutter.
local function fillerClear(x: number, z: number, r: number): boolean
	local c = fillerClutter()
	for bx = (x - r) // FILLER_CELL, (x + r) // FILLER_CELL do
		for bz = (z - r) // FILLER_CELL, (z + r) // FILLER_CELL do
			for _, d in ipairs(c.bins[binKey(bx, bz)] or NO_DISCS) do
				local dx, dz = x - d.x, z - d.z
				if dx * dx + dz * dz < (d.r + r) ^ 2 then
					return false
				end
			end
		end
	end
	local p = Vector2.new(x, z)
	for _, route in ipairs(c.routes) do
		if WorldLayout.SegmentDistance(p, route[1], route[2]) < WorldPlan.FillerGondola + r then
			return false
		end
	end
	return true
end

-- How likely a filler tree is at (x, z), and the mix it picks from: 0 where
-- nothing grows. `roadClearance` is TerrainGen.RoadClearance there. The
-- third value is whether a species stand may replace the mix (forest and
-- copses; the hub's lone ornament trees keep their own mix).
local function fillerDensity(x: number, z: number, roadClearance: number): (number, Mix, boolean)
	-- Bayou and Red Mesa stay empty until Lane R fills them.
	if WorldLayout.InReservedRegion(x, z) then
		return 0, ORNAMENT_MIX, false
	end
	local density = WorldPlan.FillerDensity
	local c, ring = WorldLayout.ForestCover(x, z)
	if c > 0.5 then
		local p
		if ring > 0.5 then
			p = if c < WorldPlan.FillerEdge or roadClearance < WorldPlan.FillerWall then density.edge else density.core
		else
			p = density.copse
		end
		local mix, id = mixAt(x, z)
		if id == "volcano" then
			p *= VOLCANO_SPARSE
		end
		return p, mix, true
	end
	local beach = WorldLayout.Coast.shoreX - WorldLayout.Forest.coast
	if ring == 0 and WorldLayout.HubDistance(x, z) <= 0 and roadClearance > 20 and x < beach then
		-- The hub's lawn: a lone ornamental tree, never in a lane.
		for _, lane in ipairs(WorldLayout.Forest.lanes) do
			if WorldLayout.SegmentDistance(Vector2.new(x, z), lane.a, lane.b) < lane.half + 10 then
				return 0, ORNAMENT_MIX, false
			end
		end
		return density.ornament, ORNAMENT_MIX, false
	end
	return 0, ORNAMENT_MIX, false
end

-- A filler tree: `kind` (PropArt.FillerKinds) in look `variant`
-- (1..PropArt's FillerVariants), its trunk's foot at (x, y, z) on the
-- ground, turned `yaw`, at `scale`.
export type FillerTree = { kind: string, variant: number, x: number, y: number, z: number, yaw: number, scale: number }
local FILLER_VARIANTS = 6 -- PropArt.FillerVariants (Shared code can't require Art's builders here)

local function cellSeed(cx: number, cz: number): number
	return (cx + 1000) * 7919 + (cz + 1000) * 104729 + 17
end

local cachedFillerCells: { [number]: { FillerTree } } = {}

-- The filler trees in cell (cx, cz) (its corner at (cx, cz) * FillerCellSize).
function WorldPlan.FillerCellTrees(cx: number, cz: number): { FillerTree }
	local key = binKey(cx, cz)
	local done = cachedFillerCells[key]
	if done then
		return done
	end
	local out: { FillerTree } = {}
	local rng = Kit.rng(cellSeed(cx, cz))
	local step = FILLER_CELL / FILLER_GRID
	for i = 0, FILLER_GRID - 1 do
		for k = 0, FILLER_GRID - 1 do
			-- The same seven draws for every candidate, grown or not.
			local jx, jz = rng:range(-FILLER_JITTER, FILLER_JITTER), rng:range(-FILLER_JITTER, FILLER_JITTER)
			local roll, kindRoll = rng:next(), rng:next()
			local variant = rng:int(1, FILLER_VARIANTS)
			local yaw, scaleRoll = rng:range(0, math.pi * 2), rng:next()
			local x = cx * FILLER_CELL + (i + 0.5) * step + jx
			local z = cz * FILLER_CELL + (k + 0.5) * step + jz
			if WorldLayout.FlatWeight(x, z) <= 0 then
				local roads = TerrainGen.RoadClearance(x, z)
				if roads >= WorldPlan.FillerRoad then
					local p, mix, stands = fillerDensity(x, z, roads)
					if roll < p and fillerClear(x, z, 0) then
						local h = TerrainGen.HeightAt(x, z)
						if h < FILLER_LOW then -- (dry: ForestCover keeps its margin off the water)
							local kind = pickKind(mix, kindRoll)
							if stands then
								-- One species per stand, neighbor kinds only in the border band.
								kind = RegionLogic.StandKind(x, z) or kind
							end
							table.insert(out, {
								kind = kind,
								variant = variant,
								x = x,
								y = h,
								z = z,
								yaw = yaw,
								scale = 0.85 + scaleRoll * 0.35,
							})
						end
					end
				end
			end
		end
	end
	cachedFillerCells[key] = out
	return out
end

-- A far stand-in: a dark block standing for a cell's canopy.
export type FarBlock = { cframe: CFrame, size: Vector3, kind: string }
local cachedFarCells: { [number]: { FarBlock } } = {}
local FAR_TOP: { [string]: number } = { -- canopy tops (studs over the ground), as PropArt's trees
	broad = 17,
	birch = 18,
	maple = 17,
	conifer = 19,
	snowpine = 19,
	dead = 12,
}

-- The stand-ins for cell (cx, cz): none unless two of five spots in it are forest; one
-- block over most of the cell (kept clear of the roads and the clutter, as
-- the trees are) and, deep in the forest, a second, smaller block on top
-- for a bumpy skyline. Coloured by the kind of tree there
-- (PropArt.FillerFarColor).
function WorldPlan.FillerFarCell(cx: number, cz: number): { FarBlock }
	local key = binKey(cx, cz)
	local done = cachedFarCells[key]
	if done then
		return done
	end
	local out: { FarBlock } = {}
	local x0, z0 = cx * FILLER_CELL, cz * FILLER_CELL
	local forest, sx, sz = 0, 0, 0
	for _, o in ipairs({ { 0, 0 }, { -9, -9 }, { 9, -9 }, { -9, 9 }, { 9, 9 } }) do
		local x, z = x0 + FILLER_CELL / 2 + o[1], z0 + FILLER_CELL / 2 + o[2]
		local c = WorldLayout.ForestCover(x, z)
		if c > 0.5 then
			forest += 1
			sx += x
			sz += z
		end
	end
	-- Over the forest's part of the cell.
	local mx, mz = if forest > 0 then sx / forest else 0, if forest > 0 then sz / forest else 0
	if forest >= 2 and WorldLayout.FlatWeight(mx, mz) <= 0 then
		local rng = Kit.rng(cellSeed(cx, cz) + 55)
		local yaw, kindRoll, bump, bx, bz = rng:range(0, math.pi / 2), rng:next(), rng:next(), rng:next(), rng:next()
		local h = TerrainGen.HeightAt(mx, mz)
		local roads = TerrainGen.RoadClearance(mx, mz)
		-- (A turned square reaches 1.42 x its half out: never into a road's corridor.)
		local half = math.min(9 + forest, (roads - 4) / 1.42)
		while half >= 7 and not fillerClear(mx, mz, half * 1.42) do
			half -= 3
		end
		if half >= 7 and h < FILLER_LOW then
			local mix = mixAt(mx, mz)
			-- The same stands as the trees, so a far canopy matches the grove under it.
			local kind = RegionLogic.StandKind(mx, mz) or pickKind(mix, kindRoll)
			local top = FAR_TOP[kind] or 17
			local turn = CFrame.Angles(0, yaw, 0)
			table.insert(out, {
				cframe = CFrame.new(mx, h + (top - 3) / 2, mz) * turn,
				size = Vector3.new(half * 2, top + 3, half * 2),
				kind = kind,
			})
			if forest == 5 and bump < 0.6 then
				local s = half * 1.1
				table.insert(out, {
					cframe = CFrame.new(mx + (bx - 0.5) * 6, h + top + 1.5, mz + (bz - 0.5) * 6)
						* CFrame.Angles(0, yaw + math.pi / 4, 0),
					size = Vector3.new(s, 5, s),
					kind = kind,
				})
			end
		end
	end
	cachedFarCells[key] = out
	return out
end

-- Whether a filler trunk stands within `r` of (x, z) (AmbientLife keeps
-- its ground decoration out of them). False until the plan is ready.
-- Grass tufts (FOR-04): clumps of PropArt.GrassTuft where grass grows
-- long, round the camera (ForestFiller, within QualityBudgets' TuftNear):
-- along the forest's fringe (ForestCover TUFT_EDGE), on the road verges
-- (within TUFT_VERGE of a road's edge, never on it), round the boulders,
-- the cluster rocks and the scenery's outcrops, and at the foot of the
-- scenery's fence posts. Never in town or on the plots, on the water,
-- snow or the volcano's rock, nor up the mountains. `biome` picks the
-- grass's tint (PropArt.Tints).
export type Tuft = { x: number, y: number, z: number, yaw: number, seed: number, biome: string }
local TUFT_EDGE = { 0.28, 0.62 }
local TUFT_VERGE = { 0.6, 3.5 }
local TUFT_TRIES = 16 -- candidates per cell for the fringe and the verges
local TUFT_NO: { [string]: boolean } = { snow = true, volcano = true }

-- What tufts gather round, binned by FILLER_CELL squares: rocks (a disc to
-- ring) and fence posts (a point beside each).
type TuftAnchor = { x: number, z: number, r: number, post: boolean }
local cachedTuftAnchors: { [number]: { TuftAnchor } }? = nil
local function tuftAnchors(): { [number]: { TuftAnchor } }
	if cachedTuftAnchors then
		return cachedTuftAnchors
	end
	local bins: { [number]: { TuftAnchor } } = {}
	local function add(x: number, z: number, r: number, post: boolean)
		local key = binKey(x // FILLER_CELL, z // FILLER_CELL)
		local bin = bins[key]
		if not bin then
			bin = {}
			bins[key] = bin
		end
		table.insert(bin, { x = x, z = z, r = r, post = post })
	end
	for _, b in ipairs(WorldPlan.Boulders()) do
		add(b.position.X, b.position.Z, b.size * 0.5, false)
	end
	for _, c in ipairs(WorldPlan.BoulderClusters()) do
		for _, rock in ipairs(c.rocks) do
			add(rock.position.X, rock.position.Z, rock.size * 0.5, false)
		end
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		for _, item in ipairs(spot.items) do
			if item.builder == "Outcrop" then
				add(item.cframe.X, item.cframe.Z, 5, false)
			elseif item.builder == "Fence" then
				local posts = math.max(2, math.floor(item.size / 6) + 1)
				for i = 0, posts - 1 do
					local x = -item.size / 2 + i * item.size / (posts - 1)
					for _, side in ipairs({ -0.9, 0.9 }) do
						local p = item.cframe * Vector3.new(x, 0, side)
						add(p.X, p.Z, 0, true)
					end
				end
			end
		end
	end
	cachedTuftAnchors = bins
	return bins
end

local cachedTuftCells: { [number]: { Tuft } } = {}

-- The grass tufts in cell (cx, cz). Each candidate draws the same rng
-- numbers whether it grows or not.
function WorldPlan.TuftCell(cx: number, cz: number): { Tuft }
	local key = binKey(cx, cz)
	local done = cachedTuftCells[key]
	if done then
		return done
	end
	local out: { Tuft } = {}
	local rng = Kit.rng(cellSeed(cx, cz) + 909)
	local function add(x: number, z: number, yaw: number, seed: number)
		if WorldLayout.FlatWeight(x, z) > 0 or TerrainGen.RoadClearance(x, z) < TUFT_VERGE[1] then
			return
		end
		if TerrainGen.WaterLevelAt(x, z) ~= nil then
			return
		end
		local coast = WorldLayout.Coast
		if z < coast.northZ and x > coast.shoreX - coast.beachWidth - 10 then
			return
		end
		local biome = BiomeData.At(x, z)
		local id = if biome then biome.id else "starter"
		if TUFT_NO[id] then
			return
		end
		local h = TerrainGen.HeightAt(x, z)
		if h < FILLER_LOW then
			table.insert(out, { x = x, y = h, z = z, yaw = yaw, seed = seed, biome = id })
		end
	end
	-- The forest's fringe and the road verges.
	for _ = 1, TUFT_TRIES do
		local x = cx * FILLER_CELL + rng:next() * FILLER_CELL
		local z = cz * FILLER_CELL + rng:next() * FILLER_CELL
		local roll, yaw, seed = rng:next(), rng:range(0, math.pi * 2), rng:int(1, 99999)
		local roads = TerrainGen.RoadClearance(x, z)
		if roads <= TUFT_VERGE[2] then
			if roll < 0.55 then
				add(x, z, yaw, seed)
			end
		elseif roll < 0.6 then
			local c = WorldLayout.ForestCover(x, z)
			if c > TUFT_EDGE[1] and c < TUFT_EDGE[2] then
				add(x, z, yaw, seed)
			end
		end
	end
	-- Round the rocks and at the fence posts whose middles are in this cell.
	local anchors: { TuftAnchor } = tuftAnchors()[key] or {}
	for _, anchor in ipairs(anchors) do
		local count = if anchor.post then 1 else 3
		local start = rng:range(0, math.pi * 2)
		for k = 1, count do
			local a = start + k * math.pi * 2 / count + rng:range(-0.4, 0.4)
			local r = if anchor.post then 0 else anchor.r + rng:range(0.2, 0.8)
			add(anchor.x + math.cos(a) * r, anchor.z + math.sin(a) * r, rng:range(0, math.pi * 2), rng:int(1, 99999))
		end
	end
	cachedTuftCells[key] = out
	return out
end

-- The cells round (px, py, pz) that get their tufts (within `near`, or
-- `near` + FillerHysteresis for the ones `current` has).
function WorldPlan.TuftPlanAround(
	px: number,
	py: number,
	pz: number,
	near: number,
	current: { [number]: boolean }?
): { [number]: boolean }
	local out: { [number]: boolean } = {}
	local dy = math.max(0, py - TerrainGen.HeightAt(px, pz) - 40)
	local reach = near + WorldPlan.FillerHysteresis
	if dy >= reach then
		return out
	end
	for cx = (px - reach) // FILLER_CELL, (px + reach) // FILLER_CELL do
		for cz = (pz - reach) // FILLER_CELL, (pz + reach) // FILLER_CELL do
			local dx = (cx + 0.5) * FILLER_CELL - px
			local dz = (cz + 0.5) * FILLER_CELL - pz
			local d = math.sqrt(dx * dx + dz * dz + dy * dy)
			local key = binKey(cx, cz)
			if d <= near or (current and current[key] and d <= reach) then
				out[key] = true
			end
		end
	end
	return out
end

function WorldPlan.FillerTrunkNear(x: number, z: number, r: number): boolean
	if not cachedFillerClutter then
		return false
	end
	for cx = (x - r) // FILLER_CELL, (x + r) // FILLER_CELL do
		for cz = (z - r) // FILLER_CELL, (z + r) // FILLER_CELL do
			for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
				local dx, dz = tree.x - x, tree.z - z
				if dx * dx + dz * dz < r * r then
					return true
				end
			end
		end
	end
	return false
end

-- Cell keys (as FillerCellKey) round a camera at (px, py, pz): "near"
-- (real trees) within `near` studs of the camera, "far" (stand-ins) out
-- to `far`. Distance is to the cell's middle, with the camera's height
-- over 150 studs counted too (from the isles the ground is all far). A
-- cell already loaded (`current`) keeps its look FillerHysteresis past its
-- radius, so standing at a cell's edge doesn't flip it to and fro.
function WorldPlan.FillerCellKey(cx: number, cz: number): number
	return binKey(cx, cz)
end
function WorldPlan.FillerCellOf(key: number): (number, number)
	return key // 4096 - 1000, key % 4096 - 1000
end
function WorldPlan.FillerPlanAround(
	px: number,
	py: number,
	pz: number,
	near: number,
	far: number,
	current: { [number]: string }?
): { [number]: string }
	local out: { [number]: string } = {}
	local hyst = WorldPlan.FillerHysteresis
	local dy = math.max(0, py - 150)
	local reach = math.sqrt(math.max(0, (far + hyst) ^ 2 - dy * dy))
	if reach <= 0 then
		return out
	end
	local half = WorldLayout.WorldHalf
	for cx = math.max(-half, px - reach) // FILLER_CELL, math.min(half - 1, px + reach) // FILLER_CELL do
		for cz = math.max(-half, pz - reach) // FILLER_CELL, math.min(half - 1, pz + reach) // FILLER_CELL do
			local dx = (cx + 0.5) * FILLER_CELL - px
			local dz = (cz + 0.5) * FILLER_CELL - pz
			local d = math.sqrt(dx * dx + dz * dz + dy * dy)
			local key = binKey(cx, cz)
			local was = if current then current[key] else nil
			if d <= near or (was == "near" and d <= near + hyst) then
				out[key] = "near"
			elseif d <= far or (was == "far" and d <= far + hyst) then
				out[key] = "far"
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Reserved regions (Lane R fills them). Anchors only: no trees, no props.
---------------------------------------------------------------------------

export type DiscAnchor = { id: string, x: number, z: number, radius: number }
export type BoxAnchor = { id: string, x: number, z: number, sx: number, sz: number }
export type PointAnchor = { id: string, x: number, z: number }
export type ResourceRegion = { id: string, x: number, z: number, trees: number }

local bayou = WorldLayout.Bayou
local mesa = WorldLayout.RedMesa

WorldPlan.BayouCentre = { id = bayou.id, x = bayou.x, z = bayou.z, radius = bayou.radius } :: DiscAnchor
WorldPlan.MesaCentre = { id = mesa.id, x = mesa.x, z = mesa.z, radius = mesa.radius } :: DiscAnchor

-- Four mud patches inside the basin, off BayouRoad, each radius 18–30.
WorldPlan.MudZones = {
	{ id = "mud-1", x = -820, z = -640, radius = 20 },
	{ id = "mud-2", x = -680, z = -760, radius = 22 },
	{ id = "mud-3", x = -740, z = -640, radius = 18 },
	{ id = "mud-4", x = -700, z = -800, radius = 22 },
} :: { DiscAnchor }

WorldPlan.BaitShackSpot = { id = "bait-shack", x = -720, z = -660 } :: PointAnchor
-- A 40 by 30 log landing on the flat basin.
WorldPlan.BayouLogLanding = { id = "bayou-landing", x = -800, z = -700, sx = 40, sz = 30 } :: BoxAnchor

-- Eight ore slabs along the mesa's north rim, 8 studs in from the edge.
local slabNodes: { PointAnchor } = {}
local slabDx = { -70, -50, -30, -10, 10, 30, 50, 70 }
for i, dx in ipairs(slabDx) do
	local inset = math.sqrt(mesa.radius * mesa.radius - dx * dx) - 8
	table.insert(slabNodes, { id = "slab-" .. tostring(i), x = mesa.x + dx, z = mesa.z + inset })
end
WorldPlan.SlabNodes = slabNodes

-- A 40 by 30 truck lot on the mesa, south of the junction circle.
WorldPlan.MesaTruckLot = { id = "mesa-lot", x = 620, z = -770, sx = 40, sz = 30 } :: BoxAnchor

-- One empty spawn hook per region. Lane R puts the unique item here.
WorldPlan.UniqueItemSpawns = {
	{ id = "bayou", x = -780, z = -780 },
	{ id = "redmesa", x = 590, z = -860 },
} :: { PointAnchor }

-- Faces south (-Z) onto MainStreet. Between GondolaPath (x -37.5) and
-- ToolShedFloor (x -62).
WorldPlan.LeaderboardBoard = CFrame.new(-50, 0, 92)

-- Biome discs that grow a wood, plus the two reserved regions (0 trees
-- until Lane R). Centre to centre must be at least 500. A pair under 700
-- keeps 70 trees or fewer between them.
function WorldPlan.ResourceRegions(): { ResourceRegion }
	local out: { ResourceRegion } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		local trees = biome.trees
		if area and trees then
			local count = 0
			for _, n in pairs(trees) do
				count += n
			end
			table.insert(out, { id = biome.id, x = area.x, z = area.z, trees = count })
		end
	end
	table.insert(out, { id = bayou.id, x = bayou.x, z = bayou.z, trees = 0 })
	table.insert(out, { id = mesa.id, x = mesa.x, z = mesa.z, trees = 0 })
	return out
end

function WorldPlan.SpacingViolations(): { string }
	local regions = WorldPlan.ResourceRegions()
	local out: { string } = {}
	for i = 1, #regions do
		for j = i + 1, #regions do
			local a, b = regions[i], regions[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
			if d < 500 then
				table.insert(out, string.format("%s and %s are %.0f apart", a.id, b.id, d))
			elseif d < 700 and a.trees + b.trees > 70 then
				table.insert(
					out,
					string.format("%s and %s are %.0f apart with %d trees", a.id, b.id, d, a.trees + b.trees)
				)
			end
		end
	end
	return out
end

local TreeFill = require(script.Parent.TreeFill)
TreeFill.Bind({
	GoodGround = WorldPlan.GoodGround,
	Town = WorldPlan.Town,
	Scenery = WorldPlan.Scenery,
	GroveDiscs = WorldPlan.GroveDiscs,
	CountryStands = WorldPlan.CountryStands,
	Boulders = WorldPlan.Boulders,
	MeadowBoulders = WorldPlan.MeadowBoulders,
	RoadSigns = WorldPlan.RoadSigns,
	GateSigns = WorldPlan.GateSigns,
	LandmarkDiscs = WorldPlan.LandmarkDiscs,
	BoulderClusters = WorldPlan.BoulderClusters,
})

return WorldPlan
