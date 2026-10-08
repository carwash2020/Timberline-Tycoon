--!nocheck
-- PickaxeData: the ladder, and a Lux stub that is not for sale.

return function(t)
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")

	t.test("the free ladder and the Lux stub", function()
		local shop = {}
		for _, pick in ipairs(PickaxeData.Shop()) do
			table.insert(shop, pick.id)
			t.eq(pick.forSale, nil)
			t.eq(pick.robux, nil)
		end
		t.eq(shop, { "RustyPick", "CopperPick", "IronPick", "SteelPick", "ObsidianPick" })
		local lux = PickaxeData.Get("LuxPickaxe")
		t.eq(lux.passId, 0)
		t.eq(lux.passKey, "LuxPickaxe")
		t.eq(lux.level, 4)
		t.eq(lux.speed, 1.45)
		t.eq(lux.forSale, false)
		t.eq(lux.price, 0)
	end)

	t.test("a level names the free pick, never the Lux Pickaxe", function()
		t.eq(PickaxeData.NameForLevel(1), "Rusty Pick")
		t.eq(PickaxeData.NameForLevel(4), "Steel Pick")
		t.eq(PickaxeData.NameForLevel(5), "Obsidian Pick")
	end)

	t.test("prices climb and the rusty pick is free", function()
		local last = -1
		for _, pick in ipairs(PickaxeData.Shop()) do
			t.ok(pick.price >= last, pick.id)
			last = pick.price
		end
		t.eq(PickaxeData.Get("RustyPick").price, 0)
		local obsidian = PickaxeData.Get("ObsidianPick")
		t.eq(obsidian.opalIngots, 5)
		t.eq(obsidian.needsHeartstone, nil)
		t.eq(obsidian.level, 5)
		t.eq(obsidian.price, 50000)
	end)
end
