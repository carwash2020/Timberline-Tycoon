--!nocheck
-- Lane G nature looks: six rock families at three sizes, one biome look
-- per column (moss, snow, sand, basalt, gloam, cave), every plant, and
-- the cave dressing (mushrooms, glow fungus, crystal rocks, roots, bats)
-- plus a gloamwood mushroom ring and lanternwood pods. Night views light
-- the glow pieces.
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
		-- Rock sheets sit apart from the plants so a plaque in front of a
		-- rock is the only thing between the camera and that row.
		Kit.part(
			root,
			"RockPad",
			V3.new(72, 1, 56),
			CF.new(18, -0.5, 186),
			C3.fromRGB(116, 170, 74),
			Enum.Material.Grass
		)
		Kit.part(
			root,
			"RockPad",
			V3.new(72, 1, 56),
			CF.new(98, -0.5, 186),
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

		-- Flat on the grass, text on the top face, just in front of the rock.
		local function plaque(text, x, z)
			local board = Kit.part(
				root,
				"Plaque",
				V3.new(5.2, 0.12, 1.55),
				CF.new(x, 0.06, z),
				C3.fromRGB(98, 68, 42),
				Enum.Material.Wood
			)
			Kit.signText(board, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Top })
		end

		-- 3/4 view, 30 degrees above the row, far enough that `span` studs fit.
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
					1.15 + dist * math.tan(elev),
					targetZ - math.cos(yaw) * dist,
				},
				target = { targetX, 1.25, targetZ },
				fov = fov,
			}
		end

		local function put(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
		end

		-- Six families plus the two sizes the large moss boulder does not
		-- already show. Four rocks to a row, each name on the grass in front.
		local gap = 12
		local sheetZ = 200
		local sheets = {
			{
				{ "Boulder", "meadow", "MOSS", "large" },
				{ "CrackedBoulder", "snow", "SNOW", "large" },
				{ "Spire", "shore", "SAND", "large" },
				{ "Slab", "volcano", "BASALT", "large" },
			},
			{
				{ "PebbleCluster", "gloam", "GLOAM", "large" },
				{ "Outcrop", "cave", "CAVE", "large" },
				{ "Boulder", "meadow", "SMALL", "small" },
				{ "Boulder", "meadow", "MID", "mid" },
			},
		}
		for s, sheet in ipairs(sheets) do
			local x0 = (s - 1) * 80
			for i, row in ipairs(sheet) do
				local x = x0 + (i - 1) * gap
				put(NatureArt.Build(row[1], s * 40 + i * 17, row[4], row[2]), CF.new(x, 0, sheetZ))
				plaque(row[3], x, sheetZ - 5.1)
			end
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

		local row1 = frameRow(18, sheetZ, 50)
		row1.label = "rocks 1"
		local row2 = frameRow(98, sheetZ, 50)
		row2.label = "rocks 2"
		-- Close on the large moss boulder (first of sheet 1), still 3/4 and
		-- above, so the plaque stays on the grass in front of it.
		local close = frameRow(0, sheetZ, 16, 32)
		close.label = "boulder close"
		return {
			root = root,
			shadowRadius = 80,
			fov = 42,
			cameras = {
				row1,
				row2,
				close,
				{ pos = { 36, 10, -40 }, target = { 36, 0.6, -18 }, label = "plants" },
				{ pos = { 18, 2.2, -24 }, target = { 18, 0.45, -18 }, label = "flowers close", fov = 32 },
				{ pos = { 20, 8, 8 }, target = { 20, 1.2, 30 }, label = "cave", night = true },
				{ pos = { 12, 2.2, 22 }, target = { 12, 0.8, 30 }, label = "glow fungus", night = true },
				{ pos = { 44, 3.5, 22 }, target = { 44, 1, 31 }, label = "ring and pods", night = true },
			},
		}
	end,
}
