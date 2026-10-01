--!strict
-- VehicleLogic: the rules behind trucks that don't need Roblox running, so
-- they can be tested (tests/VehicleLogic.spec.luau):
--   * the anti-exploit speed check (VehicleService), tolerant of network
--     stalls: a move is judged against the time since the last ACCEPTED
--     position, and a truck that hasn't moved keeps that clock running;
--   * which way is up under a truck, from four corner ground rays, never
--     tilted past a limit (VehicleController, and parking on exit);
--   * the truck's target orientation (Heading), NaN-proof;
--   * overflow parking spots that stay put across rebuilds;
--   * a saved truck bed, cleaned and copied (profile.truckBed);
--   * wheel spin, steering, brake lights and dust (VehicleFX).
-- Uses only datatypes (no services). CFrames are built with fromMatrix,
-- never lookAt, so Roblox and the Lune tests agree.

local VehicleLogic = {}

---------------------------------------------------------------------------
-- Speed check
---------------------------------------------------------------------------

VehicleLogic.SpeedSlack = 1.5 -- a truck may cover this many times its top speed (bumps, physics)
VehicleLogic.SlackStuds = 8 -- plus this much
VehicleLogic.MaxJudgeSeconds = 8 -- longer gaps count as this long (a parked truck doesn't bank distance)
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
-- of spawn, for when every ParkingSlot is taken.
function VehicleLogic.OverflowSpot(index: number): Vector3
	return Vector3.new(-20 - (index % 8) * 8, 0, 56 - (index // 8) * 28)
end

---------------------------------------------------------------------------
-- The bed (saved in profile.truckBed)
---------------------------------------------------------------------------

export type BedEntry = { woodId: string, value: number, figure: string? }

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
	Mud = Color3.fromRGB(104, 90, 116), -- the Phantom Grove's violet floor
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
