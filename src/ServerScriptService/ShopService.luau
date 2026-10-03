--!strict
-- ShopService: the BuyItem and EquipItem remotes. The Tool Shed sells
-- axes, and (v2) sawmills into stock you place on your plot. The
-- Dealership sells trucks and swaps between the ones you own. Hearth &
-- Home sells biome gear (once each, yours for good).
--
-- Every purchase is checked here, whatever the client showed:
--   * the player stands within GameConfig.ShopRange (+ tolerance) of that
--     shop's counter,
--   * ShopLogic allows it (axes: sold in order, forged axes never, at most
--     GameConfig.MaxOwnedAxes; trucks: not owned yet),
--   * EconomyService.SpendCash succeeds (it refuses if cash is short).
-- A bought axe goes straight into the player's hand (AxeService.Grant); a
-- bought truck replaces the current one in their parking slot
-- (VehicleService.Equip). The result comes back as a toast. The
-- OwnedTrucks and EquippedTruck player attributes feed the shop screen.
-- Axes, trucks and trailers cost ShopLogic.Price(item, loop): their v2
-- prices under the v2 core loop (GameServer passes CoreLoop.Active() to
-- Init), priceCash under v1. Gear has one price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local AxeService = require(script.Parent.AxeService)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local VehicleService = require(script.Parent.VehicleService)

local ShopService = {}

-- Which shop building (a model in TimberlineMap) sells each category.
local SHOP_FOR: { [string]: string } = {
	Axe = "ToolShed",
	Truck = "Dealership",
	Trailer = "Dealership",
	Gear = "HearthAndHome",
	Sawmill = "ToolShed",
}

local map: Instance? = nil
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local loop = 1 -- the core loop that runs (Init)

local function shopPoint(category: string): Vector3?
	local shopName = SHOP_FOR[category]
	local shop = if shopName and map then map:FindFirstChild(shopName) else nil
	local counter = if shop then shop:FindFirstChild("Counter") else nil
	local point = if counter then counter:FindFirstChild("ShopPoint") else nil
	return if point and point:IsA("Attachment") then point.WorldPosition else nil
end

local function inRange(player: Player, category: string): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local point = shopPoint(category)
	return hrp ~= nil
		and point ~= nil
		and (hrp.Position - point).Magnitude <= GameConfig.ShopRange + GameConfig.RangeTolerance
end

local function buyAxe(player: Player, axeId: string)
	local profile = ProfileService.GetProfile(player)
	local axe = ItemCatalog.GetAxe(axeId)
	if not profile or not axe then
		return
	end
	local counts, total = AxeService.OwnedCounts(player)
	local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, profile.bestAxeTier, counts[axe.id] or 0, total)
	if not ShopLogic.CanPurchase(status) then
		notify(player, ShopLogic.WhyNot(status, axe, profile.bestAxeTier))
		return
	end
	local price = ShopLogic.Price(axe, loop)
	if profile.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - profile.cash), axe.displayName)
		)
		return
	end
	-- Nothing below yields, so the checks above still hold.
	if not EconomyService.SpendCash(player, price, "bought " .. axe.displayName, axe.id) then
		return
	end
	local _item, tool = AxeService.Grant(player, axe.id)
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if tool and humanoid then
		humanoid:EquipTool(tool)
	end
	notify(player, string.format("Bought the %s! It's in your hotbar.", axe.displayName))
	MilestoneService.Mark(player, "First upgrade bought")
	QuestService.Event(player, "axeBought")
	QuestService.RefreshNextGoal(player)
end

local function publishGear(player: Player, profile: ProfileService.Profile)
	player:SetAttribute("OwnedGear", ShopLogic.EncodeSet(profile.gear))
end

local function buyGear(player: Player, gearId: string)
	local profile = ProfileService.GetProfile(player)
	local gear = ItemCatalog.GetGear(gearId)
	if not profile or not gear then
		return
	end
	local owned: { [string]: boolean } = {}
	for _, id in ipairs(profile.gear) do
		owned[id] = true
	end
	local status: ShopLogic.GearStatus = ShopLogic.GearStatusOf(gear, owned)
	if status == "owned" then
		notify(player, string.format("You already have the %s.", gear.displayName))
		return
	elseif status == "soon" then
		notify(player, string.format("The %s isn't for sale yet: its biome is coming soon.", gear.displayName))
		return
	end
	if profile.cash < gear.priceCash then
		notify(
			player,
			string.format(
				"You need %s more for the %s.",
				Util.formatCash(gear.priceCash - profile.cash),
				gear.displayName
			)
		)
		return
	end
	if not EconomyService.SpendCash(player, gear.priceCash, "bought " .. gear.displayName, gear.id) then
		return
	end
	table.insert(profile.gear, gear.id)
	publishGear(player, profile)
	notify(player, string.format("Bought the %s! You're wearing it from now on.", gear.displayName))
end

local function publishTrucks(player: Player, profile: ProfileService.Profile)
	player:SetAttribute("OwnedTrucks", ShopLogic.EncodeSet(profile.ownedTrucks))
	player:SetAttribute("EquippedTruck", profile.equippedTruck)
	player:SetAttribute("OwnedTrailers", ShopLogic.EncodeSet(profile.ownedTrailers))
	player:SetAttribute("HitchedTrailer", profile.equippedTrailer)
end

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	return set
end

-- Rebuilds the rig with `trailerId` hitched ("" = none); says why not.
local function hitch(player: Player, profile: ProfileService.Profile, trailerId: string): boolean
	local ok, why = VehicleService.Equip(player, profile.equippedTruck, trailerId)
	if not ok then
		if why then
			notify(player, why)
		end
		return false
	end
	profile.equippedTrailer = trailerId
	publishTrucks(player, profile)
	return true
end

local function buyTrailer(player: Player, trailerId: string)
	local profile = ProfileService.GetProfile(player)
	local trailer = ItemCatalog.GetTrailer(trailerId)
	if not profile or not trailer then
		return
	end
	local status: ShopLogic.TrailerStatus =
		ShopLogic.TrailerStatusOf(trailer, toSet(profile.ownedTrailers), profile.equippedTrailer)
	if status ~= "buy" then
		notify(player, string.format("You already own the %s.", trailer.displayName))
		return
	end
	local price = ShopLogic.Price(trailer, loop)
	if profile.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - profile.cash), trailer.displayName)
		)
		return
	end
	if not EconomyService.SpendCash(player, price, "bought " .. trailer.displayName, trailer.id) then
		return
	end
	table.insert(profile.ownedTrailers, trailer.id)
	publishTrucks(player, profile)
	-- A truck without a bed (the Scout ATV) can't tow: keep it unhitched.
	local truck = ItemCatalog.GetTruck(profile.equippedTruck)
	if truck and truck.bedCapacity <= 0 then
		notify(
			player,
			string.format(
				"Bought the %s! The %s can't tow, so hitch it here once you drive a truck with a bed.",
				trailer.displayName,
				truck.displayName
			)
		)
	elseif hitch(player, profile, trailer.id) then
		notify(player, string.format("Bought the %s! It's hitched to your truck.", trailer.displayName))
	else
		notify(player, string.format("Bought the %s! Hitch it here when you're ready.", trailer.displayName))
	end
end

local function ownedTruckSet(profile: ProfileService.Profile): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in ipairs(profile.ownedTrucks) do
		set[id] = true
	end
	return set
end

-- Switches to an owned truck (keeping the hitched trailer); says why not
-- when it can't.
local function switchTo(player: Player, profile: ProfileService.Profile, truck: ItemCatalog.TruckDef): boolean
	local ok, why = VehicleService.Equip(player, truck.id, profile.equippedTrailer)
	if not ok then
		if why then
			notify(player, why)
		end
		return false
	end
	profile.equippedTruck = truck.id
	publishTrucks(player, profile)
	return true
end

local function buyTruck(player: Player, truckId: string)
	local profile = ProfileService.GetProfile(player)
	local truck = ItemCatalog.GetTruck(truckId)
	if not profile or not truck then
		return
	end
	local status: ShopLogic.TruckStatus = ShopLogic.TruckStatusOf(truck, ownedTruckSet(profile), profile.equippedTruck)
	if status ~= "buy" then
		notify(player, string.format("You already own the %s.", truck.displayName))
		return
	end
	local price = ShopLogic.Price(truck, loop)
	if profile.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - profile.cash), truck.displayName)
		)
		return
	end
	if not EconomyService.SpendCash(player, price, "bought " .. truck.displayName, truck.id) then
		return
	end
	table.insert(profile.ownedTrucks, truck.id)
	publishTrucks(player, profile)
	if switchTo(player, profile, truck) then
		notify(player, string.format("Bought the %s! It's waiting in your parking spot.", truck.displayName))
	else
		notify(player, string.format("Bought the %s! Switch to it here when you're ready.", truck.displayName))
	end
end

-- A second press on the hitched trailer unhitches it.
local function toggleTrailer(player: Player, profile: ProfileService.Profile, trailerId: string)
	local trailer = ItemCatalog.GetTrailer(trailerId)
	if not trailer then
		return
	end
	local status: ShopLogic.TrailerStatus =
		ShopLogic.TrailerStatusOf(trailer, toSet(profile.ownedTrailers), profile.equippedTrailer)
	local truck = ItemCatalog.GetTruck(profile.equippedTruck)
	if status == "hitched" then
		if hitch(player, profile, "") then
			notify(player, string.format("Unhitched the %s.", trailer.displayName))
		end
	elseif status == "hitch" then
		if truck and truck.bedCapacity <= 0 then
			notify(player, string.format("The %s can't tow a trailer.", truck.displayName))
		elseif hitch(player, profile, trailer.id) then
			notify(player, string.format("The %s is hitched to your truck.", trailer.displayName))
		end
	end
end

local function onEquipItem(player: Player, category: unknown, itemId: unknown)
	if
		(category ~= "Truck" and category ~= "Trailer")
		or type(itemId) ~= "string"
		or not RateLimiter.Allow(player, "EquipItem")
	then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	if not inRange(player, "Truck") then
		notify(player, "Walk up to the Dealership counter to switch trucks.")
		return
	end
	if category == "Trailer" then
		toggleTrailer(player, profile, itemId)
		return
	end
	local truck = ItemCatalog.GetTruck(itemId)
	if not truck then
		return
	end
	local status: ShopLogic.TruckStatus = ShopLogic.TruckStatusOf(truck, ownedTruckSet(profile), profile.equippedTruck)
	if status == "use" and switchTo(player, profile, truck) then
		notify(player, string.format("Your %s is waiting in your parking spot.", truck.displayName))
	end
end

local function publishStock(player: Player, profile: ProfileService.Profile)
	local stock = profile.sawmillStock
	if type(stock) ~= "table" then
		stock = {}
		profile.sawmillStock = stock
	end
	player:SetAttribute("SawmillStock", SawmillLogic.EncodeStock(stock))
end

-- A sawmill goes into stock. You place it from BUILD on your plot (that
-- spends the stock; placing without one charges the price there instead).
local function buySawmill(player: Player, millId: string)
	if loop ~= 2 then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local mill = ItemCatalog.GetSawmill(millId)
	if not profile or not mill then
		return
	end
	if profile.cash < mill.priceCash then
		notify(
			player,
			string.format(
				"You need %s more for the %s.",
				Util.formatCash(mill.priceCash - profile.cash),
				mill.displayName
			)
		)
		return
	end
	if not EconomyService.SpendCash(player, mill.priceCash, "bought " .. mill.displayName, mill.id) then
		return
	end
	if type(profile.sawmillStock) ~= "table" then
		profile.sawmillStock = {}
	end
	table.insert(profile.sawmillStock, mill.id)
	publishStock(player, profile)
	notify(player, string.format("Bought a %s! Place it from BUILD on your plot.", mill.displayName))
end

local function onBuyItem(player: Player, category: unknown, itemId: unknown)
	if type(category) ~= "string" or type(itemId) ~= "string" or not RateLimiter.Allow(player, "BuyItem") then
		return
	end
	if not SHOP_FOR[category] then
		return
	end
	if not inRange(player, category) then
		notify(player, "Walk up to the counter to buy.")
		return
	end
	if category == "Axe" then
		buyAxe(player, itemId)
	elseif category == "Truck" then
		buyTruck(player, itemId)
	elseif category == "Trailer" then
		buyTrailer(player, itemId)
	elseif category == "Gear" then
		buyGear(player, itemId)
	elseif category == "Sawmill" then
		buySawmill(player, itemId)
	end
end

-- Call once the player's save has loaded (after their truck spawned).
function ShopService.PlayerJoined(player: Player, profile: ProfileService.Profile)
	publishTrucks(player, profile)
	publishGear(player, profile)
	publishStock(player, profile)
end

-- `mapFolder` is TimberlineMap; `notifyFn` shows a toast (GameServer's
-- notify); `activeLoop` is the core loop that runs (CoreLoop.Active(); 1
-- when not given).
function ShopService.Init(
	mapFolder: Instance,
	buyRemote: RemoteEvent,
	equipRemote: RemoteEvent,
	notifyFn: (Player, string) -> (),
	activeLoop: number?
)
	map = mapFolder
	notify = notifyFn
	loop = if activeLoop == 2 then 2 else 1
	buyRemote.OnServerEvent:Connect(onBuyItem)
	equipRemote.OnServerEvent:Connect(onEquipItem)
end

return ShopService
