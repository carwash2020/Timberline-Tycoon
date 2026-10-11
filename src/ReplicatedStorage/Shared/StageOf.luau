--!strict
-- StageOf: which V1 ladder stage (S1 to S8) a player is on. Pure.
--   * Lane E's MilestoneService writes "Stage:S1".."Stage:S8" into the
--     account-wide profile.onboarding map the first time each stage is
--     reached. The highest one present wins.
--   * Before E has written any (old saves, or before E merges), the stage
--     is derived from progress the save already has: the best axe rung ever
--     owned and the biome gear (coat, boots, lantern). A veteran is never
--     read as S1 just because the keys are missing.
--   * The result is the larger of the two, clamped to 1..8.
-- Used by StoreData.PackCash (cash packs scale with the stage); Lanes F and
-- X read it too.

local StageOf = {}

StageOf.Count = 8

-- The onboarding key E writes for stage `n`.
function StageOf.Key(n: number): string
	return "Stage:S" .. tostring(n)
end

-- Highest "Stage:Sn" key set to true, or 0 when there is none.
function StageOf.FromKeys(onboarding: unknown): number
	if type(onboarding) ~= "table" then
		return 0
	end
	local best = 0
	for n = 1, StageOf.Count do
		if (onboarding :: any)[StageOf.Key(n)] == true then
			best = n
		end
	end
	return best
end

-- Stage implied by the best axe rung (ItemCatalog.AxeTier order: 1 Rusty,
-- 2 Steel, 3 Hardened, 4 Silver, 5 Cobalt, 6 Gold, 7 Obsidian, 8 Inferno,
-- 9 Starfall). S1's goal is the Steel Axe, S6's is the Obsidian Axe.
StageOf.AxeStage = { 1, 2, 2, 3, 4, 5, 6, 6, 7 }

-- Gear that only makes sense from a stage on: the coat opens the snow (S3),
-- the boots the volcano (S4), the lantern the Gloam (S5).
StageOf.GearStage = {
	InsulatedCoat = 3,
	HeatBoots = 4,
	Lantern = 5,
} :: { [string]: number }

function StageOf.FromProgress(profile: unknown): number
	if type(profile) ~= "table" then
		return 1
	end
	local p = profile :: any
	local stage = 1
	local tier = p.bestAxeTier
	if type(tier) == "number" and tier == tier then
		local rung = math.clamp(math.floor(tier), 1, #StageOf.AxeStage)
		stage = math.max(stage, StageOf.AxeStage[rung])
	end
	if type(p.gear) == "table" then
		for _, id in ipairs(p.gear) do
			local s = if type(id) == "string" then StageOf.GearStage[id] else nil
			if s then
				stage = math.max(stage, s)
			end
		end
	end
	return stage
end

-- The player's stage, 1 to 8.
function StageOf.Current(profile: unknown): number
	local keys = if type(profile) == "table" then StageOf.FromKeys((profile :: any).onboarding) else 0
	return math.clamp(math.max(keys, StageOf.FromProgress(profile)), 1, StageOf.Count)
end

-- A real player's wood income per hour at each stage ($/h), for scaling
-- cash packs. Anchored on the economy model: about $4.9k/h at S2 and
-- $115k/h at S6, the rest spaced between and past them.
StageOf.IncomePerHour = { 2_000, 4_900, 11_000, 24_000, 52_000, 114_800, 160_000, 200_000 }

function StageOf.Income(stage: number): number
	return StageOf.IncomePerHour[math.clamp(math.floor(stage), 1, StageOf.Count)]
end

-- Display names for the stages (PROPOSAL, Awaiting Connor), used by the
-- blueprint book's "Unlocks at <stage>" lines. 0 is "the start".
StageOf.Names = {
	[0] = "the start",
	[1] = "Logger",
	[2] = "Sawyer",
	[3] = "Builder",
	[4] = "Red Mesa",
	[5] = "Smith",
	[6] = "Highlands",
	[7] = "Sky Island",
	[8] = "Master Timber",
} :: { [number]: string }

function StageOf.Name(stage: number): string
	return StageOf.Names[math.clamp(math.floor(stage), 0, StageOf.Count)] or "later"
end

return StageOf
