--!nocheck
-- Lane G wildlife: the current critters plus the new gull, snow fox and
-- sky moth. Particles (fireflies, motes) do not draw in the preview.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local CritterArt = ctx.art("CritterArt")
		local root = roblox.Instance.new("Model")

		Kit.part(root, "Meadow", V3.new(70, 1, 36), CF.new(10, -0.5, 0), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
		Kit.part(root, "Snow", V3.new(28, 1, 16), CF.new(62, -0.5, 0), C3.fromRGB(230, 236, 242), Enum.Material.Snow)
		Kit.part(root, "Shore", V3.new(24, 1, 16), CF.new(-8, -0.5, 22), C3.fromRGB(196, 176, 130), Enum.Material.Sand)
		Kit.part(
			root,
			"Water",
			V3.new(16, 0.25, 16),
			CF.new(8, -0.15, 22),
			C3.fromRGB(70, 150, 190),
			Enum.Material.Glass
		)
		Kit.part(root, "Isle", V3.new(22, 1, 14), CF.new(40, -0.5, 22), C3.fromRGB(72, 110, 86), Enum.Material.Grass)
		Kit.part(root, "Night", V3.new(22, 0.2, 12), CF.new(62, 0.02, 22), C3.fromRGB(48, 40, 62), Enum.Material.Ground)
		Kit.part(
			root,
			"Basalt",
			V3.new(16, 0.2, 12),
			CF.new(-28, 0.02, 0),
			C3.fromRGB(52, 46, 44),
			Enum.Material.Basalt
		)

		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(7, 1.4, 0.25), CF.new(x, 0.7, z), C3.fromRGB(110, 74, 44))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local function put(model, cf)
			model:PivotTo(cf * model:GetPivot())
			model.Parent = root
		end

		for i = 1, 3 do
			local bird = CritterArt.Bird(i, 1)
			CritterArt.FoldWings(bird)
			put(bird, CF.new(-18 + (i - 1) * 2.4, 0, -4) * CF.Angles(0, math.rad(-15 + i * 12), 0))
		end
		put(CritterArt.Bird(4, 1.5, true), CF.new(-14, 4.5, -1) * CF.Angles(0, math.rad(20), math.rad(-8)))
		label("BIRDS", -16, -8)

		for i = 1, 3 do
			put(CritterArt.Butterfly(i), CF.new(-6 + (i - 1) * 2.2, 1.6, -4) * CF.Angles(0, math.rad(i * 40), 0))
		end
		label("MOTHS", -4, -8)

		for i = 1, 2 do
			put(CritterArt.Rabbit(i), CF.new(4 + (i - 1) * 3.2, 0, -4) * CF.Angles(0, math.rad(-20 + i * 30), 0))
		end
		put(CritterArt.Rabbit(8, true), CF.new(11, 0, -3) * CF.Angles(0, math.rad(40), 0))
		label("RABBITS", 7, -8)

		put(CritterArt.Deer(2), CF.new(20, 0, -2) * CF.Angles(0, math.rad(-30), 0))
		put(CritterArt.Deer(5), CF.new(28, 0, 0) * CF.Angles(0, math.rad(-50), 0))
		label("DEER", 24, -8)

		for i = 1, 3 do
			put(
				CritterArt.Gull(i),
				CF.new(-12 + (i - 1) * 3.4, 3.2 + (i % 2) * 0.6, 20) * CF.Angles(0, math.rad(i * 25), math.rad(-6))
			)
		end
		label("GULLS", -8, 16)

		for i = 1, 2 do
			put(CritterArt.Duck(i), CF.new(4 + (i - 1) * 3, 0.1, 22) * CF.Angles(0, math.rad(40 + i * 30), 0))
		end
		put(CritterArt.Fish(1), CF.new(12, 1.6, 24) * CF.Angles(math.rad(30), math.rad(80), 0))
		label("DUCKS", 8, 16)

		for i = 1, 2 do
			put(CritterArt.SnowFox(i), CF.new(56 + (i - 1) * 4, 0, 0) * CF.Angles(0, math.rad(-25 + i * 20), 0))
		end
		label("SNOW FOX", 60, -6)

		for i = 1, 3 do
			put(CritterArt.SkyMoth(i), CF.new(36 + (i - 1) * 2.4, 1.8, 22) * CF.Angles(0, math.rad(i * 30), 0))
		end
		label("SKY MOTH", 38, 16)

		for i = 1, 3 do
			put(CritterArt.Wisp(i), CF.new(56 + (i - 1) * 3, 2.2, 22))
		end
		label("WISPS", 60, 16)

		for i = 1, 2 do
			put(CritterArt.EmberSprite(i), CF.new(-30 + (i - 1) * 3, 0.5, 0))
		end
		label("EMBERS", -28, -6)

		return {
			root = root,
			shadowRadius = 70,
			fov = 40,
			cameras = {
				{ pos = { 16, 22, -36 }, target = { 16, 1, 6 }, label = "everyone" },
				{ pos = { -14, 4, -14 }, target = { -14, 1.5, -3 }, label = "birds" },
				{ pos = { 6, 3.5, -12 }, target = { 7, 0.6, -4 }, label = "rabbits" },
				{ pos = { 24, 5, -14 }, target = { 24, 1.6, -1 }, label = "deer" },
				{ pos = { -6, 5, 10 }, target = { -8, 2.2, 20 }, label = "gulls" },
				{ pos = { 58, 3.2, -8 }, target = { 58, 0.6, 0 }, label = "snow fox" },
				{ pos = { 38, 3, 14 }, target = { 38, 1.6, 22 }, label = "sky moth", night = true },
				{ pos = { 60, 4, 14 }, target = { 60, 1.8, 22 }, label = "wisps", night = true },
				{ pos = { -28, 2.6, -8 }, target = { -28, 0.6, 0 }, label = "embers" },
			},
		}
	end,
}
