--!nocheck
-- The client's entry point (StarterPlayerScripts/Client.client): one
-- controller failing to start, the HUD included, never stops the others.
return function(t)
	-- Runs Client.client with every controller faked: `failing` names the
	-- ones whose Start errors. Returns who started, the warnings and the
	-- prints, in order.
	local function run(failing)
		local started, prints = {}, {}
		local function fake(name)
			return {
				Start = function()
					table.insert(started, name)
					if failing[name] then
						error(name .. " broke")
					end
				end,
			}
		end
		local fakes = {}
		local mocks = setmetatable({}, {
			__index = function(_, name)
				if name == "Client.client" then
					return nil -- the script under test
				end
				fakes[name] = fakes[name] or fake(name)
				return fakes[name]
			end,
		})
		local loader = t.loader({
			mocks = mocks,
			globals = {
				debug = debug,
				print = function(...)
					table.insert(prints, table.concat({ ... }, " "))
				end,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		loader:load("StarterPlayer/StarterPlayerScripts/Client.client")
		return started, loader.warnings, prints, fakes
	end

	local function failures(warnings)
		local names = {}
		for _, w in ipairs(warnings) do
			local name = string.match(w, "^%[Client%] (%S+) failed to start")
			if name then
				table.insert(names, name)
			end
		end
		return names
	end

	t.test("everything starts, the HUD first, and the client says so", function()
		local started, warnings, prints, fakes = run({})
		t.eq(started[1], "HUD")
		local count = 0
		for _ in pairs(fakes) do
			count += 1
		end
		t.eq(#started, count, "every controller it requires starts once")
		t.ok(count > 20, "the real controller list")
		t.eq(#warnings, 0)
		t.eq(prints[#prints], "[Client] Timberline Tycoon client started.")
	end)

	t.test("a HUD that fails to start warns, and every other controller still starts", function()
		local started, warnings, prints = run({ HUD = true })
		local all = run({})
		t.eq(started, all, "the same controllers, in the same order")
		t.eq(failures(warnings), { "HUD" })
		t.ok(string.find(warnings[1], "HUD broke", 1, true), "with the error")
		t.eq(prints[#prints], "[Client] Timberline Tycoon client started.")
	end)

	t.test("only the controller made to fail reports a failure", function()
		local started, warnings, prints = run({ QuestUI = true })
		t.ok(table.find(started, "PromptUI"), "the ones after it start")
		t.ok(table.find(started, "DailyUI"))
		t.eq(failures(warnings), { "QuestUI" })
		t.eq(prints[#prints], "[Client] Timberline Tycoon client started.")
	end)

	-- PlayerScripts' modules arrive one by one: the client waits for all of
	-- them before its first require (a missing HUD stopped everything once).
	t.test("it waits for every module in its folder before the first require", function()
		local fs = require("@lune/fs")
		local folder = "src/StarterPlayer/StarterPlayerScripts"
		local onDisk = {}
		for _, entry in ipairs(fs.readDir(folder)) do
			local name = string.match(entry, "^([^%.]+)%.luau$")
			if name then
				table.insert(onDisk, name)
			end
		end
		table.sort(onDisk)
		local source = fs.readFile(folder .. "/Client.client.luau")
		local list = string.match(source, "local MODULES = (%b{})")
		t.ok(list, "a MODULES list")
		local listed = {}
		for name in string.gmatch(list, '"([^"]+)"') do
			table.insert(listed, name)
		end
		table.sort(listed)
		t.eq(listed, onDisk, "MODULES names every module in StarterPlayerScripts, no more, no less")
		local waits = string.find(source, "WaitForChild(name, MODULE_WAIT)", 1, true)
		local firstRequire = string.find(source, "require(script.Parent.", 1, true)
		t.ok(waits and firstRequire and waits < firstRequire, "the wait comes before any require")
	end)
end
