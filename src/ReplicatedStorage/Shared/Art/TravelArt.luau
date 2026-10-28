--!strict
-- TravelArt: the T413 greyboxes. MeshId 0 until Connor uploads. Colours are
-- the Midday travel palette. The ferry boat itself stays LandmarkArt.FerryBoat.

local BuildingArt = require(script.Parent.BuildingArt)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local FerryLogic = require(script.Parent.Parent.FerryLogic)
local TerrainGen = require(script.Parent.Parent.World.TerrainGen)
local TravelPlan = require(script.Parent.Parent.TravelPlan)
local WorldLayout = require(script.Parent.Parent.World.WorldLayout)

local TravelArt = {}

local V3 = Vector3.new
local CF = CFrame.new
local WOOD = Enum.Material.Wood
local PLANKS = Enum.Material.WoodPlanks
local METAL = Enum.Material.Metal
local STONE = Enum.Material.Cobblestone
local CONCRETE = Enum.Material.Concrete
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GROUND = Enum.Material.Ground
local SAND = Enum.Material.Sand

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return Kit.part(model, name, size, cf, color, mat)
end

local function deck(model: Model, size: Vector3, cf: CFrame, color: Color3): Part
	local p = part(model, "Deck", size, cf, color, PLANKS)
	model.PrimaryPart = p
	return p
end

-- The valley already has ground, camps, and shops under these spans. The
-- greybox shows the bridge. It does not take the space those pieces occupy.
local function showOnly(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
end

function TravelArt.FreeBridge(): Model
	local model = Kit.model("FreeTownBridge")
	model:SetAttribute("Tolled", false)
	model:SetAttribute("Width", TravelPlan.FreeBridge.width)
	local span = TravelPlan.FreeBridge.length
	deck(model, V3(TravelPlan.FreeBridge.width, 1, span), CF(0, 0.5, 0), Palette.PlankHoney)
	for _, x in ipairs({ -1, 1 }) do
		part(
			model,
			"Abutment",
			V3(4, 6, span),
			CF(x * (TravelPlan.FreeBridge.width / 2 + 2), -2, 0),
			Palette.StoneBase,
			STONE
		)
		part(
			model,
			"Rail",
			V3(0.6, 3, span),
			CF(x * (TravelPlan.FreeBridge.width / 2 - 0.4), 2, 0),
			Palette.IronBlack,
			METAL
		)
	end
	showOnly(model)
	return model
end

function TravelArt.LiftBridge(): Model
	local model = Kit.model("LiftBridge")
	model:SetAttribute("Tolled", true)
	model:SetAttribute("Width", TravelPlan.LiftWidth)
	model:SetAttribute("Length", TravelPlan.LiftLength)
	local length, width = TravelPlan.LiftLength, TravelPlan.LiftWidth
	deck(model, V3(length, 1, width), CF(0, 0.5, 0), Palette.RoadGravel)
	local deckPart = model.PrimaryPart :: BasePart
	deckPart.Material = CONCRETE
	deckPart.Color = Palette.RoadGravel
	for _, x in ipairs({ -1, 1 }) do
		local tower = part(model, "Tower", V3(3, 28, 3), CF(x * (length / 2 - 4), 15, 0), Palette.IronBlack, METAL)
		tower.Name = "Tower"
		part(model, "Abutment", V3(6, 8, width + 4), CF(x * (length / 2 - 2), -3, 0), Palette.StoneBase, STONE)
		part(model, "Rail", V3(length, 3, 0.6), CF(0, 2.2, x * (width / 2 - 0.4)), Palette.IronBlack, METAL)
	end
	part(model, "Brace", V3(length - 10, 1.2, 1.2), CF(0, 26, 0), Palette.IronBlack, METAL)
	local arm = part(model, "StopRed", V3(width, 0.6, 0.6), CF(-length / 2 + 6, 3.2, 0), Palette.StopRed, NEON)
	arm.CanCollide = false
	-- Booth on the south side of the west approach, not in the lane.
	local booth = Kit.model("Booth")
	booth.Parent = model
	part(booth, "Wall", V3(8, 7, 6), CF(0, 3.5, 0), Palette.PlankHoney, PLANKS)
	part(booth, "Roof", V3(10, 1, 8), CF(0, 7.5, 0), Palette.RoofSlate, STONE)
	local counter = part(booth, "Counter", V3(6, 3, 1), CF(0, 2, -2), Palette.TimberBrown, WOOD)
	counter.Name = "Counter"
	local sign = part(booth, "TollSign", V3(6, 2, 0.2), CF(0, 6, -3.2), Palette.SignCream, PLASTIC)
	sign:SetAttribute("Text", TravelPlan.TollSign())
	Kit.signText(sign, TravelPlan.TollSign(), Palette.SignInk, { Enum.NormalId.Front, Enum.NormalId.Back })
	local lamp = part(booth, "Lamp", V3(0.8, 0.8, 0.8), CF(0, 8.4, -2), Palette.Brass, METAL)
	local light = Instance.new("PointLight")
	light.Color = Kit.hex("#FFC45C")
	light.Range = 14
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = lamp
	booth:PivotTo(CF(-length / 2 - 8, 0, width / 2 + 8))
	showOnly(model)
	return model
end

function TravelArt.StoneBridge(): Model
	local model = Kit.model("StoneBranch")
	model:SetAttribute("Width", TravelPlan.BranchWidth)
	deck(model, V3(TravelPlan.BranchWidth, 1, 20), CF(0, 0.5, 0), Palette.RoadGravel)
	local deckPart = model.PrimaryPart :: BasePart
	deckPart.Material = CONCRETE
	for _, x in ipairs({ -1, 1 }) do
		part(model, "Face", V3(2, 5, 20), CF(x * (TravelPlan.BranchWidth / 2 + 1), -1.5, 0), Palette.StoneBase, STONE)
	end
	return model
end

function TravelArt.FootBridge(): Model
	local model = Kit.model("GloamFoot")
	model:SetAttribute("Width", TravelPlan.FootWidth)
	deck(model, V3(TravelPlan.FootWidth, 0.4, 16), CF(0, 0.4, 0), Palette.PlankHoney)
	for _, x in ipairs({ -1, 1 }) do
		part(
			model,
			"Rope",
			V3(0.3, 3.2, 16),
			CF(x * (TravelPlan.FootWidth / 2 - 0.2), 1.8, 0),
			Palette.TimberBrown,
			WOOD
		)
	end
	return model
end

local function apron(model: Model, width: number, depth: number, centerX: number): Part
	local p = part(model, "Deck", V3(depth, 1, width), CF(centerX, 0.5, 0), Palette.WeatheredPlank, PLANKS)
	p.Position = V3(centerX, 0.5, 0)
	local posts = math.max(2, math.floor(width / 8))
	for i = 0, posts do
		local z = -width / 2 + (width / posts) * i
		-- West edge only, so a harbour shop to the east is not fenced in.
		part(model, "Bollard", V3(0.8, 2.2, 0.8), CF(centerX - depth / 2 + 1, 1.6, z), Palette.IronBlack, METAL)
		part(model, "Pile", V3(1, 6, 1), CF(centerX, -2.5, z), Palette.TimberBrown, WOOD)
	end
	return p
end

function TravelArt.MainlandDock(): Model
	local model = Kit.model("MainlandDock")
	local apronSize = TravelPlan.MainlandApron()
	local p = apron(model, apronSize.width, apronSize.depth, 0)
	model.PrimaryPart = p
	local board =
		part(model, "FerryBoard", V3(8, 3, 0.2), CF(0, 5, apronSize.width / 2 + 1), Palette.SignCream, PLASTIC)
	board:SetAttribute("Title", FerryLogic.BoardTitle())
	board:SetAttribute("Text", FerryLogic.TimetableText())
	Kit.signText(
		board,
		FerryLogic.BoardTitle() .. "\n" .. FerryLogic.TimetableText(),
		Palette.SignInk,
		{ Enum.NormalId.Front, Enum.NormalId.Back }
	)
	local sand = part(model, "Sand", V3(18, 0.4, 14), CF(-apronSize.depth, 0.1, 0), Palette.ShoreSand, SAND)
	sand.CanCollide = false
	return model
end

function TravelArt.IslandDock(): Model
	local model = Kit.model("IslandDock")
	local spec = TravelPlan.IslandApron()
	-- Local X is east. The pin is the origin. The apron sits west of it so
	-- the east edge stays off the Sparkworks floor once the pin is at x 1100.
	local centerX = spec.centerX - TravelPlan.IslandDock.x
	apron(model, spec.width, spec.depth, centerX)
	local pin = part(model, "Pin", V3(0.4, 0.4, 0.4), CF(0, 1, 0), Palette.Brass, METAL)
	pin.CanCollide = false
	pin.Transparency = 1
	model.PrimaryPart = pin
	return model
end

function TravelArt.PlaceSigns(parent: Instance, skipId: string?)
	for _, sign in ipairs(TravelPlan.Signs()) do
		if sign.id == skipId then
			continue
		end
		local post = BuildingArt.Signpost(sign.text, false, true, nil, true, true)
		post.Name = "JunctionSign"
		post:SetAttribute("SignId", sign.id)
		post:PivotTo(CF(sign.x, 0, sign.z))
		post.Parent = parent
	end
end

function TravelArt.SkyrootRoad(): Model
	local model = Kit.model("SkyrootRoad")
	local pts = TravelPlan.DrivenPoints()
	local y = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0.5 then
			local mid = CF((a.x + b.x) / 2, y + 0.3, (a.z + b.z) / 2)
			local yaw = math.atan2(dx, dz)
			local slab = part(
				model,
				"Deck",
				V3(TravelPlan.MainWidth, 0.6, len),
				mid * CFrame.Angles(0, yaw, 0),
				Palette.RoadGravel,
				CONCRETE
			)
			slab.CanCollide = false
			part(
				model,
				"Shoulder",
				V3(6, 0.4, len),
				mid * CFrame.Angles(0, yaw, 0) * CF(TravelPlan.MainWidth / 2 + 3, -0.1, 0),
				Palette.TrailDirt,
				GROUND
			).CanCollide =
				false
		end
	end
	return model
end

local function atGround(model: Model, x: number, z: number)
	local y = TerrainGen.HeightAt(x, z)
	if y < WorldLayout.SeaLevel then
		y = WorldLayout.SeaLevel
	end
	Kit.placeAt(model, CF(x, y, z))
end

local function persistent(model: Model)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
end

function TravelArt.Build(parent: Instance)
	local folder = Kit.model("Travel", parent)
	local free = TravelArt.FreeBridge()
	atGround(free, TravelPlan.FreeBridge.x, TravelPlan.FreeBridge.z)
	free.Parent = folder
	local lift = TravelArt.LiftBridge()
	atGround(lift, TravelPlan.LiftX, TravelPlan.LiftZ)
	persistent(lift)
	lift.Parent = folder
	local liftBooth = lift:FindFirstChild("Booth")
	if liftBooth and liftBooth:IsA("Model") then
		liftBooth.Name = "LiftBooth"
		liftBooth.Parent = parent
		persistent(liftBooth)
	end
	local stone = TravelArt.StoneBridge()
	atGround(stone, -420, 110)
	stone.Parent = folder
	local foot = TravelArt.FootBridge()
	atGround(foot, -565, -455)
	foot.Parent = folder
	local mainDock = TravelArt.MainlandDock()
	atGround(mainDock, TravelPlan.Mainland.x, TravelPlan.Mainland.z)
	persistent(mainDock)
	mainDock.Parent = folder
	local mainDeck = mainDock:FindFirstChild("Deck")
	if mainDeck then
		pcall(function()
			game:GetService("CollectionService"):AddTag(mainDeck, "FerryDock")
		end)
	end
	local isle = TravelArt.IslandDock()
	atGround(isle, TravelPlan.IslandDock.x, TravelPlan.IslandDock.z)
	persistent(isle)
	isle.Parent = folder
	local isleDeck = isle:FindFirstChild("Deck")
	if isleDeck then
		pcall(function()
			game:GetService("CollectionService"):AddTag(isleDeck, "FerryDock")
		end)
	end
	local road = TravelArt.SkyrootRoad()
	road.Parent = folder
	-- The lift booth already carries TOLL $100. A second post would sit in it.
	TravelArt.PlaceSigns(folder, "toll")
	local spur = TravelPlan.Spur()
	local span = math.abs(spur.b.z - spur.a.z)
	local spurModel = Kit.model("DealershipSpur")
	part(
		spurModel,
		"Deck",
		V3(spur.width, 0.4, span),
		CF(spur.a.x, 0.2, (spur.a.z + spur.b.z) / 2),
		Palette.RoadGravel,
		CONCRETE
	).CanCollide =
		false
	spurModel.Parent = folder
	return folder
end

return TravelArt
