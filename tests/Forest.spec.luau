--!nocheck
-- The forest (phase 10, FOR-*): "a forest with the main area open and then
-- the wild landscapes".
--   FOR-01 the band layout (WorldLayout.Forest, WorldLayout.ForestCover):
--          an open hub round the town and the plot district, a forest ring
--          round it with clearings, the wild biomes and lanes left open.

return function(t)
	local Vector2 = t.roblox.Vector2
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BiomeData = t.shared("BiomeData")
	local Forest = WorldLayout.Forest
	local cover = WorldLayout.ForestCover

	local function report(problems)
		local shown = {}
		for i = 1, math.min(#problems, 8) do
			shown[i] = problems[i]
		end
		return #problems .. " problems: " .. table.concat(shown, "; ")
	end

	local function zone(name)
		for _, z in ipairs(WorldLayout.FlatZones) do
			if z.name == name then
				return z
			end
		end
		error("no flat zone " .. name)
	end

	-- Dry lowland where trees could grow at all.
	local function land(x, z)
		return TerrainGen.WaterLevelAt(x, z) == nil
			and TerrainGen.HeightAt(x, z) < 70
			and WorldLayout.FlatWeight(x, z) <= 0
	end

	---------------------------------------------------------------------------
	-- FOR-01: the band layout
	---------------------------------------------------------------------------

	t.test("FOR-01: the hub is open: town, spawn, sawmill, shops, parking lot, plot district", function()
		local town = WorldPlan.Town()
		local problems = {}
		local function open(x, z, what)
			local c, ring = cover(x, z)
			if c ~= 0 or ring ~= 0 then
				table.insert(problems, string.format("%s (%d, %d): cover %.2f", what, x, z, c))
			end
		end
		local townZone = zone("Town")
		for x = townZone.x0, townZone.x1, 8 do
			for z = townZone.z0, townZone.z1, 8 do
				open(x, z, "Town")
			end
		end
		-- A homestead shelf is flat ground, so nothing chops there even when
		-- the country around it is forest.
		for _, pad in ipairs(WorldLayout.FlatZones) do
			if pad.name == "Plot" then
				t.eq(WorldLayout.FlatWeight((pad.x0 + pad.x1) / 2, (pad.z0 + pad.z1) / 2), 1, "shelf")
			end
		end
		open(town.spawn.X, town.spawn.Z, "the spawn")
		open(town.sawmill.X, town.sawmill.Z, "the sawmill")
		for _, shop in ipairs(town.shops) do
			-- (The showroom hall stands on its own flat zone, where no tree grows.)
			if WorldLayout.FlatWeight(shop.cframe.X, shop.cframe.Z) <= 0 then
				open(shop.cframe.X, shop.cframe.Z, shop.kind)
			end
		end
		for i, cf in ipairs(town.parkingSlots) do
			open(cf.X, cf.Z, "parking slot " .. i)
		end
		for _, g in ipairs(town.greenery) do
			open(g.cframe.X, g.cframe.Z, "town " .. g.kind)
		end
		open(town.gondola.X, town.gondola.Z, "the gondola station")
		open(town.campsite.X, town.campsite.Z, "Murph's camp")
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the forest ring wraps the hub: north, south, west and beyond the plots", function()
		-- Walking out from the hub's edge, you're in the forest's canopy
		-- within a few hundred studs, and the lawn round the town is no
		-- wider than the brief's hub (the view from the spawn closes).
		local function firstForest(from, dir, upTo)
			for d = 0, upTo, 4 do
				local p = from + dir * d
				if cover(p.X, p.Y) > 0.5 then
					return d
				end
			end
			return nil
		end
		local spawn = Vector2.new(0, 40)
		-- North past the sawmill, the pine band and the lawn (beside the Snow Road).
		local north = firstForest(spawn + Vector2.new(40, 0), Vector2.new(0, 1), 600)
		t.ok(north and north >= 220 and north <= 380, "north of the spawn the forest starts at " .. tostring(north))
		-- South: the Starter Forest is the ring's front step, the canopy right
		-- round its west and south sides (north-west of it is the town's
		-- lawn, Murph's camp and the spawn; east of it the plot district).
		local starter = BiomeData.Get("starter").area
		for _, deg in ipairs({ 180, 210, 240, 270 }) do
			local dir = Vector2.new(math.cos(math.rad(deg)), math.sin(math.rad(deg)))
			local c = Vector2.new(starter.x, starter.z) + dir * (starter.radius + 8)
			local d = firstForest(c, dir, 200)
			t.ok(d ~= nil and d <= 90, string.format("%d deg off the Starter Forest: forest at %s", deg, tostring(d)))
		end
		-- South of the open ground east of town (the old district's near edge).
		for x = 166, 340, 80 do
			local d = firstForest(Vector2.new(x, -200), Vector2.new(0, -1), 300)
			t.ok(d ~= nil, string.format("south of town at x %d: no forest", x))
		end
		-- Round the Hills (a wild room in the ring): forest north and south of
		-- it (west, it opens onto the river's valley; east, the town's lawn).
		local hills = BiomeData.Get("hills").area
		for _, deg in ipairs({ 90, 270 }) do
			local dir = Vector2.new(math.cos(math.rad(deg)), math.sin(math.rad(deg)))
			local d = firstForest(Vector2.new(hills.x, hills.z) + dir * hills.radius, dir, 260)
			t.ok(d ~= nil, string.format("%d deg off the Hills: no forest", deg))
		end
	end)

	t.test(
		"FOR-01: the ring is 65-80% canopy (Connor: more trees), with clearings; the wild band only copses",
		function()
			local inRing, canopy, wild, copse = 0, 0, 0, 0
			for x = -1150, 1150, 23 do
				for z = -1150, 1150, 23 do
					if land(x, z) then
						local c, ring = cover(x, z)
						if ring > 0.5 then
							inRing += 1
							canopy += if c > 0.5 then 1 else 0
						elseif ring == 0 and WorldLayout.HubDistance(x, z) > 0 then
							wild += 1
							copse += if c > 0.5 then 1 else 0
						end
					end
				end
			end
			local share = canopy / inRing
			t.ok(share >= 0.65 and share <= 0.8, string.format("the ring is %.0f%% canopy", share * 100))
			-- The ring wraps the town, not the old plot lawn, so the band is smaller.
			-- Extra shelves and their lanes took a few more samples (1197 left).
			t.ok(inRing >= 1150, inRing .. " samples in the ring")
			local copses = copse / wild
			-- The old plot lawn is wild country now, and a few of its copses count.
			t.ok(copses >= 0.03 and copses <= 0.16, string.format("the wild band is %.0f%% copse", copses * 100))
		end
	)

	t.test("FOR-01: every wild biome keeps its own ground: no canopy in it or its margin", function()
		local problems = {}
		for id, margin in pairs(Forest.wild) do
			local a = BiomeData.Get(id).area
			local r = if id == "grove" then WorldLayout.GroveRidge.outer + margin else a.radius + margin
			-- The edge wanders by up to hubNoise, so check inside that.
			local keep = r - Forest.hubNoise
			for _, frac in ipairs({ 0, 0.3, 0.6, 0.9, 1 }) do
				for k = 0, 23 do
					local ang = k / 24 * math.pi * 2
					local x, z = a.x + math.cos(ang) * keep * frac, a.z + math.sin(ang) * keep * frac
					local c = cover(x, z)
					if c > 0 then
						table.insert(problems, string.format("%s (%d, %d): %.2f", id, x, z, c))
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the forest keeps off the water, the beach and the mountains", function()
		local problems = {}
		for x = -1490, 1490, 17 do
			for z = -1490, 1490, 17 do
				local c = cover(x, z)
				if c > 0 then
					if TerrainGen.WaterLevelAt(x, z) ~= nil then
						table.insert(problems, string.format("water at (%d, %d)", x, z))
					end
					local _, material = TerrainGen.Sample(x, z)
					if material == "Sand" then
						table.insert(problems, string.format("sand at (%d, %d)", x, z))
					end
					if math.max(math.abs(x), math.abs(z)) > Forest.mountains then
						table.insert(problems, string.format("mountains at (%d, %d)", x, z))
					end
				end
			end
		end
		-- A margin off the river, the lake and the pond.
		for _, line in ipairs({ WorldLayout.River, WorldLayout.LakeOutflow }) do
			local pts = line.points
			for i = 1, #pts - 1 do
				for s = 0, 1, 0.02 do
					local p = pts[i]:Lerp(pts[i + 1], s)
					local dir = (pts[i + 1] - pts[i]).Unit
					for _, side in ipairs({ -1, 1 }) do
						local q = p + Vector2.new(-dir.Y, dir.X) * side * (line.width / 2 + Forest.water)
						if cover(q.X, q.Y) > 0 then
							table.insert(problems, string.format("by the water at (%d, %d)", q.X, q.Y))
						end
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the lanes stay open: the spawn's view of the lighthouse, the grove's trail", function()
		local lighthouse = WorldPlan.Lighthouse()
		t.ok(lighthouse ~= nil, "a lighthouse")
		local vista
		for _, lane in ipairs(Forest.lanes) do
			if lane.name == "LighthouseVista" then
				vista = lane
			end
		end
		t.ok(vista ~= nil, "the lighthouse's lane")
		local base = lighthouse.cframe.Position
		local spawn = WorldPlan.Town().spawn
		t.ok((vista.b - Vector2.new(base.X, base.Z)).Magnitude < 3, "the lane ends at the lighthouse")
		t.ok((vista.a - Vector2.new(spawn.X, spawn.Z)).Magnitude < 1, "and starts at the spawn")
		local problems = {}
		for _, lane in ipairs(Forest.lanes) do
			local dir = (lane.b - lane.a).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			for s = 0, 1, 0.01 do
				local p = lane.a:Lerp(lane.b, s)
				for _, off in ipairs({ -0.95, -0.5, 0, 0.5, 0.95 }) do
					local q = p + side * off * lane.half
					local c = cover(q.X, q.Y)
					if c > 0 then
						table.insert(problems, string.format("%s at (%d, %d): %.2f", lane.name, q.X, q.Y, c))
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
		-- The grove's trail starts inside its ridge's gap and leads toward town.
		local grove = BiomeData.Get("grove").area
		local trail
		for _, lane in ipairs(Forest.lanes) do
			if lane.name == "GroveTrail" then
				trail = lane
			end
		end
		local fromGrove = (trail.a - Vector2.new(grove.x, grove.z)).Magnitude
		t.ok(fromGrove < WorldLayout.GroveRidge.inner, "the trail starts inside the ridge")
		local toTown = (Vector2.new(0, 110) - Vector2.new(grove.x, grove.z)).Unit
		t.ok((trail.b - trail.a).Unit:Dot(toTown) > 0.99, "and leads toward town")
		t.ok((trail.b - trail.a).Magnitude >= 250, "far enough to clear the ring")
	end)

	t.test("FOR-01: ForestCover is pure: the same on every server, 0..1, ring 0..1", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldLayout")
		for i = 1, 400 do
			local x, z = (i * 97.3) % 2900 - 1450, (i * 61.7) % 2900 - 1450
			local c, ring = cover(x, z)
			local c2, ring2 = again.ForestCover(x, z)
			t.eq(c, c2)
			t.eq(ring, ring2)
			t.ok(c >= 0 and c <= 1 and ring >= 0 and ring <= 1, "in range")
			t.ok(ring == 0 or c <= ring + 1e-9, "a clearing only takes canopy away")
		end
	end)

	---------------------------------------------------------------------------
	-- FOR-02: the client-built filler forest
	---------------------------------------------------------------------------

	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local QualityBudgets = t.shared("QualityBudgets")
	local fs = require("@lune/fs")
	local CELL = WorldPlan.FillerCellSize

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Parts per filler look (ForestFiller clones exactly these).
	local partsOf = {}
	for _, kind in ipairs(PropArt.FillerKinds) do
		partsOf[kind] = {}
		for v = 1, PropArt.FillerVariants do
			partsOf[kind][v] = #parts(PropArt.FillerTree(kind, v))
		end
	end

	-- Every filler tree on the map, worked out once: { tree, cx, cz }.
	local allFiller
	local function everyFiller()
		if allFiller then
			return allFiller
		end
		allFiller = {}
		local half = WorldLayout.WorldHalf // CELL
		for cx = -half, half - 1 do
			for cz = -half, half - 1 do
				for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
					table.insert(allFiller, { tree = tree, cx = cx, cz = cz })
				end
			end
		end
		return allFiller
	end

	t.test("FOR-02: a filler tree is 3-5 SmoothPlastic parts of decoration, shadowless, on the ground", function()
		local seen = {}
		for _, kind in ipairs(PropArt.FillerKinds) do
			for v = 1, PropArt.FillerVariants do
				local model = PropArt.FillerTree(kind, v)
				local list = parts(model)
				t.ok(#list >= 3 and #list <= 5, string.format("%s %d: %d parts", kind, v, #list))
				local lowest, highest = math.huge, -math.huge
				for _, p in ipairs(list) do
					local here = string.format("%s %d's %s", kind, v, p.Name)
					t.eq(p.Material, t.roblox.Enum.Material.SmoothPlastic, here)
					t.ok(p.Anchored, here .. " is anchored")
					t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch, here .. " is decoration")
					t.ok(not p.CastShadow, here .. " casts a shadow")
					t.ok(
						p.Name == "FillerTrunk" or p.Name == "FillerCrown" or p.Name == "FillerBranch",
						here .. ": a filler part's name (never Leaves, Frond, Tier or Facet)"
					)
					local y, s = p.CFrame.Position.Y, p.Size.Magnitude / 2
					lowest, highest = math.min(lowest, y - s), math.max(highest, y + s)
				end
				t.ok(lowest < -0.5, kind .. ": its trunk's foot sits in the ground")
				t.ok(highest > 10 and highest < 28, string.format("%s %d: %.0f tall", kind, v, highest))
				seen[kind] = true
			end
			local a, b = PropArt.FillerTree(kind, 1), PropArt.FillerTree(kind, 1)
			local pa, pb = parts(a), parts(b)
			for i = 1, #pa do
				t.ok((pa[i].CFrame.Position - pb[i].CFrame.Position).Magnitude < 1e-6, kind .. ": the same look")
			end
		end
		t.eq(PropArt.FillerVariants, 6, "WorldPlan's FILLER_VARIANTS")
	end)

	t.test("FOR-02: the filler is the same on every client", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan")
		for i = 1, 60 do
			local cx, cz = (i * 37) % 80 - 40, (i * 53) % 80 - 40
			local a, b = WorldPlan.FillerCellTrees(cx, cz), again.FillerCellTrees(cx, cz)
			t.eq(#a, #b)
			for k, tree in ipairs(a) do
				t.eq(b[k], tree)
			end
			local fa, fb = WorldPlan.FillerFarCell(cx, cz), again.FillerFarCell(cx, cz)
			t.eq(#fa, #fb)
			for k, block in ipairs(fa) do
				t.ok((block.cframe.Position - fb[k].cframe.Position).Magnitude < 1e-9, "the same stand-in")
				t.eq(block.size, fb[k].size)
				t.eq(block.kind, fb[k].kind)
			end
		end
	end)

	t.test(
		"FOR-02: the filler keeps off roads, trees, rocks, scenery, signs, gondola, town, water, mountains",
		function()
			local problems = {}
			local function check(ok, what)
				if not ok then
					table.insert(problems, what)
				end
			end
			local trees = WorldPlan.Trees()
			local treeBins = {}
			for _, tree in ipairs(trees) do
				local k = (tree.position.X // 32) .. "," .. (tree.position.Z // 32)
				treeBins[k] = treeBins[k] or {}
				table.insert(treeBins[k], tree.position)
			end
			local discs = {}
			for _, b in ipairs(WorldPlan.Boulders()) do
				table.insert(discs, { b.position.X, b.position.Z, b.size / 2, "a boulder" })
			end
			for _, spot in ipairs(WorldPlan.Scenery()) do
				table.insert(discs, { spot.center.X, spot.center.Z, spot.radius, "a " .. spot.kind })
			end
			for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
				local p = sign.cframe.Position
				table.insert(discs, { p.X, p.Z, 5.3, "a road sign" })
			end
			for _, c in ipairs(WorldPlan.BoulderClusters()) do
				table.insert(discs, { c.center.X, c.center.Z, c.radius, "a boulder cluster" })
			end
			-- The landmarks (the plan never looks at them: the water's margin
			-- and the beach keep the forest off them).
			local bridge = WorldPlan.Footbridge()
			if bridge then
				local a = bridge.cframe.Position
				local along = bridge.cframe.LookVector
				for s = -8, bridge.span + 8, 2 do
					local p = a + along * s
					table.insert(discs, { p.X, p.Z, bridge.width / 2 + 1, "the footbridge" })
				end
				if bridge.sign then
					table.insert(discs, { bridge.sign.X, bridge.sign.Z, 5.3, "the footbridge's sign" })
				end
			end
			for _, dock in ipairs(WorldPlan.Docks()) do
				local a = dock.cframe.Position
				for s = -4, dock.length, 2 do
					local p = a + dock.cframe.LookVector * s
					table.insert(discs, { p.X, p.Z, dock.width / 2 + 1, "a dock" })
				end
				if dock.sign then
					table.insert(discs, { dock.sign.X, dock.sign.Z, 5.3, "a dock's sign" })
				end
			end
			local lighthouse = WorldPlan.Lighthouse()
			table.insert(discs, { lighthouse.cframe.X, lighthouse.cframe.Z, 8, "the lighthouse" })
			local sky = WorldPlan.Sky()
			local top = sky.gondolaTop.Position
			local routes = {}
			for _, from in ipairs({ WorldPlan.TownGondolaSpot, sky.gondolaBase.Position }) do
				table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
			end
			local count = 0
			for _, entry in ipairs(everyFiller()) do
				local tree = entry.tree
				count += 1
				local x, z = tree.x, tree.z
				local here = string.format("filler %s at (%.0f, %.0f)", tree.kind, x, z)
				check(
					x >= entry.cx * CELL and x < (entry.cx + 1) * CELL + 4 and z >= entry.cz * CELL - 4,
					here .. ": outside its cell"
				)
				check(TerrainGen.RoadClearance(x, z) >= WorldPlan.FillerRoad, here .. " is in a road's corridor")
				check(WorldLayout.FlatWeight(x, z) <= 0, here .. " is on the town's or the plots' ground")
				check(math.abs(tree.y - TerrainGen.HeightAt(x, z)) < 1e-6, here .. " isn't on the ground")
				check(tree.y < 70, here .. " is up in the mountains")
				for k = 0, 7 do
					local a = k * math.pi / 4
					check(
						TerrainGen.WaterLevelAt(x + math.cos(a) * 6, z + math.sin(a) * 6) == nil,
						here .. " is within 6 studs of the water"
					)
				end
				for ix = x // 32 - 1, x // 32 + 1 do
					for iz = z // 32 - 1, z // 32 + 1 do
						for _, p in ipairs(treeBins[ix .. "," .. iz] or {}) do
							local d = Vector2.new(p.X - x, p.Z - z).Magnitude
							check(
								d >= WorldPlan.FillerTreeGap,
								string.format("%s is %.1f from a choppable tree", here, d)
							)
						end
					end
				end
				for _, disc in ipairs(discs) do
					local dx, dz = x - disc[1], z - disc[2]
					local reach = disc[3] + WorldPlan.FillerGap
					if math.abs(dx) < reach and math.abs(dz) < reach then
						check(dx * dx + dz * dz >= reach * reach, here .. " stands in " .. disc[4])
					end
				end
				for _, route in ipairs(routes) do
					check(
						WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) >= WorldPlan.FillerGondola,
						here .. " is under the gondola"
					)
				end
			end
			t.ok(#problems == 0, report(problems))
			-- Shelves and lanes ate open forest the filler used to stand in.
			t.ok(count >= 2100, count .. " filler trees on the map")
		end
	)

	t.test("FOR-02: a forest's density: about one tree per 150-250 sq studs, denser rows at its edges", function()
		-- Deep in the forest: whole cells under full canopy, well off the roads.
		local deep, deepCells = 0, 0
		for cx = -40, 39 do
			for cz = -40, 39 do
				local mx, mz = (cx + 0.5) * CELL, (cz + 0.5) * CELL
				local lo = math.huge
				for _, o in ipairs({ { -14, -14 }, { 14, -14 }, { -14, 14 }, { 14, 14 }, { 0, 0 } }) do
					local c, ring = cover(mx + o[1], mz + o[2])
					lo = math.min(lo, if ring < 0.5 then -1 else c)
				end
				if lo > 0.9 and TerrainGen.RoadClearance(mx, mz) >= 60 and land(mx, mz) then
					deep += #WorldPlan.FillerCellTrees(cx, cz)
					deepCells += 1
				end
			end
		end
		-- Shelves and lanes broke up some of the deep canopy cells.
		t.ok(deepCells >= 120, deepCells .. " deep cells")
		local perTree = deepCells * CELL * CELL / deep
		-- Phase 12 thinned the filler (core roll 0.55 to 0.4), so a deep
		-- cell holds fewer trees than the old 150-260 band.
		t.ok(perTree >= 250 and perTree <= 400, string.format("deep in the forest a tree per %.0f sq studs", perTree))
		-- Its edges (canopy 0.5 to FillerEdge): the area there, every 4 studs,
		-- and the trees standing in it, in the north and south forests.
		local function edgeBand(x, z)
			local c, ring = cover(x, z)
			return ring > 0.5 and c > 0.5 and c < WorldPlan.FillerEdge and TerrainGen.RoadClearance(x, z) >= 60
		end
		local regions = { { -500, 700, -1150, -700 }, { -400, 800, 340, 800 } }
		local area, trees = 0, 0
		for _, r in ipairs(regions) do
			for x = r[1], r[2], 4 do
				for z = r[3], r[4], 4 do
					if edgeBand(x, z) then
						area += 16
					end
				end
			end
			for cx = r[1] // CELL, r[2] // CELL do
				for cz = r[3] // CELL, r[4] // CELL do
					for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
						if tree.x >= r[1] and tree.x < r[2] + 4 and tree.z >= r[3] and tree.z < r[4] + 4 then
							trees += if edgeBand(tree.x, tree.z) then 1 else 0
						end
					end
				end
			end
		end
		-- The ring wraps the town only, so these two rectangles hold a shorter edge.
		-- Lanes out to the shelves take a few of those edge trees (71 left since The Climb moved north for the showroom hall).
		t.ok(area > 20000 and trees >= 65, string.format("%d sq studs of edge, %d trees in it", area, trees))
		local perEdge = area / trees
		-- Lanes cross the edge band, so it is only a little denser than the deep cells.
		t.ok(
			perEdge < perTree * 0.95,
			string.format("at its edges a tree per %.0f sq studs (deep: %.0f)", perEdge, perTree)
		)
		t.ok(perEdge >= 90, string.format("but not a solid wall: a tree per %.0f sq studs", perEdge))
	end)

	t.test("FOR-02: from the spawn, the forest closes the view 220-500 studs out (north, west, south)", function()
		local eye = WorldPlan.SpawnEye()
		local bins = {}
		for _, entry in ipairs(everyFiller()) do
			local tree = entry.tree
			local k = (tree.x // 16) .. "," .. (tree.z // 16)
			bins[k] = bins[k] or {}
			table.insert(bins[k], tree)
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			local p = spot.position
			local k = (p.X // 16) .. "," .. (p.Z // 16)
			bins[k] = bins[k] or {}
			table.insert(bins[k], { x = p.X, z = p.Z })
		end
		-- The first tree (filler or choppable) a crown's width off the line of sight.
		local function firstTree(deg)
			local dir = Vector2.new(math.sin(math.rad(deg)), math.cos(math.rad(deg))) -- 0 = north (+Z)
			for d = 20, 800, 4 do
				local x, z = eye.X + dir.X * d, eye.Z + dir.Y * d
				for _, tree in ipairs(bins[(x // 16) .. "," .. (z // 16)] or {}) do
					if (Vector2.new(tree.x, tree.z) - Vector2.new(x, z)).Magnitude < 5 then
						return d
					end
				end
			end
			return nil
		end
		-- North past the sawmill and the pine band, round to the west, and
		-- south through the Starter Forest. Two bearings run down a homestead
		-- and then open country (North Bend into the Snowfields, Orchard Edge),
		-- so the check uses the next bearing that still meets a tree.
		for _, deg in ipairs({ -40, -30, 20, 35, 180, 200, 260 }) do
			local d = firstTree(deg)
			t.ok(
				d ~= nil and d <= 620,
				string.format("looking %d deg from north: the first tree at %s", deg, tostring(d))
			)
		end
	end)

	-- Filler and stand-in parts a camera at (x, y, z) loads on a tier.
	local function loaded(budget, x, y, z)
		local plan = WorldPlan.FillerPlanAround(x, y, z, budget.FillerNear, budget.FillerFar)
		local near, far, trees = 0, 0, 0
		for key, mode in pairs(plan) do
			local cx, cz = WorldPlan.FillerCellOf(key)
			if mode == "near" then
				for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
					near += partsOf[tree.kind][tree.variant]
					trees += 1
				end
			else
				far += #WorldPlan.FillerFarCell(cx, cz)
			end
		end
		-- And the grass tufts (FOR-04): 9 parts each at most (PropArt.spec).
		for key in pairs(WorldPlan.TuftPlanAround(x, y, z, budget.TuftNear)) do
			local cx, cz = WorldPlan.FillerCellOf(key)
			near += #WorldPlan.TuftCell(cx, cz) * 9
		end
		return near, far, trees
	end

	t.test("FOR-02: budgets: filler, tufts and stand-ins in view under 6,000 parts on low, 14,000 on high", function()
		local spots = {
			{ "the spawn", WorldPlan.SpawnEye() },
			{ "the Starter Forest", t.roblox.Vector3.new(0, 8, -180) },
			{ "the Hills", t.roblox.Vector3.new(-500, 40, 110) },
			{ "the Snowfields", t.roblox.Vector3.new(80, 45, 760) },
			{ "the Phantom Grove", t.roblox.Vector3.new(10, 4, -720) },
			{ "deep in the south forest", t.roblox.Vector3.new(800, 8, -600) },
			{ "on the Snow Road in the forest", t.roblox.Vector3.new(30, 8, 450) },
			{ "on the isles", t.roblox.Vector3.new(680, 706, 280) },
		}
		local most = { low = 0, high = 0 }
		for _, tier in ipairs({ "low", "high" }) do
			local budget = QualityBudgets.For(tier)
			for _, spot in ipairs(spots) do
				local p = spot[2]
				local near, far = loaded(budget, p.X, p.Y, p.Z)
				local limit = if tier == "low" then 6000 else 14000
				t.ok(
					near + far < limit,
					string.format("%s at %s: %d filler and tuft + %d stand-in parts", tier, spot[1], near, far)
				)
				most[tier] = math.max(most[tier], near + far)
			end
		end
		-- And the forest is really there: thousands of trees round you in it.
		local _, _, trees = loaded(QualityBudgets.High, 800, 8, -600)
		t.ok(trees > 200, trees .. " filler trees round you deep in the forest on high")
		t.ok(most.low < most.high, "low loads less")
	end)

	t.test("FOR-02: FillerPlanAround: trees near, stand-ins out to FillerFar, a margin before a cell flips", function()
		local budget = QualityBudgets.High
		local plan = WorldPlan.FillerPlanAround(0, 6, 40, budget.FillerNear, budget.FillerFar)
		local nearCount, farCount = 0, 0
		for key, mode in pairs(plan) do
			local cx, cz = WorldPlan.FillerCellOf(key)
			t.eq(WorldPlan.FillerCellKey(cx, cz), key, "keys round-trip")
			local d = Vector2.new((cx + 0.5) * CELL, (cz + 0.5) * CELL - 40).Magnitude
			if mode == "near" then
				nearCount += 1
				t.ok(d <= budget.FillerNear, "a near cell within FillerNear")
			else
				farCount += 1
				t.eq(mode, "far")
				t.ok(d > budget.FillerNear and d <= budget.FillerFar, "a far cell between the radii")
			end
		end
		-- The far ring is the band between FillerNear and FillerFar. Launch
		-- keeps that band inside StreamingTargetRadius 640, so it is a few
		-- hundred cells, not the old ring out to 1,000.
		t.ok(nearCount > 600, nearCount .. " near cells")
		t.ok(farCount > 100, nearCount .. " near, " .. farCount .. " far")
		-- Moved 30 studs on: the cells it had keep their looks (hysteresis).
		local moved = WorldPlan.FillerPlanAround(30, 6, 40, budget.FillerNear, budget.FillerFar, plan)
		for key, mode in pairs(plan) do
			local cx, cz = WorldPlan.FillerCellOf(key)
			local d = Vector2.new((cx + 0.5) * CELL - 30, (cz + 0.5) * CELL - 40).Magnitude
			if mode == "near" and d <= budget.FillerNear + WorldPlan.FillerHysteresis then
				t.eq(moved[key], "near", "a near cell stays near just past the radius")
			end
		end
		-- From the isles the ground is all far: stand-ins only.
		for _, mode in pairs(WorldPlan.FillerPlanAround(680, 706, 280, budget.FillerNear, budget.FillerFar)) do
			t.eq(mode, "far")
		end
	end)

	t.test("FOR-02: stand-ins stand only over forest, off the roads, and never hide the lighthouse", function()
		local lighthouse = WorldPlan.Lighthouse()
		local eye = WorldPlan.SpawnEye()
		local lamp = lighthouse.lamp
		local a, b = Vector2.new(eye.X, eye.Z), Vector2.new(lamp.X, lamp.Z)
		local problems = {}
		local blocks = 0
		for cx = -47, 46 do
			for cz = -47, 46 do
				for _, block in ipairs(WorldPlan.FillerFarCell(cx, cz)) do
					blocks += 1
					local p = block.cframe.Position
					local reach = math.max(block.size.X, block.size.Z) * 0.71
					local here = string.format("a stand-in at (%.0f, %.0f)", p.X, p.Z)
					if TerrainGen.RoadClearance(p.X, p.Z) < reach then
						table.insert(problems, here .. " on a road")
					end
					if cover(p.X, p.Z) <= 0 then
						table.insert(problems, here .. " over open ground")
					end
					local d, s = WorldLayout.SegmentDistance(Vector2.new(p.X, p.Z), a, b)
					local lineY = eye.Y + (lamp.Y - eye.Y) * s
					if d < reach + 2 and lineY < p.Y + block.size.Y / 2 then
						table.insert(problems, here .. " hides the lighthouse")
					end
				end
			end
		end
		-- Nor does any filler tree (its crown 20 studs up, 8 across).
		for _, entry in ipairs(everyFiller()) do
			local tree = entry.tree
			local d, s = WorldLayout.SegmentDistance(Vector2.new(tree.x, tree.z), a, b)
			if d < 10 and eye.Y + (lamp.Y - eye.Y) * s < tree.y + 24 then
				table.insert(
					problems,
					string.format("a filler tree at (%.0f, %.0f) hides the lighthouse", tree.x, tree.z)
				)
			end
		end
		t.ok(#problems == 0, report(problems))
		t.ok(blocks > 500, blocks .. " stand-ins")
	end)

	t.test("FOR-02: ForestFiller starts with the client, builds decoration only, reads its budgets", function()
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/ForestFiller.luau")
		local code = string.gsub(source, "%-%-[^\n]*", "")
		local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		t.ok(string.find(client, "require(script.Parent.ForestFiller)", 1, true), "Client.client starts it")
		for _, key in ipairs({ "FillerNear", "FillerFar", "FillerBuildMs" }) do
			t.ok(string.find(code, "%." .. key .. "%f[%W]") ~= nil, "reads " .. key)
		end
		t.eq(string.find(code, "CanCollide = true", 1, true), nil, "nothing it builds collides")
		t.eq(string.find(code, "CanQuery = true", 1, true), nil, "nothing it builds is clickable")
		t.eq(string.find(code, "CastShadow = true", 1, true), nil, "nothing it builds casts a shadow")
		t.ok(string.find(code, "Kit.decor(block, false)", 1, true), "its stand-in block is decoration")
		t.ok(string.find(code, "PropArt.FillerTree(", 1, true), "its trees are PropArt's")
		t.eq(string.find(code, "CollectionService", 1, true), nil, "never tagged (not a Tree)")
		-- AmbientLife keeps its decoration out of the filler's trunks.
		local life = fs.readFile("src/StarterPlayer/StarterPlayerScripts/AmbientLife.luau")
		t.ok(string.find(life, "WorldPlan.FillerTrunkNear(", 1, true), "AmbientLife asks about the trunks")
		local entry = everyFiller()[100]
		t.ok(WorldPlan.FillerTrunkNear(entry.tree.x + 1, entry.tree.z, 2.5), "a trunk is found")
		t.ok(WorldPlan.FillerReady(), "the plan is ready once worked out")
	end)

	---------------------------------------------------------------------------
	-- FOR-03: more trees to chop where the forest is
	---------------------------------------------------------------------------

	local BASE = 481 -- the first 322 and the country stands (WorldPlan.spec pins both)
	local forestTrees = WorldPlan.ForestTrees()

	-- Which kind of place a forest tree stands in.
	local function placeOf(spot)
		local p = spot.position
		if TerrainGen.RoadClearance(p.X, p.Z) <= WorldPlan.ForestVerge[2] + 2 then
			return "verge"
		end
		local c = cover(p.X, p.Z)
		return if c > 0.12 then "edge" else "clearing"
	end

	t.test("FOR-03: 200-350 new trees to chop after the country stands: verges, edges and clearings", function()
		local trees = WorldPlan.Trees()
		t.ok(#trees > BASE + #forestTrees, "the density fill is appended after the forest")
		for i, spot in ipairs(forestTrees) do
			t.eq(trees[BASE + i], spot, "the forest's trees follow the stands, in order")
			t.eq(spot.biome, "wild")
		end
		t.ok(#forestTrees >= 200 and #forestTrees <= 350, #forestTrees .. " new trees")
		local count = { verge = 0, edge = 0, clearing = 0 }
		for _, spot in ipairs(forestTrees) do
			local kind = placeOf(spot)
			count[kind] += 1
		end
		for kind, n in pairs(count) do
			t.ok(n >= 15, string.format("%d trees on the %ss", n, kind))
		end
		local most = WorldPlan.ForestMost
		t.ok(#forestTrees <= most.verge + most.edge + most.clearing, "within ForestMost")
	end)

	t.test("FOR-03: forest trees on good ground, reachable, off everything players and trucks use", function()
		local trees = WorldPlan.Trees()
		local mill = Vector2.new(0, 110)
		local coast = WorldLayout.Coast
		local discs = {}
		for _, b in ipairs(WorldPlan.Boulders()) do
			table.insert(discs, { b.position.X, b.position.Z, b.size / 2 + 6, "a boulder" })
		end
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			local p = sign.cframe.Position
			table.insert(discs, { p.X, p.Z, 12, "a road sign" })
		end
		for _, spot in ipairs(WorldPlan.Scenery()) do
			table.insert(discs, { spot.center.X, spot.center.Z, spot.radius + 8, "a " .. spot.kind })
		end
		for _, c in ipairs(WorldPlan.BoulderClusters()) do
			table.insert(discs, { c.center.X, c.center.Z, c.radius + 6, "a boulder cluster" })
		end
		local lighthouse = WorldPlan.Lighthouse()
		table.insert(discs, { lighthouse.cframe.X, lighthouse.cframe.Z, 14, "the lighthouse" })
		local sky = WorldPlan.Sky()
		local top = sky.gondolaTop.Position
		local routes = {}
		for _, from in ipairs({ WorldPlan.TownGondolaSpot, sky.gondolaBase.Position }) do
			table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
		end
		local problems = {}
		local function check(ok, what)
			if not ok then
				table.insert(problems, what)
			end
		end
		for i, spot in ipairs(forestTrees) do
			local p = spot.position
			local x, z = p.X, p.Z
			local here = string.format("%s at (%.0f, %.0f)", spot.woodId, x, z)
			check(WorldPlan.GoodGround(x, z, WorldPlan.ForestVerge[1] - 1, 0.6), here .. ": bad ground or on a road")
			check(TerrainGen.RoadClearance(x, z) >= WorldPlan.ForestVerge[1] - 1, here .. " is on a road's verge")
			check(math.abs(p.Y - (TerrainGen.HeightAt(x, z) - 0.3)) < 1e-3, here .. " stands on the ground")
			check(TerrainGen.HeightAt(x, z) < 70, here .. " is up in the mountains")
			check(WorldLayout.FlatWeight(x, z) == 0, here .. " is in town or the plots")
			check(not (z < coast.northZ and x > coast.shoreX - coast.beachWidth - 40), here .. " is on the beach")
			for k = 0, 7 do -- dry all round: you walk up to it
				local a = k * math.pi / 4
				check(
					TerrainGen.WaterLevelAt(x + math.cos(a) * 4, z + math.sin(a) * 4) == nil,
					here .. " is by the water"
				)
			end
			local fromMill = (Vector2.new(x, z) - mill).Magnitude
			check(fromMill > 300, string.format("%s is %.0f from the sawmill", here, fromMill))
			if spot.woodId == "pine" or spot.woodId == "maple" then
				check(fromMill >= 400, string.format("%s is %.0f from the sawmill", here, fromMill))
			end
			for _, biome in ipairs(BiomeData.All()) do
				local a = biome.area
				if a then
					local margin = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 else a.radius + 30
					check(Vector2.new(x - a.x, z - a.z).Magnitude >= margin, here .. " is in " .. biome.id)
				end
			end
			for _, route in ipairs(routes) do
				check(WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) >= 30, here .. ": gondola")
			end
			for _, disc in ipairs(discs) do
				check(Vector2.new(x - disc[1], z - disc[2]).Magnitude >= disc[3], here .. " is in " .. disc[4])
			end
			for _, lane in ipairs(Forest.lanes) do
				check(
					WorldLayout.SegmentDistance(Vector2.new(x, z), lane.a, lane.b) >= lane.half + 10,
					here .. " stands in the " .. lane.name
				)
			end
			for j = 1, BASE + i - 1 do
				local q = trees[j].position
				local d = Vector2.new(x - q.X, z - q.Z).Magnitude
				check(d >= 12, string.format("%s is %.1f from tree %d", here, d, j))
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-03: the forest's trees are the same on every server", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").ForestTrees()
		t.eq(#again, #forestTrees)
		for i, spot in ipairs(forestTrees) do
			t.eq(again[i].woodId, spot.woodId)
			t.ok((again[i].position - spot.position).Magnitude < 1e-6, "tree " .. i .. " in the same place")
		end
	end)

	t.test("FOR-03: a forest-ring tree is still about 33 parts", function()
		local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
		local WoodData = t.shared("WoodData")
		local TreeLogic = t.shared("TreeLogic")
		local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
		local forest, forestN = 0, 0
		for _, spot in ipairs(WorldPlan.Trees()) do
			local zone = spot.zone
			if zone and string.sub(zone.id, 1, 7) == "forest:" then
				local p = spot.position
				local seed = Kit.seedAt(p.X, p.Z)
				local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
				forest += #parts(TreeArt.Build(WoodData.Get(spot.woodId), seed, size.scale))
				forestN += 1
			end
		end
		t.eq(forestN, #forestTrees, "the ring is the forest zones")
		t.ok(forest / forestN <= 36, string.format("%.1f parts a forest tree", forest / forestN))
	end)

	---------------------------------------------------------------------------
	-- FOR-04: the ground: the forest floor, the grass, the tufts
	---------------------------------------------------------------------------

	local function materialAt(x, z)
		local _, m = TerrainGen.Sample(x, z)
		return m
	end

	t.test("FOR-04: under the canopy the floor is LeafyGrass (bare Ground where worn), never bladed Grass", function()
		local counts, n = {}, 0
		local problems = {}
		for x = -1150, 1150, 19 do
			for z = -1150, 1150, 19 do
				local c, ring = cover(x, z)
				if c > 0.66 and land(x, z) and not BiomeData.At(x, z) and TerrainGen.RoadClearance(x, z) > 2 then
					local m = materialAt(x, z)
					counts[m] = (counts[m] or 0) + 1
					n += 1
					if m == "Grass" then
						table.insert(problems, string.format("Grass under the canopy at (%d, %d)", x, z))
					end
				end
			end
		end
		t.ok(n > 2000, n .. " samples under the canopy")
		t.ok(#problems == 0, report(problems))
		t.ok(
			(counts.LeafyGrass or 0) / n > 0.85,
			string.format("%.0f%% LeafyGrass", (counts.LeafyGrass or 0) / n * 100)
		)
		t.ok((counts.Ground or 0) / n > 0.01, "and some bare earth")
	end)

	t.test("FOR-04: the hub's lawns and the open meadows keep their bladed Grass", function()
		-- The plot district's lawn (Terrain.spec pins it plain Grass), the
		-- town's lawn north of the pine band, and the wild meadows.
		local function share(x0, x1, z0, z1)
			local grass, n = 0, 0
			for x = x0, x1, 9 do
				for z = z0, z1, 9 do
					if cover(x, z) == 0 and TerrainGen.RoadClearance(x, z) > 3 and land(x, z) then
						n += 1
						grass += if materialAt(x, z) == "Grass" then 1 else 0
					end
				end
			end
			return grass / math.max(n, 1), n
		end
		local lawn, n1 = share(-100, 120, 240, 300)
		t.ok(n1 > 50 and lawn > 0.4, string.format("the town's north lawn is %.0f%% Grass", lawn * 100))
		local meadow, n2 = share(-1150, -950, -1100, -400)
		t.ok(n2 > 300 and meadow > 0.4, string.format("the west meadow is %.0f%% Grass", meadow * 100))
	end)

	t.test(
		"FOR-04: the new floor moves nothing that stands on grass: clusters, footbridge, docks, lighthouse",
		function()
			-- A fingerprint of the boulder clusters' rocks, the footbridge, the
			-- docks and the lighthouse, worked out before the forest floor (their
			-- searches read the terrain's material: grass under a rock or a deck).
			local h = 7
			local function add(s)
				for k = 1, #s do
					h = (h * 31 + string.byte(s, k)) % 1000000007
				end
			end
			for _, c in ipairs(WorldPlan.BoulderClusters()) do
				for _, r in ipairs(c.rocks) do
					add(string.format("%.2f %.2f %.2f;", r.position.X, r.position.Z, r.size))
				end
			end
			local b = WorldPlan.Footbridge()
			add(string.format("%.2f %.2f %.2f;", b.cframe.X, b.cframe.Z, b.span))
			for _, d in ipairs(WorldPlan.Docks()) do
				add(string.format("%s %.2f %.2f;", d.kind, d.cframe.X, d.cframe.Z))
			end
			local l = WorldPlan.Lighthouse()
			add(string.format("%.2f %.2f;", l.cframe.X, l.cframe.Z))
			-- Re-sampled in phase 12. Wider roads moved the roadside clusters
			-- and the pieces they keep clear of; the search itself did not.
			-- Re-sampled when the homesteads left the one lawn, and again when the
			-- lighthouse moved to (1203, 236). The searches still read the grass
			-- under each rock; the shelves moved a few clusters.
			t.eq(h, 901717980, "a cluster or landmark moved")
		end
	)

	t.test(
		"FOR-04: the project's grass: blades off (flat LT2 meadow), GrassLength kept short; streaming out far content",
		function()
			local serde = require("@lune/serde")
			local tree = serde.decode("json", fs.readFile("default.project.json")).tree
			local terrain = tree.Workspace.Terrain["$properties"]
			-- Blades were on until 7 October 2026: Connor wants the Lumber Tycoon 2
			-- ground, flat and smooth, and blades also poke through the plots'
			-- 1-stud build platform. GrassLength stays short in case they come back.
			t.eq(terrain.Decoration, false, "grass blades off: a flat, smooth meadow")
			t.ok(terrain.GrassLength >= 0.45 and terrain.GrassLength <= 0.6, "GrassLength " .. terrain.GrassLength)
			local workspace = tree.Workspace["$properties"]
			t.eq(workspace.StreamOutBehavior, "Opportunistic", "far server content streams out on any device")
			t.ok(
				QualityBudgets.High.FillerFar < workspace.StreamingTargetRadius,
				"stand-ins never outreach the streamed terrain"
			)
			t.ok(
				QualityBudgets.Low.FillerFar < workspace.StreamingTargetRadius,
				"a phone's stand-ins stay inside the streamed terrain too"
			)
			t.eq(workspace.StreamingTargetRadius, 640, "phones stream a 640-stud disc, not 1024")
			t.eq(workspace.StreamingMinRadius, 128, "the pause bubble is 128 studs")
		end
	)

	t.test("FOR-04: Timber ground MaterialVariants are in MaterialService, off until checked in Studio", function()
		local serde = require("@lune/serde")
		local want = { TimberGrass = "Grass", TimberLeafy = "LeafyGrass", TimberGround = "Ground" }
		for name, base in pairs(want) do
			local file = "src/MaterialService/" .. name .. ".model.json"
			local def = serde.decode("json", fs.readFile(file))
			t.eq(def.className, "MaterialVariant", file)
			local props = def.properties
			t.eq(props.BaseMaterial, base, name .. "'s base material")
			for _, map in ipairs({ "ColorMap", "NormalMap", "RoughnessMap" }) do
				t.ok(string.match(props[map], "^rbxassetid://%d+$"), name .. "'s " .. map)
			end
			t.ok(props.StudsPerTile >= 16 and props.StudsPerTile <= 24, name .. "'s tiling")
			t.eq(props.MaterialPattern, "Organic", name .. " tiles organically")
		end
		local tree = serde.decode("json", fs.readFile("default.project.json")).tree
		local service = tree.MaterialService
		t.eq(service["$className"], "MaterialService")
		t.eq(service["$path"], "src/MaterialService")
		t.eq(service["$ignoreUnknownInstances"], true, "never deletes a variant made in Studio")
		-- The textures can't be checked from here (Roblox's asset servers are
		-- out of reach): no base material is switched over to them until
		-- Connor has seen them in Studio (GrassName and friends stay default).
		local props = service["$properties"] or {}
		for _, key in ipairs({ "GrassName", "LeafyGrassName", "GroundName" }) do
			t.eq(props[key], nil, key .. " is left to Studio for now")
		end
	end)

	t.test("FOR-04: a grass tuft is 5-7 thin fanned blades with two lighter tips, shadowless decoration", function()
		local grass = PropArt.Tints("starter").grass
		local _, _, gv = grass:ToHSV()
		for seed = 1, 40 do
			local model = PropArt.GrassTuft(seed, grass)
			local blades, tips = {}, {}
			for _, p in ipairs(parts(model)) do
				t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.CastShadow, "decoration")
				t.ok(p.Size.X <= 0.16, "thin")
				if p.Name == "Blade" then
					table.insert(blades, p)
				elseif p.Name == "BladeTip" then
					table.insert(tips, p)
				end
			end
			t.ok(#blades >= 5 and #blades <= 7, #blades .. " blades")
			t.eq(#tips, 2, "two sunlit tips")
			for _, tip in ipairs(tips) do
				local _, _, v = tip.Color:ToHSV()
				t.ok(v > gv, "a tip is lighter than the grass")
			end
			-- Fanned: each blade leans away from the root (its top further out).
			local out = 0
			for _, p in ipairs(blades) do
				local top = (p.CFrame * t.roblox.Vector3.new(0, p.Size.Y / 2, 0))
				local foot = (p.CFrame * t.roblox.Vector3.new(0, -p.Size.Y / 2, 0))
				local reachTop = Vector2.new(top.X, top.Z).Magnitude
				local reachFoot = Vector2.new(foot.X, foot.Z).Magnitude
				out += if reachTop > reachFoot then 1 else 0
				t.ok(
					foot.Y < 0.05 and top.Y > 0.3 and top.Y < 1.3,
					"rooted in the ground, standing up, knee height at most"
				)
			end
			t.ok(out >= #blades - 1, out .. " of " .. #blades .. " blades lean outward")
		end
	end)

	t.test(
		"FOR-04: tufts gather at the forest's fringe, the verges, the rocks and the fences, never on a road",
		function()
			local problems = {}
			local kinds = { fringe = 0, verge = 0, rock = 0 }
			local rocks = {}
			for _, b in ipairs(WorldPlan.Boulders()) do
				table.insert(rocks, { b.position.X, b.position.Z, b.size })
			end
			for _, c in ipairs(WorldPlan.BoulderClusters()) do
				for _, r in ipairs(c.rocks) do
					table.insert(rocks, { r.position.X, r.position.Z, r.size })
				end
			end
			local total = 0
			for cx = -30, 29 do
				for cz = -30, 29 do
					for _, tuft in ipairs(WorldPlan.TuftCell(cx, cz)) do
						total += 1
						local x, z = tuft.x, tuft.z
						local here = string.format("a tuft at (%.0f, %.0f)", x, z)
						if TerrainGen.RoadClearance(x, z) < 0.6 then
							table.insert(problems, here .. " on a road")
						end
						if WorldLayout.FlatWeight(x, z) > 0 then
							table.insert(problems, here .. " in town or on the plots")
						end
						if TerrainGen.WaterLevelAt(x, z) ~= nil then
							table.insert(problems, here .. " in the water")
						end
						if math.abs(tuft.y - TerrainGen.HeightAt(x, z)) > 1e-6 then
							table.insert(problems, here .. " off the ground")
						end
						local biome = BiomeData.At(x, z)
						if biome and (biome.id == "snow" or biome.id == "volcano") then
							table.insert(problems, here .. " on " .. biome.id)
						end
						local roads = TerrainGen.RoadClearance(x, z)
						if roads <= 3.6 then
							kinds.verge += 1
						else
							local nearRock = false
							for _, r in ipairs(rocks) do
								if Vector2.new(x - r[1], z - r[2]).Magnitude < r[3] then
									nearRock = true
									break
								end
							end
							if nearRock then
								kinds.rock += 1
							else
								kinds.fringe += 1
							end
						end
					end
				end
			end
			t.ok(#problems == 0, report(problems))
			for kind, n in pairs(kinds) do
				t.ok(n > 30, string.format("%d tufts by the %ss", n, kind))
			end
			local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan")
			for i = 1, 30 do
				local cx, cz = (i * 7) % 40 - 20, (i * 11) % 40 - 20
				t.eq(again.TuftCell(cx, cz), WorldPlan.TuftCell(cx, cz), "the same tufts on every client")
			end
			t.ok(total > 1000, total .. " tufts in the middle of the map")
		end
	)
end
