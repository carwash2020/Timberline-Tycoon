--!strict
-- WorldTime: the in-game clock, worked out from the real time so every
-- server (and every player) agrees on the hour. Pure, shared by
-- WorldClock (server), LightingController, the HUD clock and tests.
-- Tuning of the day length is GameConfig.DayCycleMinutes. The faster
-- night below is tuned here.
--
-- A full day is DayCycleMinutes real minutes (24). Hours from
-- NightFastFrom to NightFastTo pass NightSpeed times faster than a
-- daytime hour, and the daytime hours stretch so the total stays
-- DayCycleMinutes. NightSpeed 1 is an even clock.

local ClockOverride = require(script.Parent.ClockOverride)
local GameConfig = require(script.Parent.GameConfig)

local WorldTime = {}

-- Approved: 2. Each hour from 20:00 to 04:00 takes half as long as a
-- daytime hour (36 s instead of 72 s), so that stretch of night is 4.8 real
-- minutes and the other sixteen hours fill the rest of the 24. The window
-- sits evenly around midnight, so noon is still halfway through the day.
-- Set NightSpeed to 1 for an even clock; the day is still 24 minutes.
WorldTime.NightFastFrom = 20
WorldTime.NightFastTo = 4
WorldTime.NightSpeed = 2

local function cycleSeconds(): number
	return GameConfig.DayCycleMinutes * 60
end

local function speedFactor(): number
	local factor = WorldTime.NightSpeed
	if type(factor) ~= "number" or factor ~= factor or factor < 1 then
		return 1
	end
	return factor
end

-- Real seconds for one slow (daytime) hour and one fast (night) hour.
local function hourSeconds(): (number, number)
	local cycle = cycleSeconds()
	local from = WorldTime.NightFastFrom % 24
	local to = WorldTime.NightFastTo % 24
	local fastSpan = if from == to then 0 else (to - from) % 24
	local slowSpan = 24 - fastSpan
	local factor = speedFactor()
	local weight = slowSpan + fastSpan / factor
	local slow = cycle / weight
	return slow, slow / factor
end

local function fastAt(hour: number): boolean
	local from = WorldTime.NightFastFrom % 24
	local to = WorldTime.NightFastTo % 24
	if from == to then
		return false
	end
	local h = hour % 24
	if from < to then
		return h >= from and h < to
	end
	return h >= from or h < to
end

-- Clock hours where the speed changes, plus midnight and the next midnight.
local function edges(): { number }
	local from = WorldTime.NightFastFrom % 24
	local to = WorldTime.NightFastTo % 24
	local list = { 0, 24 }
	if from ~= to then
		if from ~= 0 then
			table.insert(list, from)
		end
		if to ~= 0 then
			table.insert(list, to)
		end
	end
	table.sort(list)
	local out: { number } = {}
	local last = -1
	for _, h in ipairs(list) do
		if h ~= last then
			table.insert(out, h)
			last = h
		end
	end
	return out
end

-- Real seconds from hour 0 to `hour` (0..24) on this clock.
local function secondsUpTo(hour: number): number
	local slow, fast = hourSeconds()
	local stops = edges()
	local acc = 0
	for i = 1, #stops - 1 do
		local a, b = stops[i], stops[i + 1]
		if hour <= a then
			break
		end
		local stop = math.min(hour, b)
		local per = if fastAt(a) then fast else slow
		acc += (stop - a) * per
		if hour <= b then
			break
		end
	end
	return acc
end

-- In-game hour, 0 to 24 (Lighting.ClockTime), at unix time `now`.
function WorldTime.ClockTime(now: number): number
	local cycle = cycleSeconds()
	if cycle <= 0 then
		return 0
	end
	local into = now % cycle
	if into < 0 then
		into += cycle
	end
	local slow, fast = hourSeconds()
	local stops = edges()
	local left = into
	for i = 1, #stops - 1 do
		local a, b = stops[i], stops[i + 1]
		local per = if fastAt(a) then fast else slow
		local sec = (b - a) * per
		if left <= sec or i == #stops - 1 then
			local frac = if sec > 0 then math.clamp(left / sec, 0, 1) else 0
			local hour = a + (b - a) * frac
			if hour >= 24 then
				return 0
			end
			return hour
		end
		left -= sec
	end
	return 0
end

-- Owner time control (AdminService). The clock normally reads the real server
-- time. The owner can speed it up or set the hour: the server then writes three
-- workspace attributes, and every clock reader (the sky, shop hours, night,
-- the corner clock) works the "game time" out from them. They live in server
-- memory only: a new server starts without them, so time is real again after
-- a restart (nothing is saved to the profile or a DataStore).
--   TimeAnchorReal: the server time (GetServerTimeNow) when it was last set
--   TimeAnchorGame: the game time that moment showed
--   TimeSpeed: one of WorldTime.Speeds
WorldTime.Speeds = { 1, 4, 20, 60 } :: { number }
WorldTime.AnchorRealAttribute = "TimeAnchorReal"
WorldTime.AnchorGameAttribute = "TimeAnchorGame"
WorldTime.SpeedAttribute = "TimeSpeed"

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -1e12 and n < 1e12
end

function WorldTime.IsSpeed(speed: unknown): boolean
	return type(speed) == "number" and table.find(WorldTime.Speeds, speed) ~= nil
end

-- Game time at real time `realNow`, given the anchors and speed as read off
-- the workspace (any type). Anything missing or off the list is real time.
function WorldTime.Scaled(realNow: number, anchorReal: unknown, anchorGame: unknown, speed: unknown): number
	if not (finite(anchorReal) and finite(anchorGame) and WorldTime.IsSpeed(speed)) then
		return realNow
	end
	return (anchorGame :: number) + (realNow - (anchorReal :: number)) * (speed :: number)
end

-- The game time (unix-like seconds) the sky is on right now.
function WorldTime.GameNow(): number
	local real = workspace:GetServerTimeNow()
	return WorldTime.Scaled(
		real,
		workspace:GetAttribute(WorldTime.AnchorRealAttribute),
		workspace:GetAttribute(WorldTime.AnchorGameAttribute),
		workspace:GetAttribute(WorldTime.SpeedAttribute)
	)
end

-- The game time that shows `hour` (0..24) on the day `gameNow` is in.
function WorldTime.GameTimeForHour(gameNow: number, hour: number): number
	local cycle = cycleSeconds()
	return math.floor(gameNow / cycle) * cycle + WorldTime.SecondsFromMidnight(hour % 24)
end

-- The hour the sky shows right now. Pass a unix time to ask about that
-- moment (tests, the weather). Omit it to read the server clock, which is
-- what shop hours, night glow and dailies want. In Studio the workspace
-- attribute ClockOverride stands in, the same way WorldClock does.
function WorldTime.Hour(now: number?): number
	if now ~= nil then
		return WorldTime.ClockTime(now)
	end
	local clock = WorldTime.ClockTime(WorldTime.GameNow())
	if game:GetService("RunService"):IsStudio() then
		return ClockOverride.Apply(clock, workspace:GetAttribute(ClockOverride.Attribute), true)
	end
	return clock
end

-- The in-game day number. A pure function of the shared clock, so every
-- server agrees. Day 0 is the epoch.
function WorldTime.Day(now: number): number
	local cycle = cycleSeconds()
	if cycle <= 0 then
		return 0
	end
	return math.floor(now / cycle)
end

function WorldTime.IsNight(clockTime: number?): boolean
	local clock = if type(clockTime) == "number" then clockTime else WorldTime.Hour()
	local from, to = GameConfig.NightStartsAt, GameConfig.NightEndsAt
	if from > to then
		return clock >= from or clock < to -- the night crosses midnight
	end
	return clock >= from and clock < to
end

-- Real seconds from the previous midnight to in-game `hour` (0..24).
-- 24 is a whole day. The same on every server.
function WorldTime.SecondsFromMidnight(hour: number): number
	if hour <= 0 then
		return 0
	end
	local cycle = cycleSeconds()
	if hour >= 24 then
		return math.floor(hour / 24) * cycle + secondsUpTo(hour % 24)
	end
	return secondsUpTo(hour)
end

-- Real seconds to walk the clock forward from `fromHour` to `toHour`.
function WorldTime.SecondsBetween(fromHour: number, toHour: number): number
	local cycle = cycleSeconds()
	local a = fromHour % 24
	local b = toHour % 24
	if a < 0 then
		a += 24
	end
	if b < 0 then
		b += 24
	end
	local d = secondsUpTo(b) - secondsUpTo(a)
	if d < 0 then
		d += cycle
	end
	return d
end

-- Real seconds until the night starts or ends, whichever is next.
function WorldTime.SecondsUntilChange(now: number): number
	local clock = WorldTime.ClockTime(now)
	local target = if WorldTime.IsNight(clock) then GameConfig.NightEndsAt else GameConfig.NightStartsAt
	return WorldTime.SecondsBetween(clock, target)
end

-- The one way the game writes an hour to a player: a 12-hour clock,
-- 12:00 AM through 11:59 PM, then 12:00 AM again. The clock itself still
-- runs 0 to 24 inside; only the words change. 0 -> "12:00 AM",
-- 14.5 -> "2:30 PM", 12 -> "12:00 PM". No leading zero on the hour.
function WorldTime.Format(clockTime: number): string
	local minutes = math.floor(clockTime * 60) % (24 * 60)
	return WorldTime.FormatMinutes(minutes)
end

-- Same, from whole minutes since midnight (wraps at 24 h).
function WorldTime.FormatMinutes(totalMinutes: number): string
	local minutes = math.floor(totalMinutes) % (24 * 60)
	local h24 = minutes // 60
	local h12 = h24 % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, minutes % 60, if h24 < 12 then "AM" else "PM")
end

return WorldTime
