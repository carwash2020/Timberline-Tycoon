--!strict
-- ReadyGates: named "this is ready" flags with waiters and guards. The load
-- order of the server (and of what a player may touch) is a set of gates:
-- "world" (terrain, town and the sell area are in), "services" (every
-- service has had its Init), "npcs", "itemMeshes", and so on. A system that
-- another one depends on opens its gate when it is usable; anything that
-- needs it asks the gate instead of assuming.
--
--   * Set(name)            opens a gate (idempotent) and runs its listeners.
--   * IsReady(name)
--   * OnReady(name, fn)    fn now if the gate is open, else when it opens.
--   * Wait(name, timeout?) yields until open; false if the timeout passed.
--   * Guard(name, fn)      a wrapper for a remote handler: while the gate is
--                          shut it REFUSES (returns false and calls
--                          `onRefuse`, never errors); once open it calls fn.
--   * Snapshot()           { [name] = seconds since creation it opened }.
--
-- The clock, wait and spawn are injected for the specs; the defaults are
-- os.clock, task.wait and task.spawn.

local ReadyGates = {}

export type Options = {
	clock: (() -> number)?,
	wait: (() -> ())?,
	spawn: ((fn: () -> ()) -> ())?,
}

export type Gates = {
	Define: (name: string) -> (),
	Set: (name: string) -> (),
	IsReady: (name: string) -> boolean,
	OnReady: (name: string, fn: () -> ()) -> (),
	Wait: (name: string, timeout: number?) -> boolean,
	WaitAll: (names: { string }, timeout: number?) -> boolean,
	AllReady: (names: { string }) -> boolean,
	Guard: (name: string, fn: (...any) -> (), onRefuse: ((...any) -> ())?) -> (...any) -> boolean,
	Snapshot: () -> { [string]: number },
	Names: () -> { string },
}

function ReadyGates.new(options: Options?): Gates
	local clock = (options and options.clock) or os.clock
	local injectedWait = options and options.wait
	local waitFn = injectedWait or function()
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
	local created = clock()
	local order: { string } = {}
	local openedAt: { [string]: number } = {}
	local known: { [string]: boolean } = {}
	local listeners: { [string]: { () -> () } } = {}

	local function define(name: string)
		if not known[name] then
			known[name] = true
			table.insert(order, name)
		end
	end

	local gates = {} :: Gates

	gates.Define = define

	gates.Set = function(name: string)
		define(name)
		if openedAt[name] ~= nil then
			return
		end
		openedAt[name] = clock() - created
		local waiting = listeners[name]
		listeners[name] = nil
		if waiting then
			for _, fn in ipairs(waiting) do
				spawnFn(fn)
			end
		end
	end

	gates.IsReady = function(name: string): boolean
		return openedAt[name] ~= nil
	end

	gates.OnReady = function(name: string, fn: () -> ())
		define(name)
		if openedAt[name] ~= nil then
			spawnFn(fn)
			return
		end
		local list = listeners[name]
		if not list then
			list = {}
			listeners[name] = list
		end
		table.insert(list :: { () -> () }, fn)
	end

	gates.Wait = function(name: string, timeout: number?): boolean
		define(name)
		local started = clock()
		while openedAt[name] == nil do
			-- No scheduler (the spec loader): nothing can open it while we wait.
			if (timeout ~= nil and clock() - started >= timeout) or (injectedWait == nil and task == nil) then
				return false
			end
			waitFn()
		end
		return true
	end

	gates.AllReady = function(names: { string }): boolean
		for _, name in ipairs(names) do
			if openedAt[name] == nil then
				return false
			end
		end
		return true
	end

	gates.WaitAll = function(names: { string }, timeout: number?): boolean
		local started = clock()
		for _, name in ipairs(names) do
			local left = if timeout ~= nil then math.max(0, timeout - (clock() - started)) else nil
			if not gates.Wait(name, left) then
				return false
			end
		end
		return true
	end

	gates.Guard = function(name: string, fn: (...any) -> (), onRefuse: ((...any) -> ())?): (...any) -> boolean
		define(name)
		return function(...: any): boolean
			if openedAt[name] == nil then
				if onRefuse then
					onRefuse(...)
				end
				return false
			end
			fn(...)
			return true
		end
	end

	gates.Snapshot = function(): { [string]: number }
		return table.clone(openedAt)
	end

	gates.Names = function(): { string }
		return table.clone(order)
	end

	return gates
end

return ReadyGates
