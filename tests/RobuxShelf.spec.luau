--!nocheck
-- The gold Robux shelf: one box for every pass and pack StoreData lists, in
-- StoreData's order, from StoreData alone (no id or name is written here),
-- and nothing it does can change what MonetizationService sells or grants.
return function(t)
	local RobuxShelf = t.shared("RobuxShelf")
	local StoreData = t.shared("StoreData")
	local StoreStock = t.shared("StoreStock")
	local fs = require("@lune/fs")

	t.test("the shelf lists exactly the passes, then the packs, that StoreData lists", function()
		local list = RobuxShelf.List()
		local passes, products = StoreData.ListedPasses(), StoreData.ListedProducts()
		t.eq(#list, #passes + #products)
		t.ok(#list > 0, "something is for sale")
		for i, pass in ipairs(passes) do
			local entry = list[i]
			t.eq(entry.kind, "Pass")
			t.eq(entry.key, pass.key)
			t.eq(entry.displayName, pass.name)
		end
		for i, product in ipairs(products) do
			local entry = list[#passes + i]
			t.eq(entry.kind, "Product")
			t.eq(entry.key, product.key)
			t.eq(entry.displayName, product.name)
		end
		local seen = {}
		for _, entry in ipairs(list) do
			t.eq(entry.color, RobuxShelf.Gold)
			t.ok(not seen[entry.slotId], "slot ids are unique")
			seen[entry.slotId] = true
			t.eq(StoreStock.Get(entry.slotId), nil, "never a cash slot")
			-- BuyRobuxItem takes exactly these two strings, and MonetizationService
			-- looks them up in StoreData the same way.
			t.ok(if entry.kind == "Pass" then StoreData.Pass(entry.key) ~= nil else StoreData.Product(entry.key) ~= nil)
		end
	end)

	t.test("Find forwards only a kind and key the shelf lists", function()
		t.ok(RobuxShelf.Find("Pass", "DoubleCash") ~= nil)
		t.ok(RobuxShelf.Find("Pass", "LuxAxe") ~= nil)
		t.ok(RobuxShelf.Find("Product", "Cash1k") ~= nil)
		t.eq(RobuxShelf.Find("Pass", "Cash1k"), nil, "a pack is not a pass")
		t.eq(RobuxShelf.Find("Product", "DoubleCash"), nil)
		t.eq(RobuxShelf.Find("Pass", "Nope"), nil)
		t.eq(RobuxShelf.Find("Gift", "DoubleCash"), nil)
		t.eq(RobuxShelf.Get("robux-Pass-DoubleCash").key, "DoubleCash")
		t.eq(RobuxShelf.Get("toolshed-SteelAxe"), nil)
		-- An item whose id is still 0 (not for sale) is not on the shelf.
		for _, entry in ipairs(RobuxShelf.List()) do
			t.ok(entry.key ~= "DoubleWood" and entry.key ~= "InstantDelivery", "ids of 0 stay off the shelf")
		end
	end)

	t.test("the boxes sit in one even row on the table, which is as wide as the row needs", function()
		local places = RobuxShelf.Placements()
		t.eq(#places, #RobuxShelf.List())
		local width = RobuxShelf.RowWidth()
		for i, place in ipairs(places) do
			t.eq(place.slotId, RobuxShelf.List()[i].slotId)
			t.eq(place.z, RobuxShelf.TableZ)
			t.ok(math.abs(place.y - (RobuxShelf.TableTop + RobuxShelf.BoxHalfHeight)) < 1e-9, "on the table top")
			t.ok(math.abs(place.x) + 0.7 <= width / 2, "inside the table's width")
			if i > 1 then
				t.ok(math.abs(place.x - places[i - 1].x - RobuxShelf.Step) < 1e-9, "evenly spaced")
			end
		end
		local sum = 0
		for _, place in ipairs(places) do
			sum += place.x
		end
		t.ok(math.abs(sum) < 1e-9, "centred on the shop's middle")
	end)

	t.test("the tag says R$ until Roblox's price is known", function()
		t.eq(RobuxShelf.Tag(nil), "R$")
		t.eq(RobuxShelf.Tag(0), "R$")
		t.eq(RobuxShelf.Tag(399), "R$ 399")
		t.eq(RobuxShelf.Tag(399.9), "R$ 399")
	end)

	t.test("no Creator Hub id is written in the shelf, and the gated files are not touched by it", function()
		local source = fs.readFile("src/ReplicatedStorage/Shared/RobuxShelf.luau")
		t.eq(string.find(source, "%d%d%d%d%d%d"), nil, "no six-digit id")
		t.eq(string.find(source, "CreatorIds", 1, true), nil)
		local box = fs.readFile("src/ServerScriptService/BoxService.luau")
		-- BoxService reads StoreData for the price lookup only.
		t.ok(string.find(box, "StoreData.Pass(key)", 1, true) ~= nil)
		t.eq(string.find(box, "PromptGamePassPurchase", 1, true), nil, "the prompt stays in MonetizationService")
		t.eq(string.find(box, "PromptProductPurchase", 1, true), nil)
		t.eq(string.find(box, "ProcessReceipt", 1, true), nil)
	end)
end
