--!nocheck
-- ShelfLayout: boxes are spaced by their own width, never overlap, stay on
-- their lane, and the real shops' stock fits with walking room.
return function(t)
	local ShelfLayout = t.shared("ShelfLayout")
	local BoxSize = t.shared("BoxSize")
	local StoreStock = t.shared("StoreStock")
	local GameConfig = t.shared("GameConfig")

	local lane = { name = "L", x0 = 0, x1 = 9, z0 = 0, z1 = 36, y = 3, kinds = nil }

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
				t.eq(ShelfLayout.Apart(a, spots[j]), true, a.id .. " and " .. spots[j].id .. " keep the gap")
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

	t.test("Connor: space the boxes out. 1.5 studs side by side, 2.5 between rows, on every shelf", function()
		t.ok(BoxSize.Gap >= 1.5, "at least 1.5 studs between boxes in a row")
		t.ok(BoxSize.RowGap >= 2.5, "about 2.5 studs between rows")
		t.eq(BoxSize.Pitch(3), 3 + BoxSize.RowGap)
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			local places = StoreStock.Placements(shop)
			local sideBySide, rowsApart = 0, 0
			for i = 1, #places do
				for j = i + 1, #places do
					local a, b = places[i], places[j]
					if a.lane ~= b.lane then
						continue
					end
					local ad = a.count * a.size.Z + (a.count - 1) * (a.pitch - a.size.Z)
					local bd = b.count * b.size.Z + (b.count - 1) * (b.pitch - b.size.Z)
					if a.row == b.row then
						sideBySide += 1
						local gap = math.abs(a.x - b.x) - (a.size.X + b.size.X) / 2
						t.ok(
							gap >= BoxSize.Gap - 1e-6,
							string.format("%s %s / %s are %.2f apart", shop, a.slotId, b.slotId, gap)
						)
						-- and their plinths (a quarter stud bigger each side) are a stud apart
						t.ok(gap - 2 * StoreStock.PlinthMargin >= 1 - 1e-6, a.slotId .. " plinths clear")
					else
						rowsApart += 1
						local gap = math.abs(a.z - b.z) - (ad + bd) / 2
						t.ok(
							gap >= BoxSize.RowGap - 1e-6,
							string.format("%s %s / %s rows are %.2f apart", shop, a.slotId, b.slotId, gap)
						)
					end
				end
			end
			t.ok(rowsApart > 0, shop .. " has rows")
			t.ok(sideBySide > 0, shop .. " has boxes side by side somewhere")
			t.ok(StoreStock.AisleGap(shop) >= 10, shop .. " keeps a 10-stud aisle")
			t.eq(#StoreStock.Overflow(shop), 0, shop .. " keeps every item on a shelf")
			-- Every box is on a lane inside the shop it is in (BuildingArt's frame).
			local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
			local frame = BuildingArt.InteriorFrame(shop, BuildingArt.Scale[shop]).frame
			for _, l in ipairs(StoreStock.Lanes(shop)) do
				t.ok(l.x0 >= -frame.halfW and l.x1 <= frame.halfW, shop .. " " .. l.name .. " is inside the walls in x")
				t.ok(l.z0 >= -frame.halfD and l.z1 <= frame.halfD, shop .. " " .. l.name .. " is inside the walls in z")
			end
		end
		-- The widest shelf box and a carrier still walk the aisle (the carry spec's rule).
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			for _, p in ipairs(StoreStock.Placements(shop)) do
				t.ok(p.size.X + 2 <= StoreStock.AisleGap(shop), p.slotId .. " carried down the aisle")
			end
		end
	end)

	t.test("the gold Robux table keeps the same spacing and fits the Tool Shed", function()
		local RobuxShelf = t.shared("RobuxShelf")
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local width = BoxSize.Class(RobuxShelf.Class).size.X
		t.ok(RobuxShelf.Step - width >= BoxSize.Gap - 1e-6, "boxes on the gold table are a gap apart")
		local frame = BuildingArt.InteriorFrame("ToolShed", BuildingArt.Scale.ToolShed).frame
		t.ok(
			RobuxShelf.RowWidth() <= 2 * frame.halfW,
			"the gold row fits between the walls (more than six passes need a second row)"
		)
		t.ok(RobuxShelf.TableZ + RobuxShelf.TableDepth / 2 <= frame.halfD, "the gold table is inside the back wall")
		-- It stands behind the lanes' ends.
		for _, l in ipairs(StoreStock.Lanes("ToolShed")) do
			t.ok(RobuxShelf.TableZ - RobuxShelf.TableDepth / 2 >= l.z1 - 1e-6, l.name .. " ends before the gold table")
		end
	end)

	t.test("the axe rack's blocks are 1.5 studs apart and inside the walls", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
		local shed = BuildingArt.Shop("ToolShed", "TOOL SHED", t.roblox.Color3.fromRGB(150, 62, 44))
		local blocks = {}
		for _, d in ipairs(shed:GetDescendants()) do
			if d.Name == "AxeBlock" then
				table.insert(blocks, d)
			end
		end
		t.ok(#blocks >= 7, "a block for every axe sold")
		table.sort(blocks, function(a, b)
			return a.CFrame.Position.X < b.CFrame.Position.X
		end)
		local frame = BuildingArt.InteriorFrame("ToolShed", BuildingArt.Scale.ToolShed).frame
		for i, b in ipairs(blocks) do
			t.ok(
				math.abs(b.CFrame.Position.X) + b.Size.X / 2 <= frame.halfW,
				"block " .. i .. " is inside the side walls"
			)
			if i > 1 then
				local gap = b.CFrame.Position.X
					- blocks[i - 1].CFrame.Position.X
					- (b.Size.X + blocks[i - 1].Size.X) / 2
				t.ok(
					gap >= ShopInterior.RackGap - 1e-6,
					string.format("blocks %d and %d are %.2f apart", i - 1, i, gap)
				)
			end
		end
		t.ok(ShopInterior.RackGap >= 1.5)
	end)

	t.test(
		"the showroom's boxes are far apart already: well over a gap side by side, the aisle between the rows",
		function()
			local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
			local layout = DealershipLot.Layout()
			local prev = nil
			for _, bay in ipairs(layout.bays) do
				if prev and prev.row == bay.row then
					local gap = (bay.x - prev.x) - (bay.box.X + prev.box.X) / 2
					t.ok(gap >= BoxSize.Gap, prev.id .. " and " .. bay.id .. " boxes are " .. gap .. " apart")
					t.ok(
						bay.x - prev.x - (bay.width + prev.width) / 2 >= DealershipLot.BayGap - 1e-6,
						"and so are the plinths"
					)
				end
				prev = bay
			end
			t.ok(DealershipLot.Aisle >= 12, "the walkway between the rows")
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
