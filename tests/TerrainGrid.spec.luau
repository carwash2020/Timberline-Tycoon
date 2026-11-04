--!nocheck
-- T417: the terrain stays on the voxel grid. #270 (T409) made WorldHalf 1350, so the
-- generated half (1550) was not a multiple of the 4-stud voxel, every block started 2
-- studs off the grid and Terrain:WriteVoxels refused all of them in Studio (no ground).
-- The fakes now enforce the engine's two rules (tests/support/StrictTerrain).

return function(t)
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Strict = t.support("StrictTerrain")
	local VOXEL = 4

	local function strictTerrain(log)
		return {
			GetAttribute = function()
				return nil
			end,
			Clear = function() end,
			SetMaterialColor = function() end,
			FillBlock = function() end,
			WriteVoxels = function(_, region, res, mats, occs)
				Strict.check(region, res, mats, occs)
				table.insert(log, region)
			end,
		}
	end

	local function builderWith(terrain)
		local loader = t.loader({ globals = { workspace = { Terrain = terrain }, task = { wait = function() end } } })
		return loader:server("TerrainBuilder")
	end

	t.test("the strict fake itself refuses an unaligned region and wrong array sizes", function()
		local R3, V3 = t.roblox.Region3, t.roblox.Vector3
		local function arr(nx, ny, nz, v)
			local a = {}
			for i = 1, nx do
				a[i] = {}
				for j = 1, ny do
					a[i][j] = table.create(nz, v)
				end
			end
			return a
		end
		local ok = R3.new(V3.new(-8, 0, 4), V3.new(0, 8, 12))
		Strict.check(ok, 4, arr(2, 2, 2, 1), arr(2, 2, 2, 1))
		t.ok(
			not pcall(Strict.check, R3.new(V3.new(-6, 0, 4), V3.new(2, 8, 12)), 4, arr(2, 2, 2, 1), arr(2, 2, 2, 1)),
			"unaligned"
		)
		t.ok(not pcall(Strict.check, ok, 4, arr(3, 2, 2, 1), arr(2, 2, 2, 1)), "materials 3x2x2")
		t.ok(not pcall(Strict.check, ok, 4, arr(2, 2, 2, 1), arr(2, 2, 3, 1)), "occupancy 2x2x3")
	end)

	t.test("every block of Jobs, Split and Order for the real world starts on the voxel grid", function()
		local TerrainBuilder = builderWith(strictTerrain({}))
		local R3, V3 = t.roblox.Region3, t.roblox.Vector3
		local jobs = TerrainBuilder.Jobs()
		t.ok(#jobs > 0)
		local blocks = TerrainBuilder.Order(TerrainBuilder.Split(jobs, TerrainBuilder.SubColumns))
		local minX, maxX = math.huge, -math.huge
		for _, list in ipairs({ jobs, blocks }) do
			for _, b in ipairs(list) do
				t.eq(b.x0 % VOXEL, 0, "x0 " .. b.x0)
				t.eq(b.z0 % VOXEL, 0, "z0 " .. b.z0)
				local region = R3.new(V3.new(b.x0, 0, b.z0), V3.new(b.x0 + b.nx * VOXEL, 8, b.z0 + b.nz * VOXEL))
				t.ok(Strict.aligned(region, VOXEL), "ExpandToGrid is not the identity at " .. b.x0 .. "," .. b.z0)
				minX = math.min(minX, b.x0)
				maxX = math.max(maxX, b.x0 + b.nx * VOXEL)
			end
		end
		-- The generated square still covers the whole playable square plus the skirt.
		t.ok(minX <= -(WorldLayout.WorldHalf + WorldLayout.TerrainSkirt), "covers the west edge: " .. minX)
		t.ok(maxX >= WorldLayout.WorldHalf + WorldLayout.TerrainSkirt, "covers the east edge: " .. maxX)
		t.eq(WorldLayout.WorldHalf, 1350, "the playable square is untouched")
	end)

	t.test("writeChunk expands an unaligned origin to the grid and sizes the arrays to it", function()
		local log = {}
		local terrain = strictTerrain(log)
		local TerrainBuilder = builderWith(terrain)
		-- 2 studs off the grid on both axes, like the T409 origin (-1550).
		TerrainBuilder._writeChunk(terrain, -1550, -1550, 16, 16)
		TerrainBuilder._writeChunk(terrain, -14, 50, 16, 16)
		TerrainBuilder._writeChunk(terrain, 1.3, -2.9, 5, 7)
		t.eq(#log, 3)
		for _, region in ipairs(log) do
			t.ok(Strict.aligned(region, VOXEL))
		end
		-- It covers every stud the caller asked for.
		local b = Strict.bounds(log[2])
		t.ok(b[1] <= -14 and b[4] >= -14 + 64 and b[3] <= 50 and b[6] >= 50 + 64)
	end)

	-- The town's ground, read back from what the strict fake accepted: y = 0 at the probes
	-- (the Studio log said 2.00 only because nothing had been written at all).
	t.test("with the strict fake the written town ground tops out at y = 0 (SettleTown, no shift)", function()
		local live = {}
		local terrain = strictTerrain({})
		local inner = terrain.WriteVoxels
		terrain.WriteVoxels = function(self, region, res, mats, occs)
			inner(self, region, res, mats, occs)
			table.insert(live, { region = region, mats = mats, occs = occs })
		end
		local TerrainBuilder = builderWith(terrain)
		local function written(x, z)
			for i = #live, 1, -1 do
				local w = live[i]
				local b = Strict.bounds(w.region)
				if x >= b[1] and x < b[4] and z >= b[3] and z < b[6] then
					local ix, iz = math.floor((x - b[1]) / VOXEL) + 1, math.floor((z - b[3]) / VOXEL) + 1
					local top
					for j = 1, #w.mats[ix] do
						local m = w.mats[ix][j][iz].Name
						if m ~= "Air" and m ~= "Water" then
							top = b[2] + (j - 1) * VOXEL + VOXEL * w.occs[ix][j][iz]
						end
					end
					return top, w.mats[ix], ix, iz
				end
			end
			return nil
		end
		local shift, ground, tries = TerrainBuilder.SettleTown(terrain, TerrainBuilder.Jobs(), function(x, z)
			return (written(x, z))
		end, function() end)
		t.eq(shift, 0)
		t.ok(ground ~= nil and math.abs(ground) < 0.3, "town ground reads " .. tostring(ground))
		t.eq(#tries, 1)
		for _, p in ipairs(TerrainBuilder.TownProbes) do
			local top = written(p.X, p.Y)
			t.ok(top ~= nil and math.abs(top) < 0.3, string.format("probe (%d, %d) top %s", p.X, p.Y, tostring(top)))
		end
	end)
end
