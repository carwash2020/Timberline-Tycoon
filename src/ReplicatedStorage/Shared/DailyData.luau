--!strict
-- DailyData: daily goals and streaks (GAME_DESIGN §12, "a reason to come
-- back each day"). Pure data and rules, shared by DailyService (server)
-- and DailyUI (client), and tested outside Roblox. Tuning = editing this.
--
--   * Every UTC day each player gets GOALS_PER_DAY goals, picked from their
--     user id and the day (so a rejoin gives the same ones), sized to their
--     axe tier (a Gold Axe player gets bigger goals and bigger rewards).
--   * Each goal pays its reward when done. Finishing all of them pays a
--     bonus that grows with the streak: days in a row with every goal done.
--   * Missing a day breaks the streak.

local Util = require(script.Parent.Util)
local WoodData = require(script.Parent.WoodData)

local DailyData = {}

DailyData.GoalsPerDay = 3
DailyData.SecondsPerDay = 86400

export type GoalKind = "fell" | "sell" | "earn" | "sellWood" | "load"

export type Goal = {
	kind: GoalKind,
	target: number,
	progress: number,
	reward: number,
	wood: string?, -- sellWood only
	done: boolean,
}

-- Sizes by axe tier (profile.bestAxeTier; 1 = Rusty Axe ... 9 = Starfall).
-- `reward` is one goal's cash, roughly a minute or three of play at that
-- tier (ECONOMY.md); the all-done bonus is 2 rewards, times the streak
-- multiplier.
type TierScale = { trees: number, logs: number, cash: number, reward: number }
local TIERS: { TierScale } = {
	{ trees = 4, logs = 12, cash = 60, reward = 15 }, -- Rusty
	{ trees = 6, logs = 18, cash = 150, reward = 30 }, -- Steel
	{ trees = 6, logs = 24, cash = 400, reward = 75 }, -- Hardened
	{ trees = 8, logs = 30, cash = 900, reward = 150 }, -- Silver
	{ trees = 8, logs = 36, cash = 1500, reward = 250 }, -- Cobalt
	{ trees = 10, logs = 42, cash = 2500, reward = 400 }, -- Gold
	{ trees = 10, logs = 48, cash = 4000, reward = 600 }, -- Obsidian
	{ trees = 12, logs = 60, cash = 6000, reward = 900 }, -- Inferno
	{ trees = 12, logs = 60, cash = 9000, reward = 1300 }, -- Starfall
}
DailyData.Tiers = TIERS

local KINDS: { GoalKind } = { "fell", "sell", "earn", "sellWood", "load" }

-- Woods a "sell N <wood> logs" goal can ask for: ones that grow in the
-- world today. Add woods here as their biomes are built.
DailyData.WoodPool = { "oak", "birch" }

-- The streak multiplier on the all-done bonus: +25% per day in a row after
-- the first, up to 2x at 5 days.
function DailyData.StreakMultiplier(streak: number): number
	return 1 + 0.25 * math.clamp(streak - 1, 0, 4)
end

local function scaleFor(tier: number): TierScale
	return TIERS[math.clamp(math.floor(tier), 1, #TIERS)]
end

function DailyData.Bonus(tier: number, streak: number): number
	return math.floor(scaleFor(tier).reward * 2 * DailyData.StreakMultiplier(streak) + 0.5)
end

-- The day number (UTC) for a unix time, and when the next day starts.
function DailyData.Day(now: number): number
	return now // DailyData.SecondsPerDay
end

function DailyData.NextReset(now: number): number
	return (DailyData.Day(now) + 1) * DailyData.SecondsPerDay
end

-- A small seeded random number generator (Park–Miller), so the same player
-- gets the same goals on the same day on any server.
local function rng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Today's goals for a player.
function DailyData.Roll(userId: number, day: number, tier: number): { Goal }
	local random = rng(math.abs(userId) * 7919 + day * 104729 + 1)
	local kinds = table.clone(KINDS)
	local scale = scaleFor(tier)
	local goals: { Goal } = {}
	for _ = 1, math.min(DailyData.GoalsPerDay, #kinds) do
		local kind: GoalKind = table.remove(kinds, math.floor(random() * #kinds) + 1) :: GoalKind
		local goal: Goal = { kind = kind, target = 0, progress = 0, reward = scale.reward, done = false }
		if kind == "fell" then
			goal.target = scale.trees
		elseif kind == "sell" or kind == "load" then
			goal.target = scale.logs
		elseif kind == "earn" then
			goal.target = scale.cash
		else
			goal.target = math.ceil(scale.logs / 2)
			goal.wood = DailyData.WoodPool[math.floor(random() * #DailyData.WoodPool) + 1]
		end
		table.insert(goals, goal)
	end
	return goals
end

-- "Sell 9 birch logs"
function DailyData.GoalText(goal: Goal): string
	if goal.kind == "fell" then
		return string.format("Fell %d trees", goal.target)
	elseif goal.kind == "sell" then
		return string.format("Sell %d logs", goal.target)
	elseif goal.kind == "load" then
		return string.format("Load %d logs into your truck", goal.target)
	elseif goal.kind == "earn" then
		return string.format("Earn %s selling logs", Util.formatCash(goal.target))
	end
	local wood = if goal.wood then WoodData.Get(goal.wood) else nil
	return string.format("Sell %d %s logs", goal.target, if wood then string.lower(wood.displayName) else "")
end

-- The DailyGoals player attribute (attributes can't hold tables):
-- "kind,target,progress,reward,wood,done;..." with wood "-" when unused.
function DailyData.Encode(goals: { Goal }): string
	local parts: { string } = {}
	for _, g in ipairs(goals) do
		table.insert(
			parts,
			string.format(
				"%s,%d,%d,%d,%s,%d",
				g.kind,
				g.target,
				g.progress,
				g.reward,
				g.wood or "-",
				if g.done then 1 else 0
			)
		)
	end
	return table.concat(parts, ";")
end

function DailyData.Decode(text: string): { Goal }
	local goals: { Goal } = {}
	for kind, target, progress, reward, wood, done in string.gmatch(text, "(%a+),(%d+),(%d+),(%d+),([%w%-]+),([01])") do
		if table.find(KINDS, kind :: any) then
			table.insert(goals, {
				kind = kind :: any,
				target = tonumber(target) or 0,
				progress = tonumber(progress) or 0,
				reward = tonumber(reward) or 0,
				wood = if wood ~= "-" then wood else nil,
				done = done == "1",
			})
		end
	end
	return goals
end

return DailyData
