--!nocheck
-- The owner hub's rules (Shared/AdminHubLogic): tabs, confirmation, the
-- shared player pick, filters, navigation order. None of it is a lock.
return function(t)
	local Hub = t.shared("AdminHubLogic")
	local AdminLogic = t.shared("AdminLogic")

	t.test("the tabs run PLAYERS, GIFTS, PAID ITEMS, WORLD, ROLES, LOG, and every tool sits in one of them", function()
		local ids = {}
		for _, tab in ipairs(Hub.Tabs) do
			table.insert(ids, tab.id)
			t.ok(#tab.hint > 0, tab.id .. " has a hint")
			t.ok(#Hub.ToolsFor(tab.id) > 0 or tab.always, tab.id .. " has tools (or is the always-there log)")
		end
		t.eq(ids, { "players", "gifts", "paid", "world", "roles", "log" })
		for _, tool in ipairs(Hub.Tools) do
			t.ok(table.find(ids, tool.tab) ~= nil, tool.id .. " is in a real tab")
			t.ok(#tool.hint > 0 and #tool.label > 0, tool.id .. " has a label and a hint")
		end
		t.eq(Hub.TabStep(1, -1), 6)
		t.eq(Hub.TabStep(6, 1), 1)
		t.eq(Hub.TabStep(1, -1, 3), 3, "fewer tabs for a delegate")
		t.eq(Hub.TabStep(2, 1), 3)
	end)

	t.test("every hub tool is an action the server whitelists, and builds a request the server accepts", function()
		local ctx = {
			who = "Bob",
			amount = 500,
			kind = "Axe",
			itemId = "SteelAxe",
			hours = 24,
			speed = 20,
			hour = "noon",
			text = "hello",
			role = "HELPER",
			expiry = "1h",
			paidId = "pass_LuxAxe",
			paidHours = 24,
			userId = 123456,
		}
		local seen = {}
		for _, tool in ipairs(Hub.Tools) do
			t.ok(table.find(AdminLogic.MenuActions, tool.id) ~= nil, tool.id .. " is a menu action")
			seen[tool.id] = true
			local req = Hub.Request(tool.id, ctx)
			t.eq(Hub.Check(req, "Connor"), nil, tool.id .. " passes the hub check")
			local line = AdminLogic.FromRequest(req)
			t.ok(line ~= nil, tool.id .. " passes the server whitelist: " .. tostring(line))
			t.ok(string.sub(line, 1, #tool.id + 1) == "/" .. tool.id, line)
		end
		for _, action in ipairs(AdminLogic.MenuActions) do
			t.ok(seen[action], action .. " has a tool in the hub")
		end
	end)

	t.test("the hub check says why before sending, and agrees with the server about what is refused", function()
		local check = Hub.Check
		t.eq(check({ action = "give", amount = 5 }, "Connor"), "Pick a player first.")
		t.eq(check({ action = "give", target = "Bob", amount = 0 }, "Connor") ~= nil, true)
		t.eq(check({ action = "give", target = "Bob", amount = 99999999 }, "Connor") ~= nil, true)
		t.eq(check({ action = "setcash", target = "Bob", amount = 0 }, "Connor"), nil)
		t.eq(check({ action = "kick", target = "Connor" }, "Connor"), "You can't do that to yourself.")
		t.eq(check({ action = "ban", target = "Bob", hours = 0 }, "Connor") ~= nil, true)
		t.eq(check({ action = "ban", target = "Bob", hours = "perm" }, "Connor"), nil)
		t.eq(check({ action = "gift", target = "Bob" }, "Connor"), "Pick an item first.")
		t.eq(check({ action = "announce", text = "  " }, "Connor") ~= nil, true)
		t.eq(check({ action = "timespeed", speed = 7 }, "Connor") ~= nil, true)
		t.eq(check({ action = "nope" }, "Connor"), "That tool does not exist.")
	end)

	t.test("kick, ban, take cash, set cash and shut down need a second press for the same target", function()
		for _, id in ipairs({
			"kick",
			"ban",
			"take",
			"setcash",
			"shutdown",
			"resettutorial",
			"undelegate",
			"unban",
			"paidgive",
			"paidrevoke",
		}) do
			t.eq(Hub.NeedsConfirm(id), true, id)
		end
		for _, id in ipairs({ "give", "gift", "goto", "bring", "superrun", "stats", "timereset", "paidlist" }) do
			t.eq(Hub.NeedsConfirm(id), false, id)
		end
		local fire, pending = Hub.Press("kick", "kick:Bob", 10, nil)
		t.eq(fire, false)
		t.eq(Hub.StillPending(pending, 12), true)
		t.eq(Hub.StillPending(pending, 15), false, "the window passes")
		local again = Hub.Press("kick", "kick:Eve", 11, pending)
		t.eq(again, false, "another player starts over")
		local second, after = Hub.Press("kick", "kick:Bob", 12, pending)
		t.eq(second, true)
		t.eq(after, nil)
		local late = Hub.Press("kick", "kick:Bob", 20, pending)
		t.eq(late, false, "too late")
		local plain = Hub.Press("give", "give:Bob", 1, nil)
		t.eq(plain, true, "no confirmation needed")
	end)

	t.test("the player pick is one name that survives people leaving", function()
		local names = { "bob", "Connor", "Alice" }
		t.eq(Hub.SortNames(names, "Connor"), { "Connor", "Alice", "bob" })
		t.eq(Hub.Pick(names, nil, "Connor"), "Alice", "the first other player")
		t.eq(Hub.Pick(names, "bob", "Connor"), "bob")
		t.eq(Hub.Pick({ "Connor", "Alice" }, "bob", "Connor"), "Alice", "the picked one left")
		t.eq(Hub.Pick({ "Connor" }, "bob", "Connor"), "Connor", "alone: you")
		t.eq(Hub.Pick({}, nil, "Connor"), nil)
		t.eq(Hub.StepName(names, "Alice", 1, "Connor"), "bob")
		t.eq(Hub.StepName(names, "bob", 1, "Connor"), "Connor", "wraps")
		t.eq(Hub.StepName(names, "Connor", -1, "Connor"), "bob")
	end)

	t.test("amounts parse from plain and short text, and stay under the cap", function()
		t.eq(Hub.ParseAmount("2500"), 2500)
		t.eq(Hub.ParseAmount("$2,500"), 2500)
		t.eq(Hub.ParseAmount("10k"), 10000)
		t.eq(Hub.ParseAmount("1.5m"), 1500000)
		t.eq(Hub.ParseAmount("0"), 0)
		for _, bad in ipairs({ "", "abc", "-5", "1.5", "3m", "99999999", "1e6", 5 }) do
			t.eq(Hub.ParseAmount(bad), nil, tostring(bad))
		end
	end)

	local items = {
		{ id = "SteelAxe", name = "Steel Axe", kind = "Axe" },
		{ id = "CobaltAxe", name = "Cobalt Axe", kind = "Axe" },
		{ id = "Lantern", name = "Lantern", kind = "Gear" },
		{ id = "Cabin", name = "Cabin", kind = "Blueprint" },
	}

	t.test("the item list filters by category and by every typed word, and Recent shows recents", function()
		t.eq(#Hub.Filter(items, "", "All"), 4)
		t.eq(#Hub.Filter(items, "", "Axe"), 2)
		t.eq(#Hub.Filter(items, "axe", "All"), 2)
		t.eq(#Hub.Filter(items, "STEEL axe", "All"), 1)
		t.eq(#Hub.Filter(items, "cabin", "Axe"), 0)
		t.eq(Hub.Filter(items, "lant", "All")[1].id, "Lantern")
		t.eq(#Hub.Filter(items, "", "Recent", {}), 0)
		t.eq(Hub.Filter(items, "", "Recent", { items[3] })[1].id, "Lantern")
		t.eq(Hub.NextCategory("All", 1), "Recent")
		t.eq(Hub.NextCategory("All", -1), "Blueprint")
		t.eq(Hub.NextCategory("Blueprint", 1), "All")
		local shown, more = Hub.Limit(items, 3)
		t.eq(#shown, 3)
		t.eq(more, 1)
		t.eq(select(2, Hub.Limit(items, 10)), 0)
	end)

	t.test("recents keep the newest first, once each, up to the cap", function()
		local list = {}
		for _, item in ipairs(items) do
			list = Hub.PushRecent(list, item)
		end
		t.eq(list[1].id, "Cabin")
		list = Hub.PushRecent(list, items[1])
		t.eq(list[1].id, "SteelAxe")
		t.eq(#list, 4, "no duplicate")
		for i = 1, 10 do
			list = Hub.PushRecent(list, { id = "x" .. i, name = "x", kind = "Gear" })
		end
		t.eq(#list, Hub.RecentCap)
	end)

	t.test("search finds tools across tabs by name, hint or word, and nothing for an empty query", function()
		t.eq(#Hub.FilterTools(""), 0)
		t.eq(#Hub.FilterTools(nil), 0)
		local function ids(query)
			local out = {}
			for _, tool in ipairs(Hub.FilterTools(query)) do
				table.insert(out, tool.id)
			end
			return out
		end
		t.ok(table.find(ids("kick"), "kick"))
		t.ok(table.find(ids("teleport"), "goto"))
		t.ok(table.find(ids("teleport"), "tospawn"), "from another tab")
		t.ok(table.find(ids("restart"), "shutdown"))
		t.eq(ids("zzzz"), {})
	end)

	t.test("the pad's order: left and right stay in a row, up and down go to the nearest column", function()
		local nav = Hub.NavGrid({ { "a", "b", "c" }, {}, { "d" }, { "e", "f" } })
		t.eq(nav.a.left, nil)
		t.eq(nav.a.right, "b")
		t.eq(nav.c.right, nil)
		t.eq(nav.a.up, nil, "no wrap")
		t.eq(nav.a.down, "d", "empty rows are skipped")
		t.eq(nav.b.down, "d")
		t.eq(nav.d.up, "b", "back to the middle of the row above")
		t.eq(nav.d.down, "e")
		t.eq(nav.f.up, "d")
		t.eq(nav.f.down, nil)
		t.eq(nav.e.left, nil)
		t.eq(nav.e.right, "f")
		local wide = Hub.NavGrid({ { "t1", "t2", "t3", "t4" }, { "x", "y" } })
		t.eq(wide.t1.down, "x")
		t.eq(wide.t4.down, "y")
		t.eq(wide.y.up, "t3")
	end)

	t.test("a phone's two rows of tabs are one focus chain: stick down goes row to row, then into the body", function()
		local nav = Hub.NavGrid({
			{ "search", "close" },
			{ "tab1", "tab2", "tab3" },
			{ "tab4", "tab5", "tab6" },
			{ "search_paid" },
			{ "paiditem1" },
			{ "paiditem2" },
			{ "tool_paidlist" },
		})
		t.eq(nav.tab1.up, "search")
		t.eq(nav.tab1.down, "tab4")
		t.eq(nav.tab6.up, "tab3")
		t.eq(nav.tab5.down, "search_paid")
		t.eq(nav.search_paid.up, "tab5", "back to the middle of the tab row above")
		t.eq(nav.search_paid.down, "paiditem1")
		t.eq(nav.paiditem2.down, "tool_paidlist")
		t.eq(nav.tool_paidlist.down, nil, "no wrap: the stick stops at the end")
		t.eq(nav.tab2.left, "tab1")
		t.eq(nav.tab3.right, nil)
	end)

	t.test("scrolling follows the selection and stays inside the canvas", function()
		-- In view: no change.
		t.eq(Hub.ScrollTarget(100, 300, 150, 40, 10), 100)
		-- Below the view: scroll just enough, plus the margin.
		t.eq(Hub.ScrollTarget(0, 300, 400, 40, 10), 150)
		-- Above the view.
		t.eq(Hub.ScrollTarget(200, 300, 120, 40, 10), 110)
		-- Never past the top or the bottom of the canvas.
		t.eq(Hub.ScrollTarget(50, 300, 0, 40, 10), 0)
		t.eq(Hub.ScrollTarget(0, 300, 580, 40, 10, 600), 300)
	end)

	t.test("a delegate sees only the tabs and tools they were granted, and never the DELEGATES tab", function()
		local helper = {}
		for _, action in ipairs(AdminLogic.AllowedActions({ role = "HELPER", powers = AdminLogic.Roles.HELPER })) do
			helper[action] = true
		end
		local tabs = {}
		for _, tab in ipairs(Hub.VisibleTabs(helper)) do
			table.insert(tabs, tab.id)
		end
		t.eq(tabs, { "players", "world", "log" }, "helper: players (go to, bring...), world (announce), the log")
		t.eq(#Hub.VisibleTabs(nil), 6, "the owner sees everything")
		t.eq(Hub.Allows(helper, "kick"), false)
		t.eq(Hub.Allows(helper, "goto"), true)
		t.eq(Hub.Allows(helper, "delegate"), false)
		local found = {}
		for _, tool in ipairs(Hub.FilterTools("teleport", helper)) do
			table.insert(found, tool.id)
		end
		t.eq(found, { "goto", "bring" }, "search only finds what they may use")
		local tester = {}
		for _, action in ipairs(AdminLogic.AllowedActions({ role = "TESTER", powers = {} })) do
			tester[action] = true
		end
		t.eq(tester.shutdown, true)
		t.eq(tester.delegate, nil)
		t.eq(#Hub.VisibleTabs(tester), 4, "TESTER has no ROLES tab and no PAID ITEMS tab")
		for _, tab in ipairs(Hub.VisibleTabs(tester)) do
			t.ok(tab.id ~= "paid" and tab.id ~= "roles", tab.id)
		end
		-- A CUSTOM role with the Gifts power sees the PAID ITEMS tab, but cannot revoke there.
		local gifts = {}
		for _, action in ipairs(AdminLogic.AllowedActions({ role = "CUSTOM", powers = { "paidgive" } })) do
			gifts[action] = true
		end
		local giftTabs = {}
		for _, tab in ipairs(Hub.VisibleTabs(gifts)) do
			table.insert(giftTabs, tab.id)
		end
		t.eq(giftTabs, { "paid", "log" })
		t.eq(Hub.Allows(gifts, "paidgive"), true)
		t.eq(Hub.Allows(gifts, "paidrevoke"), false)
	end)

	t.test(
		"granting TESTER and a TESTER's destructive tools ask twice, and TESTER never lasts until the server closes",
		function()
			t.eq(Hub.NeedsConfirmFor("delegate", { role = "TESTER" }, false), true)
			t.eq(Hub.NeedsConfirmFor("delegate", { role = "HELPER" }, false), false)
			t.eq(Hub.NeedsConfirmFor("give", {}, false), false)
			t.eq(Hub.NeedsConfirmFor("give", {}, true), false, "cash given is not destructive")
			t.eq(Hub.NeedsConfirmFor("ban", {}, true), true)
			t.eq(Hub.NeedsConfirmFor("shutdown", {}, true), true)
			local fire, pending = Hub.Press("delegate", "delegate:Bob:TESTER", 1, nil, true)
			t.eq(fire, false)
			t.eq((Hub.Press("delegate", "delegate:Bob:TESTER", 2, pending, true)), true)
			local ids = {}
			for _, choice in ipairs(Hub.ExpiriesFor("TESTER")) do
				table.insert(ids, choice.id)
			end
			t.eq(ids, { "session", "1h", "24h" })
			t.eq(#Hub.ExpiriesFor("HELPER"), 4)
			t.ok(
				Hub.Check(Hub.Request("delegate", { who = "Bob", role = "TESTER", expiry = "server" }), "Connor") ~= nil
			)
			t.eq(
				Hub.Check(
					Hub.Request("delegate", { who = "Bob", role = "CUSTOM", powers = {}, expiry = "1h" }),
					"Connor"
				),
				"Tick at least one power."
			)
			t.eq(
				Hub.Check(Hub.Request("delegate", { who = "Connor", role = "HELPER", expiry = "1h" }), "Connor"),
				"You are the owner already."
			)
		end
	)

	t.test("B goes back one level at a time and closes only when there is nothing left", function()
		local function back(state)
			state.toolQuery = state.toolQuery or ""
			return Hub.Back(state)
		end
		t.eq(back({ pending = true, toolQuery = "kick", detail = "pass_LuxAxe", listQuery = "x" }), "cancel")
		t.eq(back({ pending = false, toolQuery = "kick", detail = "pass_LuxAxe", listQuery = "x" }), "clearSearch")
		t.eq(back({ pending = false, toolQuery = "", detail = "pass_LuxAxe", listQuery = "x" }), "leaveDetail")
		t.eq(back({ pending = false, toolQuery = "", detail = nil, listQuery = "x" }), "clearFilter")
		t.eq(back({ pending = false, toolQuery = "", detail = nil, listQuery = "" }), "close")
		t.eq(back({ pending = false, toolQuery = "", detail = nil, listQuery = nil }), "close")
	end)

	t.test("the header says who you are, your role and how long it lasts", function()
		t.eq(Hub.WhoText("Connor", "OWNER"), "Connor  |  OWNER")
		t.eq(Hub.WhoText("Bob", "DELEGATE", "MODERATOR", 600), "Bob  |  DELEGATE (MODERATOR)  |  10 min left")
		t.eq(Hub.WhoText("Eve", "TESTER (full power)", "TESTER", nil), "Eve  |  TESTER (full power)")
	end)

	t.test("rows are bigger on a pad and a phone, and a narrow panel wraps its tabs instead of scrolling", function()
		t.ok(Hub.RowHeight("console") >= 60)
		t.ok(Hub.RowHeight("console") > Hub.RowHeight("phone"))
		t.ok(Hub.RowHeight("phone") > Hub.RowHeight("desktop"))
		t.ok(Hub.RowHeight("desktop") >= Hub.Layout.MinTouch)
		t.ok(Hub.HintSize("console") > Hub.HintSize("desktop"))
		t.ok(Hub.HintSize("phone") >= 12)
		t.eq(Hub.TabColumns(560, 6), 6, "a roomy panel: one row")
		t.eq(Hub.TabRows(560, 6), 1)
		t.eq(Hub.TabColumns(340, 6), 3, "a phone: two rows of three")
		t.eq(Hub.TabRows(340, 6), 2)
		t.eq(Hub.TabColumns(340, 3), 3, "a delegate's few tabs stay in one row")
		t.eq(Hub.TabColumns(340, 5), 3)
		t.eq(Hub.TabRows(340, 5), 2)
		t.eq(Hub.TabColumns(340, 0), 1)
		-- Every tab button still has room for a thumb: at least 44 wide at the narrowest panel.
		local narrow = 320 - 2 * Hub.Layout.Pad
		t.ok((narrow - Hub.Layout.Gap * (Hub.TabColumns(320, 6) - 1)) / Hub.TabColumns(320, 6) >= 60)
	end)

	t.test("the player list: recents first, search narrows, you first among the rest", function()
		local names = { "bob", "Connor", "Alice", "Dale" }
		local list = Hub.PlayerList(names, "Connor", {}, "")
		local out = {}
		for _, row in ipairs(list) do
			table.insert(out, row.name)
		end
		t.eq(out, { "Connor", "Alice", "bob", "Dale" })
		list = Hub.PlayerList(names, "Connor", { "Dale", "gone", "Connor", "bob" }, "")
		out = {}
		for _, row in ipairs(list) do
			table.insert(out, row.name .. (row.recent and "*" or ""))
		end
		t.eq(out, { "Dale*", "bob*", "Connor", "Alice" }, "recents (online, not you) come first")
		list = Hub.PlayerList(names, "Connor", { "Dale" }, "ALI")
		t.eq(#list, 1)
		t.eq(list[1].name, "Alice")
		t.eq(list[1].recent, false, "a search is one flat list")
		t.eq(#Hub.PlayerList(names, "Connor", {}, "zzz"), 0)
		-- Recents keep the newest first, once each, and are capped.
		local recents = {}
		for _, n in ipairs({ "a", "b", "c", "a", "d", "e", "f" }) do
			recents = Hub.PushName(recents, n)
		end
		t.eq(recents[1], "f")
		t.eq(#recents, Hub.RecentPlayerCap)
		t.eq(Hub.PushName({ "x", "y" }, "y"), { "y", "x" })
	end)

	t.test("any list of lines narrows by every typed word, and recents move to the front once", function()
		local lines = { "/give <player> <amount>", "/kick <player>", "/timespeed <1|4|20|60>" }
		t.eq(#Hub.FilterLines(lines, ""), 3)
		t.eq(Hub.FilterLines(lines, "PLAYER kick"), { "/kick <player>" })
		t.eq(#Hub.FilterLines(lines, "nothing"), 0)
		t.eq(#Hub.FilterLines(lines, nil), 3)
		local items = {
			{ id = "a", name = "A", kind = "Axe" },
			{ id = "b", name = "B", kind = "Axe" },
			{ id = "c", name = "C", kind = "Gear" },
		}
		local ordered, n = Hub.RecentsFirst(items, { items[3], items[1] })
		t.eq({ ordered[1].id, ordered[2].id, ordered[3].id }, { "c", "a", "b" })
		t.eq(n, 2)
		ordered, n = Hub.RecentsFirst(items, {})
		t.eq({ ordered[1].id, ordered[3].id }, { "a", "c" })
		t.eq(n, 0)
	end)

	t.test("the paid list is the store's, searchable, with recent items first", function()
		local PaidItems = t.shared("PaidItems")
		local all = PaidItems.All()
		local list, n = Hub.PaidList(all, "", {})
		t.eq(#list, #all)
		t.eq(n, 0)
		list, n = Hub.PaidList(all, "", { "product_Cash1k", "pass_LuxAxe", "pass_Gone" })
		t.eq(list[1].id, "product_Cash1k")
		t.eq(list[2].id, "pass_LuxAxe")
		t.eq(n, 2)
		t.eq(#list, #all, "none twice")
		list, n = Hub.PaidList(all, "lux", { "product_Cash1k" })
		t.eq(#list, 1)
		t.eq(n, 0, "a search is one flat list")
		t.eq(Hub.PushPaidRecent({ "a", "b" }, "b"), { "b", "a" })
		local recents = {}
		for i = 1, 9 do
			recents = Hub.PushPaidRecent(recents, "x" .. i)
		end
		t.eq(#recents, Hub.PaidRecentCap)
	end)

	t.test("a paid button that can't go says why, with the same reasons the server gives", function()
		local PaidItems = t.shared("PaidItems")
		local all = PaidItems.All()
		local function item(id)
			return PaidItems.Find(all, id)
		end
		local lux = item("pass_LuxAxe")
		local none = { owned = false, bought = false, granted = false, count = 0, label = "NOT OWNED" }
		local granted = { owned = true, bought = false, granted = true, count = 0, label = "OWNED (granted)" }
		local bought = { owned = true, bought = true, granted = false, count = 0, label = "OWNED (bought)" }
		t.eq(Hub.PaidDisabled(lux, none, "Bob", "Connor", false, false), nil)
		t.eq(Hub.PaidDisabled(lux, none, nil, "Connor", false, false), "Pick a player first.")
		t.eq(Hub.PaidDisabled(lux, nil, "Bob", "Connor", false, false), "Loading what Bob owns...")
		t.eq(
			Hub.PaidDisabled(lux, granted, "Bob", "Connor", false, false),
			"They already have Lux Axe from an owner grant."
		)
		t.eq(Hub.PaidDisabled(lux, bought, "Bob", "Connor", false, false), "They already own Lux Axe.")
		t.eq(Hub.PaidDisabled(lux, none, "Bob", "Connor", true, false), "They don't have Lux Axe.")
		t.eq(Hub.PaidDisabled(lux, granted, "Bob", "Connor", true, false), nil)
		t.ok(string.find(Hub.PaidDisabled(lux, bought, "Bob", "Connor", true, false), "purchase", 1, true))
		-- A Gifts-power delegate may only pick themself.
		t.ok(string.find(Hub.PaidDisabled(lux, none, "Bob", "Connor", false, true), "only gives to you", 1, true))
		t.eq(Hub.PaidDisabled(lux, none, "Connor", "Connor", false, true), nil)
		t.eq(
			Hub.PaidDisabled(item("pass_TimberClassic"), granted, "Bob", "Connor", true, false) ~= nil,
			true,
			"no revoke"
		)
		-- The row from the server becomes the same state.
		t.eq(Hub.PaidState(nil), nil)
		t.eq(Hub.PaidState({ owned = true, granted = true, label = "x", count = 3 }).count, 3)
	end)

	t.test("a tool that can't go says why before it is pressed", function()
		local ctx = { who = "Bob", amount = 500, hours = 24, speed = 20, hour = "noon", text = "hi" }
		t.eq(Hub.ToolDisabled("give", ctx, "Connor"), nil)
		t.eq(Hub.ToolDisabled("give", { who = nil, amount = 5 }, "Connor"), "Pick a player first.")
		t.eq(Hub.ToolDisabled("kick", { who = "Connor" }, "Connor"), "You can't do that to yourself.")
		t.eq(Hub.ToolDisabled("announce", { text = "" }, "Connor") ~= nil, true)
		t.eq(
			Hub.ToolDisabled("unban", { userId = nil }, "Connor"),
			"Type the UserId (a number) of the account to unban."
		)
		t.eq(Hub.ToolDisabled("unban", { userId = 99 }, "Connor"), nil)
		t.eq(Hub.ToolDisabled("paidgive", { who = "Bob", paidId = nil }, "Connor"), "Pick a paid item first.")
		t.eq(Hub.ToolDisabled("paidgive", { who = "Bob", paidId = "pass_LuxAxe" }, "Connor"), nil)
		t.ok(
			string.find(
				Hub.ToolDisabled("paidgive", { who = "Bob", paidId = "pass_LuxAxe" }, "Connor", true),
				"Gifts",
				1,
				true
			)
		)
		t.eq(Hub.ToolDisabled("nope", ctx, "Connor"), "That tool does not exist.")
	end)

	t.test("every delegable power has a name and a help line, and the paid tools have hints and words", function()
		for _, power in ipairs(AdminLogic.DelegablePowers) do
			t.ok(Hub.PowerLabels[power], power .. " has a name")
			t.ok(Hub.PowerHelp[power] and #Hub.PowerHelp[power] > 0, power .. " has a help line")
		end
		for _, id in ipairs({ "paidgive", "paidrevoke", "paidlist", "unban" }) do
			local tool = Hub.Tool(id)
			t.ok(tool and #tool.hint > 0, id)
		end
		t.eq(Hub.Tool("paidgive").tab, "paid")
		t.eq(Hub.Tool("unban").tab, "players")
		t.eq(Hub.Tool("superrun").tab, "players", "your own tools sit with the players now")
		t.ok(table.find(
			(function()
				local out = {}
				for _, tool in ipairs(Hub.FilterTools("robux")) do
					table.insert(out, tool.id)
				end
				return out
			end)(),
			"paidgive"
		))
	end)

	t.test("everything you tap is at least 44 tall, and hint text is never tiny", function()
		local L = Hub.Layout
		t.ok(L.MinTouch >= 44)
		for _, name in ipairs({ "Row", "Chip", "TabHeight" }) do
			t.ok(L[name] >= L.MinTouch, name)
		end
		t.ok(L.HintText >= 12)
		t.ok(L.PanelMaxW <= 640, "a panel that fits a phone in landscape once scaled")
	end)

	t.test("status text is one tidy line and the audit list keeps the newest eight", function()
		t.eq(Hub.StatusText("a\nb"), "a b")
		t.eq(Hub.StatusText(nil), "")
		t.ok(#Hub.StatusText(string.rep("x", 500)) <= 160)
		local list = {}
		for i = 1, 12 do
			list = Hub.PushAudit(list, "line " .. i)
		end
		t.eq(#list, Hub.AuditCap)
		t.eq(list[1], "line 12")
	end)
end
