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

	local function stepIndex(id)
		for i, step in ipairs(TutorialData.Steps) do
			if step.id == id then
				return i
			end
		end
		error("no tutorial step " .. id)
	end

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

	t.test("the pouch: from the plant step on, once you hold a seed", function()
		local plant = stepIndex("plant")
		t.ok(plant > 1, "the plant step comes after the first")
		for step = 1, plant - 1 do
			t.eq(HudRules.Pouch(step, 4), false, "step " .. step .. " (" .. TutorialData.Steps[step].id .. ")")
		end
		for step = plant, #TutorialData.Steps do
			t.eq(HudRules.Pouch(step, 4), true, "step " .. step)
			t.eq(HudRules.Pouch(step, 0), false, "no seeds, no pouch")
		end
		t.eq(HudRules.Pouch(0, 1), true, "after the tutorial")
		t.eq(HudRules.Pouch(0, 0), false)
		t.eq(HudRules.Pouch(nil, 4), false, "loading")
	end)

	t.test("the pouch waits for TutorialData.PlantStep, the step the server lets you plant from", function()
		t.eq(TutorialData.PlantStep, stepIndex("plant"))
		t.eq(HudRules.Pouch(TutorialData.PlantStep - 1, 4), false)
		t.eq(HudRules.Pouch(TutorialData.PlantStep, 4), TutorialData.CanPlant(TutorialData.PlantStep))
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HudRules.luau")
		t.ok(not string.find(source, "PLANT_STEP", 1, true), "no copy of the plant step of its own")
	end)

	t.test("Send truck home: on foot, away from the truck, and the truck away from its spot", function()
		t.eq(HudRules.SendHome(true, 50, 300), true, "in the forest, walked 50 studs off")
		t.eq(HudRules.SendHome(true, nil, 300), true, "not streamed in: far from you")
		t.eq(HudRules.SendHome(true, 50, 20), false, "in the lot, you at the shops")
		t.eq(HudRules.SendHome(true, nil, 0), false, "parked, out of streaming range")
		t.eq(HudRules.SendHome(true, 50, nil), false, "no truck yet")
		t.eq(HudRules.SendHome(true, 30, 300), false, "standing by it: drive it instead")
		t.eq(HudRules.SendHome(false, 50, 300), false, "driving, or no character")
		-- TruckHome's line is half a parking slot (M1.5: 30 for the 60-stud
		-- slots), so a truck at the far end of its own bay isn't offered.
		t.eq(HudRules.SendHome(true, 50, 30), false, "parked at the end of its own bay")
		t.eq(HudRules.SendHome(true, 41, 31), true, "just past both lines")
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

	-- PLAY-03: the first seeds say to keep them during the tutorial, even
	-- when they come with an extra.
	t.test("Heartseed toasts: none for a plain drop, extras in brackets", function()
		t.eq(HudRules.SeedToast(1, "Oak", {}, false, true), nil, "the flying seed and the pouch say it")
		t.eq(HudRules.SeedToast(2, "Oak", { "lucky" }, false, true), "+2 Oak Heartseeds (lucky)")
		t.eq(
			HudRules.SeedToast(3, "Pine", { "big tree", "lucky" }, false, false),
			"+3 Pine Heartseeds (big tree, lucky)",
			"not the first: no instructions, in the tutorial or not"
		)
	end)

	t.test("the first Heartseeds say what to do: keep them in the tutorial, extras or not", function()
		t.eq(HudRules.SeedToast(1, "Oak", {}, true, false), "+1 Oak Heartseed: keep it for now")
		t.eq(HudRules.SeedToast(2, "Oak", {}, true, false), "+2 Oak Heartseeds: keep them for now")
		t.eq(HudRules.SeedToast(2, "Oak", { "lucky" }, true, false), "+2 Oak Heartseeds (lucky): keep them for now")
		t.eq(
			HudRules.SeedToast(3, "Birch", { "big tree" }, true, false),
			"+3 Birch Heartseeds (big tree): keep them for now"
		)
		t.eq(
			HudRules.SeedToast(4, "Birch", { "big tree", "lucky" }, true, false),
			"+4 Birch Heartseeds (big tree, lucky): keep them for now"
		)
		-- Once planting's allowed (the plant step, or no tutorial).
		t.eq(HudRules.SeedToast(1, "Oak", {}, true, true), "+1 Oak Heartseed: plant it in a stump")
		t.eq(HudRules.SeedToast(2, "Oak", {}, true, true), "+2 Oak Heartseeds: plant them in stumps")
		t.eq(HudRules.SeedToast(2, "Oak", { "lucky" }, true, true), "+2 Oak Heartseeds (lucky): plant them in stumps")
	end)

	t.test("the seed toast's planting word follows TutorialData.CanPlant through the steps", function()
		for step = 1, #TutorialData.Steps do
			local text = HudRules.SeedToast(2, "Oak", { "lucky" }, true, TutorialData.CanPlant(step))
			local keep = step < stepIndex("plant")
			t.eq(string.find(text, "keep them for now", 1, true) ~= nil, keep, "step " .. step)
			t.eq(string.find(text, "plant them in stumps", 1, true) ~= nil, not keep, "step " .. step)
		end
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
				t.eq(file, owner.file, owner.key .. " is also bound in " .. file)
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
end
