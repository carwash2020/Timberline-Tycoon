--!nocheck
-- Lane R: the rare finds. Deterministic and free, one pick at a time, saved as
-- one stamp, and both ship disabled until the Designer picks them.
return function(t)
	local RegionItems = t.load("ReplicatedStorage/Shared/Regions/RegionItems")

	local function facts(item, over)
		local f = { region = item.region, distance = 3, stage = 8, hasIt = false, frame = 1 }
		for k, v in pairs(over or {}) do
			f[k] = v
		end
		return f
	end

	t.test("one find a region, at B's UniqueItemSpawn ids, disabled with the rare line", function()
		local all = RegionItems.All()
		t.eq(#all, 2)
		t.eq(RegionItems.ForAnchor("bayou").region, "bayou")
		t.eq(RegionItems.ForAnchor("redmesa").region, "mesa")
		for _, item in ipairs(all) do
			t.eq(item.enabled, false, item.id)
			t.eq(item.signLine, "Something rare lives here")
		end
	end)

	t.test("a disabled find is refused with the rare line, and nothing is taken", function()
		local anchors = RegionItems.NewAnchors()
		local item = RegionItems.ForAnchor("bayou")
		local v = RegionItems.Pick(anchors, item, 0, facts(item))
		t.eq(v.ok, false)
		t.eq(v.reason, "Something rare lives here.")
		t.eq(RegionItems.Live(anchors, "bayou", 0), true)
	end)

	local function on(item)
		local copy = {}
		for k, v in pairs(item) do
			copy[k] = v
		end
		copy.enabled = true
		return copy
	end

	t.test("an enabled find is picked once: the same frame, or before the respawn, is refused", function()
		local anchors = RegionItems.NewAnchors()
		local item = on(RegionItems.ForAnchor("redmesa"))
		t.eq(RegionItems.Pick(anchors, item, 10, facts(item, { frame = 7 })).ok, true)
		-- A second player in the same frame.
		t.eq(RegionItems.Pick(anchors, item, 10, facts(item, { frame = 7 })).ok, false, "same frame")
		-- A later frame, anchor still empty.
		t.eq(RegionItems.Pick(anchors, item, 11, facts(item, { frame = 8 })).ok, false, "before the respawn")
		t.eq(RegionItems.Pick(anchors, item, 10 + item.respawnSec, facts(item, { frame = 9 })).ok, true, "after it")
	end)

	t.test("it needs the region, the reach and the stage, and a slot that does not hold it", function()
		local anchors = RegionItems.NewAnchors()
		local item = on(RegionItems.ForAnchor("bayou"))
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { region = "mesa" })).ok, false, "found only in its region")
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { region = "" })).ok, false)
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { distance = RegionItems.Reach + 1 })).ok, false)
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { distance = 0 / 0 })).ok, false)
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { stage = 1 })).ok, false)
		t.eq(RegionItems.Pick(anchors, item, 0, facts(item, { hasIt = true })).ok, false)
		t.eq(RegionItems.Live(anchors, "bayou", 0), true, "no refusal took the anchor")
	end)

	t.test("the save flag is one Region: stamp a slot, written once", function()
		local stamps = {}
		t.eq(RegionItems.StampKey("BayouFind"), "Region:Found:BayouFind")
		t.eq(RegionItems.SeenKey("bayou"), "Region:Seen:bayou")
		t.eq(RegionItems.Has(stamps, "BayouFind"), false)
		t.eq(RegionItems.Stamp(stamps, "BayouFind"), true)
		t.eq(RegionItems.Stamp(stamps, "BayouFind"), false, "idempotent")
		t.eq(RegionItems.Has(stamps, "BayouFind"), true)
		t.eq(RegionItems.Has(nil, "BayouFind"), false)
		for key in pairs(stamps) do
			t.ok(string.sub(key, 1, 7) == "Region:", key)
		end
	end)

	t.test("nothing here costs Robux or is a paid random item", function()
		local fs = require("@lune/fs")
		local text = fs.readFile("src/ReplicatedStorage/Shared/Regions/RegionItems.luau")
		t.ok(not string.find(text, "Robux", 1, false) or string.find(text, "no Robux", 1, true), "Robux only as a ban")
		for _, item in ipairs(RegionItems.All()) do
			t.eq(item.cost, nil, "free")
		end
	end)
end
