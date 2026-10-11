--!nocheck
-- Lane R: the Bayou's and Red Mesa's part-built art. Part caps, names, what
-- collides, lights that stay small, and signs that face the way they read.
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local V3 = roblox.Vector3
	local loader = t.loader()
	local RegionArt = loader:load("ReplicatedStorage/Shared/Art/RegionArt")
	local BayouData = loader:load("ReplicatedStorage/Shared/Regions/BayouData")
	local MesaData = loader:load("ReplicatedStorage/Shared/Regions/MesaData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")

	local function flat()
		return 0
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
	local function named(model, name)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end
	local function lights(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function noForbidden(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				t.eq(d:GetAttribute("OwnerId"), nil, d.Name .. " carries no owner")
				t.eq(d:GetAttribute("Slab"), nil, d.Name .. " is not a slab")
			end
		end
	end
	local function parent()
		return Instance.new("Folder")
	end

	t.test("the boardwalk: 16 deck planks on posts with a rail, at most 60 parts, 8 wide", function()
		local m = RegionArt.Boardwalk(parent(), flat)
		local n = RegionArt.PartCount(m)
		t.ok(n <= 60, n .. " parts")
		t.eq(#named(m, "Deck"), 16)
		for _, deck in ipairs(named(m, "Deck")) do
			t.eq(deck.Size.X, 8)
			t.ok(deck.CanCollide, "a plank you walk on")
		end
		t.ok(m:GetAttribute("DeckTop") > 0, "the deck is above the ground")
		for _, post in ipairs(named(m, "Post")) do
			t.eq(post.CanCollide, false, "a post you cannot snag on")
		end
		noForbidden(m)
	end)

	t.test("the boardwalk stays on the ground it samples: a level deck over every post foot", function()
		local function hill(x, _z)
			return math.sin(x / 9) * 1.2
		end
		local m = RegionArt.Boardwalk(parent(), hill)
		local top = m:GetAttribute("DeckTop")
		for _, deck in ipairs(named(m, "Deck")) do
			local surface = deck.CFrame.Position.Y + deck.Size.Y / 2
			t.ok(math.abs(surface - top) < 1e-3, "a level deck")
		end
		for _, post in ipairs(named(m, "Post")) do
			-- An upright cylinder's length is its X.
			local bottom = post.CFrame.Position.Y - post.Size.X / 2
			t.ok(bottom <= hill(post.CFrame.Position.X, post.CFrame.Position.Z), "a post that floats")
		end
	end)

	t.test(
		"the Bait Shack: at most 40 parts, a counter with the boots prompt, a keeper's spot, stilts that reach down",
		function()
			local m = RegionArt.BaitShack(parent(), flat, 1.4)
			local n = RegionArt.PartCount(m)
			t.ok(n <= 40, n .. " parts")
			t.eq(#named(m, "Counter"), 1)
			t.eq(named(m, "Counter")[1]:GetAttribute("Prompt"), "WaderBoots")
			local stand = named(m, "NPCStand")[1]
			t.ok(stand ~= nil and stand.CanCollide == false and stand.Transparency == 1, "an invisible keeper's spot")
			local stilts = named(m, "Stilt")
			t.ok(#stilts >= 4)
			for _, s in ipairs(stilts) do
				local bottom, top = s.CFrame.Position.Y - s.Size.X / 2, s.CFrame.Position.Y + s.Size.X / 2
				t.ok(bottom <= 0 and top >= 1.0, "a stilt from the ground to the floor")
			end
			noForbidden(m)
		end
	)

	t.test(
		"the Bait Shack's sign reads from the boardwalk: front toward the ring's middle, text on the Front face",
		function()
			local m = RegionArt.BaitShack(parent(), flat, 1.4)
			local sign = named(m, "Sign")[1]
			local s = BayouData.Shack
			local toward = V3.new(s.faceX - sign.CFrame.Position.X, 0, s.faceZ - sign.CFrame.Position.Z).Unit
			-- The part's front face is -Z, so CFrame.lookAt points -Z at the target.
			t.ok(sign.CFrame.LookVector:Dot(toward) > 0.9, "the sign's front points at the walkway")
			local gui = sign:FindFirstChildOfClass("SurfaceGui")
			t.ok(gui ~= nil and gui.Face == roblox.Enum.NormalId.Front, "the text is on the front face")
			t.eq(gui:FindFirstChildOfClass("TextLabel").Text, "BAIT & WADERS")
		end
	)

	t.test("four Bayou lanterns, Range 16 or less, shadows off", function()
		local m = RegionArt.Lanterns(parent(), flat, 1.4)
		local list = lights(m)
		t.eq(#list, 4)
		for _, l in ipairs(list) do
			t.ok(l.Range <= 16, "Range " .. l.Range)
			t.eq(l.Shadows, false)
		end
		t.eq(#named(m, "LanternGlow"), 4)
	end)

	t.test("mud discs and pools are looks only, one disc for each of Builder's four zones", function()
		local m = RegionArt.MudAndPools(parent(), flat)
		t.eq(#named(m, "Mud"), 4)
		t.eq(#named(m, "Pool"), #BayouData.Pools)
		for _, p in ipairs(parts(m)) do
			t.eq(p.CanCollide, false)
			t.eq(p.CanTouch, false)
			t.eq(p.CanQuery, false)
		end
		for i, mud in ipairs(named(m, "Mud")) do
			t.eq(mud:GetAttribute("MudZone"), WorldPlan.MudZones[i].id)
		end
	end)

	t.test("the mist is a FogZone volume (the lighting controller's input), not an Atmosphere", function()
		local zone = RegionArt.MistZone(parent(), flat)
		t.eq(zone:GetAttribute("FogPreset"), "fog")
		t.eq(zone.CanCollide, false)
		t.eq(zone.Transparency, 1)
		local fs = require("@lune/fs")
		local text = fs.readFile("src/ReplicatedStorage/Shared/Art/RegionArt.luau")
		t.ok(not string.find(text, 'Instance.new("Atmosphere")', 1, true), "no Atmosphere written here")
	end)

	t.test("the quarry: eight SlabNodes on WorldPlan's anchors, each on the ground, and a lot", function()
		local m = RegionArt.QuarryFace(parent(), flat)
		local nodes = named(m, "SlabNode")
		t.eq(#nodes, 8)
		for i, node in ipairs(nodes) do
			local want = WorldPlan.SlabNodes[i]
			t.eq(node:GetAttribute("NodeId"), want.id)
			t.ok(
				math.abs(node.CFrame.Position.X - want.x) < 1e-3 and math.abs(node.CFrame.Position.Z - want.z) < 1e-3,
				"on its anchor"
			)
			local bottom = node.CFrame.Position.Y - node.Size.Y / 2
			t.ok(bottom >= -0.01 and bottom <= 0.5, "on the ground")
		end
		t.eq(#named(m, "LotPad"), 1)
		t.ok(RegionArt.PartCount(m) <= 60)
		noForbidden(m)
	end)

	t.test("the quarry walls face the middle of the mesa", function()
		local m = RegionArt.QuarryFace(parent(), flat)
		local c = MesaData.Centre
		for _, wall in ipairs(named(m, "Wall")) do
			local toward = V3.new(c.x - wall.CFrame.Position.X, 0, c.z - wall.CFrame.Position.Z).Unit
			t.ok(wall.CFrame.LookVector:Dot(toward) > 0.99, "a wall turned the wrong way")
		end
	end)

	t.test("two Mesa lanterns, Range 16 or less, shadows off", function()
		local m = RegionArt.MesaLanterns(parent(), flat)
		local list = lights(m)
		t.eq(#list, 2)
		for _, l in ipairs(list) do
			t.ok(l.Range <= 16)
			t.eq(l.Shadows, false)
		end
	end)

	t.test("the overlook: at most 30 parts, a 6 wide ramp at 12 degrees or less meeting the deck", function()
		local m = RegionArt.Overlook(parent(), flat)
		local n = RegionArt.PartCount(m)
		t.ok(n <= 30, n .. " parts")
		local ramp = named(m, "Ramp")[1]
		t.eq(ramp.Size.X, 6)
		local degrees = math.deg(math.atan2(ramp.Size.Y, ramp.Size.Z))
		t.ok(degrees <= 12, string.format("a ramp of %.1f degrees", degrees))
		local deck = named(m, "Deck")[1]
		t.ok(
			math.abs((deck.CFrame.Position.Y + deck.Size.Y / 2) - MesaData.Overlook.deckRise) < 1e-3,
			"the deck is deckRise up"
		)
		-- The ramp's high end touches the deck's near edge, and its foot is on the floor.
		local highZ = ramp.CFrame.Position.Z - ramp.Size.Z / 2
		t.ok(math.abs(highZ - (deck.CFrame.Position.Z + deck.Size.Z / 2)) < 1e-3, "the ramp meets the deck")
		t.ok(math.abs(ramp.CFrame.Position.Y - ramp.Size.Y / 2) < 1e-3, "the ramp's foot is on the ground")
		noForbidden(m)
	end)

	t.test("the arch: at most 60 parts, banded sandstone and sand", function()
		local m = RegionArt.Arch(parent(), flat)
		local n = RegionArt.PartCount(m)
		t.ok(n <= 60, n .. " parts")
		t.eq(#named(m, "Span"), 12)
		local tallest = 0
		for _, p in ipairs(parts(m)) do
			tallest = math.max(tallest, p.CFrame.Position.Y + p.Size.Y / 2)
		end
		t.ok(tallest >= 16 and tallest <= 40, "an arch " .. tallest .. " tall")
		noForbidden(m)
	end)

	t.test("the butte: steps at +15, +30 and +45, a truss ladder on each, and the rare find's plinth on top", function()
		local m = RegionArt.Butte(parent(), flat)
		for i, h in ipairs({ 15, 30, 45 }) do
			local step = named(m, "Step" .. i)[1]
			-- An upright cylinder's length is its X.
			local top = step.CFrame.Position.Y + step.Size.X / 2
			t.ok(math.abs(top - h) < 1e-3, "step " .. i .. " tops out at " .. top)
			local ladder = named(m, "Ladder" .. i)[1]
			t.ok(ladder ~= nil, "a ladder for step " .. i)
			t.ok(math.abs(ladder.CFrame.Position.Y + ladder.Size.Y / 2 - h) < 1e-3, "the ladder reaches step " .. i)
		end
		local plinth = named(m, "Plinth")[1]
		t.eq(plinth:GetAttribute("UniqueSpot"), true)
		t.ok(
			math.abs(plinth.CFrame.Position.X - MesaData.UniqueSpot.x) < 1e-3
				and math.abs(plinth.CFrame.Position.Z - MesaData.UniqueSpot.z) < 1e-3
		)
	end)

	t.test("the Bayou's rare plinth stands at B's anchor, with the rare line facing the landing", function()
		local m = RegionArt.RarePlinth(parent(), flat)
		local plinth = named(m, "Plinth")[1]
		t.eq(plinth:GetAttribute("UniqueSpot"), true)
		t.ok(math.abs(plinth.CFrame.Position.X - BayouData.UniqueSpot.x) < 1e-3)
		local sign = named(m, "RareSign")[1]
		local l = BayouData.Landing
		local toward = V3.new(l.x - sign.CFrame.Position.X, 0, l.z - sign.CFrame.Position.Z).Unit
		t.ok(sign.CFrame.LookVector:Dot(toward) > 0.99, "the sign faces the landing")
		t.eq(
			sign:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel").Text,
			"Something rare lives here"
		)
	end)

	t.test("every scatter kind builds in 10 parts or fewer and is looks only", function()
		local kinds = {}
		for _, k in ipairs(BayouData.ScatterKinds) do
			table.insert(kinds, k)
		end
		for _, k in ipairs(MesaData.ScatterKinds) do
			table.insert(kinds, k)
		end
		for _, kind in ipairs(kinds) do
			for seed = 1, 20 do
				local piece = RegionArt.Scatter(kind, seed)
				t.ok(piece ~= nil, kind)
				local n = RegionArt.PartCount(piece)
				t.ok(n >= 1 and n <= 10, kind .. ": " .. n .. " parts")
				for _, p in ipairs(parts(piece)) do
					t.eq(p.CanCollide, false, kind .. " collides")
					t.eq(p.CanQuery, false, kind .. " is queryable")
					t.eq(p.CanTouch, false, kind .. " is touchable")
				end
			end
		end
		t.eq(RegionArt.Scatter("nope", 1), nil)
	end)

	t.test("the part counts the boot report prints", function()
		local p = parent()
		local report = {
			boardwalk = RegionArt.PartCount(RegionArt.Boardwalk(p, flat)),
			baitShack = RegionArt.PartCount(RegionArt.BaitShack(p, flat, 1.4)),
			overlook = RegionArt.PartCount(RegionArt.Overlook(p, flat)),
			arch = RegionArt.PartCount(RegionArt.Arch(p, flat)),
			quarry = RegionArt.PartCount(RegionArt.QuarryFace(p, flat)),
			butte = RegionArt.PartCount(RegionArt.Butte(p, flat)),
		}
		print(
			string.format(
				"  region parts: boardwalk %d, bait shack %d, overlook %d, arch %d, quarry %d, butte %d",
				report.boardwalk,
				report.baitShack,
				report.overlook,
				report.arch,
				report.quarry,
				report.butte
			)
		)
		t.ok(report.boardwalk <= RegionArt.Caps.boardwalk and report.baitShack <= RegionArt.Caps.baitShack)
		t.ok(report.overlook <= RegionArt.Caps.overlook and report.arch <= RegionArt.Caps.arch)
	end)
end
