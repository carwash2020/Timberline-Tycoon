--!nocheck
-- The one objective after Murph's tutorial.
return function(t)
	local FieldGuide = t.shared("FieldGuide")
	local ItemCatalog = t.shared("ItemCatalog")
	local NextGoal = t.shared("NextGoal")
	local ShopLogic = t.shared("ShopLogic")
	local WoodData = t.shared("WoodData")

	local function foundNone()
		return { oak = true }
	end

	t.test("the next axe on the ladder, then a forge when it isn't sold", function()
		local steel = ItemCatalog.AxeLadder()[2]
		local goal = NextGoal.Pick(2, 1, foundNone(), 0)
		t.eq(goal.kind, "axe")
		t.eq(goal.beacon, "toolShed")
		t.eq(
			goal.text,
			string.format("Buy the %s (%s)", steel.displayName, FieldGuide.CashText(ShopLogic.Price(steel, 2)))
		)
		t.eq(ShopLogic.Price(steel, 2), 120)
		local hardened = ItemCatalog.AxeLadder()[3]
		local nextUp = NextGoal.Pick(2, 2, foundNone(), 0)
		t.ok(string.find(nextUp.text, hardened.displayName, 1, true) ~= nil)
		local star = ItemCatalog.AxeTier("StarfallAxe")
		local forge = NextGoal.Pick(2, star - 1, foundNone(), 0)
		t.eq(forge.text, "Forge the Starfall Axe")
		t.eq(forge.beacon, nil)
	end)

	t.test("then a Field Guide blank, then the daily streak", function()
		local mystery = NextGoal.Pick(2, #ItemCatalog.AxeLadder(), foundNone(), 0)
		t.eq(mystery.kind, "wood")
		t.ok(string.find(mystery.text, "???", 1, true) ~= nil)
		local hidden = WoodData.All()[2]
		t.ok(string.find(mystery.text, hidden.displayName, 1, true) == nil, "the name stays blank")
		t.ok(string.find(mystery.text, FieldGuide.Hint(hidden), 1, true) ~= nil)
		local all = {}
		for _, wood in ipairs(WoodData.All()) do
			all[wood.id] = true
		end
		t.eq(NextGoal.Pick(2, 99, all, 0).text, "Finish day 1 of your daily streak")
		t.eq(NextGoal.Pick(1, 99, all, 3).text, "Daily streak: day 3")
	end)

	t.test("the axe goal says when the Tool Shed opens while it is shut", function()
		local open = NextGoal.Pick(2, 1, foundNone(), 0, 12)
		local shut = NextGoal.Pick(2, 1, foundNone(), 0, 23)
		t.ok(string.find(open.text, "opens at", 1, true) == nil, open.text)
		t.ok(string.find(shut.text, "opens at 6:00 AM", 1, true) ~= nil, shut.text)
		t.eq(shut.beacon, "toolShed")
		t.eq(NextGoal.Pick(2, 1, foundNone(), 0).text, open.text, "no hour: no note")
	end)
end
