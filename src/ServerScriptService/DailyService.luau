--!strict
-- DailyService: daily goals and streaks (rules in Shared/DailyData).
--   * The day's goals live in the save (profile.daily) and are mirrored on
--     the DailyGoals, DailyStreak and DailyResetAt player attributes for
--     DailyUI.
--   * Game code reports what happened with DailyService.Event (the same
--     moments as the tutorial: trees felled, logs loaded, logs sold, and
--     from the Living Forest: figured logs sold).
--   * A finished goal is owed, not paid: Rook Calloway, the Sawmill Foreman
--     (Shared/ForemanData), pays it when the player hands it in (the
--     ForemanTurnIn remote, checked against the distance to him). Finishing
--     all of them extends the streak at once and owes the streak bonus the
--     same way. Whatever is still owed when the day resets is paid then,
--     and a wallet at the cap leaves the remainder owed (`bonusOwed`). A
--     missed day breaks the streak.
--   * New goals roll at midnight UTC, including for players online then.
--   * While Murph's tutorial runs (profile.tutorialDone is false, so the
--     TutorialStep attribute is above 0), goals still count and pay, but
--     their toasts are held back: the first minute has one objective, and
--     DailyUI hides its button until then too.
--   * The daily-return calendar (day 1..7, a milestone at 7): the first
--     time you are seen on a UTC day it pays that day's cash, growing
--     with consecutive days (DailyData.LoginStep / LoginReward).
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
local ForemanData = require(ReplicatedStorage.Shared.ForemanData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local QuestService = require(script.Parent.QuestService)

type Profile = ProfileService.Profile
type Goal = DailyData.Goal

export type DailyEvent = "treeFelled" | "logsLoaded" | "logsSold" | "figuredSold"

local DailyService = {}

-- Called with (player, "treeFelled" | "piecesSold", amount) for the same
-- moments the goals count; EventService.InitEvent sets it (the event's
-- themed goals). Nil when no event listens.
DailyService.Listener = nil :: ((Player, string, number) -> ())?

local function tell(player: Player, moment: string, amount: number)
	local listener = DailyService.Listener
	if listener and amount > 0 then
		local ok, err = pcall(function(): any
			listener(player, moment, amount)
			return nil
		end)
		if not ok then
			warn("[DailyService] listener failed: " .. tostring(err))
		end
	end
end

-- The goal kind each event counts toward, one per tree or log.
-- ForestService reports figuredSold (figured logs sold).
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
	player:SetAttribute("DailyBonusOwed", daily.bonusOwed or 0) -- the streak bonus (or a full wallet's remainder) Rook still owes
	player:SetAttribute("DailyResetAt", DailyData.NextReset(clock()))
	player:SetAttribute("DailyLoginDay", daily.loginDay or 0) -- the calendar day paid today (1..7)
end

-- The daily-return calendar (DailyData.LoginStep): the first time a player
-- is seen on a UTC day, it pays that calendar day's cash (day 7 is the
-- milestone) through AddCash, so the wallet cap holds. Server-side only:
-- no remote, nothing to claim twice. Returns true if it paid.
local function claimLogin(player: Player, profile: Profile): boolean
	local daily = profile.daily
	local today = DailyData.Day(clock())
	local day, pays = DailyData.LoginStep(daily.loginDay, daily.lastLoginDay, today)
	if not pays then
		return false
	end
	daily.loginDay = day
	daily.lastLoginDay = today
	local reward = DailyData.LoginReward(profile.bestAxeTier, day, if loop == 2 then 2 else nil)
	EconomyService.AddCash(player, reward, string.format("daily return, day %d", day), "daily")
	local message = if day == DailyData.LoginDays
		then string.format("Day %d of your daily return: the weekly milestone! +%s", day, Util.formatCash(reward))
		else string.format("Daily return, day %d of %d: +%s", day, DailyData.LoginDays, Util.formatCash(reward))
	toast(player, profile, message)
	analytics(player, "DailyReturn", day)
	return true
end

-- Pays everything the foreman owes: each finished goal not yet paid, then
-- the all-done bonus. Marked paid before the cash moves, so a second call
-- (a double tap, a hand-in during a sale) pays nothing. A full wallet keeps
-- the part that did not fit owed. Returns (credited, still owed).
local function settle(player: Player, profile: Profile, reason: string): (number, number)
	local daily = profile.daily
	local total = ForemanData.Owed(daily.goals, daily.bonusOwed)
	if total <= 0 then
		return 0, 0
	end
	for _, goal in ipairs(daily.goals) do
		if goal.done and goal.paid == false then
			goal.paid = true
		end
	end
	daily.bonusOwed = 0
	local credited, overflow = EconomyService.AddCash(player, total, reason, "daily")
	if overflow > 0 then
		daily.bonusOwed = overflow
	end
	return credited, overflow
end

-- Rolls new goals if the day has changed. Returns true if it did. What the
-- foreman still owed from the old day is paid first.
local function rollIfNewDay(player: Player, profile: Profile): boolean
	local daily = profile.daily
	local today = DailyData.Day(clock())
	if daily.day == today then
		return false
	end
	local paid = settle(player, profile, "daily jobs, paid at the reset")
	if paid > 0 then
		toast(player, profile, string.format("Rook paid your %s for yesterday's jobs.", Util.formatCash(paid)))
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
	daily.bonusOwed = (daily.bonusOwed or 0) + bonus
	toast(
		player,
		profile,
		string.format(
			"All daily jobs done! Rook owes you %s more. Streak: %d day%s.",
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
	if rolled and claimLogin(player, profile) then
		changed = true
	end
	for _, goal in ipairs(profile.daily.goals) do
		if not goal.done then
			local add = addFor(goal)
			if add > 0 then
				changed = true
				goal.progress = math.min(goal.target, goal.progress + add)
				if goal.progress >= goal.target then
					goal.done = true
					goal.paid = false -- Rook pays it when you hand it in
					toast(
						player,
						profile,
						string.format(
							"Daily job done: %s. Rook has %s for you.",
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
	if event == "treeFelled" then
		tell(player, "treeFelled", amount)
	elseif event == "logsSold" and loop ~= 2 then
		tell(player, "piecesSold", amount)
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
	local pieces = 0
	for _, volume in ipairs(sale.pieces or {}) do
		if type(volume) == "number" and volume >= DailyData.MinPieceVolumeV2 then
			pieces += 1
		end
	end
	tell(player, "piecesSold", pieces)
	progress(player, profile, function(goal: Goal): number
		return DailyData.CountV2(goal, "woodSold", nil, sale)
	end)
end

-- Hands the day's finished jobs in to Rook: pays what is owed. Returns the
-- cash credited and the part a full wallet left owed. Nothing during the
-- tutorial (Rook sends you back to Murph).
function DailyService.TurnIn(player: Player): (number, number)
	local profile = ProfileService.GetProfile(player)
	if not profile or not profile.tutorialDone then
		return 0, 0
	end
	rollIfNewDay(player, profile)
	local credited, owedLeft = settle(player, profile, "daily jobs, paid by the foreman")
	publish(player, profile)
	if credited > 0 then
		notify(player, string.format("Rook paid you %s.", Util.formatCash(credited)))
		analytics(player, "DailyPaid", credited)
	elseif owedLeft > 0 then
		notify(player, "Your wallet is full. Rook keeps the rest owed.")
	end
	QuestService.RefreshNextGoal(player)
	return credited, owedLeft
end

-- Whether `player` stands within hand-in reach of Rook (the Foreman model,
-- tagged NPC): the same reach as his Talk prompt, with a little slack.
DailyService.Reach = 16
function DailyService.NearForeman(player: Player): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not hrp or not hrp:IsA("BasePart") then
		return false
	end
	local ok, near = pcall(function(): boolean
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("NPC")) do
			if model:GetAttribute("NPCId") == ForemanData.Id and model:IsA("Model") and model.PrimaryPart then
				if (model.PrimaryPart.Position - hrp.Position).Magnitude <= DailyService.Reach then
					return true
				end
			end
		end
		return false
	end)
	return ok and near
end

local function onTurnIn(player: Player)
	if not RateLimiter.Allow(player, "ForemanTurnIn") then
		return
	end
	if not DailyService.NearForeman(player) then
		return
	end
	DailyService.TurnIn(player)
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
	claimLogin(player, profile)
	publish(player, profile)
	QuestService.RefreshNextGoal(player)
end

-- New goals at midnight for everyone online.
local function midnightLoop()
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = ProfileService.GetProfile(player)
			local rolled = profile ~= nil and rollIfNewDay(player, profile)
			local paid = profile ~= nil and claimLogin(player, profile) -- also if an event rolled the day first
			if profile and (rolled or paid) then
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
function DailyService.Init(
	notifyFn: (Player, string) -> (),
	clockFn: (() -> number)?,
	activeLoop: number?,
	turnInRemote: RemoteEvent?
)
	notify = notifyFn
	if turnInRemote then
		turnInRemote.OnServerEvent:Connect(onTurnIn)
	end
	loop = if activeLoop == 2 then 2 else 1
	if clockFn then
		clock = clockFn
	else
		task.spawn(midnightLoop)
	end
end

return DailyService
