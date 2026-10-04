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
			t.ok(type(plan) == "number" and plan > wood.v2.logPrice, wood.id .. " has a plan plank price")
			t.eq(wood.v2.plankPrice, WoodData.ScaledPlank(wood.v2.logPrice, plan), wood.id)
			t.ok(wood.v2.plankPrice >= wood.v2.logPrice * WoodData.PlankFloor - 1e-9, wood.id .. " floor")
		end
		local oak = WoodData.Get("oak").v2
		-- 10 u³ of oak planks pays the floor multiple of 10 u³ of oak logs.
		local logs = SellLogic.PieceValue("oak", "log", 10, nil, 1)
		local planks = SellLogic.PieceValue("oak", "plank", 10, nil, 1)
		t.eq(logs, 10 * oak.logPrice)
		t.eq(planks, logs * WoodData.PlankFloor)
		t.eq(planks / logs, 2.5)
	end)

	t.test("a full plot is the first square plus expansions 1..24, priced for about 32 h", function()
		local expansions = 24
		local sumK = expansions * (expansions + 1) / 2
		local total = GameConfig.FirstPlotPrice + GameConfig.ExpansionPriceStep * sumK
		t.eq(GameConfig.FirstPlotPrice, 100)
		t.eq(GameConfig.ExpansionPriceStep, 2280, "was 3000 ($900,100, 39.4 h)")
		t.eq(sumK, 300)
		t.eq(total, 684100)
	end)
end
