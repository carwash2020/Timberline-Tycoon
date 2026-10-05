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
end
