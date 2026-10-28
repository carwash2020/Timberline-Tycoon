--!strict
-- ShopPlace (T412): builds each shop model the map places. The four live
-- stores stay BuildingArt.Shop. Kiosks, Odds and Ends, the Land Office, the
-- secret cave, and the cloud market are greyboxes until Connor uploads a mesh.
-- MeshId 0 keeps those parts. ShopPlace.HideStandIns hides StandIn parts once
-- a mesh id is set. Sparkworks keeps its store and is signed shut.

local BuildingArt = require(script.Parent.BuildingArt)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local ShopPins = require(script.Parent.Parent.World.ShopPins)
local TerrainGen = require(script.Parent.Parent.World.TerrainGen)
local WorldLayout = require(script.Parent.Parent.World.WorldLayout)

local ShopPlace = {}

local KRAFT = Kit.hex("#C4A574")
local TAPE = Kit.hex("#E8D9A8")
local WOOD = Enum.Material.Wood
local PLANKS = Enum.Material.WoodPlanks

local function marker(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Kit.part(model, name, size, cf, color, material)
	part:SetAttribute("StandIn", true)
	return part
end

local function dress(part: Part): Part
	Kit.decor(part, false)
	return part
end

local function lightOn(part: BasePart, color: Color3)
	local light = Instance.new("PointLight")
	light.Brightness = 1.4
	light.Range = 12
	light.Color = color
	light.Shadows = false
	light.Parent = part
end

local function hero(model: Model, cf: CFrame, size: Vector3, color: Color3)
	local part = dress(Kit.part(model, "Hero", size, cf, color, Enum.Material.SmoothPlastic))
	lightOn(part, color)
	return part
end

local function kraft(model: Model, cf: CFrame, size: Vector3, label: string)
	-- `cf` is the centre of the box. The caller sits it on a solid top.
	local box = dress(Kit.part(model, "KraftBox", size, cf, KRAFT, PLANKS))
	local tape = dress(
		Kit.part(
			model,
			"KraftTape",
			Vector3.new(size.X + 0.02, 0.12, size.Z + 0.02),
			cf * CFrame.new(0, size.Y / 2 - 0.02, 0),
			TAPE,
			Enum.Material.SmoothPlastic
		)
	)
	tape.CastShadow = false
	local face = dress(
		Kit.part(
			model,
			"KraftLabel",
			Vector3.new(size.X * 0.7, size.Y * 0.45, 0.04),
			cf * CFrame.new(0, 0, -size.Z / 2 - 0.02),
			Palette.SignCream,
			Enum.Material.SmoothPlastic
		)
	)
	Kit.signText(face, label, Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.15)
	local band = dress(
		Kit.part(
			model,
			"KraftBand",
			Vector3.new(size.X * 0.7, 0.08, 0.05),
			cf * CFrame.new(0, -size.Y * 0.12, -size.Z / 2 - 0.04),
			Palette.Brass,
			Enum.Material.SmoothPlastic
		)
	)
	band.CastShadow = false
	return box
end

local function zoneSign(model: Model, text: string, cf: CFrame)
	local board = dress(
		Kit.part(model, "ZoneSign", Vector3.new(3.2, 0.8, 0.16), cf, Palette.SignCream, Enum.Material.SmoothPlastic)
	)
	Kit.signText(board, text, Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.GothamBold, 0.2)
end

local function shopPin(model: Model)
	local pin = Kit.part(
		model,
		"ShopPin",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(0, 0.2, 0),
		Palette.Brass,
		Enum.Material.Metal
	)
	pin.Transparency = 1
	pin.CanCollide = false
	pin.CanQuery = false
	pin.CanTouch = false
	pin.CastShadow = false
end

-- A front wall with a door gap. The opening part is the clearance volume.
local function front(
	model: Model,
	halfW: number,
	wallH: number,
	doorW: number,
	doorH: number,
	z: number,
	color: Color3,
	floorTop: number
)
	local gap = doorW / 2 + 0.15
	local side = halfW - gap
	if side > 0.2 then
		marker(
			model,
			"Wall",
			Vector3.new(side, wallH, 0.45),
			CFrame.new(-(gap + side / 2), wallH / 2, z),
			color,
			PLANKS
		)
		marker(model, "Wall", Vector3.new(side, wallH, 0.45), CFrame.new(gap + side / 2, wallH / 2, z), color, PLANKS)
	end
	local doorTop = floorTop + doorH
	local header = wallH - doorTop
	if header > 0.15 then
		marker(model, "Wall", Vector3.new(doorW, header, 0.45), CFrame.new(0, doorTop + header / 2, z), color, PLANKS)
	end
	local opening = Kit.part(
		model,
		"DoorOpening",
		Vector3.new(doorW, doorH, 0.3),
		CFrame.new(0, floorTop + doorH / 2, z),
		Palette.TimberBrown,
		WOOD
	)
	opening.Transparency = 1
	opening.CanCollide = false
	opening.CanQuery = false
	opening.CanTouch = false
	opening.CastShadow = false
end

local function approach(model: Model, z: number)
	local pad = Kit.part(
		model,
		"Approach",
		Vector3.new(8, 0.2, 8),
		CFrame.new(0, 0.12, z),
		Palette.StoneBase,
		Enum.Material.Cobblestone
	)
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
end

local function aisle(model: Model, size: Vector3, cf: CFrame)
	local clear = Kit.part(model, "AisleClear", size, cf, Palette.SignCream, Enum.Material.SmoothPlastic)
	clear.Transparency = 1
	clear.CanCollide = false
	clear.CanQuery = false
	clear.CanTouch = false
	clear.CastShadow = false
end

local function backDoor(model: Model, x: number, z: number)
	local door =
		Kit.part(model, "BackRoomDoor", Vector3.new(4, 7.5, 0.3), CFrame.new(x, 3.75, z), Palette.TimberBrown, WOOD)
	door.CanCollide = false
	door.CanQuery = false
	door.CanTouch = false
end

local function counterAt(model: Model, z: number, floorTop: number): Part
	local height = 3.2
	return Kit.part(
		model,
		"Counter",
		Vector3.new(4.5, height, 1.2),
		CFrame.new(0, floorTop + height / 2, z),
		Palette.TimberBrown,
		WOOD
	)
end

-- Lune cannot read BasePart.Position. Stay in the counter's own CFrame.
local function onCounter(counter: BasePart, x: number, lift: number): CFrame
	return counter.CFrame * CFrame.new(x, counter.Size.Y / 2 + lift, 0)
end

local function kiosk(title: string, accent: Color3, hook: string): Model
	local model = Kit.model("Kiosk")
	marker(model, "Floor", Vector3.new(8, 0.4, 6), CFrame.new(0, 0.2, 0), Palette.StoneBase, Enum.Material.Cobblestone)
	marker(model, "Wall", Vector3.new(8, 8, 0.4), CFrame.new(0, 4, 2.8), Palette.PlankHoney, PLANKS)
	marker(model, "Wall", Vector3.new(0.4, 8, 5.2), CFrame.new(-3.8, 4, 0.2), Palette.PlankHoney, PLANKS)
	marker(model, "Wall", Vector3.new(0.4, 8, 5.2), CFrame.new(3.8, 4, 0.2), Palette.PlankHoney, PLANKS)
	marker(model, "Roof", Vector3.new(8.6, 0.3, 6.6), CFrame.new(0, 8.15, 0), Palette.RoofSlate, Enum.Material.Slate)
	front(model, 4, 8, 4, 7.5, -2.8, Palette.PlankHoney, 0.4)
	local counter = counterAt(model, -1.4, 0.4)
	approach(model, -7.2)
	local top = onCounter(counter, 0, 0)
	hero(model, top * CFrame.new(-1.1, 0.9, 0), Vector3.new(0.7, 1.6, 0.25), accent)
	kraft(model, top * CFrame.new(1.15, 0.4, 0), Vector3.new(1.1, 0.8, 0.8), hook)
	zoneSign(model, hook, CFrame.new(0, 6.4, -3.15))
	local sign = marker(
		model,
		"Sign",
		Vector3.new(5, 1.2, 0.16),
		CFrame.new(0, 7.2, -3.2),
		Palette.SignCream,
		Enum.Material.SmoothPlastic
	)
	sign.CanCollide = false
	Kit.signText(sign, title, Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.18)
	local strip = dress(
		Kit.part(model, "GlowStrip", Vector3.new(6, 0.12, 0.08), CFrame.new(0, 7.6, -3.05), accent, Enum.Material.Neon)
	)
	strip.CastShadow = false
	return model
end

local function shack(title: string): Model
	local model = Kit.model("OddsAndEnds")
	marker(model, "Floor", Vector3.new(20, 0.4, 16), CFrame.new(0, 0.2, 0), Palette.TrailDirt, Enum.Material.Ground)
	marker(model, "Wall", Vector3.new(20, 9, 0.45), CFrame.new(0, 4.5, 7.8), Palette.WeatheredPlank, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 9, 15), CFrame.new(-9.8, 4.5, 0), Palette.PlankHoney, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 9, 15), CFrame.new(9.8, 4.5, 0), Palette.PlankHoney, PLANKS)
	-- Tin roof, a little crooked, still clear of the door.
	local roof = marker(
		model,
		"Roof",
		Vector3.new(21, 0.28, 17),
		CFrame.new(0.2, 9.2, 0.2) * CFrame.Angles(0.04, 0.03, -0.03),
		Palette.RoofSlate,
		Enum.Material.Metal
	)
	roof.Name = "Roof"
	front(model, 10, 9, 4.5, 7.5, -7.8, Palette.WeatheredPlank, 0.4)
	marker(model, "Shelf", Vector3.new(2.2, 4, 8), CFrame.new(-8.2, 2.2, 1), Palette.TimberBrown, WOOD)
	marker(model, "Shelf", Vector3.new(2.2, 4, 8), CFrame.new(8.2, 2.2, 1), Palette.TimberBrown, WOOD)
	aisle(model, Vector3.new(8, 4, 8), CFrame.new(0, 3.2, 1))
	local counter = counterAt(model, -5.6, 0.4)
	local top = onCounter(counter, 0, 0)
	hero(model, top * CFrame.new(-1, 0.7, 0), Vector3.new(0.5, 1.2, 0.5), Palette.CoinGold)
	kraft(model, top * CFrame.new(1.2, 0.45, 0), Vector3.new(1.2, 0.9, 0.9), "CHARGE")
	backDoor(model, -6, 7.5)
	zoneSign(model, "CHARGES", CFrame.new(-8.2, 5.2, 1))
	zoneSign(model, "LANTERN", CFrame.new(8.2, 5.2, 1))
	local sign =
		dress(Kit.part(model, "Sign", Vector3.new(6, 1.3, 0.16), CFrame.new(0, 8.2, -8.15), Palette.SignCream, WOOD))
	Kit.signText(sign, title, Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.16)
	approach(model, -12.2)
	return model
end

local function office(): Model
	local model = Kit.model("LandOffice")
	-- Narrower than the 24-wide guidance so the plot-district signpost (x ~145) stays outside the walls.
	marker(
		model,
		"Floor",
		Vector3.new(14, 0.4, 16),
		CFrame.new(0, 0.2, 1),
		Palette.StoneBase,
		Enum.Material.Cobblestone
	)
	marker(model, "Wall", Vector3.new(14, 10, 0.45), CFrame.new(0, 5, 8.8), Palette.PlankHoney, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 10, 15), CFrame.new(-6.8, 5, 1), Palette.WeatheredPlank, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 10, 15), CFrame.new(6.8, 5, 1), Palette.WeatheredPlank, PLANKS)
	marker(model, "Roof", Vector3.new(15, 0.4, 19), CFrame.new(0, 10.2, 0), Palette.RoofSlate, Enum.Material.Slate)
	front(model, 7, 10, 4.5, 7.5, -8.8, Palette.PlankHoney, 0.4)
	marker(model, "Shelf", Vector3.new(1.4, 4, 8), CFrame.new(-5.6, 2.2, 0), Palette.TimberBrown, WOOD)
	marker(model, "Shelf", Vector3.new(1.4, 4, 8), CFrame.new(5.6, 2.2, 0), Palette.TimberBrown, WOOD)
	aisle(model, Vector3.new(8, 4, 8), CFrame.new(0, 3.2, 0))
	local counter = counterAt(model, -6.2, 0.4)
	local board =
		marker(model, "PlotMap", Vector3.new(10, 6, 0.3), CFrame.new(0, 5.2, -9.3), Palette.Brass, Enum.Material.Metal)
	board.CanCollide = false
	hero(model, CFrame.new(-3.2, 5.2, -9.15), Vector3.new(0.4, 1.2, 0.2), Palette.Brass)
	kraft(model, onCounter(counter, 1.1, 0.4), Vector3.new(1.1, 0.8, 0.8), "DEED")
	backDoor(model, -8, 8.4)
	zoneSign(model, "DEEDS", CFrame.new(0, 6.6, -6))
	local sign =
		dress(Kit.part(model, "Sign", Vector3.new(8, 1.4, 0.16), CFrame.new(0, 8.6, -9.2), Palette.SignCream, WOOD))
	Kit.signText(sign, "LAND OFFICE", Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.16)
	approach(model, -13.2)
	return model
end

local function cave(): Model
	local model = Kit.model("SecretShop")
	model:SetAttribute("Sold", false)
	marker(model, "Mouth", Vector3.new(10, 8, 2), CFrame.new(0, 4, -7), Palette.StoneBase, Enum.Material.Slate)
	marker(model, "Floor", Vector3.new(16, 0.4, 12), CFrame.new(0, 0.2, 0), Palette.StoneBase, Enum.Material.Slate)
	marker(model, "Wall", Vector3.new(16, 8, 0.45), CFrame.new(0, 4, 5.8), Palette.PlankHoney, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 8, 11), CFrame.new(-7.8, 4, 0), Palette.WeatheredPlank, PLANKS)
	marker(model, "Wall", Vector3.new(0.45, 8, 11), CFrame.new(7.8, 4, 0), Palette.WeatheredPlank, PLANKS)
	marker(model, "Roof", Vector3.new(16.4, 0.4, 12.4), CFrame.new(0, 8.2, 0), Palette.StoneBase, Enum.Material.Slate)
	front(model, 8, 8, 4.5, 7.5, -5.8, Palette.StoneBase, 0.4)
	marker(model, "Shelf", Vector3.new(1.6, 3.5, 6), CFrame.new(-6.4, 2, 0), Palette.TimberBrown, WOOD)
	marker(model, "Shelf", Vector3.new(1.6, 3.5, 6), CFrame.new(6.4, 2, 0), Palette.TimberBrown, WOOD)
	aisle(model, Vector3.new(8, 3.5, 6), CFrame.new(0, 2.8, 0))
	local counter = counterAt(model, -3.6, 0.4)
	hero(model, CFrame.new(4.5, 3.2, 4.2), Vector3.new(1.4, 2.2, 0.8), Kit.hex("#7A4FD0"))
	kraft(model, onCounter(counter, 1, 0.35), Vector3.new(1, 0.7, 0.7), "STUDY")
	backDoor(model, -5, 5.4)
	zoneSign(model, "PAINTINGS", CFrame.new(0, 5.5, 4.6))
	approach(model, -10.2)
	return model
end

local function market(): Model
	local model = Kit.model("SkyMarket")
	marker(model, "Floor", Vector3.new(12, 0.4, 10), CFrame.new(0, 0.2, 0), Palette.StoneBase, Enum.Material.Slate)
	marker(model, "Stall", Vector3.new(12, 5, 0.3), CFrame.new(0, 2.7, 4.6), Palette.PlankHoney, PLANKS)
	marker(model, "Post", Vector3.new(0.4, 6, 0.4), CFrame.new(-5.4, 3, -2), Palette.TimberBrown, WOOD)
	marker(model, "Post", Vector3.new(0.4, 6, 0.4), CFrame.new(5.4, 3, -2), Palette.TimberBrown, WOOD)
	local awning = dress(
		Kit.part(
			model,
			"Awning",
			Vector3.new(12.4, 0.15, 4),
			CFrame.new(0, 6.1, -0.4) * CFrame.Angles(-0.2, 0, 0),
			Palette.LumenGlow,
			Enum.Material.Fabric
		)
	)
	awning.CastShadow = false
	front(model, 6, 8.2, 4.2, 7.5, -4.7, Palette.PlankHoney, 0.4)
	local counter = counterAt(model, -2.4, 0.4)
	hero(model, CFrame.new(0, 2.6, 2.2), Vector3.new(1.2, 1.8, 1.2), Palette.StarfallGlow)
	kraft(model, onCounter(counter, 1.2, 0.35), Vector3.new(1, 0.7, 0.7), "RELIC")
	zoneSign(model, "RELICS", CFrame.new(0, 4.4, 1))
	approach(model, -9)
	return model
end

local function pilings(model: Model, kind: string)
	local row = ShopPins.Get(kind)
	if row == nil or row.cloud or row.y ~= nil then
		return
	end
	local ground = TerrainGen.HeightAt(row.ox, row.oz)
	local deck = math.max(ground, WorldLayout.SeaLevel + 1)
	local drop = deck - ground
	if drop <= 0.5 then
		return
	end
	for _, corner in ipairs({ { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } }) do
		marker(
			model,
			"Piling",
			Vector3.new(1.1, drop, 1.1),
			CFrame.new(corner[1], -drop / 2, corner[2]),
			Palette.WeatheredPlank,
			WOOD
		)
	end
end

local function ensureCommon(model: Model, kind: string, title: string)
	if model:FindFirstChild("ShopPin") == nil then
		shopPin(model)
	end
	if model:FindFirstChild("ZoneSign", true) == nil then
		zoneSign(model, title, CFrame.new(0, 6, -2))
	end
	if model:FindFirstChild("Counter") == nil then
		counterAt(model, -8, 0.8)
	end
	if model:FindFirstChild("DoorBlock", true) == nil and model:FindFirstChild("DoorOpening") == nil then
		local opening = Kit.part(
			model,
			"DoorOpening",
			Vector3.new(6, 7.5, 0.3),
			CFrame.new(0, 0.8 + 3.75, -12.5),
			Palette.TimberBrown,
			WOOD
		)
		opening.Transparency = 1
		opening.CanCollide = false
		opening.CanQuery = false
		opening.CanTouch = false
		opening.CastShadow = false
	end
	local counter = model:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		if model:FindFirstChild("Hero", true) == nil then
			hero(model, onCounter(counter, -1.2, 0.6), Vector3.new(0.6, 1.2, 0.3), Palette.Brass)
		end
		if model:FindFirstChild("KraftBox", true) == nil then
			kraft(model, onCounter(counter, 1.3, 0.4), Vector3.new(1.1, 0.8, 0.8), "GOODS")
		end
	end
	if kind == "Sparkworks" then
		model:SetAttribute("FerryRequired", true)
		local board = dress(
			Kit.part(
				model,
				"FerrySign",
				Vector3.new(6, 1.4, 0.16),
				CFrame.new(0, 6.5, -2),
				Palette.SignCream,
				Enum.Material.SmoothPlastic
			)
		)
		board:SetAttribute("Text", "Ferry required")
		Kit.signText(board, "FERRY REQUIRED", Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.GothamBold, 0.16)
		if model:FindFirstChild("BackRoomDoor", true) == nil then
			local frame = BuildingArt.InteriorFrame("Sparkworks", BuildingArt.Scale.Sparkworks or 1)
			backDoor(model, 0, frame.frame.halfD - 0.5)
		end
	end
	if kind == "SecretShop" then
		model:SetAttribute("Sold", false)
	end
	if kind == "CoatKiosk" or kind == "HeatBoots" or kind == "OddsAndEnds" then
		BuildingArt.PlaceShelfSlots(model, kind)
	end
end

function ShopPlace.Build(kind: string, title: string, accent: Color3): Model
	local model: Model
	if kind == "ToolShed" or kind == "HearthAndHome" or kind == "Dealership" or kind == "Sparkworks" then
		model = BuildingArt.Shop(kind, title, accent)
	elseif kind == "SkyForge" then
		model = BuildingArt.SkyForgeCourt()
	elseif kind == "CoatKiosk" or kind == "HeatBoots" then
		model = kiosk(title, accent, if kind == "CoatKiosk" then "COAT" else "BOOTS")
	elseif kind == "OddsAndEnds" then
		model = shack(title)
	elseif kind == "LandOffice" then
		model = office()
	elseif kind == "SecretShop" then
		model = cave()
	elseif kind == "SkyMarket" then
		model = market()
	else
		model = Kit.model(kind)
	end
	model.Name = kind
	pilings(model, kind)
	ensureCommon(model, kind, title)
	return model
end

function ShopPlace.DeckY(kind: string): number
	local row = ShopPins.Get(kind)
	if row == nil then
		return 0
	end
	if row.y ~= nil then
		return row.y
	end
	local ground = TerrainGen.HeightAt(row.ox, row.oz)
	return math.max(ground, WorldLayout.SeaLevel + 1)
end

function ShopPlace.HideStandIns(model: Model, meshId: number)
	if type(meshId) ~= "number" or meshId == 0 then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("StandIn") == true then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

return ShopPlace
