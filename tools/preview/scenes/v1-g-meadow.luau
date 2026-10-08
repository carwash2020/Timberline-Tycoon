--!nocheck
-- A 60x60 meadow patch from 12 studs up, 30 degrees down. Flowers, small
-- rocks, ferns and two animals sit in the view so one frame shows the
-- life the surface scatter spreads across a cell.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local CritterArt = ctx.art("CritterArt")
		local root = roblox.Instance.new("Model")

		local lookX, lookZ = 30, 36
		Kit.part(
			root,
			"Meadow",
			V3.new(60, 1, 60),
			CF.new(lookX, -0.5, lookZ),
			C3.fromRGB(116, 170, 74),
			Enum.Material.Grass
		)

		local function put(model, x, z, yaw)
			Kit.placeAt(model, CF.new(x, 0, z) * CF.Angles(0, yaw or 0, 0))
			model.Parent = root
		end

		local flowers = {
			{ 22, 30, 0.4 },
			{ 27, 33, 1.2 },
			{ 36, 31, 2.1 },
			{ 41, 36, 0.7 },
			{ 24, 40, 1.7 },
			{ 33, 42, 2.6 },
			{ 39, 44, 0.2 },
			{ 18, 36, 1.1 },
		}
		for i, spot in ipairs(flowers) do
			put(NatureArt.Build("Flowers", i * 11), spot[1], spot[2], spot[3])
		end

		local ferns = {
			{ 20, 42, 0.5 },
			{ 44, 40, 1.4 },
			{ 26, 46, 2.2 },
			{ 38, 28, 0.9 },
		}
		for i, spot in ipairs(ferns) do
			put(NatureArt.Build("Fern", i * 13), spot[1], spot[2], spot[3])
		end

		put(NatureArt.Build("Bush", 4), 16, 34, 0.6)
		put(NatureArt.Build("Bush", 9), 46, 33, 1.8)

		local rocks = {
			{ "Boulder", 3, 19, 38 },
			{ "PebbleCluster", 8, 43, 38 },
			{ "Boulder", 15, 34, 48 },
			{ "Slab", 21, 15, 40 },
		}
		for _, rock in ipairs(rocks) do
			put(NatureArt.Build(rock[1], rock[2], "small", "meadow"), rock[3], rock[4], rock[2] * 0.2)
		end

		put(CritterArt.Rabbit(6, false), 26, 29, 0.8)
		put(CritterArt.Deer(5), 35, 39, -0.5)

		local elev = math.rad(30)
		local back = 12 / math.tan(elev)
		return {
			root = root,
			shadowRadius = 50,
			fov = 58,
			cameras = {
				{
					pos = { lookX, 12, lookZ - back },
					target = { lookX, 0.5, lookZ },
					label = "meadow",
					fov = 58,
				},
			},
		}
	end,
}
