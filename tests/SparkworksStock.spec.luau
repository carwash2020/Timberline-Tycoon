--!nocheck
-- SparkworksStock: one row per V1 logic piece, one price, shelf order.
return function(t)
	local Stock = t.shared("SparkworksStock")
	local Items = t.shared("LogicItems")

	local EXPECT = {
		"Button",
		"Lever",
		"PressurePlate",
		"SparkSwitch",
		"GateAnd",
		"GateOr",
		"GateXor",
		"GateNot",
		"Delay",
		"Sustain",
		"Clock",
		"SparkLamp",
		"GlowWire",
		"Hatch",
		-- Lane W (8 Oct 2026): practical automation pieces.
		"WoodSweeper",
		"LaserEmitter",
		"LaserReceiver",
	}

	t.test("every V1 piece is listed once, in shelf order, at its LogicItems price", function()
		local list = Stock.List()
		t.eq(#list, #EXPECT)
		local seen = {}
		for i, row in ipairs(list) do
			t.eq(row.id, EXPECT[i])
			t.eq(seen[row.id], nil, "once")
			seen[row.id] = true
			t.eq(row.price, Stock.Price(row.id))
			t.eq(type(row.blurb), "string")
			t.ok(#row.blurb > 0 and #row.blurb < 80, row.id)
			t.eq(string.find(row.blurb, "u³", 1, true), nil)
			t.eq(string.find(row.displayName, "$", 1, true), nil)
			local bp
			for _, item in ipairs(Items) do
				if item.id == row.id then
					bp = item
				end
			end
			t.eq(row.price, bp.priceCash, row.id)
			t.eq(row.displayName, bp.displayName)
		end
		t.eq(Stock.Price("Door"), nil, "a door is not a Sparkworks box")
		t.eq(Stock.Get("Nope"), nil)
	end)
end
