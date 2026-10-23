--!nocheck
-- WorldBuild: builds the whole world once, headless, the way MapBuilder.spec
-- does (the real art and WorldPlan, with the sky; the terrain, the tree
-- spawners and the clock are stubbed because they are not parts). The result
-- is cached for the process, so every spec that wants the world (GeometryLint,
-- MustKeep, PipelineE2E) shares one build. Read-only: do not change what it
-- hands back; use :Clone() or build your own pieces.
--
-- Use:  local world = t.support("WorldBuild").Get(t)
--   world.workspace   the fake Workspace Folder
--   world.map         Workspace.TimberlineMap
--   world.warnings    the builder's warnings, bar the one Lune-only error
return function()
	local WorldBuild = {}
	local cached: any = nil

	-- Lune can't read BasePart.Position ("missing default value"; Roblox can),
	-- so the gondola cable step fails here and only here.
	local LUNE_ONLY = "missing default value"

	function WorldBuild.Build(t: any): any
		local Instance = t.roblox.Instance
		local s: any = { prints = {}, loaded = {}, autoLoads = true, spawned = 0 }
		local ws = Instance.new("Folder")
		ws.Name = "Workspace"
		local baseplate = Instance.new("Part")
		baseplate.Name = "Baseplate"
		baseplate.Parent = ws
		local templateSpawn = Instance.new("SpawnLocation")
		templateSpawn.Parent = ws

		local Players = setmetatable({}, {
			__index = function(_, key)
				if key == "CharacterAutoLoads" then
					return s.autoLoads
				elseif key == "GetPlayers" then
					return function()
						return {}
					end
				end
				return nil
			end,
			__newindex = function(_, key, value)
				assert(key == "CharacterAutoLoads", "unexpected Players." .. tostring(key))
				s.autoLoads = value
			end,
		})

		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local loader = t.loader({
			mocks = {
				-- The ground parts are TownGround's (TownGround.spec builds them); they carry no collision of
				-- their own that a piece could overlap.
				TownGroundArt = {
					Build = function()
						return t.roblox.Instance.new("Model")
					end,
				},
				WorldPlan = WorldPlan,
				TerrainBuilder = {
					NearRadius = 230,
					SliceSeconds = 0.03,
					BackgroundSliceSeconds = 0.012,
					Build = function(onProgress)
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
					end,
				},
				SectionTrees = {
					SpawnTree = function()
						s.spawned += 1
					end,
					RegisterGroups = function()
						return true
					end,
				},
				ColorMapGuard = {
					Run = function()
						return 0
					end,
				},
				MaterialSetup = {
					Apply = function()
						return 4
					end,
				},
				NodeService = { Spawn = function() end },
				UndergroundBuilder = { Build = function() end },
				SecretService = { V1Init = function() end },
				WorldClock = {
					StartFresh = function() end,
					Start = function() end,
					Refresh = function() end,
				},
			},
			services = {
				Players = Players,
				MaterialService = { Name = "MaterialService" },
				RunService = {
					IsStudio = function()
						return false
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
						return 0
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
		s.workspace = ws
		s.loader = loader
		s.map = ws:FindFirstChild("TimberlineMap")
		return s
	end

	function WorldBuild.Get(t: any): any
		if not cached then
			cached = WorldBuild.Build(t)
		end
		return cached
	end

	return WorldBuild
end
