--!nocheck
-- SellLogic (V2_PLAN.md §5): wood is worth volume x price per x figure x
-- boost, a sale pays the owner (or the last holder), and the toast reads well.

return function(t)
	local SellLogic = t.shared("SellLogic")
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local ForestLogic = t.shared("ForestLogic")

	local function near(a, b, eps, what)
		t.ok(math.abs(a - b) <= eps, string.format("%s: %.4f vs %.4f", what, a, b))
	end

	t.test("volume is in timber units: a u-sided cube is 1", function()
		local u = GameConfig.WoodUnit
		near(SellLogic.VolumeU3(u, u, u), 1, 1e-9, "one")
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

	t.test("the Lux tag is 10% once, stacks with 2x Wood, and passes to children", function()
		local plain = SellLogic.PieceValue("oak", "log", 10, nil, 1, false)
		local lux = SellLogic.PieceValue("oak", "log", 10, nil, 1, true)
		near(lux, plain * GameConfig.LuxSellBonus, 1e-9, "10% once")
		local both = SellLogic.PieceValue("oak", "log", 10, nil, 2, true)
		near(both, plain * 2 * GameConfig.LuxSellBonus, 1e-9, "2x Wood then Lux, once")
		local plank = SellLogic.PieceValue("oak", "plank", 4, nil, 1, true)
		near(plank, SellLogic.PieceValue("oak", "plank", 4, nil, 1, false) * GameConfig.LuxSellBonus, 1e-9, "plank")
		-- 2x Cash is Payout's job, not a second multiply inside the piece.
		t.eq(SellLogic.Payout(lux, 2), SellLogic.Payout(plain * GameConfig.LuxSellBonus, 2))
		t.eq(SellLogic.InheritLux(false, true), true)
		t.eq(SellLogic.InheritLux(true, false), true)
		t.eq(SellLogic.InheritLux(false, false), false)
		local entry = SellLogic.Entry("oak", "log", 10, nil, 2, true)
		t.eq(entry.l, true)
		near(SellLogic.EntryValue(entry), both, 1e-6, "bin entry keeps the tag")
		t.eq(SellLogic.Entry("oak", "plank", 1, nil, 1, false).l, nil)
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

	t.test("the sale toast: pieces, and dollars", function()
		t.eq(SellLogic.SaleText(3, 41.2, 96), "Sold 3 pieces · $96")
		t.eq(SellLogic.SaleText(1, 2.5, 4), "Sold 1 piece · $4")
		t.eq(SellLogic.SaleText(2, 3, 1234567), "Sold 2 pieces · $1,234,567")
		t.eq(SellLogic.Money(999), "999")
		t.eq(SellLogic.Money(1000), "1,000")
	end)

	t.test("a mature-ish oak trunk (2 x 9 x 2 studs) sells for about $10 as a log", function()
		local u3 = SellLogic.VolumeU3(2, 9, 2)
		local v = SellLogic.PieceValue("oak", "log", u3, nil, 1)
		t.ok(v > 7 and v < 15, string.format("$%.2f for %.1f", v, u3))
	end)

	-- M1.7b: the Sky Bin keeps pieces as short entries and pays them as the
	-- pad would have.
	t.test("a Sky Bin entry keeps wood,, figure, plank and a boost over 1", function()
		t.eq(SellLogic.Entry("oak", "log", 4, nil, 1), { w = "oak", v = 4 })
		t.eq(SellLogic.Entry("maple", "plank", 2.5, "curly", 2), { w = "maple", v = 2.5, f = "curly", p = true, b = 2 })
		t.eq(SellLogic.Entry("oak", "log", 4, nil, 0 / 0), { w = "oak", v = 4 }, "a broken boost is 1")
	end)

	t.test("an entry is worth what the piece was worth on the pad", function()
		local entry = SellLogic.Entry("maple", "plank", 2, "curly", 2)
		near(SellLogic.EntryValue(entry), SellLogic.PieceValue("maple", "plank", 2, "curly", 2), 1e-9, "figured plank")
		local plain = SellLogic.Entry("lumenwood", "log", 12, nil, 1)
		near(SellLogic.EntryValue(plain), 12 * WoodData.Get("lumenwood").v2.logPrice, 1e-9, "lumenwood log")
	end)

	t.test("a list of entries adds up; malformed ones count for nothing", function()
		local entries = {
			SellLogic.Entry("oak", "log", 10, nil, 1),
			SellLogic.Entry("pine", "log", 5, "birdseye", 2),
			{ w = "oak", v = 0 / 0 },
			{ w = "oak", v = -3 },
			{ w = 7, v = 3 },
			"oak",
		}
		local value, volume, count = SellLogic.EntriesValue(entries)
		local oak, pine = WoodData.Get("oak").v2, WoodData.Get("pine").v2
		near(value, 10 * oak.logPrice + 5 * pine.logPrice * ForestLogic.Multiplier("birdseye") * 2, 1e-9, "value")
		t.eq(volume, 15)
		t.eq(count, 2)
		t.eq({ SellLogic.EntriesValue({}) }, { 0, 0, 0 })
		t.ok(not SellLogic.ValidEntry({ w = "oak", v = math.huge }), "an infinite volume")
		t.eq(SellLogic.EntryValue({ w = "oak", v = -1 }), 0)
	end)

	t.test("the bin's room and its label", function()
		t.ok(SellLogic.Fits(100, 20, 120), "exactly full fits")
		t.ok(not SellLogic.Fits(100, 20.5, 120))
		t.ok(SellLogic.Fits(0.1 + 0.2, 119.7, 120), "float noise doesn't refuse")
		t.eq(SellLogic.BinText(14, 120), "14/120")
		t.eq(SellLogic.BinText(0, 120), "0/120")
		t.eq(SellLogic.BinText(4.25, 120), "4.3/120")
	end)

	t.test("a plank's mill bonus and a board's planer bonus multiply its sale value (planks only)", function()
		local plain = SellLogic.PieceValue("oak", "plank", 10, nil, 1)
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 1.22), plain * 1.22, 1e-9, "mill bonus")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, nil, 1.4), plain * 1.4, 1e-9, "board bonus")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 1.22, 1.4), plain * 1.22 * 1.4, 1e-9, "both")
		-- It stacks with figure, boost and Lux like the rest.
		local lux = SellLogic.PieceValue("oak", "plank", 10, "curly", 2, true)
		near(SellLogic.PieceValue("oak", "plank", 10, "curly", 2, true, 1.5, 2), lux * 3, 1e-9, "stacks")
		-- A log has no bonus whatever is written on it.
		near(
			SellLogic.PieceValue("oak", "log", 10, nil, 1, false, 1.5, 2),
			SellLogic.PieceValue("oak", "log", 10, nil, 1),
			1e-9,
			"logs never"
		)
		-- Old pieces (nothing stamped) and junk stamps are 1.0; stamps are capped.
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, nil, nil), plain, 1e-9, "old piece")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 0.5, -3), plain, 1e-9, "below 1 is 1")
		near(
			SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 0 / 0, math.huge),
			plain * SellLogic.BonusCap,
			1e-9,
			"NaN is 1, infinity is the cap"
		)
		t.eq(SellLogic.Bonus(nil), 1)
		t.eq(SellLogic.Bonus("1.5"), 1)
		t.eq(SellLogic.Bonus(99), SellLogic.BonusCap)
	end)

	t.test(
		"the Sky Bin entry keeps a plank's stamps, an old entry is 1.0, and the bin pays what the pad would",
		function()
			local entry = SellLogic.Entry("oak", "plank", 10, "curly", 2, true, 1.36, 1.65)
			t.eq(entry.m, 1.36)
			t.eq(entry.d, 1.65)
			near(
				SellLogic.EntryValue(entry),
				SellLogic.PieceValue("oak", "plank", 10, "curly", 2, true, 1.36, 1.65),
				1e-9,
				"the bin pays what the pad would"
			)
			local old = SellLogic.Entry("oak", "plank", 10)
			t.eq(old.m, nil)
			t.eq(old.d, nil)
			near(
				SellLogic.EntryValue({ w = "oak", v = 10, p = true }),
				SellLogic.PieceValue("oak", "plank", 10),
				1e-9,
				"a save from before mill tiers"
			)
			-- A hand-edited save can't stamp more than the cap or a NaN.
			near(
				SellLogic.EntryValue({ w = "oak", v = 10, p = true, m = 99, d = 0 / 0 }),
				SellLogic.PieceValue("oak", "plank", 10) * SellLogic.BonusCap,
				1e-9,
				"capped"
			)
			t.eq(SellLogic.Entry("oak", "plank", 10, nil, nil, nil, 1, 1).m, nil, "1.0 is not written")
		end
	)

	t.test("temper t is the last argument: a log is price times t, a plank caps the product at 3", function()
		local plain = SellLogic.PieceValue("oak", "plank", 10)
		local log = SellLogic.PieceValue("oak", "log", 10)
		near(SellLogic.PieceValue("oak", "log", 10, nil, 1, false, nil, nil, 1.10), log * 1.10, 1e-9, "log times t")
		near(SellLogic.PieceValue("oak", "log", 10, nil, 1, false, 2, 1.8, 1.10), log * 1.10, 1e-9, "a log ignores mill and board")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 2, 1.8, 1), plain * SellLogic.BonusCap, 1e-9, "mill 2 and board 1.8 cap at 3")
		near(SellLogic.PieceValue("oak", "plank", 10, nil, 1, false, 1.5, 1.8, 1.10), plain * math.min(3, 1.5 * 1.8 * 1.10), 1e-9, "under the cap")
		t.eq(SellLogic.Temper(1.04), 1.04)
		t.eq(SellLogic.Temper(1.07), 1.07)
		t.eq(SellLogic.Temper(1.10), 1.10)
		t.eq(SellLogic.Temper(1.5), 1)
		t.eq(SellLogic.Temper(nil), 1)
		local stamped = SellLogic.Entry("oak", "log", 10, nil, nil, nil, nil, nil, 1.07)
		t.eq(stamped.t, 1.07)
		t.eq(SellLogic.Entry("oak", "log", 10, nil, nil, nil, nil, nil, 1).t, nil, "1 is not written")
		near(SellLogic.EntryValue(stamped), SellLogic.PieceValue("oak", "log", 10, nil, nil, nil, nil, nil, 1.07), 1e-9, "the bin pays t")
	end)
end
