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
				t.ok(id ~= "palmwood" and id ~= "lumenwood", "only woods in the world")
			end
		end
	end)

	t.test("bigger tiers mean bigger goals and rewards", function()
		for i = 2, #DailyData.Tiers do
			local a, b = DailyData.Tiers[i - 1], DailyData.Tiers[i]
			t.ok(b.reward > a.reward, "reward tier " .. i)
			t.ok(b.cash >= a.cash and b.logs >= a.logs and b.trees >= a.trees, "size tier " .. i)
		end
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
	end)
end
