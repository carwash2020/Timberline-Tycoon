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
	local BiomeData = t.shared("BiomeData")

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
			MaxDecor = 148, -- the whole AmbientLife folder holds 160 (next test)
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

	-- PLAY-05's acceptance counts the whole workspace.AmbientLife folder on
	-- low ("160 models or fewer"), not only the decoration. AmbientLife puts
	-- exactly these into it: decoration (at most MaxDecor), critter bodies
	-- and firefly clouds (one model per MaxCritters point), the Skyroot's 2
	-- mote clouds (made once, always there) and fish splashes (each lives
	-- 1.2 s and a leap takes 0.95 s, with at most one fish wanted, so at most
	-- 2 at once). This pins the sum and what it assumes about AmbientLife:
	-- if AmbientLife starts putting something new in its folder, recount.
	t.test("low: the whole AmbientLife folder holds 160 models or fewer", function()
		local Low = QualityBudgets.Low
		local MOTES, SPLASHES = 2, 2
		t.ok(
			Low.MaxDecor + Low.MaxCritters + MOTES + SPLASHES <= 160,
			"decoration " .. Low.MaxDecor .. " + critters " .. Low.MaxCritters .. " + motes + splashes"
		)

		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/AmbientLife.luau")
		local code = string.gsub(source, "%-%-[^\n]*", "")
		local function count(pattern: string): number
			local n = 0
			for _ in string.gmatch(code, pattern) do
				n += 1
			end
			return n
		end
		-- Everything AmbientLife parents to its folder: decoration in loadCell;
		-- acquireBody (every critter body), the firefly cloud, the splash, a
		-- leaping fish (a body acquireBody already counted) and the 2 motes.
		t.eq(count("%.Parent = parent%f[%W]"), 1, "decoration is parented in one place")
		t.eq(count("%.Parent = root%(%)"), 6, "a new kind of model in the AmbientLife folder: recount Low.MaxDecor")
		t.eq(count("CritterArt%.Motes%("), MOTES, "the Skyroot's mote clouds")
		-- One model per cost point: a Flock's cost is its bird count.
		t.eq(tonumber(string.match(code, "local FLOCK_SIZE = (%d+)")), EnvironmentData.CritterCost.Flock)
		for kind, cost in pairs(EnvironmentData.CritterCost) do
			t.ok(cost >= 1, kind .. " costs at least its one model")
		end
		-- Splashes: two per leap (in and out), each living 1.2 s, and a fish
		-- waits at least 4 s after landing before it leaps again, so one
		-- leap's splashes are gone before the next leap's.
		t.eq(count("splash%("), 3, "the splash function and a fish leap's two calls")
		t.ok(string.find(code, "task.delay(1.2, function()", 1, true) ~= nil, "a splash lives 1.2 s")
		t.ok(string.find(code, "d.nextJump = t + 4 + ", 1, true) ~= nil, "4 s or more between leaps")
		local biomeIds = { "" }
		for _, biome in ipairs(BiomeData.All()) do
			table.insert(biomeIds, biome.id)
		end
		local fishPlans = 0
		for _, weather in ipairs({ "Clear", "Cloudy", "Rain", "Storm", "Fog", "Blizzard", "Ashfall" }) do
			for _, biomeId in ipairs(biomeIds) do
				for _, daylight in ipairs({ 0, 0.5, 1 }) do
					for _, intensity in ipairs({ 0.2, 1 }) do
						for _, vitality in ipairs({ 0, 50, 100 }) do
							local wants = EnvironmentData.CritterPlan({
								biomeId = biomeId,
								daylight = daylight,
								weather = weather,
								intensity = intensity,
								vitality = vitality,
								nearPond = true,
								nearWater = true,
							})
							for _, w in ipairs(wants) do
								if w.kind == "Fish" then
									t.ok(w.count <= 1, "one fish at a time")
									fishPlans += 1
								end
							end
						end
					end
				end
			end
		end
		t.ok(fishPlans > 0, "the sweep reached the fish")
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
