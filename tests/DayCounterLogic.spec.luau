--!nocheck
return function(t)
	local D = t.shared("DayCounterLogic")

	t.test("the first play stamps the day, and a stamp is kept", function()
		t.eq(D.Stamp(0, 20000), 20001)
		t.eq(D.Stamp(nil, 0), 1)
		t.eq(D.Stamp(20001, 20050), 20001, "never restamped")
		t.eq(D.Stamp("junk", 7), 8)
	end)

	t.test("Day N counts from 1 on the first world day", function()
		local stored = D.Stamp(0, 20000)
		t.eq(D.Number(stored, 20000), 1)
		t.eq(D.Number(stored, 20004), 5)
		t.eq(D.Number(stored, 19990), 1, "never below 1")
		t.eq(D.Number(0, 20000), nil, "not stamped yet")
		t.eq(D.Label(stored, 20002), "Day 3")
		t.eq(D.Label(nil, 5), nil)
	end)

	t.test("a day-0 start still reads Day 1", function()
		t.eq(D.Number(D.Stamp(0, 0), 0), 1)
		t.eq(D.Number(D.Stamp(0, 0), 3), 4)
	end)

	t.test(
		"a new player on a fresh server (08:00, same world day) reads Day 1 at 8 AM, Day 2 after midnight",
		function()
			local WorldTime = t.shared("WorldTime")
			local cycle = t.shared("GameConfig").DayCycleMinutes * 60
			-- The real clock says 1:19 AM on world day 20000: the old first look.
			local real = 20000 * cycle + WorldTime.SecondsFromMidnight(1.3)
			local start = WorldTime.FreshStart(real, 8)
			local stored = D.Stamp(0, WorldTime.Day(start.game))
			t.eq(D.Label(stored, WorldTime.Day(start.game)), "Day 1")
			-- 16 in-game hours later (midnight) the day rolls over, as it always did.
			local midnight = start.game + WorldTime.SecondsBetween(8, 0)
			t.eq(D.Label(stored, WorldTime.Day(midnight)), "Day 2")
			-- A returning player's stamp is untouched by the fresh start.
			t.eq(D.Number(19998, WorldTime.Day(start.game)), 4)
		end
	)
end
