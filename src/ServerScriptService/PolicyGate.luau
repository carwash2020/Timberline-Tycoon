--!strict
-- PolicyGate: PolicyService:GetPolicyInfoForPlayerAsync, once per player.
-- The answer is cached for the visit (a player's region does not change
-- mid-session), fetched in the background at join so nothing waits, and
-- mirrored on the Player as attributes for the client's store. A failed
-- or missing answer is the strict policy (Shared/PolicyLogic) and is
-- tried again later, up to MaxTries, so a hiccup does not lock a player
-- out of the strict default for the whole visit. Pure rules: PolicyLogic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PolicyLogic = require(ReplicatedStorage.Shared.PolicyLogic)

local PolicyGate = {}

local MAX_TRIES = 3
local RETRY_SECONDS = 5

local cache: { [Player]: PolicyLogic.Policy } = {}
local inflight: { [Player]: boolean } = {}
local tries: { [Player]: number } = {}

local function service(): any?
	local ok, found = pcall(function()
		return game:GetService("PolicyService")
	end)
	if ok and (typeof(found) == "Instance" or type(found) == "table") then
		return found
	end
	return nil
end

local function publish(player: Player, policy: PolicyLogic.Policy)
	local ok = pcall(function()
		player:SetAttribute(PolicyLogic.Attr.known, policy.known)
		player:SetAttribute(PolicyLogic.Attr.paidRandomRestricted, policy.paidRandomRestricted)
		player:SetAttribute(PolicyLogic.Attr.tradingAllowed, policy.tradingAllowed)
	end)
	if not ok then
		warn("[PolicyGate] could not publish the policy")
	end
end

-- Asks Roblox now (yields). Caches and publishes a good answer; a failure
-- leaves the strict default in place and returns false.
function PolicyGate.Fetch(player: Player): boolean
	local svc = service()
	if svc == nil or type(svc.GetPolicyInfoForPlayerAsync) ~= "function" then
		return false
	end
	local ok, info = pcall(function()
		return svc:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then
		warn("[PolicyGate] policy lookup failed: " .. tostring(info))
		return false
	end
	local policy = PolicyLogic.Normalize(info)
	cache[player] = policy
	publish(player, policy)
	return true
end

-- The player's policy, never yielding: the cached answer, else the strict
-- default (and a background fetch is started).
function PolicyGate.Of(player: Player): PolicyLogic.Policy
	local cached = cache[player]
	if cached then
		return cached
	end
	PolicyGate.Warm(player)
	return PolicyLogic.Strict()
end

-- Starts a background fetch with a few retries. Safe to call again.
function PolicyGate.Warm(player: Player)
	if cache[player] or inflight[player] then
		return
	end
	inflight[player] = true
	task.spawn(function()
		while cache[player] == nil and (tries[player] or 0) < MAX_TRIES and player.Parent == Players do
			tries[player] = (tries[player] or 0) + 1
			if PolicyGate.Fetch(player) then
				break
			end
			task.wait(RETRY_SECONDS)
		end
		inflight[player] = nil
	end)
end

-- For a purchase: the policy, waiting for the first answer if the join
-- fetch has not finished. Still strict when Roblox cannot answer.
function PolicyGate.Ensure(player: Player): PolicyLogic.Policy
	if cache[player] == nil then
		tries[player] = (tries[player] or 0) + 1
		PolicyGate.Fetch(player)
	end
	return cache[player] or PolicyLogic.Strict()
end

-- Whether `item` (a StoreData pass or product) may be offered to or bought
-- by `player`.
function PolicyGate.Allows(player: Player, item: { [string]: any }): boolean
	if item.paidRandom ~= true and item.tradable ~= true then
		return true -- nothing in it is policy-restricted: no lookup needed
	end
	return PolicyLogic.Allows(PolicyGate.Ensure(player), item)
end

function PolicyGate.PlayerRemoving(player: Player)
	cache[player] = nil
	inflight[player] = nil
	tries[player] = nil
end

local bound = false

function PolicyGate.Init()
	if bound then
		return
	end
	bound = true
	Players.PlayerAdded:Connect(PolicyGate.Warm)
	Players.PlayerRemoving:Connect(PolicyGate.PlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		PolicyGate.Warm(player)
	end
end

return PolicyGate
