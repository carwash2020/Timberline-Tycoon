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
		if options.playerAt then
			-- "Here" stands at this spot (a character with a root part).
			players[2].Character = {
				FindFirstChild = function()
					return {
						IsA = function()
							return true
						end,
						Position = options.playerAt,
					}
				end,
			}
		end
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
				-- T402: the ground parts are TownGround's (its own spec builds them for real; here a stub keeps each run cheap).
				TownGroundArt = options.townGroundArt or {
					Build = function()
						s.groundBuilt = (s.groundBuilt or 0) + 1
						return t.roblox.Instance.new("Model")
					end,
				},
				WorldPlan = worldPlan,
				TerrainBuilder = {
					NearRadius = 230,
					SliceSeconds = 0.03,
					BackgroundSliceSeconds = 0.012,
					Build = options.terrain and function(onProgress, buildOptions)
						return options.terrain(onProgress, buildOptions, s)
					end or function(onProgress)
						onProgress(24, 24)
						return 1.25
					end,
					SurfaceNear = options.surfaceNear,
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
						s.spawnKinds = s.spawnKinds or {}
						table.insert(s.spawnKinds, if tutorial then "tutorial" else "world")
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
								if s.ringAtFirstTree == nil then
									s.ringAtFirstTree = ws:GetAttribute("NearRingBuilt")
								end
							end
						end
					end,
					RegisterGroups = function()
						s.groups = true
						return true
					end,
				},
				-- T402: the ColorMap check preloads assets (spec MaterialSetup runs it for real).
				ColorMapGuard = {
					Run = function()
						s.colorMapChecks = (s.colorMapChecks or 0) + 1
						return 0
					end,
				},
				-- T397: the ground's texture overrides (spec MaterialSetup).
				MaterialSetup = {
					Apply = function(service, terrain)
						s.materials = (s.materials or 0) + 1
						s.materialsService = service
						s.materialsTerrain = terrain
						return 4
					end,
				},
				NodeService = { Spawn = function() end },
				UndergroundBuilder = { Build = function() end },
				SecretService = { V1Init = function() end },
				WorldClock = {
					StartFresh = function()
						s.clockFresh = true
					end,
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
				MaterialService = { Name = "MaterialService" },
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

	-- Palms, the north-strip stands, Lane R's region woods and the added trees and teasers
	-- (WORLD-T323) and the spawn's oak clumps (WORLD-SPREAD). Lanternwood is planted only once WoodData has the row (B12).
	local function extraTrees(WorldPlan)
		local WoodData = t.shared("WoodData")
		local n = #WorldPlan.StripTrees()
			+ #WorldPlan.FerryPalms()
			+ #WorldPlan.RegionTrees()
			+ #WorldPlan.AddedTrees()
			+ #WorldPlan.NearGrove()
			+ #WorldPlan.SpreadTrees()
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

	t.test("T406: the uploaded town meshes are ON in the game (the build check says so)", function()
		local GameConfig = t.shared("GameConfig")
		t.eq(GameConfig.TownMeshes, true)
		local s = build()
		local found
		for _, line in ipairs(s.prints) do
			if string.find(line, "[MapBuilder] build check: uploaded town meshes ", 1, true) then
				found = line
			end
		end
		t.ok(found and string.find(found, "uploaded town meshes ON,", 1, true), tostring(found))
		t.eq(string.find(found, "OFF", 1, true), nil)
	end)

	t.test("T406: a footpath the drawn terrain would bury is raised onto it; one that shows stays", function()
		local function count(s)
			local paths = s.map:FindFirstChild("TownGround"):FindFirstChild("TownPaths")
			local n, tops = 0, {}
			for _, p in ipairs(paths:GetChildren()) do
				n += 1
				table.insert(tops, p.CFrame.Position.Y + p.Size.Y / 2)
			end
			return n, tops
		end
		local ground = t.shared("Art/TownGroundArt")
		local plain = build({ townGroundArt = ground })
		local n, tops = count(plain)
		t.eq(n, 8, "the eight footpaths T402 made")
		local line
		for _, l in ipairs(plain.prints) do
			if string.find(l, "town footpaths", 1, true) then
				line = l
			end
		end
		t.eq(
			line,
			"[MapBuilder] town footpaths: 0 parts, 0 raised onto the drawn terrain",
			"no terrain probe in this world"
		)
		-- The drawn terrain is 0.3 over every path's planned top.
		local buried = build({
			townGroundArt = ground,
			surfaceNear = function(_x, y, _z)
				return y + 0.3
			end,
		})
		local m, raised = count(buried)
		t.eq(m, 8)
		for i = 1, 8 do
			t.ok(raised[i] > tops[i] + 0.3, "path " .. i .. " is lifted over the terrain")
		end
		-- Terrain that sits well under the paths changes nothing.
		local fine = build({
			townGroundArt = ground,
			surfaceNear = function(_x, y, _z)
				return y - 0.1
			end,
		})
		local _, same = count(fine)
		for i = 1, 8 do
			t.ok(math.abs(same[i] - tops[i]) < 1e-6, "path " .. i .. " stays where it was planned")
		end
	end)

	t.test("a clean build warns nothing, parents SellArea last and lets everyone in", function()
		local s = build()
		t.eq(s.warnings, {})
		-- T397: the ground's MaterialVariants are switched on once, with the service.
		t.eq(s.materials, 1)
		t.eq(s.materialsService.Name, "MaterialService")
		t.eq(s.colorMapChecks, 1, "the ColorMaps are checked once, on a thread of their own (T402)")
		t.eq(s.groundBuilt, 1, "the town's ground parts are built once (T402)")
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
		t.ok(s.clockFresh, "a new server opens on a morning (WorldClock.StartFresh)")
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

	-- T402: the town's roads, curbs, footpaths and lot are parts (Shared/World/TownGround, built by
	-- Art/TownGroundArt). Here the real builder runs inside MapBuilder and the PARTS are read.
	t.test(
		"the town's ground parts (T402): anchored, solid, on the graded ground, seams under 0.05, gaps of 20, under 150",
		function()
			local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
			local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
			local V3 = roblox.Vector3
			local s = build({ townGroundArt = t.shared("Art/TownGroundArt") })
			t.eq(#s.warnings, 0, table.concat(s.warnings, "\n"))
			local ground = s.map:FindFirstChild("TownGround")
			t.ok(ground and ground:IsA("Model"), "a TownGround model under the map")
			local parts = {}
			for _, d in ipairs(ground:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			-- The budget, and one Model a material group.
			t.ok(#parts <= 150, "town ground parts: " .. #parts)
			t.eq(#parts, #TownGround.Pieces(), "a part per piece")
			t.ok(#ground:GetChildren() <= 5, "same-material runs share a Model")
			for _, group in ipairs(ground:GetChildren()) do
				local material
				for _, part in ipairs(group:GetChildren()) do
					if group.Name == "TownRoads" or group.Name == "TownCurbs" or group.Name == "TownPaths" then
						material = material or part.Material
						t.eq(part.Material, material, group.Name .. " holds one material")
					end
				end
			end
			-- The top surface of a part over (x, z): its plane, or nil when (x, z) is off the part.
			local function topAt(part, x, z)
				local cf = part.CFrame
				local up = cf.UpVector
				local top = cf.Position + up * (part.Size.Y / 2) -- (part.Position is unreadable in Lune)
				local y = top.Y - (up.X * (x - top.X) + up.Z * (z - top.Z)) / up.Y
				local l = cf:PointToObjectSpace(V3.new(x, y, z))
				if math.abs(l.X) <= part.Size.X / 2 and math.abs(l.Z) <= part.Size.Z / 2 then
					return y
				end
				return nil
			end
			local roads, curbs, paths = {}, {}, {}
			for _, part in ipairs(parts) do
				if part.Material == roblox.Enum.Material.Asphalt then
					table.insert(roads, part)
				elseif part.Material == roblox.Enum.Material.Concrete then
					table.insert(curbs, part)
				elseif part.Material == roblox.Enum.Material.Ground then
					table.insert(paths, part)
				end
			end
			t.ok(
				#roads > 20 and #curbs > 10 and #paths > 5,
				string.format("%d road, %d curb, %d path parts", #roads, #curbs, #paths)
			)
			for _, part in ipairs(parts) do
				t.ok(part.Anchored, part.Name .. " is anchored")
				t.ok(not part.CastShadow, part.Name .. " casts no shadow")
			end
			for _, part in ipairs(roads) do
				t.ok(part.CanCollide, part.Name .. " collides")
				t.eq(part.Color:ToHex(), "55585A")
				-- Within 0.2 studs of the graded ground over its whole footprint (top 0.05 over it at the ends).
				local c = part.CFrame
				for u = -1, 1, 0.5 do
					for v = -1, 1, 0.5 do
						local w = c * V3.new(u * part.Size.X / 2 * 0.98, part.Size.Y / 2, v * part.Size.Z / 2 * 0.98)
						local y = topAt(part, w.X, w.Z)
						t.ok(y ~= nil)
						local off = math.abs(y - TerrainGen.HeightAt(w.X, w.Z))
						t.ok(
							off <= 0.2,
							string.format("%s is %.3f off the ground at (%.0f, %.0f)", part.Name, off, w.X, w.Z)
						)
					end
				end
				-- Its ends: 0.05 over the ground.
				for _, v in ipairs({ -1, 1 }) do
					local w = c * V3.new(0, part.Size.Y / 2, v * part.Size.Z / 2 * 0.999)
					t.ok(
						math.abs(w.Y - TerrainGen.HeightAt(w.X, w.Z) - 0.05) <= 0.05 + 0.02,
						part.Name .. " end lift " .. (w.Y - TerrainGen.HeightAt(w.X, w.Z))
					)
				end
			end
			for _, part in ipairs(paths) do
				t.ok(part.CanCollide, part.Name .. " collides")
				t.eq(part.Size.X, 6)
				t.eq(part.Color:ToHex(), "8E6C4A")
			end
			-- Touching road parts: tops within 0.05 where they overlap.
			local joins = 0
			for i = 1, #roads do
				local a = roads[i]
				for j = i + 1, #roads do
					local b = roads[j]
					if
						(a.CFrame.Position - b.CFrame.Position).Magnitude
						< (a.Size.Magnitude + b.Size.Magnitude) / 2
					then
						for u = -0.9, 0.9, 0.3 do
							for v = -0.9, 0.9, 0.3 do
								local w = a.CFrame * V3.new(u * a.Size.X / 2, 0, v * a.Size.Z / 2)
								local ya, yb = topAt(a, w.X, w.Z), topAt(b, w.X, w.Z)
								if ya and yb then
									joins += 1
									t.ok(
										math.abs(ya - yb) <= 0.05 + 1e-6,
										string.format(
											"%s / %s step %.3f at (%.0f, %.0f)",
											a.Name,
											b.Name,
											math.abs(ya - yb),
											w.X,
											w.Z
										)
									)
								end
							end
						end
					end
				end
			end
			t.ok(joins > 50, "road overlaps compared: " .. joins)
			-- Curb gaps: the curb parts on one line, in order, are 20 or more studs apart unless a footpath is there.
			local lines = {}
			for _, c in ipairs(curbs) do
				local d = c.CFrame.LookVector
				d = V3.new(d.X, 0, d.Z).Unit
				if d.X < -1e-6 or (math.abs(d.X) <= 1e-6 and d.Z < 0) then
					d = d * -1
				end
				local n = V3.new(-d.Z, 0, d.X)
				local key = string.format(
					"%d,%d,%d",
					math.floor(d.X * 100 + 0.5),
					math.floor(d.Z * 100 + 0.5),
					math.floor(c.CFrame.Position:Dot(n) * 20 + 0.5)
				)
				local mid = c.CFrame.Position:Dot(d)
				local half = c.Size.Z / 2 * math.sqrt(1 - c.CFrame.LookVector.Y ^ 2)
				lines[key] = lines[key] or { dir = d, list = {} }
				table.insert(lines[key].list, { s0 = mid - half, s1 = mid + half, at = c.CFrame.Position })
			end
			local seen = 0
			for _, line in pairs(lines) do
				table.sort(line.list, function(x, y)
					return x.s0 < y.s0
				end)
				for i = 2, #line.list do
					local gap = line.list[i].s0 - line.list[i - 1].s1
					if gap > 0.5 and gap < 20 - 1e-6 then
						local midpoint = line.list[i - 1].at
							+ line.dir
								* ((line.list[i].s0 + line.list[i - 1].s1) / 2 - line.list[i - 1].at:Dot(line.dir))
						local onPath = false
						for _, p in ipairs(paths) do
							local l = p.CFrame:PointToObjectSpace(midpoint)
							if math.abs(l.X) <= p.Size.X / 2 + 1 and math.abs(l.Z) <= p.Size.Z / 2 + 1 then
								onPath = true
							end
						end
						seen += 1
						t.ok(
							onPath,
							string.format(
								"a %.1f stud curb gap at (%.0f, %.0f) is no footpath",
								gap,
								midpoint.X,
								midpoint.Z
							)
						)
					end
				end
			end
			t.ok(seen >= 3, "footpath gaps seen: " .. seen)
		end
	)

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
		t.eq(
			s.spawned,
			(#WorldPlan.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount())
				+ #WorldPlan.ReachTrees()
				+ #TutorialGrove.Trees
				+ extra
		)
		t.eq(
			s.workspace:GetAttribute("MapTrees"),
			(#WorldPlan.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount())
				+ #WorldPlan.ReachTrees()
				+ #TutorialGrove.Trees
				+ extra
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
			(#WorldPlan.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount())
				+ #WorldPlan.ReachTrees()
				+ #sky.lumenwood
				+ #TutorialGrove.Trees
				+ extraTrees(WorldPlan),
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
		t.eq(s.sectionWoods.lumenwood >= #sky.lumenwood, true)
	end)

	t.test("v2: the forest comes in the order a player meets it, batch by batch, nearest the spawn first", function()
		-- A fresh plan (the shared one is cached by other specs, so it would hand
		-- everything over at once): the first batch (WorldPlan.FirstTrees) goes in
		-- before the rest is even planned, then the town's trees, the first thing
		-- the planner hands over, then the rest as it is planned.
		local fresh = t.loader({ isolated = true }):load("ReplicatedStorage/Shared/World/WorldPlan")
		local s = build({
			loop = 2,
			worldPlan = {
				Trees = fresh.Trees,
				FirstTrees = fresh.FirstTrees,
			},
		})
		local spawn = t.shared("World/WorldLayout").Spawn
		local function d2(p)
			return (p.X - spawn.X) ^ 2 + (p.Z - spawn.Z) ^ 2
		end
		local firstN = fresh.FirstTreeCount()
		local townN = 0
		local townAt, planAt = {}, {}
		for _, spot in ipairs(fresh.Trees()) do
			planAt[tostring(spot.position)] = true
			if spot.zone and string.sub(spot.zone.id, 1, 5) == "town:" then
				townN += 1
				townAt[tostring(spot.position)] = true
			end
		end
		t.ok(townN > 0, "the plan has town trees")
		-- The tutorial's first tree stands from the first moment, before any world tree:
		-- the three oaks west of the spawn are planted synchronously, before the world
		-- opens, so the first chop never waits for the forest.
		local TutorialGrove = t.shared("TutorialGrove")
		for i = 1, #TutorialGrove.Trees do
			t.eq(s.spawnKinds[i], "tutorial", "tree " .. i .. " is a tutorial oak")
		end
		t.ok(s.tutorialBeforeSellArea, "...and they are in before SellArea")
		-- (The deferred queue plants the town's greenery trees in the same frames:
		-- only the plan's own trees count here.)
		local order = {}
		for _, p in ipairs(s.forestOrder) do
			if planAt[tostring(p)] then
				table.insert(order, p)
			end
		end
		t.eq(
			#order,
			#fresh.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount(),
			"every tree of the plan is planted once, bar the thinned ones"
		)
		local last, ordered = -1, true
		for i = 1, firstN do
			ordered = ordered and d2(order[i]) >= last
			last = d2(order[i])
		end
		t.ok(ordered, "the first batch is planted nearest the spawn first")
		last, ordered = -1, true
		for i = firstN + 1, firstN + townN do
			ordered = ordered and d2(order[i]) >= last and townAt[tostring(order[i])] == true
			last = d2(order[i])
		end
		t.ok(ordered, "then the town's trees, nearest the spawn first, before any of the far forest")
	end)

	-- Launch performance (14 October 2026): the forest comes nearest the PLAYERS
	-- first, and the client's loading card waits for the ring round the spawn.
	t.test("v2: the forest is planted nearest the player first, not the spawn, when one is in", function()
		local fresh = t.loader({ isolated = true }):load("ReplicatedStorage/Shared/World/WorldPlan")
		local firstTrees = fresh.FirstTrees()
		-- The player stands at the first-batch tree farthest from the spawn.
		local spawn = t.shared("World/WorldLayout").Spawn
		local farthest = firstTrees[1].position
		for _, spot in ipairs(firstTrees) do
			local a = (spot.position.X - spawn.X) ^ 2 + (spot.position.Z - spawn.Z) ^ 2
			local b = (farthest.X - spawn.X) ^ 2 + (farthest.Z - spawn.Z) ^ 2
			if a > b then
				farthest = spot.position
			end
		end
		local s = build({
			loop = 2,
			playerAt = farthest,
			worldPlan = { Trees = fresh.Trees, FirstTrees = fresh.FirstTrees },
		})
		local planAt = {}
		for _, spot in ipairs(firstTrees) do
			planAt[tostring(spot.position)] = true
		end
		local order = {}
		for _, p in ipairs(s.forestOrder) do
			if planAt[tostring(p)] then
				table.insert(order, p)
			end
		end
		t.eq(#order, #firstTrees, "every first-batch tree is planted once")
		local function d2(p)
			return (p.X - farthest.X) ^ 2 + (p.Z - farthest.Z) ^ 2
		end
		local last, ordered = -1, true
		for _, p in ipairs(order) do
			ordered = ordered and d2(p) >= last
			last = d2(p)
		end
		t.ok(ordered, "nearest the player first")
		t.ok(d2(order[1]) < 1, "the tree the player stands by is the first planted")
	end)

	t.test("v2: NearRingBuilt is false while the world builds and true once the trees round the spawn stand", function()
		local s = build({ loop = 2 })
		t.eq(s.ringAtFirstTree, false, "the client's card is told to wait until the ring is planted")
		t.eq(s.workspace:GetAttribute("NearRingBuilt"), true, "and told it is built when the forest is in")
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
		local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")
		for _, spot in ipairs(WorldPlan.Trees()) do
			if spot.woodId == "birch" and not TreeSpread.Skipped(spot.position.X, spot.position.Z) then
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
		for _, spot in ipairs(WorldPlan.AddedTrees()) do
			if spot.woodId == "birch" then
				birches += 1 -- the added birches fail to build too (WORLD-T323)
			end
		end
		for _, spot in ipairs(WorldPlan.SpreadTrees()) do
			if spot.woodId == "birch" then
				birches += 1 -- and so do the refill's (WORLD-SPREAD)
			end
		end
		local TutorialGrove = t.shared("TutorialGrove")
		t.eq(
			s.sectionSpawned,
			(#WorldPlan.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount())
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
		-- Lane R's two road ends are road signs too: the Bayou and Red Mesa are
		-- biomes now, so their posts read like the others' (name, wood, stage).
		road[WorldPlan.BiomeSignText("bayou")] = true
		road[WorldPlan.BiomeSignText("mesa")] = true
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
		t.eq(solidBoards, 9, "the four road signs, the three gate signs and the Bayou and Red Mesa ends")
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
			(#WorldPlan.Trees() - t.load("ReplicatedStorage/Shared/World/TreeSpread").SkipCount())
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
			-- Ring map: 1,500 parts and 800 solid (it was 2,500 and 1,000), as WorldPlan.spec.
			-- Lane R: the Bayou's and Red Mesa's grounds are Limestone and Sandstone now
			-- (scenery and boulders stand on grass), so the floor is 1,400 (was 1,500).
			t.ok(total >= 1400 and total <= 5000, total .. " scenery parts")
			t.ok(solidTotal >= 800 and solidTotal < total, solidTotal .. " of them solid")
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

	t.test("the forge, dock, campfire, lookout and bench stand in the built town", function()
		local s = build()
		t.eq(s.warnings, {})
		local folder = s.map:FindFirstChild("TownScenes")
		t.ok(folder and folder:IsA("Folder"), "TownScenes")
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local town = WorldPlan.Town()
		local names = {
			forge = "SkyForgeCourt",
			fishing = "fishing",
			campfire = "campfire",
			lookout = "lookout",
			bench = "bench",
		}
		t.eq(#folder:GetChildren(), 5, "the five scenes")
		for _, spot in ipairs(town.scenes) do
			local model = folder:FindFirstChild(names[spot.kind])
			t.ok(model and model:IsA("Model"), names[spot.kind] .. " is built")
			local lo, hi
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					lo = if lo then lo:Min(p) else p
					hi = if hi then hi:Max(p) else p
				end
			end
			local at = spot.cframe.Position
			t.ok(
				at.X >= lo.X - 1 and at.X <= hi.X + 1 and at.Z >= lo.Z - 1 and at.Z <= hi.Z + 1,
				names[spot.kind] .. " stands on its spot"
			)
		end
		local dock = folder:FindFirstChild("fishing")
		t.ok(
			dock:FindFirstChild("Deck", true) and dock:FindFirstChild("Pile", true) and dock:FindFirstChild("Rod", true)
		)
		t.eq(dock:FindFirstChild("Water"), nil, "the pond is the water under the dock")
		local forge = folder:FindFirstChild("SkyForgeCourt")
		t.ok(
			forge:FindFirstChild("Anvil", true)
				and forge:FindFirstChild("OrderBoard", true)
				and forge:FindFirstChild("RelicGem", true)
		)
		t.ok(folder:FindFirstChild("lookout"):FindFirstChild("Telescope", true), "the lookout's telescope")
		t.ok(folder:FindFirstChild("bench"):FindFirstChild("Back", true), "the bench's back")
		t.ok(folder:FindFirstChild("campfire"):FindFirstChild("Pot", true), "the campfire's pot")
		local tagged = false
		for _, d in ipairs(folder:FindFirstChild("campfire"):GetDescendants()) do
			if d.Name == "Flame" then
				tagged = tagged or d:HasTag("Flame")
			end
		end
		t.ok(tagged, "the campfire's flame is tagged for TownFX")
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

	-- Server audit (11 October 2026): the terrain is staged. Build returns once the
	-- chunks round the town are written and hands back the rest; the world gate
	-- (and so the first player) no longer waits for it.
	t.test("the rest of the terrain is written after SellArea goes in, not before", function()
		local finished = { n = 0 }
		local s = build({
			terrain = function(_onProgress, options, state)
				t.ok(type(options) == "table" and type(options.nearRadius) == "number", "the build is staged")
				t.ok(type(options.firstSpots) == "table" and #options.firstSpots > 0, "the pad ground goes first")
				return 2,
					function()
						finished.n += 1
						finished.sellAreaIn = state.sellAreaIn()
						return 7
					end
			end,
		})
		t.eq(s.warnings, {})
		lastStepsRan(s)
		t.eq(finished.n, 1, "the second stage ran once")
		t.eq(finished.sellAreaIn, true, "after the world gate, so the first player is not held for it")
		local line = builtLine(s)
		t.ok(
			line ~= nil and string.find(line, "terrain 2.0s", 1, true) ~= nil,
			"the world line counts the near stage: " .. tostring(line)
		)
		local said = false
		for _, p in ipairs(s.prints) do
			if string.find(p, "the rest of the terrain is written", 1, true) then
				said = true
			end
		end
		t.ok(said, "a [Load] line says the rest is in")
		t.eq(s.workspace:GetAttribute("MapBuildFailures"), 0)
	end)

	t.test("a failing second terrain stage is one counted failure; SellArea and spawning are untouched", function()
		local s = build({
			terrain = function()
				return 2, function()
					error("a bad chunk")
				end
			end,
		})
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "the rest of the terrain failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.eq(s.workspace:GetAttribute("MapBuildFailures"), 1)
	end)
end
