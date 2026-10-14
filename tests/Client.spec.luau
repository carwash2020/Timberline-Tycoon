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
		-- The real ClientBoot (the deferred queue) and PerfProbe, fresh for each run:
		-- ClientBoot keeps its queue in the module, so runs must not share it.
		local realLoader = t.loader({ isolated = true })
		local real = {
			ClientBoot = realLoader:load("ReplicatedStorage/Shared/ClientBoot"),
			PerfProbe = realLoader:load("ReplicatedStorage/Shared/PerfProbe"),
		}
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
				if name == "ModulesReady" then
					return {
						Mark = function() end,
						Wait = function()
							return true
						end,
					}
				end
				if name == "JoinFlow" then
					return { ClientReadyTries = 30, ClientReadyEvery = 3 }
				end
				if name == "ClientBoot" or name == "PerfProbe" then
					return real[name]
				end
				if name == "MeshKit" then
					return {} -- the swap focus Client.client sets: not a controller, nothing to start
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
		-- (the deferred queue lives in the real ClientBoot, loaded by its own loader: its warnings too)
		local warnings = table.clone(loader.warnings)
		for _, w in ipairs(realLoader.warnings) do
			table.insert(warnings, w)
		end
		return started, warnings, prints, fakes
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

	-- The DEFERRED table in Client.client: name -> priority.
	local function deferredTable()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		local body = string.match(source, "local DEFERRED[^=]*= (%b{})")
		local out = {}
		for name, priority in string.gmatch(body, "([%w_]+) = (%d+)") do
			out[name] = tonumber(priority)
		end
		return out
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
		local deferred = deferredTable()
		local deferredStarted = 0
		for _, name in ipairs(started) do
			if deferred[name] then
				deferredStarted += 1
			end
		end
		t.ok(deferredStarted > 0, "the deferred controllers started too (after the player could play)")
		t.eq(lastFired, 1, "one handshake (the save was already in, so no repeats)")
		-- The critical controllers' handlers must be connected first; the deferred
		-- ones (effects, news, the tools) start after the player can play.
		t.eq(
			lastOrder,
			{ "ClientReady after " .. (#started - deferredStarted) .. " starts" },
			"after every critical Start returned"
		)
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
		-- Lane E: DailyUI is the Foreman's job board now and starts again.
		t.ok(table.find(started, "DailyUI"), "DailyUI (Rook's job board) starts")
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

	-- The other .client scripts start on their own, maybe before every
	-- sibling has arrived: CraftUI and ForgeUI require siblings straight
	-- away and a missing one failed them (and the HUD) for good. Client says
	-- when all are in, and each of them waits for that before its first
	-- require of a sibling.
	t.test("Client marks the folder ready and every other .client script waits for it", function()
		local fs = require("@lune/fs")
		local folder = "src/StarterPlayer/StarterPlayerScripts"
		local client = fs.readFile(folder .. "/Client.client.luau")
		local marks = string.find(client, "ModulesReady.Mark(folder)", 1, true)
		local loop = string.find(client, "WaitForChild(name, left)", 1, true)
		local firstRequire = string.find(client, "require(script.Parent.", 1, true)
		t.ok(marks and loop and marks > loop, "it marks the folder after the wait loop")
		t.ok(marks and firstRequire and marks < firstRequire, "and before any controller is required")
		local checked = 0
		for _, entry in ipairs(fs.readDir(folder)) do
			if string.match(entry, "%.client%.luau$") and entry ~= "Client.client.luau" then
				local source = fs.readFile(folder .. "/" .. entry)
				local firstSibling = string.find(source, "require(script.Parent", 1, true)
				if firstSibling then
					local waits = string.find(source, "ModulesReady.Wait(script.Parent", 1, true)
					t.ok(
						waits ~= nil and waits < firstSibling,
						entry .. " waits for ModulesReady before requiring a sibling"
					)
					checked += 1
				end
			end
		end
		t.ok(checked >= 2, "MiningClient and ForgeClient are both checked")
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

	-- Launch performance (14 October 2026): the effects and the tools' controllers
	-- start after the player can play, not in the first seconds. What must NOT
	-- wait is pinned by name.
	t.test("the deferred controllers start after every critical one, soonest-needed first", function()
		local started = run({})
		local deferred = deferredTable()
		local names = {}
		for name in pairs(deferred) do
			table.insert(names, name)
		end
		t.ok(#names >= 10, "a real deferred list")
		local lastCritical, firstDeferred = 0, math.huge
		for i, name in ipairs(started) do
			if deferred[name] then
				firstDeferred = math.min(firstDeferred, i)
			else
				lastCritical = i
			end
		end
		t.ok(lastCritical < firstDeferred, "every critical Start comes before the first deferred one")
		table.sort(names, function(a, b)
			return deferred[a] < deferred[b]
		end)
		local order = {}
		for _, name in ipairs(started) do
			if deferred[name] then
				table.insert(order, name)
			end
		end
		t.eq(order, names, "every deferred controller started once, in priority order")
	end)

	t.test("what is needed to play never waits", function()
		local deferred = deferredTable()
		for _, name in ipairs({
			"HUD",
			"Quality",
			"QualityPickerUI",
			"CarryController",
			"DragController",
			"CutController",
			"ChopController",
			"AxeController",
			"SprintController",
			"PromptUI",
			"ShopUI",
			"PlotPickerUI",
			"SaveSlotUI",
			"QuestUI",
			"NPCController",
			"VehicleController",
			"LightingController",
			"IdlePing",
			"BuilderTools",
			"WireTool",
			"PlotUI",
			"SettingsUI",
			"QuickMenuUI",
		}) do
			t.eq(deferred[name], nil, name .. " is critical: it starts at once")
		end
		-- The ones the brief names.
		for _, name in ipairs({ "WoodFX", "LuxFX", "DialogueUI", "BlueprintPlacer", "HammerController" }) do
			t.ok(deferred[name] ~= nil, name .. " is deferred")
		end
	end)

	t.test("a deferred controller that fails to start warns once and the rest still start", function()
		local started, warnings = run({ WoodFX = true })
		local all = run({})
		t.eq(started, all, "the same controllers, in the same order")
		t.eq(failures(warnings), { "WoodFX" })
	end)
end
