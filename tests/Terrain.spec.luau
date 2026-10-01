--!nocheck
-- TerrainGen (the world's shape) and TerrainBuilder (writing it as voxels).

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local BiomeData = t.shared("BiomeData")

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

	t.test("a voxel is solid, water or air", function()
		t.eq({ TerrainGen.Voxel(10, nil, 0) }, { "solid", 1 })
		t.eq({ TerrainGen.Voxel(2, nil, 0) }, { "solid", 0.5 })
		t.eq({ TerrainGen.Voxel(-6, -2, -4) }, { "water", 0.5 })
		t.eq({ TerrainGen.Voxel(-6, -2, 0) }, { "air", 0 })
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
end
