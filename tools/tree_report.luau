--!nocheck
-- Tree report (WORLD-SPREAD, T349/T356): how the trees stand on the map today.
-- Read-only: it changes nothing and fails nothing. Run from the repo root:
--   lune run tools/tree_report            the whole report
--   lune run tools/tree_report --exempt   only the fixed-only cells over 25
--
-- The count (one definition for every number below, and for "total at least
-- main"): every ground tree of WorldPlan.Trees (which already holds the forest's
-- ForestTrees) + StripTrees + FerryPalms + Lanternwood + RegionTrees +
-- ReachTrees + AddedTrees. The Sky's Lumenwood stands 650 studs up, so it is
-- listed apart and never counts toward a ground cell.
--
-- Fixed (never thinned or moved): the first 331 (tutorial oaks, the town grove),
-- every BiomeData supply tree (biome starter/hills/snow/volcano/grove, and the
-- Bayou and Mesa region trees), the town and plot rings, the added trees (their
-- counts are pinned), the strip, palms, Lanternwood and the Reach.
-- Movable: the wild trees from the country stands (zone "stand"), the forest
-- ring ("forest"), the 30 wild clumps ("wild") and the grove's wild clumps.
--
-- Cells: 100x100 for density, 200x200 for empties. A 200 cell is land when at
-- least 8 of its 25 sample points are above the sea; the town flat zone, plots,
-- roads, gates, water and the Sky forge are the spec's exemptions and are only
-- listed here, not removed.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/tree_report")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WorldPlan = modules:shared("World/WorldPlan")
local WorldLayout = modules:shared("World/WorldLayout")
local TreeSpread = modules:shared("World/TreeSpread")
local GrowLogic = modules:shared("GrowLogic")
local TerrainGen = modules:shared("World/TerrainGen")
local BiomeData = modules:shared("BiomeData")

local ONLY_EXEMPT = false
local ONLY_SKIP = false
for _, a in ipairs(process.args) do
	if a == "--exempt" then
		ONLY_EXEMPT = true
	elseif a == "--skip" then
		ONLY_SKIP = true
	end
end

local FIRST = WorldPlan.FirstTreeCount()
local EXTENT = 1200
local CAP = 25

---------------------------------------------------------------------------
-- The trees
---------------------------------------------------------------------------

type Tree = { x: number, z: number, wood: string, zone: string, source: string, fixed: boolean }
local trees: { Tree } = {}

local function zonePrefix(spot): string
	local id = if spot.zone then spot.zone.id else "none"
	return (string.match(id, "^[^:]*"))
end

local SUPPLY = { starter = true, hills = true, snow = true, volcano = true, grove = true }

local ground = WorldPlan.Trees()
for i, spot in ipairs(ground) do
	local prefix = zonePrefix(spot)
	local fixed = i <= FIRST or SUPPLY[spot.biome] == true or prefix == "town" or prefix == "plot"
	local source = if i <= FIRST then "first" elseif fixed then "supply/town/plot" else "wild:" .. prefix
	table.insert(trees, {
		x = spot.position.X,
		z = spot.position.Z,
		wood = spot.woodId,
		zone = "?",
		source = source,
		fixed = fixed,
	})
end
local function addList(name: string, list: any)
	for _, spot in ipairs(list) do
		table.insert(trees, {
			x = spot.position.X,
			z = spot.position.Z,
			wood = spot.woodId or "palm",
			zone = "?",
			source = name,
			fixed = true,
		})
	end
end
addList("strip", WorldPlan.StripTrees())
addList("ferry palms", WorldPlan.FerryPalms())
addList("lanternwood", WorldPlan.Lanternwood())
addList("region", WorldPlan.RegionTrees())
addList("reach", WorldPlan.ReachTrees())
addList("added", WorldPlan.AddedTrees())

-- The thinning plan (TreeSpread.PlanSkip) over the same trees.
local TreeSpreadItems = modules:shared("World/TreeSpreadItems")
local planItems, planObstacles = TreeSpreadItems.Build(WorldPlan)
local skipPlan = TreeSpread.PlanSkip(planItems, planObstacles)

if ONLY_SKIP then
	print("TreeSpreadData.Skipped = {")
	for _, index in ipairs(skipPlan) do
		local tr = trees[index]
		print(string.format("\t{ index = %d, x = %.2f, z = %.2f },", index, tr.x, tr.z))
	end
	print("} :: { Entry }")
	return
end

-- From here on the report describes the map as planted: thinned trees are out,
-- and the oak clumps by the spawn and the refill rows are in.
do
	local kept = {}
	for i, tr in ipairs(trees) do
		local isTrees = i <= #ground
		if not (isTrees and TreeSpread.Skipped(tr.x, tr.z)) then
			table.insert(kept, tr)
		end
	end
	trees = kept
end
addList("near grove", WorldPlan.NearGrove())
addList("spread", WorldPlan.SpreadTrees())

local sky = WorldPlan.Sky()
local skyCount = if sky then #sky.lumenwood else 0

---------------------------------------------------------------------------
-- Zones: nearest area by edge distance
---------------------------------------------------------------------------

type Area = { id: string, x: number, z: number, radius: number }
local areas: { Area } = {}
for _, biome in ipairs(BiomeData.All()) do
	local area = biome.area
	if area and biome.id ~= "sky" then
		table.insert(areas, { id = biome.id, x = area.x, z = area.z, radius = area.radius })
	end
end
for _, region in ipairs(WorldLayout.ReservedRegions) do
	local id = if region.id == "redmesa" then "mesa" else region.id
	table.insert(areas, { id = id, x = region.x, z = region.z, radius = region.radius })
end

local function zoneOf(x: number, z: number): string
	local best, bestD = "meadow", math.huge
	for _, a in ipairs(areas) do
		local d = math.sqrt((x - a.x) ^ 2 + (z - a.z) ^ 2) - a.radius
		if d < bestD then
			best, bestD = a.id, d
		end
	end
	if bestD > 60 then
		return "meadow"
	end
	return best
end
for _, tr in ipairs(trees) do
	tr.zone = zoneOf(tr.x, tr.z)
end

---------------------------------------------------------------------------
-- Cells
---------------------------------------------------------------------------

local function cellsOf(size: number, filter: ((Tree) -> boolean)?): { [string]: number }
	local out: { [string]: number } = {}
	for _, tr in ipairs(trees) do
		if not filter or filter(tr) then
			local key = string.format("%d,%d", math.floor(tr.x / size), math.floor(tr.z / size))
			out[key] = (out[key] or 0) + 1
		end
	end
	return out
end

local function keyParts(key: string): (number, number)
	local a, b = string.match(key, "^(-?%d+),(-?%d+)$")
	return tonumber(a) :: number, tonumber(b) :: number
end

local all100 = cellsOf(100)
local fixed100 = cellsOf(100, function(tr)
	return tr.fixed
end)

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------

local function line(...)
	print(string.format(...))
end

local function listFixedOnly()
	local over: { { key: string, n: number, total: number } } = {}
	for key, n in pairs(fixed100) do
		if n > CAP then
			table.insert(over, { key = key, n = n, total = all100[key] or n })
		end
	end
	table.sort(over, function(a, b)
		return a.n > b.n
	end)
	line("Fixed-only cells over %d (100x100, counting FIXED trees alone): %d", CAP, #over)
	for _, c in ipairs(over) do
		local cx, cz = keyParts(c.key)
		line(
			"  cell x %5d..%5d z %5d..%5d  fixed %2d  all %2d  (%s)",
			cx * 100,
			cx * 100 + 100,
			cz * 100,
			cz * 100 + 100,
			c.n,
			c.total,
			zoneOf(cx * 100 + 50, cz * 100 + 50)
		)
	end
end

if ONLY_EXEMPT then
	listFixedOnly()
	return
end

line("== Tree report (main) ==")
local fixedN, movableN = 0, 0
local bySource: { [string]: number } = {}
for _, tr in ipairs(trees) do
	if tr.fixed then
		fixedN += 1
	else
		movableN += 1
	end
	bySource[tr.source] = (bySource[tr.source] or 0) + 1
end
line(
	"Total ground trees: %d (fixed %d, movable %d). Sky Lumenwood (not counted): %d",
	#trees,
	fixedN,
	movableN,
	skyCount
)
local names: { string } = {}
for name in pairs(bySource) do
	table.insert(names, name)
end
table.sort(names)
for _, name in ipairs(names) do
	line("  %-18s %4d", name, bySource[name])
end

line("")
line("Per zone (nearest area by edge distance; meadow = more than 60 studs off any area):")
line("  %-9s %6s %6s %8s %10s  %s", "zone", "trees", "fixed", "movable", "per 10k sq", "woods")
local zoneRows: { [string]: { n: number, fixed: number, woods: { [string]: number } } } = {}
for _, tr in ipairs(trees) do
	local row = zoneRows[tr.zone]
	if not row then
		row = { n = 0, fixed = 0, woods = {} }
		zoneRows[tr.zone] = row
	end
	row.n += 1
	if tr.fixed then
		row.fixed += 1
	end
	row.woods[tr.wood] = (row.woods[tr.wood] or 0) + 1
end
local areaOf: { [string]: Area } = {}
for _, a in ipairs(areas) do
	areaOf[a.id] = a
end
local zoneNames: { string } = {}
for z in pairs(zoneRows) do
	table.insert(zoneNames, z)
end
table.sort(zoneNames)
for _, z in ipairs(zoneNames) do
	local row = zoneRows[z]
	local a = areaOf[z]
	local density = if a then row.n / (math.pi * a.radius * a.radius) * 10000 else 0
	local woods: { string } = {}
	for w, c in pairs(row.woods) do
		table.insert(woods, string.format("%s %d", w, c))
	end
	table.sort(woods)
	line(
		"  %-9s %6d %6d %8d %10s  %s",
		z,
		row.n,
		row.fixed,
		row.n - row.fixed,
		if a then string.format("%.1f", density) else "-",
		table.concat(woods, ", ")
	)
end

line("")
local peaks: { { key: string, n: number } } = {}
local over20, over25 = 0, 0
for key, n in pairs(all100) do
	table.insert(peaks, { key = key, n = n })
	if n >= 20 then
		over20 += 1
	end
	if n > CAP then
		over25 += 1
	end
end
table.sort(peaks, function(a, b)
	return a.n > b.n
end)
line(
	"100x100 cells: %d hold a tree; %d hold 20 or more; %d hold more than %d. Peak %d.",
	#peaks,
	over20,
	over25,
	CAP,
	peaks[1].n
)
for i = 1, math.min(12, #peaks) do
	local cx, cz = keyParts(peaks[i].key)
	local fixedHere = fixed100[peaks[i].key] or 0
	line(
		"  x %5d z %5d  %2d trees (fixed %2d, movable %2d)  %s",
		cx * 100,
		cz * 100,
		peaks[i].n,
		fixedHere,
		peaks[i].n - fixedHere,
		zoneOf(cx * 100 + 50, cz * 100 + 50)
	)
end
line("")
listFixedOnly()

line("")
local cells200 = cellsOf(200)
local SEA = WorldLayout.SeaLevel
local empty: { string } = {}
local landCells = 0
for cx = -EXTENT / 200, EXTENT / 200 - 1 do
	for cz = -EXTENT / 200, EXTENT / 200 - 1 do
		local land = 0
		for i = 0, 4 do
			for j = 0, 4 do
				local x, z = cx * 200 + 20 + i * 40, cz * 200 + 20 + j * 40
				if TerrainGen.HeightAt(x, z) > SEA + 1 then
					land += 1
				end
			end
		end
		if land >= 8 then
			landCells += 1
			if not cells200[string.format("%d,%d", cx, cz)] then
				table.insert(
					empty,
					string.format(
						"x %5d..%5d z %5d..%5d (%s)",
						cx * 200,
						cx * 200 + 200,
						cz * 200,
						cz * 200 + 200,
						zoneOf(cx * 200 + 100, cz * 200 + 100)
					)
				)
			end
		end
	end
end
line("200x200 land cells: %d; with no tree: %d (the spec's exemptions are not removed here)", landCells, #empty)
for _, e in ipairs(empty) do
	line("  %s", e)
end

line("")
local best, bx, bz = 0, 0, 0
local r2 = 640 * 640
for cx = -EXTENT, EXTENT, 40 do
	for cz = -EXTENT, EXTENT, 40 do
		local n = 0
		for _, tr in ipairs(trees) do
			local dx, dz = tr.x - cx, tr.z - cz
			if dx * dx + dz * dz <= r2 then
				n += 1
			end
		end
		if n > best then
			best, bx, bz = n, cx, cz
		end
	end
end
line("Most trees inside any 640 stud radius (centres on a 40 stud grid): %d at (%d, %d)", best, bx, bz)

local near70 = 0
for _, tr in ipairs(trees) do
	if math.sqrt(tr.x ^ 2 + (tr.z - 40) ^ 2) <= 70 then
		near70 += 1
	end
end
line("Trees within 70 studs of the spawn pad (0, 40): %d  (the first plot pad is measured by the T349 spec)", near70)
