--!nocheck
-- TerrainBuilder (T402): what it writes under the grass, how thick the top
-- layer is, and that the build gives the frame back every ~4 ms of work.

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Enum = t.roblox.Enum

	-- A terrain that keeps the voxels it was given, so a spec can read them.
	local function recordingTerrain(onWrite)
		local writes = {}
		local terrain = {
			GetAttribute = function()
				return nil
			end,
			Clear = function() end,
			SetMaterialColor = function() end,
			FillBlock = function() end,
			WriteVoxels = function(_, region, _, mats, occs)
				table.insert(writes, { mats = mats, occs = occs })
				if onWrite then
					onWrite()
				end
			end,
		}
		return terrain, writes
	end

	local function builder(globals)
		local loader = t.loader({ globals = globals or {} })
		return loader:server("TerrainBuilder")
	end

	-- The column (i, k) of a written block, top to bottom: { material name, occupancy }.
	local function column(write, i, k)
		local out = {}
		local mx, ox = write.mats[i], write.occs[i]
		for j = #mx, 1, -1 do
			table.insert(out, { name = mx[j][k].Name, occ = ox[j][k] })
		end
		return out
	end

	t.test("Grass and LeafyGrass never have Rock or Slate under them", function()
		local TerrainBuilder = builder()
		-- By rule, for every surface the sampler can answer with.
		for x = -1000, 1000, 40 do
			for z = -1000, 1000, 40 do
				local _, surface = TerrainGen.Sample(x, z)
				local under = TerrainBuilder.UnderMaterial(surface)
				if surface == "Grass" or surface == "LeafyGrass" then
					t.ok(under ~= "Rock" and under ~= "Slate", surface .. " has " .. under .. " under it")
					t.eq(under, "Ground")
				end
			end
		end
		-- And in the voxels: blocks of the town, a Hills slope and a mountain side.
		local spots = {
			{ -30, 40 }, -- the town
			{ 20, -10 }, -- the lot
			{ -520, 120 }, -- the Hills Road's bank
			{ 380, 380 }, -- country in the north-east
			{ -1000, 300 }, -- the mountains' foot
		}
		local checked = 0
		for _, spot in ipairs(spots) do
			local terrain, writes = recordingTerrain()
			TerrainBuilder._writeChunk(terrain, spot[1], spot[2], 16, 16)
			local w = writes[1]
			for i = 1, 16 do
				for k = 1, 16 do
					local col = column(w, i, k)
					local top
					for index, voxel in ipairs(col) do
						if voxel.occ > 0 and voxel.name ~= "Water" then
							top = index
							break
						end
					end
					if top and (col[top].name == "Grass" or col[top].name == "LeafyGrass") then
						checked += 1
						for index = top, #col do
							local name = col[index].name
							if name ~= "Water" and name ~= "Air" then
								t.ok(
									name ~= "Rock" and name ~= "Slate",
									"grass over " .. name .. " at " .. spot[1] .. "," .. spot[2]
								)
							end
						end
					end
				end
			end
		end
		t.ok(checked > 400, "grass columns were checked: " .. checked)
	end)

	t.test("the surface band is 3 voxels deep (was 2)", function()
		local TerrainBuilder = builder()
		t.eq(TerrainBuilder.SurfaceBand, 3)
		-- Flat grass in the town: the top three solid voxels are Grass, the ones under are Ground.
		local terrain, writes = recordingTerrain()
		TerrainBuilder._writeChunk(terrain, 40, 20, 4, 4)
		local col = column(writes[1], 2, 2)
		local solid = {}
		for _, voxel in ipairs(col) do
			if voxel.occ > 0 then
				table.insert(solid, voxel.name)
			end
		end
		t.eq(solid[1], "Grass")
		t.eq(solid[2], "Grass")
		t.eq(solid[3], "Grass")
		t.eq(solid[4], "Ground", "the 4th voxel down is the under-layer")
		t.eq(solid[5], "Ground")
	end)

	-- A flat world and a clock that only the writes advance (1 ms each): the
	-- specs read how long the build worked between two task.wait calls.
	local function runBuild(buildOptions)
		local now = 0
		local waits = {}
		local lastWait = 0
		local longest = 0
		local terrain = recordingTerrain(function()
			now += 0.001
		end)
		local flat = setmetatable({
			HeightAt = function()
				return 0
			end,
			SurfaceMaterial = function()
				return "Grass"
			end,
			WaterLevelFor = function()
				return nil
			end,
		}, { __index = TerrainGen })
		local ws = { Terrain = terrain }
		function ws.SetAttribute() end
		function ws.Raycast()
			return nil
		end
		local loader = t.loader({
			mocks = { TerrainGen = flat },
			globals = {
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				workspace = ws,
				os = setmetatable({
					clock = function()
						return now
					end,
				}, { __index = os }),
			},
		})
		local TerrainBuilder = loader:server("TerrainBuilder")
		buildOptions.clock = function()
			return now
		end
		buildOptions.wait = function()
			longest = math.max(longest, now - lastWait)
			table.insert(waits, now)
			lastWait = now
		end
		local _, finish = TerrainBuilder.Build(nil, buildOptions)
		if finish then
			buildOptions.wait() -- (MapBuilder runs the second stage on a later frame)
			finish()
		end
		longest = math.max(longest, now - lastWait)
		return {
			waits = waits,
			longest = longest,
			total = now,
			steps = TerrainBuilder.StepTimes,
			builder = TerrainBuilder,
		}
	end

	t.test("an injected clock yields at least once per 4 ms of work, in both stages", function()
		local r = runBuild({ nearRadius = 230 })
		t.ok(r.total > 1, "the build did work: " .. r.total .. " s")
		-- A write is 1 ms: no stretch between yields passes 4 ms plus the write that crossed it.
		t.ok(r.longest <= 0.005 + 1e-9, string.format("longest stretch %.1f ms", r.longest * 1000))
		t.ok(#r.waits >= math.floor(r.total / 0.005), "yields: " .. #r.waits .. " for " .. r.total .. " s of work")
		t.eq(r.builder.YieldSeconds, 0.004)
		-- One stage on its own (no radius: no background).
		local one = runBuild({})
		t.ok(one.longest <= 0.005 + 1e-9, string.format("single-stage longest stretch %.1f ms", one.longest * 1000))
	end)

	t.test("the build logs each step's time, and every step's longest stretch is under 50 ms", function()
		local r = runBuild({ nearRadius = 230 })
		local names = {}
		for _, step in ipairs(r.steps) do
			names[step.name] = true
			t.ok(step.seconds >= 0)
			t.ok(step.longest <= 0.05, step.name .. " longest stretch " .. step.longest)
		end
		t.ok(
			names["settle town"] and names["near ring"] and names["background blocks"] and names["caves"],
			"every step is logged"
		)
	end)

	t.test("the town zone's blocks are written first in the background, then the pads", function()
		local TerrainBuilder = builder()
		local blocks =
			TerrainBuilder.Order(TerrainBuilder.Split(TerrainBuilder.Jobs(), TerrainBuilder.SubColumns), nil, nil)
		local zone = WorldLayout.TownZone
		local townEnd = 0
		for i, b in ipairs(blocks) do
			if not TerrainBuilder.InTown(b) then
				townEnd = i - 1
				break
			end
		end
		t.ok(townEnd > 20, "town blocks lead: " .. townEnd)
		for i = 1, townEnd do
			local b = blocks[i]
			t.ok(b.x0 < zone.x1 and b.x0 + b.nx * 4 > zone.x0 and b.z0 < zone.z1 and b.z0 + b.nz * 4 > zone.z0)
		end
		t.ok(Enum ~= nil)
	end)
end
