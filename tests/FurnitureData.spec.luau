--!nocheck
-- Lane F: the crafted furniture (Copper Lamp Post, Gold-banded Chest). At most
-- 12 parts each, sized to the uploaded meshes, never sold, never a starter plan,
-- and small parts cast no shadow.
return function(t)
	local FurnitureData = t.shared("FurnitureData")
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BlueprintBook = t.shared("BlueprintBook")
	local BlueprintModels = t.shared("BlueprintModels")
	local SawmillLogic = t.shared("SawmillLogic")
	local CraftData = t.load("ReplicatedStorage/Shared/Mining/CraftData")

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	t.test("two pieces, in PlotData, as Decor that is granted and never for sale", function()
		t.eq(#FurnitureData.Pieces, 2)
		for _, id in ipairs({ "CopperLampPost", "GoldChest" }) do
			local piece = bp(id)
			t.ok(piece ~= nil, id .. " is a blueprint")
			t.eq(piece.category, "Decor")
			t.eq(piece.granted, true)
			t.eq(piece.priceCash, 0, "never sold")
			t.eq(piece.unlock, nil, "not a store unlock")
			t.eq(piece.kit, nil)
			t.eq(BlueprintBook.IsStarter(piece), false, id .. " is not a starter plan")
			t.eq(BlueprintBook.IsGranted(id), true)
			t.eq(PlotLogic.SellPlan(piece, { uid = "a" }).cash, 0, "and sells for nothing")
		end
		t.eq(FurnitureData.IsGranted("Table"), false)
		t.eq(FurnitureData.IsGranted(nil), false)
	end)

	t.test("at most 12 parts, inside their footprint, on the 2-stud grid", function()
		for _, piece in ipairs(FurnitureData.Pieces) do
			t.ok(
				#piece.boxes >= 1 and #piece.boxes <= FurnitureData.MaxBoxes,
				piece.id .. " has " .. #piece.boxes .. " parts"
			)
			for i, box in ipairs(piece.boxes) do
				local hx, hz = piece.footprint.X / 2, piece.footprint.Y / 2
				t.ok(math.abs(box.offset.X) + box.size.X / 2 <= hx + 0.101, piece.id .. " part " .. i .. " inside X")
				t.ok(math.abs(box.offset.Z) + box.size.Z / 2 <= hz + 0.201, piece.id .. " part " .. i .. " inside Z")
			end
		end
	end)

	t.test("sized to the uploaded meshes' bounding boxes (stats.json)", function()
		local function top(piece)
			local y = 0
			for _, box in ipairs(piece.boxes) do
				y = math.max(y, box.offset.Y + box.size.Y / 2)
			end
			return y
		end
		-- Copper Lamp Post: 7.075 tall; Gold Chest: 2.68 tall and 3.35 wide.
		t.ok(math.abs(top(bp("CopperLampPost")) - 7.075) < 0.3, "the post's height")
		t.ok(math.abs(top(bp("GoldChest")) - 2.68) < 0.1, "the chest's height")
		local wide = 0
		for _, box in ipairs(bp("GoldChest").boxes) do
			wide = math.max(wide, box.size.X)
		end
		t.ok(math.abs(wide - 3.4) < 0.1, "the chest's width")
		t.eq({ bp("CopperLampPost").footprint.X, bp("CopperLampPost").footprint.Y }, { 2, 3 })
		t.eq({ bp("GoldChest").footprint.X, bp("GoldChest").footprint.Y }, { 4, 3 })
	end)

	t.test("the lamp lights; parts under one stud cast no shadow, bigger ones do", function()
		local lit = 0
		for _, box in ipairs(bp("CopperLampPost").boxes) do
			if box.light then
				lit += 1
			end
		end
		t.eq(lit, 1, "one glowing lantern")
		for _, id in ipairs({ "CopperLampPost", "GoldChest" }) do
			local model = BlueprintModels.Build(bp(id), false)
			local small, big = 0, 0
			for _, part in ipairs(model:GetChildren()) do
				if part.Name ~= "Root" and part:IsA("BasePart") then
					local least = math.min(part.Size.X, part.Size.Y, part.Size.Z)
					if least < 1 then
						small += 1
						t.eq(part.CastShadow, false, id .. " " .. part.Name .. " is under a stud")
					else
						big += 1
						t.ok(part.CastShadow ~= false, id .. " " .. part.Name .. " keeps its shadow")
					end
				end
			end
			t.ok(small > 0, id .. " has parts under a stud")
			if id == "GoldChest" then
				t.ok(big > 0, "the chest's body is bigger than a stud and keeps its shadow")
			end
		end
	end)

	t.test("a crafted piece in stock shows in the hammer's list and the book never learns it", function()
		local book = BlueprintBook.Starter()
		t.eq(table.find(book, "CopperLampPost"), nil)
		t.eq(BlueprintBook.Learn(book, "CopperLampPost"), false, "Learn refuses a granted piece")
		t.eq(BlueprintBook.LearnWithFamily(book, "GoldChest"), false)
		t.eq({ BlueprintBook.Allowed("GoldChest", true, 0, false) }, { false, "grant" }, "no stock, no placing")
		t.eq({ BlueprintBook.Allowed("GoldChest", false, 1, false) }, { true, nil }, "one in stock places")
		t.ok(BlueprintBook.Message("grant", bp("GoldChest")):find("Craft the Gold-banded Chest", 1, true) ~= nil)
		local entries = BlueprintBook.Entries(book, { GoldChest = 2 })
		local found
		for _, entry in ipairs(entries) do
			if entry.id == "GoldChest" then
				found = entry
			end
		end
		t.ok(found ~= nil and found.stock == 2, "it shows with its count")
		local row = BlueprintBook.Row(found, { tier = 1, cash = 0, boxed = false })
		t.eq({ row.ready, row.state, row.own }, { true, "buy", "· 2 in stock" })
		t.eq(row.button, "Place", "free: no price on the button")
		local without = BlueprintBook.Entries(book, {})
		for _, entry in ipairs(without) do
			t.ok(entry.id ~= "GoldChest" and entry.id ~= "CopperLampPost", "nothing in stock, nothing listed")
		end
		-- The save's stock list survives the client decode.
		t.eq(SawmillLogic.DecodeStock("CopperLampPost,Wall4,GoldChest"), { "CopperLampPost", "GoldChest" })
		-- A migrated book keeps stock out of the book.
		local record = { sawmillStock = { "CopperLampPost" }, blueprintBook = {} }
		BlueprintBook.Migrate(record)
		t.eq(table.find(record.blueprintBook, "CopperLampPost"), nil)
	end)

	t.test("both craft recipes are on and name these pieces", function()
		for _, id in ipairs({ "CopperLampPost", "GoldChest" }) do
			local recipe = CraftData.Get(id)
			t.eq(recipe.enabled, true)
			t.eq(FurnitureData.Known(recipe.gives.furniture), true, id .. " gives a piece we define")
		end
	end)
end
