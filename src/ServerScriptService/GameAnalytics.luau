--!strict
-- GameAnalytics: the one server wrapper around Roblox's AnalyticsService.
--   * Every call is in a pcall: analytics never throws into gameplay, a
--     failure only warns.
--   * A funnel step goes out once per player ever: its name is remembered in
--     the save's onboarding table (account-wide), marked BEFORE the call so a
--     failing service never sends it twice.
--   * Event names and fields come from Shared/AnalyticsEvents, which sends no
--     player names, ids or free text.
-- The service is read at call time, so a spec can swap it (services mock).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsEvents = require(ReplicatedStorage.Shared.AnalyticsEvents)

local GameAnalytics = {}

local function service(): any
	return game:GetService("AnalyticsService")
end

local function guarded(label: string, fn: () -> ()): boolean
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn("[GameAnalytics] " .. label .. " failed: " .. tostring(err))
	end
	return ok
end

-- Onboarding funnel step `step` (its number in the funnel) called `name`.
-- `onboarding` is the save's flag table. True when it was sent now; false for
-- a step already sent in an earlier session (or this one) or a bad call.
function GameAnalytics.FunnelStep(
	player: Player,
	onboarding: { [string]: boolean },
	step: number,
	name: string
): boolean
	if
		type(name) ~= "string"
		or name == ""
		or type(step) ~= "number"
		or step ~= step
		or step % 1 ~= 0
		or onboarding[name]
	then
		return false
	end
	onboarding[name] = true
	guarded("funnel step " .. name, function()
		service():LogOnboardingFunnelStepEvent(player, step, name)
	end)
	return true
end

-- One of AnalyticsEvents.Custom, with the store item key if there is one.
function GameAnalytics.Store(player: Player, eventName: string, item: string?): boolean
	local name, value, fields = AnalyticsEvents.CustomEvent(eventName, item)
	if name == nil then
		return false
	end
	return guarded(name, function()
		if fields then
			service():LogCustomEvent(player, name, value, fields)
		else
			service():LogCustomEvent(player, name, value)
		end
	end)
end

-- One cash event: `flow` Source or Sink, `transaction` the Roblox transaction
-- type (its Name is sent), `sku` what earned or took the cash. Bad amounts are
-- dropped.
function GameAnalytics.Economy(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	amount: number,
	balance: number,
	transaction: Enum.AnalyticsEconomyTransactionType,
	sku: string?
): boolean
	local args = AnalyticsEvents.Economy(amount, balance, sku)
	if args == nil then
		return false
	end
	return guarded("economy event", function()
		service():LogEconomyEvent(player, flow, "Cash", args.amount, args.balance, transaction.Name, args.sku)
	end)
end

-- A stage reached (MilestoneService.CheckStages). Roblox's signature is
-- (player, pathName: string, level: number, levelName: string?): the level
-- must be a whole number (a string there fails with "Unable to cast string
-- to int"), the name is the readable label.
function GameAnalytics.Progression(player: Player, path: string, level: number, levelName: string?): boolean
	if type(path) ~= "string" or type(level) ~= "number" or level ~= level or level % 1 ~= 0 then
		return false
	end
	local label = if type(levelName) == "string" and levelName ~= "" then levelName else nil
	return guarded("progression " .. (label or tostring(level)), function()
		if label then
			service():LogProgressionCompleteEvent(player, path, level, label)
		else
			service():LogProgressionCompleteEvent(player, path, level)
		end
	end)
end

return GameAnalytics
