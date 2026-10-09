--!nocheck
-- Town trees (Connor, 8 October 2026: "we need more choppable trees in the
-- spawn area too, near the pad, by the dealership ... it's a lumberjack
-- game"). TreeFill.TownRings plants clusters of ordinary felling trees in
-- and round the town from TownTreeData's sites: the counts per quality tier
-- (budgets, a lower tier's trees are a subset of a higher one's), the
-- placement rules (inside the site's disc, a gap apart, deterministic, never
-- on a road, path, floor, building, prop, lamp, sign, the parking lot or its
-- pull-outs, a loading pad, the sell area, the spawn lane, a shop door, the
-- Land Office queue, the gondola's lane, a townsperson's walk, a plot, water
-- or steep ground), and that a felled tree regrows only on ground that obeys
-- the same rules (TreeFill.GroundFor). They are 'wild' trees outside
-- BiomeData's counts, so the economy model is unchanged.
return function(t)
	local roblox = t.roblox
	local Vector2, Vector3, CFrame = roblox.Vector2, roblox.Vector3, roblox.CFrame
	local TownTreeData = t.shared("TownTreeData")
	local QualityBudgets = t.shared("QualityBudgets")
	local BiomeData = t.shared("BiomeData")
	local NPCData = t.shared("NPCData")
	local PlotData = t.shared("PlotData")
	local ForestLogic = t.shared("ForestLogic")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	local COMMON = { oak = true, birch = true, pine = true, maple = true }
	-- The three shop doors (the front of each building, where its path ends).
	local DOORS = {
		{ name = "Dealership", x = 189, z = 91 },
		{ name = "Tool Shed", x = -84, z = 88 },
		{ name = "General Store", x = -100, z = 159 },
	}

	local function dist(x, z, ox, oz)
		local dx, dz = x - ox, z - oz
		return math.sqrt(dx * dx + dz * dz)
	end

	local function outsideRect(x, z, r)
		local dx = math.max(r.x0 - x, 0, x - r.x1)
		local dz = math.max(r.z0 - z, 0, z - r.z1)
		return math.sqrt(dx * dx + dz * dz)
	end

	local function segmentDistance(x, z, ax, az, bx, bz)
		return (WorldLayout.SegmentDistance(Vector2.new(x, z), Vector2.new(ax, az), Vector2.new(bx, bz)))
	end

	local function townTrees(list)
		local out = {}
		for _, spot in ipairs(list) do
			local zone = spot.zone
			if zone and string.sub(zone.id, 1, 5) == "town:" then
				table.insert(out, spot)
			end
		end
		return out
	end

	local function zoneOf(site)
		return "town:" .. site.id
	end

	---------------------------------------------------------------------------
	-- The numbers
	---------------------------------------------------------------------------

	t.test("tiers: the quality budgets' names, growing counts, each inside its budget", function()
		t.eq(TownTreeData.Tiers, { "low", "medium", "high" })
		for _, tier in ipairs(TownTreeData.Tiers) do
			t.eq(QualityBudgets.For(tier).Tier, tier, tier .. " is a QualityBudgets tier")
			t.ok(TownTreeData.Count(tier) <= TownTreeData.Budget[tier], tier .. " is over its budget")
		end
		local low, medium, high = TownTreeData.Count("low"), TownTreeData.Count("medium"), TownTreeData.Count("high")
		t.ok(low >= 40, "low plants a town's worth: " .. low)
		t.ok(low < medium and medium < high, string.format("%d < %d < %d", low, medium, high))
		-- A phone is the tightest: low is what ships, and it is the smallest.
		t.eq(TownTreeData.ShippedTier, "low")
		t.eq(TownTreeData.Count("anything else"), low, "an unknown tier is the lowest")
		-- Each tier's sites are the lower tier's plus its own, in the same order.
		local function ids(tier)
			local out = {}
			for _, site in ipairs(TownTreeData.SitesFor(tier)) do
				table.insert(out, site.id)
			end
			return out
		end
		local lowIds, mediumIds, highIds = ids("low"), ids("medium"), ids("high")
		for i, id in ipairs(lowIds) do
			t.eq(mediumIds[i], id, "medium starts with low's sites")
		end
		for i, id in ipairs(mediumIds) do
			t.eq(highIds[i], id, "high starts with medium's sites")
		end
		t.eq(#highIds, #TownTreeData.Sites)
	end)

	t.test("sites: unique ids, a small disc, a handful of trees, a known tier", function()
		local seen = {}
		for _, site in ipairs(TownTreeData.Sites) do
			t.ok(not seen[site.id], "duplicate site " .. site.id)
			seen[site.id] = true
			t.ok(site.radius >= 6 and site.radius <= TownTreeData.MaxClusterRadius, site.id .. " radius")
			t.ok(site.want >= 1 and site.want <= 5, site.id .. " want")
			t.ok(TownTreeData.TierIndex(site.tier) >= 1 and table.find(TownTreeData.Tiers, site.tier), site.id)
			t.ok(#site.why > 10, site.id .. " says where it is")
		end
		-- No zone is so wide that its regrow wanders far from the cluster.
		t.ok(TownTreeData.MaxClusterRadius <= 16)
		t.ok(TownTreeData.Gap >= 11, "a gap a player and a truck can pass through")
	end)

	t.test("the walks and the gondola station the planner avoids are NPCData's and WorldPlan's", function()
		local routes = {}
		for _, npc in ipairs(NPCData.All()) do
			if npc.route then
				routes[npc.id] = npc.route
			end
		end
		local count = 0
		for _, walk in ipairs(TownTreeData.Walks) do
			local route = routes[walk.id]
			t.ok(route ~= nil, walk.id .. " still walks")
			t.eq(#route, #walk.points, walk.id .. " waypoints")
			for i, w in ipairs(route) do
				t.ok(
					math.abs(w.x - walk.points[i][1]) <= 1 and math.abs(w.z - walk.points[i][2]) <= 1,
					walk.id .. " waypoint " .. i
				)
			end
			count += 1
		end
		-- Every walker is listed: a new route must be added to the data.
		local walkers = 0
		for _ in pairs(routes) do
			walkers += 1
		end
		t.eq(count, walkers, "every NPC route is in TownTreeData.Walks")
		t.eq(
			{ TownTreeData.GondolaStation.x, TownTreeData.GondolaStation.z },
			{ WorldPlan.TownGondolaSpot.X, WorldPlan.TownGondolaSpot.Z }
		)
		-- The sight line to the lighthouse's lamp runs from the spawn pad to the lamp.
		local lamp = WorldPlan.Lighthouse().lamp
		local sight
		for _, lane in ipairs(TownTreeData.Lanes) do
			if lane.name == "LighthouseSight" then
				sight = lane
			end
		end
		t.ok(sight ~= nil, "the lighthouse's sight line is kept clear")
		t.eq({ sight.ax, sight.az }, { WorldPlan.Town().spawn.X, WorldPlan.Town().spawn.Z })
		t.eq({ sight.bx, sight.bz }, { lamp.X, lamp.Z })
		t.ok(sight.half >= 10, "at least the 10 studs WorldPlan.spec asks")
	end)

	---------------------------------------------------------------------------
	-- The planner
	---------------------------------------------------------------------------

	t.test("every site plants all of its trees: in its disc, common woods, a zone with a cap", function()
		for _, tier in ipairs(TownTreeData.Tiers) do
			local spots = TreeFill.TownRings({}, nil, tier)
			t.eq(#spots, TownTreeData.Count(tier), tier .. ": the count")
			local per = {}
			for _, spot in ipairs(spots) do
				per[spot.zone.id] = (per[spot.zone.id] or 0) + 1
				t.eq(spot.biome, "wild", "the wild biome, so BiomeData's counts do not move")
				t.ok(COMMON[spot.woodId], "a common wood: " .. spot.woodId)
			end
			for _, site in ipairs(TownTreeData.SitesFor(tier)) do
				t.eq(per[zoneOf(site)], site.want, site.id .. " plants " .. site.want)
			end
		end
		for _, spot in ipairs(TreeFill.TownRings({}, nil, "high")) do
			local zone = spot.zone
			local site
			for _, s in ipairs(TownTreeData.Sites) do
				if zoneOf(s) == zone.id then
					site = s
				end
			end
			t.ok(site ~= nil, zone.id .. " is a site")
			t.eq(zone.cx, site.cx)
			t.eq(zone.cz, site.cz)
			t.eq(zone.radius, site.radius, "a small zone")
			t.eq(zone.cap, site.want, "capped at the cluster")
			t.ok(
				dist(spot.position.X, spot.position.Z, site.cx, site.cz) <= site.radius + 1e-6,
				site.id .. " in its disc"
			)
		end
	end)

	t.test("the same seed plants the same trees, and a lower tier's trees are a higher tier's", function()
		local first = TreeFill.TownRings({}, nil, "high")
		local second = TreeFill.TownRings({}, nil, "high")
		t.eq(#first, #second)
		for k = 1, #first do
			t.eq(first[k].position, second[k].position)
			t.eq(first[k].woodId, second[k].woodId)
		end
		local byKey = {}
		for _, spot in ipairs(first) do
			byKey[string.format("%s|%.3f|%.3f|%s", spot.zone.id, spot.position.X, spot.position.Z, spot.woodId)] = true
		end
		for _, tier in ipairs({ "low", "medium" }) do
			for _, spot in ipairs(TreeFill.TownRings({}, nil, tier)) do
				local key =
					string.format("%s|%.3f|%.3f|%s", spot.zone.id, spot.position.X, spot.position.Z, spot.woodId)
				t.ok(byKey[key], tier .. " tree missing from high: " .. key)
			end
		end
		-- The pause hook changes nothing.
		local paused = 0
		local third = TreeFill.TownRings({}, function()
			paused += 1
		end, "high")
		t.ok(paused > 0)
		t.eq(#third, #first)
		for k = 1, #first do
			t.eq(third[k].position, first[k].position)
		end
	end)

	t.test("town trees keep the gap from each other and from every other tree", function()
		local gap = TownTreeData.Gap
		local all = WorldPlan.Trees()
		local town = townTrees(all)
		t.eq(#town, TownTreeData.Count(TownTreeData.ShippedTier), "WorldPlan.Trees carries the shipped tier")
		for i = 1, #town do
			for j = i + 1, #town do
				local a, b = town[i].position, town[j].position
				t.ok(dist(a.X, a.Z, b.X, b.Z) >= gap - 0.05, "two town trees closer than the gap")
			end
		end
		local isTown = {}
		for _, spot in ipairs(town) do
			isTown[spot] = true
		end
		for _, spot in ipairs(town) do
			for _, other in ipairs(all) do
				if not isTown[other] then
					local p, q = spot.position, other.position
					t.ok(dist(p.X, p.Z, q.X, q.Z) >= gap - 0.05, "a town tree against the forest's")
				end
			end
		end
		-- Appended last: the trees before them keep their places.
		local first
		for i, spot in ipairs(all) do
			if isTown[spot] then
				first = first or i
			else
				t.ok(first == nil, "a town tree is not followed by another kind")
			end
		end
		t.ok(first and first > 730)
	end)

	t.test("town trees are not in BiomeData's counts (the economy model's inputs)", function()
		local biomes = {}
		for _, biome in ipairs(BiomeData.All()) do
			biomes[biome.id] = true
		end
		for _, spot in ipairs(townTrees(WorldPlan.Trees())) do
			t.ok(not biomes[spot.biome], "town tree in biome " .. spot.biome)
			t.eq(spot.biome, "wild")
		end
		-- The economy tools read the counts, never the planner.
		local fs = require("@lune/fs")
		for _, path in ipairs({ "tools/economy.luau", "tools/economy1.luau" }) do
			local source = fs.readFile(path)
			t.ok(not string.find(source, "TreeFill", 1, true), path .. " reads TreeFill")
			t.ok(not string.find(source, "WorldPlan.Trees", 1, true), path .. " reads WorldPlan.Trees")
		end
	end)

	t.test("planning the town's trees is quick, and touches nothing the forest's plan did", function()
		local start = os.clock()
		local spots = TreeFill.TownRings({}, nil, "high")
		local took = os.clock() - start
		print(string.format("town trees planned: %d spots in %.1f ms (Lune)", #spots, took * 1000))
		t.ok(took < 1, string.format("%.2f s", took))
	end)

	---------------------------------------------------------------------------
	-- Where they may not stand
	---------------------------------------------------------------------------

	-- Everything MapBuilder builds in town (as WorldPlan.spec builds it), as
	-- XZ boxes: { label, x0, z0, x1, z1 } for each part low enough to matter.
	local boxes
	local function townBoxes()
		if boxes then
			return boxes
		end
		local town = WorldPlan.Town()
		local out = {}
		local function add(label, model, cf)
			Kit.placeAt(model, cf)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local lo, hi
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
					if lo.Y < 6 and hi.Y > 0.3 then
						table.insert(out, { label = label, x0 = lo.X, z0 = lo.Z, x1 = hi.X, z1 = hi.Z })
					end
				end
			end
		end
		for _, cf in ipairs(town.lamps) do
			add("lamp", BuildingArt.LampPost(), cf)
		end
		for _, f in ipairs(town.fences) do
			add("fence", BuildingArt.Fence(f.length), f.cframe)
		end
		for _, p in ipairs(town.props) do
			add("prop " .. p.name, BuildingArt.Prop(p.name, p.seed), p.cframe)
		end
		for _, s in ipairs(town.signs) do
			add("sign", BuildingArt.Signpost(s.text), s.cframe)
		end
		add("Murph's camp", BuildingArt.Campsite(), town.campsite)
		add("gondola station", BuildingArt.GondolaStation(), town.gondola)
		add("sawmill", BuildingArt.Sawmill(), town.sawmill)
		add("sell station", BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth), town.sellPad)
		for _, spot in ipairs(town.shops) do
			add(spot.kind, BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
		end
		for _, spot in ipairs(town.scenes) do
			local model = if spot.kind == "forge" then BuildingArt.SkyForgeCourt() else PropArt.Scene(spot.kind)
			add(spot.kind .. " scene", model, spot.cframe)
		end
		add("dealership lot", DealershipLot.Build(), town.displayLot)
		for _, g in ipairs(town.greenery) do
			add("greenery " .. g.kind, BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId), g.cframe)
		end
		boxes = out
		return out
	end

	-- The reasons a town tree may not stand at (x, z), measured on the real
	-- art and layout rather than on the planner's own lists. nil: all clear.
	local gondolaPath
	local function problem(x, z)
		-- Connor's keep-out, and the spawn.
		if x > -60 and x < 60 and z > 80 and z < 140 then
			return "in the sell area"
		end
		if dist(x, z, 0, 40) < 22 then
			return "on the spawn pad"
		end
		if x > -18 and x < 18 and z > 8 and z < 100 then
			return "in the spawn lane"
		end
		for _, door in ipairs(DOORS) do
			if dist(x, z, door.x, door.z) < 12 then
				return "at the " .. door.name .. "'s door"
			end
		end
		if dist(x, z, 147, 86) < 22 then
			return "at the Land Office"
		end
		if segmentDistance(x, z, 147, 86, 112, 74) < 14 then
			return "in the Land Office queue"
		end
		-- The lighthouse lamp stays in view from the spawn pad (the rule
		-- WorldPlan.spec holds every tree to: 10 studs off the line).
		do
			local eye, lamp = WorldPlan.SpawnEye(), WorldPlan.Lighthouse().lamp
			local d, s =
				WorldLayout.SegmentDistance(Vector2.new(x, z), Vector2.new(eye.X, eye.Z), Vector2.new(lamp.X, lamp.Z))
			if d < 10 and eye.Y + (lamp.Y - eye.Y) * s - TerrainGen.HeightAt(x, z) <= 40 then
				return "hiding the lighthouse lamp"
			end
		end
		-- The ornamental trees: trunk to trunk.
		for _, g in ipairs(WorldPlan.Town().greenery) do
			if g.kind == "tree" and dist(x, z, g.cframe.X, g.cframe.Z) < 8.5 then
				return "by an ornamental tree"
			end
		end
		-- Every building, prop, lamp, sign, fence, ornamental tree and the camp.
		for _, b in ipairs(townBoxes()) do
			local d = outsideRect(x, z, b)
			if d < 5 then
				return string.format("%.1f studs from %s", d, b.label)
			end
		end
		-- Roads, paths, the street, floors, the lot.
		if TerrainGen.RoadClearance(x, z) < 10 then
			return "on a road"
		end
		for _, p in ipairs(WorldLayout.TownPaint) do
			if outsideRect(x, z, p) < 6 then
				return "on the " .. p.name
			end
		end
		for _, p in ipairs(WorldLayout.TownFloors) do
			if outsideRect(x, z, p) < 6 then
				return "on the " .. p.name
			end
		end
		if outsideRect(x, z, WorldLayout.ParkingLot) < 10 then
			return "at the parking lot"
		end
		if outsideRect(x, z, TownTreeData.PullOut) < 6 then
			return "in the lot's pull-out lanes"
		end
		for _, pad in ipairs({ WorldLayout.DealershipLoadingPad, WorldLayout.ToolShedLoadingPad }) do
			if outsideRect(x, z, pad) < 10 then
				return "at a loading pad"
			end
		end
		-- The townsfolk.
		for _, npc in ipairs(NPCData.All()) do
			local route = npc.route
			if route then
				for i, w in ipairs(route) do
					local nxt = route[i % #route + 1]
					if segmentDistance(x, z, w.x, w.z, nxt.x, nxt.z) < 6 then
						return "on " .. npc.id .. "'s walk"
					end
				end
			end
			local spot = npc.spot.position or npc.spot.fallback
			if spot and dist(x, z, spot.X, spot.Z) < 10 then
				return "by " .. npc.id
			end
		end
		-- The gondola's first stretch out of town.
		if not gondolaPath then
			local sky = WorldPlan.Sky()
			local town = WorldPlan.Town()
			local station = BuildingArt.GondolaStation()
			Kit.placeAt(station, town.gondola)
			local platform = station.PrimaryPart
			local top = sky.gondolaTop.Position
			gondolaPath = WorldPlan.GondolaPath(sky, platform.CFrame.Position, platform.CFrame.ZVector, top)
		end
		do
			local length = 0
			for i = 1, #gondolaPath - 1 do
				length += (gondolaPath[i + 1] - gondolaPath[i]).Magnitude
			end
			local k = 0
			while k <= 300 do
				local at = WorldPlan.AlongPath(gondolaPath, k / length)
				if dist(x, z, at.X, at.Z) < 14 then
					return "under the gondola, " .. k .. " studs out"
				end
				k += 4
			end
		end
		for _, slot in ipairs(PlotData.Slots) do
			local half = PlotData.Tiers[#PlotData.Tiers].size / 2
			if
				outsideRect(x, z, { x0 = slot.X - half, z0 = slot.Y - half, x1 = slot.X + half, z1 = slot.Y + half })
				< 30
			then
				return "by a plot"
			end
		end
		if WorldLayout.TreeBlocked(x, z) then
			return "on blocked ground"
		end
		if TerrainGen.WaterLevelAt(x, z) ~= nil then
			return "in water"
		end
		if TerrainGen.SlopeAt(x, z) >= 0.5 then
			return "on steep ground"
		end
		return nil
	end

	t.test("no town tree stands on a road, building, shop door, queue, walk, lot, plot or the spawn", function()
		local spots = TreeFill.TownRings({}, nil, "high")
		t.eq(#spots, TownTreeData.Count("high"), "every site is checked")
		local problems = {}
		for _, spot in ipairs(spots) do
			local x, z = spot.position.X, spot.position.Z
			local why = problem(x, z)
			if why then
				table.insert(problems, string.format("%s at (%.1f, %.1f) is %s", spot.zone.id, x, z, why))
			end
		end
		t.ok(#problems == 0, table.concat(problems, "; "))
	end)

	t.test("the check itself: a tree in the sell area, on the street, by a door or on a building is caught", function()
		t.ok(problem(0, 110), "the sell area")
		t.ok(problem(0, 34), "the spawn walk")
		t.ok(problem(-40, 75), "the main street")
		t.ok(problem(189, 84), "the dealership door")
		t.ok(problem(250, 120), "inside the showroom hall")
		t.ok(problem(147, 80), "the Land Office")
		t.ok(problem(60, 20), "the parking lot")
		t.ok(problem(-30, 48), "Murph's camp")
		t.ok(problem(-60, 82), "Rosa's walk")
		t.eq(problem(-60, -25), nil, "open meadow south-west of the pad")
	end)

	t.test("the sell area (x -60 to 60, z 80 to 140) and the spawn lane hold no town tree at any tier", function()
		for _, tier in ipairs(TownTreeData.Tiers) do
			for _, spot in ipairs(TreeFill.TownRings({}, nil, tier)) do
				local x, z = spot.position.X, spot.position.Z
				t.ok(not (x > -60 and x < 60 and z > 80 and z < 140), "a tree in the sell area")
				t.ok(not (x > -18 and x < 18 and z > 8 and z < 100), "a tree in the spawn lane")
				t.ok(dist(x, z, 0, 40) >= 22, "a tree by the pad")
			end
		end
		-- And nothing in the area to regrow into.
		for x = -60, 60, 4 do
			for z = 80, 140, 4 do
				t.ok(not TreeFill.TownGround(x, z), "regrow ground in the sell area")
			end
		end
	end)

	t.test("trees near the spawn pad and the dealership, but never at a door", function()
		local near = { dealership = 0, round = 0, spawn = 0 }
		for _, spot in ipairs(townTrees(WorldPlan.Trees())) do
			local x, z = spot.position.X, spot.position.Z
			-- Round the showroom's door (its west wall: the Land Office and the
			-- door path, the lighthouse's sight line and the forecourt's paths leave
			-- no room closer), and never within 12 of it.
			local d = dist(x, z, 189, 91)
			if d < 70 then
				near.dealership += 1
			end
			if d < 190 then
				near.round += 1
			end
			t.ok(d >= 12, "a tree at the door")
			if dist(x, z, 0, 40) < 110 then
				near.spawn += 1
			end
		end
		t.ok(near.dealership >= 5, near.dealership .. " trees within 70 studs of the dealership door")
		t.ok(near.round >= 15, near.round .. " trees within 190 studs of it")
		t.ok(near.spawn >= 6, near.spawn .. " trees within 110 studs of the spawn pad")
	end)

	---------------------------------------------------------------------------
	-- Felling and regrowing
	---------------------------------------------------------------------------

	t.test("a felled town tree regrows inside its zone, on ground that obeys the same rules", function()
		local seenZones = 0
		for _, site in ipairs(TownTreeData.Sites) do
			local zone = { id = zoneOf(site), cx = site.cx, cz = site.cz, radius = site.radius, cap = site.want }
			local base
			for _, spot in ipairs(TreeFill.TownRings({}, nil, "high")) do
				if spot.zone.id == zone.id then
					base = spot.position
					break
				end
			end
			t.ok(base ~= nil, site.id .. " has a tree")
			local got = 0
			for guard = 1, 150 do
				local n = 0
				local x, z = ForestLogic.FindSpot(zone.cx, zone.cz, zone.radius, 48, function()
					n += 1
					return (guard * 0.173 + n * 0.091) % 1
				end, function(px, pz)
					if dist(px, pz, base.X, base.Z) < 10 then
						return false
					end
					return TreeFill.GroundFor(zone, px, pz)
				end)
				if x and z then
					got += 1
					local why = problem(x, z)
					t.ok(why == nil, string.format("%s regrows at (%.1f, %.1f), %s", site.id, x, z, tostring(why)))
					t.ok(dist(x, z, site.cx, site.cz) <= site.radius + 1e-6, "inside its zone")
				end
			end
			t.ok(got >= 20, string.format("%s yielded %d regrow spots of 150", site.id, got))
			seenZones += 1
		end
		t.eq(seenZones, #TownTreeData.Sites)
	end)

	t.test("GroundFor: a town zone uses the town's ground, any other zone the general rule", function()
		-- Behind the sawmill is inside the flat town: the general rule refuses it
		-- (WorldPlan.GoodGround: not in town), the town's ground allows it.
		local x, z = 30, 158
		t.ok(TreeFill.TownGround(x, z))
		t.ok(not TreeFill.Ground(x, z), "the forest's rule says no in the flat town")
		t.ok(TreeFill.GroundFor({ id = "town:mill", cx = x, cz = z, radius = 10 }, x, z))
		t.ok(not TreeFill.GroundFor({ id = "wild", cx = x, cz = z, radius = 10 }, x, z))
		t.ok(not TreeFill.GroundFor(nil, x, z))
		-- A point the town's ground refuses (the street) is refused for a town zone.
		t.ok(not TreeFill.GroundFor({ id = "town:mill", cx = -40, cz = 75, radius = 10 }, -40, 75))
		-- Open country is the same for both.
		t.eq(TreeFill.GroundFor({ id = "wild" }, 300, -300), TreeFill.Ground(300, -300))
	end)
end
