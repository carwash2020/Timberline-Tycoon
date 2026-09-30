--!strict
-- ShopService: the BuyItem remote. Phase 2 sells axes at the Tool Shed;
-- trucks at the Dealership come with Phase 4.
--
-- Every purchase is checked here, whatever the client showed:
--   * the player stands within GameConfig.ShopRange (+ tolerance) of the
--     shop's counter,
--   * ShopLogic.StatusOf allows it (axes are sold in order, forged axes
--     never, and at most GameConfig.MaxOwnedAxes),
--   * EconomyService.SpendCash succeeds (it refuses if cash is short).
-- Then AxeService.Grant adds the axe and it goes straight into the
-- player's hand. The result comes back as a toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local AxeService = require(script.Parent.AxeService)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)

local ShopService = {}

-- Which shop building (a model in TimberlineMap) sells each category.
local SHOP_FOR: { [string]: string } = {
	Axe = "ToolShed",
}

local map: Instance? = nil
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

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
	if profile.cash < axe.priceCash then
		notify(
			player,
			string.format(
				"You need %s more for the %s.",
				Util.formatCash(axe.priceCash - profile.cash),
				axe.displayName
			)
		)
		return
	end
	-- Nothing below yields, so the checks above still hold.
	if not EconomyService.SpendCash(player, axe.priceCash, "bought " .. axe.displayName, axe.id) then
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
	end
end

-- `mapFolder` is TimberlineMap; `notifyFn` shows a toast (GameServer's notify).
function ShopService.Init(mapFolder: Instance, buyRemote: RemoteEvent, notifyFn: (Player, string) -> ())
	map = mapFolder
	notify = notifyFn
	buyRemote.OnServerEvent:Connect(onBuyItem)
end

return ShopService
