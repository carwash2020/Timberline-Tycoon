--!nocheck
-- T415 streaming: Improved behaviour and the radii are as shipped, Persistent is exactly the short list,
-- everything interactive is Atomic, pure decor is Default.
return function(t)
	local PerfPolicy = t.shared("PerfPolicy")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local function code(path)
		local lines = {}
		for line in string.gmatch(fs.readFile(path), "[^\n]*") do
			if not string.match(line, "^%s*%-%-") then
				table.insert(lines, line)
			end
		end
		return table.concat(lines, "\n")
	end
	local function count(text, pattern)
		local n = 0
		for _ in string.gmatch(text, pattern) do
			n += 1
		end
		return n
	end
	local function walk(dir, out)
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

	t.test("ModelStreamingBehavior is Improved and the radii are 128 / 640", function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local ws = project.tree.Workspace["$properties"]
		t.eq(ws.ModelStreamingBehavior, "Improved")
		t.eq(ws.StreamingEnabled, true)
		t.eq(ws.StreamingMinRadius, 128)
		t.eq(ws.StreamingTargetRadius, 640)
		local place = fs.readFile("src/ServerScriptService/PlaceCheck.luau")
		t.ok(string.find(place, 'property = "StreamingMinRadius", value = 128', 1, true))
		t.ok(string.find(place, 'property = "StreamingTargetRadius", value = 640', 1, true))
	end)

	t.test("the Persistent set is exactly the short list", function()
		local names = {}
		for name in pairs(PerfPolicy.Persistent) do
			table.insert(names, name)
		end
		table.sort(names)
		t.eq(names, {
			"FerryBoat",
			"GateLodge",
			"IslandDock",
			"LiftBridge",
			"MainlandDock",
			"Murph",
			"OldHank",
			"StoreBoard",
			"TownBoard",
		})
	end)

	-- Where `ModelStreamingMode.Persistent` may be written, and how often.
	t.test("Persistent is written only at the sites of the list", function()
		local allowed = {
			["src/ServerScriptService/FerryService.luau"] = 1, -- FerryBoat
			["src/ReplicatedStorage/Shared/Art/TravelArt.luau"] = 1, -- the persistent() helper (lift, two docks)
			["src/ServerScriptService/MapBuilder.server.luau"] = 1, -- the persistent() helper (StoreBoard, GateLodge)
			["src/ServerScriptService/NPCService.luau"] = 1, -- NPCData persistent (Murph, Old Hank)
			["src/ServerScriptService/TownBoardService.luau"] = 1, -- TownBoard
		}
		for _, path in ipairs(walk("src", {})) do
			local n = count(code(path), "ModelStreamingMode%.Persistent")
			t.eq(n, allowed[path] or 0, path)
		end
	end)

	t.test("the persistent() helpers wrap only the listed models", function()
		local map = code("src/ServerScriptService/MapBuilder.server.luau")
		t.eq(count(map, "[^%w_]persistent%("), 3, "the definition and two calls")
		t.ok(string.find(map, "persistent(StoreBoard.Build())", 1, true))
		t.ok(string.find(map, "persistent(BuildingArt.GateLodge())", 1, true))
		local travel = code("src/ReplicatedStorage/Shared/Art/TravelArt.luau")
		t.eq(count(travel, "[^%w_]persistent%("), 4, "the definition and three calls")
		t.ok(string.find(travel, "persistent(lift)", 1, true))
		t.ok(string.find(travel, "persistent(mainDock)", 1, true))
		t.ok(string.find(travel, "persistent(isle)", 1, true))
		local npc = code("src/ReplicatedStorage/Shared/NPCData.luau")
		t.eq(count(npc, "persistent = true"), 2, "Murph and Old Hank")
	end)

	t.test("shops, the sawmill, the sell area and the mine mouth are Atomic, not Persistent", function()
		local map = code("src/ServerScriptService/MapBuilder.server.luau")
		t.eq(string.find(map, "row.preload", 1, true), nil, "no shop streams as Persistent")
		t.ok(string.find(map, "atomic(BuildingArt.Sawmill())", 1, true))
		t.ok(string.find(map, "sellArea.ModelStreamingMode = Enum.ModelStreamingMode.Atomic", 1, true))
		local under = code("src/ServerScriptService/UndergroundBuilder.luau")
		t.ok(string.find(under, "ModelStreamingMode.Atomic", 1, true))
		local travel = code("src/ReplicatedStorage/Shared/Art/TravelArt.luau")
		t.eq(string.find(travel, "persistent(liftBooth)", 1, true), nil)
	end)

	t.test("every interactive model type sets Atomic", function()
		local files = {
			"src/ServerScriptService/TreeService.luau", -- trees, stumps
			"src/ServerScriptService/WoodService.luau", -- logs, wood
			"src/ServerScriptService/NodeService.luau", -- nodes
			"src/ServerScriptService/VehicleService.luau", -- trucks, trailers
			"src/ServerScriptService/TruckLoad.luau",
			"src/ServerScriptService/PlotService.luau", -- plots and machines
			"src/ServerScriptService/NPCService.luau",
			"src/ReplicatedStorage/Shared/Art/BuildingArt.luau", -- shops, props
		}
		for _, path in ipairs(files) do
			t.ok(string.find(code(path), "ModelStreamingMode.Atomic", 1, true), path)
		end
	end)

	t.test("pure decor stays Default: scatter", function()
		t.ok(string.find(code("src/ServerScriptService/ScatterBuilder.luau"), "ModelStreamingMode.Default", 1, true))
		local landmark = code("src/ReplicatedStorage/Shared/Art/LandmarkArt.luau")
		t.eq(string.find(landmark, "DeepWater(), Enum.ModelStreamingMode.Persistent", 1, true), nil)
	end)
end
