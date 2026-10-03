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
--   5. The biomes: every wild tree (BiomeData counts) on the terrain
--      (TreeService's under the v1 loop; SectionTrees' section trees,
--      most mature and some young, under v2, after the v2 wood collision
--      groups are registered),
--      boulders, the volcano's crater, the grove's glowing mushrooms, the
--      palm island offshore, signposts where the roads arrive, the
--      open country's scenery (decor set pieces), and the landscape's
--      landmarks (phase 10, STY: brown boulder clusters, a footbridge
--      over the river, two docks, a lighthouse on the coast).
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
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local IsleArt = require(ReplicatedStorage.Shared.Art.IsleArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local LandmarkArt = require(ReplicatedStorage.Shared.Art.LandmarkArt)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local NodeService = require(script.Parent.NodeService)
local SectionTrees = require(script.Parent.SectionTrees)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local TutorialGrove = require(ReplicatedStorage.Shared.TutorialGrove)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local TreeService = require(script.Parent.TreeService)
local WorldClock = require(script.Parent.WorldClock)

local started = os.clock()

-- Which core loop this server runs (V2_PLAN.md §0), decided once, before
-- anything is built: every server module and client reads CoreLoopActive.
do
	local loop =
		CoreLoop.Resolve(GameConfig.CoreLoop, workspace:GetAttribute(CoreLoop.Attribute), RunService:IsStudio())
	workspace:SetAttribute(CoreLoop.ActiveAttribute, loop)
	print(string.format("[CoreLoop] %d%s", loop, if loop ~= GameConfig.CoreLoop then " (Studio override)" else ""))
end

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
-- The v2 loop's trees are section trees (V2_PLAN.md M1.3), planted at a
-- random age so the world isn't all saplings; v1 keeps TreeService's.
local V2 = CoreLoop.V2()
local function spawnTree(woodId: string, at: Vector3)
	if V2 then
		SectionTrees.SpawnTree(woodId, CFrame.new(at), { boot = true })
	else
		TreeService.SpawnTree(woodId, CFrame.new(at))
	end
	treesSpawned += 1
end

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
		-- Players spawn facing the sawmill, on the drawn ground if it is
		-- above the town's y = 0 (TerrainBuilder.LiftOnto: never underground).
		local at = town.spawnFacing.Position
		local lift = TerrainBuilder.LiftOnto(at.X, 0, at.Z)
		spawn.CFrame = town.spawnFacing + Vector3.new(0, lift, 0)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0 -- no force field bubble
		spawn.Color = Color3.fromRGB(168, 152, 128)
		spawn.Material = Enum.Material.Cobblestone
		spawn.Parent = map
	end)

	-- The sawmill, and the sell area in front of it.
	step("4. The sawmill", function()
		-- Persistent: the mill is the landmark you steer by from the biomes.
		-- (Lookout towers, further out and numerous, use a StreamingMesh
		-- instead — see the scenery step. The lighthouse is Persistent too.
		-- Hearth & Home, the town hall, is Persistent with the other shops.)
		local sawmill = place(persistent(BuildingArt.Sawmill()), town.sawmill)
		local blade = sawmill:FindFirstChild("SawBlade", true)
		if blade then
			CollectionService:AddTag(blade, "SawBlade") -- TownFX spins it
		end
	end)

	-- The zone reaches over the street and into the mill's front (40 deep
	-- round the pad's middle, phase 12), so a big truck backed in has its
	-- whole bed in it; the prompt stays over the pad's middle.
	step("4. The sell area", function()
		local sellZone = Kit.part(sellArea, "SellZone", WorldPlan.SellZoneSize, town.sellZone, Color3.new(1, 1, 1))
		ghost(sellZone, 1)
		local sellPoint = Instance.new("Attachment") -- where the client's "Sell logs" prompt appears
		sellPoint.Name = "SellPoint"
		local padMiddle = town.sellZone:ToObjectSpace(town.sellPad).Position
		sellPoint.Position = Vector3.new(padMiddle.X, -2.5, padMiddle.Z)
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

	-- Parking lot: a slot per player and one to spare, so trucks never spawn
	-- inside each other. VehicleService gives each rig the smallest free
	-- slot it fits (it reads each slot's Index, CFrame and Size). Paint on
	-- the ground: no lip for a truck to snag on. Each slot is its bay's size
	-- (town.parkingSizes, WorldPlan.ParkingBays, phase 12): small ones for
	-- the small trucks, long pull-through ones for the big rigs.
	local slots: { BasePart } = {}
	step("4. The parking lot", function()
		for index, cf in ipairs(town.parkingSlots) do
			local slot = Kit.part(
				map,
				"ParkingSlot_" .. index,
				town.parkingSizes[index] or WorldPlan.ParkingSlotSize,
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
		-- Saw-cut rounds on the shop paths (looks only). Not on the spawn
		-- walk: that stretch stays open for the tutorial grove.
		local rounds = Instance.new("Folder")
		rounds.Name = "PathRounds"
		rounds.Parent = map
		for _, cf in ipairs(town.pathRounds) do
			place(atomic(BuildingArt.PathRound()), cf, rounds)
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

	-- A few small oaks and Murph's buy cart, west of the spawn. The cart
	-- buys one small load (SellService's gate / the v1 sell handler). The
	-- zone is a ghost: the beacon and the server read its box, and it
	-- doesn't stand on the street or Bram's walk.
	step("4. The tutorial grove", function()
		local model = Instance.new("Model")
		model.Name = "TutorialGrove"
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local spot = TutorialGrove.Cart
		place(atomic(BuildingArt.Prop("Cart", 7)), CFrame.new(spot.x, 0, spot.z), model)
		local zone =
			Kit.part(model, "CartZone", TutorialGrove.ZoneSize, TutorialGrove.CartCFrame(), Color3.new(1, 1, 1))
		ghost(zone, 1)
		local board = Kit.part(
			model,
			"Board",
			Vector3.new(4.2, 1.8, 0.2),
			CFrame.new(spot.x, 4.4, spot.z),
			Color3.fromRGB(101, 67, 33),
			Enum.Material.Wood
		)
		board.CanCollide = false
		board.CanQuery = false
		board.CastShadow = false
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.Parent = board
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "MURPH BUYS\nFirst load"
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.TextColor3 = Color3.fromRGB(255, 244, 220)
			label.Parent = gui
		end
		model.Parent = map
	end)
end)

---------------------------------------------------------------------------
-- 5. The biomes
---------------------------------------------------------------------------

step("5. The trees", function()
	if V2 then
		SectionTrees.RegisterGroups() -- Wood, WoodFalling, WoodHeld, Leaves, Players
	end
	-- The tutorial oaks: small, mature, a fixed seed. Not boot-aged, so
	-- they aren't saplings a new player can't fell. Same crystal-cut oak
	-- as the rest of the forest (section trees), so the grove matches.
	for i, spot in ipairs(TutorialGrove.Trees) do
		local ok, err = pcall(function(): any
			local y = TerrainGen.HeightAt(spot.x, spot.z) - 0.3
			local at = CFrame.new(spot.x, y, spot.z)
			local options = { size = TreeLogic.Sizes[1], seed = 4100 + i }
			local model = if V2
				then SectionTrees.SpawnTree("oak", at, options)
				else TreeService.SpawnTree("oak", at, options)
			-- A stub (the build test) may not hand back a model.
			if model then
				model:SetAttribute("TutorialGrove", true)
			end
			treesSpawned += 1
			return nil
		end)
		if not ok then
			warn(string.format("[MapBuilder] tutorial oak %d failed: %s", i, tostring(err)))
		end
	end
	local before = os.clock()
	-- One tree that fails to build (a bad seed) mustn't take the rest of
	-- the forest with it: each on its own, one warning for all of them.
	local failed, firstErr = 0, nil
	for _, spot in ipairs(WorldPlan.Trees()) do
		local ok, err = pcall(function(): any
			spawnTree(spot.woodId, spot.position)
			return nil
		end)
		if not ok then
			failed += 1
			firstErr = firstErr or string.format("%s at %s: %s", spot.woodId, tostring(spot.position), tostring(err))
		end
	end
	if failed > 0 then
		warn(string.format("[MapBuilder] %d tree(s) failed to build; the first: %s", failed, tostring(firstErr)))
	end
	if V2 then
		print(string.format("[MapBuilder] %d section trees in %.1fs", treesSpawned, os.clock() - before))
	end
end)

-- Boulders: something to drive around and climb on.
step("5. The boulders", function()
	local rocks = Instance.new("Folder")
	rocks.Name = "Boulders"
	rocks.Parent = map
	local SNOWY = { Color3.fromRGB(232, 238, 245), Color3.fromRGB(200, 208, 218), Color3.fromRGB(150, 150, 156) }
	local DARK = { Color3.fromRGB(58, 52, 50), Color3.fromRGB(44, 40, 40), Color3.fromRGB(72, 64, 60) }
	local function placeRock(b: WorldPlan.Boulder)
		-- Brown out in the green (STY-03), like the clusters and outcrops.
		local colors = if b.snowy then SNOWY elseif b.dark then DARK else PropArt.BrownTones[b.seed % 2 + 1]
		local moss = if colors ~= SNOWY and colors ~= DARK and b.seed % 3 == 0 then PropArt.Moss else nil
		place(
			atomic(PropArt.Rock(b.size, b.seed, colors, moss)),
			CFrame.new(b.position) * CFrame.Angles(0, b.seed % 6, 0),
			rocks
		)
	end
	for _, b in ipairs(WorldPlan.Boulders()) do
		placeRock(b)
	end
	for _, b in ipairs(WorldPlan.MeadowBoulders()) do
		placeRock(b)
	end
end)

-- The Gloam Hollow's glowing mushrooms (its tell at night).
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
-- boats yet (palmwood comes after V1). Looks only but for each palm's
-- trunk, which collides (COL-01), like a town tree's. Never tagged Tree.
step("5. The palm island", function()
	local palm = WoodData.Get("palmwood")
	if palm then
		for i, pos in ipairs(WorldPlan.IslandPalms()) do
			local tree = TreeArt.Build(palm, 3000 + i, 0.9 + (i % 3) * 0.1)
			Kit.decorAll(tree, { Trunk = true })
			place(atomic(tree), CFrame.new(pos) * CFrame.Angles(0, i * 1.3, 0))
		end
	end
end)

-- Signposts where the roads arrive: the biome, its woods, the gear it needs
-- (WorldPlan.BiomeSignText, which the world preview shows too). Their
-- boards collide (COL-01), 2+ studs off the road.
step("5. The road signs", function()
	for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		place(atomic(BuildingArt.Signpost(sign.text, false, true)), sign.cframe)
	end
	for _, sign in ipairs(WorldPlan.GateSigns(WorldPlan.BiomeSignText)) do
		place(atomic(BuildingArt.Signpost(sign.text, false, true)), sign.cframe)
	end
end)

-- Open-country scenery (WLD-01): outcrops, log piles, fence and hay lines,
-- ruined cabins, windmills and lookout towers between the biomes and along
-- the haul roads (WorldPlan.Scenery). Each piece is its own Atomic model
-- under TimberlineMap.Scenery. What its builder made solid collides (COL-01:
-- the stones, walls, posts, towers, fence posts and rails, bales and logs,
-- all of it 4+ studs off the roads); the rest is looks only. Nothing in it
-- is touched, and parts under a stud cast no shadow.
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
				if math.max(size.X, size.Y, size.Z) < 1 then
					d.CastShadow = false
				end
				d.CanTouch = false -- nothing listens for a set piece's touches
				if not d.CanCollide then
					Kit.decor(d) -- looks only: no clicks either
				end
			end
		end
		-- Lookout towers stay Atomic (they stream in whole when you're
		-- close). LevelOfDetail is plugin-only: a game script cannot set
		-- StreamingMesh, and trying to threw away the rest of this step.
		atomic(piece).Parent = folder
	end
end)

-- The landscape, a little toward the classic lumber-game look (phase 10, STY-03,
-- STY-04): brown boulder clusters over the open grass
-- (WorldPlan.BoulderClusters), each its own Atomic model under
-- TimberlineMap.BoulderClusters; then, under TimberlineMap.Landmarks, a
-- timber footbridge over the river with its TIMBER BRIDGE sign, plank
-- docks on Mirror Lake and the east coast with a moored rowboat each, and
-- the lighthouse on the coast's headland (Persistent: the town sees it on
-- the horizon; its "LampGlow" lights at dusk). Rocks, decks, posts, rails
-- and the tower collide; the rowboats are looks only. Each part of this
-- step runs on its own.
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
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = map
	step("5. The footbridge", function()
		local bridge = WorldPlan.Footbridge()
		if bridge then
			local model = LandmarkArt.Footbridge(bridge.span, bridge.drop, bridge.width, bridge.rise, bridge.beds)
			place(atomic(model), bridge.cframe, landmarks)
			if bridge.sign then
				place(atomic(BuildingArt.Signpost(WorldPlan.BridgeText)), bridge.sign, landmarks)
			end
		end
	end)
	step("5. The docks", function()
		for i, dock in ipairs(WorldPlan.Docks()) do
			local model = LandmarkArt.Dock(dock.length, dock.width, dock.deck, dock.water, dock.beds)
			place(atomic(model), dock.cframe, landmarks)
			place(atomic(LandmarkArt.Rowboat(i * 17)), dock.boat, landmarks)
			if dock.sign then
				place(atomic(BuildingArt.Signpost(WorldPlan.LakeDockText)), dock.sign, landmarks)
			end
		end
	end)
	step("5. The lighthouse", function()
		local lighthouse = WorldPlan.Lighthouse()
		if lighthouse then
			place(persistent(LandmarkArt.Lighthouse()), lighthouse.cframe, landmarks)
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
			spawnTree("lumenwood", pos)
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
