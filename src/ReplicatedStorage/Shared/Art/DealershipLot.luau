--!strict
-- The dealership's open display lot: every truck in one row facing the
-- street (-Z), every trailer unhitched in a row behind. Each model is
-- anchored, has no scripts, streams Atomic, and carries a price sign and
-- a buy prompt. MapBuilder places the model; ShopService buys from the
-- ShopDisplay tag.

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

local GAP = 6
local MARGIN = 4
local DEPTH = 56 -- fits the lawn north of the plot road
-- Trailers sit unhitched behind the three shorter trucks. The Flatbed and
-- the Logging Rig are too long to leave a trailer behind them in that depth,
-- so the long trailer goes behind the Scout and the short one behind the Pickup.
local TRUCKS = { "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }
local BEHIND = {
	Rustbucket = "RanchTrailer",
	Pickup = "PonyTrailer",
	ScoutATV = "HeavyHauler",
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

local function bayWidth(id: string): number
	if id == "Flatbed" then
		return 15
	elseif id == "LoggingRig" then
		return 16
	end
	return 14.25
end

local function truckLength(id: string): number
	local def = ItemCatalog.GetTruck(id)
	return if def then TruckLayout.For(def).length else 20
end

local function trailerLayout(id: string): TruckLayout.TrailerLayout?
	local trailer = ItemCatalog.GetTrailer(id)
	local truck = ItemCatalog.GetTruck("Pickup")
	if not trailer or not truck then
		return nil
	end
	return TruckLayout.ForTrailer(trailer, TruckLayout.For(truck))
end

local function trailerLength(id: string): number
	local lay = trailerLayout(id)
	return if lay then lay.length else 20
end

-- Width and depth of the open lot, in studs. About 106 x 56: one row of
-- trucks facing the road, trailers unhitched behind the shorter ones.
function DealershipLot.Size(): (number, number)
	local width = MARGIN
	for i, id in ipairs(TRUCKS) do
		width += bayWidth(id)
		if i < #TRUCKS then
			width += GAP
		end
	end
	width += MARGIN
	return math.max(100, width), DEPTH
end

local function prep(model: Model, category: string, id: string, priceText: string, frontZ: number)
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
	local sign = Kit.part(
		model,
		"PriceSign",
		Vector3.new(4.5, 2.4, 0.3),
		CFrame.new(0, 3.2, frontZ - 3),
		Color3.fromRGB(62, 42, 24),
		Enum.Material.Wood
	)
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

local function placeTruck(id: string): Model?
	local def = ItemCatalog.GetTruck(id)
	if not def then
		return nil
	end
	local model = TruckArt.Build(def)
	local price = ShopLogic.Price(def, priceLoop())
	prep(model, "Truck", id, def.displayName .. "\n" .. Util.formatCash(price), -TruckLayout.For(def).length / 2)
	return model
end

local function placeTrailer(id: string): Model?
	local def = ItemCatalog.GetTrailer(id)
	local lay = trailerLayout(id)
	if not def or not lay then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	TruckArt.AddTrailer(model, def, lay)
	local centerZ = lay.hitchZ + lay.length / 2
	model:PivotTo(CFrame.new(0, 0, -centerZ))
	local price = ShopLogic.Price(def, priceLoop())
	prep(model, "Trailer", id, def.displayName .. "\n" .. Util.formatCash(price), -lay.length / 2)
	return model
end

-- The lot around the origin, front (-Z) toward the street. Place it with
-- Kit.placeAt. Returns the model; each vehicle is a child model.
function DealershipLot.Build(): Model
	local width, depth = DealershipLot.Size()
	local lot = Instance.new("Model")
	lot.Name = "DealershipLot"
	local front = -depth / 2 + MARGIN
	local x = -width / 2 + MARGIN
	local spot: { [string]: { x: number, length: number } } = {}
	for _, id in ipairs(TRUCKS) do
		local bay = bayWidth(id)
		local model = placeTruck(id)
		local length = truckLength(id)
		local cx = x + bay / 2
		if model then
			model.Parent = lot
			model:PivotTo(CFrame.new(cx, 0, front + length / 2))
		end
		spot[id] = { x = cx, length = length }
		x += bay + GAP
	end
	for _, id in ipairs(TRUCKS) do
		local trailerId = BEHIND[id]
		local here = spot[id]
		if trailerId and here then
			local model = placeTrailer(trailerId)
			if model then
				model.Parent = lot
				local length = trailerLength(trailerId)
				model:PivotTo(CFrame.new(here.x, 0, front + here.length + 4 + length / 2))
			end
		end
	end
	return lot
end

return DealershipLot
