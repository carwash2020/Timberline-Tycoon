--!strict
-- ModulesReady: the flag Client sets once PlayerScripts' modules are all in,
-- and the wait the other .client scripts do before requiring a sibling.
return function(t: any)
	-- A scheduler by hand: spawn runs now (a thread resumes), delay fires
	-- when the test advances the clock.
	local timers: { { at: number, fn: () -> (), live: boolean } } = {}
	local now = 0
	local fakeTask = {
		spawn = function(f: any, ...)
			if type(f) == "thread" then
				coroutine.resume(f, ...)
			else
				coroutine.wrap(f)(...)
			end
		end,
		delay = function(seconds: number, fn: () -> ())
			local timer = { at = now + seconds, fn = fn, live = true }
			table.insert(timers, timer)
			return timer
		end,
		cancel = function(timer: any)
			timer.live = false
		end,
	}
	local function advance(seconds: number)
		now += seconds
		for _, timer in ipairs(table.clone(timers)) do
			if timer.live and timer.at <= now then
				timer.live = false
				timer.fn()
			end
		end
	end
	local ModulesReady = t.loader({ globals = { task = fakeTask } }):shared("ModulesReady")

	-- A folder with one attribute and its change signal.
	local function fakeFolder()
		local value: any = nil
		local listeners: { () -> () } = {}
		local folder = {}
		function folder:GetAttribute(_name: string): any
			return value
		end
		function folder:SetAttribute(_name: string, v: any)
			value = v
			for _, listener in ipairs(table.clone(listeners)) do
				listener()
			end
		end
		function folder:GetAttributeChangedSignal(_name: string)
			return {
				Connect = function(_, fn: () -> ())
					table.insert(listeners, fn)
					return {
						Disconnect = function()
							local at = table.find(listeners, fn)
							if at then
								table.remove(listeners, at)
							end
						end,
					}
				end,
			}
		end
		return folder, listeners
	end

	t.test("it returns at once when the folder is already marked", function()
		local folder = fakeFolder()
		ModulesReady.Mark(folder)
		t.eq(ModulesReady.Wait(folder, 5), true)
	end)

	t.test("it waits for the mark, then returns true", function()
		local folder, listeners = fakeFolder()
		local result: boolean? = nil
		fakeTask.spawn(function()
			result = ModulesReady.Wait(folder, 5)
		end)
		t.eq(result, nil, "still waiting")
		t.eq(#listeners, 1)
		ModulesReady.Mark(folder)
		t.eq(result, true)
		t.eq(#listeners, 0, "the connection is dropped")
	end)

	t.test("it gives up after the time and returns false", function()
		local folder, listeners = fakeFolder()
		local result: boolean? = nil
		fakeTask.spawn(function()
			result = ModulesReady.Wait(folder, 35)
		end)
		t.eq(result, nil)
		advance(34)
		t.eq(result, nil, "not yet")
		advance(2)
		t.eq(result, false)
		t.eq(#listeners, 0)
	end)

	t.test("the wait is longer than Client's own, so Client can finish first", function()
		t.ok(ModulesReady.DefaultWait > 30)
	end)
end
