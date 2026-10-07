--!nocheck
-- WorkPool: yielding jobs side by side with a join barrier (the mesh
-- preload, the NPC build barrier). One CreateMeshPartAsync costs a third of
-- a second of network time, so 153 of them in a row held NPCService.Init for
-- 60 s; run 24 at a time the same loads take a few seconds.
return function(t)
	local WorkPool = t.shared("WorkPool")

	local function scheduler()
		local s = { now = 0, parked = {} }
		local main = coroutine.running() -- (Lune runs scripts inside a thread, so isyieldable() is no test)
		function s.clock()
			return s.now
		end
		function s.spawn(fn)
			local co = coroutine.create(fn)
			local ok, err = coroutine.resume(co)
			assert(ok, err)
			if coroutine.status(co) ~= "dead" then
				table.insert(s.parked, co)
			end
		end
		function s.wait()
			if coroutine.running() ~= main then
				coroutine.yield()
				return
			end
			s.now += 0.1
			local running = s.parked
			s.parked = {}
			for _, co in ipairs(running) do
				local ok, err = coroutine.resume(co)
				assert(ok, err)
				if coroutine.status(co) ~= "dead" then
					table.insert(s.parked, co)
				end
			end
		end
		return s
	end

	-- A job that takes `ticks` waits (a network call), recording peak overlap.
	local function networkJob(s, state, ticks)
		return function(_item, _index)
			state.running += 1
			state.peak = math.max(state.peak, state.running)
			for _ = 1, ticks do
				s.wait()
			end
			state.running -= 1
			state.done += 1
		end
	end

	t.test("every job runs once, at most `concurrency` at a time, and the join waits for all", function()
		local s = scheduler()
		local state = { running = 0, peak = 0, done = 0 }
		local items = {}
		for i = 1, 50 do
			items[i] = i
		end
		local result = WorkPool.Run(items, networkJob(s, state, 4), {
			concurrency = 8,
			spawn = s.spawn,
			wait = s.wait,
			clock = s.clock,
		})
		t.eq(state.done, 50)
		t.eq(state.peak, 8, "eight at a time")
		t.eq(result.total, 50)
		t.eq(result.completed, 50)
		t.eq(result.errors, 0)
		t.eq(result.timedOut, false)
	end)

	t.test("side by side beats one after another: 153 loads at 4 ticks each", function()
		local items = {}
		for i = 1, 153 do
			items[i] = i
		end
		local function elapsed(concurrency)
			local s = scheduler()
			local state = { running = 0, peak = 0, done = 0 }
			local result = WorkPool.Run(items, networkJob(s, state, 4), {
				concurrency = concurrency,
				spawn = s.spawn,
				wait = s.wait,
				clock = s.clock,
			})
			return result.seconds
		end
		local serial = elapsed(1)
		local parallel = elapsed(24)
		t.ok(serial > 10 * parallel, string.format("serial %.1f s, parallel %.1f s", serial, parallel))
	end)

	t.test("a job that errors is counted and the rest still run", function()
		local s = scheduler()
		local seen = {}
		local errors = {}
		local result = WorkPool.Run({ 1, 2, 3, 4 }, function(item)
			if item == 2 then
				error("boom")
			end
			table.insert(seen, item)
		end, {
			concurrency = 2,
			spawn = s.spawn,
			wait = s.wait,
			clock = s.clock,
			onError = function(index, err)
				table.insert(errors, index)
			end,
		})
		table.sort(seen)
		t.eq(seen, { 1, 3, 4 })
		t.eq(result.errors, 1)
		t.eq(result.completed, 4)
		t.eq(errors, { 2 })
	end)

	t.test("the join gives up at the timeout and starts no new jobs", function()
		local s = scheduler()
		local state = { running = 0, peak = 0, done = 0 }
		local items = {}
		for i = 1, 40 do
			items[i] = i
		end
		-- Each job takes 50 ticks (5 s); the join waits only 1 s.
		local result = WorkPool.Run(items, networkJob(s, state, 50), {
			concurrency = 4,
			timeout = 1,
			spawn = s.spawn,
			wait = s.wait,
			clock = s.clock,
		})
		t.eq(result.timedOut, true)
		t.ok(result.seconds < 2, "returned near the timeout")
		t.eq(state.done, 0, "nothing had finished yet")
		-- The running jobs finish by themselves; nothing new starts after the give-up.
		for _ = 1, 100 do
			s.wait()
		end
		t.eq(state.done, 4, "only the four that were running finished")
	end)

	t.test("an empty list returns at once", function()
		local s = scheduler()
		local result = WorkPool.Run({}, function() end, { spawn = s.spawn, wait = s.wait, clock = s.clock })
		t.eq(result.total, 0)
		t.eq(result.timedOut, false)
	end)
end
