--!strict
-- BuildCost: everything one placed piece costs, in one shape. Pure.
-- cash is the placing fee (PlotData.Price), woodUnits the plank units the
-- fill takes, slabUnits the sandstone slabs, ingots the ingots by ore id.
-- Existing pieces keep their numbers exactly (a spec pins all 24 kit pieces).

local PlotData = require(script.Parent.PlotData)

export type Cost = {
	cash: number,
	woodUnits: number,
	slabUnits: number,
	ingots: { [string]: number },
}

local BuildCost = {}

-- Box count ceiling for a full plot: MaxKit pieces × the most boxes any kit
-- piece has stays at or under this (Builder: at most 1,200 kit parts).
BuildCost.MaxKitParts = 1200

local function count(n: unknown): number
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		return 0
	end
	return n
end

function BuildCost.Of(bp: PlotData.Blueprint): Cost
	local ingots: { [string]: number } = {}
	if type(bp.ingots) == "table" then
		for ore, n in pairs(bp.ingots) do
			if type(ore) == "string" and count(n) > 0 then
				ingots[ore] = n
			end
		end
	end
	return {
		cash = PlotData.Price(bp),
		woodUnits = count(bp.woodUnits),
		slabUnits = count(bp.slabUnits),
		ingots = ingots,
	}
end

-- Whether anything beyond the cash fee and planks is needed.
function BuildCost.NeedsSlabsOrIngots(cost: Cost): boolean
	return cost.slabUnits > 0 or next(cost.ingots) ~= nil
end

-- Player text for what finishing a piece takes: one price, no units jargon.
function BuildCost.Text(cost: Cost): string
	local parts: { string } = {}
	if cost.woodUnits > 0 then
		table.insert(parts, string.format("%d planks' worth of one wood", cost.woodUnits))
	end
	if cost.slabUnits > 0 then
		table.insert(
			parts,
			string.format("%d sandstone slab%s", cost.slabUnits, if cost.slabUnits == 1 then "" else "s")
		)
	end
	local ores: { string } = {}
	for ore in pairs(cost.ingots) do
		table.insert(ores, ore)
	end
	table.sort(ores)
	for _, ore in ipairs(ores) do
		local n = cost.ingots[ore]
		table.insert(parts, string.format("%d %s ingot%s", n, ore, if n == 1 then "" else "s"))
	end
	if #parts == 0 then
		return "Nothing to fill"
	end
	return table.concat(parts, ", ")
end

-- The most boxes a full plot of kit pieces could hold: MaxKit × the
-- largest box count among kit pieces.
function BuildCost.WorstKitParts(): number
	local most = 0
	for _, bp in ipairs(PlotData.Blueprints) do
		if bp.kit == true then
			most = math.max(most, #bp.boxes)
		end
	end
	return PlotData.MaxKit * most
end

return BuildCost
