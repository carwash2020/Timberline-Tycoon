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
local Kit = require(script.Parent.Parent.Art.Kit)
local TerrainGen = require(script.Parent.TerrainGen)
local WorldLayout = require(script.Parent.WorldLayout)

local WorldPlan = {}

export type TreeSpot = { woodId: string, position: Vector3, biome: string }
export type Placement = { name: string, cframe: CFrame, seed: number }
export type Sign = { text: string, cframe: CFrame }

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

-- Every wild tree on the ground (the sky's Lumenwood is in WorldPlan.Sky).
function WorldPlan.Trees(): { TreeSpot }
	if cachedTrees then
		return cachedTrees
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
	cachedTrees = out
	return out
end

---------------------------------------------------------------------------
-- Boulders and nature landmarks
---------------------------------------------------------------------------

export type Boulder = { position: Vector3, size: number, seed: number, snowy: boolean, dark: boolean }

function WorldPlan.Boulders(): { Boulder }
	local out: { Boulder } = {}
	local rng = Kit.rng(4242)
	local trees = WorldPlan.Trees()
	local tries = 0
	while #out < 90 and tries < 2000 do
		tries += 1
		local x, z = rng:range(-1350, 1350), rng:range(-1350, 1350)
		local ok = WorldLayout.FlatWeight(x, z) <= 0
			and TerrainGen.WaterLevelAt(x, z) == nil
			and TerrainGen.RoadClearance(x, z) > 10
			and TerrainGen.HeightAt(x, z) < 90
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

-- The volcano's crater: where the lava glows and the smoke rises.
function WorldPlan.Crater(): (Vector3, number)
	local cone = WorldLayout.VolcanoCone
	return Vector3.new(cone.x, TerrainGen.HeightAt(cone.x, cone.z), cone.z), cone.crater
end

---------------------------------------------------------------------------
-- The town
---------------------------------------------------------------------------

export type ShopSpot = { kind: string, title: string, accent: Color3, cframe: CFrame }

export type Town = {
	spawn: Vector3,
	sawmill: CFrame,
	sellZone: CFrame, -- centre of the 24 x 12 x 18 sell volume
	sellPad: CFrame,
	skyBin: CFrame,
	shops: { ShopSpot },
	gondola: CFrame,
	campsite: CFrame,
	parkingSlots: { CFrame }, -- in claim order (Index 1, 2, ...)
	lamps: { CFrame },
	props: { Placement },
	signs: { Sign },
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
	local lamps: { CFrame } = {}
	-- Main street: spawn north to the sell pad, lamps both sides.
	for z = 48, 74, 13 do
		table.insert(lamps, CFrame.new(-11, 0, z))
		table.insert(lamps, CFrame.new(11, 0, z))
	end
	-- Around the plaza and the shop row.
	for _, p in ipairs({
		{ -28, 84 },
		{ 28, 84 },
		{ -62, 90 },
		{ 62, 90 },
		{ -98, 92 },
		{ -40, 135 },
		{ 0, 30 },
		{ 120, 52 },
		{ 120, 0 },
	}) do
		table.insert(lamps, CFrame.new(p[1], 0, p[2]))
	end

	local props: { Placement } = {
		{ name = "LogPile", cframe = CFrame.new(24, 0, 112) * CFrame.Angles(0, math.pi / 2, 0), seed = 1 },
		{ name = "LogPile", cframe = CFrame.new(-25, 0, 118) * CFrame.Angles(0, math.pi / 2, 0), seed = 2 },
		{ name = "SawdustPile", cframe = CFrame.new(-21, 0, 96), seed = 3 },
		{ name = "WaterTower", cframe = CFrame.new(30, 0, 140), seed = 4 },
		{ name = "Well", cframe = CFrame.new(-24, 0, 70), seed = 5 },
		{ name = "Bench", cframe = CFrame.new(-6, 0, 52) * CFrame.Angles(0, math.pi / 2, 0), seed = 6 },
		{ name = "Bench", cframe = CFrame.new(6, 0, 62) * CFrame.Angles(0, -math.pi / 2, 0), seed = 7 },
		{ name = "Crate", cframe = CFrame.new(-55, 0, 93), seed = 8 },
		{ name = "Barrel", cframe = CFrame.new(-36, 0, 93), seed = 9 },
		{ name = "Barrel", cframe = CFrame.new(-35, 0, 95), seed = 10 },
		{ name = "Cart", cframe = CFrame.new(57, 0, 92) * CFrame.Angles(0, 0.4, 0), seed = 11 },
		{ name = "FlowerBox", cframe = CFrame.new(-86, 0, 92), seed = 12 },
		{ name = "FlowerBox", cframe = CFrame.new(-74, 0, 92), seed = 13 },
		{ name = "Mailbox", cframe = CFrame.new(-14, 0, 40) * CFrame.Angles(0, math.pi / 2, 0), seed = 14 },
		{ name = "Haybale", cframe = CFrame.new(-92, 0, 110), seed = 15 },
		{ name = "Wheelbarrow", cframe = CFrame.new(18, 0, 92) * CFrame.Angles(0, 2.2, 0), seed = 16 },
		{ name = "ToolRack", cframe = CFrame.new(-55, 0, 104) * CFrame.Angles(0, math.pi, 0), seed = 17 },
		{ name = "Planter", cframe = CFrame.new(10, 0, 30), seed = 18 },
		{ name = "Planter", cframe = CFrame.new(-10, 0, 30), seed = 19 },
	}

	-- Parking: two rows of 12 slots facing the forest (-Z), sized for the
	-- longest rig (VehicleService claims them by Index).
	local slots: { CFrame } = {}
	for row = 0, 1 do
		for col = 0, 11 do
			table.insert(slots, CFrame.new(16 + col * 8, 0.1, 45 - row * 40))
		end
	end

	-- Signs: one by the spawn with every destination, the gondola, plots.
	local distances: { string } = {}
	for _, id in ipairs({ "starter", "hills", "snow", "volcano" }) do
		local def = BiomeData.Get(id)
		if def then
			table.insert(distances, string.format("%s  %d", def.displayName, def.haulStuds or 0))
		end
	end
	local signs: { Sign } = {
		{ text = "TO THE WOODS\n" .. table.concat(distances, "\n"), cframe = standing(-18, 44, 0, 40) },
		{ text = "PLOT DISTRICT\nClaim a free plot\nand build on it", cframe = standing(124, 62, 0, 40) },
	}

	return {
		spawn = Vector3.new(0, 0.5, 40),
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
		campsite = CFrame.new(-17, 0, 25) * CFrame.Angles(0, math.rad(35), 0),
		parkingSlots = slots,
		lamps = lamps,
		props = props,
		signs = signs,
	}
end

-- Signposts where the roads reach each biome: facing back down the road,
-- listing the woods and the gear you need. (The Phantom Grove has none.)
function WorldPlan.RoadSigns(text: (biomeId: string) -> string): { Sign }
	local out: { Sign } = {}
	local roadFor = { HillsRoad = "hills", SnowRoad = "snow", VolcanoRoad = "volcano", SkyrootRoad = "sky" }
	for _, road in ipairs(WorldLayout.Roads) do
		local biomeId = roadFor[road.name]
		if biomeId then
			local pts = road.points
			local last, prev = pts[#pts], pts[#pts - 1]
			local dir = (last - prev).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			local at = last - dir * 6 + side * (road.width / 2 + 4)
			table.insert(out, { text = text(biomeId), cframe = standing(at.X, at.Y, prev.X, prev.Y) })
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
	chutes: { CFrame }, -- each on an outer isle's edge, facing outward
	forge: CFrame,
	gondolaTop: CFrame,
	gondolaBase: CFrame,
	lumenwood: { Vector3 },
	shards: { Vector3 },
	waterfall: { top: Vector3, bottom: Vector3 },
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
	local nearest = isles[1]
	for _, isle in ipairs(isles) do
		local d = Vector2.new(isle.center.X - spring.X, isle.center.Z - spring.Y).Magnitude
		local best = Vector2.new(nearest.center.X - spring.X, nearest.center.Z - spring.Y).Magnitude
		if d < best then
			nearest = isle
		end
	end
	local toSpring = Vector3.new(spring.X - nearest.center.X, 0, spring.Y - nearest.center.Z)
	local fallDir = if toSpring.Magnitude > 1 then toSpring.Unit else nearest.dir
	local fallTop = nearest.center + fallDir * (nearest.radius - 3) - Vector3.new(0, 2, 0)
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
		waterfall = { top = fallTop, bottom = Vector3.new(fallTop.X, WorldLayout.LakeLevel, fallTop.Z) },
	}
end

return WorldPlan
