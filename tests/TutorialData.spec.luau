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
		t.eq(plant.objective, "Fell a tree, then plant its Heartseed in the stump")
		t.eq(plant.murph, "Cut one, plant one, kid. Plant that seed in the stump and the forest'll thank you.")
	end)

	t.test("seeds wait for the plant step; stumps felled until then are held", function()
		local plant = TutorialData.PlantStep
		t.eq(TutorialData.Steps[plant].id, "plant")
		for i = 1, #TutorialData.Steps do
			t.eq(TutorialData.CanPlant(i), i >= plant, "step " .. i)
			t.eq(TutorialData.StumpHold(i), if i <= plant then 240 else 0, "hold at step " .. i)
		end
		t.ok(TutorialData.CanPlant(0), "finished or skipped: plant any time")
		t.eq(TutorialData.StumpHold(0), 0, "and no held stumps")
		t.eq(TutorialData.StumpHoldSeconds, 240)
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

	t.test("Murph's device words ({click}) expand on every device; the tracker lines have none", function()
		local HintLogic = t.shared("HintLogic")
		local lines = { TutorialData.Farewell }
		for _, step in ipairs(TutorialData.Steps) do
			table.insert(lines, step.murph)
			t.ok(not HintLogic.HasToken(step.objective), step.id .. ": the tracker shows its objective as is")
		end
		local tokens = 0
		for _, line in ipairs(lines) do
			if HintLogic.HasToken(line) then
				tokens += 1
				for _, device in ipairs(HintLogic.Devices) do
					local said = HintLogic.Expand(line, device)
					t.ok(not HintLogic.HasToken(said), device .. ": " .. said)
					t.ok(not string.find(said, "[{}]"), device .. ": a brace left in " .. said)
				end
			end
			-- Device words only through a token: no bare "click" or "tap".
			local bare = string.gsub(line, "{%a+}", "")
			t.ok(not string.find(string.lower(bare), "%f[%a]click%f[%A]"), "a bare click in: " .. line)
			t.ok(not string.find(string.lower(bare), "%f[%a]tap%f[%A]"), "a bare tap in: " .. line)
		end
		t.ok(tokens >= 1, "Murph's first line uses one")
		local first = TutorialData.Steps[1].murph
		t.ok(string.find(HintLogic.Expand(first, "phone"), "Tap, or hold", 1, true), "Tap on a phone")
		t.ok(string.find(HintLogic.Expand(first, "desktop"), "Click, or hold", 1, true), "Click with a mouse")
		t.ok(string.find(HintLogic.Expand(first, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(string.find(first, "south of town, past the parking lot", 1, true), "it points the way to the woods")
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
