--!strict
-- DailyService: daily goals and streaks (rules in Shared/DailyData).
--   * The day's goals live in the save (profile.daily) and are mirrored on
--     the DailyGoals, DailyStreak and DailyResetAt player attributes for
--     DailyUI.
--   * Game code reports what happened with DailyService.Event (the same
--     moments as the tutorial: trees felled, logs loaded, logs sold).
--   * A finished goal pays its reward; finishing all of them pays the
--     streak bonus and extends the streak. A missed day breaks it.
--   * New goals roll at midnight UTC, including for players online then.
-- All rewards go through EconomyService.AddCash, so the wallet cap holds.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyData = require(ReplicatedStorage.Shared.DailyData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)

type Profile = ProfileService.Profile
type Goal = DailyData.Goal

export type DailyEvent = "treeFelled" | "logsLoaded" | "logsSold"

local DailyService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local clock: () -> number = os.time -- tests replace this

local function analytics(player: Player, name: string, value: number)
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value)
	end)
	if not ok then
		warn("[DailyService] Analytics failed: " .. tostring(err))
	end
end

local function publish(player: Player, profile: Profile)
	local daily = profile.daily
	player:SetAttribute("DailyGoals", DailyData.Encode(daily.goals))
	player:SetAttribute("DailyStreak", daily.streak)
	player:SetAttribute("DailyResetAt", DailyData.NextReset(clock()))
end

-- Rolls new goals if the day has changed. Returns true if it did.
local function rollIfNewDay(player: Player, profile: Profile): boolean
	local daily = profile.daily
	local today = DailyData.Day(clock())
	if daily.day == today then
		return false
	end
	daily.day = today
	daily.goals = DailyData.Roll(player.UserId, today, profile.bestAxeTier)
	if daily.lastCompleteDay < today - 1 then
		daily.streak = 0 -- a whole day went by without finishing: the streak is over
	end
	return true
end

local function allDone(goals: { Goal }): boolean
	for _, goal in ipairs(goals) do
		if not goal.done then
			return false
		end
	end
	return #goals > 0
end

local function finishDay(player: Player, profile: Profile)
	local daily = profile.daily
	local today = daily.day
	if daily.lastCompleteDay == today then
		return
	end
	daily.streak = if daily.lastCompleteDay == today - 1 then daily.streak + 1 else 1
	daily.lastCompleteDay = today
	daily.bestStreak = math.max(daily.bestStreak, daily.streak)
	local bonus = DailyData.Bonus(profile.bestAxeTier, daily.streak)
	EconomyService.AddCash(player, bonus, string.format("daily bonus, %d-day streak", daily.streak), "daily")
	notify(
		player,
		string.format(
			"All daily goals done! +%s. Streak: %d day%s.",
			Util.formatCash(bonus),
			daily.streak,
			if daily.streak == 1 then "" else "s"
		)
	)
	analytics(player, "DailyAllDone", daily.streak)
end

-- Something that counts toward goals happened. `amount` is how many (trees
-- or logs); for logsSold, `byWood` counts the logs per wood id and `cash`
-- is what the sale paid.
function DailyService.Event(
	player: Player,
	event: DailyEvent,
	amount: number,
	byWood: { [string]: number }?,
	cash: number?
)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local rolled = rollIfNewDay(player, profile)
	local changed = rolled
	for _, goal in ipairs(profile.daily.goals) do
		if not goal.done then
			local add = 0
			if event == "treeFelled" and goal.kind == "fell" then
				add = amount
			elseif event == "logsLoaded" and goal.kind == "load" then
				add = amount
			elseif event == "logsSold" and goal.kind == "sell" then
				add = amount
			elseif event == "logsSold" and goal.kind == "earn" then
				add = cash or 0
			elseif event == "logsSold" and goal.kind == "sellWood" and goal.wood and byWood then
				add = byWood[goal.wood] or 0
			end
			if add > 0 then
				changed = true
				goal.progress = math.min(goal.target, goal.progress + add)
				if goal.progress >= goal.target then
					goal.done = true
					EconomyService.AddCash(player, goal.reward, "daily goal: " .. goal.kind, "daily")
					notify(
						player,
						string.format(
							"Daily goal done: %s. +%s",
							DailyData.GoalText(goal),
							Util.formatCash(goal.reward)
						)
					)
					analytics(player, "DailyGoalDone", goal.reward)
				end
			end
		end
	end
	if allDone(profile.daily.goals) then
		finishDay(player, profile)
	end
	if changed then
		publish(player, profile)
	end
end

-- Call once the player's save has loaded.
function DailyService.Start(player: Player, profile: Profile)
	rollIfNewDay(player, profile)
	publish(player, profile)
end

-- New goals at midnight for everyone online.
local function midnightLoop()
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = ProfileService.GetProfile(player)
			if profile and rollIfNewDay(player, profile) then
				publish(player, profile)
				notify(player, "New daily goals are in!")
			end
		end
	end
end

-- `notifyFn` shows a toast (GameServer's notify). `clockFn` is for tests.
function DailyService.Init(notifyFn: (Player, string) -> (), clockFn: (() -> number)?)
	notify = notifyFn
	if clockFn then
		clock = clockFn
	else
		task.spawn(midnightLoop)
	end
end

return DailyService
