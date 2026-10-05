--!nocheck
-- Economy calculator for Timberline Tycoon's v1 loop (CoreLoop 1: trees
-- fall into counted logs carried in your hands). Kept until M1.10 for a
-- rollback; the live loop's model is tools/economy (ECONOMY.md).
--
-- Reads the real balance tables (WoodData, ItemCatalog, BiomeData, GameConfig), models
-- how fast a player earns with each gear setup, simulates a player climbing
-- the whole progression, and checks the results against the targets in
-- GAME_DESIGN §2, §4 and §11. Writes the report to ECONOMY_V1.md.
--
-- Run from the repo root:   lune run tools/economy1
-- Check the committed report is current (CI does):   lune run tools/economy1 --check
--
-- It's a model, not a measurement. It assumes trees are always available
-- and nobody competes for them. EFFICIENCY scales the ideal "perfect player"
-- numbers down to a real one. Calibrate it with a Studio playtest: play the
-- starter loop for ~10 minutes and the Output window prints a line like
--   lune run tools/economy1 --calibrate 612 birch=16 oak=24
-- Run it here: it measures you against the ideal model, saves EFFICIENCY
-- to tools/calibration_v1.json (read by every later run) and rewrites the report.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local luau = require("@lune/luau")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/economy1")

-- The game's own data modules, loaded outside Roblox (tools/loader.luau).
local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local function loadModule(name: string)
	return modules:shared(name)
end
local WoodData = loadModule("WoodData")
local ItemCatalog = loadModule("ItemCatalog")
local GameConfig = loadModule("GameConfig")
local BiomeData = loadModule("BiomeData")
local TutorialData = loadModule("TutorialData")
local DailyData = loadModule("DailyData")
local ForestData = loadModule("ForestData")
local ForestLogic = loadModule("ForestLogic")

---------------------------------------------------------------------------
-- Assumptions (edit these, then re-run)
---------------------------------------------------------------------------
-- Real player vs the ideal model: measured by --calibrate (see top), or a
-- guess until then.
local CALIBRATION_FILE = "tools/calibration_v1.json"
local calibration = if fs.isFile(CALIBRATION_FILE) then serde.decode("json", fs.readFile(CALIBRATION_FILE)) else nil
local EFFICIENCY = if calibration then calibration.efficiency else 0.5

local A = {
	walkSpeed = 16, -- studs/s, Roblox default WalkSpeed
	boatSpeed = 26, -- studs/s, no boats built yet
	fellTime = 0.75, -- s, fall animation + logs appearing
	betweenTrees = 15, -- studs walked to the next tree
	treeToTruck = 20, -- studs from the felled tree to the parked truck
	promptTime = 0.5, -- s per Pick up / Load press
	driveOverhead = 8, -- s per round trip: get in, park, get out
	sellTime = 2, -- s
	skyBinWalk = 5, -- s, gondola station to the Sky Bin and selling it
	shardMinutes = 1, -- min to find and mine one Sky Shard (forging cost)
	sessionMinutes = 45, -- one "session" for the "2-4 sessions" target (§4)
	groveTier = "Healthy", -- the grove's vitality tier for the figure average (ForestData)
}

-- Where to go, how to haul, required gear and slowdowns all come from
-- BiomeData (src/ReplicatedStorage/Shared/BiomeData.luau).
local function biome(id: string)
	return assert(BiomeData.Get(id), "WoodData uses unknown biome " .. id)
end

-- Players chase these until they own them all (V1's end goals).
local GOALS = { InfernoAxe = true, LoggingRig = true, StarfallAxe = true }

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------
local function sortedByPrice(tbl)
	local list = {}
	for _, item in pairs(tbl) do
		table.insert(list, item)
	end
	table.sort(list, function(a, b)
		return a.priceCash < b.priceCash
	end)
	return list
end

local AXES = ItemCatalog.AxeLadder() -- sold in order, cheapest first
local TRUCKS = sortedByPrice(ItemCatalog.Trucks)
local TRAILERS = sortedByPrice(ItemCatalog.Trailers)
local BOATS = sortedByPrice(ItemCatalog.Boats)
local GEAR = sortedByPrice(ItemCatalog.Gear)
-- Ferry Island is not on the buying path (W2 owns the biome). Leaving
-- lanternwood out holds the published headlines.
local function economyWoods()
	local list = {}
	for _, wood in ipairs(WoodData.All()) do
		if wood.biome ~= WoodData.LanternBiome then
			table.insert(list, wood)
		end
	end
	return list
end
local WOODS = economyWoods()

-- math.huge when the axe can't cut the wood (hardness >= damage).
local function hitsToFell(axe, wood): number
	local damage = ItemCatalog.AxeDamage(axe, wood)
	return if damage > 0 then math.ceil(wood.treeHP / damage) else math.huge
end

local function best(list, owned, score)
	local top, topScore = nil, -math.huge
	for _, item in ipairs(list) do
		if owned[item.id] then
			local s = score(item)
			if s > topScore then
				top, topScore = item, s
			end
		end
	end
	return top
end

-- What a player owns can carry for a biome: cargo size, travel time per
-- round trip, walk from tree to vehicle/chute, cost per trip, and a label.
local function haulFor(b, owned)
	if b.access == "gondola" then
		local g = b.gondola
		return b.skyBinCapacity, 2 * g.rideSec + A.skyBinWalk, b.chuteWalkStuds, 2 * g.fee, "Cloud Chute + Sky Bin"
	elseif b.access == "boat" then
		local boat = best(BOATS, owned, function(x)
			return x.hullCapacity
		end)
		if not boat then
			return 0, 0, 0, 0, ""
		end
		return boat.hullCapacity, 2 * b.haulStuds / A.boatSpeed + A.driveOverhead, A.treeToTruck, 0, boat.displayName
	end
	local truck = best(TRUCKS, owned, function(x)
		return x.bedCapacity
	end)
	local trailer = best(TRAILERS, owned, function(x)
		return x.extraCapacity
	end)
	if not truck then
		return 0, 0, 0, 0, ""
	end
	local cargo = truck.bedCapacity + (if trailer then trailer.extraCapacity else 0)
	local label = truck.displayName .. (if trailer then " + " .. trailer.displayName else "")
	-- Hauls at the truck's top speed (ItemCatalog); a trailer doesn't slow it (yet).
	return cargo, 2 * b.haulStuds / truck.topSpeed + A.driveOverhead, A.treeToTruck, 0, label
end

-- The Living Forest's Hidden Grain: some trees hide a figure that sells
-- for more (GAME_DESIGN §16). On average, at a Healthy grove, that adds
-- ForestLogic.FigureBonus to every log (about 6%); storms, Elders, planted
-- trees and blooms are events on top, left out.
local function figureFactor(wood): number
	return 1 + ForestLogic.FigureBonus(wood.id, A.groveTier, false, false)
end

-- One full load: chop enough trees to fill the cargo plus both hands,
-- carry logs to the vehicle (or chute) two at a time, haul, sell.
-- Returns seconds, cash (after trip fees), logs for a perfect player, or
-- nil if the player can't work this wood yet.
local function loadCycle(axe, wood, owned)
	local b = biome(wood.biome)
	local cargo, haulSecs, carryStuds, fee = haulFor(b, owned)
	if cargo <= 0 or ItemCatalog.AxeDamage(axe, wood) <= 0 then
		return nil
	end
	local slow = if b.slowdown and not owned[b.slowdown.removedBy] then 1 / (1 - b.slowdown.amount) else 1
	local hits = hitsToFell(axe, wood)
	local perTree = ((hits - 1) * GameConfig.SwingCooldown + A.fellTime + A.betweenTrees / A.walkSpeed) * slow
	local logs = cargo + GameConfig.HandCapacity
	local chop = (logs / wood.logsPerTree) * perTree
	local trips = math.ceil(cargo / GameConfig.HandCapacity)
	local carry = trips * (2 * carryStuds / A.walkSpeed) * slow + (logs + trips) * A.promptTime
	return chop + carry + haulSecs + A.sellTime, logs * wood.pricePerLog * figureFactor(wood) - fee, logs
end

-- Best cash per hour for a set of owned items (perfect player), optionally
-- limited to some biomes. Night-only biomes are left out.
-- Returns $/hr, wood, axe, haul description.
local function bestRate(owned, biomes: { [string]: boolean }?)
	local topRate, topWood, topAxe, topHaul = 0, nil, nil, ""
	for _, wood in ipairs(WOODS) do
		local b = biome(wood.biome)
		local allowed = if biomes then biomes[wood.biome] == true else true
		if allowed and not b.nightOnly and (b.requiresGear == nil or owned[b.requiresGear]) then
			local axe = best(AXES, owned, function(a)
				return ItemCatalog.AxeDamage(a, wood)
			end)
			local secs, cash = nil, 0
			if axe then
				secs, cash = loadCycle(axe, wood, owned)
			end
			if secs then
				local rate = cash / secs * 3600
				if rate > topRate then
					local _, _, _, _, label = haulFor(b, owned)
					topRate, topWood, topAxe, topHaul = rate, wood, axe, label
				end
			end
		end
	end
	return topRate, topWood, topAxe, topHaul
end

-- What an item really costs: its price, or for a forged axe the cash plus
-- the logs and materials given up (at their sell value).
local function itemPrice(item): number
	local recipe = item.forge
	if not recipe then
		return item.priceCash
	end
	local total = recipe.cash
	for woodId, count in pairs(recipe.logs) do
		total += count * WoodData.Get(woodId).pricePerLog
	end
	for materialId, count in pairs(recipe.materials) do
		total += count * ItemCatalog.Materials[materialId].sellPrice
	end
	return total
end

-- First sale for a brand-new player: walk to the truck, drive to the
-- forest, fell one oak, load its logs, drive to the mill, sell.
local function firstSaleSeconds(): number
	local oak = WoodData.Get("oak")
	local rusty = ItemCatalog.GetAxe("RustyAxe")
	local hits = hitsToFell(rusty, oak)
	local chop = (hits - 1) * GameConfig.SwingCooldown + A.fellTime
	local trips = math.ceil(oak.logsPerTree / GameConfig.HandCapacity)
	local carry = trips * (2 * A.treeToTruck / A.walkSpeed) + (oak.logsPerTree + trips) * A.promptTime
	local toTruck = 25 / A.walkSpeed -- spawn pad to the parking lot
	local speed = ItemCatalog.GetTruck("Rustbucket").topSpeed
	local drives = 80 / speed + biome("starter").haulStuds / speed + A.driveOverhead
	return toTruck + drives + chop + carry + A.sellTime
end

---------------------------------------------------------------------------
-- Progression: a player who always buys the upgrade that pays for itself
-- fastest, until they own every GOALS item (Inferno, Logging Rig, Starfall).
---------------------------------------------------------------------------
local function simulate(biomes: { [string]: boolean }?)
	local owned = { RustyAxe = true, Rustbucket = true }
	-- Murph's tutorial pays its reward before the first purchase (the
	-- Steel Axe), so it's counted as cash in hand from the start.
	local t, cash, earned = firstSaleSeconds() / EFFICIENCY, TutorialData.TotalReward(), 0
	local steps = {}
	local earnedAt15, t15done = nil, false
	local candidates = {}
	for _, list in ipairs({ AXES, TRUCKS, TRAILERS, BOATS, GEAR }) do
		for _, item in ipairs(list) do
			table.insert(candidates, item)
		end
	end

	local function advance(dt: number, rate: number)
		-- Record cumulative earnings at the 15-minute mark (§4 target).
		if not t15done and t + dt >= 15 * 60 then
			earnedAt15 = earned + math.max(0, 15 * 60 - t) * rate / 3600
			t15done = true
		end
		t += dt
		cash += dt * rate / 3600
		earned += dt * rate / 3600
	end

	for _ = 1, 40 do
		local done = true
		for id in pairs(GOALS) do
			done = done and owned[id] == true
		end
		if done then
			break
		end
		local rate = bestRate(owned, biomes) * EFFICIENCY
		-- Pick the purchase with the shortest payback (price / extra $ per hour).
		-- A purchase can be one item, or an item plus a piece of gear it's only
		-- worth having with (the Gold Axe + Heat Boots open the volcano), the
		-- way a real player plans ahead. Goals with no payback left (e.g. the
		-- Inferno Axe once a better wood isn't unlocked) are bought last.
		local pick, pickScore = nil, math.huge
		local function consider(bundle)
			local price = 0
			for _, item in ipairs(bundle) do
				-- A pass truck is not a cash buy. Forged axes are sold == false
				-- and still belong on this path, so this does not skip those.
				if item.robux == true or owned[item.id] or itemPrice(item) <= 0 then
					return
				end
				price += itemPrice(item)
			end
			for _, item in ipairs(bundle) do
				owned[item.id] = true
			end
			local newRate = bestRate(owned, biomes) * EFFICIENCY
			for _, item in ipairs(bundle) do
				owned[item.id] = nil
			end
			local gain = newRate - rate
			local main = bundle[#bundle]
			local isGoal = GOALS[main.id] == true
			local score = if gain > 0
				then price / gain
				else (if isGoal and #bundle == 1 then 1e12 + price else math.huge)
			if score < pickScore then
				pick, pickScore = bundle, score
			end
		end
		for _, item in ipairs(candidates) do
			-- Axes are sold in order: the shop only offers the next tier.
			local axeIndex = table.find(AXES, item)
			if axeIndex and axeIndex > 1 and not owned[AXES[axeIndex - 1].id] then
				continue
			end
			consider({ item })
			for _, gear in ipairs(GEAR) do
				if gear ~= item then
					consider({ gear, item })
				end
			end
		end
		if not pick or (biomes and pickScore >= 1e12) then
			break -- nothing left that helps (in a limited world, don't buy goals for nothing)
		end
		for _, item in ipairs(pick) do
			local before, nowWood = bestRate(owned, biomes)
			before *= EFFICIENCY
			local price = itemPrice(item)
			local wait = math.max(0, price - cash) / before * 3600
			if item.forge then
				-- Mining the Sky Shards takes time on top of the cash and logs.
				for _, count in pairs(item.forge.materials) do
					wait += count * A.shardMinutes * 60
				end
			end
			advance(wait, before)
			cash -= price
			owned[item.id] = true
			table.insert(steps, {
				item = item,
				saving = wait,
				total = t,
				before = before,
				after = bestRate(owned, biomes) * EFFICIENCY,
				wood = nowWood,
			})
		end
	end
	if not t15done then
		local rate = bestRate(owned, biomes) * EFFICIENCY
		earnedAt15 = earned + math.max(0, 15 * 60 - t) * rate / 3600
	end
	return steps, earnedAt15
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function money(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return "$" .. s .. out
end

local function duration(seconds: number): string
	if seconds < 90 then
		return string.format("%.0f s", seconds)
	elseif seconds < 90 * 60 then
		return string.format("%.0f min", seconds / 60)
	end
	return string.format("%.1f h", seconds / 3600)
end

-- "on target", or how far off, with a ±25% band (GAME_DESIGN §14.8).
local function verdict(value: number, lo: number, hi: number, fasterIsHigher: boolean): string
	if value >= lo * 0.75 and value <= hi * 1.25 then
		return "✅ on target"
	end
	local ratio = if value > hi then value / hi else lo / value
	local tooFast = (value > hi) == fasterIsHigher
	return string.format("⚠️ %.1f× too %s", ratio, if tooFast then "fast" else "slow")
end

local function setupRate(axeId: string, truckId: string, woodIds: { string }, extra: { string }?)
	local owned = { [axeId] = true, [truckId] = true }
	for _, id in ipairs(extra or {}) do
		owned[id] = true
	end
	local topRate, topWood = 0, nil
	for _, woodId in ipairs(woodIds) do
		local wood = WoodData.Get(woodId)
		local secs, cash = loadCycle(ItemCatalog.GetAxe(axeId), wood, owned)
		local rate = if secs then cash / secs * 3600 else 0
		if rate > topRate then
			topRate, topWood = rate, wood
		end
	end
	return topRate, topWood or WoodData.Get(woodIds[1])
end

-- --calibrate <seconds> <wood>=<logs> ...: how long a perfect player would
-- take to fell, haul and sell those logs with the starter kit, divided by
-- how long the playtester took (first chop to last sale).
if process.args[1] == "--calibrate" then
	local usage = "usage: lune run tools/economy1 --calibrate <seconds> <wood>=<logs> ..."
	local seconds = tonumber(process.args[2])
	assert(seconds and seconds > 0, usage)
	local owned = { RustyAxe = true, Rustbucket = true }
	local rusty = ItemCatalog.GetAxe("RustyAxe")
	local idealSeconds, logs, total = 0, {}, 0
	for i = 3, #process.args do
		local woodId, count = string.match(process.args[i], "^(%w+)=(%d+)$")
		local wood = if woodId then WoodData.Get(woodId) else nil
		assert(wood, "not a <wood>=<logs> pair: " .. process.args[i] .. "\n" .. usage)
		local secs, _, perLoad = loadCycle(rusty, wood, owned)
		assert(secs, "the Rusty Axe can't cut " .. woodId)
		idealSeconds += tonumber(count) * secs / perLoad
		logs[woodId] = tonumber(count)
		total += tonumber(count)
	end
	assert(total > 0, usage)
	local measured = idealSeconds / seconds
	if measured > 1 then
		print(
			string.format(
				"Warning: you beat the ideal model (%.2f). Its assumptions (walk distances, prompt times) are too slow; review them in tools/economy1.luau. Saving 1.0.",
				measured
			)
		)
		measured = 1
	end
	measured = math.floor(measured * 100 + 0.5) / 100
	print(string.format("EFFICIENCY %.2f -> %.2f (saved to %s)", EFFICIENCY, measured, CALIBRATION_FILE))
	calibration = { efficiency = measured, seconds = seconds, logs = logs, date = os.date("%Y-%m-%d") }
	fs.writeFile(CALIBRATION_FILE, serde.encode("json", calibration, true) .. "\n")
	EFFICIENCY = measured
end

local STARTER = { starter = true }
local steps = simulate() -- the whole world
local starterSteps, earnedAt15 = simulate(STARTER) -- a new player in the starter forest (all Phase 1 has)
local stepFor, starterStepFor = {}, {}
for _, s in ipairs(steps) do
	stepFor[s.item.id] = s
end
for _, s in ipairs(starterSteps) do
	starterStepFor[s.item.id] = s
end

local out = {}
local function line(s: string?)
	table.insert(out, s or "")
end

line("# Economy report")
line()
line(
	"_Generated by `lune run tools/economy1` from WoodData, ItemCatalog and GameConfig. Don't edit by hand: change the data or the assumptions in `tools/economy1.luau`, then re-run._"
)
line()
line(
	string.format(
		'**Model, not measurement.** Numbers assume trees are always available and nobody competes for them. "Real player" = the ideal model × EFFICIENCY (%.2f), %s.',
		EFFICIENCY,
		if calibration
			then string.format(
				"measured %s from a %d-min Studio playtest",
				calibration.date,
				math.floor(calibration.seconds / 60 + 0.5)
			)
			else "**a guess until a playtest calibrates it** (see below)"
	)
)
line()

-- Headline checks.
local firstSale = firstSaleSeconds() / EFFICIENCY
local early, earlyWood = setupRate("RustyAxe", "Rustbucket", { "oak", "birch" })
local mid, midWood = setupRate("SteelAxe", "Pickup", { "pine", "maple" })
local late, lateWood = setupRate("InfernoAxe", "LoggingRig", { "emberwood" }, { "HeatBoots" })
local finale = setupRate("StarfallAxe", "LoggingRig", { "lumenwood" }) -- V1 finale loop
local grind = setupRate("InfernoAxe", "LoggingRig", { "lumenwood" }) -- lumenwood before the Starfall
local steel = starterStepFor.SteelAxe
local inferno = stepFor.InfernoAxe
local rig = stepFor.LoggingRig
local starfall = stepFor.StarfallAxe
local sessionLo, sessionHi = 2 * A.sessionMinutes * 60, 4 * A.sessionMinutes * 60

-- Key findings, computed so they stay true after re-tuning.
do
	line("## Key findings")
	line()
	local rusty = { RustyAxe = true, Rustbucket = true, HeatBoots = true, InsulatedCoat = true, Rowboat = true }
	local anyRate, anyWood = bestRate(rusty)
	local startRate, startWood = bestRate(rusty, STARTER)
	local infernoOwned = table.clone(rusty)
	infernoOwned.InfernoAxe = true
	local infernoRate = bestRate(infernoOwned)
	local ratios = {
		early * EFFICIENCY / 800,
		mid * EFFICIENCY / 1500,
		late * EFFICIENCY / 20000,
	}
	table.sort(ratios)
	local median = ratios[2]
	if median > 1.25 then
		line(
			string.format(
				"- **Earning runs about %.1f× faster than the design's targets** (median of the early, mid and end-game checks below).",
				median
			)
		)
	elseif median < 0.75 then
		line(string.format("- **Earning runs about %.1f× slower than the design's targets.**", 1 / median))
	else
		line("- **Earning rates are within 25% of the design's targets.**")
	end
	line(
		string.format(
			"- **The Living Forest's figured wood adds %.1f%% to every wood** (the Hidden Grain's average at a Healthy grove, counted in every rate here; %.1f%% on Lumenwood). See \"The Living Forest\" below.",
			ForestLogic.FigureBonus("oak", A.groveTier, false, false) * 100,
			ForestLogic.FigureBonus("lumenwood", A.groveTier, false, false) * 100
		)
	)
	if anyWood and startWood and anyWood.biome ~= "starter" then
		line(
			string.format(
				"- **Rare wood doesn't need a better axe.** With the Rusty Axe and Rustbucket, %s earns %.1f× what %s does, so the best move from minute one is to skip the starter forest and axe upgrades.",
				anyWood.displayName:lower(),
				anyRate / startRate,
				startWood.displayName:lower()
			)
		)
	else
		line("- **Weak axes stay on their own tier:** the Rusty Axe earns the most in the starter forest.")
	end
	if infernoRate / anyRate < 2 then
		line(
			string.format(
				"- **Axe upgrades barely move income once you haul far.** On the best wood with the Rustbucket, going from the Rusty Axe to the Inferno Axe raises $/h only %.1f×: the drive dominates each trip, so trucks and trailers matter more than axes.",
				infernoRate / anyRate
			)
		)
	end
	line(
		string.format(
			"- **The forge grind:** before the Starfall Axe, Lumenwood with the Inferno Axe earns %s/h (emberwood: %s/h). With the Starfall Axe it earns %s/h.",
			money(grind * EFFICIENCY),
			money(late * EFFICIENCY),
			money(finale * EFFICIENCY)
		)
	)
	local lastGoal = 0
	for id in pairs(GOALS) do
		local s = stepFor[id]
		lastGoal = math.max(lastGoal, if s then s.total else math.huge)
	end
	line(
		string.format(
			"- **All of V1 (Inferno Axe, Logging Rig, forged Starfall Axe) takes %s of play** for a focused player.",
			duration(lastGoal)
		)
	)
	line(
		string.format(
			"- **The %s wallet cap** (GameConfig.CashCap) takes %s of saving at the best V1 loop (%s/h), far past the whole progression, so it only stops hardcore grinders.",
			money(GameConfig.CashCap),
			duration(GameConfig.CashCap / (finale * EFFICIENCY) * 3600),
			money(finale * EFFICIENCY)
		)
	)
	line()
end

line("## Targets vs. model (real player)")
line()
line("| Target (GAME_DESIGN) | Goal | Model | Verdict |")
line("|---|---|---|---|")
line(
	string.format(
		"| First sale (§2, §11) | under 3 min | %s | %s |",
		duration(firstSale),
		if firstSale <= 180 then "✅ on target" else "⚠️ too slow"
	)
)
line(
	string.format(
		"| Earned in first 15 min, starter forest (§4) | $150–200 | %s | %s |",
		money(earnedAt15),
		verdict(earnedAt15, 150, 200, true)
	)
)
line(
	string.format(
		"| First axe upgrade, Steel Axe, starter forest (§2, §11) | 12–15 min | %s | %s |",
		if steel then duration(steel.total) else "never",
		if steel then verdict(steel.total, 12 * 60, 15 * 60, false) else "⚠️ not reached"
	)
)
line(
	string.format(
		"| Early loop: Rusty Axe + Rustbucket (%s) | $600–800/h ¹ | %s/h | %s |",
		earlyWood.displayName,
		money(early * EFFICIENCY),
		verdict(early * EFFICIENCY, 600, 800, true)
	)
)
line(
	string.format(
		"| Mid-game: Steel Axe + Pickup (%s) (§4) | ~$1,500/h | %s/h | %s |",
		midWood.displayName,
		money(mid * EFFICIENCY),
		verdict(mid * EFFICIENCY, 1500, 1500, true)
	)
)
line(
	string.format(
		"| End-game: Inferno Axe + Logging Rig (%s) (§4) | $15k–20k/h | %s/h | %s |",
		lateWood.displayName,
		money(late * EFFICIENCY),
		verdict(late * EFFICIENCY, 15000, 20000, true)
	)
)
line(
	string.format(
		"| V1 finale: Starfall Axe on Lumenwood | above end-game (>$20k/h) | %s/h | %s |",
		money(finale * EFFICIENCY),
		if finale * EFFICIENCY > 20000 then "✅ on target" else "⚠️ below end-game"
	)
)
for _, pair in ipairs({ { "Inferno Axe", inferno }, { "Logging Rig", rig }, { "Starfall Axe (forging)", starfall } }) do
	local s = pair[2]
	line(
		string.format(
			"| Saving up for the %s (§4) | 2–4 sessions ² | %s | %s |",
			pair[1],
			if s
				then string.format("%s (%.1f sessions)", duration(s.saving), s.saving / 60 / A.sessionMinutes)
				else "never",
			if s then verdict(s.saving, sessionLo, sessionHi, false) else "⚠️ not reached"
		)
	)
end
line()
line('¹ §4\'s "$150–200 in the first 15 minutes" expressed per hour.  ')
line(string.format("² One session = %d min (an assumption in `tools/economy1.luau`).", A.sessionMinutes))
line()

-- Calibration hint.
line("## Calibrating with a playtest")
line()
line(
	"1. In Studio, play the starter loop with the Rusty Axe and Rustbucket for about 10 minutes: chop, load the truck, sell at the mill."
)
line(
	"2. The Output window prints a line starting `lune run tools/economy1 --calibrate` (every minute, and when you stop)."
)
line(
	"3. Run that line in the repo folder. It saves EFFICIENCY to `tools/calibration.json` and rewrites this report with honest numbers."
)
line()
line(
	if calibration
		then string.format(
			"Current: **%.2f**, measured %s over %d min. Re-run after big changes to how the loop plays.",
			EFFICIENCY,
			calibration.date,
			math.floor(calibration.seconds / 60 + 0.5)
		)
		else string.format(
			"Current: **%.2f (a guess)**. For reference, the ideal model earns %s/min on %s with the starter kit.",
			EFFICIENCY,
			money(early / 60),
			earlyWood.displayName:lower()
		)
)
line()

-- Woods: what a tree is worth per hit.
line("## What each wood pays")
line()
line(
	'"$ per 100 HP" is what each 100 HP of chopping earns. It falls up the tiers on purpose: rare wood pays per log (worth the long drive with a big truck), not per swing, so weak axes are better off on their own tier. Hardness is subtracted from every hit.'
)
line()
line("| Wood | Biome | HP | Hardness | Logs | $/log | $/tree | $ per 100 HP | Haul |")
line("|---|---|---|---|---|---|---|---|---|")
for _, wood in ipairs(WOODS) do
	local perTree = wood.logsPerTree * wood.pricePerLog
	line(
		string.format(
			"| %s | %s | %d | %d | %d | %s | %s | %s | %s |",
			wood.displayName,
			biome(wood.biome).displayName,
			wood.treeHP,
			wood.hardness,
			wood.logsPerTree,
			money(wood.pricePerLog),
			money(perTree),
			money(perTree / wood.treeHP * 100),
			if biome(wood.biome).access == "gondola"
				then "gondola + Cloud Chute"
				else string.format("%d studs by %s", biome(wood.biome).haulStuds, biome(wood.biome).access)
		)
	)
end
line()

-- Best wood for each axe (Rustbucket, all gear).
line("## Best wood for each axe")
line()
line(
	"With the starter Rustbucket and all gear. When the best wood is far above an axe's tier, nothing pushes players to upgrade their axe before farming rare wood."
)
line()
line("| Axe | Best wood anywhere | $/h there | Best in starter forest | $/h there |")
line("|---|---|---|---|---|")
for _, axe in ipairs(AXES) do
	local owned =
		{ [axe.id] = true, Rustbucket = true, HeatBoots = true, InsulatedCoat = true, Lantern = true, Rowboat = true }
	local anyRate, anyWood = bestRate(owned)
	local startRate, startWood = bestRate(owned, STARTER)
	line(
		string.format(
			"| %s | %s | %s | %s | %s |",
			axe.displayName,
			if anyWood then anyWood.displayName else "-",
			money(anyRate * EFFICIENCY),
			if startWood then startWood.displayName else "-",
			money(startRate * EFFICIENCY)
		)
	)
end
line()

-- Progression path.
line("## Progression path")
line()
line(
	'The whole world, with a player who always buys whichever upgrade pays for itself fastest (real-player rates). Axes are sold in order, one tier at a time. "Working" is the wood they farm while saving.'
)
line()
line("| # | Buy | Price | Saving for it | Total play time | $/h before → after | Working |")
line("|---|---|---|---|---|---|---|")
for i, s in ipairs(steps) do
	line(
		string.format(
			"| %d | %s | %s | %s | %s | %s → %s | %s |",
			i,
			s.item.displayName .. (if s.item.forge then " (forged)" else ""),
			money(itemPrice(s.item)),
			duration(s.saving),
			duration(s.total),
			money(s.before),
			money(s.after),
			if s.wood then s.wood.displayName else "-"
		)
	)
end
line()

-- Hits to fell.
line("## Hits to fell one tree")
line()
local header = "| Axe (damage) |"
local rule = "|---|"
for _, wood in ipairs(WOODS) do
	header ..= string.format(" %s (%d HP, hardness %d) |", wood.displayName, wood.treeHP, wood.hardness)
	rule ..= "---|"
end
line(header)
line(rule)
for _, axe in ipairs(AXES) do
	local row = string.format("| %s (%d%s) |", axe.displayName, axe.damage, if axe.biomeDamage then "*" else "")
	for _, wood in ipairs(WOODS) do
		local hits = hitsToFell(axe, wood)
		row ..= if hits == math.huge then " — |" else string.format(" %d |", hits)
	end
	line(row)
end
line()
line(
	"— = can't cut it: the wood's hardness is at least the axe's damage. \\* Deals more to some biomes (ItemCatalog `biomeDamage`)."
)
line()

-- The Living Forest (GAME_DESIGN §16): figured wood, the planter's share,
-- Elders. Computed from ForestData through ForestLogic.
do
	line("## The Living Forest")
	line()
	line(
		string.format(
			"Some trees hide a figure that sells for more (ForestData): %d in 100 at a Healthy grove, a figured tree's logs worth %.2f× on average (%.2f× on Lumenwood, where %d in 10 burls are Starfall Burls). Every rate above includes that average at a %s grove. Storm strikes, Elders, Skyroot Blooms and the planted-tree bonus are events on top and aren't counted.",
			math.floor(ForestData.FigureChance.base * 100 + 0.5),
			ForestLogic.FiguredAverage("oak"),
			ForestLogic.FiguredAverage("lumenwood"),
			math.floor(ForestData.StarfallShare * 10 + 0.5),
			A.groveTier
		)
	)
	line()
	line("What figures add to wood income, by the grove's vitality tier:")
	line()
	line("| Grove | Figure chance (wild / planted) | Adds (wild) | Adds (planted) | In a Skyroot Bloom (wild) |")
	line("|---|---|---|---|---|")
	for _, tier in ipairs(ForestData.Tiers) do
		line(
			string.format(
				"| %s (%d+) | %.0f%% / %.0f%% | +%.1f%% | +%.1f%% | +%.1f%% |",
				tier.displayName,
				tier.min,
				ForestLogic.FigureChance(tier.id, false, false) * 100,
				ForestLogic.FigureChance(tier.id, true, false) * 100,
				ForestLogic.FigureBonus("oak", tier.id, false, false) * 100,
				ForestLogic.FigureBonus("oak", tier.id, true, false) * 100,
				ForestLogic.FigureBonus("oak", tier.id, false, true) * 100
			)
		)
	end
	line()
	local v = ForestData.Vitality
	line(
		string.format(
			"Figure chance is flat at the Healthy rate. The grove meter and planting are not in the live loop, so a grove no longer drifts (the old rest was %d, %d a minute).",
			v.rest,
			v.driftPerMinute
		)
	)
	line()
	line(
		string.format(
			"An Elder (%.1f× size, %d× HP, %d× logs, always Quilted or Burl) pays each helper %d%% of its logs' value.",
			ForestData.Elder.scale,
			ForestData.Elder.hpMul,
			ForestData.Elder.logMul,
			math.floor(ForestData.Elder.helperShare * 100 + 0.5)
		)
	)
	line()
	-- An Elder's figure: Quilted or Burl by their weights.
	local elderMul, elderWeight = 0, 0
	for _, id in ipairs(ForestData.Elder.figures) do
		local f = ForestLogic.Figure(id)
		elderMul += f.weight * f.multiplier
		elderWeight += f.weight
	end
	elderMul /= elderWeight
	line("| Wood | Planter's share per tree | Elder HP | Elder logs | Elder value (avg) | Each helper's bonus |")
	line("|---|---|---|---|---|---|")
	for _, wood in ipairs(WOODS) do
		local b = biome(wood.biome)
		if b.area and b.area.y == nil then -- Elders wake in the ground groves
			local logs = ForestData.Elder.logMul * wood.logsPerTree
			local value = logs * wood.pricePerLog * elderMul
			line(
				string.format(
					"| %s | %s | %d | %d | %s | %s |",
					wood.displayName,
					money(ForestLogic.Royalty(wood.pricePerLog, wood.logsPerTree)),
					ForestData.Elder.hpMul * wood.treeHP,
					logs,
					money(value),
					money(ForestLogic.HelperBonus(value))
				)
			)
		end
	end
	line()
end

-- Assumptions.
line("## Assumptions")
line()
line(
	string.format(
		"- Swing every %.1f s; carry %d logs by hand (GameConfig).",
		GameConfig.SwingCooldown,
		GameConfig.HandCapacity
	)
)
local speeds = {}
for _, truck in ipairs(TRUCKS) do
	table.insert(speeds, string.format("%s %d", truck.displayName, truck.topSpeed))
end
line(
	string.format(
		"- Walk %d studs/s; trucks drive at their top speed (%s studs/s); boats %d studs/s.",
		A.walkSpeed,
		table.concat(speeds, ", "),
		A.boatSpeed
	)
)
local hauls = {}
for _, b in ipairs(BiomeData.All()) do
	if b.haulStuds then
		table.insert(hauls, string.format("%s %d (%s)", b.displayName, b.haulStuds, b.access))
	end
end
line("- One-way haul to the sawmill in studs, from BiomeData: " .. table.concat(hauls, ", ") .. ".")
local sky = biome("sky")
line(
	string.format(
		"- %s: gondola %d s each way ($%d a ride), logs carried %d studs to the Cloud Chute, Sky Bin holds %d.",
		sky.displayName,
		sky.gondola.rideSec,
		sky.gondola.fee,
		sky.chuteWalkStuds,
		sky.skyBinCapacity
	)
)
line(
	string.format(
		"- Forged axes cost their cash plus the logs and materials given up (at sell value), plus %d min per Sky Shard to mine.",
		A.shardMinutes
	)
)
line(
	string.format(
		"- %d studs between trees, %d studs from tree to truck, %.1f s per prompt press, %d s to get in/out and park.",
		A.betweenTrees,
		A.treeToTruck,
		A.promptTime,
		A.driveOverhead
	)
)
line(
	"- Biome rules come from BiomeData: required gear (volcano: Heat Boots; Phantom Grove: Lantern, night only, so left out of the path), boats for the Island, and slowdowns (snow without the Insulated Coat)."
)
line(
	string.format(
		"- Each load = cargo + a full armful; logs are sold at WoodData prices × the figure average at a %s grove (ForestData).",
		A.groveTier
	)
)
line(
	string.format(
		"- Murph's tutorial pays %s (TutorialData), counted toward the first purchase.",
		money(TutorialData.TotalReward())
	)
)
do
	-- Daily goals aren't in the pace above: they're a once-a-day extra.
	local function dailyMax(tier: number): number
		return DailyData.GoalsPerDay * DailyData.Tiers[tier].reward + DailyData.Bonus(tier, 5)
	end
	line(
		string.format(
			"- Daily goals (DailyData) aren't counted above: at most %s a day with the Rusty Axe, up to %s with the Starfall Axe (all goals plus a 5-day streak bonus).",
			money(dailyMax(1)),
			money(dailyMax(#DailyData.Tiers))
		)
	)
end

local report = table.concat(out, "\n") .. "\n"
if process.args[1] == "--check" then
	-- CI: fail if someone changed the balance tables without regenerating.
	local current = if fs.isFile("ECONOMY_V1.md") then fs.readFile("ECONOMY_V1.md") else ""
	if string.gsub(current, "\r\n", "\n") ~= report then
		print("ECONOMY_V1.md is out of date. Run `lune run tools/economy1` and commit the result.")
		process.exit(1)
	end
	print("ECONOMY_V1.md is up to date.")
else
	fs.writeFile("ECONOMY_V1.md", report)
	print(report)
end
