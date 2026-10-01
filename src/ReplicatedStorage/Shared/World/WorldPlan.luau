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
export type Sign = { text: string, cframe: CFrame }
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

-- Every tree on the ground: each biome's trees (BiomeData counts), then the
-- wild groves between them (the sky's Lumenwood is in WorldPlan.Sky).
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
	local trees = WorldPlan.Trees()
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
-- The town
---------------------------------------------------------------------------

export type ShopSpot = { kind: string, title: string, accent: Color3, cframe: CFrame }

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
		{ "Well", -38, 77 },
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
		{ "LogPile", 28, 98, 0.1 },
		{ "Wheelbarrow", 20, 93, -0.6 },
		{ "SawdustPile", 24, 118 },
		{ "SawdustPile", -21, 99 },
		{ "Lantern", lantern.X, lantern.Z, campYaw },
		{ "Barrel", -24, 120 },
		{ "Barrel", -26, 117.5 },
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

	-- Signs: one by the spawn with every destination, the gondola, plots.
	local distances: { string } = {}
	for _, id in ipairs({ "starter", "hills", "snow", "volcano" }) do
		local def = BiomeData.Get(id)
		if def then
			table.insert(distances, string.format("%s  %d", def.displayName, def.haulStuds or 0))
		end
	end
	local signs: { Sign } = {
		{ text = "TO THE WOODS\n" .. table.concat(distances, "\n"), cframe = facing(-16, 44, 0, 40) },
		{ text = "PLOT DISTRICT\nClaim a free plot\nand build on it", cframe = standing(124, 64, 0, 40) },
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

return WorldPlan
