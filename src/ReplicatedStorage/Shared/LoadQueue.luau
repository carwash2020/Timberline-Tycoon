--!strict
-- LoadQueue: the deferred build queue. Everything that nobody needs in the
-- first minute (scenery, points of interest, the isles, the townsfolk's
-- extras, ...) is added here as a named step and built AFTER the first
-- player can play, one step at a time, nearest first, never holding the
-- server for more than a slice.
--
--   * Order: lower `tier` first (1 = what a player will see soon, 3 = far
--     decoration); inside a tier the step nearest a focus point (a player,
--     else the spawn) goes first; ties keep the order they were added in.
--     The focus is asked again before EVERY pick, so a player who runs off
--     toward the volcano pulls the volcano's steps forward.
--   * A step is `run(slice)`. It calls `slice()` after each small unit of
--     work: that yields only when the slice's time budget is spent
--     (Shared/TimeSlice). The queue always yields once between steps too.
--   * A step that errors is logged and counted; the rest still run.
--   * Every step logs one `[Load] deferred <name> took Xs` line (the log
--     function is injected), so Studio's Output shows what the background
--     build costs and when it finished.
--   * Start() begins running; steps added later start it again when it has
--     gone idle. OnIdle fires each time the queue empties.
--
-- Pure: clock, wait, spawn, log and the focus are injected.

local TimeSlice = require(script.Parent.TimeSlice)

local LoadQueue = {}

export type Point = { x: number, z: number }

export type Step = {
	name: string,
	tier: number?, -- default 2
	at: Point?, -- where it builds, for nearest-first (none: first in its tier)
	run: (slice: () -> boolean) -> (),
	-- Many small steps of one job (the cells of the boulders) share a group:
	-- a step in a group logs no line of its own, and the group logs ONE line
	-- when its last step is done.
	group: string?,
	groupSize: number?,
}

export type Options = {
	budget: number?, -- seconds of work per slice (default TimeSlice's 0.012)
	clock: (() -> number)?,
	wait: (() -> ())?,
	spawn: ((fn: () -> ()) -> ())?,
	focus: (() -> { Point })?, -- where the players are (empty: the origin)
	log: ((line: string) -> ())?,
	traceback: ((err: any) -> string)?,
}

export type Stats = {
	pending: number,
	ran: number,
	failed: number,
	running: boolean,
	busySeconds: number, -- time spent inside steps
	order: { string }, -- the names, in the order they ran
}

export type Queue = {
	Add: (step: Step) -> (),
	Start: () -> (),
	Pending: () -> number,
	Running: () -> boolean,
	OnIdle: (fn: () -> ()) -> (),
	Stats: () -> Stats,
}

local DEFAULT_TIER = 2

local function distance(a: Point, b: Point): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- The step to run next: lowest tier, then nearest the closest focus point,
-- then first added. Returns its index in `steps`, or nil if empty.
function LoadQueue.Next(steps: { Step }, focus: { Point }?): number?
	local best: number? = nil
	local bestTier, bestDist = math.huge, math.huge
	local points = focus
	if points == nil or #points == 0 then
		points = { { x = 0, z = 0 } }
	end
	for i, step in ipairs(steps) do
		local tier = step.tier or DEFAULT_TIER
		local at = step.at
		local d = 0
		if at then
			d = math.huge
			for _, p in ipairs(points :: { Point }) do
				d = math.min(d, distance(at, p))
			end
		end
		if tier < bestTier or (tier == bestTier and d < bestDist) then
			best, bestTier, bestDist = i, tier, d
		end
	end
	return best
end

-- The whole run order for a fixed focus (what the queue does, with the
-- focus held still). For specs and for printing a plan.
function LoadQueue.Order(steps: { Step }, focus: { Point }?): { Step }
	local left = table.clone(steps)
	local out: { Step } = {}
	while #left > 0 do
		local i = LoadQueue.Next(left, focus) :: number
		table.insert(out, table.remove(left, i) :: Step)
	end
	return out
end

export type Cell<T> = { at: Point, items: { T } }

-- Splits a scattered list (boulders, scenery, trail slabs...) into square
-- cells `size` studs across, so each cell can be its own queue step and the
-- ones near the players get built first. `at` is the cell's centre of mass.
-- Items keep their order inside a cell; cells come out in a fixed order
-- (row by row) so the result never depends on table iteration order.
function LoadQueue.Cells<T>(items: { T }, positionOf: (item: T) -> Point, size: number): { Cell<T> }
	local byKey: { [string]: { items: { T }, sx: number, sz: number, cx: number, cz: number } } = {}
	local keys: { string } = {}
	for _, item in ipairs(items) do
		local p = positionOf(item)
		local cx, cz = math.floor(p.x / size), math.floor(p.z / size)
		local key = cx .. ":" .. cz
		local cell = byKey[key]
		if not cell then
			cell = { items = {}, sx = 0, sz = 0, cx = cx, cz = cz }
			byKey[key] = cell
			table.insert(keys, key)
		end
		table.insert(cell.items, item)
		cell.sx += p.x
		cell.sz += p.z
	end
	table.sort(keys, function(a: string, b: string): boolean
		local ca, cb = byKey[a], byKey[b]
		if ca.cz ~= cb.cz then
			return ca.cz < cb.cz
		end
		return ca.cx < cb.cx
	end)
	local out: { Cell<T> } = {}
	for _, key in ipairs(keys) do
		local cell = byKey[key]
		local n = #cell.items
		table.insert(out, { at = { x = cell.sx / n, z = cell.sz / n }, items = cell.items })
	end
	return out
end

function LoadQueue.new(options: Options?): Queue
	local clock = (options and options.clock) or os.clock
	local waitFn = (options and options.wait) or function()
		if task then
			task.wait()
		end
	end
	local spawnFn = (options and options.spawn)
		or function(fn: () -> ())
			if task then
				task.spawn(fn)
			else
				fn()
			end
		end
	local log = (options and options.log) or function(_line: string) end
	local focusFn = options and options.focus
	local handler = (options and options.traceback) or function(err: any): string
		return tostring(err)
	end

	local steps: { Step } = {}
	local idleListeners: { () -> () } = {}
	local started = false
	local running = false
	local ran, failed = 0, 0
	local busy = 0
	local groups: { [string]: { done: number, seconds: number, failed: number } } = {}
	local order: { string } = {}
	local queue = {} :: Queue

	local function runAll()
		running = true
		local slice = TimeSlice.new({ budget = options and options.budget, clock = clock, wait = waitFn })
		while #steps > 0 do
			local focus = if focusFn then focusFn() else nil
			local index = LoadQueue.Next(steps, focus) :: number
			local step = table.remove(steps, index) :: Step
			local at = clock()
			slice.reset()
			local ok, err = xpcall(function(): any
				step.run(slice.step)
				return nil
			end, handler)
			local took = clock() - at
			busy += took
			ran += 1
			table.insert(order, step.name)
			if not ok then
				failed += 1
			end
			local group = step.group
			if group then
				local g = groups[group]
				if not g then
					g = { done = 0, seconds = 0, failed = 0 }
					groups[group] = g
				end
				g.done += 1
				g.seconds += took
				if not ok then
					g.failed += 1
					log(string.format("[Load] deferred %s FAILED after %.2fs: %s", step.name, took, tostring(err)))
				end
				if g.done >= (step.groupSize or 1) then
					log(
						string.format(
							"[Load] deferred %s: %d steps took %.2fs in all%s",
							group,
							g.done,
							g.seconds,
							if g.failed > 0 then string.format(" (%d FAILED)", g.failed) else ""
						)
					)
				end
			elseif ok then
				log(string.format("[Load] deferred %s took %.2fs", step.name, took))
			else
				log(string.format("[Load] deferred %s FAILED after %.2fs: %s", step.name, took, tostring(err)))
			end
			waitFn() -- always one frame between steps: the server breathes
		end
		running = false
		local listeners = table.clone(idleListeners)
		for _, fn in ipairs(listeners) do
			fn()
		end
	end

	queue.Add = function(step: Step)
		table.insert(steps, step)
		if started and not running then
			running = true -- claimed now, so two Adds in one frame start one runner
			spawnFn(runAll)
		end
	end

	queue.Start = function()
		if started then
			return
		end
		started = true
		if #steps > 0 and not running then
			running = true
			spawnFn(runAll)
		end
	end

	queue.Pending = function(): number
		return #steps
	end

	queue.Running = function(): boolean
		return running
	end

	queue.OnIdle = function(fn: () -> ())
		table.insert(idleListeners, fn)
	end

	queue.Stats = function(): Stats
		return {
			pending = #steps,
			ran = ran,
			failed = failed,
			running = running,
			busySeconds = busy,
			order = table.clone(order),
		}
	end

	return queue
end

return LoadQueue
