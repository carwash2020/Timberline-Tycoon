--!nocheck
-- Lane F: pieces that wait in stock (crafted furniture, the Sparkworks counter's
-- pieces) and the Sparkworks counter's shelf list.
return function(t)
	local StockIds = t.shared("StockIds")
	local SparkworksStock = t.shared("SparkworksStock")
	local StoreStock = t.shared("StoreStock")
	local BlueprintBook = t.shared("BlueprintBook")
	local ItemCatalog = t.shared("ItemCatalog")
	local PlotData = t.shared("PlotData")
	local SawmillLogic = t.shared("SawmillLogic")

	t.test("the stock ids for logic pieces are exactly SparkworksStock's list", function()
		local listed = {}
		for _, row in ipairs(SparkworksStock.List()) do
			listed[row.id] = true
			t.ok(StockIds.IsLogic(row.id), row.id)
		end
		for _, id in ipairs(StockIds.Logic) do
			t.ok(listed[id] == true, id .. " is on the Sparkworks shelf")
		end
		t.eq(#StockIds.Logic, #SparkworksStock.List())
		t.eq(StockIds.IsLogic("Wall4"), false)
		t.eq(StockIds.IsLogic(nil), false)
		t.eq(StockIds.Has("GoldChest"), true)
		t.eq(StockIds.Has("Lever"), true)
		t.eq(StockIds.Has("SawmillRickety"), false, "boxed mills are not stock ids")
	end)

	t.test("the Sparkworks counter stocks every logic piece and every line piece at one price each", function()
		local slots = StoreStock.Sparkworks()
		local byId = {}
		for _, slot in ipairs(slots) do
			byId[slot.itemId] = slot
			t.eq(slot.shop, "Sparkworks")
		end
		for _, id in ipairs({ "SwitchBelt", "TiltedBelt", "BeltSupport", "WoodDetector" }) do
			t.ok(byId[id] ~= nil and byId[id].itemKind == "Machine", id .. " (a belt-line piece) is on the shelf")
			t.eq(StoreStock.UnitPrice("Machine", id, false, 2), ItemCatalog.GetMachine(id).priceCash)
		end
		for _, id in ipairs({ "WoodSweeper", "LaserEmitter", "LaserReceiver", "Lever", "Clock" }) do
			t.ok(byId[id] ~= nil and byId[id].itemKind == "Logic", id .. " (a logic piece) is on the shelf")
			t.eq(StoreStock.UnitPrice("Logic", id, false, 2), SparkworksStock.Price(id))
		end
		t.eq(StoreStock.UnitPrice("Logic", "Door", false, 2), nil, "a Door is not sold here")
		t.eq(#slots, 4 + #SparkworksStock.List())
		t.eq(StoreStock.Find("Logic", "Lever").slotId, "sparkworks-Lever")
		t.eq(StoreStock.DisplayName("Logic", "SparkLamp"), PlotData.Blueprint("SparkLamp").displayName)
		-- The interior shops' list (and the box budget built from it) is unchanged.
		for _, slot in ipairs(StoreStock.All()) do
			t.ok(slot.shop ~= "Sparkworks", slot.slotId .. " is an interior shop's")
		end
	end)

	t.test(
		"a Sparkworks piece places free from stock; without stock only a learned plan places, for its fee",
		function()
			t.eq({ BlueprintBook.Allowed("Lever", false, 1, true) }, { true, nil }, "one in stock")
			t.eq({ BlueprintBook.Allowed("Lever", false, 0, true) }, { false, "sparkworks" }, "none and no plan")
			t.ok(BlueprintBook.Message("sparkworks", PlotData.Blueprint("Lever")):find("Sparkworks counter") ~= nil)
			t.eq(
				{ BlueprintBook.Allowed("Lever", true, 0, true) },
				{ true, nil },
				"a rolled plan still places, as before"
			)
			t.eq(BlueprintBook.IsFromStock("Lever"), true)
			t.eq(BlueprintBook.IsFromStock("GoldChest"), true)
			t.eq(BlueprintBook.IsFromStock("SawmillRickety"), true)
			t.eq(BlueprintBook.IsFromStock("Wall4"), false)
			t.eq(BlueprintBook.NeedsText(PlotData.Blueprint("Lever"), 1), "Placed from your box")
			-- Stock in a save is not learned as a plan when the book is migrated.
			local record = { sawmillStock = { "Lever", "WoodSweeper" }, blueprintBook = {} }
			BlueprintBook.Migrate(record)
			t.eq(table.find(record.blueprintBook, "Lever"), nil)
			t.eq(table.find(record.blueprintBook, "WoodSweeper"), nil)
			-- And the client reads it back out of the stock attribute.
			t.eq(SawmillLogic.DecodeStock("Lever,SwitchBelt,Wall4"), { "Lever", "SwitchBelt" })
		end
	)
end
