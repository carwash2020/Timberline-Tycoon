--!strict
-- The dealership's open display lot: all eight trucks and trailers in one
-- row, facing the path along the south side (-Z). Each model is anchored,
-- has no scripts, streams Atomic, and carries a price sign on its own
-- front plus a buy prompt. MapBuilder places the model; ShopService buys
-- from the ShopDisplay tag.
--
-- Eight parking bays (about 118 studs before the gaps between them) do not
-- fit the lawn Job B keeps for this lot (x 184 to 296). The row uses each
-- vehicle's real width and the same walk gap between neighbours.

local CollectionService = game:GetService("CollectionService")

local CoreLoop = require(script.Parent.Parent.CoreLoop)
local GameConfig = require(script.Parent.Parent.GameConfig)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)
local ShopLogic = require(script.Parent.Parent.ShopLogic)
local TruckArt = require(script.Parent.TruckArt)
local TruckLayout = require(script.Parent.Parent.TruckLayout)
local Util = require(script.Parent.Parent.Util)

local DealershipLot = {}

-- Southwest corner of the row, inside the reserved lawn (x 184 to 296,
-- z 64 to 123). The path occupies z 64 to 70; the trucks start at z 70.
DealershipLot.OriginX = 184
DealershipLot.OriginZ = 70

local LOT_W = 112
local LOT_D = 53
local SIDE = 2.5 -- studs from the row's ends to the reserved edges
local FRONT = 4.2 -- bumper line, leaving the price sign inside the lot

local ORDER = {
	{ kind = "Truck", id = "Rustbucket" },
	{ kind = "Truck", id = "Pickup" },
	{ kind = "Truck", id = "ScoutATV" },
	{ kind = "Truck", id = "Flatbed" },
	{ kind = "Truck", id = "LoggingRig" },
	{ kind = "Trailer", id = "PonyTrailer" },
	{ kind = "Trailer", id = "RanchTrailer" },
	{ kind = "Trailer", id = "HeavyHauler" },
}

-- The loop the price signs use. MapBuilder publishes CoreLoopActive before
-- it builds the lot, so a Studio override shows here. Tests have no
-- workspace; the configured loop (GameConfig.CoreLoop) is the price then.
local function priceLoop(): number
	local ok, n = pcall(CoreLoop.Active)
	if ok and (n == 1 or n == 2) then
		local published = false
		pcall(function()
			published = workspace:GetAttribute(CoreLoop.ActiveAttribute) ~= nil
		end)
		if published then
			return n
		end
	end
	return if GameConfig.CoreLoop == 2 then 2 else 1
end

-- How wide the vehicle is, tyres included, and how long it is nose to tail.
local function measure(kind: string, id: string): (number, number)
	if kind == "Truck" then
		local def = ItemCatalog.GetTruck(id)
		if not def then
			return 10, 20
		end
		local lay = TruckLayout.For(def)
		return math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length
	end
	local trailer = ItemCatalog.GetTrailer(id)
	local truck = ItemCatalog.GetTruck("Pickup")
	if not trailer or not truck then
		return 10, 20
	end
	local lay = TruckLayout.ForTrailer(trailer, TruckLayout.For(truck))
	return math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length
end

-- Width and depth of the open lot, in studs: the reserved lawn's width,
-- and enough depth for the Logging Rig plus its price sign.
function DealershipLot.Size(): (number, number)
	return LOT_W, LOT_D
end

local function prep(model: Model, category: string, id: string)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Category", category)
	model:SetAttribute("ItemId", id)
	CollectionService:AddTag(model, "ShopDisplay")
	local scripts: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("VehicleSeat") then
			d.Disabled = true
			d.Anchored = true
		elseif d:IsA("BasePart") then
			d.Anchored = true
		elseif d.ClassName == "Script" or d.ClassName == "LocalScript" then
			table.insert(scripts, d)
		end
	end
	for _, d in ipairs(scripts) do
		d:Destroy()
	end
	local seat = model:FindFirstChild("DriverSeat", true)
	if seat and seat:IsA("VehicleSeat") then
		seat.Disabled = true
	end
end

-- The price board on this model's own nose, after it has been parked.
-- Relative to the pivot, so a later placeAt keeps it on this vehicle.
local function attachSign(model: Model, priceText: string, length: number)
	local sign = Kit.part(
		model,
		"PriceSign",
		Vector3.new(4.5, 2.4, 0.3),
		CFrame.new(),
		Color3.fromRGB(62, 42, 24),
		Enum.Material.Wood
	)
	sign.CFrame = model:GetPivot() * CFrame.new(0, 3.2, -length / 2 - 2)
	sign.CanCollide = false
	sign.CanQuery = false
	Kit.signText(sign, priceText, Color3.fromRGB(245, 235, 215), { Enum.NormalId.Front, Enum.NormalId.Back })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = priceText
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
end

local function priceOf(kind: string, id: string): string
	local item = if kind == "Truck" then ItemCatalog.GetTruck(id) else ItemCatalog.GetTrailer(id)
	if not item then
		return id
	end
	return item.displayName .. "\n" .. Util.formatCash(ShopLogic.Price(item, priceLoop()))
end

local function placeTruck(id: string): Model?
	local def = ItemCatalog.GetTruck(id)
	if not def then
		return nil
	end
	local model = TruckArt.Build(def)
	prep(model, "Truck", id)
	return model
end

local function placeTrailer(id: string): Model?
	local def = ItemCatalog.GetTrailer(id)
	local truck = ItemCatalog.GetTruck("Pickup")
	if not def or not truck then
		return nil
	end
	local lay = TruckLayout.ForTrailer(def, TruckLayout.For(truck))
	local model = Instance.new("Model")
	model.Name = id
	TruckArt.AddTrailer(model, def, lay)
	-- Nose (the hitch) toward -Z, centred on the pivot, same as a truck.
	model:PivotTo(CFrame.new(0, 0, -(lay.hitchZ + lay.length / 2)))
	prep(model, "Trailer", id)
	return model
end

-- The lot around the origin, front (-Z) toward the path. Place it with
-- Kit.placeAt. Returns the model; each vehicle is a child model.
function DealershipLot.Build(): Model
	local width, depth = DealershipLot.Size()
	local lot = Instance.new("Model")
	lot.Name = "DealershipLot"
	local spans: { number } = {}
	local lengths: { number } = {}
	local sum = 0
	for _, entry in ipairs(ORDER) do
		local span, length = measure(entry.kind, entry.id)
		table.insert(spans, span)
		table.insert(lengths, length)
		sum += span
	end
	local gap = (width - 2 * SIDE - sum) / math.max(1, #ORDER - 1)
	local bumper = -depth / 2 + FRONT
	local x = -width / 2 + SIDE
	for i, entry in ipairs(ORDER) do
		local model = if entry.kind == "Truck" then placeTruck(entry.id) else placeTrailer(entry.id)
		local length = lengths[i]
		local cx = x + spans[i] / 2
		if model then
			model.Parent = lot
			model:PivotTo(CFrame.new(cx, 0, bumper + length / 2))
			attachSign(model, priceOf(entry.kind, entry.id), length)
		end
		x += spans[i] + gap
	end
	return lot
end

return DealershipLot
