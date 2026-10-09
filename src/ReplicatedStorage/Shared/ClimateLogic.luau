--!strict
-- ClimateLogic: cold and heat outside the crater. Pure, so BiomeService
-- and HazardService agree with the specs.
--
-- A biome's exposure (BiomeData) names the gear that removes it, how hard
-- it hits once the meter is full, and how long the meter takes to fill.
-- The meter fills during the grace and damage starts when it is full.
-- A vehicle seat pauses the meter (no fill, no damage). Leaving the hazard,
-- putting the gear on, or respawning clears it. The crater's lava burn is
-- not this meter: that stays GameConfig.LavaDamagePerSecond.

local ClimateLogic = {}

export type Hazard = {
	kind: string,
	dps: number,
	graceSec: number,
}

-- One step. `exposure` is 0 to 1. `active` means the player is in the
-- hazard without the gear. `sheltered` (a vehicle seat) freezes the meter.
-- Returns the new exposure and the damage this step deals.
function ClimateLogic.Tick(
	exposure: number,
	dt: number,
	active: boolean,
	sheltered: boolean,
	hazard: Hazard?
): (number, number)
	if not active or hazard == nil then
		return 0, 0
	end
	local held = if type(exposure) == "number" and exposure == exposure then math.clamp(exposure, 0, 1) else 0
	if sheltered or dt <= 0 then
		return held, 0
	end
	local grace = math.max(hazard.graceSec, 1e-3)
	local nextExposure = math.min(1, held + dt / grace)
	local damage = 0
	if nextExposure >= 1 then
		local filledAt = if held >= 1 then 0 else (1 - held) * grace
		damage = hazard.dps * math.max(0, dt - filledAt)
	end
	return nextExposure, damage
end

return ClimateLogic
