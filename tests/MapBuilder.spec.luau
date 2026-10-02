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

		local function sellAreaIn()
			local map = ws:FindFirstChild("TimberlineMap")
			return map ~= nil and map:FindFirstChild("SellArea") ~= nil
		end
		s.sellAreaIn = sellAreaIn

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
				},
				TreeService = {
					SpawnTree = function()
						s.spawned += 1
						s.treeBeforeSellArea = (s.treeBeforeSellArea ~= false) and not sellAreaIn()
					end,
				},
				NodeService = { Spawn = function() end },
				WorldClock = {
					Start = function()
						s.clockStarted = true
						s.clockBeforeSellArea = not sellAreaIn()
					end,
				},
			},
			services = { Players = Players },
			globals = {
				workspace = ws,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
				print = function(...)
					table.insert(s.prints, table.concat({ ... }, " "))
				end,
			},
		})
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
		t.eq(s.autoLoads, true, "CharacterAutoLoads ends true")
		-- Off first (nobody spawns before the ground), then on, with SellArea
		-- already in.
		t.eq(s.order, { { autoLoads = false, sellAreaIn = false }, { autoLoads = true, sellAreaIn = true } })
		t.eq(s.loaded, { "Waiting" }, "only the player with no character is loaded")
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
		t.ok(s.clockStarted, "the clock started")
		t.ok(s.clockBeforeSellArea, "the clock (the last build step) starts before SellArea goes in")
		t.ok(s.treeBeforeSellArea, "every tree spawns before SellArea goes in")
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
		t.eq(#TownMarkers.Markers, 5)
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
		local plan = WorldPlan.Town().parkingSlots
		t.ok(#plan >= 24, "24 slots planned")
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
			t.ok(math.abs(slot.Size.Y - 0.2) < 1e-4 and math.abs(slot.Size.Z - 37) < 1e-4, "slot " .. index .. " size")
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
		local s = build()
		local line = builtLine(s)
		t.ok(line, "a World built line")
		t.ok(
			string.match(line, "^%[MapBuilder%] World built in %d+%.%ds %(terrain %d+%.%ds%)$"),
			"shape: " .. tostring(line)
		)
		t.ok(string.find(line, "(terrain 1.2s)", 1, true) or string.find(line, "(terrain 1.3s)", 1, true), line)
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		t.eq(s.spawned, #WorldPlan.Trees())
		t.eq(s.workspace:GetAttribute("MapTrees"), #WorldPlan.Trees())
		t.eq(s.workspace:GetAttribute("MapTerrainSeconds"), 1.25)
		t.eq(s.workspace:GetAttribute("MapBuildFailures"), 0)
		t.ok(type(s.workspace:GetAttribute("MapBuildSeconds")) == "number", "MapBuildSeconds")
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
		t.ok(string.find(s.warnings[1], "4. Lamps, fences, props and signs", 1, true), s.warnings[1])
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
		for _, id in ipairs({ "hills", "snow", "volcano", "sky" }) do
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
		t.eq(solidBoards, 4, "the four road signs' boards")
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
		t.eq(s.workspace:GetAttribute("MapTrees"), #WorldPlan.Trees() + #WorldPlan.Sky().lumenwood)
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
			local models = folder:GetChildren()
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
			t.ok(total >= 3000 and total <= 5000, total .. " scenery parts")
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
		t.ok(string.find(s.warnings[1], "[MapBuilder] 5. The scenery failed", 1, true), s.warnings[1])
		lastStepsRan(s)
		t.ok(s.map:FindFirstChild("Boulders"), "the boulders still built")
		t.ok(s.map:FindFirstChild("Backdrop"), "the backdrop still built")
	end)
end
