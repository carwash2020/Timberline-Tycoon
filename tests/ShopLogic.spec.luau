--!nocheck
return function(t)
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")

	local function axe(id)
		return ItemCatalog.GetAxe(id)
	end

	t.test("StatusOf follows the ladder", function()
		t.eq(ShopLogic.StatusOf(axe("RustyAxe"), 1, 1, 1), "starter")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 1, 0, 1), "buy")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 1, 0, 1), "locked")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 1, 2), "rebuy")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 2, 0, 2), "buy")
		t.eq(ShopLogic.StatusOf(axe("StarfallAxe"), 8, 0, 8), "forged")
		t.eq(ShopLogic.StatusOf(axe("StarfallAxe"), 9, 1, 9), "forged")
	end)

	t.test("a full inventory stops sales but still shows locked and forged", function()
		local max = GameConfig.MaxOwnedAxes
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 5, max), "full")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 2, 0, max), "full")
		t.eq(ShopLogic.StatusOf(axe("GoldAxe"), 2, 0, max), "locked")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 5, max - 1), "rebuy")
	end)

	t.test("only buy and rebuy take money", function()
		for _, status in ipairs({ "buy", "rebuy" }) do
			t.ok(ShopLogic.CanPurchase(status), status)
		end
		for _, status in ipairs({ "starter", "locked", "forged", "full" }) do
			t.ok(not ShopLogic.CanPurchase(status), status)
		end
	end)

	t.test("WhyNot explains every refusal", function()
		t.eq(ShopLogic.WhyNot("locked", axe("GoldAxe"), 2), "Axes are sold in order. Buy the Hardened Axe first.")
		t.eq(
			ShopLogic.WhyNot("forged", axe("StarfallAxe"), 8),
			"The Starfall Axe is forged in the Aether Isles, not sold."
		)
		t.eq(ShopLogic.WhyNot("starter", axe("RustyAxe"), 1), "Everyone starts with the Rusty Axe. It isn't sold.")
		t.eq(
			ShopLogic.WhyNot("full", axe("SteelAxe"), 2),
			string.format("You own %d axes, the most you can carry.", GameConfig.MaxOwnedAxes)
		)
		t.eq(ShopLogic.WhyNot("buy", axe("SteelAxe"), 1), "")
	end)

	t.test("FellSummary lists the toughest woods an axe cuts in 30 hits or fewer", function()
		t.eq(ShopLogic.FellSummary(axe("RustyAxe")), "Fells oak in 6 · birch in 12")
		t.eq(ShopLogic.FellSummary(axe("SteelAxe")), "Fells oak in 3 · birch in 5 · pine in 13")
		t.eq(ShopLogic.FellSummary(axe("InfernoAxe")), "Fells frostwood in 4 · emberwood in 6 · phantomwood in 15")
		t.eq(ShopLogic.FellSummary(axe("RustyAxe"), 3), "Too weak for any tree")
	end)

	t.test("DamageText names biome bonuses by their wood", function()
		t.eq(ShopLogic.DamageText(axe("SteelAxe")), "12 damage")
		t.eq(ShopLogic.DamageText(axe("InfernoAxe")), "150 damage (200 vs. emberwood)")
		t.eq(ShopLogic.DamageText(axe("StarfallAxe")), "180 damage (300 vs. lumenwood)")
	end)

	t.test("trucks: buy, use or in use; the Rustbucket is always yours", function()
		local function truck(id)
			return ItemCatalog.GetTruck(id)
		end
		local owned = { Pickup = true }
		t.eq(ShopLogic.TruckStatusOf(truck("Pickup"), owned, "Pickup"), "inUse")
		t.eq(ShopLogic.TruckStatusOf(truck("Rustbucket"), owned, "Pickup"), "use")
		t.eq(ShopLogic.TruckStatusOf(truck("Rustbucket"), {}, "Pickup"), "use")
		t.eq(ShopLogic.TruckStatusOf(truck("Flatbed"), owned, "Pickup"), "buy")
	end)

	t.test("truck details", function()
		t.eq(ShopLogic.TruckDetail(ItemCatalog.GetTruck("Pickup")), "Bed: 12 logs · top speed 28")
		t.eq(ShopLogic.TruckDetail(ItemCatalog.GetTruck("ScoutATV")), "No bed · top speed 40 · Fast recon, no cargo")
	end)

	t.test("id sets survive the attribute round trip", function()
		t.eq(ShopLogic.EncodeSet({ "Rustbucket", "Pickup" }), "Pickup,Rustbucket")
		t.eq(ShopLogic.DecodeSet("Pickup,Rustbucket"), { Pickup = true, Rustbucket = true })
		t.eq(ShopLogic.DecodeSet(""), {})
	end)

	t.test("owned counts survive the attribute round trip", function()
		local text = ShopLogic.EncodeOwned({ SteelAxe = 2, RustyAxe = 1, GoldAxe = 0 })
		t.eq(text, "RustyAxe=1,SteelAxe=2")
		local counts, total = ShopLogic.DecodeOwned(text)
		t.eq(counts, { RustyAxe = 1, SteelAxe = 2 })
		t.eq(total, 3)
	end)

	t.test("DecodeOwned ignores junk", function()
		local counts, total = ShopLogic.DecodeOwned("")
		t.eq(counts, {})
		t.eq(total, 0)
		counts, total = ShopLogic.DecodeOwned("garbage,SteelAxe=x,GoldAxe=3")
		t.eq(counts, { GoldAxe = 3 })
		t.eq(total, 3)
	end)
end
