--!nocheck
-- The shop screens' copy (ShopUI's three shops and StoreUI's Robux Store):
-- every subtitle reads in full on a phone, where it gets two lines of the
-- narrowest panel (UI-19), so none is longer than ShopUI.SubtitleMax.
return function(t)
	local fs = require("@lune/fs")
	local dir = "src/StarterPlayer/StarterPlayerScripts/"
	local MAX = 40 -- ShopUI.SubtitleMax

	t.test("every shop subtitle is 40 characters at most", function()
		local shop = fs.readFile(dir .. "ShopUI.luau")
		t.ok(string.find(shop, "ShopUI.SubtitleMax = " .. MAX, 1, true), "the limit the screens state")
		local found = 0
		for _, file in ipairs({ "ShopUI.luau", "StoreUI.luau" }) do
			local source = fs.readFile(dir .. file)
			for text in string.gmatch(source, '\n\tsubtitle = "([^"]*)"') do
				found += 1
				t.ok(utf8.len(text) <= MAX, string.format("%s: %q is %d long", file, text, utf8.len(text)))
				t.ok(#text > 0, file .. ": a subtitle")
			end
		end
		-- Lane P: the Store's words moved to Store/StoreCopy.
		local copy = fs.readFile("src/ReplicatedStorage/Shared/Store/StoreCopy.luau")
		for text in string.gmatch(copy, '\nStoreCopy.Subtitle = "([^"]*)"') do
			found += 1
			t.ok(utf8.len(text) <= MAX, string.format("StoreCopy: %q is %d long", text, utf8.len(text)))
		end
		t.eq(found, 8, "the four town screens, the coat, the boots, odds and ends, and the Store")
	end)

	-- M1.8b: under the v2 core loop the shops show what ShopService charges
	-- (ShopLogic.Price with the loop) and the loop's card texts; the Field
	-- Guide shows the loop's wood pages and Daily Goals the loop's bonus.
	t.test("the shops, the Field Guide and Daily Goals read the core loop's prices and texts", function()
		local shop = fs.readFile(dir .. "ShopUI.luau")
		for _, kind in ipairs({ "axe", "trailer", "truck" }) do
			t.ok(
				string.find(shop, string.format("ShopLogic.Price(%s, loop)", kind), 1, true),
				kind .. ": its price for the loop"
			)
			t.ok(not string.find(shop, kind .. ".priceCash", 1, true), kind .. ": no v1-only price left")
		end
		t.ok(string.find(shop, "ShopLogic.AxeDetail(axe, loop)", 1, true))
		t.ok(string.find(shop, "ShopLogic.TruckDetailFor(truck, loop)", 1, true))
		t.ok(string.find(shop, "ShopLogic.TrailerDetailFor(trailer, loop)", 1, true))
		t.ok(string.find(shop, "local loop = CoreLoop.Active()", 1, true), "the loop that runs")
		local guide = fs.readFile(dir .. "FieldGuideUI.luau")
		t.ok(string.find(guide, "FieldGuide.FactsFor(wood, CoreLoop.Active())", 1, true), "the loop's wood page")
		t.ok(not string.find(guide, "FieldGuide.Facts(wood)", 1, true), "no v1-only page left")
		local daily = fs.readFile(dir .. "DailyUI.luau")
		t.ok(string.find(daily, "DailyData.ProgressText(goal)", 1, true), "v2 progress in its units")
		t.ok(string.find(daily, "DailyData.Bonus(bestAxeTier(), nextStreak, if loop == 2 then 2 else nil)", 1, true))
	end)

	t.test("boxed town screens stay hidden, and the three counters stay open", function()
		local shop = fs.readFile(dir .. "ShopUI.luau")
		-- The four town screens are shelf menus: their windows hide when
		-- GameConfig.BoxedStores is on. Coat, boots and odds are shelf = false
		-- so the counter prompt still opens.
		local screens, shelves, open = 0, 0, 0
		for body in string.gmatch(shop, "\nlocal [A-Z]+: Shop = (%b{})") do
			if string.find(body, "building = ", 1, true) then
				screens += 1
				if string.find(body, "shelf = true", 1, true) then
					shelves += 1
				end
				if string.find(body, "shelf = false", 1, true) then
					open += 1
				end
			end
		end
		t.eq(screens, 7, "four town screens plus coat, boots and odds")
		t.eq(shelves, 4, "the Tool Shed, the Dealership, Hearth & Home and the saws")
		t.eq(open, 3, "coat, boots and odds open from the counter")
		t.ok(string.find(shop, "shop.shelf == true and ShopLogic.ShelfMenusHidden()", 1, true))
		t.ok(string.find(shop, 'building = "CoatKiosk"', 1, true))
		t.ok(string.find(shop, 'building = "HeatBoots"', 1, true))
		t.ok(string.find(shop, 'building = "OddsAndEnds"', 1, true))
		t.ok(
			string.find(shop, 'ShopLogic.GearShop(gear.id) == "HearthAndHome"', 1, true),
			"the general store lists only its own gear"
		)
		t.ok(string.find(shop, 'FireServer("Charge", id)', 1, true), "a charge sends BuyItem Charge")
		local plot = fs.readFile(dir .. "PlotUI.luau")
		t.eq(string.find(plot, "PLOT_ROW", 1, true), nil, "the list has no grow-the-plot row")
		t.ok(string.find(plot, "BlueprintBook.Allowed(", 1, true), "the list asks the server's own rule")
		t.ok(string.find(plot, 'name = "RaisePlotSize"', 1, true), "raising the plot size is in the Land panel")
	end)
end
