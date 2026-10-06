--!nocheck
-- The owner's tools: who counts as the owner, and what the commands parse to.
return function(t)
	local AdminLogic = t.shared("AdminLogic")

	t.test("the owner is the listed ids or the person who owns the experience, and Studio", function()
		local owner = AdminLogic.IsOwner
		t.eq(owner(100, "User", 100, false, {}), true, "the creator, a person")
		t.eq(owner(100, "Group", 100, false, {}), false, "a group's id is not a person's")
		t.eq(owner(200, "User", 100, false, {}), false, "someone else")
		t.eq(owner(200, "User", 100, false, { 200 }), true, "a listed id")
		t.eq(owner(300, "User", 100, false, { 200 }), false, "not on the list")
		t.eq(owner(5, "User", 100, true, {}), true, "Studio")
		t.eq(owner(5, "User", 100, false, nil), false, "nobody by default")
	end)

	t.test("junk is never the owner, even when it matches the creator", function()
		local owner = AdminLogic.IsOwner
		for _, junk in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, "100", true }) do
			t.eq(owner(junk, "User", junk, false, { junk }), false, tostring(junk))
		end
		t.eq(owner(nil, "User", nil, false, {}), false)
		t.eq(owner(0, "User", 0, false, {}), false, "an unpublished place has creator 0")
	end)

	t.test("no id is listed in the repository", function()
		t.eq(#AdminLogic.OwnerUserIds, 0, "ids are pasted by the owner, not committed")
	end)

	t.test("commands parse to a name and words, and only commands do", function()
		local c = AdminLogic.Parse("/give Bob 500")
		t.eq(c.name, "give")
		t.eq(c.args, { "Bob", "500" })
		t.eq(AdminLogic.Parse("  /KICK  Bob  being rude ").rest, "Bob  being rude")
		t.eq(AdminLogic.Parse("give Bob 500"), nil)
		t.eq(AdminLogic.Parse("/"), nil)
		t.eq(AdminLogic.Parse(12), nil)
		t.eq(AdminLogic.Parse(string.rep("a", 300)), nil)
	end)

	t.test("amounts are whole numbers from 1 to the cap", function()
		t.eq(AdminLogic.Amount("500"), 500)
		t.eq(AdminLogic.Amount("2000000"), 2000000)
		for _, bad in ipairs({ "0", "-5", "1.5", "abc", "2000001", "1e12", "nan", "inf", 5 }) do
			t.eq(AdminLogic.Amount(bad), nil, tostring(bad))
		end
	end)

	t.test("a name matches exactly or by one prefix", function()
		local names = { "Connor", "Cora", "Dale" }
		t.eq({ AdminLogic.MatchName("connor", names) }, { "Connor" })
		t.eq({ AdminLogic.MatchName("Da", names) }, { "Dale" })
		t.eq({ AdminLogic.MatchName("Co", names) }, { nil, "many" })
		t.eq({ AdminLogic.MatchName("Zed", names) }, { nil, "none" })
		t.eq({ AdminLogic.MatchName("", names) }, { nil, "none" })
		t.eq({ AdminLogic.MatchName(nil, names) }, { nil, "none" })
	end)

	t.test("only the free-gift kinds can be gifted, and bans have sane lengths", function()
		for _, kind in ipairs({ "Axe", "Gear", "Sawmill", "Machine", "Blueprint" }) do
			t.eq(AdminLogic.IsGiftKind(kind), true, kind)
		end
		for _, kind in ipairs({ "Truck", "Cosmetic", "axe", "", 5, nil }) do
			t.eq(AdminLogic.IsGiftKind(kind), false, tostring(kind))
		end
		t.eq(AdminLogic.BanSeconds("perm"), -1)
		t.eq(AdminLogic.BanSeconds("24"), 86400)
		for _, bad in ipairs({ "0", "-1", "9000", "1.5", "abc", 3 }) do
			t.eq(AdminLogic.BanSeconds(bad), nil, tostring(bad))
		end
	end)

	t.test("a menu request becomes a command line, and anything off the list becomes nothing", function()
		local from = AdminLogic.FromRequest
		t.eq(from({ action = "give", target = "Bob", amount = 500 }), "/give Bob 500")
		t.eq(from({ action = "take", target = "Bob_1", amount = 20 }), "/take Bob_1 20")
		t.eq(from({ action = "setcash", target = "Bob", amount = 0 }), "/setcash Bob 0")
		t.eq(from({ action = "gift", target = "Bob", kind = "Axe", itemId = "SteelAxe" }), "/gift Bob Axe SteelAxe")
		t.eq(from({ action = "kick", target = "Bob" }), "/kick Bob")
		t.eq(from({ action = "goto", target = "Bob" }), "/goto Bob")
		t.eq(from({ action = "superrun" }), "/superrun")
		-- Not on the list, or malformed.
		for _, bad in ipairs({
			{ action = "ban", target = "Bob" },
			{ action = "announce", target = "Bob" },
			{ action = "give", target = "Bob", amount = -5 },
			{ action = "give", target = "Bob", amount = 0 },
			{ action = "give", target = "Bob", amount = 1.5 },
			{ action = "give", target = "Bob", amount = 99999999 },
			{ action = "give", target = "Bob", amount = 0 / 0 },
			{ action = "give", target = "Bob", amount = "500" },
			{ action = "give", amount = 500 },
			{ action = "give", target = "Bob; /ban Bob", amount = 5 },
			{ action = "give", target = string.rep("a", 40), amount = 5 },
			{ action = "gift", target = "Bob", kind = "Truck", itemId = "Pickup" },
			{ action = "gift", target = "Bob", kind = "Axe", itemId = "x y" },
			{ action = "kick" },
			{},
			{ action = 5 },
		}) do
			t.eq(from(bad), nil)
		end
		for _, junk in ipairs({ "give", 5, true }) do
			t.eq(from(junk), nil)
		end
		t.eq(from(nil), nil)
	end)

	t.test("time speeds are the whitelist, and hours parse from names, 12-hour and 24-hour text", function()
		for _, ok in ipairs({ "1", "4", "20", "60", "20x" }) do
			t.ok(AdminLogic.Speed(ok) ~= nil, ok)
		end
		for _, bad in ipairs({ "0", "2", "61", "1000", "-4", "4.5", "fast", "", 20 }) do
			t.eq(AdminLogic.Speed(bad), nil, tostring(bad))
		end
		t.eq(AdminLogic.Speed(nil), nil)
		local hour = AdminLogic.TimeOfDay
		t.eq(hour("midnight"), 0)
		t.eq(hour("noon"), 12)
		t.eq(hour("6am"), 6)
		t.eq(hour("6pm"), 18)
		t.eq(hour("12am"), 0)
		t.eq(hour("12pm"), 12)
		t.eq(hour("7:30 PM"), 19.5)
		t.eq(hour("18:30"), 18.5)
		t.eq(hour("18"), 18)
		t.eq(hour("0"), 0)
		for _, bad in ipairs({ "24", "25:00", "13pm", "0am", "6:75", "6:5", "soon", "", "6xm", string.rep("1", 20), 6 }) do
			t.eq(hour(bad), nil, tostring(bad))
		end
		t.eq(hour(nil), nil)
	end)

	t.test("the hub's added powers are whitelisted and validated, nothing else gets through", function()
		local from = AdminLogic.FromRequest
		t.eq(from({ action = "god" }), "/god")
		t.eq(from({ action = "tospawn" }), "/tospawn")
		t.eq(from({ action = "shutdown" }), "/shutdown")
		t.eq(from({ action = "heal", target = "Bob" }), "/heal Bob")
		t.eq(from({ action = "freeze", target = "Bob" }), "/freeze Bob")
		t.eq(from({ action = "stats", target = "Bob" }), "/stats Bob")
		t.eq(from({ action = "resettutorial", target = "Bob" }), "/resettutorial Bob")
		t.eq(from({ action = "unlockbp", target = "Bob" }), "/unlockbp Bob")
		t.eq(from({ action = "ban", target = "Bob", hours = 24 }), "/ban Bob 24")
		t.eq(from({ action = "ban", target = "Bob", hours = "perm" }), "/ban Bob perm")
		t.eq(from({ action = "announce", text = "  server restart soon " }), "/announce server restart soon")
		for _, bad in ipairs({
			{ action = "heal" },
			{ action = "freeze", target = "Bob; /shutdown" },
			{ action = "stats", target = "a b" },
			{ action = "unlockbp", target = string.rep("a", 30) },
			{ action = "ban", target = "Bob" },
			{ action = "ban", target = "Bob", hours = 0 },
			{ action = "ban", target = "Bob", hours = 9000 },
			{ action = "ban", target = "Bob", hours = 1.5 },
			{ action = "ban", target = "Bob", hours = "forever" },
			{ action = "ban", target = "Bob", hours = 0 / 0 },
			{ action = "announce" },
			{ action = "announce", text = "" },
			{ action = "announce", text = "   " },
			{ action = "announce", text = string.rep("x", 121) },
			{ action = "announce", text = "line\nbreak" },
			{ action = "announce", text = 5 },
			{ action = "reset_save", target = "Bob" },
			{ action = "fly" },
			{ action = "shutdown2" },
		}) do
			t.eq(from(bad), nil)
		end
		-- Every action on the list is covered by a plain or a player request or has its own branch above.
		t.eq(AdminLogic.AnnounceText("ok"), "ok")
		t.eq(AdminLogic.AnnounceText(nil), nil)
	end)

	local function grant(role, powers)
		return { role = role, powers = AdminLogic.PowersOf(role, powers) or {} }
	end

	t.test("each role holds exactly its powers, and ban and gift are limited", function()
		local allows = AdminLogic.GrantAllows
		local helper, mod, builder = grant("HELPER"), grant("MODERATOR"), grant("BUILDER")
		for _, power in ipairs({ "goto", "bring", "freeze", "stats", "announce" }) do
			t.eq(allows(helper, power), true, "helper " .. power)
		end
		for _, power in ipairs({ "kick", "ban", "gift", "settime", "heal", "god" }) do
			t.eq(allows(helper, power), false, "helper not " .. power)
		end
		t.eq(allows(mod, "kick"), true)
		t.eq(allows(mod, "ban", { banHours = 1 }), true)
		t.eq(allows(mod, "ban", { banHours = 2 }), false, "over the hour")
		t.eq(allows(mod, "ban", { banHours = nil }), false, "never permanent")
		t.eq(allows(mod, "gift"), false)
		t.eq(allows(builder, "gift", { selfTarget = true }), true)
		t.eq(allows(builder, "gift", { selfTarget = false }), false, "only for themself")
		t.eq(allows(builder, "settime"), true)
		t.eq(allows(builder, "kick"), false)
		t.eq(allows(helper, "admin"), true, "the help list is for everyone")
		t.eq(allows(nil, "goto"), false)
		t.eq(allows(helper, 5), false)
	end)

	t.test("the never-delegable powers are the owner's, whatever a role or custom list says", function()
		for _, power in ipairs(AdminLogic.NeverDelegable) do
			t.eq(table.find(AdminLogic.DelegablePowers, power), nil, power .. " is not delegable")
			for _, role in ipairs({ "HELPER", "MODERATOR", "BUILDER" }) do
				t.eq(AdminLogic.GrantAllows(grant(role), power, { selfTarget = true, banHours = 1 }), false)
			end
			-- Even a hand-made grant that lists it.
			t.eq(AdminLogic.GrantAllows({ role = "CUSTOM", powers = { power } }, power), false, "custom " .. power)
			local clean, bad = AdminLogic.CleanPowers({ "goto", power })
			t.eq(clean, nil)
			t.eq(bad, power)
		end
		for _, power in ipairs(AdminLogic.OwnerOnly) do
			for _, role in ipairs(AdminLogic.RoleList) do
				t.eq(AdminLogic.GrantAllows(grant(role, { "goto" }), power), false, role .. " can't " .. power)
			end
			t.eq(table.find(AdminLogic.AllPowers, power), nil, "TESTER never holds " .. power)
		end
		t.eq(AdminLogic.CleanPowers({}), nil)
		t.eq(AdminLogic.CleanPowers({ "kick", "kick" })[1], "kick")
		t.eq(#AdminLogic.CleanPowers({ "kick", "kick" }), 1)
		t.eq(AdminLogic.CleanPowers("kick"), nil)
	end)

	t.test("TESTER holds every owner power except delegation, and nothing else", function()
		local tester = grant("TESTER")
		for _, action in ipairs(AdminLogic.MenuActions) do
			local ok = AdminLogic.GrantAllows(tester, action, { selfTarget = true, banHours = 5000 })
			t.eq(ok, table.find(AdminLogic.OwnerOnly, action) == nil, action)
		end
		for _, power in ipairs({
			"give",
			"take",
			"setcash",
			"superrun",
			"shutdown",
			"unban",
			"resettutorial",
			"unlockbp",
		}) do
			t.eq(AdminLogic.GrantAllows(tester, power), true, power)
		end
		t.eq(AdminLogic.GrantAllows(tester, "ban", { banHours = nil }), true, "permanent too")
		t.eq(AdminLogic.GrantAllows(tester, "grant_everything"), false)
		t.eq(AdminLogic.GrantAllows(tester, "delegate"), false)
		t.eq(AdminLogic.GrantAllows(tester, "undelegate"), false)
		t.eq(AdminLogic.GrantAllows(tester, "delegates"), false)
		for _, action in ipairs({ "ban", "kick", "shutdown", "take", "setcash", "unban", "resettutorial" }) do
			t.eq(AdminLogic.IsDestructive(action), true, action)
		end
		t.eq(AdminLogic.IsDestructive("give"), false)
	end)

	t.test("expiry: session, 1h, 24h or until the server closes; TESTER never the last", function()
		t.eq(AdminLogic.ExpirySeconds("1h"), 3600)
		t.eq(AdminLogic.ExpirySeconds("24h"), 86400)
		t.eq(AdminLogic.ExpirySeconds("session"), nil)
		t.eq(AdminLogic.ExpirySeconds("forever"), nil)
		for _, e in ipairs({ "session", "1h", "24h", "server" }) do
			t.eq(AdminLogic.ExpiryAllowed("HELPER", e), true, e)
		end
		for _, e in ipairs({ "session", "1h", "24h" }) do
			t.eq(AdminLogic.ExpiryAllowed("TESTER", e), true, e)
		end
		for _, bad in ipairs({ "server", "forever", "perm", "", 5 }) do
			t.eq(AdminLogic.ExpiryAllowed("TESTER", bad), false, tostring(bad))
		end
		t.eq(AdminLogic.ExpiryAllowed("HELPER", "perm"), false)
		local g = { role = "HELPER", powers = {}, expiresAt = 1000 }
		t.eq(AdminLogic.Expired(g, 999), false)
		t.eq(AdminLogic.Expired(g, 1000), true)
		t.eq(
			AdminLogic.Expired({ role = "HELPER", powers = {} }, 10 ^ 12),
			false,
			"no expiry time: until the session or server ends"
		)
	end)

	t.test("delegation words parse, and only the confirmed TESTER request carries confirm", function()
		local parse = AdminLogic.ParseDelegate
		local p = parse({ "Bob", "moderator", "1h" })
		t.eq(p.role, "MODERATOR")
		t.eq(p.expiry, "1h")
		t.eq(p.confirmed, false)
		t.eq(parse({ "Bob", "helper" }).expiry, "session", "the default")
		t.eq(parse({ "123456", "helper", "24h" }).userId, 123456)
		local c = parse({ "Bob", "custom", "kick,goto", "24h" })
		t.eq(c.powers, { "kick", "goto" })
		t.eq(parse({ "Bob", "tester", "1h", "confirm" }).confirmed, true)
		t.eq(parse({ "Bob", "tester", "confirm" }).confirmed, true)
		for _, bad in ipairs({
			{},
			{ "Bob" },
			{ "Bob", "boss" },
			{ "Bob", "custom" },
			{ "Bob", "custom", "give" },
			{ "Bob", "custom", "shutdown,goto" },
			{ "Bob", "helper", "forever" },
			{ "Bob", "tester", "server" },
		}) do
			t.eq(parse(bad), nil, table.concat(bad, " "))
		end
		local from = AdminLogic.FromRequest
		t.eq(from({ action = "delegate", target = "Bob", role = "HELPER", expiry = "1h" }), "/delegate Bob helper 1h")
		t.eq(
			from({
				action = "delegate",
				target = "Bob",
				role = "CUSTOM",
				powers = { "kick", "goto" },
				expiry = "session",
			}),
			"/delegate Bob custom kick,goto session"
		)
		t.eq(
			from({ action = "delegate", target = "Bob", role = "TESTER", expiry = "1h" }),
			"/delegate Bob tester 1h",
			"no confirm without it"
		)
		t.eq(
			from({ action = "delegate", target = "Bob", role = "TESTER", expiry = "1h", confirmed = true }),
			"/delegate Bob tester 1h confirm"
		)
		t.eq(from({ action = "undelegate", target = "Bob" }), "/undelegate Bob")
		t.eq(from({ action = "delegates" }), "/delegates")
		for _, bad in ipairs({
			{ action = "delegate", target = "Bob", role = "TESTER", expiry = "server", confirmed = true },
			{ action = "delegate", target = "Bob", role = "OWNER", expiry = "1h" },
			{ action = "delegate", target = "Bob", role = "CUSTOM", powers = { "give" }, expiry = "1h" },
			{ action = "delegate", target = "Bob", role = "CUSTOM", powers = {}, expiry = "1h" },
			{ action = "delegate", target = "Bob", role = "HELPER", expiry = "forever" },
			{ action = "delegate", target = "Bob", role = "HELPER" },
			{ action = "delegate", role = "HELPER", expiry = "1h" },
			{ action = "delegate", target = "Bob; /shutdown", role = "HELPER", expiry = "1h" },
			{ action = "undelegate" },
		}) do
			t.eq(from(bad), nil)
		end
		t.ok(string.find(AdminLogic.TesterWarning, "trust", 1, true))
		-- A role sent with a request is only a word for the command line: nothing here reads it as a permission.
		t.eq(from({ action = "give", target = "Bob", amount = 5, role = "TESTER" }), "/give Bob 5")
	end)

	t.test("the time menu requests become commands, only from the whitelist", function()
		local from = AdminLogic.FromRequest
		t.eq(from({ action = "timespeed", speed = 60 }), "/timespeed 60")
		t.eq(from({ action = "timespeed", speed = 1 }), "/timespeed 1")
		t.eq(from({ action = "timereset" }), "/timereset")
		for _, name in ipairs(AdminLogic.TimePresetOrder) do
			t.eq(from({ action = "settime", time = name }), "/settime " .. name)
		end
		for _, bad in ipairs({
			{ action = "timespeed", speed = 7 },
			{ action = "timespeed", speed = "60" },
			{ action = "timespeed", speed = 0 / 0 },
			{ action = "timespeed" },
			{ action = "settime", time = "9pm" },
			{ action = "settime", time = "noon; /kick Bob" },
			{ action = "settime", time = 12 },
			{ action = "settime" },
		}) do
			t.eq(from(bad), nil)
		end
	end)
end
