--!nocheck
-- TerrainGen (the world's shape) and TerrainBuilder (writing it as voxels).

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local BiomeData = t.shared("BiomeData")
	local Vector3 = t.roblox.Vector3
	local Vector2 = t.roblox.Vector2

	-- The ground's shape is a contract: trees, props, roads, plots, the
	-- crater and these specs all place things with HeightAt. Restyling the
	-- surface (materials, colours) must never move it. The fingerprint is
	-- HeightAt over a jittered grid across the whole map, plus every road
	-- (centre, shoulders, verges) and the town and plot district. Re-sampled
	-- in phase 12 when the haul roads widened, the mill road and lot loop
	-- were added, and the cliff rings and hollow pools changed the shape.
	-- The volcano ring was then raised to 24 so its one gap stays one gap.
	-- Re-sampled again when the one plot lawn became 14 homestead shelves,
	-- and once more for the dealership display lot's flat patch (and again when the showroom hall grew: its patch is x 178 to 340, z 64 to 166, and The Climb
	-- moved 55 studs north, so its lane is a little shorter). The shelves
	-- are flat at their own height, and each lane is a sample.
	local HEIGHT_FINGERPRINT = {
		n = 7717,
		sum = 78802.208470475568902,
		wsum = 64.781511060652036,
		sq = 5271518.700170860625803,
		lo = -48.000000000000000,
		hi = 161.576039893993112,
	}
	-- Ring map (WorldHalf 1000): the grid is 64 x 64 over the 2000-stud square (it was
	-- over the old 3000), the coast sample stops at the wall, and the roads are the ring's.
	local function heightFingerprint()
		local n, sum, wsum, sq, lo, hi = 0, 0, 0, 0, math.huge, -math.huge
		local function add(x, z)
			local h = TerrainGen.HeightAt(x, z)
			n += 1
			sum += h
			wsum += h * math.sin(n * 0.731)
			sq += h * h
			lo = math.min(lo, h)
			hi = math.max(hi, h)
		end
		for i = 0, 63 do
			for k = 0, 63 do
				add(-990 + i * 31.5 + (k % 7) * 1.7, -990 + k * 31.5 + (i % 5) * 2.3)
			end
		end
		for _, road in ipairs(WorldLayout.Roads) do
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = (b - a).Magnitude
				local side = Vector2.new(a.Y - b.Y, b.X - a.X) / math.max(len, 1e-6)
				for s = 0, len, 19 do
					local p = a:Lerp(b, s / math.max(len, 1e-6))
					for _, off in ipairs({ 0, road.width * 0.4, -road.width * 0.4, road.width + 9, -(road.width + 21) }) do
						local q = p + side * off
						add(q.X, q.Y)
					end
				end
			end
		end
		for x = -150, 150, 13 do
			for z = -40, 260, 13 do
				add(x, z)
			end
		end
		for x = 600, 1000, 31 do
			for z = -800, -200, 31 do
				add(x, z)
			end
		end
		return { n = n, sum = sum, wsum = wsum, sq = sq, lo = lo, hi = hi }
	end

	t.test("the ground's heights are exactly as they were (materials only may change)", function()
		local got = heightFingerprint()
		local want = HEIGHT_FINGERPRINT
		t.eq(got.n, want.n)
		for _, key in ipairs({ "sum", "wsum", "sq", "lo", "hi" }) do
			t.ok(
				math.abs(got[key] - want[key]) < 1e-5 * math.max(1, math.abs(want[key]) * 1e-6),
				string.format("HeightAt fingerprint %s is %.9f, was %.9f", key, got[key], want[key])
			)
		end
	end)

	t.test("the town is perfectly flat at y = 0", function()
		for _, p in ipairs({ { 0, 40 }, { 0, 110 }, { -80, 100 }, { 60, 25 } }) do
			t.eq(TerrainGen.HeightAt(p[1], p[2]), 0)
		end
	end)

	t.test("roads stay drivable: grade under 20% along every road", function()
		for _, road in ipairs(WorldLayout.Roads) do
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local steps = math.max(2, math.floor((b - a).Magnitude / 8))
				local prev = TerrainGen.HeightAt(a.X, a.Y)
				for s = 1, steps do
					local p = a:Lerp(b, s / steps)
					local h = TerrainGen.HeightAt(p.X, p.Y)
					local run = (b - a).Magnitude / steps
					t.ok(
						math.abs(h - prev) / run < 0.2,
						string.format("%s too steep near (%d, %d)", road.name, p.X, p.Y)
					)
					prev = h
				end
			end
		end
	end)

	t.test("every biome centre is dry land (trees grow there)", function()
		for _, biome in ipairs(BiomeData.All()) do
			local a = biome.area
			if a and a.y == nil then
				t.eq(TerrainGen.WaterLevelAt(a.x, a.z), nil)
			end
		end
	end)

	t.test("the lake and river hold water; the ocean is east", function()
		local lake = WorldLayout.Lake
		t.ok(TerrainGen.WaterLevelAt(lake.x, lake.z) ~= nil, "lake")
		local r = WorldLayout.River.points[3]
		t.ok(TerrainGen.WaterLevelAt(r.X, r.Y) ~= nil, "river")
		-- Ring map (Oct 10): the square is 2000 across, so the sea is at x 900 (it was 1400).
		t.ok(TerrainGen.WaterLevelAt(900, -300) ~= nil, "ocean")
	end)

	t.test("the volcano's crater is lava, its slopes rock, never snow", function()
		local cone = WorldLayout.VolcanoCone
		local h = TerrainGen.HeightAt(cone.x, cone.z)
		t.eq(TerrainGen.SurfaceMaterial(cone.x, cone.z, h, 0), "CrackedLava")
		local hs = TerrainGen.HeightAt(cone.x + cone.radius * 0.5, cone.z)
		local m = TerrainGen.SurfaceMaterial(cone.x + cone.radius * 0.5, cone.z, hs, 0.3)
		t.ok(m == "Basalt" or m == "Slate", m)
	end)

	t.test("the volcano's crater holds a level lava pool, its walls climbing to the rim", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local cone = WorldLayout.VolcanoCone
		local pool, radius = WorldPlan.Crater()
		t.eq(radius, cone.pool)
		local floor = TerrainGen.HeightAt(cone.x, cone.z)
		t.ok((pool - Vector3.new(cone.x, floor, cone.z)).Magnitude < 1e-3, "the pool is the crater's middle")
		for k = 0, 23 do
			local a = k / 24 * math.pi * 2
			local cx, sz = math.cos(a), math.sin(a)
			-- Level all the way to the pool's edge (MapBuilder's CraterLava
			-- disc, 2 x radius across, lies on it).
			for _, d in ipairs({ radius * 0.5, radius - 0.05 }) do
				local h = TerrainGen.HeightAt(cone.x + cx * d, cone.z + sz * d)
				t.ok(math.abs(h - floor) < 1e-6, string.format("the pool is level (%.2f off at %d)", h - floor, d))
			end
			-- Then the wall only climbs, from the pool to the rim, and meets
			-- the cone outside it.
			local prev = floor
			for d = radius, cone.crater - 0.05, 0.5 do
				local h = TerrainGen.HeightAt(cone.x + cx * d, cone.z + sz * d)
				t.ok(h >= prev - 1e-6, string.format("the crater wall dips at %.1f studs out", d))
				prev = h
			end
			local inside = TerrainGen.HeightAt(cone.x + cx * (cone.crater - 0.05), cone.z + sz * (cone.crater - 0.05))
			local outside = TerrainGen.HeightAt(cone.x + cx * (cone.crater + 0.05), cone.z + sz * (cone.crater + 0.05))
			t.ok(math.abs(inside - outside) < 6, "no cliff at the rim")
			t.ok(inside > floor + 20, "the crater is deep")
		end
	end)

	-- What a column's surface is, with the slope TerrainBuilder would see.
	local function materialAt(x, z)
		local _, m = TerrainGen.Sample(x, z)
		return m
	end

	t.test("open country is a mixed meadow: Grass and LeafyGrass swaths, a few worn patches", function()
		local counts, n = {}, 0
		-- Ring map (Oct 10): the old sample rectangles lay outside the 2000
		-- stud square, so this samples all the open country in it (where the
		-- forest's canopy leaves it open; FOR-04: under the canopy the floor
		-- is LeafyGrass, its own test below).
		for x = -1000, 1000, 12 do
			for z = -1000, 1000, 12 do
				if WorldLayout.ForestCover(x, z) <= 0.3 then
					local m = materialAt(x, z)
					counts[m] = (counts[m] or 0) + 1
					n += 1
				end
			end
		end
		t.ok(n > 1500, n .. " open samples")
		local grass, leafy, ground = counts.Grass or 0, counts.LeafyGrass or 0, counts.Ground or 0
		-- Ring map (Oct 10): LeafyGrass is 9.5% of the whole square's open ground
		-- (it was 12 to 50% of the old south and west rectangles), so the floor
		-- is 8 to 50%.
		t.ok(leafy / n > 0.08 and leafy / n < 0.5, string.format("LeafyGrass is %.0f%% of the meadow", leafy / n * 100))
		t.ok(grass / n > 0.4, string.format("Grass is %.0f%% of the meadow", grass / n * 100))
		t.ok(ground / n > 0.003 and ground / n < 0.08, string.format("worn Ground is %.1f%%", ground / n * 100))
	end)

	t.test("biome edges fray over a band: pure deep inside, mixed across the edge, gone outside", function()
		-- Rays south from the Snowfields and south-west from the Volcano
		-- (ring map, Oct 10: the Volcano Road now comes off the ring at 215 to 235 degrees, so the rays miss it)
		-- (away from the mountains' own snow and rock).
		for _, spec in ipairs({
			{ id = "snow", extra = 150, mat = "Snow", angles = { 200, 230, 260, 290, 320 } },
			{ id = "volcano", extra = 40, mat = "Basalt", angles = { 190, 240, 265, 270 } },
		}) do
			local a = BiomeData.Get(spec.id).area
			local r = a.radius + spec.extra
			local deep, mixedIn, mixedOut, outside, switches = 0, 0, 0, 0, 0
			for _, deg in ipairs(spec.angles) do
				local cx, sz = math.cos(math.rad(deg)), math.sin(math.rad(deg))
				local was = nil
				for d = r - 160, r + 160, 2 do
					local x, z = a.x + cx * d, a.z + sz * d
					local m = materialAt(x, z)
					local isBiome = m == spec.mat or m == "Glacier" or m == "Slate" or m == "CrackedLava"
					if was ~= nil and was ~= isBiome then
						switches += 1
					end
					was = isBiome
					if d < r - 110 then
						deep += if isBiome then 0 else 1
					elseif d > r + 110 then
						outside += if isBiome then 1 else 0
					elseif isBiome then
						mixedIn += 1
					else
						mixedOut += 1
					end
				end
			end
			t.eq(deep, 0)
			t.eq(outside, 0)
			t.ok(mixedIn > 20 and mixedOut > 20, string.format("%s edge: %d in, %d out", spec.id, mixedIn, mixedOut))
			-- A dithered edge flips back and forth; a hard disc crosses once.
			t.ok(switches >= 3 * #spec.angles, string.format("%s edge flips only %d times", spec.id, switches))
		end
	end)

	t.test("each homestead shelf is plain Grass (the platform stands on it); the town plaza keeps its paint", function()
		for _, zone in ipairs(WorldLayout.FlatZones) do
			if zone.name == "Plot" then
				for x = zone.x0 + 16, zone.x1 - 16, 20 do
					for z = zone.z0 + 16, zone.z1 - 16, 20 do
						local m = materialAt(x, z)
						t.eq(m, "Grass", string.format("plot (%d, %d) is %s", x, z, m))
					end
				end
			end
		end
		-- Paint overlaps, and the first patch listed wins.
		for _, paint in ipairs(WorldLayout.TownPaint) do
			local x, z = (paint.x0 + paint.x1) / 2, (paint.z0 + paint.z1) / 2
			local want
			for _, p in ipairs(WorldLayout.TownPaint) do
				if want == nil and x > p.x0 and x < p.x1 and z > p.z0 and z < p.z1 then
					want = p.material
				end
			end
			t.eq(materialAt(x, z), want)
		end
	end)

	t.test("a voxel is solid, water or air", function()
		-- Dry ground fills a voxel as far as the ground reaches (smooth hills).
		t.eq({ TerrainGen.Voxel(10, nil, 0) }, { "solid", 1 })
		t.eq({ TerrainGen.Voxel(2, nil, 0) }, { "solid", 0.5 })
		t.eq({ TerrainGen.Voxel(0.05, nil, 0) }, { "air", 0 })
		-- Under water: water up to the surface, air above it.
		t.eq({ TerrainGen.Voxel(-6, -2, -4) }, { "water", 0.5 })
		t.eq({ TerrainGen.Voxel(-6, -2, 0) }, { "air", 0 })
		-- The bed's voxel rounds: mostly ground is ground, mostly not is water.
		t.eq({ TerrainGen.Voxel(-5, -2, -8) }, { "solid", 1 })
		t.eq({ TerrainGen.Voxel(-7, -2, -8) }, { "water", 1 })
		-- A shallow margin (the bed within a voxel of the surface) holds water.
		t.eq({ TerrainGen.Voxel(-3, -2, -4) }, { "water", 0.5 })
		t.eq({ TerrainGen.Voxel(-3.5, -3, -4) }, { "water", 0.25 })
	end)

	t.test("under water, a column is ground, then water up to the surface, never air", function()
		for _, surface in ipairs({ WorldLayout.LakeLevel, WorldLayout.SeaLevel }) do
			for h = -16, surface - 0.05, 0.05 do
				local kinds, top = {}, -math.huge
				for bottom = -24, 8, 4 do
					local kind, occ = TerrainGen.Voxel(h, surface, bottom)
					table.insert(kinds, string.sub(kind, 1, 1))
					if kind == "water" then
						top = bottom + occ * 4
					end
				end
				local column = table.concat(kinds)
				t.ok(string.match(column, "^s+w+a+$") ~= nil, string.format("bed %.2f: %s", h, column))
				t.ok(math.abs(top - surface) < 1e-6, string.format("bed %.2f: water reaches %.2f", h, top))
			end
		end
	end)

	t.test("a written chunk's arrays match its region exactly", function()
		local written = {}
		local terrain = {
			WriteVoxels = function(_, region, res, mats, occs)
				table.insert(written, { region = region, res = res, mats = mats, occs = occs })
			end,
		}
		local loader = t.loader({ globals = { workspace = { Terrain = terrain }, task = { wait = function() end } } })
		local TerrainBuilder = loader:server("TerrainBuilder")
		-- The town (flat) and the lake (water) chunks.
		for _, origin in ipairs({ { -128, -16 }, { WorldLayout.Lake.x - 64, WorldLayout.Lake.z - 12 } }) do
			table.clear(written)
			TerrainBuilder._writeChunk(terrain, origin[1], origin[2], 32, 24)
			local w = written[1]
			t.eq(w.res, 4)
			local size = w.region.Size
			t.eq(#w.mats, size.X / 4)
			t.eq(#w.mats[1], size.Y / 4)
			t.eq(#w.mats[1][1], size.Z / 4)
			t.eq(#w.occs[1][1], size.Z / 4)
			t.eq(w.region.CFrame.Position.Y % 2, 0) -- grid-aligned
		end
		-- The lake chunk has water in it.
		local hasWater = false
		for _, plane in ipairs(written[1].mats) do
			for _, row in ipairs(plane) do
				for _, m in ipairs(row) do
					if m.Name == "Water" then
						hasWater = true
					end
				end
			end
		end
		t.ok(hasWater, "lake chunk wrote water")
	end)

	t.test("written water reaches the bed in every wet column (the pond, the lake)", function()
		local written = {}
		local terrain = {
			WriteVoxels = function(_, region, _, mats)
				table.insert(written, { region = region, mats = mats })
			end,
		}
		local loader = t.loader({ globals = { workspace = { Terrain = terrain }, task = { wait = function() end } } })
		local TerrainBuilder = loader:server("TerrainBuilder")
		local pond, lake = WorldLayout.Pond, WorldLayout.Lake
		-- The whole pond (half its bed lies within a voxel of the surface),
		-- and the lake's south-east shore.
		for _, chunk in ipairs({ { pond.x - 24, pond.z - 24, 12, 12 }, { lake.x, lake.z - 160, 40, 40 } }) do
			table.clear(written)
			local x0, z0, nx, nz = chunk[1], chunk[2], chunk[3], chunk[4]
			TerrainBuilder._writeChunk(terrain, x0, z0, nx, nz)
			local mats = written[1].mats
			local wet = 0
			for i = 1, nx do
				for k = 1, nz do
					local x, z = x0 + (i - 0.5) * 4, z0 + (k - 0.5) * 4
					local kinds = {}
					for j = 1, #mats[i] do
						local m = mats[i][j][k].Name
						table.insert(kinds, if m == "Water" then "w" elseif m == "Air" then "a" else "s")
					end
					local column = table.concat(kinds)
					if TerrainGen.WaterLevelAt(x, z) then
						wet += 1
						t.ok(string.match(column, "^s+w+a+$") ~= nil, string.format("(%d, %d): %s", x, z, column))
					else
						t.ok(string.match(column, "^s+a+$") ~= nil, string.format("dry (%d, %d): %s", x, z, column))
					end
				end
			end
			t.ok(wet > 40, string.format("only %d wet columns at (%d, %d)", wet, x0, z0))
		end
	end)
end
