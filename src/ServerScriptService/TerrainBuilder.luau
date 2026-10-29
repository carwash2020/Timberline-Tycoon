--!strict
-- TerrainBuilder: writes the world (Shared/World/TerrainGen) into
-- workspace.Terrain when the server starts.
--   * 256 x 256-stud chunks (64 x 64 voxel columns), nearest the town
--     first, so the spawn is solid within the first second or two.
--   * Only a crust: each chunk is filled from a few voxels under its lowest
--     ground up to its highest ground or water. Below that nobody looks.
--   * Fractional occupancy on the surface voxel (TerrainGen.Voxel) gives
--     smooth hills (under water the bed rounds to whole voxels, so water
--     always meets it); the top three voxels (SurfaceBand) take the surface
--     material, deeper ones what lies beneath (UnderMaterial).
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
local UndergroundData = require(game:GetService("ReplicatedStorage").Shared.World.UndergroundData)
local NearFirst = require(game:GetService("ReplicatedStorage").Shared.NearFirst)
local TimeSlice = require(game:GetService("ReplicatedStorage").Shared.TimeSlice)

local TerrainBuilder = {}

local VOXEL = 4
local CHUNK = 64 -- voxel columns per chunk side
local CRUST = 8 -- 32 studs of solid ground under the surface
TerrainBuilder.Crust = CRUST
-- How many voxels at the top of a column take the surface material (T402:
-- 3, was 2; a thicker top layer keeps the grass colour where the ground
-- slopes and the under-layer would otherwise blend up through it).
local SURFACE_BAND = 3
TerrainBuilder.SurfaceBand = SURFACE_BAND
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

-- What lies under a surface material (the voxels below the top band). Grass
-- and LeafyGrass always sit on Ground, never Rock or Slate: those blend up
-- through the grass on a slope as grey smears (T402).
function TerrainBuilder.UnderMaterial(surface: string): string
	local under = TerrainGen.SubMaterial(surface)
	if (surface == "Grass" or surface == "LeafyGrass") and (under == "Rock" or under == "Slate") then
		return "Ground"
	end
	return under
end

local function setLook(terrain: Terrain)
	-- The material colours are MaterialSetup's alone (T402).
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
			local w = TerrainGen.WaterLevelFor(x, z, h)
			local hw = h + lift
			local ww = if w then w + lift else nil
			wrow[k] = ww or NO_WATER
			hrow[k] = hw
			lo = math.min(lo, hw)
			hi = math.max(hi, hw, ww or -math.huge)
			local floorY = UndergroundData.LowestFloor(x, z)
			if floorY then
				lo = math.min(lo, floorY - UndergroundData.FloorSolid)
			end
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
			local under = material(TerrainBuilder.UnderMaterial(surfaceName))
			-- Index of the topmost solid voxel: the one the ground's surface cuts, or (when
			-- the ground is exactly on a voxel edge, as the flat town's y = 0 is) the one just under it.
			local topSolid = math.ceil(h / VOXEL) - yMin
			for j = 1, ny do
				local bottom = (yMin + j - 1) * VOXEL
				local kind, occ = TerrainGen.Voxel(h, if w > NO_WATER then w else nil, bottom)
				if kind == "solid" then
					mx[j][k] = if j > topSolid - SURFACE_BAND then top else under
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

-- The drawn terrain's surface within `reach` studs above and below `y` at
-- (x, z), or nil (no hit, or the ray errored: a test's fake world).
function TerrainBuilder.SurfaceNear(x: number, y: number, z: number, reach: number?): number?
	local r = reach or 3
	local ok, hit = pcall(castTerrain, x, z, y + r, y - r, false)
	if ok and type(hit) == "number" then
		return hit
	end
	return nil
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
					else " Send this line to the build agent."
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
	local half = WorldLayout.WorldHalf + WorldLayout.TerrainSkirt
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
	-- The north strip is folded inside the square (MAP_V1). Only add its
	-- chunks when it sits outside the generated square, so a column is
	-- never written twice.
	local strip = WorldLayout.NorthStrip
	local generated = half
	local stripOutside = strip.z0 >= generated
		or strip.z1 <= -generated
		or strip.x0 >= generated
		or strip.x1 <= -generated
	local xCols = if stripOutside then math.floor((strip.x1 - strip.x0) / VOXEL) else 0
	local zCols = math.floor((strip.z1 - strip.z0) / VOXEL)
	local xChunks = math.ceil(xCols / CHUNK)
	local zChunks = math.ceil(zCols / CHUNK)
	for cx = 0, xChunks - 1 do
		for cz = 0, zChunks - 1 do
			local x0 = strip.x0 + cx * CHUNK * VOXEL
			local z0 = strip.z0 + cz * CHUNK * VOXEL
			local mid = Vector3.new(x0 + CHUNK * VOXEL / 2, 0, z0 + CHUNK * VOXEL / 2)
			table.insert(jobs, {
				x0 = x0,
				z0 = z0,
				nx = math.min(CHUNK, xCols - cx * CHUNK),
				nz = math.min(CHUNK, zCols - cz * CHUNK),
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
-- swapped for tests; `pace` (a TimeSlice's step) is called after each
-- block so the settle yields every few milliseconds like the rest.
function TerrainBuilder.SettleTown(
	terrain: Terrain,
	jobs: { Job },
	cast: Cast?,
	wait: (() -> ())?,
	pace: (() -> boolean)?
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
		for _, block in ipairs(TerrainBuilder.Split(town, TerrainBuilder.SubColumns)) do
			table.insert(regions, writeChunk(terrain, block.x0, block.z0, block.nx, block.nz, shift))
			if pace then
				pace() -- a few ms of blocks, then the frame back (no 64-column stall)
			end
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

-- How long Build writes before it yields a frame (T402: 4 ms, was 30 ms near
-- the town and 12 ms in the background; a 64-column chunk is now written as
-- 16-column blocks, so one stretch of work is a block or two).
TerrainBuilder.YieldSeconds = 0.004
TerrainBuilder.SliceSeconds = TerrainBuilder.YieldSeconds

-- Staged build (server audit, 11 October 2026). Writing all 100 chunks took
-- 30 to 55 s, and the first player waited for every one of them (the
-- "terrain" gate sat behind the whole world). Now Build can return once the
-- chunks round the town are written (the chunks that touch a disc of
-- NearRadius studs round the sawmill: the spawn, the shops, the sell area,
-- Murph's camp, the tutorial grove) and hand back `finish`, which writes the
-- rest in small blocks a frame at a time while players already play, the
-- plot pads' ground first, then outward from the sawmill, and carves the
-- caves last.
TerrainBuilder.NearRadius = 230
TerrainBuilder.SubColumns = 16 -- voxel columns a side per background block (64 studs): about 1/16 of a chunk, so no frame stalls
TerrainBuilder.BackgroundSliceSeconds = TerrainBuilder.YieldSeconds -- the same 4 ms ceiling for the background blocks
TerrainBuilder.SpotReach = 150 -- studs: blocks this close to a `firstSpots` point (a plot pad) go first

export type Options = {
	nearRadius: number?, -- stage the build: only the chunks touching this disc round the sawmill block
	firstSpots: { Vector2 }?, -- x, z points whose ground goes first after the near chunks (the plot pads)
	sliceSeconds: (() -> number)?, -- the background slice, asked before each frame (default BackgroundSliceSeconds)
	frame: TimeSlice.FrameBudgetLike?, -- a frame budget shared with the forest and the deferred queue: then it, not sliceSeconds, paces the writes
	focus: (() -> { NearFirst.Point })?, -- where the players are: the later blocks nearest them go first, asked again as they move
	clock: (() -> number)?, -- os.clock; specs inject one
	wait: (() -> ())?, -- task.wait; specs inject one
}

TerrainBuilder.ResortDistance = 48 -- studs a player may move before the remaining blocks are put in order again

local function hub(): Vector3
	return WorldLayout.Sawmill
end

-- Whether a job's rectangle touches the disc of `radius` studs round the sawmill.
function TerrainBuilder.Touches(job: Job, radius: number): boolean
	local at = hub()
	local cx = math.clamp(at.X, job.x0, job.x0 + job.nx * VOXEL)
	local cz = math.clamp(at.Z, job.z0, job.z0 + job.nz * VOXEL)
	local dx, dz = cx - at.X, cz - at.Z
	return dx * dx + dz * dz <= radius * radius
end

-- Every job cut into blocks of at most `columns` voxel columns a side.
function TerrainBuilder.Split(jobs: { Job }, columns: number): { Job }
	local out: { Job } = {}
	local at = hub()
	for _, job in ipairs(jobs) do
		local ox = 0
		while ox < job.nx do
			local sx = math.min(columns, job.nx - ox)
			local oz = 0
			while oz < job.nz do
				local sz = math.min(columns, job.nz - oz)
				local x0 = job.x0 + ox * VOXEL
				local z0 = job.z0 + oz * VOXEL
				local mx, mz = x0 + sx * VOXEL / 2 - at.X, z0 + sz * VOXEL / 2 - at.Z
				table.insert(out, { x0 = x0, z0 = z0, nx = sx, nz = sz, dist = math.sqrt(mx * mx + mz * mz) })
				oz += sz
			end
			ox += sx
		end
	end
	return out
end

-- Whether a block touches the town zone (WorldLayout.TownZone): its roads,
-- curbs and lot sit on this ground, so it is written first (T402).
function TerrainBuilder.InTown(block: Job): boolean
	local zone = WorldLayout.TownZone
	return block.x0 < zone.x1
		and block.x0 + block.nx * VOXEL > zone.x0
		and block.z0 < zone.z1
		and block.z0 + block.nz * VOXEL > zone.z0
end

-- Puts blocks in the order they are written: the town zone's first, then those within SpotReach of a
-- `spots` point first, then the rest, each nearest the players first (the
-- nearest of `focus`; the sawmill when there is none). Same order as ever
-- when `focus` is nil.
function TerrainBuilder.Order(blocks: { Job }, spots: { Vector2 }?, focus: { NearFirst.Point }?): { Job }
	local key: { [Job]: number } = {}
	local hasFocus = focus ~= nil and #focus > 0
	for _, block in ipairs(blocks) do
		local k = block.dist
		if hasFocus then
			local mx, mz = block.x0 + block.nx * VOXEL / 2, block.z0 + block.nz * VOXEL / 2
			k = math.sqrt(NearFirst.Distance2(mx, mz, focus, { x = 0, z = 0 }))
		end
		if TerrainBuilder.InTown(block) then
			k -= 2e6 -- the town zone's ground goes before everything else
		end
		for _, spot in ipairs(spots or {}) do
			local dx = math.max(block.x0 - spot.X, 0, spot.X - (block.x0 + block.nx * VOXEL))
			local dz = math.max(block.z0 - spot.Y, 0, spot.Y - (block.z0 + block.nz * VOXEL))
			if dx <= TerrainBuilder.SpotReach and dz <= TerrainBuilder.SpotReach then
				k -= 1e6
				break
			end
		end
		key[block] = k
	end
	table.sort(blocks, function(a: Job, b: Job): boolean
		local ka, kb = key[a], key[b]
		if ka ~= kb then
			return ka < kb
		end
		if a.x0 ~= b.x0 then
			return a.x0 < b.x0
		end
		return a.z0 < b.z0
	end)
	return blocks
end

-- Builds the world's terrain. `onProgress(done, total)` is called after
-- each chunk. Returns how many seconds it took and, when `options.nearRadius`
-- left chunks for later, `finish`: call it (it yields) to write them and
-- carve the caves; it returns its own seconds.
-- T402: every write is a 16-column block, and after each one the build
-- yields (task.wait) once about YieldSeconds (4 ms) of os.clock() has passed,
-- or sooner when the shared frame budget is spent. Each step's time is
-- printed ("[Perf] terrain step ...") and kept in TerrainBuilder.StepTimes.
export type StepTime = { name: string, seconds: number, longest: number, blocks: number }
TerrainBuilder.StepTimes = {} :: { StepTime }

local function recordStep(name: string, seconds: number, longest: number, blocks: number)
	table.insert(TerrainBuilder.StepTimes, { name = name, seconds = seconds, longest = longest, blocks = blocks })
	print(
		string.format(
			"[Perf] terrain step %s: %.0f ms, longest stretch %.0f ms (%d blocks)",
			name,
			seconds * 1000,
			longest * 1000,
			blocks
		)
	)
end

function TerrainBuilder.Build(onProgress: ((number, number) -> ())?, options: Options?): (number, (() -> number)?)
	local clock = (options and options.clock) or os.clock
	local started = clock()
	table.clear(TerrainBuilder.StepTimes)
	local terrain = workspace.Terrain
	setLook(terrain)
	if terrain:GetAttribute("Prebuilt") == true then
		TerrainBuilder.PaintRoadShoulders(terrain)
		reportTown(terrain)
		return 0, nil
	end
	terrain:Clear()
	local jobs = TerrainBuilder.Jobs()
	local frame = options and options.frame
	-- A slice for the settle and one for the near ring (each also follows the frame budget, when given, not only the 4 ms).
	local function newSlice(): TimeSlice.Slice
		return TimeSlice.new({
			frame = frame,
			budget = TerrainBuilder.YieldSeconds,
			clock = options and options.clock,
			wait = options and options.wait,
		})
	end
	local settleSlice = newSlice() -- the near ring shares it: no yield-free gap where one stage ends and the next begins
	local shift, tries, done = 0, {} :: { TerrainFit.Try }, {} :: { [Job]: boolean }
	local settleStart = clock()
	local okSettle, settleErr = pcall(function()
		local s, _, t, d = TerrainBuilder.SettleTown(terrain, jobs, nil, nil, settleSlice.step)
		shift, tries, done = s, t, d
	end)
	if not okSettle then
		warn("[TerrainBuilder] Settling the town's ground failed: " .. tostring(settleErr))
		shift, done = 0, {}
	end
	local settleCount = 0
	for _ in pairs(done) do
		settleCount += 1
	end
	settleSlice.finish()
	recordStep("settle town", clock() - settleStart, settleSlice.longest(), settleCount)
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
	local nearRadius = if options then options.nearRadius else nil
	local near: { Job } = {}
	local later: { Job } = {}
	for _, job in ipairs(jobs) do
		if not done[job] then
			if nearRadius == nil or TerrainBuilder.Touches(job, nearRadius) then
				table.insert(near, job)
			else
				table.insert(later, job)
			end
		end
	end
	local total = #jobs
	local finished = 0
	for _ in pairs(done) do
		finished += 1
	end
	local nearStart = clock()
	local nearSlice = settleSlice
	local nearBlocks = 0
	for _, job in ipairs(near) do
		for _, block in ipairs(TerrainBuilder.Split({ job }, TerrainBuilder.SubColumns)) do
			local ok, err = pcall(function(): any
				writeChunk(terrain, block.x0, block.z0, block.nx, block.nz, shift)
				return nil
			end)
			if not ok then
				warn(string.format("[TerrainBuilder] block at (%d, %d) failed: %s", block.x0, block.z0, tostring(err)))
			end
			nearBlocks += 1
			-- A few ms of blocks, then a yield: the server stays alive (LOAD-01).
			nearSlice.step()
		end
		finished += 1
		if onProgress then
			onProgress(finished, total)
		end
	end
	nearSlice.finish()
	local nearLongest = nearSlice.longest()
	recordStep("near ring", clock() - nearStart, nearLongest, nearBlocks)
	print(
		string.format(
			"[Perf] stage terrain near ring: total %.2fs, longest step %.0f ms (%d chunks)",
			clock() - started,
			nearLongest * 1000,
			#near
		)
	)
	if #later == 0 then
		TerrainBuilder.Carve(terrain, shift)
		TerrainBuilder.PaintRoadShoulders(terrain)
		reportTown(terrain)
		return clock() - started, nil
	end
	reportTown(terrain)
	local nearSeconds = clock() - started
	local function finish(): number
		local finishStarted = clock()
		local spots = options and options.firstSpots
		local focusFn = options and options.focus
		local focus: { NearFirst.Point } = if focusFn then focusFn() else {}
		local blocks = TerrainBuilder.Order(TerrainBuilder.Split(later, TerrainBuilder.SubColumns), spots, focus)
		local resortedFor = focus
		local nextBlock = 1
		-- The block's own ceiling: the supplier asked each frame (specs, tuning), else YieldSeconds.
		local sliceBudget = if options and options.sliceSeconds then options.sliceSeconds else nil
		local slice = TimeSlice.new({
			frame = frame,
			budget = if sliceBudget then sliceBudget() else TerrainBuilder.BackgroundSliceSeconds,
			clock = options and options.clock,
			wait = options and options.wait,
		})
		local written = 0
		while nextBlock <= #blocks do
			-- Players who have moved pull the blocks round them forward.
			if focusFn and nextBlock > 1 then
				local now = focusFn()
				if NearFirst.Moved(now, resortedFor, TerrainBuilder.ResortDistance) then
					resortedFor = now
					blocks = TerrainBuilder.Order(table.move(blocks, nextBlock, #blocks, 1, {}), spots, now)
					nextBlock = 1
				end
			end
			local block = blocks[nextBlock]
			nextBlock += 1
			local ok, err = pcall(function(): any
				writeChunk(terrain, block.x0, block.z0, block.nx, block.nz, shift)
				return nil
			end)
			if not ok then
				warn(string.format("[TerrainBuilder] block at (%d, %d) failed: %s", block.x0, block.z0, tostring(err)))
			end
			written += 1
			if sliceBudget then
				slice.setBudget(sliceBudget())
			end
			slice.step()
		end
		local carveStart = clock()
		TerrainBuilder.Carve(terrain, shift, slice.step)
		if onProgress then
			onProgress(total, total)
		end
		slice.finish()
		local longest = slice.longest()
		recordStep("background blocks", carveStart - finishStarted, longest, written)
		recordStep("caves", clock() - carveStart, longest, 0)
		TerrainBuilder.PaintRoadShoulders(terrain)
		print(
			string.format(
				"[Perf] stage terrain background: total %.2fs, longest step %.0f ms (%d blocks)",
				clock() - finishStarted,
				longest * 1000,
				written
			)
		)
		return clock() - finishStarted
	end
	return nearSeconds, finish
end

-- Mains: a Ground band (TrailDirt) half-width 18, then the gravel bed
-- half-width 14 on top. Voxels are 4 studs, so 14 to 18 is one straight
-- voxel of dirt. The grade itself stays at DriveHalf (16).
function TerrainBuilder.PaintRoadShoulders(terrain: Terrain)
	local ground = material("Ground")
	local gravel = material(TerrainGen.GravelMaterial)
	for _, road in ipairs(WorldLayout.Roads) do
		local dirtHalf = WorldLayout.DirtHalf(road)
		local planHalf = WorldLayout.PlanWidth(road) / 2
		if dirtHalf <= planHalf then
			continue
		end
		local pts = road.points
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local dx, dz = b.X - a.X, b.Y - a.Y
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 1 then
				continue
			end
			local mx, mz = (a.X + b.X) / 2, (a.Y + b.Y) / 2
			local y = TerrainGen.HeightAt(mx, mz)
			local yaw = math.atan2(dx, dz)
			local cf = CFrame.new(mx, y, mz) * CFrame.Angles(0, yaw, 0)
			local function fill(width: number, mat: Enum.Material)
				pcall(function()
					-- A stud of overlap at the joints, so the voxel band does not gap.
					terrain:FillBlock(cf, Vector3.new(width, 4, len + 4), mat)
				end)
			end
			fill(dirtHalf * 2, ground)
			fill(planHalf * 2, gravel)
		end
	end
end

-- Second pass: air out the caves, the passages and the truck tunnel.
-- The voxels under each floor stay, so the crust and the 24 studs under
-- a floor are still solid. `shift` is the same studs added to the crust.
function TerrainBuilder.Carve(terrain: Terrain, shift: number?, step: (() -> boolean)?)
	local lift = shift or 0
	local air = Enum.Material.Air
	for _, box in ipairs(UndergroundData.AirBoxes()) do
		local size = Vector3.new(box.sx, box.sy, box.sz)
		local cf = CFrame.new(box.x, box.y + lift, box.z)
		local ok, err = pcall(function()
			terrain:FillBlock(cf, size, air)
		end)
		if not ok then
			warn("[TerrainBuilder] carve failed: " .. tostring(err))
		end
		if step then
			step() -- the later caves are many boxes: a frame's worth, then the frame back
		end
	end
end

return TerrainBuilder
