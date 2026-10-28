--!strict
-- OverlapCheck: does anything on the map share space with anything else?
-- Builds every footprint (trees, boulders, cluster rocks, scenery, buildings,
-- the real parts of the town's buildings, props, plot pads) into a
-- Clearance grid and runs the pair checks. tools/overlap_report prints the
-- hits; tests/Overlap.spec asserts them. Reads the world plan and builds real
-- models: never run at boot.
--
-- Shapes: a tree is a disc (trunk radius from its wood's trunkThickness plus
-- 1.0; its crown radius is a second disc for the building rule); a boulder is
-- size * 0.86; a cluster rock size * 0.5; a scenery piece its own radius; a
-- building a TownTreeData.Buildings outline (for trees) and its real parts as
-- XZ boxes (for props); a prop its world bounding box from the real model
-- (axis-aligned, shrunk 0.05); a plot pad the biggest tier's square.
-- Rules: trunk disc clears a boulder by 2; a trunk centre is 4 outside a
-- building and its crown may not enter the outline grown by 2; tree to prop 2;
-- a trunk centre keeps TreeFill's PLOT_GAP (12) off a plot pad; trees may not
-- overlap cluster rocks or scenery; props may not overlap building parts or
-- each other (and prop against prop also needs a height overlap).

local BuildingArt = require(script.Parent.Parent.Art.BuildingArt)
local ShopPlace = require(script.Parent.Parent.Art.ShopPlace)
local BuiltMoves = require(script.Parent.BuiltMoves)
local TerrainGen = require(script.Parent.TerrainGen)
local Clearance = require(script.Parent.Clearance)
local DealershipLot = require(script.Parent.Parent.Art.DealershipLot)
local Kit = require(script.Parent.Parent.Art.Kit)
local PlotData = require(script.Parent.Parent.PlotData)
local PropArt = require(script.Parent.Parent.Art.PropArt)
local TownTreeData = require(script.Parent.Parent.TownTreeData)
local TreeSpread = require(script.Parent.TreeSpread)
local WoodData = require(script.Parent.Parent.WoodData)

local OverlapCheck = {}

local CROWN: { [string]: number } = { cherry = 11.3, willow = 9.6 }
local CROWN_DEFAULT = 7

local function trunkRadius(woodId: string): number
	local wood = WoodData.Get(woodId)
	local shape = if wood and wood.v2 then wood.v2.shape else nil
	local thickness = if shape then shape.trunkThickness else 1.6
	return thickness / 2 + 1.0
end

export type Result = { title: string, hits: { Clearance.Hit } }

-- The grid for `plan` (WorldPlan), and how many of each shape went in.
function OverlapCheck.Build(plan: any): (Clearance.Grid, { [string]: number })
	local WorldPlan = plan
	local grid = Clearance.NewGrid()

	-- Trees. The id says which list and index, so a hit can be found again.
	local treeCount = 0
	local function addTrees(name: string, list: any, offset: number?)
		for i, spot in ipairs(list) do
			local p = spot.position
			if TreeSpread.Skipped(p.X, p.Z) then
				continue -- thinned: not planted
			end
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
	addTrees("neargrove", WorldPlan.NearGrove())
	addTrees("spread", WorldPlan.SpreadTrees())

	-- Boulders, clusters, scenery.
	local rocks = 0
	for i, b in ipairs(BuiltMoves.Boulders(WorldPlan, TerrainGen)) do
		Clearance.Add(grid, "boulder#" .. i, "boulder", Clearance.Disc(b.position.X, b.position.Z, b.size * 0.86))
		rocks += 1
	end
	for i, b in ipairs(BuiltMoves.MeadowBoulders(WorldPlan, TerrainGen)) do
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
	for i, spot in ipairs(BuiltMoves.Scenery(WorldPlan, TerrainGen)) do
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

	-- The real parts of the town's buildings, as XZ boxes (every part low enough to
	-- matter, as tests/TownTrees.spec reads them): what a prop may not stand in.
	local function addParts(label: string, model: any, cf: CFrame)
		Kit.placeAt(model, cf)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local lo: Vector3? = nil
				local hi: Vector3? = nil
				local h = d.Size / 2
				for _, x in ipairs({ -1, 1 }) do
					for _, y in ipairs({ -1, 1 }) do
						for _, z in ipairs({ -1, 1 }) do
							local w = d.CFrame * Vector3.new(h.X * x, h.Y * y, h.Z * z)
							lo = if lo then lo:Min(w) else w
							hi = if hi then hi:Max(w) else w
						end
					end
				end
				if lo and hi and lo.Y < 6 and hi.Y > 0.3 and hi.X - lo.X > 0.05 and hi.Z - lo.Z > 0.05 then
					Clearance.Add(
						grid,
						string.format("%s/%s", label, d.Name),
						"part",
						Clearance.Rect(lo.X + 0.05, lo.Z + 0.05, hi.X - 0.05, hi.Z - 0.05)
					)
				end
			end
		end
	end
	do
		local town = WorldPlan.Town()
		addParts("sawmill", BuildingArt.Sawmill(), town.sawmill)
		addParts("sell station", BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth), town.sellPad)
		for _, spot in ipairs(town.shops) do
			addParts(spot.kind, BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
		end
		for _, spot in ipairs(town.outlets) do
			if not spot.cloud then
				addParts(spot.kind, ShopPlace.Build(spot.kind, spot.title, spot.accent), spot.cframe)
			end
		end
		for _, spot in ipairs(town.scenes) do
			local model = if spot.kind == "forge" then BuildingArt.SkyForgeCourt() else PropArt.Scene(spot.kind)
			addParts(spot.kind .. " scene", model, spot.cframe)
		end
		addParts("dealership lot", DealershipLot.Build(), town.displayLot)
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

	local counts: { [string]: number } = {}
	for _, e in ipairs(grid.all) do
		counts[e.kind] = (counts[e.kind] or 0) + 1
	end
	return grid, counts
end

-- Every pair check, in order.
function OverlapCheck.Run(grid: Clearance.Grid): { Result }
	local results: { Result } = {}
	local function report(title: string, hits: { Clearance.Hit })
		table.insert(results, { title = title, hits = hits })
	end
	report("tree trunk vs boulder (needs 2 studs between edges)", Clearance.Hits(grid, "tree", "boulder", 2))
	report("tree trunk vs cluster rock (no overlap)", Clearance.Hits(grid, "tree", "cluster", 0.0001))
	report("tree trunk vs scenery piece (no overlap)", Clearance.Hits(grid, "tree", "scenery", 0.0001))
	report("tree trunk vs prop (needs 2 studs)", Clearance.Hits(grid, "tree", "prop", 2))
	do
		-- TreeFill's PLOT_GAP is measured from the trunk's centre.
		local hits = {}
		for _, e in ipairs(grid.all) do
			if e.kind == "tree" then
				local s = e.shape
				local centre = Clearance.Disc((s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2, 0)
				for _, plot in ipairs(Clearance.Near(grid, Clearance.Grow(centre, 12), 0, "plot")) do
					if Clearance.Closer(centre, plot.shape, 12) then
						table.insert(hits, { a = e, b = plot, gap = Clearance.Distance(centre, plot.shape) })
					end
				end
			end
		end
		report("tree trunk centre vs plot pad (TreeFill PLOT_GAP 12)", hits)
	end

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

	report("prop vs building (the real parts, low ones only)", Clearance.Hits(grid, "prop", "part", 0.0001))
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
	return results
end

return OverlapCheck
