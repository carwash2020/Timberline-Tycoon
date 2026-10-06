--!nocheck
-- BoxSize: the size class table, the rule that picks a class, and the
-- headroom the table keeps for future Large items.
return function(t)
	local BoxSize = t.shared("BoxSize")
	local StoreStock = t.shared("StoreStock")
	local ItemCatalog = t.shared("ItemCatalog")
	local Vector2 = t.roblox.Vector2

	local function volume(size)
		return size.X * size.Y * size.Z
	end

	t.test("the shop classes grow in rank, width, height, depth and volume, and keep spare classes", function()
		local last = nil
		for i, class in ipairs(BoxSize.Classes) do
			t.eq(class.rank, i, class.id)
			t.ok(not class.vehicle, class.id)
			if last then
				t.ok(class.size.X > last.size.X and class.size.Y > last.size.Y and class.size.Z > last.size.Z, class.id)
				t.ok(volume(class.size) > volume(last.size), class.id)
				t.ok(class.maxArea > last.maxArea, class.id)
			end
			last = class
		end
		t.eq(BoxSize.Classes[#BoxSize.Classes].maxArea, math.huge, "the last class takes anything bigger")
		-- Headroom: two classes no shipping item uses yet.
		local used = {}
		for _, slot in ipairs(StoreStock.All()) do
			used[slot.boxClass] = true
		end
		t.ok(not used.XXL and not used.XXXL, "XXL and XXXL are free for the first Large items")
		t.ok(BoxSize.Class("XXL").size.X > BoxSize.Class("XL").size.X)
	end)

	t.test("a hatchet box is small, a sawmill or the chop saw is big, a vehicle box is the biggest", function()
		local steel = BoxSize.SizeFor({ kind = "Axe", price = 150 })
		t.eq(BoxSize.ClassFor({ kind = "Axe", price = 150 }).id, "S")
		t.ok(volume(steel) > 2 * 1.2 * 1.6, "much larger than the old 2 x 1.2 x 1.6 block")
		t.eq(BoxSize.ClassFor({ kind = "Axe", price = 8500 }).id, "M", "better axes get a bigger box, capped at M")
		t.eq(BoxSize.ClassFor({ kind = "Axe", price = 99999 }).id, "M")
		t.eq(BoxSize.ClassFor({ kind = "Gear", price = 120 }).id, "XS")
		t.eq(BoxSize.ClassFor({ kind = "Machine", price = 7500 }).id, "L", "the chop saw")
		local mill = ItemCatalog.GetSawmill("Millmaster200L")
		local millClass = BoxSize.ClassFor({
			kind = "Sawmill",
			price = mill.priceCash,
			footprint = Vector2.new(mill.width, mill.depth),
		})
		t.eq(millClass.id, "XL")
		t.ok(volume(millClass.size) > 4 * volume(steel))
		local biggestShop = BoxSize.Classes[#BoxSize.Classes].size
		for _, class in ipairs(BoxSize.VehicleClasses) do
			t.ok(class.vehicle, class.id)
			t.ok(volume(class.size) > volume(BoxSize.Class("XL").size), class.id .. " beats every shop box in use")
		end
		t.ok(volume(BoxSize.VehicleClasses[1].size) > volume(BoxSize.Class("XL").size))
		t.ok(biggestShop.X > 0)
	end)

	t.test("a footprint picks the class by area, the edges inclusive", function()
		local function id(w, d)
			return BoxSize.ClassFor({ kind = "Blueprint", footprint = Vector2.new(w, d) }).id
		end
		t.eq(id(2, 2), "XS")
		t.eq(id(3, 2), "XS", "area 6 is the XS edge")
		t.eq(id(4, 2), "S")
		t.eq(id(8, 8), "M", "area 64 is the M edge")
		t.eq(id(10, 8), "L")
		t.eq(id(26, 10), "XL", "the biggest sawmill, 260")
		t.eq(id(30, 10), "XXL", "past 270 the reserved class takes over")
		t.eq(id(100, 100), "XXXL")
	end)

	t.test("vehicle boxes are picked by floor area, so the Rig's is bigger than the Scout's", function()
		local scout = StoreStock.VehicleClass("Truck", "ScoutATV")
		local rig = StoreStock.VehicleClass("Truck", "LoggingRig")
		local rank = function(id)
			return BoxSize.Class(id).rank
		end
		t.ok(rank(rig) > rank(scout))
		for _, id in ipairs({ "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }) do
			t.ok(BoxSize.Class(StoreStock.VehicleClass("Truck", id)).vehicle, id)
		end
		for _, id in ipairs({ "PonyTrailer", "RanchTrailer", "HeavyHauler" }) do
			t.ok(BoxSize.Class(StoreStock.VehicleClass("Trailer", id)).vehicle, id)
		end
	end)

	t.test("every slot gets the class its data says, and prices only pick a step", function()
		for _, slot in ipairs(StoreStock.All()) do
			t.ok(BoxSize.Class(slot.boxClass).id == slot.boxClass, slot.slotId)
		end
		t.eq(StoreStock.Get("toolshed-SteelAxe").boxClass, "S")
		t.eq(StoreStock.Get("toolshed-ChopSaw").boxClass, "L")
		t.eq(StoreStock.Get("toolshed-Millmaster200L").boxClass, "XL")
		t.eq(StoreStock.Get("hearth-Lantern").boxClass, "XS")
		t.eq(BoxSize.Class("not-a-class").id, BoxSize.DefaultClass, "an unknown id falls back")
		t.eq(BoxSize.Pitch(3), 3 + BoxSize.Gap)
	end)
end
