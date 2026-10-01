--!nocheck
-- The town at its real coordinates (MapBuilder / WorldLayout): the sawmill
-- at (0, 110) with the sell pad and Sky Bin in front, the Tool Shed, the
-- Dealership and Hearth & Home along the street, the gondola station behind
-- them, Murph's camp by the spawn, the parking lot east of it, lamp posts,
-- props, greenery and trees, on the real terrain, at golden hour.
-- Things MapBuilder builds itself (parking slots, Sky Bin, spawn pad) are
-- stood in for with plain parts; the dirt paths are a suggestion for the
-- terrain paint.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local PropArt = ctx.art("PropArt")
		local TreeArt = ctx.art("TreeArt")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")

		local function put(model, x, z, yaw)
			Kit.placeAt(model, CF.new(x, 0, z) * CF.Angles(0, yaw or 0, 0))
			model.Parent = root
			return model
		end
		-- The yaw that turns a model's front (-Z) toward (tx, tz).
		local function facing(x, z, tx, tz)
			return math.atan2(x - tx, z - tz)
		end
		local function flat(name, x0, x1, z0, z1, color, material, y)
			local p = Kit.part(
				root,
				name,
				V3.new(x1 - x0, 0.1, z1 - z0),
				CF.new((x0 + x1) / 2, y or 0.05, (z0 + z1) / 2),
				color,
				material
			)
			Kit.decor(p, false)
			return p
		end

		-- Ground: packed dirt for the plaza, the street, the paths; gravel
		-- for the lot.
		local DIRT = C3.fromRGB(184, 150, 106)
		flat("Plaza", -26, 26, 64, 97, DIRT, Enum.Material.Ground)
		flat("Street", -96, 64, 70, 84, DIRT, Enum.Material.Ground)
		for _, x in ipairs({ -80, -45, 45 }) do
			flat("ShopPath", x - 6, x + 6, 84, 93, DIRT, Enum.Material.Ground)
		end
		flat("Walk", -6, 6, 34, 64, DIRT, Enum.Material.Ground)
		flat("YardMill", -22, 24, 97, 126, C3.fromRGB(176, 142, 100), Enum.Material.Ground)
		flat("GondolaPath", -31, -25, 97, 142, DIRT, Enum.Material.Ground)
		flat("GondolaPath", -46, -25, 136, 142, DIRT, Enum.Material.Ground)

		-- Stand-ins for what MapBuilder builds: the spawn, the parking slots
		-- and the Sky Bin.
		local spawn = Kit.cylinder(
			root,
			"Spawn",
			0.3,
			11,
			CF.new(0, 0.15, 40) * CF.Angles(0, 0, math.pi / 2),
			C3.fromRGB(170, 160, 148),
			Enum.Material.Slate
		)
		Kit.decor(spawn, false)
		for row = 0, 1 do
			for col = 0, 11 do
				local x, z = 16 + col * 8, 45 - row * 40
				flat(
					"ParkingSlot",
					x - 3.25,
					x + 3.25,
					z - 18.5,
					z + 18.5,
					C3.fromRGB(166, 156, 140),
					Enum.Material.Slate,
					0.1
				)
			end
		end
		local bin = Kit.part(
			root,
			"SkyBin",
			V3.new(4, 4, 4),
			CF.new(-18, 2, 86),
			C3.fromRGB(150, 110, 70),
			Enum.Material.WoodPlanks
		)
		Kit.signText(bin, "SKY BIN", C3.fromRGB(245, 235, 215))

		-- The buildings.
		put(BuildingArt.Sawmill(), 0, 110)
		put(BuildingArt.SellPad(24, 18), 0, 86)
		put(BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44)), -45, 100)
		put(BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181)), 45, 100)
		put(BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", C3.fromRGB(122, 90, 60)), -80, 100)
		-- The gondola station, its back (+Z) toward the Skyroot (-1050, 1050).
		put(BuildingArt.GondolaStation(), -40, 150, math.atan2(-1050 + 40, 1050 - 150))
		put(BuildingArt.Campsite(), -21, 24, facing(-21, 24, 0, 40))
		put(BuildingArt.Signpost("TO THE WOODS\nHills 400 · Snow 1200"), -16, 44, facing(-16, 44, 0, 40))
		put(
			BuildingArt.Signpost("SKYROOT GONDOLA\nto the Aether Isles\n$250 a ride"),
			-36,
			128,
			facing(-36, 128, 0, 80)
		)

		-- Lamp posts: along the street's south side (arms over the street),
		-- at the head of the spawn walk, by the gondola path and the yard.
		for _, x in ipairs({ -92, -64, -30, -14, 16, 34, 58 }) do
			put(BuildingArt.LampPost(), x, 68.5, math.pi)
		end
		put(BuildingArt.LampPost(), -8, 60, -math.pi / 2)
		put(BuildingArt.LampPost(), 8, 60, math.pi / 2)
		put(BuildingArt.LampPost(), -23, 132, math.pi / 2)
		put(BuildingArt.LampPost(), 26, 122, 0)

		-- Fences: a paddock behind Hearth & Home, rails along the lot.
		put(BuildingArt.Fence(26), -88, 136)
		put(BuildingArt.Fence(26), -88, 114)
		put(BuildingArt.Fence(22), -101, 125, math.pi / 2)
		put(BuildingArt.Fence(36), 111, 25, math.pi / 2)

		-- Props.
		local seed = 0
		local function prop(name, x, z, yaw)
			seed += 1
			put(BuildingArt.Prop(name, seed * 13), x, z, yaw)
		end
		prop("Haybale", -93, 128, 0.3)
		prop("Haybale", -85, 121, -0.5)
		prop("Haybale", -80, 130, 1.2)
		prop("Cart", -71, 124, -0.4)
		prop("WaterTower", -58, 126)
		prop("ToolRack", -33, 97, -math.pi / 2)
		prop("Well", -38, 77)
		prop("Bench", -58, 70.5, math.pi)
		prop("Bench", 26, 71, math.pi)
		prop("Barrel", -32.5, 92)
		prop("Crate", -57, 92, 0.3)
		prop("Barrel", 32, 93)
		prop("Crate", 57, 93, -0.2)
		prop("Crate", 57.5, 89.5, 0.5)
		prop("Planter", -66, 92)
		prop("Planter", -94, 92)
		prop("Mailbox", -91, 87, 0)
		prop("FlowerBox", -86, 90.5, 0)
		prop("LogPile", 28, 108, 0)
		prop("LogPile", 28, 98, 0.1)
		prop("Wheelbarrow", 20, 93, -0.6)
		prop("SawdustPile", 24, 118)
		prop("SawdustPile", -21, 99)
		prop("Lantern", -28, 30)
		prop("Barrel", -24, 120)
		prop("Barrel", -26, 117.5)

		-- Greenery round the edges (in game the clients scatter these; here
		-- they show the intended feel).
		local greens = { C3.fromRGB(93, 162, 74), C3.fromRGB(111, 179, 82), C3.fromRGB(76, 143, 62) }
		local petals = { C3.fromRGB(242, 114, 140), C3.fromRGB(255, 210, 86), C3.fromRGB(255, 243, 230) }
		local g = 0
		local function green(kind, x, z, size)
			g += 1
			local m
			if kind == "bush" then
				m = PropArt.Bush(size or 3, g * 17, greens)
			elseif kind == "rock" then
				m = PropArt.Rock(size or 2.5, g * 17)
			else
				m = PropArt.Flowers(g * 17, petals)
			end
			put(m, x, z, g * 0.7)
		end
		for _, b in ipairs({
			{ "bush", -58, 97 },
			{ "bush", -31, 106 },
			{ "bush", -64, 108 },
			{ "bush", -97, 100 },
			{ "bush", 32, 104 },
			{ "bush", 58, 104 },
			{ "bush", 26, 88, 2.2 },
			{ "bush", -28, 88, 2.2 },
			{ "bush", -50, 144 },
			{ "bush", -30, 154 },
			{ "bush", 12, 132 },
			{ "bush", 40, 124 },
			{ "bush", -12, 30 },
			{ "bush", -32, 16 },
			{ "bush", -27, 35, 2 },
			{ "bush", 12, 28, 2.4 },
			{ "rock", -34, 22 },
			{ "rock", 14, 66, 1.6 },
			{ "rock", -54, 148, 3 },
			{ "rock", 36, 132 },
			{ "rock", -104, 92 },
			{ "rock", 64, 92, 2 },
			{ "flowers", -62, 89 },
			{ "flowers", -74, 89 },
			{ "flowers", -99, 96 },
			{ "flowers", 10, 36 },
			{ "flowers", -10, 46 },
			{ "flowers", 30, 96 },
			{ "flowers", -38, 89 },
			{ "flowers", -24, 28 },
		}) do
			green(b[1], b[2], b[3], b[4])
		end

		-- Trees around the edges: the Starter Forest south, pines north.
		local woods = {}
		for _, def in ipairs(WoodData.All()) do
			woods[def.id] = def
		end
		local rng = Kit.rng(99)
		for _, p in ipairs({
			{ "oak", -40, 2 },
			{ "oak", -62, 50 },
			{ "birch", -46, 4 },
			{ "oak", 30, -24 },
			{ "birch", -24, -6 },
			{ "oak", -70, 8 },
			{ "birch", 4, -30 },
			{ "oak", -36, 42 },
			{ "birch", -112, 70 },
			{ "oak", -116, 104 },
			{ "oak", -108, 150 },
			{ "pine", -14, 152 },
			{ "pine", 8, 160 },
			{ "pine", 40, 148 },
			{ "pine", 66, 134 },
			{ "maple", 74, 112 },
			{ "pine", -72, 158 },
			{ "maple", -94, 160 },
			{ "maple", -64, 145 },
			{ "oak", 124, 70 },
			{ "birch", 128, 100 },
			{ "pine", 18, 142 },
		}) do
			local def = woods[p[1]]
			if def then
				local t = TreeArt.Build(def, math.floor(p[2] * 7 + p[3] * 3), rng:range(0.9, 1.15))
				Kit.placeAt(t, CF.new(p[2], 0, p[3]))
				t.Parent = root
			end
		end

		return {
			root = root,
			terrain = Common.terrain(ctx, -190, -70, 190, 250, 4),
			shadowRadius = 200,
			fov = 50,
			lighting = {
				sunDir = { -0.72, 0.34, -0.5 },
				sunColor = "#ffc887",
				sunIntensity = 2.5,
				skyTop = "#7fa6d6",
				skyBottom = "#f6cf98",
				ground = "#7a6a4c",
				hemiIntensity = 1.25,
				ambient = 0.45,
				fog = "#efd2a8",
				fogNear = 220,
				fogFar = 900,
				bloom = 0.65,
			},
			cameras = {
				{ pos = { 2, 6.5, 32 }, target = { 0, 9, 110 }, label = "from the spawn" },
				{ pos = { -95, 105, -20 }, target = { -10, 0, 100 }, label = "aerial" },
				{ pos = { -36, 7.5, 74 }, target = { -45, 6, 100 }, label = "Tool Shed" },
				{ pos = { 36, 7.5, 74 }, target = { 45, 6, 100 }, label = "Dealership" },
				{ pos = { -71, 7.5, 76 }, target = { -80, 6, 100 }, label = "Hearth & Home" },
				{ pos = { -18, 12, 126 }, target = { -40, 6, 150 }, label = "gondola station" },
				{ pos = { -6, 6, 10 }, target = { -21, 2, 26 }, label = "Murph's camp" },
				{ pos = { 14, 5.5, 62 }, target = { 0, 7, 104 }, label = "sell pad + mill" },
				{ pos = { 80, 14, 24 }, target = { 0, 9, 100 }, label = "from the lot" },
			},
		}
	end,
}
