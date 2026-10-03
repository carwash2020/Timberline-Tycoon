--!nocheck
-- The save template and migrating older saves.
return function(t)
	local function fresh()
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		return Schema, Util.deepCopy(Schema.Template)
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
		t.eq(data.plot, { claimed = false, tier = 1, placed = {} })
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
		t.eq(data.schema, 2)
	end)

	t.test("MigrateV2 converts the forge's lumenwood logs to u³, capped at the recipe, and keeps forgeLogs", function()
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

	t.test("MigrateV2 restarts tutorial progress only on steps whose unit changed", function()
		local TutorialData = t.loader():shared("TutorialData")
		for index, step in ipairs(TutorialData.Steps) do
			local Schema, data = v1Save()
			data.tutorialStep = index
			data.tutorialProgress = 2
			Schema.MigrateV2(data, 20)
			local keeps = step.id == "fell" or step.id == "plant" or step.id == "steel"
			t.eq(data.tutorialProgress, if keeps then 2 else 0, step.id)
			t.eq(data.tutorialStep, index, "the step itself is kept")
		end
	end)

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
		t.eq(mid.tutorialStep, 5)
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

	t.test("MigrateV2 keeps axes, trucks, gear, heartseeds, the compendium and Robux fields", function()
		local Schema, data = v1Save()
		data.axes = { { uid = "a", id = "SteelAxe" }, { uid = "b", id = "CobaltAxe" } }
		data.bestAxeTier = 4
		data.ownedTrucks = { "Rustbucket", "Flatbed" }
		data.gear = { "Lantern" }
		data.heartseeds = { oak = 2 }
		data.compendium = { oak = true, birch = true }
		data.doubleWoodUntil = 123
		data.instantDeliveries = 2
		local before = t.loader():shared("Util").deepCopy(data)
		Schema.MigrateV2(data, 20)
		for _, key in ipairs({
			"axes",
			"bestAxeTier",
			"ownedTrucks",
			"gear",
			"heartseeds",
			"compendium",
			"doubleWoodUntil",
			"instantDeliveries",
			"plot",
			"forest",
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
		t.eq(data.schema, 2)
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
		t.eq(data.schema, 2)
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
end
