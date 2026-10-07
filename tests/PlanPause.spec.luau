--!nocheck
-- WorldPlan.Trees(pause): the forest plan is the one planner that costs
-- seconds (about 6 s in Lune, 11 s in Studio's client), and it froze the
-- server right after players came in and the client right after it joined.
-- Handed a `pause` (a time slice's step) it yields between placement
-- attempts instead, and the trees it plans are exactly the same.
return function(t)
	local TimeSlice = t.shared("TimeSlice")

	local function plan(pause)
		local loader = t.loader({ isolated = true })
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		return WorldPlan.Trees(pause), WorldPlan
	end

	t.test("with a time slice as the pause: the same trees, the frame given back all through the work", function()
		local plain = plan(nil)
		-- A fake clock where every look is 1 ms of work and a slice is 0.5 s.
		local now = 0
		local yields, calls = 0, 0
		local slice = TimeSlice.new({
			budget = 0.5,
			clock = function()
				now += 0.001
				return now
			end,
			wait = function()
				yields += 1
			end,
		})
		local paused, WorldPlan = plan(function()
			calls += 1
			slice.step()
		end)
		t.eq(#paused, #plain, "the same number of trees")
		for i, spot in ipairs(plain) do
			local other = paused[i]
			t.eq(other.woodId, spot.woodId)
			t.eq(other.biome, spot.biome)
			t.eq(other.position, spot.position)
		end
		t.ok(calls > 1000, calls .. " pauses: the planner offers the frame back all through its work")
		t.ok(yields >= 10, yields .. " yields while planning")
		t.eq(slice.yields(), yields)
		t.ok(rawequal(WorldPlan.Trees(), paused), "the plan is cached for the next caller")
	end)
end
