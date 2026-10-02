--!nocheck
-- Every player-facing text the v2 loop adds (V2_PLAN.md §0 rule 4): Murph's
-- steps, the hints, the daily goals, the Field Guide pages, the shop cards
-- and the HUD's tooltip and bed chip. None may carry the source game's
-- names, and none may leave a token or a "nan"/"inf" in it. The modules'
-- own source is checked too: the rule covers comments, because
-- ReplicatedStorage ships to every client.
return function(t)
	local DailyData = t.shared("DailyData")
	local FieldGuide = t.shared("FieldGuide")
	local HintLogic = t.shared("HintLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")
	local TutorialData = t.shared("TutorialData")
	local WoodData = t.shared("WoodData")
	local HudRules = t.load("StarterPlayer/StarterPlayerScripts/HudRules")

	-- The source game's own names (places, shops, keepers, items, woods,
	-- lines) that ours replace (V2_PLAN §2g). Lower case, matched as whole
	-- words. Our "Steel/Hardened/Silver Axe" are ours by design (§2c).
	local BANNED = {
		"lt2",
		"lumberland",
		"lumber tycoon",
		"wood r us",
		"fancy furnishings",
		"boxed cars",
		"bob's shack",
		"link's logic",
		"land store",
		"fine arts shop",
		"shabby sawmill",
		"fair sawmill",
		"sawmax",
		"hatchet",
		"plain axe",
		"fire axe",
		"bird axe",
		"amber axe",
		"many axe",
		"rukiryaxe",
		"beesaxe",
		"phantom wood",
		"spook",
		"sinister",
		"koa",
		"fir",
		"cavecrawler",
		"snow glow",
		"gold swampy",
		"dynamite",
		"strange man",
		"defaultio",
		"thom",
		"corey",
		"ruhven",
		"hot pink",
		"dropoff",
		"drop-off",
		"what are you trying to pull",
	}

	local function banned(text)
		local lower = string.lower(text)
		for _, name in ipairs(BANNED) do
			local pattern = "%f[%w]" .. string.gsub(name, "[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0") .. "%f[%W]"
			if string.find(lower, pattern) then
				return name
			end
		end
		return nil
	end

	local function texts()
		local out = {}
		local function add(where, text)
			table.insert(out, { where = where, text = text })
		end
		for _, step in ipairs(TutorialData.StepsV2) do
			add("tutorial " .. step.id .. " objective", TutorialData.ObjectiveText(step, 0))
			for _, device in ipairs(HintLogic.Devices) do
				add("tutorial " .. step.id .. " (" .. device .. ")", HintLogic.Expand(step.murph, device))
			end
		end
		add("farewell", TutorialData.Farewell)
		for _, device in ipairs(HintLogic.Devices) do
			for _, context in ipairs(HintLogic.ContextsV2) do
				add("hint " .. context .. " (" .. device .. ")", HintLogic.PickV2(device, context))
			end
		end
		for tier = 1, #DailyData.TiersV2 do
			for day = 1, 40 do
				for _, goal in ipairs(DailyData.Roll(9001, day, tier, 2)) do
					add("daily " .. goal.kind, DailyData.GoalText(goal) .. " " .. DailyData.ProgressText(goal))
				end
			end
		end
		for _, wood in ipairs(WoodData.All()) do
			add("guide " .. wood.id, FieldGuide.FactsV2(wood))
			add("tooltip " .. wood.id, HudRules.WoodTooltip(wood.id, "log", 26.3, 39.6))
		end
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			add("shop " .. axe.id, ShopLogic.AxeDetail(axe, 2))
		end
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			add("shop " .. truck.id, ShopLogic.TruckDetailV2(truck))
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			add("shop " .. trailer.id, ShopLogic.TrailerDetailV2(trailer))
		end
		add("bed chip", HudRules.BedChip(41.2, 96, 61.8, false).text)
		return out
	end

	t.test("the ban list catches what it should, and not our own words", function()
		t.eq(banned("Sell it at the Wood R Us counter"), "wood r us")
		t.eq(banned("an old HATCHET"), "hatchet")
		t.eq(banned("first fir"), "fir")
		t.eq(banned("the first tree"), nil, "fir inside a word is fine")
		t.eq(banned("Steel Axe · Hardened Axe · Gloamwood · Frostwood"), nil, "ours")
		t.eq(banned("Tink's Tool Shed · Millie's mill · Hearth & Home"), nil)
	end)

	t.test("no v2 text carries the source game's names", function()
		local all = texts()
		t.ok(#all > 100, "every module contributed")
		for _, entry in ipairs(all) do
			t.ok(type(entry.text) == "string" and #entry.text > 0, entry.where .. ": empty")
			local name = banned(entry.text)
			t.ok(name == nil, string.format("%s says %q: %s", entry.where, tostring(name), entry.text))
		end
	end)

	t.test("no v2 text has a token, a nan or an inf left in it", function()
		for _, entry in ipairs(texts()) do
			t.ok(not HintLogic.HasToken(entry.text), entry.where .. ": " .. entry.text)
			local lower = string.lower(entry.text)
			t.ok(
				not string.find(lower, "%f[%a]nan%f[%A]") and not string.find(lower, "%f[%a]inf%f[%A]"),
				entry.where .. ": " .. entry.text
			)
			t.ok(not string.find(entry.text, "%d%.%d%d%d"), entry.where .. ": a long decimal in " .. entry.text)
		end
	end)

	t.test("the v2 modules' source (comments too) is free of them", function()
		local fs = require("@lune/fs")
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/TutorialData.luau",
			"src/ReplicatedStorage/Shared/HintLogic.luau",
			"src/ReplicatedStorage/Shared/DailyData.luau",
			"src/ReplicatedStorage/Shared/FieldGuide.luau",
			"src/ReplicatedStorage/Shared/ShopLogic.luau",
			"src/StarterPlayer/StarterPlayerScripts/HudRules.luau",
		}) do
			local name = banned(fs.readFile(path))
			t.ok(name == nil, path .. " mentions " .. tostring(name))
		end
	end)
end
