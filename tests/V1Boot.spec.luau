--!nocheck
-- The v1 boot list. SecretService is Lane B's; this only reserves the name.
return function(t)
	local V1Boot = t.server("V1Boot")

	t.test("SecretService is on the boot list", function()
		local found = false
		for _, name in ipairs(V1Boot.Services) do
			if name == "SecretService" then
				found = true
			end
		end
		t.ok(found)
		t.eq(table.find(V1Boot.Services, "TradeService"), nil, "trading is not in V1")
	end)

	t.test("V1Boot binds LogicSet and a second start does not add another listener", function()
		local fs = require("@lune/fs")
		local boot = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(boot, "V1Boot.Start(safely, remote)", 1, true), "the server passes the remotes")
		local loader = t.loader()
		local Boot = loader:server("V1Boot")
		local connected = {}
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					table.insert(connected, fn)
				end,
			},
		}
		local function safely(_name, fn)
			fn()
		end
		Boot.Start(safely, { LogicSet = remote })
		t.eq(#connected, 1, "LogicSet has a listener")
		connected[1]({ UserId = 9 }, "missing", "delay", 1)
		Boot.Start(safely, { LogicSet = remote })
		t.eq(#connected, 1, "the remote is not bound twice")
	end)
	t.test("the end game starts from V1Boot: the Sky Forge now, Gus once the station is found", function()
		local fired = {}
		local loader = t.loader({
			mocks = {
				AetherService = {
					V1Init = function(ctx)
						table.insert(fired, { "aether", ctx })
					end,
				},
				SkyQuestService = {
					V1Init = function(ctx)
						table.insert(fired, { "quest", ctx })
					end,
				},
			},
		})
		local Boot = loader:server("V1Boot")
		local station = { Name = "Platform" }
		Boot.Spawn = function(fn)
			fn()
		end
		Boot.WaitStation = function()
			return station
		end
		local sent = {}
		local remotes = {
			SkyQuest = {},
			ForgeAction = {},
			ForgeOpen = {},
			Notify = {
				FireClient = function(_, player, text)
					table.insert(sent, { player, text })
				end,
			},
		}
		local order = {}
		Boot.Start(function(name, fn)
			table.insert(order, name)
			fn()
		end, remotes)
		t.eq(fired[1][1], "aether", "the Sky Forge binds first")
		t.eq(fired[2][1], "quest")
		t.eq(fired[2][2].station, station)
		t.eq(fired[1][2].remotes, remotes)
		fired[2][2].notify("ann", "hi")
		t.eq(sent[1][2], "hi", "notify goes through the Notify remote")
		t.ok(table.find(order, "AetherService.V1Init") ~= nil and table.find(order, "SkyQuestService") ~= nil)
		local fs = require("@lune/fs")
		t.ok(not fs.isFile("src/ServerScriptService/EndGameBoot.server.luau"), "EndGameBoot is gone")
	end)
end
