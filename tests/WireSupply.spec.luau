--!nocheck
-- WireSupply (T420): wire is a single-use item. You buy it by the amount
-- needed, a wire is stretched from one piece to another up to a maximum
-- length, and the length is used up from your box. The price per unit comes
-- from the item catalog (ItemCatalog.Wire); nothing here invents one.
return function(t)
	local WireSupply = t.shared("WireSupply")
	local WireLogic = t.shared("WireLogic")
	local ItemCatalog = t.shared("ItemCatalog")

	t.test("the wire's price and unit come from the item catalog, not from this module", function()
		local def = ItemCatalog.GetWire()
		t.ok(def ~= nil, "ItemCatalog has a Wire row")
		t.eq(WireSupply.UnitPrice(), def.unitPrice)
		t.ok(def.unitPrice > 0 and def.unitPrice == math.floor(def.unitPrice), "a whole, positive price per unit")
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ReplicatedStorage/Shared/WireSupply.luau")
		t.eq(string.find(source, "UnitPrice = %d"), nil, "no price literal in the rules")
	end)

	t.test("a run is at most 64 studs along its path, with at most 4 bends", function()
		t.eq(WireSupply.MaxLength, 64)
		t.eq(WireSupply.MaxLength, WireLogic.MaxRun)
		t.eq(WireSupply.MaxBends, 4)
		t.ok(WireSupply.Fits(64))
		t.ok(not WireSupply.Fits(64.01), "64.01 fails")
		t.ok(not WireSupply.Fits(0 / 0), "NaN never fits")
		t.ok(not WireSupply.Fits(-1))
		t.ok(not WireSupply.Fits(math.huge))
	end)

	t.test("a wire uses one unit per stud, rounded up, at least one", function()
		t.eq(WireSupply.UnitsFor(0.2), 1)
		t.eq(WireSupply.UnitsFor(1), 1)
		t.eq(WireSupply.UnitsFor(1.01), 2)
		t.eq(WireSupply.UnitsFor(10), 10)
		t.eq(WireSupply.UnitsFor(31.2), 32)
		t.eq(WireSupply.UnitsFor(0 / 0), 0, "a bad length uses nothing and is refused elsewhere")
		t.eq(WireSupply.UnitsFor(-3), 0)
	end)

	t.test("length is the ground distance between the two pieces", function()
		t.eq(WireSupply.Length({ x = 0, z = 0 }, { x = 3, z = 4 }), 5)
	end)

	t.test("a quote says go, too far, or short and by how many", function()
		local ok = WireSupply.Quote(20, 10)
		t.eq(ok.state, "ok")
		t.eq(ok.units, 10)
		t.eq(ok.cost, 10 * WireSupply.UnitPrice())
		t.eq(ok.short, 0)
		local short = WireSupply.Quote(4, 10)
		t.eq(short.state, "short")
		t.eq(short.short, 6)
		t.eq(short.buyCost, 6 * WireSupply.UnitPrice(), "what the missing wire costs")
		local far = WireSupply.Quote(500, WireSupply.MaxLength + 1)
		t.eq(far.state, "far")
		t.eq(far.short, 0, "too far is not fixed by buying")
		t.eq(WireSupply.Quote(0, 0 / 0).state, "far")
		t.eq(WireSupply.Quote(nil, 5).state, "short", "no box at all is short")
	end)

	t.test("using wire takes exactly its units from the box and never goes below zero", function()
		t.eq(WireSupply.Use(20, 8), 12)
		t.eq(WireSupply.Use(8, 8), 0)
		t.eq(WireSupply.Use(7, 8), nil, "not enough: nothing is taken")
		t.eq(WireSupply.Use(7, 0), nil, "a use of nothing is refused")
		t.eq(WireSupply.Use(7, 1.5), nil)
		t.eq(WireSupply.Use(7, -2), nil)
	end)

	t.test("wire is sold in packs of 32, 64 and 160 only", function()
		t.eq(WireSupply.Packs, { 32, 64, 160 })
		for _, n in ipairs({ 32, 64, 160 }) do
			t.ok(WireSupply.IsPack(n))
		end
		for _, n in ipairs({ 0, 1, 10, 31, 33, 63, 65, 100, 159, 161, 320, -32, 32.5, 0 / 0, math.huge }) do
			t.ok(not WireSupply.IsPack(n), tostring(n) .. " is not a pack")
		end
		t.ok(not WireSupply.IsPack("32"))
		t.ok(not WireSupply.IsPack(nil))
	end)

	t.test("buying checks the pack, the box's cap of 320 and the cash, and says what it costs", function()
		local price = WireSupply.UnitPrice()
		t.eq(WireSupply.MaxStock, 320)
		local ok, why, cost, stock = WireSupply.Buy(price * 64, 3, 64)
		t.ok(ok and why == nil)
		t.eq(cost, price * 64)
		t.eq(stock, 67)
		for _, bad in ipairs({ 0, -32, 10, 33, 100, 2.5, 0 / 0, "32", 321, math.huge }) do
			t.eq({ WireSupply.Buy(1e9, 0, bad) }, { false, "amount" }, tostring(bad))
		end
		t.eq({ WireSupply.Buy(price * 64 - 1, 0, 64) }, { false, "cash" })
		t.eq({ WireSupply.Buy(1e9, WireSupply.MaxStock, 32) }, { false, "full" })
		t.eq(({ WireSupply.Buy(1e9, WireSupply.MaxStock - 31, 32) })[2], "full", "32 more would pass the cap")
		local ok2, _, _, stock2 = WireSupply.Buy(1e9, WireSupply.MaxStock - 32, 32)
		t.ok(ok2)
		t.eq(stock2, WireSupply.MaxStock)
	end)

	t.test("the box a save or a player attribute holds is cleaned to a whole count in range", function()
		t.eq(WireSupply.Clean(nil), 0)
		t.eq(WireSupply.Clean("9"), 0)
		t.eq(WireSupply.Clean(-4), 0)
		t.eq(WireSupply.Clean(0 / 0), 0)
		t.eq(WireSupply.Clean(7.9), 7)
		t.eq(WireSupply.Clean(WireSupply.MaxStock + 100), WireSupply.MaxStock)
	end)

	t.test("the pack to buy is the smallest that covers the shortfall and fits the box", function()
		t.eq(WireSupply.BuyAmount(5, 12), 32, "7 short: the smallest pack")
		t.eq(WireSupply.BuyAmount(12, 12), 0, "nothing short")
		t.eq(WireSupply.BuyAmount(0, 33), 64)
		t.eq(WireSupply.BuyAmount(0, 64), 64)
		t.eq(WireSupply.BuyAmount(0, 100), 160)
		t.eq(WireSupply.BuyAmount(WireSupply.MaxStock - 20, WireSupply.MaxStock + 30), 0, "no pack fits the room left")
		t.eq(WireSupply.PackFor(1, 31), 0)
		t.eq(WireSupply.PackFor(1, 32), 32)
		t.eq(WireSupply.PackFor(0, 320), 0)
	end)

	t.test("a path is measured from the two pieces and the corners, and a fifth corner is refused", function()
		local a, b = { x = 0, z = 0 }, { x = 30, z = 0 }
		t.eq(WireSupply.Path(a, nil, b), 30)
		t.eq(WireSupply.Path(a, { { x = 0, z = 17 }, { x = 30, z = 17 } }, b), 64)
		t.eq(WireSupply.Path(a, { { 0, 17 }, { 30, 17 } }, b), 64, "array corners work too")
		local four = { { x = 1, z = 1 }, { x = 2, z = 2 }, { x = 3, z = 3 }, { x = 4, z = 4 } }
		t.ok(WireSupply.Path(a, four, b) ~= nil, "four bends pass")
		table.insert(four, { x = 5, z = 5 })
		t.eq({ WireSupply.Path(a, four, b) }, { nil, "bends" }, "five bends fail")
		t.eq(({ WireSupply.Path(a, { { x = 0 / 0, z = 1 } }, b) })[2], "badvia")
		t.eq(({ WireSupply.Path(a, { { x = "1", z = 1 } }, b) })[2], "badvia")
		t.eq(({ WireSupply.Path(a, "no", b) })[2], "badvia")
		t.eq(({ WireSupply.Path(a, { a = 1 }, b) })[2], "badvia")
	end)

	t.test("every message the player can meet is written", function()
		for _, key in ipairs({ "amount", "cash", "full", "short", "far", "bought", "bends" }) do
			t.ok(type(WireSupply.Message(key, 5, 9)) == "string", key)
		end
		t.ok(string.find(WireSupply.Message("short", 5, 9), "4"), "short names how many more")
	end)
end
