--!nocheck
-- WireSupply (T420): wire is a single-use item, sold as ONE Wire Box (160 studs, $100). A wire
-- run is stretched from one end to another up to 160 studs and only the studs it uses come out
-- of your box. The box and its price come from the item catalog (ItemCatalog.Wire).
return function(t)
	local WireSupply = t.shared("WireSupply")
	local WireLogic = t.shared("WireLogic")
	local ItemCatalog = t.shared("ItemCatalog")

	t.test("one wire catalog item: the Wire Box, 160 studs, $100, from the catalog not from this module", function()
		local def = ItemCatalog.GetWire()
		t.ok(def ~= nil, "ItemCatalog has a Wire row")
		t.eq(def.displayName, "Wire Box (160 studs)")
		t.eq(def.boxStuds, 160)
		t.eq(def.boxPrice, 100)
		t.eq(def.unitPrice, nil, "no per-stud price any more")
		t.eq(WireSupply.BoxUnits, 160)
		t.eq(WireSupply.BoxPrice, 100)
		t.eq(WireSupply.Packs, nil, "no other size is sold")
		local n = 0
		for key, value in pairs(ItemCatalog) do
			if type(value) == "table" and value.id == "Wire" then
				n += 1
				t.eq(key, "Wire")
			end
		end
		t.eq(n, 1, "exactly one wire item")
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ReplicatedStorage/Shared/WireSupply.luau")
		t.eq(string.find(source, "BoxPrice = %d"), nil, "no price literal in the rules")
	end)

	t.test("a run is at most 160 studs along its path (the whole box), with at most 4 bends", function()
		t.eq(WireSupply.MaxLength, 160)
		t.eq(WireSupply.MaxLength, WireLogic.MaxRun)
		t.eq(WireSupply.MaxLength, WireSupply.BoxUnits)
		t.eq(WireSupply.MaxBends, 4)
		t.ok(WireSupply.Fits(160), "160 passes")
		t.ok(not WireSupply.Fits(160.01), "160.01 fails")
		t.ok(not WireSupply.Fits(161), "161 fails")
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
		t.eq(ok.left, 10, "a 10 stud run leaves 10 of 20")
		t.eq(ok.buyCost, 0)
		t.eq(ok.short, 0)
		local short = WireSupply.Quote(4, 10)
		t.eq(short.state, "short")
		t.eq(short.short, 6)
		t.eq(short.buyCost, 100, "the box that covers it costs $100")
		t.eq(WireSupply.Quote(160, 40).left, 120, "a 40 stud run leaves 120 of a full box")
		t.eq(WireSupply.Quote(160, 160).state, "ok")
		t.eq(WireSupply.Quote(160, 160).left, 0)
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

	t.test("wire is sold as the one box of 160 only", function()
		t.ok(WireSupply.IsBox(160))
		for _, n in ipairs({ 0, 1, 10, 32, 64, 100, 159, 161, 320, -160, 160.5, 0 / 0, math.huge }) do
			t.ok(not WireSupply.IsBox(n), tostring(n) .. " is not the box")
		end
		t.ok(not WireSupply.IsBox("160"))
		t.ok(not WireSupply.IsBox(nil))
	end)

	t.test("buying checks the box, the cap of 320 (two boxes at most) and the cash", function()
		t.eq(WireSupply.MaxStock, 320)
		t.eq(WireSupply.MaxStock, 2 * WireSupply.BoxUnits, "two boxes at most")
		local ok, why, cost, stock = WireSupply.Buy(100, 3, 160)
		t.ok(ok and why == nil)
		t.eq(cost, 100)
		t.eq(stock, 163)
		for _, bad in ipairs({ 0, -160, 32, 64, 159, 161, 2.5, 0 / 0, "160", 320, math.huge }) do
			t.eq({ WireSupply.Buy(1e9, 0, bad) }, { false, "amount" }, tostring(bad))
		end
		t.eq({ WireSupply.Buy(99, 0, 160) }, { false, "cash" })
		t.eq({ WireSupply.Buy(1e9, 161, 160) }, { false, "full" }, "a second box would pass the cap")
		local ok2, _, _, stock2 = WireSupply.Buy(1e9, 160, 160)
		t.ok(ok2)
		t.eq(stock2, 320, "two boxes fit exactly")
	end)

	t.test("the box a save or a player attribute holds is cleaned to a whole count in range", function()
		t.eq(WireSupply.Clean(nil), 0)
		t.eq(WireSupply.Clean("9"), 0)
		t.eq(WireSupply.Clean(-4), 0)
		t.eq(WireSupply.Clean(0 / 0), 0)
		t.eq(WireSupply.Clean(7.9), 7)
		t.eq(WireSupply.Clean(WireSupply.MaxStock + 100), WireSupply.MaxStock)
	end)

	t.test("the box to buy covers any shortfall (a run is at most 160) and needs room for a whole box", function()
		t.eq(WireSupply.BuyAmount(5, 12), 160, "7 short: the one box")
		t.eq(WireSupply.BuyAmount(12, 12), 0, "nothing short")
		t.eq(WireSupply.BuyAmount(0, 160), 160)
		t.eq(WireSupply.BuyAmount(161, 400), 0, "no room for a whole box")
		t.eq(WireSupply.BoxFor(1, 159), 0)
		t.eq(WireSupply.BoxFor(1, 160), 160)
		t.eq(WireSupply.BoxFor(0, 320), 0)
	end)

	t.test("a path is measured from the two pieces and the corners, and a fifth corner is refused", function()
		local a, b = { x = 0, z = 0 }, { x = 30, z = 0 }
		t.eq(WireSupply.Path(a, nil, b), 30)
		t.eq(WireSupply.Path(a, { { x = 0, z = 17 }, { x = 30, z = 17 } }, b), 64)
		t.eq(WireSupply.Path(a, { { 0, 17 }, { 30, 17 } }, b), 64, "array corners work too")
		t.ok(
			WireSupply.Fits(WireSupply.Path(a, { { x = 0, z = 17 }, { x = 30, z = 17 } }, b) :: number),
			"64 is far from the limit now"
		)
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
		t.ok(string.find(WireSupply.Message("bought"), "$100", 1, true), "the box price is shown")
		t.ok(string.find(WireSupply.Message("amount"), "160", 1, true), "the refusal names the one box")
	end)
end
