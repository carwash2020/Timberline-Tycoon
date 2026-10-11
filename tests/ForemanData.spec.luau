--!nocheck
-- Rook Calloway, the Sawmill Foreman: what he owes and what he says.
return function(t)
	local ForemanData = t.shared("ForemanData")
	local DailyData = t.shared("DailyData")

	local function goal(done, paid, reward)
		return {
			kind = "fell",
			target = 4,
			progress = if done then 4 else 1,
			reward = reward or 15,
			done = done,
			paid = paid,
		}
	end

	t.test("owed is every finished unpaid goal plus the bonus", function()
		local total, waiting =
			ForemanData.Owed({ goal(true, false, 15), goal(true, true, 30), goal(false, nil, 75) }, 40)
		t.eq(total, 55)
		t.eq(waiting, 1)
		t.eq(ForemanData.Owed({}, nil), 0)
		t.eq(
			ForemanData.Owed({ goal(true, nil, 30) }, 0),
			0,
			"a goal with no paid flag is the old loop's: already paid"
		)
	end)

	t.test("the countdown counts to the UTC reset, never 'tomorrow'", function()
		t.eq(ForemanData.Countdown(1000 + 5 * 3600 + 12 * 60, 1000), "5h 12m")
		t.eq(ForemanData.Countdown(1000 + 12 * 60, 1000), "12m")
		t.eq(ForemanData.Countdown(500, 1000), "1m")
	end)

	local function state(over)
		local s = { tutorial = false, goals = {}, bonusOwed = 0, streak = 0, countdown = "5h 12m" }
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	t.test("his lines are two short sentences for every state", function()
		local cases = {
			state({ tutorial = true }),
			state({ goals = { goal(false), goal(false), goal(false) } }),
			state({ goals = { goal(true, false), goal(false), goal(false) } }),
			state({ goals = { goal(true, true), goal(false), goal(false) } }),
			state({ goals = { goal(true, false), goal(true, false), goal(true, false) }, bonusOwed = 60, streak = 3 }),
			state({ goals = { goal(true, true), goal(true, true), goal(true, true) }, streak = 3 }),
			state({ goals = { goal(true, true) }, bonusOwed = 20 }),
		}
		for i, c in ipairs(cases) do
			local lines = ForemanData.Lines(c)
			t.eq(#lines, 2, "case " .. i)
			for _, line in ipairs(lines) do
				t.ok(#line <= 40, string.format("case %d fits a phone line: %s", i, line))
			end
		end
		t.ok(string.find(ForemanData.Lines(cases[6])[2], "5h 12m", 1, true) ~= nil, "all done counts down")
		t.ok(string.find(table.concat(ForemanData.Lines(cases[6]), " "), "omorrow", 1, true) == nil)
		t.ok(string.find(ForemanData.Lines(cases[5])[1], "$", 1, true) ~= nil, "says what he owes")
	end)

	t.test("the DailyGoals attribute carries the unpaid flag", function()
		local goals = { goal(true, false), goal(true, true), goal(false, nil) }
		local back = DailyData.Decode(DailyData.Encode(goals))
		t.eq(back[1].paid, false)
		t.eq(back[2].paid, nil, "paid reads as nothing owed")
		t.eq(back[3].paid, nil)
		t.eq(#DailyData.Decode("fell,4,4,15,-,1"), 1, "a text from before the flag still reads")
		t.eq(DailyData.Decode("fell,4,4,15,-,1")[1].paid, nil)
	end)
end
