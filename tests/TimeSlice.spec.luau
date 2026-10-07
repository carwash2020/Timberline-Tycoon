--!nocheck
-- TimeSlice: the work-then-yield budget used by the forest planter, the
-- deferred build queue and the client's forest plan.
return function(t)
	local TimeSlice = t.shared("TimeSlice")

	local function fakeClock()
		local clock = { now = 0 }
		function clock.read()
			return clock.now
		end
		return clock
	end

	t.test("it yields only when the budget is spent, then starts a new slice", function()
		local clock = fakeClock()
		local waits = 0
		local slice = TimeSlice.new({
			budget = 0.01,
			clock = clock.read,
			wait = function()
				waits += 1
			end,
		})
		clock.now = 0.004
		t.eq(slice.step(), false, "4 ms of 10 spent")
		clock.now = 0.009
		t.eq(slice.step(), false)
		t.eq(waits, 0)
		clock.now = 0.010
		t.eq(slice.step(), true, "the budget is spent: it yielded")
		t.eq(waits, 1)
		clock.now = 0.015
		t.eq(slice.step(), false, "a new slice began after the yield")
		clock.now = 0.020
		t.eq(slice.step(), true)
		t.eq(slice.yields(), 2)
	end)

	t.test("reset starts a fresh slice (after a yield of the caller's own)", function()
		local clock = fakeClock()
		local waits = 0
		local slice = TimeSlice.new({
			budget = 0.01,
			clock = clock.read,
			wait = function()
				waits += 1
			end,
		})
		clock.now = 5
		slice.reset()
		t.eq(slice.step(), false, "no time has passed since the reset")
		t.eq(waits, 0)
	end)

	t.test("the default budget is a fraction of a frame", function()
		t.ok(TimeSlice.DefaultBudget > 0 and TimeSlice.DefaultBudget <= 0.016)
	end)

	t.test("a long job built on it yields once per budget, never starving the frame", function()
		local clock = fakeClock()
		local waits = 0
		local slice = TimeSlice.new({
			budget = 0.012,
			clock = clock.read,
			wait = function()
				waits += 1
			end,
		})
		-- 1,000 units of 1 ms each = 1 s of work: about 83 yields.
		for _ = 1, 1000 do
			clock.now += 0.001
			slice.step()
		end
		t.ok(waits >= 80 and waits <= 90, "yielded " .. waits .. " times")
	end)
end
