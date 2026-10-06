--!nocheck
return function(t)
	local WorldTime = t.shared("WorldTime")
	local GameConfig = t.shared("GameConfig")

	local cycle = GameConfig.DayCycleMinutes * 60
	local SLOW = 72 -- a daytime hour, real seconds, at NightSpeed 2
	local FAST = 36 -- a 20:00-04:00 hour

	t.test("one in-game day per DayCycleMinutes, the same everywhere", function()
		t.eq(GameConfig.DayCycleMinutes, 24)
		t.eq(cycle, 24 * 60)
		t.eq(WorldTime.ClockTime(0), 0)
		t.eq(WorldTime.ClockTime(cycle), 0)
		t.eq(WorldTime.ClockTime(123456), WorldTime.ClockTime(123456 + cycle * 7))
		-- The fast window is symmetric about midnight, so noon is still halfway.
		t.ok(math.abs(WorldTime.ClockTime(cycle / 2) - 12) < 1e-9)
		-- Two readers of one server time (two clients, or a rejoin) agree.
		t.eq(WorldTime.Hour(123456.25), WorldTime.ClockTime(123456.25))
	end)

	t.test("the night from 20:00 to 04:00 is faster and the day is still 24 minutes", function()
		t.eq(WorldTime.NightFastFrom, 20)
		t.eq(WorldTime.NightFastTo, 4)
		t.eq(WorldTime.NightSpeed, 2)
		t.eq(WorldTime.SecondsFromMidnight(24), cycle, "a full day")
		t.ok(math.abs(8 * FAST + 16 * SLOW - cycle) < 1e-6, "fast plus slow is the day")
		t.ok(math.abs(WorldTime.SecondsBetween(20, 4) - 8 * FAST) < 1e-6, "eight fast hours")
		t.ok(math.abs(WorldTime.SecondsBetween(4, 20) - 16 * SLOW) < 1e-6, "sixteen slow hours")
		local night = WorldTime.SecondsFromMidnight(21)
		t.ok(math.abs(WorldTime.ClockTime(night + FAST) - 22) < 1e-6, "a fast hour")
		local day = WorldTime.SecondsFromMidnight(10)
		t.ok(math.abs(WorldTime.ClockTime(day + SLOW) - 11) < 1e-6, "a slow hour")
		-- Integer tenths, so 4.0 and 20.0 are hit exactly. Adding 0.1 drifts.
		for i = 0, 239 do
			local h = i / 10
			local at = WorldTime.SecondsFromMidnight(h)
			t.ok(math.abs(WorldTime.ClockTime(at) - h) < 1e-6, "hour " .. h)
		end
		t.eq(WorldTime.SecondsFromMidnight(24), cycle)
	end)

	t.test("NightSpeed 1 is an even 24-minute clock", function()
		local even = t.loader():shared("WorldTime")
		even.NightSpeed = 1
		local step = cycle / 24
		t.ok(math.abs(even.ClockTime(cycle / 2) - 12) < 1e-9)
		t.ok(math.abs(even.SecondsBetween(0, 1) - step) < 1e-6)
		t.ok(math.abs(even.SecondsBetween(20, 21) - step) < 1e-6)
		t.eq(even.SecondsFromMidnight(24), cycle)
	end)

	t.test("night runs from NightStartsAt across midnight to NightEndsAt", function()
		t.ok(WorldTime.IsNight(GameConfig.NightStartsAt))
		t.ok(WorldTime.IsNight(0))
		t.ok(WorldTime.IsNight(GameConfig.NightEndsAt - 0.01))
		t.ok(not WorldTime.IsNight(GameConfig.NightEndsAt))
		t.ok(not WorldTime.IsNight(12))
		-- 18:40 is still dusk: lamps are on, the grove is not out yet.
		t.ok(not WorldTime.IsNight(18 + 40 / 60))
		t.ok(not WorldTime.IsNight(18.7))
	end)

	t.test("Hour() and IsNight() with no arguments read the server clock", function()
		local noon = cycle / 2
		local function clock(studio, now, override)
			local loader = t.loader({
				services = {
					RunService = {
						IsStudio = function()
							return studio
						end,
					},
				},
				globals = {
					workspace = {
						GetServerTimeNow = function()
							return now
						end,
						GetAttribute = function()
							return override
						end,
					},
				},
			})
			return loader:shared("WorldTime")
		end
		local live = clock(false, noon, 23)
		t.ok(math.abs(live.Hour() - 12) < 1e-6, "live servers ignore the override")
		t.eq(live.IsNight(), false)
		local studio = clock(true, noon, 23)
		t.eq(studio.Hour(), 23)
		t.eq(studio.IsNight(), true)
		local cleared = clock(true, noon, nil)
		t.ok(math.abs(cleared.Hour() - 12) < 1e-6)
		t.eq(cleared.IsNight(), false)
	end)

	t.test("counts down to the next change", function()
		local noon = cycle / 2 -- 12:00
		-- 12:00 to 19:00 is seven slow hours.
		t.ok(math.abs(WorldTime.SecondsUntilChange(noon) - 7 * SLOW) < 1e-6)
		t.ok(
			math.abs(WorldTime.SecondsUntilChange(noon) - WorldTime.SecondsBetween(12, GameConfig.NightStartsAt)) < 1e-6
		)
		-- 00:00 to 05:00 is four fast hours and one slow hour.
		local midnight = 0
		t.ok(math.abs(WorldTime.SecondsUntilChange(midnight) - (4 * FAST + SLOW)) < 1e-6)
		t.ok(
			math.abs(WorldTime.SecondsUntilChange(midnight) - WorldTime.SecondsBetween(0, GameConfig.NightEndsAt))
				< 1e-6
		)
	end)

	t.test("Format", function()
		t.eq(WorldTime.Format(0), "12:00 AM")
		t.eq(WorldTime.Format(14.5), "2:30 PM")
		t.eq(WorldTime.Format(23.99), "11:59 PM")
		t.eq(WorldTime.Format(12), "12:00 PM")
		t.eq(WorldTime.Format(0.5), "12:30 AM")
		t.eq(WorldTime.Format(24), "12:00 AM", "24 wraps to midnight")
		t.eq(WorldTime.Format(11.99), "11:59 AM")
	end)

	t.test("owner time control: scaled game time, speeds and hour setting", function()
		local base = 1790000000
		t.eq(WorldTime.Scaled(base, nil, nil, nil), base, "no attributes: real time")
		t.eq(WorldTime.Scaled(base, base - 10, base, 20), base + 200, "20x since the anchor")
		t.eq(WorldTime.Scaled(base + 5, base, base + 1000, 1), base + 1005, "1x keeps a set hour")
		for _, bad in ipairs({ 0, 2, -4, 1000, "20", 0 / 0 }) do
			t.eq(WorldTime.Scaled(base, base - 10, base, bad), base, "bad speed " .. tostring(bad))
		end
		t.eq(WorldTime.Scaled(base, "x", base, 20), base, "bad anchor")
		t.eq(WorldTime.Scaled(base, base, 0 / 0, 20), base, "NaN anchor")
		t.eq(WorldTime.Speeds, { 1, 4, 20, 60 })
		for _, hour in ipairs({ 0, 0.5, 6, 12, 18, 19.25, 23.99 }) do
			local game = WorldTime.GameTimeForHour(base, hour)
			t.ok(math.abs(WorldTime.ClockTime(game) - hour) < 1e-6, "hour " .. hour)
			t.ok(math.abs(game - base) <= GameConfig.DayCycleMinutes * 60, "stays within the day")
		end
	end)
end
