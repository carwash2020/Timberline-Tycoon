--!nocheck
-- The landscape's look, nudged toward Lumber Tycoon 2 (phase 10, STY-*),
-- keeping the cozy low-poly palette:
--   STY-01 a deeper meadow green and brown rock (TerrainGen.MaterialColors).
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
end
