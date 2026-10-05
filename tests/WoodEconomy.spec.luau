--!nocheck
-- B02: the plank-price knob, and the full-plot square price (acceptance E1).
return function(t)
	local GameConfig = t.shared("GameConfig")
	local SellLogic = t.shared("SellLogic")
	local WoodData = t.shared("WoodData")

	t.test("plank prices are the plan times PlankScale, never under PlankFloor times the log", function()
		t.eq(WoodData.PlankScale, 0.35)
		t.eq(WoodData.PlankFloor, 2.5)
		for _, wood in ipairs(WoodData.All()) do
			local plan = WoodData.PlanPlank[wood.id]
			t.ok(type(plan) == "number" and plan > 0, wood.id .. " has a plan plank price")
			local boost = WoodData.RareBoost[wood.id]
			local planned = if boost then plan * boost * WoodData.RarePlankBonus else plan
			t.eq(wood.v2.plankPrice, WoodData.ScaledPlank(wood.v2.logPrice, planned), wood.id)
			t.ok(wood.v2.plankPrice >= wood.v2.logPrice * WoodData.PlankFloor - 1e-9, wood.id .. " floor")
		end
		local oak = WoodData.Get("oak").v2
		-- 10 of oak planks pays the floor multiple of 10 of oak logs.
		local logs = SellLogic.PieceValue("oak", "log", 10, nil, 1)
		local planks = SellLogic.PieceValue("oak", "plank", 10, nil, 1)
		t.eq(logs, 10 * oak.logPrice)
		t.eq(planks, logs * WoodData.PlankFloor)
		t.eq(planks / logs, 2.5)
	end)

	t.test("a full plot is the first square plus expansions 1..24, priced for about 30 h", function()
		local expansions = 24
		local sumK = expansions * (expansions + 1) / 2
		local total = GameConfig.FirstPlotPrice + GameConfig.ExpansionPriceStep * sumK
		t.eq(GameConfig.FirstPlotPrice, 100)
		t.eq(GameConfig.ExpansionPriceStep, 3050, "was 2280 ($684,100) before the rarer woods paid more")
		t.eq(sumK, 300)
		t.eq(total, 915100)
	end)

	t.test("rarer woods pay more, per log and per plank, and common woods are unchanged", function()
		for _, id in ipairs({ "oak", "birch", "pine", "maple", "palmwood", "frostwood" }) do
			t.eq(WoodData.RareBoost[id], nil, id .. " is common: no boost")
		end
		t.eq(WoodData.Get("oak").v2.logPrice, 1.5)
		local last = 0
		for _, id in ipairs({ "emberwood", "phantomwood", "lumenwood" }) do
			local boost = WoodData.RareBoost[id]
			t.ok(boost ~= nil and boost > 1, id .. " is boosted")
			t.ok(boost > last, id .. " pays a bigger boost than the one before")
			last = boost
		end
		t.ok(WoodData.RarePlankBonus > 1, "milling a rare wood adds a bonus")
	end)
end
