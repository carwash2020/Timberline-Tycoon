--!nocheck
-- QualityProfile: the Lower / Higher choice, the screen that asks for it, how
-- it meets the device, and what each choice controls (Connor, 7 October 2026:
-- "just let them pick between lower quality (Phone) or higher quality at
-- launch"). The rules are pure; the saved setting, the remote and the shop box
-- windows have their own tests (SettingsLogic, ProfileSchema, QualityService,
-- BoxWindows below).
local fs = require("@lune/fs")

return function(t)
	local QualityProfile = t.shared("QualityProfile")
	local QualityBudgets = t.shared("QualityBudgets")
	local SettingsLogic = t.shared("SettingsLogic")

	t.test("two choices with the wording the screen shows", function()
		t.eq(QualityProfile.Choices, { "low", "high" })
		t.eq(QualityProfile.Options.low.button, "Lower quality (best for phones)")
		t.eq(QualityProfile.Options.high.button, "Higher quality (Xbox, PC, tablets)")
		for _, id in ipairs(QualityProfile.Choices) do
			local option = QualityProfile.Options[id]
			t.eq(option.id, id)
			t.ok(
				#option.blurb > 20 and not string.find(option.blurb, "\n", 1, true),
				id .. " has a one-line description"
			)
			t.ok(string.find(option.button, option.title, 1, true), "the whole name starts with the title")
		end
		t.ok(#QualityProfile.PickerTitle > 0 and #QualityProfile.PickerHint > 0)
		t.ok(string.find(QualityProfile.PickerHint, "Settings", 1, true), "it says where to change it later")
	end)

	t.test("the device recommendation: a touch-only screen is Lower, a console or a PC is Higher", function()
		t.eq(QualityProfile.Recommended(true), "low")
		t.eq(QualityProfile.Recommended(false), "high")
		-- A save that once forced the old Graphics override keeps its lean.
		t.eq(QualityProfile.Recommended(false, "low"), "low")
		t.eq(QualityProfile.Recommended(true, "high"), "high")
		t.eq(QualityProfile.Recommended(true, "medium"), "high")
		t.eq(QualityProfile.Recommended(true, "auto"), "low")
		t.eq(QualityProfile.Recommended(false, nil), "high")
	end)

	t.test("the screen shows until a real choice is saved, once", function()
		t.eq(QualityProfile.NeedsPicker("unset"), true, "a new save")
		t.eq(QualityProfile.NeedsPicker(nil), true, "an old save with no key")
		t.eq(QualityProfile.NeedsPicker("ultra"), true, "a bad value is asked again")
		t.eq(QualityProfile.NeedsPicker(42), true)
		t.eq(QualityProfile.NeedsPicker("low"), false)
		t.eq(QualityProfile.NeedsPicker("high"), false)
		t.eq(QualityProfile.Sanitize("low"), "low")
		t.eq(QualityProfile.Sanitize("high"), "high")
		t.eq(QualityProfile.Sanitize("medium"), "unset")
		t.eq(QualityProfile.Sanitize(nil), "unset")
		t.eq(QualityProfile.IsChoice("unset"), false, "unset is never a choice")
	end)

	t.test("the choice in force, the Settings row, and the other choice", function()
		t.eq(QualityProfile.Resolve("low", "high"), "low", "a saved choice wins over the device")
		t.eq(QualityProfile.Resolve("high", "low"), "high")
		t.eq(QualityProfile.Resolve("unset", "low"), "low", "until chosen, the recommendation")
		t.eq(QualityProfile.Resolve(nil, "high"), "high")
		t.eq(QualityProfile.Other("low"), "high")
		t.eq(QualityProfile.Other("high"), "low")
		t.eq(QualityProfile.RowText("low", "high"), "Graphics: Lower")
		t.eq(QualityProfile.RowText("high", "low"), "Graphics: Higher")
		t.eq(QualityProfile.RowText("unset", "low"), "Graphics: Lower", "an unchosen save shows what it follows")
	end)

	t.test("Lower is always low; Higher is the device's tier, and a weak device is allowed medium", function()
		-- saved, device tier -> tier that runs
		local cases = {
			{ "low", "low", "low" },
			{ "low", "medium", "low" },
			{ "low", "high", "low" }, -- Lower on a PC: lower
			{ "high", "high", "high" },
			{ "high", "medium", "medium" }, -- never heavier than the device says
			{ "high", "low", "medium" }, -- Higher on a phone or a weak PC: the high world, calm motion
			{ "unset", "low", "low" }, -- not chosen yet: the device alone, as before
			{ "unset", "medium", "medium" },
			{ "unset", "high", "high" },
			{ nil, "high", "high" },
			{ "bogus", "low", "low" },
			{ "high", "nonsense", "high" },
		}
		for _, c in ipairs(cases) do
			t.eq(
				QualityProfile.TierFor(c[1], c[2]),
				c[3],
				string.format("saved %s on a %s device", tostring(c[1]), tostring(c[2]))
			)
		end
		-- Higher never raises above "high", and the tier is always one with a budget.
		for _, saved in ipairs({ "low", "high", "unset" }) do
			for _, device in ipairs({ "low", "medium", "high" }) do
				local tier = QualityProfile.TierFor(saved, device)
				t.eq(QualityBudgets.For(tier).Tier, tier)
			end
		end
	end)

	t.test("the choice never reaches gameplay: only the client's budgets and the box windows read it", function()
		-- No server module reads settings.quality but the one that saves it.
		for _, file in ipairs(fs.readDir("src/ServerScriptService")) do
			if string.match(file, "%.luau$") and file ~= "QualityService.luau" and file ~= "ProfileSchema.luau" then
				local source = string.gsub(fs.readFile("src/ServerScriptService/" .. file), "%-%-[^\n]*", "")
				t.eq(
					string.find(source, "settings.quality", 1, true),
					nil,
					file .. " must not read the graphics choice"
				)
				t.eq(string.find(source, "SettingQuality", 1, true), nil, file)
			end
		end
		-- The pure rule modules know nothing about prices, boxes' holds or hitboxes.
		for _, name in ipairs({ "QualityProfile", "BoxWindows" }) do
			local source =
				string.gsub(fs.readFile("src/ReplicatedStorage/Shared/" .. name .. ".luau"), "%-%-[^\n]*", "")
			for _, word in ipairs({ "priceCash", "UnitPrice", "CanCollide", "CanQuery", "Anchored" }) do
				t.eq(string.find(source, word, 1, true), nil, name .. " must not touch " .. word)
			end
		end
	end)

	t.test("Lower trims the budgets that make the dressing; Higher is today's look", function()
		local High, Low = QualityBudgets.High, QualityBudgets.Low
		t.eq(High.BoxContents, true)
		t.eq(Low.BoxContents, false, "no item copies in the box windows")
		t.ok(Low.LightScale < High.LightScale and Low.LightScale <= 0.6, "shorter light reach")
		t.eq(High.LightScale, 1)
		t.ok(Low.NpcAnimateRange < High.NpcAnimateRange, "fewer NPC extras")
		t.ok(Low.MaxDecor < High.MaxDecor, "fewer decor models")
		t.ok(Low.TuftNear < High.TuftNear, "tufts only close by")
		t.ok(Low.FillerNear < High.FillerNear and Low.FillerFar < High.FillerFar, "the forest ring's fillers closer in")
		t.ok(Low.LeafShadows == false and High.LeafShadows == true, "no leaf shadows on Lower")
		t.eq(QualityBudgets.Medium.BoxContents, true, "a weak device on Higher still gets the boxes' items")
	end)

	t.test("the settings key and the attribute the client reads agree", function()
		t.eq(SettingsLogic.QualityAttribute, "SettingQuality")
		t.eq(SettingsLogic.Attributes.quality, "SettingQuality")
		t.eq(SettingsLogic.Defaults.quality, "unset")
	end)
end
