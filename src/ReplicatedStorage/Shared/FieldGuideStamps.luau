--!strict
-- FieldGuideStamps: Rosa's Field Guide stamps. The first time you SELL a log
-- of a wood, that wood is stamped (profile.guideStamps["<woodId>"]). When every
-- wood of a biome is stamped, the biome's page is stamped too
-- (guideStamps["page:<biome>"]). Each stamp pays a small cash reward and each
-- page a bigger one, through EconomyService (FieldGuideService.Stamp).
-- PROPOSAL (awaiting Connor, per the Designer's rule when there is no finding):
-- a stamp is 2 minutes of the stage's income, a page 6 minutes (StageOf.Income
-- is dollars an hour), rounded to $5. Pure; the server and the Field Guide
-- screen share it.

local StageOf = require(script.Parent.StageOf)
local WoodData = require(script.Parent.WoodData)

local FieldGuideStamps = {}

FieldGuideStamps.StampMinutes = 2
FieldGuideStamps.PageMinutes = 6
FieldGuideStamps.PagePrefix = "page:"

local function reward(stage: number, minutes: number): number
	return math.max(5, math.floor(StageOf.Income(stage) * minutes / 60 / 5 + 0.5) * 5)
end

function FieldGuideStamps.StampReward(stage: number): number
	return reward(stage, FieldGuideStamps.StampMinutes)
end

function FieldGuideStamps.PageReward(stage: number): number
	return reward(stage, FieldGuideStamps.PageMinutes)
end

-- The woods a biome's page holds (every WoodData wood that grows there).
function FieldGuideStamps.PageWoods(biome: string): { string }
	local out: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		if wood.biome == biome then
			table.insert(out, wood.id)
		end
	end
	return out
end

-- Wood ids in `sold` (a table keyed by wood id with a positive count) that
-- have no stamp yet, in WoodData order.
function FieldGuideStamps.NewStamps(stamps: { [string]: boolean }, sold: { [string]: number }): { string }
	local out: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		local n = sold[wood.id]
		if type(n) == "number" and n > 0 and stamps[wood.id] ~= true then
			table.insert(out, wood.id)
		end
	end
	return out
end

-- Biome pages that are now complete (every wood stamped) and not stamped yet.
function FieldGuideStamps.NewPages(stamps: { [string]: boolean }): { string }
	local biomes: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, wood in ipairs(WoodData.All()) do
		if not seen[wood.biome] then
			seen[wood.biome] = true
			table.insert(biomes, wood.biome)
		end
	end
	local out: { string } = {}
	for _, biome in ipairs(biomes) do
		if stamps[FieldGuideStamps.PagePrefix .. biome] ~= true then
			local complete = true
			for _, id in ipairs(FieldGuideStamps.PageWoods(biome)) do
				if stamps[id] ~= true then
					complete = false
					break
				end
			end
			if complete then
				table.insert(out, biome)
			end
		end
	end
	return out
end

-- (woods stamped, woods in all).
function FieldGuideStamps.Count(stamps: { [string]: boolean }): (number, number)
	local n, total = 0, 0
	for _, wood in ipairs(WoodData.All()) do
		total += 1
		if stamps[wood.id] == true then
			n += 1
		end
	end
	return n, total
end

-- The Field Guide header's second line: "Stamps 3 of 12. Secrets 2 of 5."
function FieldGuideStamps.Line(stamped: number, woods: number, secretsFound: number, secretsTotal: number): string
	return string.format("Stamps %d of %d. Secrets %d of %d.", stamped, woods, secretsFound, secretsTotal)
end

return FieldGuideStamps
