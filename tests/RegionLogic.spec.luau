--!nocheck
-- Named regions: stands, limited bleed, the hidden reach, trails, and
-- which trees stay awake around a player.
return function(t)
	local RegionLogic = t.shared("RegionLogic")
	local BiomeData = t.shared("BiomeData")
	local WoodData = t.shared("WoodData")

	local function here(x, z, y)
		return RegionLogic.At(x, z, y)
	end

	t.test("every built biome is a named region with a shape and a palette", function()
		local want =
			{ starter = "plains", hills = "hills", snow = "plateau", volcano = "cone", grove = "hollow", sky = "sky" }
		for id, shape in pairs(want) do
			local biome = BiomeData.Get(id)
			local area = biome.area
			local place = here(area.x, area.z, area.y or 0)
			t.ok(place, id .. " has a place")
			t.eq(place.base, id)
			t.eq(place.shape, shape)
			t.ok(#place.palette > 0, id .. " names a palette")
			t.ok(RegionLogic.Toast(place.id), id .. " has a toast")
		end
	end)

	t.test("the beach and the river banks are places of their own", function()
		local coast = t.load("ReplicatedStorage/Shared/World/WorldLayout").Coast
		local strand = here(coast.shoreX - 20, 0, 0)
		t.eq(strand.base, "strand")
		t.eq(strand.shape, "beach")
		local river = t.load("ReplicatedStorage/Shared/World/WorldLayout").River
		local a = river.points[2]
		local banks = here(a.X + river.width, a.Y, 0)
		t.eq(banks.base, "banks")
		t.eq(banks.shape, "banks")
	end)

	t.test("the open country between regions has no name", function()
		-- Well clear of every disc, the beach and the river: the middle of
		-- the eastern meadow, south of the volcano's approach.
		t.eq(here(400, -400, 0), nil)
	end)

	t.test("meadows rename the place you're in, and the region underneath stays", function()
		for _, meadow in ipairs(RegionLogic.Meadows()) do
			local place = here(meadow.x, meadow.z, 0)
			t.eq(place.base, meadow.region)
			t.eq(place.displayName, meadow.name)
			t.ok(string.find(place.id, meadow.id, 1, true), place.id)
			t.eq(RegionLogic.Base(place.id), meadow.region)
		end
	end)

	t.test("a stand is one species, and the border only borrows a little", function()
		local starter = BiomeData.Get("starter").area
		-- Deep inside one stand cell: every sample is the same kind, and
		-- it belongs to the Starter Forest. The cell is 84 studs, so the
		-- sample stays well inside it.
		local studs = RegionLogic.StandStuds
		local ix = math.floor(starter.x / studs)
		local iz = math.floor(starter.z / studs)
		local cx = (ix + 0.5) * studs
		local cz = (iz + 0.5) * studs
		local kind = RegionLogic.StandKind(cx, cz)
		t.ok(kind == "broad" or kind == "birch", "starter stand is " .. tostring(kind))
		local same = true
		for dx = -24, 24, 8 do
			for dz = -24, 24, 8 do
				if RegionLogic.StandKind(cx + dx, cz + dz) ~= kind then
					same = false
				end
			end
		end
		t.ok(same, "one cell, one species")
		-- The whole interior, away from the edge: only oak and birch kinds.
		local foreign = 0
		local n = 0
		for dx = -40, 40, 8 do
			for dz = -40, 40, 8 do
				n += 1
				local k = RegionLogic.StandKind(starter.x + dx, starter.z + dz)
				if not RegionLogic.Allows("starter", k) then
					foreign += 1
				end
				t.ok(k ~= "snowpine" and k ~= "dead", "no snow or dead wood in the plains")
			end
		end
		t.eq(foreign, 0, "no foreign species deep in the Starter Forest")
		-- The border band, on the west side toward the Hills: some pine is
		-- allowed, and it stays a minority.
		local bleed, samples = 0, 0
		local west = starter.x - starter.radius + 20
		for dz = -30, 30, 6 do
			for dx = -10, 10, 5 do
				samples += 1
				local k = RegionLogic.StandKind(west + dx, starter.z + dz)
				if k == "conifer" or k == "maple" then
					bleed += 1
				end
			end
		end
		t.ok(bleed / samples < 0.45, string.format("bleed is %.0f%% of the border", bleed / samples * 100))
	end)

	t.test("the Hills' interior is pine and maple, not the starter's oak", function()
		local hills = BiomeData.Get("hills").area
		local oak = 0
		local n = 0
		for dx = -50, 50, 10 do
			for dz = -50, 50, 10 do
				n += 1
				local k = RegionLogic.StandKind(hills.x + dx, hills.z + dz)
				if k == "broad" then
					oak += 1
				end
				t.ok(RegionLogic.Allows("hills", k) or k == "broad" or k == "birch", tostring(k))
			end
		end
		t.ok(oak / n < 0.2, string.format("oak is %.0f%% of the Hills' interior", oak / n * 100))
	end)

	t.test("frostwood, emberwood, gloamwood and lumenwood stay exclusive", function()
		local home = { frostwood = "snow", emberwood = "volcano", phantomwood = "grove", lumenwood = "sky" }
		for _, wood in ipairs(WoodData.All()) do
			local only = home[wood.id]
			if only then
				local region = RegionLogic.Get(only)
				t.eq(region.exclusive, wood.id)
				-- The price is the one the economy was tuned on.
				t.ok(wood.pricePerLog > 0, wood.id)
			end
		end
		-- Palm stays an island wood: the beach doesn't grow it yet.
		t.eq(WoodData.Get("palmwood").biome, "island")
		t.eq(RegionLogic.Get("strand").exclusive, nil)
	end)

	t.test("the Petrified Reach sits past the hollow, and only it is named there", function()
		local x, z, r = RegionLogic.ReachCenter()
		local place = here(x, z, 0)
		t.eq(place.base, "reach")
		t.eq(place.hidden, true)
		t.eq(place.biomeId, "grove", "same night rules as the hollow")
		local grove = BiomeData.Get("grove").area
		local dx, dz = x - grove.x, z - grove.z
		t.ok(math.sqrt(dx * dx + dz * dz) > grove.radius + 40, "outside the hollow's disc")
		t.ok(r > 20 and r < 80, "a pocket, not a biome")
		-- Its stand is the dead look, almost alone.
		local dead = 0
		local n = 0
		for dx2 = -16, 16, 8 do
			for dz2 = -16, 16, 8 do
				n += 1
				if RegionLogic.StandKind(x + dx2, z + dz2) == "dead" then
					dead += 1
				end
			end
		end
		t.ok(dead / n > 0.7, string.format("dead wood is %.0f%% of the reach", dead / n * 100))
	end)

	t.test("the ground under the isles is not the sky", function()
		local sky = BiomeData.Get("sky").area
		t.eq(here(sky.x, sky.z, 0), nil)
		t.eq(here(sky.x, sky.z, sky.y).base, "sky")
	end)

	t.test("points of interest and trails have a home region", function()
		local anchors = RegionLogic.Anchors()
		t.ok(#anchors >= 5, #anchors .. " points")
		local seen = {}
		for _, anchor in ipairs(anchors) do
			t.ok(RegionLogic.Get(anchor.region), anchor.id .. " region")
			t.ok(#anchor.name > 0 and anchor.search > 0, anchor.id)
			seen[anchor.kind] = true
		end
		t.eq(seen.LookoutTower, true)
		t.eq(seen.RuinedCabin, true)
		t.eq(seen.Cave, true)
		t.eq(seen.Crystal, true)
		for _, trail in ipairs(RegionLogic.Trails()) do
			local dx, dz = trail.bx - trail.ax, trail.bz - trail.az
			t.ok(math.sqrt(dx * dx + dz * dz) > 20, trail.name .. " goes somewhere")
		end
	end)

	t.test("a player at the spawn does not keep the far regions awake", function()
		local spawn = { { x = 0, z = 40, y = 6 } }
		local starter = BiomeData.Get("starter").area
		t.eq(RegionLogic.KeepTree("starter", starter.x, starter.z, 4, spawn), true)
		local snow = BiomeData.Get("snow").area
		t.eq(RegionLogic.KeepTree("snow", snow.x, snow.z, 30, spawn), false)
		local volcano = BiomeData.Get("volcano").area
		t.eq(RegionLogic.KeepTree("volcano", volcano.x, volcano.z, 20, spawn), false)
		local sky = BiomeData.Get("sky").area
		t.eq(RegionLogic.KeepTree("sky", sky.x, sky.z, sky.y, spawn), false)
		t.eq(RegionLogic.KeepTree("sky", sky.x, sky.z, sky.y, { { x = sky.x, z = sky.z, y = sky.y } }), true)
		-- Close wild trees stay; a wild tree on the far coast does not.
		t.eq(RegionLogic.KeepTree("wild", 40, -80, 4, spawn), true)
		t.eq(RegionLogic.KeepTree("wild", 1100, -400, 4, spawn), false)
		-- Nobody on the server: keep the tree (tests, an empty place).
		t.eq(RegionLogic.KeepTree("snow", snow.x, snow.z, 30, {}), true)
	end)

	t.test("walking up to a region wakes it before you are inside", function()
		local snow = BiomeData.Get("snow").area
		-- 80 studs outside the disc, on the south road's line.
		local z = snow.z - snow.radius - 80
		local person = { { x = snow.x, z = z, y = 20 } }
		t.eq(RegionLogic.KeepTree("snow", snow.x, snow.z, 30, person), true, "the plateau is already there")
		-- Still far down the road: asleep.
		local far = { { x = snow.x, z = snow.z - snow.radius - 400, y = 8 } }
		t.eq(RegionLogic.KeepTree("snow", snow.x, snow.z, 30, far), false)
	end)

	t.test("the reach, the landmarks and the trails stand on open ground, and a phone at spawn keeps less", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local reach = WorldPlan.ReachTrees()
		t.ok(#reach >= 3 and #reach <= 4, #reach .. " gloamwood in the reach")
		for _, spot in ipairs(reach) do
			local p = spot.position
			t.eq(spot.woodId, "phantomwood")
			t.eq(spot.biome, "reach")
			t.eq(TerrainGen.WaterLevelAt(p.X, p.Z), nil, "reach tree in the water")
			t.ok(WorldLayout.FlatWeight(p.X, p.Z) < 0.5, "reach tree in town or on a plot")
			t.ok(TerrainGen.RoadClearance(p.X, p.Z) >= 8, "reach tree on a road")
		end
		local pois = WorldPlan.PointsOfInterest()
		t.ok(#pois >= 4, #pois .. " points of interest")
		local kinds = {}
		for _, poi in ipairs(pois) do
			kinds[poi.kind] = true
			local p = poi.cframe.Position
			t.eq(TerrainGen.WaterLevelAt(p.X, p.Z), nil, poi.id .. " is in the water")
			t.ok(TerrainGen.RoadClearance(p.X, p.Z) >= 8, poi.id .. " is on a road")
			t.ok(WorldLayout.FlatWeight(p.X, p.Z) < 0.5, poi.id .. " is in town or on a plot")
		end
		t.eq(kinds.LookoutTower, true)
		t.eq(kinds.RuinedCabin, true)
		local slabs = WorldPlan.TrailSlabs()
		t.ok(#slabs >= 6, #slabs .. " trail slabs")
		for _, slab in ipairs(slabs) do
			local p = slab.cframe.Position
			t.eq(TerrainGen.WaterLevelAt(p.X, p.Z), nil)
			t.ok(TerrainGen.RoadClearance(p.X, p.Z) > 7, slab.name)
		end
		-- What a phone at the spawn used to replicate (everything inside the
		-- 640-stud stream) against what RegionWake now leaves in the world.
		local player = { { x = 0, z = 40, y = 6 } }
		local streamed, awake = 0, 0
		local function consider(spot, region)
			local dx, dz = spot.position.X, spot.position.Z - 40
			if dx * dx + dz * dz <= 640 * 640 then
				streamed += 1
			end
			if RegionLogic.KeepTree(region, spot.position.X, spot.position.Z, spot.position.Y, player) then
				awake += 1
			end
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			consider(spot, spot.biome)
		end
		for _, spot in ipairs(reach) do
			consider(spot, "reach")
		end
		t.ok(awake < streamed, string.format("awake %d, stream radius would send %d", awake, streamed))
		print(
			string.format(
				"[regions] spawn: %d trees awake, %d inside 640 studs, %d on the ground",
				awake,
				streamed,
				#WorldPlan.Trees() + #reach
			)
		)
	end)
end
