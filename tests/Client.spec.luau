--!nocheck
-- The client's entry point (StarterPlayerScripts/Client.client): one
-- controller failing to start, the HUD included, never stops the others.
return function(t)
	-- Runs Client.client with every controller faked: `failing` names the
	-- ones whose Start errors. Returns who started, the warnings and the
	-- prints, in order.
	local lastFired = 0
	local lastOrder = {}
	local function run(failing, failingLoad)
		failingLoad = failingLoad or {}
		local started, prints = {}, {}
		local fired = 0
		local fakeNet = {
			Remote = function(name)
				return {
					FireServer = function()
						fired += 1
						table.insert(lastOrder, name .. " after " .. #started .. " starts")
					end,
				}
			end,
		}
		lastOrder = {}
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
				if name == "Net" then
					return fakeNet
				end
				if name == "JoinFlow" then
					return { ClientReadyTries = 30, ClientReadyEvery = 3 }
				end
				if failingLoad[name] then
					error(name .. " broke at load") -- its top level errors
				end
				fakes[name] = fakes[name] or fake(name)
				return fakes[name]
			end,
		})
		local loader = t.loader({
			mocks = mocks,
			services = {
				Players = {
					LocalPlayer = {
						GetAttribute = function()
							return true -- the save is in: the handshake stops after one fire
						end,
					},
				},
			},
			globals = {
				debug = debug,
				print = function(...)
					table.insert(prints, table.concat({ ... }, " "))
				end,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
			},
		})
		loader:load("StarterPlayer/StarterPlayerScripts/Client.client")
		lastFired = fired
		return started, loader.warnings, prints, fakes
	end

	local function failures(warnings, what)
		local names = {}
		for _, w in ipairs(warnings) do
			local name = string.match(w, "^%[Client%] (%S+) failed to " .. (what or "start"))
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

	-- Join race fix: the controllers start before the server has made its
	-- remotes, so the server waits for the client to say its handlers are in.
	t.test("the client says ClientReady once every controller has started, even if one broke", function()
		local started = run({ QuestUI = true })
		t.eq(lastFired, 1, "one handshake (the save was already in, so no repeats)")
		t.eq(lastOrder, { "ClientReady after " .. #started .. " starts" }, "after every Start returned")
		local _, _, prints = run({})
		local found = false
		for _, line in ipairs(prints) do
			if string.find(line, "[Load] client ready handshake", 1, true) then
				found = true
			end
		end
		t.ok(found, "the [Load] client ready handshake line")
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
		t.ok(table.find(started, "DialogueUI"))
		t.ok(not table.find(started, "DailyUI"), "DailyUI is not started")
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
		local waits = string.find(source, "WaitForChild(name, left)", 1, true)
		local firstRequire = string.find(source, "require(script.Parent.", 1, true)
		t.ok(waits and firstRequire and waits < firstRequire, "the wait comes before any require")
		-- One deadline for all of them: a half-synced place doesn't wait
		-- MODULE_WAIT for each missing module in turn.
		t.ok(string.find(source, "local deadline = os.clock() + MODULE_WAIT", 1, true), "a shared deadline")
		t.ok(string.find(source, "local left = deadline - os.clock()", 1, true), "each wait gets what is left")
	end)

	-- A module whose top level errors (a broken sibling, a missing remote)
	-- used to stop the whole client at its require: no HUD, no tutorial, no
	-- driving. Now it is skipped with a warning and the rest still start.
	t.test("a controller that fails to load warns, and every other controller still starts", function()
		local started, warnings, prints = run({}, { VehicleController = true })
		local all = run({})
		local expected = {}
		for _, name in ipairs(all) do
			if name ~= "VehicleController" then
				table.insert(expected, name)
			end
		end
		t.eq(started, expected, "every other controller, in the same order")
		t.eq(failures(warnings, "load"), { "VehicleController" })
		t.ok(string.find(warnings[1], "VehicleController broke at load", 1, true), "with the error")
		t.eq(failures(warnings), {}, "nothing failed to start")
		t.eq(prints[#prints], "[Client] Timberline Tycoon client started.")
	end)

	t.test("a HUD that fails to load warns, and every other controller still starts", function()
		local started, warnings, prints = run({}, { HUD = true })
		t.eq(started[1], "Quality", "the others start, the HUD skipped")
		t.ok(not table.find(started, "HUD"))
		t.eq(failures(warnings, "load"), { "HUD" })
		t.eq(prints[#prints], "[Client] Timberline Tycoon client started.")
	end)
end
