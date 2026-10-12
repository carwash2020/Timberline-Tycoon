--!nocheck
-- Server boot audit (12 October 2026): things that stop a real Studio server
-- from starting or starting well, which the service specs (each module alone,
-- with mocks) cannot see.
return function(t)
	local fs = require("@lune/fs")

	local function code(path)
		return (string.gsub(fs.readFile(path), "%-%-[^\n]*", ""))
	end
	local function at(text, needle, from)
		return string.find(text, needle, from or 1, true)
	end

	-- A ServerScriptService / ReplicatedStorage the boot scripts can look in.
	local function fakeServices(children, remotes)
		local function folder(entries)
			return {
				FindFirstChild = function(_self, name)
					return entries[name]
				end,
				WaitForChild = function(_self, name)
					return entries[name]
				end,
			}
		end
		local shared = { Net = { __module = "src/ReplicatedStorage/Shared/Net.luau", Name = "Net" } }
		local replicated = { Shared = shared }
		if remotes then
			replicated.Remotes = {}
		end
		local rs = folder(replicated)
		rs.Shared = shared
		local entries = {}
		for name, _ in pairs(children) do
			entries[name] = {
				__module = "src/ServerScriptService/" .. name .. ".luau",
				Name = name,
				IsA = function(_self, class)
					return class == "ModuleScript"
				end,
			}
		end
		return { ReplicatedStorage = rs, ServerScriptService = folder(entries) }
	end

	local function recorder(into, name)
		return {
			Init = function()
				table.insert(into, name)
			end,
		}
	end

	t.test("the v2 wiring in GameServer cannot end the script: one safely holds every raw call", function()
		-- A throw in a hook setter or an AdminService.Set* ran bare, ended the whole
		-- script, and the "services" gate and PlayerAdded were never reached: nobody
		-- could join. Inside safely it is a warning with a traceback.
		local game = code("src/ServerScriptService/GameServer.server.luau")
		local opener = '\nif CoreLoop.V2() then\n\tsafely("core loop v2 wiring", function()\n'
		local block = at(game, opener)
		t.ok(block, "the v2 block is one guarded function")
		local services = at(game, '\nLoadState.Gates.Set("services")', block)
		t.ok(services, "the services gate comes after it")
		local closes = at(game, "\n\tend)\nend\n", block)
		t.ok(closes and closes < services, "the guarded function closes before the services gate")
		local stubs = at(game, "\nBootReport.StartStubs({", block)
		t.ok(stubs and closes and closes < stubs, "and before the stubs, which are guarded on their own")
		-- Nothing in the block is at its top level (one tab in): all of it is inside the function.
		local inside = string.sub(game, block + #opener, closes)
		for line in string.gmatch(inside, "[^\n]+") do
			t.ok(string.sub(line, 1, 2) == "\t\t" or string.match(line, "^%s*$") ~= nil, "indented: " .. line)
		end
	end)

	t.test("MiningBoot waits for the world before it builds the mine, and says so when it cannot", function()
		local text = code("src/ServerScriptService/MiningBoot.server.luau")
		local wait = at(text, 'WaitForChild("Remotes", Net.RemotesWaitSeconds)')
		local mining = at(text, 'boot("MiningService")')
		local crafting = at(text, 'boot("CraftingService")')
		t.ok(wait and mining and crafting and wait < mining and mining < crafting, "wait, then mining, then crafting")
		-- Run it for real: no Remotes folder means GameServer never started.
		local started = {}
		local loader = t.loader({
			services = fakeServices({ MiningService = true, CraftingService = true }, false),
			mocks = {
				MiningService = recorder(started, "MiningService"),
				CraftingService = recorder(started, "CraftingService"),
			},
		})
		loader:run("ServerScriptService/MiningBoot.server")
		t.eq(#started, 0, "nothing starts into an empty world")
		t.eq(#loader.warnings, 1, "and it says why")
		t.ok(string.find(loader.warnings[1], "no Remotes folder", 1, true), loader.warnings[1])
		-- With the world up, both start, in order.
		local started2 = {}
		local loader2 = t.loader({
			services = fakeServices({ MiningService = true, CraftingService = true }, true),
			mocks = {
				MiningService = recorder(started2, "MiningService"),
				CraftingService = recorder(started2, "CraftingService"),
			},
		})
		loader2:run("ServerScriptService/MiningBoot.server")
		t.eq(started2, { "MiningService", "CraftingService" })
		t.eq(#loader2.warnings, 0)
	end)

	t.test("the boot scripts are loud when a module is missing or does not load", function()
		local mining = code("src/ServerScriptService/MiningBoot.server.luau")
		t.ok(at(mining, 'warn("[MiningBoot] " .. name .. " is not in ServerScriptService'), "missing mining module")
		t.ok(at(mining, '" did not load: "'), "a module that errors on require")
		local started = {}
		local loader = t.loader({
			services = fakeServices({ MiningService = true }, true),
			mocks = { MiningService = recorder(started, "MiningService") },
		})
		loader:run("ServerScriptService/MiningBoot.server")
		t.eq(started, { "MiningService" })
		t.eq(#loader.warnings, 1, "CraftingService is not there: one warning")
		t.ok(string.find(loader.warnings[1], "CraftingService", 1, true), loader.warnings[1])
		local board = code("src/ServerScriptService/TownBoardBoot.server.luau")
		t.ok(at(board, "TownBoardService did not load"), "a board that fails to load is a warning")
		t.ok(at(board, "TownBoardService is not in ServerScriptService"), "a board that is missing too")
		local base = code("src/ServerScriptService/BaseBoot.server.luau")
		t.ok(
			at(base, "is not in ServerScriptService; what depends on it was not started"),
			"BaseBoot names a missing service"
		)
	end)
end
