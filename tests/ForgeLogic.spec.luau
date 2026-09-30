--!nocheck
return function(t)
	local ForgeLogic = t.shared("ForgeLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local recipe = ItemCatalog.GetAxe("StarfallAxe").forge

	local function stock(cash, lumenwood, shards)
		return { cash = cash, logs = { lumenwood = lumenwood }, materials = { SkyShard = shards } }
	end

	t.test("everything missing, listed plainly", function()
		t.eq(ForgeLogic.Missing(recipe, stock(0, 0, 0)), {
			"$60,000 more",
			"40 more Lumenwood logs",
			"12 more Sky Shards",
		})
	end)

	t.test("partly there", function()
		t.eq(ForgeLogic.Missing(recipe, stock(70000, 28, 5)), { "12 more Lumenwood logs", "7 more Sky Shards" })
		t.eq(ForgeLogic.Missing(recipe, { cash = 60000, logs = {}, materials = {} })[1], "40 more Lumenwood logs")
	end)

	t.test("ready to forge", function()
		t.eq(ForgeLogic.Missing(recipe, stock(60000, 40, 12)), {})
		t.eq(ForgeLogic.Missing(recipe, stock(99999, 50, 20)), {})
	end)

	t.test("the forge only takes what the recipe still needs", function()
		t.eq(ForgeLogic.LogsWanted(recipe, stock(0, 0, 0), "lumenwood"), 40)
		t.eq(ForgeLogic.LogsWanted(recipe, stock(0, 38, 0), "lumenwood"), 2)
		t.eq(ForgeLogic.LogsWanted(recipe, stock(0, 40, 0), "lumenwood"), 0)
		t.eq(ForgeLogic.LogsWanted(recipe, stock(0, 0, 0), "oak"), 0, "not in the recipe")
	end)

	t.test("progress line", function()
		t.eq(ForgeLogic.Progress(recipe, stock(0, 12, 5)), "Lumenwood 12/40 · Sky Shards 5/12 · $60,000")
	end)
end
