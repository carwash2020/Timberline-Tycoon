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
--   * The engine draws the ground where it likes (the live game drew the
--     flat town 2 studs above the y = 0 we wrote), so the chunks under the
--     town go first and are rewritten, shifted, until rays read the town's
--     ground at 0 (TER-04, Shared/World/TerrainFit.NextShift). The same
--     shift then goes on every height and water level in the world. Output
--     says what it found; workspace attributes TerrainShift (studs added to
--     every written height) and TownGroundY (what the town reads after).
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
-- every height and water level written `shift` studs higher (0 if nil) so
-- the engine draws them where TerrainGen says. Materials follow the true
-- heights. Returns the region it wrote.
local function writeChunk(terrain: Terrain, x0: number, z0: number, nx: number, nz: number, shift: number?): Region3
	local lift = shift or 0
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
			local hw = h + lift
			local ww = if w then w + lift else nil
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
	return region
end

TerrainBuilder._writeChunk = writeChunk -- for tests

---------------------------------------------------------------------------
-- Measuring the engine (TER-01)
---------------------------------------------------------------------------

-- `cast(x, z, fromY, toY, water)`: the Y where a ray straight down hits
-- the terrain (its water too when `water`), or nil.
export type Cast = (x: number, z: number, fromY: number, toY: number, water: boolean?) -> number?

local castParams: { [boolean]: RaycastParams } = {}
local function castTerrain(x: number, z: number, fromY: number, toY: number, water: boolean?): number?
	local wet = water == true
	local params: RaycastParams
	local cached = castParams[wet]
	if cached then
		params = cached
	else
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		params.IgnoreWater = not wet
		castParams[wet] = params
	end
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, toY - fromY, 0), params)
	return if hit then hit.Position.Y else nil
end

-- The terrain's surface under (x, z), if it is drawn more than 0.15 studs
-- above `y` (and less than `reach`, default 6, over it); otherwise `y`.
-- NPCs, parked trucks and the spawn use it so they never stand buried if
-- the ground is not where it was written (a failed calibration, an old
-- Prebuilt bake). Rays that error (tests' fake worlds) change nothing.
function TerrainBuilder.LiftOnto(x: number, y: number, z: number, reach: number?): number
	local ok, hit = pcall(castTerrain, x, z, y + (reach or 6), y - 2, false)
	if ok and type(hit) == "number" and hit > y + 0.15 then
		return hit
	end
	return y
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
-- ray hit), how many hit, and their mean.
function TerrainBuilder.TownGround(cast: Cast?): (number?, number, number?)
	local castFn: Cast = cast or castTerrain
	local top: number? = nil
	local hits, sum = 0, 0
	for _, p in ipairs(TerrainBuilder.TownProbes) do
		local y = castFn(p.X, p.Y, 40, -40)
		if y then
			hits += 1
			sum += y
			top = if top then math.max(top, y) else y
		end
	end
	return top, hits, if hits > 0 then sum / hits else nil
end

local function reportTown(terrain: Terrain, cast: Cast?): number?
	local top, hits = TerrainBuilder.TownGround(cast)
	if top == nil then
		warn("[TerrainBuilder] Town ground check: no ray hit the town's ground")
		return nil
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
					else " Send this line to Claude."
			)
		)
	else
		print(string.format("[TerrainBuilder] Town ground at y = %.2f (%d probes): good", top, hits))
	end
	return top
end

export type Job = { x0: number, z0: number, nx: number, nz: number, dist: number }

-- Every chunk of the world, nearest the sawmill first.
function TerrainBuilder.Jobs(): { Job }
	local half = WorldLayout.WorldHalf
	local totalColumns = math.floor(2 * half / VOXEL)
	local chunksPerSide = math.ceil(totalColumns / CHUNK)
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
	return jobs
end

-- Whether a chunk holds one of the town probes.
local function underTown(job: Job): boolean
	for _, p in ipairs(TerrainBuilder.TownProbes) do
		if p.X >= job.x0 and p.X < job.x0 + job.nx * VOXEL and p.Y >= job.z0 and p.Y < job.z0 + job.nz * VOXEL then
			return true
		end
	end
	return false
end

-- Writes the chunks under the town and moves them up or down until the
-- town's ground reads y = 0 (TER-04): each try clears what the last one
-- wrote, writes them `shift` studs higher, waits a frame and casts the
-- town probes (TerrainFit.NextShift picks the next shift). Ends on the
-- best try. Returns the shift, the town's ground at it (nil if no ray
-- ever hit), the tries, and the chunks it wrote. `cast` and `wait` can be
-- swapped for tests.
function TerrainBuilder.SettleTown(
	terrain: Terrain,
	jobs: { Job },
	cast: Cast?,
	wait: (() -> ())?
): (number, number?, { TerrainFit.Try }, { [Job]: boolean })
	local waitFn = wait or function()
		task.wait()
	end
	local town: { Job } = {}
	local done: { [Job]: boolean } = {}
	for _, job in ipairs(jobs) do
		if underTown(job) then
			table.insert(town, job)
			done[job] = true
		end
	end
	local regions: { Region3 } = {}
	local function write(shift: number)
		for _, r in ipairs(regions) do
			terrain:FillBlock(r.CFrame, r.Size, Enum.Material.Air)
		end
		table.clear(regions)
		for _, job in ipairs(town) do
			table.insert(regions, writeChunk(terrain, job.x0, job.z0, job.nx, job.nz, shift))
		end
	end
	local function measure(): number?
		for _ = 1, 30 do
			waitFn()
			local _, hits, mean = TerrainBuilder.TownGround(cast)
			if mean and hits >= math.ceil(#TerrainBuilder.TownProbes / 2) then
				return mean
			end
		end
		return nil
	end
	local tries: { TerrainFit.Try } = {}
	local shift = 0
	write(shift)
	local first = measure()
	if first == nil then
		return 0, nil, tries, done
	end
	table.insert(tries, { shift = shift, error = first })
	while #tries < TerrainFit.MaxTries do
		local nextShift = TerrainFit.NextShift(tries)
		if nextShift == nil then
			break
		end
		shift = nextShift
		write(shift)
		local got = measure()
		if got == nil then
			break
		end
		table.insert(tries, { shift = shift, error = got })
	end
	local best = TerrainFit.Best(tries)
	if best.shift ~= shift then
		write(best.shift)
		waitFn()
	end
	return best.shift, best.error, tries, done
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
	local jobs = TerrainBuilder.Jobs()
	local shift, tries, done = 0, {} :: { TerrainFit.Try }, {} :: { [Job]: boolean }
	local okSettle, settleErr = pcall(function()
		local s, _, t, d = TerrainBuilder.SettleTown(terrain, jobs)
		shift, tries, done = s, t, d
	end)
	if not okSettle then
		warn("[TerrainBuilder] Settling the town's ground failed: " .. tostring(settleErr))
		shift, done = 0, {}
	end
	local steps: { string } = {}
	for _, t in ipairs(tries) do
		table.insert(steps, string.format("%+.2f -> %.2f", t.shift, t.error))
	end
	print(
		string.format(
			"[TerrainBuilder] Town ground: written at 0, drawn at %s; heights shifted %+.2f studs (tries: %s)",
			if tries[1] then string.format("%.2f", tries[1].error) else "?",
			shift,
			if #steps > 0 then table.concat(steps, ", ") else "none: no ray hit the town"
		)
	)
	workspace:SetAttribute("TerrainShift", math.floor(shift * 100 + 0.5) / 100)
	for index, job in ipairs(jobs) do
		if not done[job] then
			local ok, err = pcall(function(): any
				writeChunk(terrain, job.x0, job.z0, job.nx, job.nz, shift)
				return nil
			end)
			if not ok then
				warn(string.format("[TerrainBuilder] chunk at (%d, %d) failed: %s", job.x0, job.z0, tostring(err)))
			end
			task.wait()
		end
		if onProgress then
			onProgress(index, #jobs)
		end
	end
	reportTown(terrain)
	return os.clock() - started
end

return TerrainBuilder
