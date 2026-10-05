--!nocheck
-- Shelf stock: aisles, the lamp pool, and the part budget.
return function(t)
	local GameConfig = t.shared("GameConfig")
	local StoreStock = t.shared("StoreStock")
	local BoxLogic = t.shared("BoxLogic")

	local function partsOf(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end

	local function boxesOf(shop)
		local n = 0
		for _, slot in ipairs(StoreStock.ForShop(shop)) do
			n += if slot.limited then GameConfig.LimitedStockCount else 1
		end
		return n
	end

	t.test("aisles clear six studs and the box count stays in the store budget", function()
		t.ok(StoreStock.AisleGap("ToolShed") >= GameConfig.ShelfAisleMin)
		t.ok(StoreStock.AisleGap("HearthAndHome") >= GameConfig.ShelfAisleMin)
		t.ok(StoreStock.BoxCount() <= GameConfig.StorePartBudget)
		t.ok(StoreStock.BoxCount() > 0)
		t.eq(GameConfig.LimitedStockCount, 3)
		t.eq(GameConfig.LimitedRestockSec, 1200)
		t.eq(GameConfig.LimitedPerPlayer, 1)
		t.eq(GameConfig.LimitedItemPrice, 750)
		t.eq(StoreStock.UnitPrice("Cosmetic", "LampPost", true, 2), 750)
		t.eq(StoreStock.UnitPrice("Axe", "SteelAxe", false, 2), 160)
		t.eq(StoreStock.UnitPrice("Axe", "SteelAxe", true, 2), 750, "a limited flag ignores the offer")
		local left, clock = StoreStock.Sign(2, 3, 90)
		t.eq(left, "2 of 3 left")
		t.eq(clock, "1:30")
	end)

	t.test("two buyers cannot both take the last lamp, and a restock refills it", function()
		StoreStock.Reset(0)
		t.eq(StoreStock.Left(), 3)
		t.eq(StoreStock.TryClaim(1, 0), true)
		t.eq(StoreStock.TryClaim(2, 0), true)
		t.eq(StoreStock.Left(), 1)
		local a, whyA = StoreStock.TryClaim(3, 0)
		local b, whyB = StoreStock.TryClaim(4, 0)
		t.eq(a, true)
		t.eq(whyA, nil)
		t.eq(b, false)
		t.eq(whyB, "missing")
		t.eq(StoreStock.Left(), 0)
		local again, why = StoreStock.TryClaim(3, 0)
		t.eq(again, false)
		t.eq(why, "alreadyOwned")
		t.eq(StoreStock.Left(), 0)
		t.eq(StoreStock.Restock(1199), false)
		t.eq(StoreStock.Restock(1200), true)
		t.eq(StoreStock.Left(), 3)
		t.eq(StoreStock.TryClaim(3, 1200), true, "the per-player mark cleared")
	end)

	t.test("shelves are attachments, and shelves plus boxes stay within 250", function()
		local BuildingArt = t.shared("Art/BuildingArt")
		local Color3 = t.roblox.Color3
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			local model = BuildingArt.Shop(shop, shop, Color3.fromRGB(90, 60, 40))
			local rx, ry, rz = model:GetPivot():ToOrientation()
			t.ok(math.abs(rx) < 1e-3 and math.abs(ry) < 1e-3 and math.abs(rz) < 1e-3, shop .. " pivot")
			local slots = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == "ShelfSlot" then
					slots += 1
				end
			end
			t.eq(slots, #StoreStock.ForShop(shop), shop)
			local zone = StoreStock.Zone(shop)
			local scale = BuildingArt.Scale[shop]
			t.eq(model:GetAttribute("ZoneSizeX"), zone.size.X * scale)
			t.eq(model:GetAttribute("ZoneSizeZ"), zone.size.Z * scale)
			t.ok(partsOf(model) + boxesOf(shop) <= GameConfig.StorePartBudget, shop)
			t.ok(BoxLogic.BoxPartCap <= 6)
		end
		local lot = BuildingArt.Shop("Dealership", "Dale", Color3.fromRGB(40, 70, 110))
		local slots = 0
		for _, d in ipairs(lot:GetDescendants()) do
			if d.Name == "ShelfSlot" then
				slots += 1
			end
		end
		t.eq(slots, 0, "the dealership board is not a shelf")
	end)

	t.test("T2: box prices are the catalog v2 prices, with no second table", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ReplicatedStorage/Shared/StoreStock.luau")
		t.eq(string.find(source, "VEHICLES", 1, true), nil)
		local ids = { "Pickup", "ScoutATV", "Flatbed", "LoggingRig", "PonyTrailer", "RanchTrailer", "HeavyHauler" }
		for _, id in ipairs(ids) do
			local truck = ItemCatalog.GetTruck(id)
			local trailer = ItemCatalog.GetTrailer(id)
			local item = truck or trailer
			local kind = if truck then "Truck" else "Trailer"
			t.eq(StoreStock.UnitPrice(kind, id, false, 2), item.v2.price, id)
			t.eq(item.v2.price, ItemCatalog.GetTruck(id) and ItemCatalog.GetTruck(id).v2.price or item.v2.price)
		end
		t.eq(StoreStock.UnitPrice("Truck", "Pickup", false, 2), 400)
		t.eq(StoreStock.UnitPrice("Truck", "Flatbed", false, 2), 5000)
		t.eq(StoreStock.UnitPrice("Truck", "LoggingRig", false, 2), 19000)
		t.eq(StoreStock.UnitPrice("Truck", "Rustbucket", false, 2), 75)
		t.eq(StoreStock.ForShop("Dealership"), {})
	end)

	t.test("the chop saw is a Tool Shed box at its catalog price", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local slot = StoreStock.Get("toolshed-ChopSaw")
		t.ok(slot ~= nil, "a shelf slot")
		t.eq(slot.shop, "ToolShed")
		t.eq(slot.itemKind, "Machine")
		t.eq(slot.itemId, "ChopSaw")
		t.eq(slot.limited, false)
		t.eq(StoreStock.UnitPrice("Machine", "ChopSaw", false, 2), ItemCatalog.ChopSawPrice)
		t.eq(StoreStock.UnitPrice("Machine", "ChopSaw", false, 2), 7500)
		t.eq(StoreStock.UnitPrice("Machine", "Nope", false, 2), nil)
		t.ok(StoreStock.FindInShop("ToolShed", "ChopSaw") ~= nil)
	end)

	t.test("every box stands inside its shop's zone, with room to walk the aisle carrying one", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local RobuxShelf = t.shared("RobuxShelf")
		-- A person (2 wide) holding a box (2 wide) out in front: 4 studs, and
		-- a stud either side. The tables (2.9 wide) or shelves (4.8) under
		-- the boxes take their width off the aisle.
		local CARRY = 6
		for shop, tableWidth in pairs({ ToolShed = 2.9, HearthAndHome = 4.8 }) do
			local zone = StoreStock.Zone(shop)
			local scale = BuildingArt.Scale[shop]
			for _, place in ipairs(StoreStock.Placements(shop)) do
				t.ok(math.abs(place.x) + 1 <= zone.size.X / 2, shop .. " " .. place.slotId .. " in x")
				t.ok(math.abs(place.z) + 1 <= zone.size.Z / 2, shop .. " " .. place.slotId .. " in z")
			end
			local aisle = StoreStock.AisleGap(shop) * scale - tableWidth
			t.ok(aisle >= CARRY, string.format("%s aisle is %.1f studs between the tables", shop, aisle))
		end
		for _, place in ipairs(RobuxShelf.Placements()) do
			local zone = StoreStock.Zone("ToolShed")
			t.ok(math.abs(place.x) + 1 <= zone.size.X / 2, place.slotId .. " in x")
			t.ok(place.z + 1 <= zone.size.Z / 2, place.slotId .. " in z")
		end
	end)

	t.test("the Tool Shed's gold slots are their own attachments, and the whole shop stays within 250 parts", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local RobuxShelf = t.shared("RobuxShelf")
		local model = BuildingArt.Shop("ToolShed", "TOOL SHED", t.roblox.Color3.fromRGB(150, 62, 44))
		local gold, cash = 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "RobuxSlot" then
				gold += 1
			elseif d.Name == "ShelfSlot" then
				cash += 1
			end
		end
		t.eq(gold, #RobuxShelf.List())
		t.eq(cash, #StoreStock.ForShop("ToolShed"))
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		t.ok(parts + boxesOf("ToolShed") + gold <= GameConfig.StorePartBudget, "parts, cash boxes and gold boxes")
		local hearth = BuildingArt.Shop("HearthAndHome", "STORE", t.roblox.Color3.fromRGB(122, 90, 60))
		for _, d in ipairs(hearth:GetDescendants()) do
			t.ok(d.Name ~= "RobuxSlot", "no gold shelf at Hearth & Home")
		end
	end)
end
