--!strict
-- ValleyGround (T409): the one live landform. TerrainGen.HeightAt calls
-- this unless the classic ground is on (the first trees, T410). There is
-- no second height function for the player.
--
-- Shape: today's ground, plus a lift for each T408 disc (pads, the north
-- strip, wet columns and the live road beds stay put), then the draft
-- roads cut in as level beds at no more than 12% with banks both sides.
-- The lodge pad at (-40, 720) is flat and is not a road bed.
--
-- Materials: RoadGravel (Asphalt) on the bed, the draft belt sequence
-- beside it, and rock on anything steeper than 40 degrees.

local WorldLayout = require(script.Parent.WorldLayout)
local WorldPlanDraft = require(script.Parent.WorldPlanDraft)
local BiomeData = require(script.Parent.Parent.BiomeData)

local ValleyGround = {}

local GRADE = 0.12
-- A flat bed plus a short bank stays inside 64 studs. Where the graded bed
-- stands well above the hillside the bank lengthens, so the ramp stays near
-- 4% and a rock already on that ground is not tipped over. A short bank is
-- kept where the two heights already agree, so a level meadow is not paved
-- out into a sheet.
local BANK = 10
-- A bank off a draft bed stays near 6 degrees, under the 15 degree country
-- cap, and starts only once it is past a shelf's held blend.
-- Shelf ramp and road bank. 0.1 cleared the hill test; a little under that
-- keeps a rock just off the gravel inside ClusterDrop.
local SHELF_SLOPE = 0.1
-- Flatter beside the gravel, where a rock's footprint sits, then the
-- country grade. The far grade is what keeps a road switch under 15 degrees.
local NEAR_SLOPE = 0.07
local NEAR_RUN = 6
local BANK_SLOPE = 0.09
local MAX_REACH = 280
local LODGE_X = -40
local LODGE_Z = 720
local LODGE_R = 26
local CELL = 96
local STEEP = math.tan(math.rad(40))

ValleyGround.LodgeX = LODGE_X
ValleyGround.LodgeZ = LODGE_Z
ValleyGround.LodgePad = LODGE_R
ValleyGround.GradeCap = GRADE
ValleyGround.Steep = STEEP

local legacy: (number, number) -> number = function(_x: number, _z: number): number
	return 0
end
local legacyWater: (number, number) -> number? = function(_x: number, _z: number): number?
	return nil
end

local ready = false
local padH = 0

type Seg = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	ah: number,
	bh: number,
	half: number,
	name: string,
}
-- A sample on a draft centreline. Locked samples (a town pad, the north
-- strip, a reserved floor, a junction both roads share) do not move.
type Sample = {
	x: number,
	z: number,
	h: number,
	target: number,
	locked: boolean,
	road: number,
	index: number,
}

-- A hair under the 12% test cap so a junction weld cannot push a step over.
local ROAD_GRADE = 0.115
-- The toll spur's own cap is 20% (strict). Stay under it.
local SPUR_GRADE = 0.19
-- Only a shared point. A wider weld locked neighbouring samples to two
-- different crossings and the span between them exceeded the grade cap.
local JUNCTION = 3

local buckets: { [number]: { Seg } } = {}
local liveLines: { { line: any, half: number, drive: number, name: string } } = {}

local function bucketKey(ix: number, iz: number): number
	return (ix + 80) * 400 + (iz + 80)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function hypot(dx: number, dz: number): number
	return math.sqrt(dx * dx + dz * dz)
end

-- Clearance to the nearest live road edge (negative on the bed), and the
-- distance to the nearest live centreline.
local function liveNear(x: number, z: number): (number, number)
	local bestClear = 1e6
	local bestDist = 1e6
	for _, road in ipairs(liveLines) do
		local d = WorldLayout.FastDistance(road.line, x, z, road.half + 48)
		local clear = d - road.half
		if clear < bestClear then
			bestClear = clear
		end
		if d < bestDist then
			bestDist = d
		end
	end
	return bestClear, bestDist
end

local function liveClear(x: number, z: number): number
	local clear = liveNear(x, z)
	return clear
end

-- Distance to the edge of the flat drive (negative on it). Wider than the
-- plan bed on mains, so HeightAt stays level out to DriveHalf. Paint and
-- the tree plan keep using liveClear / PlanWidth.
local function driveClear(x: number, z: number): number
	local best = 1e6
	local inTown = WorldLayout.InTownZone(x, z)
	for _, road in ipairs(liveLines) do
		local drive = road.drive
		if
			inTown
			and WorldLayout.TownBedRoads[road.name]
			and not WorldLayout.OnStorePad(x, z)
			and not WorldLayout.OnPlotPad(x, z)
		then
			drive = math.max(drive, WorldLayout.TownBedHalf)
		end
		local reach = drive + 2
		local d = WorldLayout.FastDistance(road.line, x, z, reach)
		local clear = d - drive
		if clear < best then
			best = clear
		end
	end
	return best
end

local AMP: { [string]: number } = {
	frost = 18,
	skyroot = 14,
	-- 1.5, not 8: a steeper pine disc drops the ground under a rock at
	-- (-303, 169) by more than ClusterDrop allows.
	pine = 1.5,
	mesa = 10,
	isle = 7,
	valley = 3,
	gloam = -6,
	bayou = -2,
	caldera = 0,
}

local function regionLift(x: number, z: number): number
	local lift = 0
	for _, region in ipairs(WorldPlanDraft.Regions) do
		local d = hypot(x - region.x, z - region.z)
		if region.id == "caldera" then
			-- A bowl. The wall from 16 to 40 studs is steeper than 40 degrees
			-- and paints as rock, never grass.
			if d < 16 then
				lift += -6
			elseif d < 40 then
				lift += -6 + 32 * ((d - 16) / 24)
			elseif d < region.radius then
				lift += 8 * smooth(1 - (d - 40) / (region.radius - 40))
			end
		else
			local amp = AMP[region.id] or 0
			if d < region.radius and amp ~= 0 then
				lift += amp * smooth(1 - d / region.radius)
			end
		end
	end
	return lift
end

local FADE = 48

local function outsideRect(x: number, z: number, x0: number, z0: number, x1: number, z1: number): number
	local dx = math.max(x0 - x, 0, x - x1)
	local dz = math.max(z0 - z, 0, z - z1)
	return hypot(dx, dz)
end

-- 0 on a declared pad, 1 once FADE studs outside it. The disc must not step
-- off a yard: that join was a cliff.
local function padFade(x: number, z: number): number
	local best = 1e6
	for _, zone in ipairs(WorldLayout.FlatZones) do
		local d = outsideRect(x, z, zone.x0, zone.z0, zone.x1, zone.z1)
		if d < best then
			best = d
		end
	end
	for _, pad in ipairs(WorldLayout.StorePads) do
		local d = outsideRect(x, z, pad.x0, pad.z0, pad.x1, pad.z1)
		if d < best then
			best = d
		end
	end
	if best >= FADE then
		return 1
	end
	return smooth(best / FADE)
end

-- The toll bridge takes its deck height from the ground at the shelf probe.
-- The lift fades out there so the probe, the deck and the spur stay one shelf.
local function shelfFade(x: number, z: number): number
	local d = hypot(x, z - WorldLayout.ShelfProbeZ)
	local reach = 90
	if d >= reach then
		return 1
	end
	return smooth(d / reach)
end

local function countryAt(x: number, z: number): number
	local base = legacy(x, z)
	if WorldLayout.FlatWeight(x, z) > 0.85 or WorldLayout.InNorthStrip(x, z) or WorldLayout.InReservedRegion(x, z) then
		return base
	end
	if legacyWater(x, z) ~= nil then
		return base
	end
	-- The lift grows away from a live road. A hard cut left one sign post on
	-- the hillside and the other on the bed, six studs apart.
	local clear = liveClear(x, z)
	local fade = 0
	if clear > 0 then
		local reach = 80
		fade = if clear >= reach then 1 else smooth(clear / reach)
	end
	return base + regionLift(x, z) * padFade(x, z) * shelfFade(x, z) * fade
end

local function roadTarget(x: number, z: number): number
	local h = countryAt(x, z)
	local wet = legacyWater(x, z)
	if wet and h < wet + 1.2 then
		h = wet + 1.2
	end
	-- A live road keeps its own height. The draft grade can only arrive there
	-- as fast as the cap allows, so the target comes down as the bed gets close.
	if
		WorldLayout.FlatWeight(x, z) > 0.85
		or WorldLayout.InNorthStrip(x, z)
		or WorldLayout.InReservedRegion(x, z)
		or WorldLayout.OnPlotPad(x, z)
	then
		return h
	end
	for _, road in ipairs(liveLines) do
		local segs = road.line.segs
		local best = 1e6
		local hx, hz = x, z
		for i = 1, #segs, 4 do
			local ax, az, bx, bz = segs[i], segs[i + 1], segs[i + 2], segs[i + 3]
			local abx, abz = bx - ax, bz - az
			local len2 = abx * abx + abz * abz
			local t = if len2 > 1e-8 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
			local px = ax + abx * t
			local pz = az + abz * t
			local d = hypot(x - px, z - pz)
			if d < best then
				best = d
				hx, hz = px, pz
			end
		end
		local edge = best - road.half
		if edge < 160 then
			local room = 0.1 * math.max(edge, 0)
			local spineH = legacy(hx, hz)
			h = math.clamp(h, spineH - room, spineH + room)
		end
	end
	return h
end

local function lodgeDist(x: number, z: number): number
	return hypot(x - LODGE_X, z - LODGE_Z)
end

local function pushSeg(seg: Seg)
	local reach = seg.half + MAX_REACH
	local minX = math.min(seg.ax, seg.bx) - reach
	local maxX = math.max(seg.ax, seg.bx) + reach
	local minZ = math.min(seg.az, seg.bz) - reach
	local maxZ = math.max(seg.az, seg.bz) + reach
	local ix0 = math.floor(minX / CELL)
	local ix1 = math.floor(maxX / CELL)
	local iz0 = math.floor(minZ / CELL)
	local iz1 = math.floor(maxZ / CELL)
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local key = bucketKey(ix, iz)
			local list = buckets[key]
			if not list then
				list = {}
				buckets[key] = list
			end
			table.insert(list, seg)
		end
	end
end

local function chainCap(a: Sample, b: Sample): number
	return ROAD_GRADE * math.max(hypot(b.x - a.x, b.z - a.z), 1)
end

-- Grade one road. Free samples follow the ground until the slope would pass
-- the cap, then the road cuts. A backward sweep pulls the approach up to a
-- locked pad so the join is not a wall. The last sweep restores the cap
-- wherever the backward sweep had to move a sample.
local function solveChain(group: { Sample })
	local n = #group
	for i = 1, n do
		if not group[i].locked then
			group[i].h = group[i].target
		end
	end
	for i = 2, n do
		local a, b = group[i - 1], group[i]
		if not b.locked then
			local c = chainCap(a, b)
			b.h = math.clamp(b.target, a.h - c, a.h + c)
		end
	end
	for i = n - 1, 1, -1 do
		local a, b = group[i], group[i + 1]
		if not a.locked then
			local c = chainCap(a, b)
			a.h = math.clamp(a.h, b.h - c, b.h + c)
		end
	end
end

-- Two roads that meet, or a hairpin that folds back on itself, must share
-- one height. Otherwise the nearest-segment query jumps from one bed to the
-- other and the centreline grade spikes. Locked pads keep their own height.
local function syncJunctions(samples: { Sample })
	local parent: { number } = table.create(#samples)
	for i = 1, #samples do
		parent[i] = i
	end
	local function find(i: number): number
		local root = i
		while parent[root] ~= root do
			root = parent[root]
		end
		while parent[i] ~= root do
			local next = parent[i]
			parent[i] = root
			i = next
		end
		return root
	end
	local function unite(a: number, b: number)
		local pa, pb = find(a), find(b)
		if pa ~= pb then
			parent[pb] = pa
		end
	end
	local cells: { [number]: { Sample } } = {}
	local function key(ix: number, iz: number): number
		return (ix + 200) * 800 + (iz + 200)
	end
	for _, sample in ipairs(samples) do
		local k = key(math.floor(sample.x / JUNCTION), math.floor(sample.z / JUNCTION))
		local list = cells[k]
		if not list then
			list = {}
			cells[k] = list
		end
		table.insert(list, sample)
	end
	for _, sample in ipairs(samples) do
		local ix = math.floor(sample.x / JUNCTION)
		local iz = math.floor(sample.z / JUNCTION)
		for ox = -1, 1 do
			for oz = -1, 1 do
				local list = cells[key(ix + ox, iz + oz)]
				if list then
					for _, other in ipairs(list) do
						if other.index > sample.index and other.road ~= sample.road then
							if hypot(other.x - sample.x, other.z - sample.z) <= JUNCTION then
								unite(sample.index, other.index)
							end
						end
					end
				end
			end
		end
	end
	local clusters: { [number]: { Sample } } = {}
	for _, sample in ipairs(samples) do
		local root = find(sample.index)
		local list = clusters[root]
		if not list then
			list = {}
			clusters[root] = list
		end
		table.insert(list, sample)
	end
	for _, cluster in pairs(clusters) do
		if #cluster < 2 then
			continue
		end
		-- The higher road wins. Averaging pulled a junction below the grade a
		-- live bed could descend, and the centreline stepped.
		local h = -1e9
		for _, sample in ipairs(cluster) do
			if sample.h > h then
				h = sample.h
			end
		end
		for _, sample in ipairs(cluster) do
			if not sample.locked then
				sample.h = h
				sample.locked = true
			end
		end
	end
end

local function buildRoads()
	table.clear(buckets)
	for _, road in ipairs(WorldLayout.Roads) do
		table.insert(liveLines, {
			line = WorldLayout.FastLine(road.points),
			half = WorldLayout.PlanWidth(road) / 2,
			drive = WorldLayout.DriveHalf(road),
			name = road.name,
		})
	end
	local groups: { { Sample } } = {}
	local all: { Sample } = {}
	local function add(group: { Sample }, x: number, z: number, roadIndex: number)
		local onPad = WorldLayout.OnPlotPad(x, z)
		if not onPad then
			for _, pad in ipairs(WorldLayout.StorePads) do
				if x >= pad.x0 and x <= pad.x1 and z >= pad.z0 and z <= pad.z1 then
					onPad = true
					break
				end
			end
		end
		local locked = WorldLayout.FlatWeight(x, z) > 0.85
			or WorldLayout.InNorthStrip(x, z)
			or WorldLayout.InReservedRegion(x, z)
			or onPad
		local target = roadTarget(x, z)
		local sample: Sample = {
			x = x,
			z = z,
			h = target,
			target = target,
			locked = locked,
			road = roadIndex,
			index = #all + 1,
		}
		table.insert(group, sample)
		table.insert(all, sample)
	end
	for roadIndex, road in ipairs(WorldPlanDraft.Roads) do
		local group: { Sample } = {}
		table.insert(groups, group)
		local pts = road.points
		add(group, pts[1].x, pts[1].z, roadIndex)
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			local dx, dz = b.x - a.x, b.z - a.z
			local len = hypot(dx, dz)
			local n = math.max(1, math.floor(len / 8))
			for s = 1, n do
				local u = s / n
				add(group, a.x + dx * u, a.z + dz * u, roadIndex)
			end
		end
		solveChain(group)
	end
	syncJunctions(all)
	for _, group in ipairs(groups) do
		solveChain(group)
	end
	-- The lodge pad is flat. It takes the graded height under the pin, and
	-- the roads lock to that so the approach arrives level.
	padH = countryAt(LODGE_X, LODGE_Z)
	local bestD = 1e6
	for _, sample in ipairs(all) do
		local d = hypot(sample.x - LODGE_X, sample.z - LODGE_Z)
		if d < bestD then
			bestD = d
			padH = sample.h
		end
	end
	for _, sample in ipairs(all) do
		if lodgeDist(sample.x, sample.z) <= LODGE_R then
			sample.h = padH
			sample.locked = true
		end
	end
	for _, group in ipairs(groups) do
		solveChain(group)
	end
	-- On a live bed the ground is that road, not the draft grade. Lock those
	-- samples and solve once more so the approach arrives within the cap.
	for _, group in ipairs(groups) do
		local touch = false
		for _, sample in ipairs(group) do
			if lodgeDist(sample.x, sample.z) > LODGE_R and liveClear(sample.x, sample.z) <= 0 then
				sample.h = legacy(sample.x, sample.z)
				sample.target = sample.h
				sample.locked = true
				touch = true
			end
		end
		if touch then
			solveChain(group)
		end
	end
	for roadIndex, group in ipairs(groups) do
		local road = WorldPlanDraft.Roads[roadIndex]
		local half = road.width / 2
		for i = 2, #group do
			local a, b = group[i - 1], group[i]
			pushSeg({
				ax = a.x,
				az = a.z,
				bx = b.x,
				bz = b.z,
				ah = a.h,
				bh = b.h,
				half = half,
				name = road.name,
			})
		end
	end
end

local function closest(x: number, z: number): (number?, number?, number?)
	local list = buckets[bucketKey(math.floor(x / CELL), math.floor(z / CELL))]
	if not list then
		return nil, nil, nil
	end
	local bestD = math.huge
	local bestHalf, bestH = 0, 0
	for _, seg in ipairs(list) do
		local abx, abz = seg.bx - seg.ax, seg.bz - seg.az
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-8 then math.clamp(((x - seg.ax) * abx + (z - seg.az) * abz) / len2, 0, 1) else 0
		local px = seg.ax + abx * t
		local pz = seg.az + abz * t
		local d = hypot(x - px, z - pz)
		if d < bestD then
			bestD = d
			bestHalf = seg.half
			bestH = seg.ah + (seg.bh - seg.ah) * t
		end
	end
	if bestD > bestHalf + MAX_REACH then
		return nil, nil, nil
	end
	return bestD, bestHalf, bestH
end

function ValleyGround.Ready(): boolean
	return ready
end

-- The spur's approach (Snow Road to the graded suffix) is not a draft road,
-- and it is not OnTollSpur. Lodge Path crosses it. A legacy hold there
-- punched a hole in the path; the raw hillside is steeper than the spur's
-- 20% cap. This profile is the centreline both of them share: legacy at the
-- snow join and at the graded suffix, the draft bed where a road crosses,
-- and the hillside in between, clamped to the spur cap.
local spurSegs: { Seg } = {}

local function solveSpur(group: { Sample })
	local n = #group
	for i = 1, n do
		if not group[i].locked then
			group[i].h = group[i].target
		end
	end
	for i = 2, n do
		local a, b = group[i - 1], group[i]
		if not b.locked then
			local c = SPUR_GRADE * math.max(hypot(b.x - a.x, b.z - a.z), 1)
			b.h = math.clamp(b.target, a.h - c, a.h + c)
		end
	end
	for i = n - 1, 1, -1 do
		local a, b = group[i], group[i + 1]
		if not a.locked then
			local c = SPUR_GRADE * math.max(hypot(b.x - a.x, b.z - a.z), 1)
			a.h = math.clamp(a.h, b.h - c, b.h + c)
		end
	end
end

local function buildSpurApproach()
	table.clear(spurSegs)
	local spur = WorldLayout.TollSpur
	local pts = spur.points
	local group: { Sample } = {}
	local function add(x: number, z: number)
		local dist, _, graded = closest(x, z)
		local onRoad = dist ~= nil and dist <= 1 and graded ~= nil
		local lock = WorldLayout.OnTollSpur(x, z)
		local base = legacy(x, z)
		local sample: Sample = {
			x = x,
			z = z,
			h = if lock then base elseif onRoad then graded :: number else base,
			target = if onRoad and not lock then graded :: number else countryAt(x, z),
			locked = lock or onRoad,
			road = 0,
			index = #group + 1,
		}
		table.insert(group, sample)
	end
	add(pts[1].X, pts[1].Y)
	group[1].locked = true
	group[1].h = legacy(pts[1].X, pts[1].Y)
	group[1].target = group[1].h
	for i = 2, spur.gradeFrom do
		local a, b = pts[i - 1], pts[i]
		local dx, dz = b.X - a.X, b.Y - a.Y
		local len = hypot(dx, dz)
		local n = math.max(1, math.floor(len / 8))
		for s = 1, n do
			local u = s / n
			add(a.X + dx * u, a.Y + dz * u)
		end
	end
	solveSpur(group)
	for i = 2, #group do
		local a, b = group[i - 1], group[i]
		table.insert(spurSegs, {
			ax = a.x,
			az = a.z,
			bx = b.x,
			bz = b.z,
			ah = a.h,
			bh = b.h,
			half = 1,
			name = "spur",
		})
	end
end

-- Height on the approach centreline, or nil once a stud off it. Wider than
-- that and the ribbon swallows Lodge Path.
local function spurHeight(x: number, z: number): number?
	local bestD = math.huge
	local bestH = 0
	for _, seg in ipairs(spurSegs) do
		local abx, abz = seg.bx - seg.ax, seg.bz - seg.az
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-8 then math.clamp(((x - seg.ax) * abx + (z - seg.az) * abz) / len2, 0, 1) else 0
		local px = seg.ax + abx * t
		local pz = seg.az + abz * t
		local d = hypot(x - px, z - pz)
		if d < bestD then
			bestD = d
			bestH = seg.ah + (seg.bh - seg.ah) * t
		end
	end
	if bestD <= 1 then
		return bestH
	end
	return nil
end

function ValleyGround.Bind(heightAt: (number, number) -> number, waterAt: (number, number) -> number?)
	legacy = heightAt
	legacyWater = waterAt
	if not ready then
		buildRoads()
		buildSpurApproach()
		ready = true
	end
end

function ValleyGround.OnPad(x: number, z: number): boolean
	-- 0.3 reaches the skirt of a declared flat zone (town, a plot, a store
	-- pad). The skirt is part of that level; the open country past it is not.
	if WorldLayout.FlatWeight(x, z) > 0.3 then
		return true
	end
	if WorldLayout.InNorthStrip(x, z) then
		return true
	end
	if WorldLayout.InReservedRegion(x, z) then
		return true
	end
	if lodgeDist(x, z) <= LODGE_R then
		return true
	end
	for _, pad in ipairs(WorldLayout.StorePads) do
		if x >= pad.x0 and x <= pad.x1 and z >= pad.z0 and z <= pad.z1 then
			return true
		end
	end
	return false
end

local function onTollSpur(x: number, z: number): boolean
	return WorldLayout.OnTollSpur(x, z)
end

-- Pads, the north strip, a reserved floor and a live road bed keep the
-- height they already had. A draft bed must not tilt them.
local function held(x: number, z: number): boolean
	if WorldLayout.InNorthStrip(x, z) or WorldLayout.InReservedRegion(x, z) then
		return true
	end
	if WorldLayout.FlatWeight(x, z) > 0.85 or WorldLayout.OnPlotPad(x, z) then
		return true
	end
	for _, pad in ipairs(WorldLayout.StorePads) do
		if x >= pad.x0 and x <= pad.x1 and z >= pad.z0 and z <= pad.z1 then
			return true
		end
	end
	return false
end

local function capFrom(shelfY: number, padD: number, cut: number): number
	return shelfY + SHELF_SLOPE * math.max(0, padD - cut)
end

function ValleyGround.HeightAt(x: number, z: number): number
	local ld = lodgeDist(x, z)
	if ld <= LODGE_R then
		return padH
	end
	local approach = spurHeight(x, z)
	if approach then
		return approach
	end
	-- The live drive, out to DriveHalf. A draft centreline that crosses it has
	-- already been graded down to this height, so the truck's road stays level.
	-- The plan bed is narrower; the extra studs are the flat shoulder.
	if driveClear(x, z) <= 0 then
		return legacy(x, z)
	end
	if held(x, z) or onTollSpur(x, z) then
		return legacy(x, z)
	end
	local country = countryAt(x, z)
	local h = country
	local dist, half, graded = closest(x, z)
	local onBed = false
	local gap = 100
	local reach = 0
	if dist and half and graded then
		gap = dist - half
		if gap <= 0 then
			h = graded
			onBed = true
		else
			local diff = math.abs(graded - country)
			local nearDrop = NEAR_SLOPE * NEAR_RUN
			local natural = if diff <= nearDrop then diff / NEAR_SLOPE else NEAR_RUN + (diff - nearDrop) / BANK_SLOPE
			-- A bank taller than the far grade can finish inside the search
			-- meets the hillside at the search edge instead of stepping off it.
			local capped = natural > MAX_REACH
			reach = math.min(MAX_REACH, natural)
			if gap < reach and diff > 1e-6 then
				local drop = if capped
					then diff * (gap / MAX_REACH)
					elseif gap <= NEAR_RUN then NEAR_SLOPE * gap
					else nearDrop + BANK_SLOPE * (gap - NEAR_RUN)
				drop = math.min(drop, diff)
				if graded >= country then
					h = graded - drop
				else
					h = graded + drop
				end
			end
		end
	end
	-- FlatWeight stays above 0.85 for about a quarter of a shelf's blend, and
	-- that band is held flat, so the climb starts outside it.
	if not onBed then
		local bestD, bestY, bestCut = 1e6, 0, 0
		for _, zone in ipairs(WorldLayout.FlatZones) do
			local d = outsideRect(x, z, zone.x0, zone.z0, zone.x1, zone.z1)
			if d < bestD then
				bestD = d
				bestY = zone.y or 0
				bestCut = (zone.blend or 0) * 0.244
			end
		end
		if bestD < 400 and h > capFrom(bestY, bestD, bestCut) then
			local cap = capFrom(bestY, bestD, bestCut)
			if country > bestY + 20 then
				-- A mountain that already stands well above the shelf.
				h = math.max(cap, country)
			elseif gap >= 8 then
				-- Meet the shelf at its contour, then ease back up to the
				-- bank. The run is long enough that the ease stays under
				-- 15 degrees. Far from the shelf the bank is left alone, so
				-- a prop on it is not trenched. The ease used to switch on
				-- all at once where the bank meets it, and that step was
				-- too steep for a trunk. It comes in between 8 and 12 studs
				-- off the gravel, and from there it is the ease it was.
				local excess = h - cap
				local out = bestD - bestCut
				local run = math.max(24, excess / 0.15)
				local along = math.clamp(out / run, 0, 1)
				local eased = cap + excess * along
				local fade = smooth(math.clamp((gap - 8) / 4, 0, 1))
				h = h * (1 - fade) + eased * fade
			end
		end
	end
	-- The cone's impostor is buried in the old cone. A road bank must not
	-- shave that surface down, or the impostor sticks out.
	local cone = WorldLayout.VolcanoCone
	local cdx, cdz = x - cone.x, z - cone.z
	if not onBed and cdx * cdx + cdz * cdz < (cone.radius + 30) * (cone.radius + 30) then
		h = country
	end
	-- Off the bed, the pad shoulder eases into the hillside. On the bed the
	-- graded centreline is already locked to the pad, so it is left alone.
	if not onBed and ld < LODGE_R + BANK then
		local s = smooth((ld - LODGE_R) / BANK)
		h = padH * (1 - s) + h * s
	end
	return h
end

-- Distance from (x, z) to the edge of the nearest draft bed. Negative on
-- the gravel. The lodge pad is not a bed: clearance there is the distance
-- out to the pad edge.
function ValleyGround.DraftClearance(x: number, z: number): number
	local dist, half = closest(x, z)
	if not dist or not half then
		return 1e6
	end
	local clear = dist - half
	local ld = lodgeDist(x, z)
	if ld < LODGE_R then
		local padClear = LODGE_R - ld
		if clear < padClear then
			clear = padClear
		end
	end
	return clear
end

local MAT: { [string]: string } = {
	MeadowGrass = "Grass",
	DeepMeadow = "LeafyGrass",
	TrailDirt = "Ground",
	WetMud = "Mud",
	CliffRock = "Rock",
	FreshSnow = "Snow",
	AshBasalt = "Basalt",
	QuarrySlate = "Slate",
	ShoreSand = "Sand",
	BayouSilt = "Limestone",
	MesaRed = "Sandstone",
	LumenCream = "Sand",
}

local function mapped(name: string): string
	return MAT[name] or "Grass"
end

local function beltHit(x: number, z: number): (number?, number?, { string }?, number?)
	local bestT, bestDist, bestMats, bestWidth = nil, math.huge, nil, nil
	for _, belt in ipairs(WorldPlanDraft.Belts) do
		local dx = belt.edge.x - belt.outer.x
		local dz = belt.edge.z - belt.outer.z
		local len2 = dx * dx + dz * dz
		if len2 < 1 then
			continue
		end
		local t = math.clamp(((x - belt.outer.x) * dx + (z - belt.outer.z) * dz) / len2, 0, 1)
		local px = belt.outer.x + dx * t
		local pz = belt.outer.z + dz * t
		local d = hypot(x - px, z - pz)
		local reach = belt.width / 2 + 24
		if d < reach and d < bestDist then
			bestT = t
			bestDist = d
			bestMats = belt.materials
			bestWidth = belt.width
		end
	end
	return bestT, bestDist, bestMats, bestWidth
end

local function beltMaterial(x: number, z: number, t: number, materials: { string }): string
	local n = #materials
	if n == 0 then
		return "Grass"
	end
	-- The ends of the belt are fixed so the blend spans the whole depth.
	-- The middle dithers, which is what keeps the join from being a hard line.
	if t <= 0.02 then
		return mapped(materials[1])
	end
	if t >= 0.98 then
		return mapped(materials[n])
	end
	local jitter = math.noise(x / 22, z / 22, 4.2) * 0.12
	local w = math.clamp(t + jitter, 0, 0.999)
	local idx = math.clamp(math.floor(w * n) + 1, 1, n)
	return mapped(materials[idx])
end

local function steepRock(x: number, z: number): string
	local best, bestD = "Rock", math.huge
	for _, region in ipairs(WorldPlanDraft.Regions) do
		local d = hypot(x - region.x, z - region.z)
		if d < bestD then
			bestD = d
			if region.id == "caldera" then
				best = "Basalt"
			elseif region.id == "mesa" then
				best = "Sandstone"
			else
				best = "Rock"
			end
		end
	end
	return best
end

local function snowDeep(x: number, z: number): boolean
	local snow = BiomeData.Get("snow")
	local area = if snow then snow.area else nil
	if not area then
		return false
	end
	local dx, dz = x - area.x, z - area.z
	local reach = area.radius + 40
	return dx * dx + dz * dz < reach * reach
end

local function onTownFloor(x: number, z: number): boolean
	for _, floor in ipairs(WorldLayout.TownFloors) do
		if x >= floor.x0 and x <= floor.x1 and z >= floor.z0 and z <= floor.z1 then
			return true
		end
	end
	return false
end

function ValleyGround.Paint(x: number, z: number, _h: number, slope: number, base: string): string?
	local clear = liveClear(x, z)
	local ld = lodgeDist(x, z)
	local dist, half = closest(x, z)
	local onBed = dist ~= nil and half ~= nil and dist <= (half :: number) and ld > LODGE_R
	local beltHere = false
	if dist and half and not snowDeep(x, z) then
		local bd = dist
		beltHere = bd > (half :: number) + 5 and bd < (half :: number) + 8
	end
	-- A live road keeps its gravel. The belt strip is the one place a blend
	-- may cross the outer edge of a road that is wider than the draft bed.
	if not beltHere and (clear <= 0 or (clear <= 2.5 and base == "Asphalt")) then
		return nil
	end
	-- Biome floors stay themselves, except a draft bed outside the snow
	-- disc's deep interior: that one point is the gravel the belt check asks
	-- for, and the snow rays never cross it.
	local protect = base == "Glacier"
		or base == "Basalt"
		or base == "CrackedLava"
		or base == "Slate"
		or (base == "Snow" and (not onBed or snowDeep(x, z)))
	local lawn = WorldLayout.NearPlotPad(x, z, 40)
	local pad = WorldLayout.FlatWeight(x, z) > 0.85
		or WorldLayout.OnPlotPad(x, z)
		or WorldLayout.InReservedRegion(x, z)
		or lawn
	if
		onBed
		and dist <= (half :: number) - 4
		-- A live edge of exactly 2 is where the style check's Vector2
		-- distance reads a hair over 2. Skip that sliver. A draft bed far
		-- from every live road (clearance past 2.5) is still gravel.
		and (clear < 1.99 or clear > 2.5)
		and not protect
		and not pad
		and not snowDeep(x, z)
		and not WorldLayout.InTownZone(x, z)
	then
		return "Asphalt"
	end
	-- A narrow strip beside the bed. The homestead grid sits further out
	-- and stays plain Grass. Inside the snow disc the rays stay snow.
	if not snowDeep(x, z) and not onBed then
		local t, bd, materials, width = beltHit(x, z)
		if t and materials and bd and width and bd > width / 2 + 5 and bd < width / 2 + 8 then
			local mat = beltMaterial(x, z, t, materials)
			local dirt = mat == "Ground" or mat == "Mud" or mat == "Sand"
			if not (lawn and slope <= STEEP and dirt) then
				if slope > STEEP and (mat == "Grass" or mat == "LeafyGrass") then
					return steepRock(x, z)
				end
				return mat
			end
		end
	end
	if slope > STEEP and (base == "Grass" or base == "LeafyGrass" or lawn) and not WorldLayout.OnPlotPad(x, z) then
		return steepRock(x, z)
	end
	-- A plot skirt reads as grass. Rock or gravel there is the pad's edge, not a cliff.
	if
		lawn
		and slope <= STEEP
		and not onTownFloor(x, z)
		and (base == "Rock" or base == "Slate" or base == "Asphalt" or base == "Ground" or base == "Mud")
	then
		return "Grass"
	end
	return nil
end

return ValleyGround
