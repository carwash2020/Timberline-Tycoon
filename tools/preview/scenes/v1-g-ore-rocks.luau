--!nocheck
-- Ore rocks for Lane M: coal, copper, iron, silver, gold, and two that glow
-- (opal, heartstone). Daylight on grass, then the same row in a dark cave.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")

		Kit.part(root, "Meadow", V3.new(70, 1, 18), CF.new(24, -0.5, 0), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
		Kit.part(
			root,
			"CaveFloor",
			V3.new(70, 1, 18),
			CF.new(24, -0.5, 22),
			C3.fromRGB(36, 34, 40),
			Enum.Material.Slate
		)
		Kit.part(root, "CaveWall", V3.new(70, 8, 1), CF.new(24, 3.5, 31), C3.fromRGB(28, 26, 32), Enum.Material.Slate)
		-- Dim fill so the night shot still shows the stone. The ore glow stays the neon.
		for _, x in ipairs({ 8, 40 }) do
			local lamp = Kit.part(root, "CaveFill", V3.new(0.2, 0.2, 0.2), CF.new(x, 3.2, 22), C3.fromRGB(20, 22, 28))
			lamp.Transparency = 1
			local light = roblox.Instance.new("PointLight")
			light.Brightness = 0.8
			light.Range = 22
			light.Shadows = false
			light.Color = C3.fromRGB(170, 180, 200)
			light.Parent = lamp
		end

		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(7.2, 1.3, 0.25), CF.new(x, 0.65, z), C3.fromRGB(110, 74, 44))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local function put(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
		end

		local ores = {
			{ "COAL", "Boulder", C3.fromRGB(28, 28, 32), Enum.Material.Slate, false },
			{ "COPPER", "CrackedBoulder", C3.fromRGB(184, 112, 48), Enum.Material.Metal, false },
			{ "IRON", "Spire", C3.fromRGB(150, 78, 52), Enum.Material.CorrodedMetal, false },
			{ "SILVER", "Slab", C3.fromRGB(196, 200, 208), Enum.Material.Metal, false },
			{ "GOLD", "Outcrop", C3.fromRGB(214, 176, 64), Enum.Material.Metal, false },
			{ "OPAL", "Boulder", C3.fromRGB(64, 210, 196), Enum.Material.Neon, true },
			{ "HEARTSTONE", "CrackedBoulder", C3.fromRGB(210, 42, 58), Enum.Material.Neon, true },
		}

		for i, ore in ipairs(ores) do
			local x = (i - 1) * 8
			put(NatureArt.OreRock(ore[2], "mid", ore[3], ore[4], ore[5]), CF.new(x, 0, 0))
			put(NatureArt.OreRock(ore[2], "mid", ore[3], ore[4], ore[5]), CF.new(x, 0, 22))
			label(ore[1], x, -3.2)
			label(ore[1], x, 18.6)
		end
		label("DAYLIGHT", -8, 0)
		label("CAVE", -8, 22)

		return {
			root = root,
			shadowRadius = 40,
			fov = 42,
			cameras = {
				{ pos = { 24, 8, -14 }, target = { 24, 1, 1 }, label = "daylight" },
				{ pos = { 24, 3.4, 13 }, target = { 24, 1.1, 22 }, label = "cave", night = true },
			},
		}
	end,
}
