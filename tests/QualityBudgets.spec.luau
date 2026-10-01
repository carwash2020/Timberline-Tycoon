--!nocheck
-- QualityBudgets (PLAY-05): the two tiers' numbers and the rule that picks
-- a tier. "high" must be today's look exactly (the constants the client
-- modules held before PLAY-05, and WindSway's PLAY-04 budget), and "low"
-- the phone budgets HANDOFF.md PLAY-05 asks for. A change to either is on
-- purpose: update this spec with it.
local fs = require("@lune/fs")

return function(t)
	local QualityBudgets = t.shared("QualityBudgets")
	local EnvironmentData = t.shared("EnvironmentData")

	local KEYS = {
		"Tier",
		"MaxDecor",
		"DecorLoadRadius",
		"MaxCritters",
		"SwayParts",
		"SwayTrees",
		"SwayRange",
		"WeatherRate",
		"SunRays",
		"DepthOfField",
		"Bloom",
		"TownFxNear",
	}

	t.test("high is today's look", function()
		t.eq(QualityBudgets.High, {
			Tier = "high",
			MaxDecor = 420, -- AmbientLife MAX_DECOR
			DecorLoadRadius = 200, -- AmbientLife LOAD_RADIUS
			MaxCritters = 16, -- EnvironmentData.MaxCritters
			SwayParts = 900, -- WindSway (PLAY-04)
			SwayTrees = 32,
			SwayRange = 120,
			WeatherRate = 1, -- every emitter at its full rate
			SunRays = 1, -- EnvironmentData's post effects, untouched
			DepthOfField = 1,
			Bloom = 1,
			TownFxNear = 260, -- TownFX NEAR
		})
		t.eq(QualityBudgets.High.MaxCritters, EnvironmentData.MaxCritters, "the same cap the critter plan was made for")
	end)

	t.test("low is the phone budget", function()
		t.eq(QualityBudgets.Low, {
			Tier = "low",
			MaxDecor = 160,
			DecorLoadRadius = 140,
			MaxCritters = 8,
			SwayParts = 400,
			SwayTrees = 16,
			SwayRange = 80,
			WeatherRate = 0.5,
			SunRays = 0,
			DepthOfField = 0,
			Bloom = 0.5,
			TownFxNear = 120,
		})
	end)

	t.test("both tiers have every key, low never asks for more than high, and neither can be changed", function()
		for _, budget in ipairs({ QualityBudgets.High, QualityBudgets.Low }) do
			local count = 0
			for _ in pairs(budget) do
				count += 1
			end
			t.eq(count, #KEYS, "no extra keys")
			for _, key in ipairs(KEYS) do
				t.ok(budget[key] ~= nil, key)
			end
			t.ok(table.isfrozen(budget), "frozen")
		end
		for _, key in ipairs(KEYS) do
			if key ~= "Tier" then
				t.ok(QualityBudgets.Low[key] <= QualityBudgets.High[key], key)
				t.ok(QualityBudgets.Low[key] >= 0, key)
			end
		end
		-- A frame's sway budget fits the dearest tree (a frostwood's 96 canopy
		-- parts), or WindSway would never move it.
		t.ok(QualityBudgets.Low.SwayParts >= 96)
		t.fails(function()
			QualityBudgets.High.MaxDecor = 1
		end)
	end)

	t.test("For: a tier's budget, high for anything else", function()
		t.eq(QualityBudgets.For("low"), QualityBudgets.Low)
		t.eq(QualityBudgets.For("high"), QualityBudgets.High)
		t.eq(QualityBudgets.For("medium"), QualityBudgets.High)
	end)

	t.test("TierFor: graphics quality 1-4 is low on any device, 5-10 high", function()
		for level = 1, 10 do
			local want = if level <= 4 then "low" else "high"
			t.eq(QualityBudgets.TierFor("QualityLevel" .. level, false), want, "desktop " .. level)
			t.eq(QualityBudgets.TierFor("QualityLevel" .. level, true), want, "phone " .. level)
		end
	end)

	t.test("TierFor: Automatic is low on a touch-only device and high elsewhere", function()
		t.eq(QualityBudgets.TierFor("Automatic", true), "low", "a phone")
		t.eq(QualityBudgets.TierFor("Automatic", false), "high", "a desktop, a laptop with touch, a console")
		t.eq(QualityBudgets.TierFor(nil, true), "low", "unreadable: as Automatic")
		t.eq(QualityBudgets.TierFor(nil, false), "high")
		t.eq(QualityBudgets.TierFor("QualityLevel", false), "high", "a name we don't know: as Automatic")
		t.eq(QualityBudgets.TierFor("QualityLevel3x", true), "low")
	end)

	t.test("TierFor reads every Enum.SavedQualitySetting name", function()
		for _, item in ipairs(t.roblox.Enum.SavedQualitySetting:GetEnumItems()) do
			local tier = QualityBudgets.TierFor(item.Name, false)
			if item.Name == "Automatic" then
				t.eq(tier, "high")
			else
				t.eq(tier, if item.Value <= 4 then "low" else "high", item.Name)
			end
		end
	end)

	t.test("every budget is read by the client module it's for, and the old constants are gone", function()
		local SPS = "src/StarterPlayer/StarterPlayerScripts/"
		local readers = {
			AmbientLife = { "MaxDecor", "DecorLoadRadius", "MaxCritters" },
			WindSway = { "SwayParts", "SwayTrees", "SwayRange" },
			WeatherController = { "WeatherRate" },
			LightingController = { "SunRays", "DepthOfField", "Bloom" },
			TownFX = { "TownFxNear" },
		}
		local gone = {
			AmbientLife = { "local MAX_DECOR", "local LOAD_RADIUS", "EnvironmentData%.MaxCritters" },
			WindSway = { "local RANGE", "local MAX_TREES", "local PART_BUDGET" },
			TownFX = { "local NEAR" },
		}
		local covered = {}
		for module, keys in pairs(readers) do
			local source = fs.readFile(SPS .. module .. ".luau")
			t.ok(string.find(source, "require(script.Parent.Quality)", 1, true), module .. " requires Quality")
			for _, key in ipairs(keys) do
				t.ok(string.find(source, "%." .. key .. "%f[%W]") ~= nil, module .. " reads " .. key)
				covered[key] = true
			end
			for _, pattern in ipairs(gone[module] or {}) do
				local code = string.gsub(source, "%-%-[^\n]*", "") -- comments may still name them
				t.eq(string.find(code, pattern), nil, module .. " still has " .. pattern)
			end
		end
		for _, key in ipairs(KEYS) do
			if key ~= "Tier" then
				t.ok(covered[key], key .. " has a reader")
			end
		end
	end)
end
