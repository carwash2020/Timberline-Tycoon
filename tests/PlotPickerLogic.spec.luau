--!nocheck
-- Choosing a homestead (Shared/PlotPickerLogic): the rules the picker and
-- PlotService both follow.
return function(t)
	local Logic = t.shared("PlotPickerLogic")

	t.test("the picker stays up for about a minute, then gives up", function()
		t.eq(Logic.TimeoutSeconds, 60)
		t.eq(Logic.TimedOut(0, 59), false)
		t.eq(Logic.TimedOut(0, 60), true)
	end)

	t.test("a player who already has a pad does not pick again", function()
		t.eq(Logic.ShouldPick(false), true)
		t.eq(Logic.ShouldPick(true), false)
	end)

	t.test("next and previous walk every pad, including taken ones", function()
		t.eq(Logic.Step(1, 14, -1), 14)
		t.eq(Logic.Step(14, 14, 1), 1)
		t.eq(Logic.Step(3, 14, 1), 4)
	end)

	t.test("a claim is an integer slot that is still free", function()
		t.eq(Logic.ClaimIndex(1.5, 14), nil)
		t.eq(Logic.ClaimIndex(0, 14), nil)
		t.eq(Logic.ClaimIndex(15, 14), nil)
		t.eq(Logic.ClaimIndex("3", 14), nil)
		t.eq(Logic.ClaimIndex(0 / 0, 14), nil)
		t.eq(Logic.ClaimIndex(7, 14), 7)
		t.eq(Logic.CanClaim(true), false)
		t.eq(Logic.CanClaim(false), true)
	end)

	t.test("two claims of one pad in one breath: the first wins", function()
		local taken = { false, false, false }
		local aOk, aWhy = Logic.TryClaim(taken, 2)
		local bOk, bWhy = Logic.TryClaim(taken, 2)
		t.eq(aOk, true)
		t.eq(aWhy, "ok")
		t.eq(bOk, false)
		t.eq(bWhy, "taken")
		t.eq(taken[2], true)
		t.eq(Logic.FirstFree(taken), 1)
		t.eq(Logic.NextOpen({ { taken = true }, { taken = true }, { taken = false } }, 2), 3)
	end)

	t.test("the buttons sit clear of the thumbstick in both orientations", function()
		for _, screen in ipairs({
			{ 390, 844 },
			{ 844, 390 },
			{ 568, 320 },
			{ 320, 568 },
		}) do
			t.eq(Logic.ControlsClear(screen[1], screen[2]), true, screen[1] .. "x" .. screen[2])
		end
	end)

	t.test("a plot is bought, not given: only a save that already owns one picks free", function()
		t.eq(Logic.Price(false, 200), 200)
		t.eq(Logic.Price(true, 200), 0)
		t.eq(Logic.Price(false, t.shared("GameConfig").PlotPrice), t.shared("GameConfig").PlotPrice)
	end)

	t.test("the server's verdict on a claim, in the order it checks", function()
		-- hasPlot, inRange, taken, price, cash
		t.eq({ Logic.Decide(true, true, false, 200, 999) }, { "owned", 0 })
		t.eq({ Logic.Decide(false, false, false, 200, 999) }, { "range", 0 })
		t.eq({ Logic.Decide(false, true, true, 200, 999) }, { "taken", 0 })
		t.eq({ Logic.Decide(false, true, false, 200, 150) }, { "cash", 50 })
		t.eq({ Logic.Decide(false, true, false, 200, 199) }, { "cash", 1 })
		t.eq({ Logic.Decide(false, true, false, 200, 200) }, { "ok", 0 })
		t.eq({ Logic.Decide(false, true, false, 0, 0) }, { "ok", 0 }, "a free pick needs no cash")
		t.eq(Logic.ShortText(50), "You need $50 more for a plot.")
	end)

	t.test("the picker's words carry the price the server charges", function()
		t.eq(Logic.ClaimLabel(200), "BUY PLOT $200")
		t.eq(Logic.ClaimLabel(0), "CLAIM PLOT")
		t.eq(Logic.OpenText("Hills", 200), "Hills\nOpen plot · $200")
		t.eq(Logic.OpenText("Hills", 0), "Hills\nOpen plot")
		t.eq(Logic.AnyText(200), "Not now", "a buyer is never handed a pad")
		t.eq(Logic.AnyText(0), "Give me any open plot")
	end)
	t.test("the picker gives back a real walk speed, never a stuck zero", function()
		t.eq(Logic.SafeSpeed(16), 16)
		t.eq(Logic.SafeSpeed(24.5), 24.5, "a sprint's speed is kept")
		t.eq(Logic.SafeSpeed(0), Logic.DefaultWalkSpeed, "a zero saved by a second lock")
		t.eq(Logic.SafeSpeed(-3), Logic.DefaultWalkSpeed)
		t.eq(Logic.SafeSpeed(nil), Logic.DefaultWalkSpeed)
		t.eq(Logic.SafeSpeed(0 / 0), Logic.DefaultWalkSpeed)
		t.eq(Logic.SafeSpeed(math.huge), Logic.DefaultWalkSpeed)
		t.eq(Logic.SafeSpeed("fast"), Logic.DefaultWalkSpeed)
	end)
end
