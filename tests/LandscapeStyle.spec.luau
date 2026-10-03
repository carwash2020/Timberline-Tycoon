--!nocheck
-- The landscape's look, nudged toward Lumber Tycoon 2 (phase 10, STY-*;
-- taken further in phase 12, ATMOS), keeping the cozy low-poly palette:
--   STY-01 a dark, muted meadow green and brown rock (TerrainGen.MaterialColors).
--   STY-02 the haul roads: pale grey road their whole width (phase 12; phase
--          10 laid a pale gravel crown between dirt verges).
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

	t.test("STY-01: the meadow is a dark, muted green, LeafyGrass a step darker, still the cozy hue", function()
		-- The colours before phase 10, and phase 10's first step (STY-01).
		-- Phase 12 (ATMOS) took the home meadow on to the classic dark, muted
		-- green: clearly darker than phase 10's and a little less saturated.
		local oldGrass = Color3.fromRGB(116, 170, 74)
		local oldLeafy = Color3.fromRGB(86, 140, 62)
		local p10Grass = Color3.fromRGB(100, 152, 64)
		local p10Leafy = Color3.fromRGB(76, 126, 54)
		local grass, leafy = colors.Grass, colors.LeafyGrass
		local function sat(c)
			local _, s = c:ToHSV()
			return s
		end
		for _, set in ipairs({ { "Grass", grass, oldGrass, p10Grass }, { "LeafyGrass", leafy, oldLeafy, p10Leafy } }) do
			local name, now, was, p10 = set[1], set[2], set[3], set[4]
			-- Dark: 15-35% darker than the original (still a meadow, not a bog).
			local drop = 1 - lum(now) / lum(was)
			t.ok(
				drop >= 0.15 and drop <= 0.35,
				string.format("%s is %.0f%% darker than the original", name, drop * 100)
			)
			-- Clearly darker than phase 10's step, not a nudge.
			t.ok(lum(now) <= lum(p10) * 0.92, name .. " is clearly darker than phase 10's")
			-- Muted: a little less saturated than phase 10's, still a real green.
			t.ok(sat(now) < sat(p10), string.format("%s is less saturated (%.3f)", name, sat(now)))
			t.ok(sat(now) > sat(p10) - 0.1, string.format("%s stays a green, not a grey (%.3f)", name, sat(now)))
			-- Still a meadow green, the same family as before (never olive-brown).
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
	-- A haul-road junction flare is pale past the road's own edge, on purpose.
	local function inHaulJunction(x, z)
		for _, junction in ipairs(WorldLayout.Junctions) do
			if
				junction.haul
				and (Vector2.new(x, z) - junction.at).Magnitude < junction.radius - TerrainGen.GravelEdge + 0.81
			then
				return true
			end
		end
		return false
	end

	-- Phase 12 (ATMOS) changed the rule: phase 10 laid a pale beige gravel
	-- crown (182, 174, 158) between dirt verges 3 studs wide; now a haul road
	-- is pale grey road its whole width, the classic way, its edge fraying
	-- into dirt for a stud or so at most.

	t.test("STY-02: the pale road is a real terrain material of its own, a light, cool grey", function()
		t.ok(t.roblox.Enum.Material[GRAVEL] ~= nil, GRAVEL .. " is an Enum.Material")
		for _, used in ipairs({ "Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Rock", "Snow", "Glacier" }) do
			t.ok(used ~= GRAVEL, "the road isn't " .. used)
		end
		for _, used in ipairs({ "Basalt", "Slate", "CrackedLava", "Cobblestone" }) do
			t.ok(used ~= GRAVEL, "the road isn't " .. used)
		end
		local c = colors[GRAVEL]
		t.ok(c ~= nil, "the road has a colour in MaterialColors (TerrainBuilder's setLook applies it)")
		local _, s, v = c:ToHSV()
		t.ok(s < 0.06, "grey: hardly any colour in it")
		t.ok(v > 0.6, "pale")
		t.ok(lum(c) > lum(colors.Ground) * 1.25, "much paler than dirt")
		-- Cooler and greyer than phase 10's beige: a neutral light grey, a
		-- hair warm at most, never blue, pink or green.
		local r, g, b = rgb(c)
		t.ok(r - b >= 0 and r - b <= 8, string.format("a neutral grey, not beige (%d, %d, %d)", r, g, b))
		t.ok(math.abs(r - g) <= 4, string.format("neither pink nor green (%d, %d, %d)", r, g, b))
		for name, other in pairs(colors) do
			if name ~= GRAVEL then
				local d = math.max(math.abs(c.R - other.R), math.abs(c.G - other.G), math.abs(c.B - other.B))
				t.ok(d > 4 / 255, "the road's colour is its own, not " .. name .. "'s")
			end
		end
	end)

	t.test(
		"STY-02: out in the country every haul road is pale road its whole width, a thin dirt edge at most",
		function()
			local edge = TerrainGen.GravelEdge
			t.ok(edge >= 0 and edge <= 1.5, "the dirt edge is thin")
			for _, name in ipairs(TerrainGen.HaulRoads) do
				local road = roadNamed(name)
				t.ok(road ~= nil, name .. " is a road")
				local half = road.width / 2
				-- Inside the pale surface's frayed edge (it wanders 0.8 either way):
				-- pale every time. Dirt only in that frayed edge: the outer couple
				-- of studs each side, so at least three quarters of the road's
				-- width is pale (more on the wider roads to come). (A terrain voxel
				-- is 4 studs: in game the dirt is the odd edge voxel.)
				local solid = half - edge - 0.85
				local centre, inside, pale, across, paleAcross = 0, 0, 0, 0, 0
				for _, s in ipairs(along(road, 9)) do
					local p = s.p
					if WorldLayout.FlatWeight(p.X, p.Y) <= 0 then
						centre += 1
						for off = -half, half, 0.5 do
							local q = p + s.side * off
							-- Only where this road is the nearest (not at a fork).
							if nearestRoad(q.X, q.Y) == road then
								local m = materialAt(q.X, q.Y)
								across += 1
								paleAcross += if m == GRAVEL then 1 else 0
								if math.abs(off) <= solid then
									inside += 1
									pale += if m == GRAVEL then 1 else 0
								end
							end
						end
					end
				end
				t.ok(centre > 10, name .. " runs through the country")
				t.ok(inside > centre * 10, name .. " has its middle checked")
				t.eq(pale, inside, name .. ": pale all the way across")
				t.ok(
					paleAcross / across >= 0.75,
					string.format("%s: %.0f%% of its width is pale road", name, paleAcross / across * 100)
				)
			end
		end
	)

	t.test("STY-02: the pale road is only on the haul roads, never in town, on the plots or anywhere else", function()
		local seen = 0
		local haul = {}
		for _, name in ipairs(TerrainGen.HaulRoads) do
			haul[name] = true
		end
		-- Across every road, from edge to edge and a little past.
		for _, road in ipairs(WorldLayout.Roads) do
			local half = road.width / 2
			for _, s in ipairs(along(road, 3)) do
				for off = -half - 2, half + 2, 1.5 do
					local q = s.p + s.side * off
					if materialAt(q.X, q.Y) == GRAVEL then
						seen += 1
						local nearest, edge = nearestRoad(q.X, q.Y)
						local x, z = q.X, q.Y
						t.ok(haul[nearest.name], string.format("pale road at (%d, %d) on %s", x, z, nearest.name))
						-- On the road (its pale edge ends GravelEdge in from the
						-- road's, give or take 0.8), never out on the grass.
						local nh = nearest.width / 2
						t.ok(
							edge + nh <= nh - TerrainGen.GravelEdge + 0.81 or inHaulJunction(x, z),
							string.format("pale road at (%d, %d) past the road's edge", x, z)
						)
						t.ok(WorldLayout.FlatWeight(x, z) < 0.6, string.format("pale road at (%d, %d) in town", x, z))
					end
				end
			end
		end
		t.ok(seen > 4000, seen .. " pale road samples")
		-- Far from any road, never: a coarse sweep of the rest of the map.
		for x = -1490, 1490, 37 do
			for z = -1490, 1490, 37 do
				local _, edge = nearestRoad(x, z)
				if edge > 2 and not inHaulJunction(x, z) then
					t.ok(materialAt(x, z) ~= GRAVEL, string.format("pale road off the roads at (%d, %d)", x, z))
				end
			end
		end
	end)

	t.test("STY-02: the town's roads, street and paths stay dirt", function()
		-- The Hills Road and the Snow Road where they run through town (the
		-- pale road frays into the town's dirt where its flat ground begins),
		-- the Forest Path, the plot district's road and lanes.
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
