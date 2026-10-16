--!strict
-- PerfProbe: what the first seconds after joining cost, in a few lines of
-- Output, so a Studio run says whether the frames after "can play" are smooth.
-- (Studio's log of 14 October 2026: playable at +4.6 s, but heavy work ran
-- until +11.9 s. Studio cannot be run from the build environment, so this is how Connor reads it.)
--
-- The client feeds it every Heartbeat (`Frame(dt)`, dt = the frame's length)
-- from the moment the character first spawns, and tells it three moments:
--
--   MarkSpawn()    the character first spawned: "+0" for every line below
--   MarkCanPlay()  the save is in and the loading card is gone
--   MarkBuilt()    the server says the whole world is built
--
-- Lines (all `[Perf] ...`, about nine in a whole run, never per frame):
--   [Perf] can play at +X.Xs
--   [Perf] fully built at +X.Xs
--   [Perf] worst frame after spawn: N ms at +X.Xs, frames over 33 ms: n, over 50 ms: m
--      every 5 s for the seconds since the last line, then once at +30 s for
--      the whole 30 s; after that the probe is done and prints nothing more.
--
-- Pure: the clock and the log are injected.

local PerfProbe = {}

export type Options = {
	clock: (() -> number)?,
	log: ((line: string) -> ())?,
	every: number?, -- seconds between rolling lines (default 5)
	finalAt: number?, -- seconds after spawn of the last, whole-run line (default 30)
	slowMs: number?, -- a "slow" frame (default 33)
	hitchMs: number?, -- a "hitch" (default 50)
}

export type Stats = {
	frames: number,
	worstMs: number,
	worstAt: number, -- seconds after spawn
	overSlow: number,
	overHitch: number,
}

export type Probe = {
	MarkSpawn: () -> (),
	MarkCanPlay: () -> (),
	MarkBuilt: () -> (),
	Frame: (dt: number) -> (),
	Stats: () -> Stats, -- the whole run so far
	Done: () -> boolean,
	Lines: () -> { string }, -- every line printed, for specs
}

function PerfProbe.new(options: Options?): Probe
	local clock = (options and options.clock) or os.clock
	local logFn = (options and options.log) or function(_line: string) end
	local every = (options and options.every) or 5
	local finalAt = (options and options.finalAt) or 30
	local slowMs = (options and options.slowMs) or 33
	local hitchMs = (options and options.hitchMs) or 50

	local spawnedAt: number? = nil
	local printed: { string } = {}
	local canPlayDone, builtDone, done = false, false, false
	-- The whole run, and the window since the last rolling line.
	local whole: Stats = { frames = 0, worstMs = 0, worstAt = 0, overSlow = 0, overHitch = 0 }
	local window: Stats = { frames = 0, worstMs = 0, worstAt = 0, overSlow = 0, overHitch = 0 }
	local nextRolling = every

	local function say(line: string)
		table.insert(printed, line)
		logFn(line)
	end

	local function since(): number
		local at = spawnedAt
		return if at then clock() - at else 0
	end

	local function line(stats: Stats): string
		return string.format(
			"[Perf] worst frame after spawn: %.0f ms at +%.1fs, frames over %d ms: %d, over %d ms: %d",
			stats.worstMs,
			stats.worstAt,
			slowMs,
			stats.overSlow,
			hitchMs,
			stats.overHitch
		)
	end

	local function note(stats: Stats, ms: number, at: number)
		stats.frames += 1
		if ms > stats.worstMs then
			stats.worstMs, stats.worstAt = ms, at
		end
		if ms > slowMs then
			stats.overSlow += 1
		end
		if ms > hitchMs then
			stats.overHitch += 1
		end
	end

	local probe = {} :: Probe
	probe.MarkSpawn = function()
		if spawnedAt == nil then
			spawnedAt = clock()
		end
	end
	probe.MarkCanPlay = function()
		if canPlayDone then
			return
		end
		canPlayDone = true
		if spawnedAt == nil then
			spawnedAt = clock() -- (no spawn seen: count from here)
		end
		say(string.format("[Perf] can play at +%.1fs", since()))
	end
	probe.MarkBuilt = function()
		if builtDone then
			return
		end
		builtDone = true
		if spawnedAt == nil then
			spawnedAt = clock()
		end
		say(string.format("[Perf] fully built at +%.1fs", since()))
	end
	probe.Frame = function(dt: number)
		if done or spawnedAt == nil then
			return
		end
		local at = since()
		local ms = dt * 1000
		note(whole, ms, at)
		note(window, ms, at)
		if at >= finalAt then
			done = true
			say(line(whole))
			return
		end
		if at >= nextRolling then
			say(line(window))
			window = { frames = 0, worstMs = 0, worstAt = 0, overSlow = 0, overHitch = 0 }
			nextRolling += every
			-- (a long stall can skip several marks: do not print them all)
			if nextRolling <= at then
				nextRolling = (math.floor(at / every) + 1) * every
			end
		end
	end
	probe.Stats = function(): Stats
		return table.clone(whole)
	end
	probe.Done = function(): boolean
		return done
	end
	probe.Lines = function(): { string }
		return table.clone(printed)
	end
	return probe
end

return PerfProbe
