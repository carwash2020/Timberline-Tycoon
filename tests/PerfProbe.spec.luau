--!nocheck
-- PerfProbe: the [Perf] lines the client prints so a Studio run says whether the
-- frames after "can play" are smooth. A fake clock; no real time.
return function(t)
	local PerfProbe = t.shared("PerfProbe")

	local function world(options)
		local w = { now = 100, lines = {} }
		options = options or {}
		w.probe = PerfProbe.new({
			clock = function()
				return w.now
			end,
			log = function(line)
				table.insert(w.lines, line)
			end,
			every = options.every,
			finalAt = options.finalAt,
		})
		-- One frame: the clock moves by dt and the probe is told.
		function w.frame(dt)
			w.now += dt
			w.probe.Frame(dt)
		end
		return w
	end

	t.test("frames before the character spawns are not counted", function()
		local w = world()
		w.frame(0.2)
		t.eq(w.probe.Stats().frames, 0)
		w.probe.MarkSpawn()
		w.frame(0.016)
		t.eq(w.probe.Stats().frames, 1)
	end)

	t.test("the worst frame, when it was, and the frames over 33 and 50 ms", function()
		local w = world()
		w.probe.MarkSpawn()
		for _ = 1, 10 do
			w.frame(0.016)
		end
		w.frame(0.040) -- over 33
		w.frame(0.016)
		w.frame(0.120) -- the worst, over 50 too
		w.frame(0.034) -- over 33
		w.frame(0.050) -- exactly 50: over 33, not over 50
		local stats = w.probe.Stats()
		t.eq(stats.frames, 15)
		t.ok(math.abs(stats.worstMs - 120) < 1e-6)
		t.eq(stats.overSlow, 4, "40, 120, 34 and 50 ms")
		t.eq(stats.overHitch, 1, "only the 120 ms one is over 50")
		-- The worst frame happened 10 * 16 + 40 + 16 + 120 ms after the spawn.
		t.ok(math.abs(stats.worstAt - (0.160 + 0.040 + 0.016 + 0.120)) < 1e-6, "worst at +" .. stats.worstAt)
	end)

	t.test("'can play' and 'fully built' print once each, as +seconds after the spawn", function()
		local w = world()
		w.probe.MarkSpawn()
		w.now += 4.6
		w.probe.MarkCanPlay()
		w.probe.MarkCanPlay()
		w.now += 7.3
		w.probe.MarkBuilt()
		w.probe.MarkBuilt()
		t.eq(w.lines, { "[Perf] can play at +4.6s", "[Perf] fully built at +11.9s" })
	end)

	t.test(
		"a rolling summary every 5 s for the seconds since the last, then the whole 30 s once, then silence",
		function()
			local w = world()
			w.probe.MarkSpawn()
			for second = 1, 40 do
				-- 60 frames a second; second 7 has one 90 ms hitch.
				for i = 1, 60 do
					w.frame(if second == 7 and i == 1 then 0.090 else 1 / 60)
				end
			end
			local rolling = {}
			for _, line in ipairs(w.lines) do
				table.insert(rolling, line)
			end
			-- 5, 10, 15, 20, 25 s rolling, 30 s final: six lines, then nothing more.
			t.eq(#rolling, 6, table.concat(rolling, "\n"))
			for _, line in ipairs(rolling) do
				t.ok(
					string.find(
						line,
						"^%[Perf%] worst frame after spawn: %d+ ms at %+%d+%.%ds, frames over 33 ms: %d+, over 50 ms: %d+$"
					),
					line
				)
			end
			t.ok(string.find(rolling[1], "worst frame after spawn: 17 ms", 1, true), "the first window: " .. rolling[1])
			t.ok(string.find(rolling[1], "frames over 33 ms: 0", 1, true))
			t.ok(
				string.find(rolling[2], "worst frame after spawn: 90 ms", 1, true),
				"the hitch in second 7 is in the 5-10 s window: " .. rolling[2]
			)
			t.ok(string.find(rolling[2], "frames over 33 ms: 1, over 50 ms: 1", 1, true))
			t.ok(
				string.find(rolling[3], "worst frame after spawn: 17 ms", 1, true),
				"the next window is clean again: " .. rolling[3]
			)
			t.ok(
				string.find(rolling[6], "worst frame after spawn: 90 ms", 1, true),
				"the final line covers the whole run: " .. rolling[6]
			)
			t.ok(string.find(rolling[6], "frames over 33 ms: 1, over 50 ms: 1", 1, true))
			t.eq(w.probe.Done(), true)
			local count = #w.lines
			for _ = 1, 600 do
				w.frame(0.2)
			end
			t.eq(#w.lines, count, "nothing more after the final line")
		end
	)

	t.test("a long stall does not print one line for every window it skipped", function()
		local w = world()
		w.probe.MarkSpawn()
		w.frame(0.016)
		w.frame(12) -- a 12 s stall
		t.eq(#w.lines, 1)
		w.frame(0.016)
		t.eq(#w.lines, 1)
	end)

	t.test("it never prints more than about nine lines in a whole run", function()
		local w = world()
		w.probe.MarkSpawn()
		w.probe.MarkCanPlay()
		for _ = 1, 5000 do
			w.frame(0.05)
		end
		w.probe.MarkBuilt()
		t.ok(#w.lines <= 9, #w.lines .. " lines")
	end)
end
