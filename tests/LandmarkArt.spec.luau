--!nocheck
-- The landmarks' models (Shared/Art/LandmarkArt, phase 10, STY-04): part
-- budgets, what collides, the walkways kept clear, posts reaching their
-- beds, and the glow parts LightingController lights at dusk.
local fs = require("@lune/fs")

return function(t)
	local roblox = t.roblox
	local V3 = roblox.Vector3
	local Enum = roblox.Enum
	local loader = t.loader()
	local LandmarkArt = loader:load("ReplicatedStorage/Shared/Art/LandmarkArt")
	local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LightingController.luau")

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function named(model, name)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end
	-- A part's world bounding box.
	local function bounds(p)
		local lo, hi
		local h = p.Size / 2
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local w = p.CFrame * V3.new(h.X * x, h.Y * y, h.Z * z)
					lo = if lo then lo:Min(w) else w
					hi = if hi then hi:Max(w) else w
				end
			end
		end
		return lo, hi
	end
	-- The names LightingController lights after dark.
	local glowNames = {}
	do
		local list = string.match(controller, "local GLOW_NAMES[^=]*= {([^}]*)}")
		for name in string.gmatch(list or "", "(%w+) = true") do
			glowNames[name] = true
		end
	end
	local function everyLightShadowless(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				t.eq(d.Shadows, false, model.Name .. ": a light casts shadows")
			end
		end
	end
	local function decorRules(model)
		for _, p in ipairs(parts(model)) do
			t.ok(p.Anchored, model.Name .. ": " .. p.Name .. " is anchored")
			if not p.CanCollide then
				t.eq(p.CanQuery, false, model.Name .. ": " .. p.Name .. " is looks only")
				t.eq(p.CanTouch, false, model.Name .. ": " .. p.Name .. " is looks only")
				local s = p.Size
				if math.max(s.X, s.Y, s.Z) < 1 then
					t.eq(p.CastShadow, false, model.Name .. ": a small " .. p.Name .. " casts a shadow")
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- The footbridge
	---------------------------------------------------------------------------

	local SPANS = {
		{ span = 36, drop = 0, beds = { 0, -7, -9, -7, 0 } },
		{ span = 46, drop = 1.1, beds = { -0.2, -8, -11, -8, 0.9 } },
		{ span = 30, drop = -0.8, beds = { 0.1, -6.5, -9, -6, -0.9 } },
	}

	t.test("footbridge: 110 parts at most; planks, posts and rails collide, the rest is looks", function()
		for _, s in ipairs(SPANS) do
			local model = LandmarkArt.Footbridge(s.span, s.drop, 7, 1.6, s.beds)
			local n = #parts(model)
			t.ok(n <= 110, n .. " parts")
			decorRules(model)
			for _, p in ipairs(parts(model)) do
				local solid = p.Name == "Plank" or p.Name == "Post" or p.Name == "Rail"
				t.eq(p.CanCollide, solid, p.Name .. " collides only if it's a plank, post or rail")
			end
			t.eq(#named(model, "Post"), 2 * #s.beds)
		end
	end)

	t.test("footbridge: the planks make one deck from bank to bank along DeckTop, arched", function()
		for _, s in ipairs(SPANS) do
			local width, rise = 7, 1.6
			local model = LandmarkArt.Footbridge(s.span, s.drop, width, rise, s.beds)
			local planks = named(model, "Plank")
			table.sort(planks, function(a, b)
				return a.CFrame.Position.Z > b.CFrame.Position.Z
			end)
			local reached = 0
			for _, p in ipairs(planks) do
				local lo, hi = bounds(p)
				local mid = p.CFrame.Position
				local tAt = -mid.Z / s.span
				-- Its top on the deck line (within its own tilt).
				local top = mid.Y + p.Size.Y / 2
				t.ok(math.abs(top - LandmarkArt.DeckTop(tAt, s.drop, rise)) < 0.08, "a plank's top on the deck")
				t.ok(p.Size.X >= width - 0.2, "a plank spans the walkway")
				-- No gap a foot falls through: each starts where the last ended.
				t.ok(-hi.Z <= reached + 0.2, string.format("a gap in the deck at %.1f", reached))
				reached = math.max(reached, -lo.Z)
			end
			t.ok(reached >= s.span - 0.2, "the deck reaches the far bank")
			-- Both ends rest just over their banks, the middle rises.
			t.ok(math.abs(LandmarkArt.DeckTop(0, s.drop, rise) - LandmarkArt.BRIDGE_DECK) < 1e-9, "end a")
			t.ok(math.abs(LandmarkArt.DeckTop(1, s.drop, rise) - (s.drop + LandmarkArt.BRIDGE_DECK)) < 1e-9, "end b")
			t.ok(LandmarkArt.DeckTop(0.5, s.drop, rise) > LandmarkArt.BRIDGE_DECK + s.drop / 2 + rise - 1e-9, "arched")
		end
	end)

	t.test("footbridge: the walkway is clear between the rails; the posts reach their beds", function()
		for _, s in ipairs(SPANS) do
			local width = 7
			local model = LandmarkArt.Footbridge(s.span, s.drop, width, 1.6, s.beds)
			for _, p in ipairs(parts(model)) do
				if p.CanCollide and p.Name ~= "Plank" then
					local lo, hi = bounds(p)
					-- Rails and posts stand outside the deck's width.
					t.ok(lo.X >= width / 2 - 1e-3 or hi.X <= -width / 2 + 1e-3, p.Name .. " stands on the walkway")
				end
			end
			-- A post at each station, reaching down into its bed, up past the top rail.
			local stations = #s.beds
			for _, post in ipairs(named(model, "Post")) do
				local lo, hi = bounds(post)
				local z = -post.CFrame.Position.Z
				local station = math.floor(z / s.span * (stations - 1) + 0.5) + 1
				t.ok(lo.Y <= s.beds[station] - 0.5, "a post reaches its bed")
				local tAt = (station - 1) / (stations - 1)
				t.ok(
					hi.Y >= LandmarkArt.DeckTop(tAt, s.drop, 1.6) + LandmarkArt.BRIDGE_RAIL,
					"a post holds the top rail"
				)
			end
			-- The rails: a top one about 3 studs over the deck, all along.
			local top = 0
			for _, rail in ipairs(named(model, "Rail")) do
				local _, hi = bounds(rail)
				local tAt = -rail.CFrame.Position.Z / s.span
				if hi.Y > LandmarkArt.DeckTop(tAt, s.drop, 1.6) + 2.5 then
					top += 1
				end
			end
			t.eq(top, 2 * (stations - 1), "a top rail along every bay, both sides")
		end
	end)

	---------------------------------------------------------------------------
	-- The docks and the rowboat
	---------------------------------------------------------------------------

	t.test("dock: 60 parts at most; planks over the water from its land end, posts to the bed", function()
		for _, d in ipairs({
			{ length = 20, deck = 0.3, water = -2.5, beds = { -0.05, -3.5, -4.7, -5.9 } },
			{ length = 26, deck = 0.3, water = -1, beds = { -0.3, -2.7, -5, -7.4 } },
		}) do
			local width = 5
			local model = LandmarkArt.Dock(d.length, width, d.deck, d.water, d.beds)
			local n = #parts(model)
			t.ok(n <= 60, n .. " parts")
			decorRules(model)
			for _, p in ipairs(parts(model)) do
				local solid = p.Name == "Plank" or p.Name == "Post"
				t.eq(p.CanCollide, solid, p.Name .. " collides only if it's a plank or a post")
			end
			local reached = 0
			local planks = named(model, "Plank")
			table.sort(planks, function(a, b)
				return a.CFrame.Position.Z > b.CFrame.Position.Z
			end)
			for _, p in ipairs(planks) do
				local lo, hi = bounds(p)
				t.ok(math.abs(hi.Y - d.deck) < 0.06, "a plank's top on the deck")
				t.ok(-hi.Z <= reached + 0.2, "no gap in the deck")
				reached = math.max(reached, -lo.Z)
			end
			t.ok(math.abs(reached - d.length) < 0.3, "the deck runs its length")
			for _, post in ipairs(named(model, "Post")) do
				local lo = bounds(post)
				local z = -post.CFrame.Position.Z
				local station = math.floor((z - 0.6) / (d.length - 1.2) * (#d.beds - 1) + 0.5) + 1
				t.ok(lo.Y <= d.beds[station] - 0.5, "a post reaches its bed")
			end
			-- Its lantern (LightingController lights it) and a ladder into the water.
			local glows = named(model, "LanternGlow")
			t.ok(#glows >= 1 and glowNames.LanternGlow, "a LanternGlow LightingController lights")
			for _, g in ipairs(glows) do
				t.eq(g.Material, Enum.Material.Neon)
			end
			everyLightShadowless(model)
			local deepest = math.huge
			for _, rail in ipairs(named(model, "LadderRail")) do
				local lo = bounds(rail)
				deepest = math.min(deepest, lo.Y)
			end
			t.ok(deepest <= d.water - 1, "the ladder reaches into the water")
		end
	end)

	t.test("rowboat: looks only, 14 parts at most, about 3 x 8 studs, floating at its waterline", function()
		for seed = 1, 6 do
			local model = LandmarkArt.Rowboat(seed)
			local all = parts(model)
			t.ok(#all <= 14, #all .. " parts")
			decorRules(model)
			local lo, hi
			for _, p in ipairs(all) do
				t.eq(p.CanCollide, false, "the rowboat is decor: " .. p.Name)
				local a, b = bounds(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
			local size = hi - lo
			t.ok(size.X <= 3.6 and size.Z <= 8.5 and size.Z >= 6, string.format("%.1f x %.1f", size.X, size.Z))
			t.ok(lo.Y < -0.4 and lo.Y > -1.2, "its hull sits in the water")
		end
	end)

	---------------------------------------------------------------------------
	-- The lighthouse
	---------------------------------------------------------------------------

	t.test("lighthouse: 75 parts at most, its lamp a Neon LampGlow that lights at dusk", function()
		local model = LandmarkArt.Lighthouse()
		local all = parts(model)
		t.ok(#all <= 75, #all .. " parts")
		decorRules(model)
		local lamps = named(model, "LampGlow")
		t.eq(#lamps, 1)
		local lamp = lamps[1]
		t.ok(glowNames.LampGlow, "LightingController lights LampGlow parts")
		t.eq(lamp.Material, Enum.Material.Neon)
		t.ok(math.abs(lamp.CFrame.Position.Y - LandmarkArt.LIGHTHOUSE_LAMP) < 1e-3, "the lamp's height")
		local light = lamp:FindFirstChildWhichIsA("PointLight")
		t.ok(light and light.Range >= 50, "the lamp throws its light far")
		everyLightShadowless(model)
		t.ok(#named(model, "WindowGlass") >= 2 and glowNames.WindowGlass, "warm windows up the tower")
		-- The lamp room's glass never hides the lamp's glow: it's see-through.
		for _, room in ipairs(named(model, "LampRoom")) do
			t.ok(room.Transparency >= 0.4, "the lamp room is glass")
		end
	end)

	t.test("lighthouse: tall, its tower, plinth, gallery and rocks collide, all within its radius", function()
		local model = LandmarkArt.Lighthouse()
		local top, solidTower = -math.huge, 0
		for _, p in ipairs(parts(model)) do
			local lo, hi = bounds(p)
			top = math.max(top, hi.Y)
			for _, corner in ipairs({ lo, hi }) do
				local r = math.sqrt(corner.X * corner.X + corner.Z * corner.Z)
				t.ok(r <= LandmarkArt.LIGHTHOUSE_RADIUS * 1.42, p.Name .. " reaches past the lighthouse's radius")
			end
			local mid = p.CFrame.Position
			t.ok(
				math.sqrt(mid.X * mid.X + mid.Z * mid.Z) <= LandmarkArt.LIGHTHOUSE_RADIUS,
				p.Name .. " stands outside the lighthouse's radius"
			)
			if p.Name == "Tower" then
				t.ok(p.CanCollide, "the tower collides")
				solidTower += 1
			elseif p.Name == "Plinth" or p.Name == "Gallery" or p.Name == "Rock" then
				t.ok(p.CanCollide, p.Name .. " collides")
			end
		end
		t.ok(solidTower >= 4, "a banded tower")
		t.ok(top >= 50 and top <= LandmarkArt.LIGHTHOUSE_TOP + 0.5, string.format("%.1f studs tall", top))
	end)

	t.test("the ferry boat: one anchored deck to ride, a few parts, rails that hold and a lantern", function()
		local model = LandmarkArt.FerryBoat()
		local all = parts(model)
		t.ok(#all <= 80, #all .. " parts")
		local deck = model:FindFirstChild("Deck")
		t.ok(deck, "a Deck")
		t.eq(model.PrimaryPart, deck)
		t.ok(deck.Anchored and deck.CanCollide, "anchored, solid")
		t.eq(deck.Size.X, 14)
		t.eq(deck.Size.Z, 22)
		for _, p in ipairs(all) do
			t.ok(p.Anchored, p.Name .. " anchored (the server moves the whole model)")
		end
		t.ok(model:FindFirstChild("LanternGlow", true), "a lantern for the dusk")
	end)
end
