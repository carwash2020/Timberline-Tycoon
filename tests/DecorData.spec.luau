--!nocheck
-- Furniture (DecorData) and the wired pieces (LogicItems) as blueprints:
-- well formed, cheap, small, placeable through PlotLogic, and sold boxed at
-- Hearth & Home without crowding its shelf.
return function(t)
	local DecorData = t.shared("DecorData")
	local LogicItems = t.shared("LogicItems")
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local StoreStock = t.shared("StoreStock")
	local GameConfig = t.shared("GameConfig")
	local BlueprintModels = t.shared("BlueprintModels")

	local MAX_BOXES = 5
	local MAX_PRICE = 200 -- the dearest older decor (the Flag)
	local SHELF_SLOTS = 20 -- ten a side on Hearth & Home's 19.6-stud shelves

	local function all()
		local out = {}
		for _, bp in ipairs(DecorData) do
			table.insert(out, bp)
		end
		for _, bp in ipairs(LogicItems) do
			table.insert(out, bp)
		end
		return out
	end

	t.test("every piece is in PlotData, once, with the fields PlotLogic needs", function()
		local seen = {}
		for _, bp in ipairs(all()) do
			t.ok(not seen[bp.id], "duplicate " .. bp.id)
			seen[bp.id] = true
			t.eq(PlotData.Blueprint(bp.id), bp, bp.id)
			t.eq(PlotLogic.Blueprint(bp.id), bp, bp.id)
			t.eq(bp.category, "Decor", bp.id)
			t.eq(bp.tier, 1, bp.id)
			t.ok(bp.priceCash > 0 and bp.priceCash <= MAX_PRICE, bp.id .. " price")
			t.eq(bp.kit, nil, bp.id .. " is not a plank kit")
			t.eq(bp.woodUnits, nil, bp.id .. " takes no gathered material")
			t.ok(#bp.boxes >= 1 and #bp.boxes <= MAX_BOXES, bp.id .. " part budget")
			t.ok(bp.footprint.X <= 6 and bp.footprint.Y <= 6, bp.id .. " footprint")
		end
		t.eq(#all(), 9)
	end)

	t.test("the older blueprints keep their ids and prices", function()
		local expect = { Bench = 80, LampPost = 120, Flag = 200, Mailbox = 80, Shed = 600, Cabin = 2000 }
		for id, price in pairs(expect) do
			t.eq(PlotData.Blueprint(id).priceCash, price, id)
		end
	end)

	t.test("each box stays inside its footprint, on or above the ground", function()
		for _, bp in ipairs(all()) do
			for i, box in ipairs(bp.boxes) do
				local where = bp.id .. " box " .. i
				t.ok(box.offset.Y - box.size.Y / 2 >= -1e-6, where .. " sinks")
				t.ok(math.abs(box.offset.X) + box.size.X / 2 <= bp.footprint.X / 2 + 0.3, where .. " x")
				t.ok(math.abs(box.offset.Z) + box.size.Z / 2 <= bp.footprint.Y / 2 + 0.3, where .. " z")
				t.ok(
					pcall(function()
						return t.roblox.Enum.Material[box.material]
					end),
					where .. " material"
				)
			end
		end
	end)

	t.test("PlotLogic places a piece on the Campsite and refuses one past the edge", function()
		for _, bp in ipairs(all()) do
			local ok = PlotLogic.Check(bp, 0, 0, 0, 1, {})
			t.eq(ok, true, bp.id)
			local far = PlotLogic.Check(bp, 200, 0, 0, 1, {})
			t.eq(far, false, bp.id .. " outside")
		end
		local table_ = PlotData.Blueprint("Table")
		local placed = { { uid = "a", blueprintId = "Table", x = 0, z = 0, rot = 0 } }
		t.eq(PlotLogic.Check(table_, 2, 0, 0, 1, placed), false, "overlap")
		t.eq(PlotLogic.Check(table_, 4, 0, 0, 1, placed), true, "side by side")
	end)

	t.test("unlock pieces are Hearth & Home boxes, and the shelf still has room", function()
		local hearth = StoreStock.ForShop("HearthAndHome")
		t.ok(#hearth <= SHELF_SLOTS, "Hearth & Home has " .. #hearth .. " boxes")
		for _, id in ipairs({
			"Table",
			"Chair",
			"Bookshelf",
			"Rug",
			"Barrel",
			"Crate",
			"FirePit",
			"SparkSwitch",
			"SparkLamp",
		}) do
			local slot = StoreStock.FindInShop("HearthAndHome", id)
			t.ok(slot ~= nil, id .. " is on the shelf")
			t.eq(slot.itemKind, "Blueprint", id)
		end
		for _, id in ipairs({ "Bookshelf", "Rug", "Barrel", "Crate", "FirePit" }) do
			t.eq(StoreStock.UnitPrice("Blueprint", id, false, 2), PlotData.Blueprint(id).priceCash, id)
		end
		t.eq(StoreStock.UnitPrice("Blueprint", "Bookshelf", false, 2), 140)
		t.eq(StoreStock.UnitPrice("Blueprint", "FirePit", false, 2), 110)
		t.eq(StoreStock.UnitPrice("Blueprint", "Table", false, 2), 90)
		t.eq(StoreStock.UnitPrice("Blueprint", "SparkLamp", false, 2), 150)
		t.ok(StoreStock.BoxCount() <= GameConfig.StorePartBudget)
	end)

	t.test("selling an unlock piece refunds nothing, a kit piece half", function()
		t.eq(PlotLogic.SellPlan(PlotData.Blueprint("Table"), { uid = "a" }).cash, 0)
		t.eq(PlotLogic.SellPlan(PlotData.Blueprint("Bookshelf"), { uid = "a" }).cash, 0)
		t.eq(PlotLogic.SellPlan(PlotData.Blueprint("Wall"), { uid = "a" }).cash > 0, true, "kit pieces still pay half")
	end)

	t.test("the models build with one part per box and a light only where authored", function()
		for _, bp in ipairs(all()) do
			local model = BlueprintModels.Build(bp, false)
			local parts, lights = 0, 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Root" then
					parts += 1
				elseif d:IsA("PointLight") then
					lights += 1
				end
			end
			t.eq(parts, #bp.boxes, bp.id)
			local want = 0
			for _, box in ipairs(bp.boxes) do
				want += if box.light then 1 else 0
			end
			t.eq(lights, want, bp.id .. " lights")
			t.ok(want <= 1, bp.id .. " at most one light")
		end
	end)
end
