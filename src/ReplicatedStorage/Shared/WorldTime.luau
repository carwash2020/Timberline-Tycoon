--!strict
-- WorldTime: the in-game clock, worked out from the real time so every
-- server (and every player) agrees on whether it's night. Pure, shared by
-- WorldClock (server), the HUD clock and tests. Tuning is in GameConfig.

local GameConfig = require(script.Parent.GameConfig)

local WorldTime = {}

-- In-game hour, 0 to 24 (Lighting.ClockTime), at unix time `now`.
function WorldTime.ClockTime(now: number): number
	local cycle = GameConfig.DayCycleMinutes * 60
	return (now % cycle) / cycle * 24
end

function WorldTime.IsNight(clockTime: number): boolean
	local from, to = GameConfig.NightStartsAt, GameConfig.NightEndsAt
	if from > to then
		return clockTime >= from or clockTime < to -- the night crosses midnight
	end
	return clockTime >= from and clockTime < to
end

-- Real seconds until the night starts or ends, whichever is next.
function WorldTime.SecondsUntilChange(now: number): number
	local secondsPerHour = GameConfig.DayCycleMinutes * 60 / 24
	local clock = WorldTime.ClockTime(now)
	local target = if WorldTime.IsNight(clock) then GameConfig.NightEndsAt else GameConfig.NightStartsAt
	local hours = (target - clock) % 24
	return hours * secondsPerHour
end

-- "14:05"
function WorldTime.Format(clockTime: number): string
	local minutes = math.floor(clockTime * 60) % (24 * 60)
	return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

return WorldTime
