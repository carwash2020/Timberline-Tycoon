--!nocheck
-- Lane F: anything owned that falls out of the world comes back at its owner's
-- plot. The pure rules; WoodService, VehicleService and PlotService.RecoverSpot
-- have their own cases beside their specs.
return function(t)
	local FallenLogic = t.shared("FallenLogic")

	t.test("below the void line is out of the world; the ground and the lake beds are not", function()
		t.eq(FallenLogic.Fell(-81), true)
		t.eq(FallenLogic.Fell(-500), true)
		t.eq(FallenLogic.Fell(-80), false)
		t.eq(FallenLogic.Fell(0), false)
		t.eq(FallenLogic.Fell(-12), false, "a lake bed is above it")
		t.eq(FallenLogic.Fell(650), false, "the isles are above it")
		t.eq(FallenLogic.Fell(0 / 0), true, "a NaN position is out of the world too")
		t.eq(FallenLogic.Fell(nil :: any), false)
	end)

	t.test("a rescued piece waits before it can be rescued again", function()
		t.eq(FallenLogic.MayRecover(10, nil), true)
		t.eq(FallenLogic.MayRecover(10, 9), false)
		t.eq(FallenLogic.MayRecover(11, 9), true)
	end)

	t.test("rescued pieces land on a ring over the plot, a different spot each, never inside each other", function()
		local seen = {}
		for n = 1, 16 do
			local x, y, z = FallenLogic.Offset(n)
			t.ok(y >= FallenLogic.SpotRise, "in the air above the plot")
			local key = string.format("%.2f,%.2f,%.2f", x, y, z)
			t.eq(seen[key], nil, "spot " .. n .. " is new")
			seen[key] = true
		end
		local x1, _, z1 = FallenLogic.Offset(1)
		local x2, _, z2 = FallenLogic.Offset(2)
		t.ok(math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2) > 3, "neighbours are apart")
		t.eq({ FallenLogic.Offset(0) }, { FallenLogic.Offset(1) }, "a bad index is the first spot")
	end)

	t.test("every case has a line to read", function()
		for _, key in ipairs({ "wood", "truck", "stone" }) do
			t.ok(type(FallenLogic.Texts[key]) == "string" and #FallenLogic.Texts[key] > 10, key)
		end
	end)
end
