--!nocheck
return function(t)
	local DailyData = t.shared("DailyData")
	local WoodData = t.shared("WoodData")

	t.test("the same player gets the same goals all day, different ones tomorrow", function()
		local a = DailyData.Roll(12345, 20000, 1)
		t.eq(DailyData.Roll(12345, 20000, 1), a)
		local differs = false
		for day = 20001, 20010 do
			local other = DailyData.Roll(12345, day, 1)
			for i, goal in ipairs(other) do
				if goal.kind ~= a[i].kind or goal.wood ~= a[i].wood then
					differs = true
				end
			end
		end
		t.ok(differs, "goals should change from day to day")
	end)

	t.test("three different kinds, sized to the tier, starting at zero", function()
		for tier = 1, #DailyData.Tiers do
			for day = 1, 30 do
				local goals = DailyData.Roll(day * 97, day, tier)
				t.eq(#goals, DailyData.GoalsPerDay)
				local seen = {}
				for _, goal in ipairs(goals) do
					t.ok(not seen[goal.kind], "duplicate kind " .. goal.kind)
					seen[goal.kind] = true
					t.ok(goal.target > 0 and goal.progress == 0 and not goal.done)
					t.eq(goal.reward, DailyData.Tiers[tier].reward)
					if goal.kind == "sellWood" then
						t.ok(WoodData.Get(goal.wood) ~= nil, "unknown wood " .. tostring(goal.wood))
					end
				end
			end
		end
	end)

	t.test("wood goals ask for wood the player's axe can fell", function()
		t.eq(DailyData.WoodsFor(1), { "oak", "birch" })
		local steel = DailyData.WoodsFor(2)
		t.ok(table.find(steel, "pine") ~= nil, "the Steel Axe fells pine")
		for tier = 1, #DailyData.Tiers do
			local woods = DailyData.WoodsFor(tier)
			t.ok(#woods > 0, "tier " .. tier .. " has woods")
			for _, id in ipairs(woods) do
				t.ok(id ~= "phantomwood", "night-only wood isn't a daily goal")
				t.ok(id ~= "palmwood", "only woods in the world")
			end
		end
	end)

	t.test("bigger tiers mean bigger goals and rewards", function()
		for i = 2, #DailyData.Tiers do
			local a, b = DailyData.Tiers[i - 1], DailyData.Tiers[i]
			t.ok(b.reward > a.reward, "reward tier " .. i)
			t.ok(b.cash >= a.cash and b.logs >= a.logs and b.trees >= a.trees, "size tier " .. i)
			t.ok(b.seeds >= a.seeds and b.figured >= a.figured, "forest goals tier " .. i)
		end
	end)

	t.test("the Living Forest's goal is figured logs; a saved plant goal is replaced alone", function()
		local seen = {}
		for day = 1, 200 do
			for _, goal in ipairs(DailyData.Roll(4242, day, 2)) do
				seen[goal.kind] = true
				t.ok(goal.kind ~= "plant", "plant is not rolled")
				if goal.kind == "sellFigured" then
					t.eq(goal.target, DailyData.Tiers[2].figured)
				end
			end
		end
		t.ok(seen.sellFigured, "figured logs come up")
		for _, tier in ipairs(DailyData.Tiers) do
			t.ok(tier.figured >= 3 and tier.figured <= 10, "figured target")
		end
		local fell = { kind = "fell", target = 4, progress = 2, reward = 15, done = false }
		local plant = { kind = "plant", target = 3, progress = 1, reward = 30, done = false }
		local goals = { fell, plant }
		t.eq(DailyData.ReplaceRetired(goals, 4242, 3, 2, nil), true)
		t.eq(goals[1], fell, "the other goal stays, progress and all")
		t.ok(
			goals[2].kind ~= "plant" and table.find(DailyData.Kinds, goals[2].kind),
			"the plant goal became a live kind"
		)
		t.eq(goals[2].progress, 0)
		t.eq(goals[2].reward, 30, "its pay stays")
		t.eq(DailyData.ReplaceRetired(goals, 4242, 3, 2, nil), false, "a second pass leaves them")
	end)

	t.test("streak bonus grows to 2x at 5 days, then stays", function()
		t.eq(DailyData.StreakMultiplier(0), 1)
		t.eq(DailyData.StreakMultiplier(1), 1)
		t.eq(DailyData.StreakMultiplier(2), 1.25)
		t.eq(DailyData.StreakMultiplier(5), 2)
		t.eq(DailyData.StreakMultiplier(30), 2)
		t.eq(DailyData.Bonus(1, 1), 30)
		t.eq(DailyData.Bonus(1, 5), 60)
	end)

	t.test("days are UTC days", function()
		t.eq(DailyData.Day(0), 0)
		t.eq(DailyData.Day(86399), 0)
		t.eq(DailyData.Day(86400), 1)
		t.eq(DailyData.NextReset(90000), 172800)
	end)

	t.test("goals survive the attribute round trip; junk is dropped", function()
		local goals = DailyData.Roll(777, 20000, 4)
		goals[1].progress = 3
		goals[2].done = true
		goals[2].progress = goals[2].target
		t.eq(DailyData.Decode(DailyData.Encode(goals)), goals)
		t.eq(DailyData.Decode(""), {})
		t.eq(#DailyData.Decode("nope,1,2,3,-,0;fell,4,0,15,-,0"), 1)
	end)

	t.test("goal text", function()
		t.eq(DailyData.GoalText({ kind = "fell", target = 4 }), "Fell 4 trees")
		t.eq(DailyData.GoalText({ kind = "earn", target = 1500 }), "Earn $1,500 selling logs")
		t.eq(DailyData.GoalText({ kind = "sellWood", target = 9, wood = "birch" }), "Sell 9 birch logs")
		t.eq(DailyData.GoalText({ kind = "sellFigured", target = 4 }), "Sell 4 figured logs (read the bark!)")
	end)

	---------------------------------------------------------------------------
	-- The v2 loop's goals (V2_PLAN.md §17, §14 step 7)
	---------------------------------------------------------------------------

	local BiomeData = t.shared("BiomeData")
	local FieldGuide = t.shared("FieldGuide")
	local ItemCatalog = t.shared("ItemCatalog")
	local V2 = DailyData.TiersV2

	t.test("v2: each loop rolls from its own pool; no kind is in both; kinds are letters only", function()
		t.eq(DailyData.ForLoop(1).kinds, DailyData.Kinds)
		t.ok(DailyData.ForLoop(1).tiers == DailyData.Tiers, "v1's sizes")
		t.eq(DailyData.ForLoop(2).kinds, DailyData.KindsV2)
		t.ok(DailyData.ForLoop(2).tiers == V2, "v2's sizes")
		t.ok(DailyData.ForLoop(nil) == DailyData.ForLoop(1), "no loop: v1")
		t.ok(DailyData.ForLoop(3) == DailyData.ForLoop(1))
		t.eq(#DailyData.KindsV2, #DailyData.Kinds)
		t.eq(#V2, #DailyData.Tiers, "a size for every axe tier")
		t.eq(#V2, #ItemCatalog.AxeLadder())
		for _, kind in ipairs(DailyData.KindsV2) do
			t.ok(not table.find(DailyData.Kinds, kind), kind .. " is in both pools")
			t.ok(string.match(kind, "^%a+$"), kind .. ": the attribute only reads letters")
		end
	end)

	t.test("v2: three different kinds, sized to the v2 tier, starting at zero; v1's roll is untouched", function()
		for tier = 1, #V2 do
			for day = 1, 30 do
				local goals = DailyData.Roll(day * 97, day, tier, 2)
				t.eq(#goals, DailyData.GoalsPerDay)
				local seen = {}
				for _, goal in ipairs(goals) do
					t.ok(table.find(DailyData.KindsV2, goal.kind), "a v1 kind under v2: " .. goal.kind)
					t.ok(not seen[goal.kind], "duplicate kind " .. goal.kind)
					seen[goal.kind] = true
					t.ok(goal.target > 0 and goal.progress == 0 and not goal.done)
					t.eq(goal.reward, V2[tier].reward)
					local s = V2[tier]
					local expected = ({
						fellTrees = s.trees,
						sellVolume = s.volume,
						earnCash = s.cash,
						sellWoodVolume = math.ceil(s.volume / 2),
						sellPieces = s.pieces,
						plantSeeds = s.seeds,
						sellFiguredVolume = s.figured,
						visitNewArea = 1, -- Discover a new area: one
					})[goal.kind]
					t.eq(goal.target, expected, goal.kind .. " at tier " .. tier)
					if goal.kind == "sellWoodVolume" then
						t.ok(
							table.find(DailyData.WoodsForV2(tier), goal.wood),
							"a wood the tier cuts: " .. tostring(goal.wood)
						)
					else
						t.eq(goal.wood, nil)
					end
				end
				t.eq(DailyData.Roll(day * 97, day, tier), DailyData.Roll(day * 97, day, tier, 1), "no loop: v1's goals")
				for _, goal in ipairs(DailyData.Roll(day * 97, day, tier)) do
					t.ok(table.find(DailyData.Kinds, goal.kind), "v1 rolls v1 kinds")
				end
			end
		end
		t.eq(DailyData.Roll(12345, 20000, 3, 2), DailyData.Roll(12345, 20000, 3, 2), "the same all day")
	end)

	t.test("v2: wood goals ask for wood one of the tier's axes cuts at a useful pace, in the world, by day", function()
		local ladder = ItemCatalog.AxeLadder()
		local previous = {}
		for tier = 1, #V2 do
			local woods = DailyData.WoodsForV2(tier)
			t.ok(#woods > 0, "tier " .. tier .. " has woods")
			for _, wood in ipairs(WoodData.All()) do
				local biome = BiomeData.Get(wood.biome)
				local quick = false
				for i = 1, tier do
					quick = quick or FieldGuide.TrunkHits(ladder[i], wood) <= FieldGuide.UsefulHitsV2
				end
				local expected = biome ~= nil and biome.area ~= nil and not biome.nightOnly and quick
				t.eq(table.find(woods, wood.id) ~= nil, expected, "tier " .. tier .. ": " .. wood.id)
			end
			for _, id in ipairs(previous) do
				t.ok(table.find(woods, id), "tier " .. tier .. " keeps " .. id .. ": axes are never lost")
			end
			previous = woods
		end
		t.eq(DailyData.WoodsForV2(1), { WoodData.All()[1].id }, "the starter axe: the starter forest's oak")
	end)

	t.test("v2: bigger tiers mean bigger goals and rewards", function()
		for i = 2, #V2 do
			local a, b = V2[i - 1], V2[i]
			t.ok(b.reward > a.reward, "reward tier " .. i)
			for _, field in ipairs({ "trees", "volume", "cash", "seeds", "figured", "pieces" }) do
				t.ok(b[field] >= a[field], field .. " tier " .. i)
			end
		end
	end)

	t.test("v2 (§17): a day's goals and bonus help toward the next axe, never buy it outright", function()
		local ladder = ItemCatalog.AxeLadder()
		for tier = 1, #V2 do
			local nextAxe = ladder[tier + 1]
			if nextAxe and nextAxe.sold ~= false then
				local day = DailyData.GoalsPerDay * V2[tier].reward + DailyData.Bonus(tier, 1, 2)
				local price = nextAxe.v2.price
				t.ok(day < price, string.format("tier %d: a day's %d buys the %s (%d)", tier, day, nextAxe.id, price))
				t.ok(day >= 0.05 * price, string.format("tier %d: a day's %d is nothing next to %d", tier, day, price))
			end
		end
	end)

	t.test("v2: a volume goal is worth about a cash goal at the tier's woods", function()
		for tier = 1, #V2 do
			local low, high = math.huge, 0
			for _, id in ipairs(DailyData.WoodsForV2(tier)) do
				local price = WoodData.Get(id).v2.logPrice
				low, high = math.min(low, price), math.max(high, price)
			end
			local s = V2[tier]
			t.ok(s.volume * low <= s.cash * 1.25, "tier " .. tier .. ": the cheapest wood pays too much")
			t.ok(s.volume * high >= s.cash * 0.75, "tier " .. tier .. ": the best wood pays too little")
		end
	end)

	t.test("v2: the bonus uses v2's rewards; without a loop it's v1's", function()
		for tier = 1, #V2 do
			t.eq(DailyData.Bonus(tier, 1, 2), V2[tier].reward * 2)
			t.eq(DailyData.Bonus(tier, 5, 2), V2[tier].reward * 4)
			t.eq(DailyData.Bonus(tier, 3), DailyData.Bonus(tier, 3, 1))
			t.eq(DailyData.Bonus(tier, 1), DailyData.Tiers[tier].reward * 2)
		end
	end)

	t.test("v2: what each event adds to each goal", function()
		local function goal(kind, wood)
			return { kind = kind, target = 10, progress = 0, reward = 1, wood = wood, done = false }
		end
		local sale = {
			volume = 26.5,
			cash = 39,
			byWood = { oak = 20, birch = 6.5 },
			pieces = { 0.4, 1, 4.4, 20.7 },
			figured = 6.5,
		}
		local function count(kind, event, amount, s, wood)
			return DailyData.CountV2(goal(kind, wood), event, amount, s)
		end
		t.eq(count("fellTrees", "treeFelled"), 1, "one tree")
		t.eq(count("fellTrees", "treeFelled", 2), 2)
		t.eq(count("plantSeeds", "treeFelled"), 0, "a retired kind counts nothing")
		t.eq(count("sellVolume", "woodSold", nil, sale), 26.5, "u³")
		t.eq(count("earnCash", "woodSold", nil, sale), 39, "$")
		t.eq(count("sellWoodVolume", "woodSold", nil, sale, "birch"), 6.5, "that wood's")
		t.eq(count("sellWoodVolume", "woodSold", nil, sale, "pine"), 0)
		t.eq(count("sellPieces", "woodSold", nil, sale), 3, "pieces of MinPieceVolumeV2 or more")
		t.eq(DailyData.MinPieceVolumeV2, 1)
		t.eq(count("sellFiguredVolume", "woodSold", nil, sale), 6.5)
		-- The wrong event, a v1 goal, or junk: nothing.
		t.eq(count("fellTrees", "woodSold", nil, sale), 0)
		t.eq(count("sellVolume", "treeFelled", 1), 0)
		t.eq(count("sellVolume", "woodSold", nil, nil), 0, "a sale with no facts")
		for _, v1 in ipairs(DailyData.Kinds) do
			for _, event in ipairs({ "treeFelled", "seedPlanted", "woodSold" }) do
				t.eq(count(v1, event, 1, sale, "oak"), 0, v1 .. " counts nothing under v2")
			end
		end
		local junk =
			{ volume = 0 / 0, cash = -5, byWood = { oak = math.huge }, pieces = { 0 / 0, "4", -2 }, figured = "x" }
		for _, kind in ipairs(DailyData.KindsV2) do
			t.eq(count(kind, "woodSold", nil, junk, "oak"), 0, kind .. " with junk numbers")
		end
		t.eq(count("fellTrees", "treeFelled", -3), 0)
		t.eq(count("fellTrees", "treeFelled", 0 / 0), 0)
	end)

	t.test("v2: a day rolled under the other loop rolls again (V2_PLAN §14 step 7)", function()
		local v1 = DailyData.Roll(777, 20000, 2)
		local v2 = DailyData.Roll(777, 20000, 2, 2)
		t.eq(DailyData.NeedsReroll(v1, 2), true, "v1 goals on a v2 server")
		t.eq(DailyData.NeedsReroll(v2, 2), false)
		t.eq(DailyData.NeedsReroll(v2, 1), true, "a rollback to v1")
		t.eq(DailyData.NeedsReroll(v1, 1), false)
		t.eq(DailyData.NeedsReroll(v1), false, "no loop: v1")
		t.eq(DailyData.NeedsReroll({}, 2), false, "no goals yet: the day rolls anyway")
	end)

	t.test("v2: goals survive the attribute round trip, progress in whole units", function()
		local goals = DailyData.Roll(777, 20000, 4, 2)
		goals[1].progress = 3.7
		goals[2].done = true
		goals[2].progress = goals[2].target
		local back = DailyData.Decode(DailyData.Encode(goals))
		t.eq(#back, #goals, "every v2 kind decodes")
		t.eq(back[1].progress, 3, "u³ and dollars round down on the client")
		back[1].progress = goals[1].progress
		t.eq(back, goals)
		local text = DailyData.Encode({
			{ kind = "sellWoodVolume", target = 20, progress = 0, reward = 15, wood = "birch", done = false },
		})
		t.eq(DailyData.Decode(text)[1].wood, "birch")
	end)

	t.test("v2: goal and progress text in, dollars and pieces", function()
		local V, C = FieldGuide.VolumeText, FieldGuide.CashText
		local function g(kind, target, progress, wood)
			return { kind = kind, target = target, progress = progress or 0, reward = 1, wood = wood, done = false }
		end
		t.eq(DailyData.GoalText(g("fellTrees", 3)), "Fell 3 trees")
		t.eq(DailyData.GoalText(g("fellTrees", 1)), "Fell a tree")
		t.eq(DailyData.GoalText(g("sellVolume", 40)), "Sell " .. V(40) .. " of wood")
		t.eq(DailyData.GoalText(g("earnCash", 1000)), "Earn " .. C(1000) .. " selling wood")
		t.eq(DailyData.GoalText(g("sellWoodVolume", 20, 0, "birch")), "Sell " .. V(20) .. " of birch")
		t.eq(DailyData.GoalText(g("sellPieces", 6)), "Sell 6 logs of " .. V(DailyData.MinPieceVolumeV2) .. " or more")
		t.eq(DailyData.GoalText(g("sellFiguredVolume", 10)), "Sell " .. V(10) .. " of figured wood (read the bark!)")
		t.eq(DailyData.ProgressText(g("sellVolume", 40, 12.8)), "(12/40)")
		t.eq(DailyData.ProgressText(g("earnCash", 60, 23.5)), "(" .. C(23.5) .. "/" .. C(60) .. ")")
		t.eq(DailyData.ProgressText(g("earnCash", 60, 23)), "($23/$60)")
		t.eq(DailyData.ProgressText(g("fellTrees", 3, 1)), "(1/3)")
		t.eq(DailyData.ProgressText(g("sellPieces", 6, 9)), "(6/6)", "never past the target")
		t.eq(DailyData.ProgressText(g("sell", 12, 4)), "(4/12)", "v1 kinds as DailyUI shows them")
		for _, kind in ipairs(DailyData.KindsV2) do
			local text = DailyData.GoalText(g(kind, 5, 0, "oak"))
			t.ok(#text > 0 and not string.find(text, "  ", 1, true), kind .. ": " .. text)
			-- Only the pieces goal counts logs; the rest are, dollars, trees, seeds.
			t.eq(string.find(text, "logs", 1, true) ~= nil, kind == "sellPieces", kind .. ": " .. text)
		end
	end)

	t.test("the daily-return calendar: consecutive days climb to a day-7 milestone, a gap restarts it", function()
		local day, pays = DailyData.LoginStep(nil, nil, 100)
		t.eq({ day, pays }, { 1, true }, "first ever sign-in")
		day, pays = DailyData.LoginStep(1, 99, 100)
		t.eq({ day, pays }, { 2, true })
		day, pays = DailyData.LoginStep(2, 100, 100)
		t.eq({ day, pays }, { 2, false }, "paid once a day")
		day, pays = DailyData.LoginStep(7, 99, 100)
		t.eq({ day, pays }, { 1, true }, "after day 7 it starts over")
		day, pays = DailyData.LoginStep(5, 90, 100)
		t.eq({ day, pays }, { 1, true }, "a missed day restarts it")
	end)

	t.test("the calendar's cash escalates, stays modest, and day 7 is the biggest", function()
		for _, loop in ipairs({ 1, 2 }) do
			for tier = 1, #DailyData.Tiers do
				local previous = 0
				for day = 1, DailyData.LoginDays do
					local reward = DailyData.LoginReward(tier, day, loop)
					t.ok(reward >= previous, "never drops")
					previous = reward
				end
				local one = DailyData.Roll(1, 1, tier, if loop == 2 then 2 else nil)[1].reward
				t.ok(DailyData.LoginReward(tier, DailyData.LoginDays, loop) <= one * 5, "at most 5 goals' worth")
				t.ok(DailyData.LoginReward(tier, 7, loop) > DailyData.LoginReward(tier, 6, loop), "milestone")
			end
		end
		t.eq(DailyData.LoginReward(1, 1, 2), 15)
		t.eq(DailyData.LoginReward(1, 7, 2), 75)
	end)
end
