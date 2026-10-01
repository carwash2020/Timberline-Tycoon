--!nocheck
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local TutorialData = t.shared("TutorialData")

	local EVENTS = {
		treeFelled = true,
		logPickedUp = true,
		logsLoaded = true,
		logsSold = true,
		seedPlanted = true,
		axeBought = true,
	}
	local BEACONS = { tree = true, log = true, truck = true, sellPad = true, stump = true, toolShed = true }

	t.test("right after the first sale, Murph teaches planting a Heartseed", function()
		local ids = {}
		for i, step in ipairs(TutorialData.Steps) do
			ids[step.id] = i
		end
		t.ok(ids.plant ~= nil, "there's a planting beat")
		t.eq(ids.plant, ids.sell + 1, "it comes right after the first sale")
		local plant = TutorialData.Steps[ids.plant]
		t.eq(plant.event, "seedPlanted")
		t.eq(plant.count, 1)
		t.eq(plant.objective, "Plant a Heartseed in a stump")
		t.eq(plant.murph, "Cut one, plant one, kid. Plant that seed in the stump and the forest'll thank you.")
	end)

	t.test("every step is well formed", function()
		local ids = {}
		for i, step in ipairs(TutorialData.Steps) do
			t.ok(not ids[step.id], "duplicate step id " .. step.id)
			ids[step.id] = true
			t.ok(EVENTS[step.event], step.id .. " has unknown event " .. tostring(step.event))
			t.ok(step.beacon == nil or BEACONS[step.beacon], step.id .. " has unknown beacon")
			t.ok(step.count >= 1, step.id .. " count")
			t.ok(#step.objective > 0 and #step.murph > 0, step.id .. " text")
			t.ok(i > 1 or step.event == "treeFelled", "the tutorial starts with chopping")
		end
		t.eq(TutorialData.Steps[#TutorialData.Steps].event, "axeBought", "it ends by buying the Steel Axe")
	end)

	t.test("rewards help toward the Steel Axe but don't buy it outright", function()
		local reward = TutorialData.TotalReward()
		t.ok(reward > 0)
		t.ok(reward < ItemCatalog.GetAxe("SteelAxe").priceCash)
	end)

	t.test("objective text shows progress only for counted steps", function()
		local fell = TutorialData.Steps[1]
		t.eq(TutorialData.ObjectiveText(fell, 0), "Chop down a tree")
		local loads = { objective = "Sell %d more logs", count = 18 }
		t.eq(TutorialData.ObjectiveText(loads, 4), "Sell 18 more logs (4/18)")
		t.eq(TutorialData.ObjectiveText(loads, 30), "Sell 18 more logs (18/18)")
	end)

	t.test("the Steel Axe step counts as done for a player who already has it", function()
		local steel = TutorialData.Steps[#TutorialData.Steps]
		t.ok(TutorialData.AlreadyDone(steel, 2))
		t.ok(not TutorialData.AlreadyDone(steel, 1))
		t.ok(not TutorialData.AlreadyDone(TutorialData.Steps[1], 5))
	end)
end
