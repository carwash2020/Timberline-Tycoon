--!nocheck
-- Seven ores plus one plain host. Two daylight rows of four, names on
-- plaques in the grass, then the same rocks in a cave. The cave keeps the
-- night lighting and adds a preview-only fill so the veins read.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")

		local function pad(name, size, cf, color, material)
			Kit.part(root, name, size, cf, color, material)
		end

		pad("Meadow", V3.new(70, 1, 36), CF.new(16, -0.5, -6), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
		pad("Meadow", V3.new(70, 1, 36), CF.new(76, -0.5, -6), C3.fromRGB(116, 170, 74), Enum.Material.Grass)

		local caveX, caveZ = 46, 78
		pad("CaveFloor", V3.new(86, 1, 56), CF.new(caveX, -0.5, caveZ - 4), C3.fromRGB(36, 34, 40), Enum.Material.Slate)
		pad("CaveWall", V3.new(86, 26, 1), CF.new(caveX, 13, caveZ + 22), C3.fromRGB(28, 26, 32), Enum.Material.Slate)
		pad(
			"CaveWall",
			V3.new(1, 26, 56),
			CF.new(caveX - 43, 13, caveZ - 4),
			C3.fromRGB(32, 30, 36),
			Enum.Material.Slate
		)
		pad(
			"CaveWall",
			V3.new(1, 26, 56),
			CF.new(caveX + 43, 13, caveZ - 4),
			C3.fromRGB(32, 30, 36),
			Enum.Material.Slate
		)

		-- Preview-only fill. The night preset stays the cave's darkness;
		-- these lamps are not part of the rock, they just let the shot read.
		local function fill(x, y, z, brightness)
			local lamp = Kit.part(root, "CaveFill", V3.new(0.2, 0.2, 0.2), CF.new(x, y, z), C3.fromRGB(16, 18, 22))
			lamp.Transparency = 1
			local light = roblox.Instance.new("PointLight")
			light.Brightness = brightness
			light.Range = 34
			light.Shadows = false
			light.Color = C3.fromRGB(186, 196, 214)
			light.Parent = lamp
		end
		-- Close to the stone and strong enough that night lighting still
		-- leaves a cave, but the faces and veins are readable.
		fill(caveX - 12, 2.6, caveZ - 2, 10)
		fill(caveX + 12, 2.6, caveZ - 2, 10)
		fill(caveX, 2.4, caveZ + 8, 8)

		local function plaque(text, x, z)
			local board = Kit.part(
				root,
				"Plaque",
				V3.new(5.4, 0.12, 1.45),
				CF.new(x, 0.06, z),
				C3.fromRGB(98, 68, 42),
				Enum.Material.Wood
			)
			Kit.signText(board, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Top })
		end

		local function put(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
		end

		local function frameRow(targetX, targetZ, span, fov)
			local elev = math.rad(30)
			local yaw = math.rad(28)
			fov = fov or 40
			local aspect = 1280 / 800
			local hHalf = math.atan(math.tan(math.rad(fov) / 2) * aspect)
			local dist = (span / 2) / math.tan(hHalf) * 1.08
			return {
				pos = {
					targetX - math.sin(yaw) * dist,
					1.05 + dist * math.tan(elev),
					targetZ - math.cos(yaw) * dist,
				},
				target = { targetX, 1.1, targetZ },
				fov = fov,
			}
		end

		local ores = {
			{ "COAL", "Boulder", C3.fromRGB(12, 12, 14), Enum.Material.Slate, false },
			{ "COPPER", "CrackedBoulder", C3.fromRGB(232, 120, 36), Enum.Material.Metal, false },
			{ "IRON", "Spire", C3.fromRGB(176, 64, 42), Enum.Material.CorrodedMetal, false },
			{ "SILVER", "Slab", C3.fromRGB(232, 236, 242), Enum.Material.Foil, false },
			{ "GOLD", "Outcrop", C3.fromRGB(250, 198, 28), Enum.Material.Metal, false },
			{ "OPAL", "Boulder", C3.fromRGB(214, 206, 230), Enum.Material.SmoothPlastic, true },
			{ "HEARTSTONE", "CrackedBoulder", C3.fromRGB(255, 70, 118), Enum.Material.Neon, true },
		}

		local gap = 11
		local function placeOre(ore, x, z)
			put(NatureArt.OreRock(ore[2], "mid", ore[3], ore[4], ore[5]), CF.new(x, 0, z))
			plaque(ore[1], x, z - 4.2)
		end

		for i = 1, 4 do
			placeOre(ores[i], (i - 1) * gap, 0)
		end
		for i = 1, 3 do
			placeOre(ores[4 + i], 60 + (i - 1) * gap, 0)
		end
		put(NatureArt.Build("Boulder", 9, "mid", "host"), CF.new(60 + 3 * gap, 0, 0))
		plaque("HOST", 60 + 3 * gap, -4.2)

		-- Same eight, two rows inside the cave, Heartstone included.
		local function placeCave(model, col, row)
			local x = caveX - 16.5 + col * gap
			local z = caveZ - 6 + row * 12
			put(model, CF.new(x, 0, z))
		end
		for i = 1, 4 do
			local ore = ores[i]
			placeCave(NatureArt.OreRock(ore[2], "mid", ore[3], ore[4], ore[5]), i - 1, 0)
		end
		for i = 1, 3 do
			local ore = ores[4 + i]
			placeCave(NatureArt.OreRock(ore[2], "mid", ore[3], ore[4], ore[5]), i - 1, 1)
		end
		placeCave(NatureArt.Build("Boulder", 9, "mid", "host"), 3, 1)

		local row1 = frameRow(16.5, 0, 48)
		row1.label = "ores 1"
		local row2 = frameRow(76.5, 0, 48)
		row2.label = "ores 2"
		-- Same 30-degree 3/4 as the daylight rows, pulled in so both cave
		-- rows fill the frame instead of sitting in a black void.
		local cave = {
			pos = { caveX - 18, 20, caveZ - 34 },
			target = { caveX, 0.8, caveZ + 2 },
			fov = 48,
			label = "cave",
			night = true,
		}
		return {
			root = root,
			shadowRadius = 50,
			fov = 40,
			cameras = { row1, row2, cave },
		}
	end,
}
