--!nocheck
-- PropArt: every prop builds, stays cheap (clients scatter hundreds), is
-- decoration only (Rock's stones and the open-country set pieces' big
-- bodies aside, COL-01; Scatter's are all decoration), sits on the
-- ground, is placed with CFrame only and comes out the same for the same
-- seed; the biome mixes only name props that exist.

return function(t)
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local BiomeData = t.shared("BiomeData")
	local Color3, Vector3 = t.roblox.Color3, t.roblox.Vector3

	local tints = PropArt.Tints("starter")
	local ICE = Color3.fromRGB(159, 230, 255)

	-- name -> (builder(seed), part budget)
	local PROPS = {
		{
			"Rock",
			function(s)
				return PropArt.Rock(3, s)
			end,
			6,
		},
		{
			"Pebbles",
			function(s)
				return PropArt.Pebbles(s)
			end,
			6,
		},
		{
			"LavaRock",
			function(s)
				return PropArt.LavaRock(s, 2.5)
			end,
			8,
		},
		{
			"Crystal",
			function(s)
				return PropArt.Crystal(s, ICE, 2)
			end,
			8,
		},
		{
			"Bush",
			function(s)
				return PropArt.Bush(3, s, tints.leaves)
			end,
			6,
		},
		{
			"BerryBush",
			function(s)
				return PropArt.BerryBush(s)
			end,
			10,
		},
		{
			"Flowers",
			function(s)
				return PropArt.Flowers(s, tints.flowers)
			end,
			10,
		},
		{
			"GrassTuft",
			function(s)
				return PropArt.GrassTuft(s, tints.grass)
			end,
			9, -- 5-7 fanned blades and 2 sunlit tips (FOR-04)
		},
		{
			"Fern",
			function(s)
				return PropArt.Fern(s, tints.grass)
			end,
			8,
		},
		{
			"Reeds",
			function(s)
				return PropArt.Reeds(s)
			end,
			8,
		},
		{
			"Cattails",
			function(s)
				return PropArt.Cattails(s)
			end,
			10,
		},
		{
			"LilyPad",
			function(s)
				return PropArt.LilyPad(s)
			end,
			7,
		},
		{
			"Mushroom",
			function(s)
				return PropArt.Mushroom(s, false)
			end,
			8,
		},
		{
			"Mushroom (glowing)",
			function(s)
				return PropArt.Mushroom(s, true)
			end,
			8,
		},
		{
			"Pinecones",
			function(s)
				return PropArt.Pinecones(s)
			end,
			8,
		},
		{
			"SnowPile",
			function(s)
				return PropArt.SnowPile(s, 4)
			end,
			4,
		},
		{
			"FallenLog",
			function(s)
				return PropArt.FallenLog(s, tints.bark, tints.moss)
			end,
			10,
		},
		{
			"Stump",
			function(s)
				return PropArt.Stump(s, tints.bark, tints.moss)
			end,
			10,
		},
		{
			"DeadBranch",
			function(s)
				return PropArt.DeadBranch(s)
			end,
			4,
		},
		{
			"Outcrop",
			function(s)
				return PropArt.Outcrop(s)
			end,
			25,
		},
		{
			"RuinedCabin",
			function(s)
				return PropArt.RuinedCabin(s)
			end,
			25,
		},
		{
			"Windmill",
			function(s)
				return PropArt.Windmill(s)
			end,
			25,
		},
		{
			"LookoutTower",
			function(s)
				return PropArt.LookoutTower(s)
			end,
			25,
		},
	}

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Half the part's extent along world Y (exact for blocks).
	local function halfHeight(p)
		local cf, s = p.CFrame, p.Size
		return 0.5 * (math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z)
	end

	t.test("every prop builds within its part budget", function()
		for _, prop in ipairs(PROPS) do
			for seed = 1, 30 do
				local model = prop[2](seed)
				t.ok(model:IsA("Model"), prop[1] .. " returns a Model")
				local n = #parts(model)
				t.ok(n > 0, prop[1] .. " has parts")
				t.ok(n <= prop[3], string.format("%s seed %d: %d parts (budget %d)", prop[1], seed, n, prop[3]))
			end
		end
	end)

	-- What collides in each prop (COL-01): a boulder's (and an outcrop's)
	-- stones and the open-country set pieces' big bodies. The rest of every
	-- prop is decoration.
	local SOLID = {
		Rock = { Rock = true },
		Outcrop = { Rock = true },
		RuinedCabin = {
			Footing = true,
			Floor = true,
			WallLog = true,
			CornerPost = true,
			Chimney = true,
			FallenRoof = true,
		},
		Windmill = { MillBase = true, Tower = true },
		LookoutTower = { Leg = true, Deck = true, Rail = true, Ladder = true },
	}

	t.test("props are decoration but for Rock's stones and the set pieces' big bodies (COL-01)", function()
		for _, prop in ipairs(PROPS) do
			local solidNames = SOLID[prop[1]] or {}
			for seed = 1, 8 do
				local seen = {}
				for _, p in ipairs(parts(prop[2](seed))) do
					t.ok(p.Anchored, prop[1] .. " parts are anchored")
					if solidNames[p.Name] then
						seen[p.Name] = true
						t.ok(p.CanCollide and p.CanQuery, prop[1] .. ": " .. p.Name .. " collides and can be clicked")
					else
						t.ok(
							not p.CanCollide and not p.CanQuery and not p.CanTouch,
							prop[1] .. ": " .. p.Name .. " is decoration"
						)
					end
				end
				-- Every one of them is there to bump into.
				for name in pairs(solidNames) do
					t.ok(seen[name], string.format("%s seed %d has a solid %s", prop[1], seed, name))
				end
			end
		end
	end)

	t.test("COL-01: every outcrop rock, cabin wall, windmill tower and lookout leg collides", function()
		for seed = 1, 30 do
			local stones = 0
			for _, p in ipairs(parts(PropArt.Outcrop(seed))) do
				if p.Name == "Rock" then
					stones += 1
					t.ok(p.CanCollide, "an outcrop's stone collides")
				end
			end
			t.ok(stones >= 9 and stones <= 12, "3 stones a rock, 3-4 rocks: " .. stones)
			local counts = {}
			for _, model in ipairs({ PropArt.RuinedCabin(seed), PropArt.Windmill(seed), PropArt.LookoutTower(seed) }) do
				for _, p in ipairs(parts(model)) do
					if p.CanCollide then
						counts[p.Name] = (counts[p.Name] or 0) + 1
					end
				end
			end
			t.eq(counts.Footing, 4, "the cabin's four footing courses")
			t.eq(counts.WallLog, 6, "its wall logs")
			t.eq(counts.CornerPost, 2)
			t.eq(counts.Chimney, 2)
			t.eq(counts.FallenRoof, 1)
			t.eq(counts.Floor, 1)
			t.eq(counts.MillBase, 1, "the windmill's base")
			t.eq(counts.Tower, 2, "and its tower")
			t.eq(counts.Leg, 4, "the lookout's legs")
			t.eq(counts.Deck, 1)
			t.eq(counts.Rail, 4)
			t.eq(counts.Ladder, 2)
			-- The trim stays walk-through.
			t.eq(counts.Sail, nil)
			t.eq(counts.Spar, nil)
			t.eq(counts.Brace, nil)
			t.eq(counts.Rung, nil)
			t.eq(counts.Board, nil)
		end
	end)

	t.test("a boulder has three stones you can climb", function()
		local stones = 0
		for _, p in ipairs(parts(PropArt.Rock(5, 7))) do
			if p.Name == "Rock" then
				stones += 1
			end
		end
		t.eq(stones, 3)
	end)

	t.test("props sit on the ground: nothing floats, nothing is buried", function()
		for _, prop in ipairs(PROPS) do
			for seed = 1, 20 do
				local low, high = math.huge, -math.huge
				for _, p in ipairs(parts(prop[2](seed))) do
					low = math.min(low, p.CFrame.Y - halfHeight(p))
					high = math.max(high, p.CFrame.Y + halfHeight(p))
				end
				t.ok(low <= 0.1, string.format("%s seed %d floats (lowest %.2f)", prop[1], seed, low))
				t.ok(high > 0.08, string.format("%s seed %d is buried (highest %.2f)", prop[1], seed, high))
			end
		end
	end)

	t.test("lily pads lie flat on the water", function()
		for seed = 1, 20 do
			for _, p in ipairs(parts(PropArt.LilyPad(seed))) do
				t.ok(p.CFrame.Y - halfHeight(p) > -0.1, "nothing sinks below the surface")
				t.ok(p.CFrame.Y + halfHeight(p) < 0.8, "nothing stands tall on a lily pad")
			end
		end
	end)

	t.test("parts are placed with CFrame, never Position", function()
		for _, prop in ipairs(PROPS) do
			for _, p in ipairs(parts(prop[2](3))) do
				local setPosition = pcall(function()
					return p.Position
				end)
				t.ok(not setPosition, prop[1] .. ": " .. p.Name .. " was placed with .Position")
			end
		end
	end)

	t.test("the same seed builds the same prop", function()
		for _, prop in ipairs(PROPS) do
			local a, b = parts(prop[2](11)), parts(prop[2](11))
			t.eq(#a, #b, prop[1] .. " part count")
			for i = 1, #a do
				t.ok((a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-6, prop[1] .. " is deterministic")
				t.eq(a[i].Color, b[i].Color)
			end
		end
	end)

	t.test("glowing mushrooms glow; the others wear spots", function()
		local glow, plain = PropArt.Mushroom(4, true), PropArt.Mushroom(4, false)
		t.ok(glow:FindFirstChildWhichIsA("PointLight", true) ~= nil, "a glowing mushroom has a light")
		t.ok(glow:FindFirstChild("Spot") == nil, "no spots on a glowing cap")
		t.ok(plain:FindFirstChild("Spot") ~= nil, "a red cap has spots")
		t.ok(plain:FindFirstChildWhichIsA("PointLight", true) == nil, "plain mushrooms cast no light")
	end)

	t.test("every biome has tints, and its mix names only props that exist", function()
		for _, biome in ipairs(BiomeData.All()) do
			local tint = PropArt.Tints(biome.id)
			t.ok(
				tint.grass and tint.bark and tint.moss and #tint.leaves > 0 and #tint.flowers > 0 and #tint.stone > 0,
				biome.id
			)
		end
		for _, id in ipairs({
			"starter",
			"hills",
			"snow",
			"volcano",
			"grove",
			"sky",
			"island",
			"beach",
			"shore",
			"water",
		}) do
			local mix = PropArt.Mix(id)
			t.ok(#mix > 0, id .. " has a mix")
			for _, entry in ipairs(mix) do
				t.ok(entry.weight > 0, id .. ": " .. entry.name .. " has a weight")
				t.ok(PropArt.Build(entry.name, 5, id) ~= nil, id .. ": " .. entry.name .. " builds")
			end
		end
		t.eq(PropArt.Build("Nope", 1, "starter"), nil)
	end)

	t.test("Scatter is decoration only, varied and deterministic", function()
		for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove", "sky", "island" }) do
			local seen = {}
			for seed = 1, 60 do
				local model = PropArt.Scatter(id, seed)
				seen[model.Name] = true
				for _, p in ipairs(parts(model)) do
					t.ok(
						not p.CanCollide and not p.CanQuery and not p.CanTouch,
						id .. ": scattered " .. model.Name .. " is decoration"
					)
				end
			end
			local kinds = 0
			for _ in pairs(seen) do
				kinds += 1
			end
			t.ok(kinds >= 4, id .. " scatters at least four kinds of prop")
			t.eq(PropArt.Scatter(id, 42).Name, PropArt.Scatter(id, 42).Name)
		end
		t.eq(PropArt.Scatter("starter", 3, "water").Name, "LilyPad")
	end)

	-- NAT-13: decor logs and stumps read as old, never as a fresh one.
	t.test("decor logs and stumps are weathered, rotten-topped, sunk and sprout mushrooms", function()
		local BARK = Color3.fromHex("#6E5038")
		local aged = BARK:Lerp(Color3.fromHex("#6E6A58"), 0.35)
		local function near(a, b, tol)
			return math.abs(a.R - b.R) <= tol and math.abs(a.G - b.G) <= tol and math.abs(a.B - b.B) <= tol
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
		local fresh = Color3.fromHex("#D9B98A") -- the pale heartwood they used to show
		for seed = 1, 20 do
			for _, case in ipairs({
				{ PropArt.FallenLog(seed), "Log", "LogEnd" },
				{ PropArt.Stump(seed), "StumpBody", "StumpTop" },
			}) do
				local model, bodyName, cutName = case[1], case[2], case[3]
				local body = named(model, bodyName)[1]
				t.ok(body, bodyName .. " exists")
				t.ok(near(body.Color, aged, 0.05), bodyName .. ": bark weathered 35% toward #6E6A58")
				local cut = named(model, cutName)[1]
				local _, _, value = cut.Color:ToHSV()
				t.ok(value < 0.5 and not near(cut.Color, fresh, 0.15), cutName .. " is rotten, not pale heartwood")
				t.ok(#named(model, "Mushroom") >= 2, model.Name .. " has a mushroom (stalk and cap)")
				-- Sunk 0.2 deeper than before: the body's bottom is 0.2 lower.
				local bottom = body.CFrame.Y - halfHeight(body)
				t.ok(bottom < -0.3, string.format("%s seed %d: sunk to %.2f", bodyName, seed, bottom))
			end
		end
	end)

	t.test("the open-country set pieces (WLD-01): SetPiece builds each; outcrops are 3-4 big rocks", function()
		for _, name in ipairs({ "Outcrop", "RuinedCabin", "Windmill", "LookoutTower" }) do
			local model = PropArt.SetPiece(name, 9)
			t.ok(model and model.Name == name, name .. " builds")
			for _, p in ipairs(parts(model)) do
				local s = p.Size
				if math.max(s.X, s.Y, s.Z) < 1 then
					t.eq(p.CastShadow, false, name .. ": a small " .. p.Name .. " casts a shadow")
				end
			end
		end
		t.eq(PropArt.SetPiece("Nope", 1), nil)
		local function solidReach(rock)
			local far = 0
			for _, p in ipairs(parts(rock)) do
				if p.CanCollide then
					local h = p.Size / 2
					for _, sx in ipairs({ -1, 1 }) do
						for _, sy in ipairs({ -1, 1 }) do
							for _, sz in ipairs({ -1, 1 }) do
								local w = p.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
								far = math.max(far, math.sqrt(w.X * w.X + w.Z * w.Z))
							end
						end
					end
				end
			end
			return far
		end
		-- Seed 87250 is the one whose tipped satellite used to reach 16.3,
		-- past the outcrop footprint (radius 15, one stud of slack).
		local seeds = {}
		for seed = 1, 30 do
			table.insert(seeds, seed)
		end
		table.insert(seeds, 87250)
		for _, seed in ipairs(seeds) do
			local rocks = PropArt.Outcrop(seed):GetChildren()
			t.ok(#rocks >= 3 and #rocks <= 4, "3-4 rocks")
			for _, rock in ipairs(rocks) do
				local widest = 0
				for _, p in ipairs(parts(rock)) do
					if p.Name == "Rock" then
						widest = math.max(widest, p.Size.X)
					end
				end
				-- Rock's body is 0.92 of its size across.
				t.ok(widest / 0.92 >= 6 - 1e-6 and widest / 0.92 <= 14 + 1e-6, "an outcrop's rocks are 6-14")
				t.ok(solidReach(rock) <= 16, string.format("seed %d rock stays inside the footprint", seed))
			end
		end
	end)
end
