--!nocheck
-- Axe ladder, sold-in-order rules and hit damage.
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local WoodData = t.shared("WoodData")

	local function ids(list)
		local out = {}
		for _, item in ipairs(list) do
			table.insert(out, item.id)
		end
		return out
	end

	t.test("the ladder runs from the Rusty Axe to the Starfall Axe by price", function()
		t.eq(ids(ItemCatalog.AxeLadder()), {
			"RustyAxe",
			"SteelAxe",
			"HardenedAxe",
			"SilverAxe",
			"CobaltAxe",
			"GoldAxe",
			"ObsidianAxe",
			"InfernoAxe",
			"StarfallAxe",
		})
	end)

	t.test("AxeTier is the rung on the ladder", function()
		t.eq(ItemCatalog.AxeTier("RustyAxe"), 1)
		t.eq(ItemCatalog.AxeTier("SteelAxe"), 2)
		t.eq(ItemCatalog.AxeTier("StarfallAxe"), 9)
		t.eq(ItemCatalog.AxeTier("NoSuchAxe"), nil)
	end)

	t.test("NextAxe is one rung up, and nil when the next one is forged", function()
		t.eq(ItemCatalog.NextAxe(1).id, "SteelAxe")
		t.eq(ItemCatalog.NextAxe(7).id, "InfernoAxe")
		t.eq(ItemCatalog.NextAxe(8), nil) -- Starfall is forged, not sold
		t.eq(ItemCatalog.NextAxe(9), nil)
	end)

	t.test("CanBuyAxe allows owned rungs and the next one, nothing further", function()
		t.ok(ItemCatalog.CanBuyAxe("SteelAxe", 1))
		t.ok(not ItemCatalog.CanBuyAxe("HardenedAxe", 1), "skipping a rung")
		t.ok(ItemCatalog.CanBuyAxe("SteelAxe", 5), "re-buying an older axe")
		t.ok(not ItemCatalog.CanBuyAxe("StarfallAxe", 8), "forged axes are never sold")
		t.ok(not ItemCatalog.CanBuyAxe("NoSuchAxe", 9))
	end)

	t.test("AxeDamage subtracts hardness and uses biome overrides", function()
		local rusty = ItemCatalog.GetAxe("RustyAxe")
		local inferno = ItemCatalog.GetAxe("InfernoAxe")
		local starfall = ItemCatalog.GetAxe("StarfallAxe")
		t.eq(ItemCatalog.AxeDamage(rusty, WoodData.Get("oak")), 5)
		t.eq(ItemCatalog.AxeDamage(rusty, WoodData.Get("pine")), 1)
		t.eq(ItemCatalog.AxeDamage(rusty, WoodData.Get("maple")), 0, "the Rusty Axe can't cut maple")
		t.eq(ItemCatalog.AxeDamage(inferno, WoodData.Get("emberwood")), 150, "200 vs volcano - 50 hardness")
		t.eq(ItemCatalog.AxeDamage(inferno, WoodData.Get("lumenwood")), 30)
		t.eq(ItemCatalog.AxeDamage(starfall, WoodData.Get("lumenwood")), 180, "300 vs sky - 120 hardness")
		t.eq(ItemCatalog.AxeDamage(starfall, WoodData.Get("emberwood")), 130, "Inferno stays better on volcano")
	end)

	t.test("the Lux Axe sits just above the Fire Axe and below the Starfall Axe, off the ladder", function()
		local fire = ItemCatalog.GetAxe("InfernoAxe")
		local lux = ItemCatalog.GetAxe("LuxAxe")
		local top = ItemCatalog.GetAxe("StarfallAxe")
		t.eq(ItemCatalog.AxeTier("LuxAxe"), nil)
		t.ok(not ItemCatalog.CanBuyAxe("LuxAxe", 9))
		t.eq(lux.robux, true)
		t.ok(lux.v2.damage > fire.v2.damage and lux.v2.damage < top.v2.damage)
		t.ok(lux.v2.range > fire.v2.range and lux.v2.range < top.v2.range)
		t.ok(lux.v2.cooldown < fire.v2.cooldown and lux.v2.cooldown > top.v2.cooldown)
		t.ok(lux.damage > fire.damage and lux.damage < top.damage)
		t.eq(lux.v2.vs, nil, "no specialist line: Fire stays best on emberwood")
		t.eq(ItemCatalog.AxeDamage(lux, WoodData.Get("emberwood")), 165 - 50)
		t.ok(
			ItemCatalog.AxeDamage(lux, WoodData.Get("emberwood"))
				< ItemCatalog.AxeDamage(fire, WoodData.Get("emberwood"))
		)
	end)

	t.test("oak falls in 6 hits with the Rusty Axe (Phase 1 acceptance)", function()
		local oak = WoodData.Get("oak")
		t.eq(math.ceil(oak.treeHP / ItemCatalog.AxeDamage(ItemCatalog.GetAxe("RustyAxe"), oak)), 6)
	end)
end
