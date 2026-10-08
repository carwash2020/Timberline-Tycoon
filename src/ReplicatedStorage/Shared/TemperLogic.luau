--!strict
-- TemperLogic: an axe's temper (Keen, Heavy, Prosperous), grades I to III.
-- Prosperous is the only prefix that changes a sale. The server stamps that
-- multiplier on a piece as `t` when the tree is felled (SellLogic.Temper).
-- A save that names an unknown prefix, or a grade that is not I, II or III,
-- drops that axe's temper (ProfileSchema.Migrate).

local SellLogic = require(script.Parent.SellLogic)

local TemperLogic = {}

TemperLogic.Prefixes = { "Keen", "Heavy", "Prosperous" }

local KNOWN = { Keen = true, Heavy = true, Prosperous = true }

export type Record = { prefix: string, tier: number }

function TemperLogic.Known(prefix: string): boolean
	return KNOWN[prefix] == true
end

-- The sale multiplier a temper record stamps on wood felled with that axe.
-- Anything that is not Prosperous I, II or III is 1.
function TemperLogic.Multiplier(rec: any): number
	if type(rec) ~= "table" or rec.prefix ~= "Prosperous" then
		return 1
	end
	local tier = rec.tier
	if tier == 1 then
		return 1.04
	elseif tier == 2 then
		return 1.07
	elseif tier == 3 then
		return 1.10
	end
	return 1
end

-- Axe tempers worth keeping. An unknown prefix, a missing grade, or a grade
-- past III (a skip) is dropped. Running this twice changes nothing.
function TemperLogic.Clean(raw: any): { [string]: Record }
	local out: { [string]: Record } = {}
	if type(raw) ~= "table" then
		return out
	end
	for uid, rec in pairs(raw) do
		if type(uid) == "string" and uid ~= "" and type(rec) == "table" then
			local prefix = rec.prefix
			local tier = rec.tier
			if type(prefix) == "string" and KNOWN[prefix] == true and (tier == 1 or tier == 2 or tier == 3) then
				out[uid] = { prefix = prefix, tier = tier }
			end
		end
	end
	return out
end

-- The `t` a save should store: a real Prosperous grade, or nil for 1.
function TemperLogic.Stored(value: number?): number?
	local t = SellLogic.Temper(value)
	return if t > 1 then t else nil
end

return TemperLogic
