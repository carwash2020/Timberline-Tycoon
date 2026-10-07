--!nocheck
-- JoinSync: the client's ClientReady handshake and the state the server
-- sends again for it. A one-shot fired before the client had connected its
-- handler used to be lost for good.
return function(t)
	local fs = require("@lune/fs")

	local function fresh()
		local JoinSync = t.load("ServerScriptService/JoinSync")
		JoinSync.Reset()
		return JoinSync
	end

	t.test("every registered resend runs for the player, in order", function()
		local JoinSync = fresh()
		local sent = {}
		JoinSync.Register("cash", function(p)
			table.insert(sent, "cash " .. p.name)
		end)
		JoinSync.Register("plotOffer", function(p)
			table.insert(sent, "offer " .. p.name)
		end)
		local player = { name = "Connor" }
		t.eq(JoinSync.Run(player), 2)
		t.eq(sent, { "cash Connor", "offer Connor" })
		t.eq(JoinSync.Names(), { "cash", "plotOffer" })
		t.eq(JoinSync.Runs(player), 1)
	end)

	t.test("regression: a one-shot sent before the handler existed is sent again on ClientReady", function()
		local JoinSync = fresh()
		local heard = {}
		local clientListening = false
		-- The server fires the offer at the join, before the client listens: lost.
		local function fireOffer(player)
			if clientListening then
				table.insert(heard, "offer")
			end
		end
		JoinSync.Register("plotOffer", fireOffer)
		local player = { name = "Connor" }
		fireOffer(player) -- the join
		t.eq(heard, {}, "lost: nobody was listening")
		clientListening = true
		t.ok(JoinSync.MarkReady(player, 8.2), "the handshake")
		JoinSync.Run(player)
		t.eq(heard, { "offer" }, "heard on the resend")
	end)

	t.test("the same resend twice is the same state (the handlers apply, they do not toggle)", function()
		local JoinSync = fresh()
		local state = {}
		JoinSync.Register("cash", function(p)
			state.cash = 83
		end)
		local player = {}
		JoinSync.Run(player)
		JoinSync.Run(player)
		t.eq(state, { cash = 83 })
	end)

	t.test("a resend that errors is reported and the rest still run", function()
		local JoinSync = fresh()
		local ran = {}
		JoinSync.Register("bad", function()
			error("nope")
		end)
		JoinSync.Register("good", function()
			table.insert(ran, "good")
		end)
		local errors = {}
		t.eq(
			JoinSync.Run({}, function(name, err)
				table.insert(errors, name)
			end),
			1
		)
		t.eq(ran, { "good" })
		t.eq(errors, { "bad" })
	end)

	t.test("registering a name again replaces it", function()
		local JoinSync = fresh()
		local ran = {}
		JoinSync.Register("cash", function()
			table.insert(ran, "old")
		end)
		JoinSync.Register("cash", function()
			table.insert(ran, "new")
		end)
		JoinSync.Run({})
		t.eq(ran, { "new" })
		t.eq(#JoinSync.Names(), 1)
	end)

	t.test("the handshake is recorded once; Forget clears it for a rejoin", function()
		local JoinSync = fresh()
		local player = {}
		t.eq(JoinSync.IsReady(player), false)
		t.eq(JoinSync.MarkReady(player, 6.5), true)
		t.eq(JoinSync.MarkReady(player, 9), false, "the retries are not new handshakes")
		t.eq(JoinSync.ReadyAt(player), 6.5)
		JoinSync.Forget(player)
		t.eq(JoinSync.IsReady(player), false)
		t.eq(JoinSync.MarkReady(player, 1), true)
	end)

	t.test("the server hears ClientReady, rate limits it, and resends cash, the plot offer and the slots", function()
		local Net = t.shared("Net")
		t.ok(table.find(Net.RemoteNames, "ClientReady"), "a named remote")
		local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
		t.ok(string.find(net, '"ClientReady", -- client -> server', 1, true), "direction marked")
		local limits = fs.readFile("src/ServerScriptService/RateLimiter.luau")
		t.ok(string.find(limits, "ClientReady = ", 1, true), "a budget")
		local game = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(game, "remote.ClientReady.OnServerEvent", 1, true))
		for _, name in ipairs({ "cash", "plotOffer", "saveSlots" }) do
			t.ok(string.find(game, 'JoinSync.Register("' .. name .. '"', 1, true), name .. " is resent")
		end
		local plot = fs.readFile("src/ServerScriptService/PlotService.luau")
		t.ok(string.find(plot, "function PlotService.Resend", 1, true))
		-- And once more right after the release.
		t.ok(string.find(game, 'safely("JoinSync.Run", resendState, player)', 1, true))
		local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		t.ok(string.find(client, 'Net.Remote("ClientReady")', 1, true))
	end)
end
