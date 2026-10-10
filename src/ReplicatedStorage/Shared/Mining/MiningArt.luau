--!strict
-- MiningArt: part-built ore nodes, chunks, ingots, picks, the bomb, the
-- smelting furnace, the prospector stall, the craft bench, and the gear.
-- Ore nodes come from OreRockArtAdapter (G's NatureArt.OreRock when it
-- exists). The furnace, the stall, the chute and the bench wear their Blender
-- bodies when those load (Shared/Art/MachineSkin); the parts below are the
-- gameplay and the fallback look. The furnace is the sawmill's sibling: timber
-- frame, stone base, gable, lantern, one light.

local Kit = require(script.Parent.Parent.Art.Kit)
local MachineMeshes = require(script.Parent.Parent.Art.MachineMeshes)
local MachineSkin = require(script.Parent.Parent.Art.MachineSkin)
local HoverTag = require(script.Parent.Parent.HoverTag)
local LuxEffect = require(script.Parent.Parent.LuxEffect)
local OreData = require(script.Parent.OreData)
local OreRockArtAdapter = require(script.Parent.OreRockArtAdapter)
local PickaxeData = require(script.Parent.PickaxeData)

local MiningArt = {}

local TimberBrown = Color3.fromHex("#7A5230")
local PlankHoney = Color3.fromHex("#C49A63")
local StoneBase = Color3.fromHex("#8C877E")
local RoofSlate = Color3.fromHex("#4A4F57")
local IronBlack = Color3.fromHex("#2B2B2E")
local Brass = Color3.fromHex("#C9A24A")
local LavaGlow = Color3.fromHex("#FF6A1E")

MiningArt.MaxNodeParts = 8
MiningArt.MaxFurnaceParts = 60
MiningArt.MaxNodeLights = 4
MiningArt.CaveLightCap = 6

local function weldTo(handle: BasePart, part: BasePart)
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = handle
	w.Part1 = part
	w.C0 = handle.CFrame:Inverse() * part.CFrame
	w.Parent = part
end

local function weldAll(model: Model, handle: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			weldTo(handle, d)
		end
	end
end

local function countParts(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function MiningArt.PartCount(model: Instance): number
	return countParts(model)
end

function MiningArt.LightCount(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("PointLight") then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Nodes, chunks, ingots
---------------------------------------------------------------------------

function MiningArt.Node(ore: OreData.Ore): Model
	local rock = OreRockArtAdapter.OreRock(ore.shape, ore.size, ore.color, ore.material, ore.glow)
	rock.Name = "OreNode"
	rock:SetAttribute("Ore", ore.id)
	rock:SetAttribute("Tier", ore.tier)
	rock:SetAttribute("Hardness", ore.hardness)
	HoverTag.Mark(rock, {
		key = "Ore:" .. ore.id,
		name = ore.name,
		kind = "Ore",
		itemId = ore.id,
		tier = ore.tier,
		need = ore.hardness,
		anchor = true,
	})
	return rock
end

function MiningArt.ClearNode(model: Instance)
	HoverTag.Clear(model)
	model:SetAttribute("Ore", nil)
end

function MiningArt.Chunk(ore: OreData.Ore): Model
	local model = Instance.new("Model")
	model.Name = "OreChunk"
	local host = Kit.part(model, "Chunk", Vector3.new(1.15, 0.9, 1.05), CFrame.new(0, 0.45, 0), ore.color, ore.material)
	host.Anchored = false
	local chip =
		Kit.wedge(model, "Vein", Vector3.new(0.4, 0.35, 0.5), CFrame.new(0.2, 0.7, 0.35), ore.color, ore.material)
	chip.Anchored = false
	model.PrimaryPart = host
	weldTo(host, chip)
	model:SetAttribute("Ore", ore.id)
	return model
end

function MiningArt.Ingot(ore: OreData.Ore): Model?
	if ore.ingotValue == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Ingot"
	local bar = Kit.part(
		model,
		"Bar",
		Vector3.new(1.4, 0.35, 0.55),
		CFrame.new(0, 0.18, 0),
		ore.color,
		if ore.material == Enum.Material.Neon then Enum.Material.Neon else Enum.Material.Metal
	)
	bar.Anchored = false
	model.PrimaryPart = bar
	model:SetAttribute("Ore", ore.id)
	return model
end

---------------------------------------------------------------------------
-- Picks and the bomb
---------------------------------------------------------------------------

local function pickColors(id: string): (Color3, Color3)
	if id == "RustyPick" then
		return Color3.fromRGB(122, 78, 48), Color3.fromRGB(92, 64, 40)
	elseif id == "CopperPick" then
		return Color3.fromRGB(184, 115, 51), Color3.fromRGB(92, 64, 36)
	elseif id == "IronPick" then
		return Color3.fromRGB(150, 150, 156), Color3.fromRGB(74, 52, 32)
	elseif id == "SteelPick" then
		return Color3.fromRGB(186, 190, 196), IronBlack
	elseif id == "ObsidianPick" then
		return Color3.fromRGB(32, 28, 36), Color3.fromRGB(48, 36, 28)
	end
	return LuxEffect.Gold, Color3.fromRGB(42, 28, 64)
end

function MiningArt.Pickaxe(pick: PickaxeData.Pick): Model
	local model = Instance.new("Model")
	model.Name = pick.id
	local head, haft = pickColors(pick.id)
	local handle =
		Kit.part(model, "Handle", Vector3.new(0.28, 3.1, 0.32), CFrame.new(0, 1.55, 0), haft, Enum.Material.Wood)
	model.PrimaryPart = handle
	Kit.part(
		model,
		"Grip",
		Vector3.new(0.32, 0.7, 0.36),
		CFrame.new(0, 0.55, 0),
		Color3.fromRGB(70, 48, 32),
		Enum.Material.Leather
	)
	local collar =
		Kit.part(model, "Collar", Vector3.new(0.46, 0.4, 0.5), CFrame.new(0, 2.85, 0), head, Enum.Material.Metal)
	Kit.decor(collar, false)
	local function bit(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
		local made: BasePart
		if name == "Poll" or name == "Cheek" or name == "LuxEdge" then
			made = Kit.part(model, name, size, cf, color, material)
		else
			made = Kit.wedge(model, name, size, cf, color, material)
		end
		Kit.decor(made, false)
		return made
	end
	-- Each head is a different silhouette. None of them carries a light.
	if pick.id == "RustyPick" then
		bit(
			"Point",
			Vector3.new(0.72, 0.4, 0.58),
			CFrame.new(0, 3.02, -0.28) * CFrame.Angles(math.rad(-12), 0, 0),
			head,
			Enum.Material.Metal
		)
	elseif pick.id == "CopperPick" then
		bit("Point", Vector3.new(1.05, 0.36, 1.05), CFrame.new(0, 3.1, -0.5), head, Enum.Material.Metal)
	elseif pick.id == "IronPick" then
		bit(
			"Point",
			Vector3.new(0.38, 0.95, 1.25),
			CFrame.new(0, 3.25, -0.55) * CFrame.Angles(0, math.rad(16), 0),
			head,
			Enum.Material.Metal
		)
		bit("Cheek", Vector3.new(0.22, 0.55, 0.62), CFrame.new(0.32, 3.12, -0.1), head, Enum.Material.Metal)
	elseif pick.id == "SteelPick" then
		bit("Point", Vector3.new(0.26, 1.15, 1.4), CFrame.new(0, 3.3, -0.62), head, Enum.Material.Metal)
	elseif pick.id == "ObsidianPick" then
		bit("Poll", Vector3.new(0.9, 0.5, 0.55), CFrame.new(0, 3.12, 0.2), head, Enum.Material.Slate)
		bit("Point", Vector3.new(0.48, 0.62, 0.78), CFrame.new(0, 3.18, -0.48), head, Enum.Material.Metal)
	else
		bit("Point", Vector3.new(0.42, 0.7, 1.0), CFrame.new(0, 3.14, -0.42), LuxEffect.Gold, Enum.Material.Metal)
		bit(
			"Fan",
			Vector3.new(0.95, 0.2, 0.72),
			CFrame.new(0, 3.4, -0.12) * CFrame.Angles(math.rad(72), 0, 0),
			LuxEffect.Gold,
			Enum.Material.Metal
		)
		local edge =
			bit("LuxEdge", Vector3.new(0.1, 0.5, 0.8), CFrame.new(0, 3.2, -0.82), LuxEffect.Gold, Enum.Material.Neon)
		edge:SetAttribute("Lux", true)
	end
	weldAll(model, handle)
	model:SetAttribute("PickId", pick.id)
	model:SetAttribute("PickLevel", pick.level)
	return model
end

function MiningArt.Bomb(lit: boolean?): Model
	local model = Instance.new("Model")
	model.Name = if lit then "BombLit" else "Bomb"
	local body =
		Kit.part(model, "Body", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 0.55, 0), IronBlack, Enum.Material.Metal)
	model.PrimaryPart = body
	local fuse = Kit.part(
		model,
		"Fuse",
		Vector3.new(0.12, 0.45, 0.12),
		CFrame.new(0.15, 1.25, 0),
		Color3.fromRGB(196, 168, 110),
		Enum.Material.Fabric
	)
	Kit.decor(fuse, false)
	if lit == true then
		local spark = Kit.part(
			model,
			"Spark",
			Vector3.new(0.22, 0.22, 0.22),
			CFrame.new(0.15, 1.55, 0),
			LavaGlow,
			Enum.Material.Neon
		)
		Kit.decor(spark, false)
	end
	weldAll(model, body)
	return model
end

function MiningArt.Dust(): Model
	local model = Instance.new("Model")
	model.Name = "RockDust"
	for i = 1, 4 do
		local puff = Kit.part(
			model,
			"Puff",
			Vector3.new(0.8, 0.35, 0.8),
			CFrame.new((i - 2.5) * 0.7, 0.4 + i * 0.15, 0),
			Color3.fromRGB(150, 140, 128),
			Enum.Material.Sand
		)
		puff.Transparency = 0.35
		Kit.decor(puff, false)
	end
	return model
end

---------------------------------------------------------------------------
-- Gear. The lamp's light ships off; the service enables it while held.
---------------------------------------------------------------------------

function MiningArt.MinersLamp(): Model
	local model = Instance.new("Model")
	model.Name = "MinersLamp"
	local cage = Kit.part(model, "Cage", Vector3.new(0.7, 0.8, 0.55), CFrame.new(0, 0.5, 0), Brass, Enum.Material.Metal)
	model.PrimaryPart = cage
	local glass =
		Kit.part(model, "Glass", Vector3.new(0.45, 0.5, 0.2), CFrame.new(0, 0.5, -0.28), LavaGlow, Enum.Material.Neon)
	Kit.decor(glass, false)
	local hook =
		Kit.part(model, "Hook", Vector3.new(0.12, 0.4, 0.12), CFrame.new(0, 1.05, 0), IronBlack, Enum.Material.Metal)
	Kit.decor(hook, false)
	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Color = LavaGlow
	light.Range = 12
	light.Brightness = 1
	light.Shadows = false
	light.Enabled = false
	light.Parent = glass
	weldAll(model, cage)
	return model
end

function MiningArt.Hardhat(): Model
	local model = Instance.new("Model")
	model.Name = "Hardhat"
	local shell = Kit.part(
		model,
		"Shell",
		Vector3.new(1.5, 0.55, 1.6),
		CFrame.new(0, 0.4, 0),
		Color3.fromRGB(214, 168, 42),
		Enum.Material.SmoothPlastic
	)
	model.PrimaryPart = shell
	local brim =
		Kit.part(model, "Brim", Vector3.new(1.9, 0.12, 1.9), CFrame.new(0, 0.15, -0.15), Color3.fromRGB(196, 150, 36))
	Kit.decor(brim, false)
	local lamp =
		Kit.part(model, "LampCap", Vector3.new(0.28, 0.2, 0.2), CFrame.new(0, 0.35, -0.75), Brass, Enum.Material.Metal)
	Kit.decor(lamp, false)
	weldAll(model, shell)
	local joint = Instance.new("Weld")
	joint.Name = "HeadWeld"
	joint.Part1 = shell
	joint.Parent = shell
	return model
end

function MiningArt.RopeLadder(): Model
	local model = Instance.new("Model")
	model.Name = "RopeLadder"
	local height = 12
	local left = Kit.part(
		model,
		"Rail",
		Vector3.new(0.15, height, 0.15),
		CFrame.new(-0.55, height / 2, 0),
		Color3.fromRGB(120, 86, 48),
		Enum.Material.Wood
	)
	model.PrimaryPart = left
	local right = Kit.part(
		model,
		"Rail",
		Vector3.new(0.15, height, 0.15),
		CFrame.new(0.55, height / 2, 0),
		Color3.fromRGB(120, 86, 48),
		Enum.Material.Wood
	)
	Kit.decor(right, false)
	-- A rung every 2 studs along 12 studs: 2, 4, 6, 8, 10.
	for y = 2, 10, 2 do
		local rung =
			Kit.part(model, "Rung", Vector3.new(1.25, 0.12, 0.28), CFrame.new(0, y, 0), PlankHoney, Enum.Material.Wood)
		Kit.decor(rung, false)
	end
	local hook = Kit.part(
		model,
		"Hook",
		Vector3.new(1.4, 0.16, 0.3),
		CFrame.new(0, height - 0.1, 0),
		IronBlack,
		Enum.Material.Metal
	)
	Kit.decor(hook, false)
	weldAll(model, left)
	model:SetAttribute("Length", height)
	return model
end

function MiningArt.LampPost(): Model
	local model = Instance.new("Model")
	model.Name = "CopperLampPost"
	local pole = Kit.part(
		model,
		"Pole",
		Vector3.new(0.35, 6, 0.35),
		CFrame.new(0, 3, 0),
		Color3.fromRGB(184, 115, 51),
		Enum.Material.Metal
	)
	model.PrimaryPart = pole
	Kit.part(model, "Base", Vector3.new(1.2, 0.3, 1.2), CFrame.new(0, 0.15, 0), StoneBase, Enum.Material.Slate)
	local arm = Kit.part(model, "Arm", Vector3.new(1.4, 0.2, 0.2), CFrame.new(0.7, 5.7, 0), Brass, Enum.Material.Metal)
	Kit.decor(arm, false)
	local lamp =
		Kit.part(model, "Lamp", Vector3.new(0.7, 0.7, 0.7), CFrame.new(1.3, 5.2, 0), LavaGlow, Enum.Material.Glass)
	Kit.decor(lamp, false)
	return model
end

function MiningArt.Chest(): Model
	local model = Instance.new("Model")
	model.Name = "GoldChest"
	local box =
		Kit.part(model, "Box", Vector3.new(2.4, 1.2, 1.4), CFrame.new(0, 0.7, 0), TimberBrown, Enum.Material.Wood)
	model.PrimaryPart = box
	local lid =
		Kit.part(model, "Lid", Vector3.new(2.5, 0.35, 1.5), CFrame.new(0, 1.4, 0), PlankHoney, Enum.Material.Wood)
	Kit.decor(lid, false)
	local band = Kit.part(
		model,
		"Band",
		Vector3.new(2.55, 0.18, 1.55),
		CFrame.new(0, 0.9, 0),
		Color3.fromRGB(212, 175, 55),
		Enum.Material.Metal
	)
	Kit.decor(band, false)
	local band2 = Kit.part(
		model,
		"Band",
		Vector3.new(0.18, 1.3, 1.55),
		CFrame.new(0, 0.75, 0),
		Color3.fromRGB(212, 175, 55),
		Enum.Material.Metal
	)
	Kit.decor(band2, false)
	return model
end

---------------------------------------------------------------------------
-- The pad: furnace, chute, stall, bench. A truck backs in from +Z.
---------------------------------------------------------------------------

local function lantern(model: Model, cf: CFrame, withLight: boolean)
	local lamp = Kit.part(model, "Lantern", Vector3.new(0.4, 0.55, 0.4), cf, Brass, Enum.Material.Metal)
	Kit.decor(lamp, false)
	local glow = Kit.part(model, "LanternGlow", Vector3.new(0.22, 0.28, 0.22), cf, LavaGlow, Enum.Material.Neon)
	Kit.decor(glow, false)
	if withLight then
		local light = Instance.new("PointLight")
		light.Name = "FurnaceLight"
		light.Color = LavaGlow
		light.Range = 14
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = glow
	end
end

-- The furnace, on the TLD-1 deck standard (8 x 10, deck stubs in at -Z and
-- out at +Z, reference LINE-STANDARD.md). Ore comes in over the -Z stub, ingots
-- leave over the +Z stub. FireMouth stays the gameplay Part (the only glow,
-- with one PointLight); the mesh has an open recess around it. With the
-- Blender body (MachineMeshes "SmeltingFurnace") the posts, beams, plinth,
-- firebox and chimney stay as see-through colliders and the roof, shingles
-- and lanterns are not built.
local FURNACE_HIDE = { StoneBase = true, Beam = true, Firebox = true, Chimney = true, StubDeck = true }

function MiningArt.SmeltingFurnace(): Model
	local model = Instance.new("Model")
	model.Name = "SmeltingFurnace"
	local skin = MachineSkin.Prepare("SmeltingFurnace", false)
	local meshed = skin ~= nil
	local base =
		Kit.part(model, "StoneBase", Vector3.new(8, 1.2, 6), CFrame.new(0, 0.6, 0), StoneBase, Enum.Material.Slate)
	model.PrimaryPart = base
	for _, x in ipairs({ -3.4, 3.4 }) do
		for _, z in ipairs({ -2.4, 2.4 }) do
			Kit.part(
				model,
				"Post",
				Vector3.new(0.45, 5.2, 0.45),
				CFrame.new(x, 3.5, z),
				TimberBrown,
				Enum.Material.Wood
			)
		end
	end
	Kit.part(model, "Beam", Vector3.new(7.6, 0.4, 0.4), CFrame.new(0, 6.1, -2.4), TimberBrown, Enum.Material.Wood)
	Kit.part(model, "Beam", Vector3.new(7.6, 0.4, 0.4), CFrame.new(0, 6.1, 2.4), TimberBrown, Enum.Material.Wood)
	if not meshed then
		local roofL = Kit.wedge(
			model,
			"Roof",
			Vector3.new(8.4, 1.6, 3.4),
			CFrame.new(0, 6.6, -1.5) * CFrame.Angles(0, math.pi, 0),
			RoofSlate,
			Enum.Material.Slate
		)
		Kit.decor(roofL, false)
		local roofR = Kit.wedge(
			model,
			"Roof",
			Vector3.new(8.4, 1.6, 3.4),
			CFrame.new(0, 6.6, 1.5),
			RoofSlate,
			Enum.Material.Slate
		)
		Kit.decor(roofR, false)
		for i = -3, 3 do
			local shingle = Kit.part(
				model,
				"Shingle",
				Vector3.new(1.05, 0.12, 3.2),
				CFrame.new(i * 1.1, 7.15, 0),
				Color3.fromRGB(58, 62, 70),
				Enum.Material.Slate
			)
			Kit.decor(shingle, false)
		end
	end
	Kit.part(model, "Firebox", Vector3.new(3.2, 2.2, 2.4), CFrame.new(0, 2.2, -0.4), StoneBase, Enum.Material.Slate)
	local mouth = Kit.part(
		model,
		"FireMouth",
		Vector3.new(1.6, 1.1, 0.2),
		CFrame.new(0, 2.1, -1.65),
		LavaGlow,
		Enum.Material.Neon
	)
	Kit.decor(mouth, false)
	Kit.part(model, "Chimney", Vector3.new(1.1, 2.4, 1.1), CFrame.new(2.2, 7.2, 0.6), StoneBase, Enum.Material.Slate)
	-- The sensor over the -Z stub: a chunk whose centre is inside it is smelted
	-- (MiningService). Not a collider: the stub deck under it carries the ore.
	local intake = Kit.part(
		model,
		"SmeltIntake",
		Vector3.new(5, 1.6, 2.7),
		CFrame.new(0, 1.5, -3.65),
		IronBlack,
		Enum.Material.DiamondPlate
	)
	intake.Transparency = if meshed then 1 else 0.6
	intake.CanCollide = false
	intake.CanQuery = false
	intake.CanTouch = false
	intake.CastShadow = false
	intake:SetAttribute("SmeltIntake", true)
	pcall(function()
		game:GetService("CollectionService"):AddTag(intake, "SmeltIntake")
	end)
	-- The two deck stubs (5.0 wide, top 0.72), flush to the port faces.
	for _, z in ipairs({ -3.65, 3.65 }) do
		local stub = Kit.part(
			model,
			"StubDeck",
			Vector3.new(5, 0.32, 2.7),
			CFrame.new(0, 0.56, z),
			IronBlack,
			Enum.Material.Metal
		)
		stub.CanTouch = false
	end
	local tray = Kit.part(
		model,
		"OutputTray",
		Vector3.new(3.2, 0.3, 2.2),
		CFrame.new(0, 1.3, 3.9),
		PlankHoney,
		Enum.Material.Wood
	)
	Kit.decor(tray, false)
	if meshed then
		-- One PointLight, Shadows off, on the only glow.
		local light = Instance.new("PointLight")
		light.Name = "FurnaceLight"
		light.Color = LavaGlow
		light.Range = 14
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = mouth
		tray.Transparency = 1
	else
		lantern(model, CFrame.new(-3.2, 4.6, -2.2), true)
		lantern(model, CFrame.new(3.2, 4.6, -2.2), false)
	end
	if skin ~= nil then
		MachineSkin.Commit(model, skin, CFrame.identity, FURNACE_HIDE)
	end
	return model
end

-- The furnace door: closed over the mouth, or ajar as the mesh is modelled
-- (about its hinge, a quarter turn less than square). No-op on the part build.
MiningArt.FurnaceDoorAjar = math.rad(55)

function MiningArt.SetFurnaceDoor(model: Model, closed: boolean): boolean
	local hinge = MachineMeshes.Point("SmeltingFurnace", "DoorHinge")
	if hinge == nil then
		return false
	end
	return MachineSkin.Swing(model, "FurnaceDoor", hinge, "Y", if closed then -MiningArt.FurnaceDoorAjar else 0)
end

function MiningArt.Prospector(): Model
	local model = Instance.new("Model")
	model.Name = "Prospector"
	local skin = MachineSkin.Prepare("Prospector", false)
	local chuteSkin = MachineSkin.Prepare("OreChute", false)
	local meshed = skin ~= nil
	local counter =
		Kit.part(model, "Counter", Vector3.new(6, 1.1, 2.2), CFrame.new(0, 1.1, 0), PlankHoney, Enum.Material.Wood)
	model.PrimaryPart = counter
	Kit.part(model, "Post", Vector3.new(0.35, 3.2, 0.35), CFrame.new(-2.6, 2.6, -0.8), TimberBrown, Enum.Material.Wood)
	Kit.part(model, "Post", Vector3.new(0.35, 3.2, 0.35), CFrame.new(2.6, 2.6, -0.8), TimberBrown, Enum.Material.Wood)
	if not meshed then
		local roof = Kit.wedge(
			model,
			"Awning",
			Vector3.new(6.4, 0.5, 2.4),
			CFrame.new(0, 4.3, -0.6),
			RoofSlate,
			Enum.Material.Slate
		)
		Kit.decor(roof, false)
	end
	-- The board's text is a SurfaceGui on the Sign part. Under the mesh the
	-- part is see-through and stands a hair in front of the mesh's plate.
	local sign = Kit.part(
		model,
		"Sign",
		Vector3.new(3.2, 0.9, if meshed then 0.04 else 0.2),
		CFrame.new(0, 3.5, if meshed then -1.72 else -1.5),
		TimberBrown,
		Enum.Material.Wood
	)
	Kit.signText(sign, "PROSPECTOR", Color3.fromRGB(245, 235, 215), { Enum.NormalId.Front })
	if meshed then
		sign.Transparency = 1
		sign.CanCollide = false
		sign.CanQuery = false
		sign.CanTouch = false
		sign.CastShadow = false
	end
	local chute = Kit.part(
		model,
		"OreChute",
		Vector3.new(3.2, 2.4, 2.4),
		CFrame.new(4.2, 1.2, 0),
		IronBlack,
		Enum.Material.DiamondPlate
	)
	chute.Transparency = if chuteSkin ~= nil then 1 else 0.15
	chute:SetAttribute("OreChute", true)
	local stand = Kit.part(
		model,
		"NpcStand",
		Vector3.new(1.2, 0.2, 1.2),
		CFrame.new(-1.2, 0.1, 1.6),
		StoneBase,
		Enum.Material.Slate
	)
	Kit.decor(stand, false)
	if skin ~= nil then
		MachineSkin.Commit(model, skin, CFrame.identity, { Counter = true })
		stand.Transparency = 1
	end
	if chuteSkin ~= nil then
		-- The hopper and its flap, on the ground under the chute's hit box.
		for _, piece in ipairs(chuteSkin.parts) do
			local offset = MachineMeshes.Piece("OreChute", piece.Name)
			piece.CFrame = CFrame.new(4.2, 0, 0) * CFrame.new(if offset then offset.offset else Vector3.zero)
			piece.Parent = model
		end
	end
	return model
end

function MiningArt.CraftBench(): Model
	local model = Instance.new("Model")
	model.Name = "CraftBench"
	local skin = MachineSkin.Prepare("CraftBench", false)
	local top = Kit.part(model, "Top", Vector3.new(4.2, 0.3, 2), CFrame.new(0, 1.7, 0), PlankHoney, Enum.Material.Wood)
	model.PrimaryPart = top
	for _, x in ipairs({ -1.8, 1.8 }) do
		Kit.part(model, "Leg", Vector3.new(0.28, 1.6, 0.28), CFrame.new(x, 0.8, -0.7), TimberBrown, Enum.Material.Wood)
		Kit.part(model, "Leg", Vector3.new(0.28, 1.6, 0.28), CFrame.new(x, 0.8, 0.7), TimberBrown, Enum.Material.Wood)
	end
	if skin == nil then
		local vise = Kit.part(
			model,
			"Vise",
			Vector3.new(0.4, 0.35, 0.5),
			CFrame.new(1.5, 2, 0.4),
			IronBlack,
			Enum.Material.Metal
		)
		Kit.decor(vise, false)
	else
		MachineSkin.Commit(model, skin, CFrame.identity, { Top = true })
	end
	return model
end

function MiningArt.Rubble(id: string, tier: number): Model
	local model = Instance.new("Model")
	model.Name = "Rubble"
	local wall = Kit.part(model, "Wall", Vector3.new(16, 12, 6), CFrame.new(0, 6, 0), StoneBase, Enum.Material.Slate)
	model.PrimaryPart = wall
	for i = 1, 6 do
		local chunk = Kit.part(
			model,
			"Stone",
			Vector3.new(2.2, 1.6, 1.4),
			CFrame.new(-6 + i * 1.8, 1 + (i % 3), 2.2),
			Color3.fromRGB(110, 104, 96),
			Enum.Material.Slate
		)
		Kit.decor(chunk, false)
	end
	model:SetAttribute("RubbleId", id)
	model:SetAttribute("Tier", tier)
	pcall(function()
		game:GetService("CollectionService"):AddTag(model, "Rubble")
	end)
	return model
end

-- Where the pieces sit on the 30 x 24 pad so a truck backs onto the
-- chute and the intake from the south (+Z).
function MiningArt.PadLayout(): { [string]: CFrame }
	return {
		furnace = CFrame.new(-6, 0, -2),
		prospector = CFrame.new(8, 0, -6),
		bench = CFrame.new(8, 0, 4),
	}
end

return MiningArt
