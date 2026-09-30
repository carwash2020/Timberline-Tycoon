--!strict
-- EconomyService: the SOLE writer of profile.cash.
-- Every cash change goes through AddCash/SpendCash with a reason string.
-- Fires CashChanged to the client, mirrors cash on a player attribute, and
-- logs a Roblox economy analytics event (Creator Hub -> Analytics -> Economy).

local AnalyticsService = game:GetService("AnalyticsService")

local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

local cashChangedEvent: RemoteEvent? = nil

function EconomyService.Init(remotes: Folder)
	local ev = remotes:WaitForChild("CashChanged")
	assert(ev:IsA("RemoteEvent"), "[EconomyService] CashChanged remote missing")
	cashChangedEvent = ev
end

local function publish(player: Player, cash: number)
	player:SetAttribute("Cash", cash)
	if cashChangedEvent then
		cashChangedEvent:FireClient(player, cash)
	end
end

-- Analytics must never break gameplay, so failures only warn.
local function logEconomy(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	amount: number,
	balance: number,
	transaction: Enum.AnalyticsEconomyTransactionType,
	itemSku: string?
)
	local ok, err = pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, "Cash", amount, balance, transaction.Name, itemSku)
	end)
	if not ok then
		warn("[EconomyService] Analytics economy event failed: " .. tostring(err))
	end
end

function EconomyService.GetCash(player: Player): number
	local profile = ProfileService.GetProfile(player)
	return if profile then profile.cash else 0
end

-- `itemSku` names what earned the cash for analytics (e.g. "logs").
function EconomyService.AddCash(player: Player, amount: number, reason: string, itemSku: string?): number
	amount = math.floor(amount)
	if amount <= 0 then
		return 0
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return 0
	end
	profile.cash += amount
	profile.totalEarned += amount
	publish(player, profile.cash)
	logEconomy(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		amount,
		profile.cash,
		Enum.AnalyticsEconomyTransactionType.Gameplay,
		itemSku
	)
	print(string.format("[Economy] +%d to %s (%s)", amount, player.Name, reason))
	return amount
end

-- `itemSku` names what was bought for analytics (e.g. "SteelAxe").
function EconomyService.SpendCash(player: Player, amount: number, reason: string, itemSku: string?): boolean
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or profile.cash < amount then
		return false
	end
	profile.cash -= amount
	publish(player, profile.cash)
	logEconomy(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		amount,
		profile.cash,
		Enum.AnalyticsEconomyTransactionType.Shop,
		itemSku
	)
	print(string.format("[Economy] -%d from %s (%s)", amount, player.Name, reason))
	return true
end

return EconomyService
