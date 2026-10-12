--!nocheck
-- StoreEventService: the schedule turns a store's event zone, banner and event
-- slots on and off, with nothing to publish and no code change. The clock is
-- injected and task.delay is captured, so each test walks time by hand. It
-- proves: the default (empty) schedule leaves every store identical; an
-- active config opens exactly that store's zone, banner and slots and nothing
-- else; the purchase of an event slot is refused when inactive, when the slot
-- has no approved item and when it has no price; a toggle off mid-event
-- closes everything and keeps what was already bought; a restart recomputes.
return function(t)
	local roblox = t.roblox
	local Instance, CFrame = roblox.Instance, roblox.CFrame
	local DAY = 86400
	local KINDS = { "ToolShed", "HearthAndHome", "Sparkworks", "Dealership" }

	local function date(text)
		return t.shared("StoreEvents").ParseDate(text)
	end
	local START, END = date("2026-12-01"), date("2026-12-15")

	local function setup(options)
		options = options or {}
		local profile = {
			cash = options.cash or 1000,
			totalEarned = 0,
			bestAxeTier = 1,
			ownedTrucks = { "Rustbucket" },
			gear = {},
			ownedTrailers = {},
			equippedTrailer = "",
			equippedTruck = "Rustbucket",
			plot = { claimed = true, tier = 1, placed = {}, squares = {} },
			storage = {},
			materials = {},
		}
		local player = { Name = "Tester", UserId = 1, SetAttribute = function() end }
		local tagged, signals, delays = {}, {}, {}
		local function signalFor(tag)
			local s = signals[tag]
			if s == nil then
				s = { fns = {} }
				function s:Connect(fn)
					table.insert(self.fns, fn)
				end
				signals[tag] = s
			end
			return s
		end
		local studio = options.studio == true
		local workspaceAttrs = options.workspaceAttrs or {}
		local loader = t.loader({
			isolated = true, -- this spec edits StoreData's event rows
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {},
				BlueprintService = {},
				MilestoneService = { Mark = function() end },
				QuestService = { Event = function() end, RefreshNextGoal = function() end },
				VehicleService = {},
			},
			services = {
				CollectionService = {
					AddTag = function(_, inst, tag)
						inst:AddTag(tag)
						tagged[tag] = tagged[tag] or {}
						table.insert(tagged[tag], inst)
					end,
					HasTag = function(_, inst, tag)
						return inst:HasTag(tag)
					end,
					GetTagged = function(_, tag)
						return tagged[tag] or {}
					end,
					GetInstanceAddedSignal = function(_, tag)
						return signalFor(tag)
					end,
				},
				HttpService = {
					GenerateGUID = function()
						return "guid"
					end,
					JSONDecode = function(_, text)
						return require("@lune/serde").decode("json", text)
					end,
				},
				RunService = {
					IsStudio = function()
						return studio
					end,
					IsServer = function()
						return true
					end,
				},
				Workspace = {
					GetAttribute = function(_, name)
						return workspaceAttrs[name]
					end,
				},
			},
			globals = {
				task = {
					delay = function(seconds, fn)
						table.insert(delays, { seconds = seconds, fn = fn })
					end,
				},
			},
		})
		local env = {
			loader = loader,
			profile = profile,
			player = player,
			tagged = tagged,
			signals = signals,
			delays = delays,
			clock = { now = options.now or (START - 5 * DAY) },
			StoreData = loader:shared("StoreData"),
			StoreEvents = loader:shared("StoreEvents"),
			StoreStock = loader:shared("StoreStock"),
			Kit = loader:load("ReplicatedStorage/Shared/Art/ShopEventKit"),
			Shop = loader:server("ShopService"),
			Service = loader:server("StoreEventService"),
		}
		env.Shop.Hour = function()
			return 12
		end
		-- Every store gets its zone and banner, as the store builders will place them.
		env.model = Instance.new("Model")
		env.zones, env.boards = {}, {}
		for i, kind in ipairs(KINDS) do
			local x = i * 40
			env.zones[kind] = env.Kit.BuildZone(env.model, kind, CFrame.new(x, 0, 0))
			local banner = env.Kit.BuildBanner(env.model, kind, CFrame.new(x, 0, -20))
			for _, d in ipairs(banner:GetChildren()) do
				if d.Name == "EventBanner" then
					env.boards[kind] = d
				end
			end
		end
		-- One approved, priced slot in Hearth & Home; one approved with no price; one unapproved.
		local rows = env.StoreData.EventSlots.HearthAndHome
		if options.approve ~= false then
			rows[1].approved, rows[1].itemKind, rows[1].itemId, rows[1].price = true, "Cosmetic", "EventHat", 250
			rows[2].approved, rows[2].itemKind, rows[2].itemId, rows[2].price = true, "Cosmetic", "EventScarf", nil
		end
		function env.init(configs, attributeText)
			env.Service.Init(
				function()
					return env.clock.now
				end,
				if attributeText ~= nil
					then function()
						return attributeText
					end
					else nil,
				function()
					return configs
				end
			)
		end
		-- Runs the minute timer once (the latest one scheduled).
		function env.tick()
			local last = table.remove(delays)
			t.ok(last, "a timer is waiting")
			t.eq(last.seconds, 60)
			last.fn()
		end
		function env.event(over)
			local c = {
				store = "HearthAndHome",
				startsAt = "2026-12-01",
				endsAt = "2026-12-15",
				enabled = true,
				items = { "event-hearth-1", "event-hearth-2", "event-hearth-3" },
			}
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return c
		end
		env.GONE = {} -- pay(uid, { field = GONE }) leaves that field off the box
		function env.pay(uid, over)
			local box = {
				uid = uid,
				kind = "Cosmetic",
				itemId = "EventHat",
				eventSlot = "event-hearth-1",
				deferGrant = false,
			}
			for k, v in pairs(over or {}) do
				box[k] = if v == env.GONE then nil else v
			end
			return env.Shop.ChargeAndGrant(env.player, box)
		end
		function env.look()
			-- every visible state of every zone and banner, as text
			local out = {}
			for _, kind in ipairs(KINDS) do
				for _, root in ipairs({ env.zones[kind], env.boards[kind].Parent }) do
					table.insert(out, root.Name .. ":" .. tostring(root:GetAttribute("Active")))
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA("BasePart") then
							table.insert(out, d.Name .. ":" .. d.Transparency)
						elseif d:IsA("PointLight") or d:IsA("SurfaceGui") then
							table.insert(out, d.ClassName .. ":" .. tostring(d.Enabled))
						elseif d:IsA("TextLabel") then
							table.insert(out, "text:" .. d.Text)
						end
					end
				end
			end
			return table.concat(out, "|")
		end
		function env.open(kind)
			return env.zones[kind]:GetAttribute("Active") == true
		end
		return env
	end

	local function ropesDown(zone)
		for _, d in ipairs(zone:GetDescendants()) do
			if d.Name == "EventRope" and d.Transparency ~= 1 then
				return false
			end
		end
		return true
	end

	t.test("the default empty schedule leaves every store, row, price and visibility exactly as it was", function()
		local s = setup({ approve = false })
		local before = s.look()
		local stockBefore = {}
		for _, slot in ipairs(s.StoreStock.All()) do
			stockBefore[slot.slotId] = tostring(s.StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2))
				.. ":"
				.. slot.displayName
		end
		local rowsBefore = s.StoreData.EventSlotList()
		local snapshot = {}
		for i, row in ipairs(rowsBefore) do
			snapshot[i] = row.id .. tostring(row.price) .. tostring(row.approved) .. tostring(row.visible)
		end
		s.Service.Init() -- the real defaults: StoreEventData (empty) and no Studio attribute
		t.eq(s.look(), before, "zones and banners untouched")
		t.eq(next(s.Shop.LiveEventSlots()), nil, "no event slot is live")
		for _, kind in ipairs(KINDS) do
			t.eq(s.Service.StateFor(kind).active, false, kind)
			t.eq(s.zones[kind]:GetAttribute("Active"), false)
			t.eq(s.boards[kind]:GetAttribute("Text"), "")
		end
		for _, slot in ipairs(s.StoreStock.All()) do
			t.eq(
				tostring(s.StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)) .. ":" .. slot.displayName,
				stockBefore[slot.slotId],
				slot.slotId
			)
		end
		for i, row in ipairs(s.StoreData.EventSlotList()) do
			t.eq(row.id .. tostring(row.price) .. tostring(row.approved) .. tostring(row.visible), snapshot[i])
			t.eq(row.price, nil)
			t.eq(row.visible, false)
		end
		t.eq(#s.delays, 1, "and it checks again in a minute")
		s.tick()
		t.eq(s.look(), before, "still nothing a minute later")
	end)

	t.test("an active config opens exactly that store's zone, banner and slot, and nothing else", function()
		local s = setup()
		local others = {}
		s.init({ s.event({ bannerText = "winter fair" }) })
		t.eq(s.open("HearthAndHome"), false, "not started yet: closed")
		s.clock.now = START
		s.tick()
		t.eq(s.open("HearthAndHome"), true)
		t.ok(ropesDown(s.zones.HearthAndHome), "the rope is down")
		local lit = 0
		for _, d in ipairs(s.zones.HearthAndHome:GetDescendants()) do
			if d:IsA("PointLight") and d.Enabled then
				lit += 1
			end
		end
		t.eq(lit, 1, "the lamp is on")
		local board = s.boards.HearthAndHome
		t.eq(board:GetAttribute("Active"), true)
		t.eq(board:GetAttribute("Text"), "WINTER FAIR")
		t.eq(board.Parent:FindFirstChild("EventBannerPost").Transparency, 0, "the banner shows")
		for _, kind in ipairs({ "ToolShed", "Sparkworks", "Dealership" }) do
			t.eq(s.open(kind), false, kind .. " stays closed")
			t.eq(s.boards[kind]:GetAttribute("Active"), false)
			t.eq(s.boards[kind]:GetAttribute("Text"), "")
			t.eq(s.boards[kind].Parent:FindFirstChild("EventBannerPost").Transparency, 1)
			t.ok(not ropesDown(s.zones[kind]), kind .. " is still roped off")
			others[kind] = true
		end
		local live = s.Shop.LiveEventSlots()
		t.ok(live["event-hearth-1"], "the approved, priced slot is live")
		t.eq(live["event-hearth-1"].price, 250)
		t.eq(live["event-hearth-2"], nil, "approved with no price: not live")
		t.eq(live["event-hearth-3"], nil, "not approved: not live")
		local n = 0
		for _ in pairs(live) do
			n += 1
		end
		t.eq(n, 1, "only that one")
		t.eq(s.Service.StateFor("HearthAndHome").slotIds, { "event-hearth-1" })
	end)

	t.test("walking the clock: closed before, open during, closed after, and the slot goes on and off sale", function()
		local s = setup()
		s.init({ s.event() })
		local function state()
			return s.open("HearthAndHome"), s.Shop.LiveEventSlots()["event-hearth-1"] ~= nil
		end
		local open, live = state()
		t.eq({ open, live }, { false, false }, "before the start")
		s.clock.now = START + DAY
		s.tick()
		open, live = state()
		t.eq({ open, live }, { true, true }, "during")
		s.clock.now = END - 1
		s.tick()
		open, live = state()
		t.eq({ open, live }, { true, true }, "the last second")
		s.clock.now = END
		s.tick()
		open, live = state()
		t.eq({ open, live }, { false, false }, "after the end")
		t.ok(not ropesDown(s.zones.HearthAndHome), "roped off again")
		t.eq(s.boards.HearthAndHome:GetAttribute("Text"), "")
		s.clock.now = START + DAY
		s.tick()
		open, live = state()
		t.eq({ open, live }, { true, true }, "a clock set back re-opens it: nothing is remembered")
		s.clock.now = START - 30 * DAY
		s.tick()
		open, live = state()
		t.eq({ open, live }, { false, false }, "and set far back closes it")
	end)

	t.test("a disabled flag, bad dates and a too-long run keep everything closed", function()
		for _, over in ipairs({
			{ enabled = false },
			{ startsAt = "2026-99-01" },
			{ endsAt = "2026-12-01" },
			{ endsAt = "2027-06-01" },
			{ store = "Casino" },
		}) do
			local s = setup({ now = START + DAY })
			local before = s.look()
			s.init({ s.event(over) })
			t.eq(s.look(), before, "unchanged")
			t.eq(next(s.Shop.LiveEventSlots()), nil)
		end
	end)

	t.test("overlapping configs for one store keep it open until the last ends", function()
		local s = setup({ now = date("2026-12-07") })
		s.init({
			s.event({ startsAt = "2026-12-01", endsAt = "2026-12-10" }),
			s.event({ startsAt = "2026-12-05", endsAt = "2026-12-20", bannerText = "second" }),
		})
		t.eq(s.open("HearthAndHome"), true)
		s.clock.now = date("2026-12-12")
		s.tick()
		t.eq(s.open("HearthAndHome"), true, "the second still runs")
		t.eq(s.boards.HearthAndHome:GetAttribute("Text"), "SECOND")
		s.clock.now = date("2026-12-20")
		s.tick()
		t.eq(s.open("HearthAndHome"), false)
	end)

	t.test("buying an event slot is refused when no event is active", function()
		local s = setup({ now = START - DAY })
		s.init({ s.event() })
		local ok, line = s.pay("box-1")
		t.eq(ok, false)
		t.eq(line, "locked")
		t.eq(s.profile.cash, 1000, "no cash moved")
		t.eq(s.profile.materials.EventHat, nil, "nothing granted")
		local none = setup()
		none.init({})
		t.eq(none.pay("box-2"), false, "with an empty schedule too")
		t.eq(none.profile.cash, 1000)
	end)

	t.test("buying is refused while active when the slot has no approved item, or no price", function()
		local s = setup({ now = START + DAY })
		s.init({ s.event() })
		-- approved item, explicit price: this one opens
		-- (the other two rows are not live, so paying for them is refused)
		local scarf = s.pay("box-scarf", { itemId = "EventScarf", eventSlot = "event-hearth-2" })
		t.eq(scarf, false, "approved but no price")
		local coat = s.pay("box-coat", { itemId = "EventCoat", eventSlot = "event-hearth-3" })
		t.eq(coat, false, "no approved item")
		t.eq(s.profile.cash, 1000)
		-- A price of 0 or an unapproved row with a price is no better.
		local rows = s.StoreData.EventSlots.HearthAndHome
		rows[3].approved, rows[3].itemKind, rows[3].itemId, rows[3].price = false, "Cosmetic", "EventCoat", 90
		rows[2].price = 0
		s.clock.now = START + 2 * DAY
		s.tick()
		t.eq(s.pay("box-scarf2", { itemId = "EventScarf", eventSlot = "event-hearth-2" }), false)
		t.eq(s.pay("box-coat2", { itemId = "EventCoat", eventSlot = "event-hearth-3" }), false)
		t.eq(s.profile.cash, 1000)
		t.eq(next(s.Shop.LiveEventSlots(), "event-hearth-1"), nil, "still only the one live slot")
	end)

	t.test("an approved, priced slot sells only while live, once per box, at its own price", function()
		local s = setup({ now = START + DAY })
		s.init({ s.event() })
		local ok, line = s.pay("box-hat")
		t.eq(ok, true)
		t.eq(line, "thanks")
		t.eq(s.profile.cash, 750, "charged its explicit price, $250")
		t.eq(s.profile.materials.EventHat, 1, "handed over")
		t.eq(s.pay("box-hat"), false, "a second pay of the same box is refused")
		t.eq(s.profile.cash, 750)
		-- It cannot be bought as an ordinary item, or with a made-up kind or item, or as a gift.
		t.eq(s.pay("b2", { eventSlot = s.GONE, itemId = "event-hearth-1" }), false, "slot id as an item")
		t.eq(
			s.pay("b3", { eventSlot = s.GONE }),
			false,
			"the item without naming its slot: the ordinary path has no price for it"
		)
		t.eq(s.pay("b4", { itemId = "SomethingElse" }), false, "the box must carry the slot's item")
		t.eq(s.pay("b5", { kind = "Gear" }), false, "and its kind")
		t.eq(s.pay("b6", { free = true }), false, "an owner gift cannot open an event slot")
		t.eq(s.pay("b7", { eventSlot = "event-toolshed-1" }), false, "a slot of a store that is not open")
		t.eq(s.profile.cash, 750)
	end)

	t.test("a toggle off mid-event closes the zone and takes items off sale; what was bought stays owned", function()
		local s = setup({ now = START + 3 * DAY })
		local configs = { s.event() }
		s.init(configs)
		t.eq(s.pay("keep-1"), true)
		t.eq(s.profile.materials.EventHat, 1)
		configs[1] = s.event({ enabled = false }) -- Connor flips it off (Studio attribute or a new deploy)
		s.tick()
		t.eq(s.open("HearthAndHome"), false, "the zone is closed")
		t.ok(not ropesDown(s.zones.HearthAndHome))
		t.eq(s.boards.HearthAndHome:GetAttribute("Active"), false)
		t.eq(s.boards.HearthAndHome:GetAttribute("Text"), "")
		t.eq(next(s.Shop.LiveEventSlots()), nil, "off sale")
		t.eq(s.pay("late-1"), false, "a late buyer is refused")
		t.eq(s.profile.materials.EventHat, 1, "the one already bought is still owned")
		t.eq(s.profile.cash, 750, "and nothing was refunded or taken")
		configs[1] = s.event()
		s.tick()
		t.eq(s.open("HearthAndHome"), true, "flipping it back on re-opens it")
	end)

	t.test("a server restart (a fresh service) recomputes the same answer from the config and the clock", function()
		local a = setup({ now = START + DAY })
		a.init({ a.event() })
		local b = setup({ now = START + DAY })
		b.init({ b.event() })
		t.eq(b.look(), a.look(), "identical")
		t.ok(b.Shop.LiveEventSlots()["event-hearth-1"])
		local after = setup({ now = END + DAY })
		after.init({ after.event() })
		t.eq(after.open("HearthAndHome"), false, "a restart after the end finds it closed")
		t.eq(next(after.Shop.LiveEventSlots()), nil)
	end)

	t.test("a restart re-run twice does not stack timers or double-apply (an old loop stops)", function()
		local s = setup({ now = START + DAY })
		s.init({ s.event() })
		local first = s.delays[1]
		s.init({ s.event() })
		t.eq(#s.delays, 2)
		table.remove(s.delays, 1) -- the first timer is stale now
		first.fn()
		t.eq(#s.delays, 1, "the stale loop did not schedule another")
	end)

	t.test("a zone or banner built after the service started is opened too", function()
		local s = setup({ now = START + DAY })
		s.init({ s.event() })
		t.eq(s.open("HearthAndHome"), true)
		local late = s.Kit.BuildZone(s.model, "HearthAndHome", CFrame.new(500, 0, 0))
		t.eq(late:GetAttribute("Active"), false, "built closed")
		for _, fn in ipairs(s.signals.EventExpansion.fns) do
			fn(late) -- the engine's GetInstanceAddedSignal
		end
		t.eq(late:GetAttribute("Active"), true, "opened the moment it was added")
		local lateBanner = s.Kit.BuildBanner(s.model, "HearthAndHome", CFrame.new(500, 0, -20))
		local board = lateBanner:FindFirstChild("EventBanner")
		for _, fn in ipairs(s.signals.EventBanner.fns) do
			fn(board)
		end
		t.eq(board:GetAttribute("Active"), true)
		t.eq(board:GetAttribute("Text"), "COMING SOON")
	end)

	t.test("the Studio attribute schedules an event, a bad one is ignored, and a live server ignores it", function()
		local json =
			'{"store":"HearthAndHome","startsAt":"2026-12-01","endsAt":"2026-12-15","enabled":true,"items":["event-hearth-1"],"bannerText":"Test Day"}'
		local studio = setup({ now = START + DAY, studio = true, workspaceAttrs = { StoreEventConfig = json } })
		studio.Service.Init(
			function()
				return studio.clock.now
			end,
			nil,
			function()
				return {}
			end
		)
		t.eq(studio.open("HearthAndHome"), true, "Studio reads the attribute")
		t.eq(studio.boards.HearthAndHome:GetAttribute("Text"), "TEST DAY")
		t.ok(studio.Shop.LiveEventSlots()["event-hearth-1"])
		-- a list works too
		local list = setup({ now = START + DAY })
		list.init({}, "[" .. json .. "]")
		t.eq(list.open("HearthAndHome"), true)
		-- bad JSON: closed, no crash
		local bad = setup({ now = START + DAY })
		local before = bad.look()
		bad.init({}, "{not json")
		t.eq(bad.look(), before)
		-- not a Studio session: the attribute is ignored
		local live = setup({ now = START + DAY, studio = false, workspaceAttrs = { StoreEventConfig = json } })
		live.Service.Init(
			function()
				return live.clock.now
			end,
			nil,
			function()
				return {}
			end
		)
		t.eq(live.open("HearthAndHome"), false, "a live server never reads it")
		t.eq(next(live.Shop.LiveEventSlots()), nil)
	end)

	t.test("a schedule that throws counts as no event: everything stays closed", function()
		local s = setup({ now = START + DAY })
		local before = s.look()
		s.Service.Init(
			function()
				return s.clock.now
			end,
			nil,
			function()
				error("boom")
			end
		)
		t.eq(s.look(), before)
		t.eq(next(s.Shop.LiveEventSlots()), nil)
	end)

	t.test("the committed schedule is empty and the service wires into GameServer once", function()
		local fs = require("@lune/fs")
		t.eq(t.shared("StoreEventData").Events, {})
		local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local _, n = string.gsub(server, 'safely%("StoreEventService%.Init", StoreEventService%.Init%)', "")
		t.eq(n, 1)
	end)
end
