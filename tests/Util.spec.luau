--!nocheck
return function(t)
	local Util = t.shared("Util")

	t.test("formatCash adds a dollar sign and thousands separators", function()
		t.eq(Util.formatCash(0), "$0")
		t.eq(Util.formatCash(999), "$999")
		t.eq(Util.formatCash(1000), "$1,000")
		t.eq(Util.formatCash(1234567), "$1,234,567")
		t.eq(Util.formatCash(2_000_000), "$2,000,000")
		t.eq(Util.formatCash(-4500), "-$4,500")
		t.eq(Util.formatCash(12.9), "$12", "rounds down")
	end)

	t.test("clamp", function()
		t.eq(Util.clamp(5, 0, 10), 5)
		t.eq(Util.clamp(-1, 0, 10), 0)
		t.eq(Util.clamp(11, 0, 10), 10)
	end)

	t.test("deepCopy copies nested tables", function()
		local original = { a = { b = 1 }, list = { 1, 2 } }
		local copy = Util.deepCopy(original)
		t.eq(copy, original)
		copy.a.b = 2
		t.eq(original.a.b, 1)
	end)

	t.test("article: an before a vowel sound, a before a consonant, the word's case kept", function()
		t.eq(Util.article("oak"), "an oak")
		t.eq(Util.article("birch"), "a birch")
		t.eq(Util.article("Elder"), "an Elder")
		t.eq(Util.article("Oak"), "an Oak")
		t.eq(Util.article("emberwood"), "an emberwood")
		t.eq(Util.article("Insulated Coat"), "an Insulated Coat")
		t.eq(Util.article("Lantern"), "a Lantern")
		t.eq(Util.article("Homestead"), "a Homestead", "a sounded h")
		t.eq(Util.article("hour"), "an hour", "a silent h")
		t.eq(Util.article("unicorn"), "a unicorn", "a u that sounds like you")
		t.eq(Util.article("umbrella"), "an umbrella")
		t.eq(Util.article(""), "", "nothing to name")
	end)

	t.test("article names every wood, gear and plot tier the toasts can name", function()
		local WoodData = t.shared("WoodData")
		local ItemCatalog = t.shared("ItemCatalog")
		local PlotData = t.shared("PlotData")
		local expect = {
			oak = "an oak",
			birch = "a birch",
			pine = "a pine",
			maple = "a maple",
			palmwood = "a palmwood",
			frostwood = "a frostwood",
			emberwood = "an emberwood",
			phantomwood = "a phantomwood",
			lumenwood = "a lumenwood",
		}
		local checked = 0
		for _, wood in ipairs(WoodData.All()) do
			local name = string.lower(wood.displayName)
			if expect[name] then
				t.eq(Util.article(name), expect[name])
				checked += 1
			end
		end
		t.ok(checked >= 9, "the nine woods are still there")
		t.eq(Util.article(ItemCatalog.GetGear("InsulatedCoat").displayName), "an Insulated Coat")
		t.eq(Util.article(ItemCatalog.GetGear("Lantern").displayName), "a Lantern")
		for _, tier in ipairs(PlotData.Tiers) do
			t.eq(Util.article(tier.name), "a " .. tier.name)
		end
	end)

	t.test("guid gives a fresh id each time", function()
		t.ok(Util.guid() ~= Util.guid())
	end)
end
