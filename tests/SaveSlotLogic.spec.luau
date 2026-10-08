--!nocheck
-- Save slots: migration into slot 1, load, reset, and the anti-dupe rule
-- (wood is committed before the swap, cash does not copy, Robux stays).
return function(t)
	local SaveSlotLogic = t.shared("SaveSlotLogic")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function guidFactory()
		local n = 0
		return function()
			n += 1
			return "id-" .. n
		end
	end

	local function fresh()
		local data = Util.deepCopy(Schema.Template)
		Schema.Migrate(data)
		return data
	end

	local function worldFor(data)
		local ground = {}
		local calls = {}
		return {
			ground = ground,
			calls = calls,
			hooks = {
				commit = function(profile)
					table.insert(calls, "commit")
					-- The leave path: wood in the world is written onto the
					-- live slot (bed pieces and ground pieces, LuxCut tag
					-- and all), then removed from the world.
					local riding, lying = {}, {}
					for _, log in ipairs(ground) do
						if log.where == "ground" then
							table.insert(lying, log)
						else
							table.insert(riding, log)
						end
					end
					table.clear(ground)
					profile.truckLoad = riding
					profile.groundLoad = lying
				end,
				setCash = function(amount)
					table.insert(calls, "cash")
					data.cash = amount
				end,
				rebuild = function()
					table.insert(calls, "rebuild")
				end,
			},
		}
	end

	t.test("an old single save becomes slot 1 and keeps its cash, axe and plot", function()
		local data = Util.deepCopy(Schema.Template)
		data.slots = nil
		data.activeSlot = nil
		data.cash = 4321
		data.axes = { { uid = "axe-1", id = "SteelAxe" } }
		data.bestAxeTier = 2
		data.equippedAxe = "axe-1"
		data.plot =
			{ claimed = true, tier = 2, placed = { { uid = "cabin", blueprintId = "Cabin", x = 4, z = 4, rot = 0 } } }
		data.truckLoad = { { w = "oak" } }
		data.purchaseIds = { "receipt-9" }
		data.doubleWoodUntil = 5000
		data.instantDeliveries = 2
		data.pendingCash = 80
		Schema.Migrate(data)
		t.eq(data.cash, 4321)
		t.eq(data.activeSlot, 1)
		t.eq(#data.slots, 3)
		t.eq(data.slots[1].cash, 4321)
		t.eq(data.slots[1].axes[1].id, "SteelAxe")
		t.eq(data.slots[1].plot.claimed, true)
		t.eq(data.slots[1].plot.placed[1].uid, "cabin")
		t.eq(data.slots[1].truckLoad[1].w, "oak")
		t.eq(data.slots[1].fresh, false)
		t.eq(data.slots[2].fresh, true)
		t.eq(data.slots[2].cash, 0)
		t.eq(data.slots[3].fresh, true)
		-- Robux never moved into a slot snapshot as the thing a load copies
		-- over the account. The account fields are still the originals.
		t.eq(data.purchaseIds[1], "receipt-9")
		t.eq(data.doubleWoodUntil, 5000)
		t.eq(data.instantDeliveries, 2)
		t.eq(data.pendingCash, 80)
		t.eq(data.slots[1].purchaseIds, nil)
		t.eq(data.slots[1].doubleWoodUntil, nil)
		t.eq(data.slots[1].instantDeliveries, nil)
		t.eq(data.slots[1].pendingCash, nil)
	end)

	t.test("migrating twice does not wipe a parked slot", function()
		local data = fresh()
		data.cash = 100
		data.slots[1] = SaveSlotLogic.Blank(Schema.Template, guidFactory(), 0)
		data.slots[1].fresh = false
		data.slots[1].cash = 100
		data.slots[2].cash = 777
		data.slots[2].fresh = false
		data.slots[2].axes = { { uid = "kept", id = "SteelAxe" } }
		Schema.Migrate(data)
		t.eq(data.slots[2].cash, 777)
		t.eq(data.slots[2].axes[1].id, "SteelAxe")
	end)

	t.test("loading a slot commits wood first, and does not copy cash or receipts", function()
		local data = fresh()
		data.cash = 900
		data.purchaseIds = { "receipt-1" }
		data.doubleWoodUntil = 80
		data.instantDeliveries = 3
		data.pendingCash = 40
		data.accountAxes = { "LuxAxe" }
		data.axes = { { uid = "lux", id = "LuxAxe" }, { uid = "rusty", id = "RustyAxe" } }
		data.slots[1] = nil
		Schema.Migrate(data)
		local world = worldFor(data)
		table.insert(world.ground, { w = "pine", v = 12 })
		local ok, why = SaveSlotLogic.Perform(data, "load", 2, 1_000, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, true, why)
		t.eq(world.calls[1], "commit")
		t.eq(#world.ground, 0, "the log left the world")
		t.eq(data.slots[1].truckLoad[1].w, "pine", "the log is only in the slot you left")
		t.eq(#data.truckLoad, 0, "the new slot did not receive it")
		t.eq(data.cash, 0)
		t.eq(data.slots[1].cash, 900)
		t.eq(data.activeSlot, 2)
		t.eq(data.purchaseIds[1], "receipt-1")
		t.eq(data.doubleWoodUntil, 80)
		t.eq(data.instantDeliveries, 3)
		t.eq(data.pendingCash, 40)
		t.eq(data.slots[2].purchaseIds, nil)
		local ids = {}
		for _, item in ipairs(data.axes) do
			ids[item.id] = true
		end
		t.eq(ids.LuxAxe, true, "the Lux Axe came with the account")
		-- Back to slot 1: the pine and the $900 return, and are not also in slot 2.
		local again = SaveSlotLogic.Perform(
			data,
			"load",
			1,
			1_000 + SaveSlotLogic.Cooldown,
			Schema.Template,
			guidFactory(),
			world.hooks
		)
		t.eq(again, true)
		t.eq(data.cash, 900)
		t.eq(data.truckLoad[1].w, "pine")
		t.eq(data.slots[2].cash, 0)
		t.ok(data.slots[2].truckLoad == nil or #data.slots[2].truckLoad == 0)
	end)

	t.test("a second load inside the cooldown does nothing, so it cannot dupe", function()
		local data = fresh()
		data.cash = 50
		Schema.Migrate(data)
		local world = worldFor(data)
		table.insert(world.ground, { w = "oak" })
		t.eq(SaveSlotLogic.Perform(data, "load", 2, 10, Schema.Template, guidFactory(), world.hooks), true)
		table.insert(world.ground, { w = "oak" }) -- a bug that left a copy in the world
		local ok, why = SaveSlotLogic.Perform(data, "load", 1, 10 + 5, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, false)
		t.ok(string.find(why, "seconds", 1, true) ~= nil, why)
		t.eq(#world.calls, 3, "commit, cash, rebuild — and then nothing")
		t.eq(#world.ground, 1, "the leftover log was not committed into a second slot")
		t.eq(data.activeSlot, 2)
		t.eq(data.cash, 0)
	end)

	t.test("reset wipes the slot's cash and wood, keeps Robux, and needs the cooldown", function()
		local data = fresh()
		data.cash = 2500
		data.purchaseIds = { "receipt-2" }
		data.doubleWoodUntil = 99
		data.instantDeliveries = 1
		data.pendingCash = 15
		data.axes = { { uid = "lux", id = "LuxAxe" } }
		data.accountAxes = { "LuxAxe" }
		data.plot =
			{ claimed = true, tier = 3, placed = { { uid = "mill", blueprintId = "Sawmill", x = 0, z = 0, rot = 0 } } }
		Schema.Migrate(data)
		local world = worldFor(data)
		table.insert(world.ground, { w = "maple" })
		local ok = SaveSlotLogic.Perform(data, "reset", 0, 50, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, true)
		t.eq(#world.ground, 0)
		t.eq(data.cash, 0)
		t.eq(#data.truckLoad, 0)
		t.eq(data.plot.claimed, false)
		t.eq(#data.plot.placed, 0)
		t.eq(data.slots[1].cash, 0)
		t.eq(data.slots[1].truckLoad == nil or #data.slots[1].truckLoad == 0, true)
		t.eq(data.purchaseIds[1], "receipt-2")
		t.eq(data.doubleWoodUntil, 99)
		t.eq(data.instantDeliveries, 1)
		t.eq(data.pendingCash, 15)
		local kept = false
		for _, item in ipairs(data.axes) do
			if item.id == "LuxAxe" then
				kept = true
			end
		end
		t.eq(kept, true)
		local blocked = SaveSlotLogic.Perform(data, "reset", 0, 50 + 1, Schema.Template, guidFactory(), world.hooks)
		t.eq(blocked, false)
	end)

	t.test("Robux passes, settings and the Lux Axe stay on the account across a load and a redo", function()
		local data = fresh()
		data.cash = 400
		data.passes = { DoubleCash = true, LuxAxe = true }
		data.settings = {
			music = false,
			sfx = true,
			musicVolume = 0.25,
			sfxVolume = 0.5,
			graphics = "low",
			cameraShake = false,
			uiScale = "small",
			showTips = false,
		}
		data.purchaseIds = { "receipt-lux" }
		data.doubleWoodUntil = 9_000
		data.instantDeliveries = 4
		data.pendingCash = 25
		data.axes = { { uid = "lux", id = "LuxAxe" } }
		data.accountAxes = { "LuxAxe" }
		data.slots[1] = nil
		Schema.Migrate(data)
		t.eq(data.slots[1].passes, nil)
		t.eq(data.slots[1].settings, nil)
		t.eq(data.slots[1].purchaseIds, nil)
		local world = worldFor(data)
		t.eq(SaveSlotLogic.Perform(data, "load", 2, 2_000, Schema.Template, guidFactory(), world.hooks), true)
		t.eq(data.passes.DoubleCash, true)
		t.eq(data.passes.LuxAxe, true)
		t.eq(data.settings.music, false)
		t.eq(data.settings.graphics, "low")
		t.eq(data.settings.uiScale, "small")
		t.eq(data.purchaseIds[1], "receipt-lux")
		t.eq(data.doubleWoodUntil, 9_000)
		t.eq(data.instantDeliveries, 4)
		t.eq(data.pendingCash, 25)
		t.eq(data.slots[2].passes, nil)
		t.eq(data.slots[2].settings, nil)
		local onFresh = false
		for _, item in ipairs(data.axes) do
			if item.id == "LuxAxe" then
				onFresh = true
			end
		end
		t.eq(onFresh, true, "the Lux Axe is on the fresh slot too")
		-- A parked slot that somehow carried its own settings and passes
		-- must not overwrite the account when it is loaded.
		data.slots[1].settings = { music = true, graphics = "high" }
		data.slots[1].passes = { DoubleCash = false }
		local back = SaveSlotLogic.Perform(
			data,
			"load",
			1,
			2_000 + SaveSlotLogic.Cooldown,
			Schema.Template,
			guidFactory(),
			world.hooks
		)
		t.eq(back, true)
		t.eq(data.settings.music, false)
		t.eq(data.settings.graphics, "low")
		t.eq(data.passes.DoubleCash, true)
		t.eq(
			SaveSlotLogic.Perform(
				data,
				"reset",
				0,
				2_000 + SaveSlotLogic.Cooldown * 2,
				Schema.Template,
				guidFactory(),
				world.hooks
			),
			true
		)
		t.eq(data.passes.LuxAxe, true)
		t.eq(data.passes.DoubleCash, true)
		t.eq(data.settings.music, false)
		t.eq(data.purchaseIds[1], "receipt-lux")
		t.eq(data.doubleWoodUntil, 9_000)
		t.eq(data.instantDeliveries, 4)
		local afterRedo = false
		for _, item in ipairs(data.axes) do
			if item.id == "LuxAxe" then
				afterRedo = true
			end
		end
		t.eq(afterRedo, true, "a redo does not take the Lux Axe")
		local summary = SaveSlotLogic.Summary(data)
		t.eq(summary[1].axeName, "Lux Axe")
	end)

	t.test("a LuxCut tag stays on the wood when a slot is stashed and loaded back", function()
		local data = fresh()
		data.skyWood = { { w = "birch", v = 4, l = true } }
		Schema.Migrate(data)
		local world = worldFor(data)
		table.insert(world.ground, { w = "pine", v = 8, l = true })
		table.insert(world.ground, { w = "oak", v = 3, l = true, where = "ground", g = { 12, 1, -4 } })
		t.eq(SaveSlotLogic.Perform(data, "load", 2, 3_000, Schema.Template, guidFactory(), world.hooks), true)
		t.eq(data.slots[1].truckLoad[1].l, true, "the bed piece keeps LuxCut in the slot you left")
		t.eq(data.slots[1].groundLoad[1].l, true, "the ground piece keeps LuxCut too")
		t.eq(data.slots[1].skyWood[1].l, true)
		t.eq(data.truckLoad == nil or #data.truckLoad == 0, true)
		t.eq(data.skyWood == nil or #data.skyWood == 0, true, "the fresh slot did not inherit the cut")
		local back = SaveSlotLogic.Perform(
			data,
			"load",
			1,
			3_000 + SaveSlotLogic.Cooldown,
			Schema.Template,
			guidFactory(),
			world.hooks
		)
		t.eq(back, true)
		t.eq(data.truckLoad[1].w, "pine")
		t.eq(data.truckLoad[1].l, true, "loading the slot restores the LuxCut tag")
		t.eq(data.groundLoad[1].l, true)
		t.eq(data.groundLoad[1].g[1], 12)
		t.eq(data.skyWood[1].l, true)
		t.eq(data.slots[2].truckLoad == nil or #data.slots[2].truckLoad == 0, true)
	end)

	t.test("starter grant: three played slots get one truck, and a second load adds none", function()
		local data = Util.deepCopy(Schema.Template)
		data.ownedTrucks = {}
		data.equippedTruck = ""
		data.starterTruckGranted = false
		data.totalEarned = 40
		data.truckLoad = { { w = "oak", value = 12 } }
		data.truckAt = { x = 4, y = 1, z = 8 }
		data.slots = {}
		data.activeSlot = 1
		for i = 1, 3 do
			local slot = Util.deepCopy(Schema.Template)
			slot.fresh = false
			slot.ownedTrucks = {}
			slot.equippedTruck = ""
			slot.starterTruckGranted = false
			slot.totalEarned = 40
			slot.truckBed = { { woodId = "oak", value = 5 } }
			slot.truckLoad = { { w = "birch" } }
			slot.truckAt = { x = i, y = 2, z = 3 }
			data.slots[i] = slot
		end
		Schema.Migrate(data)
		Schema.Migrate(data)
		t.eq(data.ownedTrucks, { "Rustbucket" })
		t.eq(data.equippedTruck, "Rustbucket")
		t.eq(data.truckLoad, { { w = "oak", value = 12 } })
		t.eq(data.truckAt.x, 4)
		for i = 2, 3 do
			t.eq(data.slots[i].ownedTrucks, { "Rustbucket" }, "slot " .. i)
			t.eq(data.slots[i].equippedTruck, "Rustbucket")
			t.eq(#data.slots[i].truckBed, 1)
			t.eq(data.slots[i].truckLoad[1].w, "birch")
			t.eq(data.slots[i].truckAt.x, i)
		end
		t.eq(data.slots[1].ownedTrucks, { "Rustbucket" })
		t.eq(#data.slots[1].ownedTrucks, 1)
	end)

	t.test("a fresh slot is not given a truck", function()
		local data = fresh()
		t.eq(data.ownedTrucks, {})
		t.eq(data.equippedTruck, "")
		t.eq(data.starterTruckGranted, true)
		t.eq(data.slots[2].fresh, true)
		t.eq(data.slots[2].ownedTrucks, {})
		t.eq(data.slots[3].ownedTrucks, {})
	end)

	t.test("cargo with no truck is kept and the slot gets exactly one starter", function()
		local data = Util.deepCopy(Schema.Template)
		data.slots = nil
		data.ownedTrucks = {}
		data.equippedTruck = ""
		data.starterTruckGranted = false
		data.totalEarned = 15
		data.truckBed = { { woodId = "oak", value = 9 } }
		data.truckLoad = { { w = "oak" } }
		data.truckAt = { x = 2, y = 0, z = 5 }
		Schema.Migrate(data)
		t.eq(data.ownedTrucks, { "Rustbucket" })
		t.eq(data.truckBed[1].value, 9)
		t.eq(data.truckLoad[1].w, "oak")
		t.eq(data.truckAt.z, 5)
		Schema.Migrate(data)
		t.eq(data.ownedTrucks, { "Rustbucket" })
		t.eq(#data.truckBed, 1)
	end)

	t.test("a bad slot index is refused before anything is committed", function()
		local data = fresh()
		Schema.Migrate(data)
		local world = worldFor(data)
		local ok = SaveSlotLogic.Perform(data, "load", 9, 1, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, false)
		t.eq(#world.calls, 0)
		t.eq(
			SaveSlotLogic.Perform(data, "load", data.activeSlot, 1, Schema.Template, guidFactory(), world.hooks),
			false
		)
	end)

	t.test("load, reset, and swap keep badges, secrets, and areas, and swap the slot fields", function()
		t.eq(SaveSlotLogic.IsAccountKey("badgesAwarded"), true)
		t.eq(SaveSlotLogic.IsAccountKey("badgesSent"), true)
		t.eq(SaveSlotLogic.IsAccountKey("secretsFound"), true)
		t.eq(SaveSlotLogic.IsAccountKey("areasVisited"), true)
		t.eq(SaveSlotLogic.IsAccountKey("cosmetics"), true, "event cosmetics follow the account")
		t.eq(SaveSlotLogic.IsAccountKey("event"), false, "event progress is per slot")
		t.eq(SaveSlotLogic.IsAccountKey("storage"), false)
		t.eq(SaveSlotLogic.IsAccountKey("permissions"), false)
		t.eq(SaveSlotLogic.IsAccountKey("questAxe"), false)

		local data = fresh()
		data.badgesAwarded = { FirstTree = true }
		data.badgesSent = { FirstTree = true }
		data.secretsFound = { LanternShrine = true }
		data.areasVisited = { Snow = true }
		data.storage = { { uid = "box-a", itemId = "Lantern", shop = "ToolShed" } }
		data.plot.squares = { "0,0" }
		data.permissions = { visit = true }
		data.questAxe = { step = 2 }
		data.slots[2].fresh = false
		data.slots[2].storage = { { uid = "box-b", itemId = "HeatBoots", shop = "ToolShed" } }
		data.slots[2].plot = { claimed = true, tier = 1, placed = {}, squares = { "1,0" } }
		data.slots[2].permissions = { visit = false }
		data.slots[2].questAxe = { step = 4 }
		data.slots[2].badgesAwarded = { Stolen = true }
		data.slots[2].badgesSent = { Stolen = true }
		data.slots[2].secretsFound = { Stolen = true }
		data.slots[2].areasVisited = { Stolen = true }

		local world = worldFor(data)
		local guid = guidFactory()
		local ok, why = SaveSlotLogic.Perform(data, "load", 2, 1_000, Schema.Template, guid, world.hooks)
		t.eq(ok, true, why)
		t.eq(data.badgesAwarded, { FirstTree = true })
		t.eq(data.badgesSent, { FirstTree = true })
		t.eq(data.secretsFound, { LanternShrine = true })
		t.eq(data.areasVisited, { Snow = true })
		t.eq(data.storage, { { uid = "box-b", itemId = "HeatBoots", shop = "ToolShed" } })
		t.eq(data.plot.squares, { "1,0" })
		t.eq(data.permissions, { visit = false })
		t.eq(data.questAxe, { step = 4 })
		t.eq(data.slots[1].storage, { { uid = "box-a", itemId = "Lantern", shop = "ToolShed" } })
		t.eq(data.slots[1].plot.squares, { "0,0" })
		t.eq(data.slots[1].questAxe, { step = 2 })
		t.eq(data.slots[1].permissions, { visit = true })
		t.eq(data.slots[1].badgesAwarded, nil)
		t.eq(data.slots[1].badgesSent, nil)

		ok, why = SaveSlotLogic.Perform(data, "reset", 2, 1_000 + 120, Schema.Template, guid, world.hooks)
		t.eq(ok, true, why)
		t.eq(data.badgesAwarded, { FirstTree = true })
		t.eq(data.badgesSent, { FirstTree = true })
		t.eq(data.secretsFound, { LanternShrine = true })
		t.eq(data.areasVisited, { Snow = true })
		t.eq(data.storage, {})
		t.eq(data.plot.squares, {})
		t.eq(data.permissions, {})
		t.eq(data.questAxe, { step = 0 })

		ok, why = SaveSlotLogic.Perform(data, "load", 1, 1_000 + 240, Schema.Template, guid, world.hooks)
		t.eq(ok, true, why)
		t.eq(data.badgesAwarded, { FirstTree = true })
		t.eq(data.badgesSent, { FirstTree = true })
		t.eq(data.secretsFound, { LanternShrine = true })
		t.eq(data.areasVisited, { Snow = true })
		t.eq(data.storage, { { uid = "box-a", itemId = "Lantern", shop = "ToolShed" } })
		t.eq(data.plot.squares, { "0,0" })
		t.eq(data.permissions, { visit = true })
		t.eq(data.questAxe, { step = 2 })
	end)

	t.test("a slot name other players can see is the filtered one, or the default", function()
		local data = fresh()
		local name, why = SaveSlotLogic.VisibleName(1, "  North Yard ", "North Yard")
		t.eq(name, "North Yard", why)
		t.eq(SaveSlotLogic.SetName(data, 1, name), true)
		t.eq(SaveSlotLogic.Summary(data)[1].name, "North Yard")
		t.eq(data.slots[1].name, "North Yard")
		-- A filter failure does not keep the typed text.
		local fallback = SaveSlotLogic.VisibleName(2, "Secret Name", nil)
		t.eq(fallback, "Save 2")
		t.eq(SaveSlotLogic.SetName(data, 2, fallback), true)
		t.eq(data.slots[2].name, "Save 2")
		t.eq(SaveSlotLogic.Summary(data)[2].name, "Save 2")
		t.eq(SaveSlotLogic.VisibleName(1, "Hello", ""), "Save 1")
		t.eq(SaveSlotLogic.VisibleName(1, "Hello", "####"), "####")
		local bad, message = SaveSlotLogic.VisibleName(1, "this name is far too long", "fine")
		t.eq(bad, nil)
		t.ok(string.find(message, "letters", 1, true) ~= nil, message)
	end)

	t.test("a named slot says when it was saved, and loading it back restores the build", function()
		local data = fresh()
		data.cash = 400
		data.plot.placed = {
			{ uid = "cabin", blueprintId = "Cabin", x = 4, z = 8, rot = 1 },
		}
		data.slots[2].fresh = false
		data.slots[2].cash = 900
		data.slots[2].lastPlayed = 1000
		data.slots[2].plot = {
			claimed = true,
			tier = 1,
			placed = { { uid = "bench", blueprintId = "Bench", x = 2, z = 2, rot = 0 } },
			squares = {},
		}
		local named, nameWhy = SaveSlotLogic.SetName(data, 1, "  North Yard ")
		t.eq(named, true, nameWhy)
		t.eq(SaveSlotLogic.SetName(data, 2, "Mill"), true)
		t.eq(SaveSlotLogic.SetName(data, 1, "this name is far too long"), false)
		t.eq(data.slots[1].name, "North Yard")
		t.eq(SaveSlotLogic.Summary(data)[1].name, "North Yard")
		t.eq(SaveSlotLogic.Summary(data)[2].name, "Mill")
		t.eq(SaveSlotLogic.SavedText(1000, 1180), "Saved 3 min ago")
		t.eq(SaveSlotLogic.SavedText(0, 1180), "Not saved")
		t.eq(SaveSlotLogic.SavedText(1150, 1180), "Saved just now")

		local world = worldFor(data)
		local ok, why = SaveSlotLogic.Perform(data, "load", 2, 2000, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, true, why)
		t.eq(data.plot.placed[1].blueprintId, "Bench")
		t.eq(data.slots[1].name, "North Yard")
		t.eq(data.slots[1].plot.placed[1].uid, "cabin")
		t.eq(data.slots[1].plot.placed[1].x, 4)

		-- Inside the cooldown the leftover log is not written into a second slot.
		table.insert(world.ground, { w = "oak" })
		local again, message = SaveSlotLogic.Perform(data, "load", 1, 2010, Schema.Template, guidFactory(), world.hooks)
		t.eq(again, false)
		t.ok(string.find(message, "seconds", 1, true) ~= nil, message)
		t.eq(#world.ground, 1)
		t.eq(data.activeSlot, 2)
		t.eq(data.plot.placed[1].blueprintId, "Bench")

		data.slotCooldownUntil = 0
		ok, why = SaveSlotLogic.Perform(data, "load", 1, 4000, Schema.Template, guidFactory(), world.hooks)
		t.eq(ok, true, why)
		t.eq(data.plot.placed[1].blueprintId, "Cabin")
		t.eq(data.plot.placed[1].x, 4)
		t.eq(data.plot.placed[1].rot, 1)
		t.eq(data.slots[2].name, "Mill")
		t.eq(SaveSlotLogic.NameOf(data.slots[1], 1), "North Yard")
	end)

	t.test("owner grants stay on the account across a slot load, like passes", function()
		local data = fresh()
		data.ownerGrants = { LuxAxe = { at = 5, by = 7, byName = "Connor" } }
		data.ownerGrantLog =
			{ { at = 5, by = 7, byName = "Connor", action = "give", item = "pass_LuxAxe", name = "Lux Axe" } }
		data.slots[1] = nil
		Schema.Migrate(data)
		t.eq(data.slots[1].ownerGrants, nil, "not copied into a slot")
		t.eq(data.slots[1].ownerGrantLog, nil)
		local world = worldFor(data)
		t.eq(SaveSlotLogic.Perform(data, "load", 2, 2_000, Schema.Template, guidFactory(), world.hooks), true)
		t.eq(data.ownerGrants.LuxAxe.by, 7)
		t.eq(#data.ownerGrantLog, 1)
		t.eq(SaveSlotLogic.IsAccountKey("ownerGrants"), true)
		t.eq(SaveSlotLogic.IsAccountKey("ownerGrantLog"), true)
	end)

	t.test("forgetting a pass axe takes it off the live axes, the account list and every parked slot", function()
		local data = fresh()
		data.axes = { { uid = "r", id = "RustyAxe" }, { uid = "lux", id = "LuxAxe" } }
		data.accountAxes = { "LuxAxe" }
		data.slots[2].axes = { { uid = "lux2", id = "LuxAxe" }, { uid = "s", id = "SteelAxe" } }
		t.eq(SaveSlotLogic.ForgetAccountAxe(data, "LuxAxe"), 1)
		t.eq(#data.axes, 1)
		t.eq(data.axes[1].id, "RustyAxe")
		t.eq(data.accountAxes, {})
		t.eq(#data.slots[2].axes, 1)
		t.eq(data.slots[2].axes[1].id, "SteelAxe")
		-- The sync that brings account axes back finds none.
		SaveSlotLogic.SyncAccountAxes(data, guidFactory())
		for _, item in ipairs(data.axes) do
			t.ok(item.id ~= "LuxAxe", "it is not back")
		end
		t.eq(SaveSlotLogic.ForgetAccountAxe(data, "LuxAxe"), 0, "twice is the same")
	end)

	t.test("the join picker's rows say whether a save has a plot and how much is on it", function()
		local data = fresh()
		data.plot.claimed = true
		data.plot.placed = { { uid = "a" }, { uid = "b" } }
		data.plot.pads = { { uid = "p" } }
		data.plot.tier = 3
		data.cash = 777
		local row = SaveSlotLogic.Summary(data)[1]
		t.eq(row.hasPlot, true)
		t.eq(row.pieces, 3)
		t.eq(row.tier, 3)
		t.eq(row.cash, 777, "the playing save's cash is the live wallet, not an old snapshot")
		local other = SaveSlotLogic.Summary(data)[2]
		t.eq(other.hasPlot, false, "a never-played save has no plot")
		t.eq(other.pieces, 0)
	end)

	t.test("an unloaded base stays with its save through a swap; the unload cooldown is the account's", function()
		t.eq(SaveSlotLogic.IsAccountKey("baseCooldownUntil"), true)
		local data = fresh()
		data.plot.claimed = true
		data.plot.placed = { { uid = "x", blueprintId = "Bench", x = 0, z = 0, rot = 0 } }
		data.baseCooldownUntil = 4000
		local world = worldFor(data)
		t.eq(SaveSlotLogic.Perform(data, "load", 2, 3_000, Schema.Template, guidFactory(), world.hooks), true)
		t.eq(data.plot.claimed, false, "the other save has its own plot")
		t.eq(data.baseCooldownUntil, 4000, "the cooldown did not travel or reset")
		t.eq(SaveSlotLogic.Summary(data)[1].hasPlot, true, "the first save still shows its base")
		t.eq(SaveSlotLogic.Perform(data, "load", 1, 9_000, Schema.Template, guidFactory(), world.hooks), true)
		t.eq(data.plot.placed[1].uid, "x", "and it comes back with it, uid for uid")
	end)
end
