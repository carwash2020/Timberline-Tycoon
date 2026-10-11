--!nocheck
-- TownBoardLogic: the town leaderboard board's rows, states, layout and
-- placement. The board stands where WorldPlan.LeaderboardBoard says, clear
-- of every road, floor, footprint and prop in the town.
return function(t)
	local TownBoardLogic = t.shared("TownBoardLogic")
	local LeaderboardLogic = t.shared("LeaderboardLogic")
	local WorldLayout = t.shared("World/WorldLayout")
	local WorldPlan = t.shared("World/WorldPlan")
	local StoreBoard = t.shared("StoreBoard")

	local function row(rank, name, score)
		return { rank = rank, name = name, score = score }
	end

	t.test("the board lists the same ten the leaderboard keeps, in two columns of five", function()
		t.eq(TownBoardLogic.Rows, LeaderboardLogic.Size)
		t.eq(TownBoardLogic.Columns * TownBoardLogic.PerColumn, TownBoardLogic.Rows)
	end)

	t.test("loading, failed and empty each have their own line", function()
		local loading = TownBoardLogic.View(nil, false)
		t.eq(loading.state, "loading")
		t.eq(loading.message, "Loading the board...")
		local failed = TownBoardLogic.View(nil, true)
		t.eq(failed.state, "failed")
		t.eq(failed.message, "The board couldn't load. Try again soon.")
		local empty = TownBoardLogic.View({}, false)
		t.eq(empty.state, "empty")
		t.eq(empty.message, "No one is on the board yet. Turn it on in Settings, Leaderboard.")
		t.eq(#empty.lines, 0)
		t.eq(TownBoardLogic.View({}, true).state, "empty", "a list in hand wins over a failed flag")
	end)

	t.test("rows print rank, name and $X earned, with the top three flagged", function()
		local view = TownBoardLogic.View({
			row(1, "Ann", 1234567),
			row(2, "Bo", 90000),
			row(3, "Cy", 1500.9),
			row(4, "Di", 7),
		}, false)
		t.eq(view.state, "rows")
		t.eq(view.message, "")
		t.eq(view.lines[1], { rank = "1", name = "Ann", cash = "$1,234,567 earned", top = true })
		t.eq(view.lines[2].cash, "$90,000 earned")
		t.eq(view.lines[3].cash, "$1,500 earned")
		t.eq(view.lines[3].top, true)
		t.eq(view.lines[4], { rank = "4", name = "Di", cash = "$7 earned", top = false })
	end)

	t.test("only ten rows show, and odd rows are cleaned", function()
		local many = {}
		for i = 1, 14 do
			table.insert(many, row(i, "P" .. i, 1000 - i))
		end
		t.eq(#TownBoardLogic.View(many, false).lines, 10)
		local view = TownBoardLogic.View({ row(1, "", 5), row(2, string.rep("x", 40), 0 / 0) }, false)
		t.eq(view.lines[1].name, LeaderboardLogic.FallbackName)
		t.eq(utf8.len(view.lines[2].name), TownBoardLogic.NameMax, "a long name is cut, with an ellipsis")
		t.eq(view.lines[2].cash, "$0 earned", "a bad score reads $0")
	end)

	t.test("the ten slots fit the canvas, do not overlap, and the text boxes are big enough to read", function()
		local canvas = TownBoardLogic.CanvasSize
		local plates = {}
		for i = 1, TownBoardLogic.Rows do
			local slot = TownBoardLogic.Slot(i)
			for name, r in pairs(slot) do
				t.ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= canvas.X and r.y + r.h <= canvas.Y, name .. " " .. i)
			end
			local p = slot.plate
			for _, inner in ipairs({ slot.medal, slot.name, slot.cash }) do
				t.ok(inner.x >= p.x and inner.x + inner.w <= p.x + p.w, "inside its plate (x) " .. i)
				t.ok(inner.y >= p.y and inner.y + inner.h <= p.y + p.h, "inside its plate (y) " .. i)
			end
			t.ok(slot.name.y + slot.name.h <= slot.cash.y, "name above cash " .. i)
			t.ok(slot.name.x >= slot.medal.x + slot.medal.w, "name right of the medal " .. i)
			for j, q in ipairs(plates) do
				local apart = p.x + p.w <= q.x or q.x + q.w <= p.x or p.y + p.h <= q.y or q.y + q.h <= p.y
				t.ok(apart, string.format("plates %d and %d overlap", i, j))
			end
			table.insert(plates, p)
		end
		-- Ranks 1 to 5 down the left, 6 to 10 down the right.
		t.ok(TownBoardLogic.Slot(1).plate.x < TownBoardLogic.Slot(6).plate.x)
		t.eq(TownBoardLogic.Slot(1).plate.y, TownBoardLogic.Slot(6).plate.y)
		t.ok(TownBoardLogic.Slot(5).plate.y > TownBoardLogic.Slot(1).plate.y)
		-- 100 px a stud: a name is over half a stud tall, the title over a stud.
		t.ok(TownBoardLogic.NameTextPx >= 50 and TownBoardLogic.CashTextPx >= 36)
		t.ok(TownBoardLogic.TitleTextPx >= 100)
		-- The title sits above the first row.
		local title = TownBoardLogic.TitleRect()
		t.ok(title.y + title.h <= TownBoardLogic.RowsTop)
		local message = TownBoardLogic.MessageRect()
		t.ok(message.x + message.w <= canvas.X and message.y + message.h <= canvas.Y)
	end)

	t.test("the face is 100 px a stud over the whole 14 x 8 field", function()
		local size = TownBoardLogic.BoardSize
		t.eq(size.X, 14)
		t.eq(size.Y, 8)
		t.eq(TownBoardLogic.CanvasSize.X, size.X * TownBoardLogic.PxPerStud)
		t.eq(TownBoardLogic.CanvasSize.Y, size.Y * TownBoardLogic.PxPerStud)
		t.eq(TownBoardLogic.MaxDistance, 120)
		t.ok(TownBoardLogic.PartCap <= 12)
	end)

	t.test(
		"the board stands where the plan says: south-facing, between the gondola path and the Tool Shed, 8 studs off the street",
		function()
			local cf = WorldPlan.LeaderboardBoard
			t.eq(cf.Position, t.roblox.Vector3.new(-50, 0, 92))
			t.ok(cf.LookVector.Z < -0.9, "the front faces -Z, onto MainStreet")
			local x0, x1, z0, z1 = TownBoardLogic.Footprint(cf)
			local street
			local gondola
			for _, paint in ipairs(WorldLayout.TownPaint) do
				if paint.name == "MainStreet" then
					street = paint
				elseif paint.name == "GondolaPath" and paint.z0 == 82 then
					gondola = paint
				end
			end
			t.ok(street and gondola)
			t.ok(z0 - street.z1 >= 7, "the street's north edge is 8 studs south of the board's middle")
			t.ok(x0 > -62 and x1 < gondola.x0, "between the Tool Shed floor and the gondola path")
			for _, floor in ipairs(WorldLayout.TownFloors) do
				t.ok(not TownBoardLogic.Overlaps(cf, floor.x0, floor.x1, floor.z0, floor.z1), floor.name)
			end
		end
	)

	t.test("the footprint is clear of every road, path, floor, prop, lamp, sign, shop and the store board", function()
		local cf = WorldPlan.LeaderboardBoard
		local margin = 1
		for _, paint in ipairs(WorldLayout.TownPaint) do
			t.ok(not TownBoardLogic.Overlaps(cf, paint.x0, paint.x1, paint.z0, paint.z1, margin), paint.name)
		end
		local lot = WorldLayout.ParkingLot
		t.ok(not TownBoardLogic.Overlaps(cf, lot.x0, lot.x1, lot.z0, lot.z1, margin), "parking lot")
		local town = WorldPlan.Town()
		local function clear(list, what, radius)
			for _, item in ipairs(list) do
				local p = (item.cframe or item).Position
				t.ok(
					not TownBoardLogic.Overlaps(cf, p.X - radius, p.X + radius, p.Z - radius, p.Z + radius, margin),
					string.format("%s at %.1f, %.1f", what, p.X, p.Z)
				)
			end
		end
		clear(town.props, "prop", 1.5)
		clear(town.lamps, "lamp", 1)
		clear(town.signs, "sign", 1.5)
		clear(town.fences, "fence", 1.5)
		clear(town.shops, "shop", 12)
		-- The store board (its prompt too: 12 studs) is well away.
		local s0, s1, s2, s3 = StoreBoard.Footprint()
		t.ok(not TownBoardLogic.Overlaps(cf, s0 - 12, s1 + 12, s2 - 12, s3 + 12, 0), "store board and its prompt")
		-- The Tool Shed's door stays free: the shop's front is on the street side.
		local door
		for _, shop in ipairs(town.shops) do
			if shop.kind == "ToolShed" then
				door = shop.cframe.Position
			end
		end
		t.ok(door ~= nil)
		t.ok(math.abs(door.X - cf.Position.X) > 20, "the board is not by the Tool Shed door")
	end)

	t.test("Overlaps and Footprint follow the board's turn", function()
		local cf = t.roblox.CFrame.new(100, 0, 0)
		local x0, x1, z0, z1 = TownBoardLogic.Footprint(cf)
		t.ok(math.abs((x1 - x0) - (2 * TownBoardLogic.PostX + TownBoardLogic.PostWidth)) < 1e-3)
		t.ok(z1 - z0 >= TownBoardLogic.PostWidth - 1e-6)
		t.ok(TownBoardLogic.Overlaps(cf, 100, 101, 0, 1))
		t.ok(not TownBoardLogic.Overlaps(cf, 120, 130, 0, 1))
		t.ok(TownBoardLogic.Overlaps(cf, x1 + 0.5, x1 + 2, -1, 1, 1), "a margin counts")
		local turned = t.roblox.CFrame.new(100, 0, 0) * t.roblox.CFrame.Angles(0, math.pi / 2, 0)
		local a0, a1, b0, b1 = TownBoardLogic.Footprint(turned)
		t.ok(
			(b1 - b0) > (a1 - a0) and math.abs((b1 - b0) - (x1 - x0)) < 1e-3,
			"turned a quarter, the long side runs along Z"
		)
	end)
end
