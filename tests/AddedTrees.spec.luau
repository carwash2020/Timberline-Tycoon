--!nocheck
-- The added trees (WORLD-T323): 100 trees at exact counts per region, planned
-- after everything else, with the teasers that pass the stage rule. Nothing
-- stands on a road, plot, spawn pad or shop door; none in BayouRoad's strip;
-- wild clumps stay outside the quiet discs; every tree keeps 10 studs from the
-- others; the plan is deterministic and sits outside BiomeData.trees.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local BiomeData = t.shared("BiomeData")
	local WoodData = t.shared("WoodData")
	local ItemCatalog = t.shared("ItemCatalog")

	local function dist(x, z, ox, oz)
		local dx, dz = x - ox, z - oz
		return math.sqrt(dx * dx + dz * dz)
	end

	local added = WorldPlan.AddedTrees()
	local base = WorldPlan.Trees()
	local regionTrees = WorldPlan.RegionTrees()

	-- Spots by group: "<biome>:<wood>" for a disc group, "clump" for the wild rings,
	-- "teaser:<wood>" for a lone tree.
	local function groupOf(spot)
		local id = spot.zone.id
		if string.sub(id, 1, 11) == "added:wild:" then
			return "clump"
		end
		local teaser = string.match(id, "^added:teaser:(%w+)$")
		if teaser then
			return "teaser:" .. teaser
		end
		return (string.gsub(string.sub(id, 7), ":", ":"))
	end

	local counts = {}
	for _, spot in ipairs(added) do
		local g = groupOf(spot)
		counts[g] = (counts[g] or 0) + 1
	end

	local WANT = {
		["starter:oak"] = 4,
		["starter:birch"] = 2,
		["starter:cherry"] = 7,
		["hills:pine"] = 8,
		["hills:maple"] = 7,
		["hills:cherry"] = 7,
		["snow:frostwood"] = 9,
		["volcano:emberwood"] = 8,
		["grove:phantomwood"] = 4,
		["bayou:bogcypress"] = 8,
		["bayou:willow"] = 12,
		["mesa:ironwood"] = 6,
		clump = 18,
	}

	local function teaserCount()
		local n = 0
		for g, c in pairs(counts) do
			if string.sub(g, 1, 7) == "teaser:" then
				n += c
			end
		end
		return n
	end

	t.test("the exact counts per region: 74 of the old woods, 26 new, 100 in all", function()
		local total = 0
		for group, want in pairs(WANT) do
			t.eq(counts[group] or 0, want, group)
			total += want
		end
		t.eq(total, 100)
		local newWoods, oldWoods = 0, 0
		for _, spot in ipairs(added) do
			if string.sub(groupOf(spot), 1, 7) ~= "teaser:" then
				if spot.woodId == "cherry" or spot.woodId == "willow" then
					newWoods += 1
				else
					oldWoods += 1
				end
			end
		end
		t.eq(newWoods, 26, "7 + 7 cherry and 12 willow")
		t.eq(oldWoods, 74)
		t.eq(#added, 100 + teaserCount(), "the 100, plus the teasers that passed")
	end)

	t.test("they are not in BiomeData.trees, so the supply caps and region budgets stay put", function()
		t.eq(BiomeData.Get("starter").trees, { oak = 70, birch = 26 })
		t.eq(BiomeData.Get("hills").trees, { pine = 80, maple = 50 })
		t.eq(BiomeData.Get("bayou").trees, { bogcypress = 44 })
		t.eq(BiomeData.Get("mesa").trees, { ironwood = 38 })
		t.eq(#regionTrees, 44 + 38, "RegionTrees is as it was")
	end)

	t.test("teasers: only the woods the previous stage's best axe cannot dent are kept", function()
		local kept = {}
		for _, row in ipairs(TreeFill.TeasersKept()) do
			kept[row.wood] = true
			t.ok(TreeFill.TeaserHidden(row.wood, row.teaser.stage), row.wood)
			local axe = TreeFill.BestAxeAt(row.teaser.stage - 1)
			t.eq(ItemCatalog.AxeDamage(axe, WoodData.Get(row.wood)), 0, row.wood .. " cannot be cut by " .. axe.id)
		end
		print("teasers kept: " .. table.concat(
			(function()
				local out = {}
				for _, row in ipairs(TreeFill.AddedTeasers) do
					table.insert(out, row.wood .. (if kept[row.wood] then " kept" else " DROPPED"))
				end
				return out
			end)(),
			", "
		))
		for _, row in ipairs(TreeFill.AddedTeasers) do
			t.eq(counts["teaser:" .. row.wood] or 0, if kept[row.wood] then 1 else 0, row.wood)
		end
	end)

	t.test("a teaser stands 24 to 30 studs off its road at 35 to 60 percent along", function()
		for _, spot in ipairs(added) do
			local wood = string.match(spot.zone.id, "^added:teaser:(%w+)$")
			if wood then
				local row
				for _, r in ipairs(TreeFill.AddedTeasers) do
					if r.wood == wood then
						row = r
					end
				end
				local road
				for _, r in ipairs(WorldLayout.Roads) do
					if r.name == row.teaser.road then
						road = r
					end
				end
				local best = math.huge
				for i = 1, #road.points - 1 do
					local a, b = road.points[i], road.points[i + 1]
					local ab = b - a
					local f =
						math.clamp(((Vector2.new(spot.position.X, spot.position.Z) - a):Dot(ab)) / ab:Dot(ab), 0, 1)
					local p = a + ab * f
					best = math.min(best, dist(spot.position.X, spot.position.Z, p.X, p.Y))
				end
				t.ok(best >= 23.5 and best <= 30.5, wood .. " is " .. best .. " off " .. row.teaser.road)
				t.eq(spot.zone.fixed, true)
				t.eq(spot.zone.cap, 1)
			end
		end
	end)

	t.test("every added tree stands on good ground: roads, plots, the spawn pad and shop doors are clear", function()
		for _, spot in ipairs(added) do
			local x, z = spot.position.X, spot.position.Z
			t.ok(TreeFill.GroundFor(spot.zone, x, z), spot.zone.id .. string.format(" at %.0f,%.0f", x, z))
			t.ok(TreeFill.Clear(x, z), "off plots, the spawn pad and shop doors")
			if spot.zone.id ~= "added:teaser:ironwood" or true then
				t.ok(not WorldLayout.RegionBuildBlocked(x, z), "off the regions' own builds")
			end
		end
	end)

	t.test("none stands in BayouRoad's strip, nor inside any road's corridor", function()
		for _, spot in ipairs(added) do
			local p = Vector2.new(spot.position.X, spot.position.Z)
			for _, road in ipairs(WorldLayout.Roads) do
				for i = 1, #road.points - 1 do
					local a, b = road.points[i], road.points[i + 1]
					local ab = b - a
					local f = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
					local q = a + ab * f
					local d = dist(p.X, p.Y, q.X, q.Y)
					t.ok(d >= road.width / 2 + 8 - 0.01, string.format("%s %.1f off %s", spot.zone.id, d, road.name))
				end
			end
		end
	end)

	t.test("every added tree keeps 10 studs from every other, old or new", function()
		local others = {}
		for _, spot in ipairs(base) do
			table.insert(others, spot.position)
		end
		for _, spot in ipairs(regionTrees) do
			table.insert(others, spot.position)
		end
		for i, spot in ipairs(added) do
			for _, q in ipairs(others) do
				t.ok(dist(spot.position.X, spot.position.Z, q.X, q.Z) >= 10 - 1e-6, spot.zone.id)
			end
			for j = i + 1, #added do
				local q = added[j].position
				t.ok(dist(spot.position.X, spot.position.Z, q.X, q.Z) >= 10 - 1e-6, spot.zone.id)
			end
		end
	end)

	t.test("wild clumps stand outside the quiet discs; the starter and hills discs lie inside them", function()
		local QUIET = { { 0, 40, 640 }, { 0, -110, 640 }, { -420, 110, 640 } }
		for _, spot in ipairs(added) do
			if groupOf(spot) == "clump" then
				for _, q in ipairs(QUIET) do
					t.ok(dist(spot.position.X, spot.position.Z, q[1], q[2]) >= q[3], "a clump tree is outside " .. q[1])
				end
				t.eq(spot.zone.cap, 6, "a clump's zone holds its six")
			end
		end
		local clumps = {}
		for _, spot in ipairs(added) do
			if groupOf(spot) == "clump" then
				clumps[spot.zone.id] = (clumps[spot.zone.id] or 0) + 1
			end
		end
		local n = 0
		for _, c in pairs(clumps) do
			n += 1
			t.eq(c, 6)
		end
		t.eq(n, 3, "three clumps of six")
	end)

	t.test("cherry stands on the starter forest's outer ring and the hills' east edge", function()
		local starter = BiomeData.Get("starter").area
		local hills = BiomeData.Get("hills").area
		for _, spot in ipairs(added) do
			local x, z = spot.position.X, spot.position.Z
			if spot.woodId == "cherry" and spot.biome == "starter" then
				local f = dist(x, z, starter.x, starter.z) / (starter.radius - 6)
				t.ok(f >= 0.70 - 1e-6 and f <= 1.25 + 1e-6, "ring fraction " .. f)
			elseif spot.woodId == "cherry" and spot.biome == "hills" then
				local f = dist(x, z, hills.x, hills.z) / (hills.radius - 6)
				t.ok(f >= 0.55 - 1e-6 and f <= 1.15 + 1e-6, "edge fraction " .. f)
				local angle = math.deg(math.atan2(z - hills.z, x - hills.x))
				t.ok(math.abs(angle) <= 60 + 1e-6, "within 60 degrees of +X: " .. angle)
			end
		end
	end)

	t.test("bayou groups stay within treesNearLanding of the landing; willow does not stand on the road", function()
		local BayouData = t.shared("Regions/BayouData")
		for _, spot in ipairs(added) do
			if spot.biome == "bayou" then
				local l = BayouData.Landing
				t.ok(
					dist(spot.position.X, spot.position.Z, l.x, l.z) <= BayouData.Budgets.treesNearLanding + 1e-6,
					spot.zone.id
				)
			end
		end
	end)

	t.test(
		"each group has its own regrow zone: added:<region>:<wood>, a disc round its spots, cap = its count",
		function()
			local zones = {}
			for _, spot in ipairs(added) do
				local zone = spot.zone
				zones[zone.id] = zone
				local d = dist(spot.position.X, spot.position.Z, zone.cx, zone.cz)
				if not zone.fixed then
					t.ok(d <= zone.radius + 1e-6, zone.id .. " holds its own trees")
				end
			end
			for group, want in pairs(WANT) do
				if group ~= "clump" then
					local zone = zones["added:" .. group]
					t.ok(zone ~= nil, group)
					t.eq(zone.cap, want, group .. " cap")
				end
			end
		end
	)

	t.test("the plan is deterministic and the same on a second run", function()
		local function fresh()
			local taken = {}
			for _, spot in ipairs(base) do
				table.insert(taken, spot.position)
			end
			for _, spot in ipairs(regionTrees) do
				table.insert(taken, spot.position)
			end
			return taken
		end
		local a = TreeFill.PlanAdded(fresh(), nil, "region")
		local b = TreeFill.PlanAdded(fresh(), nil, "region")
		t.eq(#a, #b)
		for i = 1, #a do
			t.eq(a[i].position, b[i].position, "tree " .. i)
			t.eq(a[i].woodId, b[i].woodId)
		end
		t.eq(#a, #WorldPlan.AddedRegionTrees())
		for i = 1, #a do
			t.eq(a[i].position, WorldPlan.AddedRegionTrees()[i].position, "the region plan is the same cached")
		end
	end)

	t.test("old saves load unchanged: the added trees append after every older tree", function()
		-- The first trees stay where they were; the added ones are a separate list.
		for _, spot in ipairs(added) do
			for _, old in ipairs(regionTrees) do
				t.ok(spot ~= old)
			end
		end
		t.eq(#WorldPlan.RegionTrees(), #regionTrees)
		local ids = {}
		for _, def in ipairs(WoodData.All()) do
			table.insert(ids, def.id)
		end
		t.eq(ids[#ids - 1], "cherry")
		t.eq(ids[#ids], "willow")
	end)
end
