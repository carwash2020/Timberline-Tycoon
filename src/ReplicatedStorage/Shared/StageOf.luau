--!strict
-- StageOf: which V1 stage (S0 to S8) a player has reached. Pure.
--
-- Lane E stores a stage event as a key in the account-wide `onboarding` table:
-- "Stage:S1" .. "Stage:S8" (the same pattern as "Tutorial:<id>"). Until those
-- keys exist (Lane E merges after Lane F), StageOf falls back to progress,
-- worked out from lifetime cash earned. The moment any stage key is present,
-- the keys win and the fallback is ignored, so Lane E's events are the truth
-- once they exist. BlueprintBook.UnlockStage (what each plan needs) is wired
-- to StageOf.Current here, so a stage unlock teaches the plan.

local StageOf = {}

StageOf.Max = 8

-- Display names (PROPOSAL, Awaiting Connor): the line a locked plan shows.
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

-- Fallback until Lane E's keys exist (PROPOSAL, Awaiting Connor): a stage is
-- reached when lifetime cash earned passes its line. Stage 1 is claiming a
-- plot. The lines are lowest-first.
StageOf.EarnedLines = { 100, 1000, 5000, 25000, 100000, 400000, 1000000, 2000000 } :: { number }

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- The highest "Stage:Sx" key set, and whether any key exists at all.
function StageOf.FromKeys(onboarding: unknown): (number, boolean)
	local best, any = 0, false
	if type(onboarding) ~= "table" then
		return 0, false
	end
	for n = 1, StageOf.Max do
		if (onboarding :: { [string]: any })["Stage:S" .. n] == true then
			any = true
			best = math.max(best, n)
		end
	end
	return best, any
end

-- Progress when there are no stage keys: the plot claimed is stage 1, then
-- lifetime cash earned against EarnedLines.
function StageOf.Fallback(profile: unknown): number
	if type(profile) ~= "table" then
		return 0
	end
	local p = profile :: { [string]: any }
	local stage = 0
	local plot = p.plot
	if type(plot) == "table" and plot.claimed == true then
		stage = 1
	end
	local earned = if finite(p.totalEarned) then p.totalEarned :: number else 0
	for n, line in ipairs(StageOf.EarnedLines) do
		if earned >= line then
			stage = math.max(stage, n)
		end
	end
	return math.min(stage, StageOf.Max)
end

-- The stage the profile has reached: Lane E's keys when any exist, else
-- progress. Never below what the keys say.
function StageOf.Current(profile: unknown): number
	if type(profile) ~= "table" then
		return 0
	end
	local keyed, any = StageOf.FromKeys((profile :: any).onboarding)
	if any then
		return keyed
	end
	return StageOf.Fallback(profile)
end

function StageOf.Name(stage: number): string
	return StageOf.Names[math.clamp(math.floor(stage), 0, StageOf.Max)] or "later"
end

return StageOf
