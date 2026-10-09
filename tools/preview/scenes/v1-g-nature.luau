--!nocheck
-- Lane G plants and cave dressing. Rock close-ups live in v1-g-rocks
-- (one family per frame). Night views light the glow pieces.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Meadow",
			V3.new(120, 1, 50),
			CF.new(32, -0.5, -4),
			C3.fromRGB(116, 170, 74),
			Enum.Material.Grass
		)
		Kit.part(root, "Shore", V3.new(28, 1, 16), CF.new(78, -0.5, 0), C3.fromRGB(196, 176, 130), Enum.Material.Sand)
		Kit.part(root, "Water", V3.new(18, 0.3, 16), CF.new(96, -0.2, 0), C3.fromRGB(70, 150, 190), Enum.Material.Glass)
		Kit.part(
			root,
			"CaveFloor",
			V3.new(50, 1, 28),
			CF.new(20, -0.5, 28),
			C3.fromRGB(42, 40, 46),
			Enum.Material.Slate
		)
		Kit.part(root, "CaveWall", V3.new(50, 10, 1), CF.new(20, 4.5, 41), C3.fromRGB(36, 34, 40), Enum.Material.Slate)

		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(6.5, 1.4, 0.25), CF.new(x, 0.7, z), C3.fromRGB(110, 74, 44))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local function put(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
		end

		local plants = NatureArt.PlantKinds
		for i, kind in ipairs(plants) do
			local x = (i - 1) * 9
			put(NatureArt.Build(kind, i * 5), CF.new(x, 0, -18))
			label(string.upper(kind), x, -22)
		end

		-- Reeds stand at the water's edge so the shore read is obvious.
		put(NatureArt.Build("Reeds", 2), CF.new(86, 0, 2))
		put(NatureArt.Build("Reeds", 7), CF.new(90, 0, -2))

		for i, kind in ipairs(NatureArt.CaveKinds) do
			local x = 4 + (i - 1) * 8
			put(NatureArt.Build(kind, i * 9), CF.new(x, 0, 30))
			label(string.upper(kind), x, 24)
		end
		put(NatureArt.MushroomRing(4), CF.new(40, 0, 32))
		put(NatureArt.LanternPods(2), CF.new(48, 0, 30))
		label("RING + PODS", 44, 24)

		return {
			root = root,
			shadowRadius = 80,
			fov = 42,
			cameras = {
				{ pos = { 36, 10, -40 }, target = { 36, 0.6, -18 }, label = "plants" },
				{ pos = { 18, 2.2, -24 }, target = { 18, 0.45, -18 }, label = "flowers close", fov = 32 },
				{ pos = { 20, 8, 8 }, target = { 20, 1.2, 30 }, label = "cave", night = true },
				{ pos = { 12, 2.2, 22 }, target = { 12, 0.8, 30 }, label = "glow fungus", night = true },
				{ pos = { 44, 3.5, 22 }, target = { 44, 1, 31 }, label = "ring and pods", night = true },
			},
		}
	end,
}
