--!nocheck
-- Launch analytics: the pure event rules (Shared/AnalyticsEvents), the server
-- wrapper (GameAnalytics) with a mocked AnalyticsService, the first-session
-- funnel in MilestoneService, EconomyService's cash events and the store
-- events in MonetizationService.
return function(t)
	local Events = t.shared("AnalyticsEvents")

	local function recorder(failing)
		local log = {}
		local function call(name)
			return function(_, ...)
				if failing then
					error("analytics is down")
				end
				table.insert(log, { name = name, args = { ... } })
			end
		end
		local service = {
			LogOnboardingFunnelStepEvent = call("funnel"),
			LogCustomEvent = call("custom"),
			LogEconomyEvent = call("economy"),
			LogProgressionCompleteEvent = call("progress"),
		}
		return log, service
	end

	t.test("Sku keeps only safe characters and caps the length; no free text rides along", function()
		t.eq(Events.Sku("SteelAxe"), "SteelAxe")
		t.eq(Events.Sku("tutorial: first sale"), "tutorial:firstsale")
		t.eq(Events.Sku("Bob's $$ <script>"), "Bobsscript")
		t.eq(Events.Sku(string.rep("a", 100)), string.rep("a", 40))
		t.eq(Events.Sku(nil), "unknown")
		t.eq(Events.Sku(""), "unknown")
		t.eq(Events.Sku("!!!"), "unknown")
		t.eq(Events.Sku(12345), "unknown", "a number is never a sku")
	end)

	t.test("only our own custom event names are sent", function()
		local name, value, fields = Events.CustomEvent("StoreOpened", nil)
		t.eq(name, "StoreOpened")
		t.eq(value, 1)
		t.eq(fields, nil)
		local _, _, withItem = Events.CustomEvent("PurchasePrompted", "DoubleWood")
		t.eq(withItem, { CustomField01 = "DoubleWood" })
		t.eq(Events.CustomEvent("SomethingElse", nil), nil)
		t.eq(Events.CustomEvent(42, nil), nil)
		t.eq(Events.CustomEvent("StoreOpened", "Jane Doe!"), "StoreOpened")
		local _, _, junk = Events.CustomEvent("StoreOpened", "Jane Doe!")
		t.eq(junk.CustomField01, "JaneDoe", "an item key is cleaned too")
	end)

	t.test("economy arguments: whole positive amounts only, balance never negative", function()
		t.eq(Events.Economy(50, 120, "logs"), { amount = 50, balance = 120, sku = "logs" })
		t.eq(Events.Economy(12.9, -5, nil), { amount = 12, balance = 0, sku = "unknown" })
		t.eq(Events.Economy(0, 10, "x"), nil)
		t.eq(Events.Economy(-3, 10, "x"), nil)
		t.eq(Events.Economy(0 / 0, 10, "x"), nil)
		t.eq(Events.Economy(math.huge, 10, "x"), nil)
		t.eq(Events.Economy("5", 10, "x"), nil)
	end)

	t.test("the first-session funnel is all in MilestoneService's funnel, in order, no repeats", function()
		local Milestone = t.loader({ mocks = { ProfileService = {} } }):server("MilestoneService")
		local last = 0
		local seen = {}
		for _, step in ipairs(Events.FirstSession) do
			t.ok(not seen[step], step .. " listed once")
			seen[step] = true
			local at = table.find(Milestone.Funnel, step)
			t.ok(at ~= nil, step .. " is a funnel step")
			t.ok(at > last, step .. " keeps the funnel's order")
			last = at
		end
		t.eq(Events.FirstSession[1], "Joined")
		t.eq(Events.FirstSession[2], "First chop")
		t.eq(Events.FirstSession[3], "First sale")
	end)

	t.test("GameAnalytics: a funnel step goes out once per player ever (saved flag)", function()
		local log, service = recorder(false)
		local GA = t.loader({ services = { AnalyticsService = service } }):server("GameAnalytics")
		local player = { UserId = 1 }
		local flags = {}
		t.ok(GA.FunnelStep(player, flags, 2, "First chop"))
		t.ok(not GA.FunnelStep(player, flags, 2, "First chop"), "not twice in a session")
		t.eq(#log, 1)
		t.eq(log[1].args[2], 2)
		t.eq(log[1].args[3], "First chop")
		t.eq(flags["First chop"], true, "remembered in the save")
		-- A later session: the same saved flags.
		t.ok(not GA.FunnelStep(player, flags, 2, "First chop"))
		t.eq(#log, 1)
	end)

	t.test("GameAnalytics never throws when the service errors, and a failed step is not repeated", function()
		local _, service = recorder(true)
		local GA = t.loader({ services = { AnalyticsService = service } }):server("GameAnalytics")
		local player = { UserId = 1 }
		local flags = {}
		GA.FunnelStep(player, flags, 1, "Joined")
		t.ok(not GA.FunnelStep(player, flags, 1, "Joined"), "marked before the call")
		t.ok(not GA.Store(player, "StoreOpened", nil), "reports failure instead of throwing")
		t.ok(not GA.Economy(player, "Source", 5, 5, { Name = "Gameplay" }, "logs"))
		t.ok(not GA.Progression(player, "Stages", "S1"))
	end)

	t.test("GameAnalytics sends economy events with the source name and no player data", function()
		local log, service = recorder(false)
		local GA = t.loader({ services = { AnalyticsService = service } }):server("GameAnalytics")
		local player = { UserId = 987654321, Name = "SomeoneReal" }
		t.ok(GA.Economy(player, "Source", 40, 140, { Name = "Gameplay" }, "logs sold!"))
		t.ok(not GA.Economy(player, "Source", 0, 140, { Name = "Gameplay" }, "logs"), "zero is dropped")
		t.eq(#log, 1)
		local args = log[1].args
		t.eq(args[3], "Cash")
		t.eq(args[4], 40)
		t.eq(args[5], 140)
		t.eq(args[6], "Gameplay")
		t.eq(args[7], "logssold")
		for i = 2, #args do
			local text = tostring(args[i])
			t.ok(not string.find(text, "SomeoneReal", 1, true), "no name")
			t.ok(not string.find(text, "987654321", 1, true), "no user id")
		end
	end)

	t.test("MilestoneService logs each first-session step once, through the wrapper", function()
		local log, service = recorder(false)
		local loader = t.loader({ mocks = { ProfileService = {} }, services = { AnalyticsService = service } })
		local Milestone = loader:server("MilestoneService")
		Milestone.Init(function() end)
		local profile = { cash = 0, bestAxeTier = 1, onboarding = {}, stats = { playtimeMin = 0 } }
		local player = { Name = "A", UserId = 1 }
		Milestone.Start(player, profile)
		Milestone.Mark(player, "First chop")
		Milestone.Mark(player, "First chop")
		Milestone.Mark(player, "First machine placed")
		Milestone.Mark(player, "First machine placed")
		local steps = {}
		for _, entry in ipairs(log) do
			if entry.name == "funnel" then
				table.insert(steps, entry.args[3])
			end
		end
		t.eq(steps, { "Joined", "First chop", "First machine placed" })
		-- Rejoin with the same saved flags: nothing new goes out.
		local again = loader:server("MilestoneService")
		again.Init(function() end)
		local before = #log
		again.Start(player, profile)
		again.Mark(player, "First chop")
		local funnelAfter = 0
		for i = before + 1, #log do
			if log[i].name == "funnel" then
				funnelAfter += 1
			end
		end
		t.eq(funnelAfter, 0, "once per player ever, not once per session")
	end)

	t.test("EconomyService: cash earned and spent each log one event with a source name", function()
		local log, service = recorder(false)
		local profile = { cash = 0, totalEarned = 0, pendingCash = 0 }
		local loader = t.loader({
			services = { AnalyticsService = service },
			mocks = {
				ProfileService = {
					GetProfile = function()
						return profile
					end,
				},
			},
		})
		local Economy = loader:server("EconomyService")
		local player = { Name = "Tester", SetAttribute = function() end }
		Economy.AddCash(player, 100, "sold logs", "logs")
		t.ok(Economy.SpendCash(player, 30, "bought an axe", "SteelAxe"))
		local economy = {}
		for _, entry in ipairs(log) do
			if entry.name == "economy" then
				table.insert(economy, entry)
			end
		end
		t.eq(#economy, 2)
		t.eq(economy[1].args[4], 100)
		t.eq(economy[1].args[7], "logs")
		t.eq(economy[2].args[4], 30)
		t.eq(economy[2].args[5], 70)
		t.eq(economy[2].args[7], "SteelAxe")
	end)

	t.test("EconomyService still pays when analytics is down", function()
		local _, service = recorder(true)
		local profile = { cash = 0, totalEarned = 0, pendingCash = 0 }
		local loader = t.loader({
			services = { AnalyticsService = service },
			mocks = {
				ProfileService = {
					GetProfile = function()
						return profile
					end,
				},
			},
		})
		local Economy = loader:server("EconomyService")
		local player = { Name = "Tester", SetAttribute = function() end }
		local credited = Economy.AddCash(player, 100, "sold logs", "logs")
		t.eq(credited, 100)
		t.eq(profile.cash, 100)
	end)

	t.test("store events: the source wires them to opens, prompts and granted purchases", function()
		local fs = require("@lune/fs")
		local money = fs.readFile("src/ServerScriptService/MonetizationService.luau")
		local _, prompts = string.gsub(money, 'GameAnalytics.Store%(player, "PurchasePrompted"', "")
		local _, done = string.gsub(money, 'GameAnalytics.Store%(player, "PurchaseCompleted"', "")
		t.eq(prompts, 2, "a pass prompt and a product prompt")
		t.eq(done, 2, "a pass bought and a product receipt granted")
		local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(server, 'RateLimiter.Allow(player, "StoreOpened")', 1, true), "the open is rate limited")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/StoreUI.luau")
		local _, opens = string.gsub(ui, 'Net.Remote%("StoreOpened"%):FireServer', "")
		t.eq(opens, 1, "one place fires it: the store opening")
	end)

	t.test("store events: each name is an event and goes out with the item key only", function()
		local log, service = recorder(false)
		local GA = t.loader({ services = { AnalyticsService = service } }):server("GameAnalytics")
		local player = { UserId = 1, Name = "N" }
		t.ok(GA.Store(player, "StoreOpened"))
		t.ok(GA.Store(player, "PurchasePrompted", "DoubleWood"))
		t.ok(GA.Store(player, "PurchaseCompleted", "DoubleWood"))
		t.ok(not GA.Store(player, "Hacked", "x"), "an unknown name is refused")
		t.eq(#log, 3)
		t.eq(log[2].args[2], "PurchasePrompted")
		t.eq(log[2].args[4], { CustomField01 = "DoubleWood" })
	end)
end
