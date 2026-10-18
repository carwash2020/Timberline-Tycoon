--!nocheck
-- Spread supply (WORLD-SPREAD, T366): thin the dense supply-tree cells by moving
-- trees inside their own zone. Read-only: prints the capacity table and the
-- moves; `--data` prints the TreeSpreadData.Moved lines. Run from the repo root:
--   lune run tools/spread_supply          the table and the moves
--   lune run tools/spread_supply --data   the data lines only
--
-- Rule (one deterministic pure function of tree index, zone and fixed ordering):
--   * cells are 100x100, counted with every tree that stands (all lists, the
--     thinned ones out); a cell over 22 gives up trees (over 24 for the cells
--     that hold 27) in order of x, then z;
--   * only supply trees after the first 331 (biome starter, hills, snow, volcano,
--     grove, in their own zone) move; never a large-class tree (a clump anchor),
--     Murph's oaks, the NearGrove trees or any first tree; interior trees go
--     first so the cell's edge stays thick;
--   * a moved tree keeps its index, wood, biome, zone and size class, and lands
--     inside its own zone's disc (radius minus 6, as TreeFill plants), on a 4
--     stud grid, on TreeFill.Ground and Clear, 10 studs from every tree, 2
--     studs off a rock, in a destination cell that finishes at 22 or fewer;
--   * clumps of up to 5 around a destination point, 12 studs across.
-- A tree that finds no legal spot stays where it is and is counted as unplaced.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/spread_supply")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WorldPlan = modules:shared("World/WorldPlan")
local TreeFill = modules:shared("World/TreeFill")
local BiomeData = modules:shared("BiomeData")
local GrowLogic = modules:shared("GrowLogic")
local TreeSpread = modules:shared("World/TreeSpread")
local TreeSpreadItems = modules:shared("World/TreeSpreadItems")
local Clearance = modules:shared("World/Clearance")

local DATA_ONLY = false
for _, a in ipairs(process.args) do
	if a == "--data" then
		DATA_ONLY = true
	end
end

local FIRST = WorldPlan.FirstTreeCount()
local TARGET, TARGET_27, HARD = 22, 24, 22
local SUPPLY = { starter = true, hills = true, snow = true, volcano = true, grove = true }
local trees = WorldPlan.Trees()

local function cellKey(x: number, z: number): string
	return math.floor(x / 100) .. "," .. math.floor(z / 100)
end

-- Everything that stands now: positions for the gap test, counts per cell.
local taken = {}
local counts = {}
local function stand(x: number, z: number)
	table.insert(taken, roblox.Vector3.new(x, 0, z))
	local k = cellKey(x, z)
	counts[k] = (counts[k] or 0) + 1
end
for _, spot in ipairs(trees) do
	if not TreeSpread.Skipped(spot.position.X, spot.position.Z) then
		stand(spot.position.X, spot.position.Z)
	end
end
for _, list in ipairs({
	WorldPlan.StripTrees(),
	WorldPlan.FerryPalms(),
	WorldPlan.Lanternwood(),
	WorldPlan.RegionTrees(),
	WorldPlan.ReachTrees(),
	WorldPlan.AddedTrees(),
	WorldPlan.NearGrove(),
	WorldPlan.SpreadTrees(),
}) do
	for _, spot in ipairs(list) do
		stand(spot.position.X, spot.position.Z)
	end
end
local TutorialGrove = modules:shared("TutorialGrove")
for _, spot in ipairs(TutorialGrove.Trees) do
	table.insert(taken, roblox.Vector3.new(spot.x, 0, spot.z))
end

-- Rocks and scenery a tree keeps off.
local _, obstacles = TreeSpreadItems.Build(WorldPlan)
local rocks = Clearance.NewGrid()
for _, o in ipairs(obstacles) do
	Clearance.Add(rocks, "o", "obstacle", Clearance.Disc(o.x, o.z, o.r), o.gap)
end
local function offRocks(x: number, z: number): boolean
	local disc = Clearance.Disc(x, z, 1.8)
	for _, e in ipairs(Clearance.Near(rocks, disc, 2, "obstacle")) do
		if Clearance.Closer(disc, e.shape, e.tag :: number) then
			return false
		end
	end
	return true
end

local function class(x: number, z: number): string
	local _, sizeName = GrowLogic.Site(roblox.Vector3.new(x, 0, z))
	return sizeName
end

-- The zones' discs, as TreeFill plants (radius minus 6).
local discs = {}
for id in pairs(SUPPLY) do
	local def = BiomeData.Get(id)
	local a = def and def.area
	if a then
		discs[id] = { x = a.x, z = a.z, r = a.radius - 6 }
	end
end

---------------------------------------------------------------------------
-- Capacity of every cell inside each disc (legal extra spots, up to HARD)
---------------------------------------------------------------------------

local function legal(id: string, x: number, z: number, trial: any): boolean
	local d = discs[id]
	return (x - d.x) ^ 2 + (z - d.z) ^ 2 <= d.r * d.r
		and not TreeFill.TakenNearScan(trial, x, z, 10)
		and TreeFill.Ground(x, z)
		and TreeFill.Clear(x, z)
		and offRocks(x, z)
end

local room = {} -- cell key -> spots still allowed (to HARD)
local capacityLines = {}
for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove" }) do
	local d = discs[id]
	table.insert(capacityLines, "== " .. id)
	for cx = math.floor((d.x - d.r) / 100), math.floor((d.x + d.r) / 100) do
		for cz = math.floor((d.z - d.r) / 100), math.floor((d.z + d.r) / 100) do
			local k = cx .. "," .. cz
			local have = counts[k] or 0
			local trial = table.clone(taken)
			local fits = 0
			for x = cx * 100 + 2, cx * 100 + 98, 4 do
				for z = cz * 100 + 2, cz * 100 + 98, 4 do
					if legal(id, x, z, trial) then
						table.insert(trial, roblox.Vector3.new(x, 0, z))
						fits += 1
					end
				end
			end
			local allowed = math.min(fits, math.max(0, HARD - have))
			if fits > 0 or have > 0 then
				table.insert(
					capacityLines,
					string.format(
						"  cell %5d,%5d  have %2d  legal spots %2d  room to %d: %2d",
						cx * 100,
						cz * 100,
						have,
						fits,
						HARD,
						allowed
					)
				)
			end
			room[k] = (room[k] or 0) + allowed
		end
	end
end

---------------------------------------------------------------------------
-- The moves
---------------------------------------------------------------------------

type Move = { index: number, fromX: number, fromZ: number, x: number, z: number, zone: string }
local moves: { Move } = {}
local unplaced = 0
local overCells = {}
for k, n in pairs(counts) do
	if n > TARGET then
		local cx, cz = string.match(k, "^(-?%d+),(-?%d+)$")
		table.insert(overCells, { key = k, cx = tonumber(cx), cz = tonumber(cz), n = n })
	end
end
table.sort(overCells, function(a, b)
	if a.cx ~= b.cx then
		return a.cx < b.cx
	end
	return a.cz < b.cz
end)

local movedAway = {}
local centres = {} -- destination clump centres
local report = {}
for _, cell in ipairs(overCells) do
	-- Supply trees of this cell that may move: index after the first 331, the supply biome, not an anchor.
	local pool = {}
	for index, spot in ipairs(trees) do
		local p = spot.position
		if
			index > FIRST
			and SUPPLY[spot.biome]
			and not TreeSpread.Skipped(p.X, p.Z)
			and cellKey(p.X, p.Z) == cell.key
			and class(p.X, p.Z) ~= "large"
		then
			local x0, z0 = cell.cx * 100, cell.cz * 100
			local edge = math.min(p.X - x0, x0 + 100 - p.X, p.Z - z0, z0 + 100 - p.Z)
			table.insert(pool, { index = index, spot = spot, edge = edge })
		end
	end
	table.sort(pool, function(a, b)
		if a.edge ~= b.edge then
			return a.edge > b.edge -- interior first
		end
		return a.index < b.index
	end)
	local limit = if cell.n == 27 then TARGET_27 else TARGET
	local need = cell.n - limit
	local done = 0
	for _, item in ipairs(pool) do
		if done >= need then
			break
		end
		local spot = item.spot
		local id = spot.biome
		local from = spot.position
		local want = class(from.X, from.Z)
		-- A legal spot of the same class in a cell with room, near the last clump if it has space.
		local best, bestScore, bestKey = nil, math.huge, nil
		local d = discs[id]
		for cx = math.floor((d.x - d.r) / 100), math.floor((d.x + d.r) / 100) do
			for cz = math.floor((d.z - d.r) / 100), math.floor((d.z + d.r) / 100) do
				local k = cx .. "," .. cz
				if k ~= cell.key and (room[k] or 0) > 0 and (counts[k] or 0) < HARD then
					for x = cx * 100 + 2, cx * 100 + 98, 4 do
						for z = cz * 100 + 2, cz * 100 + 98, 4 do
							if legal(id, x, z, taken) and class(x, z) == want then
								-- Prefer a spot beside a clump centre already started (within 12), else 40 or more from every centre.
								local score = 1000
								for _, c in ipairs(centres) do
									local dd = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
									if dd <= 12 and c.n < 5 then
										score = math.min(score, dd)
									elseif dd < 40 and dd > 12 then
										score = score + 500
									end
								end
								score += ((x - d.x) ^ 2 + (z - d.z) ^ 2) / 1e6
								if score < bestScore then
									best, bestScore, bestKey = { x = x, z = z }, score, k
								end
							end
						end
					end
				end
			end
		end
		if best and bestKey then
			table.insert(taken, roblox.Vector3.new(best.x, 0, best.z))
			counts[bestKey] = (counts[bestKey] or 0) + 1
			counts[cell.key] -= 1
			room[bestKey] -= 1
			movedAway[item.index] = true
			local joined = false
			for _, c in ipairs(centres) do
				if math.sqrt((best.x - c.x) ^ 2 + (best.z - c.z) ^ 2) <= 12 and c.n < 5 then
					c.n += 1
					joined = true
					break
				end
			end
			if not joined then
				table.insert(centres, { x = best.x, z = best.z, n = 1 })
			end
			table.insert(
				moves,
				{ index = item.index, fromX = from.X, fromZ = from.Z, x = best.x, z = best.z, zone = id }
			)
			done += 1
		else
			unplaced += 1
		end
	end
	table.insert(
		report,
		string.format(
			"cell %s: %d trees, limit %d, moved %d, unplaced %d, now %d",
			cell.key,
			cell.n,
			limit,
			done,
			math.max(0, need - done),
			counts[cell.key]
		)
	)
end

table.sort(moves, function(a, b)
	return a.index < b.index
end)

if DATA_ONLY then
	print("TreeSpreadData.Moved = {")
	for _, m in ipairs(moves) do
		print(
			string.format(
				"\t{ index = %d, fromX = %.2f, fromZ = %.2f, x = %.2f, z = %.2f },",
				m.index,
				m.fromX,
				m.fromZ,
				m.x,
				m.z
			)
		)
	end
	print("} :: { Move }")
	return
end

print("Capacity inside each zone disc (legal spots on a 4 stud grid, 10 stud gap, ground, rocks; room is up to 22):")
for _, line in ipairs(capacityLines) do
	print(line)
end
print("")
print("Cells over 22 (all trees counted):")
for _, line in ipairs(report) do
	print("  " .. line)
end
local far = 0
for _, m in ipairs(moves) do
	far = math.max(far, math.sqrt((m.x - m.fromX) ^ 2 + (m.z - m.fromZ) ^ 2))
end
print(string.format("Moved %d trees, %d could not be placed, largest move %.0f studs", #moves, unplaced, far))
for _, m in ipairs(moves) do
	print(string.format("  index %4d (%s)  (%.1f, %.1f) -> (%.1f, %.1f)", m.index, m.zone, m.fromX, m.fromZ, m.x, m.z))
end
