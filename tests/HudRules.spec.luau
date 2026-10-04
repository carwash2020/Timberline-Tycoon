--!nocheck
-- When the HUD's optional pieces show (StarterPlayerScripts/HudRules): the
-- first minute has one objective, so Daily Goals and the pouch wait for
-- the tutorial, "Send truck home" waits until the truck is away, and
-- "Drop axe" waits until you have an axe to spare and takes two presses;
-- the load chip says what's in your hands and your truck's bed; the
-- HUD's loading card says what the wait is for.
return function(t)
	local HudRules = t.load("StarterPlayer/StarterPlayerScripts/HudRules")
	local TutorialData = t.shared("TutorialData")

	t.test("the tutorial runs while TutorialStep > 0, and while the save loads (nil)", function()
		t.eq(HudRules.TutorialRunning(nil), true)
		t.eq(HudRules.TutorialRunning(1), true)
		t.eq(HudRules.TutorialRunning(#TutorialData.Steps), true)
		t.eq(HudRules.TutorialRunning(0), false)
		t.eq(HudRules.TutorialRunning("0"), true, "only a number counts")
	end)

	t.test("Daily Goals: hidden through the whole tutorial, shown after it", function()
		for step = 1, #TutorialData.Steps do
			t.eq(HudRules.DailyButton(step, 3), false, "step " .. step)
		end
		t.eq(HudRules.DailyButton(nil, 3), false, "loading")
		t.eq(HudRules.DailyButton(0, 3), true)
		t.eq(HudRules.DailyButton(0, 0), false, "no goals yet")
	end)

	t.test("the Daily Goals label: the streak after the count; a phone drops GOALS when there's one", function()
		t.eq(HudRules.DailyLabel(1, 3, 0, false), "DAILY GOALS  1/3")
		t.eq(HudRules.DailyLabel(1, 3, 5, false), "DAILY GOALS  1/3  ·  5-day streak", "a computer, as before")
		t.eq(HudRules.DailyLabel(1, 3, 0, true), "DAILY GOALS  1/3", "a phone with no streak")
		t.eq(HudRules.DailyLabel(3, 3, 12, true), "DAILY 3/3  ·  12-day streak")
		t.ok(#HudRules.DailyLabel(1, 3, 99, true) < #HudRules.DailyLabel(1, 3, 99, false), "shorter on a phone")
		-- An odd streak attribute never breaks the button.
		t.eq(HudRules.DailyLabel(0, 3, 0 / 0, true), "DAILY GOALS  0/3", "NaN: no streak")
		t.eq(HudRules.DailyLabel(0, 3, -2, false), "DAILY GOALS  0/3")
		t.eq(HudRules.DailyLabel(0, 3, math.huge, false), "DAILY GOALS  0/3")
		t.eq(HudRules.DailyLabel(0, 3, 4.7, false), "DAILY GOALS  0/3  ·  4-day streak", "whole days")
	end)

	t.test("the compact Daily Goals icon is just the count", function()
		t.eq(HudRules.DailyMark(1, 3), "1/3")
		t.eq(HudRules.DailyMark(0, 3), "0/3")
		t.eq(HudRules.DailyMark(0 / 0, 3), "0/3", "NaN done")
		t.eq(HudRules.DailyMark(2, 0 / 0), "2/0", "NaN total")
		t.eq(HudRules.DailyMark(1.9, 3.2), "1/3", "whole numbers")
	end)

	t.test("Send truck home: on foot, away from the truck, and the truck away from its spot", function()
		t.eq(HudRules.SendHome(true, 50, 300), true, "in the forest, walked 50 studs off")
		t.eq(HudRules.SendHome(true, nil, 300), true, "not streamed in: far from you")
		t.eq(HudRules.SendHome(true, 50, 20), false, "in the lot, you at the shops")
		t.eq(HudRules.SendHome(true, nil, 0), false, "parked, out of streaming range")
		t.eq(HudRules.SendHome(true, 50, nil), false, "no truck yet")
		t.eq(HudRules.SendHome(true, 30, 300), false, "standing by it: drive it instead")
		t.eq(HudRules.SendHome(false, 50, 300), false, "driving, or no character")
		-- TruckHome's line is half the longest parking bay's diagonal (phase
		-- 12: 42 for the 80 x 16 bay; M1.5's was 30), so a truck at the far
		-- end of its own bay isn't offered.
		t.eq(HudRules.SendHome(true, 50, 42), false, "parked at the end of its own bay")
		t.eq(HudRules.SendHome(true, 43, 43), true, "just past both lines")
	end)

	t.test("Drop axe: never for a new player's lone Rusty Axe", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local starter = ItemCatalog.AxeLadder()[1].id
		t.eq(starter, "RustyAxe")
		t.eq(HudRules.DropAxe(1, starter), false, "a fresh profile")
		t.eq(HudRules.DropAxe(2, starter), true, "a second axe in the Backpack")
		t.eq(HudRules.DropAxe(1, "SteelAxe"), true, "holding a better one")
		t.eq(HudRules.DropAxe(3, nil), false, "nothing in hand")
		t.eq(HudRules.DropAxe(0, nil), false)
		t.eq(HudRules.DropAxe(1, "NoSuchAxe"), false, "an unknown axe counts as the starter")
		t.eq(HudRules.DropAxe(3, "LuxAxe"), false, "a pass axe never offers Drop")
	end)

	t.test("Drop axe takes two presses, 0.3 to 3 s apart", function()
		-- One press only waits.
		local drop, at = HudRules.DropPress(nil, 10)
		t.eq(drop, false, "one tap doesn't drop it")
		t.eq(at, 10)
		-- A second one in the window drops.
		drop, at = HudRules.DropPress(10, 11)
		t.eq(drop, true)
		t.eq(at, nil)
		t.eq((HudRules.DropPress(10, 10.3)), true, "right at the gap")
		t.eq((HudRules.DropPress(10, 13)), true, "right at the end")
	end)

	t.test("a double tap, a bounce or mashing doesn't confirm; a late press starts again", function()
		local drop, at = HudRules.DropPress(10, 10.1)
		t.eq(drop, false)
		t.eq(at, 10, "still waiting, from the first press")
		-- Three presses 0.1 s apart (mashing) never drop.
		local armed = nil
		local dropped = false
		for i = 0, 2 do
			local d, a = HudRules.DropPress(armed, 20 + i * 0.1)
			dropped = dropped or d
			armed = a
		end
		t.eq(dropped, false)
		t.eq(armed, 20)
		-- Too late: that press is a new first press.
		drop, at = HudRules.DropPress(10, 13.5)
		t.eq(drop, false)
		t.eq(at, 13.5)
	end)
	local HANDS = t.shared("GameConfig").HandCapacity

	t.test("the load chip: Hands, then Bed with a truck; Bed full and amber at capacity", function()
		t.eq(HANDS, 2, "you carry two")
		local function chip(carried, bed, room)
			return HudRules.LoadChip(carried, bed, room, HANDS, false)
		end
		t.eq(chip(1, 0, 0), { shown = true, hands = "Hands 1/2", full = false }, "a log in hand, no truck bed")
		t.eq(chip(1, 0, 6), { shown = true, hands = "Hands 1/2", bed = "Bed 0/6", full = false }, "picked one up")
		t.eq(chip(0, 1, 6), { shown = true, hands = "Hands 0/2", bed = "Bed 1/6", full = false }, "loaded it")
		t.eq(chip(2, 4, 6), { shown = true, hands = "Hands 2/2", bed = "Bed 4/6", full = false })
		t.eq(chip(0, 6, 6), { shown = true, hands = "Hands 0/2", bed = "Bed full", full = true }, "a full bed")
		t.eq(chip(0, 7, 6).full, true, "more than full still reads full")
		t.eq(chip(2, 12, 12).bed, "Bed full")
		-- The Scout ATV has no bed: the chip is just your hands.
		t.eq(chip(2, 0, 0), { shown = true, hands = "Hands 2/2", full = false })
	end)

	t.test("the load chip hides with nothing in hand or bed, and while a panel is open", function()
		t.eq(HudRules.LoadChip(nil, nil, nil, HANDS, false).shown, false, "the save still loading")
		t.eq(HudRules.LoadChip(0, 0, 0, HANDS, false).shown, false, "no truck, nothing carried")
		t.eq(HudRules.LoadChip(0, 0, nil, HANDS, false).shown, false, "BedCapacity not set yet")
		-- UI-FU-1: everyone has a truck from the moment they join; an empty
		-- one doesn't put "Hands 0/2 · Bed 0/6" on screen from minute one.
		t.eq(
			HudRules.LoadChip(0, 0, 6, HANDS, false),
			{ shown = false, hands = "Hands 0/2", bed = "Bed 0/6", full = false },
			"a new player's empty truck: hidden"
		)
		t.eq(HudRules.LoadChip(0, 0, 12, HANDS, false).shown, false, "a bigger empty truck too")
		t.eq(HudRules.LoadChip(1, 0, 6, HANDS, false).shown, true, "the first log picked up shows it")
		t.eq(HudRules.LoadChip(0, 1, 6, HANDS, false).shown, true, "and it stays while the log's in the bed")
		t.eq(HudRules.LoadChip(0, 0, 6, HANDS, false).shown, false, "sold: the bed's empty again, it goes")
		for _, case in ipairs({ { 1, 0, 0 }, { 0, 3, 6 }, { 2, 6, 6 }, { 0, 0, 6 } }) do
			local view = HudRules.LoadChip(case[1], case[2], case[3], HANDS, true)
			t.eq(view.shown, false, "hidden with the hint while the shop is open")
		end
	end)

	t.test("the load chip reads odd attribute values as 0", function()
		local odd = HudRules.LoadChip("2", 0 / 0, -3, HANDS, false)
		t.eq(odd, { shown = false, hands = "Hands 0/2", full = false })
		t.eq(HudRules.LoadChip(1.7, 2.2, 6.9, HANDS, false).hands, "Hands 1/2", "whole numbers")
		t.eq(HudRules.LoadChip(1.7, 2.2, 6.9, HANDS, false).bed, "Bed 2/6")
		t.eq(HudRules.LoadChip(math.huge, 0, 0, HANDS, false).hands, "Hands 999/2", "never a format error")
	end)
	t.test("the HUD's loading card: building the world, then loading your save, then gone", function()
		t.eq(HudRules.LoadingText(false, nil), "Building the world...", "no Remotes yet: the map is still building")
		t.eq(HudRules.LoadingText(true, nil), "Loading your save...", "Remotes are in")
		t.eq(HudRules.LoadingText(true, false), "Loading your save...")
		t.eq(HudRules.LoadingText(true, true), nil, "the save is in: the card goes")
		t.eq(HudRules.LoadingText(false, true), nil, "a loaded save always takes it down")
		t.eq(HudRules.LoadingText(true, "true"), "Loading your save...", "only the boolean counts")
	end)

	-- A toast's seconds, near enough (the formula's floats).
	local function near(actual, expected, what)
		t.ok(math.abs(actual - expected) < 1e-9, string.format("%s: %s s, not %s s", what, actual, expected))
	end

	t.test("a toast stays 1.6 s plus 0.045 s a character, from 2.5 to 6 s", function()
		near(HudRules.ToastSeconds(""), 2.5, "empty")
		near(HudRules.ToastSeconds("Hop out first."), 2.5, "short: the least")
		near(HudRules.ToastSeconds(string.rep("x", 20)), 2.5, "20 characters: the least")
		near(HudRules.ToastSeconds(string.rep("x", 40)), 1.6 + 0.045 * 40, "40 characters")
		near(HudRules.ToastSeconds(string.rep("x", 60)), 1.6 + 0.045 * 60, "60 characters")
		near(HudRules.ToastSeconds(string.rep("x", 98)), 6, "98 characters: the most")
		near(HudRules.ToastSeconds(string.rep("x", 400)), 6, "a long one: still the most")
		-- Longer never means shorter.
		local last = 0
		for n = 0, 140 do
			local s = HudRules.ToastSeconds(string.rep("x", n))
			t.ok(s >= last and s >= 2.5 and s <= 6, n .. " characters")
			last = s
		end
		-- A real one: the lightning toast, 72 characters (4.84 s).
		local struck = "Lightning struck an oak nearby! Fell it within 2 minutes for Stormgrain."
		near(HudRules.ToastSeconds(struck), 1.6 + 0.045 * #struck, "the lightning toast")
	end)

	t.test("a toast's length is its plain text: rich-text tags out, an entity or a · one character", function()
		local plain = "Sold 4 logs for $120"
		local rich = '<font color="#3F7A34" weight="heavy">Sold 4 logs</font> for <b>$120</b>'
		local long = string.rep("word ", 12) -- 60 characters
		local richLong = "<i>" .. long .. "</i>"
		t.eq(HudRules.ToastSeconds(rich), HudRules.ToastSeconds(plain))
		t.eq(HudRules.ToastSeconds(richLong), HudRules.ToastSeconds(long))
		near(HudRules.ToastSeconds(string.rep("&amp;", 60)), 1.6 + 0.045 * 60, "60 entities")
		near(HudRules.ToastSeconds(string.rep("·", 60)), 1.6 + 0.045 * 60, "60 middle dots (two bytes each)")
	end)

	t.test("a confirm toast (press again to go ahead) stays the full 6 s; a caller's seconds win", function()
		t.eq(HudRules.ConfirmToastSeconds, 6)
		-- VehicleService's recall confirm (it waits 6 s for the second press).
		t.eq(
			HudRules.ToastSeconds(
				"Your 1 log will be left where your truck stands. Press Send truck home again to go ahead."
			),
			6
		)
		t.eq(HudRules.ToastSeconds("Tap again to skip"), 6)
		t.ok(HudRules.ToastSeconds("Your truck's on its way. Try again in 4 s.") < 6, "a cooldown isn't a confirm")
		t.ok(HudRules.ToastSeconds("Northern Hills is healthy again.") < 6)
		t.eq(HudRules.ToastSeconds("Hi", 6), 6, "the caller's seconds")
		t.eq(HudRules.ToastSeconds(string.rep("x", 200), 3), 3, "even for a long one")
		t.eq(HudRules.ToastSeconds("Hi", 0), 1, "never under 1 s")
		t.eq(HudRules.ToastSeconds("Hi", 1e9), 15, "nor over 15 s")
		t.eq(HudRules.ToastSeconds("Hi", 0 / 0), 2.5, "NaN: by its length")
	end)

	t.test("the corner clock: Day or Night and the hour, as it always read", function()
		local GameConfig = t.shared("GameConfig")
		t.eq(HudRules.ClockText(14 + 5 / 60), "Day 14:05")
		t.eq(HudRules.ClockText(22 + 10 / 60), "Night 22:10")
		t.eq(HudRules.ClockText(0), "Night 00:00")
		t.eq(
			HudRules.ClockText(GameConfig.NightStartsAt),
			"Night " .. string.format("%02d:00", GameConfig.NightStartsAt)
		)
		t.eq(HudRules.ClockText(GameConfig.NightEndsAt), "Day " .. string.format("%02d:00", GameConfig.NightEndsAt))
	end)

	t.test("the corner clock shows Lighting.ClockTime, so Studio's ClockOverride shows on it", function()
		local ClockOverride = t.shared("ClockOverride")
		-- A tester sets the override to 23 at noon: the sky goes dark, and so must the label.
		t.eq(HudRules.ClockText(ClockOverride.Apply(12, 23, true)), "Night 23:00")
		t.eq(HudRules.ClockText(ClockOverride.Apply(12, 23, false)), "Day 12:00", "a live server ignores it")
		-- WorldUI reads the hour LightingController sets, not the server clock again.
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WorldUI.luau")
		local clock = string.match(source, "local function buildClock%(%).-\nend\n")
		t.ok(clock, "WorldUI's buildClock moved")
		t.ok(
			string.find(clock, "HudRules.ClockText(Lighting.ClockTime)", 1, true),
			"the label reads Lighting.ClockTime"
		)
		t.ok(not string.find(clock, "GetServerTimeNow", 1, true), "and doesn't work the hour out again")
	end)
	-- UI-15: the gamepad's D-pad shortcuts.
	local PAD_OWNERS = {
		daily = { key = "DPadUp", file = "DailyUI" },
		guide = { key = "DPadLeft", file = "FieldGuideUI" },
		settings = { key = "DPadRight", file = "SettingsUI" },
		dropAxe = { key = "DPadDown", file = "AxeController" },
	}

	t.test("the D-pad: Up Daily Goals, Left the Field Guide, Right Settings, Down Drop axe", function()
		local seen = {}
		local count = 0
		for name, key in pairs(HudRules.PadKeys) do
			count += 1
			t.ok(PAD_OWNERS[name], "an unexpected pad shortcut " .. name)
			t.eq(key, PAD_OWNERS[name].key, name)
			t.ok(not seen[key], key .. " used twice")
			seen[key] = true
		end
		t.eq(count, 4)
	end)

	-- The one exception: while you hold a piece of wood (the v2 loop's
	-- DragController), the D-pad pushes, pulls and turns it. Checked below:
	-- only while holding, over HUD's shortcuts, and handed back on the drop.
	local WHILE_HOLDING = "DragController"

	t.test("each D-pad direction is bound by its own controller and by nothing else on the client", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		local users = {} -- key -> { file }
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") then
				local source = fs.readFile(dir .. "/" .. entry)
				for key in string.gmatch(source, "Enum%.KeyCode%.(DPad%a+)") do
					users[key] = users[key] or {}
					users[key][string.gsub(entry, "%.luau$", "")] = true
				end
			end
		end
		for name, owner in pairs(PAD_OWNERS) do
			local files = users[owner.key] or {}
			t.ok(files[owner.file], string.format("%s (%s) isn't bound in %s", name, owner.key, owner.file))
			for file in pairs(files) do
				if file ~= WHILE_HOLDING then
					t.eq(file, owner.file, owner.key .. " is also bound in " .. file)
				end
			end
		end
		for _, name in ipairs({ "daily", "guide", "settings" }) do
			local owner = PAD_OWNERS[name]
			local source = fs.readFile(dir .. "/" .. owner.file .. ".luau")
			t.ok(
				string.find(source, "HUD.PadShortcut(Enum.KeyCode." .. owner.key, 1, true),
				owner.file .. " registers its shortcut with HUD.PadShortcut"
			)
			t.ok(
				string.find(source, "HUD.PadGlyph(Enum.KeyCode." .. owner.key, 1, true),
				owner.file .. " shows its glyph chip"
			)
		end
	end)

	t.test("a held piece of wood takes the D-pad only while held, over HUD's shortcuts", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/" .. WHILE_HOLDING .. ".luau")
		-- Every D-pad key it names is in bindHold (the grab), nowhere else.
		local from = string.find(source, "local function bindHold()", 1, true)
		local to = string.find(source, "local function unbindHold()", 1, true)
		t.ok(from and to and from < to, "bindHold, then unbindHold")
		local count = 0
		local at = 1
		while true do
			local s, e = string.find(source, "Enum%.KeyCode%.DPad%a+", at)
			if not s then
				break
			end
			count += 1
			t.ok(s > from and s < to, "a D-pad key named outside bindHold at " .. s)
			at = e + 1
		end
		t.eq(count, 4, "all four, for pushing, pulling and turning")
		t.ok(
			string.find(source, "HOLD_PRIORITY = Enum.ContextActionPriority.High.Value + 1", 1, true),
			"over HUD.PadShortcut's priority (High)"
		)
		local unbind = string.sub(source, to, (string.find(source, "\nend\n", to, true)))
		t.ok(string.find(unbind, 'UnbindAction("DragPad")', 1, true), "handed back on the drop")
	end)

	t.test("a D-pad shortcut works only when nothing else holds the pad", function()
		local function state(over)
			local s = {
				available = true,
				typing = false,
				selecting = false,
				modal = false,
				seated = false,
				prompt = false,
			}
			for k, v in pairs(over or {}) do
				s[k] = v
			end
			return s
		end
		t.eq(HudRules.PadShortcut(state()), true, "on foot, nothing open: it opens")
		t.eq(HudRules.PadShortcut(state({ available = false })), false, "Daily during the tutorial, no Field Guide yet")
		t.eq(HudRules.PadShortcut(state({ typing = true })), false, "typing in chat")
		t.eq(HudRules.PadShortcut(state({ selecting = true })), false, "a menu has the selection (the D-pad moves it)")
		t.eq(HudRules.PadShortcut(state({ modal = true })), false, "a shop, the Store or the Field Guide is open")
		t.eq(HudRules.PadShortcut(state({ seated = true })), false, "driving a truck")
		t.eq(HudRules.PadShortcut(state({ prompt = true })), false, "a world prompt uses that button")
	end)

	t.test("glyph chips and popup selection: on a gamepad or a TV only, never for a mouse or a finger", function()
		t.eq(HudRules.PadGlyphs("console"), true)
		t.eq(HudRules.PadGlyphs("desktop"), false)
		t.eq(HudRules.PadGlyphs("phone"), false)
		t.eq(HudRules.PadSelects("console"), true)
		t.eq(HudRules.PadSelects("desktop"), false)
		t.eq(HudRules.PadSelects("phone"), false)
	end)

	---------------------------------------------------------------------------
	-- The v2 loop (V2_PLAN.md §4a, §4d)
	---------------------------------------------------------------------------

	local FieldGuide = t.shared("FieldGuide")
	local WoodData = t.shared("WoodData")

	t.test("v2: no hands to count; the HUD's u³ and dollars are the Field Guide's", function()
		t.eq(HudRules.ShowsHands(1), true, "v1: Hands 1/2")
		t.eq(HudRules.ShowsHands(2), false, "v2: one piece at a time, with a tooltip")
		t.ok(HudRules.VolumeText == FieldGuide.VolumeText, "one rounding rule for u³")
		t.ok(HudRules.VolumeNumber == FieldGuide.VolumeNumber)
		t.ok(HudRules.PriceText == FieldGuide.PriceText)
		t.ok(HudRules.CashText == FieldGuide.CashText, "and for dollars")
	end)

	t.test("v2: the hold tooltip names the wood, its u³ and its worth", function()
		local V, C = FieldGuide.VolumeText, FieldGuide.CashText
		for _, wood in ipairs(WoodData.All()) do
			t.eq(
				HudRules.WoodTooltip(wood.id, "log", 26.3, 39.6),
				wood.displayName .. " log · " .. V(26.3) .. " · " .. C(39.6),
				wood.id
			)
		end
		t.eq(HudRules.WoodTooltip("oak", "log", 26.3, 39), "Oak log · 26 u³ · $39", "V2_PLAN's example")
		t.eq(HudRules.WoodTooltip("maple", "plank", 2, 52.8), "Maple plank · " .. V(2) .. " · " .. C(52.8))
		t.eq(HudRules.WoodTooltip("oak", nil, 4.4, 6.6), "Oak log · 4.4 u³ · $7", "no Kind yet: a log")
		t.eq(HudRules.WoodTooltip("oak", "log", 0.2, 0.3), "Oak log · 0.2 u³ · $1", "what selling it alone pays")
		t.eq(HudRules.WoodTooltip("oak", "log", nil, 39), "Oak log · $39", "Volume not replicated yet")
		t.eq(HudRules.WoodTooltip("oak", "log", 26, 0 / 0), "Oak log · 26 u³", "a NaN value is left out")
		t.eq(HudRules.WoodTooltip("nope", "log", 1, 1), nil, "not a known wood")
		t.eq(HudRules.WoodTooltip(nil, "log", 1, 1), nil)
		t.eq(HudRules.WoodTooltip(5, "log", 1, 1), nil)
	end)

	t.test("v2: the bed chip in u³, with the load's worth, hidden while empty", function()
		local function chip(volume, room, value, modal)
			return HudRules.BedChip(volume, room, value, modal or false)
		end
		t.eq(chip(41.2, 96, 61.2), { shown = true, text = "Bed 41 / 96 u³ · $61", full = false })
		t.eq(chip(41.2, nil, 61.2), { shown = true, text = "Bed 41 u³ · $61", full = false }, "no room figure")
		t.eq(chip(4.44, 0, 0.4), { shown = true, text = "Bed 4.4 u³ · $1", full = false }, "the pad pays at least $1")
		t.eq(chip(4.44, 0, 0), { shown = true, text = "Bed 4.4 u³", full = false }, "worth nothing: no $0")
		t.eq(chip(96, 96, 140).full, true, "full at the room")
		t.eq(chip(120, 96, 140).full, true, "piled over the walls")
		t.eq(chip(95.9, 96, 140).full, false)
		t.eq(chip(0, 96, 0).shown, false, "an empty bed: no chip")
		t.eq(chip(nil, nil, nil).shown, false, "the truck's attributes not there yet")
		t.eq(chip(5, 96, 8, true).shown, false, "hidden while a panel is open")
		t.eq(chip("5", 0 / 0, -2), { shown = false, text = "Bed 0 u³", full = false }, "junk reads as nothing")
		t.eq(chip(math.huge, 96, math.huge).shown, false)
	end)

	t.test("v2: the bed chip never grows past the v1 chip's longest text", function()
		t.eq(HudRules.BedChipMaxChars, utf8.len("Hands 2/2 · Bed 12/12"))
		for _, volume in ipairs({ 0.4, 4.4, 41, 96, 250, 999 }) do
			for _, room in ipairs({ 0, 19, 96, 400, 999 }) do
				for _, value in ipairs({ 0, 6, 61, 999, 4500, 99999 }) do
					local text = HudRules.BedChip(volume, room, value, false).text
					t.ok(utf8.len(text) <= HudRules.BedChipMaxChars, string.format("%q is too long", text))
				end
			end
		end
		t.eq(HudRules.BedChip(41, 96, 4500, false).text, "Bed 41 / 96 u³", "a big worth drops out before it overflows")
	end)

	-- M1.8b: what the HUD's chip shows under v2.
	local function held(woodId, kind, volume, value)
		return { woodId = woodId, kind = kind, volume = volume, value = value }
	end

	t.test("v2: the chip shows what you hold; else the bed once TruckLoad publishes it; else nothing", function()
		local oak = held("oak", "log", 26.3, 39)
		t.eq(
			HudRules.LoadChipV2(oak, nil, nil, nil, false, false),
			{ shown = true, text = "Oak log · 26 u³ · $39", full = false }
		)
		t.eq(
			HudRules.LoadChipV2(oak, 41.2, 96, 61.2, false, false).text,
			"Oak log · 26 u³ · $39",
			"holding wins over the bed"
		)
		t.eq(HudRules.LoadChipV2(oak, nil, nil, nil, true, false).shown, false, "hidden while a panel is open")
		t.eq(
			HudRules.LoadChipV2(nil, 41.2, 96, 61.2, false, false),
			HudRules.BedChip(41.2, 96, 61.2, false),
			"empty hands: the bed chip"
		)
		t.eq(HudRules.LoadChipV2(nil, 41.2, nil, 61.2, false, true).text, "Bed 41 u³ · $61")
		t.eq(
			HudRules.LoadChipV2(nil, nil, nil, nil, false, false).shown,
			false,
			"no BedVolume yet (TruckLoad, M1.6): no chip, no Hands"
		)
		t.eq(
			HudRules.LoadChipV2(held("nope", "log", 1, 1), 5, nil, 8, false, false).text,
			"Bed 5 u³ · $8",
			"not known wood: the bed instead"
		)
		t.eq(HudRules.LoadChipV2(held(nil, nil, nil, nil), nil, nil, nil, false, false).shown, false)
	end)

	t.test("v2: the HUD wires these rules, and only under the v2 loop", function()
		local fs = require("@lune/fs")
		local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		local function has(text, why)
			t.ok(string.find(hud, text, 1, true) ~= nil, why .. " (" .. text .. ")")
		end
		has("if not HudRules.ShowsHands(CoreLoop.Active()) then", "no Hands chip under v2")
		has("HudRules.LoadChipV2(", "the v2 chip: what you hold, else the bed")
		has('model:GetAttribute("HeldBy") ~= player.UserId', "the held piece is the one whose HeldBy is you")
		has('CollectionService:GetTagged("Wood")', "loose wood, by its tag")
		has("HintLogic.ContextForV2(hintStateV2())", "the v2 hint's context")
		has("if v2Watching or not CoreLoop.V2() then", "the v2 sources start only under v2")
		has("HintLogic.Pick(UITheme.Device(), hintForced or HintLogic.ContextFor(hintState))", "v1's hint as it was")
	end)

	t.test("v2: on a phone the held tooltip fits the chip's longest, dropping the kind, then the u³", function()
		t.eq(HudRules.ChipTooltip(held("oak", "log", 26.3, 39), true), "Oak log · 26 u³ · $39", "fits as it is")
		t.eq(HudRules.ChipTooltip(held("birch", "log", 7.5, 17), true), "Birch · 7.5 u³ · $17")
		t.eq(HudRules.ChipTooltip(held("frostwood", "plank", 4.4, 470), true), "Frostwood · $470")
		t.eq(
			HudRules.ChipTooltip(held("frostwood", "plank", 4.4, 470), false),
			"Frostwood plank · 4.4 u³ · $470",
			"a computer or a TV: all of it"
		)
		for _, wood in ipairs(WoodData.All()) do
			for _, kind in ipairs({ "log", "plank" }) do
				for _, volume in ipairs({ 0.2, 4.4, 26, 140 }) do
					for _, value in ipairs({ 0.3, 39, 470, 4500 }) do
						local text = HudRules.ChipTooltip(held(wood.id, kind, volume, value), true)
						t.ok(
							utf8.len(text) <= HudRules.BedChipMaxChars,
							string.format("%q is longer than the chip's room", text)
						)
						t.ok(string.find(text, wood.displayName, 1, true) == 1, "it names the wood: " .. text)
					end
				end
			end
		end
	end)
end
