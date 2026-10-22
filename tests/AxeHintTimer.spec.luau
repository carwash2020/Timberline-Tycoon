--!nocheck
-- AxeHintTimer (T406): the "put your axe away" line is brief. Before, it showed
-- for as long as an axe was out and aimed at wood.
return function(t)
	local AxeHintTimer = t.shared("AxeHintTimer")
	local TipTimer = t.shared("TipTimer")

	t.test("nothing shows until the player tries to grab with an axe out", function()
		local s = AxeHintTimer.New()
		t.ok(not AxeHintTimer.Showing(s, 0, true, false), "aiming at wood with an axe is not a try")
		t.ok(not AxeHintTimer.Showing(s, 500, true, false))
	end)

	t.test("a try shows it for under 3.5 s (3 s plus the 0.4 s fade), then it is gone", function()
		t.ok(AxeHintTimer.Seconds < 3.5, "limit")
		t.eq(AxeHintTimer.Seconds, TipTimer.VisibleSeconds + TipTimer.FadeSeconds)
		local s = AxeHintTimer.New()
		t.ok(AxeHintTimer.Try(s, 10))
		t.ok(AxeHintTimer.Showing(s, 10, true, false))
		t.ok(AxeHintTimer.Showing(s, 13.3, true, false))
		t.ok(not AxeHintTimer.Showing(s, 13.4, true, false), "gone at 3.4 s")
		t.ok(not AxeHintTimer.Showing(s, 14, true, false))
		t.ok(not AxeHintTimer.Showing(s, 3000, true, false), "never comes back by itself")
	end)

	t.test("it goes at once when the axe is put away, or a drag starts or ends", function()
		local s = AxeHintTimer.New()
		AxeHintTimer.Try(s, 0)
		t.ok(not AxeHintTimer.Showing(s, 1, false, false), "axe put away")
		t.ok(not AxeHintTimer.Showing(s, 1, true, true), "dragging")
		AxeHintTimer.Cancel(s)
		t.ok(not AxeHintTimer.Showing(s, 1, true, false), "cancelled: not back when the axe is out again")
	end)

	t.test("the TipTimer cooldown: not again within 60 s of the last start", function()
		local s = AxeHintTimer.New()
		t.ok(AxeHintTimer.Try(s, 0))
		t.ok(not AxeHintTimer.Try(s, 30), "within the cooldown")
		t.ok(not AxeHintTimer.Showing(s, 31, true, false))
		t.ok(AxeHintTimer.Try(s, 60), "after it")
		t.ok(AxeHintTimer.Showing(s, 61, true, false))
	end)
end
