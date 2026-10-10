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

-- Designer findings (Oct 8, approved). Grade I, II, III by index.
TemperLogic.Effects = {
	Keen = { 0.92, 0.85, 0.78 }, -- swing cooldown multiplier (-8, -15, -22%)
	Heavy = { 1.10, 1.20, 1.30 }, -- damage multiplier
	Prosperous = { 1.04, 1.07, 1.10 }, -- sale multiplier (`t`), under BonusCap
}

export type Cost = { cash: number, shards: number, woodId: string, u3: number }

-- What a grade costs at the anvil. Fixed: no random rolls, no Robux.
TemperLogic.Costs = {
	{ cash = 20000, shards = 6, woodId = "phantomwood", u3 = 30 },
	{ cash = 50000, shards = 10, woodId = "lumenwood", u3 = 40 },
	{ cash = 120000, shards = 16, woodId = "lumenwood", u3 = 80 },
} :: { Cost }

TemperLogic.GradeNames = { "I", "II", "III" }

-- Axes that can't be tempered: the Lux Axe is a Robux pass item.
TemperLogic.Untemperable = { LuxAxe = true }

function TemperLogic.CanTemperAxe(axeId: string): boolean
	return TemperLogic.Untemperable[axeId] ~= true
end

-- The grade this temper would make: a new family starts at I (it replaces
-- the old one), the same family goes up one grade. Nil past III, for an
-- unknown prefix, or for an axe that can't be tempered.
function TemperLogic.NextTier(axeId: string, current: Record?, prefix: string): number?
	if not KNOWN[prefix] or not TemperLogic.CanTemperAxe(axeId) then
		return nil
	end
	if current == nil or current.prefix ~= prefix then
		return 1
	end
	local tier = current.tier
	if tier == 1 or tier == 2 then
		return tier + 1
	end
	return nil
end

function TemperLogic.CostFor(tier: number): Cost?
	return TemperLogic.Costs[tier]
end

-- "Keen II" for display; "" for none.
function TemperLogic.Label(rec: Record?): string
	if rec == nil or not KNOWN[rec.prefix] then
		return ""
	end
	local grade = TemperLogic.GradeNames[rec.tier]
	return if grade then rec.prefix .. " " .. grade else ""
end

-- What the grade does, in words: "Swings 15% faster".
function TemperLogic.EffectText(prefix: string, tier: number): string
	local list = TemperLogic.Effects[prefix]
	local m = if list then list[tier] else nil
	if m == nil then
		return ""
	end
	local pct = math.floor(math.abs(m - 1) * 100 + 0.5)
	if prefix == "Keen" then
		return string.format("Swings %d%% faster", pct)
	elseif prefix == "Heavy" then
		return string.format("Hits %d%% harder", pct)
	end
	return string.format("Wood it fells sells for %d%% more", pct)
end

-- The factor a temper puts on the swing cooldown: Keen I, II, III is 0.92,
-- 0.85, 0.78 (Effects.Keen); anything else, or no temper, is 1. The client
-- reads the tool's TemperPrefix / TemperTier attributes (AxeService stamps
-- them) so its own swing pacing matches the cooldown Apply gives the server.
function TemperLogic.CooldownMultiplier(prefix: any, tier: any): number
	if prefix ~= "Keen" or type(tier) ~= "number" then
		return 1
	end
	local m = TemperLogic.Effects.Keen[tier]
	return if type(m) == "number" then m else 1
end

-- A copy of `axe` with the temper's swing effects (v2 damage, cooldown and
-- each per-wood row). Prosperous changes no swing; it is stamped on the
-- wood instead (Multiplier). The catalog entry is never written.
function TemperLogic.Apply(axe: any, rec: any): any
	if type(axe) ~= "table" or type(rec) ~= "table" or not KNOWN[rec.prefix] then
		return axe
	end
	local list = TemperLogic.Effects[rec.prefix]
	local m = list[rec.tier]
	if m == nil or rec.prefix == "Prosperous" or type(axe.v2) ~= "table" then
		return axe
	end
	local key = if rec.prefix == "Keen" then "cooldown" else "damage"
	local copy = table.clone(axe)
	local v2 = table.clone(axe.v2)
	local base = v2[key]
	if type(base) == "number" then
		v2[key] = base * (m :: number)
	end
	if type(v2.vs) == "table" then
		local vs = {}
		for woodId, row in pairs(v2.vs) do
			local r = table.clone(row)
			local value = r[key]
			if type(value) == "number" then
				r[key] = value * (m :: number)
			end
			vs[woodId] = r
		end
		v2.vs = vs
	end
	copy.v2 = v2
	copy.temper = { prefix = rec.prefix, tier = rec.tier }
	return copy
end

-- The `t` a save should store: a real Prosperous grade, or nil for 1.
function TemperLogic.Stored(value: number?): number?
	local t = SellLogic.Temper(value)
	return if t > 1 then t else nil
end

return TemperLogic
