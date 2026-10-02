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
		"DecorUnloadRadius",
		"MaxCritters",
		"SwayParts",
		"SwayTrees",
		"SwayRange",
		"WeatherRate",
		"SunRays",
		"DepthOfField",
		"Bloom",
		"TownFxNear",
		"FillerNear",
		"FillerFar",
		"FillerBuildMs",
		"TuftNear",
		"ChipCount",
		"LeafPool",
		"LeafShadows",
	}

	t.test("high is today's look", function()
		t.eq(QualityBudgets.High, {
			Tier = "high",
			MaxDecor = 560, -- AmbientLife MAX_DECOR was 420; +140 for the ground cover (DecorCover.spec)
			DecorLoadRadius = 200, -- AmbientLife LOAD_RADIUS
			DecorUnloadRadius = 260, -- AmbientLife UNLOAD_RADIUS
			MaxCritters = 16, -- EnvironmentData.MaxCritters
			SwayParts = 900, -- WindSway (PLAY-04)
			SwayTrees = 32,
			SwayRange = 120,
			WeatherRate = 1, -- every emitter at its full rate
			SunRays = 1, -- EnvironmentData's post effects, untouched
			DepthOfField = 1,
			Bloom = 1,
			TownFxNear = 260, -- TownFX NEAR
			-- ForestFiller (FOR-02, new): trees to 480 studs, stand-ins to 1,000
			-- (inside StreamingTargetRadius 1024), 2 ms of building a frame.
			FillerNear = 480,
			FillerFar = 1000,
			FillerBuildMs = 2,
			TuftNear = 150, -- grass tufts (FOR-04, new)
			-- WoodFX (the v2 loop, V2_PLAN.md §16, new): pooled chips and leaves.
			ChipCount = 48,
			LeafPool = 64,
			LeafShadows = true,
		})
		t.eq(QualityBudgets.High.MaxCritters, EnvironmentData.MaxCritters, "the same cap the critter plan was made for")
	end)

	t.test("low is the phone budget", function()
		t.eq(QualityBudgets.Low, {
			Tier = "low",
			MaxDecor = 148, -- the whole AmbientLife folder holds 160 (next test)
			DecorLoadRadius = 110, -- see "low keeps the ground beside you dressed"
			DecorUnloadRadius = 130,
			MaxCritters = 8,
			SwayParts = 400,
			SwayTrees = 16,
			SwayRange = 80,
			WeatherRate = 0.5,
			SunRays = 0,
			DepthOfField = 0,
			Bloom = 0.5,
			TownFxNear = 120,
			FillerNear = 340, -- the forest's edges round the spawn stay trees
			FillerFar = 640,
			FillerBuildMs = 1.2,
			TuftNear = 90,
			-- WoodFX (V2_PLAN.md §16): half the chips and leaves, no leaf shadows.
			ChipCount = 24,
			LeafPool = 32,
			LeafShadows = false,
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

	-- AmbientLife's decoration cells, played out along walks and drives. Its
	-- rules (Ground decoration, AmbientLife.luau): every SCAN_EVERY (0.4 s)
	-- it queues the missing cells within DecorLoadRadius, nearest first, and
	-- unloads the cells past DecorUnloadRadius; each frame it loads up to
	-- CELLS_PER_FRAME (2) of them, a spot at a time, skipping spots within
	-- TREE_CLEARANCE (4) of a tree, until MaxDecor models are live. A cell
	-- cut short by the cap still counts as loaded, and a loaded cell is never
	-- swapped for a nearer one. So if the cells inside DecorUnloadRadius hold
	-- far more than MaxDecor, the cap fills with cells behind you and the
	-- ground beside you stays bare (on low, with high's 260-stud unload
	-- radius, over half of it in the Hills). This measures, from 20 s on,
	-- the share of the spots within 80 studs that have no model.
	local function bareNearby(budget, path, seconds: number): number
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local CELL = EnvironmentData.DecorCell
		local treeBins = {}
		for _, tree in ipairs(WorldPlan.Trees()) do
			local p = tree.position
			local key = (p.X // 16) .. "," .. (p.Z // 16)
			treeBins[key] = treeBins[key] or {}
			table.insert(treeBins[key], p)
		end
		local function nearTree(x: number, z: number): boolean
			for dx = -1, 1 do
				for dz = -1, 1 do
					for _, p in ipairs(treeBins[(x // 16 + dx) .. "," .. (z // 16 + dz)] or {}) do
						if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < 16 then
							return true
						end
					end
				end
			end
			return false
		end
		local spotsOf = {}
		local function spots(cx: number, cz: number)
			local key = cx .. "," .. cz
			if not spotsOf[key] then
				local kept = {}
				for _, spot in
					ipairs(EnvironmentData.DecorSpots(cx, cz, function()
						return EnvironmentData.DefaultVitality
					end))
				do
					if not nearTree(spot.x, spot.z) then
						table.insert(kept, spot)
					end
				end
				spotsOf[key] = kept
			end
			return spotsOf[key]
		end
		local function centreDistance(cx: number, cz: number, x: number, z: number): number
			return math.sqrt(((cx + 0.5) * CELL - x) ^ 2 + ((cz + 0.5) * CELL - z) ^ 2)
		end

		local cells, live, queue = {}, 0, {}
		local sinceScan, bare, samples = math.huge, 0, 0
		local dt = 1 / 60
		for frame = 1, math.floor(seconds / dt) do
			local now = frame * dt
			local x, z = path(now)
			sinceScan += dt
			if sinceScan >= 0.4 then
				sinceScan = 0
				local reach = math.ceil(budget.DecorLoadRadius / CELL) + 1
				local wanted = {}
				for cx = x // CELL - reach, x // CELL + reach do
					for cz = z // CELL - reach, z // CELL + reach do
						local d = centreDistance(cx, cz, x, z)
						if d <= budget.DecorLoadRadius and not cells[cx .. "," .. cz] then
							table.insert(wanted, { cx = cx, cz = cz, d = d })
						end
					end
				end
				table.sort(wanted, function(a, b)
					return a.d < b.d
				end)
				queue = wanted
				for key, cell in pairs(cells) do
					if centreDistance(cell.cx, cell.cz, x, z) > budget.DecorUnloadRadius then
						live -= cell.n
						cells[key] = nil
					end
				end
				if now >= 20 then
					local missing, total = 0, 0
					for cx = (x - 80) // CELL, (x + 80) // CELL do
						for cz = (z - 80) // CELL, (z + 80) // CELL do
							local cell = cells[cx .. "," .. cz]
							for i, spot in ipairs(spots(cx, cz)) do
								if (spot.x - x) ^ 2 + (spot.z - z) ^ 2 <= 80 * 80 then
									total += 1
									if not cell or i > cell.n then
										missing += 1
									end
								end
							end
						end
					end
					if total > 0 then
						bare += missing / total
						samples += 1
					end
				end
			end
			for _ = 1, 2 do
				local q = table.remove(queue, 1)
				if not q or live >= budget.MaxDecor then
					break
				end
				local key = q.cx .. "," .. q.cz
				if not cells[key] then
					local n = 0
					for _ in ipairs(spots(q.cx, q.cz)) do
						if live >= budget.MaxDecor then
							break
						end
						n += 1
						live += 1
					end
					cells[key] = { cx = q.cx, cz = q.cz, n = n }
				end
			end
			t.ok(live <= budget.MaxDecor)
		end
		t.ok(samples > 0, "measured")
		return bare / samples
	end

	-- Straight lines at `speed` studs/s, then pottering about the last point
	-- (20 studs either way, as when chopping); or round a circle.
	local function route(points: { { number } }, speed: number)
		return function(now: number): (number, number)
			local s = now * speed
			for i = 1, #points - 1 do
				local a, b = points[i], points[i + 1]
				local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
				if s <= length then
					return a[1] + (b[1] - a[1]) * s / length, a[2] + (b[2] - a[2]) * s / length
				end
				s -= length
			end
			local last = points[#points]
			return last[1] + 20 * math.sin(s / 40), last[2] + 20 * math.cos(s / 55)
		end
	end
	local function loop(biomeId: string, radius: number)
		local area = assert(assert(BiomeData.Get(biomeId)).area)
		return function(now: number): (number, number)
			local a = now * 16 / radius -- walking pace
			return area.x + radius * math.cos(a), area.z + radius * math.sin(a)
		end
	end
	local function centre(biomeId: string): { number }
		local area = assert(assert(BiomeData.Get(biomeId)).area)
		return { area.x, area.z }
	end

	-- At the default vitality (Healthy: every grove tonight). Today's high
	-- leaves 0-5% bare on these walks; low with high's unload radius left
	-- 30-55% bare in the Hills and the Grove.
	t.test("low keeps the ground beside you dressed", function()
		local walks = {
			{ "drive from the spawn to the Hills, then chop there", route({ { 0, 40 }, centre("hills") }, 40), 150 },
			{ "walk a loop through the Hills", loop("hills", 100), 120 },
			{ "walk a loop through the Phantom Grove", loop("grove", 70), 90 },
			{ "drive into the Snowfields, then chop there", route({ { 0, 700 }, centre("snow") }, 40), 120 },
			{ "walk a loop through the Starter Forest", loop("starter", 60), 90 },
		}
		for _, walk in ipairs(walks) do
			local name, path, seconds = walk[1], walk[2], walk[3]
			local high = bareNearby(QualityBudgets.High, path, seconds)
			local low = bareNearby(QualityBudgets.Low, path, seconds)
			t.ok(
				low <= 0.1,
				string.format(
					"%s: %.1f%% of the decoration within 80 studs missing on low (%.1f%% on high); "
						.. "retune QualityBudgets.Low MaxDecor, DecorLoadRadius and DecorUnloadRadius together",
					name,
					low * 100,
					high * 100
				)
			)
		end
		-- What this guards against: low's cap with high's unload radius.
		local stale = table.clone(QualityBudgets.Low)
		stale.DecorUnloadRadius = QualityBudgets.High.DecorUnloadRadius
		local bare = bareNearby(stale, walks[1][2], walks[1][3])
		t.ok(bare > 0.3, string.format("unload past 260 on low: %.1f%% bare", bare * 100))
	end)

	t.test("decoration cells unload a little past where they load", function()
		for _, budget in ipairs({ QualityBudgets.High, QualityBudgets.Low }) do
			-- An edge cell must not load and unload as you sway while chopping.
			t.ok(budget.DecorUnloadRadius >= budget.DecorLoadRadius + 20, budget.Tier)
		end
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
			if key ~= "Tier" and type(QualityBudgets.High[key]) == "number" then
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
			AmbientLife = { "MaxDecor", "DecorLoadRadius", "DecorUnloadRadius", "MaxCritters" },
			WindSway = { "SwayParts", "SwayTrees", "SwayRange" },
			WeatherController = { "WeatherRate" },
			LightingController = { "SunRays", "DepthOfField", "Bloom" },
			TownFX = { "TownFxNear" },
			ForestFiller = { "FillerNear", "FillerFar", "FillerBuildMs", "TuftNear" },
			WoodFX = { "ChipCount", "LeafPool", "LeafShadows" }, -- the v2 loop (M1.3)
		}
		local gone = {
			AmbientLife = {
				"local MAX_DECOR",
				"local LOAD_RADIUS",
				"local UNLOAD_RADIUS",
				"EnvironmentData%.MaxCritters",
			},
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
