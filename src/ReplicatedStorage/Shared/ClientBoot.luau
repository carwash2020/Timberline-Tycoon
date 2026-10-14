--!strict
-- ClientBoot: the client's deferred Start queue. Studio's log of 14 October
-- 2026 had a dozen controllers (WoodFX, LuxFX, DialogueUI, BlueprintPlacer,
-- HammerController, ...) each spending up to 1.4 s inside Start in the first
-- seconds after the character spawned, all at once. A controller is either
--
--   * critical: needed to play (input, the HUD, camera, grab and drag, chop,
--     tools, the join screens, the shops, the loading handoff). Client.client
--     starts these at once, as it always did; or
--   * deferrable: effects, cosmetics, ambient life, news, the daily card, the
--     dialogue box, the blueprint and hammer tools. Registered here, and
--     started ONE OR TWO A FRAME after the player can play, soonest-needed
--     first (lowest `priority`).
--
-- A deferrable controller used before its turn must still work, so each has a
-- first-use fallback: Ensure(name) starts it right now (once: a second call,
-- or the queue reaching it later, does nothing). The tools call Ensure when
-- one is equipped or begun (BlueprintPlacer.Begin, HammerController.Equip),
-- the dialogue box when a talk opens, and Client.client watches the backpack.
-- A Start that errors is warned once with its traceback and counts as started
-- (it must not run twice); the rest carry on.
--
-- Pure: wait, clock and warn are injected. Start times are logged as
-- `[Perf] client <name> Start took X ms` only for a slow one (over SlowMs), so
-- the log never fills.

local ClientBoot = {}

export type Entry = { priority: number, start: () -> () }

export type Options = {
	wait: (() -> ())?, -- one frame (default task.wait)
	clock: (() -> number)?,
	warn: ((text: string) -> ())?,
	log: ((line: string) -> ())?,
	maxPerFrame: number?, -- Starts a frame (default 2)
	budget: number?, -- seconds of Starts a frame; a second one only runs under it (default 0.004)
	traceback: ((err: any) -> string)?,
}

export type Boot = {
	Register: (name: string, entry: Entry) -> (),
	Ensure: (name: string) -> boolean, -- starts it now if it has not started; true if it ran just now
	Release: () -> (), -- the player can play: start draining the queue
	IsStarted: (name: string) -> boolean,
	IsRegistered: (name: string) -> boolean,
	Pending: () -> number,
	Order: () -> { string }, -- the names still waiting, in the order they will start
	Started: () -> { string }, -- the order they started in
	Released: () -> boolean,
	Drained: () -> boolean, -- released and nothing left waiting
	OnDrained: (fn: () -> ()) -> (),
	Slowest: () -> (string?, number), -- the Start that took longest, and its seconds
}

ClientBoot.SlowMs = 20

function ClientBoot.new(options: Options?): Boot
	local clock = (options and options.clock) or os.clock
	local waitFn = (options and options.wait) or function()
		if task then
			task.wait()
		end
	end
	local warnFn = (options and options.warn) or function(text: string)
		warn(text)
	end
	local logFn = (options and options.log) or function(_line: string) end
	local maxPerFrame = math.max(1, (options and options.maxPerFrame) or 2)
	local budget = (options and options.budget) or 0.004
	local handler = (options and options.traceback) or function(err: any): string
		return tostring(err)
	end

	local entries: { [string]: Entry } = {}
	local serial: { [string]: number } = {}
	local count = 0
	local startedSet: { [string]: boolean } = {}
	local startedOrder: { string } = {}
	local released, drained = false, false
	local listeners: { () -> () } = {}
	local slowName: string? = nil
	local slowSeconds = 0

	local function waiting(): { string }
		local names: { string } = {}
		for name in pairs(entries) do
			if not startedSet[name] then
				table.insert(names, name)
			end
		end
		table.sort(names, function(a: string, b: string): boolean
			local pa, pb = entries[a].priority, entries[b].priority
			if pa ~= pb then
				return pa < pb
			end
			return serial[a] < serial[b]
		end)
		return names
	end

	local function startNow(name: string)
		if startedSet[name] then
			return
		end
		startedSet[name] = true -- before the call: a Start that asks for itself must not run twice
		table.insert(startedOrder, name)
		local entry = entries[name]
		local at = clock()
		local ok, err = xpcall(function(): any
			entry.start()
			return nil
		end, handler)
		local took = clock() - at
		if took > slowSeconds then
			slowName, slowSeconds = name, took
		end
		if not ok then
			warnFn(string.format("[Client] %s failed to start:\n%s", name, tostring(err)))
		end
		if took * 1000 >= ClientBoot.SlowMs then
			logFn(string.format("[Perf] client %s Start took %.0f ms", name, took * 1000))
		end
	end

	local function finishIfDrained()
		if released and not drained and #waiting() == 0 then
			drained = true
			local copy = table.clone(listeners)
			for _, fn in ipairs(copy) do
				fn()
			end
		end
	end

	local boot = {} :: Boot
	boot.Register = function(name: string, entry: Entry)
		if entries[name] == nil then
			count += 1
			serial[name] = count
		end
		entries[name] = entry
	end
	boot.Ensure = function(name: string): boolean
		if entries[name] == nil or startedSet[name] then
			return false
		end
		startNow(name)
		finishIfDrained()
		return true
	end
	boot.Release = function()
		if released then
			return
		end
		released = true
		if #waiting() == 0 then
			finishIfDrained()
			return
		end
		local function run()
			while true do
				local names = waiting()
				if #names == 0 then
					break
				end
				local frameStart = clock()
				local ran = 0
				for _, name in ipairs(names) do
					if ran >= maxPerFrame or (ran > 0 and clock() - frameStart >= budget) then
						break
					end
					startNow(name)
					ran += 1
				end
				waitFn()
			end
			finishIfDrained()
		end
		if type(task) == "table" and type(task.defer) == "function" then
			task.defer(run)
		else
			run()
		end
	end
	boot.IsStarted = function(name: string): boolean
		return startedSet[name] == true
	end
	boot.IsRegistered = function(name: string): boolean
		return entries[name] ~= nil
	end
	boot.Pending = function(): number
		return #waiting()
	end
	boot.Order = waiting
	boot.Started = function(): { string }
		return table.clone(startedOrder)
	end
	boot.Released = function(): boolean
		return released
	end
	boot.Drained = function(): boolean
		return drained
	end
	boot.OnDrained = function(fn: () -> ())
		if drained then
			fn()
		else
			table.insert(listeners, fn)
		end
	end
	boot.Slowest = function(): (string?, number)
		return slowName, slowSeconds
	end
	return boot
end

-- The player can play: the HUD's loading card has been handed over (the save is
-- loaded, ProfileLoaded) or `timeout` seconds have passed (a save that never
-- loads must not keep the effects away for good), then `settleFrames` more
-- frames (the card's fade), then the queue is released. Returns when it has been.
function ClientBoot.ReleaseWhenPlaying(
	boot: Boot,
	isPlaying: () -> boolean,
	options: {
		wait: (() -> ())?,
		clock: (() -> number)?,
		timeout: number?,
		settleFrames: number?,
	}?
)
	local clock = (options and options.clock) or os.clock
	local waitFn = (options and options.wait) or function()
		if task then
			task.wait()
		end
	end
	local timeout = (options and options.timeout) or 30
	local settleFrames = (options and options.settleFrames) or 30
	local startedAt = clock()
	while not isPlaying() and clock() - startedAt < timeout do
		waitFn()
	end
	for _ = 1, settleFrames do
		waitFn()
	end
	boot.Release()
end

-- A server event that a deferred controller listens for, arriving before its
-- Start has connected that listener, would be lost (a box opened in the first
-- seconds, Old Hank's reply). This is the listener for the OnClientEvent of that
-- remote, connected at once by Client.client: when the controller has not
-- started, it starts it now (first use) and hands it the event it missed by
-- calling module[handler](...). Once started, the controller's own listener
-- hears the event and this does nothing. `only` limits it to one event kind
-- (the first argument).
function ClientBoot.EarlyHandler(boot: Boot, name: string, module: any, handler: string, only: any?): (...any) -> ()
	return function(...: any)
		if only ~= nil and (...) ~= only then
			return
		end
		if boot.Ensure(name) then
			local f = module[handler]
			if f then
				f(...)
			end
		end
	end
end

-- The shared queue the client modules ask (`ClientBoot.Ensure("HammerController")`
-- at their first-use entry points). Client.client registers the deferred
-- controllers into it; where nothing is registered (a spec, an old client)
-- Ensure does nothing.
ClientBoot.Default = ClientBoot.new({
	log = function(line: string)
		print(line)
	end,
})

function ClientBoot.Ensure(name: string): boolean
	return ClientBoot.Default.Ensure(name)
end

return ClientBoot
