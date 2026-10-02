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

	-- The v2 loop (M1.7b): the forge takes lumenwood by the u³.
	local axe = ItemCatalog.GetAxe("StarfallAxe")
	local v2 = ForgeLogic.RecipeV2(axe)

	local function stockV2(cash, lumenwood, shards)
		return { cash = cash, wood = { lumenwood = lumenwood }, materials = { SkyShard = shards } }
	end

	t.test("v2: the recipe is 60 u³ of lumenwood (40 logs x 1.5), the forge's cash and shards", function()
		t.eq(v2, { cash = 60000, wood = { lumenwood = 60 }, materials = { SkyShard = 12 } })
		t.eq(ForgeLogic.RecipeV2(ItemCatalog.GetAxe("SteelAxe")), nil, "not forged")
		local Schema = t.loader():server("ProfileSchema")
		t.eq(v2.wood.lumenwood, recipe.logs.lumenwood * Schema.ForgeU3PerLog, "the conversion MigrateV2 uses")
	end)

	t.test("v2: what's missing, in u³", function()
		t.eq(
			ForgeLogic.MissingV2(v2, stockV2(0, 0, 0)),
			{ "$60,000 more", "60 more u³ of Lumenwood", "12 more Sky Shards" }
		)
		t.eq(ForgeLogic.MissingV2(v2, stockV2(70000, 47.5, 12)), { "12.5 more u³ of Lumenwood" })
		t.eq(
			ForgeLogic.MissingV2(v2, stockV2(70000, 59.96, 12)),
			{ "0.1 more u³ of Lumenwood" },
			"never 0 while short"
		)
		t.eq(ForgeLogic.MissingV2(v2, stockV2(60000, 60, 12)), {})
		t.eq(ForgeLogic.MissingV2(v2, stockV2(60000, 59.9999999, 12)), {}, "float noise isn't short")
		t.eq(ForgeLogic.MissingV2(v2, { cash = 0, wood = {}, materials = {} })[2], "60 more u³ of Lumenwood")
	end)

	t.test("v2: the forge takes up to the recipe", function()
		t.eq(ForgeLogic.WoodWanted(v2, stockV2(0, 0, 0), "lumenwood"), 60)
		t.eq(ForgeLogic.WoodWanted(v2, stockV2(0, 42.5, 0), "lumenwood"), 17.5)
		t.eq(ForgeLogic.WoodWanted(v2, stockV2(0, 60, 0), "lumenwood"), 0)
		t.eq(ForgeLogic.WoodWanted(v2, stockV2(0, 0, 0), "oak"), 0, "not in the recipe")
	end)

	t.test("v2: the progress line", function()
		t.eq(ForgeLogic.ProgressV2(v2, stockV2(0, 18, 5)), "Lumenwood 18/60 u³ · Sky Shards 5/12 · $60,000")
		t.eq(ForgeLogic.ProgressV2(v2, stockV2(0, 59.96, 5)), "Lumenwood 59.9/60 u³ · Sky Shards 5/12 · $60,000")
		t.eq(
			ForgeLogic.ProgressV2(v2, { cash = 0, wood = {}, materials = {} }),
			"Lumenwood 0/60 u³ · Sky Shards 0/12 · $60,000"
		)
	end)

	t.test("v2: what the forge refuses, and why", function()
		t.eq(ForgeLogic.RefusalV2(v2, stockV2(0, 0, 0), "lumenwood", nil), nil)
		t.eq(ForgeLogic.RefusalV2(v2, stockV2(0, 0, 0), "oak", nil), "The forge takes plain Lumenwood only.")
		t.eq(ForgeLogic.RefusalV2(v2, stockV2(0, 0, 0), "oak", "curly"), "The forge takes plain Lumenwood only.")
		t.eq(
			ForgeLogic.RefusalV2(v2, stockV2(0, 0, 0), "lumenwood", "starfall"),
			"Figured wood is worth more sold than forged: take it to the sawmill."
		)
		t.eq(ForgeLogic.RefusalV2(v2, stockV2(0, 60, 0), "lumenwood", nil), "The forge has all the Lumenwood it needs.")
	end)

	t.test("v2: the forged line counts hits to cut a lumenwood trunk", function()
		local FieldGuide = t.shared("FieldGuide")
		local WoodData = t.shared("WoodData")
		local hits = FieldGuide.TrunkHits(axe, WoodData.Get("lumenwood"))
		t.ok(hits > 1 and hits < 100, tostring(hits))
		t.eq(
			ForgeLogic.ForgedTextV2(axe, v2),
			string.format("The Starfall Axe is yours! It cuts a Lumenwood trunk in %d hits.", hits)
		)
	end)
end
