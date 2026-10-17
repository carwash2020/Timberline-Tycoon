--!nocheck
-- Overlap report (WORLD-SPREAD): does anything on the map share space with
-- anything else? Read-only: it prints every hit with ids and coordinates and
-- changes nothing. Run from the repo root:   lune run tools/overlap_report
-- (Shared/World/Clearance does the geometry; tests/Overlap.spec.luau will pin
-- the same pairs once they are fixed.)
--
-- Shapes: a tree is a disc (trunk radius from its wood's trunkThickness plus
-- 1.0; its crown radius is a second disc for the building rule); a boulder is
-- size * 0.86; a cluster rock size * 0.5 (WorldPlan.ClusterFootprint); a
-- scenery piece its own radius; a building a TownTreeData.Buildings rectangle
-- (the same list TreeFill keeps trees out of); a prop its world bounding box
-- from the real model (BuildingArt.Prop, placed at its CFrame: axis-aligned,
-- so a turned prop reads a little larger than it is); a plot pad the biggest
-- tier's square. Props are shrunk 0.05 studs so two props that only touch
-- do not count. Props are 2D here, plus a height check for prop against prop.
--
-- Rules (ruling 6): trunk disc clears a boulder by 2; a trunk centre is 4
-- outside a building and its crown may not enter the building grown by 2; tree
-- to prop 2; a tree to a plot pad keeps TreeFill's PLOT_GAP (12); a tree may
-- not overlap a cluster rock or a scenery piece; props may not overlap
-- buildings or each other.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/overlap_report")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WorldPlan = modules:shared("World/WorldPlan")
local Clearance = modules:shared("World/Clearance")
local TownTreeData = modules:shared("TownTreeData")
local BuildingArt = modules:shared("Art/BuildingArt")
local PlotData = modules:shared("PlotData")
local WoodData = modules:shared("WoodData")

local FIRST = WorldPlan.FirstTreeCount()
local CROWN = { cherry = 11.3, willow = 9.6 }
local CROWN_DEFAULT = 7

local function trunkRadius(woodId: string): number
	local wood = WoodData.Get(woodId)
	local thickness = if wood and wood.v2 then wood.v2.shape.trunkThickness else 1.6
	return thickness / 2 + 1.0
end

local grid = Clearance.NewGrid()
local function fmt(e): string
	local s = e.shape
	return string.format("%s (%.1f, %.1f)", e.id, (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2)
end

-- Trees. The id says which list and index, so a hit can be found again.
local treeCount = 0
local function addTrees(name: string, list: any, offset: number?)
	for i, spot in ipairs(list) do
		local p = spot.position
		local wood = spot.woodId or "palmwood"
		local tag = { wood = wood }
		Clearance.Add(
			grid,
			string.format("%s#%d %s", name, i + (offset or 0), wood),
			"tree",
			Clearance.Disc(p.X, p.Z, trunkRadius(wood)),
			tag
		)
		treeCount += 1
	end
end
addTrees("trees", WorldPlan.Trees())
addTrees("strip", WorldPlan.StripTrees())
addTrees("palms", WorldPlan.FerryPalms())
addTrees("lantern", WorldPlan.Lanternwood())
addTrees("region", WorldPlan.RegionTrees())
addTrees("reach", WorldPlan.ReachTrees())
addTrees("added", WorldPlan.AddedTrees())
_ = FIRST

-- Boulders, clusters, scenery.
local rocks = 0
for i, b in ipairs(WorldPlan.Boulders()) do
	Clearance.Add(grid, "boulder#" .. i, "boulder", Clearance.Disc(b.position.X, b.position.Z, b.size * 0.86))
	rocks += 1
end
for i, b in ipairs(WorldPlan.MeadowBoulders()) do
	Clearance.Add(grid, "meadowBoulder#" .. i, "boulder", Clearance.Disc(b.position.X, b.position.Z, b.size * 0.86))
	rocks += 1
end
local clusterRocks = 0
for i, cluster in ipairs(WorldPlan.BoulderClusters()) do
	for j, rock in ipairs(cluster.rocks) do
		Clearance.Add(
			grid,
			string.format("cluster#%d.%d", i, j),
			"cluster",
			Clearance.Disc(rock.position.X, rock.position.Z, rock.size * 0.5)
		)
		clusterRocks += 1
	end
end
local sceneryCount = 0
for i, spot in ipairs(WorldPlan.Scenery()) do
	Clearance.Add(
		grid,
		string.format("scenery#%d %s", i, spot.kind),
		"scenery",
		Clearance.Disc(spot.center.X, spot.center.Z, spot.radius)
	)
	sceneryCount += 1
end

-- Buildings.
for _, r in ipairs(TownTreeData.Buildings) do
	Clearance.Add(grid, "building " .. r.name, "building", Clearance.Rect(r.x0, r.z0, r.x1, r.z1))
end

-- Props, from the real models.
local town = WorldPlan.Town()
local propCount = 0
for i, p in ipairs(town.props) do
	local model = BuildingArt.Prop(p.name, p.seed)
	model:PivotTo(p.cframe)
	local cf, size = model:GetBoundingBox()
	local x, z = cf.Position.X, cf.Position.Z
	local hx, hz = size.X / 2 - 0.05, size.Z / 2 - 0.05
	Clearance.Add(
		grid,
		string.format("prop#%d %s", i, p.name),
		"prop",
		Clearance.Rect(x - hx, z - hz, x + hx, z + hz),
		{ y0 = cf.Position.Y - size.Y / 2, y1 = cf.Position.Y + size.Y / 2 }
	)
	propCount += 1
end

-- Plot pads.
local half = PlotData.Tiers[#PlotData.Tiers].size / 2
for i, slot in ipairs(PlotData.Slots) do
	Clearance.Add(
		grid,
		"plot#" .. i,
		"plot",
		Clearance.Rect(slot.X - half, slot.Y - half, slot.X + half, slot.Y + half)
	)
end

print(
	string.format(
		"Shapes: %d trees, %d boulders, %d cluster rocks, %d scenery, %d buildings, %d props, %d plot pads",
		treeCount,
		rocks,
		clusterRocks,
		sceneryCount,
		#TownTreeData.Buildings,
		propCount,
		#PlotData.Slots
	)
)

local total = 0
local function report(title: string, hits: { any })
	total += #hits
	print("")
	print(string.format("%s: %d", title, #hits))
	table.sort(hits, function(a, b)
		return a.a.id < b.a.id
	end)
	for _, h in ipairs(hits) do
		print(string.format("  %s  vs  %s  (gap %.2f)", fmt(h.a), fmt(h.b), h.gap))
	end
end

report("tree trunk vs boulder (needs 2 studs between edges)", Clearance.Hits(grid, "tree", "boulder", 2))
report("tree trunk vs cluster rock (no overlap)", Clearance.Hits(grid, "tree", "cluster", 0.0001))
report("tree trunk vs scenery piece (no overlap)", Clearance.Hits(grid, "tree", "scenery", 0.0001))
report("tree trunk vs prop (needs 2 studs)", Clearance.Hits(grid, "tree", "prop", 2))
report("tree trunk vs plot pad (TreeFill PLOT_GAP 12)", Clearance.Hits(grid, "tree", "plot", 12))

-- Trees against buildings: the trunk centre 4 outside, the crown not inside the building grown by 2.
local buildingTrunk, buildingCrown = {}, {}
for _, b in ipairs(grid.all) do
	if b.kind == "building" then
		for _, t in ipairs(Clearance.Near(grid, Clearance.Grow(b.shape, 14), 0, "tree")) do
			local s = t.shape
			local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
			local centre = Clearance.Disc(cx, cz, 0)
			if Clearance.Closer(centre, b.shape, 4) then
				table.insert(buildingTrunk, { a = t, b = b, gap = Clearance.Distance(centre, b.shape) })
			end
			local crown = Clearance.Disc(cx, cz, CROWN[t.tag.wood] or CROWN_DEFAULT)
			if Clearance.Distance(crown, Clearance.Grow(b.shape, 2)) <= 0 then
				table.insert(buildingCrown, { a = t, b = b, gap = Clearance.Distance(crown, b.shape) })
			end
		end
	end
end
report("tree trunk centre within 4 studs of a building", buildingTrunk)
report("tree crown (cherry 11.3, willow 9.6, others 7) inside a building grown by 2", buildingCrown)

report("prop vs building", Clearance.Hits(grid, "prop", "building", 0.0001))
report(
	"prop vs prop (footprints overlap by more than 0.05 on the ground and in height)",
	Clearance.Hits(grid, "prop", "prop", 0.0001, function(a, b)
		local ta, tb = a.tag, b.tag
		return math.min(ta.y1, tb.y1) - math.max(ta.y0, tb.y0) <= 0.05
	end)
)
report(
	"tree trunk vs tree trunk closer than 2 studs (should be none; TREE_GAP is 10)",
	Clearance.Hits(grid, "tree", "tree", 2)
)
print("")
print(string.format("Total hits: %d", total))
