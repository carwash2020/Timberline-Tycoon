--!nocheck
return function(t)
	local StoreData = t.shared("StoreData")

	t.test("keys are unique and look up both ways", function()
		local seen = {}
		for _, item in ipairs(StoreData.Passes) do
			t.ok(not seen[item.key], "duplicate " .. item.key)
			seen[item.key] = true
			t.eq(StoreData.Pass(item.key), item)
		end
		for _, item in ipairs(StoreData.Products) do
			t.ok(not seen[item.key], "duplicate " .. item.key)
			seen[item.key] = true
			t.eq(StoreData.Product(item.key), item)
		end
		t.eq(StoreData.Pass("Nope"), nil)
	end)

	t.test("CreatorIds is the only id table, and 0 is not for sale", function()
		t.eq(StoreData.IsForSale(0), false)
		t.eq(StoreData.IsForSale(-1), false)
		t.eq(StoreData.ProductById(0), nil)
		t.eq(StoreData.PassById(0), nil)
		t.eq(StoreData.CreatorIds.Passes.DoubleCash, 2005256811)
		t.eq(StoreData.CreatorIds.Passes.LuxAxe, 2005226878)
		t.eq(StoreData.CreatorIds.Products.Cash1k, 3716312861)
		t.eq(StoreData.CreatorIds.Products.Cash10k, 3716312899)
		-- Lane P: these five stay at 0 (off sale, "Coming soon") until Connor
		-- says to paste their ids (kept in the comments in StoreData).
		t.eq(StoreData.CreatorIds.Passes.TowService, 0)
		t.eq(StoreData.CreatorIds.Passes.TimberClassic, 0)
		t.eq(StoreData.CreatorIds.Passes.PaintShop, 0)
		t.eq(StoreData.CreatorIds.Products.DoubleWood, 0)
		t.eq(StoreData.CreatorIds.Products.InstantDelivery, 0)
		local forSale = 0
		local seen = {}
		for _, pass in ipairs(StoreData.Passes) do
			t.eq(pass.id, StoreData.CreatorIds.Passes[pass.key], pass.key)
			if StoreData.IsForSale(pass.id) then
				forSale += 1
				t.ok(not seen[pass.id], "pass id used twice")
				seen[pass.id] = true
			end
		end
		for _, product in ipairs(StoreData.Products) do
			t.eq(product.id, StoreData.CreatorIds.Products[product.key], product.key)
			if StoreData.IsForSale(product.id) then
				forSale += 1
				t.ok(not seen[product.id], "product id used twice")
				seen[product.id] = true
			end
		end
		-- Four ids are pasted (2x Cash, Lux Axe, both cash packs); whether
		-- each is on sale is still Roblox's answer (StoreSale).
		t.eq(forSale, 4)
		t.eq(StoreData.AnyForSale(), true)
		t.eq(#StoreData.ListedPasses(), 2)
		t.eq(#StoreData.ListedProducts(), 2)
		t.eq(#StoreData.Ordered(), 9)
		t.eq(StoreData.ProductById(0), nil, "id 0 never lists a product")
		t.eq(StoreData.Pass("LuxAxe").image, 0, "Lux Axe image slot left at 0")
		t.eq(StoreData.Pass("DoubleCash").image, 0, "2x Cash image slot left at 0")
		t.eq(StoreData.Pass("DoubleCash").key, "DoubleCash")
		t.eq(StoreData.Passes[1].key, "DoubleCash", "2x Cash stays first so its test id stays 101")
		t.eq(StoreData.CreatorIds.Passes.DoubleCash, 2005256811)
		t.eq(StoreData.CreatorIds.Passes.LuxAxe, 2005226878)
		t.eq(StoreData.CreatorIds.Products.Cash1k, 3716312861)
		t.eq(StoreData.CreatorIds.Products.Cash10k, 3716312899)
		t.eq(StoreData.Pass("TowService").image, 91282142796474)
		t.eq(StoreData.Pass("TimberClassic").image, 79037897236948)
		t.eq(StoreData.Pass("PaintShop").image, 71028498113750)
		-- Retired cash passes are not for sale and are not ids we grant.
		local retired = { [2005844842] = true, [2004962887] = true }
		for id in pairs(seen) do
			t.ok(not retired[id], "retired cash pass id " .. tostring(id))
		end
		t.eq(
			StoreData.Pass("DoubleCash").description,
			"Wood you sell pays double. It doesn't change your axes, trucks, or how fast you chop, and everything in the game can still be earned without it."
		)
		t.eq(
			StoreData.Pass("LuxAxe").description,
			"A black axe with a gold head, a diamond edge, and a sparkle. It sits between the Inferno Axe and the Starfall Axe, and the Starfall Axe can still be bought with cash. Wood you cut with it sells for 10% more. It's yours to keep and can't be sold. It can't be tempered."
		)
		t.eq(
			StoreData.Pass("TowService").description,
			"Free recalls for every truck you own. Without this pass, a recall costs 5% of the truck's price, with a $5 minimum."
		)
		t.eq(
			StoreData.Pass("TimberClassic").description,
			"Unlocks the Timber Classic, an old-school pickup with the same stats as the Pickup. Its dashboard gauge shows what your load is worth, as an estimate at the Wood Dropoff. Your display name is painted on both doors."
		)
		t.eq(
			StoreData.Pass("PaintShop").description,
			"Paint your trucks in any color from the Paint Shop palette. Paint is cosmetic only and stays on after you rejoin."
		)
	end)

	t.test("set-up ids are unique", function()
		local ids = {}
		for _, list in ipairs({ StoreData.Passes, StoreData.Products }) do
			for _, item in ipairs(list) do
				if StoreData.IsForSale(item.id) then
					t.ok(not ids[item.id], "id used twice: " .. item.id)
					ids[item.id] = true
				end
			end
		end
	end)

	t.test("Lane P: the packs are Small and Large and say what they add; 2x Wood says what it does", function()
		t.eq(StoreData.Product("Cash1k").name, "Small Cash Pack")
		t.eq(StoreData.Product("Cash10k").name, "Large Cash Pack")
		t.eq(StoreData.Product("Cash1k").description, "Adds 15 minutes of wood income at your current stage.")
		t.eq(StoreData.Product("Cash10k").description, "Adds 2 hours of wood income at your current stage.")
		t.eq(
			StoreData.Product("DoubleWood").description,
			"For 48 hours, wood from every tree you fell sells for double. Buying it again adds 48 more hours."
		)
		local small, large = StoreData.Product("Cash1k"), StoreData.Product("Cash10k")
		t.eq(StoreData.PackCashAt(small, 1), 1000, "never under the old floor")
		t.eq(StoreData.PackCashAt(large, 1), 10000)
		t.eq(StoreData.PackCashAt(small, 6), 28700)
		t.eq(StoreData.PackCashAt(large, 6), 229600)
		for n = 2, 8 do
			t.ok(StoreData.PackCashAt(large, n) >= StoreData.PackCashAt(large, n - 1), "climbs at S" .. n)
			t.eq(StoreData.PackCashAt(large, n) % 10, 0, "rounded to $10")
		end
		t.eq(StoreData.PackCash(large, { onboarding = { ["Stage:S6"] = true } }), 229600)
		t.eq(StoreData.PackCash(large, { onboarding = {}, bestAxeTier = 7 }), 229600, "a veteran before Lane E")
		t.ok(StoreData.PackFits(large, 0, 300000, 229600))
		t.ok(not StoreData.PackFits(large, 100000, 300000, 229600), "the scaled amount is what must fit")
		local order = {}
		for _, entry in ipairs(StoreData.Ordered()) do
			table.insert(order, entry.key)
			t.eq(StoreData.IdOf(entry.kind, entry.key), entry.item.id)
		end
		t.eq(order[1], "DoubleCash")
		t.eq(#order, 9)
		t.eq(StoreData.IdOf("Gift", "DoubleCash"), 0)
	end)

	t.test("a pass with IsForSale == false is hidden", function()
		for _, key in ipairs({ "TowService", "TimberClassic", "PaintShop" }) do
			local pass = StoreData.Pass(key)
			t.eq(StoreData.PassCardVisible(pass.id, false), false, key .. " is off sale")
		end
		t.eq(StoreData.PassCardVisible(StoreData.Pass("LuxAxe").id, nil), false, "hidden until the lookup")
		t.eq(StoreData.PassCardVisible(StoreData.Pass("DoubleCash").id, true), true, "2x Cash is on sale")
		t.eq(StoreData.PassCardVisible(StoreData.Pass("LuxAxe").id, true), true, "Lux Axe is on sale")
		t.eq(StoreData.PassCardVisible(0, true), false, "no id, still hidden")
	end)

	t.test("cash packs only fit under the wallet cap", function()
		local pack = StoreData.Product("Cash10k")
		t.ok(StoreData.PackFits(pack, 0, 2_000_000))
		t.ok(StoreData.PackFits(pack, 1_990_000, 2_000_000), "exactly to the cap is fine")
		t.ok(not StoreData.PackFits(pack, 1_990_001, 2_000_000))
		t.ok(StoreData.PackFits(StoreData.Product("DoubleWood"), 2_000_000, 2_000_000), "boosts aren't cash")
	end)
end
