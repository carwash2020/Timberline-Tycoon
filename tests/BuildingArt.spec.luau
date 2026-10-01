--!nocheck
-- The town's models (Shared/Art/BuildingArt): the named parts other code
-- looks up, the part budgets, and the space gameplay needs kept clear.
return function(t)
	local roblox = t.roblox
	local V3, C3 = roblox.Vector3, roblox.Color3
	local loader = t.loader()
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")

	local SHOPS = {
		{ kind = "ToolShed", title = "TOOL SHED", accent = C3.fromRGB(150, 62, 44) },
		{ kind = "Dealership", title = "DEALERSHIP", accent = C3.fromRGB(47, 109, 181) },
		{ kind = "HearthAndHome", title = "HEARTH & HOME", accent = C3.fromRGB(122, 90, 60) },
	}

	local function near(a, b)
		return (a - b).Magnitude < 1e-3
	end

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

	-- A part's world-space bounding box.
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

	local function overlaps(p, lo, hi)
		local a, b = bounds(p)
		return a.X < hi.X and b.X > lo.X and a.Y < hi.Y and b.Y > lo.Y and a.Z < hi.Z and b.Z > lo.Z
	end

	-- Collidable parts (other than `except`) inside the box lo..hi.
	local function blockers(model, lo, hi, except)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.CanCollide and p ~= except and overlaps(p, lo, hi) then
				table.insert(out, p.Name)
			end
		end
		return out
	end

	local function texts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				out[d.Text] = true
			end
		end
		return out
	end

	t.test("the sawmill: a spinnable SawBlade, a smoking Smokestack, under budget", function()
		local mill = BuildingArt.Sawmill()
		local blade = mill:FindFirstChild("SawBlade")
		t.ok(blade and blade:IsA("BasePart"), "SawBlade is a direct child part")
		t.eq(blade.Shape, roblox.Enum.PartType.Cylinder)
		t.ok(math.abs(blade.CFrame.XVector.Z) > 0.999, "the blade's axis (its X) runs along world Z")
		t.ok(not blade.CanCollide and blade.Anchored, "the blade is anchored and doesn't collide")
		local welded = 0
		for _, p in ipairs(parts(mill)) do
			local weld = p:FindFirstChildOfClass("WeldConstraint")
			if weld and weld.Part0 == blade then
				t.ok(not p.Anchored and p.Massless, p.Name .. " turns with the blade")
				welded += 1
			end
		end
		t.ok(welded >= 18, "the teeth are welded to the blade")
		local stack = find(mill, "Smokestack")
		t.ok(stack and stack:FindFirstChildOfClass("Smoke"), "Smokestack has a Smoke")
		t.ok(stack.CFrame.Position.Y > 20, "the smoke leaves the top of the stack")
		t.ok(#parts(mill) <= 400, "sawmill parts: " .. #parts(mill))
		t.ok(texts(mill)["TIMBERLINE SAWMILL"], "the sign")
	end)

	t.test("the sawmill leaves the sell pad and the Sky Bin clear", function()
		local mill = BuildingArt.Sawmill()
		-- The Sky Bin (4 x 4 x 4) stands 24 in front and 18 to the west.
		t.eq(blockers(mill, V3.new(-21, 0, -27), V3.new(-15, 6, -21)), {}, "Sky Bin spot")
		-- The pad (24 x 18) starts 13 studs in front of the mill's centre;
		-- only things over 8 studs up (lanterns, the crest sign) reach over it.
		for _, p in ipairs(parts(mill)) do
			local lo, hi = bounds(p)
			if lo.X < 12 and hi.X > -12 and lo.Y < 8 then
				t.ok(lo.Z >= -13.05, p.Name .. " reaches into the sell pad at z " .. lo.Z)
			end
			t.ok(lo.Y > -0.6 or p.Name == "Sawdust", p.Name .. " sinks into the ground") -- sawdust mounds are half buried
			t.ok(
				math.abs(lo.X) < 23 and math.abs(hi.X) < 23 and lo.Z > -15 and hi.Z < 17,
				p.Name .. " is outside the footprint"
			)
		end
	end)

	t.test("shops: a direct-child Counter you can walk up to, under budget", function()
		for _, shop in ipairs(SHOPS) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			t.eq(model.Name, shop.kind)
			local counter = model:FindFirstChild("Counter")
			t.ok(counter and counter:IsA("BasePart"), shop.kind .. " has a direct-child Counter")
			t.ok(counter.CanCollide, shop.kind .. " counter collides")
			local cf = counter.CFrame
			t.ok(
				cf.XVector:Dot(V3.xAxis) > 0.999 and cf.ZVector:Dot(V3.zAxis) > 0.999,
				shop.kind .. " counter is axis-aligned"
			)
			-- Clear floor from the open front to the counter's customer side.
			local front = cf.Position.Z - counter.Size.Z / 2
			local x = cf.Position.X
			local hit = blockers(model, V3.new(x - 1.5, 0.7, -8), V3.new(x + 1.5, 6, front - 0.05), counter)
			t.eq(hit, {}, shop.kind .. " path to the counter")
			t.ok(#parts(model) <= 220, shop.kind .. " parts: " .. #parts(model))
			t.ok(texts(model)[shop.title], shop.kind .. " sign shows its title")
			for _, p in ipairs(parts(model)) do
				local lo, hi = bounds(p)
				t.ok(
					lo.X > -12 and hi.X < 12.5 and lo.Z > -11.6 and hi.Z < 9.2,
					shop.kind .. " " .. p.Name .. " is outside the footprint"
				)
			end
		end
	end)

	t.test("an unknown shop kind still builds a store with a Counter", function()
		local model = BuildingArt.Shop("Bakery", "BAKERY", C3.fromRGB(200, 120, 80))
		t.ok(model:FindFirstChild("Counter"), "Counter")
	end)

	t.test("the gondola station: Platform is the 10 x 1 x 10 PrimaryPart, the cabin has room", function()
		local station = BuildingArt.GondolaStation()
		local platform = station.PrimaryPart
		t.ok(platform and platform.Name == "Platform", "PrimaryPart is Platform")
		t.ok(near(platform.Size, V3.new(10, 1, 10)), "Platform is 10 x 1 x 10")
		t.ok(math.abs(platform.CFrame.Position.Y + platform.Size.Y / 2 - 1) < 1e-4, "its top is at y = 1")
		t.ok(platform.CanCollide, "it collides")
		-- The 5 x 5 cabin rides from the platform's middle out the back (+Z).
		t.eq(blockers(station, V3.new(-2.6, 1.2, -2.6), V3.new(2.6, 7.5, 9), platform), {}, "cabin path")
		t.ok(#parts(station) <= 140, "station parts: " .. #parts(station))
	end)

	t.test("street furniture keeps its named parts", function()
		local sign = BuildingArt.Signpost("TO THE WOODS")
		t.ok(find(sign, "Board") and texts(sign)["TO THE WOODS"], "Signpost board and text")
		local lamp = BuildingArt.LampPost()
		local glow = find(lamp, "LampGlow")
		t.ok(glow and glow:FindFirstChildOfClass("PointLight"), "LampGlow with its light")
		t.eq(glow.Material, roblox.Enum.Material.Neon)
		for _, length in ipairs({ 6, 18, 31 }) do
			local fence = BuildingArt.Fence(length)
			local lo, hi
			for _, p in ipairs(parts(fence)) do
				local a, b = bounds(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
			t.ok(math.abs((hi.X - lo.X) - length) < 1.2, "fence " .. length .. " spans its length")
		end
	end)

	t.test("the sell pad: SellPad doesn't collide, nothing on it does or stands tall", function()
		local art = BuildingArt.SellPad(24, 18)
		local pad = find(art, "SellPad")
		t.ok(pad, "SellPad")
		t.ok(near(pad.Size, V3.new(24, 0.2, 18)), "SellPad is w x 0.2 x d")
		t.ok(not pad.CanCollide, "SellPad CanCollide off")
		local gui = pad:FindFirstChildOfClass("SurfaceGui")
		t.ok(gui and gui.Face == roblox.Enum.NormalId.Top, "text on the top face")
		t.ok(texts(art)["SELL LOGS HERE"], "SELL LOGS HERE")
		for _, p in ipairs(parts(art)) do
			local _, hi = bounds(p)
			t.ok(not p.CanCollide and hi.Y <= 0.3, p.Name .. " is flat paint")
		end
	end)

	t.test("Murph's camp and the campfire: Embers with Fire and light", function()
		for _, model in ipairs({ BuildingArt.Campfire(), BuildingArt.Campsite() }) do
			local embers = find(model, "Embers")
			t.ok(embers, model.Name .. " has Embers")
			t.ok(embers:FindFirstChildOfClass("Fire") and embers:FindFirstChildOfClass("PointLight"), "Fire + light")
		end
		local camp = BuildingArt.Campsite()
		t.ok(#parts(camp) <= 110, "camp parts: " .. #parts(camp))
		-- Room for Murph in front of the fire.
		t.eq(blockers(camp, V3.new(-1, 0.2, -4), V3.new(1, 5, -2.4)), {}, "Murph's spot")
	end)

	t.test("every prop builds; unknown names build a crate", function()
		local names = BuildingArt.PropNames()
		for _, name in ipairs({
			"LogPile",
			"Crate",
			"Barrel",
			"Bench",
			"Well",
			"Cart",
			"SawdustPile",
			"WaterTower",
			"Mailbox",
			"FlowerBox",
			"Haybale",
			"Wheelbarrow",
			"ToolRack",
			"Lantern",
			"Planter",
		}) do
			t.ok(table.find(names, name), name .. " is listed")
		end
		for i, name in ipairs(names) do
			local model = BuildingArt.Prop(name, i)
			t.eq(model.Name, name)
			t.ok(#parts(model) > 0 and #parts(model) <= 60, name .. " parts: " .. #parts(model))
		end
		local odd = BuildingArt.Prop("Teapot", 3)
		t.eq(odd.Name, "Teapot")
		t.ok(find(odd, "Crate"), "an unknown prop is a crate")
		t.ok(find(BuildingArt.Prop("Lantern", 1), "LanternGlow"), "the Lantern prop glows")
	end)

	t.test("the Sky Bin: a 4 x 4 x 4 SkyBin at y = 2 with its text on SurfaceGuis", function()
		local art = BuildingArt.SkyBin()
		local bin = art:FindFirstChild("SkyBin")
		t.ok(bin and bin.CanCollide, "SkyBin collides")
		t.ok(near(bin.Size, V3.new(4, 4, 4)), "SkyBin is 4 x 4 x 4")
		t.ok(math.abs(bin.CFrame.Position.Y - 2) < 1e-4, "centred at y = 2")
		local labels = 0
		for _, gui in ipairs(bin:GetChildren()) do
			if gui:IsA("SurfaceGui") and gui:FindFirstChildWhichIsA("TextLabel", true) then
				labels += 1
			end
		end
		t.eq(labels, 2)
	end)

	t.test("the isle pieces keep CloudChute and StarfallForge", function()
		local chute = find(BuildingArt.CloudChute(), "CloudChute")
		t.ok(chute and chute.CanCollide, "CloudChute collides")
		t.ok(near(chute.Size, V3.new(4, 3, 4)), "CloudChute is 4 x 3 x 4")
		t.ok(math.abs(chute.CFrame.Position.Y - 1.5) < 1e-4, "centred at y = 1.5")
		local forge = BuildingArt.StarfallForge()
		local anvil = forge:FindFirstChild("StarfallForge")
		t.ok(anvil and anvil:FindFirstChildOfClass("PointLight"), "StarfallForge glows")
		t.ok(anvil:FindFirstChildOfClass("ParticleEmitter"), "and sparkles")
	end)

	t.test("bridges: planks' tops run through both ends; a zero-length bridge is empty", function()
		local a, b = V3.new(10, 50, 0), V3.new(10, 52, 30)
		local bridge = BuildingArt.Bridge(a, b, 6)
		t.ok(find(bridge, "Deck"), "Deck")
		local dir = (b - a).Unit
		for _, p in ipairs(parts(bridge)) do
			if p.Name == "Plank" then
				local top = p.CFrame * V3.new(0, p.Size.Y / 2, 0)
				local along = (top - a):Dot(dir)
				local onLine = a + dir * along
				t.ok((top - onLine).Magnitude < 0.2, "plank top on the a-b line")
				t.ok(p.CanCollide, "planks are walkable")
			end
		end
		t.eq(#parts(BuildingArt.Bridge(a, a, 6)), 0)
	end)

	t.test("art rules: CFrame only, deterministic, decoration can't be clicked", function()
		local models = { BuildingArt.Sawmill(), BuildingArt.GondolaStation(), BuildingArt.Campsite() }
		for _, shop in ipairs(SHOPS) do
			table.insert(models, BuildingArt.Shop(shop.kind, shop.title, shop.accent))
		end
		for _, model in ipairs(models) do
			for _, p in ipairs(parts(model)) do
				local setPosition = pcall(function()
					return p.Position
				end)
				t.ok(not setPosition, model.Name .. " " .. p.Name .. " was placed with .Position")
				if not p.CanCollide and p.Name ~= "SellPad" then
					t.ok(not p.CanQuery and not p.CanTouch, model.Name .. " " .. p.Name .. " decoration can be clicked")
				end
			end
		end
		local one, two = parts(BuildingArt.Sawmill()), parts(BuildingArt.Sawmill())
		t.eq(#one, #two)
		for i = 1, #one do
			t.ok(one[i].CFrame == two[i].CFrame and one[i].Color == two[i].Color, "same sawmill every time")
		end
	end)
end
