--!strict
-- ForestLogic: the Living Forest's rules (GAME_DESIGN §16), pure so tests
-- and tools can check them. Numbers come from ForestData; randomness comes
-- in as rolls in [0, 1), so every rule is deterministic here.
--   * Heartseeds: how many a felled tree drops, and the pouch's caps.
--   * Grove Vitality: changes, the drift back to rest, tiers.
--   * The Hidden Grain: the figure chance, the roll, value multipliers,
--     and the average a figure adds (the economy model's factor).
--   * Who a felling counts for (the most chopping, not the last swing).
--   * Elders: their size class, who counts as a helper, the helper's
--     bonus, which grove wakes one.
--   * The planter's share and the Skyroot Bloom.

local ForestData = require(script.Parent.ForestData)
local TreeLogic = require(script.Parent.TreeLogic)
local WoodData = require(script.Parent.WoodData)

type FigureDef = ForestData.FigureDef
type Tier = ForestData.Tier
type TierId = ForestData.TierId

local ForestLogic = {}

local figureById: { [string]: FigureDef } = {}
for _, f in ipairs(ForestData.Figures) do
	figureById[f.id] = f
end

local groveSet: { [string]: boolean } = {}
for _, id in ipairs(ForestData.Groves) do
	groveSet[id] = true
end

---------------------------------------------------------------------------
-- Heartseeds
---------------------------------------------------------------------------

export type DropFacts = {
	large: boolean, -- a large tree or an Elder
	storm: boolean, -- storm-struck when felled
	steward: boolean, -- the feller planted it
	roll: number, -- [0, 1) for the 15% bonus
}

-- Heartseeds a felled tree gives its feller.
function ForestLogic.SeedDrop(facts: DropFacts): number
	local s = ForestData.Seeds
	local n = s.perTree
	if facts.large then
		n += s.largeBonus
	end
	if facts.roll < s.rollChance then
		n += s.rollBonus
	end
	if facts.storm then
		n += s.stormBonus
	end
	if facts.steward then
		n += s.stewardBonus
	end
	return n
end

-- True for the size classes that drop the large tree's extra seed.
function ForestLogic.IsLarge(size: TreeLogic.SizeClass): boolean
	return size.name == "large" or size.name == "elder"
end

function ForestLogic.TotalSeeds(seeds: { [string]: number }): number
	local total = 0
	for _, n in pairs(seeds) do
		total += n
	end
	return total
end

-- Puts up to `n` seeds of `woodId` in the pouch, within the caps. Changes
-- `seeds`; returns how many fit.
function ForestLogic.AddSeeds(seeds: { [string]: number }, woodId: string, n: number): number
	local s = ForestData.Seeds
	local have = seeds[woodId] or 0
	local room = math.min(s.maxPerWood - have, s.maxTotal - ForestLogic.TotalSeeds(seeds))
	local added = math.clamp(math.floor(n), 0, math.max(0, room))
	if added > 0 then
		seeds[woodId] = have + added
	end
	return added
end

-- Takes one seed of `woodId`. False if there's none.
function ForestLogic.TakeSeed(seeds: { [string]: number }, woodId: string): boolean
	local have = seeds[woodId] or 0
	if have < 1 then
		return false
	end
	if have > 1 then
		seeds[woodId] = have - 1
	else
		seeds[woodId] = nil
	end
	return true
end

-- A saved pouch made safe: known woods only, whole numbers, within the caps
-- (a save edited by hand, or caps lowered since).
function ForestLogic.CleanSeeds(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "table" then
		return out
	end
	local ids: { string } = {}
	for id, n in pairs(raw) do
		if type(id) == "string" and WoodData.Get(id) and type(n) == "number" and n >= 1 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		ForestLogic.AddSeeds(out, id, raw[id])
	end
	return out
end

---------------------------------------------------------------------------
-- Grove Vitality
---------------------------------------------------------------------------

function ForestLogic.IsGrove(biomeId: string): boolean
	return groveSet[biomeId] == true
end

function ForestLogic.ClampVitality(v: number): number
	local d = ForestData.Vitality
	return math.clamp(v, d.min, d.max)
end

-- Vitality after a change (fell, plant).
function ForestLogic.ApplyVitality(v: number, delta: number): number
	return ForestLogic.ClampVitality(v + delta)
end

-- Vitality after `seconds` of drifting back toward rest.
function ForestLogic.Drift(v: number, seconds: number): number
	local d = ForestData.Vitality
	local step = d.driftPerMinute * seconds / 60
	if v > d.rest then
		return math.max(d.rest, v - step)
	elseif v < d.rest then
		return math.min(d.rest, v + step)
	end
	return v
end

-- The change felling a tree makes (planted trees cost the grove less).
function ForestLogic.FellDelta(planted: boolean): number
	local d = ForestData.Vitality
	return if planted then d.fellPlanted else d.fellWild
end

function ForestLogic.TierFor(v: number): Tier
	local tiers = ForestData.Tiers
	local pick = tiers[1]
	for _, tier in ipairs(tiers) do
		if v >= tier.min then
			pick = tier
		end
	end
	return pick
end

function ForestLogic.Tier(id: string): Tier?
	for _, tier in ipairs(ForestData.Tiers) do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

-- 1 (Thinning) ... 4 (Old Growth); 0 for an unknown id.
function ForestLogic.TierIndex(id: string): number
	for i, tier in ipairs(ForestData.Tiers) do
		if tier.id == id then
			return i
		end
	end
	return 0
end

---------------------------------------------------------------------------
-- The Hidden Grain
---------------------------------------------------------------------------

function ForestLogic.Figure(id: string?): FigureDef?
	return if id then figureById[id] else nil
end

-- What each log of a tree with this figure sells for, times its price.
function ForestLogic.Multiplier(id: string?): number
	local f = ForestLogic.Figure(id)
	return if f then f.multiplier else 1
end

-- The chance a growing tree hides a figure: 6% x the grove's tier, +4% if
-- planted, x2 in a Skyroot Bloom. `tierId` nil = outside any grove.
function ForestLogic.FigureChance(tierId: string?, planted: boolean, bloom: boolean): number
	local c = ForestData.FigureChance
	local tier = ForestLogic.Tier(tierId or ForestData.DefaultTier) or ForestLogic.Tier(ForestData.DefaultTier)
	local chance = c.base * (if tier then tier.figureMul else 1)
	if planted then
		chance += c.plantedBonus
	end
	if bloom then
		chance *= c.bloomMul
	end
	return math.clamp(chance, 0, 1)
end

-- The figures a plain roll can give (weight > 0), in ForestData order.
local function rollable(): { FigureDef }
	local out: { FigureDef } = {}
	for _, f in ipairs(ForestData.Figures) do
		if f.weight > 0 then
			table.insert(out, f)
		end
	end
	return out
end

-- Picks one of `ids` (or every rollable figure) by weight for a roll in
-- [0, 1); a Lumenwood burl turns Starfall when `starRoll` < 30%.
function ForestLogic.PickFigure(woodId: string, pickRoll: number, starRoll: number, ids: { string }?): string
	local pool: { FigureDef } = {}
	if ids then
		for _, id in ipairs(ids) do
			local f = figureById[id]
			if f and f.weight > 0 then
				table.insert(pool, f)
			end
		end
	else
		pool = rollable()
	end
	assert(#pool > 0, "[ForestLogic] no figures to pick from")
	local total = 0
	for _, f in ipairs(pool) do
		total += f.weight
	end
	local pick = pool[#pool]
	local acc = 0
	for _, f in ipairs(pool) do
		acc += f.weight / total
		if pickRoll < acc then
			pick = f
			break
		end
	end
	if pick.id == "burl" and woodId == ForestData.StarfallWood and starRoll < ForestData.StarfallShare then
		return "starfall"
	end
	return pick.id
end

-- The figure a growing tree hides, or nil: `chanceRoll` against `chance`,
-- then PickFigure.
function ForestLogic.RollFigure(
	woodId: string,
	chance: number,
	chanceRoll: number,
	pickRoll: number,
	starRoll: number
): string?
	if chanceRoll >= chance then
		return nil
	end
	return ForestLogic.PickFigure(woodId, pickRoll, starRoll)
end

-- A storm-struck tree's logs: Stormgrain, unless what it already hid is
-- worth more (a struck burl stays a burl).
function ForestLogic.StruckFigure(hidden: string?): string
	local storm = ForestData.Storm.figure
	if hidden and ForestLogic.Multiplier(hidden) > ForestLogic.Multiplier(storm) then
		return hidden
	end
	return storm
end

-- The average multiplier of a figured tree of this wood (plain rolls).
function ForestLogic.FiguredAverage(woodId: string): number
	local total, sum = 0, 0
	for _, f in ipairs(rollable()) do
		local m = f.multiplier
		if f.id == "burl" and woodId == ForestData.StarfallWood then
			local star = ForestLogic.Multiplier("starfall")
			m = m * (1 - ForestData.StarfallShare) + star * ForestData.StarfallShare
		end
		total += f.weight
		sum += f.weight * m
	end
	return if total > 0 then sum / total else 1
end

-- What figures add to a wood's income on average, as a fraction (0.06 =
-- +6%): the figure chance x the extra a figured log is worth. Lightning,
-- Elders and planted trees come on top (they're events, not the average).
function ForestLogic.FigureBonus(woodId: string, tierId: string?, planted: boolean, bloom: boolean): number
	local chance = ForestLogic.FigureChance(tierId, planted, bloom)
	return chance * (ForestLogic.FiguredAverage(woodId) - 1)
end

-- "x2", "x1.5", "x2.5" (the Field Guide, the sawmill's stamp).
function ForestLogic.MultiplierText(m: number): string
	if math.abs(m - math.floor(m + 0.5)) < 1e-6 then
		return string.format("x%d", math.floor(m + 0.5))
	end
	return string.format("x%.1f", m)
end

-- One log's value: the wood's price x the figure's multiplier.
function ForestLogic.LogValue(pricePerLog: number, figureId: string?): number
	return pricePerLog * ForestLogic.Multiplier(figureId)
end

---------------------------------------------------------------------------
-- The planter's share
---------------------------------------------------------------------------

-- The planter's cut of a tree with `logCount` logs at `pricePerLog` (base
-- value: no figure), whole dollars, at least $1.
function ForestLogic.Royalty(pricePerLog: number, logCount: number): number
	return math.max(1, math.floor(pricePerLog * logCount * ForestData.PlanterShare + 0.5))
end

---------------------------------------------------------------------------
-- Who fells a tree
---------------------------------------------------------------------------

-- The user id a felling counts for (its logs, seeds, stats): whoever
-- chopped the most of it among those `isHere`, so the last swing can't take
-- someone else's tree. A tie with the swinger goes to the swinger, other
-- ties to the lowest id.
function ForestLogic.Feller(damageBy: { [number]: number }, swingerId: number, isHere: (number) -> boolean): number
	local best, bestDealt = swingerId, damageBy[swingerId] or 0
	for userId, dealt in pairs(damageBy) do
		if userId ~= swingerId and isHere(userId) then
			local more = dealt > bestDealt + 1e-9
			local tie = math.abs(dealt - bestDealt) <= 1e-9 and best ~= swingerId and userId < best
			if more or tie then
				best, bestDealt = userId, dealt
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Elders
---------------------------------------------------------------------------

-- An Elder's size class for `def`: 1.7x size, 6x HP and 3x logs (its
-- logDelta adds 2x logsPerTree to the tree's own).
function ForestLogic.ElderSize(def: WoodData.WoodDef): TreeLogic.SizeClass
	local e = ForestData.Elder
	return {
		name = "elder",
		scale = e.scale,
		hpMul = e.hpMul,
		logDelta = (e.logMul - 1) * def.logsPerTree,
		weight = 0,
	}
end

-- The players who chopped at least 10% of a tree's HP, by user id (sorted).
function ForestLogic.Helpers(damageBy: { [number]: number }, maxHp: number): { number }
	local need = maxHp * ForestData.Elder.helperMinShare
	local out: { number } = {}
	for userId, dealt in pairs(damageBy) do
		if dealt >= need - 1e-9 then
			table.insert(out, userId)
		end
	end
	table.sort(out)
	return out
end

-- Each helper's bonus: 10% of the Elder's logs' value, whole dollars.
function ForestLogic.HelperBonus(totalValue: number): number
	return math.max(1, math.floor(totalValue * ForestData.Elder.helperShare + 0.5))
end

-- The chance a grove at vitality `v` wakes an Elder at a check: none below
-- Thriving, then rising with vitality.
function ForestLogic.ElderWakeChance(v: number): number
	local tier = ForestLogic.TierFor(v)
	if not tier.alive then
		return 0
	end
	local e = ForestData.Elder
	local lo = (ForestLogic.Tier("Thriving") :: Tier).min
	local t = math.clamp((v - lo) / (ForestData.Vitality.max - lo), 0, 1)
	return e.wakeChanceAtThriving + (e.wakeChanceAtMax - e.wakeChanceAtThriving) * t
end

export type GroveState = { biome: string, vitality: number }

-- Which grove wakes an Elder at a check, if any: one is picked weighted by
-- its wake chance (`pickRoll`), then it wakes on `wakeRoll` < its chance.
function ForestLogic.PickElderGrove(groves: { GroveState }, pickRoll: number, wakeRoll: number): string?
	local total = 0
	for _, g in ipairs(groves) do
		total += ForestLogic.ElderWakeChance(g.vitality)
	end
	if total <= 0 then
		return nil
	end
	local acc = 0
	for _, g in ipairs(groves) do
		local p = ForestLogic.ElderWakeChance(g.vitality)
		acc += p / total
		if p > 0 and pickRoll < acc then
			return if wakeRoll < p then g.biome else nil
		end
	end
	local last = groves[#groves]
	local p = ForestLogic.ElderWakeChance(last.vitality)
	return if p > 0 and wakeRoll < p then last.biome else nil
end

-- A free spot in a circle: up to `tries` candidates from `roll` (uniform
-- over the disc), the first that `accept` takes. Returns x, z or nil.
function ForestLogic.FindSpot(
	cx: number,
	cz: number,
	radius: number,
	tries: number,
	roll: () -> number,
	accept: (x: number, z: number) -> boolean
): (number?, number?)
	for _ = 1, tries do
		local angle = roll() * math.pi * 2
		local r = math.sqrt(roll()) * radius
		local x, z = cx + math.cos(angle) * r, cz + math.sin(angle) * r
		if accept(x, z) then
			return x, z
		end
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- The Skyroot Bloom
---------------------------------------------------------------------------

-- The groves' average vitality (missing ones count as at rest).
function ForestLogic.AverageVitality(vitality: { [string]: number }): number
	local sum = 0
	for _, id in ipairs(ForestData.Groves) do
		sum += vitality[id] or ForestData.Vitality.rest
	end
	return sum / #ForestData.Groves
end

-- True when the groves together are vital enough to make the Skyroot bloom.
function ForestLogic.BloomReady(vitality: { [string]: number }): boolean
	return ForestLogic.AverageVitality(vitality) >= ForestData.Bloom.threshold
end

return ForestLogic
