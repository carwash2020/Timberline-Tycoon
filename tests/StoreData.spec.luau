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

	t.test("an id of 0 means not set up: never matches a receipt", function()
		t.eq(StoreData.ProductById(0), nil)
	end)

	t.test("set-up ids are unique", function()
		local ids = {}
		for _, list in ipairs({ StoreData.Passes, StoreData.Products }) do
			for _, item in ipairs(list) do
				if item.id ~= 0 then
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
