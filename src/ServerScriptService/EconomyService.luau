--!strict
-- EconomyService: the SOLE writer of profile.cash.
-- Every cash change goes through AddCash/SpendCash with a reason string.
-- Fires CashChanged to the client and mirrors cash on a player attribute.

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

function EconomyService.GetCash(player: Player): number
	local profile = ProfileService.GetProfile(player)
	return if profile then profile.cash else 0
end

function EconomyService.AddCash(player: Player, amount: number, reason: string): number
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
	print(string.format("[Economy] +%d to %s (%s)", amount, player.Name, reason))
	return amount
end

function EconomyService.SpendCash(player: Player, amount: number, reason: string): boolean
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
	print(string.format("[Economy] -%d from %s (%s)", amount, player.Name, reason))
	return true
end

return EconomyService
