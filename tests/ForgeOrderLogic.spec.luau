--!nocheck
-- Old Bram's weekly order: Monday 00:00 UTC weeks, a fixed list, paid once.
return function(t)
	local O = t.shared("ForgeOrderLogic")

	-- Fixed timestamps (UTC).
	local MON = 1791158400 -- Monday 2026-10-05 00:00:00 UTC
	local SUN_LATE = MON + 7 * 86400 - 1 -- Sunday 23:59:59
	local NEXT_MON = MON + 7 * 86400

	t.test("the week turns at Monday 00:00 UTC, not a second before", function()
		local w = O.WeekId(MON)
		t.eq(O.WeekId(MON - 1), w - 1, "Sunday night is last week")
		t.eq(O.WeekId(SUN_LATE), w)
		t.eq(O.WeekId(NEXT_MON), w + 1)
		t.eq(O.WeekEnds(w), NEXT_MON)
		t.eq(os.date("!%A %H:%M", O.WeekEnds(w)), "Monday 00:00")
	end)

	t.test("each week asks for the fixed order from the list", function()
		local w = O.WeekId(MON)
		for k = 0, 7 do
			local want = O.List[((w + k) % #O.List) + 1]
			t.eq(O.OrderFor(w + k), want)
		end
		t.eq(O.Pays, 18000)
		t.eq(O.Shards, 4)
	end)

	t.test("deliveries add up, pay once, and reset when the week turns", function()
		local w = O.WeekId(MON)
		local order = O.OrderFor(w)
		local s = O.Current(nil, w)
		t.eq(s.claimed, false)
		local half = {}
		for id, need in pairs(order) do
			half[id] = need / 2
		end
		local s1, used1, done1 = O.Deliver(s, half)
		t.eq(done1, false)
		for id, need in pairs(order) do
			t.eq(used1[id], need / 2)
		end
		local more = {}
		for id, need in pairs(order) do
			more[id] = need * 3
		end
		more.oak = 999
		local s2, used2, done2 = O.Deliver(s1, more)
		t.eq(done2, true, "paid now")
		t.eq(used2.oak, nil, "other wood is not taken")
		for id, need in pairs(order) do
			t.eq(used2[id], need / 2, "only what is still needed")
		end
		t.eq(s2.claimed, true)
		local s3, used3, done3 = O.Deliver(s2, more)
		t.eq(done3, false, "never twice")
		t.eq(next(used3), nil)
		t.eq(O.Current(s3, w).claimed, true, "still claimed this week")
		local nextWeek = O.Current(s3, O.WeekId(NEXT_MON))
		t.eq(nextWeek.claimed, false, "a new week, a new order")
		t.eq(next(nextWeek.delivered), nil)
	end)

	t.test("progress words and a broken save", function()
		local w = 0 -- the first list entry: Gloamwood 30, Lumenwood 10
		local s = O.Current({ week = 0, delivered = { phantomwood = 12, lumenwood = 0 / 0 } }, w)
		t.eq(O.ProgressText(s), "Lumenwood 0/10 · Gloamwood 12/30")
		t.eq(O.Current("junk", w).week, w)
	end)
end
