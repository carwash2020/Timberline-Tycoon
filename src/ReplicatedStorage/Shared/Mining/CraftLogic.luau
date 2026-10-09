--!strict
-- CraftLogic: can-craft, one transaction, log rules. No yields, no
-- instances. The service destroys the log through WoodService from the
-- step list this returns, in the same block as the ingots.

local CraftData = require(script.Parent.CraftData)
local MiningLogic = require(script.Parent.MiningLogic)

local CraftLogic = {}

export type Bag = { [string]: number }

export type Stock = {
	ingots: Bag,
	chunks: Bag,
}

export type LogFacts = {
	uid: string,
	owner: number,
	volume: number,
	welded: boolean,
}

export type Step = {
	kind: string, -- "ingots" | "chunks" | "log"
	ore: string?,
	n: number?,
	uid: string?,
}

export type Plan = {
	ok: boolean,
	reason: string?,
	steps: { Step },
	gives: CraftData.Gives?,
}

CraftLogic.TruckBeds = { BedFloor = true, TrailerBed = true, Bed = true }

function CraftLogic.IsTruckWeld(partName: string): boolean
	return CraftLogic.TruckBeds[partName] == true
end

-- Owner 0 is unowned. Size is the Volume attribute, never a part's size.
function CraftLogic.LogOk(log: LogFacts, userId: number): boolean
	if log.welded then
		return false
	end
	if type(log.owner) ~= "number" or log.owner == 0 or log.owner ~= userId then
		return false
	end
	if type(log.volume) ~= "number" or log.volume < CraftData.LogVolume then
		return false
	end
	return true
end

local function have(bag: Bag, ore: string): number
	return bag[ore] or 0
end

function CraftLogic.Counts(recipe: CraftData.Recipe, stock: Stock, log: LogFacts?, userId: number): { NeedCount }
	local rows = {}
	for _, need in ipairs(recipe.needs) do
		if need.kind == "log" then
			local ok = log ~= nil and CraftLogic.LogOk(log, userId)
			table.insert(rows, {
				kind = "log",
				label = "Log",
				have = if ok then 1 else 0,
				need = 1,
			})
		else
			local ore = need.ore or ""
			local bag = if need.kind == "ingot" then stock.ingots else stock.chunks
			table.insert(rows, {
				kind = need.kind,
				ore = ore,
				label = ore,
				have = have(bag, ore),
				need = need.n or 0,
			})
		end
	end
	return rows
end

export type NeedCount = {
	kind: string,
	ore: string?,
	label: string,
	have: number,
	need: number,
}

-- stillLog: the log was still free at the commit (a grab mid-craft
-- passes false and the ingots stay).
function CraftLogic.Commit(recipeId: string, stock: Stock, log: LogFacts?, userId: number, stillLog: boolean): Plan
	local recipe = CraftData.Get(recipeId)
	if recipe == nil then
		return { ok = false, reason = "unknown", steps = {} }
	end
	if not recipe.enabled then
		return { ok = false, reason = "soon", steps = {} }
	end
	local steps: { Step } = {}
	for _, need in ipairs(recipe.needs) do
		if need.kind == "log" then
			if log == nil or not stillLog or not CraftLogic.LogOk(log, userId) then
				return { ok = false, reason = "log", steps = {} }
			end
		else
			local ore = need.ore or ""
			local bag = if need.kind == "ingot" then stock.ingots else stock.chunks
			if have(bag, ore) < (need.n or 0) then
				return { ok = false, reason = "short", steps = {} }
			end
		end
	end
	for _, need in ipairs(recipe.needs) do
		if need.kind == "ingot" or need.kind == "chunk" then
			local step: Step = { kind = need.kind, ore = need.ore, n = need.n }
			table.insert(steps, step)
		end
	end
	if log ~= nil then
		for _, need in ipairs(recipe.needs) do
			if need.kind == "log" then
				table.insert(steps, { kind = "log", uid = log.uid })
			end
		end
	end
	return { ok = true, steps = steps, gives = recipe.gives }
end

export type MiningBits = {
	bombs: number,
	ropes: number,
	lamp: boolean,
	hardhat: boolean,
	crafted: { [string]: number },
}

-- Applies a successful plan. Charges clamp at 0..99. Returns the next
-- bits (the input table is not mutated).
function CraftLogic.Grant(bits: MiningBits, gives: CraftData.Gives, recipeId: string): MiningBits
	local crafted = table.clone(bits.crafted)
	crafted[recipeId] = (crafted[recipeId] or 0) + 1
	local bombs = bits.bombs + (gives.bombs or 0)
	local ropes = bits.ropes + (gives.ropes or 0)
	return {
		bombs = math.clamp(bombs, 0, MiningLogic.ChargeCap),
		ropes = math.clamp(ropes, 0, MiningLogic.ChargeCap),
		lamp = bits.lamp or gives.lamp == true,
		hardhat = bits.hardhat or gives.hardhat == true,
		crafted = crafted,
	}
end

return CraftLogic
