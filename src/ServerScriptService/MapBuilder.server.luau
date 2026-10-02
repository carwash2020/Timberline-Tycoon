--!strict
-- MapBuilder: builds the world when the server starts (GAME_DESIGN §10,
-- §13; REDESIGN.md). Where things go is Shared/World/WorldPlan (pure, so
-- tools/preview draws the same world); how they look is Shared/Art.
--   1. TimberlineMap, the folder everything lives in (GameServer, TreeService
--      and the clients wait for it).
--   2. Characters wait until there's ground to stand on.
--   3. Terrain (TerrainBuilder): hills, rivers, the lake, the coast, roads.
--   4. The town: sawmill and sell area, the three shops, the gondola
--      station, Murph's camp, the parking lot, lamps, signs, props, and
--      its greenery (ornamental trees no one can chop, bushes, flowers).
--   5. The biomes: every wild tree (BiomeData counts) on the terrain,
--      boulders, the volcano's crater, the grove's glowing mushrooms, the
--      palm island offshore, signposts where the roads arrive, the
--      open country's scenery (decor set pieces), and the landscape's
--      landmarks (phase 10, STY: brown boulder clusters).
--   6. The Skyroot and the Aether Isles: isles, bridges, Lumenwood, Sky
--      Shard nodes, Cloud Chutes, the Starfall Forge, the waterfall.
--   7. The backdrop beyond the world's edge (mountains, sea, the volcano's
--      impostor), walls at the edge, the day/night clock, then characters.
-- Each part of 3-7 runs on its own (step() below): an error in one is
-- warned with a traceback and the rest still builds. The last three steps
-- (SellArea in, CharacterAutoLoads back on, load anyone waiting) always
-- run, so one broken builder can never stop players spawning.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local IsleArt = require(ReplicatedStorage.Shared.Art.IsleArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local LandmarkArt = require(ReplicatedStorage.Shared.Art.LandmarkArt)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local NodeService = require(script.Parent.NodeService)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local TreeService = require(script.Parent.TreeService)
local WorldClock = require(script.Parent.WorldClock)

local started = os.clock()

-- Runs one build step on its own. A failure warns once, with a traceback,
-- and is counted (the MapBuildFailures attribute); the world carries on.
-- (tostring first: debug.traceback itself errors on a non-string error.)
local failedSteps = 0
local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end
local function step(name: string, build: () -> ())
	local ok, err = xpcall(function(): any
		build()
		return nil
	end, traceback)
	if not ok then
		failedSteps += 1
		warn(string.format("[MapBuilder] %s failed, the rest of the world still builds:\n%s", name, tostring(err)))
	end
end

-- A place made from Studio's "Baseplate" template ships its own Baseplate
-- and SpawnLocation. They would fight our ground and steal spawns, so
-- remove them for this session (changes made while playing never touch the
-- saved place file).
for _, child in ipairs(workspace:GetChildren()) do
	if (child.Name == "Baseplate" and child:IsA("BasePart")) or child:IsA("SpawnLocation") then
		child:Destroy()
	end
end

-- 1. The folder.
local map = Instance.new("Folder")
map.Name = "TimberlineMap"
map.Parent = workspace

-- 2. Nobody spawns until the ground exists.
Players.CharacterAutoLoads = false

-- 3. Terrain.
local terrainSeconds = 0
step("3. Terrain", function()
	terrainSeconds = TerrainBuilder.Build(function(done: number, total: number)
		if done % 24 == 0 or done == total then
			print(string.format("[MapBuilder] Terrain %d/%d", done, total))
		end
	end)
end)

-- Helpers ------------------------------------------------------------------

local function place(model: Model, cf: CFrame, parent: Instance?): Model
	Kit.placeAt(model, cf)
	model.Parent = parent or map
	return model
end

local function persistent(model: Model): Model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

local function atomic(model: Model): Model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

-- An invisible helper volume: no collisions, clicks or touches.
local function ghost(p: BasePart, transparency: number)
	p.Transparency = transparency
	p.CanCollide = false -- must be false before CanQuery can be
	p.CanQuery = false
	p.CanTouch = false
end

-- A gondola station (GondolaService rides from its Platform).
local function station(name: string, cf: CFrame): Model
	local model = persistent(BuildingArt.GondolaStation())
	model.Name = name
	return place(model, cf)
end

-- Trees spawned (the MapTrees attribute, for GameServer's boot report).
local treesSpawned = 0

-- The sell area in front of the sawmill. SellArea is Persistent so every
-- client always has the sell zone (CarryController's prompt). It is made
-- here so the last steps can always parent it (last of all: GameServer
-- starts once it appears, so the whole world must exist by then); the
-- town fills it in.
local sellArea = Instance.new("Model")
sellArea.Name = "SellArea"
sellArea.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

---------------------------------------------------------------------------
-- 4. The town
---------------------------------------------------------------------------

local townStation: Model? = nil -- the town's gondola cable starts here (section 6)

step("4. The town", function()
	local town = WorldPlan.Town()

	step("4. The spawn", function()
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = town.spawnFacing -- players spawn facing the sawmill
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0 -- no force field bubble
		spawn.Color = Color3.fromRGB(168, 152, 128)
		spawn.Material = Enum.Material.Cobblestone
		spawn.Parent = map
	end)

	-- The sawmill, and the sell area in front of it.
	step("4. The sawmill", function()
		local sawmill = place(atomic(BuildingArt.Sawmill()), town.sawmill)
		local blade = sawmill:FindFirstChild("SawBlade", true)
		if blade then
			CollectionService:AddTag(blade, "SawBlade") -- TownFX spins it
		end
	end)

	step("4. The sell area", function()
		local sellZone = Kit.part(sellArea, "SellZone", Vector3.new(24, 12, 18), town.sellZone, Color3.new(1, 1, 1))
		ghost(sellZone, 1)
		local sellPoint = Instance.new("Attachment") -- where the client's "Sell logs" prompt appears
		sellPoint.Name = "SellPoint"
		sellPoint.Position = Vector3.new(0, -2.5, 0)
		sellPoint.Parent = sellZone

		local padArt = BuildingArt.SellPad(24, 18)
		place(padArt, town.sellPad, sellArea)
	end)

	-- The Sky Bin: logs sent down the Cloud Chute wait here (WorldUI rewrites
	-- its labels with each player's own count). The bin part itself goes into
	-- SellArea (the contract); the flume and cloud behind it stay in the map.
	step("4. The Sky Bin", function()
		local binArt = BuildingArt.SkyBin()
		place(atomic(binArt), town.skyBin * CFrame.new(0, -2, 0)) -- town.skyBin is the bin's centre
		local bin = binArt:FindFirstChild("SkyBin")
		if bin then
			bin.Parent = sellArea
		end
	end)

	-- Shops: Persistent, with a Counter whose ShopPoint is where the client's
	-- "Browse" prompt appears and what ShopService measures range from.
	step("4. The shops", function()
		for _, spot in ipairs(town.shops) do
			local shop = persistent(BuildingArt.Shop(spot.kind, spot.title, spot.accent))
			shop.Name = spot.kind
			local counter = shop:FindFirstChild("Counter")
			assert(counter and counter:IsA("BasePart"), "[MapBuilder] " .. spot.kind .. " has no Counter")
			local point = Instance.new("Attachment")
			point.Name = "ShopPoint"
			point.Position = Vector3.new(0, 0, -(counter.Size.Z / 2 + 0.5)) -- the customer's side
			point.Parent = counter
			shop.PrimaryPart = counter
			place(shop, spot.cframe)
		end
	end)

	-- The gondola station in town.
	step("4. The gondola station", function()
		townStation = station("GondolaTown", town.gondola)
	end)

	-- Murph's camp by the spawn (Murph himself is NPCService's).
	step("4. Murph's camp", function()
		local camp = place(atomic(BuildingArt.Campsite()), town.campsite)
		for _, part in ipairs(camp:GetDescendants()) do
			if part.Name == "Flame" and part:IsA("BasePart") then
				CollectionService:AddTag(part, "Flame") -- TownFX flickers them
			end
		end
	end)

	-- Parking lot: one slot per player, so trucks never spawn inside each other.
	-- VehicleService claims slots by Index. Paint on the ground: no lip for a
	-- truck to snag on.
	local slots: { BasePart } = {}
	step("4. The parking lot", function()
		for index, cf in ipairs(town.parkingSlots) do
			local slot = Kit.part(
				map,
				"ParkingSlot_" .. index,
				Vector3.new(6.5, 0.2, 37),
				cf,
				Color3.fromRGB(186, 168, 140),
				Enum.Material.Slate
			)
			slot.CanCollide = false
			slot.CastShadow = false
			slot:SetAttribute("Index", index)
			CollectionService:AddTag(slot, "ParkingSlot")
			table.insert(slots, slot)
		end
	end)
	-- Its paint and lights (TWN-06), a step of their own so a failure here
	-- never costs a slot (the slab then just stays visible).
	step("4. The parking lot's lines and lamps", function()
		for index, slot in ipairs(slots) do
			BuildingArt.ParkingBay(slot, index)
		end
	end)

	-- Lamps, props, signs.
	step("4. Lamps, fences, props and signs", function()
		for _, cf in ipairs(town.lamps) do
			local lamp = BuildingArt.LampPost()
			CollectionService:AddTag(lamp, "StreetLamp") -- clients light them at night
			place(atomic(lamp), cf)
		end
		for _, fence in ipairs(town.fences) do
			place(atomic(BuildingArt.Fence(fence.length)), fence.cframe)
		end
		for _, prop in ipairs(town.props) do
			place(atomic(BuildingArt.Prop(prop.name, prop.seed)), prop.cframe)
		end
		for _, sign in ipairs(town.signs) do
			place(atomic(BuildingArt.Signpost(sign.text, sign.lit)), sign.cframe)
		end
		do
			local skyBiome = BiomeData.Get("sky")
			local fee = if skyBiome and skyBiome.gondola then skyBiome.gondola.fee else 250
			place(
				atomic(BuildingArt.Signpost(string.format("SKYROOT GONDOLA\nto the Aether Isles\n$%d a ride", fee))),
				town.gondolaSign
			)
		end
	end)

	-- The town's greenery: ornamental trees in stone rings, bushes, flower
	-- beds and rocks, each Atomic, in their own folder. Decoration but for
	-- the trees' trunks (BuildingArt.Greenery). Never tagged Tree and never
	-- in the Trees folder, so nobody can chop them, and WindSway and
	-- CanopyFade leave them be.
	step("4. Greenery", function()
		local folder = Instance.new("Folder")
		folder.Name = "TownGreenery"
		folder.Parent = map
		for _, g in ipairs(town.greenery) do
			place(atomic(BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId)), g.cframe, folder)
		end
	end)
end)

---------------------------------------------------------------------------
-- 5. The biomes
---------------------------------------------------------------------------

step("5. The trees", function()
	for _, spot in ipairs(WorldPlan.Trees()) do
		TreeService.SpawnTree(spot.woodId, CFrame.new(spot.position))
		treesSpawned += 1
	end
end)

-- Boulders: something to drive around and climb on.
step("5. The boulders", function()
	local rocks = Instance.new("Folder")
	rocks.Name = "Boulders"
	rocks.Parent = map
	local SNOWY = { Color3.fromRGB(232, 238, 245), Color3.fromRGB(200, 208, 218), Color3.fromRGB(150, 150, 156) }
	local DARK = { Color3.fromRGB(58, 52, 50), Color3.fromRGB(44, 40, 40), Color3.fromRGB(72, 64, 60) }
	for _, b in ipairs(WorldPlan.Boulders()) do
		local colors = if b.snowy then SNOWY elseif b.dark then DARK else nil
		place(
			atomic(PropArt.Rock(b.size, b.seed, colors)),
			CFrame.new(b.position) * CFrame.Angles(0, b.seed % 6, 0),
			rocks
		)
	end
end)

-- The Phantom Grove's glowing mushrooms (its tell at night).
step("5. The grove's mushrooms", function()
	for i, cf in ipairs(WorldPlan.GroveMushrooms()) do
		place(atomic(PropArt.Mushroom(i, true)), cf)
	end
end)

-- The volcano's crater: glowing lava filling the level pool on its floor,
-- smoke rising, a light the whole valley sees at night.
step("5. The volcano's crater", function()
	local pool, radius = WorldPlan.Crater()
	local lava = Kit.cylinder(
		map,
		"CraterLava",
		1,
		radius * 2,
		CFrame.new(pool + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 106, 26),
		Enum.Material.Neon
	)
	Kit.decor(lava, false)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 120, 40)
	glow.Range = 60
	glow.Brightness = 4
	glow.Parent = lava
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "VolcanoSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 64, 62), Color3.fromRGB(150, 140, 136))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 45) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(8, 14)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(10, 18)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Acceleration = Vector3.new(3, 2, 1)
	smoke.LightInfluence = 0.6
	smoke.Parent = lava
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "VolcanoEmbers"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new(0.6)
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Rate = 12
	embers.Speed = NumberRange.new(20, 34)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.Acceleration = Vector3.new(0, -14, 0)
	embers.Parent = lava
end)

-- The palm island offshore: you can see it from the beach, but there are no
-- boats yet (palmwood comes after V1). Looks only.
step("5. The palm island", function()
	local palm = WoodData.Get("palmwood")
	if palm then
		for i, pos in ipairs(WorldPlan.IslandPalms()) do
			local tree = TreeArt.Build(palm, 3000 + i, 0.9 + (i % 3) * 0.1)
			Kit.decorAll(tree)
			place(atomic(tree), CFrame.new(pos) * CFrame.Angles(0, i * 1.3, 0))
		end
	end
end)

-- Signposts where the roads arrive: the biome, its woods, the gear it needs
-- (WorldPlan.BiomeSignText, which the world preview shows too).
step("5. The road signs", function()
	for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		place(atomic(BuildingArt.Signpost(sign.text)), sign.cframe)
	end
end)

-- Open-country scenery (WLD-01): outcrops, log piles, fence and hay lines,
-- ruined cabins, windmills and lookout towers between the biomes and along
-- the haul roads (WorldPlan.Scenery). Each piece is its own Atomic model
-- under TimberlineMap.Scenery. Looks only: nothing in it collides, is
-- clicked or touched, and parts under a stud cast no shadow.
step("5. The scenery", function()
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = map
	for _, spot in ipairs(WorldPlan.Scenery()) do
		local piece = Kit.model(spot.kind)
		for _, item in ipairs(spot.items) do
			local model: Model?
			if item.builder == "Fence" then
				model = BuildingArt.Fence(item.size)
			elseif item.builder == "LogPile" or item.builder == "Haybale" then
				model = BuildingArt.Prop(item.builder, item.seed)
			else
				model = PropArt.SetPiece(item.builder, item.seed)
			end
			if model then
				Kit.placeAt(model, item.cframe)
				model.Parent = piece
			end
		end
		for _, d in ipairs(piece:GetDescendants()) do
			if d:IsA("BasePart") then
				local size = d.Size
				Kit.decor(d, if math.max(size.X, size.Y, size.Z) < 1 then false else nil)
			end
		end
		atomic(piece).Parent = folder
	end
end)

-- The landscape, a little toward Lumber Tycoon 2 (phase 10, STY-03): brown
-- boulder clusters over the open grass (WorldPlan.BoulderClusters), each
-- its own Atomic model under TimberlineMap.BoulderClusters. Their rocks
-- collide, as the lone boulders do. Each part of this step runs on its own.
step("5. The landmarks", function()
	step("5. The boulder clusters", function()
		local folder = Instance.new("Folder")
		folder.Name = "BoulderClusters"
		folder.Parent = map
		for _, spot in ipairs(WorldPlan.BoulderClusters()) do
			local cluster = Kit.model("BoulderCluster")
			for _, r in ipairs(spot.rocks) do
				local rock = LandmarkArt.BrownRock(r.size, r.seed, spot.tone, r.mossy)
				Kit.placeAt(rock, CFrame.new(r.position) * CFrame.Angles(0, r.yaw, 0))
				rock.Parent = cluster
			end
			atomic(cluster).Parent = folder
		end
	end)
end)

---------------------------------------------------------------------------
-- 6. The Skyroot and the Aether Isles
---------------------------------------------------------------------------

step("6. The Skyroot and the Aether Isles", function()
	local sky = WorldPlan.Sky()
	if not sky then
		return
	end
	local fall = sky.waterfall
	local fromRoot = WorldPlan.IslesFromRoot(sky)

	-- The Skyroot: seen from anywhere, so Persistent. Its limbs reach up
	-- into each isle, its hollow faces the gondola, it parts round the fall.
	step("6. The Skyroot", function()
		place(
			persistent(IsleArt.Skyroot(sky.trunkHeight, fromRoot, sky.main.dir, fall.top - sky.root)),
			CFrame.new(sky.root)
		)
	end)

	local islesFolder = Instance.new("Folder")
	islesFolder.Name = "AetherIsles"
	islesFolder.Parent = map
	step("6. The isles", function()
		local mainIsle = IsleArt.Isle(sky.main.radius, 1, { clear = WorldPlan.IsleClearPoints(sky, sky.main.center) })
		mainIsle.Name = "MainIsle"
		place(persistent(mainIsle), CFrame.new(sky.main.center), islesFolder)
		for i, isle in ipairs(sky.isles) do
			local options: IsleArt.IsleOptions = {
				clear = WorldPlan.IsleClearPoints(sky, isle.center),
				spout = if i == fall.isle then fall.dir else nil, -- the spring that feeds the waterfall
			}
			local model = IsleArt.Isle(isle.radius, i + 1, options)
			model.Name = "Isle" .. i
			place(persistent(model), CFrame.new(isle.center), islesFolder)
		end
	end)
	step("6. The bridges", function()
		for _, bridge in ipairs(sky.bridges) do
			local model = BuildingArt.Bridge(bridge.a, bridge.b, 6)
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			model.Parent = islesFolder
			-- A lantern at each bridge head.
			for k, at in ipairs({ bridge.a, bridge.b }) do
				local along = (bridge.b - bridge.a).Unit * (if k == 1 then 1 else -1)
				local side = Vector3.new(-along.Z, 0, along.X)
				place(
					atomic(IsleArt.LanternPost(k)),
					CFrame.lookAt(at - along * 2 + side * 4.2, at + along),
					islesFolder
				)
			end
		end
	end)

	-- Cloud banks drifting round the Skyroot's crown.
	step("6. The cloud banks", function()
		local clouds = Instance.new("Folder")
		clouds.Name = "CloudBanks"
		clouds.Parent = map
		for i, spot in ipairs(IsleArt.CloudSpots(fromRoot, sky.trunkHeight, 99, sky.main.dir)) do
			place(persistent(IsleArt.CloudBank(spot.size, i)), CFrame.new(sky.root) * spot.cframe, clouds)
		end
	end)
	step("6. The Lumenwood", function()
		for _, pos in ipairs(sky.lumenwood) do
			TreeService.SpawnTree("lumenwood", CFrame.new(pos))
			treesSpawned += 1
		end
	end)
	step("6. The Sky Shards", function()
		for _, pos in ipairs(sky.shards) do
			NodeService.Spawn("SkyShard", pos, map)
		end
	end)
	step("6. The Cloud Chutes", function()
		for _, cf in ipairs(sky.chutes) do
			local chute = BuildingArt.CloudChute()
			local box = chute:FindFirstChild("CloudChute")
			place(atomic(chute), cf)
			if box then
				CollectionService:AddTag(box, "CloudChute")
			end
			-- The flume carries on from the chute's lip (its +Z end), out off
			-- the isle and down into the clouds (WorldPlan.ChuteFlume, which
			-- the previews draw too).
			local from, to = WorldPlan.ChuteFlume(cf)
			Kit.decor(Kit.beam(map, "Flume", from, to, 2.4, 1.2, Color3.fromRGB(90, 62, 38), Enum.Material.WoodPlanks))
		end
	end)
	step("6. The Starfall Forge", function()
		local forge = BuildingArt.StarfallForge()
		local anvil = forge:FindFirstChild("StarfallForge")
		place(atomic(forge), sky.forge)
		if anvil then
			CollectionService:AddTag(anvil, "StarfallForge")
		end
	end)

	-- The gondola: from town and from the Skyroot's foot up to the top
	-- station on the main isle's town-facing edge. The cable runs 8.5 studs
	-- above the cabins' route (WorldPlan.GondolaPath), one rod per stretch.
	step("6. The gondola", function()
		local top = station("GondolaTop", sky.gondolaTop)
		local base = station("GondolaBase", sky.gondolaBase)
		local function cableFrom(model: Model)
			local platform = model.PrimaryPart :: BasePart
			local to = (top.PrimaryPart :: BasePart).Position
			local path = WorldPlan.GondolaPath(sky, platform.Position, platform.CFrame.ZVector, to)
			for _, piece in ipairs(WorldPlan.GondolaCable(path, platform.CFrame.ZVector)) do
				local cable = Kit.rod(
					map,
					"GondolaCable",
					piece[1],
					piece[2],
					0.4,
					Color3.fromRGB(70, 70, 75),
					Enum.Material.Metal
				)
				Kit.decor(cable, false)
			end
		end
		if townStation then
			cableFrom(townStation)
		end
		cableFrom(base)
	end)

	-- The waterfall pouring off an outer isle into the river's spring.
	step("6. The waterfall", function()
		place(
			persistent(IsleArt.Waterfall(fall.top.Y - fall.bottom.Y, 10)),
			CFrame.lookAt(fall.top, fall.top + fall.dir) -- its -Z away from the isle
		)
	end)
end)

---------------------------------------------------------------------------
-- 7. The edge of the world, the clock, and in you come
---------------------------------------------------------------------------

-- The backdrop (WLD-02, WLD-09): mountains, skirt and sea beyond the walls,
-- the volcano's impostor and the Skyroot's footing (WorldPlan.Backdrop).
-- Persistent, so every client always has the horizon however little of
-- the terrain it has streamed in; looks only, so nothing collides, is
-- clicked or touched, or casts a shadow.
step("7. The backdrop", function()
	local backdrop = Instance.new("Model")
	backdrop.Name = "Backdrop"
	backdrop.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, piece in ipairs(WorldPlan.Backdrop()) do
		local part: BasePart
		if piece.kind == "Wedge" then
			part = Kit.wedge(backdrop, piece.name, piece.size, piece.cframe, piece.color, piece.material)
		elseif piece.kind == "Cylinder" then
			part = Kit.cylinder(
				backdrop,
				piece.name,
				piece.size.X,
				piece.size.Y,
				piece.cframe,
				piece.color,
				piece.material
			)
		else
			part = Kit.part(backdrop, piece.name, piece.size, piece.cframe, piece.color, piece.material)
		end
		part.Transparency = piece.transparency
		Kit.decor(part, false)
	end
	backdrop.Parent = map
end)

-- Invisible walls at the edge (a part can be at most 2,048 studs long, so
-- each side is several segments; tall enough for the mountains).
step("7. The world's edge", function()
	local half = WorldLayout.WorldHalf
	local segments = 4
	local length = half * 2 / segments
	for _, edge in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local ex, ez = edge[1], edge[2]
		for i = 0, segments - 1 do
			local along = -half + length * (i + 0.5)
			local wall = Kit.part(
				map,
				"WorldEdge",
				Vector3.new(if ex ~= 0 then 4 else length + 4, 900, if ez ~= 0 then 4 else length + 4),
				CFrame.new(if ex ~= 0 then ex * half else along, 300, if ez ~= 0 then ez * half else along),
				Color3.new(1, 1, 1)
			)
			wall.Transparency = 1
			wall.CastShadow = false
		end
	end
end)

step("7. The day/night clock", function()
	WorldClock.Start()
end)

-- What the build took, for GameServer's boot report. Set before SellArea
-- goes in, so GameServer (which starts when it appears) always finds them.
local builtSeconds = os.clock() - started
workspace:SetAttribute("MapBuildSeconds", builtSeconds)
workspace:SetAttribute("MapTerrainSeconds", terrainSeconds)
workspace:SetAttribute("MapTrees", treesSpawned)
workspace:SetAttribute("MapBuildFailures", failedSteps)

-- The last three steps run whatever failed above.
-- The world is ready: GameServer starts when the sell area appears.
sellArea.Parent = map

-- The ground is in: let everyone spawn.
Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if not player.Character then
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

print(string.format("[MapBuilder] World built in %.1fs (terrain %.1fs)", builtSeconds, terrainSeconds))
