--!nocheck
-- SellLogic (V2_PLAN.md §5): wood is worth volume x price per u³ x figure x
-- boost, a sale pays the owner (or the last holder), and the toast reads well.

return function(t)
	local SellLogic = t.shared("SellLogic")
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local ForestLogic = t.shared("ForestLogic")

	local function near(a, b, eps, what)
		t.ok(math.abs(a - b) <= eps, string.format("%s: %.4f vs %.4f", what, a, b))
	end

	t.test("volume is in timber units: a u-sided cube is 1 u³", function()
		local u = GameConfig.WoodUnit
		near(SellLogic.VolumeU3(u, u, u), 1, 1e-9, "one u³")
		near(SellLogic.VolumeU3(2 * u, u, 3 * u), 6, 1e-9, "six")
	end)

	t.test("a log is worth its volume at the log price, a plank at the plank price", function()
		local oak = WoodData.Get("oak").v2
		near(SellLogic.PieceValue("oak", "log", 10, nil, 1), 10 * oak.logPrice, 1e-9, "oak log")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1), 10 * oak.plankPrice, 1e-9, "oak plank")
		t.eq(SellLogic.PieceValue("nonsense", "log", 10, nil, 1), 0)
		t.eq(SellLogic.PieceValue("oak", "log", -5, nil, 1), 0)
	end)

	t.test("figures and 2x Wood raise a piece's worth; no boost means 1", function()
		local plain = SellLogic.PieceValue("maple", "log", 8, nil, nil)
		local curly = SellLogic.PieceValue("maple", "log", 8, "curly", 1)
		near(curly, plain * ForestLogic.Multiplier("curly"), 1e-9, "curly")
		near(SellLogic.PieceValue("maple", "log", 8, nil, 2), plain * 2, 1e-9, "2x Wood")
		near(SellLogic.PieceValue("maple", "log", 8, nil, 0), plain, 1e-9, "a bad boost is 1")
	end)

	t.test("a payout rounds to whole dollars, applies 2x Cash once, and never rounds wood to $0", function()
		t.eq(SellLogic.Payout(41.6, 1), 42)
		t.eq(SellLogic.Payout(41.6, 2), 83)
		t.eq(SellLogic.Payout(0.2, 1), 1)
		t.eq(SellLogic.Payout(0, 2), 0)
		t.eq(SellLogic.Payout(-3, 1), 0)
	end)

	t.test("wood pays its owner, else its last holder, else nobody", function()
		local here = { [1] = true, [2] = true }
		local function online(id)
			return here[id] == true
		end
		t.eq(SellLogic.Payee(1, 2, online), 1)
		t.eq(SellLogic.Payee(9, 2, online), 2) -- the owner left
		t.eq(SellLogic.Payee(0, 2, online), 2) -- unowned wood someone carried
		t.eq(SellLogic.Payee(9, 8, online), nil)
		t.eq(SellLogic.Payee(nil, nil, online), nil)
	end)

	t.test("the sale toast: pieces, u³ and dollars", function()
		t.eq(SellLogic.SaleText(3, 41.2, 96), "Sold 3 pieces · 41 u³ · $96")
		t.eq(SellLogic.SaleText(1, 2.5, 4), "Sold 1 piece · 2.5 u³ · $4")
		t.eq(SellLogic.SaleText(2, 3, 1234567), "Sold 2 pieces · 3 u³ · $1,234,567")
		t.eq(SellLogic.Money(999), "999")
		t.eq(SellLogic.Money(1000), "1,000")
	end)

	t.test("a mature-ish oak trunk (2 x 9 x 2 studs) sells for about $10 as a log", function()
		local u3 = SellLogic.VolumeU3(2, 9, 2)
		local v = SellLogic.PieceValue("oak", "log", u3, nil, 1)
		t.ok(v > 7 and v < 15, string.format("$%.2f for %.1f u³", v, u3))
	end)
end
