--!strict
-- TerrainBuilder: writes the world (Shared/World/TerrainGen) into
-- workspace.Terrain when the server starts.
--   * 256 x 256-stud chunks (64 x 64 voxel columns), nearest the town
--     first, so the spawn is solid within the first second or two.
--   * Only a crust: each chunk is filled from a few voxels under its lowest
--     ground up to its highest ground or water. Below that nobody looks.
--   * Fractional occupancy on the surface voxel (TerrainGen.Voxel) gives
--     smooth hills (under water the bed rounds to whole voxels, so water
--     always meets it); the top two voxels take the surface material,
--     deeper ones what lies beneath (TerrainGen.SubMaterial).
--   * Yields between chunks, so the server keeps ticking.
-- A place that already has the terrain saved can skip all this: set the
-- attribute Prebuilt = true on Workspace.Terrain in Studio.

local WorldLayout = require(game:GetService("ReplicatedStorage").Shared.World.WorldLayout)
local TerrainGen = require(game:GetService("ReplicatedStorage").Shared.World.TerrainGen)

local TerrainBuilder = {}

local VOXEL = 4
local CHUNK = 64 -- voxel columns per chunk side
local CRUST = 3 -- solid voxels under a chunk's lowest ground
local NO_WATER = -1e9

local materialCache: { [string]: Enum.Material } = {}
local function material(name: string): Enum.Material
	local cached = materialCache[name]
	if cached then
		return cached
	end
	local ok, found = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	local mat: Enum.Material = if ok and found then found else Enum.Material.Grass
	materialCache[name] = mat
	return mat
end

local function setLook(terrain: Terrain)
	for name, color in pairs(TerrainGen.MaterialColors) do
		terrain:SetMaterialColor(material(name), color)
	end
	terrain.WaterColor = Color3.fromRGB(62, 140, 150)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 7
end

-- Writes one chunk of nx by nz voxel columns starting at world (x0, z0).
local function writeChunk(terrain: Terrain, x0: number, z0: number, nx: number, nz: number)
	-- Heights with a one-column border, for slopes.
	local heights: { { number } } = table.create(nx + 2)
	for i = 1, nx + 2 do
		local row = table.create(nz + 2)
		local x = x0 + (i - 1.5) * VOXEL
		for k = 1, nz + 2 do
			row[k] = TerrainGen.HeightAt(x, z0 + (k - 1.5) * VOXEL)
		end
		heights[i] = row
	end
	-- Surface material and water per column, and the chunk's height range.
	local surfaces: { { string } } = table.create(nx)
	local waters: { { number } } = table.create(nx) -- NO_WATER where dry
	local lo, hi = math.huge, -math.huge
	for i = 1, nx do
		local srow, wrow = table.create(nz), table.create(nz)
		local x = x0 + (i - 0.5) * VOXEL
		for k = 1, nz do
			local z = z0 + (k - 0.5) * VOXEL
			local h = heights[i + 1][k + 1]
			local slope = math.max(
				math.abs(heights[i + 2][k + 1] - heights[i][k + 1]),
				math.abs(heights[i + 1][k + 2] - heights[i + 1][k])
			) / (2 * VOXEL)
			srow[k] = TerrainGen.SurfaceMaterial(x, z, h, slope)
			local w = TerrainGen.WaterLevelAt(x, z)
			wrow[k] = w or NO_WATER
			lo = math.min(lo, h)
			hi = math.max(hi, h, w or -math.huge)
		end
		surfaces[i], waters[i] = srow, wrow
	end
	local yMin = math.floor(lo / VOXEL) - CRUST
	local yMax = math.ceil(hi / VOXEL) + 1
	local ny = yMax - yMin

	local water = Enum.Material.Water
	local air = Enum.Material.Air
	local mats: { { { Enum.Material } } } = table.create(nx)
	local occs: { { { number } } } = table.create(nx)
	for i = 1, nx do
		local mx, ox = table.create(ny), table.create(ny)
		for j = 1, ny do
			mx[j] = table.create(nz)
			ox[j] = table.create(nz)
		end
		for k = 1, nz do
			local h = heights[i + 1][k + 1]
			local w = waters[i][k]
			local surfaceName = surfaces[i][k]
			local top = material(surfaceName)
			local under = material(TerrainGen.SubMaterial(surfaceName))
			local surfaceVoxel = math.floor(h / VOXEL) - yMin + 1 -- index of the voxel holding the ground's surface
			for j = 1, ny do
				local bottom = (yMin + j - 1) * VOXEL
				local kind, occ = TerrainGen.Voxel(h, if w > NO_WATER then w else nil, bottom)
				if kind == "solid" then
					mx[j][k] = if j >= surfaceVoxel - 1 then top else under
					ox[j][k] = occ
				elseif kind == "water" then
					mx[j][k] = water
					ox[j][k] = occ
				else
					mx[j][k] = air
					ox[j][k] = 0
				end
			end
		end
		mats[i], occs[i] = mx, ox
	end
	local region =
		Region3.new(Vector3.new(x0, yMin * VOXEL, z0), Vector3.new(x0 + nx * VOXEL, yMax * VOXEL, z0 + nz * VOXEL))
	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

TerrainBuilder._writeChunk = writeChunk -- for tests

-- Builds the whole world's terrain. `onProgress(done, total)` is called
-- after each chunk. Returns how many seconds it took.
function TerrainBuilder.Build(onProgress: ((number, number) -> ())?): number
	local started = os.clock()
	local terrain = workspace.Terrain
	setLook(terrain)
	if terrain:GetAttribute("Prebuilt") == true then
		return 0
	end
	terrain:Clear()
	local half = WorldLayout.WorldHalf
	local totalColumns = math.floor(2 * half / VOXEL)
	local chunksPerSide = math.ceil(totalColumns / CHUNK)
	type Job = { x0: number, z0: number, nx: number, nz: number, dist: number }
	local jobs: { Job } = {}
	local hub = WorldLayout.Sawmill
	for cx = 0, chunksPerSide - 1 do
		for cz = 0, chunksPerSide - 1 do
			local x0 = -half + cx * CHUNK * VOXEL
			local z0 = -half + cz * CHUNK * VOXEL
			local mid = Vector3.new(x0 + CHUNK * VOXEL / 2, 0, z0 + CHUNK * VOXEL / 2)
			table.insert(jobs, {
				x0 = x0,
				z0 = z0,
				nx = math.min(CHUNK, totalColumns - cx * CHUNK),
				nz = math.min(CHUNK, totalColumns - cz * CHUNK),
				dist = (mid - hub).Magnitude,
			})
		end
	end
	table.sort(jobs, function(a, b)
		return a.dist < b.dist
	end)
	for index, job in ipairs(jobs) do
		local ok, err = pcall(function(): any
			writeChunk(terrain, job.x0, job.z0, job.nx, job.nz)
			return nil
		end)
		if not ok then
			warn(string.format("[TerrainBuilder] chunk at (%d, %d) failed: %s", job.x0, job.z0, tostring(err)))
		end
		if onProgress then
			onProgress(index, #jobs)
		end
		task.wait()
	end
	return os.clock() - started
end

return TerrainBuilder
