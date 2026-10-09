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
		-- SecretService (Lane B) is a real module now; MapBuilder starts it,
		-- so stub it here and keep this test on LogicSet.
		local loader = t.loader({ mocks = { SecretService = {} } })
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
end
