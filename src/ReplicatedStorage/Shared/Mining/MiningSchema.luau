--!strict
-- MiningSchema: the self-contained `mining` save section (version 1).
-- Migrate is idempotent. ProfileSchema calls it once A1's hook is in;
-- until then MiningService migrates the table it keeps on the profile.

local MiningLogic = require(script.Parent.MiningLogic)
local OreData = require(script.Parent.OreData)
local PickaxeData = require(script.Parent.PickaxeData)

local MiningSchema = {}

export type StashItem = MiningLogic.StashRow

export type Mining = {
	v: number,
	picks: { [string]: boolean },
	pick: string,
	bombs: number,
	lamp: boolean,
	hardhat: boolean,
	ropes: number,
	crafted: { [string]: number },
	stash: { StashItem },
	starterGiven: boolean,
}

function MiningSchema.Template(): Mining
	return {
		v = 1,
		picks = { RustyPick = true },
		pick = "RustyPick",
		bombs = 0,
		ropes = 0,
		lamp = false,
		hardhat = false,
		crafted = {},
		stash = {},
		starterGiven = false,
	}
end

local function clampCount(n: any): number
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, MiningLogic.ChargeCap)
end

local function boolOf(v: any): boolean
	return v == true
end

function MiningSchema.Clean(raw: any): Mining
	local base = MiningSchema.Template()
	if type(raw) ~= "table" then
		return base
	end
	local picks: { [string]: boolean } = {}
	if type(raw.picks) == "table" then
		for id, on in pairs(raw.picks) do
			if type(id) == "string" and on == true and PickaxeData.Known(id) and id ~= PickaxeData.LuxId then
				picks[id] = true
			end
		end
	end
	if next(picks) == nil then
		picks.RustyPick = true
	end
	local pick = raw.pick
	-- The Lux Pickaxe is not stored in `picks` (the pass is the source of
	-- truth). Keep the id; the service refuses it when the pass is absent.
	if pick == PickaxeData.LuxId then
		pick = PickaxeData.LuxId
	elseif type(pick) ~= "string" or picks[pick] ~= true then
		pick = MiningLogic.BestFreeId(picks)
	end
	local crafted: { [string]: number } = {}
	if type(raw.crafted) == "table" then
		for id, n in pairs(raw.crafted) do
			if type(id) == "string" and type(n) == "number" and n == n and n > 0 then
				crafted[id] = math.floor(n)
			end
		end
	end
	local rows: { StashItem } = {}
	if type(raw.stash) == "table" then
		for _, row in ipairs(raw.stash) do
			if type(row) == "table" then
				local item: StashItem = {
					kind = row.kind,
					ore = row.ore,
					uid = row.uid,
					value = row.value,
					cf = row.cf,
				}
				if item.kind == "ingot" and item.ore == "Coal" then
					item.kind = "chunk"
				end
				if OreData.Known(item.ore) and MiningLogic.RowOk(item) then
					item.value = MiningLogic.SellValue(item.value)
					table.insert(rows, item)
				end
			end
		end
	end
	local packed = MiningLogic.PackStash(rows, MiningLogic.StashCap)
	return {
		v = 1,
		picks = picks,
		pick = pick,
		bombs = clampCount(raw.bombs),
		ropes = clampCount(raw.ropes),
		lamp = boolOf(raw.lamp),
		hardhat = boolOf(raw.hardhat),
		crafted = crafted,
		stash = packed.kept,
		starterGiven = boolOf(raw.starterGiven),
	}
end

-- Nil, garbage, an older shape, and a clean v1 all come back as v1.
-- A second call changes nothing.
function MiningSchema.Migrate(data: any): Mining
	if type(data) == "table" and data.v == 1 then
		return MiningSchema.Clean(data)
	end
	return MiningSchema.Clean(data)
end

return MiningSchema
