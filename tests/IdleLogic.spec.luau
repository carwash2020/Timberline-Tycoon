--!nocheck
-- Idle kick: a warning at 18 minutes, removal at 20, activity resets it, and
-- nobody is removed in their first five minutes in the world.
return function(t)
	local Idle = t.shared("IdleLogic")
	local MIN = 60

	t.test("the numbers: warn at 18 minutes, remove at 20, five minutes of grace", function()
		t.eq(Idle.WarnAfter, 18 * MIN)
		t.eq(Idle.KickAfter, 20 * MIN)
		t.eq(Idle.Grace, 5 * MIN)
		t.ok(string.find(Idle.KickMessage, "Rejoin", 1, true) ~= nil, "the message tells them to rejoin")
	end)

	t.test("an idle player is warned at 18 minutes, reminded each minute, removed at 20", function()
		local s = Idle.New(0)
		t.eq(Idle.Step(s, 17 * MIN + 59), "none")
		t.eq(Idle.Step(s, 18 * MIN), "warn")
		t.eq(Idle.Step(s, 18 * MIN + 30), "none", "not again within a minute")
		t.eq(Idle.Step(s, 19 * MIN), "warn", "the reminder")
		t.eq(Idle.Step(s, 19 * MIN + 59), "none")
		t.eq(Idle.Step(s, 20 * MIN), "kick")
		t.eq(Idle.SecondsLeft(s, 18 * MIN), 2 * MIN)
		t.eq(Idle.SecondsLeft(s, 25 * MIN), 0)
	end)

	t.test("any activity starts the count again, and a later idle spell warns again", function()
		local s = Idle.New(0)
		t.eq(Idle.Step(s, 18 * MIN), "warn")
		Idle.Touch(s, 19 * MIN) -- a key press, a chat line, a step, a remote
		t.eq(Idle.Step(s, 20 * MIN), "none", "not removed: they were active a minute ago")
		t.eq(Idle.Step(s, 36 * MIN), "none", "17 minutes since the touch")
		t.eq(Idle.Step(s, 37 * MIN), "warn", "18 minutes since the touch")
		t.eq(Idle.Step(s, 39 * MIN), "kick")
		Idle.Touch(s, 5 * MIN)
		t.eq(s.lastActive, 19 * MIN, "an old timestamp never moves the clock back")
	end)

	t.test("nobody is removed or warned in the first five minutes in the world", function()
		-- Even with a clock that says they were last active long before.
		local s = Idle.New(100 * MIN)
		s.lastActive = 0
		t.eq(Idle.Step(s, 100 * MIN), "none")
		t.eq(Idle.Step(s, 100 * MIN + 299), "none")
		t.eq(Idle.Step(s, 105 * MIN), "kick", "the grace is over and the clock says 105 minutes")
	end)

	t.test("a player who joined and did nothing is safe until 20 minutes after they could play", function()
		local s = Idle.New(50)
		t.eq(Idle.Step(s, 50 + 17 * MIN), "none")
		t.eq(Idle.Step(s, 50 + 20 * MIN), "kick")
	end)

	t.test("movement is a step of half a stud or more; no character is not movement", function()
		local a = { x = 0, y = 3, z = 0 }
		t.eq(Idle.Moved(a, { x = 0.2, y = 3, z = 0.2 }), false, "idle animation jitter")
		t.eq(Idle.Moved(a, { x = 0.6, y = 3, z = 0 }), true)
		t.eq(Idle.Moved(a, { x = 0, y = 9, z = 0 }), true, "a jump or a lift")
		t.eq(Idle.Moved(nil, a), false)
		t.eq(Idle.Moved(a, nil), false)
	end)

	t.test("the warning text counts minutes", function()
		t.ok(string.find(Idle.WarnText(120), "2 minutes", 1, true) ~= nil)
		t.ok(string.find(Idle.WarnText(45), "in 1 minute.", 1, true) ~= nil, "singular")
	end)
end
