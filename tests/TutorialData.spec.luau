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

	---------------------------------------------------------------------------
	-- The v2 loop's steps (V2_PLAN.md §13)
	---------------------------------------------------------------------------

	local FieldGuide = t.shared("FieldGuide")
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local V2 = TutorialData.StepsV2
	local V2_EVENTS = {}
	for _, event in ipairs(TutorialData.EventsV2) do
		V2_EVENTS[event] = true
	end
	local V2_BEACONS = { tree = true, wood = true, truckBed = true, sellPad = true, stump = true, toolShed = true }

	local function ids(steps)
		local out = {}
		for _, step in ipairs(steps) do
			table.insert(out, step.id)
		end
		return out
	end

	t.test("v2: the same step ids in the same order (they're save keys)", function()
		t.eq(ids(V2), ids(TutorialData.Steps))
		t.eq(#V2, #TutorialData.Steps)
	end)

	t.test("v2: ForLoop picks the list, v1's for anything but 2", function()
		t.ok(TutorialData.ForLoop(2) == V2, "the v2 loop")
		t.ok(TutorialData.ForLoop(1) == TutorialData.Steps, "the v1 loop")
		t.ok(TutorialData.ForLoop(0) == TutorialData.Steps)
		t.ok(TutorialData.ForLoop(3) == TutorialData.Steps)
	end)

	t.test("v2: every step is well formed and listens to a v2 event", function()
		for i, step in ipairs(V2) do
			t.ok(V2_EVENTS[step.event], step.id .. " has an unknown v2 event " .. tostring(step.event))
			t.eq(step.event, TutorialData.EventsV2[i], step.id .. ": EventsV2 lists the steps' events in order")
			t.ok(step.beacon == nil or V2_BEACONS[step.beacon], step.id .. " has an unknown beacon")
			t.ok(
				step.beacon ~= "log" and step.beacon ~= "truck",
				step.id .. ": v1's log and truck beacons find v1 things"
			)
			t.ok(step.count >= 1, step.id .. " count")
			t.ok(#step.objective > 0 and #step.murph > 0, step.id .. " text")
			t.ok(step.beaconWood == nil or WoodData.Get(step.beaconWood) ~= nil, step.id .. ": beaconWood is a wood")
			t.ok(step.unit == nil or step.unit == "cash", step.id .. ": unit")
		end
		t.eq(V2[1].event, "treeFelled", "it starts with chopping")
		t.eq(V2[1].beacon, "tree")
		t.eq(V2[1].beaconWood, "oak", "Murph points at an oak")
		t.eq(V2[#V2].event, "axeBought", "it ends by buying the Steel Axe")
		t.eq(#TutorialData.EventsV2, #V2)
	end)

	t.test("v2: the plant step sits where v1's does, so the seed and stump rules hold for both", function()
		local plant = TutorialData.PlantStep
		t.eq(V2[plant].id, "plant")
		t.eq(V2[plant].event, "seedPlanted")
		t.eq(V2[plant].objective, TutorialData.Steps[plant].objective, "unchanged")
		t.eq(V2[plant].murph, TutorialData.Steps[plant].murph, "unchanged")
		t.eq(V2[plant - 1].id, "sell", "right after the first sale")
	end)

	t.test("v2: Murph's device words expand everywhere; the drag beat says how to put the axe away", function()
		local HintLogic = t.shared("HintLogic")
		for _, step in ipairs(V2) do
			t.ok(not HintLogic.HasToken(step.objective), step.id .. ": the tracker shows its objective as is")
			for _, device in ipairs(HintLogic.Devices) do
				local said = HintLogic.Expand(step.murph, device)
				t.ok(not HintLogic.HasToken(said), device .. ": " .. said)
				t.ok(not string.find(said, "[{}]"), device .. ": a brace left in " .. said)
			end
			local bare = string.gsub(step.murph, "{%a+}", "")
			t.ok(not string.find(string.lower(bare), "%f[%a]click%f[%A]"), "a bare click in: " .. step.murph)
			t.ok(not string.find(string.lower(bare), "%f[%a]tap%f[%A]"), "a bare tap in: " .. step.murph)
		end
		local drag = V2[2].murph
		t.ok(string.find(drag, "{unequip}", 1, true), "how to put the axe away, per device")
		t.ok(string.find(drag, "{grab}", 1, true), "how to start a drag, per device")
		t.ok(string.find(HintLogic.Expand(drag, "desktop"), "(press 1)", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "phone"), "tap and hold on a log", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "console"), "hold LT on a log", 1, true))
		local first = V2[1].murph
		t.ok(string.find(HintLogic.Expand(first, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(string.find(first, "south of town, past the parking lot", 1, true), "it points the way to the woods")
		t.ok(string.find(V2[3].murph, "Cut it to fit", 1, true), "the load beat: cut it to fit the bed")
		t.ok(string.find(V2[4].murph, "SELL LOGS HERE", 1, true), "the sell beat names the pad as it reads")
	end)

	t.test("v2: every number Murph says comes from the v2 data", function()
		local ladder = t.shared("ItemCatalog").AxeLadder()
		local starter, steel = ladder[1], ladder[2]
		local oak, birch = WoodData.Get("oak"), WoodData.Get("birch")
		local said = {
			[FieldGuide.TrunkHits(starter, oak)] = true,
			[FieldGuide.TrunkHits(starter, birch)] = true,
			[FieldGuide.TrunkHits(steel, oak)] = true,
		}
		for _, step in ipairs(V2) do
			for n in string.gmatch(step.murph, "%d+") do
				t.ok(said[tonumber(n)], step.id .. ": " .. n .. " isn't from the data in: " .. step.murph)
			end
		end
		local function has(line, n)
			return string.find(line, "%f[%d]" .. n .. "%f[%D]") ~= nil
		end
		t.ok(has(V2[1].murph, FieldGuide.TrunkHits(starter, oak)), "hits for the first oak")
		t.ok(has(V2[6].murph, FieldGuide.TrunkHits(starter, birch)), "the starter axe on birch")
		t.ok(
			string.find(V2[6].murph, starter.displayName, 1, true)
				and string.find(V2[6].murph, steel.displayName, 1, true)
		)
		t.ok(has(V2[7].murph, FieldGuide.TrunkHits(steel, oak)), "the Steel Axe on oak")
		t.ok(has(V2[7].murph, FieldGuide.TrunkHits(starter, oak)), "...against the starter's")
		t.ok(FieldGuide.TrunkHits(steel, oak) < FieldGuide.TrunkHits(starter, oak), "and it's quicker")
	end)

	t.test("v2: the cash path reaches the Steel Axe; Murph's share doesn't buy it", function()
		local steel = t.shared("ItemCatalog").AxeLadder()[2]
		local loads = V2[6]
		t.eq(loads.id, "loads")
		t.eq(loads.event, "woodSoldCash")
		t.eq(loads.unit, "cash", "counted in dollars")
		local reward = TutorialData.TotalReward(2)
		t.ok(reward > 0)
		t.ok(reward < steel.v2.price, "Murph helps, the player earns it")
		t.ok(GameConfig.StartingCash + loads.count + reward >= steel.v2.price, "start + the sold loads + Murph's share")
		t.eq(TutorialData.TotalReward(), TutorialData.TotalReward(1), "no loop: v1's, as the economy model reads it")
	end)

	t.test("v2: the tracker reads a cash step in dollars", function()
		local loads = V2[6]
		local Util = t.shared("Util")
		local function expect(progress)
			return string.format(
				"Sell %s more wood (%s/%s)",
				Util.formatCash(loads.count),
				Util.formatCash(progress),
				Util.formatCash(loads.count)
			)
		end
		t.eq(TutorialData.ObjectiveText(loads, 23), expect(23))
		t.eq(TutorialData.ObjectiveText(loads, 23.7), expect(24), "whole dollars, rounded as the pad pays")
		t.eq(TutorialData.ObjectiveText(loads, loads.count + 40), expect(loads.count), "never past the goal")
		t.eq(TutorialData.ObjectiveText(V2[1], 0), "Chop down a tree", "a one-off step shows no count")
	end)

	t.test("v2: progress carries over only where the event is the same in both lists", function()
		local kept = {}
		for i, step in ipairs(V2) do
			if TutorialData.KeepsProgressV2(i) then
				table.insert(kept, step.id)
			end
		end
		t.eq(kept, { "fell", "plant", "steel" }, "V2_PLAN §14: pickup, load, sell and loads start again")
		t.eq(TutorialData.KeepsProgressV2(0), false)
		t.eq(TutorialData.KeepsProgressV2(#V2 + 1), false)
	end)

	t.test("v2: the Steel Axe step counts as done for a player who already has it", function()
		t.ok(TutorialData.AlreadyDone(V2[#V2], 2))
		t.ok(not TutorialData.AlreadyDone(V2[#V2], 1))
		t.ok(not TutorialData.AlreadyDone(V2[1], 5))
	end)

	-- QuestService as GameServer runs it under v2 (Init with the loop): its
	-- step list is TutorialData.ForLoop(2). The service's own rules (only
	-- the current step's event counts, amounts add up, rewards pay) carry
	-- the v2 steps through unchanged.
	t.test("v2: QuestService walks StepsV2 end to end on the v2 events", function()
		local loader = t.loader()
		local profile = loader:shared("Util").deepCopy(loader:server("ProfileSchema").Template)
		local player = {
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local toasts, marks = {}, {}
		loader = t.loader({
			mocks = {
				TreeService = {},
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				MilestoneService = {
					Mark = function(_, name)
						table.insert(marks, name)
					end,
				},
			},
		})
		local Quest = loader:server("QuestService")
		Quest.Init({ OnServerEvent = { Connect = function() end } }, function(_, message)
			table.insert(toasts, message)
		end, 2)
		local function at()
			return V2[profile.tutorialStep].id
		end
		Quest.Start(player, profile)
		t.eq(at(), "fell")
		Quest.Event(player, "woodGrabbed")
		t.eq(at(), "fell", "only the current step's event counts")
		Quest.Event(player, "treeFelled")
		t.eq(at(), "pickup")
		Quest.Event(player, "logPickedUp")
		t.eq(at(), "pickup", "v1's events count for nothing under v2")
		Quest.Event(player, "woodGrabbed")
		t.eq(at(), "load")
		Quest.Event(player, "woodLoaded")
		t.eq(at(), "sell")
		Quest.Event(player, "woodSold", 3)
		t.eq(at(), "plant", "the first sale, however many pieces")
		Quest.Event(player, "seedPlanted")
		t.eq(at(), "loads")
		local loads = V2[profile.tutorialStep]
		local cash = profile.cash
		Quest.Event(player, "woodSold", 4)
		t.eq(profile.tutorialProgress, 0, "pieces don't count toward dollars")
		Quest.Event(player, "woodSoldCash", loads.count - 1)
		t.eq(player.attrs.TutorialProgress, loads.count - 1)
		t.eq(profile.cash, cash, "no reward yet")
		Quest.Event(player, "woodSoldCash", 30)
		t.eq(at(), "steel")
		t.eq(profile.cash, cash + loads.rewardCash, "Murph's share")
		t.eq(toasts, { string.format("Murph chipped in $%d!", loads.rewardCash) })
		profile.bestAxeTier = 2
		Quest.Event(player, "axeBought")
		t.ok(profile.tutorialDone)
		t.eq(player.attrs.TutorialStep, 0)
		t.eq(marks, { "Finished the tutorial" })
	end)
end
