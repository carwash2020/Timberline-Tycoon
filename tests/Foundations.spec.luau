--!nocheck
-- Wave 0 foundations: reserved remotes, unread config, loading pads.
return function(t)
	local GameConfig = t.shared("GameConfig")
	local WorldLayout = t.shared("World/WorldLayout")
	local WoodData = t.shared("WoodData")

	local CLIENT_TO_SERVER = {
		"Dialogue",
		"BoxOpen",
		"SpawnPadPress",
		"ChopSawSet",
		"ExpandLand",
		"SetPermission",
		"Wire",
		"TollPay",
		"FerryBoard",
	}

	local function fakeRemote()
		local handlers = {}
		return {
			OnServerEvent = {
				Connect = function(_, fn)
					table.insert(handlers, fn)
					return { Disconnect = function() end }
				end,
			},
			Fire = function(_, player)
				for _, fn in ipairs(handlers) do
					fn(player)
				end
			end,
			count = function()
				return #handlers
			end,
		}
	end

	local function player()
		return { Name = "Tester", UserId = 7 }
	end

	t.test("placeholders match the builder and designer numbers and the day is unchanged", function()
		t.eq(GameConfig.DayCycleMinutes, 20)
		t.eq(GameConfig.StoreDespawnPad, 6)
		t.eq(GameConfig.StoreDespawnHeight, 20)
		t.eq(GameConfig.DespawnChecks, 2)
		t.eq(GameConfig.LoadingPadSize, 14)
		t.eq(GameConfig.ShelfAisleMin, 6)
		t.eq(GameConfig.CounterPayReach, 10)
		t.eq(GameConfig.StorePartBudget, 250)
		t.eq(GameConfig.CounterMaxItems, 3)
		t.eq(GameConfig.LimitedStockCount, 3)
		t.eq(GameConfig.LimitedRestockSec, 1200)
		t.eq(GameConfig.LimitedPerPlayer, 1)
		t.eq(GameConfig.LimitedItemPrice, 750)
		t.eq(GameConfig.ChopSawPrice, 12200)
		t.eq(GameConfig.DynamitePrice, 220)
		t.eq(GameConfig.DynamitePrice, GameConfig.BlastingChargePrice)
		t.eq(GameConfig.DemandBoost, 0.2)
		t.eq(GameConfig.BoxRespawnSec, 60)
		t.eq(GameConfig.BoxUnpaidDespawnSec, 180)
		t.eq(GameConfig.ShopHours, { open = 7, close = 19 })
		t.eq(GameConfig.NightGlowWoodId, "lumenwood")
		t.ok(WoodData.Get("lumenwood") ~= nil, "the glow id is a wood we already have")
	end)

	t.test("loading pads are 14-stud rects that terrain and reservation do not read", function()
		local function unused(rect, label)
			t.eq(rect.x1 - rect.x0, GameConfig.LoadingPadSize, label)
			t.eq(rect.z1 - rect.z0, GameConfig.LoadingPadSize, label)
		end
		unused(WorldLayout.DealershipLoadingPad, "DealershipLoadingPad")
		unused(WorldLayout.ToolShedLoadingPad, "ToolShedLoadingPad")
		local function absent(list)
			for _, zone in ipairs(list) do
				t.ok(zone.name ~= "DealershipLoadingPad" and zone.name ~= "ToolShedLoadingPad", zone.name)
			end
		end
		absent(WorldLayout.FlatZones)
		absent(WorldLayout.TownPaint)
		absent(WorldLayout.TownFloors)
		absent(WorldLayout.Reserved)
	end)

	t.test("each new client-to-server remote is connected once, budgeted, and dropped", function()
		local loader = t.loader()
		local RateLimiter = loader:server("RateLimiter")
		local Dialogue = loader:server("DialogueService")
		local Box = loader:server("BoxService")
		local Gate = loader:server("GateService")
		local Ferry = loader:server("FerryService")
		local Permission = loader:server("PermissionService")
		local Logic = loader:server("LogicService")
		local Event = loader:server("EventService")
		local who = player()

		local function once(remote, connect, name, limit)
			connect()
			connect()
			t.eq(remote.count(), 1, name .. " connected once")
			for _ = 1, limit do
				remote.Fire(remote, who)
			end
			t.ok(not RateLimiter.Allow(who, name), name .. " spent its budget and did nothing else")
		end

		local dialogue = fakeRemote()
		once(dialogue, function()
			Dialogue.Init(dialogue)
		end, "Dialogue", 4)

		local box = fakeRemote()
		once(box, function()
			Box.Init(box)
		end, "BoxOpen", 4)

		local toll = fakeRemote()
		once(toll, function()
			Gate.Init(toll)
		end, "TollPay", 1)

		local ferry = fakeRemote()
		once(ferry, function()
			Ferry.Init(ferry)
		end, "FerryBoard", 1)

		local perm = fakeRemote()
		once(perm, function()
			Permission.Init(perm)
		end, "SetPermission", 4)

		local wire = fakeRemote()
		once(wire, function()
			Logic.Init(wire)
		end, "Wire", 4)

		local expand, pad, saw = fakeRemote(), fakeRemote(), fakeRemote()
		local function connectEvent()
			Event.Init({ ExpandLand = expand, SpawnPadPress = pad, ChopSawSet = saw })
		end
		connectEvent()
		connectEvent()
		t.eq(expand.count(), 1, "ExpandLand")
		t.eq(pad.count(), 1, "SpawnPadPress")
		t.eq(saw.count(), 1, "ChopSawSet")
		expand.Fire(expand, who)
		t.ok(not RateLimiter.Allow(who, "ExpandLand"))
		pad.Fire(pad, who)
		t.ok(not RateLimiter.Allow(who, "SpawnPadPress"))
		for _ = 1, 6 do
			saw.Fire(saw, who)
		end
		t.ok(not RateLimiter.Allow(who, "ChopSawSet"))

		local fs = require("@lune/fs")
		local function readTree(dir, out)
			for _, entry in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					readTree(path, out)
				elseif string.sub(entry, -5) == ".luau" then
					table.insert(out, fs.readFile(path))
				end
			end
		end
		local sources = {}
		readTree("src", sources)
		local all = table.concat(sources, "\n")
		for _, name in ipairs(CLIENT_TO_SERVER) do
			local _, count = string.gsub(all, 'RateLimiter.Allow%(player, "' .. name .. '"%)', "")
			t.eq(count, 1, name .. " has one handler")
		end
		local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(server, "BootReport.StartStubs(", 1, true) ~= nil)
		t.ok(string.find(server, "GateService.PlayerRemoving", 1, true) ~= nil)
		t.ok(string.find(all, "BadgeSync.OnServerEvent", 1, true) == nil, "BadgeSync is not connected")
	end)

	t.test("tollPaidUntil is a server table cleared when the player leaves", function()
		local Gate = t.loader():server("GateService")
		Gate.TollPaidUntil[7] = 5000
		Gate.TollPaidUntil[8] = 6000
		Gate.PlayerRemoving({ UserId = 7 })
		t.eq(Gate.TollPaidUntil[7], nil)
		t.eq(Gate.TollPaidUntil[8], 6000)
		local Schema = t.server("ProfileSchema")
		t.eq(Schema.Template.tollPaidUntil, nil)
	end)

	t.test("BoxService registers the Boxes collision group", function()
		local registered = {}
		local loader = t.loader({
			services = {
				PhysicsService = {
					IsCollisionGroupRegistered = function(_, name)
						return registered[name] == true
					end,
					RegisterCollisionGroup = function(_, name)
						registered[name] = true
					end,
				},
			},
		})
		local Box = loader:server("BoxService")
		Box.Init(fakeRemote())
		t.eq(registered.Boxes, true)
		t.eq(Box.Group, "Boxes")
	end)
end
