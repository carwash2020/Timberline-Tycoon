--!strict
-- ClockOverride (WLD-06): a Studio-only way to look at any hour. Set the
-- workspace attribute "ClockOverride" to an hour from 0 to 24, e.g. in the
-- server command bar during Play:
--     workspace:SetAttribute("ClockOverride", 23)
-- WorldClock (the server: IsNight, the Phantom Grove's trees) and
-- LightingController (each client: the sun, the light, the lamps and
-- windows) then use that hour instead of the shared clock; clear it
-- (workspace:SetAttribute("ClockOverride", nil)) to go back. Both read it
-- only in Studio (RunService:IsStudio()), so a live server and its players
-- ignore it. Pure: the callers read the attribute.

local ClockOverride = {}

ClockOverride.Attribute = "ClockOverride"

-- The hour to show: `clock` (the shared clock's hour), or `override` when
-- running in Studio and it is a number from 0 to 24 (24 is midnight, 0).
-- Anything else (nil, a string, NaN, -1, 25) leaves the shared clock.
function ClockOverride.Apply(clock: number, override: unknown, isStudio: boolean): number
	if not isStudio or type(override) ~= "number" then
		return clock
	end
	if not (override >= 0 and override <= 24) then -- also false for NaN
		return clock
	end
	return override % 24
end

return ClockOverride
