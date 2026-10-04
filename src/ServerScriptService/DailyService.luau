--!strict
-- DailyService: daily goals and streaks (rules in Shared/DailyData).
--   * The day's goals live in the save (profile.daily) and are mirrored on
--     the DailyGoals, DailyStreak and DailyResetAt player attributes for
--     DailyUI.
--   * Game code reports what happened with DailyService.Event (the same
--     moments as the tutorial: trees felled, logs loaded, logs sold, and
--     from the Living Forest: figured logs sold).
--   * A finished goal pays its reward; finishing all of them pays the
--     streak bonus and extends the streak. A missed day breaks it.
--   * New goals roll at midnight UTC, including for players online then.
--   * While Murph's tutorial runs (profile.tutorialDone is false, so the
--     TutorialStep attribute is above 0), goals still count and pay, but
--     their toasts are held back: the first minute has one objective, and
--     DailyUI hides its button until then too.
-- All rewards go through EconomyService.AddCash, so the wallet cap holds.
--
-- The v2 core loop (V2_PLAN.md, Shared/CoreLoop: GameServer passes
-- CoreLoop.Active() to Init) rolls from its own pool (DailyData.ForLoop):
-- goals in u³, dollars and pieces. A day rolled under the other loop
-- (DailyData.NeedsReroll) rolls again on join; the streak is kept. Its
-- goals count with DailyData.CountV2: trees felled through Event (the
-- same call as v1), and each sale through WoodSold
-- (SellService's onSold, per payee per tick).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyData = require(ReplicatedStorage.Shared.DailyData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)

type Profile = ProfileService.Profile
type Goal = DailyData.Goal

export type DailyEvent = "treeFelled" | "logsLoaded" | "logsSold" | "seedPlanted" | "figuredSold"

local DailyService = {}

-- The goal kind each event counts toward, one per tree or log.
-- ForestService reports figuredSold (figured logs sold). seedPlanted is
-- still accepted and counts for nothing.
local COUNTED_BY: { [DailyEvent]: DailyData.GoalKind } = {
	treeFelled = "fell",
	logsLoaded = "load",
	logsSold = "sell",
	figuredSold = "sellFigured",
}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local clock: () -> number = os.time -- tests replace this
local loop = 1 -- the core loop that runs (Init)

-- A toast about the daily goals, unless the tutorial is still running.
local function toast(player: Player, profile: Profile, message: string)
	if profile.tutorialDone then
		notify(player, message)
	end
end

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
	daily.goals = DailyData.Roll(player.UserId, today, profile.bestAxeTier, if loop == 2 then 2 else nil)
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
	local bonus = DailyData.Bonus(profile.bestAxeTier, daily.streak, if loop == 2 then 2 else nil)
	EconomyService.AddCash(player, bonus, string.format("daily bonus, %d-day streak", daily.streak), "daily")
	toast(
		player,
		profile,
		string.format(
			"All daily goals done! +%s. Streak: %d day%s.",
			Util.formatCash(bonus),
			daily.streak,
			if daily.streak == 1 then "" else "s"
		)
	)
	analytics(player, "DailyAllDone", daily.streak)
	QuestService.RefreshNextGoal(player)
end

-- Adds to each of today's open goals what `addFor` says it gains, paying
-- each goal done and, once all are, the day's bonus.
local function progress(player: Player, profile: Profile, addFor: (Goal) -> number)
	local rolled = rollIfNewDay(player, profile)
	local changed = rolled
	for _, goal in ipairs(profile.daily.goals) do
		if not goal.done then
			local add = addFor(goal)
			if add > 0 then
				changed = true
				goal.progress = math.min(goal.target, goal.progress + add)
				if goal.progress >= goal.target then
					goal.done = true
					EconomyService.AddCash(player, goal.reward, "daily goal: " .. goal.kind, "daily")
					toast(
						player,
						profile,
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
	if rolled then
		QuestService.RefreshNextGoal(player)
	end
end

-- Something that counts toward goals happened. `amount` is how many (trees
-- or logs); for logsSold, `byWood` counts the logs per wood id and `cash`
-- is what the sale paid. Under the v2 loop only trees felled count here
-- (DailyData.CountV2); sales come through WoodSold.
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
	if loop == 2 then
		local v2Event: DailyData.EventV2? = if event == "treeFelled" then event else nil
		progress(player, profile, function(goal: Goal): number
			return if v2Event then DailyData.CountV2(goal, v2Event, amount) else 0
		end)
		return
	end
	progress(player, profile, function(goal: Goal): number
		local add = 0
		if goal.kind == COUNTED_BY[event] then
			add = amount
		elseif event == "logsSold" and goal.kind == "earn" then
			add = cash or 0
		elseif event == "logsSold" and goal.kind == "sellWood" and goal.wood and byWood then
			add = byWood[goal.wood] or 0
		end
		return add
	end)
end

-- A v2 sale paid `player` (SellService's onSold, per payee per tick): its
-- u³, the dollars credited, u³ by wood, each piece's u³ and the figured
-- u³ (DailyData.SaleV2) count toward today's v2 goals. Nothing under the
-- v1 loop (its sales report logsSold through Event).
function DailyService.WoodSold(player: Player, sale: DailyData.SaleV2)
	local profile = ProfileService.GetProfile(player)
	if not profile or loop ~= 2 then
		return
	end
	progress(player, profile, function(goal: Goal): number
		return DailyData.CountV2(goal, "woodSold", nil, sale)
	end)
end

-- Call once the player's save has loaded. Today's goals from the other
-- loop's pool (a save from before the switch, or after a rollback) roll
-- again; the streak stays.
function DailyService.Start(player: Player, profile: Profile)
	local active = if loop == 2 then 2 else nil
	-- A saved plant goal is replaced on its own. The other goals and the
	-- streak stay. A day from the other loop still rolls again, whole.
	DailyData.ReplaceRetired(profile.daily.goals, player.UserId, profile.daily.day, profile.bestAxeTier, active)
	if DailyData.NeedsReroll(profile.daily.goals, loop) then
		profile.daily.day = 0
	end
	rollIfNewDay(player, profile)
	publish(player, profile)
	QuestService.RefreshNextGoal(player)
end

-- New goals at midnight for everyone online.
local function midnightLoop()
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = ProfileService.GetProfile(player)
			if profile and rollIfNewDay(player, profile) then
				publish(player, profile)
				toast(player, profile, "New daily goals are in!")
				QuestService.RefreshNextGoal(player)
			end
		end
	end
end

-- `notifyFn` shows a toast (GameServer's notify). `clockFn` is for tests.
-- `activeLoop` is the core loop that runs (CoreLoop.Active(); 1 when not
-- given).
function DailyService.Init(notifyFn: (Player, string) -> (), clockFn: (() -> number)?, activeLoop: number?)
	notify = notifyFn
	loop = if activeLoop == 2 then 2 else 1
	if clockFn then
		clock = clockFn
	else
		task.spawn(midnightLoop)
	end
end

return DailyService
