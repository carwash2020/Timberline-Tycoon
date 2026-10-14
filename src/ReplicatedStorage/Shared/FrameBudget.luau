--!strict
-- FrameBudget: ONE per-frame time budget that several background jobs share.
-- The forest planter, the terrain writer, the deferred build queue and the
-- mesh swaps each took their own 12 ms slice a frame, so on a busy frame they
-- stacked to 30 ms and more (Studio log, 14 October 2026: heavy work until
-- +11.9 s with frames well over 33 ms). Here every job asks the same budget:
-- the frame's spend is counted from the first job that woke in it, and a job
-- that finds the frame's budget spent yields, whoever spent it. A job always
-- finishes the unit it is on (one tree, one terrain block) first, so each job
-- still moves at least one unit a frame and none starves.
--
--   Begin()   a job woke up (or starts): if this is a new frame, the frame's
--             spend starts now.
--   Over()    true when the frame's budget is spent (call after each unit).
--   Spent()   seconds spent so far this frame.
--   Limit()   the budget now (it may change: bigger while nobody plays yet).
--
-- A new frame is told by `frame()` (a counter that changes every frame, e.g. a
-- Heartbeat count) or, with none, by a gap in the calls longer than `gap`
-- seconds (jobs that run in one frame call back to back; the engine's own
-- work sits between frames). Pure: clock and frame are injected.

local FrameBudget = {}

export type Options = {
	budget: (number | (() -> number))?, -- seconds a frame (default 0.012)
	clock: (() -> number)?,
	frame: (() -> number)?,
	gap: number?, -- seconds between calls that mean a new frame (default 0.002)
}

export type Stats = {
	frames: number, -- frames that spent anything
	worst: number, -- the most seconds spent in one frame
	over: number, -- frames that went past the budget
}

export type Budget = {
	Begin: () -> (),
	Over: () -> boolean,
	Spent: () -> number,
	Limit: () -> number,
	Stats: () -> Stats,
}

FrameBudget.DefaultBudget = 0.012

function FrameBudget.new(options: Options?): Budget
	local clock = (options and options.clock) or os.clock
	local frameFn = options and options.frame
	local gap = (options and options.gap) or 0.002
	local rawBudget = options and options.budget
	local function limit(): number
		if type(rawBudget) == "function" then
			return (rawBudget :: () -> number)()
		elseif type(rawBudget) == "number" then
			return rawBudget
		end
		return FrameBudget.DefaultBudget
	end
	local frameStart = clock()
	local lastTouch = frameStart
	local currentFrame: number? = nil
	local frames, worst, overCount = 0, 0, 0
	local frameOver = false

	-- Starts a new frame's count when `now` is in a different frame.
	local function touch(now: number)
		local fresh: boolean
		if frameFn then
			local f = frameFn()
			fresh = f ~= currentFrame
			currentFrame = f
		else
			fresh = now - lastTouch > gap
		end
		lastTouch = now
		if fresh then
			frameStart = now
			frames += 1
			frameOver = false
		end
	end

	local budget = {} :: Budget
	budget.Begin = function()
		touch(clock())
	end
	budget.Over = function(): boolean
		local now = clock()
		touch(now)
		local spent = now - frameStart
		if spent > worst then
			worst = spent
		end
		local isOver = spent >= limit()
		if isOver and not frameOver then
			frameOver = true
			overCount += 1
		end
		return isOver
	end
	budget.Spent = function(): number
		return clock() - frameStart
	end
	budget.Limit = limit
	budget.Stats = function(): Stats
		return { frames = frames, worst = worst, over = overCount }
	end
	return budget
end

-- A frame counter for the engine: it goes up once every Heartbeat. nil where
-- there is no RunService (Lune, specs): FrameBudget then tells frames by gap.
function FrameBudget.HeartbeatCounter(): (() -> number)?
	local ok, counter = pcall(function(): (() -> number)?
		local runService = (game :: any):GetService("RunService")
		local count = 0
		runService.Heartbeat:Connect(function()
			count += 1
		end)
		return function(): number
			return count
		end
	end)
	if ok then
		return counter
	end
	return nil
end

-- How much of a base budget (ms) to spend when the last frame took `dt`
-- seconds: all of it up to a 20 ms frame (50 fps), falling to a quarter of it
-- 20 ms later, so a client that is already hitching does not build on top.
-- `expected` is the frame length the caller runs at (a loop that steps every
-- other frame passes 1/30): a frame is only slow if it is over that (x1.2) too.
function FrameBudget.Adapt(baseMs: number, dt: number, expected: number?): number
	local fast = math.max(0.02, (expected or 0) * 1.2)
	if dt <= fast then
		return baseMs
	end
	local t = math.min((dt - fast) / 0.02, 1)
	return baseMs * (1 - 0.75 * t)
end

return FrameBudget
