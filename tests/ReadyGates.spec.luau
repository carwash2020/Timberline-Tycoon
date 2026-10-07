--!nocheck
-- ReadyGates: the readiness gates the server's start-up is ordered by. A
-- gate shut means "refuse or wait", never "error".
return function(t)
	local ReadyGates = t.shared("ReadyGates")

	-- A tiny cooperative scheduler: wait() from the main thread lets every
	-- parked thread run once and moves the clock on a tenth of a second;
	-- wait() from a spawned thread parks it.
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

	local function gates(s)
		return ReadyGates.new({ clock = s.clock, wait = s.wait, spawn = s.spawn })
	end

	t.test("a gate starts shut, Set opens it, and opening twice is harmless", function()
		local s = scheduler()
		local g = gates(s)
		g.Define("world")
		t.eq(g.IsReady("world"), false)
		g.Set("world")
		t.eq(g.IsReady("world"), true)
		g.Set("world")
		t.eq(g.IsReady("world"), true)
		t.eq(g.IsReady("never defined"), false)
	end)

	t.test("OnReady runs now if open, else when it opens, and only once", function()
		local s = scheduler()
		local g = gates(s)
		local calls = {}
		g.OnReady("npcs", function()
			table.insert(calls, "first")
		end)
		t.eq(calls, {}, "not yet")
		g.Set("npcs")
		t.eq(calls, { "first" })
		g.Set("npcs")
		t.eq(calls, { "first" }, "a second Set does not rerun it")
		g.OnReady("npcs", function()
			table.insert(calls, "late")
		end)
		t.eq(calls, { "first", "late" }, "an open gate runs a new listener at once")
	end)

	t.test("Wait yields until the gate opens, and gives up at the timeout", function()
		local s = scheduler()
		local g = gates(s)
		local result
		s.spawn(function()
			result = g.Wait("itemMeshes", 5)
		end)
		t.eq(result, nil, "still waiting")
		s.wait()
		s.wait()
		g.Set("itemMeshes")
		s.wait()
		t.eq(result, true, "woke up when it opened")

		local timedOut
		s.spawn(function()
			timedOut = g.Wait("never", 1)
		end)
		for _ = 1, 15 do
			s.wait()
		end
		t.eq(timedOut, false, "a shut gate times out instead of hanging")
	end)

	t.test("Wait on an open gate returns at once and WaitAll needs every gate", function()
		local s = scheduler()
		local g = gates(s)
		g.Set("a")
		t.eq(g.Wait("a", 1), true)
		t.eq(g.AllReady({ "a", "b" }), false)
		g.Set("b")
		t.eq(g.AllReady({ "a", "b" }), true)
		t.eq(g.WaitAll({ "a", "b" }, 1), true)
	end)

	t.test("Guard refuses while shut (never errors) and passes through once open", function()
		local s = scheduler()
		local g = gates(s)
		local handled, refused = {}, {}
		local handler = g.Guard("services", function(player, value)
			table.insert(handled, { player, value })
		end, function(player)
			table.insert(refused, player)
		end)
		t.eq(handler("ann", 1), false, "refused")
		t.eq(handler("bob", 2), false)
		t.eq(handled, {})
		t.eq(refused, { "ann", "bob" })
		g.Set("services")
		t.eq(handler("cy", 3), true)
		t.eq(handled, { { "cy", 3 } })
		t.eq(refused, { "ann", "bob" })
		-- No refusal callback is fine too.
		local quiet = g.Guard("other", function() end)
		t.eq(quiet(), false)
	end)

	t.test("Snapshot says when each gate opened, in seconds since creation", function()
		local s = scheduler()
		local g = gates(s)
		s.now = 2
		g.Set("terrain")
		s.now = 7.5
		g.Set("world")
		local snap = g.Snapshot()
		t.eq(snap.terrain, 2)
		t.eq(snap.world, 7.5)
		t.eq(snap.npcs, nil)
		t.eq(g.Names(), { "terrain", "world" }, "names in the order they were first seen")
	end)
end
