--!strict
-- GrowLogic: the life of a v2 section tree's site (V2_PLAN.md §3h). Pure,
-- so SectionTrees, the specs and tools/preview agree on every number:
--   * Site(pos, seed?): a site's look, from its spot, as TreeService rolled
--     it (the same seed, size class and turn): the seed, the size class's
--     name and its v2 scale (TreeGen.SizeScales), and the yaw.
--   * StageAt(age, growSec): how grown a tree is `age` seconds after it
--     sprouted: 0 (a sapling, not cuttable) for the first 1/GrowStages of
--     growSec, then 0.25, 0.5, 0.75 and 1 (mature) at each quarter.
--     StageStartsAt is when a stage begins.
--   * Lifespan(def, seed, growth): how long a tree lives (the wood's
--     lifespan, multiples of growSec), a new roll for each growth.
--   * PhaseAt(age, life): "alive", "preDead" (its leaves have dropped, from
--     PreDeadAt of its life) or "dead".
--   * BootAge(def, seed, life): how old a site's tree is when the server
--     starts: MatureShare of them mature (somewhere in the first part of
--     their mature life, so they don't all die at once), the rest at a
--     random growth stage (never a sapling).
--   * TakeDue(due, now, n): the growth tick's batch: at most n of the
--     trees whose next change is due, the most overdue first.
--   * BootTree(def, pos): a site's tree as the server plants it at boot
--     (Site, its mature skeleton, its lifespan, its boot age and stage):
--     what SectionTrees.SpawnTree builds with { boot = true }, so the
--     preview's v2 world (tools/preview) draws the same forest.

local ForestData = require(script.Parent.ForestData)
local GameConfig = require(script.Parent.GameConfig)
local Kit = require(script.Parent.Art.Kit)
local TreeGen = require(script.Parent.TreeGen)
local TreeLogic = require(script.Parent.TreeLogic)
local WoodData = require(script.Parent.WoodData)

type WoodDef = WoodData.WoodDef

local GrowLogic = {}

GrowLogic.MatureShare = 0.85 -- of sites mature when the server starts
-- A mature tree at boot is somewhere in this much of the time between
-- growing up and its leaves dropping (so boot deaths are spread out).
GrowLogic.BootMatureSpread = 0.7
GrowLogic.SaplingGrowth = 0.5 -- how grown the sapling model is drawn (TreeArt.GrowingSapling)
GrowLogic.DefaultGrowSec = 600 -- a wood without v2 data
GrowLogic.DefaultLifespan = { 3, 6 }

export type Phase = "alive" | "preDead" | "dead"

-- The look of the tree on a site at `pos` (or with `seed`): the seed,
-- its size class's name, its v2 scale and its yaw (radians). The same
-- draws as TreeService.SpawnTree (seed + 101 the size, seed + 202 the
-- turn), so a site keeps its size class and facing across the loops.
function GrowLogic.Site(pos: Vector3, seed: number?): (number, string, number, number)
	local s = seed or Kit.seedAt(pos.X, pos.Z)
	local size = TreeLogic.SizeFor(Kit.rng(s + 101):next())
	local yaw = Kit.rng(s + 202):range(0, math.pi * 2)
	return s, size.name, TreeGen.ScaleFor(size.name), yaw
end

-- The wood's growSec (sapling to mature), or the default.
function GrowLogic.GrowSec(def: WoodDef): number
	local v2 = def.v2
	return if v2 and v2.growSec > 0 then v2.growSec else GrowLogic.DefaultGrowSec
end

-- How grown a tree is `age` seconds after it sprouted (see the header).
function GrowLogic.StageAt(age: number, growSec: number, stages: number?): number
	local n = stages or GameConfig.GrowStages
	if growSec <= 0 or n <= 0 then
		return 1
	end
	local k = math.floor(age / (growSec / n) + 1e-9)
	return math.clamp(k, 0, n) / n
end

-- Seconds after sprouting that `stage` (0, 0.25 ... 1) begins.
function GrowLogic.StageStartsAt(stage: number, growSec: number): number
	return math.clamp(stage, 0, 1) * growSec
end

-- The next stage after `stage` (nil once mature).
function GrowLogic.NextStage(stage: number, stages: number?): number?
	local n = stages or GameConfig.GrowStages
	if stage >= 1 - 1e-9 then
		return nil
	end
	local k = math.floor(stage * n + 1e-9) + 1
	return math.min(1, k / n)
end

-- How long a tree of `def` lives, in seconds: its lifespan (multiples of
-- growSec) rolled from the site's seed and how many times it has grown.
function GrowLogic.Lifespan(def: WoodDef, seed: number, growth: number): number
	local v2 = def.v2
	local span = if v2 then v2.lifespan else GrowLogic.DefaultLifespan
	local lo, hi = span[1] or 3, span[2] or span[1] or 6
	local rng = Kit.rng(seed * 31 + growth * 7 + 404)
	return GrowLogic.GrowSec(def) * rng:range(math.min(lo, hi), math.max(lo, hi))
end

-- Where a tree `age` seconds old with `life` seconds to live is.
function GrowLogic.PhaseAt(age: number, life: number, preDeadAt: number?): Phase
	if age >= life then
		return "dead"
	elseif age >= life * (preDeadAt or GameConfig.PreDeadAt) then
		return "preDead"
	end
	return "alive"
end

-- The site's tree's age when the server starts (see the header).
function GrowLogic.BootAge(def: WoodDef, seed: number, life: number): number
	local growSec = GrowLogic.GrowSec(def)
	local rng = Kit.rng(seed + 303)
	local n = GameConfig.GrowStages
	if rng:next() >= GrowLogic.MatureShare then
		-- Young: one of the stages between the sapling and mature.
		local k = rng:int(1, math.max(1, n - 1))
		return (k + rng:range(0.05, 0.95)) * growSec / n
	end
	local room = math.max(0, life * GameConfig.PreDeadAt - growSec)
	return growSec + rng:next() * room * GrowLogic.BootMatureSpread
end

export type Boot = {
	seed: number,
	sizeName: string,
	scale: number,
	yaw: number,
	skel: TreeGen.Skeleton, -- the mature tree
	life: number,
	age: number,
	stage: number,
}

-- A site's tree at server start (see the header). `seed` and `elder` as
-- SectionTrees.SpawnTree takes them.
function GrowLogic.BootTree(def: WoodDef, pos: Vector3, seed: number?, elder: boolean?): Boot
	local s, sizeName, scale, yaw = GrowLogic.Site(pos, seed)
	if elder then
		sizeName, scale = "elder", ForestData.Elder.scale
	end
	local skel = TreeGen.Skeleton(def.id, s, scale, { elder = elder == true })
	local life = GrowLogic.Lifespan(def, s, 0)
	local age = if elder then GrowLogic.GrowSec(def) else GrowLogic.BootAge(def, s, life)
	return {
		seed = s,
		sizeName = sizeName,
		scale = scale,
		yaw = yaw,
		skel = skel,
		life = life,
		age = age,
		stage = GrowLogic.StageAt(age, GrowLogic.GrowSec(def)),
	}
end

export type Due = { uid: string, at: number }

-- The growth tick's batch: up to `n` uids whose change is due by `now`,
-- the most overdue first (ties by uid, so the order is stable).
function GrowLogic.TakeDue(due: { Due }, now: number, n: number): { string }
	local ready: { Due } = {}
	for _, d in ipairs(due) do
		if d.at <= now then
			table.insert(ready, d)
		end
	end
	table.sort(ready, function(a: Due, b: Due): boolean
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.uid < b.uid
	end)
	local out: { string } = {}
	for i = 1, math.min(n, #ready) do
		out[i] = ready[i].uid
	end
	return out
end

return GrowLogic
