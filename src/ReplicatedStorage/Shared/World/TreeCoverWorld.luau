--!strict
-- TreeCoverWorld: the world as TreeCover sees it, built the same way for
-- tools/tree_cover (which writes TreeSpreadData) and tests/TreeCover.spec
-- (which checks it). Reads the world plan: never run at boot.

local BiomeData = require(script.Parent.Parent.BiomeData)
local GrowLogic = require(script.Parent.Parent.GrowLogic)
local TutorialGrove = require(script.Parent.Parent.TutorialGrove)
local WoodData = require(script.Parent.Parent.WoodData)
local TerrainGen = require(script.Parent.TerrainGen)
local TreeCover = require(script.Parent.TreeCover)
local TreeFill = require(script.Parent.TreeFill)
local TreeSpread = require(script.Parent.TreeSpread)
local TreeSpreadItems = require(script.Parent.TreeSpreadItems)
local WorldLayout = require(script.Parent.WorldLayout)

local TreeCoverWorld = {}

local SUPPLY: { [string]: boolean } = { starter = true, hills = true, snow = true, volcano = true, grove = true }

-- A trunk's radius: half the base section's thickness, as the tree stands at this spot.
local radii: { [string]: number } = {}
function TreeCoverWorld.TrunkRadius(woodId: string, x: number, z: number): number
	local def = WoodData.Get(woodId)
	if not def then
		return 1
	end
	local key = string.format("%s %.2f %.2f", woodId, x, z)
	local hit = radii[key]
	if hit then
		return hit
	end
	local boot = GrowLogic.BootTree(def, Vector3.new(x, 0, z))
	local r = boot.skel.sections[1].thickness / 2
	radii[key] = r
	return r
end

-- The size class ("small", "normal", "large") of a tree planted at (x, z).
function TreeCoverWorld.SizeAt(x: number, z: number): string
	local _, name = GrowLogic.Site(Vector3.new(x, 0, z))
	return name
end

-- Every road's centreline and half width (the plot spurs are the plots' own).
local function roadLines(): ({ { Vector2 } }, { number })
	local lines: { { Vector2 } } = {}
	local halves: { number } = {}
	for _, road in ipairs(WorldLayout.Roads) do
		if road.name ~= "PlotSpur" then
			table.insert(lines, road.points)
			table.insert(halves, road.width / 2)
		end
	end
	return lines, halves
end

-- Dry ground a new trunk may stand on, as TreeFill plants everywhere (the
-- regions keep off their own builds too).
local function ground(x: number, z: number): boolean
	if TerrainGen.HeightAt(x, z) <= WorldLayout.SeaLevel + 1 then
		return false
	end
	if TerrainGen.WaterLevelAt(x, z) ~= nil then
		return false
	end
	if WorldLayout.RegionBuildBlocked(x, z) then
		return false
	end
	-- The square grew past ±1000 so Frostpeak's rim and Lantern Isle fit.
	-- That new band is not meadow to plant. A biome or a region that
	-- already stands there still is.
	if math.abs(x) > 1000 or math.abs(z) > 1000 then
		if BiomeData.At(x, z) == nil and BiomeData.RegionAt(x, z) == nil then
			return false
		end
	end
	return TreeFill.Ground(x, z)
end

TreeCoverWorld.Ground = ground

-- The Env for the planner and the specs. `total` is the tree count that stands.
function TreeCoverWorld.Env(total: number, pause: (() -> ())?, plan: any?): TreeCover.Env
	local lines, halves = roadLines()
	local blocked: ((x: number, z: number, r: number) -> boolean)? = nil
	if plan then
		-- Boulders (2 studs between edges), cluster rocks and scenery pieces, binned by 32 studs.
		local _, obstacles = TreeSpreadItems.Build(plan)
		local bins: { [number]: { TreeSpread.Obstacle } } = {}
		for _, o: TreeSpread.Obstacle in ipairs(obstacles) do
			local reach = o.r + o.gap + 2
			for bx = math.floor((o.x - reach) / 32), math.floor((o.x + reach) / 32) do
				for bz = math.floor((o.z - reach) / 32), math.floor((o.z + reach) / 32) do
					local key = (bx + 4096) * 8192 + (bz + 4096)
					bins[key] = bins[key] or {}
					table.insert(bins[key], o)
				end
			end
		end
		blocked = function(x: number, z: number, r: number): boolean
			for _, o: TreeSpread.Obstacle in
				ipairs(bins[(math.floor(x / 32) + 4096) * 8192 + (math.floor(z / 32) + 4096)] or {})
			do
				local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2)
				if d - o.r - r < o.gap + 0.5 then
					return true
				end
			end
			return false
		end
	end
	return {
		blocked = blocked,
		ground = ground,
		roadClear = TerrainGen.RoadClearance,
		roads = lines,
		roadHalf = halves,
		trunkRadius = TreeCoverWorld.TrunkRadius,
		sizeAt = TreeCoverWorld.SizeAt,
		total = total,
		pause = pause,
	}
end

-- The trees standing before the plan: every list, the thinned ones out
-- (PlanSkip only, never the relocated), no cover trees. `plan` is WorldPlan.
function TreeCoverWorld.BaseItems(plan: any): { TreeCover.Tree }
	local first = plan.FirstTreeCount()
	local items: { TreeCover.Tree } = {}
	for i, spot in ipairs(plan.Trees()) do
		local p = spot.position
		if not TreeSpread.SkippedBase(p.X, p.Z) then
			local prefix = if spot.zone then string.match(spot.zone.id, "^[^:]*") else "none"
			local fixed = i <= first or SUPPLY[spot.biome] == true or prefix == "town" or prefix == "plot"
			local anchor = false
			if not fixed then
				anchor = TreeCoverWorld.SizeAt(p.X, p.Z) == "large"
			end
			table.insert(items, {
				x = p.X,
				z = p.Z,
				r = TreeCoverWorld.TrunkRadius(spot.woodId, p.X, p.Z),
				wood = spot.woodId,
				index = i,
				movable = not fixed,
				anchor = anchor,
			})
		end
	end
	local function other(list: { any })
		for _, spot in ipairs(list) do
			local p = spot.position
			if not TreeSpread.SkippedBase(p.X, p.Z) then
				local wood = spot.woodId or "palmwood"
				table.insert(items, { x = p.X, z = p.Z, r = TreeCoverWorld.TrunkRadius(wood, p.X, p.Z), wood = wood })
			end
		end
	end
	other(plan.StripTrees())
	other(plan.FerryPalms())
	other(plan.Lanternwood())
	other(plan.ReachTrees())
	other(plan.RegionTrees())
	other(plan.AddedTrees())
	other(plan.NearGrove())
	-- Murph's three oaks (MapBuilder plants them apart from every list).
	for _, spot in ipairs(TutorialGrove.Trees) do
		table.insert(
			items,
			{ x = spot.x, z = spot.z, r = TreeCoverWorld.TrunkRadius("oak", spot.x, spot.z), wood = "oak" }
		)
	end
	return items
end

-- Every tree that stands (thinned and relocated ones out, the cover trees in),
-- as the server plants them.
function TreeCoverWorld.Standing(plan: any): { TreeCover.Tree }
	local out: { TreeCover.Tree } = {}
	local function add(list: { any })
		for _, spot in ipairs(list) do
			local p = spot.position
			if not TreeSpread.Skipped(p.X, p.Z) then
				local wood = spot.woodId or "palmwood"
				table.insert(out, { x = p.X, z = p.Z, r = TreeCoverWorld.TrunkRadius(wood, p.X, p.Z), wood = wood })
			end
		end
	end
	add(plan.Trees())
	add(plan.StripTrees())
	add(plan.FerryPalms())
	add(plan.Lanternwood())
	add(plan.ReachTrees())
	add(plan.RegionTrees())
	add(plan.AddedTrees())
	add(plan.NearGrove())
	add(plan.SpreadTrees())
	for _, spot in ipairs(TutorialGrove.Trees) do
		table.insert(
			out,
			{ x = spot.x, z = spot.z, r = TreeCoverWorld.TrunkRadius("oak", spot.x, spot.z), wood = "oak" }
		)
	end
	return out
end

return TreeCoverWorld
