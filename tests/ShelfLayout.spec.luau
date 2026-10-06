--!nocheck
-- ShelfLayout: boxes are spaced by their own width, never overlap, stay on
-- their lane, and the real shops' stock fits with walking room.
return function(t)
	local ShelfLayout = t.shared("ShelfLayout")
	local BoxSize = t.shared("BoxSize")
	local StoreStock = t.shared("StoreStock")
	local GameConfig = t.shared("GameConfig")

	local lane = { name = "L", x0 = 0, x1 = 9, z0 = 0, z1 = 26, y = 3, kinds = nil }

	local function item(id, w, d, kind)
		return { id = id, kind = kind or "Axe", w = w, h = 2, d = d }
	end

	t.test("boxes sit beside each other by width and in rows by depth, none overlapping", function()
		local items = {}
		for i = 1, 6 do
			table.insert(items, item("s" .. i, 2.8, 2.2))
		end
		table.insert(items, item("big", 7, 5.6))
		table.insert(items, item("m", 3.6, 2.9))
		local spots, over = ShelfLayout.Fill({ lane }, items)
		t.eq(#over, 0)
		t.eq(#spots, #items)
		for i = 1, #spots do
			local a = spots[i]
			t.ok(a.x - a.w / 2 >= lane.x0 - 1e-6 and a.x + a.w / 2 <= lane.x1 + 1e-6, a.id .. " on the lane in x")
			t.ok(a.z - a.d / 2 >= lane.z0 - 1e-6 and a.z + a.d / 2 <= lane.z1 + 1e-6, a.id .. " on the lane in z")
			t.eq(a.y, lane.y + a.h / 2, "on the surface")
			for j = i + 1, #spots do
				t.eq(
					ShelfLayout.Overlap(a, spots[j], BoxSize.Gap),
					false,
					a.id .. " and " .. spots[j].id .. " keep the gap"
				)
			end
		end
	end)

	t.test("a wide box takes a row to itself and a narrow one fits beside another", function()
		local spots = ShelfLayout.Fill({ lane }, { item("a", 2.8, 2.2), item("b", 2.8, 2.2), item("c", 7, 5) })
		local byId = {}
		for _, s in ipairs(spots) do
			byId[s.id] = s
		end
		t.ok(math.abs(byId.a.z - byId.b.z) < 1e-9, "two small boxes share a row")
		t.ok(byId.c.z - byId.c.d / 2 > byId.a.z + byId.a.d / 2, "the wide one is in a later row")
		-- Whatever the order, a bigger box never moves its neighbours into it.
		local reversed = ShelfLayout.Fill({ lane }, { item("c", 7, 5), item("a", 2.8, 2.2), item("b", 2.8, 2.2) })
		for i = 1, #reversed do
			for j = i + 1, #reversed do
				t.eq(ShelfLayout.Overlap(reversed[i], reversed[j], 0), false)
			end
		end
	end)

	t.test("what does not fit goes to the next lane that takes its kind, then to overflow", function()
		local a = { name = "A", x0 = 0, x1 = 6, z0 = 0, z1 = 6, y = 1, kinds = { "Axe" } }
		local b = { name = "B", x0 = 10, x1 = 16, z0 = 0, z1 = 6, y = 1, kinds = { "Axe", "Gear" } }
		local items = { item("1", 4, 4), item("2", 4, 4), item("g", 4, 4, "Gear"), item("3", 4, 4) }
		local spots, over = ShelfLayout.Fill({ a, b }, items)
		local lanes = {}
		for _, s in ipairs(spots) do
			lanes[s.id] = s.lane
		end
		t.eq(lanes["1"], "A")
		t.eq(lanes["2"], "B", "lane A was full")
		t.eq(lanes["g"], nil, "lane B was full of the second axe")
		t.eq(#over, 2, "the gear and the third axe have nowhere to go")
		-- a box wider than every lane is never placed
		local _, wide = ShelfLayout.Fill({ a }, { item("w", 9, 2) })
		t.eq(#wide, 1)
	end)

	t.test("a future Large box never overlaps: add an XXL and an XXXL to the real Tool Shed lanes", function()
		local lanes = StoreStock.Lanes("ToolShed")
		local items = {}
		for _, place in ipairs(StoreStock.Placements("ToolShed")) do
			local slot = StoreStock.Get(place.slotId)
			table.insert(
				items,
				{ id = place.slotId, kind = slot.itemKind, w = place.size.X, h = place.size.Y, d = place.size.Z }
			)
		end
		local xxl = BoxSize.Class("XXL").size
		table.insert(items, { id = "future1", kind = "Machine", w = xxl.X, h = xxl.Y, d = xxl.Z })
		local spots = ShelfLayout.Fill(lanes, items)
		for i = 1, #spots do
			for j = i + 1, #spots do
				t.eq(ShelfLayout.Overlap(spots[i], spots[j], 0), false, spots[i].id .. " / " .. spots[j].id)
			end
		end
	end)

	t.test("the real shops: every box placed, on its lane, spaced by size, with an aisle", function()
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			t.eq(#StoreStock.Overflow(shop), 0, shop .. " has room for all its stock")
			t.ok(StoreStock.AisleGap(shop) >= GameConfig.ShelfAisleMin + 4, shop .. " aisle is comfortable")
			local places = StoreStock.Placements(shop)
			t.eq(#places, #StoreStock.ForShop(shop))
			local spots = {}
			for _, p in ipairs(places) do
				local d = p.count * p.size.Z + (p.count - 1) * (p.pitch - p.size.Z)
				table.insert(
					spots,
					{ id = p.slotId, lane = "", x = p.x, y = p.y, z = p.z, w = p.size.X, h = p.size.Y, d = d }
				)
			end
			for i = 1, #spots do
				for j = i + 1, #spots do
					t.eq(
						ShelfLayout.Overlap(spots[i], spots[j], BoxSize.Gap - 1e-6),
						false,
						shop .. " " .. spots[i].id .. " / " .. spots[j].id
					)
				end
			end
			for _, p in ipairs(places) do
				local slot = StoreStock.Get(p.slotId)
				t.eq(p.size, StoreStock.BoxSizeOf(slot), p.slotId)
			end
		end
	end)
end
