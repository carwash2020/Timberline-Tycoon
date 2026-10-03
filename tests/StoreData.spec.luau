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
		local forSale = 0
		for _, pass in ipairs(StoreData.Passes) do
			t.eq(pass.id, StoreData.CreatorIds.Passes[pass.key], pass.key)
			if StoreData.IsForSale(pass.id) then
				forSale += 1
			end
		end
		for _, product in ipairs(StoreData.Products) do
			t.eq(product.id, StoreData.CreatorIds.Products[product.key], product.key)
			if StoreData.IsForSale(product.id) then
				forSale += 1
			end
		end
		t.eq(forSale, 0, "nothing is for sale until a Creator Hub id is pasted in")
		t.eq(StoreData.AnyForSale(), false)
		t.eq(#StoreData.ListedPasses(), 0)
		t.eq(#StoreData.ListedProducts(), 0)
		t.eq(StoreData.Pass("LuxAxe").image, 0, "image slot left at 0")
		t.eq(StoreData.Pass("DoubleCash").key, "DoubleCash")
		t.eq(StoreData.Passes[1].key, "DoubleCash", "2x Cash stays first so its test id stays 101")
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

	t.test("cash packs only fit under the wallet cap", function()
		local pack = StoreData.Product("Cash10k")
		t.ok(StoreData.PackFits(pack, 0, 2_000_000))
		t.ok(StoreData.PackFits(pack, 1_990_000, 2_000_000), "exactly to the cap is fine")
		t.ok(not StoreData.PackFits(pack, 1_990_001, 2_000_000))
		t.ok(StoreData.PackFits(StoreData.Product("DoubleWood"), 2_000_000, 2_000_000), "boosts aren't cash")
	end)
end
