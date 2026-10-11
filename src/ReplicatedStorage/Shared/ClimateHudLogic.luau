--!strict
-- ClimateHudLogic: what the player sees while cold or heat is on them: a
-- frost or heat vignette that grows with the exposure meter, and a one-line
-- tip the first time (saved in profile.tipsSeen). Pure; WorldUI draws it and
-- QuestService sends the tip. The meter is the player attributes HazardService
-- sets: ClimateKind ("cold", "heat" or "") and Exposure (0 to 1; 1 means damage is on).

local ClimateHudLogic = {}

-- The strongest the vignette gets (alpha of the edge colour at full exposure).
ClimateHudLogic.MaxAlpha = 0.55

-- Edge colour by kind: frost blue, heat orange. nil when safe.
local COLORS: { [string]: { number } } = {
	cold = { 191, 227, 245 },
	heat = { 232, 100, 42 },
}

function ClimateHudLogic.Color(kind: unknown): { number }?
	return if type(kind) == "string" then COLORS[kind] else nil
end

-- 0 when safe or unknown, else exposure (clamped) times MaxAlpha, with a small
-- floor so the first second of cold already shows.
function ClimateHudLogic.Alpha(kind: unknown, exposure: unknown): number
	if ClimateHudLogic.Color(kind) == nil then
		return 0
	end
	local e = if type(exposure) == "number" and exposure == exposure then math.clamp(exposure, 0, 1) else 0
	return math.max(0.08, e * ClimateHudLogic.MaxAlpha)
end

local TIPS: { [string]: { key: string, text: string } } = {
	cold = { key = "climate:cold", text = "Cold hurts here. Find a campfire or wear a Coat." },
	heat = { key = "climate:heat", text = "Heat hurts here. Find shade or wear Heat Boots." },
}

-- The tip to show now (once per kind, ever), or nil. Does not write `seen`.
function ClimateHudLogic.Tip(kind: unknown, seen: { [string]: boolean }?): { key: string, text: string }?
	local tip = if type(kind) == "string" then TIPS[kind] else nil
	if tip == nil or (seen ~= nil and seen[tip.key] == true) then
		return nil
	end
	return tip
end

return ClimateHudLogic
