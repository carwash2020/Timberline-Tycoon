--!nocheck
-- V1 hardening (item 3): the game stays correct under StreamingEnabled.
--
-- default.project.json holds the settings (PlaceCheck warns in Studio when the
-- place disagrees). Radii: StreamingMinRadius 128 is the pause bubble around a
-- player (PauseOutsideLoadedArea holds the join until it is in); 640 is the
-- target a phone can hold; StreamOutBehavior Opportunistic lets distant
-- content go early, which is what a low-memory phone wants. The client reads
-- the world only through lookups that survive a part not being there yet.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local function walk(dir, out)
		out = out or {}
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end
	local function code(path)
		local lines = {}
		for line in string.gmatch(fs.readFile(path), "[^\n]*") do
			if not string.match(line, "^%s*%-%-") then
				table.insert(lines, line)
			end
		end
		return table.concat(lines, "\n")
	end

	local project = serde.decode("json", fs.readFile("default.project.json"))
	local props = project.tree.Workspace["$properties"]
	local client = walk("src/StarterPlayer")
	for _, path in ipairs(walk("src/ReplicatedFirst")) do
		table.insert(client, path)
	end

	t.test(
		"the project streams: Improved, pause outside the loaded area, 128 / 640, opportunistic stream-out",
		function()
			t.eq(props.StreamingEnabled, true)
			t.eq(props.ModelStreamingBehavior, "Improved")
			t.eq(props.StreamingIntegrityMode, "PauseOutsideLoadedArea")
			t.eq(props.StreamingMinRadius, 128)
			t.eq(props.StreamingTargetRadius, 640)
			t.eq(props.StreamOutBehavior, "Opportunistic")
		end
	)

	t.test("the radii are sane for a phone: min under target, target no more than 1024, min at least 64", function()
		t.ok(props.StreamingMinRadius >= 64, "a pause bubble smaller than 64 studs pauses constantly")
		t.ok(props.StreamingMinRadius < props.StreamingTargetRadius)
		t.ok(props.StreamingTargetRadius <= 1024, "past 1024 a phone holds the whole map")
		-- The ranges the game reads off the client (grab reach, chop range, prompts,
		-- the load and sell prompts) all fit inside the minimum radius, so what a
		-- player can act on is always streamed in.
		local GameConfig = t.shared("GameConfig")
		for _, key in ipairs({ "LoadPromptRange", "PickupPromptRange", "ChopRange", "SellTruckRange" }) do
			local value = GameConfig[key]
			if type(value) == "number" then
				t.ok(value + GameConfig.RangeTolerance <= props.StreamingMinRadius, key .. " = " .. value)
			end
		end
		t.ok(t.shared("Tune") ~= nil)
		t.ok(GameConfig.HoldMax + GameConfig.ReleaseDistance <= props.StreamingTargetRadius)
	end)

	t.test("PlaceCheck expects the same numbers the project file holds", function()
		local source = code("src/ServerScriptService/PlaceCheck.luau")
		t.ok(
			string.find(source, 'property = "StreamingTargetRadius", value = ' .. props.StreamingTargetRadius, 1, true)
		)
		t.ok(string.find(source, 'property = "StreamingMinRadius", value = ' .. props.StreamingMinRadius, 1, true))
		t.ok(string.find(source, 'property = "StreamingEnabled", value = true', 1, true))
	end)

	t.test("no client script indexes a Workspace child by name: only the engine's own properties", function()
		local allowed = {
			CurrentCamera = true,
			Terrain = true,
			GlobalWind = true,
			Gravity = true,
			DescendantAdded = true,
			ChildAdded = true,
			DescendantRemoving = true,
			ChildRemoved = true,
			StreamingEnabled = true,
			DistributedGameTime = true,
			GetServerTimeNow = true,
			FallenPartsDestroyHeight = true,
			StreamingTargetRadius = true,
			StreamingMinRadius = true,
			Name = true,
			Parent = true,
			ClassName = true,
			AirDensity = true,
			AirTurbulenceIntensity = true,
		}
		local scanned = 0
		for _, path in ipairs(client) do
			scanned += 1
			for name in string.gmatch(code(path), "[^%w_%.]workspace%.([%w_]+)") do
				t.ok(
					allowed[name],
					path
						.. ": workspace."
						.. name
						.. " is not an engine property; use FindFirstChild or a timed WaitForChild"
				)
			end
			for name in string.gmatch(code(path), "[^%w_%.]Workspace%.([%w_]+)") do
				t.ok(allowed[name], path .. ": Workspace." .. name .. " is not an engine property")
			end
		end
		t.ok(scanned > 50, "scanned " .. scanned .. " client files")
	end)

	t.test("no client script chains into a world lookup that may not have streamed in", function()
		-- FindFirstChild(...).Member and :WaitForChild(...) with no timeout on a
		-- streamed instance would error or hang when it is out of range.
		for _, path in ipairs(client) do
			local src = code(path)
			t.eq(
				string.find(src, 'workspace:FindFirstChild%("[%w_]+"%)%.'),
				nil,
				path .. " indexes the result of workspace:FindFirstChild without a nil check"
			)
			t.eq(
				string.find(src, 'map:FindFirstChild%("[%w_]+"%)%.'),
				nil,
				path .. " indexes the result of map:FindFirstChild without a nil check"
			)
			-- An unbounded WaitForChild on the map's children is only for the persistent ones
			-- (the map folder, the sell area and its zone; MapBuilder marks the area Persistent).
			for receiver, name in string.gmatch(src, '([%w_]+):WaitForChild%("([%w_]+)"%)') do
				if receiver == "map" or receiver == "area" or receiver == "zone" or receiver == "workspace" then
					t.ok(
						name == "TimberlineMap" or name == "SellArea" or name == "SellZone" or name == "SellPoint",
						path
							.. ": an unbounded "
							.. receiver
							.. ":WaitForChild("
							.. name
							.. ") on something that may stream out"
					)
				end
			end
		end
	end)

	t.test("what the client waits for without a timeout is persistent: the sell area, the town's anchors", function()
		local map = code("src/ServerScriptService/MapBuilder.server.luau")
		-- SellArea is waited for by CarryController (the v1 loop's carry); it must be Persistent.
		local at = string.find(map, "sellArea.ModelStreamingMode = Enum.ModelStreamingMode.Persistent", 1, true)
		t.ok(at ~= nil, "the sell area is Persistent")
		-- The landmarks the player steers by and the shops they talk to.
		t.ok(
			string.find(map, "backdrop.ModelStreamingMode = Enum.ModelStreamingMode.Persistent", 1, true),
			"the backdrop"
		)
		local npc = code("src/ServerScriptService/NPCService.luau")
		t.ok(string.find(npc, "ModelStreamingMode.Persistent", 1, true), "Murph, who the tutorial waits for")
		local board = code("src/ServerScriptService/TownBoardService.luau")
		t.ok(string.find(board, "ModelStreamingMode.Persistent", 1, true), "the town board")
		local ferry = code("src/ServerScriptService/FerryService.luau")
		t.ok(string.find(ferry, "ModelStreamingMode.Persistent", 1, true), "the ferry")
	end)

	t.test("everything the server builds in bulk streams Atomic, so a client never sees half of a thing", function()
		-- Plots and what stands on them, wood, trees, trucks, NPCs, nodes and boxes.
		local files = {
			"PlotService",
			"WoodService",
			"TreeService",
			"SectionTrees",
			"VehicleService",
			"NodeService",
			"TruckLoad",
		}
		for _, name in ipairs(files) do
			local src = code("src/ServerScriptService/" .. name .. ".luau")
			t.ok(
				string.find(src, "ModelStreamingMode.Atomic", 1, true) ~= nil,
				name .. " builds models that are not marked Atomic"
			)
		end
	end)

	t.test(
		"loose wood and parts the server caps are streamed (Atomic) models, so a cap removal is seen by everyone",
		function()
			local wood = code("src/ServerScriptService/WoodService.luau")
			t.ok(string.find(wood, "model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic", 1, true))
		end
	)
end
