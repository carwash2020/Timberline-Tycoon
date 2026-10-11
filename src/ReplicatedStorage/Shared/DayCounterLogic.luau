--!strict
-- DayCounterLogic: the "Day N" under the clock. The first time a save is
-- played the server stamps the world day it started on (`profile.dayCounter`,
-- stored as that day + 1 so 0 means "not yet"); the HUD shows
-- WorldTime.Day(now) - firstWorldDay + 1. Pure, so the server (QuestService)
-- and the client (WorldUI) agree and the spec can pin it.

local DayCounterLogic = {}

-- What to save: the stored value if it is set, else `today` + 1.
function DayCounterLogic.Stamp(stored: unknown, today: number): number
	if type(stored) == "number" and stored == stored and stored >= 1 then
		return math.floor(stored)
	end
	return math.max(0, math.floor(today)) + 1
end

-- "Day N": N is 1 on the first world day, never below 1, nil until stamped.
function DayCounterLogic.Number(stored: unknown, today: number): number?
	if type(stored) ~= "number" or stored ~= stored or stored < 1 then
		return nil
	end
	return math.max(1, math.floor(today) - (math.floor(stored) - 1) + 1)
end

function DayCounterLogic.Label(stored: unknown, today: number): string?
	local n = DayCounterLogic.Number(stored, today)
	return if n then "Day " .. tostring(n) else nil
end

return DayCounterLogic
