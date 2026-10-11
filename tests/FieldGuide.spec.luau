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

	---------------------------------------------------------------------------
	-- The v2 loop (V2_PLAN.md §2-§3a)
	---------------------------------------------------------------------------

	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local Util = t.shared("Util")
	local function axe(id)
		return ItemCatalog.GetAxe(id)
	end

	t.test("v2: every wood has a typical size; until its v2 shape lands it's V2_PLAN §3a's", function()
		local fs = require("@lune/fs")
		local plan = fs.readFile("V2_PLAN.md")
		for _, wood in ipairs(WoodData.All()) do
			local size = FieldGuide.TreeSize(wood)
			t.ok(size ~= nil, wood.id .. " has a size")
			t.ok(size.height[1] > 0 and size.height[2] >= size.height[1], wood.id .. " height band")
			t.ok(size.trunk > 0 and size.trunkLength > 0, wood.id .. " trunk")
			if not (wood.v2 and wood.v2.shape) then
				local low, high, trunk, length = string.match(
					plan,
					"\n" .. wood.id .. " = { height = { (%d+), (%d+) }, trunkThickness = ([%d%.]+), trunkLength = (%d+)"
				)
				t.ok(low ~= nil, wood.id .. ": its row in V2_PLAN §3a moved")
				t.eq(size.height, { tonumber(low), tonumber(high) }, wood.id .. " height")
				t.eq(size.trunk, tonumber(trunk), wood.id .. " trunk thickness")
				t.eq(size.trunkLength, tonumber(length), wood.id .. " trunk length")
			end
		end
	end)

	t.test("v2: a wood's own v2 shape wins over the plan's numbers, field by field", function()
		local oak = WoodData.Get("oak")
		local fake = table.clone(oak)
		fake.v2 = table.clone(oak.v2)
		fake.v2.shape = { height = { 40, 50 }, trunkThickness = 3 }
		local size = FieldGuide.TreeSize(fake)
		t.eq(size.height, { 40, 50 })
		t.eq(size.trunk, 3)
		t.eq(size.trunkLength, FieldGuide.TreeSize(oak).trunkLength, "no trunkLength in the shape: the plan's")
		fake.v2.shape = { height = { 50, 40 }, trunkThickness = 0 / 0 }
		t.eq(FieldGuide.TreeSize(fake), FieldGuide.TreeSize(oak), "a broken shape falls back")
		t.eq(FieldGuide.TreeSize({ id = "nope", v2 = nil }), nil, "no wood, no size")
		t.eq(FieldGuide.TrunkHits(axe("RustyAxe"), { id = "nope" }), math.huge)
	end)

	t.test("v2: hits to cut a mature trunk follow V2_PLAN §2c", function()
		-- §2c's Rusty and Steel rows (emberwood left out: its column predates
		-- §18 giving it the swamp-gold row's hardness 11).
		local plan = {
			RustyAxe = {
				oak = 16,
				birch = 35,
				pine = 73,
				maple = 68,
				palmwood = 19,
				frostwood = 95,
				phantomwood = 180,
				lumenwood = 397,
			},
			SteelAxe = {
				oak = 6,
				birch = 13,
				pine = 27,
				maple = 25,
				palmwood = 7,
				frostwood = 35,
				phantomwood = 66,
				lumenwood = 145,
			},
			StarfallAxe = { lumenwood = 7 },
		}
		for axeId, row in pairs(plan) do
			for woodId, hits in pairs(row) do
				t.eq(FieldGuide.TrunkHits(axe(axeId), WoodData.Get(woodId)), hits, axeId .. " on " .. woodId)
			end
		end
		-- The formula itself, from the data: ceil(hardness x (t/u)^2 x CutK / damage).
		for _, a in ipairs(ItemCatalog.AxeLadder()) do
			for _, wood in ipairs(WoodData.All()) do
				local damage = ItemCatalog.AxeStats(a, wood.id)
				local t2 = (FieldGuide.TreeSize(wood).trunk / GameConfig.WoodUnit) ^ 2
				local exact = wood.v2.hardness * t2 * GameConfig.CutK / damage
				local hits = FieldGuide.TrunkHits(a, wood)
				t.ok(hits >= exact - 1e-6 and hits < exact + 1, a.id .. " on " .. wood.id)
				t.eq(
					hits,
					FieldGuide.CutHits(a, wood.id, FieldGuide.TreeSize(wood).trunk),
					"TrunkHits is CutHits at the trunk"
				)
			end
		end
	end)

	t.test("v2: CutHits: thicker takes more, specialists hit harder, nothing breaks it", function()
		local rusty, inferno = axe("RustyAxe"), axe("InfernoAxe")
		t.ok(FieldGuide.CutHits(rusty, "oak", 1) < FieldGuide.CutHits(rusty, "oak", 2), "thicker")
		t.eq(
			FieldGuide.CutHits(rusty, "oak", 1.6, 1.6),
			FieldGuide.CutHits(rusty, "oak", 1.6),
			"depth defaults to width"
		)
		t.ok(FieldGuide.CutHits(rusty, "oak", 1.6, 3.2) > FieldGuide.CutHits(rusty, "oak", 1.6, 1.6), "a wide section")
		t.eq(FieldGuide.CutHits(rusty, "oak", 0.01), 1, "a twig still takes a swing")
		-- 7 x 1 x 1 / 0.2 is 35 exactly, even in floating point.
		t.eq(
			FieldGuide.CutHits(rusty, "birch", GameConfig.WoodUnit),
			math.ceil(WoodData.Get("birch").v2.hardness / rusty.v2.damage - 1e-9)
		)
		local vs = inferno.v2.vs.emberwood.damage
		local ember = WoodData.Get("emberwood")
		t.eq(
			FieldGuide.CutHits(inferno, "emberwood", GameConfig.WoodUnit),
			math.ceil(ember.v2.hardness / vs - 1e-9),
			"the Inferno Axe uses its emberwood damage"
		)
		t.ok(
			FieldGuide.TrunkHits(inferno, ember) < FieldGuide.TrunkHits(axe("SilverAxe"), ember),
			"a specialist beats its tier"
		)
		t.eq(FieldGuide.CutHits(rusty, "nope", 2), math.huge, "no such wood")
		t.eq(FieldGuide.CutHits(rusty, "oak", 0), math.huge, "no size")
		t.eq(FieldGuide.CutHits(rusty, "oak", 0 / 0), math.huge, "NaN")
		t.eq(FieldGuide.CutHits({ id = "x", v2 = nil }, "oak", 2), math.huge, "an axe without v2 stats")
	end)

	t.test("v2: the first axe that cuts a trunk at a useful pace", function()
		local ladder = ItemCatalog.AxeLadder()
		for _, wood in ipairs(WoodData.All()) do
			local first, n = FieldGuide.FirstAxeV2(wood, FieldGuide.UsefulHitsV2)
			t.ok(first ~= nil, wood.id .. " has a useful axe")
			t.eq(n, FieldGuide.TrunkHits(first, wood))
			t.ok(n <= FieldGuide.UsefulHitsV2)
			for _, earlier in ipairs(ladder) do
				if earlier == first then
					break
				end
				t.ok(
					FieldGuide.TrunkHits(earlier, wood) > FieldGuide.UsefulHitsV2,
					wood.id .. ": " .. earlier.id .. " is earlier"
				)
			end
			local any = FieldGuide.FirstAxeV2(wood)
			t.eq(any, ladder[1], "every axe cuts every wood under v2")
		end
		t.eq(FieldGuide.UsefulHitsV2, 20)
	end)

	t.test("v2: hardness is 1 to 5 axe marks, and every wood lists them", function()
		local expect = {
			oak = 1,
			palmwood = 1,
			pine = 2,
			maple = 2,
			birch = 3,
			frostwood = 4,
			lanternwood = 4,
			emberwood = 4,
			phantomwood = 5,
			lumenwood = 5,
			bogcypress = 3, -- Lane R: hardness 8
			ironwood = 5, -- Lane R: hardness 18
		}
		t.eq(#WoodData.All(), 12)
		for _, wood in ipairs(WoodData.All()) do
			local marks = FieldGuide.HardnessMarks(wood.v2.hardness)
			t.eq(marks, expect[wood.id], wood.id)
			local icons = FieldGuide.HardnessIcons(wood.v2.hardness)
			t.eq(#icons, 5, wood.id)
			t.eq(string.sub(icons, 1, marks), string.rep("x", marks), wood.id)
			t.eq(string.sub(icons, marks + 1), string.rep("-", 5 - marks), wood.id)
			t.eq(FieldGuide.AxeOff, "-")
			local text = FieldGuide.HardnessText(wood.v2.hardness)
			t.eq(text, icons .. " " .. tostring(marks) .. "/5", wood.id)
			t.ok(string.find(FieldGuide.FactsV2(wood), "hardness " .. text, 1, true) ~= nil, wood.id)
		end
		t.eq(
			"hardness " .. FieldGuide.HardnessText(WoodData.Get("birch").v2.hardness),
			"hardness xxx-- 3/5",
			"birch is the middle band"
		)
		t.eq(FieldGuide.HardnessMarks(0 / 0), 1, "not a number: the softest mark")
	end)

	t.test("v2: a found wood's page: where, hardness, $/u³, size, and the axe for it", function()
		local short = FieldGuide.ShortNumber
		for _, wood in ipairs(WoodData.All()) do
			local page = FieldGuide.FactsV2(wood)
			local v2, size = wood.v2, FieldGuide.TreeSize(wood)
			local starter, starterHits = FieldGuide.FirstAxeV2(wood)
			local axeLine = string.format(
				"%s: %d hit%s a cut",
				starter.displayName,
				starterHits,
				if starterHits == 1 then "" else "s"
			)
			if starterHits > FieldGuide.UsefulHitsV2 then
				local good, goodHits = FieldGuide.FirstAxeV2(wood, FieldGuide.UsefulHitsV2)
				axeLine ..= string.format("; %s: %d", good.displayName, goodHits)
			end
			local biome = t.shared("BiomeData").Get(wood.biome)
			local where = if biome then biome.displayName else wood.biome
			t.eq(
				page,
				table.concat({
					where,
					"hardness " .. FieldGuide.HardnessText(v2.hardness),
					string.format(
						"logs %s, planks %s",
						FieldGuide.PriceText(v2.logPrice),
						FieldGuide.PriceText(v2.plankPrice)
					),
					string.format(
						"%s-%s studs tall, %s-stud trunk",
						short(size.height[1], 1),
						short(size.height[2], 1),
						short(size.trunk, 2)
					),
					axeLine,
				}, " · "),
				wood.id
			)
			t.ok(
				not string.find(page, "HP", 1, true) and not string.find(page, "logs ×", 1, true),
				wood.id .. ": no v1 words"
			)
			t.eq(FieldGuide.FactsFor(wood, 2), page)
			t.eq(FieldGuide.FactsFor(wood, 1), FieldGuide.Facts(wood), "v1's page under v1")
		end
		t.ok(
			string.find(FieldGuide.FactsV2(WoodData.Get("oak")), "Rusty Axe: 16 hits a cut$") ~= nil,
			"the starter's wood"
		)
		local pine = FieldGuide.FactsV2(WoodData.Get("pine"))
		t.ok(string.find(pine, "; Hardened Axe: 16$") ~= nil, "pine names the first axe at a useful pace: " .. pine)
	end)

	t.test("v2: how, $/u³ and cash read (rounding)", function()
		local V = FieldGuide.VolumeText
		t.eq(V(26.4), "26")
		t.eq(V(26.5), "27", "half up")
		t.eq(V(4.44), "4.4", "one decimal under 10")
		t.eq(V(3.96), "4", "no trailing .0")
		t.eq(V(9.94), "9.9")
		t.eq(V(9.96), "10")
		t.eq(V(0.04), "0.1", "something is never 0")
		t.eq(V(1234.5), "1,235")
		for _, junk in ipairs({ 0, -3, 0 / 0, math.huge, "5" }) do
			t.eq(V(junk), "0", tostring(junk))
		end
		t.eq(FieldGuide.VolumeNumber(41.2), "41")
		local P = FieldGuide.PriceText
		t.eq(P(1.5), "$1.50")
		t.eq(P(9), "$9", "whole dollars without cents")
		t.eq(P(26.4), "$26.40")
		t.eq(P(0.1 + 0.2), "$0.30", "float noise rounds away")
		t.eq(P(1200), "$1,200")
		t.eq(P(-1), "$0")
		local C = FieldGuide.CashText
		-- As the sell pad pays a sale: the nearest whole dollar, never $0 for
		-- wood worth something (M1.7's SellLogic.Payout).
		t.eq(C(39.4), "$39")
		t.eq(C(39.5), "$40", "half up")
		t.eq(C(39.9), "$40")
		t.eq(C(0.3), "$1", "a sliver still pays a dollar")
		t.eq(C(1234), "$1,234")
		for _, junk in ipairs({ -1, 0 / 0, "5" }) do
			t.eq(C(junk), "$0", tostring(junk))
		end
		for _, wood in ipairs(WoodData.All()) do
			for _, price in ipairs({ wood.v2.logPrice, wood.v2.plankPrice }) do
				local dollars, cents = string.match(P(price), "^%$([%d,]+)%.?(%d*)$")
				local back = tonumber((string.gsub(dollars, ",", "")))
					+ (if cents ~= "" then tonumber(cents) / 100 else 0)
				t.ok(math.abs(back - price) < 0.005, wood.id .. ": " .. P(price) .. " reads its price")
			end
		end
		t.eq(FieldGuide.ShortNumber(0.55, 2), "0.55")
		t.eq(FieldGuide.ShortNumber(6, 2), "6")
		t.eq(FieldGuide.ShortNumber(0.7, 2), "0.7")
		t.eq(FieldGuide.ShortNumber(100, 1), "100", "zeros before the point stay")
		t.eq(Util.formatCash(39), C(39), "the same dollars as everywhere else")
	end)
end
