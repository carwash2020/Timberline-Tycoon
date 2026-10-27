--!nocheck
-- The Skyroot gate lodge: a checkpoint on the north road, not a ride.
-- Enter needs the Sky Pass. Leaving never strands anyone. The shell is
-- the checkpoint size; the lamp is the tall mark. No cabin, no fare.
return function(t)
	local roblox = t.roblox
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local V3 = roblox.Vector3
	local loader = t.loader()
	local GateLodgeLogic = loader:load("ReplicatedStorage/Shared/GateLodgeLogic")
	local SkyQuestLogic = loader:load("ReplicatedStorage/Shared/SkyQuestLogic")
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Palette = loader:load("ReplicatedStorage/Shared/Art/Palette")
	local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = loader:load("ReplicatedStorage/Shared/World/TerrainGen")

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function find(model, name)
		for _, p in ipairs(parts(model)) do
			if p.Name == name then
				return p
			end
		end
		return nil
	end

	local function sameColor(a, b)
		return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
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

	t.test("enter needs the Sky Pass; leaving never strands the driver", function()
		t.eq(GateLodgeLogic.MayEnter(true), true)
		t.eq(GateLodgeLogic.MayEnter(false), false)
		t.eq(SkyQuestLogic.MayPass("enter", true), true)
		t.eq(SkyQuestLogic.MayPass("enter", false), false)
		t.eq(SkyQuestLogic.MayPass("leave", true), true)
		t.eq(SkyQuestLogic.MayPass("leave", false), true)
		t.eq(GateLodgeLogic.SignText, "Sky Pass")
		t.eq(GateLodgeLogic.EdgeColor(false), GateLodgeLogic.ClosedEdge)
		t.eq(GateLodgeLogic.EdgeColor(true), GateLodgeLogic.OpenEdge)
	end)

	t.test("the lodge is pinned at (-40, 720), facing north, on the ground", function()
		local cf = WorldPlan.GateLodge()
		t.ok(cf, "the sky build has a lodge")
		local p = cf.Position
		t.ok(
			math.abs(p.X - -40) <= 1 and math.abs(p.Z - 720) <= 1,
			string.format("at (%.1f, %.1f), want (-40, 720)", p.X, p.Z)
		)
		t.ok((V3.new(p.X, 0, p.Z) - V3.new(680, 0, 280)).Magnitude > 400, "not the old gondola top")
		t.ok(math.abs(p.Y - TerrainGen.HeightAt(p.X, p.Z)) < 0.05, "Y is the ground")
		local clear = TerrainGen.RoadClearance(p.X, p.Z, 200)
		t.ok(clear >= 18 and clear <= 42, string.format("beside the road, clearance %.1f", clear))
		t.ok(cf.LookVector.Z > 0.7, string.format("faces north, look %.2f", cf.LookVector.Z))
	end)

	t.test("shell 28 by 20, peak 14, door clear 6, one lamp past 80", function()
		local model = BuildingArt.GateLodge()
		t.eq(model:GetAttribute("GateId"), "sky")
		local boxCf, boxSize = model:GetBoundingBox()
		t.ok(boxCf ~= nil)
		t.ok(boxSize.X >= 27 and boxSize.X <= 30, string.format("span %.2f", boxSize.X))
		t.ok(boxSize.Z >= 20 and boxSize.Z <= 24, string.format("depth %.2f", boxSize.Z))

		local roofs, lamps, glow = 0, 0, 0
		local peak = 0
		for _, p in ipairs(parts(model)) do
			t.ok(not string.find(string.lower(p.Name), "cabin", 1, true), p.Name)
			t.ok(not string.find(string.lower(p.Name), "gondola", 1, true), p.Name)
			if p.Name == "Roof" then
				roofs += 1
				t.eq(p.Material, roblox.Enum.Material.Slate)
				t.ok(sameColor(p.Color, Palette.RoofSlate), "slate roof")
				peak = math.max(peak, p.CFrame.Position.Y + p.Size.Y / 2)
			elseif p.Name == "Lamp" then
				lamps += 1
			end
			if sameColor(p.Color, Palette.LumenGlow) then
				glow += 1
				t.ok(p.Name == "SignRim" or p.Name == "GateRim", "glow on " .. p.Name)
				local thin = math.min(p.Size.X, p.Size.Y, p.Size.Z)
				t.ok(thin <= 0.2, p.Name .. " is a thin rim")
			end
			if not p.CanCollide and p.Name ~= "Pivot" then
				t.ok(not p.CanQuery and not p.CanTouch, p.Name .. " decoration can be clicked")
			end
		end
		t.eq(roofs, 2)
		t.eq(lamps, 1)
		t.ok(glow >= 2, "the sign rim and the gate rim glow")
		t.ok(math.abs(peak - 14) < 0.05, string.format("peak %.2f", peak))
		local cap = find(model, "LampCap")
		t.ok(cap.CFrame.Position.Y + cap.Size.Y / 2 >= 80, "the lamp clears 80")

		local door = find(model, "Door")
		t.eq(door.Size.X, 6)
		t.ok(door.CFrame.Position.Z < -9, "the door faces the road")
		t.eq(door.CanCollide, false)
		local pad = find(model, "PromptPad")
		t.eq(pad.Size.X, 4)
		t.eq(pad.Size.Z, 4)
		t.eq(pad.CanCollide, false)

		local texts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				texts[d.Text] = true
			end
			t.eq(d:IsA("ProximityPrompt"), false, "no fare prompt on the lodge")
		end
		t.eq(texts["Sky Pass"], true)
		t.eq(texts["Gondola Pass"], nil)
	end)

	t.test("no gondola ride left in the build, the boot list, or a prompt", function()
		t.eq(fs.isFile("src/ServerScriptService/GondolaService.luau"), false)
		t.eq(fs.isFile("src/ReplicatedStorage/Shared/GondolaRide.luau"), false)
		t.eq(fs.isFile("src/StarterPlayer/StarterPlayerScripts/GondolaController.luau"), false)
		local map = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		local plan = fs.readFile("src/ReplicatedStorage/Shared/World/WorldPlan.luau")
		local limits = fs.readFile("src/ServerScriptService/RateLimiter.luau")
		local kept = fs.readFile("tests/mustkeep.json")
		t.eq(string.find(map, "Gondola", 1, true), nil)
		t.eq(string.find(plan, "Gondola", 1, true), nil)
		t.eq(string.find(plan, "gondola", 1, true), nil)
		t.eq(string.find(limits, "Gondola", 1, true), nil)
		t.eq(string.find(kept, "Gondola", 1, true), nil)
		t.eq(string.find(kept, "gondola", 1, true), nil)
		local list = serde.decode("json", kept)
		local door = false
		for _, e in ipairs(list.world) do
			if e.path == "TimberlineMap/GateLodge/Door" then
				door = true
			end
		end
		t.eq(door, true, "the lodge door is on the must-keep list")
		for _, path in ipairs(walk("src", {})) do
			local text = string.lower(fs.readFile(path))
			t.eq(string.find(text, "gondolaservice", 1, true), nil, path)
			t.eq(string.find(text, "gondolaride", 1, true), nil, path)
			t.eq(string.find(text, "gondolacontroller", 1, true), nil, path)
			local i = 1
			while true do
				local a, b = string.find(text, "objecttext", i, true)
				if not a then
					break
				end
				local window = string.sub(text, a, math.min(#text, a + 120))
				t.eq(string.find(window, "gondola", 1, true), nil, path .. " ObjectText")
				i = b + 1
			end
		end
	end)
end
