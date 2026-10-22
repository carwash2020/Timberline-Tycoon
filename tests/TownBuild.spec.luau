--!nocheck
-- TownBuild (T409): the cloud test builds the town with Shared/Lint/TownBuild, because MapBuilder is a
-- Script and a cloud task can only require modules. This spec keeps the two honest: every piece
-- TownBuild makes is in the real MapBuilder world at the same place, with the same parts, and the lint
-- finds the same things in both.
return function(t)
	local TownBuild = t.load("ReplicatedStorage/Shared/Lint/TownBuild")
	local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")
	local Lanes = t.load("ReplicatedStorage/Shared/Lint/Lanes")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local allow = serde.decode("json", fs.readFile("tests/geometry_allow.json"))

	local function shape(inst)
		-- A name, a place, and how many colliding parts it has.
		local pos = if inst:IsA("Model") then inst:GetPivot().Position else inst.CFrame.Position
		local solid = 0
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				solid += 1
			end
		end
		return string.format("%s @ %.2f,%.2f,%.2f solid=%d", inst.Name, pos.X, pos.Y, pos.Z, solid)
	end

	local function listOf(folder, names)
		local out = {}
		for _, c in ipairs(folder:GetChildren()) do
			if names[c.Name] then
				table.insert(out, shape(c))
			elseif c:IsA("Folder") and names[c.Name .. "/"] then
				for _, cc in ipairs(c:GetChildren()) do
					table.insert(out, c.Name .. "/" .. shape(cc))
				end
			end
		end
		table.sort(out)
		return out
	end

	t.test("every piece TownBuild makes is in the MapBuilder world, at the same place with the same solids", function()
		local town = TownBuild.Build()
		local world = t.support("WorldBuild").Get(t).map
		local names = {}
		for _, c in ipairs(town:GetChildren()) do
			if c:IsA("Folder") then
				names[c.Name .. "/"] = true
			elseif c.Name ~= "SpawnLocation" then
				names[c.Name] = true
			end
		end
		for _, n in ipairs({
			"Sawmill",
			"SellArea",
			"ToolShed",
			"HearthAndHome",
			"Sparkworks",
			"Dealership",
			"TownScenes/",
		}) do
			t.ok(names[n], n .. " is built by TownBuild")
		end
		local mine, theirs = listOf(town, names), listOf(world, names)
		t.ok(#mine > 40, #mine .. " pieces compared")
		-- (the world has other fences, crates and signs out in the country: every town piece is in it)
		local left = {}
		for _, line in ipairs(theirs) do
			left[line] = (left[line] or 0) + 1
		end
		for _, line in ipairs(mine) do
			t.ok((left[line] or 0) > 0, "not in the MapBuilder world: " .. line)
			left[line] = (left[line] or 0) - 1
		end
	end)

	t.test("the lint says the same of the town as of the whole world, and the Sawmill's lanes are clear", function()
		local town = TownBuild.Build()
		-- (an allowlist entry for something outside the town hits nothing here: not a finding)
		local own = Geometry.Run(town, allow, nil, { skipStale = true })
		t.eq(own.failures, {}, "\n" .. table.concat(own.failures, "\n"))
		local frame = WorldPlan.Town().sawmill
		t.eq(Lanes.Run(town, { Sawmill = frame }).failures, {})
	end)
end
