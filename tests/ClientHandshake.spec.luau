--!nocheck
-- ClientHandshake: the ClientReady listener is up before the services, so a
-- handshake sent early is heard at once (it used to wait for the client's
-- next repeat, 3 s later), and the resend it owes waits for the services.
return function(t)
	local function rig(allowed)
		local w = { first = {}, ready = {}, resent = {}, handler = nil }
		local event = {
			OnServerEvent = {
				Connect = function(_, fn)
					w.handler = fn
					return { Disconnect = function() end }
				end,
			},
		}
		local ClientHandshake = t.loader({
			mocks = {
				RateLimiter = {
					Allow = function(_, key)
						assert(key == "ClientReady")
						return allowed ~= false
					end,
				},
			},
		}):server("ClientHandshake")
		w.handshake = ClientHandshake.Bind(event, {
			markReady = function(player)
				if w.ready[player] then
					return false
				end
				w.ready[player] = true
				return true
			end,
			onFirst = function(player)
				table.insert(w.first, player)
			end,
		})
		return w
	end

	t.test("a handshake before the services are up marks the player ready at once", function()
		local w = rig()
		local ann = { Name = "Ann" }
		w.handler(ann)
		t.eq(w.first, { ann }, "ready the moment it is heard")
		t.eq(w.handshake.Pending(), 1, "the resend is owed")
		w.handler(ann) -- the 3 s repeat
		t.eq(#w.first, 1, "the first is logged once")
	end)

	t.test("the owed resends go out when the services say so, once each; later ones are immediate", function()
		local w = rig()
		local ann, bob = { Name = "Ann" }, { Name = "Bob" }
		w.handler(ann)
		w.handler(ann)
		w.handler(bob)
		local sent = {}
		w.handshake.SetResend(function(player)
			table.insert(sent, player)
		end)
		t.eq(#sent, 2, "one per player who asked")
		t.ok(table.find(sent, ann) and table.find(sent, bob))
		t.eq(w.handshake.Pending(), 0)
		w.handler(ann)
		t.eq(#sent, 3, "heard after the services: sent at once")
	end)

	t.test("a rate-limited fire does nothing", function()
		local w = rig(false)
		w.handler({ Name = "Spam" })
		t.eq(#w.first, 0)
		t.eq(w.handshake.Pending(), 0)
	end)

	t.test("GameServer binds it as soon as the remotes exist, before any service's Init, and only once", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local bind = string.find(source, "ClientHandshake.Bind(remote.ClientReady", 1, true)
		local firstInit = string.find(source, 'safely("EconomyService.Init"', 1, true)
		local made = string.find(source, "remotes.Parent = ReplicatedStorage", 1, true)
		t.ok(bind and firstInit and made, "all three found")
		t.ok(made < bind and bind < firstInit, "after the remotes exist, before the first service")
		t.ok(not string.find(source, "ClientReady.OnServerEvent", 1, true), "no second listener")
		t.ok(string.find(source, "Handshake.SetResend(resendState)", 1, true), "the owed resends are released")
	end)
end
