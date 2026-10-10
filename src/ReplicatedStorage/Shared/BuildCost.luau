--!strict
-- BuildCost: everything one placed piece costs, in one shape. Pure.
-- cash is the placing fee (PlotData.Price), woodUnits the plank units the
-- fill takes, slabUnits the sandstone slabs, ingots the ingots by ore id.
-- Existing pieces keep their numbers exactly (a spec pins all 24 kit pieces).

local PieceSize = require(script.Parent.PieceSize)
local PlotData = require(script.Parent.PlotData)

export type Cost = {
	cash: number,
	woodUnits: number,
	slabUnits: number,
	ingots: { [string]: number },
}

-- What a placed kit piece has taken so far. `units` is plank units (u³),
-- `slabs` sandstone slabs, `ingots` ingots by ore id. The last two are
-- left off until the first one is dropped in, so old saves and wood-only
-- pieces keep the small { units = n } shape.
export type Fill = {
	units: number,
	slabs: number?,
	ingots: { [string]: number }?,
}

-- What finishing one placed piece takes, with the resize applied to wood.
export type Need = {
	units: number,
	slabs: number,
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

---------------------------------------------------------------------------
-- Filling: planks, slabs and ingots into a placed ghost. Pure. The server
-- (PlotFill) takes one part at a time and calls these for the numbers.
---------------------------------------------------------------------------

local function whole(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n < 0 then
		return 0
	end
	return n
end

-- What this placed piece needs in all. Wood follows the resize (PieceSize);
-- slabs and ingots are fixed per piece.
function BuildCost.Need(bp: PlotData.Blueprint, item: PieceSize.Sized?): Need
	local cost = BuildCost.Of(bp)
	return {
		units = PieceSize.Units(bp, item),
		slabs = cost.slabUnits,
		ingots = cost.ingots,
	}
end

function BuildCost.NewFill(_bp: PlotData.Blueprint): Fill
	return { units = 0 }
end

function BuildCost.CloneFill(fill: Fill?): Fill?
	if fill == nil then
		return nil
	end
	local out: Fill = { units = fill.units }
	if fill.slabs ~= nil and fill.slabs > 0 then
		out.slabs = fill.slabs
	end
	if fill.ingots ~= nil and next(fill.ingots) ~= nil then
		out.ingots = table.clone(fill.ingots)
	end
	return out
end

-- How many parts have gone into a ghost: planks' units plus slabs plus
-- ingots. Zero means it is still empty.
function BuildCost.Taken(fill: Fill?): number
	if fill == nil then
		return 0
	end
	local n = whole(fill.units) + whole(fill.slabs)
	if fill.ingots ~= nil then
		for _, count in pairs(fill.ingots) do
			n += whole(count)
		end
	end
	return n
end

-- The same count for a placed piece, finished or not (a finished piece has
-- no fill table and holds all of its cost).
function BuildCost.TakenOf(
	bp: PlotData.Blueprint,
	item: { fill: Fill?, len: number?, lenX: number?, lenZ: number? }
): number
	local held = BuildCost.Held(bp, item)
	local n = held.units + held.slabs
	for _, count in pairs(held.ingots) do
		n += count
	end
	return n
end

-- Has anything at all gone into the piece? A ghost with nothing in it can
-- still be moved, resized and sold for the whole fee.
function BuildCost.IsEmpty(fill: Fill?): boolean
	if fill == nil then
		return false
	end
	if whole(fill.units) > 0 or whole(fill.slabs) > 0 then
		return false
	end
	if fill.ingots ~= nil then
		for _, n in pairs(fill.ingots) do
			if whole(n) > 0 then
				return false
			end
		end
	end
	return true
end

-- What is still missing. All zero means the piece is built.
function BuildCost.Missing(
	bp: PlotData.Blueprint,
	item: { fill: Fill?, len: number?, lenX: number?, lenZ: number? }
): Need
	local need = BuildCost.Need(bp, item)
	local fill = item.fill
	if fill == nil then
		return { units = 0, slabs = 0, ingots = {} }
	end
	local ingots: { [string]: number } = {}
	for ore, n in pairs(need.ingots) do
		local have = if fill.ingots then whole(fill.ingots[ore]) else 0
		if have < n then
			ingots[ore] = n - have
		end
	end
	return {
		units = math.max(0, need.units - whole(fill.units)),
		slabs = math.max(0, need.slabs - whole(fill.slabs)),
		ingots = ingots,
	}
end

function BuildCost.IsComplete(
	bp: PlotData.Blueprint,
	item: { fill: Fill?, len: number?, lenX: number?, lenZ: number? }
): boolean
	if bp.kit ~= true or item.fill == nil then
		return true
	end
	local missing = BuildCost.Missing(bp, item)
	return missing.units <= 1e-9 and missing.slabs <= 1e-9 and next(missing.ingots) == nil
end

-- What the piece holds right now (a finished piece with no fill table
-- holds all of its cost). Used by undo and by the sell plan.
function BuildCost.Held(bp: PlotData.Blueprint, item: { fill: Fill?, len: number?, lenX: number?, lenZ: number? }): Need
	local fill = item.fill
	if fill == nil then
		return BuildCost.Need(bp, item)
	end
	local ingots: { [string]: number } = {}
	if fill.ingots ~= nil then
		for ore, n in pairs(fill.ingots) do
			if whole(n) > 0 then
				ingots[ore] = n
			end
		end
	end
	return { units = whole(fill.units), slabs = whole(fill.slabs), ingots = ingots }
end

-- A saved fill made safe: whole numbers inside what the piece needs, and
-- nil once the piece is complete (a finished piece keeps no fill). Never
-- returns a fill for a piece that is not a kit piece.
function BuildCost.CleanFill(
	bp: PlotData.Blueprint,
	item: { fill: any, len: number?, lenX: number?, lenZ: number? }
): Fill?
	local raw = item.fill
	if type(raw) ~= "table" then
		return nil
	end
	local need = BuildCost.Need(bp, item)
	local units = (raw :: any).units
	if type(units) ~= "number" or units ~= units or units < 0 then
		return nil
	end
	local fill: Fill = { units = math.min(units, need.units) }
	local slabs = whole((raw :: any).slabs)
	if need.slabs > 0 and slabs > 0 then
		fill.slabs = math.min(math.floor(slabs), need.slabs)
	end
	local rawIngots = (raw :: any).ingots
	if type(rawIngots) == "table" then
		local ingots: { [string]: number } = {}
		for ore, want in pairs(need.ingots) do
			local have = whole((rawIngots :: any)[ore])
			if have > 0 then
				ingots[ore] = math.min(math.floor(have), want)
			end
		end
		if next(ingots) ~= nil then
			fill.ingots = ingots
		end
	end
	if BuildCost.IsComplete(bp, { fill = fill, len = item.len, lenX = item.lenX, lenZ = item.lenZ }) then
		return nil
	end
	return fill
end

-- Short player text for what is still missing, one line, no jargon.
function BuildCost.MissingText(missing: Need): string
	local parts: { string } = {}
	if missing.units > 0 then
		table.insert(parts, "planks")
	end
	if missing.slabs > 0 then
		table.insert(
			parts,
			string.format("%d sandstone slab%s", math.ceil(missing.slabs), if missing.slabs <= 1 then "" else "s")
		)
	end
	local ores: { string } = {}
	for ore in pairs(missing.ingots) do
		table.insert(ores, ore)
	end
	table.sort(ores)
	for _, ore in ipairs(ores) do
		local n = missing.ingots[ore]
		table.insert(parts, string.format("%d %s ingot%s", n, ore, if n == 1 then "" else "s"))
	end
	if #parts == 0 then
		return "Built"
	end
	return "Needs " .. table.concat(parts, ", ")
end

-- Boxes (parts) in one placed piece. Resizing stretches boxes, it does not
-- add them, so the count is the blueprint's.
function BuildCost.PartsOf(bp: PlotData.Blueprint): number
	if bp.kit ~= true then
		return 0
	end
	return math.max(1, #bp.boxes)
end

-- Total kit parts a plot's placed list holds. `lookup` finds a blueprint
-- (PlotLogic.Blueprint); `skipUid` leaves one piece out (a move).
function BuildCost.KitParts(
	placed: { { uid: string, blueprintId: string } },
	lookup: (string) -> PlotData.Blueprint?,
	skipUid: string?
): number
	local n = 0
	for _, item in ipairs(placed) do
		if item.uid ~= skipUid then
			local bp = lookup(item.blueprintId)
			if bp then
				n += BuildCost.PartsOf(bp)
			end
		end
	end
	return n
end

BuildCost.PartCapText = "Your plot holds %d kit parts at most"

-- May one more piece with `adding` parts join a plot already holding
-- `current`? Only new placements ask: nothing already built is touched.
function BuildCost.PartsFit(current: number, adding: number): boolean
	return current + adding <= BuildCost.MaxKitParts
end

return BuildCost
