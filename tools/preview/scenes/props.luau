--!nocheck
-- Every PropArt prop on a labelled row (Starter Forest tints), then one
-- strip per biome scattered the way clients scatter them (PropArt.Scatter,
-- with that biome's ground colour), shore and water included.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local PropArt = ctx.art("PropArt")
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local root = roblox.Instance.new("Model")

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end
		local function label(text, at)
			local sign =
				Kit.part(root, "Label", V3.new(7, 1.4, 0.3), CF.new(at), C3.fromRGB(120, 80, 50), Enum.Material.Wood)
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end
		local function ground(center, size, color, material)
			Kit.part(root, "Ground", size, CF.new(center - V3.new(0, size.Y / 2, 0)), color, material)
		end

		-- The line-up.
		local t = PropArt.Tints("starter")
		local lineup = {
			{ "Rock", PropArt.Rock(3.5, 3) },
			{ "Rock (snow)", PropArt.Rock(3, 5, PropArt.Tints("snow").stone) },
			{ "Pebbles", PropArt.Pebbles(2) },
			{ "LavaRock", PropArt.LavaRock(4, 2.6) },
			{ "Crystal", PropArt.Crystal(1, C3.fromRGB(159, 230, 255), 2.2) },
			{ "Bush", PropArt.Bush(3.2, 2, t.leaves) },
			{ "BerryBush", PropArt.BerryBush(2) },
			{ "Flowers", PropArt.Flowers(4, t.flowers) },
			{ "GrassTuft", PropArt.GrassTuft(5, t.grass) },
			{ "Fern", PropArt.Fern(6, t.leaves[1]) },
			{ "Reeds", PropArt.Reeds(7) },
			{ "Cattails", PropArt.Cattails(8) },
			{ "LilyPad", PropArt.LilyPad(2) },
			{ "Mushroom", PropArt.Mushroom(3, false) },
			{ "Mushroom (glow)", PropArt.Mushroom(4, true) },
			{ "Pinecones", PropArt.Pinecones(9) },
			{ "SnowPile", PropArt.SnowPile(10, 4) },
			{ "FallenLog", PropArt.FallenLog(11, t.bark) },
			{ "Stump", PropArt.Stump(12, t.bark) },
			{ "DeadBranch", PropArt.DeadBranch(13) },
		}
		local spacing = 8
		local width = (#lineup - 1) * spacing
		ground(V3.new(width / 2, 0, 0), V3.new(width + 20, 1, 16), TerrainGen.MaterialColors.Grass, Enum.Material.Grass)
		for i, entry in ipairs(lineup) do
			local x = width - (i - 1) * spacing
			if entry[1] == "LilyPad" then
				Kit.part(
					root,
					"Water",
					V3.new(8, 0.2, 8),
					CF.new(x, 0, 0),
					C3.fromRGB(63, 154, 194),
					Enum.Material.Glass
				).Transparency =
					0.1
			end
			place(entry[2], CF.new(x, if entry[1] == "LilyPad" then 0.1 else 0, 0))
			label(entry[1], V3.new(x, 0.7, -6))
		end

		-- Ground cover (AmbientLife's second layer on high), on a row in
		-- front of the line-up.
		local EnvironmentData = ctx.load("ReplicatedStorage/Shared/EnvironmentData")
		local pal = EnvironmentData.DecorPalettes
		local cover = {
			{ "GroundCover", PropArt.GroundCover(3, t.grass, pal.meadowFlowers) },
			{ "Wildflowers", PropArt.Wildflowers(4, pal.meadowFlowers) },
			{ "LowBush", PropArt.LowBush(5, pal.greens) },
			{ "FernClump", PropArt.FernClump(6, t.grass) },
			{ "MushroomCluster", PropArt.MushroomCluster(7) },
		}
		ground(
			V3.new(width / 2, 0, -16),
			V3.new(width + 20, 1, 12),
			TerrainGen.MaterialColors.Grass,
			Enum.Material.Grass
		)
		for i, entry in ipairs(cover) do
			local x = width / 2 + (3 - i) * 12
			place(entry[2], CF.new(x, 0, -15))
			label(entry[1], V3.new(x, 0.7, -21))
		end

		-- One strip per biome, scattered like the clients do.
		local biomes = {
			{ "starter", "Starter Forest", "Grass" },
			{ "hills", "The Hills", "LeafyGrass" },
			{ "snow", "Snowfields", "Snow" },
			{ "volcano", "Volcano", "Basalt" },
			{ "grove", "Phantom Grove", "Mud" },
			{ "sky", "Aether Isles", "Grass" },
			{ "island", "The Island", "Sand" },
		}
		local stripW, stripD = 90, 20
		for k, b in ipairs(biomes) do
			local z = 24 + (k - 1) * (stripD + 4)
			local color = TerrainGen.MaterialColors[b[3]]
			if b[1] == "sky" then
				color = C3.fromRGB(178, 212, 106)
			end
			ground(V3.new(stripW / 2, 0, z), V3.new(stripW + 4, 1, stripD), color, Enum.Material.Grass)
			label(b[2], V3.new(-9, 0.7, z))
			local rng = Kit.rng(k * 101)
			for n = 1, 46 do
				local x, dz = rng:range(2, stripW - 2), rng:range(-stripD / 2 + 2, stripD / 2 - 2)
				place(
					PropArt.Scatter(b[1], k * 1000 + n),
					CF.new(x, 0, z + dz) * CF.Angles(0, rng:range(0, math.pi * 2), 0)
				)
			end
		end
		-- A pond with its shore.
		local pz = 24 + #biomes * (stripD + 4) + 6
		ground(
			V3.new(stripW / 2, 0, pz),
			V3.new(stripW + 4, 1, 26),
			TerrainGen.MaterialColors.Grass,
			Enum.Material.Grass
		)
		Kit.part(
			root,
			"Water",
			V3.new(50, 0.2, 14),
			CF.new(stripW / 2, 0, pz),
			C3.fromRGB(63, 154, 194),
			Enum.Material.Glass
		).Transparency =
			0.1
		label("Shore and water", V3.new(-9, 0.7, pz))
		local rng = Kit.rng(77)
		for n = 1, 14 do
			place(
				PropArt.Scatter("starter", 5000 + n, "water"),
				CF.new(stripW / 2 + rng:range(-22, 22), 0.1, pz + rng:range(-5, 5))
			)
		end
		for n = 1, 30 do
			local side = if n % 2 == 0 then 1 else -1
			local x = stripW / 2 + rng:range(-30, 30)
			local onBank = math.abs(x - stripW / 2) > 25
			local dz = if onBank then rng:range(-9, 9) else side * rng:range(7.5, 11)
			place(
				PropArt.Scatter("starter", 6000 + n, "shore"),
				CF.new(x, 0, pz + dz) * CF.Angles(0, rng:range(0, 6), 0)
			)
		end

		return {
			root = root,
			shadowRadius = 140,
			fov = 50,
			cameras = {
				{ pos = { width / 2, 55, -100 }, target = { width / 2, 0, 20 }, label = "every prop" },
				{ pos = { 136, 6, -16 }, target = { 136, 1.5, 0 }, label = "stones and crystals" },
				{ pos = { 96, 6, -16 }, target = { 96, 1.2, 0 }, label = "green things" },
				{ pos = { 56, 6, -16 }, target = { 56, 1.2, 0 }, label = "water's edge, mushrooms" },
				{ pos = { 16, 6, -16 }, target = { 16, 1, 0 }, label = "the forest floor" },
				{ pos = { 45, 40, -10 }, target = { 45, 0, 40 }, label = "starter and hills strips" },
				{ pos = { 45, 40, 30 }, target = { 45, 0, 84 }, label = "snow and volcano strips" },
				{ pos = { 45, 40, 90 }, target = { 45, 0, 150 }, label = "grove, sky, island, the pond" },
				{ pos = { 30, 4, 22 }, target = { 50, 0.5, 26 }, label = "ground level in the forest" },
				{ pos = { width / 2, 12, -46 }, target = { width / 2, 0.6, -15 }, label = "ground cover" },
			},
		}
	end,
}
