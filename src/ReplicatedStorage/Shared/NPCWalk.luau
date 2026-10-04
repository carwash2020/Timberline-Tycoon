--!strict
-- NPCWalk: smooth placement for anchored town walkers. The server only
-- publishes the route; each client samples NPCData.RouteState from the
-- shared clock and eases an anchored root toward that pose (NPCController).
-- Humanoid:MoveTo does not drive these rigs.
--
-- Ground is sampled at bind: down at each waypoint and every
-- SampleSpacing studs along a segment. FeetAt interpolates those heights.
-- A miss falls back to the caller's terrain height (TerrainGen.HeightAt)
-- and is remembered. Retry re-probes those points a few at a time, so a
-- porch that streams in later can replace the fallback. FeetAt and Follow
-- never call the probe. The root sits rootHeight above the feet.
--
-- Follow snaps only when there is no visual yet (the first frame after
-- the rig streams in) or the horizontal error is past SnapError and the
-- walker is off screen. On screen a clock jump eases out over EaseTime.
-- A pose already within one frame of the clock is copied, so a steady
-- walk moves at most speed*dt plus Slack and two clients agree.

local NPCWalk = {}

NPCWalk.SampleSpacing = 4
NPCWalk.EaseTime = 0.5
NPCWalk.SnapError = 20
NPCWalk.Slack = 0.05
NPCWalk.LegHz = 30
NPCWalk.Stride = 4.2
-- StreamingMinRadius. A walker this close can retry ground the ray missed
-- because the porch or the road had not streamed in yet.
NPCWalk.RetryRadius = 128
NPCWalk.RetryGap = 1 -- seconds between passes
NPCWalk.RetryRays = 4 -- a few rays per pass, never a ray every frame
NPCWalk.RetryBudget = 8 -- failed retries per point, then HeightAt stands

-- Same shape as NPCData.Waypoint. The extra fields are unused here;
-- they stay so a route table type-checks without a cast.
export type Waypoint = { x: number, z: number, pause: number?, face: number? }

export type Pose = {
	x: number,
	y: number,
	z: number,
	yaw: number,
	moving: boolean,
	walked: number,
}

export type GroundSample = { along: number, feet: number, x: number, z: number }

export type LegProfile = { length: number, samples: { GroundSample } }

-- A sample that used the terrain fallback. `tries` counts retries.
export type Miss = { x: number, z: number, tries: number }

export type Profile = { legs: { LegProfile }, misses: { Miss } }

export type RoutePoint = { leg: number, along: number, x: number, z: number }

local function copyPose(pose: Pose): Pose
	return {
		x = pose.x,
		y = pose.y,
		z = pose.z,
		yaw = pose.yaw,
		moving = pose.moving,
		walked = pose.walked,
	}
end

local function wrapAngle(d: number): number
	return (d + math.pi) % (math.pi * 2) - math.pi
end

-- True when `inst` is part of `map` and not an NPC, a Wood pile, or a vehicle.
-- Ancestors named Wood, Townsfolk, or Murph, and anything tagged NPC or
-- Truck, are skipped so a walker stands on the street instead of a neighbour.
function NPCWalk.MapGround(inst: Instance, map: Instance?): boolean
	if map == nil then
		return false
	end
	local cur: Instance? = inst
	while cur do
		if cur == map then
			return true
		end
		if cur.Name == "Wood" or cur.Name == "Townsfolk" or cur.Name == "Murph" then
			return false
		end
		if cur:HasTag("NPC") or cur:HasTag("Truck") then
			return false
		end
		cur = cur.Parent
	end
	return false
end

-- Waypoints plus a point every SampleSpacing studs along each segment.
-- The segment's end is included (it is also the next waypoint).
function NPCWalk.RoutePoints(route: { Waypoint }): { RoutePoint }
	local points: { RoutePoint } = {}
	local n = #route
	if n == 0 then
		return points
	end
	for i = 1, n do
		local w = route[i]
		local nxt = route[i % n + 1]
		local dx, dz = nxt.x - w.x, nxt.z - w.z
		local len = math.sqrt(dx * dx + dz * dz)
		table.insert(points, { leg = i, along = 0, x = w.x, z = w.z })
		if len > 1e-6 then
			local along = NPCWalk.SampleSpacing
			while along < len - 1e-4 do
				local f = along / len
				table.insert(points, {
					leg = i,
					along = along,
					x = w.x + dx * f,
					z = w.z + dz * f,
				})
				along += NPCWalk.SampleSpacing
			end
			table.insert(points, { leg = i, along = len, x = nxt.x, z = nxt.z })
		end
	end
	return points
end

local function pointKey(x: number, z: number): string
	return string.format("%.4f,%.4f", x, z)
end

-- One height per sample point. `probe` returns feet Y, or nil on a miss
-- (then `fallback`, the terrain height). A miss is recorded so Retry can
-- ask again. Repeated points share one call.
function NPCWalk.Sample(
	route: { Waypoint },
	probe: (number, number) -> number?,
	fallback: (number, number) -> number
): Profile
	local heights: { [string]: number } = {}
	local seenMiss: { [string]: boolean } = {}
	local misses: { Miss } = {}
	local function heightAt(x: number, z: number): number
		local key = pointKey(x, z)
		local known = heights[key]
		if known ~= nil then
			return known
		end
		local hit = probe(x, z)
		local y = if hit ~= nil then hit else fallback(x, z)
		heights[key] = y
		if hit == nil and not seenMiss[key] then
			seenMiss[key] = true
			table.insert(misses, { x = x, z = z, tries = 0 })
		end
		return y
	end
	local legs: { LegProfile } = {}
	local n = #route
	for i = 1, n do
		local samples: { GroundSample } = {}
		local length = 0
		for _, point in ipairs(NPCWalk.RoutePoints(route)) do
			if point.leg == i then
				local feet = heightAt(point.x, point.z)
				table.insert(samples, { along = point.along, feet = feet, x = point.x, z = point.z })
				length = math.max(length, point.along)
			end
		end
		table.insert(legs, { length = length, samples = samples })
	end
	return { legs = legs, misses = misses }
end

local function writeFeet(profile: Profile, x: number, z: number, feet: number)
	local key = pointKey(x, z)
	for _, leg in ipairs(profile.legs) do
		for _, sample in ipairs(leg.samples) do
			if pointKey(sample.x, sample.z) == key then
				sample.feet = feet
			end
		end
	end
end

-- Re-probe recorded misses, at most `rays` of them (default RetryRays).
-- A hit overwrites every sample on that point and drops the miss. A nil
-- keeps the fallback height. After RetryBudget nils the point is dropped
-- and not asked again. Returns how many rays this pass cast.
function NPCWalk.Retry(profile: Profile, probe: (number, number) -> number?, rays: number?): number
	local batch = if rays ~= nil then math.max(0, rays) else NPCWalk.RetryRays
	local made = 0
	local later: { Miss } = {}
	local again: { Miss } = {}
	for _, miss in ipairs(profile.misses) do
		if miss.tries < NPCWalk.RetryBudget then
			if made >= batch then
				table.insert(later, miss)
			else
				miss.tries += 1
				made += 1
				local hit = probe(miss.x, miss.z)
				if hit ~= nil then
					writeFeet(profile, miss.x, miss.z, hit)
				elseif miss.tries < NPCWalk.RetryBudget then
					table.insert(again, miss)
				end
			end
		end
	end
	for _, miss in ipairs(again) do
		table.insert(later, miss)
	end
	profile.misses = later
	return made
end

local function feetAlong(leg: LegProfile, along: number): number
	local samples = leg.samples
	local count = #samples
	if count == 0 then
		return 0
	end
	if along <= samples[1].along then
		return samples[1].feet
	end
	for i = 2, count do
		local b = samples[i]
		local a = samples[i - 1]
		if along <= b.along then
			local span = b.along - a.along
			local t = if span > 1e-6 then (along - a.along) / span else 0
			return a.feet + (b.feet - a.feet) * t
		end
	end
	return samples[count].feet
end

-- Feet Y at (x, z), from the samples. No probe.
function NPCWalk.FeetAt(profile: Profile, route: { Waypoint }, x: number, z: number): number
	local n = #route
	if n == 0 or #profile.legs == 0 then
		return 0
	end
	local bestLeg, bestAlong, bestD = 1, 0, math.huge
	for i = 1, n do
		local leg = profile.legs[i]
		if leg then
			local w = route[i]
			local nxt = route[i % n + 1]
			local dx, dz = nxt.x - w.x, nxt.z - w.z
			local len2 = dx * dx + dz * dz
			local t = 0
			if len2 > 1e-8 then
				t = math.clamp(((x - w.x) * dx + (z - w.z) * dz) / len2, 0, 1)
			end
			local px, pz = w.x + dx * t, w.z + dz * t
			local ddx, ddz = x - px, z - pz
			local d = ddx * ddx + ddz * ddz
			if d < bestD then
				bestD = d
				bestLeg = i
				bestAlong = t * math.sqrt(len2)
			end
		end
	end
	local leg = profile.legs[bestLeg]
	if not leg then
		return 0
	end
	return feetAlong(leg, bestAlong)
end

-- Root centre above the feet (or above HeightAt, when the ray missed).
function NPCWalk.RootY(feet: number, rootHeight: number): number
	return feet + rootHeight
end

-- Walk-cycle phase from distance, so the feet match speed at any frame rate.
function NPCWalk.Phase(walked: number, scale: number): number
	local stride = NPCWalk.Stride * math.max(scale, 1e-3)
	return walked / stride * math.pi * 2
end

-- True once `elapsed` seconds have passed since the legs were last posed.
-- 30 Hz is the floor while a walker is moving; the controller poses every
-- rendered frame, which is at least this on a phone.
function NPCWalk.LegDue(elapsed: number): boolean
	return elapsed >= 1 / NPCWalk.LegHz - 1e-4
end

local function easeAlpha(dt: number): number
	local tau = NPCWalk.EaseTime / 3
	if dt <= 0 or tau <= 1e-6 then
		return if dt <= 0 then 0 else 1
	end
	return 1 - math.exp(-dt / tau)
end

-- `visual` nil snaps (stream-in), even on screen. Returns the new visual
-- and whether this frame snapped.
function NPCWalk.Follow(visual: Pose?, target: Pose, dt: number, speed: number, onScreen: boolean): (Pose, boolean)
	if visual == nil then
		return copyPose(target), true
	end
	dt = math.max(dt, 0)
	speed = math.max(speed, 0)
	local dx, dz = target.x - visual.x, target.z - visual.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > NPCWalk.SnapError and not onScreen then
		return copyPose(target), true
	end
	local yErr = target.y - visual.y
	local budget = speed * dt + NPCWalk.Slack
	if dist <= budget and math.abs(yErr) <= 0.1 then
		return copyPose(target), false
	end
	local alpha = easeAlpha(dt)
	local excess = math.max(0, dist - speed * dt)
	local step = math.min(dist, speed * dt + excess * alpha)
	local x, z = visual.x, visual.z
	if dist > 1e-8 then
		x += dx / dist * step
		z += dz / dist * step
	end
	local y = if math.abs(yErr) <= 0.1 then target.y else visual.y + yErr * alpha
	local yawErr = wrapAngle(target.yaw - visual.yaw)
	local yaw = if dist <= budget then target.yaw else visual.yaw + yawErr * alpha
	local walked = if dist <= budget then target.walked else visual.walked + step
	return {
		x = x,
		y = y,
		z = z,
		yaw = yaw,
		moving = target.moving,
		walked = walked,
	}, false
end

return NPCWalk
