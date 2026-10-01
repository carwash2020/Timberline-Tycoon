--!nocheck
-- TerrainGen (the world's shape) and TerrainBuilder (writing it as voxels).

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local BiomeData = t.shared("BiomeData")
	local Vector3 = t.roblox.Vector3

	t.test("town and plot district are perfectly flat at y = 0", function()
		for _, p in ipairs({ { 0, 40 }, { 0, 110 }, { -80, 100 }, { 60, 25 }, { 250, -60 }, { 910, -500 } }) do
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
		t.ok(TerrainGen.WaterLevelAt(1400, -300) ~= nil, "ocean")
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
		for _, origin in ipairs({ { -128, -16 }, { -900, -260 } }) do
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
