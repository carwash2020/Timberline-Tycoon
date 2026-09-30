--!nocheck
-- Economy calculator for Timberline Tycoon.
--
-- Reads the real balance tables (WoodData, ItemCatalog, GameConfig), models
-- how fast a player earns with each gear setup, simulates a player climbing
-- the whole progression, and checks the results against the targets in
-- GAME_DESIGN §2, §4 and §11. Writes the report to ECONOMY.md.
--
-- Run from the repo root:   lune run tools/economy
--
-- It's a model, not a measurement. It assumes trees are always available
-- and nobody competes for them. EFFICIENCY scales the ideal "perfect player"
-- numbers down to a real one. Calibrate it with a Studio playtest: play the
-- starter loop for ~10 minutes, read the "[Stopwatch] ... overall" $/min,
-- divide by the ideal $/min this report prints, put that in EFFICIENCY and
-- re-run.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/economy")

-- The data modules are plain Luau except WoodData's Color3 colours, so load
-- them with Lune's Color3 standing in for Roblox's.
local function loadModule(name: string)
	local path = "src/ReplicatedStorage/Shared/" .. name .. ".luau"
	return luau.load(fs.readFile(path), { debugName = path, environment = { Color3 = roblox.Color3 } })()
end
local WoodData = loadModule("WoodData")
local ItemCatalog = loadModule("ItemCatalog")
local GameConfig = loadModule("GameConfig")

---------------------------------------------------------------------------
-- Assumptions (edit these, then re-run)
---------------------------------------------------------------------------
local EFFICIENCY = 0.5 -- real player vs the ideal model (calibrate, see top)

local A = {
	walkSpeed = 16, -- studs/s, Roblox default WalkSpeed
	driveSpeed = 26, -- studs/s, VehicleService DRIVE_SPEED (every truck, for now)
	boatSpeed = 26, -- studs/s, no boats built yet
	fellTime = 0.75, -- s, fall animation + logs appearing
	betweenTrees = 15, -- studs walked to the next tree
	treeToTruck = 20, -- studs from the felled tree to the parked truck
	promptTime = 0.5, -- s per Pick up / Load press
	driveOverhead = 8, -- s per round trip: get in, park, get out
	sellTime = 2, -- s
	coldSlowdown = 0.15, -- snow without the Insulated Coat: 15% slower (§10)
	sessionMinutes = 45, -- one "session" for the "2-4 sessions" target (§4)
}

-- One-way haul from each biome to the sawmill, in studs (GAME_DESIGN §10;
-- the starter forest is measured from the Phase 1 MapBuilder layout).
local HAUL = { starter = 190, hills = 400, snow = 1200, volcano = 1600, island = 900, grove = 800 }
local NIGHT_ONLY = { grove = true } -- the Phantom Grove only exists at night
local NEEDS = { volcano = "HeatBoots", grove = "Lantern" } -- gear required to work the biome
local BY_BOAT = { island = true } -- trucks can't swim; the boat's hull is the cargo

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

local AXES = sortedByPrice(ItemCatalog.Axes)
local TRUCKS = sortedByPrice(ItemCatalog.Trucks)
local TRAILERS = sortedByPrice(ItemCatalog.Trailers)
local BOATS = sortedByPrice(ItemCatalog.Boats)
local GEAR = sortedByPrice(ItemCatalog.Gear)
local WOODS = WoodData.All()

local function hitsToFell(axe, wood): number
	return math.ceil(wood.treeHP / ItemCatalog.AxeDamage(axe, wood.biome))
end

-- One full load: chop enough trees to fill the cargo plus both hands,
-- carry logs to the vehicle two at a time, drive to the mill, sell.
-- Returns seconds, cash, logs for a perfect player.
local function loadCycle(axe, cargo: number, speed: number, wood, hasCoat: boolean)
	local slow = if wood.biome == "snow" and not hasCoat then 1 / (1 - A.coldSlowdown) else 1
	local hits = hitsToFell(axe, wood)
	local perTree = ((hits - 1) * GameConfig.SwingCooldown + A.fellTime + A.betweenTrees / A.walkSpeed) * slow
	local logs = cargo + GameConfig.HandCapacity
	local chop = (logs / wood.logsPerTree) * perTree
	local trips = math.ceil(cargo / GameConfig.HandCapacity)
	local carry = trips * (2 * A.treeToTruck / A.walkSpeed) * slow + (logs + trips) * A.promptTime
	local haul = 2 * HAUL[wood.biome] / speed + A.driveOverhead
	return chop + carry + haul + A.sellTime, logs * wood.pricePerLog, logs
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

-- Best cash per hour for a set of owned items (perfect player), optionally
-- limited to some biomes. Night-only biomes are left out.
-- Returns $/hr, wood, axe, cargo description.
local function bestRate(owned, biomes: { [string]: boolean }?)
	local topRate, topWood, topAxe, topCargo = 0, nil, nil, ""
	for _, wood in ipairs(WOODS) do
		local gear = NEEDS[wood.biome]
		local allowed = if biomes then biomes[wood.biome] == true else true
		if allowed and not NIGHT_ONLY[wood.biome] and (gear == nil or owned[gear]) then
			local axe = best(AXES, owned, function(a)
				return ItemCatalog.AxeDamage(a, wood.biome)
			end)
			local cargo, speed, label = 0, A.driveSpeed, ""
			if BY_BOAT[wood.biome] then
				local boat = best(BOATS, owned, function(b)
					return b.hullCapacity
				end)
				if boat then
					cargo, speed, label = boat.hullCapacity, A.boatSpeed, boat.displayName
				end
			else
				local truck = best(TRUCKS, owned, function(t)
					return t.bedCapacity
				end)
				local trailer = best(TRAILERS, owned, function(t)
					return t.extraCapacity
				end)
				if truck then
					cargo = truck.bedCapacity + (if trailer then trailer.extraCapacity else 0)
					label = truck.displayName .. (if trailer then " + " .. trailer.displayName else "")
				end
			end
			if axe and cargo > 0 then
				local secs, cash = loadCycle(axe, cargo, speed, wood, owned.InsulatedCoat == true)
				local rate = cash / secs * 3600
				if rate > topRate then
					topRate, topWood, topAxe, topCargo = rate, wood, axe, label
				end
			end
		end
	end
	return topRate, topWood, topAxe, topCargo
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
	local drives = 80 / A.driveSpeed + HAUL.starter / A.driveSpeed + A.driveOverhead
	return toTruck + drives + chop + carry + A.sellTime
end

---------------------------------------------------------------------------
-- Progression: a player who always buys the upgrade that pays for itself
-- fastest, until they own the Inferno Axe and the Logging Rig.
---------------------------------------------------------------------------
local function simulate(biomes: { [string]: boolean }?)
	local owned = { RustyAxe = true, Rustbucket = true }
	local t, cash, earned = firstSaleSeconds() / EFFICIENCY, 0, 0
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
		if owned.InfernoAxe and owned.LoggingRig then
			break
		end
		local rate, wood = bestRate(owned, biomes)
		rate *= EFFICIENCY
		-- Pick the purchase with the shortest payback (price / extra $ per hour).
		-- Goals with no payback left (e.g. the Inferno Axe once a better
		-- wood isn't unlocked) are still bought at the end.
		local pick, pickScore, pickRate = nil, math.huge, rate
		for _, item in ipairs(candidates) do
			if not owned[item.id] and item.priceCash > 0 then
				owned[item.id] = true
				local newRate = bestRate(owned, biomes) * EFFICIENCY
				owned[item.id] = nil
				local gain = newRate - rate
				local isGoal = item.id == "InfernoAxe" or item.id == "LoggingRig"
				local score = if gain > 0
					then item.priceCash / gain
					else (if isGoal then 1e12 + item.priceCash else math.huge)
				if score < pickScore then
					pick, pickScore, pickRate = item, score, newRate
				end
			end
		end
		if not pick or (biomes and pickScore >= 1e12) then
			break -- nothing left that helps (in a limited world, don't buy goals for nothing)
		end
		local wait = math.max(0, pick.priceCash - cash) / rate * 3600
		advance(wait, rate)
		cash -= pick.priceCash
		owned[pick.id] = true
		table.insert(steps, {
			item = pick,
			saving = wait,
			total = t,
			before = rate,
			after = pickRate,
			wood = wood,
		})
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
		local secs, cash = loadCycle(
			ItemCatalog.GetAxe(axeId),
			ItemCatalog.GetTruck(truckId).bedCapacity,
			A.driveSpeed,
			wood,
			owned.InsulatedCoat == true
		)
		local rate = cash / secs * 3600
		if rate > topRate then
			topRate, topWood = rate, wood
		end
	end
	return topRate, topWood
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
	"_Generated by `lune run tools/economy` from WoodData, ItemCatalog and GameConfig. Don't edit by hand: change the data or the assumptions in `tools/economy.luau`, then re-run._"
)
line()
line(
	string.format(
		'**Model, not measurement.** Numbers assume trees are always available and nobody competes for them. "Real player" = the ideal model × EFFICIENCY (%.2f), a guess until a playtest calibrates it.',
		EFFICIENCY
	)
)
line()

-- Headline checks.
local firstSale = firstSaleSeconds() / EFFICIENCY
local early, earlyWood = setupRate("RustyAxe", "Rustbucket", { "oak", "birch" })
local mid, midWood = setupRate("SteelAxe", "Pickup", { "pine", "maple" })
local late, lateWood = setupRate("InfernoAxe", "LoggingRig", { "emberwood" }, { "HeatBoots" })
local steel = starterStepFor.SteelAxe
local inferno = stepFor.InfernoAxe
local rig = stepFor.LoggingRig
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
				"- **Earning runs about %.0f× faster than the design's targets** (median of the early, mid and end-game checks below).",
				median
			)
		)
	elseif median < 0.75 then
		line(string.format("- **Earning runs about %.0f× slower than the design's targets.**", 1 / median))
	else
		line("- **Earning rates are within 25% of the design's targets.**")
	end
	if anyWood and startWood and anyWood.biome ~= "starter" then
		line(
			string.format(
				"- **Rare wood doesn't need a better axe.** With the Rusty Axe and Rustbucket, %s earns %.1f× what %s does, so the best move from minute one is to skip the starter forest and axe upgrades.",
				anyWood.displayName:lower(),
				anyRate / startRate,
				startWood.displayName:lower()
			)
		)
	end
	line(
		string.format(
			"- **Axe upgrades barely move income once you haul far.** On the best wood with the Rustbucket, going from the Rusty Axe to the Inferno Axe raises $/h only %.1f×: the drive dominates each trip, so trucks and trailers matter more than axes.",
			infernoRate / anyRate
		)
	)
	if inferno and rig then
		line(
			string.format(
				"- **The whole progression (Inferno Axe + Logging Rig) takes %s of play** for a focused player.",
				duration(math.max(inferno.total, rig.total))
			)
		)
	end
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
for _, pair in ipairs({ { "Inferno Axe", inferno }, { "Logging Rig", rig } }) do
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
line(string.format("² One session = %d min (an assumption in `tools/economy.luau`).", A.sessionMinutes))
line()

-- Calibration hint.
line("## Calibrating with a playtest")
line()
line(
	string.format(
		"The ideal model earns **%s/min** with the Rusty Axe and Rustbucket on %s. Play that loop in Studio for ~10 minutes and read the `[Stopwatch] ... overall` $/min in the Output window. Set `EFFICIENCY` in `tools/economy.luau` to your number ÷ %s, and re-run.",
		money(early / 60),
		earlyWood.displayName:lower(),
		money(early / 60)
	)
)
line()

-- Woods: what a tree is worth per hit.
line("## What each wood pays")
line()
line(
	'"$ per 100 HP" is what each 100 HP of chopping earns, whatever the axe. If it climbs much faster than the haul gets longer, rare wood beats upgrading your axe.'
)
line()
line("| Wood | Biome | HP | Logs | $/log | $/tree | $ per 100 HP | Haul (studs) |")
line("|---|---|---|---|---|---|---|---|")
for _, wood in ipairs(WOODS) do
	local perTree = wood.logsPerTree * wood.pricePerLog
	line(
		string.format(
			"| %s | %s | %d | %d | %s | %s | %s | %d |",
			wood.displayName,
			wood.biome,
			wood.treeHP,
			wood.logsPerTree,
			money(wood.pricePerLog),
			money(perTree),
			money(perTree / wood.treeHP * 100),
			HAUL[wood.biome]
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
	'The whole world, with a player who always buys whichever upgrade pays for itself fastest (real-player rates). "Working" is the wood they farm while saving.'
)
line()
line("| # | Buy | Price | Saving for it | Total play time | $/h before → after | Working |")
line("|---|---|---|---|---|---|---|")
for i, s in ipairs(steps) do
	line(
		string.format(
			"| %d | %s | %s | %s | %s | %s → %s | %s |",
			i,
			s.item.displayName,
			money(s.item.priceCash),
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
	header ..= string.format(" %s (%d HP) |", wood.displayName, wood.treeHP)
	rule ..= "---|"
end
line(header)
line(rule)
for _, axe in ipairs(AXES) do
	local row = string.format("| %s (%d%s) |", axe.displayName, axe.damage, if axe.biomeDamage then "*" else "")
	for _, wood in ipairs(WOODS) do
		row ..= string.format(" %d |", hitsToFell(axe, wood))
	end
	line(row)
end
line()
line("\\* Deals more to some biomes (ItemCatalog `biomeDamage`).")
line()

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
line(
	string.format(
		"- Walk %d studs/s; every truck drives %d studs/s; boats %d studs/s.",
		A.walkSpeed,
		A.driveSpeed,
		A.boatSpeed
	)
)
local hauls = {}
for _, biome in ipairs({ "starter", "hills", "snow", "volcano", "island", "grove" }) do
	table.insert(hauls, string.format("%s %d", biome, HAUL[biome]))
end
line("- One-way haul to the sawmill (studs): " .. table.concat(hauls, ", ") .. ".")
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
	"- Volcano needs Heat Boots, the Phantom Grove needs a Lantern and only exists at night (left out of the path), the Island needs a boat, and snow is 15% slower without the Insulated Coat."
)
line("- Each load = cargo + a full armful; logs are sold at WoodData prices.")

local report = table.concat(out, "\n") .. "\n"
fs.writeFile("ECONOMY.md", report)
print(report)
