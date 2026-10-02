--!nocheck
-- The landscape's look, nudged toward Lumber Tycoon 2 (phase 10, STY-*),
-- keeping the cozy low-poly palette:
--   STY-01 a deeper meadow green and brown rock (TerrainGen.MaterialColors).
--   STY-02 the haul roads' pale gravel crown between dirt verges.
--   STY-03 brown boulders (LandmarkArt.BrownRock; WorldPlan.spec and
--          MapBuilder.spec check where the clusters go and how they build).
return function(t)
	local Color3 = t.roblox.Color3
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local colors = TerrainGen.MaterialColors

	local function rgb(c)
		return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
	end
	local function lum(c)
		return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	end
	local function hue(c)
		local h = c:ToHSV()
		return h
	end

	---------------------------------------------------------------------------
	-- STY-01: the palette
	---------------------------------------------------------------------------

	t.test("STY-01: snow, sand, the volcano, the grove, dirt and cobbles keep their colours", function()
		local kept = {
			Snow = { 238, 244, 250 },
			Glacier = { 172, 214, 236 },
			Sand = { 226, 205, 150 },
			Basalt = { 52, 46, 44 },
			Slate = { 74, 66, 62 },
			CrackedLava = { 255, 108, 30 },
			Mud = { 64, 50, 72 }, -- the Phantom Grove's violet floor
			Ground = { 150, 116, 78 }, -- dirt: road verges, the town's street and paths
			Cobblestone = { 170, 160, 146 }, -- the plaza
		}
		for name, want in pairs(kept) do
			t.eq({ rgb(colors[name]) }, want, name)
		end
	end)

	t.test("STY-01: the meadow is a deeper green, LeafyGrass a step darker, still the cozy hue", function()
		local oldGrass = Color3.fromRGB(116, 170, 74)
		local oldLeafy = Color3.fromRGB(86, 140, 62)
		local grass, leafy = colors.Grass, colors.LeafyGrass
		for _, pair in ipairs({ { "Grass", grass, oldGrass }, { "LeafyGrass", leafy, oldLeafy } }) do
			local name, now, was = pair[1], pair[2], pair[3]
			-- Deeper: 5-20% darker than before (moderate: still recognisable).
			local drop = 1 - lum(now) / lum(was)
			t.ok(drop >= 0.05 and drop <= 0.2, string.format("%s is %.0f%% darker than before", name, drop * 100))
			-- Still a warm meadow green, the same family as before.
			t.ok(math.abs(hue(now) - hue(was)) < 0.03, name .. " keeps its hue")
			t.ok(now.G > now.R * 1.3 and now.G > now.B * 2, name .. " is green")
		end
		-- The swaths stay readable: LeafyGrass a visible step darker than Grass.
		t.ok(lum(leafy) < lum(grass) * 0.88, "LeafyGrass is a step darker than Grass")
	end)

	t.test("STY-01: rock is brown: warmer than the old grey, darker than dirt, never green", function()
		local rock, ground = colors.Rock, colors.Ground
		local r, g, b = rgb(rock)
		t.ok(r > g and g > b, string.format("rock %d,%d,%d runs red > green > blue (brown)", r, g, b))
		t.ok(r - b >= 30, "rock is warm enough to read brown, not grey")
		-- The old grey was 128,122,114 (R - B = 14).
		t.ok(r - b > 128 - 114 + 15, "warmer than the old grey rock")
		-- Darker and duller than the dirt roads, so a cliff never reads as a road.
		t.ok(lum(rock) < lum(ground) * 0.9, "rock is darker than dirt")
		local _, rs = rock:ToHSV()
		local _, gs = ground:ToHSV()
		t.ok(rs < gs, "rock is less saturated than dirt")
	end)

	---------------------------------------------------------------------------
	-- STY-02: haul roads that read as roads
	---------------------------------------------------------------------------

	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Vector2 = t.roblox.Vector2
	local GRAVEL = TerrainGen.GravelMaterial

	local function materialAt(x, z)
		local _, m = TerrainGen.Sample(x, z)
		return m
	end
	local function roadNamed(name)
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				return road
			end
		end
		return nil
	end
	-- Points along a road every `step` studs, with the stretch's sideways unit.
	local function along(road, step)
		local out = {}
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local len = (b - a).Magnitude
			local dir = (b - a).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			for s = 0, len, step do
				table.insert(out, { p = a + dir * s, side = side })
			end
		end
		return out
	end
	-- How far (x, z) is from a road's centreline.
	local function fromCentre(road, x, z)
		return WorldLayout.PolylineDistance(Vector2.new(x, z), road.points)
	end
	local function nearestRoad(x, z)
		local best, bestRoad = math.huge, nil
		for _, road in ipairs(WorldLayout.Roads) do
			local d = fromCentre(road, x, z) - road.width / 2
			if d < best then
				best, bestRoad = d, road
			end
		end
		return bestRoad, best
	end

	t.test("STY-02: the gravel is a real terrain material of its own, pale grey-beige", function()
		t.ok(t.roblox.Enum.Material[GRAVEL] ~= nil, GRAVEL .. " is an Enum.Material")
		for _, used in ipairs({ "Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Rock", "Snow", "Glacier" }) do
			t.ok(used ~= GRAVEL, "the gravel isn't " .. used)
		end
		for _, used in ipairs({ "Basalt", "Slate", "CrackedLava", "Cobblestone" }) do
			t.ok(used ~= GRAVEL, "the gravel isn't " .. used)
		end
		local c = colors[GRAVEL]
		t.ok(c ~= nil, "the gravel has a colour in MaterialColors (TerrainBuilder's setLook applies it)")
		local _, s, v = c:ToHSV()
		t.ok(s < 0.2, "grey-beige: barely saturated")
		t.ok(v > 0.6, "pale")
		t.ok(lum(c) > lum(colors.Ground) * 1.15, "paler than the dirt verges")
		t.ok(c.R >= c.G and c.G >= c.B, "a warm grey (beige), not a cold one")
		for name, other in pairs(colors) do
			if name ~= GRAVEL then
				local d = math.max(math.abs(c.R - other.R), math.abs(c.G - other.G), math.abs(c.B - other.B))
				t.ok(d > 4 / 255, "the gravel's colour is its own, not " .. name .. "'s")
			end
		end
	end)

	t.test("STY-02: every haul road's crown is gravel out in the country, its verges dirt", function()
		for _, name in ipairs(TerrainGen.HaulRoads) do
			local road = roadNamed(name)
			t.ok(road ~= nil, name .. " is a road")
			local half = road.width / 2
			local crown = math.max(half - TerrainGen.GravelVerge, TerrainGen.GravelLeast)
			local centre, gravel, verges, dirt = 0, 0, 0, 0
			for _, s in ipairs(along(road, 9)) do
				local p = s.p
				if WorldLayout.FlatWeight(p.X, p.Y) <= 0 then
					centre += 1
					if materialAt(p.X, p.Y) == GRAVEL then
						gravel += 1
					end
					-- Both verges: past the gravel's frayed edge, short of the dirt's.
					local off = (crown + 0.85 + half - 1.25) / 2
					for _, sign in ipairs({ -1, 1 }) do
						local q = p + s.side * (sign * off)
						-- Only where this road is the nearest (not at a fork).
						local nearest = nearestRoad(q.X, q.Y)
						if nearest == road and math.abs(fromCentre(road, q.X, q.Y) - off) < 0.01 then
							verges += 1
							if materialAt(q.X, q.Y) == "Ground" then
								dirt += 1
							end
						end
					end
				end
			end
			t.ok(centre > 10, name .. " runs through the country")
			t.eq(gravel, centre, name .. ": gravel all along its crown")
			t.ok(verges > 10, name .. " has verges checked")
			t.ok(dirt / verges >= 0.95, string.format("%s: %d of %d verge points are dirt", name, dirt, verges))
		end
	end)

	t.test("STY-02: the gravel is only on the haul roads, never in town, on the plots or anywhere else", function()
		local seen = 0
		local haul = {}
		for _, name in ipairs(TerrainGen.HaulRoads) do
			haul[name] = true
		end
		-- Across every road, from verge to verge and a little past.
		for _, road in ipairs(WorldLayout.Roads) do
			local half = road.width / 2
			for _, s in ipairs(along(road, 3)) do
				for off = -half - 2, half + 2, 1.5 do
					local q = s.p + s.side * off
					if materialAt(q.X, q.Y) == GRAVEL then
						seen += 1
						local nearest, edge = nearestRoad(q.X, q.Y)
						local x, z = q.X, q.Y
						t.ok(haul[nearest.name], string.format("gravel at (%d, %d) on %s", x, z, nearest.name))
						-- Within the crown (and its frayed edge), never out on a verge.
						local nh = nearest.width / 2
						local crown = math.max(nh - TerrainGen.GravelVerge, TerrainGen.GravelLeast)
						t.ok(edge + nh <= crown + 0.81, string.format("gravel at (%d, %d) on the verge", x, z))
						t.ok(nh - crown >= 2.5, nearest.name .. " keeps dirt verges 2.5+ studs wide")
						t.ok(WorldLayout.FlatWeight(x, z) < 0.6, string.format("gravel at (%d, %d) in town", x, z))
					end
				end
			end
		end
		t.ok(seen > 2000, seen .. " gravel samples")
		-- Far from any road, never: a coarse sweep of the rest of the map.
		for x = -1490, 1490, 37 do
			for z = -1490, 1490, 37 do
				local _, edge = nearestRoad(x, z)
				if edge > 2 then
					t.ok(materialAt(x, z) ~= GRAVEL, string.format("gravel off the roads at (%d, %d)", x, z))
				end
			end
		end
	end)

	t.test("STY-02: the town's roads, street and paths stay dirt", function()
		-- The Hills Road and the Forest Path where they run through town,
		-- the plot district's road and lanes.
		for _, name in ipairs({ "ForestPath", "PlotRoad", "PlotLane", "HillsRoad", "SnowRoad" }) do
			for _, road in ipairs(WorldLayout.Roads) do
				if road.name == name then
					for _, s in ipairs(along(road, 5)) do
						local p = s.p
						if WorldLayout.FlatWeight(p.X, p.Y) > 0.6 then
							local m = materialAt(p.X, p.Y)
							t.ok(m ~= GRAVEL, string.format("%s at (%d, %d) is %s in town", name, p.X, p.Y, m))
						end
					end
				end
			end
		end
	end)

	---------------------------------------------------------------------------
	-- STY-03: brown boulders (WorldPlan.spec checks where the clusters go)
	---------------------------------------------------------------------------

	t.test("STY-03: a brown rock is PropArt.Rock in a brown tone, its blocks colliding, moss when asked", function()
		local LandmarkArt = t.load("ReplicatedStorage/Shared/Art/LandmarkArt")
		for _, tone in ipairs({ 1, 2 }) do
			for _, palette in ipairs({ LandmarkArt.ROCK_TONES[tone] }) do
				for _, c in ipairs(palette) do
					t.ok(c.R > c.G and c.G > c.B and c.R - c.B >= 20 / 255, "a brown in tone " .. tone)
				end
			end
			for seed = 1, 12 do
				local mossy = seed % 2 == 0
				local model = LandmarkArt.BrownRock(6, seed * 31, tone, mossy)
				local hard, moss = 0, 0
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then
						t.ok(p.Anchored, "anchored")
						if p.CanCollide then
							hard += 1
							local r, g, b = rgb(p.Color)
							t.ok(r > b + 10 and r >= g, string.format("a block %d,%d,%d reads brown", r, g, b))
						end
						if p.Name == "Moss" then
							moss += 1
							t.eq(p.CanCollide, false, "moss is looks only")
						end
					end
				end
				t.eq(hard, 3)
				t.eq(moss, if mossy then 1 else 0)
			end
		end
	end)
	t.test(
		"STY-03: every rock out in the green is brown: lone boulders, outcrops and clusters share one palette",
		function()
			local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
			local LandmarkArt = t.load("ReplicatedStorage/Shared/Art/LandmarkArt")
			t.eq(LandmarkArt.ROCK_TONES, PropArt.BrownTones)
			local function brown(c)
				local r, g, b = rgb(c)
				return r > b + 15 and r >= g
			end
			for seed = 1, 6 do
				local outcrop = PropArt.Outcrop(seed)
				local stones = 0
				for _, d in ipairs(outcrop:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Rock" then
						stones += 1
						t.ok(brown(d.Color), string.format("outcrop %d stone %d,%d,%d", seed, rgb(d.Color)))
					end
				end
				t.ok(stones >= 9, "an outcrop has its stones")
			end
			-- MapBuilder colours the lone boulders the same way (snowy and
			-- volcanic ones keep their own).
			local src = require("@lune/fs").readFile("src/ServerScriptService/MapBuilder.server.luau")
			t.ok(
				string.find(src, "else PropArt.BrownTones[b.seed % 2 + 1]", 1, true) ~= nil,
				"MapBuilder's lone boulders are brown"
			)
		end
	)
end
