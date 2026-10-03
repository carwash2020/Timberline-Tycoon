--!nocheck
-- Economy model for the v2 core loop (V2_PLAN.md §17): section trees cut
-- anywhere, wood sold by volume: the live loop since the M1.9 flip. Writes
-- ECONOMY.md (tools/economy1 keeps the v1 loop's model, ECONOMY_V1.md).
--
-- Run from the repo root:   lune run tools/economy
-- Check the committed report is current (CI does):   lune run tools/economy --check
--
-- Reads the real tables (WoodData v2 rows and shapes, ItemCatalog v2 stats,
-- BiomeData, GameConfig) and builds the trees with Shared/TreeGen, so the
-- volumes are the game's own. The per-u³ prices, hardness and axe stats are
-- LT2's rows renamed (V2_PLAN §2; that provenance lives only in tools/ and
-- the plan). Truck beds are TruckLayout's, as the game builds them.
--
-- It's a model, not a measurement: trees always available, nobody
-- competing. EFFICIENCY scales the ideal player to a real one: the value
-- tools/calibration.json holds (MilestoneService's stopwatch line, run
-- with --calibrate, writes it), or 0.5.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local luau = require("@lune/luau")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/economy")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WoodData = modules:shared("WoodData")
local ItemCatalog = modules:shared("ItemCatalog")
local GameConfig = modules:shared("GameConfig")
local BiomeData = modules:shared("BiomeData")
local ForestData = modules:shared("ForestData")
local ForestLogic = modules:shared("ForestLogic")
local TreeGen = modules:shared("TreeGen")
local SectionLogic = modules:shared("SectionLogic")
local SawmillLogic = modules:shared("SawmillLogic")

local CALIBRATION_FILE = "tools/calibration.json"
local calibration = if fs.isFile(CALIBRATION_FILE) then serde.decode("json", fs.readFile(CALIBRATION_FILE)) else nil
local EFFICIENCY = if calibration then calibration.efficiency else 0.5
local U = GameConfig.WoodUnit

---------------------------------------------------------------------------
-- Assumptions (edit these, then re-run)
---------------------------------------------------------------------------
local A = {
	seeds = 50, -- trees per wood and size measured
	walkSpeed = 16, -- studs/s
	betweenTrees = 15, -- studs walked to the next tree
	dragStuds = 20, -- studs from where a piece lands to the bed (§17)
	dragSpeed = 16, -- studs/s dragging a liftable piece
	heavyFactor = 2, -- a piece too heavy to lift drags this much slower
	liftU3 = 130 / (1.6 ^ 3), -- §2f: about 130 studs³ lifts (density 0.15, ~20 mass)
	aimSec = 1.5, -- s to walk to and line up each cut after the first
	tripOverhead = 8, -- s per round trip: get in, park, get out (§17)
	sellSec = 4, -- s at the pad (§17)
	murphReward = 25, -- the tutorial's `loads` reward (§13), after murphAfter dollars sold
	murphAfter = 120, -- TutorialData's v2 loads step (dollars sold before Murph pays)
	groveTier = "Healthy", -- figured-wood average, as tools/economy
	plotPrice = 900100, -- a full plot (§2f: $100 + 3000 x (1 + ... + 24))
	sharing = 4, -- players sharing a biome's regrowth (a rare wood's cap on $/h)
	-- A sawmill you own mills a piece when that pays more than selling the
	-- log. The blade's own time is SawmillLogic.ProcessSeconds; these are
	-- the rest (stop at the plot, feed each piece). Plank prices in WoodData
	-- were scaled so this handling still lands the §17 headlines.
	millFeedSec = 15, -- drag one piece in and the planks back onto the truck
	millDetourSec = 40, -- unload, mill and reload, on the way to the pad
}

-- Truck and trailer beds as the game builds them (TruckLayout): length,
-- interior width, wall height. The Scout ATV's rack carries no wood.
local TruckLayout = modules:shared("TruckLayout")
local BEDS = {}
for id, truck in pairs(ItemCatalog.Trucks) do
	local l = TruckLayout.For(truck)
	BEDS[id] = { l.bedLength, l.bedWidth, l.wallHeight }
end
local towLayout = TruckLayout.For(ItemCatalog.GetTruck("Rustbucket"))
for id, trailer in pairs(ItemCatalog.Trailers) do
	local l = TruckLayout.ForTrailer(trailer, towLayout)
	BEDS[id] = { l.bedLength, l.bedWidth, l.wallHeight }
end

-- §17's estimates of $ per mature tree, logs / planks (for comparison).
local PLAN_PER_TREE = {
	oak = { 39, 260 },
	birch = { 28, 187 },
	pine = { 128, 720 },
	maple = { 88, 830 },
	palmwood = { 52, 570 },
	frostwood = { 240, 2830 },
	emberwood = { 79, 635 },
	phantomwood = { 348, 990 },
	lumenwood = { 1090, 3900 },
}

---------------------------------------------------------------------------
-- Helpers
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
	if seconds == math.huge then
		return "never"
	elseif seconds < 90 then
		return string.format("%.0f s", seconds)
	elseif seconds < 90 * 60 then
		return string.format("%.1f min", seconds / 60)
	end
	return string.format("%.1f h", seconds / 3600)
end

local function verdict(value: number, lo: number, hi: number): string
	if value == math.huge then
		return "⚠️ never"
	elseif value >= lo * 0.75 and value <= hi * 1.25 then
		return "✅ on target"
	end
	return if value < lo
		then string.format("⚠️ %.1f× too fast", lo / value)
		else string.format("⚠️ %.1f× too slow", value / hi)
end

local WOODS = WoodData.All()
local SIZE_WEIGHTS = { { TreeGen.SizeLo, 0.25 }, { 1, 0.5 }, { TreeGen.SizeHi, 0.25 } }

---------------------------------------------------------------------------
-- Trees: volumes from the generator itself
---------------------------------------------------------------------------
-- One mature tree, measured: its volume (u³), the trunk's share, its base
-- and limb thicknesses, the trunk's length.
local function measureTree(skel)
	local total, trunk = 0, 0
	local trunkLen = 0
	for _, s in ipairs(skel.sections) do
		local v = SectionLogic.NodeVolume(s)
		total += v
		if s.depth < skel.trunkSegments then
			trunk += v
			trunkLen += s.length
		end
	end
	local top = skel.sections[skel.trunkSegments]
	local limbs = {}
	for _, c in ipairs(top.children) do
		table.insert(limbs, skel.sections[c].thickness)
	end
	-- The trunk's thickness half way up (where the bucking cuts fall).
	local mid = skel.sections[math.max(1, math.floor(skel.trunkSegments / 2 + 0.5))].thickness
	return {
		volume = total,
		trunk = trunk,
		base = skel.sections[1].thickness,
		mid = mid,
		limbs = limbs,
		trunkLen = trunkLen,
		sections = #skel.sections,
		height = skel.height,
	}
end

-- The average tree of a wood at one scale over A.seeds seeds.
local function average(woodId: string, scale: number, elder: boolean)
	local sum =
		{ volume = 0, trunk = 0, base = 0, mid = 0, limbCount = 0, limbT = 0, trunkLen = 0, sections = 0, height = 0 }
	for seed = 1, A.seeds do
		local m = measureTree(TreeGen.Skeleton(woodId, seed, scale, { elder = elder }))
		sum.volume += m.volume
		sum.trunk += m.trunk
		sum.base += m.base
		sum.mid += m.mid
		sum.trunkLen += m.trunkLen
		sum.sections += m.sections
		sum.height += m.height
		sum.limbCount += #m.limbs
		for _, t in ipairs(m.limbs) do
			sum.limbT += t
		end
	end
	local n = A.seeds
	return {
		volume = sum.volume / n,
		trunk = sum.trunk / n,
		base = sum.base / n,
		mid = sum.mid / n,
		trunkLen = sum.trunkLen / n,
		sections = sum.sections / n,
		height = sum.height / n,
		limbs = sum.limbCount / n,
		limbT = if sum.limbCount > 0 then sum.limbT / sum.limbCount else 0,
	}
end

local TREES = {} -- [woodId] = { small, normal, large, elder, mean }
for _, wood in ipairs(WOODS) do
	local row = {}
	local mean =
		{ volume = 0, trunk = 0, base = 0, mid = 0, trunkLen = 0, sections = 0, height = 0, limbs = 0, limbT = 0 }
	for _, sw in ipairs(SIZE_WEIGHTS) do
		local a = average(wood.id, sw[1], false)
		row[sw[1]] = a
		for k, v in pairs(a) do
			mean[k] += v * sw[2]
		end
	end
	row.elder = average(wood.id, ForestData.Elder.scale, true)
	row.mean = mean
	TREES[wood.id] = row
end

---------------------------------------------------------------------------
-- The work model
---------------------------------------------------------------------------
local supplyRate: (any) -> number

local function figureFactor(wood): number
	return 1 + ForestLogic.FigureBonus(wood.id, A.groveTier, false, false)
end

-- u³ a bed (or bed plus trailer) carries a trip.
local function bedU3(id: string?): number
	local b = id and BEDS[id]
	if not b or b[1] <= 0 then
		return 0
	end
	return TruckLayout.BedRoomU3(b[1], b[2], b[3], U)
end

local function bedLength(id: string): number
	local b = BEDS[id]
	return if b then b[1] else 0
end

-- Hits for a cut through a square section `t` studs across.
local function hits(axe, wood, t: number): number
	local damage = ItemCatalog.AxeStats(axe, wood.id)
	return SectionLogic.HitsToCut(wood.v2.hardness, t, damage or 0)
end

local function cutSec(axe, wood, t: number): number
	local _, cooldown = ItemCatalog.AxeStats(axe, wood.id)
	local h = hits(axe, wood, t)
	if h == math.huge then
		return math.huge
	end
	return SectionLogic.CutSeconds(h, cooldown)
end

-- Seconds to fell, limb and buck one average tree so its pieces fit a bed
-- `bedLen` long, and drag them to it; and how many pieces that makes.
local function treeWork(axe, wood, bedLen: number): (number, number)
	local tree = TREES[wood.id].mean
	local fell = cutSec(axe, wood, tree.base)
	if fell == math.huge then
		return math.huge, 0
	end
	local limbs = math.floor(tree.limbs + 0.5)
	local limbing = limbs * (cutSec(axe, wood, tree.limbT) + A.aimSec)
	local bucks = if bedLen > 0 then math.max(0, math.ceil(tree.trunkLen / bedLen) - 1) else 0
	local bucking = bucks * (cutSec(axe, wood, tree.mid) + A.aimSec)
	local pieces = 1 + limbs + bucks
	local trunkPiece = tree.trunk / (bucks + 1)
	local heavy = if trunkPiece > A.liftU3 then A.heavyFactor else 1
	local drag = (bucks + 1) * A.dragStuds / A.dragSpeed * heavy + limbs * A.dragStuds / A.dragSpeed
	return fell + limbing + bucking + drag + A.betweenTrees / A.walkSpeed, pieces
end

-- The best vehicle the player owns for wood, and its trip's u³ and seconds.
local function haulFor(b, owned)
	if b.access == "gondola" then
		local g = b.gondola
		return BiomeData.Get("sky").skyBinVolume, 2 * g.rideSec + 5, 2 * g.fee, "Cloud Chute + Sky Bin", 12
	elseif b.access == "boat" then
		return 0, 0, 0, "", 0 -- the Island comes with the ferry (M6)
	end
	local bestTruck, bestCap = nil, 0
	for id, truck in pairs(ItemCatalog.Trucks) do
		local cap = bedU3(id)
		if owned[id] and cap > bestCap then
			bestTruck, bestCap = truck, cap
		end
	end
	if not bestTruck then
		return 0, 0, 0, "", 0
	end
	local bestTrailer, trailerCap = nil, 0
	for id, trailer in pairs(ItemCatalog.Trailers) do
		local cap = bedU3(id)
		if owned[id] and cap > trailerCap then
			bestTrailer, trailerCap = trailer, cap
		end
	end
	local label = bestTruck.displayName .. (if bestTrailer then " + " .. bestTrailer.displayName else "")
	local secs = 2 * (b.haulStuds or 0) / bestTruck.topSpeed + A.tripOverhead
	return bestCap + trailerCap, secs, 0, label, bedLength(bestTruck.id)
end

-- The biggest mill owned (width, then length). Nil when the player has none,
-- which is the first sale and `--calibrate` (logs only).
local function bestMill(owned)
	local best = nil
	for _, mill in ipairs(ItemCatalog.SawmillList()) do
		if owned[mill.id] then
			if
				not best
				or mill.maxWidth > best.maxWidth
				or (mill.maxWidth == best.maxWidth and mill.maxLength > best.maxLength)
			then
				best = mill
			end
		end
	end
	return best
end

-- Share of a mean tree this mill can take: the trunk if its base is thin
-- enough (half the trunk if only the middle is), and the limbs if they are.
local function milledShare(mill, wood): number
	if not mill then
		return 0
	end
	local tree = TREES[wood.id].mean
	if tree.volume <= 0 then
		return 0
	end
	local limit = mill.maxWidth * U + 1e-3
	local trunk = 0
	if tree.base <= limit then
		trunk = tree.trunk
	elseif tree.mid <= limit then
		trunk = tree.trunk * 0.5
	end
	local limbs = if tree.limbT <= limit then math.max(0, tree.volume - tree.trunk) else 0
	return math.clamp((trunk + limbs) / tree.volume, 0, 1)
end

-- $/u³ this load actually sells for, and the share of it that was milled.
local function unitPrice(wood, mill): (number, number)
	local share = milledShare(mill, wood)
	return wood.v2.logPrice * (1 - share) + wood.v2.plankPrice * share, share
end

-- One load of `wood`: (seconds, cash, $/u³) for a perfect player, or nil.
-- Logs, or planks when a mill you own can take some of the tree and the
-- extra time still pays. Milled pieces are bucked down to the mill's length.
local function loadCycle(axe, wood, owned, cash: number?)
	local b = BiomeData.Get(wood.biome)
	if b.nightOnly or (b.requiresGear and not owned[b.requiresGear]) then
		return nil
	end
	local cap, tripSec, fee, _, bedLen = haulFor(b, owned)
	if cap <= 0 or (cash ~= nil and fee > cash) then
		return nil -- (a trip's fee must be affordable: the gondola's)
	end
	local slow = if b.slowdown and not owned[b.slowdown.removedBy] then 1 / (1 - b.slowdown.amount) else 1
	local tree = TREES[wood.id].mean
	local trees = cap / tree.volume
	local function trip(fitLen: number, price: number, extra: number): (number?, number?, number?)
		local perTree, pieces = treeWork(axe, wood, fitLen)
		if perTree == math.huge or pieces <= 0 then
			return nil
		end
		local secs = trees * perTree * slow + tripSec + A.sellSec + extra
		local earned = cap * price * figureFactor(wood) - fee
		return secs, earned, price
	end
	local secs, earned, price = trip(bedLen, wood.v2.logPrice, 0)
	local mill = bestMill(owned)
	local plankPrice, share = unitPrice(wood, mill)
	if mill and share > 0 and secs then
		local fitLen = math.min(bedLen, mill.maxLength * U)
		local _, pieces = treeWork(axe, wood, fitLen)
		local handle = SawmillLogic.ProcessSeconds(tree.volume / math.max(pieces, 1)) + A.millFeedSec
		local extra = trees * pieces * share * handle + A.millDetourSec
		local mSecs, mEarned, mPrice = trip(fitLen, plankPrice, extra)
		if mSecs and mEarned and mEarned / mSecs > earned / secs then
			secs, earned, price = mSecs, mEarned, mPrice
		end
	end
	return secs, earned, price
end

local AXES = ItemCatalog.AxeLadder()
local function bestAxeFor(owned, wood)
	local best, bestT = nil, math.huge
	for _, axe in ipairs(AXES) do
		if owned[axe.id] then
			local damage, cooldown = ItemCatalog.AxeStats(axe, wood.id)
			if damage and damage > 0 then
				local h = SectionLogic.HitsToCut(wood.v2.hardness, TREES[wood.id].mean.base, damage)
				local t = math.max(0, h - 1) * cooldown
				if t < bestT then
					best, bestT = axe, t
				end
			end
		end
	end
	return best
end

-- Trees of a wood that regrow in its biome an hour.
local function regrowPerHour(wood): number
	local count = (BiomeData.Get(wood.biome).trees or {})[wood.id] or 0
	return count / (wood.respawnSec + wood.v2.growSec) * 3600
end

-- $/hour of a wood one player can get when A.sharing players share its
-- biome's regrowth.
supplyRate = function(wood, pricePerU3: number?): number
	local price = pricePerU3 or wood.v2.logPrice
	return regrowPerHour(wood) / A.sharing * TREES[wood.id].mean.volume * price * figureFactor(wood)
end

-- Best $/hour (real player) for what's owned, filling the hour wood by
-- wood: the best-paying wood first, but only as long as the player's share
-- of its regrowth lasts (supplyRate), then the next. Returns the rate and
-- the wood the player spends most of the hour on (its axe and haul).
local function bestRate(owned, cash: number?)
	local options = {}
	for _, wood in ipairs(WOODS) do
		local axe = bestAxeFor(owned, wood)
		if axe then
			local secs, value, price = loadCycle(axe, wood, owned, cash)
			if secs and value > 0 then
				table.insert(options, {
					wood = wood,
					axe = axe,
					price = price,
					rate = value / secs * 3600 * EFFICIENCY,
				})
			end
		end
	end
	table.sort(options, function(x, y)
		return x.rate > y.rate
	end)
	local total, left = 0, 1
	local main, mainShare = nil, 0
	for _, o in ipairs(options) do
		if left <= 1e-9 then
			break
		end
		local share = math.min(left, supplyRate(o.wood, o.price) / o.rate)
		total += share * o.rate
		left -= share
		if share > mainShare then
			main, mainShare = o, share
		end
	end
	if not main then
		return 0, nil, nil, ""
	end
	local _, _, _, label = haulFor(BiomeData.Get(main.wood.biome), owned)
	return total, main.wood, main.axe, label
end

---------------------------------------------------------------------------
-- First sale and the progression
---------------------------------------------------------------------------
local function firstSale()
	local oak = WoodData.Get("oak")
	local rusty = ItemCatalog.GetAxe("RustyAxe")
	local truck = ItemCatalog.GetTruck("Rustbucket")
	local cap = bedU3("Rustbucket")
	local perTree = treeWork(rusty, oak, bedLength("Rustbucket"))
	local tree = TREES.oak.mean.volume
	local toTruck = 25 / A.walkSpeed
	local drive = 80 / truck.topSpeed + 2 * BiomeData.Get("starter").haulStuds / truck.topSpeed + A.tripOverhead
	local secs = (toTruck + drive + perTree + A.sellSec) / EFFICIENCY
	return secs, math.min(cap, tree) * oak.v2.logPrice
end

local function priceOf(item): number
	if item.v2 and item.v2.price then
		return item.v2.price
	end
	return item.priceCash or 0
end

local function simulate()
	local owned = { RustyAxe = true, Rustbucket = true }
	local t, value = firstSale()
	local cash = GameConfig.StartingCash + value
	local earned = value
	local murphPaid = false
	local events = { firstSale = t }
	local steps = {}
	local candidates = {}
	for _, list in ipairs({ ItemCatalog.Trucks, ItemCatalog.Trailers, ItemCatalog.Gear, ItemCatalog.Sawmills }) do
		for _, item in pairs(list) do
			table.insert(candidates, item)
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	local function earn(dt, rate)
		local before = earned
		t += dt
		cash += dt * rate / 3600
		earned += dt * rate / 3600
		if not murphPaid and earned >= value + A.murphAfter then
			murphPaid = true
			cash += A.murphReward
		end
		if not events.thousand and earned >= 1000 then
			local need = (1000 - before) / math.max(rate, 1e-9) * 3600
			events.thousand = t - dt + need
		end
	end
	for _ = 1, 30 do
		local rate = bestRate(owned, cash)
		-- The next axe on the ladder (forged ones aren't sold), or any
		-- vehicle or gear: the shortest payback wins.
		local pick, pickScore = nil, math.huge
		local function consider(item)
			if owned[item.id] or item.sold == false then
				return
			end
			local price = priceOf(item)
			if price <= 0 then
				return
			end
			owned[item.id] = true
			local gain = bestRate(owned, cash) - rate
			owned[item.id] = nil
			if gain > 1e-6 then
				local score = price / gain
				if score < pickScore then
					pick, pickScore = item, score
				end
			end
		end
		for i, axe in ipairs(AXES) do
			if not owned[axe.id] and (i == 1 or owned[AXES[i - 1].id]) then
				consider(axe)
				break
			end
		end
		for _, item in ipairs(candidates) do
			consider(item)
		end
		if not pick then
			break
		end
		local price = priceOf(pick)
		-- Save up, a minute at a time (the rate can rise as cash allows the
		-- gondola's fee).
		while cash < price do
			local r = bestRate(owned, cash)
			earn(math.min(60, (price - cash) / math.max(r, 1e-9) * 3600 + 1e-6), r)
		end
		cash -= price
		owned[pick.id] = true
		events[pick.id] = t
		local after, wood, axe, label = bestRate(owned, cash)
		table.insert(
			steps,
			{ item = pick, price = price, at = t, before = rate, after = after, wood = wood, axe = axe, label = label }
		)
	end
	local finalRate, finalWood, finalAxe, finalLabel = bestRate(owned)
	if not events.thousand then
		local need = math.max(0, 1000 - earned)
		events.thousand = t + need / finalRate * 3600
	end
	events.plot = t + math.max(0, A.plotPrice - cash) / finalRate * 3600
	return steps, events, { rate = finalRate, wood = finalWood, axe = finalAxe, label = finalLabel }
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local out = {}
local function line(s: string?)
	table.insert(out, s or "")
end

-- --calibrate <seconds> <wood>=<u³> ...: how long a perfect player would
-- take to cut, drag, haul and sell that much wood with the starter kit
-- (Rusty Axe, or the first axe up the ladder that cuts the wood, and the
-- Rustbucket), divided by how long the playtester took (first chop to last
-- sale). MilestoneService's stopwatch prints the line in Studio.
if process.args[1] == "--calibrate" then
	local usage = "usage: lune run tools/economy --calibrate <seconds> <wood>=<u3> ..."
	local seconds = tonumber(process.args[2])
	assert(seconds and seconds > 0, usage)
	local idealSeconds, volumes, total = 0, {}, 0
	for i = 3, #process.args do
		local woodId, amount = string.match(process.args[i], "^(%w+)=(%d+)$")
		local wood = if woodId then WoodData.Get(woodId) else nil
		assert(wood and wood.v2, "not a <wood>=<u3> pair: " .. process.args[i] .. "\n" .. usage)
		local owned = { Rustbucket = true }
		local secs = nil
		for _, axe in ipairs(AXES) do
			owned[axe.id] = true
			local tool = bestAxeFor(owned, wood)
			secs = if tool then loadCycle(tool, wood, owned) else nil
			if secs then
				break
			end
		end
		assert(secs, "no axe and the Rustbucket can fetch " .. woodId)
		local cap = haulFor(BiomeData.Get(wood.biome), owned)
		idealSeconds += tonumber(amount) / cap * secs
		volumes[woodId] = tonumber(amount)
		total += tonumber(amount)
	end
	assert(total > 0, usage)
	local measured = idealSeconds / seconds
	if measured > 1 then
		print(
			string.format(
				"Warning: you beat the ideal model (%.2f). Its assumptions (walk and drag distances, cut times) are too slow; review them in tools/economy.luau. Saving 1.0.",
				measured
			)
		)
		measured = 1
	end
	measured = math.floor(measured * 100 + 0.5) / 100
	print(string.format("EFFICIENCY %.2f -> %.2f (saved to %s)", EFFICIENCY, measured, CALIBRATION_FILE))
	calibration = { efficiency = measured, seconds = seconds, volumes = volumes, loop = 2, date = os.date("%Y-%m-%d") }
	fs.writeFile(CALIBRATION_FILE, serde.encode("json", calibration, true) .. "\n")
	EFFICIENCY = measured
end

local steps, events, final = simulate()

line("# Economy report, v2 core loop")
line()
line(
	"_Generated by `lune run tools/economy` from WoodData (v2 rows and shapes), ItemCatalog (v2 stats), BiomeData, GameConfig and the trees Shared/TreeGen builds. Don't edit by hand: change the data or the assumptions in `tools/economy.luau`, then re-run. The live loop since the M1.9 flip (V2_PLAN.md §17); the v1 loop's model is ECONOMY_V1.md._"
)
line()
line(
	string.format(
		'**Model, not measurement.** Trees always there, nobody competing. "Real player" = the ideal model × EFFICIENCY (%.2f), %s. Truck beds are TruckLayout\'s, as the game builds them.',
		EFFICIENCY,
		if calibration then "from tools/calibration.json" else "a guess until a playtest calibrates it"
	)
)
line()
line(
	"Planks: a sawmill mills the part of a tree it can take (trunk and limbs no thicker than its maxWidth, bucked to its maxLength) when that pays more per hour than selling the logs. Extra time is the blade plus `millFeedSec` a piece and `millDetourSec` a trip. Plank prices are WoodData's. The first sale and `--calibrate` haul logs only."
)
line()
line("## Headline targets (V2_PLAN §17)")
line()
line("| Target | Goal | Model | Verdict |")
line("|---|---|---|---|")
local function target(name, goal, value, lo, hi)
	line(string.format("| %s | %s | %s | %s |", name, goal, duration(value), verdict(value, lo, hi)))
end
target("First sale", "under 3 min", events.firstSale, 0, 180)
target(
	"Steel Axe (" .. money(ItemCatalog.GetAxe("SteelAxe").v2.price) .. ")",
	"5-8 min",
	events.SteelAxe or math.huge,
	300,
	480
)
target("First $1k earned", "15-20 min", events.thousand, 900, 1200)
target("Cobalt Axe ($2,040)", "about 1 h", events.CobaltAxe or math.huge, 2700, 4500)
target("Full plot ($900,100)", "20-40 h", events.plot, 72000, 144000)
line()
line(
	string.format(
		"End of the buying path: %s/h on %s with the %s and the %s.",
		money(final.rate),
		if final.wood then final.wood.displayName else "nothing",
		if final.axe then final.axe.displayName else "-",
		final.label
	)
)
line()

line("## Tree volumes (TreeGen, mean of " .. A.seeds .. " seeds)")
line()
line("u³ = (" .. U .. " studs)³. Sizes roll small / normal / large at 25 / 50 / 25%.")
line()
line(
	"| Wood | Small u³ | Normal u³ | Large u³ | Mean u³ | Trunk share | Elder u³ | Height (normal) | Sections | Main limbs |"
)
line("|---|---|---|---|---|---|---|---|---|---|")
for _, wood in ipairs(WOODS) do
	local r = TREES[wood.id]
	line(
		string.format(
			"| %s | %.1f | %.1f | %.1f | %.1f | %.0f%% | %.1f | %.1f | %.1f | %.1f |",
			wood.displayName,
			r[TreeGen.SizeLo].volume,
			r[1].volume,
			r[TreeGen.SizeHi].volume,
			r.mean.volume,
			r.mean.trunk / r.mean.volume * 100,
			r.elder.volume,
			r[1].height,
			r.mean.sections,
			r.mean.limbs
		)
	)
end
line()

line("## $ per mature tree, logs / planks")
line()
line("Mean volume × the v2 price per u³ (the figured-wood bonus left out). The plan's column is §17's estimate.")
line()
line("| Wood | Log $/u³ | Plank $/u³ | $ / tree as logs | $ / tree as planks | Plan's estimate |")
line("|---|---|---|---|---|---|")
for _, wood in ipairs(WOODS) do
	local v = TREES[wood.id].mean.volume
	local plan = PLAN_PER_TREE[wood.id]
	line(
		string.format(
			"| %s | %s | %s | %s | %s | %s / %s |",
			wood.displayName,
			tostring(wood.v2.logPrice),
			tostring(wood.v2.plankPrice),
			money(v * wood.v2.logPrice),
			money(v * wood.v2.plankPrice),
			money(plan[1]),
			money(plan[2])
		)
	)
end
line()

line("## Hits to cut a mature trunk at its base")
line()
line(
	"`ceil(hardness × (t / "
		.. U
		.. ")² / damage)`, t the shape's trunkThickness (V2_PLAN §2c; SectionLogic.spec pins it)."
)
line()
local header = { "| Axe |" }
local rule = { "|---|" }
for _, wood in ipairs(WOODS) do
	table.insert(header, string.format(" %s %.1f |", wood.displayName, wood.v2.shape.trunkThickness))
	table.insert(rule, "---|")
end
line(table.concat(header))
line(table.concat(rule))
for _, axe in ipairs(AXES) do
	local row = { "| " .. axe.displayName .. " |" }
	for _, wood in ipairs(WOODS) do
		local damage = ItemCatalog.AxeStats(axe, wood.id)
		local h = SectionLogic.HitsToCut(wood.v2.hardness, wood.v2.shape.trunkThickness, damage or 0)
		local vs = axe.v2 and axe.v2.vs and axe.v2.vs[wood.id]
		table.insert(
			row,
			string.format(" %s%s |", if h == math.huge then "-" else tostring(h), if vs then " ★" else "")
		)
	end
	line(table.concat(row))
end
line()
line("★ the axe's specialist stats against that wood.")
line()

line("## Beds")
line()
line(
	string.format(
		"u³ a trip = length × width × (walls + %d studs piled) × %.1f packing / u³ (§17).",
		TruckLayout.BedPileOver,
		TruckLayout.BedPacking
	)
)
line()
line("| Vehicle | Bed (studs) | u³ a trip | Oak $ a trip | v2 price |")
line("|---|---|---|---|---|")
local vehicles = {}
for id in pairs(BEDS) do
	table.insert(vehicles, id)
end
table.sort(vehicles, function(a, b)
	return bedU3(a) < bedU3(b)
end)
for _, id in ipairs(vehicles) do
	local item = ItemCatalog.Trucks[id] or ItemCatalog.Trailers[id]
	local b = BEDS[id]
	line(
		string.format(
			"| %s | %s | %.1f | %s | %s |",
			if item then item.displayName else id,
			if b[1] > 0 then string.format("%g × %g, walls %g", b[1], b[2], b[3]) else "rack only",
			bedU3(id),
			money(bedU3(id) * WoodData.Get("oak").v2.logPrice),
			if item then money(priceOf(item)) else "-"
		)
	)
end
line()

line("## The buying path")
line()
line("Each step buys what pays for itself fastest (axes in ladder order). $/h is a real player's at their best wood.")
line()
line("| At | Buys | Price | $/h before | $/h after | Then cuts |")
line("|---|---|---|---|---|---|")
for _, s in ipairs(steps) do
	line(
		string.format(
			"| %s | %s | %s | %s | %s | %s (%s) |",
			duration(s.at),
			s.item.displayName,
			money(s.price),
			money(s.before),
			money(s.after),
			if s.wood then s.wood.displayName else "-",
			if s.axe then s.axe.displayName else "-"
		)
	)
end
line()

line("## Supply: how many players a biome feeds")
line()
line(
	"Trees regrow in respawnSec + growSec (stump, then sapling to mature). A real player with the starter kit (Rusty Axe, Rustbucket) cuts the trees a column shows; blank where that kit can't work the wood."
)
line()
line(
	"| Biome | Wood | Trees | Regrow | Trees an hour | Real players fed (starter kit) | $/h cap a player (shared by "
		.. A.sharing
		.. ") |"
)
line("|---|---|---|---|---|---|---|")
for _, biome in ipairs(BiomeData.All()) do
	for woodId, count in pairs(biome.trees or {}) do
		local wood = WoodData.Get(woodId)
		local regrow = wood.respawnSec + wood.v2.growSec
		local perHour = regrowPerHour(wood)
		-- A starter-kit player's trees an hour on this wood.
		local owned = { RustyAxe = true, Rustbucket = true }
		local secs = loadCycle(ItemCatalog.GetAxe("RustyAxe"), wood, owned)
		local need = if secs then bedU3("Rustbucket") / TREES[wood.id].mean.volume / secs * 3600 * EFFICIENCY else 0
		line(
			string.format(
				"| %s | %s | %d | %s | %.0f | %s | %s |",
				biome.displayName,
				wood.displayName,
				count,
				duration(regrow),
				perHour,
				if need > 0 then string.format("%.0f", perHour / need) else "-",
				money(supplyRate(wood))
			)
		)
	end
end
line()

line("## Lux Axe (Robux)")
line()
line(
	"Not on the cash ladder and not in the buying path above. A game pass (StoreData LuxAxe). Stats sit just above the Inferno Axe's main row and below the Starfall Axe. Wood whose final chop was this axe sells for "
		.. string.format("%d%%", math.floor((GameConfig.LuxSellBonus - 1) * 100 + 0.5))
		.. " more (GameConfig.LuxSellBonus), once, on the piece, before 2x Cash."
)
line()
local lux = ItemCatalog.GetAxe("LuxAxe")
local fire = ItemCatalog.GetAxe("InfernoAxe")
local top = ItemCatalog.GetAxe("StarfallAxe")
if lux and lux.v2 and fire and fire.v2 and top and top.v2 then
	line("| Axe | v2 damage | range | cooldown | v1 damage |")
	line("|---|---|---|---|---|")
	for _, axe in ipairs({ fire, lux, top }) do
		local v2 = axe.v2
		line(string.format("| %s | %g | %g | %g | %d |", axe.displayName, v2.damage, v2.range, v2.cooldown, axe.damage))
	end
	line()
end

line("## Assumptions")
line()
local keys = {}
for k in pairs(A) do
	table.insert(keys, k)
end
table.sort(keys)
for _, k in ipairs(keys) do
	local v = A[k]
	line(string.format("- `%s` = %s", k, if type(v) == "number" then string.format("%g", v) else tostring(v)))
end
line()

local report = table.concat(out, "\n")
if process.args[1] == "--check" then
	local current = if fs.isFile("ECONOMY.md") then fs.readFile("ECONOMY.md") else ""
	if current ~= report then
		print("ECONOMY.md is out of date: run `lune run tools/economy` and commit the result.")
		process.exit(1)
	end
	print("ECONOMY.md is up to date.")
else
	fs.writeFile("ECONOMY.md", report)
	print("Wrote ECONOMY.md")
	for _, l in ipairs(out) do
		if
			string.find(l, "^| First sale")
			or string.find(l, "^| Steel")
			or string.find(l, "^| First")
			or string.find(l, "^| Cobalt")
			or string.find(l, "^| Full")
		then
			print(l)
		end
	end
end
