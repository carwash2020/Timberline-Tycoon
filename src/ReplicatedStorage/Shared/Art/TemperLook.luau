--!strict
-- TemperLook: the colour of an axe temper prefix. Look only, no stats.
-- A2's prefixes are Swift, Keen and Prosperous, tiers 1 to 3.
-- Tier 1 is trim. Tier 2 adds a thin Neon edge (glow > 0). Tier 3 names a
-- client particle. An unknown prefix returns nil, and nothing is applied.

local TemperLook = {}

export type Look = {
	trimColor: Color3,
	glow: number,
	particle: string?,
}

local PREFIXES: { [string]: { color: string, particle: string } } = {
	Swift = { color = "#6FB7E8", particle = "Wind" }, -- SkyBlue, wind streaks
	Keen = { color = "#FFFFFF", particle = "Sheen" }, -- white edge sheen
	Prosperous = { color = "#F2C14E", particle = "Sparkle" }, -- CoinGold sparkles
}

function TemperLook.For(prefix: string, tier: number): Look?
	local row = PREFIXES[prefix]
	if row == nil or (tier ~= 1 and tier ~= 2 and tier ~= 3) then
		return nil
	end
	local glow = if tier == 1 then 0 elseif tier == 2 then 0.4 else 0.75
	return {
		trimColor = Color3.fromHex(row.color),
		glow = glow,
		particle = if tier >= 3 then row.particle else nil,
	}
end

function TemperLook.Known(prefix: string): boolean
	return PREFIXES[prefix] ~= nil
end

return TemperLook
