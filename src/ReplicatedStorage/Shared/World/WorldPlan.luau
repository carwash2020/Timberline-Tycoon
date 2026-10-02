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
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Parent.Art.Kit)
local TerrainGen = require(script.Parent.TerrainGen)
local WoodData = require(script.Parent.Parent.WoodData)
local WorldLayout = require(script.Parent.WorldLayout)

local WorldPlan = {}

export type TreeSpot = { woodId: string, position: Vector3, biome: string } -- biome "wild": a meadow grove
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
	if TerrainGen.WaterLevelAt(x, z) ~= nil then
		return false
	end
	if TerrainGen.RoadClearance(x, z) < (roadClearance or 6) then
		return false
	end
	local cone = WorldLayout.VolcanoCone
	local dx, dz = x - cone.x, z - cone.z
	if dx * dx + dz * dz < (cone.radius * 0.55) ^ 2 then
		return false
	end
	return TerrainGen.SlopeAt(x, z) < (maxSlope or 0.75)
end
local goodGround = WorldPlan.GoodGround

local cachedTrees: { TreeSpot }? = nil

local WILD_GROVES = 22 -- stands of trees in the open country
local WILD_NEAREST = 300 -- studs from the sawmill (the Starter Forest is 190)

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
local function firstTrees(): { TreeSpot }
	if cachedFirst then
		return cachedFirst
	end
	local out: { TreeSpot } = {}
	local taken: { Vector3 } = {}
	for _, biome in ipairs(BiomeData.All()) do
		local area = biome.area
		local counts = biome.trees
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
						table.insert(out, { woodId = woodId, position = p, biome = biome.id })
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
	for _, c in ipairs(centers) do
		local woods = wildWoodsNear(c)
		local want = wildRng:int(4, 8)
		local placed, attempts = 0, 0
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
				table.insert(out, { woodId = woodId, position = p, biome = "wild" })
				placed += 1
			end
		end
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
local STAND_MAX = 180 -- new trees in all (about 33 parts each)
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

-- Every tree on the ground, in spawn order: the first 322 (each biome's
-- trees, then the wild groves), then the country stands' (the sky's
-- Lumenwood is in WorldPlan.Sky).
function WorldPlan.Trees(): { TreeSpot }
	if cachedTrees then
		return cachedTrees
	end
	local out = table.clone(firstTrees())
	for _, stand in ipairs(WorldPlan.CountryStands()) do
		for _, spot in ipairs(stand.trees) do
			table.insert(out, spot)
		end
	end
	cachedTrees = out
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

-- Glowing mushrooms in the Phantom Grove (its tell at night).
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

-- Palm trees on the offshore island (looks only, until boats).
function WorldPlan.IslandPalms(): { Vector3 }
	local island = WorldLayout.Island
	local out: { Vector3 } = {}
	local rng = Kit.rng(909)
	for _ = 1, 7 do
		local a, r = rng:range(0, math.pi * 2), rng:range(5, island.radius * 0.55)
		local x, z = island.x + math.cos(a) * r, island.z + math.sin(a) * r
		table.insert(out, Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z))
	end
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

export type Town = {
	spawn: Vector3,
	spawnFacing: CFrame, -- the SpawnLocation's CFrame: at `spawn`, its front toward the sawmill
	sawmill: CFrame,
	sellZone: CFrame, -- centre of the 24 x 12 x 18 sell volume
	sellPad: CFrame,
	skyBin: CFrame,
	shops: { ShopSpot },
	gondola: CFrame,
	campsite: CFrame,
	murph: CFrame, -- where Murph stands, facing the spawn
	gondolaSign: CFrame, -- the "SKYROOT GONDOLA" signpost
	parkingSlots: { CFrame }, -- in claim order (Index 1, 2, ...)
	lamps: { CFrame },
	fences: { Fence },
	props: { Placement },
	signs: { Sign },
	greenery: { Greenery }, -- ornamental: never choppable
}

local FACING_SOUTH = CFrame.Angles(0, 0, 0) -- builders face -Z already

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
	-- None stand where trucks pull out of the parking slots (x 16 to 104),
	-- and none on a road (like every colliding thing in town: WorldPlan.spec).
	-- The lot's lamp stands south of the Plot Road's mouth, its arm over it.
	local lamps: { CFrame } = {}
	for _, x in ipairs({ -92, -64, -30, -14 }) do
		table.insert(lamps, at(x, 68.5, math.pi)) -- south side, arm north over the street
	end
	for _, x in ipairs({ 30, 58 }) do
		table.insert(lamps, at(x, 86, 0)) -- north side, arm south over the street
	end
	table.insert(lamps, at(-8, 60, -math.pi / 2))
	table.insert(lamps, at(8, 60, math.pi / 2))
	table.insert(lamps, at(-23, 132, math.pi / 2))
	table.insert(lamps, at(26, 122, 0))
	table.insert(lamps, at(118, 40, math.pi))
	table.insert(lamps, at(120, 0, math.pi / 2))

	-- Fences: a paddock behind Hearth & Home, a rail along the lot's east
	-- edge (z 6 to 42, ending short of the Plot Road).
	local fences: { Fence } = {
		{ length = 26, cframe = at(-88, 136) },
		{ length = 26, cframe = at(-88, 114) },
		{ length = 22, cframe = at(-101, 125, math.pi / 2) },
		{ length = 36, cframe = at(111, 24, math.pi / 2) },
	}

	-- Murph's camp west of the spawn, behind the TO THE WOODS sign and clear
	-- of the Hills Road: the campfire at its origin, the tent behind (+Z),
	-- facing the spawn; Murph stands at camp-local (0, 0, -3), his lantern
	-- on its hook beside the camp, turned with it.
	local campsite = facing(-28, 42, 0, 40)
	local _, campYaw = campsite:ToEulerAnglesYXZ()
	local lantern = campsite * Vector3.new(9, 0, 2)

	local propSpots: { { any } } = { -- { name, x, z, yaw? }
		{ "Haybale", -93, 128, 0.3 },
		{ "Haybale", -85, 121, -0.5 },
		{ "Haybale", -80, 130, 1.2 },
		{ "Cart", -71, 124, -0.4 },
		{ "WaterTower", -58, 126 },
		{ "ToolRack", -33, 97, -math.pi / 2 },
		{ "Well", -49, 60 }, -- on the green south of the street, between the benches
		{ "Bench", -58, 66, math.pi },
		{ "Bench", -40, 66, math.pi },
		{ "Barrel", -32.5, 92 },
		{ "Crate", -57, 92, 0.3 },
		{ "Barrel", 32, 93 },
		{ "Crate", 57, 93, -0.2 },
		{ "Crate", 57.5, 89.5, 0.5 },
		{ "Planter", -66, 92 },
		{ "Planter", -94, 92 },
		{ "Mailbox", -91, 87, 0 },
		{ "FlowerBox", -86, 90.5, 0 },
		{ "LogPile", 28, 108, 0 },
		{ "LogPile", 29, 98, 0.1 }, -- clear of the plaza's corner
		{ "Wheelbarrow", 20, 93, -0.6 },
		{ "SawdustPile", 22, 114 }, -- by the lean-to, clear of the yard lamp
		{ "SawdustPile", -21, 99 },
		{ "Lantern", lantern.X, lantern.Z, campYaw },
		{ "Barrel", -22, 116 }, -- against the mill's side shed, off the gondola path
		{ "Barrel", -22, 113.5 },
	}
	local props: { Placement } = {}
	for i, p in ipairs(propSpots) do
		local name: string, x: number, z: number, yaw: number? = p[1], p[2], p[3], p[4]
		table.insert(props, { name = name, cframe = at(x, z, yaw), seed = i * 13 })
	end

	-- Parking: two rows of 12 slots facing the forest (-Z), sized for the
	-- longest rig (VehicleService claims them by Index).
	local slots: { CFrame } = {}
	for row = 0, 1 do
		for col = 0, 11 do
			table.insert(slots, CFrame.new(16 + col * 8, 0.1, 45 - row * 40))
		end
	end

	-- Signs: one by the spawn with every destination, the plots, and SELL
	-- LOGS HERE by the pad (the gondola's is gondolaSign).
	local distances: { string } = {}
	for _, id in ipairs({ "starter", "hills", "snow", "volcano" }) do
		local def = BiomeData.Get(id)
		if def then
			table.insert(distances, string.format("%s  %d", def.displayName, def.haulStuds or 0))
		end
	end
	-- SELL LOGS HERE (TWN-04) stands upright at the pad's east edge, facing
	-- the street, beside Millie (who stands at (14.6, 92.5), just off the
	-- pad's edge): its west post 2.4 studs east of the pad, out of the
	-- trucks' lane in from the street, 5 studs north of the street, 2.5
	-- studs or more from Millie and south of her, so from the spawn she
	-- shows just left of its board; its east post inside the plaza (x < 26),
	-- out of the lane north (TWN-05) and clear of the lamp at (30, 86).
	-- Like the corner lamps, it may stand on the plaza, never on the
	-- street, the pad or a path (WorldPlan.spec).
	local signs: { Sign } = {
		{ text = "TO THE WOODS\n" .. table.concat(distances, "\n"), cframe = facing(-16, 44, 0, 40) },
		{ text = "PLOT DISTRICT\nClaim a free plot\nand build on it", cframe = standing(124, 64, 0, 40) },
		{ text = "SELL LOGS HERE", cframe = at(20.5, 89.5) * FACING_SOUTH, lit = true }, -- lamps over its face (TWN-07)
	}

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
		{ "tree", -58, 196, 1.22, "pine" },
		{ "tree", -62, 147, 1, "pine" },
		{ "tree", -80, 163, 1.22, "pine" },
		{ "tree", -94, 150, 1, "pine" },
		{ "tree", -106, 174, 1.22, "pine" },
		-- Birch and maple round the edges.
		{ "tree", -106, 56, 1.22, "maple" },
		{ "tree", -116, 86, 1, "birch" },
		{ "tree", -112, 110, 1.22, "birch" },
		{ "tree", -118, 138, 1, "maple" },
		{ "tree", -80, 50, 1, "maple" },
		{ "tree", -62, 6, 1, "birch" },
		{ "tree", -98, 14, 1.22, "birch" },
		{ "tree", -46, 118, 1, "birch" },
		{ "tree", 50, 122, 1, "maple" },
		{ "tree", 78, 114, 1.22, "birch" },
		{ "tree", 104, 128, 1.22, "maple" },
		{ "tree", 130, 98, 1, "birch" },
		{ "tree", 124, 150, 1, "maple" },
		{ "tree", 96, 162, 1.22, "birch" },
		{ "tree", 68, 168, 1.22, "maple" },
		{ "tree", 128, 24, 1, "birch" },
		{ "tree", 132, -14, 1.22, "maple" },
		-- Bushes along the shops' sides, the mill's back and the station.
		{ "bush", -66, 100, 2.8 },
		{ "bush", -66.5, 105.5, 2.4 },
		{ "bush", -57, 100, 2.6 },
		{ "bush", -57.5, 106, 3 },
		{ "bush", 58, 101, 2.8 },
		{ "bush", 58.5, 106.5, 2.4 },
		{ "bush", -8, 129, 2.6 },
		{ "bush", 8, 129, 2.8 },
		{ "bush", -51.5, 146, 2.8 },
		{ "bush", -28, 148, 2.6 },
		{ "bush", -28.5, 154, 2.4 },
		-- Flower beds: off the plaza's south-west corner, by the spawn walk,
		-- at the mouths of the Hearth & Home path, by the well. (None where
		-- the townsfolk walk: NPCData's routes pass 3 studs or more away.)
		{ "flowers", -30, 54.5, 2.4 },
		{ "flowers", -8.4, 53.6, 2 },
		{ "flowers", -72.5, 87.2, 2.2 },
		{ "flowers", -87.5, 86, 1.8 },
		{ "flowers", -57.5, 57, 2.4 },
		-- Rocks.
		{ "rock", -55, 150, 1.8 },
		{ "rock", 66, 110, 2 },
		{ "rock", -101, 100, 1.6 },
		{ "rock", 116, 72, 1.8 },
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

	-- A character spawns facing its SpawnLocation's front (LookVector), so
	-- turn the pad's front (-Z) half a turn to +Z: the sawmill is due north
	-- of the spawn, framed by the walk's two lamps. (Angles, not
	-- CFrame.lookAt: Lune gets lookAt wrong, and Shared code runs there.)
	local spawn = Vector3.new(0, 0.5, 40)
	local spawnFacing = CFrame.new(spawn) * CFrame.Angles(0, math.pi, 0)

	return {
		spawn = spawn,
		spawnFacing = spawnFacing,
		sawmill = CFrame.new(mill) * FACING_SOUTH,
		sellZone = CFrame.new(mill.X, 6, mill.Z - 24),
		sellPad = CFrame.new(mill.X, 0, mill.Z - 24),
		skyBin = CFrame.new(mill.X - 18, 2, mill.Z - 24),
		shops = {
			{
				kind = "ToolShed",
				title = "TOOL SHED",
				accent = Color3.fromRGB(150, 62, 44),
				cframe = CFrame.new(-45, 0, 100),
			},
			{
				kind = "Dealership",
				title = "DEALERSHIP",
				accent = Color3.fromRGB(47, 109, 181),
				cframe = CFrame.new(45, 0, 100),
			},
			{
				kind = "HearthAndHome",
				title = "HEARTH & HOME",
				accent = Color3.fromRGB(122, 90, 60),
				cframe = CFrame.new(-80, 0, 100),
			},
		},
		gondola = townGondola(),
		campsite = campsite,
		murph = campsite * CFrame.new(0, 0, -3),
		gondolaSign = facing(-36, 128, 0, 80),
		parkingSlots = slots,
		lamps = lamps,
		fences = fences,
		props = props,
		signs = signs,
		greenery = greenery,
	}
end

-- Signposts where the roads reach each biome: facing back down the road,
-- listing the woods and the gear you need. (The Phantom Grove has none.)
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
	local roadFor = { HillsRoad = "hills", SnowRoad = "snow", VolcanoRoad = "volcano", SkyrootRoad = "sky" }
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
			for back = 6, math.min(66, (last - prev).Magnitude - 6), 4 do
				for _, s in ipairs({ 1, -1 }) do
					local at = last - dir * back + side * (s * (road.width / 2 + SIGN_POST + SIGN_CLEAR + 0.5))
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
			if not spot then
				local at = last - dir * 6 + side * (road.width / 2 + 0.35 + SIGN_CLEAR + 0.5)
				local roadSide = Vector3.new(at.X - side.X, 0, at.Y - side.Y) -- its face toward the road
				spot = setDown(CFrame.lookAt(Vector3.new(at.X, 0, at.Y), roadSide))
			end
			table.insert(out, { text = text(biomeId), cframe = spot :: CFrame })
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

return WorldPlan
