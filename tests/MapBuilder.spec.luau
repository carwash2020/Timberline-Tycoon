--!nocheck
-- MapBuilder (PLAY-07): one broken builder never stops anyone spawning.
-- The script runs here for real (tools/loader.luau's run), with the art and
-- WorldPlan real and the heavy or Roblox-only services mocked: terrain,
-- trees, crystal nodes, the clock. Most runs leave the sky out (fast); the
-- full one keeps it.
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance

	-- Lune can't read BasePart.Position ("missing default value"; Roblox
	-- can), so the gondola cable step fails here and only here.
	local LUNE_ONLY = "missing default value"

	local function build(options)
		options = options or {}
		local s = { prints = {}, loaded = {}, order = {}, spawned = 0, autoLoads = true }
		local ws = Instance.new("Folder")
		ws.Name = "Workspace"
		local baseplate = Instance.new("Part")
		baseplate.Name = "Baseplate"
		baseplate.Parent = ws
		local templateSpawn = Instance.new("SpawnLocation")
		templateSpawn.Parent = ws
		s.workspace = ws
		s.baseplate, s.templateSpawn = baseplate, templateSpawn
		if options.loop then
			ws:SetAttribute("CoreLoop", options.loop) -- the Studio override (RunService says Studio below)
		end

		local function sellAreaIn()
			local map = ws:FindFirstChild("TimberlineMap")
			return map ~= nil and map:FindFirstChild("SellArea") ~= nil
		end
		s.sellAreaIn = sellAreaIn

		-- What stood when the world gate opened (the deferred build comes after).
		local function snapshot()
			local map = ws:FindFirstChild("TimberlineMap")
			local function count(name)
				local folder = map and map:FindFirstChild(name)
				return if folder then #folder:GetChildren() else 0
			end
			s.atReady = {
				boulders = count("Boulders"),
				scenery = count("Scenery"),
				greenery = count("TownGreenery"),
				pointsOfInterest = count("PointsOfInterest"),
				backdrop = if map and map:FindFirstChild("Backdrop") then 1 else 0,
				shops = if map and map:FindFirstChild("ToolShed") then 1 else 0,
				stations = if map and map:FindFirstChild("GondolaTop") then 1 else 0,
				parking = if map and map:FindFirstChild("ParkingSlot_1") then 1 else 0,
			}
		end

		-- Two players: one already has a character, one is waiting.
		local function player(name, hasCharacter)
			local p = { Name = name, Character = if hasCharacter then {} else nil }
			function p:LoadCharacter()
				table.insert(s.loaded, name)
			end
			return p
		end
		local players = { player("Waiting", false), player("Here", true) }
		local Players = setmetatable({}, {
			__index = function(_, key)
				if key == "CharacterAutoLoads" then
					return s.autoLoads
				elseif key == "GetPlayers" then
					return function()
						return players
					end
				end
				return nil
			end,
			__newindex = function(_, key, value)
				assert(key == "CharacterAutoLoads", "unexpected Players." .. tostring(key))
				s.autoLoads = value
				table.insert(s.order, { autoLoads = value, sellAreaIn = sellAreaIn() })
			end,
		})

		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local worldPlan = setmetatable({}, { __index = WorldPlan })
		if not options.sky then
			worldPlan.Sky = function()
				return nil
			end
		end
		for name, fn in pairs(options.worldPlan or {}) do
			worldPlan[name] = fn
		end
		local buildingArt = setmetatable(options.buildingArt or {}, { __index = t.shared("Art/BuildingArt") })

		local loader = t.loader({
			mocks = {
				BuildingArt = buildingArt,
				WorldPlan = worldPlan,
				TerrainBuilder = {
					Build = options.terrain or function(onProgress)
						onProgress(24, 24)
						return 1.25
					end,
					LiftOnto = function(_, y)
						return y
					end,
				},
				TreeService = {
					SpawnTree = function()
						s.spawned += 1
						s.treeBeforeSellArea = (s.treeBeforeSellArea ~= false) and not sellAreaIn()
					end,
				},
				-- The v2 loop's section trees (M1.3).
				SectionTrees = {
					SpawnTree = function(woodId, _cf, opts)
						if options.failWood == woodId then
							error("a bad seed")
						end
						s.sectionSpawned = (s.sectionSpawned or 0) + 1
						if type(opts) == "table" and opts.seed ~= nil then
							s.tutorialBeforeSellArea = (s.tutorialBeforeSellArea ~= false) and not sellAreaIn()
						end
						s.sectionWoods = s.sectionWoods or {}
						s.sectionWoods[woodId] = (s.sectionWoods[woodId] or 0) + 1
						-- The tutorial oaks carry a fixed seed and stay mature. A
						-- world site is { boot = true }; forgetting that still fails.
						local tutorial = type(opts) == "table" and opts.seed ~= nil
						if not tutorial then
							s.sectionBoot = (s.sectionBoot ~= false) and opts ~= nil and opts.boot == true
							s.groupsFirst = (s.groupsFirst ~= false) and s.groups == true
							-- The isles' lumenwood goes in with the sky; every other
							-- site is planted once SellArea is in (LOAD-01).
							if woodId == "lumenwood" then
								s.skyBeforeSellArea = (s.skyBeforeSellArea ~= false) and not sellAreaIn()
							else
								s.forestAfterSellArea = (s.forestAfterSellArea ~= false) and sellAreaIn()
								s.forestOrder = s.forestOrder or {}
								table.insert(s.forestOrder, _cf.Position)
							end
						end
					end,
					RegisterGroups = function()
						s.groups = true
						return true
					end,
				},
				NodeService = { Spawn = function() end },
				UndergroundBuilder = { Build = function() end },
				SecretService = { V1Init = function() end },
				WorldClock = {
					Start = function()
						s.clockStarted = true
						s.clockBeforeSellArea = not sellAreaIn()
					end,
					Refresh = function()
						s.clockRefreshed = (s.clockRefreshed or 0) + 1
						s.refreshedAfterForest = s.sectionSpawned
					end,
				},
			},
			services = {
				Players = Players,
				RunService = {
					IsStudio = function()
						return options.loop ~= nil
					end,
					IsServer = function()
						return true
					end,
				},
			},
			globals = {
				workspace = ws,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function()
						s.yields = (s.yields or 0) + 1
					end,
				},
				print = function(...)
					table.insert(s.prints, table.concat({ ... }, " "))
				end,
			},
		})
		local LoadState = loader:load("ServerScriptService/LoadState")
		LoadState.Gates.OnReady("world", snapshot)
		loader:run("ServerScriptService/MapBuilder.server")
		s.warnings = {}
		for _, line in ipairs(loader.warnings) do
			if not string.find(line, LUNE_ONLY, 1, true) then
				table.insert(s.warnings, line)
			end
		end
		s.allWarnings = loader.warnings
		s.map = ws:FindFirstChild("TimberlineMap")
		s.sellArea = s.map and s.map:FindFirstChild("SellArea")
		return s
	end

	-- The three steps that must always run, whatever failed before them.
	local function lastStepsRan(s)
		t.ok(s.map, "TimberlineMap is built")
		t.ok(s.sellArea and s.sellArea.Parent == s.map, "SellArea is parented to TimberlineMap")
		-- Join race fix: MapBuilder turns CharacterAutoLoads off before the
		-- ground exists and never back on, and loads nobody. GameServer's join
		-- flow (Shared/JoinFlow) spawns each player once the first-player
		-- gates are open, their save is loaded and the spawn area is streamed.
		t.eq(s.autoLoads, false, "CharacterAutoLoads stays off: the join flow owns spawning")
		t.eq(s.order, { { autoLoads = false, sellAreaIn = false } }, "off before the ground, and nothing turns it on")
		t.eq(s.loaded, {}, "MapBuilder loads no character (it used to, at +6.5 s, before the save and the pads)")
	end

	-- Palms and the north-strip stands. Lanternwood is planted only once
	-- WoodData has the row (B12).
	local function extraTrees(WorldPlan)
		local WoodData = t.shared("WoodData")
		local n = #WorldPlan.StripTrees() + #WorldPlan.FerryPalms()
		if WoodData.Get("lanternwood") then
			n += #WorldPlan.Lanternwood()
		end
		return n
	end

	-- The deferred build makes scenery pieces and boulder clusters nearest the
	-- players first, so a folder's children are not in plan order: each model
	-- carries its PlanIndex.
	local function inPlanOrder(folder)
		local models = folder:GetChildren()
		table.sort(models, function(a, b)
			return a:GetAttribute("PlanIndex") < b:GetAttribute("PlanIndex")
		end)
		return models
	end

	local function builtLine(s)
		for _, line in ipairs(s.prints) do
			if string.find(line, "World built", 1, true) then
				return line
			end
		end
		return nil
	end

	t.test("a clean build warns nothing, parents SellArea last and lets everyone in", function()
		local s = build()
		t.eq(s.warnings, {})
		lastStepsRan(s)
		t.ok(s.sellArea:FindFirstChild("SellZone"), "SellZone")
		t.ok(s.sellArea:FindFirstChild("SellZone"):FindFirstChild("SellPoint"), "SellPoint")
		-- The sell station beside the mill: the zone is the pad's width (28)
		-- and 52 deep round the pad's middle (53, 111), z 85 to 137, east of
		-- the mill's lean-to; the prompt sits over the pad's middle, and the
		-- station's art (pad, Weigh House, rack) is in the SellArea with it.
		do
			local zone = s.sellArea:FindFirstChild("SellZone")
			local c, size = zone.CFrame.Position, zone.Size
			t.ok(math.abs(size.X - 28) < 1e-4 and math.abs(size.Z - 52) < 1e-4, "the sell zone is 28 x 52")
			t.ok(math.abs(c.Z - 111) < 1e-4, "its middle at z 111")
			t.ok(math.abs(c.Z + size.Z / 2 - 137) < 1e-4 and math.abs(c.Z - size.Z / 2 - 85) < 1e-4, "z 85 to 137")
			t.ok(math.abs(c.X - 53) < 1e-4, "east of the mill, at x 53")
			local point = zone.CFrame * zone:FindFirstChild("SellPoint").Position
			t.ok(math.abs(point.X - 53) < 1e-4 and math.abs(point.Z - 111) < 1e-4, "the prompt over the pad's middle")
			t.ok(s.sellArea:FindFirstChild("SellPad", true), "the station's pad is in the sell area")
			t.ok(s.sellArea:FindFirstChild("WeighHouse", true), "and its Weigh House")
			t.ok(zone.CanCollide == false and zone.CanQuery == false and zone.Transparency == 1, "a ghost")
		end
		t.ok(s.clockStarted, "the clock started")
		t.ok(s.clockBeforeSellArea, "the clock (the last build step) starts before SellArea goes in")
		t.ok(s.tutorialBeforeSellArea, "the tutorial oaks spawn before SellArea goes in")
		t.ok(s.forestAfterSellArea, "the forest follows SellArea (LOAD-01)")
		t.ok(s.baseplate.Parent == nil and s.templateSpawn.Parent == nil, "the template's Baseplate and spawn go")
		t.ok(s.map:FindFirstChild("SpawnLocation"), "our spawn is built")
		-- TWN-03: the pad is turned to WorldPlan's spawnFacing (toward the
		-- sawmill), keeping its size, place and Neutral.
		local spawn = s.map:FindFirstChild("SpawnLocation")
		local facing = t.load("ReplicatedStorage/Shared/World/WorldPlan").Town().spawnFacing
		t.ok((spawn.CFrame.Position - facing.Position).Magnitude < 1e-4, "the spawn pad stays at town.spawn")
		t.ok(spawn.CFrame.LookVector:Dot(facing.LookVector) > 0.99999, "the spawn pad faces spawnFacing's way")
		t.ok(spawn.CFrame.UpVector.Y > 0.99999, "the spawn pad lies flat")
		t.ok(spawn.Size == roblox.Vector3.new(6, 1, 6), "the spawn pad stays 6 x 1 x 6")
		t.eq(spawn.Neutral, true)
	end)

	t.test("LOAD-02: at the moment everyone is let in only the essentials stand; the decor follows", function()
		local s = build({ sky = true })
		-- What a player needs to stand and play was built first.
		t.eq(s.atReady.shops, 1, "the shops")
		t.eq(s.atReady.parking, 1, "the parking lot (VehicleService reads its slots)")
		t.eq(s.atReady.stations, 1, "the gondola stations GondolaService waits for")
		-- Everything else is a deferred step, built after SellArea.
		t.eq(s.atReady.boulders, 0, "no boulders yet")
		t.eq(s.atReady.scenery, 0, "no scenery yet")
		t.eq(s.atReady.greenery, 0, "no greenery yet")
		t.eq(s.atReady.pointsOfInterest, 0, "no points of interest yet")
		t.eq(s.atReady.backdrop, 0, "no backdrop yet")
		-- ...and all of it is there once the queue has run.
		t.ok(#s.map.Boulders:GetChildren() > 0, "the boulders came")
		t.ok(#s.map.Scenery:GetChildren() > 0, "the scenery came")
		t.ok(#s.map.TownGreenery:GetChildren() > 0, "the greenery came")
		t.ok(#s.map.PointsOfInterest:GetChildren() > 0, "the points of interest came")
		t.ok(s.map:FindFirstChild("Backdrop"), "the backdrop came")
		t.ok(s.map:FindFirstChild("AetherIsles"), "the isles came")
		-- A [Load] line says each deferred step's cost, and the queue says when it starts.
		local deferred, started = 0, false
		for _, line in ipairs(s.prints) do
			if string.find(line, "[Load] deferred ", 1, true) then
				deferred += 1
			end
			if string.find(line, "deferred build starts", 1, true) then
				started = true
			end
		end
		t.ok(started, "the start of the deferred build is printed")
		t.ok(deferred >= 10, deferred .. " [Load] deferred lines")
	end)

	t.test("the milestones the client's loading bar reads: the world is the last one before the services", function()
		local s = build()
		t.eq(s.workspace:GetAttribute("LoadStage"), "world")
	end)

	t.test(
		"the town's greenery: Atomic, in its own folder, never a Tree and never in the Trees folder (TWN-01)",
		function()
			local s = build()
			t.eq(s.warnings, {})
			local town = t.load("ReplicatedStorage/Shared/World/WorldPlan").Town()
			local folder = s.map:FindFirstChild("TownGreenery")
			t.ok(folder and folder:IsA("Folder"), "a TownGreenery folder in TimberlineMap")
			t.eq(#folder:GetChildren(), #town.greenery, "one model per piece")
			local trees = 0
			for i, model in ipairs(folder:GetChildren()) do
				local g = town.greenery[i]
				t.ok(model:IsA("Model"), model.Name .. " is a Model")
				t.eq(model.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, model.Name .. " streams Atomic")
				-- No attributes (no HP, no WoodId) but the loader's own pivot note.
				for name in pairs(model:GetAttributes()) do
					t.eq(name, "__pivot", model.Name .. " has an attribute")
				end
				if g.kind == "tree" then
					trees += 1
					t.eq(model.Name, "TownTree")
					local trunk = model.PrimaryPart
					t.ok(trunk and trunk.Name == "Trunk", "a town tree's PrimaryPart is its Trunk")
					-- Where WorldPlan says, its trunk standing on the spot.
					local base = trunk.CFrame.Position - roblox.Vector3.new(0, trunk.Size.X / 2, 0)
					t.ok((base - g.cframe.Position).Magnitude < 1e-3, "a town tree stands on its spot")
				end
				-- Only a tree's Trunk and a rock's stones (COL-01) collide.
				local solidName = if g.kind == "tree" then "Trunk" elseif g.kind == "rock" then "Rock" else nil
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide then
						t.eq(d.Name, solidName, model.Name .. "'s " .. d.Name .. " collides")
					end
				end
			end
			t.ok(trees >= 20, "the town's trees are built")
			-- Nothing in the map is tagged Tree (TreeService, mocked here, tags
			-- the wild ones), and the greenery never goes in a Trees folder.
			for _, d in ipairs(s.map:GetDescendants()) do
				t.ok(not d:HasTag("Tree"), d:GetFullName() .. " is tagged Tree")
			end
			t.ok(
				folder:FindFirstAncestor("Trees") == nil and folder.Parent == s.map,
				"TownGreenery sits in TimberlineMap"
			)
			t.ok(s.map:FindFirstChild("Trees") == nil or #s.map.Trees:GetChildren() == 0, "no town tree in Trees")
		end
	)

	t.test("every town marker's part is in the built map, where TownMarkers looks (TWN-04)", function()
		local s = build()
		local client = t.loader({
			services = {
				CollectionService = {},
				Players = { LocalPlayer = {} },
				GuiService = {},
				TextChatService = {},
				TweenService = {},
				UserInputService = {},
			},
		})
		local TownMarkers = client:load("StarterPlayer/StarterPlayerScripts/TownMarkers")
		t.eq(#TownMarkers.Markers, 6)
		for _, marker in ipairs(TownMarkers.Markers) do
			local at = s.map
			for _, name in ipairs(marker.path) do
				at = at and at:FindFirstChild(name)
			end
			t.ok(
				at and at:IsA("BasePart"),
				marker.name .. ": TimberlineMap." .. table.concat(marker.path, ".") .. " is a part"
			)
			-- Its model is Persistent: always streamed in on every client.
			local model = s.map:FindFirstChild(marker.path[1])
			t.eq(
				model.ModelStreamingMode,
				roblox.Enum.ModelStreamingMode.Persistent,
				marker.path[1] .. " is Persistent"
			)
		end
	end)

	t.test("the parking lot: every ParkingSlot as VehicleService reads it, painted and lit (TWN-06)", function()
		local s = build()
		t.eq(#s.warnings, 0, table.concat(s.warnings, "\n"))
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local town = WorldPlan.Town()
		local plan = town.parkingSlots
		t.eq(#plan, 13, "13 bays planned: one for each player a server holds, and one to spare")
		t.eq(#town.parkingSizes, #plan, "a size for every bay")
		for index, cf in ipairs(plan) do
			local slot = s.map:FindFirstChild("ParkingSlot_" .. index)
			t.ok(slot and slot:IsA("BasePart"), "ParkingSlot_" .. index .. " is built")
			t.ok(slot:HasTag("ParkingSlot"), "slot " .. index .. " is tagged")
			t.eq(slot:GetAttribute("Index"), index)
			t.ok(
				(slot.CFrame.Position - cf.Position).Magnitude < 1e-3
					and slot.CFrame.LookVector:Dot(cf.LookVector) > 0.9999,
				"slot " .. index .. " sits where WorldPlan puts it"
			)
			-- Its bay's size (phase 12: VehicleService fits each rig to the
			-- slots' Size.X and Size.Z); Size.Y is what it reads to find the
			-- ground under it.
			local want = town.parkingSizes[index]
			t.ok((slot.Size - want).Magnitude < 1e-4, "slot " .. index .. " size")
			t.ok(math.abs(slot.Size.Y - 0.2) < 1e-4, "slot " .. index .. " is 0.2 thick")
			t.ok(math.abs(slot.CFrame.Y - slot.Size.Y / 2) < 1e-4, "slot " .. index .. " lies on the ground")
			t.eq(slot.Transparency, 1)
			local glows = 0
			for _, d in ipairs(slot:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(not d.CanCollide and not d.CanQuery, "slot " .. index .. "'s " .. d.Name .. " is looks-only")
					if d.Name == "LanternGlow" then
						glows += 1
					end
				end
			end
			t.ok(glows > 0, "slot " .. index .. " has its lamp")
		end
	end)

	t.test("a broken parking-bay builder costs no slot: every ParkingSlot is still built and tagged", function()
		local s = build({
			buildingArt = {
				ParkingBay = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "4. The parking lot's lines and lamps", 1, true), s.warnings[1])
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		for index in ipairs(WorldPlan.Town().parkingSlots) do
			local slot = s.map:FindFirstChild("ParkingSlot_" .. index)
			t.ok(slot and slot:HasTag("ParkingSlot"), "ParkingSlot_" .. index)
		end
		lastStepsRan(s)
	end)

	t.test("the build line has the shape WLD-03 and the checklist read, and the stats are published", function()
		local s = build({ loop = 1 }) -- TreeService's stub counts the spawns
		local line = builtLine(s)
		t.ok(line, "a World built line")
		t.ok(
			string.match(line, "^%[MapBuilder%] World built in %d+%.%ds %(terrain %d+%.%ds%)$"),
			"shape: " .. tostring(line)
		)
		t.ok(string.find(line, "(terrain 1.2s)", 1, true) or string.find(line, "(terrain 1.3s)", 1, true), line)
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local TutorialGrove = t.shared("TutorialGrove")
		local extra = extraTrees(WorldPlan)
		t.eq(s.spawned, #WorldPlan.Trees() + #WorldPlan.ReachTrees() + #TutorialGrove.Trees + extra)
		t.eq(
			s.workspace:GetAttribute("MapTrees"),
			#WorldPlan.Trees() + #WorldPlan.ReachTrees() + #TutorialGrove.Trees + extra
		)
		t.eq(s.workspace:GetAttribute("MapTerrainSeconds"), 1.25)
		t.eq(s.workspace:GetAttribute("MapBuildFailures"), 0)
		t.ok(type(s.workspace:GetAttribute("MapBuildSeconds")) == "number", "MapBuildSeconds")
	end)

	t.test("v2 loop (M1.3): section trees on every site, groups first, at a boot age, before SellArea", function()
		local s = build({ loop = 2, sky = true })
		t.eq(s.warnings, {})
		lastStepsRan(s)
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local sky = WorldPlan.Sky()
		t.eq(s.spawned, 0, "no TreeService trees under v2")
		local TutorialGrove = t.shared("TutorialGrove")
		t.eq(
			s.sectionSpawned,
			#WorldPlan.Trees() + #WorldPlan.ReachTrees() + #sky.lumenwood + #TutorialGrove.Trees + extraTrees(WorldPlan),
			"every site, the isles' lumenwood, the tutorial oaks, and the strip and ferry"
		)
		t.eq(s.workspace:GetAttribute("MapTrees"), s.sectionSpawned)
		t.eq(s.workspace:GetAttribute("CoreLoopActive"), 2)
		t.ok(s.groupsFirst, "the collision groups are registered before the first tree")
		t.ok(s.sectionBoot, "every site planted at a boot age")
		t.ok(s.tutorialBeforeSellArea, "the tutorial oaks stand before SellArea goes in")
		t.ok(not s.skyBeforeSellArea, "the isles' lumenwood is a deferred step: it stands after SellArea goes in")
		t.ok(s.forestAfterSellArea, "the forest is planted after SellArea (LOAD-01), so players need not wait for it")
		t.eq(s.clockRefreshed, 1, "the night-only woods are re-checked once the forest is in")
		t.ok(
			s.refreshedAfterForest == s.sectionSpawned - #sky.lumenwood,
			"...after the last tree of the forest (the isles' lumenwood is planted later, by the deferred sky)"
		)
		-- Nearest the sawmill first: the forest comes in as a spiral out, not in plan order.
		local hub = t.shared("World/WorldLayout").Sawmill
		local last, ordered = -1, true
		for _, p in ipairs(s.forestOrder) do
			local d = (p.X - hub.X) ^ 2 + (p.Z - hub.Z) ^ 2
			ordered = ordered and d >= last
			last = d
		end
		t.ok(ordered, "world trees are planted nearest the sawmill first")
		t.eq(s.sectionWoods.lumenwood >= #sky.lumenwood, true)
	end)

	t.test("a live server (no Studio override) builds the v2 loop's section trees", function()
		local s = build()
		t.eq(s.workspace:GetAttribute("CoreLoopActive"), 2)
		t.eq(s.spawned or 0, 0, "no TreeService trees")
		t.ok((s.sectionSpawned or 0) > 0, "section trees")
	end)

	t.test("a tree that fails to build doesn't stop the rest: one warning for all of them", function()
		local s = build({ failWood = "birch" })
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local birches = 0
		for _, spot in ipairs(WorldPlan.Trees()) do
			if spot.woodId == "birch" then
				birches += 1
			end
		end
		t.ok(birches > 0, "the plan has birches")
		local stripBirch = 0
		for _, spot in ipairs(WorldPlan.StripTrees()) do
			if spot.woodId == "birch" then
				stripBirch += 1
			end
		end
		local TutorialGrove = t.shared("TutorialGrove")
		t.eq(
			s.sectionSpawned,
			#WorldPlan.Trees()
				- birches
				+ #WorldPlan.ReachTrees()
				+ #TutorialGrove.Trees
				+ extraTrees(WorldPlan)
				- stripBirch,
			"every other tree, plus the grove, the reach, and the strip and ferry"
		)
		local found = 0
		for _, line in ipairs(s.allWarnings) do
			if string.find(tostring(line), "tree(s) failed to build", 1, true) then
				found += 1
			end
		end
		t.eq(found, 1)
	end)

	t.test("v1 loop (a rollback, or Studio's CoreLoop = 1): TreeService's trees, SectionTrees untouched", function()
		local s = build({ loop = 1 })
		t.eq(s.sectionSpawned, nil)
		t.eq(s.groups, nil, "no v2 collision groups on a v1 server")
		t.eq(s.workspace:GetAttribute("CoreLoopActive"), 1)
	end)

	t.test("an erroring BuildingArt builder: one warning, the rest of the town, SellArea, spawning", function()
		local s = build({
			buildingArt = {
				Sawmill = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1, "exactly one warning")
		t.ok(string.find(s.warnings[1], "[MapBuilder] 4. The sawmill failed", 1, true), s.warnings[1])
		t.ok(string.find(s.warnings[1], "function step", 1, true), "with a traceback: " .. s.warnings[1])
		lastStepsRan(s)
		t.ok(s.sellArea:FindFirstChild("SellZone"), "the sell zone still exists (GameServer waits on it)")
		for _, shop in ipairs({ "ToolShed", "Dealership", "HearthAndHome", "GondolaTown" }) do
			t.ok(s.map:FindFirstChild(shop), shop .. " still built")
		end
		t.ok(s.map:FindFirstChild("ParkingSlot_1"), "the parking lot still built")
		t.ok(s.map:FindFirstChild("Boulders"), "the biomes still built")
		t.eq(s.workspace:GetAttribute("MapBuildFailures"), 1)
		t.ok(builtLine(s), "still prints the build line")
	end)

	t.test("a builder used in a loop fails its step once, not once per use", function()
		local s = build({
			buildingArt = {
				LampPost = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "4. Lamps", 1, true), s.warnings[1])
		lastStepsRan(s)
	end)

	t.test("terrain failing still builds the town and lets everyone in", function()
		local s = build({
			terrain = function()
				error("terrain broke")
			end,
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "3. Terrain failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.ok(s.sellArea:FindFirstChild("SellZone"), "SellZone")
		t.eq(s.workspace:GetAttribute("MapTerrainSeconds"), 0)
	end)

	t.test("the whole town failing (WorldPlan.Town) still parents an empty SellArea and spawns", function()
		local s = build({
			worldPlan = {
				Town = function()
					error("no town")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "4. The town failed", 1, true), s.warnings[1])
		lastStepsRan(s)
	end)

	t.test("a non-string error still warns with a readable message", function()
		local s = build({
			buildingArt = {
				Campsite = function()
					error({ reason = "table" })
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "4. Murph's camp failed", 1, true), s.warnings[1])
		t.ok(not string.find(s.warnings[1], "error in error handling", 1, true), s.warnings[1])
		lastStepsRan(s)
	end)

	t.test("road signs and Cloud Chute flumes come from WorldPlan, the way the previews draw them", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local signText = nil
		local s = build({
			sky = true,
			worldPlan = {
				RoadSigns = function(text)
					signText = text
					return WorldPlan.RoadSigns(text)
				end,
			},
		})
		lastStepsRan(s)
		t.ok(signText, "the road signs are built")
		for _, id in ipairs({ "hills", "snow", "volcano", "sky" }) do
			t.eq(signText(id), WorldPlan.BiomeSignText(id), id .. "'s sign")
		end
		-- COL-01: the road signs' boards collide; the town's signposts' boards
		-- don't (people walk under TO THE WOODS's, a rig drives under SELL
		-- LOGS HERE's), and no signpost's rocks do.
		local road = {}
		-- The gate signs (snow, volcano, grove) use the same boards as the
		-- road signs, so their boards collide too. Town signs stay open.
		for _, id in ipairs({ "hills", "snow", "volcano", "sky", "grove" }) do
			road[WorldPlan.BiomeSignText(id)] = true
		end
		local boards, solidBoards = 0, 0
		for _, model in ipairs(s.map:GetChildren()) do
			if model.Name == "Signpost" then
				local board = model:FindFirstChild("Board")
				local label = board and board:FindFirstChildWhichIsA("TextLabel", true)
				local text = if label then label.Text else "?"
				boards += 1
				t.eq(board.CanCollide, road[text] == true, text .. "'s board collides")
				if board.CanCollide then
					solidBoards += 1
				end
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Rock" then
						t.ok(not d.CanCollide, text .. "'s rock collides")
					end
				end
			end
		end
		t.eq(solidBoards, 7, "the four road signs and the three gate signs")
		t.ok(boards >= 8, boards .. " signposts")
		-- One flume per chute, along WorldPlan.ChuteFlume (out off the isle).
		local flumes = {}
		for _, child in ipairs(s.map:GetChildren()) do
			if child.Name == "Flume" then
				table.insert(flumes, child)
			end
		end
		local chutes = WorldPlan.Sky().chutes
		t.eq(#flumes, #chutes)
		for i, cf in ipairs(chutes) do
			local from, to = WorldPlan.ChuteFlume(cf)
			local found = false
			for _, flume in ipairs(flumes) do
				local at = flume.CFrame
				if (at.Position - (from + to) / 2).Magnitude < 1e-3 then
					found = true
					t.ok(
						at.LookVector:Dot((to - from).Unit) > 0.9999,
						"chute " .. i .. ": the flume runs from its lip out"
					)
					t.ok(math.abs(flume.Size.Z - (to - from).Magnitude) < 1e-3, "chute " .. i .. ": the flume's length")
				end
			end
			t.ok(found, "chute " .. i .. " has its flume")
		end
	end)

	t.test("the full world with the sky: an erroring sky builder is contained too", function()
		local s = build({
			sky = true,
			buildingArt = {
				StarfallForge = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "6. The Starfall Forge failed", 1, true), s.warnings[1])
		-- The only other failure is the gondola cable, and only because Lune
		-- can't read BasePart.Position.
		for _, line in ipairs(s.allWarnings) do
			t.ok(
				line == s.warnings[1] or string.find(line, "[MapBuilder] 6. The gondola failed", 1, true),
				"unexpected warning: " .. line
			)
		end
		lastStepsRan(s)
		local isles = s.map:FindFirstChild("AetherIsles")
		t.ok(isles and isles:FindFirstChild("MainIsle"), "the isles are built")
		t.ok(s.map:FindFirstChild("GondolaTop") and s.map:FindFirstChild("GondolaBase"), "the sky stations")
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local TutorialGrove = t.shared("TutorialGrove")
		t.eq(
			s.workspace:GetAttribute("MapTrees"),
			#WorldPlan.Trees()
				+ #WorldPlan.ReachTrees()
				+ #WorldPlan.Sky().lumenwood
				+ #TutorialGrove.Trees
				+ extraTrees(WorldPlan)
		)
	end)

	t.test(
		"the backdrop: one Persistent model of decor parts, as WorldPlan.Backdrop() lays them out (WLD-02)",
		function()
			local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
			local s = build()
			t.eq(s.warnings, {})
			lastStepsRan(s)
			local backdrop = s.map:FindFirstChild("Backdrop")
			t.ok(backdrop and backdrop:IsA("Model"), "a Backdrop model in the map")
			t.eq(backdrop.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
			local pieces = WorldPlan.Backdrop()
			local parts = backdrop:GetChildren()
			t.eq(#parts, #pieces)
			for i, piece in ipairs(pieces) do
				local part = parts[i]
				local class = if piece.kind == "Wedge" then "WedgePart" else "Part"
				t.eq(part.ClassName, class)
				if piece.kind == "Cylinder" then
					t.eq(part.Shape, roblox.Enum.PartType.Cylinder)
				elseif class == "Part" then
					t.eq(part.Shape, roblox.Enum.PartType.Block)
				end
				t.eq(part.Name, piece.name)
				t.ok((part.CFrame.Position - piece.cframe.Position).Magnitude < 1e-4, piece.name .. " placed")
				t.ok(part.CFrame.LookVector:Dot(piece.cframe.LookVector) > 0.99999, piece.name .. " turned")
				t.ok(part.CFrame.UpVector:Dot(piece.cframe.UpVector) > 0.99999, piece.name .. " turned")
				t.ok((part.Size - piece.size).Magnitude < 1e-4, piece.name .. " sized")
				t.eq(part.Color, piece.color)
				t.eq(part.Material, piece.material)
				t.ok(math.abs(part.Transparency - piece.transparency) < 1e-6, piece.name .. " transparency")
				-- Looks only: never collides, clicked, touched or shadowed.
				t.eq(part.Anchored, true)
				t.eq(part.CanCollide, false)
				t.eq(part.CanQuery, false)
				t.eq(part.CanTouch, false)
				t.eq(part.CastShadow, false)
			end
		end
	)

	t.test("an erroring backdrop fails its step alone: the rest of the world, SellArea, spawning", function()
		local s = build({
			worldPlan = {
				Backdrop = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "[MapBuilder] 7. The backdrop failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.ok(s.map:FindFirstChild("Backdrop") == nil, "no half-built backdrop")
		t.ok(s.map:FindFirstChild("WorldEdge"), "the walls still built")
		t.ok(s.clockStarted, "the clock still started")
	end)

	t.test(
		"the scenery: an Atomic model per WorldPlan.Scenery piece in a Scenery folder; what looks solid collides (WLD-01, COL-01)",
		function()
			local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
			local s = build()
			t.eq(s.warnings, {})
			lastStepsRan(s)
			local folder = s.map:FindFirstChild("Scenery")
			t.ok(folder and folder:IsA("Folder"), "a Scenery folder in TimberlineMap")
			local spots = WorldPlan.Scenery()
			local models = inPlanOrder(folder)
			t.eq(#models, #spots)
			-- What collides in each kind of piece (its builders' big bodies), and
			-- one thing each kind always has that stops you.
			local SOLID = {
				Outcrop = { Rock = true },
				RuinedCabin = {
					Footing = true,
					Floor = true,
					WallLog = true,
					CornerPost = true,
					Chimney = true,
					FallenRoof = true,
				},
				Windmill = { MillBase = true, Tower = true },
				LookoutTower = { Leg = true, Deck = true, Rail = true, Ladder = true },
				LogPile = { Log = true },
				FenceLine = { Post = true, Rail = true, Haybale = true },
				HayLine = { Haybale = true },
			}
			local MUST = {
				Outcrop = "Rock",
				RuinedCabin = "WallLog",
				Windmill = "Tower",
				LookoutTower = "Leg",
				LogPile = "Log",
				FenceLine = "Post",
				HayLine = "Haybale",
			}
			local total, solidTotal = 0, 0
			for i, model in ipairs(models) do
				t.ok(model:IsA("Model"), "a Model")
				t.eq(model.Name, spots[i].kind)
				t.eq(model.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, model.Name .. " streams Atomic")
				-- LevelOfDetail is plugin-only. A game script that sets
				-- StreamingMesh throws and the rest of the scenery step never runs.
				t.eq(
					model.LevelOfDetail,
					roblox.Enum.ModelLevelOfDetail.Automatic,
					model.Name .. " keeps the default detail"
				)
				local n, solid = 0, {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						n += 1
						t.eq(d.Anchored, true)
						t.ok(not d.CanTouch, model.Name .. ": " .. d.Name .. " can be touched")
						if d.CanCollide then
							solid[d.Name] = true
							solidTotal += 1
							t.ok(SOLID[model.Name][d.Name], model.Name .. ": " .. d.Name .. " collides")
							t.ok(d.CanQuery, model.Name .. ": a solid " .. d.Name .. " can't be clicked")
						else
							t.ok(not d.CanQuery, model.Name .. ": " .. d.Name .. " is decor but can be clicked")
						end
						local size = d.Size
						if math.max(size.X, size.Y, size.Z) < 1 then
							t.eq(d.CastShadow, false, model.Name .. ": a small " .. d.Name .. " casts a shadow")
						end
					end
				end
				t.ok(solid[MUST[model.Name]], model.Name .. " has a solid " .. MUST[model.Name])
				t.ok(n >= 1 and n <= 25, model.Name .. ": " .. n .. " parts")
				total += n
			end
			-- Phase 12's wider roads and cliff rings took the flat spots the
			-- scenery used to claim. WorldPlan.spec uses the same floor.
			t.ok(total >= 2500 and total <= 5000, total .. " scenery parts")
			t.ok(solidTotal >= 1000 and solidTotal < total, solidTotal .. " of them solid")
		end
	)

	t.test("an erroring scenery fails its step alone: the rest of the world, SellArea, spawning", function()
		local s = build({
			worldPlan = {
				Scenery = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "[MapBuilder] 5. The scenery (plan) failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.ok(s.map:FindFirstChild("Boulders"), "the boulders still built")
		t.ok(s.map:FindFirstChild("Backdrop"), "the backdrop still built")
	end)

	-- Phase 10, STY: the landscape's landmarks (one new step, "5. The landmarks").
	t.test("the boulder clusters: an Atomic model per cluster in a BoulderClusters folder, rocks colliding", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local s = build()
		t.eq(s.warnings, {})
		lastStepsRan(s)
		local folder = s.map:FindFirstChild("BoulderClusters")
		t.ok(folder and folder:IsA("Folder"), "a BoulderClusters folder in TimberlineMap")
		local spots = WorldPlan.BoulderClusters()
		local models = inPlanOrder(folder)
		t.eq(#models, #spots)
		for i, model in ipairs(models) do
			t.ok(model:IsA("Model"), "a Model")
			t.eq(model.Name, "BoulderCluster")
			t.eq(model.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, "streams Atomic")
			local rocks = model:GetChildren()
			t.eq(#rocks, #spots[i].rocks, "one rock model per rock")
			for k, rock in ipairs(rocks) do
				local hard = 0
				for _, d in ipairs(rock:GetDescendants()) do
					if d:IsA("BasePart") then
						t.eq(d.Anchored, true)
						if d.CanCollide then
							hard += 1
						end
					end
				end
				t.eq(hard, 3, "a rock's three blocks collide, as a lone boulder's do")
				-- Where WorldPlan says: every part round the rock's spot.
				local spot = spots[i].rocks[k]
				for _, d in ipairs(rock:GetDescendants()) do
					if d:IsA("BasePart") then
						local at = d.CFrame.Position
						local off = roblox.Vector3.new(at.X - spot.position.X, 0, at.Z - spot.position.Z).Magnitude
						t.ok(off <= spot.size * WorldPlan.ClusterReach, "the rock stands on its spot")
						t.ok(math.abs(at.Y - spot.position.Y) <= spot.size, "the rock stands on its spot's ground")
					end
				end
			end
		end
	end)

	t.test(
		"the landmarks: footbridge, docks and rowboats Atomic, the lighthouse Persistent, in a Landmarks folder",
		function()
			local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
			local s = build()
			t.eq(s.warnings, {})
			lastStepsRan(s)
			local folder = s.map:FindFirstChild("Landmarks")
			t.ok(folder and folder:IsA("Folder"), "a Landmarks folder in TimberlineMap")
			local Atomic, Persistent = roblox.Enum.ModelStreamingMode.Atomic, roblox.Enum.ModelStreamingMode.Persistent
			local count = {}
			for _, model in ipairs(folder:GetChildren()) do
				t.ok(model:IsA("Model"), model.Name .. " is a Model")
				count[model.Name] = (count[model.Name] or 0) + 1
				local mode = if model.Name == "Lighthouse" then Persistent else Atomic
				t.eq(model.ModelStreamingMode, mode, model.Name .. "'s streaming")
				local solid = 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						t.eq(d.Anchored, true, model.Name .. ": " .. d.Name .. " is anchored")
						if d.CanCollide then
							solid += 1
						end
					end
				end
				if model.Name == "Rowboat" then
					t.eq(solid, 0, "the rowboats are looks only")
				else
					t.ok(solid > 0, model.Name .. " has something to stand on or bump into")
				end
			end
			local docks = WorldPlan.Docks()
			t.eq(count.Footbridge, 1)
			t.eq(count.Dock, #docks)
			t.eq(count.Rowboat, #docks)
			t.eq(count.Lighthouse, 1)
			t.eq(count.Signpost, 2, "the TIMBER BRIDGE and MIRROR LAKE signs")
			-- The lamp LightingController lights at dusk, where WorldPlan says.
			local lighthouse = folder:FindFirstChild("Lighthouse")
			local lamp = lighthouse:FindFirstChild("LampGlow", true)
			t.ok(lamp and lamp.Material == roblox.Enum.Material.Neon, "a Neon LampGlow")
			t.ok(
				(lamp.CFrame.Position - WorldPlan.Lighthouse().lamp).Magnitude < 1e-3,
				"the lamp where WorldPlan puts it"
			)
			-- The signs say what they're for.
			local texts = {}
			for _, model in ipairs(folder:GetChildren()) do
				if model.Name == "Signpost" then
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("TextLabel") then
							texts[d.Text] = true
						end
					end
				end
			end
			t.ok(texts["TIMBER BRIDGE"] and texts["MIRROR LAKE"], "the signs' text")
		end
	)

	t.test("horizon landmarks stay visible, and the shop paths are saw-cut rounds", function()
		local s = build()
		t.eq(s.warnings, {})
		local Persistent = roblox.Enum.ModelStreamingMode.Persistent
		local sawmill = s.map:FindFirstChild("Sawmill")
		t.eq(sawmill.ModelStreamingMode, Persistent, "the sawmill is Persistent")
		t.eq(s.map:FindFirstChild("HearthAndHome").ModelStreamingMode, Persistent, "the town hall is Persistent")
		t.eq(s.map:FindFirstChild("Lighthouse", true).ModelStreamingMode, Persistent, "the lighthouse is Persistent")
		local rounds = s.map:FindFirstChild("PathRounds")
		t.ok(rounds and #rounds:GetChildren() == 6, "three rounds on each of the two shop paths")
		for _, model in ipairs(rounds:GetChildren()) do
			t.eq(model.Name, "PathRound")
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, "a round is flat decor")
				end
			end
		end
		local grove = false
		for _, model in ipairs(s.map:GetChildren()) do
			if model.Name == "Signpost" then
				local label = model:FindFirstChild("Board", true)
				label = label and label:FindFirstChildWhichIsA("TextLabel", true)
				if label and string.find(label.Text, "FIRST GROVE", 1, true) then
					grove = true
					t.ok(model:FindFirstChild("LampBulb", true), "the exit sign is lit")
				end
			end
		end
		t.ok(grove, "a sign points to the first grove")
	end)

	t.test("an erroring landmark plan fails its own step alone: the other landmarks, SellArea, spawning", function()
		local s = build({
			worldPlan = {
				Lighthouse = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "[MapBuilder] 5. The lighthouse failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		local folder = s.map:FindFirstChild("Landmarks")
		t.ok(folder:FindFirstChild("Footbridge") and folder:FindFirstChild("Dock"), "the other landmarks still built")
		t.ok(folder:FindFirstChild("Lighthouse") == nil, "no half-built lighthouse")
		t.ok(s.map:FindFirstChild("BoulderClusters"), "the clusters still built")
	end)

	t.test("an erroring cluster plan fails its own step alone: the rest of the world, SellArea, spawning", function()
		local s = build({
			worldPlan = {
				BoulderClusters = function()
					error("x")
				end,
			},
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "[MapBuilder] 5. The boulder clusters (plan) failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.ok(s.map:FindFirstChild("Boulders"), "the boulders still built")
		t.ok(s.map:FindFirstChild("Scenery"), "the scenery still built")
		t.ok(s.map:FindFirstChild("Backdrop"), "the backdrop still built")
	end)
end
