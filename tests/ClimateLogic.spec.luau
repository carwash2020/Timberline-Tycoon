--!nocheck
-- Cold and heat outside the crater. The meter fills during the grace.
-- Damage starts once it is full. A seat pauses it. Gear removes it.
return function(t)
	local ClimateLogic = t.shared("ClimateLogic")
	local BiomeData = t.shared("BiomeData")

	local snow = { kind = "snow", dps = 4, graceSec = 8 }
	local heat = { kind = "volcano", dps = 6, graceSec = 6 }

	t.test("the meter fills through the grace and then deals its damage", function()
		local exposure, damage = ClimateLogic.Tick(0, 4, true, false, snow)
		t.eq(exposure, 0.5)
		t.eq(damage, 0)
		exposure, damage = ClimateLogic.Tick(exposure, 4, true, false, snow)
		t.eq(exposure, 1)
		t.eq(damage, 0, "the frame that fills the meter is still the grace")
		exposure, damage = ClimateLogic.Tick(exposure, 1, true, false, snow)
		t.eq(exposure, 1)
		t.eq(damage, 4)
		exposure, damage = ClimateLogic.Tick(0, 1, true, false, heat)
		t.ok(math.abs(exposure - 1 / 6) < 1e-9)
		t.eq(damage, 0)
	end)

	t.test("a seat pauses the meter, and leaving or respawning clears it", function()
		local exposure, damage = ClimateLogic.Tick(0.25, 10, true, true, snow)
		t.eq(exposure, 0.25)
		t.eq(damage, 0)
		exposure, damage = ClimateLogic.Tick(0.25, 10, false, false, snow)
		t.eq(exposure, 0)
		t.eq(damage, 0)
	end)

	t.test("snow and the volcano outside the crater name their gear; the crater does not", function()
		local snowBiome = BiomeData.Get("snow")
		local volcano = BiomeData.Get("volcano")
		local cold = BiomeData.Exposure(snowBiome, {}, true)
		t.eq(cold.dps, 4)
		t.eq(cold.graceSec, 8)
		t.eq(BiomeData.Exposure(snowBiome, { InsulatedCoat = true }, true), nil)
		t.eq(BiomeData.Exposure(volcano, {}, false), nil, "the crater keeps the lava burn")
		local outside = BiomeData.Exposure(volcano, {}, true)
		t.eq(outside.dps, 6)
		t.eq(outside.graceSec, 6)
		t.eq(BiomeData.Exposure(volcano, { HeatBoots = true }, true), nil)
	end)
end
