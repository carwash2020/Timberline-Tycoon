--!strict
-- Lux Axe swing cosmetics (pass 2005226878). Numbers only: the client
-- (LuxFX) builds one Trail and two emitters per axe and reuses them.
-- Nothing here changes damage, range, cooldown, grip or the sell bonus.
-- No PointLight: the trail and the particles are the whole effect.

local LuxEffect = {}

-- AxeArt's Lux gold (#E8C547).
LuxEffect.Gold = Color3.fromRGB(232, 197, 71)

LuxEffect.TrailFull = 0.25
LuxEffect.TrailLow = 0.12
LuxEffect.BurstFull = 12
LuxEffect.BurstLow = 4
LuxEffect.SparklePerSec = 6

function LuxEffect.TrailLifetime(tier: string): number
	if tier == "low" then
		return LuxEffect.TrailLow
	end
	return LuxEffect.TrailFull
end

function LuxEffect.BurstCount(tier: string): number
	if tier == "low" then
		return LuxEffect.BurstLow
	end
	return LuxEffect.BurstFull
end

-- 0 on low (and on any tier that is not medium or high). The cap is 6 a second.
function LuxEffect.SparkleRate(tier: string): number
	if tier == "low" then
		return 0
	end
	if tier == "medium" or tier == "high" then
		return LuxEffect.SparklePerSec
	end
	return 0
end

-- True when a sparkle may emit. Low is off. `cosmeticDue` is the quality
-- loop (QualityBudgets.CosmeticDue): a frame the loop skips emits nothing.
function LuxEffect.SparkleDue(tier: string, elapsed: number, cosmeticDue: boolean): boolean
	if not cosmeticDue then
		return false
	end
	local hz = LuxEffect.SparkleRate(tier)
	if hz <= 0 then
		return false
	end
	return elapsed >= 1 / hz - 1e-4
end

return LuxEffect
