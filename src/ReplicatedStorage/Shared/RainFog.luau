--!strict
-- RainFog: the wet-weather addition to the sky. WeatherController publishes
-- a wetness from 0 (clear, or under a roof) to 1 (a storm in the open).
-- LightingController is the only script that writes Atmosphere and
-- ColorShift_Top. It folds this wetness into its own target once, so a
-- steady rain cannot stack fog every frame.

local RainFog = {}

RainFog.DensityAdd = 0.08
RainFog.HazeAdd = 1.1
RainFog.Cool = Color3.fromRGB(150, 168, 188)
RainFog.Shift = 0.25

local wet = 0

function RainFog.SetWet(value: number)
	wet = math.clamp(value, 0, 1)
end

function RainFog.GetWet(): number
	return wet
end

export type Target = {
	density: number,
	haze: number,
	shift: Color3,
}

-- The sky Lighting should write this frame. `base*` is the dry look.
-- Wetness is applied once, never on top of a value that already includes it.
function RainFog.Target(baseDensity: number, baseHaze: number, baseShift: Color3): Target
	local w = wet
	return {
		density = baseDensity + RainFog.DensityAdd * w,
		haze = baseHaze + RainFog.HazeAdd * w,
		shift = baseShift:Lerp(RainFog.Cool, RainFog.Shift * w),
	}
end

return RainFog
