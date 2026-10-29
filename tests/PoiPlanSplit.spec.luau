--!nocheck
-- Studio log of 14 October 2026: the deferred build's "Points of interest
-- (plan)" step took 5.07 s in ONE step. The plan puts a point only where no
-- tree stands, so it needs the whole forest plan first, and the step ran it
-- with nobody giving the frame back. Now the plan is a queue of small units
-- run on a time slice (WorldPlan.PlanPointsOfInterest(pause) and
-- MapBuilder's deferPlanned). These pin that the split plan is byte for byte
-- the plan the single step made, on the same seed.
return function(t)
	local TimeSlice = t.shared("TimeSlice")

	-- Every field of every point, in the order they come, as one string.
	local function serialise(list)
		local parts = {}
		for _, poi in ipairs(list) do
			local nums = {}
			for _, v in ipairs({ poi.cframe:GetComponents() }) do
				table.insert(nums, string.format("%.9g", v))
			end
			table.insert(
				parts,
				table.concat({
					poi.id,
					poi.name,
					poi.kind,
					poi.region,
					table.concat(nums, ","),
					tostring(poi.seed),
					tostring(poi.secret),
					tostring(poi.text),
				}, "|")
			)
		end
		return table.concat(parts, "\n")
	end
	local function checksum(s)
		local h = 5381
		for i = 1, #s do
			h = (h * 33 + string.byte(s, i)) % 4294967296
		end
		return h
	end

	-- What origin/main's single-step PointsOfInterest returned (14 October
	-- 2026): five points, 1026 characters. A change to the planner that moves
	-- a point moves these numbers: that is a design change, not a refactor.
	local GOLDEN_COUNT, GOLDEN_LENGTH, GOLDEN_SUM = 5, 1028, 1408521780 -- T397: length re-pinned (the ground moved); hills closer to +18: same length, a point beside the Hills stands at the new ground height (244961358 before). T409: same five points, the valley height (1249355442 before). T413: same five points; a shoulder beside a main sits on the drive grade (3070203921 before).

	t.test("planned on a time slice, the points are byte for byte the single step's", function()
		local loader = t.loader({ isolated = true })
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		-- A fake clock: every read is 1 ms, so a 8 ms slice yields every few units.
		local now = 0
		local yields, calls, longestRun, run = 0, 0, 0, 0
		local slice = TimeSlice.new({
			budget = 0.008,
			clock = function()
				now += 0.001
				return now
			end,
			wait = function()
				yields += 1
				longestRun = math.max(longestRun, run)
				run = 0
			end,
		})
		local split = WorldPlan.PlanPointsOfInterest(function()
			calls += 1
			run += 1
			slice.step()
		end)
		local text = serialise(split)
		t.eq(#split, GOLDEN_COUNT)
		t.eq(#text, GOLDEN_LENGTH)
		t.eq(checksum(text), GOLDEN_SUM, "the split plan is the old plan")
		t.ok(calls > 1000, calls .. " units: the plan offers the frame back all through its work")
		t.ok(yields >= 20, yields .. " yields while planning")
		-- The unsplit call (the forest plan is cached now) gives the same bytes.
		local plain = WorldPlan.PlanPointsOfInterest(nil)
		t.eq(serialise(plain), text, "with and without the pause: identical")
		-- And the cached lookup the rest of the game uses.
		t.eq(serialise(WorldPlan.PointsOfInterest()), text)
		t.eq(serialise(WorldPlan.PointsOfInterest(function() end)), text, "a later caller gets the cached list")

		-- No unit of the point planning runs long (the forest plan is cached now;
		-- PlanPause.spec and ClientFreeze.spec cover its units).
		local last, worst, units = os.clock(), 0, 0
		WorldPlan.PlanPointsOfInterest(function()
			local at = os.clock()
			units += 1
			worst = math.max(worst, at - last)
			last = os.clock()
		end)
		t.ok(units >= 5, units .. " pauses: at least one per anchor")
		t.ok(worst < 0.05, string.format("longest stretch between two pauses was %.0f ms", worst * 1000))
	end)
end
