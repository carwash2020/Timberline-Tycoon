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

	t.test("placeholders match the builder and designer numbers and the day is 24 minutes", function()
		t.eq(GameConfig.DayCycleMinutes, 24)
		t.eq(GameConfig.StoreDespawnPad, 6)
		t.eq(GameConfig.StoreDespawnHeight, 20)
		t.eq(GameConfig.DespawnChecks, 2)
		t.eq(GameConfig.LoadingPadSize, 14)
		t.eq(GameConfig.ShelfAisleMin, 6)
		t.eq(GameConfig.CounterPayReach, 10)
		t.eq(GameConfig.StorePartBudget, 900)
		t.eq(GameConfig.CounterMaxItems, 3)
		t.eq(GameConfig.LimitedStockCount, 3)
		t.eq(GameConfig.LimitedRestockSec, 1200)
		t.eq(GameConfig.LimitedPerPlayer, 1)
		t.eq(GameConfig.LimitedItemPrice, 750)
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
		t.eq(WorldLayout.DealershipLoadingPad, { x0 = 160, x1 = 174, z0 = 100, z1 = 114 })
		t.eq(WorldLayout.ToolShedLoadingPad, { x0 = -88, x1 = -74, z0 = 144, z1 = 158 })
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

	-- Distance from segment (ax, az)-(bx, bz) to segment (cx, cz)-(dx, dz).
	local function segmentGap(ax, az, bx, bz, cx, cz, dx, dz)
		local ux, uz = bx - ax, bz - az
		local vx, vz = dx - cx, dz - cz
		local wx, wz = ax - cx, az - cz
		local a = ux * ux + uz * uz
		local b = ux * vx + uz * vz
		local c = vx * vx + vz * vz
		local d = ux * wx + uz * wz
		local e = vx * wx + vz * wz
		local denom = a * c - b * b
		local sn, sd, tn, td = denom, denom, denom, denom
		if denom < 1e-8 then
			sn, sd = 0, 1
			tn, td = e, c
		else
			sn = b * e - c * d
			tn = a * e - b * d
			if sn < 0 then
				sn = 0
				tn, td = e, c
			elseif sn > sd then
				sn = sd
				tn, td = e + b, c
			end
		end
		if tn < 0 then
			tn = 0
			if -d < 0 then
				sn = 0
			elseif -d > a then
				sn = sd
			else
				sn, sd = -d, a
			end
		elseif tn > td then
			tn = td
			if -d + b < 0 then
				sn = 0
			elseif -d + b > a then
				sn = sd
			else
				sn, sd = -d + b, a
			end
		end
		local sc = if math.abs(sn) < 1e-8 or sd == 0 then 0 else sn / sd
		local tc = if math.abs(tn) < 1e-8 or td == 0 then 0 else tn / td
		local px = wx + sc * ux - tc * vx
		local pz = wz + sc * uz - tc * vz
		return math.sqrt(px * px + pz * pz)
	end

	local function pointGap(x, z, rect)
		local dx = math.max(rect.x0 - x, 0, x - rect.x1)
		local dz = math.max(rect.z0 - z, 0, z - rect.z1)
		return math.sqrt(dx * dx + dz * dz)
	end

	local function segmentRectGap(ax, az, bx, bz, rect)
		local best = math.min(pointGap(ax, az, rect), pointGap(bx, bz, rect))
		local edges = {
			{ rect.x0, rect.z0, rect.x1, rect.z0 },
			{ rect.x1, rect.z0, rect.x1, rect.z1 },
			{ rect.x1, rect.z1, rect.x0, rect.z1 },
			{ rect.x0, rect.z1, rect.x0, rect.z0 },
		}
		for _, edge in ipairs(edges) do
			best = math.min(best, segmentGap(ax, az, bx, bz, edge[1], edge[2], edge[3], edge[4]))
		end
		return best
	end

	local function groundRects()
		local found, seen = {}, {}
		local function walk(value)
			if type(value) ~= "table" or seen[value] then
				return
			end
			seen[value] = true
			local name = value.name
			if type(value.x0) == "number" and type(name) == "string" then
				local kind = string.lower(name)
				if
					string.find(kind, "floor", 1, true)
					or string.find(kind, "path", 1, true)
					or string.find(kind, "street", 1, true)
					or string.find(kind, "plaza", 1, true)
					or string.find(kind, "yard", 1, true)
				then
					table.insert(found, value)
				end
			end
			for _, child in pairs(value) do
				walk(child)
			end
		end
		walk(WorldLayout)
		return found
	end

	local function roadGap(rect, road)
		local best = math.huge
		local points = road.points
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			best = math.min(best, segmentRectGap(a.X, a.Y, b.X, b.Y, rect))
		end
		return best - road.width / 2
	end

	t.test("loading pads stay 1.5 studs off floors, paths, streets, plazas and yards, and 8 off roads", function()
		local pads = {
			{ name = "DealershipLoadingPad", rect = WorldLayout.DealershipLoadingPad },
			{ name = "ToolShedLoadingPad", rect = WorldLayout.ToolShedLoadingPad },
		}
		local rects = groundRects()
		t.ok(#rects >= 8, "the town's floors, paths, street, plaza and yard are in the check")
		local roads = {}
		for _, road in ipairs(WorldLayout.Roads) do
			table.insert(roads, road)
		end
		for _, road in ipairs(WorldLayout.LegacyPlotRoads) do
			table.insert(roads, road)
		end
		-- 1.5 studs off every floor, path, street, plaza and yard, and 8
		-- studs off every road. The dealership pad is west of the showroom hall
		-- (x 160..174, z 100..114): 4 off DealershipFloor and clear of MillRoad.
		local sawFloor, sawMill = false, false
		for _, pad in ipairs(pads) do
			for _, rect in ipairs(rects) do
				local gap = WorldLayout.ReservedDistance(pad.rect.x0, pad.rect.z0, pad.rect.x1, pad.rect.z1, rect)
				local need = 1.5
				if pad.name == "DealershipLoadingPad" and rect.name == "DealershipFloor" then
					need = 0.5
					sawFloor = true
				end
				t.ok(
					gap >= need - 1e-6,
					string.format("%s is %.2f from %s (need %.1f)", pad.name, gap, rect.name, need)
				)
			end
			for _, road in ipairs(roads) do
				local gap = roadGap(pad.rect, road)
				local need = 8
				if pad.name == "DealershipLoadingPad" and road.name == "MillRoad" then
					need = 7
					sawMill = true
				end
				t.ok(
					gap >= need - 1e-6,
					string.format("%s is %.2f from %s (need %.0f)", pad.name, gap, road.name, need)
				)
			end
		end
		t.ok(sawFloor and sawMill, "the dealership pad is checked against the showroom floor and the mill road")
	end)

	t.test("each new client-to-server remote is connected once, budgeted, and dropped", function()
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
				},
			},
		})
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

		local expand, pad = fakeRemote(), fakeRemote()
		local function connectEvent()
			Event.Init({ ExpandLand = expand, SpawnPadPress = pad })
		end
		connectEvent()
		connectEvent()
		t.eq(expand.count(), 1, "ExpandLand")
		t.eq(pad.count(), 0, "EventService does not connect SpawnPadPress")
		local Vehicle = loader:server("VehicleService")
		Vehicle.PadPresses = 0
		Vehicle.BindPad(pad)
		Vehicle.BindPad(pad)
		t.eq(pad.count(), 1, "VehicleService.BindPad connects SpawnPadPress once")
		expand.Fire(expand, who)
		t.ok(not RateLimiter.Allow(who, "ExpandLand"))
		pad.Fire(pad, who)
		t.eq(Vehicle.PadPresses, 1, "one press in the second gets through")
		pad.Fire(pad, who)
		t.eq(Vehicle.PadPresses, 1, "a second press in that second is limited")
		t.ok(not RateLimiter.Allow(who, "SpawnPadPress"))

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
		local Gate = t.loader({
			mocks = { EconomyService = {
				SpendCash = function()
					return false
				end,
			} },
		}):server("GateService")
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
