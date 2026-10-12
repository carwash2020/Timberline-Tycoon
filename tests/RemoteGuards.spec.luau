--!nocheck
-- V1 hardening (item 2, exploit guards): every remote in Net, one by one.
--
-- V1Refs checks the lists agree (a budget, a user, a listener). This goes
-- one step further for each client -> server remote: the table below names
-- the file that connects it and the file and budget its handler spends, and
-- the spec proves
--   * the table and Net.RemoteNames agree (a new remote fails here until it
--     is classified, so none can ship unguarded);
--   * the handler's file connects the remote and spends exactly that budget
--     through RateLimiter.Allow (the real limiter, below);
--   * every payload parameter of every handler is typed `unknown`, so the
--     type checker forces the handler to validate it before use;
--   * the budget behaves: the limit is spent, the next request is dropped, a
--     new second refills it, one player's spam never touches another's, a
--     human burst is never a strike, and an unknown name is refused;
--   * sell, buy, build and grab have explicit tight budgets;
--   * the v1-loop remotes are connected only under the v1 loop.
-- The bad-payload tests (NaN, huge, long, wrong class, far away, someone
-- else's plot or box, spam) sit beside each family's own harness: ShopService,
-- PlotService, GrabService, BoxService, SawmillService, DialogueService,
-- PermissionService, SectionTrees and the others.
return function(t)
	local fs = require("@lune/fs")

	-- remote -> { connect = file that connects OnServerEvent, allow = file whose
	-- handler spends the budget, limit = the RateLimiter name, family, v1 }.
	-- Files are in src/ServerScriptService (.luau).
	local function row(family, connect, allow, limit, v1)
		return { family = family, connect = connect, allow = allow, limit = limit or false, v1 = v1 == true }
	end
	local GS = "GameServer.server"
	local TABLE = {
		-- sell
		SellPlaced = row("sell", "PlotService", "PlotService", "SellPlaced"),
		UseInstantDelivery = row("sell", GS, GS, "UseInstantDelivery"),
		SellLogs = row("sell", GS, GS, "SellLogs", true),
		-- buy
		BuyItem = row("buy", "ShopService", "ShopService", "BuyItem"),
		EquipItem = row("buy", "ShopService", "ShopService", "EquipItem"),
		BuyRobuxItem = row("buy", "MonetizationService", "MonetizationService", "BuyRobuxItem"),
		-- build
		PlaceBlueprint = row("build", "PlotService", "PlotService", "PlaceBlueprint"),
		MoveBlueprint = row("build", "PlotService", "PlotService", "MoveBlueprint"),
		BlueprintEdit = row("build", "PlotService", "PlotService", "BlueprintEdit"),
		UpgradePlot = row("build", "PlotService", "PlotService", "UpgradePlot"),
		ExpandLand = row("build", "EventService", "EventService", "ExpandLand"),
		ClaimPlot = row("build", "PlotService", "PlotService", "ClaimPlot"),
		PlotPass = row("build", "PlotService", "PlotService", "PlotPass"),
		PlotShown = row("build", "PlotService", "PlotService", "PlotShown"),
		BaseAction = row("build", "PlotService", "PlotService", "BaseAction"),
		PaintPiece = row("build", "PlotService", "PlotService", "PaintPiece"),
		PaintAllType = row("build", "PlotService", "PlotService", "PaintAllType"),
		VisitPlot = row("build", "PlotService", "PlotService", "VisitPlot"),
		UseBlueprint = row("build", "BlueprintService", "BlueprintService", "UseBlueprint"),
		DropBlueprint = row("build", "BlueprintService", "BlueprintService", "DropBlueprint"),
		SetPermission = row("build", "PermissionService", "PermissionService", "SetPermission"),
		Wire = row("build", "LogicService", "LogicService", "Wire"),
		LogicSet = row("build", "LogicService", "LogicService", "LogicSet"),
		-- grab and carry
		Grab = row("grab", "GrabService", "GrabService", "Grab"),
		Release = row("grab", "GrabService", "GrabService", "Release"),
		DropAxe = row("grab", GS, "AxeService", "DropAxe"),
		BoxOpen = row("grab", "BoxService", "BoxService", "BoxOpen"),
		PickupLog = row("grab", GS, GS, "PickupLog", true),
		LoadToTruck = row("grab", GS, GS, "LoadToTruck", true),
		-- chop and mine
		Chop = row("work", GS, "SectionTrees", "Chop"),
		ChopTree = row("work", GS, GS, "ChopTree", true),
		Swing = row("work", GS, GS, "Swing"),
		MineNode = row("work", GS, GS, "MineNode"),
		MineAction = row("work", "MiningService", "MiningService", "MineAction"),
		CraftAction = row("work", "CraftingService", "CraftingService", "CraftAction"),
		-- machines
		SawmillSet = row("machine", "SawmillService", "SawmillService", "SawmillSet"),
		PlanerSet = row("machine", "PlanerService", "PlanerService", "PlanerSet"),
		ChopSawSet = row("machine", "ChopSawService", "ChopSawService", "ChopSawSet"),
		ForgeAction = row("machine", "SkyForgeService", "SkyForgeService", "ForgeAction"),
		ForgeOpen = row("machine", "SkyForgeService", "SkyForgeService", "ForgeOpen"),
		SkyQuest = row("machine", "SkyQuestService", "SkyQuestService", "SkyQuest"),
		-- talk, trucks, travel, saves, settings, the owner
		Dialogue = row("world", "DialogueService", "DialogueService", "Dialogue"),
		SpawnPadPress = row("world", "VehicleService", "VehicleService", "SpawnPadPress"),
		CallTruck = row("world", GS, GS, "CallTruck"),
		PaintTruck = row("world", "PaintService", "PaintService", "PaintTruck"),
		TollPay = row("world", "GateService", "GateService", "TollPay"),
		FerryBoard = row("world", "FerryService", "FerryService", "FerryBoard"),
		ForemanTurnIn = row("world", "DailyService", "DailyService", "ForemanTurnIn"),
		BoardRequest = row("world", "LeaderboardService", "LeaderboardService", "BoardRequest"),
		SkipTutorial = row("session", "QuestService", "QuestService", "SkipTutorial"),
		ResetTutorial = row("session", "QuestService", "QuestService", "ResetTutorial"),
		TutorialSeen = row("session", "QuestService", "QuestService", "TutorialSeen"),
		NewsSeen = row("session", GS, GS, "NewsSeen"),
		SaveSetting = row("session", GS, GS, "SaveSetting"),
		SetQuality = row("session", GS, "QualityService", "SetQuality"),
		ClientReady = row("session", GS, "ClientHandshake", "ClientReady"), -- bound in GameServer, limited in ClientHandshake
		Sprint = row("session", GS, GS, "Sprint"),
		SlotAction = row("session", "SaveSlotService", "SaveSlotService", "SlotAction"),
		SaveNow = row("session", "SaveSlotService", "SaveSlotService", "SaveNow"),
		AdminRun = row("owner", GS, GS, "AdminRun"),
		PlotModerate = row("build", "PlotService", "PlotService", "PlotModerate"),
		RedeemCode = row("session", "CodeService", "CodeService", "RedeemCode"),
		StoreOpened = row("session", GS, GS, "StoreOpened"),
		Activity = row("session", GS, GS, "Activity"),
	}
	-- Server -> client only: the server fires them; nothing may connect them.
	local SERVER_TO_CLIENT = {
		AdminResult = true,
		AdminAccess = true,
		PlotOffer = true,
		BadgeSync = true,
		CashChanged = true,
		Notify = true,
		WorldFX = true,
		SlotState = true,
		BoardData = true,
		CodeResult = true,
	}

	local cache = {}
	local function read(path)
		if cache[path] == nil then
			cache[path] = fs.readFile(path)
		end
		return cache[path]
	end
	local function code(path)
		local lines = {}
		for line in string.gmatch(read(path), "[^\n]*") do
			if not string.match(line, "^%s*%-%-") then
				table.insert(lines, line)
			end
		end
		return table.concat(lines, "\n")
	end
	local function serverFile(name)
		return "src/ServerScriptService/" .. name .. ".luau"
	end

	local Net = t.shared("Net")

	t.test("every remote in Net is classified: a guarded client -> server row, or server -> client only", function()
		local listed = {}
		for _, name in ipairs(Net.RemoteNames) do
			listed[name] = true
			t.ok(
				TABLE[name] ~= nil or SERVER_TO_CLIENT[name] == true,
				name .. " is in Net.RemoteNames but not classified in tests/RemoteGuards.spec.luau"
			)
			t.ok(not (TABLE[name] ~= nil and SERVER_TO_CLIENT[name] == true), name .. " is in both lists")
		end
		for name in pairs(TABLE) do
			t.ok(listed[name], name .. " is guarded here but is not in Net.RemoteNames")
		end
		for name in pairs(SERVER_TO_CLIENT) do
			t.ok(listed[name], name .. " is listed server -> client but is not in Net.RemoteNames")
		end
	end)

	t.test("a server -> client remote has no server handler (the client can never drive it)", function()
		for name in pairs(SERVER_TO_CLIENT) do
			for _, file in ipairs(fs.readDir("src/ServerScriptService")) do
				if string.sub(file, -5) == ".luau" and not string.find(file, "Vendor", 1, true) then
					local src = code("src/ServerScriptService/" .. file)
					t.eq(
						string.find(src, "%." .. name .. "%.OnServerEvent"),
						nil,
						file .. " connects the server -> client remote " .. name
					)
				end
			end
		end
	end)

	t.test("each handler's file connects its remote and spends its own RateLimiter budget", function()
		for name, r in pairs(TABLE) do
			local connect = code(serverFile(r.connect))
			t.ok(
				string.find(connect, "OnServerEvent", 1, true) ~= nil,
				name .. ": " .. r.connect .. " connects nothing"
			)
			t.ok(string.find(connect, name, 1, true) ~= nil, name .. " is not named in " .. r.connect)
			local allow = code(serverFile(r.allow))
			local spends = string.find(allow, 'RateLimiter.Allow%([%w_%.]+, "' .. r.limit .. '"%)') ~= nil
			t.ok(spends, name .. ": " .. r.allow .. ' never calls RateLimiter.Allow(player, "' .. r.limit .. '")')
		end
	end)

	t.test("every payload parameter of a handler is typed unknown, so it must be validated before use", function()
		local scanned = 0
		for _, file in ipairs(fs.readDir("src/ServerScriptService")) do
			if string.sub(file, -5) == ".luau" then
				local src = code("src/ServerScriptService/" .. file)
				-- OnServerEvent:Connect(function(player: Player, a: T, b: T)
				for params in string.gmatch(src, "OnServerEvent:Connect%(function%(([^)]*)%)") do
					scanned += 1
					local first = true
					for param in string.gmatch(params, "[^,]+") do
						if first then
							first = false
						else
							t.ok(
								string.find(param, ":%s*unknown%s*$") ~= nil,
								file .. ": a handler parameter is not typed unknown: " .. param
							)
						end
					end
				end
			end
		end
		t.ok(scanned >= 20, "scanned " .. scanned .. " inline handlers")
		-- The handlers connected by name.
		local named = {
			{ "PlotService", "function PlotService.Place(", { "blueprintId", "x", "z", "rot", "y", "boxUid" } },
			{ "PlotService", "function PlotService.Move(", { "uid", "x", "z", "rot", "y" } },
			{ "PlotService", "function PlotService.Sell(", { "uid" } },
			{ "BlueprintService", "function BlueprintService.Use(", { "uid" } },
			{ "BlueprintService", "function BlueprintService.Drop(", { "uid" } },
			{ "AxeService", "function AxeService.Drop(", { "uid" } },
			{ "ShopService", "local function onBuyItem(", { "category", "itemId" } },
			{ "ShopService", "local function onEquipItem(", { "category", "itemId" } },
			{ "BoxService", "function onBoxOpen(", { "action" } },
			{ "VehicleService", "local function onPadPress(", { "pad" } },
			{ "LogicService", "function LogicService.OnWire(", { "a", "b", "c", "d" } },
			{ "MonetizationService", "local function onBuy(", { "kind", "key" } },
			{ "QuestService", "local function onSeen(", { "what" } },
			{ "CodeService", "local function onRedeem(", { "raw" } },
			{ "GameServer.server", "local function onSwing(", { "woodId", "cancel" } },
			{ "GameServer.server", "local function onMineNode(", { "nodeUid" } },
		}
		for _, n in ipairs(named) do
			local src = code(serverFile(n[1]))
			local at = string.find(src, n[2], 1, true)
			t.ok(at ~= nil, n[1] .. " no longer defines " .. n[2])
			if at then
				local params = string.match(src, "%b()", at + #n[2] - 1) or ""
				for _, p in ipairs(n[3]) do
					t.ok(
						string.find(params, p .. "%s*:%s*unknown") ~= nil,
						n[1] .. ": " .. p .. " of " .. n[2] .. " is not typed unknown"
					)
				end
			end
		end
	end)

	-- The real limiter, a fake clock. Budgets are read off its behaviour.
	local now = 100
	local fakeOs = setmetatable({
		clock = function()
			return now
		end,
	}, { __index = os })
	local function limiter()
		now = 100
		return t.loader({ globals = { os = fakeOs } }):server("RateLimiter")
	end
	local function player(name)
		return {
			Name = name or "Tester",
			kicked = nil,
			Kick = function(self, reason)
				self.kicked = reason
			end,
		}
	end
	local function spend(L, p, name, n)
		local allowed = 0
		for _ = 1, n do
			if L.Allow(p, name) then
				allowed += 1
			end
		end
		return allowed
	end
	-- The budget, found by spending it.
	local function budget(name)
		return spend(limiter(), player(), name, 200)
	end

	t.test("every guarded remote has a budget of 1 to 8 a second, and nothing above that", function()
		for name, r in pairs(TABLE) do
			local n = budget(r.limit)
			t.ok(n >= 1 and n <= 8, name .. " (" .. r.limit .. ") allows " .. n .. " a second")
		end
	end)

	t.test("sell, buy, build and grab have explicit tight budgets", function()
		local cap = {
			-- sell
			SellPlaced = 4,
			SellLogs = 4,
			UseInstantDelivery = 2,
			-- buy
			BuyItem = 3,
			EquipItem = 2,
			BuyRobuxItem = 2,
			-- build
			PlaceBlueprint = 2,
			MoveBlueprint = 2,
			BlueprintEdit = 5,
			UpgradePlot = 1,
			ExpandLand = 1,
			ClaimPlot = 4,
			SetPermission = 4,
			Wire = 4,
			-- grab
			Grab = 6,
			Release = 6,
			DropAxe = 2,
			BoxOpen = 4,
		}
		for name, most in pairs(cap) do
			local r = TABLE[name]
			t.ok(r ~= nil, name .. " is not guarded here")
			local n = budget(r.limit)
			t.ok(n <= most, name .. " allows " .. n .. " a second; the tight budget is " .. most)
		end
		-- Money never moves faster than a few presses a second.
		for _, name in ipairs({ "SellPlaced", "BuyItem", "BuyRobuxItem", "PlaceBlueprint" }) do
			t.ok(budget(name) <= 4, name)
		end
	end)

	t.test("past its budget a request is dropped, in the same second and only that second", function()
		for name, r in pairs(TABLE) do
			local L = limiter()
			local p = player()
			local first = spend(L, p, r.limit, 3 * 8)
			t.ok(first >= 1, name)
			t.eq(L.Allow(p, r.limit), false, name .. " is still dropped")
			now += 1
			t.eq(L.Allow(p, r.limit), true, name .. " has a fresh budget the next second")
			t.eq(p.kicked, nil, name .. ": spam is dropped quietly, never a kick for a human burst")
		end
	end)

	t.test("one player's spam never spends another's budget, and a mash is not a strike", function()
		for name, r in pairs(TABLE) do
			local L = limiter()
			local spammer, other = player("Spammer"), player("Other")
			local n = budget(r.limit)
			spend(L, spammer, r.limit, n * 3)
			t.eq(spend(L, other, r.limit, n), n, name .. ": the other player has the whole budget")
			t.eq(spammer.kicked, nil, name .. ": three times the budget in a second is mashing")
		end
	end)

	t.test("a flood far past any human rate, kept up, is kicked; a leaver's strikes are forgotten", function()
		local L = limiter()
		local p = player()
		for second = 1, 6 do
			spend(L, p, "Grab", 200)
			now += 1
			if p.kicked then
				break
			end
			t.ok(second < 6, "never kicked")
		end
		t.ok(p.kicked ~= nil, "five flooded seconds is a kick")
		local q = player()
		for _ = 1, 4 do
			spend(L, q, "Grab", 200)
			now += 1
		end
		L.Forget(q)
		spend(L, q, "Grab", 200)
		now += 1
		t.eq(q.kicked, nil, "Forget clears the strikes")
	end)

	t.test("a name with no budget is refused, never allowed by default", function()
		local L = limiter()
		local p = player()
		for _, junk in ipairs({ "NoSuchRemote", "", "grab", "GRAB", "Grab ", string.rep("x", 10000) }) do
			t.eq(L.Allow(p, junk), false)
		end
	end)

	t.test("the v1 loop's remotes are connected only under the v1 loop; v2 never hears them", function()
		local src = code("src/ServerScriptService/GameServer.server.luau")
		local gate = string.find(src, "if not CoreLoop.V2() then", 1, true)
		t.ok(gate ~= nil, "the v1 gate exists")
		local closes = string.find(src, "\nend\n", gate, true)
		for name, r in pairs(TABLE) do
			if r.v1 then
				local at = string.find(src, "remote." .. name .. ".OnServerEvent", 1, true)
				t.ok(at ~= nil, name .. " is not connected in GameServer")
				t.ok(at > gate and at < closes, name .. " is connected outside the v1 gate")
			end
		end
		-- The v2 intents are never inside it.
		for _, name in ipairs({ "Chop", "Swing", "MineNode", "UseInstantDelivery" }) do
			local at = string.find(src, "remote." .. name .. ".OnServerEvent", 1, true)
			t.ok(at ~= nil and (at < gate or at > closes), name .. " must stay connected under v2")
		end
	end)

	t.test("no handler trusts a player id from the client for who is acting", function()
		-- A target may be named (VisitPlot's owner, SetPermission's visitor): the
		-- actor is always the `player` argument the engine fills in. No handler
		-- takes a parameter that names the actor.
		for _, file in ipairs(fs.readDir("src/ServerScriptService")) do
			if string.sub(file, -5) == ".luau" then
				local src = code("src/ServerScriptService/" .. file)
				for params in string.gmatch(src, "OnServerEvent:Connect%(function%(([^)]*)%)") do
					for param in string.gmatch(params, "[^,]+") do
						local name = string.lower(string.match(param, "^%s*([%w_]+)") or "")
						-- PlotModerate(action, userId) names its TARGET (a visitor the plot's owner
						-- removes); the owner is still the `player` the engine passes.
						local target = name == "userid"
							and string.find(params, "action: unknown, userId: unknown", 1, true)
						t.ok(
							target or (name ~= "userid" and name ~= "actor" and name ~= "who" and name ~= "asplayer"),
							file .. ": a handler parameter names the actor: " .. param
						)
					end
				end
			end
		end
	end)

	t.test("cash is changed only by EconomyService, and no handler file writes it", function()
		for name, r in pairs(TABLE) do
			if r.connect ~= "EconomyService" then
				local src = code(serverFile(r.connect))
				t.eq(
					string.find(src, "profile%.cash%s*[%+%-]?=[^=]"),
					nil,
					name .. " (" .. r.connect .. ") writes profile.cash"
				)
				t.eq(
					string.find(src, "%.cash%s*[%+%-]=[^=]"),
					nil,
					name .. " (" .. r.connect .. ") adds to a cash field"
				)
			end
		end
	end)
end
