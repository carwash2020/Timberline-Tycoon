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
local shopDoors: { Vector3 }? = nil
local function shopDoorsOf(): { Vector3 }
	if shopDoors then
		return shopDoors
	end
	local list: { Vector3 } = {}
	local town = world().Town() :: { shops: { Shop } }
	for _, shop in ipairs(town.shops) do
		table.insert(list, shop.cframe.Position)
	end
	shopDoors = list
	return list
end

-- 12 studs off every plot's biggest footprint, and 20 off the spawn pad
-- and each shop door. Roads are GoodGround's.
function TreeFill.Clear(x: number, z: number): boolean
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	for _, slot in ipairs(PlotData.Slots) do
		if outsideBox(x, z, slot.X - half, slot.Y - half, slot.X + half, slot.Y + half) < PLOT_GAP then
			return false
		end
	end
	if dist(x, z, 0, 40) < DOOR_GAP + 3 then
		return false
	end
	for _, p in ipairs(shopDoorsOf()) do
		if dist(x, z, p.X, p.Z) < DOOR_GAP then
			return false
		end
	end
	return true
end

local function takenNear(taken: { Vector3 }, x: number, z: number, gap: number): boolean
	local g2 = gap * gap
	for _, p in ipairs(taken) do
		local dx, dz = p.X - x, p.Z - z
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
local function sceneryClear(x: number, z: number): boolean
	for _, pad in ipairs(sceneryList()) do
		if dist(x, z, pad[1], pad[2]) < pad[3] then
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
		if dist(x, z, pad[1], pad[2]) < pad[3] + extra then
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

-- Boot placement and regrowth share this. A point on a widened haul road,
-- in a loading pad, or on a homestead square is not ground.
function TreeFill.Ground(x: number, z: number): boolean
	if WorldLayout.TreeBlocked(x, z) then
		return false
	end
	return world().GoodGround(x, z, ROAD_GAP, 0.75)
		and TreeFill.Clear(x, z)
		and sceneryClear(x, z)
		and landmarkClear(x, z, 0)
		and yardsClear(x, z)
end

-- The trunk's plan position sits inside a haul road's paved width.
function TreeFill.InHaulLane(x: number, z: number): boolean
	local p = Vector2.new(x, z)
	for _, road in ipairs(WorldLayout.Roads) do
		if HAUL[road.name] then
			if WorldLayout.PolylineDistance(p, road.points) < road.width / 2 - 1e-3 then
				return true
			end
		end
	end
	return false
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
		return TreeFill.Ground(px, pz) and not takenNear(taken, px, pz, gap)
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
function TreeFill.Extra(existing: { Spot }): { Spot }
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

	local clumps = TreeFill.Clumps(taken, rng)
	for _, spot in ipairs(clumps) do
		table.insert(out, spot)
		table.insert(taken, spot.position)
	end
	return out
end

local function quiet(x: number, z: number, pad: number): boolean
	for _, q in ipairs(QUIET) do
		if dist(x, z, q[1], q[2]) < q[3] + pad then
			return false
		end
	end
	return true
end

local function haulClear(x: number, z: number, gap: number): boolean
	local p = Vector2.new(x, z)
	for _, road in ipairs(WorldLayout.Roads) do
		if HAUL[road.name] then
			if WorldLayout.PolylineDistance(p, road.points) - road.width / 2 < gap then
				return false
			end
		end
	end
	return true
end

local function plotClear(x: number, z: number, gap: number): boolean
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	for _, slot in ipairs(PlotData.Slots) do
		if outsideBox(x, z, slot.X - half, slot.Y - half, slot.X + half, slot.Y + half) < gap then
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
		if dist(x, z, o[1], o[2]) < o[3] then
			return false
		end
	end
	return true
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
				and TreeFill.Ground(x, z)
				and quiet(x, z, 0)
				and not takenNear(taken, x, z, TREE_GAP)
				and not takenNear(reserved, x, z, TREE_GAP)
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
function TreeFill.Clumps(taken: { Vector3 }, rng: any): { Spot }
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
