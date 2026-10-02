--!nocheck
-- The Living Forest's rules (GAME_DESIGN §16), number by number.
return function(t)
	local ForestData = t.shared("ForestData")
	local ForestLogic = t.shared("ForestLogic")
	local TreeLogic = t.shared("TreeLogic")
	local WoodData = t.shared("WoodData")
	local BiomeData = t.shared("BiomeData")

	local function near(a, b, message)
		t.ok(
			math.abs(a - b) < 1e-9,
			string.format("%s: expected %s, got %s", message or "value", tostring(b), tostring(a))
		)
	end

	t.test("§16's numbers are the data", function()
		local s = ForestData.Seeds
		t.eq({ s.perTree, s.largeBonus, s.rollChance, s.stormBonus, s.stewardBonus }, { 1, 1, 0.15, 1, 1 })
		t.eq({ s.maxPerWood, s.maxTotal }, { 50, 200 })
		t.eq(s.stewardAfter, 600)
		t.eq(ForestData.PlantRange, 12)
		t.eq(ForestData.SproutSeconds, 8)
		t.eq(ForestData.SlowSproutShare, 0.5)
		t.eq(ForestData.PlanterShare, 0.15)
		local v = ForestData.Vitality
		t.eq({ v.start, v.rest, v.driftPerMinute, v.fellWild, v.fellPlanted, v.plant }, { 60, 60, 1, -1.5, -0.5, 4 })
		t.eq(ForestData.FigureChance, { base = 0.06, plantedBonus = 0.04, bloomMul = 2 })
		t.eq({ ForestData.Storm.strikeRadius, ForestData.Storm.glowSeconds }, { 60, 120 })
		local e = ForestData.Elder
		t.eq({ e.maxActive, e.checkMinSeconds, e.checkMaxSeconds }, { 1, 480, 900 })
		t.eq({ e.scale, e.hpMul, e.logMul, e.helperMinShare, e.helperSeeds, e.helperShare }, { 1.7, 6, 3, 0.1, 2, 0.1 })
		t.eq(e.fadeSeconds, 900)
		t.eq(e.nightLeftSeconds, 300)
		t.eq(ForestData.Bloom, { threshold = 75, seconds = 480, restSeconds = 1800 })
	end)

	t.test("figures: weights, values and clues as designed", function()
		local want = {
			curly = { 45, 1.5 },
			birdseye = { 30, 2 },
			quilted = { 17, 2.5 },
			burl = { 8, 4 },
			starfall = { 0, 8 },
			stormgrain = { 0, 3 },
		}
		local seen = 0
		for _, f in ipairs(ForestData.Figures) do
			local w = want[f.id]
			t.ok(w ~= nil, "unexpected figure " .. f.id)
			t.eq({ f.weight, f.multiplier }, w, f.id)
			t.ok(#f.clue > 0 and f.revealSeconds > 0, f.id .. " has a clue and a reveal")
			t.ok(string.match(f.id, "^%a+$") ~= nil, f.id .. " is letters only (attributes, saves)")
			seen += 1
		end
		t.eq(seen, 6)
		t.eq(ForestData.StarfallShare, 0.3)
		-- The reveal waits longer for rarer figures (the list runs rarest last).
		for i = 2, #ForestData.Figures do
			t.ok(ForestData.Figures[i].multiplier > ForestData.Figures[i - 1].multiplier, "ordered by value")
			t.ok(ForestData.Figures[i].revealSeconds > ForestData.Figures[i - 1].revealSeconds, "rarer stays longer")
		end
	end)

	t.test("the five ground groves have vitality; the isles don't", function()
		t.eq(#ForestData.Groves, 5)
		for _, id in ipairs(ForestData.Groves) do
			local biome = BiomeData.Get(id)
			t.ok(biome ~= nil and biome.area ~= nil and biome.area.y == nil, id .. " is a ground biome in the world")
			t.ok(ForestLogic.IsGrove(id))
		end
		t.ok(not ForestLogic.IsGrove("sky"))
		t.ok(not ForestLogic.IsGrove("island"))
	end)

	t.test("seed drops: 1, +1 large, +1 on a 15% roll, +1 storm, +1 steward", function()
		local function drop(large, storm, steward, roll)
			return ForestLogic.SeedDrop({ large = large, storm = storm, steward = steward, roll = roll })
		end
		t.eq(drop(false, false, false, 0.5), 1)
		t.eq(drop(true, false, false, 0.5), 2)
		t.eq(drop(false, false, false, 0.14), 2)
		t.eq(drop(false, false, false, 0.15), 1, "the roll is strictly under 15%")
		t.eq(drop(false, true, false, 0.5), 2)
		t.eq(drop(false, false, true, 0.5), 2)
		t.eq(drop(true, true, true, 0), 5)
		t.ok(ForestLogic.IsLarge(TreeLogic.Sizes[3]))
		t.ok(not ForestLogic.IsLarge(TreeLogic.Sizes[1]) and not ForestLogic.IsLarge(TreeLogic.Sizes[2]))
		t.ok(ForestLogic.IsLarge(ForestLogic.ElderSize(WoodData.Get("oak"))), "Elders count as large")
	end)

	t.test("the steward's bonus waits until the tree has stood 10 minutes", function()
		t.ok(ForestLogic.StewardEarned(nil, 0), "planted long ago (or before a restart)")
		t.ok(not ForestLogic.StewardEarned(1000, 1000))
		t.ok(not ForestLogic.StewardEarned(1000, 1599.9))
		t.ok(ForestLogic.StewardEarned(1000, 1600))
	end)

	t.test("a sapling stands in 8 s in the groves; slow woods outside them take half their regrowth", function()
		for _, wood in ipairs(WoodData.All()) do
			local seconds = ForestLogic.SproutSeconds(wood)
			if ForestLogic.IsGrove(wood.biome) then
				t.eq(seconds, 8, wood.id)
			else
				t.eq(seconds, wood.respawnSec / 2, wood.id)
				t.ok(seconds > 8, wood.id .. " stays slow")
			end
		end
		local lumen = WoodData.Get("lumenwood")
		t.eq(ForestLogic.SproutSeconds(lumen), 450)
		t.eq(ForestLogic.SproutSeconds(WoodData.Get("palmwood")), 75)
		t.eq(ForestLogic.SproutSeconds(lumen, 600), 450)
		t.eq(ForestLogic.SproutSeconds(lumen, 120), 120, "never past its own regrowth")
		t.eq(ForestLogic.SproutSeconds(lumen, 2), 8, "never under 8 s")
		t.eq(ForestLogic.SproutSeconds(WoodData.Get("oak"), 3), 8)
		t.eq(ForestLogic.SproutSeconds(WoodData.Get("oak"), 30), 8)
	end)

	t.test("a felling counts for whoever chopped the most of it, not the last swing", function()
		local function here()
			return true
		end
		t.eq(ForestLogic.Feller({ [1] = 29, [2] = 1 }, 2, here), 1, "1 HP from the end doesn't take it")
		t.eq(ForestLogic.Feller({ [1] = 10, [2] = 20 }, 2, here), 2)
		t.eq(ForestLogic.Feller({ [1] = 15, [2] = 15 }, 2, here), 2, "a tie goes to the swinger")
		t.eq(ForestLogic.Feller({ [1] = 12, [3] = 12, [2] = 6 }, 2, here), 1, "other ties to the lowest id")
		t.eq(
			ForestLogic.Feller({ [1] = 29, [2] = 1 }, 2, function(id)
				return id ~= 1
			end),
			2,
			"someone who left doesn't count"
		)
		t.eq(ForestLogic.Feller({}, 5, here), 5)
	end)

	t.test("the pouch holds 50 of a wood and 200 in all", function()
		local seeds = {}
		t.eq(ForestLogic.AddSeeds(seeds, "oak", 3), 3)
		t.eq(seeds.oak, 3)
		t.eq(ForestLogic.AddSeeds(seeds, "oak", 60), 47, "up to 50 of one wood")
		t.eq(seeds.oak, 50)
		t.eq(ForestLogic.AddSeeds(seeds, "oak", 1), 0)
		ForestLogic.AddSeeds(seeds, "birch", 50)
		ForestLogic.AddSeeds(seeds, "pine", 50)
		ForestLogic.AddSeeds(seeds, "maple", 45)
		t.eq(ForestLogic.TotalSeeds(seeds), 195)
		t.eq(ForestLogic.AddSeeds(seeds, "frostwood", 9), 5, "the rest is over the 200")
		t.eq(ForestLogic.TotalSeeds(seeds), 200)
		t.ok(ForestLogic.TakeSeed(seeds, "frostwood"))
		t.eq(seeds.frostwood, 4)
		local one = { oak = 1 }
		t.ok(ForestLogic.TakeSeed(one, "oak"))
		t.eq(one.oak, nil, "the last seed of a wood leaves no 0 behind")
		t.ok(not ForestLogic.TakeSeed(one, "oak"))
		t.ok(not ForestLogic.TakeSeed({}, "birch"))
	end)

	t.test("a saved pouch is cleaned: known woods, whole numbers, within the caps", function()
		local clean = ForestLogic.CleanSeeds({ oak = 70, birch = 2.6, unicorn = 5, pine = -3, maple = "7" })
		t.eq(clean, { oak = 50, birch = 2 })
		t.eq(ForestLogic.CleanSeeds(nil), {})
		local many = {}
		for _, wood in ipairs(WoodData.All()) do
			many[wood.id] = 50
		end
		t.eq(ForestLogic.TotalSeeds(ForestLogic.CleanSeeds(many)), 200)
	end)

	t.test("vitality: fells and plants, clamped to 0-100, drifting back to 60 by 1 a minute", function()
		t.eq(ForestLogic.FellDelta(false), -1.5)
		t.eq(ForestLogic.FellDelta(true), -0.5)
		t.eq(ForestLogic.FellDelta(true, true), -4.5, "its planter refelling it: the planting's 4 back too")
		t.eq(ForestLogic.FellDelta(false, true), -1.5)
		t.eq(ForestLogic.ApplyVitality(60, ForestData.Vitality.plant), 64)
		t.eq(ForestLogic.ApplyVitality(99, 4), 100)
		t.eq(ForestLogic.ApplyVitality(1, -1.5), 0)
		t.eq(ForestLogic.Drift(80, 60), 79)
		t.eq(ForestLogic.Drift(40, 120), 42)
		t.eq(ForestLogic.Drift(60.5, 60), 60, "never past rest")
		t.eq(ForestLogic.Drift(59.9, 60), 60)
		near(ForestLogic.Drift(70, 1), 70 - 1 / 60, "a second's drift")
	end)

	t.test("tiers: Thinning under 35, Healthy 35-74, Thriving 75-89, Old Growth 90+", function()
		local function tier(v)
			return ForestLogic.TierFor(v).id
		end
		t.eq(tier(0), "Thinning")
		t.eq(tier(34.9), "Thinning")
		t.eq(tier(35), "Healthy")
		t.eq(tier(60), "Healthy")
		t.eq(tier(74.9), "Healthy")
		t.eq(tier(75), "Thriving")
		t.eq(tier(89.9), "Thriving")
		t.eq(tier(90), "OldGrowth")
		t.eq(tier(100), "OldGrowth")
		t.eq(ForestLogic.TierIndex("Thinning"), 1)
		t.eq(ForestLogic.TierIndex("OldGrowth"), 4)
		t.eq(ForestLogic.TierIndex("nope"), 0)
		t.eq(ForestLogic.Tier("OldGrowth").displayName, "Old Growth")
	end)

	t.test("figure chance: 6% x tier, +4% planted, x2 in a bloom", function()
		near(ForestLogic.FigureChance("Thinning", false, false), 0.03, "thinning")
		near(ForestLogic.FigureChance("Healthy", false, false), 0.06, "healthy")
		near(ForestLogic.FigureChance("Thriving", false, false), 0.09, "thriving")
		near(ForestLogic.FigureChance("OldGrowth", false, false), 0.12, "old growth")
		near(ForestLogic.FigureChance("Healthy", true, false), 0.10, "planted")
		near(ForestLogic.FigureChance("Healthy", false, true), 0.12, "bloom")
		near(ForestLogic.FigureChance("OldGrowth", true, true), 0.32, "everything")
		near(ForestLogic.FigureChance(nil, false, false), 0.06, "outside the groves: as Healthy")
	end)

	t.test("the figure roll: chance first, then by weight; starfall is 30% of lumenwood burls", function()
		t.eq(ForestLogic.RollFigure("oak", 0.06, 0.06, 0, 0), nil, "the roll must be under the chance")
		t.eq(ForestLogic.RollFigure("oak", 0.06, 0.059, 0, 0), "curly")
		-- Weights 45 / 30 / 17 / 8 in that order.
		t.eq(ForestLogic.PickFigure("oak", 0.0, 0), "curly")
		t.eq(ForestLogic.PickFigure("oak", 0.449, 0), "curly")
		t.eq(ForestLogic.PickFigure("oak", 0.451, 0), "birdseye")
		t.eq(ForestLogic.PickFigure("oak", 0.749, 0), "birdseye")
		t.eq(ForestLogic.PickFigure("oak", 0.751, 0), "quilted")
		t.eq(ForestLogic.PickFigure("oak", 0.919, 0), "quilted")
		t.eq(ForestLogic.PickFigure("oak", 0.921, 0), "burl")
		t.eq(ForestLogic.PickFigure("oak", 0.999, 0), "burl")
		t.eq(ForestLogic.PickFigure("oak", 0.95, 0.1), "burl", "starfall is Lumenwood only")
		t.eq(ForestLogic.PickFigure("lumenwood", 0.95, 0.29), "starfall")
		t.eq(ForestLogic.PickFigure("lumenwood", 0.95, 0.31), "burl")
		-- Elders: Quilted or Burl, by their weights (17 : 8).
		t.eq(ForestLogic.PickFigure("maple", 0, 0, ForestData.Elder.figures), "quilted")
		t.eq(ForestLogic.PickFigure("maple", 17 / 25 - 0.001, 0, ForestData.Elder.figures), "quilted")
		t.eq(ForestLogic.PickFigure("maple", 17 / 25 + 0.001, 0, ForestData.Elder.figures), "burl")
	end)

	t.test("over many rolls the figures land near their weights", function()
		local counts = {}
		local n = 20000
		for i = 1, n do
			local id = ForestLogic.PickFigure("oak", (i - 0.5) / n, 0.5)
			counts[id] = (counts[id] or 0) + 1
		end
		t.eq(counts, { curly = 9000, birdseye = 6000, quilted = 3400, burl = 1600 })
	end)

	t.test("log values and the storm", function()
		t.eq(ForestLogic.Multiplier(nil), 1)
		t.eq(ForestLogic.Multiplier("birdseye"), 2)
		t.eq(ForestLogic.LogValue(10, "quilted"), 25)
		t.eq(ForestLogic.LogValue(3, nil), 3)
		t.eq(ForestLogic.StruckFigure(nil), "stormgrain")
		t.eq(ForestLogic.StruckFigure("curly"), "stormgrain")
		t.eq(ForestLogic.StruckFigure("quilted"), "stormgrain")
		t.eq(ForestLogic.StruckFigure("burl"), "burl", "a struck burl is still worth more as a burl")
		t.eq(ForestLogic.StruckFigure("starfall"), "starfall")
		t.eq(ForestLogic.MultiplierText(2), "x2")
		t.eq(ForestLogic.MultiplierText(1.5), "x1.5")
		t.eq(ForestLogic.MultiplierText(2.5), "x2.5")
	end)

	t.test("the figure average adds about 6% at a Healthy grove", function()
		near(ForestLogic.FiguredAverage("oak"), 2.02, "a figured tree's average multiplier")
		near(ForestLogic.FigureBonus("oak", "Healthy", false, false), 0.0612, "healthy")
		t.ok(
			ForestLogic.FiguredAverage("lumenwood") > ForestLogic.FiguredAverage("oak"),
			"Starfall Burl lifts lumenwood"
		)
		near(ForestLogic.FiguredAverage("lumenwood"), (67.5 + 60 + 42.5 + 8 * (0.7 * 4 + 0.3 * 8)) / 100, "lumenwood")
		t.ok(
			ForestLogic.FigureBonus("oak", "Thinning", false, false)
				< ForestLogic.FigureBonus("oak", "OldGrowth", true, false)
		)
	end)

	t.test("the planter's share: 15% of the logs' base value, whole dollars, at least $1", function()
		t.eq(ForestLogic.Royalty(3, 3), 1) -- an oak: $9 -> $1.35
		t.eq(ForestLogic.Royalty(7, 5), 5) -- a pine: $35 -> $5.25
		t.eq(ForestLogic.Royalty(55, 8), 66) -- an emberwood: $440
		t.eq(ForestLogic.Royalty(3, 2), 1, "never nothing")
	end)

	t.test("an Elder: 1.7x size, 6x HP, 3x logs", function()
		for _, wood in ipairs(WoodData.All()) do
			local size = ForestLogic.ElderSize(wood)
			t.eq(size.name, "elder")
			t.eq(size.scale, 1.7)
			t.eq(size.hpMul, 6)
			t.eq(size.logDelta, 2 * wood.logsPerTree)
			t.eq(TreeLogic.LogCount(wood.logsPerTree, size), 3 * wood.logsPerTree, wood.id .. " logs")
			t.eq(TreeLogic.MaxHP(wood.treeHP, size), 6 * wood.treeHP, wood.id .. " HP")
		end
	end)

	t.test("Elder helpers: everyone with 10% of its HP; the bonus is 10% of its value", function()
		t.eq(ForestLogic.Helpers({ [1] = 100, [2] = 18, [3] = 17.99, [4] = 60 }, 180), { 1, 2, 4 })
		t.eq(ForestLogic.Helpers({}, 180), {})
		t.eq(ForestLogic.HelperBonus(9 * 3 * 2.5), 7) -- an Elder Oak, quilted: $67.50
		t.eq(ForestLogic.HelperBonus(1), 1)
	end)

	t.test("Elders wake in Thriving and Old Growth groves, more likely the higher", function()
		t.eq(ForestLogic.ElderWakeChance(74.9), 0)
		near(ForestLogic.ElderWakeChance(75), 0.4, "at 75")
		near(ForestLogic.ElderWakeChance(100), 1, "at 100")
		t.ok(ForestLogic.ElderWakeChance(95) > ForestLogic.ElderWakeChance(80))
		local groves = { { biome = "starter", vitality = 60 }, { biome = "hills", vitality = 100 } }
		t.eq(ForestLogic.PickElderGrove(groves, 0.5, 0.99), "hills", "the only awake grove")
		t.eq(
			ForestLogic.PickElderGrove({ { biome = "starter", vitality = 60 } }, 0.5, 0),
			nil,
			"a healthy grove sleeps"
		)
		local thriving = { { biome = "starter", vitality = 75 } }
		t.eq(ForestLogic.PickElderGrove(thriving, 0.5, 0.39), "starter")
		t.eq(ForestLogic.PickElderGrove(thriving, 0.5, 0.41), nil, "40% at 75")
		-- Picked by chance: 0.4 vs 1.0 -> starter takes the first 2/7 of the pick roll.
		local both = { { biome = "starter", vitality = 75 }, { biome = "hills", vitality = 100 } }
		t.eq(ForestLogic.PickElderGrove(both, 0.2, 0), "starter")
		t.eq(ForestLogic.PickElderGrove(both, 0.3, 0), "hills")
	end)

	t.test("finding a spot: the first candidate the test accepts", function()
		local rolls = { 0, 0.25, 0.5, 1 }
		local i = 0
		local function roll()
			i += 1
			return rolls[(i - 1) % #rolls + 1]
		end
		local x, z = ForestLogic.FindSpot(100, 200, 10, 5, roll, function(px)
			return px > 100
		end)
		t.ok(x ~= nil and x > 100 and x <= 110 and z ~= nil)
		local none = ForestLogic.FindSpot(0, 0, 10, 5, roll, function()
			return false
		end)
		t.eq(none, nil)
	end)

	t.test("the Skyroot blooms when the five groves average 75", function()
		local all = {}
		for _, id in ipairs(ForestData.Groves) do
			all[id] = 75
		end
		t.ok(ForestLogic.BloomReady(all))
		all.starter = 74
		t.ok(not ForestLogic.BloomReady(all), "average 74.8")
		all.hills = 100
		t.ok(ForestLogic.BloomReady(all), "one grove's old growth carries a thinner one")
		t.eq(ForestLogic.AverageVitality({}), 60, "missing groves count as at rest")
		t.ok(not ForestLogic.BloomReady({}))
	end)

	t.test("v2 (M1.3): the large tree's seed by scale, the planter's share by value", function()
		t.ok(ForestLogic.IsLargeScale(1.15), "TreeGen's large roll")
		t.ok(ForestLogic.IsLargeScale(ForestData.Elder.scale), "an Elder")
		t.ok(not ForestLogic.IsLargeScale(1), "normal")
		t.ok(not ForestLogic.IsLargeScale(0.85))
		t.eq(ForestLogic.RoyaltyByValue(39), 6, "15% of an oak's $39")
		t.eq(ForestLogic.RoyaltyByValue(2), 1, "at least $1 for something")
		t.eq(ForestLogic.RoyaltyByValue(0), 0, "nothing for nothing")
		t.eq(ForestLogic.Royalty(7, 5), 5, "the v1 share is unchanged")
	end)
end
