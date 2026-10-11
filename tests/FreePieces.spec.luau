--!nocheck
-- Lane F: blueprints for free pieces. A piece PlotLogic.FreeToPlace allows (a
-- store unlock you own) is marked "Free" in the book, places for nothing, and
-- sells for $0: it can never turn into cash or wood.
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BlueprintBook = t.shared("BlueprintBook")

	local function free()
		local out = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			if PlotLogic.FreeToPlace(bp) then
				table.insert(out, bp)
			end
		end
		return out
	end

	t.test("there are free pieces, and none of them is a kit piece or a granted one", function()
		local list = free()
		t.ok(#list >= 10, "the store unlocks")
		for _, bp in ipairs(list) do
			t.ok(bp.kit ~= true and bp.granted ~= true, bp.id)
			t.eq(PlotLogic.PlacePrice(bp, true), 0, bp.id .. " places free once you own it")
			t.eq(PlotLogic.PlacePrice(bp, false), nil, bp.id .. " is not placeable before you own it")
		end
	end)

	t.test("an owned free piece shows as Free in the book and places with no price", function()
		for _, bp in ipairs(free()) do
			local entry = { id = bp.id, bp = bp, group = BlueprintBook.Group(bp), stock = 0 }
			local row = BlueprintBook.Row(entry, { tier = 9, cash = 0, boxed = false })
			t.eq(row.own, "· Free", bp.id)
			t.eq({ row.ready, row.state, row.button }, { true, "buy", "Place" }, bp.id .. " needs no cash")
		end
		-- A paid piece is not marked.
		local wall = PlotData.Blueprint("Wall4")
		local row = BlueprintBook.Row(
			{ id = "Wall4", bp = wall, group = "Buildings", stock = 0 },
			{ tier = 9, cash = 1000, boxed = false }
		)
		t.eq(row.own, nil)
	end)

	t.test("a free piece sells for $0: never cash, never wood, even inside the undo window", function()
		for _, bp in ipairs(free()) do
			local item = { uid = "x", blueprintId = bp.id, x = 0, z = 0, rot = 0 }
			for _, undo in ipairs({ false, true }) do
				local plan = PlotLogic.SellPlan(bp, item, undo)
				t.eq(plan.cash, 0, bp.id .. " cash")
				t.eq(plan.planks, 0, bp.id .. " wood")
				t.eq(plan.slabs, nil)
				t.eq(plan.ingots, nil)
			end
			t.eq(PlotLogic.SellValue(bp), 0, bp.id)
		end
	end)
end
