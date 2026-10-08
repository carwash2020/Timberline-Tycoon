--!strict
-- EconomyService: the SOLE writer of profile.cash.
-- Every cash change goes through AddCash/SpendCash with a reason string.
-- A wallet holds at most GameConfig.CashCap; AddCash reports what didn't fit.
-- Fires CashChanged to the client, mirrors cash on a player attribute, and
-- logs a Roblox economy analytics event (Creator Hub -> Analytics -> Economy).

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
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

-- Adds cash up to the wallet cap. Returns (credited, overflow): overflow is
-- what didn't fit, so the caller can tell the player.
-- `itemSku` names what earned the cash for analytics (e.g. "logs");
-- `transaction` defaults to Gameplay (IAP for Robux cash packs).
function EconomyService.AddCash(
	player: Player,
	amount: number,
	reason: string,
	itemSku: string?,
	transaction: Enum.AnalyticsEconomyTransactionType?
): (number, number)
	amount = math.floor(amount)
	if amount <= 0 then
		return 0, 0
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return 0, 0
	end
	local credited = math.clamp(GameConfig.CashCap - profile.cash, 0, amount)
	local overflow = amount - credited
	if overflow > 0 then
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "CashOverCap", overflow)
		end)
	end
	if credited <= 0 then
		return 0, overflow
	end
	profile.cash += credited
	profile.totalEarned += credited
	publish(player, profile.cash)
	logEconomy(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		credited,
		profile.cash,
		transaction or Enum.AnalyticsEconomyTransactionType.Gameplay,
		itemSku
	)
	print(string.format("[Economy] +%d to %s (%s)", credited, player.Name, reason))
	return credited, overflow
end

-- Gives back cash the player spent (a placed item picked up or sold back):
-- up to the wallet cap, and not counted in totalEarned. Returns (credited,
-- overflow) like AddCash.
function EconomyService.Refund(player: Player, amount: number, reason: string, itemSku: string?): (number, number)
	amount = math.floor(amount)
	local profile = ProfileService.GetProfile(player)
	if amount <= 0 or not profile then
		return 0, 0
	end
	local credited = math.clamp(GameConfig.CashCap - profile.cash, 0, amount)
	if credited > 0 then
		profile.cash += credited
		publish(player, profile.cash)
		logEconomy(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			credited,
			profile.cash,
			Enum.AnalyticsEconomyTransactionType.Shop,
			itemSku
		)
		print(string.format("[Economy] +%d refund to %s (%s)", credited, player.Name, reason))
	end
	return credited, amount - credited
end

-- Adds cash the player paid real money for (a Robux cash pack). What
-- doesn't fit under the wallet cap is banked (profile.pendingCash) and paid
-- out as spending frees up room, because a granted receipt can't be undone.
-- Returns (credited now, banked).
function EconomyService.AddPaidCash(player: Player, amount: number, reason: string, itemSku: string?): (number, number)
	return EconomyService.AddOwedCash(player, amount, reason, itemSku, Enum.AnalyticsEconomyTransactionType.IAP)
end

-- Adds cash the game owes the player and mustn't lose to the wallet cap
-- (the v2 buy-back of logs they had on hand, AddPaidCash's Robux cash):
-- what doesn't fit is banked like AddPaidCash's. Returns (credited now,
-- banked).
function EconomyService.AddOwedCash(
	player: Player,
	amount: number,
	reason: string,
	itemSku: string?,
	transaction: Enum.AnalyticsEconomyTransactionType?
): (number, number)
	local credited, overflow = EconomyService.AddCash(player, amount, reason, itemSku, transaction)
	local profile = ProfileService.GetProfile(player)
	if overflow > 0 and profile then
		profile.pendingCash += overflow
		player:SetAttribute("PendingCash", profile.pendingCash)
	end
	return credited, overflow
end

-- Sets the wallet to `amount` (a save-slot load or reset). Not an earn and
-- not a spend: the dollars were already in that slot. Clamped, then mirrored
-- to the client. No economy analytics event, so changing slots doesn't look
-- like cash appearing from nowhere.
function EconomyService.ReplaceCash(player: Player, amount: number, reason: string)
	amount = math.floor(amount)
	if amount ~= amount then
		amount = 0
	end
	amount = math.clamp(amount, 0, GameConfig.CashCap)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	profile.cash = amount
	publish(player, profile.cash)
	print(string.format("[Economy] %s wallet set to %d (%s)", player.Name, amount, reason))
end

-- Moves banked cash (AddPaidCash) into the wallet while there's room.
-- SpendCash calls it; GameServer calls it when a save loads.
function EconomyService.PayPending(player: Player)
	local profile = ProfileService.GetProfile(player)
	if profile == nil then
		return
	end
	local pending = profile.pendingCash or 0
	if pending <= 0 then
		return
	end
	local room = GameConfig.CashCap - profile.cash
	local move = math.min(room, pending)
	if move > 0 then
		profile.pendingCash = pending - move
		profile.cash += move
		publish(player, profile.cash)
		player:SetAttribute("PendingCash", profile.pendingCash)
		print(string.format("[Economy] +%d banked cash to %s", move, player.Name))
	end
end

-- `itemSku` names what was bought for analytics (e.g. "SteelAxe").
function EconomyService.SpendCash(player: Player, amount: number, reason: string, itemSku: string?): boolean
	if amount ~= amount then
		return false
	end
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
	EconomyService.PayPending(player)
	return true
end

return EconomyService
