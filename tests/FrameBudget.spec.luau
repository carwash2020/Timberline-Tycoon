--!nocheck
-- FrameBudget: the one per-frame budget the forest, the terrain, the deferred
-- queue and the mesh swaps share (launch performance, 14 October 2026). Every
-- clock and frame counter here is injected: no real time.
return function(t)
	local FrameBudget = t.shared("FrameBudget")
	local TimeSlice = t.shared("TimeSlice")

	local function world()
		local w = { now = 0, frame = 1 }
		function w.clock()
			return w.now
		end
		function w.nextFrame()
			w.frame += 1
		end
		return w
	end

	t.test("the frame's spend is counted from its first job and shared by every job", function()
		local w = world()
		local budget = FrameBudget.new({
			budget = 0.010,
			clock = w.clock,
			frame = function()
				return w.frame
			end,
		})
		budget.Begin() -- job A wakes
		w.now = 0.006
		t.eq(budget.Over(), false, "6 of 10 ms")
		budget.Begin() -- job B wakes in the same frame: it does not start a new count
		w.now = 0.011
		t.eq(budget.Over(), true, "A and B together passed 10 ms")
		t.ok(budget.Spent() >= 0.010)
		w.nextFrame()
		w.now = 0.020
		budget.Begin() -- a new frame
		t.eq(budget.Over(), false, "a fresh frame starts from zero")
		w.now = 0.0285
		t.eq(budget.Over(), false, "8.5 ms into the new frame")
		w.now = 0.0301
		t.eq(budget.Over(), true)
	end)

	t.test("without a frame counter, a gap in the calls is a new frame", function()
		local w = world()
		local budget = FrameBudget.new({ budget = 0.0095, clock = w.clock, gap = 0.002 })
		budget.Begin()
		-- Calls 1 ms apart (jobs working back to back): one frame.
		for i = 1, 9 do
			w.now = i * 0.001
			t.eq(budget.Over(), false, i .. " ms in")
		end
		w.now = 0.010
		t.eq(budget.Over(), true, "10 ms in one run of calls")
		w.now = 0.030 -- the engine had the rest of the frame
		budget.Begin()
		w.now = 0.031
		t.eq(budget.Over(), false, "a new frame")
	end)

	t.test("the limit can change: more of the frame while nobody plays, less after", function()
		local w = world()
		local playing = false
		local budget = FrameBudget.new({
			budget = function()
				return if playing then 0.010 else 0.030
			end,
			clock = w.clock,
			frame = function()
				return w.frame
			end,
		})
		budget.Begin()
		w.now = 0.020
		t.eq(budget.Over(), false, "30 ms before anyone plays")
		playing = true
		t.eq(budget.Over(), true, "10 ms once a player can play")
		t.eq(budget.Limit(), 0.010)
	end)

	t.test("three jobs sharing one budget spend about one budget a frame, not three", function()
		local w = world()
		local waits = 0
		local budget = FrameBudget.new({
			budget = 0.0115,
			clock = w.clock,
			frame = function()
				return w.frame
			end,
		})
		-- Each job's unit of work costs 1 ms; a "frame" is the three jobs taking turns.
		local slices = {}
		for i = 1, 3 do
			slices[i] = TimeSlice.new({
				frame = budget,
				clock = w.clock,
				wait = function()
					waits += 1
				end,
			})
		end
		local perFrame = {}
		for _ = 1, 20 do
			local before = w.now
			-- Each job wakes in the new frame (the engine resumes its task.wait),
			-- then does units until its slice says to give the frame back.
			for i = 1, 3 do
				slices[i].reset()
				repeat
					w.now += 0.001
				until slices[i].step()
			end
			table.insert(perFrame, w.now - before)
			w.nextFrame()
			w.now += 0.010 -- the rest of the frame
		end
		local worst = 0
		for _, spent in ipairs(perFrame) do
			worst = math.max(worst, spent)
		end
		-- Alone, each would take 12 ms (36 ms in all). Shared: the first spends the
		-- budget, the others do one unit each (a job always finishes its unit).
		t.ok(worst <= 0.0115 + 3 * 0.001 + 1e-9, string.format("a frame took %.1f ms", worst * 1000))
		t.ok(worst >= 0.0115, "and the budget really was used")
		t.eq(waits, 60, "every job yielded every frame (none starved, none ran on)")
		t.ok(budget.Stats().worst <= 0.0115 + 3 * 0.001 + 1e-9, "the budget's own worst frame agrees")
	end)

	t.test("a job that wakes into a spent frame still does one unit, then yields", function()
		local w = world()
		local budget = FrameBudget.new({
			budget = 0.005,
			clock = w.clock,
			frame = function()
				return w.frame
			end,
		})
		budget.Begin()
		w.now = 0.006
		t.eq(budget.Over(), true)
		local slice = TimeSlice.new({ frame = budget, clock = w.clock, wait = function() end })
		w.now += 0.001 -- its one unit
		t.eq(slice.step(), true, "it yields at once: the frame is spent")
		t.eq(slice.yields(), 1)
	end)

	t.test("TimeSlice with a shared budget has no slice of its own, and reports its longest stretch", function()
		local w = world()
		local budget = FrameBudget.new({
			budget = 0.010,
			clock = w.clock,
			frame = function()
				return w.frame
			end,
		})
		local slice = TimeSlice.new({
			frame = budget,
			clock = w.clock,
			wait = function()
				w.nextFrame()
			end,
		})
		w.now = 0.004
		t.eq(slice.step(), false)
		w.now = 0.0095
		t.eq(slice.step(), false)
		w.now = 0.0105
		t.eq(slice.step(), true)
		t.ok(math.abs(slice.longest() - 0.0105) < 1e-9, "the longest stretch between yields: " .. slice.longest())
		w.now = 0.014
		slice.step()
		slice.finish()
		t.ok(slice.longest() >= 0.0105)
	end)

	t.test("Adapt: all of the budget up to a 20 ms frame, a quarter of it at 40 ms", function()
		t.eq(FrameBudget.Adapt(4, 0.016), 4)
		t.eq(FrameBudget.Adapt(4, 0.020), 4)
		t.ok(math.abs(FrameBudget.Adapt(4, 0.030) - 4 * 0.625) < 1e-9, "halfway: 62.5%")
		t.ok(math.abs(FrameBudget.Adapt(4, 0.040) - 1) < 1e-9)
		t.ok(math.abs(FrameBudget.Adapt(4, 0.200) - 1) < 1e-9, "never below a quarter")
		-- A loop that steps every other frame (30 Hz) is not slow at 33 ms.
		t.eq(FrameBudget.Adapt(4, 1 / 30, 1 / 30), 4)
		t.ok(FrameBudget.Adapt(4, 0.080, 1 / 30) < 4)
	end)
end
