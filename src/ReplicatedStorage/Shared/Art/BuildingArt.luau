--!strict
-- BuildingArt: the town's buildings and set dressing (GAME_DESIGN §13):
-- stone-footed timber buildings with shingle roofs, warm windows that glow
-- at night, chimney smoke. Pure (see Kit), so tools/preview draws them too.
--
-- Every builder returns a Model built around the origin: ground at y = 0,
-- the front (door, counter, open side) facing -Z. MapBuilder places and
-- turns them, and adds the gameplay bits (attachments, tags, zones).
-- Parts other systems look up by name are listed per builder: keep them.
--
-- (First pass: simple shapes. The buildings workstream replaces the
-- insides of these functions; keep the signatures and named parts.)

local Kit = require(script.Parent.Kit)

local BuildingArt = {}

local WOOD = Color3.fromRGB(101, 67, 33)
local WOOD_DARK = Color3.fromRGB(70, 45, 22)
local STONE = Color3.fromRGB(140, 134, 128)
local ROOF = Color3.fromRGB(120, 64, 50)

local function shell(model: Model, w: number, d: number, h: number, roofColor: Color3, openFront: boolean)
	local rng = Kit.rng(w * 7 + d)
	Kit.part(model, "Floor", Vector3.new(w, 1, d), CFrame.new(0, 0.5, 0), STONE, Enum.Material.Slate)
	Kit.plankWall(model, "BackWall", CFrame.new(0, 1 + h / 2, d / 2 - 0.4), w, h, 0.8, 7, rng, { WOOD_DARK })
	Kit.plankWall(
		model,
		"WallL",
		CFrame.new(-w / 2 + 0.4, 1 + h / 2, 0) * CFrame.Angles(0, math.pi / 2, 0),
		d,
		h,
		0.8,
		7,
		rng,
		{ WOOD_DARK }
	)
	Kit.plankWall(
		model,
		"WallR",
		CFrame.new(w / 2 - 0.4, 1 + h / 2, 0) * CFrame.Angles(0, math.pi / 2, 0),
		d,
		h,
		0.8,
		7,
		rng,
		{ WOOD_DARK }
	)
	if not openFront then
		Kit.plankWall(model, "FrontWall", CFrame.new(0, 1 + h / 2, -d / 2 + 0.4), w, h, 0.8, 7, rng, { WOOD_DARK })
	end
	Kit.gableRoof(
		model,
		"Roof",
		CFrame.new(0, 1 + h, 0) * CFrame.Angles(0, math.pi / 2, 0),
		d + 2,
		w + 2,
		h * 0.5,
		roofColor,
		Enum.Material.WoodPlanks
	)
end

-- The sawmill: about 40 x 30 studs, open front (-Z). Named parts:
-- "SawBlade" (a cylinder clients spin), "Smokestack" (has a Smoke).
function BuildingArt.Sawmill(): Model
	local model = Kit.model("Sawmill")
	shell(model, 34, 26, 8, ROOF, true)
	local blade = Kit.cylinder(
		model,
		"SawBlade",
		0.4,
		6,
		CFrame.new(-8, 5.5, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(170, 170, 175),
		Enum.Material.Metal
	)
	Kit.decor(blade)
	local stack = Kit.post(model, "Smokestack", Vector3.new(12, 1, 8), 16, 2, STONE, Enum.Material.Slate)
	local smoke = Instance.new("Smoke")
	smoke.Opacity = 0.15
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = stack
	return model
end

-- A shop: about 18 x 14 studs, open front (-Z). `kind` is "ToolShed",
-- "Dealership" or "HearthAndHome"; `title` goes on the sign. Named parts:
-- "Counter" (a direct child; MapBuilder puts the ShopPoint on its -Z side).
function BuildingArt.Shop(kind: string, title: string, accent: Color3): Model
	local model = Kit.model(kind)
	shell(model, 16, 12, 8, accent, true)
	Kit.part(model, "Counter", Vector3.new(10, 3, 2), CFrame.new(0, 2.5, 1), WOOD, Enum.Material.Wood)
	local sign =
		Kit.part(model, "Sign", Vector3.new(12, 2.5, 0.5), CFrame.new(0, 11.25, -6.5), WOOD, Enum.Material.Wood)
	Kit.signText(sign, title, Color3.fromRGB(245, 235, 215))
	return model
end

-- A gondola station: PrimaryPart "Platform" (10 x 1 x 10, its top at y = 1).
function BuildingArt.GondolaStation(): Model
	local model = Kit.model("GondolaStation")
	local platform =
		Kit.part(model, "Platform", Vector3.new(10, 1, 10), CFrame.new(0, 0.5, 0), STONE, Enum.Material.Slate)
	for _, c in ipairs({ { 4.5, 4.5 }, { -4.5, 4.5 }, { 4.5, -4.5 }, { -4.5, -4.5 } }) do
		Kit.post(model, "Post", Vector3.new(c[1], 1, c[2]), 10, 0.6, WOOD_DARK, Enum.Material.Wood)
	end
	Kit.part(
		model,
		"Roof",
		Vector3.new(11, 0.6, 11),
		CFrame.new(0, 11.3, 0),
		Color3.fromRGB(92, 135, 184),
		Enum.Material.Wood
	)
	model.PrimaryPart = platform
	return model
end

-- A signpost: a post at the origin with a board facing -Z (text both sides).
function BuildingArt.Signpost(text: string): Model
	local model = Kit.model("Signpost")
	Kit.decor(Kit.post(model, "Post", Vector3.zero, 7, 0.6, WOOD_DARK, Enum.Material.Wood))
	local board = Kit.part(model, "Board", Vector3.new(9, 4, 0.4), CFrame.new(0, 7, 0), WOOD, Enum.Material.Wood)
	Kit.decor(board)
	Kit.signText(board, text, Color3.fromRGB(245, 235, 215))
	return model
end

-- A street lamp (lit; clients may switch the glow by time of day).
-- Named parts: "LampGlow".
function BuildingArt.LampPost(): Model
	local model = Kit.model("LampPost")
	Kit.decor(Kit.post(model, "Post", Vector3.zero, 9, 0.5, Color3.fromRGB(45, 40, 38), Enum.Material.Metal))
	local glow = Kit.lantern(model, CFrame.new(0, 9.2, 0), 1.2)
	glow.Name = "LampGlow"
	return model
end

-- A rail fence `length` studs long along X.
function BuildingArt.Fence(length: number): Model
	local model = Kit.model("Fence")
	local posts = math.max(2, math.floor(length / 6) + 1)
	for i = 0, posts - 1 do
		local x = -length / 2 + length * i / (posts - 1)
		Kit.decor(
			Kit.part(model, "Post", Vector3.new(0.5, 3, 0.5), CFrame.new(x, 1.5, 0), WOOD_DARK, Enum.Material.Wood)
		)
	end
	for _, y in ipairs({ 1.2, 2.3 }) do
		Kit.decor(
			Kit.part(model, "Rail", Vector3.new(length, 0.35, 0.25), CFrame.new(0, y, 0), WOOD, Enum.Material.Wood)
		)
	end
	return model
end

-- The painted sell pad (w x d), CanCollide off. Named parts: "SellPad".
function BuildingArt.SellPad(w: number, d: number): Model
	local model = Kit.model("SellPadArt")
	local pad = Kit.part(
		model,
		"SellPad",
		Vector3.new(w, 0.2, d),
		CFrame.new(0, 0.1, 0),
		Color3.fromRGB(214, 170, 92),
		Enum.Material.WoodPlanks
	)
	pad.CanCollide = false
	Kit.signText(pad, "SELL LOGS HERE", Color3.fromRGB(70, 45, 22), { Enum.NormalId.Top })
	return model
end

-- Murph's camp by the spawn: a tent, a campfire, a log bench.
function BuildingArt.Campsite(): Model
	local model = Kit.model("MurphsCamp")
	Kit.gableRoof(model, "Tent", CFrame.new(0, 0, 4), 6, 5, 3.5, Color3.fromRGB(176, 72, 52), Enum.Material.Fabric)
	local fire = BuildingArt.Campfire()
	fire.Parent = model
	return model
end

-- A campfire with flames and warm light. Named parts: "Embers" (has Fire).
function BuildingArt.Campfire(): Model
	local model = Kit.model("Campfire")
	local rng = Kit.rng(5)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		Kit.decor(
			Kit.part(
				model,
				"FireStone",
				Vector3.new(0.9, 0.6, 0.7),
				CFrame.new(math.cos(a) * 1.6, 0.3, math.sin(a) * 1.6) * CFrame.Angles(0, -a, 0),
				Kit.vary(STONE, rng, 0.08),
				Enum.Material.Slate
			),
			false
		)
	end
	local embers = Kit.part(
		model,
		"Embers",
		Vector3.new(1.6, 0.3, 1.6),
		CFrame.new(0, 0.15, 0),
		Color3.fromRGB(255, 120, 40),
		Enum.Material.Neon
	)
	Kit.decor(embers, false)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Parent = embers
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 18
	light.Brightness = 1.6
	light.Parent = embers
	return model
end

-- Town dressing, by name: "LogPile", "Crate", "Barrel", "Bench", "Well",
-- "Cart", "SawdustPile", "WaterTower", "Mailbox", "FlowerBox".
function BuildingArt.Prop(name: string, seed: number): Model
	local model = Kit.model(name)
	local rng = Kit.rng(seed)
	if name == "LogPile" then
		for row = 0, 2 do
			for i = 0, 3 - row do
				Kit.decor(
					Kit.cylinder(
						model,
						"PileLog",
						6,
						1.3,
						CFrame.new(0, 0.65 + row * 1.1, (i - (3 - row) / 2) * 1.35),
						Kit.vary(Color3.fromRGB(122, 82, 48), rng, 0.05),
						Enum.Material.Wood
					)
				)
			end
		end
	else
		Kit.decor(Kit.part(model, name, Vector3.new(2, 2, 2), CFrame.new(0, 1, 0), WOOD, Enum.Material.WoodPlanks))
	end
	return model
end

-- The Cloud Chute on an isle's edge. Named parts: "CloudChute" (4 x 3 x 4,
-- centred at y = 1.5; MapBuilder tags it).
function BuildingArt.CloudChute(): Model
	local model = Kit.model("CloudChuteArt")
	Kit.part(model, "CloudChute", Vector3.new(4, 3, 4), CFrame.new(0, 1.5, 0), WOOD, Enum.Material.WoodPlanks)
	local water = Kit.part(
		model,
		"ChuteWater",
		Vector3.new(3.4, 0.2, 3.4),
		CFrame.new(0, 3.05, 0),
		Color3.fromRGB(120, 190, 255),
		Enum.Material.Neon
	)
	Kit.decor(water)
	return model
end

-- The Starfall Forge. Named parts: "StarfallForge" (the anvil; MapBuilder
-- tags it).
function BuildingArt.StarfallForge(): Model
	local model = Kit.model("StarfallForgeArt")
	Kit.part(model, "ForgeStone", Vector3.new(6, 2, 4), CFrame.new(0, 1, 0), STONE, Enum.Material.Slate)
	local anvil = Kit.part(
		model,
		"StarfallForge",
		Vector3.new(3, 1.5, 1.6),
		CFrame.new(0, 2.75, 0),
		Color3.fromRGB(60, 62, 70),
		Enum.Material.Metal
	)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(191, 216, 255)
	glow.Range = 16
	glow.Brightness = 2
	glow.Parent = anvil
	return model
end

-- A plank bridge with rope rails from `a` to `b` (world points; the deck's
-- top passes through both). Built in world space.
function BuildingArt.Bridge(a: Vector3, b: Vector3, width: number): Model
	local model = Kit.model("Bridge")
	local mid = (a + b) / 2
	local deck = Kit.part(
		model,
		"Deck",
		Vector3.new(width, 0.6, (b - a).Magnitude),
		CFrame.lookAt(mid, b) * CFrame.new(0, -0.3, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	local side = deck.CFrame.RightVector * (width / 2)
	for _, s in ipairs({ 1, -1 }) do
		Kit.decor(
			Kit.rod(
				model,
				"Rope",
				a + side * s + Vector3.new(0, 2.5, 0),
				b + side * s + Vector3.new(0, 2.5, 0),
				0.25,
				Color3.fromRGB(160, 130, 90),
				Enum.Material.Fabric
			)
		)
	end
	return model
end

return BuildingArt
