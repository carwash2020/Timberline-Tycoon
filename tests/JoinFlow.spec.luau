--!nocheck
-- JoinFlow: the order a player is let into the world in (join race fix,
-- 7 October 2026). Studio showed the character released at +6.5 s, before the
-- save, the plot pads, Murph, the services and the client's handlers.
return function(t)
	local JoinFlow = t.shared("JoinFlow")
	local fs = require("@lune/fs")

	local function state(overrides)
		local s = {
			worldReady = true,
			saveLoaded = true,
			streamed = true,
			spawned = true,
			grounded = true,
			clientReady = true,
			groundWaited = 0,
			clientWaited = 0,
		}
		for k, v in pairs(overrides or {}) do
			s[k] = v
		end
		return s
	end

	t.test("the first player waits for what the first minute needs, and not for the townsfolk", function()
		local gates = JoinFlow.FirstPlayerGates
		for _, name in ipairs({ "terrain", "town", "world", "services", "plots", "murph" }) do
			t.ok(table.find(gates, name), name .. " is a first-player gate")
		end
		t.ok(not table.find(gates, "npcs"), "the rest of the townsfolk stay deferred")
		t.ok(not table.find(gates, "deferred"), "the deferred build stays deferred")
		t.ok(not table.find(gates, "firstPlayer"), "firstPlayer is what these gates lead to")
		-- Every one of them is a gate LoadState defines (a typo would never open).
		local source = fs.readFile("src/ServerScriptService/LoadState.luau")
		local defined = string.match(source, "ipairs%((%b{})%) do%s+LoadState%.Gates%.Define")
		t.ok(defined, "LoadState defines its gates in one list")
		for _, name in ipairs(gates) do
			t.ok(string.find(defined, '"' .. name .. '"', 1, true), "LoadState defines " .. name)
		end
	end)

	t.test("Missing names the gates still shut", function()
		local open = { terrain = true, town = true, world = true }
		t.eq(
			JoinFlow.Missing(function(name)
				return open[name] == true
			end),
			{ "services", "plots", "murph" }
		)
		t.eq(
			JoinFlow.Missing(function()
				return true
			end),
			{}
		)
	end)

	t.test("the order: world, save, stream, spawn, ground, client, release", function()
		t.eq(JoinFlow.Decide(state({ worldReady = false, saveLoaded = false })), "waitWorld")
		t.eq(JoinFlow.Decide(state({ saveLoaded = false })), "waitSave")
		t.eq(JoinFlow.Decide(state({ streamed = false, spawned = false })), "stream", "the area before the character")
		t.eq(JoinFlow.Decide(state({ spawned = false, grounded = false, clientReady = false })), "spawn")
		t.eq(JoinFlow.Decide(state({ grounded = false })), "waitGround")
		t.eq(JoinFlow.Decide(state({ clientReady = false })), "waitClient")
		t.eq(JoinFlow.Decide(state()), "release")
	end)

	-- The old behaviour released the player the moment the world was built.
	t.test("regression: a built world alone never releases a player", function()
		local atWorldReady = state({
			saveLoaded = false,
			streamed = false,
			spawned = false,
			grounded = false,
			clientReady = false,
		})
		t.ok(JoinFlow.Decide(atWorldReady) ~= "release")
		t.ok(JoinFlow.Decide(atWorldReady) ~= "spawn", "not even a character yet: the save and the stream come first")
	end)

	t.test("the waits are bounded: a slow client or a floor that never reads still releases", function()
		t.eq(JoinFlow.Decide(state({ grounded = false, groundWaited = JoinFlow.GroundSeconds })), "release")
		t.eq(JoinFlow.Decide(state({ clientReady = false, clientWaited = JoinFlow.ClientWaitSeconds })), "release")
		t.eq(
			JoinFlow.Decide(state({ clientReady = false, clientWaited = JoinFlow.ClientWaitSeconds - 0.1 })),
			"waitClient"
		)
		t.ok(JoinFlow.GateWaitSeconds >= 30, "the gate wait is generous: a cold server builds for a while")
	end)

	t.test("standing: on a floor, still, for a moment", function()
		local tracker = JoinFlow.Settled()
		t.eq(tracker.Update(0, false, 0), false, "in the air")
		t.eq(tracker.Update(0.1, true, 0), false, "landed, not long enough")
		t.eq(tracker.Update(0.2, true, 0.1), false)
		t.eq(tracker.Update(0.1 + JoinFlow.SettleSeconds, true, 0), true, "long enough")
		-- A fall in between starts it over.
		local again = JoinFlow.Settled()
		again.Update(0, true, 0)
		t.eq(again.Update(0.2, true, -30), false, "still falling")
		t.eq(again.Update(0.3, true, 0), false, "the clock restarted")
		t.eq(again.Update(0.3 + JoinFlow.SettleSeconds, true, 0), true)
		t.ok(JoinFlow.OnGround(true, 1.9))
		t.ok(not JoinFlow.OnGround(true, 2))
		t.ok(not JoinFlow.OnGround(false, 0))
	end)

	t.test("respawn delay follows Players.RespawnTime within sane limits", function()
		t.eq(JoinFlow.RespawnDelay(5), 5)
		t.eq(JoinFlow.RespawnDelay(0), 0)
		t.eq(JoinFlow.RespawnDelay(-4), 0)
		t.eq(JoinFlow.RespawnDelay(900), JoinFlow.MaxRespawnSeconds)
		t.eq(JoinFlow.RespawnDelay(nil), 5)
		t.eq(JoinFlow.RespawnDelay("soon"), 5)
		t.eq(JoinFlow.RespawnDelay(0 / 0), 5)
	end)

	-- The wiring, read from the source: the spec cannot run Studio, but it can
	-- stop the old order coming back.
	t.test("the wiring: MapBuilder lets nobody in, GameServer's join flow does, in order", function()
		local map = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		t.ok(string.find(map, "CharacterAutoLoads = false", 1, true), "off before the ground")
		t.ok(string.find(map, "CharacterAutoLoads = true", 1, true) == nil, "MapBuilder never turns it back on")
		t.ok(string.find(map, "LoadCharacter", 1, true) == nil, "and loads nobody")
		local game = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local enter = string.find(game, "pcall(enterWorld", 1, true)
		local loaded = string.find(game, 'player:SetAttribute("ProfileLoaded", true)', 1, true)
		local canPlay = string.find(game, "LoadState.PlayerCanPlay(player.Name)", 1, true)
		t.ok(enter and loaded and canPlay, "the join flow, ProfileLoaded and PlayerCanPlay are all there")
		t.ok(enter < loaded and loaded < canPlay, "the character first, then ProfileLoaded, then 'can play'")
		t.ok(string.find(game, "WaitAll(JoinFlow.FirstPlayerGates", 1, true), "waits on the first-player gates")
		t.ok(string.find(game, "RequestStreamAroundAsync", 1, true), "streams the spawn area first")
		t.ok(string.find(game, "character spawned at +", 1, true), "the [Load] character spawned line")
		t.ok(string.find(game, "client ready handshake", 1, true), "the [Load] client ready handshake line")
		t.ok(string.find(game, 'LoadState.Gates.Set("plots")', 1, true), "the plots gate is opened")
		t.ok(string.find(game, 'LoadState.Gates.Set("murph")', 1, true), "the murph gate is opened")
		t.ok(string.find(game, "player:LoadCharacterAsync()", 1, true), "GameServer loads the character")
		t.ok(string.find(game, "JoinFlow.RespawnDelay", 1, true), "and respawns it after a death")
	end)
end
