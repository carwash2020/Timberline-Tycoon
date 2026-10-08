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
-- warned with a traceback and the rest still builds. The last step (SellArea
-- in, which starts GameServer) always runs, so one broken builder can never
-- stop players spawning. Characters are loaded by GameServer's join flow
-- (Shared/JoinFlow), not here: CharacterAutoLoads stays false.
--
-- LOAD-02 (7 October 2026): only what a player needs to stand and play is
-- built before SellArea goes in (terrain, the town's buildings, the shops,
-- the parking lot, the gondola stations, the tutorial grove, the north
-- strip, the edge walls, the clock). Everything else is a step of the
-- deferred build (defer / deferCells below, LoadState.Queue): the town's
-- dressing and the townsfolk first, then the country (boulders, scenery,
-- points of interest, trails, landmarks, backdrop), then the sky, each
-- nearest the players first and a time slice at a time, after the first
-- player can play. Every mesh starts loading when this script starts
-- (MeshKit.Preload) so no builder waits on one.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local IsleArt = require(ReplicatedStorage.Shared.Art.IsleArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local AxeModels = require(ReplicatedStorage.Shared.Art.AxeModels)
local MeshKit = require(ReplicatedStorage.Shared.Art.MeshKit)
local MeshManifest = require(ReplicatedStorage.Shared.Art.MeshManifest)
local LoadQueue = require(ReplicatedStorage.Shared.LoadQueue)
local TimeSlice = require(ReplicatedStorage.Shared.TimeSlice)
local LoadState = require(script.Parent.LoadState)
local TownMeshes = require(ReplicatedStorage.Shared.Art.TownMeshes)
local LandmarkArt = require(ReplicatedStorage.Shared.Art.LandmarkArt)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local NodeService = require(script.Parent.NodeService)
local SectionTrees = require(script.Parent.SectionTrees)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local StoreBoard = require(ReplicatedStorage.Shared.StoreBoard)
local TutorialGrove = require(ReplicatedStorage.Shared.TutorialGrove)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local UndergroundBuilder = require(script.Parent.UndergroundBuilder)
local SecretService = require(script.Parent.SecretService)
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
-- [Load] lines (LOAD-01): seconds since this script started, per phase, and
-- how many Instances a top-level step added, so Output says where a slow
-- start went. Nested steps skip the count (GetDescendants is not free).
local stepDepth = 0
local function loadLine(what: string)
	print(string.format("[Load] +%.1fs %s", os.clock() - started, what))
end
local function step(name: string, build: () -> ())
	-- A line when a step starts and when it ends, so a stalled world build
	-- shows which step it is in (the tree planning is silent for a while).
	print(string.format("[MapBuilder] %s ...", name))
	local startedAt = os.clock()
	stepDepth += 1
	local top = stepDepth == 1
	local ok, err = xpcall(function(): any
		build()
		return nil
	end, traceback)
	stepDepth -= 1
	if ok then
		print(string.format("[MapBuilder] %s done in %.1fs", name, os.clock() - startedAt))
	end
	if top then
		loadLine(string.format("%s took %.2fs", name, os.clock() - startedAt))
	end
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

-- 2. Nobody spawns until GameServer's join flow says so (the world, the save and
-- the streamed spawn area are all ready). The flow also respawns the dead.
Players.CharacterAutoLoads = false

-- 3. Terrain.
local terrainSeconds = 0
-- Kill switch for the uploaded town meshes: GameConfig.TownMeshes, and in
-- Studio the workspace attribute TownMeshes (true/false) wins for one test run.
local townMeshesOn = GameConfig.TownMeshes
do
	local override = workspace:GetAttribute("TownMeshes")
	if RunService:IsStudio() and type(override) == "boolean" then
		townMeshesOn = override
	end
end
TownMeshes.Enabled = townMeshesOn
-- One probe load before anything is built, so a permission problem shows
-- here (and in MeshKit's warning) instead of as silent part-built art.
do
	local rusty = AxeModels.Get("RustyAxe")
	if rusty then
		local probe = MeshKit.Create(rusty.Handle.meshId, "Probe", rusty.Handle.size)
		if probe then
			probe:Destroy()
		end
	end
end
-- Every uploaded mesh the server will ask for starts loading NOW, a couple of
-- dozen at a time, while the terrain below is written (a mesh load is network
-- time, the terrain is CPU, so they overlap). Studio's log of 7 October 2026:
-- the same loads, one after another inside NPCService.Init and
-- PlotService.Init, cost 60 s and 11 s. The builders find every mesh cached.
LoadState.Stage("starting")
task.spawn(function()
	local entries = MeshManifest.Flat(townMeshesOn)
	local result = MeshKit.Preload(entries)
	LoadState.Gates.Set("meshes")
	LoadState.Line(
		string.format(
			"meshes: %d of %d loaded, %d failed in %.1fs%s",
			result.loaded,
			result.total,
			result.failed,
			result.seconds,
			if result.timedOut then " (timed out, the rest keep loading)" else ""
		)
	)
end)
print(
	"[MapBuilder] build check: uploaded town meshes "
		.. (if townMeshesOn then "ON" else "OFF (part-built town)")
		.. ", axe/tree/NPC/vehicle/kit meshes: "
		.. MeshKit.Report()
		.. ", starting plot "
		.. tostring(PlotData.Tiers[1].size)
		.. " studs"
)

step("3. Terrain", function()
	terrainSeconds = TerrainBuilder.Build(function(done: number, total: number)
		if done % 24 == 0 or done == total then
			print(string.format("[MapBuilder] Terrain %d/%d", done, total))
		end
	end)
end)
LoadState.Gates.Set("terrain")
LoadState.Stage("terrain")

step("3b. Underground", function()
	UndergroundBuilder.Build(map)
end)
SecretService.V1Init()

-- Helpers ------------------------------------------------------------------

local function place(model: Model, cf: CFrame, parent: Instance?): Model
	Kit.placeAt(model, cf)
	model.Parent = parent or map
	return model
end

-- A building never stands under the ground: if the terrain is drawn above
-- the town's y = 0 anywhere under its footprint (a 3 x 3 grid of rays), the
-- whole building goes up by that much. Nothing moves when the ground is
-- where it was written.
local function standOnGround(model: Model, quiet: boolean?): Model
	local cf, size = model:GetBoundingBox()
	local lift = 0
	for _, fx in ipairs({ -0.45, 0, 0.45 }) do
		for _, fz in ipairs({ -0.45, 0, 0.45 }) do
			local at = cf:PointToWorldSpace(Vector3.new(size.X * fx, 0, size.Z * fz))
			lift = math.max(lift, TerrainBuilder.LiftOnto(at.X, 0, at.Z, 12))
		end
	end
	if lift > 0.15 then
		if not quiet then
			print(string.format("[MapBuilder] %s was %.2f studs under the ground: lifted", model.Name, lift))
		end
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
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
local function spawnTree(woodId: string, at: Vector3, region: string, zone: WorldPlan.TreeZone?): Model?
	local model = if V2
		then SectionTrees.SpawnTree(
			woodId,
			CFrame.new(at),
			{ boot = true, zone = zone, cap = if zone then zone.cap else nil }
		)
		else TreeService.SpawnTree(woodId, CFrame.new(at))
	if model then
		model:SetAttribute("Region", region)
	end
	treesSpawned += 1
	return model
end

-- The deferred build. Steps nobody needs in the first minute (scenery,
-- boulders, points of interest, the town's greenery, the isles...) are queued
-- on LoadState.Queue and built AFTER the world is ready, tier 1 (soon seen)
-- before tier 2 (decor) before tier 3 (far or high up), nearest the players
-- first, a time slice at a time (Shared/LoadQueue, Shared/TimeSlice), so the
-- server keeps its frame rate while players are already in. A step that fails
-- warns once with a traceback and is counted, like a build step.
local function guarded(name: string, build: (slice: () -> boolean) -> ()): (slice: () -> boolean) -> ()
	return function(slice: () -> boolean)
		local ok, err = xpcall(function(): any
			build(slice)
			return nil
		end, traceback)
		if not ok then
			failedSteps += 1
			workspace:SetAttribute("MapBuildFailures", failedSteps)
			warn(string.format("[MapBuilder] %s failed, the rest of the world still builds:\n%s", name, tostring(err)))
		end
	end
end

local function defer(name: string, tier: number, at: Vector3?, build: (slice: () -> boolean) -> ())
	LoadState.Queue.Add({
		name = name,
		tier = tier,
		at = if at then { x = at.X, z = at.Z } else nil,
		run = guarded(name, build),
	})
end

-- A scattered list as one queue step per square cell of `size` studs, so the
-- cells near a player are built first.
local function deferCells<T>(
	name: string,
	tier: number,
	items: { T },
	positionOf: (item: T) -> Vector3,
	size: number,
	build: (cell: { T }, slice: () -> boolean) -> ()
)
	local cells = LoadQueue.Cells(items, function(item: T): LoadQueue.Point
		local p = positionOf(item)
		return { x = p.X, z = p.Z }
	end, size)
	for i, cell in ipairs(cells) do
		local label = string.format("%s %d/%d (%d)", name, i, #cells, #cell.items)
		LoadState.Queue.Add({
			name = label,
			tier = tier,
			at = cell.at,
			group = name,
			groupSize = #cells,
			run = guarded(label, function(slice: () -> boolean)
				build(cell.items, slice)
			end),
		})
	end
end

-- The same, for a list that costs time to work out (WorldPlan.Scenery takes
-- over a second): one step plans it (tier 1 lower so it runs first of its
-- tier, and it is its own step so the server breathes after it), and the
-- cells it finds are added to the queue then.
local function deferPlanned<T>(
	name: string,
	tier: number,
	plan: () -> { T },
	positionOf: (item: T) -> Vector3,
	size: number,
	build: (cell: { T }, slice: () -> boolean) -> ()
)
	defer(name .. " (plan)", tier, nil, function(_slice)
		deferCells(name, tier, plan(), positionOf, size, build)
	end)
end

-- The sell area beside the sawmill, east of its lean-to (the sell station).
-- SellArea is Persistent so every
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
		local sawmill = standOnGround(place(persistent(BuildingArt.Sawmill()), town.sawmill))
		local blade = sawmill:FindFirstChild("SawBlade", true)
		if blade then
			CollectionService:AddTag(blade, "SawBlade") -- TownFX spins it
		end
	end)

	-- The zone is the pad's width and 52 deep round its middle (WorldPlan.
	-- SellZoneSize), so a big truck backed in from the street has its whole
	-- bed in it; the prompt stays over the pad's middle. The station is the
	-- pad, its slots, rack, scale, Weigh House and rails.
	step("4. The sell area", function()
		local sellZone = Kit.part(sellArea, "SellZone", WorldPlan.SellZoneSize, town.sellZone, Color3.new(1, 1, 1))
		ghost(sellZone, 1)
		local sellPoint = Instance.new("Attachment") -- where the client's "Sell logs" prompt appears
		sellPoint.Name = "SellPoint"
		local padMiddle = town.sellZone:ToObjectSpace(town.sellPad).Position
		sellPoint.Position = Vector3.new(padMiddle.X, -2.5, padMiddle.Z)
		sellPoint.Parent = sellZone

		local padArt = BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth)
		place(padArt, town.sellPad, sellArea)
	end)

	-- Shops: Persistent, with a Counter whose ShopPoint is where the client's
	-- "Browse" prompt appears and what ShopService measures range from.
	step("4. The shops", function()
		for _, spot in ipairs(town.shops) do
			local shop = persistent(BuildingArt.Shop(spot.kind, spot.title, spot.accent))
			shop.Name = spot.kind
			CollectionService:AddTag(shop, "ShopDoorModel") -- ShopDoorAnim tweens its leaves
			local counter = shop:FindFirstChild("Counter")
			assert(counter and counter:IsA("BasePart"), "[MapBuilder] " .. spot.kind .. " has no Counter")
			local point = Instance.new("Attachment")
			point.Name = "ShopPoint"
			point.Position = Vector3.new(0, 0, -(counter.Size.Z / 2 + 0.5)) -- the customer's side
			point.Parent = counter
			shop.PrimaryPart = counter
			standOnGround(place(shop, spot.cframe))
		end
	end)

	-- Display lot: every truck and trailer, anchored, bought from its sign.
	-- Deferred (tier 1): nothing reads it, and it builds every truck.
	defer("4. The dealership lot", 1, town.displayLot.Position, function(_slice)
		local DealershipLot = require(ReplicatedStorage.Shared.Art.DealershipLot)
		local lot = DealershipLot.Build()
		lot.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		place(lot, town.displayLot)
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

	-- Lamps, props, signs. Deferred (tier 1, nearest the player first): the
	-- town stands without them and they are only looks, but they are what you
	-- see first, so they come before any decor out in the country.
	local rounds = Instance.new("Folder")
	rounds.Name = "PathRounds"
	rounds.Parent = map
	do
		local function around(x: number, z: number): Vector3
			return Vector3.new(x, 0, z)
		end
		defer("4. Lamps", 1, around(0, 60), function(slice)
			for _, cf in ipairs(town.lamps) do
				local lamp = BuildingArt.LampPost()
				CollectionService:AddTag(lamp, "StreetLamp") -- clients light them at night
				standOnGround(place(atomic(lamp), cf), true)
				slice()
			end
		end)
		defer("4. Fences", 1, around(0, 60), function(slice)
			for _, fence in ipairs(town.fences) do
				standOnGround(place(atomic(BuildingArt.Fence(fence.length)), fence.cframe), true)
				slice()
			end
		end)
		defer("4. Props", 1, around(0, 60), function(slice)
			for _, prop in ipairs(town.props) do
				standOnGround(place(atomic(BuildingArt.Prop(prop.name, prop.seed)), prop.cframe), true)
				slice()
			end
		end)
		defer("4. Town signs", 1, around(0, 60), function(slice)
			for _, sign in ipairs(town.signs) do
				standOnGround(place(atomic(BuildingArt.Signpost(sign.text, sign.lit)), sign.cframe), true)
				slice()
			end
		end)
		-- Saw-cut rounds on the shop paths (looks only). Not on the spawn
		-- walk: that stretch stays open for the tutorial grove.
		defer("4. Path rounds", 1, around(0, 60), function(slice)
			for _, cf in ipairs(town.pathRounds) do
				place(atomic(BuildingArt.PathRound()), cf, rounds)
				slice()
			end
		end)
	end

	-- The town's greenery: ornamental trees in stone rings, bushes, flower
	-- beds and rocks, each Atomic, in their own folder. Decoration but for
	-- the trees' trunks (BuildingArt.Greenery). Never tagged Tree and never
	-- in the Trees folder, so nobody can chop them, and WindSway and
	-- CanopyFade leave them be.
	do
		local folder = Instance.new("Folder")
		folder.Name = "TownGreenery"
		folder.Parent = map
		-- Deferred (tier 1), in plan order (a spec reads the folder by index).
		defer("4. Greenery", 1, Vector3.new(0, 0, 60), function(slice)
			for _, g in ipairs(town.greenery) do
				place(atomic(BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId)), g.cframe, folder)
				slice()
			end
		end)
	end
end)

-- The Robux store's bulletin board, off the roads and Bram's walk.
-- Persistent: the prompt has to be there when the player streams in.
step("4. The store board", function()
	local model = persistent(StoreBoard.Build())
	place(model, StoreBoard.CFrame)
end)
LoadState.Gates.Set("town")
LoadState.Stage("town")

---------------------------------------------------------------------------
-- 5. The biomes
---------------------------------------------------------------------------

-- Set by step 5: plants the world's trees (see there). Run once, after the
-- sell area under v2.
local forestPlanter: ((yielding: boolean) -> ())? = nil
local FOREST_SLICE = 0.012 -- seconds of planting per frame; the deferred queue takes as much again (LoadState.Queue), so the server keeps its frame rate

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
			local model = if V2
				then SectionTrees.SpawnTree("oak", at, {
					size = TreeLogic.Sizes[1],
					seed = 4100 + i,
					zone = { id = "tutorial", cx = -21, cz = 43, radius = 36, cap = 3 },
					cap = 3,
				})
				else TreeService.SpawnTree("oak", at, { size = TreeLogic.Sizes[1], seed = 4100 + i })
			-- A stub (the build test) may not hand back a model.
			if model then
				model:SetAttribute("TutorialGrove", true)
				model:SetAttribute("Region", "starter")
			end
			treesSpawned += 1
			return nil
		end)
		if not ok then
			warn(string.format("[MapBuilder] tutorial oak %d failed: %s", i, tostring(err)))
		end
	end
	-- The rest of the world's trees (about 1,400 with the planning) are the
	-- longest part of the build, and nobody needs them to stand up: the
	-- tutorial grove above is what a new player first meets. Under v2 they
	-- are planted AFTER the sell area goes in (so GameServer starts and the
	-- save loads meanwhile), nearest the sawmill first, a frame's worth at a
	-- time (LOAD-01). v1 (a rollback) keeps its one synchronous pass.
	local function plant(yielding: boolean)
		local before = os.clock()
		local firstCount = treesSpawned
		type Entry = { spot: WorldPlan.TreeSpot, reach: boolean, order: number }
		local entries: { Entry } = {}
		local function collect(list: { WorldPlan.TreeSpot }, reach: boolean)
			for _, spot in ipairs(list) do
				table.insert(entries, { spot = spot, reach = reach, order = #entries })
			end
		end
		-- Each planner is one block of CPU the engine cannot split, so the
		-- server gets a frame between them when it is planting after the
		-- players are in (a player's physics and remotes run in those frames).
		local function breathe()
			if yielding then
				task.wait()
			end
		end
		-- WorldPlan.Trees is the planner that costs seconds: it pauses on the
		-- time slice, so the server keeps its frames while it works.
		local planSlice = TimeSlice.new({ budget = FOREST_SLICE })
		collect(WorldPlan.Trees(if yielding then planSlice.step else nil), false)
		breathe()
		-- Strip and ferry sites share one warning, so one bad wood is still
		-- one line. Lanternwood waits until WoodData has the row (B12).
		collect(WorldPlan.StripTrees(), false)
		collect(WorldPlan.FerryPalms(), false)
		breathe()
		if WoodData.Get("lanternwood") then
			collect(WorldPlan.Lanternwood(), false)
		end
		-- The Petrified Reach, planned after the fingerprint trees, so none of
		-- those move.
		collect(WorldPlan.ReachTrees(), true)
		breathe()
		loadLine(string.format("forest planned: %d sites in %.2fs", #entries, os.clock() - before))
		if yielding then
			local hub = WorldLayout.Sawmill
			local function far(e: Entry): number
				local dx, dz = e.spot.position.X - hub.X, e.spot.position.Z - hub.Z
				return dx * dx + dz * dz
			end
			local keyed: { [Entry]: number } = {}
			for _, e in ipairs(entries) do
				keyed[e] = far(e)
			end
			table.sort(entries, function(a: Entry, b: Entry): boolean
				if keyed[a] ~= keyed[b] then
					return keyed[a] < keyed[b]
				end
				return a.order < b.order
			end)
		end
		-- One tree that fails to build (a bad seed) mustn't take the rest of
		-- the forest with it: each on its own, one warning for all of them.
		local failed, firstErr = 0, nil
		local sliceStart = os.clock()
		for _, e in ipairs(entries) do
			local spot = e.spot
			local ok, err = pcall(function(): any
				spawnTree(spot.woodId, spot.position, spot.biome, spot.zone)
				return nil
			end)
			if not ok then
				if e.reach then
					warn(string.format("[MapBuilder] reach tree failed: %s", tostring(err)))
				else
					failed += 1
					firstErr = firstErr
						or string.format("%s at %s: %s", spot.woodId, tostring(spot.position), tostring(err))
				end
			end
			if yielding and os.clock() - sliceStart > FOREST_SLICE then
				workspace:SetAttribute("MapTrees", treesSpawned)
				task.wait()
				sliceStart = os.clock()
			end
		end
		if failed > 0 then
			warn(string.format("[MapBuilder] %d tree(s) failed to build; the first: %s", failed, tostring(firstErr)))
		end
		workspace:SetAttribute("MapTrees", treesSpawned)
		if V2 then
			print(string.format("[MapBuilder] %d section trees in %.1fs", treesSpawned, os.clock() - before))
		end
		loadLine(string.format("forest planted: %d trees in %.2fs", treesSpawned - firstCount, os.clock() - before))
	end
	if not V2 then
		plant(false)
	else
		forestPlanter = plant
	end
end)

-- Boulders: something to drive around and climb on.
do
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
	deferPlanned(
		"5. The boulders",
		2,
		function(): { WorldPlan.Boulder }
			local boulders: { WorldPlan.Boulder } = {}
			for _, b in ipairs(WorldPlan.Boulders()) do
				table.insert(boulders, b)
			end
			for _, b in ipairs(WorldPlan.MeadowBoulders()) do
				table.insert(boulders, b)
			end
			return boulders
		end,
		function(b: WorldPlan.Boulder): Vector3
			return b.position
		end,
		400,
		function(cell, slice)
			for _, b in ipairs(cell) do
				placeRock(b)
				slice()
			end
		end
	)
end

-- The Gloam Hollow's glowing mushrooms (its tell at night).
do
	deferPlanned(
		"5. The grove's mushrooms",
		2,
		function(): { { i: number, cf: CFrame } }
			local indexed: { { i: number, cf: CFrame } } = {}
			for i, cf in ipairs(WorldPlan.GroveMushrooms()) do
				table.insert(indexed, { i = i, cf = cf })
			end
			return indexed
		end,
		function(m): Vector3
			return m.cf.Position
		end,
		400,
		function(cell, slice)
			for _, m in ipairs(cell) do
				place(atomic(PropArt.Mushroom(m.i, true)), m.cf)
				slice()
			end
		end
	)
end

-- Named places worth the walk: a lookout, the old ranger cabin, a cave
-- mouth, the pale cache, and the falls. Decor and a few things you can
-- stand on. Secrets live on the Secret attribute for anyone who looks.
do
	local folder = Instance.new("Folder")
	folder.Name = "PointsOfInterest"
	folder.Parent = map
	local DARK = { Color3.fromRGB(42, 36, 34), Color3.fromRGB(28, 24, 24), Color3.fromRGB(58, 48, 46) }
	deferPlanned(
		"5. Points of interest",
		2,
		WorldPlan.PointsOfInterest,
		function(poi: WorldPlan.PointOfInterest): Vector3
			return poi.cframe.Position
		end,
		500,
		function(cell, slice)
			for _, poi in ipairs(cell) do
				local model: Model
				if poi.kind == "LookoutTower" then
					model = PropArt.LookoutTower(poi.seed)
				elseif poi.kind == "RuinedCabin" then
					model = PropArt.RuinedCabin(poi.seed)
				elseif poi.kind == "Cave" then
					model = PropArt.Outcrop(poi.seed, DARK)
				elseif poi.kind == "Crystal" then
					model = PropArt.Crystal(poi.seed, Color3.fromRGB(186, 230, 255), 2.4)
				else
					model = BuildingArt.Signpost(poi.text or poi.name, false, true)
				end
				model.Name = poi.id
				model:SetAttribute("PointOfInterest", poi.name)
				model:SetAttribute("Region", poi.region)
				if poi.secret then
					model:SetAttribute("Secret", poi.secret)
				end
				place(atomic(model), poi.cframe, folder)
				slice()
			end
		end
	)
end

-- Footpaths: a short run of worn slabs. Not roads, so the haul roads and
-- the tree rules are unchanged.
do
	local folder = Instance.new("Folder")
	folder.Name = "Trails"
	folder.Parent = map
	local dirt = Color3.fromRGB(156, 94, 64) -- TerrainGen.MaterialColors.Ground, so a trail matches the earth round it
	deferPlanned(
		"5. The trails",
		2,
		WorldPlan.TrailSlabs,
		function(slab: WorldPlan.TrailSlab): Vector3
			return slab.cframe.Position
		end,
		500,
		function(cell, slice)
			for _, slab in ipairs(cell) do
				local part =
					Kit.part(folder, slab.name, Vector3.new(3.2, 0.25, 7), slab.cframe, dirt, Enum.Material.Ground)
				Kit.decor(part, false)
				slice()
			end
		end
	)
end

-- The volcano's crater: glowing lava filling the level pool on its floor,
-- smoke rising, a light the whole valley sees at night.
do
	local pool, radius = WorldPlan.Crater()
	defer("5. The volcano's crater", 3, pool, function(_slice)
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
		smoke.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
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
end

-- Toll bridge, gorge, ferry docks, the secret cave, deep water, and the
-- heat column. Palms and strip trees are planted with the other sites.
step("5. The north strip and ferry", function()
	LandmarkArt.BuildW2(map)
end)

-- Signposts where the roads arrive: the biome, its woods, the gear it needs
-- (WorldPlan.BiomeSignText, which the world preview shows too). Their
-- boards collide (COL-01), 2+ studs off the road.
do
	deferPlanned(
		"5. The road signs",
		2,
		function(): { { text: string, cframe: CFrame } }
			local signs: { { text: string, cframe: CFrame } } = {}
			for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
				table.insert(signs, sign)
			end
			for _, sign in ipairs(WorldPlan.GateSigns(WorldPlan.BiomeSignText)) do
				table.insert(signs, sign)
			end
			return signs
		end,
		function(sign): Vector3
			return sign.cframe.Position
		end,
		500,
		function(cell, slice)
			for _, sign in ipairs(cell) do
				place(atomic(BuildingArt.Signpost(sign.text, false, true)), sign.cframe)
				slice()
			end
		end
	)
end

-- Open-country scenery (WLD-01): outcrops, log piles, fence and hay lines,
-- ruined cabins, windmills and lookout towers between the biomes and along
-- the haul roads (WorldPlan.Scenery). Each piece is its own Atomic model
-- under TimberlineMap.Scenery. What its builder made solid collides (COL-01:
-- the stones, walls, posts, towers, fence posts and rails, bales and logs,
-- all of it 4+ studs off the roads); the rest is looks only. Nothing in it
-- is touched, and parts under a stud cast no shadow.
do
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = map
	deferPlanned(
		"5. The scenery",
		2,
		function(): { { spot: WorldPlan.ScenerySpot, index: number } }
			local out: { { spot: WorldPlan.ScenerySpot, index: number } } = {}
			for index, spot in ipairs(WorldPlan.Scenery()) do
				table.insert(out, { spot = spot, index = index })
			end
			return out
		end,
		function(entry): Vector3
			return entry.spot.center
		end,
		400,
		function(cell, slice)
			for _, entry in ipairs(cell) do
				local spot = entry.spot
				local piece = Kit.model(spot.kind)
				piece:SetAttribute("PlanIndex", entry.index) -- cells build nearest first, not in plan order
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
				slice()
			end
		end
	)
end

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
do
	local clusterFolder = Instance.new("Folder")
	clusterFolder.Name = "BoulderClusters"
	clusterFolder.Parent = map
	deferPlanned(
		"5. The boulder clusters",
		2,
		function(): { { spot: WorldPlan.BoulderCluster, index: number } }
			local out: { { spot: WorldPlan.BoulderCluster, index: number } } = {}
			for index, spot in ipairs(WorldPlan.BoulderClusters()) do
				table.insert(out, { spot = spot, index = index })
			end
			return out
		end,
		function(entry): Vector3
			return entry.spot.center
		end,
		400,
		function(cell, slice)
			for _, entry in ipairs(cell) do
				local spot = entry.spot
				local cluster = Kit.model("BoulderCluster")
				cluster:SetAttribute("PlanIndex", entry.index) -- cells build nearest first, not in plan order
				for _, r in ipairs(spot.rocks) do
					local rock = LandmarkArt.BrownRock(r.size, r.seed, spot.tone, r.mossy)
					Kit.placeAt(rock, CFrame.new(r.position) * CFrame.Angles(0, r.yaw, 0))
					rock.Parent = cluster
				end
				atomic(cluster).Parent = clusterFolder
				slice()
			end
		end
	)
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = map
	defer("5. The footbridge", 2, nil, function(_slice)
		local bridge = WorldPlan.Footbridge()
		if bridge then
			local model = LandmarkArt.Footbridge(bridge.span, bridge.drop, bridge.width, bridge.rise, bridge.beds)
			place(atomic(model), bridge.cframe, landmarks)
			if bridge.sign then
				place(atomic(BuildingArt.Signpost(WorldPlan.BridgeText)), bridge.sign, landmarks)
			end
		end
	end)
	defer("5. The docks", 2, nil, function(_slice)
		for i, dock in ipairs(WorldPlan.Docks()) do
			local model = LandmarkArt.Dock(dock.length, dock.width, dock.deck, dock.water, dock.beds)
			place(atomic(model), dock.cframe, landmarks)
			place(atomic(LandmarkArt.Rowboat(i * 17)), dock.boat, landmarks)
			if dock.sign then
				place(atomic(BuildingArt.Signpost(WorldPlan.LakeDockText)), dock.sign, landmarks)
			end
		end
	end)
	defer("5. The lighthouse", 2, nil, function(_slice)
		local lighthouse = WorldPlan.Lighthouse()
		if lighthouse then
			place(persistent(LandmarkArt.Lighthouse()), lighthouse.cframe, landmarks)
		end
	end)
end

---------------------------------------------------------------------------
-- 6. The Skyroot and the Aether Isles
---------------------------------------------------------------------------

-- The whole sky is deferred (tier 3: far and high up, and the gondola's
-- stations are only waited for, by GondolaService, never needed at once).
-- It is split into steps of its own so the queue can interleave them with
-- the rest, and the Lumenwood plants a tree per slice.
do
	local sky = WorldPlan.Sky()
	if sky then
		local fall = sky.waterfall
		local fromRoot = WorldPlan.IslesFromRoot(sky)

		-- The Skyroot: seen from anywhere, so Persistent. Its limbs reach up
		-- into each isle, its hollow faces the gondola, it parts round the fall.
		defer("6. The Skyroot", 3, sky.root, function(_slice)
			place(
				persistent(IsleArt.Skyroot(sky.trunkHeight, fromRoot, sky.main.dir, fall.top - sky.root)),
				CFrame.new(sky.root)
			)
		end)

		local islesFolder = Instance.new("Folder")
		islesFolder.Name = "AetherIsles"
		islesFolder.Parent = map
		defer("6. The isles", 3, sky.root, function(slice)
			local mainIsle =
				IsleArt.Isle(sky.main.radius, 1, { clear = WorldPlan.IsleClearPoints(sky, sky.main.center) })
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
				slice()
			end
		end)
		defer("6. The bridges", 3, sky.root, function(slice)
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
				slice()
			end
		end)

		-- Cloud banks drifting round the Skyroot's crown.
		defer("6. The cloud banks", 3, sky.root, function(_slice)
			local clouds = Instance.new("Folder")
			clouds.Name = "CloudBanks"
			clouds.Parent = map
			for i, spot in ipairs(IsleArt.CloudSpots(fromRoot, sky.trunkHeight, 99, sky.main.dir)) do
				place(persistent(IsleArt.CloudBank(spot.size, i)), CFrame.new(sky.root) * spot.cframe, clouds)
			end
		end)
		defer("6. The Lumenwood", 3, sky.root, function(slice)
			for _, pos in ipairs(sky.lumenwood) do
				spawnTree("lumenwood", pos, "sky", {
					id = "sky",
					cx = pos.X,
					cz = pos.Z,
					radius = 0,
					fixed = true,
					cap = 12,
				})
				slice()
			end
			workspace:SetAttribute("MapTrees", treesSpawned) -- the boot report counts the isles' trees too
		end)
		defer("6. The Sky Shards", 3, sky.root, function(slice)
			for _, pos in ipairs(sky.shards) do
				NodeService.Spawn("SkyShard", pos, map)
				slice()
			end
		end)
		defer("6. The Cloud Chutes", 3, sky.root, function(_slice)
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
				Kit.decor(
					Kit.beam(map, "Flume", from, to, 2.4, 1.2, Color3.fromRGB(90, 62, 38), Enum.Material.WoodPlanks)
				)
			end
		end)
		defer("6. The Starfall Forge", 3, sky.root, function(_slice)
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
		-- The two stations GondolaService waits for stay in the ready path (they
		-- are small); only the cable between them is deferred.
		local top: Model? = nil
		local base: Model? = nil
		step("6. The gondola stations", function()
			top = station("GondolaTop", sky.gondolaTop)
			base = station("GondolaBase", sky.gondolaBase)
		end)
		defer("6. The gondola", 3, sky.root, function(_slice)
			local topStation, baseStation = top, base
			if not topStation or not baseStation then
				error("the gondola's stations were not built")
			end
			local function cableFrom(model: Model)
				local platform = model.PrimaryPart :: BasePart
				local to = (topStation.PrimaryPart :: BasePart).Position
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
			cableFrom(baseStation)
		end)

		-- The waterfall pouring off an outer isle into the river's spring.
		defer("6. The waterfall", 3, sky.root, function(_slice)
			place(
				persistent(IsleArt.Waterfall(fall.top.Y - fall.bottom.Y, 10)),
				CFrame.lookAt(fall.top, fall.top + fall.dir) -- its -Z away from the isle
			)
		end)
	end
end

---------------------------------------------------------------------------
-- 7. The edge of the world, the clock, and in you come
---------------------------------------------------------------------------

-- The backdrop (WLD-02, WLD-09): mountains, skirt and sea beyond the walls,
-- the volcano's impostor and the Skyroot's footing (WorldPlan.Backdrop).
-- Persistent, so every client always has the horizon however little of
-- the terrain it has streamed in; looks only, so nothing collides, is
-- clicked or touched, or casts a shadow.
defer("7. The backdrop", 2, nil, function(slice)
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
		slice()
	end
	backdrop.Parent = map
end)

-- Invisible walls at the edge (a part can be at most 2,048 studs long, so
-- each side is several segments; tall enough for the mountains).
step("7. The world's edge", function()
	local half = WorldLayout.WorldHalf
	local segments = 4
	local length = half * 2 / segments
	local function wall(size: Vector3, cf: CFrame)
		local part = Kit.part(map, "WorldEdge", size, cf, Color3.new(1, 1, 1))
		part.Transparency = 1
		part.CastShadow = false
	end
	-- East, west, and south. The north side is gapped for the strip.
	for _, edge in ipairs({ { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
		local ex, ez = edge[1], edge[2]
		for i = 0, segments - 1 do
			local along = -half + length * (i + 0.5)
			wall(
				Vector3.new(if ex ~= 0 then 4 else length + 4, 900, if ez ~= 0 then 4 else length + 4),
				CFrame.new(if ex ~= 0 then ex * half else along, 300, if ez ~= 0 then ez * half else along)
			)
		end
	end
	local strip = WorldLayout.NorthStrip
	local function span(x0: number, x1: number, z: number)
		local spanLength = x1 - x0
		if spanLength <= 0 then
			return
		end
		wall(Vector3.new(spanLength, 900, 4), CFrame.new((x0 + x1) / 2, 300, z))
	end
	span(-half, strip.x0, half)
	span(strip.x1, half, half)
	local stripLength = strip.z1 - strip.z0
	local stripMidZ = (strip.z0 + strip.z1) / 2
	wall(Vector3.new(4, 900, stripLength), CFrame.new(strip.x0, 300, stripMidZ))
	wall(Vector3.new(4, 900, stripLength), CFrame.new(strip.x1, 300, stripMidZ))
	span(strip.x0, strip.x1, strip.z1)
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

-- The last step runs whatever failed above.
-- The forest is background work the summary line waits for (see LoadState).
local planter = forestPlanter
if planter then
	LoadState.Track("forest")
end

-- The world is ready: GameServer starts when the sell area appears.
LoadState.Gates.Set("world")
LoadState.Stage("world")
sellArea.Parent = map

-- The ground is in, but nobody spawns yet. CharacterAutoLoads stays off: this
-- used to turn it on and load everyone waiting here, at +6.5 s, before
-- GameServer had started its services, before the save was loaded, before the
-- plot pads and Murph existed and before the client had streamed the spawn
-- area in (Studio, 7 October: the character glitched and could not move, and
-- the plot picker could not be used). GameServer's join flow (Shared/JoinFlow)
-- loads each player's character once the first-player gates are open, the
-- spawn area is streamed in and their save is loaded, and respawns them.

print(string.format("[MapBuilder] World built in %.1fs (terrain %.1fs)", builtSeconds, terrainSeconds))
print("[MapBuilder] meshes after the build: " .. MeshKit.Report())
loadLine(string.format("world ready for players (terrain %.1fs); the forest plants next", terrainSeconds))

-- The forest, now the players can come in: planned, then planted a frame's
-- worth at a time, nearest the sawmill first. The night-only woods are
-- re-checked against the clock once it is in (they were not there when it
-- first ticked).
if planter then
	forestPlanter = nil
	task.spawn(function()
		local ok, err = xpcall(function(): any
			planter(true)
			return nil
		end, traceback)
		if not ok then
			failedSteps += 1
			workspace:SetAttribute("MapBuildFailures", failedSteps)
			warn(string.format("[MapBuilder] the forest failed, the rest of the world is up:\n%s", tostring(err)))
		end
		WorldClock.Refresh()
		LoadState.Finish("forest")
	end)
end

-- The deferred build starts now, after the players can come in: NPCs and the
-- town's dressing first, then the country, then the sky, each nearest the
-- players first (LoadState.Queue; the `[Load] deferred ...` lines say what
-- each step cost). GameServer adds the townsfolk to it as it starts.
loadLine(string.format("deferred build starts: %d steps queued", LoadState.Queue.Pending()))
LoadState.Queue.Start()
