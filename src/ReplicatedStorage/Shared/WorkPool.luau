--!strict
-- WorkPool: run a list of YIELDING jobs side by side (at most `concurrency`
-- at once) and join: Run returns when every job has finished or the timeout
-- passed. This is the "task.spawn per job with a join barrier" the mesh
-- loads need: AssetService:CreateMeshPartAsync takes about a third of a
-- second of network time per mesh, so loading 150 NPC meshes one after the
-- other held the server's Init for a minute, while 24 at a time take a few
-- seconds (MeshKit.Preload; Studio log of 7 October 2026).
--
-- Pure: spawn, wait and clock are injected (defaults task.spawn, task.wait,
-- os.clock). A job that errors is counted and the others carry on. A job
-- still running at the timeout is left to finish by itself; Run reports
-- `timedOut` and returns.

local WorkPool = {}

export type Options = {
	concurrency: number?, -- default 16
	timeout: number?, -- seconds to wait for the join (default: no limit)
	spawn: ((fn: () -> ()) -> ())?,
	wait: (() -> ())?,
	clock: (() -> number)?,
	onError: ((index: number, err: string) -> ())?,
}

export type Result = {
	total: number,
	completed: number, -- jobs that ran to the end (even if they errored)
	errors: number,
	timedOut: boolean,
	seconds: number,
}

WorkPool.DefaultConcurrency = 16

function WorkPool.Run<T>(items: { T }, job: (item: T, index: number) -> (), options: Options?): Result
	local clock = (options and options.clock) or os.clock
	-- Without a scheduler (the spec loader has no `task`) jobs run to the end
	-- one after another, which is also what a job that never yields does.
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
	local startedAt = clock()
	local total = #items
	local workers =
		math.min(math.max(1, math.floor((options and options.concurrency) or WorkPool.DefaultConcurrency)), total)
	local nextIndex = 1
	local completed, errors, finishedWorkers = 0, 0, 0
	local timeout = options and options.timeout
	local onError = options and options.onError
	local abandoned = false

	local function worker()
		while not abandoned do
			local index = nextIndex
			if index > total then
				break
			end
			nextIndex += 1
			local ok, err = pcall(function(): any
				job(items[index], index)
				return nil
			end)
			completed += 1
			if not ok then
				errors += 1
				if onError then
					onError(index, tostring(err))
				end
			end
		end
		finishedWorkers += 1
	end

	for _ = 1, workers do
		spawnFn(worker)
	end
	local timedOut = false
	while finishedWorkers < workers do
		if timeout ~= nil and clock() - startedAt >= timeout then
			timedOut = true
			abandoned = true -- no new jobs start; running ones finish by themselves
			break
		end
		waitFn()
	end
	return {
		total = total,
		completed = completed,
		errors = errors,
		timedOut = timedOut,
		seconds = clock() - startedAt,
	}
end

return WorkPool
