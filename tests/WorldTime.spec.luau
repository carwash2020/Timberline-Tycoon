--!nocheck
return function(t)
	local WorldTime = t.shared("WorldTime")
	local GameConfig = t.shared("GameConfig")

	local cycle = GameConfig.DayCycleMinutes * 60

	t.test("one in-game day per DayCycleMinutes, the same everywhere", function()
		t.eq(WorldTime.ClockTime(0), 0)
		t.eq(WorldTime.ClockTime(cycle / 2), 12)
		t.eq(WorldTime.ClockTime(cycle), 0)
		t.eq(WorldTime.ClockTime(123456), WorldTime.ClockTime(123456 + cycle * 7))
	end)

	t.test("night runs from NightStartsAt across midnight to NightEndsAt", function()
		t.ok(WorldTime.IsNight(GameConfig.NightStartsAt))
		t.ok(WorldTime.IsNight(0))
		t.ok(WorldTime.IsNight(GameConfig.NightEndsAt - 0.01))
		t.ok(not WorldTime.IsNight(GameConfig.NightEndsAt))
		t.ok(not WorldTime.IsNight(12))
	end)

	t.test("counts down to the next change", function()
		local secondsPerHour = cycle / 24
		local noon = cycle / 2 -- 12:00
		t.ok(math.abs(WorldTime.SecondsUntilChange(noon) - (GameConfig.NightStartsAt - 12) * secondsPerHour) < 1e-6)
		local midnight = 0
		t.ok(math.abs(WorldTime.SecondsUntilChange(midnight) - GameConfig.NightEndsAt * secondsPerHour) < 1e-6)
	end)

	t.test("Format", function()
		t.eq(WorldTime.Format(0), "00:00")
		t.eq(WorldTime.Format(14.5), "14:30")
		t.eq(WorldTime.Format(23.99), "23:59")
	end)
end
