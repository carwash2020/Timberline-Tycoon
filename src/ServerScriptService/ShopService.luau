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

local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopHoursLogic = require(ReplicatedStorage.Shared.ShopHoursLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local StoreStock = require(ReplicatedStorage.Shared.StoreStock)
local Util = require(ReplicatedStorage.Shared.Util)
local AxeService = require(script.Parent.AxeService)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileSchema = require(script.Parent.ProfileSchema)
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

-- The hour shop doors use. Tests replace this. Production reads
-- WorldTime.Hour() through ShopHoursLogic.Now, so Studio's ClockOverride works.
function ShopService.Hour(): number
	return ShopHoursLogic.Now()
end

-- Shops for this category whose counter the player can reach, and whether
-- they are also at a display model (the dealership lot).
local function shopsInReach(player: Player, category: string): ({ string }, boolean)
	local names: { string } = {}
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return names, false
	end
	local reach = GameConfig.ShopRange + GameConfig.RangeTolerance
	local folder = map
	for _, shopName in ipairs(SHOP_FOR[category] or {}) do
		local shop = if folder then folder:FindFirstChild(shopName) else nil
		local counter = if shop then shop:FindFirstChild("Counter") else nil
		local point = if counter then counter:FindFirstChild("ShopPoint") else nil
		if point and point:IsA("Attachment") and (hrp.Position - point.WorldPosition).Magnitude <= reach then
			table.insert(names, shopName)
		end
	end
	return names, nearDisplay(hrp, category)
end

-- A sale is allowed when any in-range shop for the category is open. The
-- test map parks every ShopPoint on one spot, so a night axe still sells
-- at the Tool Shed while Hearth & Home, also "in range", is closed.
local function closedShop(player: Player, category: string, hour: number): string?
	local names, display = shopsInReach(player, category)
	local closedName: string? = nil
	local anyOpen = false
	for _, shopName in ipairs(names) do
		if ShopHoursLogic.IsOpen(shopName, hour) then
			anyOpen = true
		else
			closedName = shopName
		end
	end
	if display then
		if ShopHoursLogic.IsOpen("Dealership", hour) then
			anyOpen = true
		elseif closedName == nil then
			closedName = "Dealership"
		end
	end
	if anyOpen or (#names == 0 and not display) then
		return nil
	end
	return closedName or "HearthAndHome"
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

local function hasLand(profile: ProfileService.Profile): boolean
	local plot = (profile :: any).plot
	return type(plot) == "table" and plot.claimed == true
end

local NEEDS_PLOT = "You'll need a plot to open this."

-- Loop 2: a truck or trailer is a box you open on your plot. Cash does
-- not move until the plot check has passed. ownedTrucks stays as it was.
local function buyVehicleBox(
	player: Player,
	profile: ProfileService.Profile,
	itemId: string,
	displayName: string,
	price: number
): boolean
	if not hasLand(profile) then
		notify(player, NEEDS_PLOT)
		return false
	end
	local hour = ShopService.Hour()
	if not ShopHoursLogic.IsOpen("Dealership", hour) then
		notify(player, DialogueData.Sleepy("Dealership", hour))
		return false
	end
	local storage = (profile :: any).storage
	local stored = if type(storage) == "table" then #storage else 0
	if stored >= ProfileSchema.StorageCap then
		notify(player, "storage is full")
		return false
	end
	if profile.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - profile.cash), displayName)
		)
		return false
	end
	if not EconomyService.SpendCash(player, price, "bought " .. displayName, itemId) then
		return false
	end
	if type(storage) ~= "table" then
		storage = {}
		(profile :: any).storage = storage
	end
	table.insert(storage, { uid = Util.guid(), itemId = itemId, shop = "Dealership" })
	notify(player, string.format("Bought the %s! Open the box on your plot.", displayName))
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
	if loop == 2 then
		buyVehicleBox(player, profile, trailer.id, trailer.displayName, price)
		return
	end
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
	-- The Rustbucket stays an instant grant so the old loop still works.
	-- Every other loop-2 truck is a box.
	if loop == 2 and truck.id ~= "Rustbucket" then
		if buyVehicleBox(player, profile, truck.id, truck.displayName, price) then
			QuestService.Event(player, "truckBought")
			MilestoneService.Mark(player, "Bought a truck")
		end
		return
	end
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
-- spends the stock; with boxed shelves on, placing without one is refused).
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
	local shut = closedShop(player, category, ShopService.Hour())
	if shut then
		notify(player, DialogueData.Sleepy(shut, ShopService.Hour()))
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
	VehicleService.RestorePads(player, profile)
	if type((VehicleService :: any).AnnounceWaiting) == "function" then
		(VehicleService :: any).AnnounceWaiting(player, profile)
	end
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

-- A boxed purchase. The price, the owner and the stock are read here; the
-- client never supplies them. The uid is claimed before any cash moves, so
-- ten pays in one frame charge once. Nothing in this function yields, so
-- the limited shelf cannot sell its last unit twice.
export type BoxGrant = {
	uid: string,
	kind: string,
	itemId: string,
	limited: boolean?,
	shop: string?,
}

local settled: { [string]: string } = {}

function ShopService.Loop(): number
	return loop
end

function ShopService.ResetGrants()
	table.clear(settled)
end

local function listed(ids: any, itemId: string): boolean
	if type(ids) ~= "table" then
		return false
	end
	for _, id in ipairs(ids) do
		if id == itemId then
			return true
		end
	end
	return false
end

function ShopService.ChargeAndGrant(player: Player, box: BoxGrant, now: number?): (boolean, string, string?)
	local uid = box.uid
	if type(uid) ~= "string" or uid == "" then
		return false, "missing", nil
	end
	local state = settled[uid]
	if state == "granted" or state == "settling" then
		return false, "thanks", nil
	end
	settled[uid] = "settling"
	local function fail(line: string): (boolean, string, string?)
		settled[uid] = nil
		return false, line, nil
	end

	local profile = ProfileService.GetProfile(player)
	if not profile then
		return fail("missing")
	end
	local shopId = box.shop
	if type(shopId) ~= "string" or shopId == "" then
		local slot = StoreStock.Find(box.kind, box.itemId)
		shopId = if slot then slot.shop else nil
	end
	if (box.kind == "Truck" or box.kind == "Trailer") and (type(shopId) ~= "string" or shopId == "") then
		shopId = "Dealership"
	end
	if type(shopId) == "string" and not ShopHoursLogic.IsOpen(shopId, ShopService.Hour()) then
		return fail("sleepy")
	end
	local limited = box.limited == true or (box.kind == "Cosmetic" and box.itemId == "LampPost")
	local price = StoreStock.UnitPrice(box.kind, box.itemId, limited, loop)
	if price == nil then
		return fail("locked")
	end

	local axe: ItemCatalog.AxeDef? = nil
	if box.kind == "Axe" then
		axe = ItemCatalog.GetAxe(box.itemId)
		if not axe then
			return fail("locked")
		end
		local counts, total = AxeService.OwnedCounts(player)
		local rawTier = (profile :: any).bestAxeTier
		local best: number = if type(rawTier) == "number" then rawTier else 1
		local ownedCount = counts[axe.id]
		local have: number = if type(ownedCount) == "number" then ownedCount else 0
		local many: number = if type(total) == "number" then total else 0
		local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, best, have, many)
		if not ShopLogic.CanPurchase(status) then
			notify(player, ShopLogic.WhyNot(status, axe, best))
			return fail("locked")
		end
	elseif box.kind == "Gear" then
		local gear = ItemCatalog.GetGear(box.itemId)
		if not gear then
			return fail("locked")
		end
		if listed(profile.gear, gear.id) then
			return fail("alreadyOwned")
		end
		local owned: { [string]: boolean } = {}
		if type(profile.gear) == "table" then
			for _, id in ipairs(profile.gear) do
				owned[id] = true
			end
		end
		if ShopLogic.GearStatusOf(gear, owned) == "soon" then
			return fail("locked")
		end
	elseif box.kind == "Sawmill" then
		if loop ~= 2 or not ItemCatalog.GetSawmill(box.itemId) then
			return fail("locked")
		end
		if not hasLand(profile) then
			return fail("needsLand")
		end
	elseif box.kind == "Machine" then
		if loop ~= 2 or not ItemCatalog.GetMachine(box.itemId) then
			return fail("locked")
		end
		if not hasLand(profile) then
			return fail("needsLand")
		end
	elseif box.kind == "Blueprint" then
		local bp = PlotLogic.Blueprint(box.itemId)
		if not bp or bp.unlock ~= true then
			return fail("locked")
		end
		if not hasLand(profile) then
			return fail("needsLand")
		end
		local have = profile.furnitureBlueprints
		if type(have) == "table" and have[bp.id] == true then
			return fail("alreadyOwned")
		end
	elseif box.kind == "Truck" then
		local truck = ItemCatalog.GetTruck(box.itemId)
		if not truck or truck.id == "Rustbucket" or truck.sold == false or truck.robux == true then
			return fail("locked")
		end
		-- Plot check before any cash moves. Yes on the card still calls
		-- Pay, and Pay lands here without SpendCash.
		if not hasLand(profile) then
			return fail("needsPlot")
		end
	elseif box.kind == "Trailer" then
		if not ItemCatalog.GetTrailer(box.itemId) then
			return fail("locked")
		end
		if not hasLand(profile) then
			return fail("needsPlot")
		end
	elseif box.kind ~= "Cosmetic" then
		return fail("locked")
	end

	if profile.cash < price then
		return fail("broke")
	end

	local took = false
	if limited then
		local claimed, why = StoreStock.TryClaim(player.UserId, now or os.clock())
		if not claimed then
			return fail(if why == "alreadyOwned" then "alreadyOwned" else "missing")
		end
		took = true
	end
	if not EconomyService.SpendCash(player, price, "bought " .. box.itemId, box.itemId) then
		if took then
			StoreStock.Refund(player.UserId)
		end
		return fail("broke")
	end
	settled[uid] = "granted"

	local axeUid: string? = nil
	if box.kind == "Axe" and axe then
		local item, tool = AxeService.Grant(player, axe.id)
		axeUid = if item then item.uid else nil
		local char = player.Character
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if tool and humanoid then
			humanoid:EquipTool(tool)
		end
		notify(player, string.format("Bought the %s! It's in your hotbar.", axe.displayName))
		MilestoneService.Mark(player, "First upgrade bought")
		QuestService.Event(player, "axeBought")
		QuestService.RefreshNextGoal(player)
	elseif box.kind == "Gear" then
		local gear = ItemCatalog.GetGear(box.itemId)
		if gear then
			if type(profile.gear) ~= "table" then
				profile.gear = {}
			end
			table.insert(profile.gear, gear.id)
			publishGear(player, profile)
			notify(player, string.format("Bought the %s. It's yours for good.", gear.displayName))
		end
	elseif box.kind == "Sawmill" then
		local mill = ItemCatalog.GetSawmill(box.itemId)
		if mill then
			if type(profile.sawmillStock) ~= "table" then
				profile.sawmillStock = {}
			end
			table.insert(profile.sawmillStock, mill.id)
			publishStock(player, profile)
			notify(player, string.format("Bought a %s! Place it from BUILD on your plot.", mill.displayName))
		end
	elseif box.kind == "Machine" then
		local machine = ItemCatalog.GetMachine(box.itemId)
		if machine then
			-- The same stock list the sawmills wait in; BUILD places it.
			if type(profile.sawmillStock) ~= "table" then
				profile.sawmillStock = {}
			end
			table.insert(profile.sawmillStock, machine.id)
			publishStock(player, profile)
			notify(player, string.format("Bought a %s! Place it from BUILD on your plot.", machine.displayName))
		end
	elseif box.kind == "Blueprint" then
		local bp = PlotLogic.Blueprint(box.itemId)
		if bp then
			if type(profile.furnitureBlueprints) ~= "table" then
				profile.furnitureBlueprints = {}
			end
			profile.furnitureBlueprints[bp.id] = true
			publishBlueprints(player, profile)
			notify(player, string.format("Bought the %s blueprint. Place it from BUILD on your plot.", bp.displayName))
		end
	elseif box.kind == "Truck" or box.kind == "Trailer" then
		local named = if box.kind == "Truck"
			then ItemCatalog.GetTruck(box.itemId)
			else ItemCatalog.GetTrailer(box.itemId)
		local display = if named then named.displayName else box.itemId
		notify(player, string.format("Bought the %s. Open the box on your plot.", display))
		if box.kind == "Truck" then
			QuestService.Event(player, "truckBought")
			MilestoneService.Mark(player, "Bought a truck")
		end
	else
		local materials = (profile :: any).materials
		if type(materials) ~= "table" then
			materials = {}
			(profile :: any).materials = materials
		end
		materials[box.itemId] = (materials[box.itemId] or 0) + 1
		notify(player, string.format("Bought the %s.", StoreStock.DisplayName(box.kind, box.itemId)))
	end
	return true, "thanks", axeUid
end

return ShopService
