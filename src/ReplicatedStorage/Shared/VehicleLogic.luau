--!strict
-- VehicleLogic: the rules behind trucks that don't need Roblox running, so
-- they can be tested (tests/VehicleLogic.spec.luau):
--   * the anti-exploit speed check (VehicleService), tolerant of short
--     network stalls: a move is judged against the time since the last
--     ACCEPTED position, and a truck that hasn't moved keeps that clock
--     running (for at most MaxJudgeSeconds);
--   * which way is up under a truck, from four corner ground rays, never
--     tilted past a limit (VehicleController, and parking on exit);
--   * the truck's target orientation (Heading), NaN-proof, and where a
--     tipped or airborne truck is set down (on the ground, nothing sunk in);
--   * overflow parking spots that stay put across rebuilds;
--   * a saved truck bed, cleaned and copied (profile.truckBed), where the
--     truck was (profile.truckAt), whether that was in town (a load only
--     rides along on a rebuild or a rejoin from there), and how a load left
--     behind is laid on the ground;
--   * wheel spin, steering, brake lights and dust (VehicleFX).
-- Uses only datatypes (no services). CFrames are built with fromMatrix,
-- never lookAt, so Roblox and the Lune tests agree.

local VehicleLogic = {}

---------------------------------------------------------------------------
-- Speed check
---------------------------------------------------------------------------

VehicleLogic.SpeedSlack = 1.5 -- a truck may cover this many times its top speed (bumps, physics)
VehicleLogic.SlackStuds = 8 -- plus this much
-- Longer gaps count as this long, so a truck that sat still (parked with
-- its driver in it, or a stalled connection) never banks more than about
-- 86 studs of allowance at 26 studs/s. A stall longer than this puts the
-- truck back where it was last accepted: an honest driver loses a couple
-- of seconds of driving, an exploiter can't hop across the map.
VehicleLogic.MaxJudgeSeconds = 2
VehicleLogic.StillStuds = 0.05 -- closer than this counts as not moved at all
VehicleLogic.ClimbShare = 0.75 -- the steepest climb, as a share of top speed
VehicleLogic.Gravity = 196.2 -- studs/s², Roblox's default

export type MoveVerdict = "still" | "ok" | "tooFar"

-- Judges a move from `from` (the last accepted position, accepted
-- `elapsed` seconds ago) to `to`. "still": it hasn't moved (keep the old
-- accepted position and its time, so a stalled connection doesn't shrink
-- the allowance); "ok": accept `to`; "tooFar": nothing drives that far
-- that fast (put it back).
function VehicleLogic.JudgeMove(from: Vector3, to: Vector3, elapsed: number, topSpeed: number): MoveVerdict
	local dx, dz = to.X - from.X, to.Z - from.Z
	local flat = math.sqrt(dx * dx + dz * dz)
	local rise = to.Y - from.Y
	if flat ~= flat or rise ~= rise then
		return "tooFar" -- NaN: a corrupt position
	end
	if flat <= VehicleLogic.StillStuds and math.abs(rise) <= VehicleLogic.StillStuds then
		return "still"
	end
	local t = math.clamp(elapsed, 0, VehicleLogic.MaxJudgeSeconds)
	local slack, k = VehicleLogic.SlackStuds, VehicleLogic.SpeedSlack
	if flat > topSpeed * t * k + slack then
		return "tooFar"
	end
	if rise > topSpeed * VehicleLogic.ClimbShare * t * k + slack then
		return "tooFar" -- up faster than any hill
	end
	if -rise > (topSpeed * t + 0.5 * VehicleLogic.Gravity * t * t) * k + slack then
		return "tooFar" -- down faster than falling
	end
	return "ok"
end

---------------------------------------------------------------------------
-- Ground and orientation
---------------------------------------------------------------------------

local function finite(v: Vector3): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < math.huge
		and math.abs(v.Y) < math.huge
		and math.abs(v.Z) < math.huge
end
VehicleLogic.Finite = finite

-- Where to cast the four ground rays, in truck-local studs (front is -Z):
-- front-left, front-right, rear-left, rear-right, just inside the corners.
function VehicleLogic.CornerOffsets(width: number, length: number): { Vector3 }
	local x, z = math.max(0.5, width / 2 - 0.3), math.max(0.5, length / 2 - 0.5)
	return {
		Vector3.new(-x, 0, -z),
		Vector3.new(x, 0, -z),
		Vector3.new(-x, 0, z),
		Vector3.new(x, 0, z),
	}
end

-- `up`, tilted at most `maxTilt` radians from straight up (and pointing
-- up, and finite: anything broken becomes straight up).
function VehicleLogic.ClampTilt(up: Vector3, maxTilt: number): Vector3
	if not finite(up) or up.Magnitude < 1e-6 then
		return Vector3.yAxis
	end
	local u = up.Unit
	if u.Y < 0 then
		u = -u
	end
	if u.Y >= math.cos(maxTilt) then
		return u
	end
	local flat = Vector3.new(u.X, 0, u.Z)
	if flat.Magnitude < 1e-6 then
		return Vector3.yAxis
	end
	return Vector3.yAxis * math.cos(maxTilt) + flat.Unit * math.sin(maxTilt)
end

-- The ground's "up" under a truck from its four corner rays, in
-- CornerOffsets order (nil where a ray missed): the plane through the four
-- hit points when all of them hit, else the average normal of the hits,
-- else straight up. Clamped to `maxTilt`.
function VehicleLogic.GroundUp(points: { Vector3? }, normals: { Vector3? }, maxTilt: number): Vector3
	local fl, fr, rl, rr = points[1], points[2], points[3], points[4]
	if fl and fr and rl and rr then
		local forward = (fl + fr) / 2 - (rl + rr) / 2
		local right = (fr + rr) / 2 - (fl + rl) / 2
		local up = right:Cross(forward)
		if finite(up) and up.Magnitude > 1e-4 then
			return VehicleLogic.ClampTilt(up, maxTilt)
		end
	end
	local sum, n = Vector3.zero, 0
	for i = 1, 4 do
		local normal = normals[i]
		if normal and finite(normal) then
			sum += normal
			n += 1
		end
	end
	if n == 0 then
		return Vector3.yAxis
	end
	return VehicleLogic.ClampTilt(sum / n, maxTilt)
end

-- The flat direction a CFrame faces (its LookVector without the slope),
-- or -Z when it points straight up or down.
function VehicleLogic.FlatFacing(look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	if not finite(flat) or flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- An orientation facing `facing` (any direction; its slope is ignored),
-- tilted so its up is `up` (never more than 75 degrees: a truck is never
-- asked to lie on its side). Never NaN: when `facing` runs along `up` it
-- falls back to level.
function VehicleLogic.HeadingCFrame(facing: Vector3, up: Vector3): CFrame
	local u = VehicleLogic.ClampTilt(up, math.rad(75))
	local flat = VehicleLogic.FlatFacing(facing)
	local look = flat - u * flat:Dot(u)
	if not finite(look) or look.Magnitude < 1e-3 then
		u, look = Vector3.yAxis, flat
	end
	look = look.Unit
	local right = look:Cross(u).Unit
	return CFrame.fromMatrix(Vector3.zero, right, u, -look)
end

-- Where a truck parks: its chassis `clearance` above `ground` (a point)
-- along the ground's up (normal, clamped to `maxTilt`), facing `facing`.
function VehicleLogic.ParkedCFrame(
	ground: Vector3,
	normal: Vector3,
	facing: Vector3,
	clearance: number,
	maxTilt: number
): CFrame
	local up = VehicleLogic.ClampTilt(normal, maxTilt)
	return VehicleLogic.HeadingCFrame(facing, up) + (ground + up * clearance)
end

-- Ground-ray points under a whole rig, truck-local (front is -Z): the four
-- corners of the box `width` wide from z = `front` to z = `rear` (the
-- trailer's back when one is hitched), just inside, in CornerOffsets
-- order; then both sides halfway along.
function VehicleLogic.RigCorners(width: number, front: number, rear: number): { Vector3 }
	local mid = (front + rear) / 2
	local out: { Vector3 } = {}
	for _, c in ipairs(VehicleLogic.CornerOffsets(width, rear - front)) do
		table.insert(out, c + Vector3.new(0, 0, mid))
	end
	local x = out[2].X
	table.insert(out, Vector3.new(-x, 0, mid))
	table.insert(out, Vector3.new(x, 0, mid))
	return out
end

-- Where a tipped or airborne truck is set down: facing `facing`, tilted to
-- `up` (at most `maxTilt`), its pivot over `at` (X and Z) with the chassis
-- `clearance` above the ground, then lifted until no point of `corners`
-- (truck-local, chassis level, as RigCorners) is below the ground hit
-- under it (`hits`, in the same order; nil where a ray missed). So it
-- rests on the highest ground under it and nothing sinks into a slope.
-- Nil when no ray hit anything.
function VehicleLogic.RestingCFrame(
	at: Vector3,
	up: Vector3,
	facing: Vector3,
	clearance: number,
	maxTilt: number,
	corners: { Vector3 },
	hits: { Vector3? }
): CFrame?
	local lowest = math.huge
	for i = 1, #corners do
		local hit = hits[i]
		if hit and finite(hit) then
			lowest = math.min(lowest, hit.Y)
		end
	end
	if lowest == math.huge then
		return nil
	end
	local u = VehicleLogic.ClampTilt(up, maxTilt)
	local cf = VehicleLogic.HeadingCFrame(facing, u) + (Vector3.new(at.X, lowest, at.Z) + u * clearance)
	local lift = 0
	for i, c in ipairs(corners) do
		local hit = hits[i]
		if hit and finite(hit) then
			local wheel = cf * (c - Vector3.new(0, clearance, 0)) -- the corner at ground level
			lift = math.max(lift, hit.Y - wheel.Y)
		end
	end
	return cf + Vector3.new(0, lift, 0)
end

---------------------------------------------------------------------------
-- Parking bays (phase 12)
---------------------------------------------------------------------------

-- A parking bay as VehicleService sees it: its slot's Index and its
-- painted size (the ParkingSlot part's Size.Z and Size.X, studs).
export type BayInfo = { index: number, length: number, width: number }

-- The furthest a rig's nose may stick out past a bay's head when no free
-- bay is long enough: it parks with its tail at the bay's tail, its nose
-- over the bay's pull-out (WorldPlan.ParkingPullOut, kept clear of
-- everything, is longer).
VehicleLogic.MaxOverhang = 25

-- Whether a rig `length` long and `width` wide (TruckLayout.RigSize) fits
-- inside a bay's paint.
function VehicleLogic.BayFits(bay: BayInfo, length: number, width: number): boolean
	return length <= bay.length and width <= bay.width
end

-- Whether a rig may park in a bay at all: it fits, or it's no wider and
-- at most MaxOverhang longer (its nose out past the head).
function VehicleLogic.BayTakes(bay: BayInfo, length: number, width: number): boolean
	return width <= bay.width and length <= bay.length + VehicleLogic.MaxOverhang
end

-- The bays a rig `length` x `width` should park in, best first, as slot
-- Indexes, from `bays` (the free ones, and `current`, the Index of the
-- bay its player holds now, which counts as free for them): first every
-- bay it fits, the smallest first (shortest, then narrowest), `current`
-- ahead of another of the same size (so a rebuild keeps a bay that's
-- still the best fit), then the lowest Index (nearest the spawn); then
-- the bays it only overhangs (BayTakes), the longest first. A bay it
-- can't take isn't listed; none at all means an overflow spot.
function VehicleLogic.BayChoices(bays: { BayInfo }, length: number, width: number, current: number?): { number }
	local fits: { BayInfo } = {}
	local over: { BayInfo } = {}
	for _, bay in ipairs(bays) do
		if VehicleLogic.BayFits(bay, length, width) then
			table.insert(fits, bay)
		elseif VehicleLogic.BayTakes(bay, length, width) then
			table.insert(over, bay)
		end
	end
	local function tieBreak(a: BayInfo, b: BayInfo): boolean
		if (a.index == current) ~= (b.index == current) then
			return a.index == current
		end
		return a.index < b.index
	end
	table.sort(fits, function(a: BayInfo, b: BayInfo): boolean
		if a.length ~= b.length then
			return a.length < b.length
		elseif a.width ~= b.width then
			return a.width < b.width
		end
		return tieBreak(a, b)
	end)
	table.sort(over, function(a: BayInfo, b: BayInfo): boolean
		if a.length ~= b.length then
			return a.length > b.length
		end
		return tieBreak(a, b)
	end)
	local out: { number } = {}
	for _, list in ipairs({ fits, over }) do
		for _, bay in ipairs(list) do
			table.insert(out, bay.index)
		end
	end
	return out
end

-- How far ahead of its bay's middle (toward the head) a rig's middle
-- parks: 0 when it fits (centred), else half what it's longer, so its
-- tail meets the bay's tail and its nose sticks out past the head.
function VehicleLogic.OverhangShift(bayLength: number, rigLength: number): number
	return math.max(0, rigLength - bayLength) / 2
end

---------------------------------------------------------------------------
-- Overflow parking
---------------------------------------------------------------------------

-- The smallest spot index nobody holds (0, 1, 2, ...).
function VehicleLogic.NextFreeIndex(used: { [number]: boolean }): number
	local i = 0
	while used[i] do
		i += 1
	end
	return i
end

-- Ground position (x, 0, z) of overflow spot `index`: rows of eight west
-- of spawn, for when every ParkingSlot is taken. Side by side they're the
-- widest rig apart and a stud (OverflowApart: the Logging Rig is 12.9
-- across its fenders since phase 12; 11 before), so the trucks never
-- overlap their neighbours; a long rig can reach the next row, and
-- VehicleService skips any spot a truck is in.
VehicleLogic.OverflowApart = 14
function VehicleLogic.OverflowSpot(index: number): Vector3
	return Vector3.new(-20 - (index % 8) * VehicleLogic.OverflowApart, 0, 56 - (index // 8) * 28)
end

---------------------------------------------------------------------------
-- The bed (saved in profile.truckBed)
---------------------------------------------------------------------------

export type BedEntry = { woodId: string, value: number, figure: string? }
export type LeftLog = { woodId: string, value: number, figure: string?, x: number, y: number, z: number }

-- Plain copies of the bed's entries (nothing shared with the live bed).
function VehicleLogic.CopyBed(bed: { BedEntry }): { BedEntry }
	local out: { BedEntry } = table.create(#bed)
	for i, e in ipairs(bed) do
		out[i] = { woodId = e.woodId, value = e.value, figure = e.figure }
	end
	return out
end

-- A saved bed made safe to load: only entries with a known wood
-- (`isWood`) and a sane value, at most `capacity` of them. Returns the
-- entries and how many were dropped.
function VehicleLogic.CleanBed(saved: unknown, isWood: (string) -> boolean, capacity: number): ({ BedEntry }, number)
	local out: { BedEntry } = {}
	if type(saved) ~= "table" then
		return out, 0
	end
	local dropped = 0
	for _, raw in ipairs(saved :: { any }) do
		local ok = type(raw) == "table"
			and type(raw.woodId) == "string"
			and isWood(raw.woodId)
			and type(raw.value) == "number"
			and raw.value == raw.value
			and raw.value >= 0
			and raw.value < math.huge
		if ok and #out < capacity then
			table.insert(out, {
				woodId = raw.woodId,
				value = raw.value,
				figure = if type(raw.figure) == "string" then raw.figure else nil,
			})
		else
			dropped += 1
		end
	end
	return out, dropped
end

-- What a bed's logs are worth together (before any sale multiplier).
function VehicleLogic.BedValue(bed: { BedEntry }): number
	local total = 0
	for _, e in ipairs(bed) do
		total += e.value
	end
	return total
end

---------------------------------------------------------------------------
-- Where the truck is (profile.truckAt), and loads left behind
---------------------------------------------------------------------------

-- A load rides along when the truck is rebuilt (Truck to lot, switching
-- trucks) or on a rejoin only from town: inside the town's area (a flat
-- rectangle, InTown) or within HomeRadius of the player's own parking
-- spot. From further out it's left on the ground where the truck stood,
-- so nobody skips the haul home. 40 studs (30 before the trucks and their
-- 60-stud slots grew, M1.5): a big rig anywhere round its own spot counts.
VehicleLogic.HomeRadius = 40
VehicleLogic.MaxCoord = 100000 -- a saved spot further out than this is junk
VehicleLogic.SpillPerRow = 3 -- logs left behind lie this many end to end across the truck's line

-- Distance between two points, ignoring height.
function VehicleLogic.FlatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

export type Rect = { x0: number, x1: number, z0: number, z1: number }

-- True when `at` is in town: inside `rect` (flat), or within HomeRadius of
-- `home` (an overflow parking spot can sit just outside the rectangle).
function VehicleLogic.InTown(at: Vector3, rect: Rect, home: Vector3?): boolean
	if at.X >= rect.x0 and at.X <= rect.x1 and at.Z >= rect.z0 and at.Z <= rect.z1 then
		return true
	end
	return home ~= nil and VehicleLogic.FlatDistance(at, home) <= VehicleLogic.HomeRadius
end

-- True when `at` is within `radius` (flat) of any of `spots`.
function VehicleLogic.NearAny(at: Vector3, spots: { Vector3 }, radius: number): boolean
	for _, spot in ipairs(spots) do
		if VehicleLogic.FlatDistance(at, spot) <= radius then
			return true
		end
	end
	return false
end

-- A truck position as profile.truckAt saves it ({} = not known yet).
export type SavedSpot = { x: number?, y: number?, z: number? }

function VehicleLogic.SaveSpot(at: Vector3): SavedSpot
	return { x = at.X, y = at.Y, z = at.Z }
end

local function sane(n: unknown): boolean
	return type(n) == "number" and n == n and math.abs(n) <= VehicleLogic.MaxCoord
end

-- A saved truck position made safe to use: a finite point inside the map,
-- or nil (never saved, or junk).
function VehicleLogic.CleanSpot(saved: unknown): Vector3?
	if type(saved) ~= "table" then
		return nil
	end
	local raw = saved :: { [string]: any }
	if not (sane(raw.x) and sane(raw.y) and sane(raw.z)) then
		return nil
	end
	return Vector3.new(raw.x, raw.y, raw.z)
end

-- A saved left-behind log (profile.leftLoad), checked: a known wood id
-- (`isWood`), a sane value and spot. Nil for junk.
function VehicleLogic.CleanLeftLog(saved: unknown, isWood: (string) -> boolean): LeftLog?
	if type(saved) ~= "table" then
		return nil
	end
	local raw = saved :: { [string]: any }
	local spot = VehicleLogic.CleanSpot(raw)
	local value = raw.value
	if
		not spot
		or type(raw.woodId) ~= "string"
		or not isWood(raw.woodId)
		or type(value) ~= "number"
		or value ~= value
		or value < 0
		or value > 1e7
	then
		return nil
	end
	local figure = if type(raw.figure) == "string" then raw.figure else nil
	return { woodId = raw.woodId, value = math.floor(value), figure = figure, x = spot.X, y = spot.Y, z = spot.Z }
end

-- Where `count` logs left behind lie, in the truck's flat frame (front is
-- -Z, the pile centred where it stood): rows of SpillPerRow logs lying
-- across its line (a log's axis is its X), end to end with a gap, the
-- rows side by side down its length.
function VehicleLogic.SpillSpots(count: number, logLength: number, logDiameter: number): { Vector3 }
	local per = VehicleLogic.SpillPerRow
	local rows = math.ceil(count / per)
	local across, along = logLength + 0.5, logDiameter + 0.3
	local out: { Vector3 } = table.create(count)
	for i = 1, count do
		local row, col = (i - 1) // per, (i - 1) % per
		out[i] = Vector3.new((col - (per - 1) / 2) * across, 0, (row - (rows - 1) / 2) * along)
	end
	return out
end

---------------------------------------------------------------------------
-- Looks (VehicleFX)
---------------------------------------------------------------------------

VehicleLogic.MaxSteer = math.rad(28) -- front wheels at full lock
VehicleLogic.SteerRate = 6 -- how fast the wheels turn toward the stick (per second)

-- A wheel's new spin angle after rolling `speed` studs/s forward for `dt`
-- (forward rolls the top of the wheel toward the front, -Z: a negative
-- turn about the axle, X). Kept within one turn.
function VehicleLogic.SpinAngle(angle: number, speed: number, radius: number, dt: number): number
	return (angle - speed / math.max(radius, 0.1) * dt) % (2 * math.pi)
end

-- The front wheels' steer angle (radians about +Y; positive turns them
-- left), easing toward the seat's SteerFloat (-1 left .. 1 right).
function VehicleLogic.SteerAngle(current: number, steerFloat: number, dt: number): number
	local target = -math.clamp(steerFloat, -1, 1) * VehicleLogic.MaxSteer
	local alpha = 1 - math.exp(-VehicleLogic.SteerRate * dt)
	return current + (target - current) * alpha
end

-- Braking: the throttle pushes against the way the truck rolls.
function VehicleLogic.IsBraking(throttle: number, speed: number): boolean
	return (throttle < -0.1 and speed > 1) or (throttle > 0.1 and speed < -1)
end

VehicleLogic.DustSpeed = 9 -- studs/s before the wheels kick up dust

-- The dust a wheel throws up from each ground material (TerrainGen's
-- palette, paler), by Enum.Material name. Grass, rock, cobbles: none.
local DUST: { [string]: Color3 } = {
	Ground = Color3.fromRGB(176, 146, 108), -- dirt tracks
	Mud = Color3.fromRGB(104, 90, 116), -- the Gloam Hollow's violet floor
	Sand = Color3.fromRGB(232, 216, 172),
	Sandstone = Color3.fromRGB(214, 182, 136),
	Salt = Color3.fromRGB(236, 233, 226),
	Snow = Color3.fromRGB(246, 249, 255),
	Glacier = Color3.fromRGB(214, 234, 246),
	Basalt = Color3.fromRGB(92, 86, 84), -- volcano ash
	Slate = Color3.fromRGB(104, 96, 92),
	CrackedLava = Color3.fromRGB(120, 100, 92),
}

-- The dust colour for a ground material's name, or nil for no dust.
function VehicleLogic.DustColor(materialName: string): Color3?
	return DUST[materialName]
end

return VehicleLogic
