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

	t.test("a future biggest-allowed box never overlaps: add one to the real Tool Shed lanes", function()
		local lanes = StoreStock.Lanes("ToolShed")
		local items = {}
		for _, place in ipairs(StoreStock.Placements("ToolShed")) do
			local slot = StoreStock.Get(place.slotId)
			table.insert(
				items,
				{ id = place.slotId, kind = slot.itemKind, w = place.size.X, h = place.size.Y, d = place.size.Z }
			)
		end
		local max = BoxSize.MaxFor("Sawmill")
		table.insert(items, { id = "future1", kind = "Machine", w = max.X, h = max.Y, d = max.Z })
		local spots = ShelfLayout.Fill(lanes, items)
		for i = 1, #spots do
			for j = i + 1, #spots do
				t.eq(ShelfLayout.Overlap(spots[i], spots[j], 0), false, spots[i].id .. " / " .. spots[j].id)
			end
		end
	end)

	t.test("a stepped lane lifts each row a little over the one in front, up to its limit", function()
		local stepped = { name = "S", x0 = 0, x1 = 9, z0 = 0, z1 = 40, y = 3, kinds = nil, step = 0.25, maxRise = 0.6 }
		local items = {}
		for i = 1, 6 do
			table.insert(items, { id = "b" .. i, kind = "Axe", w = 7, h = 2, d = 3 })
		end
		local spots = ShelfLayout.Fill({ stepped }, items)
		t.eq(#spots, 6)
		for i, spot in ipairs(spots) do
			t.eq(spot.row, i)
			t.ok(math.abs(spot.y - (3 + math.min(0.25 * (i - 1), 0.6) + 1)) < 1e-9, "row " .. i .. " is on its step")
		end
		t.eq(ShelfLayout.Rise(stepped, 1), 0)
		t.eq(ShelfLayout.Rise(stepped, 2), 0.25)
		t.eq(ShelfLayout.Rise(stepped, 9), 0.6, "the back rows stop rising")
		t.eq(ShelfLayout.Rise(lane, 5), 0, "a flat lane never rises")
	end)

	t.test(
		"the real shops: every box placed, on its lane and its step, spaced by size, none leaving the shelf",
		function()
			for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
				t.eq(#StoreStock.Overflow(shop), 0, shop .. " has room for all its stock")
				t.ok(StoreStock.AisleGap(shop) >= GameConfig.ShelfAisleMin + 4, shop .. " aisle is comfortable")
				local places = StoreStock.Placements(shop)
				t.eq(#places, #StoreStock.ForShop(shop))
				local lanes = {}
				for _, l in ipairs(StoreStock.Lanes(shop)) do
					lanes[l.name] = l
				end
				local spots = {}
				for _, p in ipairs(places) do
					local d = p.count * p.size.Z + (p.count - 1) * (p.pitch - p.size.Z)
					table.insert(spots, {
						id = p.slotId,
						lane = p.lane,
						row = p.row,
						x = p.x,
						y = p.y,
						z = p.z,
						w = p.size.X,
						h = p.size.Y,
						d = d,
					})
					-- On its lane, a gap in from every edge.
					local l = lanes[p.lane]
					t.ok(l ~= nil, p.slotId .. " is on a real lane")
					t.ok(
						p.x - p.size.X / 2 >= l.x0 + BoxSize.EdgeGap - 1e-6,
						p.slotId .. " inside the lane's west edge"
					)
					t.ok(
						p.x + p.size.X / 2 <= l.x1 - BoxSize.EdgeGap + 1e-6,
						p.slotId .. " inside the lane's east edge"
					)
					t.ok(p.z - d / 2 >= l.z0 + BoxSize.EdgeGap - 1e-6, p.slotId .. " inside the lane's front edge")
					t.ok(p.z + d / 2 <= l.z1 + 1e-6, p.slotId .. " inside the lane's back edge")
					-- On its step and its plinth, a little higher the further back it is.
					local rise = ShelfLayout.Rise(l, p.row)
					t.ok(math.abs(p.surface - (l.y + rise)) < 1e-9, p.slotId .. " step height")
					t.ok(
						math.abs(p.y - (p.surface + StoreStock.PlinthHeight + p.size.Y / 2)) < 1e-9,
						p.slotId .. " on its plinth"
					)
					t.ok(rise <= StoreStock.MaxRise + 1e-9, p.slotId .. " a gentle step")
				end
				for i = 1, #spots do
					for j = i + 1, #spots do
						t.eq(
							ShelfLayout.Overlap(spots[i], spots[j], BoxSize.Gap - 1e-6),
							false,
							shop .. " " .. spots[i].id .. " / " .. spots[j].id
						)
						-- Nor do their plinths (a block a quarter stud bigger than the box all round).
						t.eq(
							ShelfLayout.Overlap(spots[i], spots[j], 2 * StoreStock.PlinthMargin + 0.05),
							false,
							shop .. " plinths " .. spots[i].id .. " / " .. spots[j].id
						)
					end
				end
				-- Rows stand higher toward the back (+Z) within a lane.
				for _, a in ipairs(places) do
					for _, b in ipairs(places) do
						if a.lane == b.lane and a.row < b.row then
							t.ok(
								a.surface <= b.surface + 1e-9,
								a.slotId .. " is not higher than " .. b.slotId .. " behind it"
							)
							t.ok(a.z < b.z, a.slotId .. " is in front of " .. b.slotId)
						end
					end
					local slot = StoreStock.Get(a.slotId)
					t.eq(a.size, StoreStock.BoxSizeOf(slot), a.slotId)
				end
			end
		end
	)

	t.test("the tallest box stays under the hanging lamps", function()
		-- The Tool Shed's lamps hang their lanterns to 10.4 studs; the General Store's from 14.4.
		local limit = { ToolShed = 10.2, HearthAndHome = 12 }
		for shop, top in pairs(limit) do
			for _, p in ipairs(StoreStock.Placements(shop)) do
				t.ok(
					p.y + p.size.Y / 2 <= top,
					string.format("%s %s tops out at %.1f", shop, p.slotId, p.y + p.size.Y / 2)
				)
			end
		end
	end)
end
