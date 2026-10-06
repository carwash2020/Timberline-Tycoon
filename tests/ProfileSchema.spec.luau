--!nocheck
-- The save template and migrating older saves.
return function(t)
	local function fresh()
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		return Schema, Util.deepCopy(Schema.Template)
	end

	-- Migrate stamps the active slot's lastPlayed with the clock, so two runs a
	-- second apart differ there. For "migrating again changes nothing" checks,
	-- carry that stamp across and compare everything else.
	local function sameClock(before, data)
		if type(data.slots) == "table" and type(before.slots) == "table" then
			for key, slot in pairs(data.slots) do
				if type(before.slots[key]) == "table" then
					before.slots[key].lastPlayed = slot.lastPlayed
				end
			end
		end
	end

	t.test("a new save gets one Rusty Axe, equipped by nobody yet", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		t.eq(#data.axes, 1)
		t.eq(data.axes[1].id, "RustyAxe")
		t.ok(type(data.axes[1].uid) == "string" and #data.axes[1].uid > 0)
		t.eq(data.bestAxeTier, 1)
		t.eq(data.cash, 0)
	end)

	t.test("old saves listing axe ids become items, keeping the equipped one", function()
		local Schema, data = fresh()
		data.ownedAxes = { "RustyAxe", "SteelAxe" }
		data.equippedAxe = "SteelAxe"
		Schema.Migrate(data)
		t.eq(#data.axes, 2)
		t.eq(data.ownedAxes, nil)
		t.eq(data.bestAxeTier, 2)
		local equipped
		for _, item in ipairs(data.axes) do
			if item.uid == data.equippedAxe then
				equipped = item
			end
		end
		t.ok(equipped, "equippedAxe must name one of the new uids")
		t.eq(equipped.id, "SteelAxe")
	end)

	t.test("a new save has an unclaimed Campsite plot", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		t.eq(data.plot, { claimed = false, tier = 1, placed = {}, squares = {}, wires = {}, switches = {} })
	end)

	t.test("saves from before plots lose the old size and any old-format items", function()
		local Schema, data = fresh()
		data.plot = {
			claimed = false,
			size = 120,
			tier = 1, -- Reconcile adds the new field
			placed = {
				{ uid = "old", blueprintId = "Fence", cframe = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 } },
				{ uid = "new", blueprintId = "Fence", x = 2, z = 4, rot = 1 },
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.size, nil)
		t.eq(#data.plot.placed, 1)
		t.eq(data.plot.placed[1].uid, "new")
	end)

	t.test("a plot save with a bad tier or non-finite positions is made safe", function()
		local Schema, data = fresh()
		data.plot = {
			claimed = "yes",
			tier = 9,
			placed = {
				{ uid = "nan", blueprintId = "Fence", x = 0 / 0, z = 1, rot = 0 },
				{ uid = "inf", blueprintId = "Fence", x = math.huge, z = 0, rot = 0 },
				{ uid = "", blueprintId = "Fence", x = 1, z = 1, rot = 0 },
				{ blueprintId = "Fence", x = 1, z = 1, rot = 0 },
				{ uid = "ok", blueprintId = "Fence", x = 2, z = 4, rot = 5.9 },
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.claimed, false)
		t.eq(data.plot.tier, 1)
		t.eq(#data.plot.placed, 1)
		t.eq(data.plot.placed[1].uid, "ok")
		t.eq(data.plot.placed[1].rot, 1)
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].rot, 1)
		t.eq(data.plot.tier, 1)
		t.eq(data.plot.claimed, false)
	end)

	t.test("migrating twice changes nothing", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		sameClock(before, data)
		t.eq(data, before)
	end)

	t.test("receipts: new ones are recorded once; the cache keeps the latest", function()
		local Schema, data = fresh()
		t.ok(Schema.RecordPurchase(data, "a"))
		t.ok(not Schema.RecordPurchase(data, "a"), "a retry is not new")
		for i = 1, Schema.PurchaseIdCacheSize + 5 do
			Schema.RecordPurchase(data, "id" .. i)
		end
		t.eq(#data.purchaseIds, Schema.PurchaseIdCacheSize)
		t.ok(not Schema.RecordPurchase(data, "id" .. (Schema.PurchaseIdCacheSize + 5)), "recent ids are kept")
	end)

	t.test("bestAxeTier never goes down, and unknown axe ids don't break it", function()
		local Schema, data = fresh()
		data.bestAxeTier = 6
		data.axes = { { uid = "a", id = "SteelAxe" }, { uid = "b", id = "RemovedAxe" } }
		Schema.Migrate(data)
		t.eq(data.bestAxeTier, 6)
	end)

	t.test("Migrate turns old Sky Bin wood ids into priced entries", function()
		local Schema = t.loader():server("ProfileSchema")
		local WoodData = t.loader():shared("WoodData")
		local data = t.loader():shared("Util").deepCopy(Schema.Template)
		data.skyBin = { "lumenwood", { woodId = "oak", value = 7 } }
		Schema.Migrate(data)
		t.eq(data.skyBin, {
			{ woodId = "lumenwood", value = WoodData.Get("lumenwood").pricePerLog },
			{ woodId = "oak", value = 7 },
		})
	end)

	-- MigrateV2 (V2_PLAN.md §14) --------------------------------------------

	local function v1Save()
		local Schema, data = fresh()
		Schema.Migrate(data)
		data.cash = 500
		data.truckBed = { { woodId = "oak", value = 12 }, { woodId = "birch", value = 30.4, figure = "curly" } }
		data.truckAt = { x = 1, y = 2, z = 3 }
		data.leftLoad = { { woodId = "pine", value = 18, x = 0, y = 0, z = 0 } }
		data.skyBin = { { woodId = "lumenwood", value = 400 } }
		data.forgeLogs = { lumenwood = 12 }
		return Schema, data
	end

	t.test("MigrateV2 buys back the bed, left-behind logs and Sky Bin, empties them, keeps cash", function()
		local Schema, data = v1Save()
		local r = Schema.MigrateV2(data, 20)
		t.eq(r.boughtBack, 460) -- 12 + 30.4 + 18 + 400, rounded
		t.eq(r.toppedUp, 0)
		t.ok(r.migrated)
		t.eq(data.v2Credit, 460)
		t.eq(data.cash, 500, "Migrate never writes cash")
		t.eq(data.truckBed, {})
		t.eq(data.leftLoad, {})
		t.eq(data.skyBin, {})
		t.eq(data.truckAt, {})
		t.eq(data.schema, 5)
	end)

	t.test("MigrateV2 converts the forge's lumenwood logs to, capped at the recipe, and keeps forgeLogs", function()
		local Schema, data = v1Save()
		Schema.MigrateV2(data, 20)
		t.eq(data.forgeWood.lumenwood, 18) -- 12 logs x 1.5
		t.eq(data.forgeLogs.lumenwood, 12, "kept for a rollback")
		local _, full = v1Save()
		full.forgeLogs = { lumenwood = 55 }
		Schema.MigrateV2(full, 20)
		t.eq(full.forgeWood.lumenwood, 60) -- min(60, 55 x 1.5)
	end)

	t.test("MigrateV2 tops a new or broke save up to StartingCash through the credit", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		local r = Schema.MigrateV2(data, 20)
		t.eq(r.toppedUp, 20)
		t.eq(data.v2Credit, 20)
		t.eq(data.cash, 0)
		local _, poor = fresh()
		Schema.Migrate(poor)
		poor.cash = 5
		poor.truckBed = { { woodId = "oak", value = 6 } }
		local r2 = Schema.MigrateV2(poor, 20)
		t.eq(r2.boughtBack, 6)
		t.eq(r2.toppedUp, 9) -- 5 cash + 6 credit + 9 = 20
		t.eq(poor.v2Credit, 15)
	end)

	t.test("MigrateV2 is idempotent, but drains logs an old server refilled", function()
		local Schema, data = v1Save()
		Schema.MigrateV2(data, 20)
		data.v2Credit = 0 -- GameServer paid it
		local again = Schema.MigrateV2(data, 20)
		t.eq(again.boughtBack, 0)
		t.eq(again.toppedUp, 0)
		t.ok(not again.migrated)
		t.eq(data.v2Credit, 0)
		data.forgeLogs.lumenwood = 30
		data.tutorialProgress = 3
		data.truckBed = { { woodId = "oak", value = 9 } }
		local refilled = Schema.MigrateV2(data, 20)
		t.eq(refilled.boughtBack, 9)
		t.eq(data.v2Credit, 9)
		t.eq(data.truckBed, {})
		t.eq(data.forgeWood.lumenwood, 18, "the forge converts once")
		t.eq(data.tutorialProgress, 3, "progress resets once")
	end)

	t.test("MigrateV2 restarts tutorial progress only on steps whose unit changed, and remaps every v2 step", function()
		local TutorialData = t.loader():shared("TutorialData")
		for index, step in ipairs(TutorialData.Steps) do
			local Schema, data = v1Save()
			data.tutorialStep = index
			data.tutorialProgress = 2
			data.tutorialOrder = 0
			Schema.MigrateV2(data, 20)
			local keeps = TutorialData.KeepsProgressV2(index)
			local landed = if index <= 1 then 1 else TutorialData.RemapV2Step(index)
			t.eq(data.tutorialStep, landed, step.id)
			-- Saved indexes are the plot-first list, which still names the
			-- removed plant step. The steps cut from the short tutorial land on
			-- the next one that remains, or past the end (done).
			local from = TutorialData.OrderV2Previous[index]
			if index <= 1 then
				t.eq(TutorialData.StepsV2[data.tutorialStep].id, "fell", step.id)
			elseif TutorialData.RetiredV2[from] and not TutorialData.StepsV2[landed] then
				t.eq(data.tutorialStep, #TutorialData.StepsV2 + 1, step.id .. ": a cut step past the truck is the end")
			else
				t.eq(TutorialData.StepsV2[data.tutorialStep].id, from, step.id)
			end
			if index <= 1 then
				t.eq(data.tutorialProgress, 0, "the old first step was the plot; the new one is fell")
			else
				t.eq(data.tutorialProgress, if keeps then 2 else 0, step.id)
			end
			t.eq(data.tutorialOrder, TutorialData.OrderV2)
		end
	end)

	t.test("an old v2 save remaps once, including a slot, and a second join leaves the step", function()
		local TutorialData = t.loader():shared("TutorialData")
		local Schema, data = v1Save()
		Schema.MigrateV2(data, 20)
		data.schema = 2
		data.tutorialOrder = 0
		data.tutorialDone = false
		data.tutorialStep = 4 -- old sell
		data.tutorialProgress = 0
		data.slots = {
			{
				tutorialDone = false,
				tutorialStep = 3, -- old pickup
				tutorialProgress = 1,
				tutorialOrder = 0,
				plot = { claimed = true, tier = 1, placed = {} },
			},
		}
		Schema.MigrateV2(data, 20)
		t.eq(TutorialData.StepsV2[data.tutorialStep].id, "sell")
		t.eq(data.tutorialOrder, TutorialData.OrderV2)
		t.eq(TutorialData.StepsV2[data.slots[1].tutorialStep].id, "pickup")
		t.eq(data.slots[1].plot.claimed, true)
		t.eq(data.slots[1].tutorialOrder, TutorialData.OrderV2)
		local step = data.tutorialStep
		Schema.MigrateV2(data, 20)
		t.eq(data.tutorialStep, step, "a second join does not remap again")
	end)

	t.test(
		"Murph's cart is gone: no cart fields or soft-lock helper, and a save on the sell step keeps its step",
		function()
			local Schema, data = fresh()
			t.eq(Schema.UnstickCart, nil)
			t.eq(Schema.Template.cartVolume, nil)
			t.eq(Schema.Template.cartUsed, nil)
			local TutorialData = t.loader():shared("TutorialData")
			local sellAt = 1
			for i, step in ipairs(TutorialData.StepsV2) do
				if step.id == "sell" then
					sellAt = i
				end
			end
			data.tutorialDone = false
			data.tutorialStep = sellAt
			data.tutorialOrder = TutorialData.OrderV2
			data.onboarding = { TutorialCart = true } -- an old save's flag is harmless
			Schema.Migrate(data)
			t.eq(TutorialData.StepsV2[data.tutorialStep].id, "sell")
		end
	)

	t.test("MigrateV2 reopens a finished tutorial as a refresher of the new steps, once", function()
		local Schema, done = v1Save()
		done.tutorialDone = true
		done.tutorialStep = 7
		done.tutorialProgress = 1
		t.eq(done.tutorialRefresher, false, "the template's")
		Schema.MigrateV2(done, 20)
		t.eq(done.tutorialDone, false)
		t.eq(done.tutorialStep, 1)
		t.eq(done.tutorialProgress, 0)
		t.eq(done.tutorialRefresher, true)
		-- Finished again (QuestService), a later join leaves it finished.
		done.tutorialDone = true
		done.tutorialRefresher = false
		Schema.MigrateV2(done, 20)
		t.eq(done.tutorialDone, true, "once only (schema 2)")
		-- Mid-tutorial players carry on where they were, no refresher.
		local _, mid = v1Save()
		mid.tutorialStep = 5
		Schema.MigrateV2(mid, 20)
		-- Step 5 of the plot-first list is the truck; the plot and one build
		-- lesson now sit before it, so the same step is index 6.
		t.eq(mid.tutorialStep, 6)
		t.eq(mid.tutorialRefresher, false)
	end)

	t.test("MigrateV2 rerolls today's v1 daily goals and keeps the streak", function()
		local Schema, data = v1Save()
		data.daily = {
			day = 20000,
			goals = { { kind = "fell", target = 5, progress = 1, reward = 10, done = false } },
			streak = 4,
			bestStreak = 9,
			lastCompleteDay = 19999,
		}
		Schema.MigrateV2(data, 20)
		t.eq(data.daily.day, 0)
		t.eq(data.daily.streak, 4)
		t.eq(data.daily.bestStreak, 9)
		t.eq(data.daily.lastCompleteDay, 19999)
		local _, v2 = v1Save()
		v2.daily = {
			day = 20000,
			goals = { { kind = "fellTrees", target = 5, progress = 1, reward = 10, done = false } },
			streak = 1,
			bestStreak = 1,
			lastCompleteDay = 19999,
		}
		Schema.MigrateV2(v2, 20)
		t.eq(v2.daily.day, 20000, "v2 goals stand")
	end)

	t.test("MigrateV2 keeps axes, trucks, gear, figures and Robux fields, and drops planting", function()
		local Schema, data = v1Save()
		data.axes = { { uid = "a", id = "SteelAxe" }, { uid = "b", id = "CobaltAxe" } }
		data.bestAxeTier = 4
		data.ownedTrucks = { "Rustbucket", "Flatbed" }
		data.gear = { "Lantern" }
		data.heartseeds = { oak = 2 }
		data.forest = { planted = 4, harvested = 2, royalties = 30, figures = { curly = 1 }, elders = 1 }
		data.compendium = { oak = true, birch = true }
		data.doubleWoodUntil = 123
		data.instantDeliveries = 2
		data.cash = 500
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.MigrateV2(data, 20)
		t.eq(data.heartseeds, nil)
		t.eq(data.forest.planted, nil)
		t.eq(data.forest.harvested, nil)
		t.eq(data.forest.royalties, nil)
		t.eq(data.forest.figures, { curly = 1 })
		t.eq(data.forest.elders, 1)
		t.eq(data.cash, 500)
		for _, key in ipairs({
			"axes",
			"bestAxeTier",
			"ownedTrucks",
			"gear",
			"compendium",
			"doubleWoodUntil",
			"instantDeliveries",
			"plot",
			"onboarding",
		}) do
			t.eq(data[key], before[key], key)
		end
	end)

	t.test("MigrateV2 fills its own fields on a save that lacks them and survives junk", function()
		local Schema = t.loader():server("ProfileSchema")
		local data = {
			cash = 50,
			stats = { treesChopped = 1 },
			truckBed = { "oak", { woodId = "oak", value = 0 / 0 }, { woodId = "oak", value = -5 } },
			tutorialStep = 1,
		}
		local r = Schema.MigrateV2(data, 20)
		t.ok(r.boughtBack > 0, "a bare wood id is worth its v1 log price")
		t.eq(data.schema, 5)
		t.eq(data.stats.volumeSold, 0)
		t.eq(data.stats.cuts, 0)
		t.eq(data.forgeWood, {})
		t.eq(data.skyWood, {})
	end)

	t.test("a v2 save still loads under v1: Migrate leaves the v2 fields alone", function()
		local Schema, data = v1Save()
		Schema.MigrateV2(data, 20)
		data.v2Credit = 0
		Schema.Migrate(data)
		t.eq(data.schema, 5)
		t.eq(data.forgeWood.lumenwood, 18)
		t.eq(#data.axes > 0, true)
	end)

	t.test("CreditText: a buy-back, a starter's top-up, nothing", function()
		local Schema = t.loader():server("ProfileSchema")
		t.eq(Schema.CreditText(460, 460), "Murph bought back the logs you had on hand: +$460")
		t.eq(Schema.CreditText(20, 0), "Murph chipped in $20 to get you started.")
		t.eq(Schema.CreditText(0, 0), nil)
	end)

	-- M1.6: the v2 loop's loose wood on the bed (TruckLoad, LeftLoad).
	t.test("truckLoad: a new save has an empty one; Migrate leaves it (and the v1 bed) alone", function()
		local Schema, data = fresh()
		t.eq(data.truckLoad, {})
		Schema.Migrate(data)
		t.eq(data.truckLoad, {})
		-- An older save gets it from Reconcile (a new top-level field); v1's
		-- own bed fields are untouched by it.
		local piece = {
			w = "oak",
			k = "log",
			bed = "BedFloor",
			at = { 0, 1.25, 0, 0, 0, 0 },
			s = { { 2, 9, 2, 0, 0, 0, 0, 0, 0, 3 } },
		}
		data.truckLoad = { piece }
		data.truckBed = { { woodId = "oak", value = 5 } }
		Schema.Migrate(data)
		t.eq(data.truckLoad, { piece })
		t.eq(data.truckBed, { { woodId = "oak", value = 5 } })
	end)

	-- Foundations (schema 5). tollPaidUntil is not a save field.
	local function stripFoundations(data)
		data.storage = nil
		data.permissions = nil
		data.badgesAwarded = nil
		data.badgesSent = nil
		data.questAxe = nil
		data.secretsFound = nil
		data.areasVisited = nil
		data.tollPaidUntil = nil
		if type(data.plot) == "table" then
			data.plot.squares = nil
		end
		if type(data.slots) == "table" then
			for _, slot in ipairs(data.slots) do
				if type(slot) == "table" then
					slot.storage = nil
					slot.permissions = nil
					slot.questAxe = nil
					slot.badgesAwarded = nil
					slot.badgesSent = nil
					slot.secretsFound = nil
					slot.areasVisited = nil
					slot.tollPaidUntil = nil
					if type(slot.plot) == "table" then
						slot.plot.squares = nil
					end
				end
			end
		end
	end

	t.test("an old save gains the foundations fields, and a second migrate matches", function()
		local Schema, data = fresh()
		data.cash = 80
		data.schema = 4
		data.plot.claimed = true
		stripFoundations(data)
		data.tollPaidUntil = 12345
		Schema.Migrate(data)
		t.eq(data.schema, 5)
		t.eq(data.cash, 80)
		t.eq(data.plot.claimed, true)
		-- A played save's starter Rustbucket now comes as a box (one, once).
		t.eq(#data.storage, 1)
		t.eq(data.storage[1].itemId, "Rustbucket")
		t.eq(data.storage[1].shop, "Dealership")
		t.eq(data.plot.squares, {})
		t.eq(data.permissions, {})
		t.eq(data.badgesAwarded, {})
		t.eq(data.badgesSent, {})
		t.eq(data.questAxe, { step = 0 })
		t.eq(data.secretsFound, {})
		t.eq(data.areasVisited, {})
		t.eq(data.tollPaidUntil, nil)
		t.eq(Schema.Template.tollPaidUntil, nil)
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		sameClock(before, data)
		t.eq(data, before)
	end)

	t.test("plot wires: an old save gets an empty list, junk is cleaned, good wires survive", function()
		local Schema, data = fresh()
		t.eq(Schema.Template.plot.wires, {})
		data.plot.wires = nil
		Schema.Migrate(data)
		t.eq(data.plot.wires, {})
		data.plot.wires = { { from = "a", to = "b" }, { from = "a", to = "b" }, { from = 1 }, "x" }
		Schema.Migrate(data)
		t.eq(data.plot.wires, { { from = "a", to = "b" } })
		data.plot.wires = 7
		Schema.Migrate(data)
		t.eq(data.plot.wires, {})
	end)

	t.test("plot switches: old saves get an empty list, junk is cleaned, positions survive", function()
		local Schema, data = fresh()
		t.eq(Schema.Template.plot.switches, {})
		data.plot.switches = nil
		Schema.Migrate(data)
		t.eq(data.plot.switches, {})
		data.plot.switches = { "a", "a", "", 4, "b" }
		Schema.Migrate(data)
		t.eq(data.plot.switches, { "a", "b" })
		data.plot.switches = "on"
		Schema.Migrate(data)
		t.eq(data.plot.switches, {})
		-- Other plot fields are left as they were.
		t.eq(data.plot.wires, {})
		t.eq(data.plot.tier, 1)
	end)

	t.test("a wrong-typed foundations field resets to the default and does not error", function()
		local Schema, data = fresh()
		data.storage = "box"
		data.plot.squares = 4
		data.permissions = 1
		data.badgesAwarded = false
		data.badgesSent = false
		data.questAxe = "done"
		data.secretsFound = 0
		data.areasVisited = "snow"
		Schema.Migrate(data)
		t.eq(data.storage, {})
		t.eq(data.plot.squares, {})
		t.eq(data.permissions, {})
		t.eq(data.badgesAwarded, {})
		t.eq(data.badgesSent, {})
		t.eq(data.questAxe, { step = 0 })
		t.eq(data.secretsFound, {})
		t.eq(data.areasVisited, {})
	end)

	t.test("badgesSent stays on the account and is stripped out of a slot", function()
		local Schema, data = fresh()
		data.badgesSent = { FirstSale = true, bad = 1 }
		data.slots = { {}, { badgesSent = { Stolen = true } } }
		data.activeSlot = 1
		Schema.Migrate(data)
		t.eq(data.badgesSent, { FirstSale = true })
		t.eq(Schema.Template.badgesSent, {})
		for _, slot in ipairs(data.slots) do
			t.eq(slot.badgesSent, nil)
		end
	end)

	t.test("storage keeps the pending mark of a paid box that is not opened, and drops anything else", function()
		local Schema, data = fresh()
		data.storage = {
			{ uid = "a", itemId = "SteelAxe", shop = "ToolShed", pending = true },
			{ uid = "b", itemId = "SteelAxe", shop = "ToolShed" },
			{ uid = "c", itemId = "SteelAxe", shop = "ToolShed", pending = "yes" },
		}
		Schema.Migrate(data)
		local byUid = {}
		for _, box in ipairs(data.storage) do
			byUid[box.uid] = box
		end
		t.eq(byUid.a.pending, true, "the item is still owed")
		t.eq(byUid.b.pending, nil, "an older box: its item was granted at the counter")
		t.eq(byUid.c.pending, nil, "only a real true counts")
	end)

	t.test("storage keeps 50 server uids and drops a box only when its uid is taken", function()
		local Schema, data = fresh()
		data.axes = { { uid = "axe-1", id = "SteelAxe" } }
		data.ownedTrucks = { "Rustbucket" }
		data.plot.placed = { { uid = "cabin", blueprintId = "Cabin", x = 1, z = 2, rot = 0 } }
		local boxes = {
			{ uid = "keep", itemId = "Lantern", shop = "ToolShed" },
			{ uid = "axe-1", itemId = "HeatBoots", shop = "ToolShed" },
			{ uid = "box-truck", itemId = "Rustbucket", shop = "Dealership" },
			{ uid = "cabin", itemId = "Flashlight", shop = "ToolShed" },
			{ uid = "cabin-box", itemId = "Cabin", shop = "Hearth" },
			{ uid = "axe-box", itemId = "SteelAxe", shop = "ToolShed" },
			{ uid = "keep", itemId = "InsulatedCoat", shop = "ToolShed" },
			{ itemId = "FeatherfallCloak", shop = 5 },
			"junk",
			{ uid = "", itemId = "SkyShard" },
		}
		for i = 1, 60 do
			table.insert(boxes, { uid = "extra-" .. i, itemId = "Lantern", shop = "ToolShed" })
		end
		data.storage = boxes
		Schema.Migrate(data)
		t.eq(#data.storage, Schema.StorageCap)
		t.eq(data.storage[1].uid, "keep")
		t.eq(data.storage[1].itemId, "Lantern")
		local seen = {}
		for _, box in ipairs(data.storage) do
			t.eq(type(box.uid), "string")
			t.ok(#box.uid > 0, "server uid")
			t.ok(not seen[box.uid], "uids are unique")
			seen[box.uid] = true
			t.ok(box.uid ~= "axe-1", "not an axe uid")
			t.ok(box.uid ~= "cabin", "a box whose uid matches a placed item is dropped")
		end
		local rustbucket, cabin, steel = false, false, false
		for _, box in ipairs(data.storage) do
			if box.itemId == "Rustbucket" then
				rustbucket = true
				t.eq(box.uid, "box-truck")
			elseif box.itemId == "Cabin" then
				cabin = true
				t.eq(box.uid, "cabin-box")
			elseif box.itemId == "SteelAxe" then
				steel = true
				t.eq(box.uid, "axe-box")
			end
		end
		t.ok(rustbucket, "a Rustbucket box survives while that truck is owned")
		t.ok(cabin, "a Cabin box survives while a Cabin is placed")
		t.ok(steel, "a box whose itemId is an axe catalog id survives")
		-- The duplicate "keep" was given its own uid; the cloak with a bad shop was kept.
		local cloak = false
		for _, box in ipairs(data.storage) do
			if box.itemId == "FeatherfallCloak" then
				cloak = true
				t.eq(box.shop, "")
			end
			if box.itemId == "InsulatedCoat" then
				t.ok(box.uid ~= "keep")
			end
		end
		t.ok(cloak, "a bad shop string becomes empty, the box stays")
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		t.eq(data.storage, before.storage)
	end)

	t.test("schema 0 stays 0 through Migrate so the v2 migration still runs", function()
		local Schema, data = fresh()
		data.schema = 0
		Schema.Migrate(data)
		t.eq(data.schema, 0)
		Schema.MigrateV2(data, 20)
		t.eq(data.schema, 5)
	end)

	t.test("foundations fields add at most 2 KB to a maxed save", function()
		local Schema, data = fresh()
		local placed = {}
		for i = 1, 400 do
			placed[i] = { uid = "piece-" .. i, blueprintId = "Floor", x = i, z = 1, rot = i % 4 }
		end
		data.plot.placed = placed
		-- Park the big plot in the slot first, so the measurement below is
		-- only the foundations fields being filled back in.
		Schema.Migrate(data)
		stripFoundations(data)
		data.schema = 4
		local function isArray(value)
			local n = 0
			for key in pairs(value) do
				if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
					return false
				end
				n += 1
			end
			return n == #value
		end
		local function encode(value)
			local kind = type(value)
			if kind == "string" then
				return '"' .. string.gsub(string.gsub(value, "\\", "\\\\"), '"', '\\"') .. '"'
			elseif kind == "number" then
				if value ~= value or value == math.huge or value == -math.huge then
					return "null"
				end
				if value == math.floor(value) and math.abs(value) < 1e15 then
					return string.format("%d", value)
				end
				return tostring(value)
			elseif kind == "boolean" then
				return if value then "true" else "false"
			elseif kind ~= "table" then
				return "null"
			elseif isArray(value) then
				local parts = {}
				for _, item in ipairs(value) do
					table.insert(parts, encode(item))
				end
				return "[" .. table.concat(parts, ",") .. "]"
			end
			local keys = {}
			for key in pairs(value) do
				table.insert(keys, key)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			local parts = {}
			for _, key in ipairs(keys) do
				table.insert(parts, encode(tostring(key)) .. ":" .. encode(value[key]))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		local before = #encode(data)
		Schema.Migrate(data)
		local growth = #encode(data) - before
		t.ok(growth <= 2048, "grew " .. tostring(growth) .. " bytes")
		t.eq(#data.plot.placed, 400, "the old plot is still there")
		t.eq(data.schema, 5)
	end)

	t.test("T6: migration mints one box per owned truck (the Rustbucket too), once, on every slot", function()
		local Schema, data = fresh()
		data.plot.claimed = true
		data.ownedTrucks = { "Pickup", "Rustbucket", "Flatbed" }
		data.axes = { { uid = "axe-1", id = "RustyAxe" } }
		data.slots = {
			{ ownedTrucks = { "LoggingRig" }, fresh = false, storage = {} },
			{ ownedTrucks = { "ScoutATV" }, fresh = false },
			{ ownedTrucks = { "Rustbucket" }, fresh = false },
		}
		data.activeSlot = 1
		Schema.Migrate(data)
		local function dealership(record)
			local ids = {}
			for _, box in ipairs(record.storage or {}) do
				if box.shop == "Dealership" then
					table.insert(ids, box.itemId)
					t.ok(box.uid ~= "axe-1")
					t.eq(type(box.uid), "string")
				end
			end
			table.sort(ids)
			return ids
		end
		t.eq(dealership(data), { "Flatbed", "Pickup", "Rustbucket" })
		t.eq(data.trucksBoxed, true)
		t.eq(dealership(data.slots[1]), { "Flatbed", "Pickup", "Rustbucket" })
		t.eq(
			data.slots[1].storage[1].uid,
			data.storage[1].uid,
			"the active slot is the live snapshot, not a second mint"
		)
		t.eq(dealership(data.slots[2]), { "ScoutATV" })
		t.eq(dealership(data.slots[3]), { "Rustbucket" })
		t.eq(data.slots[2].trucksBoxed, true)
		t.eq(data.slots[3].trucksBoxed, true)
		local function rust(record)
			for _, box in ipairs(record.storage or {}) do
				if box.itemId == "Rustbucket" and box.shop == "Dealership" and box.uid ~= "kept-rust" then
					return true
				end
			end
			return false
		end
		t.eq(rust(data), true, "the Rustbucket is boxed like every other truck")
		t.eq(rust(data.slots[3]), true)
		local seen = {}
		for _, box in ipairs(data.slots[2].storage) do
			t.ok(not seen[box.uid])
			seen[box.uid] = true
		end
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		t.eq(data.storage, before.storage)
		t.eq(data.slots[2].storage, before.slots[2].storage)
		t.eq(data.slots[3].storage, before.slots[3].storage)
		t.eq(data.ownedTrucks, { "Pickup", "Rustbucket", "Flatbed" })
	end)

	t.test("an old save that owns a Rustbucket with no box and no pad gets a box, once", function()
		local Schema, data = fresh()
		-- Boxed before the Rustbucket was a boxed truck: trucksBoxed is already true.
		data.plot.claimed = true
		data.ownedTrucks = { "Rustbucket", "Pickup" }
		data.equippedTruck = "Rustbucket"
		data.trucksBoxed = true
		data.rustbucketBoxed = false
		data.storage = { { uid = "pickup-box", itemId = "Pickup", shop = "Dealership" } }
		data.plot.pads = {}
		Schema.Migrate(data)
		local rustboxes = 0
		for _, box in ipairs(data.storage) do
			if box.itemId == "Rustbucket" and box.shop == "Dealership" then
				rustboxes += 1
				t.eq(type(box.uid), "string")
				t.ok(box.uid ~= "pickup-box")
			end
		end
		t.eq(rustboxes, 1, "one Rustbucket box minted")
		t.eq(#data.storage, 2, "the existing box is untouched")
		t.eq(data.storage[1].uid, "pickup-box")
		t.eq(data.rustbucketBoxed, true)
		t.eq(data.ownedTrucks, { "Rustbucket", "Pickup" }, "nothing owned is removed")
		-- Idempotent, even when the player then opens (spends) the box.
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		sameClock(before, data)
		t.eq(data, before)
		data.storage = { data.storage[1] }
		data.plot.pads = { { uid = "p1", id = "Rustbucket", kind = "Truck", x = 0, z = 0, rot = 0, presses = 0 } }
		Schema.Migrate(data)
		t.eq(#data.storage, 1, "a Rustbucket with a pad is not boxed again")
	end)

	t.test("a Rustbucket that already has a pad or a box is not boxed again", function()
		local Schema, data = fresh()
		data.plot.claimed = true
		data.ownedTrucks = { "Rustbucket" }
		data.trucksBoxed = true
		data.plot.pads = { { uid = "p1", id = "Rustbucket", kind = "Truck", x = 0, z = 0, rot = 0, presses = 0 } }
		Schema.Migrate(data)
		t.eq(#data.storage, 0)
		t.eq(data.rustbucketBoxed, true)
		local Schema2, other = fresh()
		other.ownedTrucks = { "Rustbucket" }
		other.trucksBoxed = true
		other.storage = { { uid = "have", itemId = "Rustbucket", shop = "Dealership" } }
		Schema2.Migrate(other)
		t.eq(#other.storage, 1)
		t.eq(other.storage[1].uid, "have")
	end)

	t.test("a Rustbucket box waits for storage room and never trims storage", function()
		local Schema, data = fresh()
		data.ownedTrucks = { "Rustbucket" }
		data.trucksBoxed = true
		data.storage = {}
		for i = 1, Schema.StorageCap do
			table.insert(data.storage, { uid = "keep-" .. i, itemId = "SteelAxe", shop = "ToolShed" })
		end
		Schema.Migrate(data)
		t.eq(#data.storage, Schema.StorageCap)
		t.eq(data.rustbucketBoxed, false, "still owed")
		table.remove(data.storage)
		Schema.MintTruckBoxes(data)
		t.eq(#data.storage, Schema.StorageCap)
		t.eq(data.storage[Schema.StorageCap].itemId, "Rustbucket")
		t.eq(data.rustbucketBoxed, true)
	end)

	t.test("a full storage is not trimmed to mint a truck box", function()
		local Schema, data = fresh()
		data.ownedTrucks = { "Flatbed" }
		data.trucksBoxed = false
		data.storage = {}
		local kept = {}
		for i = 1, Schema.StorageCap do
			local box = { uid = "keep-" .. i, itemId = "SteelAxe", shop = "ToolShed" }
			table.insert(data.storage, box)
			table.insert(kept, box.uid)
		end
		Schema.Migrate(data)
		t.eq(#data.storage, Schema.StorageCap)
		for i, uid in ipairs(kept) do
			t.eq(data.storage[i].uid, uid)
			t.eq(data.storage[i].itemId, "SteelAxe")
		end
		t.eq(data.trucksBoxed, false)
		t.eq(table.find(data.ownedTrucks, "Flatbed") ~= nil, true)
		table.remove(data.storage, 1)
		Schema.Migrate(data)
		local flatbeds = 0
		for _, box in ipairs(data.storage) do
			if box.itemId == "Flatbed" and box.shop == "Dealership" then
				flatbeds += 1
			end
		end
		t.eq(flatbeds, 1)
		t.eq(#data.storage, Schema.StorageCap)
		t.eq(data.trucksBoxed, true)
	end)

	t.test("retrying a mint, including beside a load, adds one box", function()
		local Schema, data = fresh()
		data.ownedTrucks = { "Flatbed" }
		data.trucksBoxed = false
		data.storage = {}
		for i = 1, Schema.StorageCap - 1 do
			table.insert(data.storage, { uid = "keep-" .. i, itemId = "SteelAxe", shop = "ToolShed" })
		end
		Schema.MintTruckBoxes(data)
		Schema.MintTruckBoxes(data)
		local function flatbeds(record)
			local n = 0
			for _, box in ipairs(record.storage) do
				if box.itemId == "Flatbed" and box.shop == "Dealership" then
					n += 1
				end
			end
			return n
		end
		t.eq(flatbeds(data), 1)
		t.eq(data.trucksBoxed, true)
		local function openSlot()
			local _, record = fresh()
			record.ownedTrucks = { "Flatbed" }
			record.trucksBoxed = false
			record.storage = {}
			for i = 1, Schema.StorageCap - 1 do
				table.insert(record.storage, { uid = "race-" .. i, itemId = "SteelAxe", shop = "ToolShed" })
			end
			return record
		end
		-- Retry and a join (Migrate) on the same record. Either order, and
		-- both together, leave one box: the mint holds the record until the
		-- insert is visible to takenIds and WaitingTrucks.
		local retryFirst = openSlot()
		Schema.MintTruckBoxes(retryFirst)
		Schema.Migrate(retryFirst)
		t.eq(flatbeds(retryFirst), 1)
		local loadFirst = openSlot()
		Schema.Migrate(loadFirst)
		Schema.MintTruckBoxes(loadFirst)
		t.eq(flatbeds(loadFirst), 1)
	end)

	t.test("T7: ownedTrucks stays catalog ids and truckPaint is unchanged", function()
		local fs = require("@lune/fs")
		local Schema, data = fresh()
		data.plot.claimed = true
		data.ownedTrucks = { "Pickup", "Rustbucket" }
		data.truckPaint = { Pickup = "#2F6DB5" }
		local paint = t.loader():shared("Util").deepCopy(data.truckPaint)
		Schema.Migrate(data)
		t.eq(data.ownedTrucks, { "Pickup", "Rustbucket" })
		t.eq(type(data.ownedTrucks[1]), "string")
		t.eq(data.truckPaint, paint)
		local src = fs.readFile("src/ServerScriptService/ProfileSchema.luau")
		t.ok(string.find(src, "data.truckPaint = PaintShop.Sanitize(data.truckPaint)", 1, true) ~= nil)
		t.eq(data.plot.pads, nil, "pads are not created for an empty plot")
	end)

	t.test("hammer build: a new save starts with the starter plans, no carried plans, and a hammer", function()
		local Schema, data = fresh()
		local Book = t.loader():shared("BlueprintBook")
		t.eq(Schema.Template.blueprintBook, Book.Starter())
		t.eq(Schema.Template.blueprintItems, {})
		t.eq(Schema.Template.hammer, true)
		Schema.Migrate(data)
		t.eq(data.blueprintBook, Book.Starter())
		t.eq(data.hammer, true)
	end)

	t.test("hammer build: an old save keeps everything it unlocked or paid for, and gets the hammer", function()
		local Schema, data = fresh()
		local Book = t.loader():shared("BlueprintBook")
		-- A save from before the book: no such fields at all.
		data.blueprintBook = nil
		data.blueprintItems = nil
		data.hammer = nil
		data.furnitureBlueprints = { Shed = true, Table = true }
		data.sawmillStock = { "ChopSaw" }
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "m", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0 },
			{ uid = "c", blueprintId = "Chair", x = 10, z = 0, rot = 0 },
		}
		Schema.Migrate(data)
		for _, id in ipairs({ "Shed", "Table", "SawmillRickety", "Chair", "ChopSaw" }) do
			t.ok(Book.Has(data.blueprintBook, id), id)
		end
		t.ok(Book.Has(data.blueprintBook, "Wall"), "the starter plans too")
		t.ok(not Book.Has(data.blueprintBook, "Mailbox"), "an unlock never bought stays unbought")
		t.eq(data.furnitureBlueprints, { Shed = true, Table = true }, "the legacy set is left for a rollback")
		t.eq(data.hammer, true)
		t.eq(data.blueprintItems, {})
	end)

	t.test("hammer build: migrating the book again changes nothing, and every slot gets one", function()
		local Schema, data = fresh()
		data.furnitureBlueprints = { Shed = true }
		Schema.Migrate(data)
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.Migrate(data)
		sameClock(before, data)
		t.eq(data, before)
		t.eq(type(data.slots), "table")
		for _, slot in ipairs(data.slots) do
			t.eq(type(slot.blueprintBook), "table")
			t.eq(slot.hammer, true)
		end
	end)

	t.test("hammer build: junk in the book fields is cleaned and a false hammer is set right", function()
		local Schema, data = fresh()
		data.blueprintBook = { "Wall", "Nope", 5, "Wall" }
		data.blueprintItems = { { uid = "a", id = "Shed" }, { uid = "a", id = "Shed" }, { uid = "b", id = "Nope" }, 3 }
		data.hammer = false
		Schema.Migrate(data)
		t.eq(data.blueprintBook[1], "Wall")
		for _, id in ipairs(data.blueprintBook) do
			t.eq(type(id), "string")
			t.ok(t.loader():shared("PlotData").Blueprint(id) ~= nil, id)
		end
		t.eq(data.blueprintItems, { { uid = "a", id = "Shed" } })
		t.eq(data.hammer, true)
	end)

	t.test("hammer build: the book and carried plans are per slot, not account-wide", function()
		local Schema, data = fresh()
		Schema.Migrate(data)
		data.blueprintItems = { { uid = "keep", id = "Shed" } }
		local Slots = t.loader():shared("SaveSlotLogic")
		t.eq(Slots.IsAccountKey("blueprintItems"), false)
		t.eq(Slots.IsAccountKey("blueprintBook"), false)
	end)
end
