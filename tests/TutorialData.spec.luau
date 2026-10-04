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

	t.test("the mill is followed by the sell-more loads; there is no plant step", function()
		local ids = {}
		for i, step in ipairs(TutorialData.Steps) do
			ids[step.id] = i
		end
		t.eq(ids.plant, nil)
		t.eq(ids.mill, ids.load + 1, "the sawmill is the trip after the truck")
		t.eq(ids.loads, ids.mill + 1, "the next load follows that haul")
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
		t.eq(TutorialData.Steps[1].event, "plotClaimed", "the tutorial starts with a plot")
		t.eq(TutorialData.Steps[#TutorialData.Steps].event, "axeBought", "the Steel Axe is still a step")
		local order = {}
		for i, step in ipairs(TutorialData.Steps) do
			order[step.id] = i
		end
		t.eq(order.truck, order.sell + 1, "the Rustbucket is the step right after the first sale")
		t.eq(order.fell, order.plot + 1, "then chop")
		t.ok(order.load and order.mill and order.loads and order.steel, "the old lessons stay")
		t.eq(order.plant, nil, "planting is not a step")
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
		t.ok(tokens >= 1, "Murph's chop line uses one")
		local first
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "fell" then
				first = step.murph
			end
		end
		t.ok(string.find(HintLogic.Expand(first, "phone"), "Tap, or hold", 1, true), "Tap on a phone")
		t.ok(string.find(HintLogic.Expand(first, "desktop"), "Click, or hold", 1, true), "Click with a mouse")
		t.ok(string.find(HintLogic.Expand(first, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(not string.find(first, "I'm Murph", 1, true), "Murph's tip already said hello")
		t.ok(not string.find(first, "just to your left", 1, true), "the swing line doesn't repeat the tip")
		local tip = table.concat(t.shared("NPCData").Get("Murph").tips, " ")
		t.ok(string.find(tip, "I'm Murph", 1, true), "the first hello is the tip")
		t.ok(string.find(tip, "just to your left", 1, true), "the tip points at the grove")
	end)

	t.test("rewards help toward the Steel Axe but don't buy it outright", function()
		local reward = TutorialData.TotalReward()
		t.ok(reward > 0)
		t.ok(reward < ItemCatalog.GetAxe("SteelAxe").priceCash)
	end)

	t.test("objective text shows progress only for counted steps", function()
		local fell
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "fell" then
				fell = step
			end
		end
		t.eq(TutorialData.ObjectiveText(fell, 0), "Chop down a tree")
		local loads = { objective = "Sell %d more logs", count = 18 }
		t.eq(TutorialData.ObjectiveText(loads, 4), "Sell 18 more logs (4/18)")
		t.eq(TutorialData.ObjectiveText(loads, 30), "Sell 18 more logs (18/18)")
	end)

	t.test("the Steel Axe step counts as done for a player who already has it", function()
		local steel, plot
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "steel" then
				steel = step
			elseif step.id == "plot" then
				plot = step
			end
		end
		t.ok(TutorialData.AlreadyDone(steel, 2))
		t.ok(not TutorialData.AlreadyDone(steel, 1))
		t.ok(not TutorialData.AlreadyDone(TutorialData.Steps[1], 5))
		t.ok(not TutorialData.AlreadyDone(plot, 2, false))
		t.ok(TutorialData.AlreadyDone(plot, 1, true), "a claimed plot skips the claim-only step")
		local truck
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "truck" then
				truck = step
			end
		end
		t.ok(not TutorialData.AlreadyDone(truck, 1, false, false))
		t.ok(TutorialData.AlreadyDone(truck, 1, false, true), "a truck they own skips the buy")
	end)

	t.test("three short loads add up to the old grind, and the tracker shows the Steel Axe", function()
		local sold, reward = 0, 0
		local ids = {}
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "loads" or step.id == "loads2" or step.id == "loads3" then
				table.insert(ids, step.id)
				t.eq(step.count, 6)
				t.eq(step.axeGoal, true)
				sold += step.count
				reward += step.rewardCash
			end
		end
		t.eq(ids, { "loads", "loads2", "loads3" })
		t.eq(sold, 18)
		t.eq(reward, 25, "the three loads still pay $8, $8 and $9")
		t.eq(TutorialData.TotalReward(), 50, "plus Murph's $25 on the first sale")
		local loads
		for _, step in ipairs(TutorialData.Steps) do
			if step.id == "loads" then
				loads = step
			end
		end
		t.eq(
			TutorialData.ObjectiveText(loads, 2, 40),
			string.format("Sell 6 more logs (2/6) · $40 of $%d to Steel Axe", loads.axePrice)
		)
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
	local GameConfig = t.shared("GameConfig")
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

	local function ids(steps)
		local out = {}
		for _, step in ipairs(steps) do
			table.insert(out, step.id)
		end
		return out
	end

	t.test("v2: the same step ids, with the plot after the first sale", function()
		local want = {
			"fell",
			"pickup",
			"sell",
			"plot",
			"truck",
			"load",
			"mill",
			"loads",
			"loads2",
			"loads3",
			"steel",
		}
		t.eq(ids(V2), want)
		t.eq(#V2, #TutorialData.Steps)
		local v1 = {}
		for _, step in ipairs(TutorialData.Steps) do
			v1[step.id] = true
		end
		for _, id in ipairs(want) do
			t.ok(v1[id], id .. " is still a v1 step")
		end
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
		t.eq(V2[1].event, "treeFelled", "it starts by felling")
		t.eq(V2[1].id, "fell")
		t.eq(V2[1].beacon, "tree")
		local fell
		for _, step in ipairs(V2) do
			if step.id == "fell" then
				fell = step
			end
		end
		t.eq(fell.event, "treeFelled")
		t.eq(fell.beacon, "tree")
		t.eq(fell.beaconWood, "oak", "Murph points at an oak")
		t.eq(V2[#V2].event, "axeBought", "the Steel Axe is still a step")
		local order = {}
		for i, step in ipairs(V2) do
			order[step.id] = i
		end
		t.eq(order.plot, order.sell + 1, "the plot is the step right after the first sale")
		t.eq(order.truck, order.plot + 1, "then the Rustbucket")
		t.eq(#TutorialData.EventsV2, #V2)
	end)

	t.test("v2: the mill is followed by the sell-more loads in both lists", function()
		local function at(steps, id)
			for i, step in ipairs(steps) do
				if step.id == id then
					return i
				end
			end
			return nil
		end
		t.eq(at(V2, "loads"), at(V2, "mill") + 1)
		t.eq(at(TutorialData.Steps, "loads"), at(TutorialData.Steps, "mill") + 1)
		t.eq(at(V2, "plant"), nil)
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
		local function byId(id)
			for _, step in ipairs(V2) do
				if step.id == id then
					return step
				end
			end
			return nil
		end
		local drag = byId("pickup").murph
		t.ok(string.find(drag, "{unequip}", 1, true), "how to put the axe away, per device")
		t.ok(string.find(drag, "{grab}", 1, true), "how to start a drag, per device")
		t.ok(string.find(HintLogic.Expand(drag, "desktop"), "(press 1)", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "phone"), "tap and hold on a log", 1, true))
		t.ok(string.find(HintLogic.Expand(drag, "console"), "hold LT on a log", 1, true))
		local first = byId("fell").murph
		t.ok(string.find(HintLogic.Expand(first, "console"), "Press RT, or hold", 1, true), "RT on a gamepad")
		t.ok(not string.find(first, "I'm Murph", 1, true), "Murph's tip already said hello")
		t.ok(not string.find(first, "just to your left", 1, true), "the swing line doesn't repeat the tip")
		t.ok(string.find(byId("load").murph, "Cut it to fit", 1, true), "the load beat: cut it to fit the bed")
		t.ok(string.find(byId("mill").murph, "SELL LOGS HERE", 1, true), "the mill beat names the pad as it reads")
	end)

	t.test("v2: every number Murph says comes from the v2 data", function()
		local ladder = t.shared("ItemCatalog").AxeLadder()
		local starter, steel = ladder[1], ladder[2]
		local oak, birch = WoodData.Get("oak"), WoodData.Get("birch")
		local said = {
			[FieldGuide.TrunkHits(starter, oak)] = true,
			[FieldGuide.TrunkHits(starter, birch)] = true,
			[FieldGuide.TrunkHits(steel, oak)] = true,
			[t.shared("ShopLogic").Price(t.shared("ItemCatalog").GetTruck("Rustbucket"), 2)] = true,
		}
		for _, step in ipairs(V2) do
			for _, line in ipairs({ step.murph, step.murphShort }) do
				if line then
					for n in string.gmatch(line, "%d+") do
						t.ok(said[tonumber(n)], step.id .. ": " .. n .. " isn't from the data in: " .. line)
					end
				end
			end
		end
		local function has(line, n)
			return string.find(line, "%f[%d]" .. n .. "%f[%D]") ~= nil
		end
		local function byId(id)
			for _, step in ipairs(V2) do
				if step.id == id then
					return step
				end
			end
			return nil
		end
		t.ok(has(byId("fell").murph, FieldGuide.TrunkHits(starter, oak)), "hits for the first oak")
		t.ok(has(byId("loads").murph, FieldGuide.TrunkHits(starter, birch)), "the starter axe on birch")
		t.ok(
			string.find(byId("loads").murph, starter.displayName, 1, true)
				and string.find(byId("loads").murph, steel.displayName, 1, true)
		)
		t.ok(has(byId("steel").murph, FieldGuide.TrunkHits(steel, oak)), "the Steel Axe on oak")
		t.ok(has(byId("steel").murph, FieldGuide.TrunkHits(starter, oak)), "...against the starter's")
		t.ok(FieldGuide.TrunkHits(steel, oak) < FieldGuide.TrunkHits(starter, oak), "and it's quicker")
	end)

	t.test("v2: the cash path reaches the Steel Axe; Murph's share doesn't buy it", function()
		local steel = t.shared("ItemCatalog").AxeLadder()[2]
		local sold = 0
		for _, step in ipairs(V2) do
			if step.event == "woodSoldCash" then
				t.eq(step.unit, "cash", "counted in dollars")
				t.eq(step.axeGoal, true)
				sold += step.count
			end
		end
		t.eq(sold, 120, "three loads of $40, the old $120 grind")
		local reward = TutorialData.TotalReward(2)
		t.ok(reward > 0)
		t.ok(reward < steel.v2.price, "Murph helps, the player earns it")
		t.eq(reward, 50, "the three loads' $25 plus Murph's $25 on the first sale")
		t.ok(GameConfig.StartingCash + sold + reward >= steel.v2.price, "start + the sold loads + Murph's share")
		t.eq(TutorialData.TotalReward(), TutorialData.TotalReward(1), "no loop: v1's, as the economy model reads it")
	end)

	t.test("v2: the tracker reads a cash step in dollars", function()
		local loads
		for _, step in ipairs(V2) do
			if step.id == "loads" then
				loads = step
			end
		end
		local Util = t.shared("Util")
		local function expect(progress)
			return string.format(
				"Sell %s more wood (%s/%s) · $0 of %s to Steel Axe",
				Util.formatCash(loads.count),
				Util.formatCash(progress),
				Util.formatCash(loads.count),
				Util.formatCash(loads.axePrice)
			)
		end
		t.eq(TutorialData.ObjectiveText(loads, 23), expect(23))
		t.eq(TutorialData.ObjectiveText(loads, 23.7), expect(24), "whole dollars, rounded as the pad pays")
		t.eq(TutorialData.ObjectiveText(loads, loads.count + 40), expect(loads.count), "never past the goal")
		local fell
		for _, step in ipairs(V2) do
			if step.id == "fell" then
				fell = step
			end
		end
		t.eq(TutorialData.ObjectiveText(fell, 0), "Chop down a tree", "a one-off step shows no count")
	end)

	t.test("v2: progress carries over only where the event is the same in both lists", function()
		local kept = {}
		for i, step in ipairs(TutorialData.Steps) do
			if TutorialData.KeepsProgressV2(i) then
				table.insert(kept, step.id)
			end
		end
		t.eq(kept, { "plot", "fell", "truck", "steel" }, "pickup, load, the cart, the mill and the loads start again")
		t.eq(TutorialData.KeepsProgressV2(0), false)
		t.eq(TutorialData.KeepsProgressV2(#V2 + 1), false)
	end)

	t.test("v2: the Steel Axe step counts as done for a player who already has it", function()
		local steel, plot
		for _, step in ipairs(V2) do
			if step.id == "steel" then
				steel = step
			elseif step.id == "plot" then
				plot = step
			end
		end
		t.ok(TutorialData.AlreadyDone(steel, 2))
		t.ok(not TutorialData.AlreadyDone(steel, 1))
		t.ok(not TutorialData.AlreadyDone(V2[1], 5), "felling isn't skipped for a better axe")
		t.ok(not TutorialData.AlreadyDone(plot, 2))
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
		Quest.Event(player, "plotClaimed")
		t.eq(at(), "fell", "the claim waits until after the cart")
		Quest.Event(player, "treeFelled")
		t.eq(at(), "pickup")
		Quest.Event(player, "logPickedUp")
		t.eq(at(), "pickup", "v1's events count for nothing under v2")
		Quest.Event(player, "woodGrabbed")
		t.eq(at(), "sell", "the cart, before the plot")
		Quest.Event(player, "woodSold", 1)
		t.eq(at(), "plot", "the sell step completes on the first piece")
		t.eq(profile.cash, 25, "Murph's $25 on that sale")
		Quest.Event(player, "plotClaimed")
		t.eq(at(), "truck")
		Quest.Event(player, "truckBought")
		t.eq(at(), "load")
		Quest.Event(player, "woodLoaded")
		t.eq(at(), "mill")
		Quest.Event(player, "woodSold", 2)
		t.eq(at(), "loads")
		local loads = V2[profile.tutorialStep]
		local cash = profile.cash
		Quest.Event(player, "woodSold", 4)
		t.eq(profile.tutorialProgress, 0, "pieces don't count toward dollars")
		Quest.Event(player, "woodSoldCash", loads.count - 1)
		t.eq(player.attrs.TutorialProgress, loads.count - 1)
		t.eq(profile.cash, cash, "no reward yet")
		Quest.Event(player, "woodSoldCash", 30)
		t.eq(at(), "loads2")
		t.eq(profile.cash, cash + loads.rewardCash, "Murph's share")
		t.eq(toasts, {
			"Murph chipped in $25!",
			string.format("Murph chipped in $%d!", loads.rewardCash),
		})
		Quest.Event(player, "woodSoldCash", V2[profile.tutorialStep].count)
		Quest.Event(player, "woodSoldCash", V2[profile.tutorialStep].count)
		t.eq(at(), "steel")
		profile.bestAxeTier = 2
		Quest.Event(player, "axeBought")
		t.ok(profile.tutorialDone, "the Steel Axe is the last step")
		t.eq(player.attrs.TutorialStep, 0)
		t.eq(marks, { "Finished the tutorial", "Saw a next goal" })
	end)

	t.test("v2: old index to step name, then that name's new index, for every step", function()
		local old = TutorialData.OrderV2Previous
		t.eq(#old, #V2 + 1, "the retired plant step is the extra name")
		for index, name in ipairs(old) do
			local at = TutorialData.RemapV2Step(index)
			local expect = if name == "plant" then "loads" else name
			t.eq(V2[at].id, expect, string.format("old %d %s", index, name))
		end
		t.eq(TutorialData.RemapV2Step(0), 0)
		t.eq(TutorialData.RemapV2Step(#old + 1), #old + 1)
	end)

	t.test("v2: ApplyOrder keeps every later step and starts a plot-step save on fell", function()
		for index, name in ipairs(TutorialData.OrderV2Previous) do
			local record = {
				tutorialStep = index,
				tutorialProgress = 3,
				tutorialDone = false,
				tutorialOrder = 0,
				plot = { claimed = true, tier = 1, placed = {} },
			}
			TutorialData.ApplyOrder(record)
			t.eq(record.tutorialOrder, TutorialData.OrderV2, name)
			t.eq(record.plot.claimed, true, name .. " keeps the plot")
			if index <= 1 then
				t.eq(V2[record.tutorialStep].id, "fell", "still on the old first step: the new order starts by felling")
				t.eq(record.tutorialProgress, 0)
			else
				local expect = if name == "plant" then "loads" else name
				t.eq(V2[record.tutorialStep].id, expect, name)
				t.eq(record.tutorialProgress, 3, name .. " keeps its count")
			end
			-- A second pass leaves the step where the first put it. Index 2 is
			-- the old "fell"; remapping it again would move it, so a stay
			-- at 2 means the version stamp already did its one job.
			record.tutorialStep = 2
			TutorialData.ApplyOrder(record)
			t.eq(record.tutorialStep, 2, name .. " remaps once")
		end
	end)

	t.test("v2: the truck and the Steel Axe show the same cash line, and Murph says to sell more when short", function()
		local function byId(id)
			for _, step in ipairs(V2) do
				if step.id == id then
					return step
				end
			end
			return nil
		end
		local truck, steel = byId("truck"), byId("steel")
		t.eq(
			TutorialData.ObjectiveText(truck, 0, 51),
			"Buy the Rustbucket at the dealership · $51 of $75 to Rustbucket"
		)
		t.eq(
			TutorialData.ObjectiveText(steel, 0, 40),
			string.format(
				"Buy the Steel Axe at the Tool Shed · $40 of %s to Steel Axe",
				t.shared("Util").formatCash(steel.cashPrice)
			)
		)
		t.eq(TutorialData.Beacon(truck, 51), "murphCart")
		t.ok(string.find(TutorialData.MurphLine(truck, false, 51), "my cart", 1, true))
		t.eq(
			TutorialData.MurphLine(truck, false, 51),
			string.format("Sell more wood at my cart first. The Rustbucket is $%d at the dealership.", truck.cashPrice)
		)
		t.eq(TutorialData.Beacon(truck, 75), "dealership")
		t.eq(TutorialData.MurphLine(truck, false, 75), truck.murph, "enough cash: the usual line")
		t.ok(string.find(TutorialData.MurphLine(steel, false, 0), "Sell more wood first", 1, true))
		t.eq(TutorialData.Beacon(steel, 0), steel.beacon, "the Steel Axe still points at the shed")
		t.eq(TutorialData.MurphLine(steel, false, steel.cashPrice), steel.murph)
	end)

	t.test("v2: the thank-you for the sale is only on the step right after sell", function()
		local sellAt = 0
		for i, step in ipairs(V2) do
			if step.id == "sell" then
				sellAt = i
			end
		end
		local function mentions(step)
			local blob =
				string.lower((step.murph or "") .. " " .. (step.murphShort or "") .. " " .. (step.murphBack or ""))
			return string.find(blob, "sale", 1, true) ~= nil
		end
		t.ok(mentions(V2[sellAt + 1]), "the plot step thanks them for the sale")
		t.ok(string.find(V2[sellAt + 1].murph, "That sale's yours", 1, true))
		for i, step in ipairs(V2) do
			if mentions(step) then
				t.eq(i, sellAt + 1, step.id .. " mentions the sale")
			end
		end
		local truck
		for _, step in ipairs(V2) do
			if step.id == "truck" then
				truck = step
			end
		end
		t.eq(
			truck.murph,
			string.format(
				"The Rustbucket is $%d at the dealership. Buy it and it shows up on your plot.",
				truck.cashPrice
			)
		)
	end)

	t.test("the plot line names no direction, and the mill's u³ tip moved to the farewell", function()
		local plot, mill
		for _, step in ipairs(V2) do
			if step.id == "plot" then
				plot = step
			elseif step.id == "mill" then
				mill = step
			end
		end
		t.ok(string.find(plot.murph, "follow the arrow", 1, true))
		for _, word in ipairs({ "east", "west", "north", "south", "left", "right" }) do
			t.ok(not string.find(string.lower(plot.murph), "%f[%a]" .. word .. "%f[%A]"), "the plot line says " .. word)
		end
		t.ok(string.find(mill.murph, "SELL LOGS HERE", 1, true))
		t.ok(not string.find(mill.murph, "u³", 1, true))
		t.ok(not string.find(string.lower(mill.murph), "plank"))
		t.ok(string.find(TutorialData.Farewell, "u³", 1, true))
		t.ok(string.find(string.lower(TutorialData.Farewell), "plank"))
	end)

	t.test("no Murph line is longer than 140 characters", function()
		local HintLogic = t.shared("HintLogic")
		local lines = { TutorialData.Farewell, TutorialData.FarewellBack }
		for _, list in ipairs({ TutorialData.Steps, V2 }) do
			for _, step in ipairs(list) do
				table.insert(lines, step.murph)
				if step.murphBack then
					table.insert(lines, step.murphBack)
				end
				if step.murphShort then
					table.insert(lines, step.murphShort)
				end
			end
		end
		for _, line in ipairs(lines) do
			for _, device in ipairs(HintLogic.Devices) do
				local said = HintLogic.Expand(line, device)
				t.ok(#said <= 140, string.format("%d chars: %s", #said, said))
			end
		end
	end)
end
