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
--   * First it measures where the engine draws what we write (TER-01,
--     Shared/World/TerrainFit): flat test pads far below the map, a ray
--     onto each, and every height after that is written so the ground is
--     drawn where TerrainGen says. The live game drew the town 2-3 studs
--     high before this. Then it checks the town's ground with rays and
--     reports it (workspace attributes TerrainOffset and TownGroundY).
-- A place that already has the terrain saved can skip all this: set the
-- attribute Prebuilt = true on Workspace.Terrain in Studio.

local WorldLayout = require(game:GetService("ReplicatedStorage").Shared.World.WorldLayout)
local TerrainGen = require(game:GetService("ReplicatedStorage").Shared.World.TerrainGen)
local TerrainFit = require(game:GetService("ReplicatedStorage").Shared.World.TerrainFit)

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

-- Writes one chunk of nx by nz voxel columns starting at world (x0, z0),
-- each height passed through `fit` (TerrainFit; identity if nil) so it is
-- drawn where TerrainGen says. Materials follow the true heights.
local function writeChunk(terrain: Terrain, x0: number, z0: number, nx: number, nz: number, fit: TerrainFit.Fit?)
	local f = fit or TerrainFit.Identity
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
	local waters: { { number } } = table.create(nx) -- NO_WATER where dry (written)
	local written: { { number } } = table.create(nx) -- the heights to write
	local lo, hi = math.huge, -math.huge
	for i = 1, nx do
		local srow, wrow, hrow = table.create(nz), table.create(nz), table.create(nz)
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
			local hw = TerrainFit.Written(f, h)
			local ww = if w then TerrainFit.Written(f, w) else nil
			wrow[k] = ww or NO_WATER
			hrow[k] = hw
			lo = math.min(lo, hw)
			hi = math.max(hi, hw, ww or -math.huge)
		end
		surfaces[i], waters[i], written[i] = srow, wrow, hrow
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
			local h = written[i][k]
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

---------------------------------------------------------------------------
-- Measuring the engine (TER-01)
---------------------------------------------------------------------------

-- `cast(x, z, fromY, toY)`: the Y where a ray straight down hits the
-- terrain, or nil.
export type Cast = (x: number, z: number, fromY: number, toY: number) -> number?

local terrainOnly: RaycastParams? = nil
local function castTerrain(x: number, z: number, fromY: number, toY: number): number?
	local params: RaycastParams
	if terrainOnly then
		params = terrainOnly
	else
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		params.IgnoreWater = true
		terrainOnly = params
	end
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, toY - fromY, 0), params)
	return if hit then hit.Position.Y else nil
end

-- The test pads: 8 x 8 columns each, side by side along X, their surfaces
-- written PAD_BASE + residue high, well under the deepest ground (the
-- world's crust stops a few voxels under its lowest valley).
local PAD_BASE = -400
local PAD_COLUMNS = 8
local PAD_STEP = 40 -- studs between pads' corners (8 clear between)
local PAD_X0 = -160
local PAD_Z0 = -16
local PAD_Y0 = PAD_BASE - 12 -- three voxels of rock under each pad
local PAD_VOXELS = 5

local function writePad(terrain: Terrain, x0: number, surface: number?)
	local mats: { { { Enum.Material } } } = table.create(PAD_COLUMNS)
	local occs: { { { number } } } = table.create(PAD_COLUMNS)
	for i = 1, PAD_COLUMNS do
		local mx, ox = table.create(PAD_VOXELS), table.create(PAD_VOXELS)
		for j = 1, PAD_VOXELS do
			local kind, occ = "air", 0
			if surface then
				kind, occ = TerrainGen.Voxel(surface, nil, PAD_Y0 + (j - 1) * VOXEL)
			end
			local m = if kind == "solid" then Enum.Material.Rock else Enum.Material.Air
			mx[j] = table.create(PAD_COLUMNS, m)
			ox[j] = table.create(PAD_COLUMNS, if kind == "solid" then occ else 0)
		end
		mats[i], occs[i] = mx, ox
	end
	local region = Region3.new(
		Vector3.new(x0, PAD_Y0, PAD_Z0),
		Vector3.new(x0 + PAD_COLUMNS * VOXEL, PAD_Y0 + PAD_VOXELS * VOXEL, PAD_Z0 + PAD_COLUMNS * VOXEL)
	)
	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

-- Writes one test pad per TerrainFit.Residues, casts onto the middle of
-- each, clears them and returns the fit with a note. `cast` and `wait` can
-- be swapped for tests.
function TerrainBuilder.Calibrate(terrain: Terrain, cast: Cast?, wait: (() -> ())?): (TerrainFit.Fit, string)
	local castFn: Cast = cast or castTerrain
	local waitFn = wait or function()
		task.wait()
	end
	local residues = TerrainFit.Residues
	for i, r in ipairs(residues) do
		writePad(terrain, PAD_X0 + (i - 1) * PAD_STEP, PAD_BASE + r)
	end
	-- The middle of each pad: the centre of its fourth column each way.
	local samples: { TerrainFit.Sample } = {}
	local missing = #residues
	local tries = 0
	local got: { [number]: number } = {}
	while missing > 0 and tries < 30 do
		waitFn()
		tries += 1
		for i, r in ipairs(residues) do
			if got[i] == nil then
				local x = PAD_X0 + (i - 1) * PAD_STEP + 3.5 * VOXEL
				local z = PAD_Z0 + 3.5 * VOXEL
				local y = castFn(x, z, PAD_BASE + 16, PAD_BASE - 10)
				if y then
					got[i] = y
					missing -= 1
					table.insert(samples, { written = PAD_BASE + r, drawn = y })
				end
			end
		end
	end
	for i = 1, #residues do
		writePad(terrain, PAD_X0 + (i - 1) * PAD_STEP, nil)
	end
	if missing > 0 then
		if #samples == 0 then
			return TerrainFit.Identity, "no ray reached the test pads; ground left as written"
		end
		return TerrainFit.Identity,
			string.format("only %d of %d test pads answered; ground left as written", #samples, #residues)
	end
	return TerrainFit.Fit(samples)
end

-- Spots on the town's flat ground (y = 0 by design): the spawn walk, the
-- parking lot, the sell pad's apron, the shop paths.
TerrainBuilder.TownProbes = {
	Vector2.new(0, 40),
	Vector2.new(40, 25),
	Vector2.new(80, 25),
	Vector2.new(0, 80),
	Vector2.new(-57, 90),
	Vector2.new(52, 90),
}

-- Where the town's ground really is: the highest of the probes (nil if no
-- ray hit), and how many hit.
function TerrainBuilder.TownGround(cast: Cast?): (number?, number)
	local castFn: Cast = cast or castTerrain
	local top: number? = nil
	local hits = 0
	for _, p in ipairs(TerrainBuilder.TownProbes) do
		local y = castFn(p.X, p.Y, 40, -40)
		if y then
			hits += 1
			top = if top then math.max(top, y) else y
		end
	end
	return top, hits
end

local function reportTown(terrain: Terrain)
	local top, hits = TerrainBuilder.TownGround()
	if top == nil then
		warn("[TerrainBuilder] Town ground check: no ray hit the town's ground")
		return
	end
	workspace:SetAttribute("TownGroundY", math.floor(top * 100 + 0.5) / 100)
	if math.abs(top) > 0.3 then
		warn(
			string.format(
				"[TerrainBuilder] Town ground is at y = %.2f, not 0 (%d probes): things in town will sink or float.%s",
				top,
				hits,
				if terrain:GetAttribute("Prebuilt") == true
					then " The baked terrain is out of date: clear Workspace.Terrain's Prebuilt attribute and publish again."
					else ""
			)
		)
	else
		print(string.format("[TerrainBuilder] Town ground at y = %.2f (%d probes): good", top, hits))
	end
end

-- Builds the whole world's terrain. `onProgress(done, total)` is called
-- after each chunk. Returns how many seconds it took.
function TerrainBuilder.Build(onProgress: ((number, number) -> ())?): number
	local started = os.clock()
	local terrain = workspace.Terrain
	setLook(terrain)
	if terrain:GetAttribute("Prebuilt") == true then
		reportTown(terrain)
		return 0
	end
	terrain:Clear()
	local useFit: TerrainFit.Fit = TerrainFit.Identity
	local note = ""
	local okFit, fitErr = pcall(function()
		useFit, note = TerrainBuilder.Calibrate(terrain)
	end)
	if not okFit then
		useFit, note = TerrainFit.Identity, "failed (" .. tostring(fitErr) .. "); ground left as written"
	end
	workspace:SetAttribute("TerrainOffset", math.floor(useFit.offset * 100 + 0.5) / 100)
	print("[TerrainBuilder] Calibration: " .. note)
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
			writeChunk(terrain, job.x0, job.z0, job.nx, job.nz, useFit)
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
	reportTown(terrain)
	return os.clock() - started
end

return TerrainBuilder
