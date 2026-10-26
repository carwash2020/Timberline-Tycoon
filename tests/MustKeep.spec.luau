--!nocheck
-- MustKeep (T409): the doors, counters, spots and machine ends that must never go missing or move
-- without somebody meaning it. The list is tests/mustkeep.json (path, built world position, tolerance
-- 0.5); a gone or moved entry fails with the expected and the actual position, or "missing". If a
-- move is meant, change the position in the JSON in the same PR.
return function(t)
	local roblox = t.roblox
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MustKeep = t.load("ReplicatedStorage/Shared/Lint/MustKeep")
	local MachineArt = t.load("ReplicatedStorage/Shared/Art/MachineArt")
	local list = serde.decode("json", fs.readFile("tests/mustkeep.json"))

	local function world()
		return t.support("WorldBuild").Get(t)
	end
	local function build(id)
		return MachineArt.BuildAny(id)
	end
	local function paths()
		local out = {}
		for _, e in ipairs(list.world) do
			out[e.path] = e
		end
		return out
	end

	t.test("the seed covers the brief's list (and no gondola prompt)", function()
		local p = paths()
		for _, path in ipairs({
			"TimberlineMap/ToolShed/BackRoomDoor",
			"TimberlineMap/ToolShed/ShopDoor/DoorBlock",
			"TimberlineMap/HearthAndHome/ShopDoor/DoorBlock",
			"TimberlineMap/Sparkworks/ShopDoor/DoorBlock",
			"TimberlineMap/Dealership/ShopDoor/DoorBlock",
			"TimberlineMap/Sawmill/Door",
			"TimberlineMap/SellArea/SellStationArt/SellPad",
			"TimberlineMap/SellArea",
			"TimberlineMap/ToolShed/Counter",
			"TimberlineMap/HearthAndHome/Counter",
			"TimberlineMap/Sparkworks/Counter",
			"TimberlineMap/Dealership/Counter",
			"TimberlineMap/TownScenes/SkyForgeCourt/Floor/KeeperSpot",
			"TimberlineMap/TownScenes/SkyForgeCourt/Anvil/TemperSpot",
			"TimberlineMap/SpawnLocation",
			"TimberlineMap/FerryDock#1",
			"TimberlineMap/TollBooth/Counter",
			"TimberlineMap/GateLodge/Door",
		}) do
			t.ok(p[path], path .. " is on the list")
		end
		local sockets = 0
		for path in pairs(p) do
			if string.find(path, "/Socket_%a+Relic$") then
				sockets += 1
			end
			t.ok(
				not string.find(string.lower(path), "gondola", 1, true),
				path .. ": the gondola is being removed, no entry for it"
			)
		end
		t.eq(sockets, 4, "the 4 relic sockets")
		t.eq(p["TimberlineMap/SellArea/SellStationArt/SellPad"].canCollide, false, "the sell pad must not collide")
		local machines = {}
		for _, e in ipairs(list.machines) do
			machines[e.machine .. "/" .. e.part] = true
		end
		for _, id in ipairs({ "SawmillRickety", "ChopSaw", "PlanerHand" }) do
			t.ok(machines[id .. "/Intake"] and machines[id .. "/Output"], id .. " Intake and Output")
		end
	end)

	t.test("the built world keeps every must-keep thing where it was", function()
		local failures = MustKeep.Run(world().workspace, list, build)
		t.eq(failures, {}, "\n" .. table.concat(failures, "\n"))
	end)

	t.test("a deleted Tool Shed back door fails, naming it and its position", function()
		local w = world()
		local door = w.map.ToolShed:FindFirstChild("BackRoomDoor")
		local parent = door.Parent
		door.Parent = nil
		local failures = MustKeep.Run(w.workspace, list, build)
		door.Parent = parent
		t.eq(#failures, 1, table.concat(failures, "\n"))
		t.ok(string.find(failures[1], "TimberlineMap/ToolShed/BackRoomDoor", 1, true), failures[1])
		t.ok(string.find(failures[1], "expected (-101.25, 4.75, 136.70)", 1, true), failures[1])
		t.ok(string.find(failures[1], "actual missing", 1, true), failures[1])
		t.eq(MustKeep.Run(w.workspace, list, build), {}, "put back, it passes")
	end)

	t.test("a moved thing fails with both positions; 0.5 studs is still fine", function()
		local w = world()
		local counter = w.map.Dealership.Counter
		local home = counter.CFrame
		counter.CFrame = home + roblox.Vector3.new(0.4, 0, 0)
		t.eq(MustKeep.Run(w.workspace, list, build), {}, "0.4 is inside the tolerance")
		counter.CFrame = home + roblox.Vector3.new(2, 0, 0)
		local failures = MustKeep.Run(w.workspace, list, build)
		counter.CFrame = home
		t.eq(#failures, 1, table.concat(failures, "\n"))
		t.ok(
			string.find(
				failures[1],
				"TimberlineMap/Dealership/Counter: expected (194.00, 1.30, 156.23), actual (196.00",
				1,
				true
			),
			failures[1]
		)
	end)

	t.test("the sell pad collides: fails", function()
		local w = world()
		local pad = w.map.SellArea.SellStationArt.SellPad
		pad.CanCollide = true
		local failures = MustKeep.Run(w.workspace, list, build)
		pad.CanCollide = false
		t.eq(#failures, 1, table.concat(failures, "\n"))
		t.ok(string.find(failures[1], "expected CanCollide false", 1, true), failures[1])
	end)

	t.test("a machine without its Intake or Output fails, and so does one that does not build", function()
		local function without(name)
			return function(id)
				local model = MachineArt.BuildAny(id)
				if id == "SawmillRickety" and model then
					local inst = model:FindFirstChild(name, true)
					if inst then
						inst:Destroy()
					end
				end
				return model
			end
		end
		local noIntake =
			MustKeep.Run(roblox.Instance.new("Folder"), { world = {}, machines = list.machines }, without("Intake"))
		t.eq(#noIntake, 1, table.concat(noIntake, "\n"))
		t.ok(
			string.find(noIntake[1], "SawmillRickety/Intake: expected (0.00, 2.50, -4.50), actual missing", 1, true),
			noIntake[1]
		)
		local noOutput =
			MustKeep.Run(roblox.Instance.new("Folder"), { world = {}, machines = list.machines }, without("Output"))
		t.eq(#noOutput, 1)
		t.ok(string.find(noOutput[1], "SawmillRickety/Output", 1, true), noOutput[1])
		local none = MustKeep.Run(roblox.Instance.new("Folder"), { world = {}, machines = list.machines }, function()
			return nil
		end)
		t.eq(#none, #list.machines, "an unbuilt machine is a failure for every part")
	end)

	t.test("every entry has a note or is a machine part; tolerances are 0.5", function()
		for _, e in ipairs(list.world) do
			t.ok(type(e.note) == "string" and e.note ~= "", e.path .. " says what it is")
			t.eq(e.tol, 0.5)
		end
		for _, e in ipairs(list.machines) do
			t.eq(e.tol, 0.5)
		end
	end)
end
