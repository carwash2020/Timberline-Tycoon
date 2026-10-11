--!nocheck
-- Lane F, decision 9: unloading a base saves everything on it, loose wood
-- included. LooseSave is the pure side: caps, refusals with a count, the
-- records for slabs and ingots, and what a load puts back.
return function(t)
	local LooseSave = t.shared("LooseSave")
	local GameConfig = t.shared("GameConfig")

	t.test("the caps are the shared contract's: 150 pieces, 300 wood sections", function()
		t.eq(LooseSave.MaxPieces, GameConfig.MaxLoosePieces)
		t.eq(LooseSave.MaxPieces, 150)
		t.eq(LooseSave.MaxSections, GameConfig.MaxSavedSections)
	end)

	t.test("a pile that fits is saved; one over the cap is refused with the count, never dropped", function()
		t.eq({ LooseSave.Check({ pieces = 0, sections = 0, unsaveable = 0 }) }, { true, nil })
		t.eq({ LooseSave.Check({ pieces = 150, sections = 300, unsaveable = 0 }) }, { true, nil }, "exactly full")
		local ok, why = LooseSave.Check({ pieces = 163, sections = 200, unsaveable = 0 })
		t.eq(ok, false)
		t.ok(why:find("163") ~= nil and why:find("150") ~= nil and why:find("13") ~= nil, why)
		ok, why = LooseSave.Check({ pieces = 20, sections = 301, unsaveable = 0 })
		t.eq(ok, false)
		t.ok(why:find("too big") ~= nil, why)
		ok, why = LooseSave.Check({ pieces = 4, sections = 8, unsaveable = 2 })
		t.eq(ok, false)
		t.ok(why:find("2 loose pieces") ~= nil, why)
		_, why = LooseSave.Check({ pieces = 4, sections = 8, unsaveable = 1 })
		t.ok(why:find("1 loose piece ") ~= nil, "singular: " .. why)
	end)

	t.test("slab and ingot records round-trip and junk is cleaned", function()
		local place = LooseSave.EncodePlace(1.23456, 2, -3.5, 0, 1.57081, 0)
		t.eq(place, { 1.235, 2, -3.5, 0, 1.5708, 0 })
		local isOre = function(id)
			return id == "Copper" or id == "Gold"
		end
		local slab = LooseSave.CleanOther(LooseSave.SlabRecord(place), isOre)
		t.eq(slab, { kind = "slab", at = place })
		local ingot = LooseSave.CleanOther(LooseSave.IngotRecord("Copper", place), isOre)
		t.eq(ingot, { kind = "ingot", ore = "Copper", at = place })
		t.eq(LooseSave.CleanOther(LooseSave.IngotRecord("Unobtainium", place), isOre), nil, "an unknown ore")
		t.eq(LooseSave.CleanOther({ slab = true, at = { 1, 2 } }, isOre), nil, "a short place")
		t.eq(LooseSave.CleanOther({ slab = true, at = { 999, 0, 0, 0, 0, 0 } }, isOre), nil, "far off the plot")
		t.eq(LooseSave.CleanOther({ slab = true, at = { 0, 0, 0, 0, 9, 0 } }, isOre), nil, "a wild angle")
		t.eq(LooseSave.CleanOther({ slab = true, at = { 0 / 0, 0, 0, 0, 0, 0 } }, isOre), nil, "not a number")
		t.eq(LooseSave.CleanOther("slab", isOre), nil)
		t.eq(LooseSave.CleanOther({ at = place }, isOre), nil, "neither a slab nor an ingot")
	end)

	t.test("wood records are told apart from slabs and ingots", function()
		t.eq(LooseSave.IsWood({ w = "oak", k = "log", s = { { 1, 1, 1 } } }), true)
		t.eq(LooseSave.IsWood({ slab = true, at = {} }), false)
		t.eq(LooseSave.IsWood({ ingot = "Copper", at = {} }), false)
		t.eq(LooseSave.IsWood(5), false)
		t.eq(LooseSave.SectionsOf({ w = "oak", s = { {}, {}, {} } }), 3)
		t.eq(LooseSave.SectionsOf({ slab = true }), 0)
	end)

	t.test("a load puts back the first 150 and keeps the rest saved", function()
		local list = {}
		for i = 1, 153 do
			list[i] = { slab = true, at = { i, 0, 0, 0, 0, 0 } }
		end
		local now, later = LooseSave.Split(list)
		t.eq(#now, 150)
		t.eq(#later, 3)
		t.eq(later[1].at[1], 151, "in saved order")
		t.eq(LooseSave.Count(list).pieces, 153)
		local none1, none2 = LooseSave.Split(nil)
		t.eq({ #none1, #none2 }, { 0, 0 })
		t.eq(LooseSave.RestoredText(1, 0), "1 loose thing is back on your plot.")
		t.eq(LooseSave.RestoredText(5, 0), "5 loose things are back on your plot.")
		t.ok(LooseSave.RestoredText(5, 3):find("3 more are still saved") ~= nil)
	end)
end
