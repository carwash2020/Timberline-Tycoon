--!nocheck
-- The landscape's look, nudged toward Lumber Tycoon 2 (phase 10, STY-*;
-- phase 12, ATMOS; and 7 October 2026, when Connor sent LT2 screenshots and
-- the ground went all the way: a flat, vivid green meadow, grey speckled
-- gravel roads, red-brown earth and cliffs):
--   STY-01 the palette (TerrainGen.MaterialColors).
--   STY-02 every road, path and street: light grey gravel their whole width.
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

	t.test("STY-01: snow, sand, the volcano, the grove and cobbles keep their colours", function()
		local kept = {
			Snow = { 238, 244, 250 },
			Glacier = { 172, 214, 236 },
			Sand = { 226, 205, 150 },
			Basalt = { 52, 46, 44 },
			Slate = { 74, 66, 62 },
			CrackedLava = { 255, 108, 30 },
			Mud = { 64, 50, 72 }, -- the Phantom Grove's violet floor
			Cobblestone = { 170, 160, 146 }, -- the plaza
		}
		for name, want in pairs(kept) do
			t.eq({ rgb(colors[name]) }, want, name)
		end
	end)

	-- 7 October 2026 (Connor, from Lumber Tycoon 2 screenshots): phase 12's
	-- "dark, muted meadow" is superseded. The ground is a flat, saturated,
	-- almost cartoon-bright mid-green; roads are light grey speckled gravel;
	-- dirt, cliffs and hill faces are warm red-brown.
	t.test("LT2: the meadow is a vivid, bright, flat green, the forest floor only a step darker", function()
		local oldGrass = Color3.fromRGB(84, 125, 55) -- phase 12's dark, muted green
		local oldLeafy = Color3.fromRGB(66, 104, 46)
		local grass, leafy = colors.Grass, colors.LeafyGrass
		local function sat(c)
			local _, s = c:ToHSV()
			return s
		end
		local function val(c)
			local _, _, v = c:ToHSV()
			return v
		end
		for _, set in ipairs({ { "Grass", grass, oldGrass }, { "LeafyGrass", leafy, oldLeafy } }) do
			local name, now, was = set[1], set[2], set[3]
			t.ok(lum(now) >= lum(was) * 1.2, name .. " is brighter than phase 12's dark green")
			t.ok(sat(now) >= 0.55, string.format("%s is saturated (%.2f)", name, sat(now)))
			t.ok(val(now) >= 0.6, string.format("%s is bright (%.2f)", name, val(now)))
			t.ok(hue(now) >= 0.22 and hue(now) <= 0.34, string.format("%s is a true green (hue %.2f)", name, hue(now)))
			t.ok(now.G > now.R * 1.4 and now.G > now.B * 2.5, name .. " is green")
		end
		-- The darker patches stay readable but gentle: LeafyGrass a small step down.
		t.ok(lum(leafy) < lum(grass) * 0.95, "LeafyGrass is a step darker than Grass")
		t.ok(lum(leafy) > lum(grass) * 0.7, "and only a step: the forest floor is not a bog")
	end)

	t.test("LT2: earth, cliffs and hill faces are warm red-brown, rock a step darker than dirt, never green", function()
		local rock, ground = colors.Rock, colors.Ground
		for name, c in pairs({ Rock = rock, Ground = ground }) do
			local r, g, b = rgb(c)
			t.ok(r > g and g > b, string.format("%s %d,%d,%d runs red > green > blue (brown)", name, r, g, b))
			t.ok(r - g >= 35, name .. " leans red, not yellow (the old dirt was 150,116,78: R - G = 34)")
			t.ok(hue(c) <= 0.08, string.format("%s is red-brown (hue %.3f)", name, hue(c)))
		end
		t.ok(lum(rock) < lum(ground), "rock is darker than dirt, so a cliff never reads as a road")
		local _, rs = rock:ToHSV()
		local _, gs = ground:ToHSV()
		t.ok(rs <= gs, "rock is no more saturated than dirt")
		-- The under-layer of grass (every cliff face and the voxels below) is Ground.
		t.eq(TerrainGen.SubMaterial("Grass"), "Ground")
		t.eq(TerrainGen.SubMaterial("LeafyGrass"), "Ground")
	end)

	---------------------------------------------------------------------------
	-- STY-02: roads that read as roads
	---------------------------------------------------------------------------

	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local PlotData = t.shared("PlotData")
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

	t.test("STY-02: the road is a real terrain material of its own, a light, neutral grey (speckled gravel)", function()
		t.eq(GRAVEL, WorldLayout.RoadMaterial, "TownPaint and the country roads share one material")
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
		t.ok(v > 0.6, "light")
		t.ok(lum(c) > lum(colors.Ground) * 1.25, "much paler than dirt")
		local r, g, b = rgb(c)
		t.ok(r - b >= 0 and r - b <= 8, string.format("a neutral grey (%d, %d, %d)", r, g, b))
		t.ok(math.abs(r - g) <= 4, string.format("neither pink nor green (%d, %d, %d)", r, g, b))
		for name, other in pairs(colors) do
			if name ~= GRAVEL then
				local d = math.max(math.abs(c.R - other.R), math.abs(c.G - other.G), math.abs(c.B - other.B))
				t.ok(d > 4 / 255, "the road's colour is its own, not " .. name .. "'s")
			end
		end
	end)

	t.test("STY-02: out in the country every road, lane and path is gravel its whole width, never dirt", function()
		local function country(road)
			local half = road.width / 2
			local centre, inside = 0, 0
			for _, s in ipairs(along(road, 9)) do
				local p = s.p
				if WorldLayout.FlatWeight(p.X, p.Y) <= 0 then
					centre += 1
					-- Inside the road's own edge noise (it wanders about a stud).
					for off = -half + 1.5, half - 1.5, 0.5 do
						local q = p + s.side * off
						if nearestRoad(q.X, q.Y) == road then
							local m = materialAt(q.X, q.Y)
							-- A road over water is the bank's sand or the bed's mud.
							if m ~= "Sand" and m ~= "Mud" then
								inside += 1
								if m ~= GRAVEL then
									t.ok(
										false,
										string.format("%s at (%d, %d) is %s, not gravel", road.name, q.X, q.Y, m)
									)
									return centre, inside
								end
							end
						end
					end
				end
			end
			return centre, inside
		end
		for _, name in ipairs({ "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }) do
			local road = roadNamed(name)
			t.ok(road ~= nil, name .. " is a road")
			local centre, inside = country(road)
			t.ok(centre > 10, name .. " runs through the country")
			t.ok(inside > centre * 10, name .. " has its middle checked")
		end
		-- Every road there is (the forest path, the mill road, the lot loop and
		-- each homestead's spur included), wherever it leaves the town.
		local seen = 0
		for _, road in ipairs(WorldLayout.Roads) do
			local _, inside = country(road)
			seen += inside
		end
		t.ok(seen > 5000, seen .. " country road samples, all gravel")
	end)

	local function inRect(rect, x, z, slack)
		return x > rect.x0 - slack and x < rect.x1 + slack and z > rect.z0 - slack and z < rect.z1 + slack
	end

	t.test(
		"STY-02: gravel is only on roads, the town's streets and paths and the lots, never on a plot or the open meadow",
		function()
			local seen = 0
			-- Across every road, from edge to edge and a little past.
			for _, road in ipairs(WorldLayout.Roads) do
				local half = road.width / 2
				for _, s in ipairs(along(road, 6)) do
					for off = -half - 2, half + 2, 1.5 do
						local q = s.p + s.side * off
						if materialAt(q.X, q.Y) == GRAVEL then
							seen += 1
							local _, edge = nearestRoad(q.X, q.Y)
							-- A junction's flare is gravel past the road's own edge, on purpose.
							local flare = false
							for _, junction in ipairs(WorldLayout.Junctions) do
								flare = flare or (Vector2.new(q.X, q.Y) - junction.at).Magnitude <= junction.radius + 2
							end
							t.ok(
								edge <= 2 or flare,
								string.format("gravel at (%d, %d) is %.1f studs off the road", q.X, q.Y, edge)
							)
						end
					end
				end
			end
			t.ok(seen > 4000, seen .. " gravel samples")
			-- Far from any road, only where the town paints or parks it.
			local lot = WorldLayout.ParkingLot
			for x = -1490, 1490, 37 do
				for z = -1490, 1490, 37 do
					if materialAt(x, z) == GRAVEL then
						local _, edge = nearestRoad(x, z)
						local explained = edge <= 2 or inRect(lot, x, z, 0)
						for _, junction in ipairs(WorldLayout.Junctions) do
							explained = explained or (Vector2.new(x, z) - junction.at).Magnitude <= junction.radius + 2
						end
						for _, list in ipairs({ WorldLayout.TownPaint, WorldLayout.TownFloors }) do
							for _, paint in ipairs(list) do
								explained = explained or (paint.material == GRAVEL and inRect(paint, x, z, 2))
							end
						end
						t.ok(explained, string.format("gravel off the roads at (%d, %d)", x, z))
					end
				end
			end
			-- Never on a homestead's pad, whatever lane is near.
			local half = PlotData.Pad / 2
			for _, home in ipairs(PlotData.Homes) do
				for dx = -half + 2, half - 2, 18 do
					for dz = -half + 2, half - 2, 18 do
						t.ok(materialAt(home.x + dx, home.z + dz) ~= GRAVEL, home.id .. " pad")
					end
				end
			end
		end
	)

	t.test(
		"STY-02: the town's street, paths, yards and lots are gravel; its plaza stays cobbles, shop floors stay earth",
		function()
			for _, paint in ipairs(WorldLayout.TownPaint) do
				local cx, cz = (paint.x0 + paint.x1) / 2, (paint.z0 + paint.z1) / 2
				-- The first patch to cover a spot paints it (the plaza runs across the street).
				local first = nil
				for _, other in ipairs(WorldLayout.TownPaint) do
					if inRect(other, cx, cz, -3) then
						first = other
						break
					end
				end
				if first == paint then
					t.eq(materialAt(cx, cz), paint.material, paint.name)
				end
				t.ok(
					paint.material == GRAVEL or paint.name == "Plaza",
					paint.name .. " is gravel (only the plaza is cobbles)"
				)
			end
			local earth = 0
			for _, floor in ipairs(WorldLayout.TownFloors) do
				if floor.material ~= GRAVEL then
					earth += 1
					t.eq(floor.material, "Ground", floor.name .. " stays packed earth")
				end
			end
			t.ok(earth >= 4, "the shop floors stay as they were")
			t.eq(materialAt(0, 80), "Cobblestone", "the plaza's centre")
			t.eq(materialAt(-60, 72), GRAVEL, "the main street")
			local lot = WorldLayout.ParkingLot
			t.eq(materialAt((lot.x0 + lot.x1) / 2, (lot.z0 + lot.z1) / 2), GRAVEL, "the parking lot")
		end
	)

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
