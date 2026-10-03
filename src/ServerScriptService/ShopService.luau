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

local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
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

-- Which shop buildings (models in TimberlineMap) sell each category.
-- Axes are at the Tool Shed and the General Store (Hearth & Home).
local SHOP_FOR: { [string]: { string } } = {
	Axe = { "ToolShed", "HearthAndHome" },
	Truck = { "Dealership" },
	Trailer = { "Dealership" },
	Gear = { "HearthAndHome" },
	Sawmill = { "ToolShed" },
	Blueprint = { "HearthAndHome" },
}

local map: Instance? = nil
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local loop = 1 -- the core loop that runs (Init)

local function shopPoints(category: string): { Vector3 }
	local out: { Vector3 } = {}
	local folder = map
	for _, shopName in ipairs(SHOP_FOR[category] or {}) do
		local shop = if folder then folder:FindFirstChild(shopName) else nil
		local counter = if shop then shop:FindFirstChild("Counter") else nil
		local point = if counter then counter:FindFirstChild("ShopPoint") else nil
		if point and point:IsA("Attachment") then
			table.insert(out, point.WorldPosition)
		end
	end
	return out
end

local function nearDisplay(hrp: BasePart, category: string): boolean
	if typeof(CollectionService.GetTagged) ~= "function" then
		return false
	end
	local reach = GameConfig.ShopRange + GameConfig.RangeTolerance
	for _, inst in ipairs(CollectionService:GetTagged("ShopDisplay")) do
		if inst:GetAttribute("Category") == category then
			local pos: Vector3? = nil
			if inst:IsA("Model") then
				pos = inst:GetPivot().Position
			elseif inst:IsA("BasePart") then
				pos = inst.Position
			end
			if pos and (hrp.Position - pos).Magnitude <= reach then
				return true
			end
		end
	end
	return false
end

local function inRange(player: Player, category: string): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return false
	end
	local reach = GameConfig.ShopRange + GameConfig.RangeTolerance
	for _, point in ipairs(shopPoints(category)) do
		if (hrp.Position - point).Magnitude <= reach then
			return true
		end
	end
	return nearDisplay(hrp, category)
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
	-- Owned check, charge, and grant happen with no yield between them, so a
	-- second Buy in the same burst cannot charge twice.
	if table.find(profile.ownedTrucks, truck.id) then
		notify(player, string.format("You already own the %s.", truck.displayName))
		return
	end
	if not ShopLogic.TruckForCash(truck) then
		notify(player, string.format("The %s is in the Store.", truck.displayName))
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
	if profile.equippedTruck == "" or not table.find(profile.ownedTrucks, profile.equippedTruck) then
		profile.equippedTruck = truck.id
	end
	publishTrucks(player, profile)
	player:SetAttribute("OwnsTruck", true)
	QuestService.Event(player, "truckBought")
	MilestoneService.Mark(player, "Bought a truck")
	if switchTo(player, profile, truck) then
		notify(player, string.format("Bought the %s! It's on its way to your plot.", truck.displayName))
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

local function publishBlueprints(player: Player, profile: ProfileService.Profile)
	local ids: { string } = {}
	local owned = profile.furnitureBlueprints
	if type(owned) == "table" then
		for id, on in pairs(owned) do
			if on == true then
				table.insert(ids, id)
			end
		end
	end
	player:SetAttribute("Blueprints", ShopLogic.EncodeSet(ids))
end

-- A blueprint is bought once. Placing copies on your plot is free after that.
local function buyBlueprint(player: Player, blueprintId: string)
	local profile = ProfileService.GetProfile(player)
	local bp = PlotLogic.Blueprint(blueprintId)
	if not profile or not bp or bp.unlock ~= true then
		return
	end
	if type(profile.furnitureBlueprints) ~= "table" then
		profile.furnitureBlueprints = {}
	end
	if profile.furnitureBlueprints[bp.id] == true then
		notify(player, string.format("You already own the %s blueprint.", bp.displayName))
		return
	end
	local price = PlotData.Price(bp)
	if profile.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - profile.cash), bp.displayName)
		)
		return
	end
	if not EconomyService.SpendCash(player, price, "bought " .. bp.displayName, bp.id) then
		return
	end
	profile.furnitureBlueprints[bp.id] = true
	publishBlueprints(player, profile)
	notify(player, string.format("Bought the %s blueprint. Place it from BUILD on your plot.", bp.displayName))
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
	elseif category == "Blueprint" then
		buyBlueprint(player, itemId)
	end
end

-- The Timber Classic pass: every slot, including a new game. Doesn't
-- replace a truck they're already driving. Completes the tutorial's truck
-- step when that step is the current one.
function ShopService.GrantPassTruck(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	SaveSlotLogic.GrantPassTrucks(profile)
	publishTrucks(player, profile)
	player:SetAttribute("OwnsTruck", #profile.ownedTrucks > 0)
	if VehicleService.GetVehicle(player) == nil and profile.equippedTruck ~= "" then
		VehicleService.SpawnTruck(player, profile.equippedTruck, nil, profile.equippedTrailer)
	end
	QuestService.Event(player, "truckBought")
end

-- Call once the player's save has loaded (after their truck spawned).
function ShopService.PlayerJoined(player: Player, profile: ProfileService.Profile)
	publishTrucks(player, profile)
	publishGear(player, profile)
	publishStock(player, profile)
	publishBlueprints(player, profile)
	player:SetAttribute("OwnsTruck", #profile.ownedTrucks > 0)
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
	-- Display models on the dealership lot carry their own BuyPrompt. The
	-- test map is a plain table with FindFirstChild only, so skip the scan
	-- when the folder can't walk its descendants.
	if typeof(mapFolder.GetDescendants) == "function" then
		for _, inst in ipairs(mapFolder:GetDescendants()) do
			if inst:IsA("ProximityPrompt") and inst.Name == "BuyPrompt" then
				inst.Triggered:Connect(function(player: Player)
					local node: Instance? = inst
					local category: string? = nil
					local itemId: string? = nil
					while node do
						if node:IsA("Model") then
							local cat = node:GetAttribute("Category")
							local id = node:GetAttribute("ItemId")
							if type(cat) == "string" and type(id) == "string" then
								category, itemId = cat, id
								break
							end
						end
						node = node.Parent
					end
					if category and itemId then
						onBuyItem(player, category, itemId)
					end
				end)
			end
		end
	end
end

return ShopService
