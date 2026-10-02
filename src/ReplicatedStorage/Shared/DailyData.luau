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
--   * Two goals come from the Living Forest (GAME_DESIGN §16): plant
--     Heartseeds, and sell figured logs (read the bark to find them).
--   * The v2 core loop (V2_PLAN.md, Shared/CoreLoop) rolls from its own
--     pool (ForLoop(2)): goals counted in u³, dollars and pieces, with
--     rewards sized to the v2 prices (TiersV2). Its kinds have names of
--     their own, so a day rolled under one loop is never read as the
--     other's (NeedsReroll). The v1 pool is unchanged.

local BiomeData = require(script.Parent.BiomeData)
local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)
local WoodData = require(script.Parent.WoodData)

local DailyData = {}

DailyData.GoalsPerDay = 3
DailyData.SecondsPerDay = 86400

-- v1: fell .. sellFigured. v2 (KindsV2): fellTrees .. sellFiguredVolume.
-- Letters only: the DailyGoals attribute's pattern reads them that way.
export type GoalKind =
	"fell"
	| "sell"
	| "earn"
	| "sellWood"
	| "load"
	| "plant"
	| "sellFigured"
	| "fellTrees"
	| "sellVolume"
	| "earnCash"
	| "sellWoodVolume"
	| "sellPieces"
	| "plantSeeds"
	| "sellFiguredVolume"

export type Goal = {
	kind: GoalKind,
	target: number,
	progress: number,
	reward: number,
	wood: string?, -- sellWood and sellWoodVolume only
	done: boolean,
}

-- Sizes by axe tier (profile.bestAxeTier; 1 = Rusty Axe ... 9 = Starfall).
-- `reward` is one goal's cash, roughly a minute or three of play at that
-- tier (ECONOMY.md); the all-done bonus is 2 rewards, times the streak
-- multiplier. `seeds` is a "plant N Heartseeds" goal; `figured` a "sell N
-- figured logs" goal, about one figured tree of that tier's wood.
type TierScale = { trees: number, logs: number, cash: number, reward: number, seeds: number, figured: number }
local TIERS: { TierScale } = {
	{ trees = 4, logs = 12, cash = 60, reward = 15, seeds = 2, figured = 3 }, -- Rusty
	{ trees = 6, logs = 18, cash = 150, reward = 30, seeds = 3, figured = 4 }, -- Steel
	{ trees = 6, logs = 24, cash = 400, reward = 75, seeds = 3, figured = 5 }, -- Hardened
	{ trees = 8, logs = 30, cash = 900, reward = 150, seeds = 4, figured = 6 }, -- Silver
	{ trees = 8, logs = 36, cash = 1500, reward = 250, seeds = 4, figured = 6 }, -- Cobalt
	{ trees = 10, logs = 42, cash = 2500, reward = 400, seeds = 5, figured = 7 }, -- Gold
	{ trees = 10, logs = 48, cash = 4000, reward = 600, seeds = 5, figured = 7 }, -- Obsidian
	{ trees = 12, logs = 60, cash = 6000, reward = 900, seeds = 6, figured = 8 }, -- Inferno
	{ trees = 12, logs = 60, cash = 9000, reward = 1300, seeds = 6, figured = 8 }, -- Starfall
}
DailyData.Tiers = TIERS

local KINDS: { GoalKind } = { "fell", "sell", "earn", "sellWood", "load", "plant", "sellFigured" }
DailyData.Kinds = KINDS

-- The v2 loop's sizes by axe tier, set against V2_PLAN.md §17 and the v2
-- axe prices (ItemCatalog `v2.price`) until tools/economy2 can size them:
-- `reward` is one goal's cash; a day's goals plus the one-day bonus come
-- to well under the next axe on the ladder, so goals help along the
-- cheap first rungs (Steel $90, Hardened $190) without skipping them.
-- `volume` (u³ sold) is worth about the `cash` goal at the tier's woods;
-- `figured` is u³ of figured wood (about half a tree); `pieces` counts
-- sold logs of at least MinPieceVolumeV2 each (so slivers don't count).
type TierScaleV2 = {
	trees: number,
	volume: number,
	cash: number,
	reward: number,
	seeds: number,
	figured: number,
	pieces: number,
}
local TIERS_V2: { TierScaleV2 } = {
	{ trees = 3, volume = 40, cash = 60, reward = 15, seeds = 2, figured = 10, pieces = 6 }, -- Rusty
	{ trees = 4, volume = 60, cash = 120, reward = 30, seeds = 3, figured = 15, pieces = 8 }, -- Steel
	{ trees = 5, volume = 80, cash = 240, reward = 60, seeds = 3, figured = 20, pieces = 10 }, -- Hardened
	{ trees = 6, volume = 100, cash = 400, reward = 100, seeds = 4, figured = 25, pieces = 12 }, -- Silver
	{ trees = 6, volume = 140, cash = 700, reward = 175, seeds = 4, figured = 30, pieces = 14 }, -- Cobalt
	{ trees = 8, volume = 180, cash = 1000, reward = 250, seeds = 5, figured = 40, pieces = 16 }, -- Gold
	{ trees = 8, volume = 220, cash = 1600, reward = 400, seeds = 5, figured = 50, pieces = 18 }, -- Obsidian
	{ trees = 10, volume = 280, cash = 2000, reward = 500, seeds = 6, figured = 60, pieces = 20 }, -- Inferno
	{ trees = 10, volume = 300, cash = 2600, reward = 650, seeds = 6, figured = 70, pieces = 20 }, -- Starfall
}
DailyData.TiersV2 = TIERS_V2

local KINDS_V2: { GoalKind } =
	{ "fellTrees", "sellVolume", "earnCash", "sellWoodVolume", "sellPieces", "plantSeeds", "sellFiguredVolume" }
DailyData.KindsV2 = KINDS_V2

-- A sold piece counts toward a "sell N logs" goal from this many u³.
DailyData.MinPieceVolumeV2 = 1

-- The goal pool a loop rolls from: its kinds and its sizes by tier.
export type Pool = { loop: number, kinds: { GoalKind }, tiers: { any } }
local POOLS: { [number]: Pool } = {
	[1] = { loop = 1, kinds = KINDS, tiers = TIERS },
	[2] = { loop = 2, kinds = KINDS_V2, tiers = TIERS_V2 },
}

-- The pool for `loop` (CoreLoop.Active()): v2's under the v2 loop, else v1's.
function DailyData.ForLoop(loop: number?): Pool
	return if loop == 2 then POOLS[2] else POOLS[1]
end

-- Whether a day's `goals` came from another loop's pool than `loop`'s, so
-- they should be rolled again (DailyService on join; ProfileSchema.MigrateV2
-- sets daily.day = 0 for it). Streaks are kept either way.
function DailyData.NeedsReroll(goals: { Goal }, loop: number?): boolean
	local kinds = DailyData.ForLoop(loop).kinds
	for _, goal in ipairs(goals) do
		if not table.find(kinds, goal.kind) then
			return true
		end
	end
	return false
end

-- Woods a "sell N <wood> logs" goal can ask for at a tier: ones growing in
-- the world by day that the tier's axe fells in 30 hits or fewer.
function DailyData.WoodsFor(tier: number): { string }
	local ladder = ItemCatalog.AxeLadder()
	local axe = ladder[math.clamp(math.floor(tier), 1, #ladder)]
	local out: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		local biome = BiomeData.Get(wood.biome)
		local damage = ItemCatalog.AxeDamage(axe, wood)
		if biome and biome.area and not biome.nightOnly and damage > 0 and wood.treeHP / damage <= 30 then
			table.insert(out, wood.id)
		end
	end
	return out
end

-- The v2 loop's woods for a "sell N u³ of <wood>" goal at a tier: ones
-- growing in the world by day whose trunk one of the tier's axes (the
-- ladder up to `tier`: they're bought in order and never lost, and v2's
-- ladder isn't strongest-last) cuts in FieldGuide.UsefulHitsV2 hits or
-- fewer.
function DailyData.WoodsForV2(tier: number): { string }
	local ladder = ItemCatalog.AxeLadder()
	local top = math.clamp(math.floor(tier), 1, #ladder)
	local out: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		local biome = BiomeData.Get(wood.biome)
		if biome and biome.area and not biome.nightOnly then
			for i = 1, top do
				if FieldGuide.TrunkHits(ladder[i], wood) <= FieldGuide.UsefulHitsV2 then
					table.insert(out, wood.id)
					break
				end
			end
		end
	end
	return out
end

-- The streak multiplier on the all-done bonus: +25% per day in a row after
-- the first, up to 2x at 5 days.
function DailyData.StreakMultiplier(streak: number): number
	return 1 + 0.25 * math.clamp(streak - 1, 0, 4)
end

local function scaleFor(tier: number): TierScale
	return TIERS[math.clamp(math.floor(tier), 1, #TIERS)]
end

local function scaleForV2(tier: number): TierScaleV2
	return TIERS_V2[math.clamp(math.floor(tier), 1, #TIERS_V2)]
end

-- The all-done bonus at `tier` with `streak` days: v1's sizes, or
-- `loop`'s.
function DailyData.Bonus(tier: number, streak: number, loop: number?): number
	local reward = if loop == 2 then scaleForV2(tier).reward else scaleFor(tier).reward
	return math.floor(reward * 2 * DailyData.StreakMultiplier(streak) + 0.5)
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

-- Today's goals under the v2 loop (Roll with loop 2): the same draw as
-- v1's, from the v2 pool.
local function rollV2(random: () -> number, tier: number): { Goal }
	local kinds = table.clone(KINDS_V2)
	local scale = scaleForV2(tier)
	local goals: { Goal } = {}
	for _ = 1, math.min(DailyData.GoalsPerDay, #kinds) do
		local kind: GoalKind = table.remove(kinds, math.floor(random() * #kinds) + 1) :: GoalKind
		local goal: Goal = { kind = kind, target = 0, progress = 0, reward = scale.reward, done = false }
		if kind == "fellTrees" then
			goal.target = scale.trees
		elseif kind == "sellVolume" then
			goal.target = scale.volume
		elseif kind == "earnCash" then
			goal.target = scale.cash
		elseif kind == "sellPieces" then
			goal.target = scale.pieces
		elseif kind == "plantSeeds" then
			goal.target = scale.seeds
		elseif kind == "sellFiguredVolume" then
			goal.target = scale.figured
		else -- sellWoodVolume
			goal.target = math.ceil(scale.volume / 2)
			local woods = DailyData.WoodsForV2(tier)
			goal.wood = woods[math.floor(random() * #woods) + 1]
		end
		table.insert(goals, goal)
	end
	return goals
end

-- Today's goals for a player (v1's pool, or `loop`'s).
function DailyData.Roll(userId: number, day: number, tier: number, loop: number?): { Goal }
	local random = rng(math.abs(userId) * 7919 + day * 104729 + 1)
	if loop == 2 then
		return rollV2(random, tier)
	end
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
		elseif kind == "plant" then
			goal.target = scale.seeds
		elseif kind == "sellFigured" then
			goal.target = scale.figured
		else
			goal.target = math.ceil(scale.logs / 2)
			local woods = DailyData.WoodsFor(tier)
			goal.wood = woods[math.floor(random() * #woods) + 1]
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
	elseif goal.kind == "plant" then
		return if goal.target == 1
			then "Plant a Heartseed in a stump"
			else string.format("Plant %d Heartseeds in stumps", goal.target)
	elseif goal.kind == "sellFigured" then
		return string.format("Sell %d figured logs (read the bark!)", goal.target)
	elseif goal.kind == "fellTrees" then
		return if goal.target == 1 then "Fell a tree" else string.format("Fell %d trees", goal.target)
	elseif goal.kind == "sellVolume" then
		return string.format("Sell %s of wood", FieldGuide.VolumeText(goal.target))
	elseif goal.kind == "earnCash" then
		return string.format("Earn %s selling wood", FieldGuide.CashText(goal.target))
	elseif goal.kind == "sellPieces" then
		return string.format(
			"Sell %d logs of %s or more",
			goal.target,
			FieldGuide.VolumeText(DailyData.MinPieceVolumeV2)
		)
	elseif goal.kind == "plantSeeds" then
		return if goal.target == 1
			then "Plant a Heartseed in a stump"
			else string.format("Plant %d Heartseeds in stumps", goal.target)
	elseif goal.kind == "sellFiguredVolume" then
		return string.format("Sell %s of figured wood (read the bark!)", FieldGuide.VolumeText(goal.target))
	end
	local wood = if goal.wood then WoodData.Get(goal.wood) else nil
	local woodName = if wood then string.lower(wood.displayName) else ""
	if goal.kind == "sellWoodVolume" then
		return string.format("Sell %s of %s", FieldGuide.VolumeText(goal.target), woodName)
	end
	return string.format("Sell %d %s logs", goal.target, woodName)
end

-- The progress after a goal's text in DailyUI: "(4/12)" for counts,
-- "(12/40 u³)" for volumes, "($23/$60)" for cash. Progress shows whole
-- units (u³ rounded down), never past the target.
function DailyData.ProgressText(goal: Goal): string
	local done = math.max(0, math.min(goal.progress, goal.target))
	if goal.kind == "earnCash" then
		return string.format("(%s/%s)", FieldGuide.CashText(done), FieldGuide.CashText(goal.target))
	elseif goal.kind == "sellVolume" or goal.kind == "sellWoodVolume" or goal.kind == "sellFiguredVolume" then
		return string.format("(%d/%d u³)", math.floor(done), goal.target)
	end
	return string.format("(%d/%d)", done, goal.target)
end

-- What a v2 sale tells the daily goals (SellService, per owner per tick):
-- u³ sold, the cash credited, u³ by wood id, each piece's u³, and the u³
-- of figured wood among them.
export type SaleV2 = {
	volume: number?,
	cash: number?,
	byWood: { [string]: number }?,
	pieces: { number }?,
	figured: number?,
}

-- The v2 events a goal can count (DailyService.Event under v2).
export type EventV2 = "treeFelled" | "seedPlanted" | "woodSold"

local function amountOf(value: unknown): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value <= 0 then
		return 0 -- not a number, NaN, infinite, or nothing
	end
	return value
end

-- How much `event` adds to a v2 goal: trees felled and seeds planted
-- (`amount`, default 1), and from a sale (`sale`) its u³, its cash, its
-- u³ of the goal's wood, its pieces of MinPieceVolumeV2 or more, or its
-- figured u³. 0 for anything else, a v1 goal, or a junk number.
function DailyData.CountV2(goal: Goal, event: EventV2, amount: number?, sale: SaleV2?): number
	if event == "treeFelled" then
		return if goal.kind == "fellTrees" then amountOf(amount or 1) else 0
	elseif event == "seedPlanted" then
		return if goal.kind == "plantSeeds" then amountOf(amount or 1) else 0
	elseif event ~= "woodSold" or not sale then
		return 0
	end
	if goal.kind == "sellVolume" then
		return amountOf(sale.volume)
	elseif goal.kind == "earnCash" then
		return amountOf(sale.cash)
	elseif goal.kind == "sellFiguredVolume" then
		return amountOf(sale.figured)
	elseif goal.kind == "sellWoodVolume" then
		local byWood = sale.byWood
		return if goal.wood and byWood then amountOf(byWood[goal.wood]) else 0
	elseif goal.kind == "sellPieces" then
		local n = 0
		for _, volume in ipairs(sale.pieces or {}) do
			if amountOf(volume) >= DailyData.MinPieceVolumeV2 then
				n += 1
			end
		end
		return n
	end
	return 0
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
		if table.find(KINDS, kind :: any) or table.find(KINDS_V2, kind :: any) then
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
