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
end
