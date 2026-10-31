--!nocheck
-- T414c: the Land Office and Sparkworks art builders. Written first. Doors,
-- pins, names that code reads, the absent ground forge. Do not loosen these to
-- make a build pass.
return function(t)
	local roblox = t.roblox
	local V3 = roblox.Vector3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopPins = t.load("ReplicatedStorage/Shared/World/ShopPins")
	local ShopPlace = t.load("ReplicatedStorage/Shared/Art/ShopPlace")
	local PlotSalesman = t.load("ReplicatedStorage/Shared/PlotSalesmanData")
	local NPCData = t.load("ReplicatedStorage/Shared/NPCData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")

	local DOOR_W, DOOR_H, SHOULDER, APRON = 8, 10, 3, 6

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

	local function bounds(p)
		local cf, s = p.CFrame, p.Size / 2
		local lo, hi
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local c = cf * V3.new(s.X * x, s.Y * y, s.Z * z)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		return lo, hi
	end

	local function inside(p, x, y, z)
		local lo, hi = bounds(p)
		return x > lo.X and x < hi.X and y > lo.Y and y < hi.Y and z > lo.Z and z < hi.Z
	end

	-- The front face is the -Z wall: its outer z is the model's lowest wall z.
	local function frontZ(model)
		local z = math.huge
		for _, p in ipairs(parts(model)) do
			if p.Name == "Wall" then
				local lo = bounds(p)
				z = math.min(z, lo.Z)
			end
		end
		return z
	end

	local function solids(model)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.CanCollide then
				table.insert(out, p)
			end
		end
		return out
	end

	-- A wall at the front covers (x, y) of the front face.
	local function wallAt(model, x, y, z)
		for _, p in ipairs(solids(model)) do
			if p.Name == "Wall" and inside(p, x, y, z) then
				return true
			end
		end
		return false
	end

	local BUILDERS = {
		{ name = "LandOffice", build = BuildingArt.LandOffice },
		{ name = "Sparkworks", build = BuildingArt.Sparkworks },
	}

	for _, case in ipairs(BUILDERS) do
		t.test("1. " .. case.name .. ": an 8 x 10 door, clear, with 3 studs of wall each side", function()
			local model = case.build()
			t.eq(model.Name, case.name)
			local z = frontZ(model)
			t.ok(z < -4, "a front wall exists, z " .. tostring(z))
			-- The opening and the apron outside it: no solid part, floor flush at most 0.6 high.
			local lo = V3.new(-DOOR_W / 2, 0.6, z - APRON)
			local hi = V3.new(DOOR_W / 2, DOOR_H, z + 2)
			for _, p in ipairs(solids(model)) do
				local a, b = bounds(p)
				local hit = a.X < hi.X and b.X > lo.X and a.Y < hi.Y and b.Y > lo.Y and a.Z < hi.Z and b.Z > lo.Z
				t.ok(not hit, p.Name .. " is solid in the door or its apron")
			end
			-- Wall each side: 3 studs from the opening's edge, 2.5 up the door's height.
			for _, side in ipairs({ -1, 1 }) do
				for _, dx in ipairs({ 0.2, 1.5, SHOULDER - 0.2 }) do
					local x = side * (DOOR_W / 2 + dx)
					t.ok(wallAt(model, x, 5, z + 0.1), case.name .. " shoulder at x " .. x)
				end
			end
			-- A header over the door (the opening is bounded above).
			t.ok(wallAt(model, 0, DOOR_H + 1, z + 0.1), case.name .. " has a header over the door")
		end)
	end

	t.test("1. names, tags and attributes that code reads still exist", function()
		local spark = BuildingArt.Sparkworks()
		for _, name in ipairs({
			"Pad",
			"Floor",
			"Wall",
			"Roof",
			"Counter",
			"Lamp",
			"Switch",
			"Wire",
			"GlowStrip",
			"DemoBoard",
		}) do
			t.ok(find(spark, name) ~= nil, "Sparkworks " .. name)
		end
		local board = find(spark, "DemoBoard")
		t.ok(math.abs(board.Size.X - 6) < 0.01 and math.abs(board.Size.Y - 4) < 0.01, "DemoBoard 6 x 4")
		t.eq(board:FindFirstChildOfClass("SurfaceGui"), nil, "the demo board is empty")
		local office = BuildingArt.LandOffice()
		for _, name in ipairs({ "Floor", "Wall", "Roof", "Sign", "Counter", "DeedMap" }) do
			t.ok(find(office, name) ~= nil, "LandOffice " .. name)
		end
		t.eq(find(office, "DeedMap").CanCollide, false, "the deed map is a picture on the wall")
	end)

	t.test("1. the lots keep their footprint and the no-Neon-wall look holds", function()
		for _, case in ipairs(BUILDERS) do
			local model = case.build()
			local lo, hi
			for _, p in ipairs(parts(model)) do
				local a, b = bounds(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
				if p.Name == "Wall" or p.Name == "Roof" then
					t.ok(p.Material ~= roblox.Enum.Material.Neon, case.name .. " " .. p.Name .. " is not Neon")
				end
			end
			t.ok(hi.X - lo.X <= 20.4 and hi.Z - lo.Z <= 16.4, case.name .. " stays in its lot " .. tostring(hi - lo))
		end
	end)

	t.test("1. the pins are unmoved: Land Office (153.5, 100) is Old Hank's spot, Sparkworks (1115, -700)", function()
		local office = ShopPins.Get("LandOffice")
		t.eq(office.x, 153.5)
		t.eq(office.z, 100)
		t.eq(PlotSalesman.Office.x, 153.5)
		t.eq(PlotSalesman.Office.z, 100)
		t.eq(PlotSalesman.Stand.x, 153.5)
		t.eq(PlotSalesman.Stand.z, 100)
		local spark = ShopPins.Get("Sparkworks")
		t.eq(spark.x, 1115)
		t.eq(spark.z, -700)
	end)

	t.test(
		"2. the clerk faces the door: Hank faces south from his spot; the office counter is behind the door line",
		function()
			local hank = NPCData.Get(PlotSalesman.Id)
			t.eq(hank.spot.position.X, 153.5)
			t.eq(hank.spot.position.Z, 100)
			t.eq(hank.spot.lookAt.Z - hank.spot.position.Z, 100, "his facing is unchanged (south)")
			local office = BuildingArt.LandOffice()
			local counter = find(office, "Counter")
			local z = frontZ(office)
			local a, b = bounds(counter)
			t.ok(a.Z > z + 3, "the counter is well inside the door")
			t.ok(b.X - a.X >= 6, "the counter spans the room, facing the door")
			-- The clerk's side is behind the counter (+Z): clear floor for a clerk to stand.
			local clerk = V3.new((a.X + b.X) / 2, 1.5, b.Z + 1.2)
			for _, p in ipairs(solids(office)) do
				if p.Name ~= "Wall" and p.Name ~= "Roof" then
					t.ok(not inside(p, clerk.X, clerk.Y, clerk.Z), p.Name .. " is where the clerk stands")
				end
			end
		end
	)

	t.test("3. Sparkworks stays on Lantern Isle, ferry required until the ferry binds", function()
		local town = WorldPlan.Town()
		local count = 0
		for _, s in ipairs(town.shops) do
			t.ok(s.kind ~= "Sparkworks", "not on the town square")
		end
		for _, s in ipairs(town.outlets) do
			if s.kind == "Sparkworks" then
				count += 1
				t.eq(s.ferry, true)
				t.eq(s.cframe.Position.X, 1115)
				t.eq(s.cframe.Position.Z, -700)
			end
		end
		t.eq(count, 1)
		local model = ShopPlace.Build("Sparkworks", "SPARKWORKS", roblox.Color3.new(1, 1, 1))
		t.eq(model:GetAttribute("FerryRequired"), true)
	end)

	t.test("4. no SkyForgeCourt on the ground; the summit socket stays", function()
		local town = WorldPlan.Town()
		for _, list in ipairs({ town.shops, town.outlets, town.scenes }) do
			for _, s in ipairs(list) do
				t.ok(s.kind ~= "forge" and s.kind ~= "SkyForgeCourt", "no ground forge spot")
			end
		end
		local world = t.support("WorldBuild").Get(t)
		t.eq(world.map.TownScenes:FindFirstChild("SkyForgeCourt"), nil)
		t.eq(world.map:FindFirstChild("SkyForgeCourt", true), nil, "no SkyForgeCourt anywhere in the built map")
		-- (the cloud socket is a separate model, SkyForge, built on the deck)
		local sky = world.map:FindFirstChild("SkyForge")
		if sky ~= nil then
			t.ok(sky:FindFirstChild("Anvil") ~= nil, "the summit anvil socket is intact")
		end
	end)
	t.test("5. Art fix: the Sparkworks back board is TimberBrown plank, framed in Brass, not a black panel", function()
		local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
		local spark = BuildingArt.Sparkworks()
		local board = find(spark, "DemoBoard")
		t.eq(board.Material, roblox.Enum.Material.WoodPlanks)
		t.eq(board.Color, Palette.TimberBrown)
		local brass = 0
		for _, p in ipairs(parts(spark)) do
			if p.Name == "DemoFrame" and p.Color == Palette.Brass then
				brass += 1
			end
		end
		t.eq(brass, 4, "four brass frame bars")
		local lit = false
		for _, d in ipairs(spark:GetDescendants()) do
			if d:IsA("PointLight") and d.Parent.Name == "DemoLamp" then
				lit = true
			end
		end
		t.ok(lit, "the board is lit by a lantern PointLight")
	end)

	t.test("5. Art fix: every invisible volume in the builders is Transparency 1 (and stays non-colliding)", function()
		for _, case in ipairs(BUILDERS) do
			local model = case.build()
			for _, p in ipairs(parts(model)) do
				local name = string.lower(p.Name)
				local volume = string.find(name, "trigger", 1, true)
					or string.find(name, "prompt", 1, true)
					or string.find(name, "clearance", 1, true)
					or string.find(name, "opening", 1, true)
					or string.find(name, "zone", 1, true)
				if volume then
					t.eq(p.Transparency, 1, case.name .. " " .. p.Name .. " is invisible")
					t.eq(p.CanCollide, false, case.name .. " " .. p.Name .. " does not collide")
				end
				-- A non-colliding, untouchable, unqueryable part that is not a looks-only piece is a volume.
				t.ok(
					not (
							p.Transparency == 0
							and p.CanCollide == false
							and p.CanQuery == false
							and p.Size.Y > 9
							and p.Size.X >= 8
						),
					case.name .. " " .. p.Name .. " is a visible door-sized ghost"
				)
			end
		end
	end)
end
