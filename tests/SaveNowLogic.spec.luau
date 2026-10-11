--!nocheck
-- Lane F: the SAVES panel's Save now (decision 11). Pure rules: the 30 s
-- cooldown that writes nothing while it runs, "Saved at 11:42", and the
-- refusals. The contract's save-slot fields: which swap with a slot and which
-- stay with the account.
return function(t)
	local SaveNow = t.shared("SaveNowLogic")
	local SaveSlotLogic = t.shared("SaveSlotLogic")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function state(over)
		local s = { now = 1000, untilAt = 0, busy = false, picking = false, hasProfile = true }
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	t.test("a write is allowed once the cooldown is over, and Stamp sets the next one 30 s on", function()
		t.eq(SaveNow.Cooldown, 30)
		t.eq({ SaveNow.Check(state()) }, { true, nil })
		t.eq(SaveNow.Stamp(1000), 1030)
		t.eq(SaveNow.Check(state({ now = 1010, untilAt = 1030 })), false)
		t.eq({ SaveNow.Check(state({ now = 1030, untilAt = 1030 })) }, { true, nil }, "exactly on time")
		local _, why = SaveNow.Check(state({ now = 1010, untilAt = 1030 }))
		t.eq(why, "Saved a moment ago. Try again in 20 seconds.")
		local _, soon = SaveNow.Check(state({ now = 1029.5, untilAt = 1030 }))
		t.eq(soon, "Saved a moment ago. Try again in 1 seconds.", "never says 0 seconds")
	end)

	t.test("refused mid-swap, mid-unload, before a save is picked, and with no profile", function()
		local ok, why = SaveNow.Check(state({ busy = true }))
		t.eq({ ok, why }, { false, SaveNow.Reasons.busy })
		ok, why = SaveNow.Check(state({ picking = true }))
		t.eq({ ok, why }, { false, SaveNow.Reasons.picking })
		ok, why = SaveNow.Check(state({ hasProfile = false }))
		t.eq({ ok, why }, { false, nil }, "a malformed press is ignored in silence")
		-- The order: nothing to do first, then the join pick, then a change in flight.
		t.eq(select(2, SaveNow.Check(state({ picking = true, busy = true }))), SaveNow.Reasons.picking)
	end)

	t.test("only the save being played may be written", function()
		t.eq(SaveNow.SlotOk(2, 2), true)
		t.eq(SaveNow.SlotOk(1, 2), false)
		t.eq(SaveNow.SlotOk("2", 2), false)
		t.eq(SaveNow.SlotOk(nil, 2), false)
		t.eq(SaveNow.SlotOk({}, 2), false)
	end)

	t.test("Saved at 11:42, in the viewer's own time", function()
		-- 2026-10-10 17:42:00 UTC
		local unix = 1791654120
		t.eq(SaveNow.Text(unix, 0), "Saved at 17:42")
		t.eq(SaveNow.Text(unix, -360), "Saved at 11:42", "Mountain time, six hours behind")
		t.eq(SaveNow.Text(unix, 120), "Saved at 19:42")
		t.eq(SaveNow.Text(unix, -17 * 60 - 42), "Saved at 0:00", "wraps at midnight")
		t.eq(SaveNow.Text(0, 0), "Not saved yet")
		t.eq(SaveNow.Text(nil, 0), "Not saved yet")
		t.eq(SaveNow.Text(0 / 0, 0), "Not saved yet")
	end)

	t.test("the button counts the cooldown down and greys out while it runs", function()
		t.eq(SaveNow.ButtonText(1000, 0), "Save now")
		t.eq(SaveNow.ButtonText(1000, 1030), "Saved (30s)")
		t.eq(SaveNow.ButtonText(1029.2, 1030), "Saved (1s)")
		t.eq(SaveNow.ButtonText(1030, 1030), "Save now")
		t.eq(SaveNow.Ready(1000, 1030), false)
		t.eq(SaveNow.Ready(1030, 1030), true)
		t.eq(SaveNow.Ready(1000, nil), true)
	end)

	-----------------------------------------------------------------------
	-- The contract's save-slot fields (the SaveSlotLogic copy lists)
	-----------------------------------------------------------------------

	t.test("saveCooldownUntil is account-wide: a slot swap must not clear it", function()
		t.eq(SaveSlotLogic.IsAccountKey("saveCooldownUntil"), true)
	end)

	t.test("the contract's per-slot fields travel with a slot and the account's stay put", function()
		-- Per the shared contract (A1): a slot's own fields swap when a save is loaded.
		for _, key in ipairs({
			"gondolaPass",
			"skyQuest",
			"temper",
			"relics",
			"forgeOrder",
			"strandedLoad",
			"worldVersion",
		}) do
			t.eq(SaveSlotLogic.IsAccountKey(key), false, key .. " is a slot field")
			t.ok(Schema.Template[key] ~= nil, key .. " is in the template")
		end
		-- Account fields A1 set (and Lane M's mining, which Connor kept account-wide;
		-- the brief lists it as a slot field: flagged in the PR).
		for _, key in ipairs({ "tipsSeen", "saveCooldownUntil", "baseCooldownUntil", "onboarding", "mining" }) do
			t.eq(SaveSlotLogic.IsAccountKey(key), true, key .. " follows the account")
		end
		-- A swap really moves them: slot 1's furnace-side fields go into its snapshot.
		local data = Util.deepCopy(Schema.Template)
		Schema.Migrate(data)
		data.gondolaPass = true
		data.relics = { star = true }
		data.plot.loose = { { slab = true, at = { 1, 0, 1, 0, 0, 0 } } }
		data.saveCooldownUntil = 5000
		local ok = SaveSlotLogic.Perform(data, "load", 2, 1893456000, Schema.Template, function()
			return "uid-" .. tostring(math.random(1, 1e9))
		end, {
			commit = function() end,
			setCash = function() end,
			rebuild = function() end,
		})
		t.eq(ok, true)
		t.eq(data.gondolaPass, false, "the other save has no gondola pass")
		t.eq(data.relics, {}, "or relics")
		t.eq(#data.plot.loose, 0, "or loose wood waiting for its base")
		t.eq(data.saveCooldownUntil, 5000, "but the Save now cooldown stays")
		t.eq(data.slots[1].gondolaPass, true, "the first save kept its own")
		t.eq(#data.slots[1].plot.loose, 1, "and its saved loose wood")
	end)
end
