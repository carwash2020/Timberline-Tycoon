--!nocheck
-- The wait between save retries: doubling, capped, bounded in tries and in
-- total waiting, and it stops at once when asked.
return function(t)
	local Backoff = t.shared("Backoff")

	t.test("the delay doubles from the base and stops at the cap", function()
		t.eq(Backoff.Delay(0), 0)
		t.eq(Backoff.Delay(1), 1)
		t.eq(Backoff.Delay(2), 2)
		t.eq(Backoff.Delay(3), 4)
		t.eq(Backoff.Delay(5), 16)
		t.eq(Backoff.Delay(6), 20, "capped")
		t.eq(Backoff.Delay(500), 20, "a huge count does not overflow")
		t.eq(Backoff.Delay(2, { base = 0.5, cap = 3 }), 1)
		t.eq(Backoff.Delay(9, { base = 0.5, cap = 3 }), 3)
		t.eq(Backoff.Delay(2, { base = -4 }), 2, "a bad option falls back to the default")
	end)

	t.test("the schedule has one wait fewer than the tries, and respects the budget", function()
		t.eq(Backoff.Schedule(), { 1, 2, 4, 8 })
		t.eq(Backoff.Schedule({ maxTries = 3 }), { 1, 2 })
		t.eq(Backoff.Schedule({ maxTries = 1 }), {})
		t.eq(Backoff.Schedule({ maxTries = 10, budget = 10 }), { 1, 2, 4, 3 }, "the last wait is trimmed")
		local total = 0
		for _, wait in ipairs(Backoff.Schedule({ maxTries = 50, budget = 30 })) do
			total += wait
		end
		t.ok(total <= 30)
	end)

	t.test("retry stops at the first success", function()
		local slept = {}
		local ok, tries = Backoff.Retry(function(n)
			return n == 3
		end, function(s)
			table.insert(slept, s)
		end)
		t.eq({ ok, tries }, { true, 3 })
		t.eq(slept, { 1, 2 })
	end)

	t.test("retry gives up when the schedule is spent, and an error counts as a failure", function()
		local slept = {}
		local calls = 0
		local ok, tries = Backoff.Retry(function()
			calls += 1
			error("DataStore request was added to queue")
		end, function(s)
			table.insert(slept, s)
		end, { maxTries = 4 })
		t.eq({ ok, tries, calls }, { false, 4, 4 })
		t.eq(slept, { 1, 2, 4 })
	end)

	t.test("retry stops at once when told to (the player left)", function()
		local calls = 0
		local gone = false
		local ok, tries = Backoff.Retry(
			function()
				calls += 1
				gone = true
				return false
			end,
			function() end,
			nil,
			function()
				return gone
			end
		)
		t.eq({ ok, tries, calls }, { false, 1, 1 })
	end)
end
