--!nocheck
-- Lane R: the Bayou's numbers, and that they sit on what Builder reserved.
return function(t)
	local BayouData = t.load("ReplicatedStorage/Shared/Regions/BayouData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BiomeData = t.shared("BiomeData")

	t.test("the centre, radius and stage mirror WorldLayout and BiomeData", function()
		local region = WorldLayout.Bayou
		t.eq(BayouData.Centre.x, region.x)
		t.eq(BayouData.Centre.z, region.z)
		t.eq(BayouData.Radius, region.radius)
		t.eq(BayouData.NeedsStage, 2)
		t.eq(BiomeData.Get("bayou").needsStage, BayouData.NeedsStage)
		t.eq(BiomeData.RegionDiscs.bayou.x, region.x)
		t.eq(BiomeData.RegionDiscs.bayou.z, region.z)
		t.eq(BiomeData.RegionDiscs.bayou.radius, region.radius)
	end)

	t.test("the mud zones, shack, landing and rare spot are Builder's anchors", function()
		t.eq(#BayouData.MudZones, #WorldPlan.MudZones)
		for i, zone in ipairs(WorldPlan.MudZones) do
			local mine = BayouData.MudZones[i]
			t.eq({ mine.id, mine.x, mine.z, mine.radius }, { zone.id, zone.x, zone.z, zone.radius })
		end
		t.eq(BayouData.BaitShackSpot.x, WorldPlan.BaitShackSpot.x)
		t.eq(BayouData.BaitShackSpot.z, WorldPlan.BaitShackSpot.z)
		local landing = WorldPlan.BayouLogLanding
		t.eq({ BayouData.Landing.x, BayouData.Landing.z, BayouData.Landing.sx, BayouData.Landing.sz }, {
			landing.x,
			landing.z,
			landing.sx,
			landing.sz,
		})
		local spawn = nil
		for _, s in ipairs(WorldPlan.UniqueItemSpawns) do
			if s.id == "bayou" then
				spawn = s
			end
		end
		t.eq({ BayouData.UniqueSpot.x, BayouData.UniqueSpot.z }, { spawn.x, spawn.z })
		local j = nil
		for _, junction in ipairs(WorldLayout.Junctions) do
			if junction.name == "Bayou" then
				j = junction
			end
		end
		t.eq({ BayouData.Junction.x, BayouData.Junction.z, BayouData.Junction.radius }, { j.at.X, j.at.Y, j.radius })
	end)

	t.test("mud discs are 18 to 30 studs, four of them, all inside the basin", function()
		t.eq(#BayouData.MudZones, 4)
		for _, z in ipairs(BayouData.MudZones) do
			t.ok(z.radius >= 18 and z.radius <= 30, z.id)
			local d = math.sqrt((z.x - BayouData.Centre.x) ^ 2 + (z.z - BayouData.Centre.z) ^ 2)
			t.ok(d + z.radius <= BayouData.Radius, z.id .. " leaves the basin")
		end
	end)

	t.test(
		"the boardwalk loop is about 40 radius, 8 wide, and keeps off the junction, the landing and the road",
		function()
			local b = BayouData.Boardwalk
			t.ok(b.radius >= 36 and b.radius <= 44)
			t.eq(b.width, 8)
			local j = BayouData.Junction
			local dj = math.sqrt((b.x - j.x) ^ 2 + (b.z - j.z) ^ 2)
			t.ok(dj > b.radius + b.width / 2 + j.radius + 4, "the ring clears the junction circle")
			local l = BayouData.Landing
			-- The ring's nearest approach to the landing box.
			local nx = math.clamp(b.x, l.x - l.sx / 2, l.x + l.sx / 2)
			local nz = math.clamp(b.z, l.z - l.sz / 2, l.z + l.sz / 2)
			local dl = math.sqrt((b.x - nx) ^ 2 + (b.z - nz) ^ 2)
			t.ok(dl > b.radius + b.width / 2 + 3, "the ring clears the log landing")
			local roads = {}
			for _, road in ipairs(WorldLayout.Roads) do
				if road.name == "BayouRoad" then
					roads = road
				end
			end
			for i = 0, 63 do
				local a = i / 64 * math.pi * 2
				local p = t.roblox.Vector2.new(b.x + math.cos(a) * b.radius, b.z + math.sin(a) * b.radius)
				local d = WorldLayout.PolylineDistance(p, roads.points)
				t.ok(d > roads.width / 2 + b.width / 2 + 2, string.format("the ring is %.1f off BayouRoad at %d", d, i))
			end
		end
	)

	t.test("the Bait Shack stands on the boardwalk's edge and the counter is on the deck", function()
		local s = BayouData.Shack
		local b = BayouData.Boardwalk
		local d = math.sqrt((s.x - b.x) ^ 2 + (s.z - b.z) ^ 2)
		t.ok(math.abs(d - b.radius) <= b.width / 2 + 1, "the shack is on the ring")
		local cx, cz = BayouData.CounterSpot()
		local dc = math.sqrt((cx - b.x) ^ 2 + (cz - b.z) ^ 2)
		t.ok(math.abs(dc - b.radius) <= b.width / 2, "the counter is over the deck")
	end)

	t.test("Wader Boots: $2,000 plus 20 u³ of Bog Cypress planks", function()
		local boots = BayouData.WaderBoots
		t.eq(boots.priceCash, 2000)
		t.eq(boots.planksU3, 20)
		t.eq(boots.woodId, "bogcypress")
		t.eq(boots.gearId, "WaderBoots")
	end)

	t.test("the budgets are the brief's caps", function()
		local b = BayouData.Budgets
		t.ok(b.trees <= 50 and b.lights <= 4 and b.landmark <= 60 and b.boardwalk <= 60 and b.baitShack <= 40)
		t.ok(b.scatterPiece <= 10)
		t.ok(BayouData.LanternCount <= 4 and BayouData.LanternRange <= 16)
		t.eq(BiomeData.Get("bayou").trees.bogcypress <= b.trees, true)
	end)

	t.test("no tree is planted in the Bayou's own build, and every cypress is near the landing", function()
		local trees = WorldPlan.RegionTrees()
		local n = 0
		local l = BayouData.Landing
		for _, spot in ipairs(trees) do
			if spot.biome == "bayou" then
				n += 1
				t.eq(spot.woodId, "bogcypress")
				t.ok(not BayouData.Blocked(spot.position.X, spot.position.Z, 0), "a cypress in the build")
				local d = math.sqrt((spot.position.X - l.x) ^ 2 + (spot.position.Z - l.z) ^ 2)
				t.ok(d <= BayouData.Budgets.treesNearLanding, string.format("a cypress %.0f from the landing", d))
			end
		end
		t.ok(n >= 30 and n <= BayouData.Budgets.trees, n .. " cypress")
	end)
end
