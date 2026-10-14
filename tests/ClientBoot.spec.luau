--!nocheck
-- ClientBoot: the client's deferred Start queue (launch performance, 14
-- October 2026). Wait, clock and warn are injected: no scheduler, no real time.
return function(t)
	local ClientBoot = t.shared("ClientBoot")

	local function world(options)
		local w = { now = 0, frames = 0, warnings = {}, logs = {}, calls = {} }
		options = options or {}
		w.boot = ClientBoot.new({
			clock = function()
				return w.now
			end,
			wait = function()
				w.frames += 1
				if w.onFrame then
					w.onFrame(w.frames)
				end
			end,
			warn = function(text)
				table.insert(w.warnings, text)
			end,
			log = function(line)
				table.insert(w.logs, line)
			end,
			maxPerFrame = options.maxPerFrame,
			budget = options.budget,
		})
		function w.register(name, priority, cost)
			w.boot.Register(name, {
				priority = priority,
				start = function()
					table.insert(w.calls, name)
					w.now += cost or 0
				end,
			})
		end
		return w
	end

	t.test("nothing starts until the player can play", function()
		local w = world()
		w.register("WoodFX", 14)
		w.register("HammerController", 10)
		t.eq(w.calls, {})
		t.eq(w.boot.Pending(), 2)
		t.eq(w.boot.Released(), false)
		t.eq(w.boot.IsStarted("WoodFX"), false)
	end)

	t.test("released, they start soonest-needed first (priority, then the order registered)", function()
		local w = world({ maxPerFrame = 2 })
		w.register("WoodFX", 14)
		w.register("LuxFX", 15)
		w.register("BlueprintPlacer", 11)
		w.register("HammerController", 10)
		w.register("DialogueUI", 12)
		w.register("TownFX", 21)
		w.register("RegionFX", 21) -- same priority: registered order
		t.eq(
			w.boot.Order(),
			{ "HammerController", "BlueprintPlacer", "DialogueUI", "WoodFX", "LuxFX", "TownFX", "RegionFX" }
		)
		w.boot.Release()
		t.eq(
			w.calls,
			{ "HammerController", "BlueprintPlacer", "DialogueUI", "WoodFX", "LuxFX", "TownFX", "RegionFX" },
			"in order"
		)
		t.eq(w.boot.Started(), w.calls)
		t.eq(w.boot.Drained(), true)
		t.eq(w.boot.Pending(), 0)
	end)

	t.test("one or two a frame, never the lot at once", function()
		local w = world({ maxPerFrame = 2 })
		for i = 1, 9 do
			w.register("M" .. i, i)
		end
		local perFrame = {}
		local seen = 0
		w.onFrame = function()
			table.insert(perFrame, #w.calls - seen)
			seen = #w.calls
		end
		w.boot.Release()
		t.eq(#w.calls, 9)
		for _, n in ipairs(perFrame) do
			t.ok(n >= 1 and n <= 2, "a frame started " .. n)
		end
		t.ok(#perFrame >= 5, #perFrame .. " frames for nine Starts")
	end)

	t.test("a second Start in a frame only runs when the first was quick (under the budget)", function()
		local w = world({ maxPerFrame = 2, budget = 0.004 })
		w.register("Slow", 1, 0.030) -- 30 ms
		w.register("Quick", 2, 0.001)
		w.register("Quick2", 3, 0.001)
		local perFrame = {}
		local seen = 0
		w.onFrame = function()
			table.insert(perFrame, #w.calls - seen)
			seen = #w.calls
		end
		w.boot.Release()
		t.eq(perFrame[1], 1, "the slow one had its frame to itself")
		t.eq(perFrame[2], 2, "the two quick ones shared one")
	end)

	t.test("first use starts it at once, and only once", function()
		local w = world()
		w.register("HammerController", 10)
		w.register("BlueprintPlacer", 11)
		t.eq(w.boot.Ensure("BlueprintPlacer"), true, "started just now")
		t.eq(w.calls, { "BlueprintPlacer" })
		t.eq(w.boot.Ensure("BlueprintPlacer"), false, "already started: nothing happens")
		t.eq(w.calls, { "BlueprintPlacer" })
		t.eq(w.boot.IsStarted("BlueprintPlacer"), true)
		t.eq(w.boot.Order(), { "HammerController" })
		-- The queue reaching it later does not start it again.
		w.boot.Release()
		t.eq(w.calls, { "BlueprintPlacer", "HammerController" }, "each Start ran exactly once")
		t.eq(w.boot.Ensure("HammerController"), false)
		t.eq(w.boot.Ensure("NoSuchController"), false, "an unregistered name does nothing")
	end)

	t.test("a Start that asks for itself (or is used from inside its own Start) is not run twice", function()
		local w = world()
		local runs = 0
		w.boot.Register("Self", {
			priority = 1,
			start = function()
				runs += 1
				w.boot.Ensure("Self")
			end,
		})
		w.boot.Ensure("Self")
		w.boot.Release()
		t.eq(runs, 1)
	end)

	t.test("a Start that errors warns once with the controller's name, and the rest still start", function()
		local w = world()
		w.boot.Register("Broken", {
			priority = 1,
			start = function()
				error("it broke")
			end,
		})
		w.register("Fine", 2)
		w.boot.Release()
		t.eq(#w.warnings, 1)
		t.ok(string.find(w.warnings[1], "[Client] Broken failed to start", 1, true), w.warnings[1])
		t.ok(string.find(w.warnings[1], "it broke", 1, true))
		t.eq(w.calls, { "Fine" })
		t.eq(w.boot.IsStarted("Broken"), true, "counted as started: it must not run twice")
		t.eq(w.boot.Drained(), true)
	end)

	t.test("OnDrained fires when the last one has started, now if it already has", function()
		local w = world()
		w.register("A", 1)
		w.register("B", 2)
		local drained = 0
		w.boot.OnDrained(function()
			drained += 1
		end)
		w.boot.Ensure("A")
		t.eq(drained, 0)
		w.boot.Release()
		t.eq(drained, 1)
		local late = 0
		w.boot.OnDrained(function()
			late += 1
		end)
		t.eq(late, 1)
		w.boot.Release() -- a second release is harmless
		t.eq(drained, 1)
	end)

	t.test("releasing with nothing queued drains at once", function()
		local w = world()
		w.boot.Release()
		t.eq(w.boot.Drained(), true)
	end)

	t.test("only a slow Start is logged, with its name and milliseconds", function()
		local w = world()
		w.register("Quick", 1, 0.005)
		w.register("DialogueUI", 2, 0.150)
		w.boot.Release()
		t.eq(#w.logs, 1, "the log never fills")
		t.eq(w.logs[1], "[Perf] client DialogueUI Start took 150 ms")
		local name, seconds = w.boot.Slowest()
		t.eq(name, "DialogueUI")
		t.ok(math.abs(seconds - 0.15) < 1e-9)
	end)

	t.test("ReleaseWhenPlaying waits for the save, then settles a few frames, then releases", function()
		local w = world()
		w.register("WoodFX", 1)
		local playing = false
		local frames = 0
		local function wait()
			frames += 1
			if frames == 7 then
				playing = true
			end
		end
		ClientBoot.ReleaseWhenPlaying(w.boot, function()
			return playing
		end, {
			wait = wait,
			clock = function()
				return 0
			end,
			settleFrames = 5,
		})
		t.eq(frames, 7 + 5, "7 frames for the save, 5 to settle")
		t.eq(w.calls, { "WoodFX" })
		t.eq(w.boot.Released(), true)
	end)

	t.test("ReleaseWhenPlaying never waits for ever: a save that never loads still releases at the timeout", function()
		local w = world()
		w.register("WoodFX", 1)
		local now = 0
		ClientBoot.ReleaseWhenPlaying(w.boot, function()
			return false
		end, {
			wait = function()
				now += 1
			end,
			clock = function()
				return now
			end,
			timeout = 30,
			settleFrames = 0,
		})
		t.eq(now, 30)
		t.eq(w.boot.Released(), true)
		t.eq(w.calls, { "WoodFX" })
	end)

	t.test("the shared Default queue: Ensure does nothing where nothing is registered", function()
		t.eq(ClientBoot.Ensure("Anything"), false)
	end)

	t.test("EarlyHandler: an event that arrives before the Start starts it and hands it the event once", function()
		local w = world()
		local module = { got = {} }
		function module.Handle(...)
			table.insert(module.got, { ... })
		end
		w.register("BlueprintPlacer", 11)
		local handler = ClientBoot.EarlyHandler(w.boot, "BlueprintPlacer", module, "Handle", "PlaceBox")
		handler("Hammer", { uid = "x" }) -- not the kind it listens for
		t.eq(w.calls, {})
		t.eq(#module.got, 0)
		handler("PlaceBox", { uid = "box1" })
		t.eq(w.calls, { "BlueprintPlacer" }, "started on the spot")
		t.eq(#module.got, 1)
		t.eq(module.got[1][1], "PlaceBox")
		t.eq(module.got[1][2].uid, "box1", "with the event it had missed")
		handler("PlaceBox", { uid = "box2" })
		t.eq(#module.got, 1, "once started, its own listener has the events: this one does nothing")
		t.eq(w.calls, { "BlueprintPlacer" })
	end)

	t.test("EarlyHandler without a kind takes every event; a missing handler or module is harmless", function()
		local w = world()
		w.register("DialogueUI", 12)
		local got = 0
		local handler = ClientBoot.EarlyHandler(w.boot, "DialogueUI", {
			Show = function()
				got += 1
			end,
		}, "Show", nil)
		handler({ text = "hello" })
		t.eq(got, 1)
		local w2 = world()
		w2.register("X", 1)
		ClientBoot.EarlyHandler(w2.boot, "X", {}, "Missing", nil)("anything")
		t.eq(w2.calls, { "X" }, "it still started")
		ClientBoot.EarlyHandler(w2.boot, "Unregistered", {}, "Show", nil)("anything") -- nothing registered: nothing happens
	end)
end
