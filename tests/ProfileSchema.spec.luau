--!nocheck
-- The save template and migrating older saves.
return function(t)
	local function fresh()
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		return Schema, Util.deepCopy(Schema.Template)
	end

	t.test("a new save gets one Rusty Axe, equipped by nobody yet", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		t.eq(#data.axes, 1)
		t.eq(data.axes[1].id, "RustyAxe")
		t.ok(type(data.axes[1].uid) == "string" and #data.axes[1].uid > 0)
		t.eq(data.bestAxeTier, 1)
		t.eq(data.cash, 0)
	end)

	t.test("old saves listing axe ids become items, keeping the equipped one", function()
		local Schema, data = fresh()
		data.ownedAxes = { "RustyAxe", "SteelAxe" }
		data.equippedAxe = "SteelAxe"
		Schema.Migrate(data)
		t.eq(#data.axes, 2)
		t.eq(data.ownedAxes, nil)
		t.eq(data.bestAxeTier, 2)
		local equipped
		for _, item in ipairs(data.axes) do
			if item.uid == data.equippedAxe then
				equipped = item
			end
		end
		t.ok(equipped, "equippedAxe must name one of the new uids")
		t.eq(equipped.id, "SteelAxe")
	end)

	t.test("a new save has an unclaimed Campsite plot", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		t.eq(data.plot, { claimed = false, tier = 1, placed = {} })
	end)

	t.test("saves from before plots lose the old size and any old-format items", function()
		local Schema, data = fresh()
		data.plot = {
			claimed = false,
			size = 120,
			tier = 1, -- Reconcile adds the new field
			placed = {
				{ uid = "old", blueprintId = "Fence", cframe = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 } },
				{ uid = "new", blueprintId = "Fence", x = 2, z = 4, rot = 1 },
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.size, nil)
		t.eq(#data.plot.placed, 1)
		t.eq(data.plot.placed[1].uid, "new")
	end)

	t.test("migrating twice changes nothing", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		t.eq(data, before)
	end)

	t.test("receipts: new ones are recorded once; the cache keeps the latest", function()
		local Schema, data = fresh()
		t.ok(Schema.RecordPurchase(data, "a"))
		t.ok(not Schema.RecordPurchase(data, "a"), "a retry is not new")
		for i = 1, Schema.PurchaseIdCacheSize + 5 do
			Schema.RecordPurchase(data, "id" .. i)
		end
		t.eq(#data.purchaseIds, Schema.PurchaseIdCacheSize)
		t.ok(not Schema.RecordPurchase(data, "id" .. (Schema.PurchaseIdCacheSize + 5)), "recent ids are kept")
	end)

	t.test("bestAxeTier never goes down, and unknown axe ids don't break it", function()
		local Schema, data = fresh()
		data.bestAxeTier = 6
		data.axes = { { uid = "a", id = "SteelAxe" }, { uid = "b", id = "RemovedAxe" } }
		Schema.Migrate(data)
		t.eq(data.bestAxeTier, 6)
	end)
end
