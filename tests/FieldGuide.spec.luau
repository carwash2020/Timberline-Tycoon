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

	t.test("the headers count fresh every time", function()
		t.eq(
			FieldGuide.WoodsSubtitle({ oak = true }),
			string.format("1 of %d woods found. Fell one of each to fill in its page.", #WoodData.All())
		)
		t.eq(
			FieldGuide.WoodsSubtitle({ oak = true, birch = true }),
			string.format("2 of %d woods found. Fell one of each to fill in its page.", #WoodData.All())
		)
		t.eq(
			FieldGuide.GrainSubtitle({ curly = 3, burl = 0 }),
			"1 of 6 figures revealed. Read the bark; the sawmill shows what's inside."
		)
	end)

	t.test("the Hidden Grain page: every figure, its clue, its value, how many you've revealed", function()
		local figures = FieldGuide.Figures()
		t.eq(#figures, 6)
		local n, total = FieldGuide.FigureCount({ curly = 2, birdseye = 1, unicorn = 9 })
		t.eq({ n, total }, { 2, 6 })
		local birdseye
		for _, f in ipairs(figures) do
			if f.id == "birdseye" then
				birdseye = f
			end
			local facts = FieldGuide.FigureFacts(f, 0)
			t.ok(string.find(facts, f.clue, 1, true) ~= nil, f.id .. " shows its clue")
			t.ok(string.find(facts, "revealed 0", 1, true) ~= nil, f.id .. " shows the count")
		end
		t.eq(
			FieldGuide.FigureFacts(birdseye, 4),
			'Clue: small dark "eyes" dotted over the trunk · logs sell for x2 · 30 in 100 figured trees · revealed 4'
		)
		local storm = FieldGuide.FigureFacts(figures[4], 1)
		t.ok(string.find(storm, "Lightning only", 1, true) ~= nil, "Stormgrain says where it comes from")
		t.ok(string.find(FieldGuide.GrainIntro(), "6 in 100", 1, true) ~= nil)
	end)
end
