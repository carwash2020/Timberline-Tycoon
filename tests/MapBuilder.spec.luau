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
end
