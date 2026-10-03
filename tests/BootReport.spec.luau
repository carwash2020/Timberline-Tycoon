--!nocheck
-- BootReport (PLAY-01): GameServer's one-line boot report.
return function(t)
	local BootReport = t.server("BootReport")

	local function world(attributes)
		return {
			GetAttribute = function(_, name)
				return attributes[name]
			end,
		}
	end

	t.test("reports build seconds, terrain seconds, trees and players", function()
		local line = BootReport.Line(
			world({ MapBuildSeconds = 12.44, MapTerrainSeconds = 9.81, MapTrees = 334, MapBuildFailures = 0 }),
			2
		)
		t.eq(line, "[GameServer] Online: world built in 12.4s (terrain 9.8s), 334 trees, 2 players")
	end)

	t.test("one of each reads singular", function()
		local line = BootReport.Line(world({ MapBuildSeconds = 3, MapTerrainSeconds = 0, MapTrees = 1 }), 1)
		t.eq(line, "[GameServer] Online: world built in 3.0s (terrain 0.0s), 1 tree, 1 player")
	end)

	t.test("failed build steps are named", function()
		local line = BootReport.Line(
			world({ MapBuildSeconds = 4, MapTerrainSeconds = 1, MapTrees = 300, MapBuildFailures = 2 }),
			0
		)
		t.eq(
			line,
			"[GameServer] Online: world built in 4.0s (terrain 1.0s), 300 trees, 0 players,"
				.. " 2 build steps failed (see the [MapBuilder] warnings)"
		)
	end)

	t.test("missing stats show as ? and never error", function()
		t.eq(BootReport.Line(world({}), 0), "[GameServer] Online: world built in ?s (terrain ?s), ? trees, 0 players")
		t.eq(
			BootReport.Line(world({ MapBuildSeconds = "soon", MapTrees = true }), 1),
			"[GameServer] Online: world built in ?s (terrain ?s), ? trees, 1 player"
		)
		local broken = {
			GetAttribute = function()
				error("no attributes")
			end,
		}
		t.eq(BootReport.Line(broken, 3), "[GameServer] Online: world built in ?s (terrain ?s), ? trees, 3 players")
	end)

	t.test("custom events carry build seconds, terrain seconds and failures", function()
		local events = BootReport.Events(
			world({ MapBuildSeconds = 12.44, MapTerrainSeconds = 9.81, MapTrees = 334, MapBuildFailures = 2 })
		)
		t.eq(events, {
			{ name = "ServerWorldBuildSeconds", value = 12.44 },
			{ name = "ServerTerrainBuildSeconds", value = 9.81 },
			{ name = "ServerWorldBuildFailures", value = 2 },
		})
		t.eq(BootReport.Events(world({ MapBuildSeconds = 3, MapTerrainSeconds = 0, MapBuildFailures = 0 })), {
			{ name = "ServerWorldBuildSeconds", value = 3 },
			{ name = "ServerTerrainBuildSeconds", value = 0 },
			{ name = "ServerWorldBuildFailures", value = 0 },
		}, "a clean boot still reports zero failures")
		t.eq(BootReport.Events(world({})), {}, "a missing stat is left out, not sent as garbage")
		local broken = {
			GetAttribute = function()
				error("no attributes")
			end,
		}
		t.eq(BootReport.Events(broken), {})
	end)

	t.test("Log sends those events for the first player and never throws", function()
		local sent = {}
		local analytics = {
			LogCustomEvent = function(_, player, name, value)
				table.insert(sent, { player = player, name = name, value = value })
			end,
		}
		local dale = { Name = "Dale" }
		t.eq(
			BootReport.Log(world({ MapBuildSeconds = 4, MapTerrainSeconds = 1, MapBuildFailures = 0 }), {}, analytics),
			false
		)
		t.eq(sent, {}, "nobody to attach them to yet")
		t.eq(
			BootReport.Log(
				world({ MapBuildSeconds = 4, MapTerrainSeconds = 1, MapBuildFailures = 0 }),
				{ dale, { Name = "Other" } },
				analytics
			),
			true
		)
		t.eq(#sent, 3, "one sample for the server, not one per player")
		t.eq(sent[1].player, dale)
		t.eq(sent[1].name, "ServerWorldBuildSeconds")
		t.eq(sent[1].value, 4)
		t.eq(sent[3].name, "ServerWorldBuildFailures")
		t.eq(sent[3].value, 0)
		local throwing = {
			LogCustomEvent = function()
				error("analytics down")
			end,
		}
		t.eq(
			BootReport.Log(
				world({ MapBuildSeconds = 1, MapTerrainSeconds = 1, MapBuildFailures = 1 }),
				{ dale },
				throwing
			),
			true,
			"a failed send doesn't stop the boot"
		)
	end)

	t.test("GameServer still prints the line and also logs the events", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(source, "print(BootReport.Line(", 1, true), "the server log print stays")
		t.ok(string.find(source, "BootReport.Log(", 1, true), "the same timings are custom events")
	end)

	t.test("reads what MapBuilder publishes (the attribute names match)", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		for _, name in ipairs({ "MapBuildSeconds", "MapTerrainSeconds", "MapTrees", "MapBuildFailures" }) do
			t.ok(string.find(source, 'workspace:SetAttribute("' .. name .. '"', 1, true), "MapBuilder sets " .. name)
		end
	end)
end
