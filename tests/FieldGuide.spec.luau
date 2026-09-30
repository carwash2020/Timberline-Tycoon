--!nocheck
return function(t)
	local FieldGuide = t.shared("FieldGuide")
	local WoodData = t.shared("WoodData")

	t.test("the first axe that cuts each wood, and the first at a useful pace", function()
		t.eq(FieldGuide.FirstAxe(WoodData.Get("oak")).id, "RustyAxe")
		t.eq(FieldGuide.FirstAxe(WoodData.Get("maple")).id, "SteelAxe", "the Rusty Axe can't dent maple")
		local cobalt, n = FieldGuide.FirstAxe(WoodData.Get("emberwood"))
		t.eq({ cobalt.id, n }, { "CobaltAxe", 90 })
		local gold, m = FieldGuide.FirstAxe(WoodData.Get("emberwood"), FieldGuide.UsefulHits)
		t.eq({ gold.id, m }, { "GoldAxe", 30 }, "GAME_DESIGN: emberwood needs the Gold Axe")
		for _, wood in ipairs(WoodData.All()) do
			t.ok(FieldGuide.FirstAxe(wood, FieldGuide.UsefulHits) ~= nil, wood.id .. " has no useful axe")
		end
	end)

	t.test("found pages have the facts", function()
		t.eq(
			FieldGuide.Facts(WoodData.Get("pine")),
			"The Hills · 100 HP · hardness 4 · 5 logs × $7 each · Rusty Axe: 100 hits; Steel Axe: 13"
		)
		t.ok(string.find(FieldGuide.Facts(WoodData.Get("oak")), "Rusty Axe: 6 hits$") ~= nil)
		t.ok(string.find(FieldGuide.Facts(WoodData.Get("oak")), "soft") ~= nil)
	end)

	t.test("hints say where to look, never the value", function()
		t.eq(FieldGuide.Hint(WoodData.Get("frostwood")), "Grows in Snowfields")
		t.eq(FieldGuide.Hint(WoodData.Get("phantomwood")), "Somewhere hidden, and only at night")
		t.ok(string.find(FieldGuide.Hint(WoodData.Get("palmwood")), "coming soon") ~= nil)
		for _, wood in ipairs(WoodData.All()) do
			t.ok(not string.find(FieldGuide.Hint(wood), "%$"), wood.id .. " hint gives away the price")
		end
	end)

	t.test("counts found woods", function()
		local n, total = FieldGuide.Count({ oak = true, birch = true, nope = true })
		t.eq(n, 2)
		t.eq(total, #WoodData.All())
	end)
end
