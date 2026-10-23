--!nocheck
-- CloudCheck (T409): the cloud runner's logic, in lune. tests/cloud/entry only adds the engine's overlap
-- query and the mesh loader; everything else is Shared/Lint/CloudCheck, which this spec drives on the
-- real town. A known overlap (a crate in a wall) must come back as a failure, a clean town as none.
-- (The real cloud run needs the Roblox cloud and the API key: see tools/cloud/run_task.py.)
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local CloudCheck = t.load("ReplicatedStorage/Shared/Lint/CloudCheck")
	local TownBuild = t.load("ReplicatedStorage/Shared/Lint/TownBuild")
	local MachineArt = t.load("ReplicatedStorage/Shared/Art/MachineArt")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local data = {
		allow = serde.decode("json", fs.readFile("tests/geometry_allow.json")),
		mustkeep = serde.decode("json", fs.readFile("tests/mustkeep.json")),
	}

	local function town()
		local map = TownBuild.Build()
		local root = Instance.new("Folder")
		root.Name = "Workspace"
		map.Parent = root
		return map, root
	end

	local function run(map, root, deps)
		local lines = {}
		local deps2 = {
			buildMachine = MachineArt.BuildAny,
			log = function(l)
				table.insert(lines, l)
			end,
		}
		for k, v in pairs(deps or {}) do
			deps2[k] = v
		end
		local report = CloudCheck.Run(map, root, data, deps2)
		return report, lines
	end

	t.test("a clean town passes every check", function()
		local map, root = town()
		local report = run(map, root)
		t.eq(report.failures, {}, "\n" .. table.concat(report.failures, "\n"))
		t.eq(report.failed, 0)
		t.eq(report.passed, 3, "lint, lanes, MustKeep")
	end)

	t.test("a known overlap fails it: a crate inside the Tool Shed wall comes back as a failure", function()
		local map, root = town()
		local wall
		for _, d in ipairs(map.ToolShed:GetDescendants()) do
			if d.Name == "Wall" and d:IsA("BasePart") and d.CanCollide then
				wall = d
				break
			end
		end
		t.ok(wall, "the Tool Shed has a wall")
		local crate = Instance.new("Model")
		crate.Name = "Crate"
		local part = Instance.new("Part")
		part.Name = "Crate"
		part.Anchored = true
		part.Size = Vector3.new(2, 2, 2)
		part.CFrame = wall.CFrame
		part.Parent = crate
		crate.Parent = map
		local report, lines = run(map, root)
		t.ok(report.failed > 0 and #report.failures > 0, "the failures list is not empty")
		local text = table.concat(report.failures, "\n")
		t.ok(string.find(text, "Crate (Crate", 1, true) and string.find(text, "(ToolShed)", 1, true), text)
		t.ok(string.find(text, "rule 2b", 1, true), text)
		t.ok(#lines > 0, "and the log says so")
	end)

	t.test("a missing must-keep thing and a thing in a lane fail it too", function()
		local map, root = town()
		map.ToolShed:FindFirstChild("BackRoomDoor"):Destroy()
		local report = run(map, root)
		t.eq(#report.failures, 1, table.concat(report.failures, "\n"))
		t.ok(string.find(report.failures[1], "ToolShed/BackRoomDoor", 1, true), report.failures[1])
		local map2, root2 = town()
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(1, 4, 1)
		post.CFrame = t.load("ReplicatedStorage/Shared/World/WorldPlan").Town().sawmill * CFrame.new(25, 3, -0.9)
		post.Parent = map2.Sawmill
		local report2 = run(map2, root2)
		t.ok(
			string.find(table.concat(report2.failures, "\n"), "x lane Sawmill.slip", 1, true),
			table.concat(report2.failures, "\n")
		)
	end)

	t.test("the engine query and the mesh loader are only run when handed in; their findings count", function()
		local map, root = town()
		local calls = 0
		local report = run(map, root, {
			engineOverlaps = function()
				calls += 1
				return { "[GeometryLint] engine says so" }
			end,
			meshLoads = function()
				calls += 1
				return { "[MeshLoad] Sawmill/Body did not load" }, 5
			end,
		})
		t.eq(calls, 2)
		t.eq(report.failed, 2)
		t.eq(report.passed, 3)
	end)
end
