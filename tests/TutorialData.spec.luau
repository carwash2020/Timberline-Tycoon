--!nocheck
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")
	local TutorialData = t.shared("TutorialData")
	local GameConfig = t.shared("GameConfig")

	local EVENTS = {
		treeFelled = true,
		logPickedUp = true,
		logsLoaded = true,
		logsSold = true,
		seedPlanted = true,
		axeBought = true,
		plotClaimed = true,
		truckBought = true,
	}
	local BEACONS = {
		tree = true,
		log = true,
		truck = true,
		sellPad = true,
		stump = true,
		toolShed = true,
		murphCart = true,
		plotSign = true,
		dealership = true,
	}

	local function idsOf(steps)
		local out = {}
		for _, step in ipairs(steps) do
			table.insert(out, step.id)
		end
		return out
	end

	local function byId(steps, id)
		for _, step in ipairs(steps) do
			if step.id == id then
				return step
			end
		end
		return nil
	end

	t.test("the short tutorial is plot, chop, first sale, then the truck", function()
		t.eq(idsOf(TutorialData.Steps), { "plot", "fell", "sell", "truck" })
		t.eq(TutorialData.Steps[1].event, "plotClaimed")
		t.eq(TutorialData.Steps[1].beacon, "plotSign")
		t.eq(TutorialData.Steps[2].event, "treeFelled")
		t.eq(TutorialData.Steps[2].beacon, "tree")
		t.eq(TutorialData.Steps[2].grove, true)
		local sell = TutorialData.Steps[3]
		t.eq(sell.event, "logsSold")
		t.eq(sell.beacon, "murphCart")
		t.eq(sell.rewardCash, 25, "Murph's bonus is on the first sale")
		t.eq(TutorialData.Steps[4].event, "truckBought")
		t.eq(TutorialData.Steps[4].beacon, "dealership")
		t.eq(TutorialData.TotalReward(), 25)
	end)

	t.test("the short tutorial has no Heartseed beat: plant any time, stumps aren't held", function()
		t.eq(TutorialData.PlantStep, 0)
		for i = 0, #TutorialData.Steps do
			t.eq(TutorialData.CanPlant(i), true, "step " .. i)
			t.eq(TutorialData.StumpHold(i), 0, "hold at step " .. i)
		end
		t.eq(TutorialData.StumpHoldSeconds, 240)
	end)

	t.test("every step is well formed", function()
		local ids = {}
		for _, step in ipairs(TutorialData.Steps) do
			t.ok(not ids[step.id], "duplicate step id " .. step.id)
			ids[step.id] = true
			t.ok(EVENTS[step.event], step.id .. " has unknown event " .. tostring(step.event))
			t.ok(step.beacon == nil or BEACONS[step.beacon], step.id .. " has unknown beacon")
			t.ok(step.count >= 1, step.id .. " count")
			t.ok(#step.objective > 0 and #step.murph > 0, step.id .. " text")
		end
		t.eq(TutorialData.Steps[1].event, "plotClaimed", "it starts with a plot")
		t.eq(TutorialData.Steps[#TutorialData.Steps].event, "truckBought", "and ends with the truck")
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
			local bare = string.gsub(line, "{%a+}", "")
			t.ok(not string.find(string.lower(bare), "%f[%a]click%f[%A]"), "a bare click in: " .. line)
			t.ok(not string.find(string.lower(bare), "%f[%a]tap%f[%A]"), "a bare tap in: " .. line)
		end
		t.ok(tokens >= 1, "the chop line uses one")
		local fell = byId(TutorialData.Steps, "fell").murph
		t.ok(string.find(HintLogic.Expand(fell, "phone"), "Tap, or hold", 1, true), "Tap on a phone")
		t.ok(string.find(HintLogic.Expand(fell, "desktop"), "Click, or hold", 1, true), "Click with a mouse")
		t.ok(string.find(HintLogic.Expand(fell, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(not string.find(fell, "I'm Murph", 1, true), "Murph's tip already said hello")
		t.ok(not string.find(fell, "just to your left", 1, true), "the swing line doesn't repeat the tip")
		local tip = table.concat(t.shared("NPCData").Get("Murph").tips, " ")
		t.ok(string.find(tip, "I'm Murph", 1, true), "the first hello is the tip")
		t.ok(string.find(tip, "just to your left", 1, true), "the tip points at the grove")
	end)

	t.test("rewards help toward the Steel Axe but don't buy it outright", function()
		local reward = TutorialData.TotalReward()
		t.ok(reward > 0)
		t.ok(reward < ItemCatalog.GetAxe("SteelAxe").priceCash)
		t.eq(reward, 25)
	end)

	t.test("objective text shows progress only for counted steps", function()
		local plot = TutorialData.Steps[1]
		t.eq(TutorialData.ObjectiveText(plot, 0), "Claim a free plot")
		local loads = { objective = "Sell %d more logs", count = 18 }
		t.eq(TutorialData.ObjectiveText(loads, 4), "Sell 18 more logs (4/18)")
		t.eq(TutorialData.ObjectiveText(loads, 30), "Sell 18 more logs (18/18)")
	end)

	t.test("a claimed plot and an owned truck skip those steps", function()
		local plot = byId(TutorialData.Steps, "plot")
		local truck = byId(TutorialData.Steps, "truck")
		local fell = byId(TutorialData.Steps, "fell")
		t.ok(TutorialData.AlreadyDone(plot, 1, true))
		t.ok(not TutorialData.AlreadyDone(plot, 1, false))
		t.ok(TutorialData.AlreadyDone(truck, 1, false, true))
		t.ok(not TutorialData.AlreadyDone(truck, 1, false, false))
		t.ok(not TutorialData.AlreadyDone(fell, 5, true, true))
	end)

	t.test("a step that needs two events stores a bit each", function()
		local step = {
			id = "both",
			objective = "Claim a free plot and plant a sapling",
			murph = "Claim one, then plant a sapling on it.",
			event = "plotClaimed",
			count = 1,
			also = "seedPlanted",
		}
		local progress, done = TutorialData.Apply(step, 0, "logsSold", 1)
		t.eq(progress, 0)
		t.eq(done, false)
		progress, done = TutorialData.Apply(step, progress, "plotClaimed", 1)
		t.eq(progress, 1)
		t.eq(done, false)
		t.eq(TutorialData.ObjectiveText(step, progress), "Claim a free plot and plant a sapling (1/2)")
		progress, done = TutorialData.Apply(step, progress, "seedPlanted", 1)
		t.eq(progress, 3)
		t.eq(done, true)
		t.ok(not TutorialData.AlreadyDone(step, 1, true), "the sapling half still waits")
	end)

	---------------------------------------------------------------------------
	-- The v2 loop's steps (V2_PLAN.md §13)
	---------------------------------------------------------------------------

	local FieldGuide = t.shared("FieldGuide")
	local WoodData = t.shared("WoodData")
	local V2 = TutorialData.StepsV2
	local V2_EVENTS = {}
	for _, event in ipairs(TutorialData.EventsV2) do
		V2_EVENTS[event] = true
	end
	local V2_BEACONS = {
		tree = true,
		wood = true,
		truckBed = true,
		sellPad = true,
		stump = true,
		toolShed = true,
		murphCart = true,
		plotSign = true,
		dealership = true,
	}

	t.test("v2: the same step ids in the same order (they're save keys)", function()
		t.eq(idsOf(V2), idsOf(TutorialData.Steps))
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
		t.eq(V2[1].event, "plotClaimed", "it starts with a plot")
		t.eq(V2[1].beacon, "plotSign")
		t.eq(V2[2].event, "treeFelled")
		t.eq(V2[2].beacon, "tree")
		t.eq(V2[2].beaconWood, "oak", "Murph points at an oak")
		t.eq(V2[3].event, "woodSold")
		t.eq(V2[3].rewardCash, 25)
		t.eq(V2[#V2].event, "truckBought")
		t.eq(V2[#V2].beacon, "dealership")
		t.eq(#TutorialData.EventsV2, #V2)
	end)

	t.test("v2: Murph's device words expand everywhere; the cart beat says how to put the axe away", function()
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
		local drag = byId(V2, "sell").murph
		t.ok(string.find(drag, "{unequip}", 1, true), "how to put the axe away, per device")
		t.ok(string.find(drag, "{grab}", 1, true), "how to start a drag, per device")
		t.ok(string.find(HintLogic.Expand(drag, "desktop"), "(press 1)", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "phone"), "tap and hold", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "console"), "hold LT", 1, true))
		local fell = byId(V2, "fell").murph
		t.ok(string.find(HintLogic.Expand(fell, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(not string.find(fell, "I'm Murph", 1, true), "Murph's tip already said hello")
		t.ok(not string.find(fell, "just to your left", 1, true), "the swing line doesn't repeat the tip")
	end)

	t.test("v2: every number Murph says comes from the v2 data", function()
		local ladder = ItemCatalog.AxeLadder()
		local starter = ladder[1]
		local oak = WoodData.Get("oak")
		local truckPrice = ShopLogic.Price(ItemCatalog.GetTruck("Rustbucket"), 2)
		local said = {
			[FieldGuide.TrunkHits(starter, oak)] = true,
			[truckPrice] = true,
		}
		for _, step in ipairs(V2) do
			for n in string.gmatch(step.murph, "%d+") do
				t.ok(said[tonumber(n)], step.id .. ": " .. n .. " isn't from the data in: " .. step.murph)
			end
		end
		local function has(line, n)
			return string.find(line, "%f[%d]" .. n .. "%f[%D]") ~= nil
		end
		t.ok(has(byId(V2, "fell").murph, FieldGuide.TrunkHits(starter, oak)), "hits for the first oak")
		t.eq(truckPrice, 75)
		t.ok(has(byId(V2, "truck").murph, truckPrice), "the Rustbucket's price")
	end)

	t.test("v2: Murph's share doesn't buy the truck or the Steel Axe", function()
		local steel = ItemCatalog.AxeLadder()[2]
		local truck = ShopLogic.Price(ItemCatalog.GetTruck("Rustbucket"), 2)
		local reward = TutorialData.TotalReward(2)
		t.eq(reward, 25)
		t.ok(reward < steel.v2.price, "Murph helps, the player earns the axe")
		t.ok(GameConfig.StartingCash + reward < truck, "the first sale has to earn the rest of the truck")
		t.eq(TutorialData.TotalReward(), TutorialData.TotalReward(1), "no loop: v1's, as the economy model reads it")
	end)

	t.test("v2: a one-off step shows no count", function()
		t.eq(TutorialData.ObjectiveText(V2[1], 0), "Claim a free plot")
		t.eq(TutorialData.ObjectiveText(byId(V2, "sell"), 0), "Sell your first load at Murph's cart")
		t.eq(TutorialData.ObjectiveText(byId(V2, "fell"), 0), "Chop down a tree")
	end)

	t.test("v2: progress carries over only where the event is the same in both lists", function()
		local kept = {}
		for i, step in ipairs(V2) do
			if TutorialData.KeepsProgressV2(i) then
				table.insert(kept, step.id)
			end
		end
		t.eq(kept, { "plot", "fell", "truck" }, "the cart sale counts logs in v1 and pieces in v2")
		t.eq(TutorialData.KeepsProgressV2(0), false)
		t.eq(TutorialData.KeepsProgressV2(#V2 + 1), false)
	end)

	t.test("v2: a claimed plot and an owned truck skip those steps", function()
		local plot = byId(V2, "plot")
		local truck = byId(V2, "truck")
		t.ok(TutorialData.AlreadyDone(plot, 1, true))
		t.ok(not TutorialData.AlreadyDone(plot, 2, false))
		t.ok(TutorialData.AlreadyDone(truck, 1, false, true))
		t.ok(not TutorialData.AlreadyDone(truck, 1, true, false))
		t.ok(not TutorialData.AlreadyDone(V2[2], 5, true, true))
	end)

	-- QuestService as GameServer runs it under v2 (Init with the loop): its
	-- step list is TutorialData.ForLoop(2).
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
		t.eq(at(), "plot")
		Quest.Event(player, "treeFelled")
		t.eq(at(), "plot", "only the current step's event counts")
		Quest.Event(player, "plotClaimed")
		t.eq(at(), "fell")
		Quest.Event(player, "woodGrabbed")
		t.eq(at(), "fell", "dragging isn't a step")
		Quest.Event(player, "treeFelled")
		t.eq(at(), "sell")
		local cash = profile.cash
		Quest.Event(player, "woodSold", 3)
		t.eq(at(), "truck", "the first sale, however many pieces")
		t.eq(profile.cash, cash + 25, "Murph's share")
		t.eq(toasts, { "Murph chipped in $25!" })
		Quest.Event(player, "truckBought")
		t.ok(profile.tutorialDone)
		t.eq(player.attrs.TutorialStep, 0)
		t.eq(marks, { "Finished the tutorial", "Saw a next goal" })
	end)
end
