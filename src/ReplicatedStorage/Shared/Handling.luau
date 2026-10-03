--!strict
-- Handling: how each truck feels, on top of DriveMath.
-- DriveMath.Speed and DriveMath.Turn stay the contracts the circle tests
-- lock (catalog topSpeed and turnRate). This module is what
-- VehicleController and the arcade fallback actually drive with: a
-- per-tier accel, brake and coast, a climb force, how hard the truck
-- resists tipping, speed-sensitive steering, and a small wider circle
-- plus a visible trailer swing while towing. The same numbers apply
-- with or without the bodywork, because every detail part is massless.

local DriveMath = require(script.Parent.DriveMath)
local GameConfig = require(script.Parent.GameConfig)
local VehicleLogic = require(script.Parent.VehicleLogic)

local Handling = {}

Handling.TowFactor = 1.12 -- a hitched trailer widens the turning circle a little
Handling.SwingLimit = 0.45 -- radians: short of a jackknife (~0.5, and far short of folding)
Handling.ForceFloor = 100 -- mass * this still climbs the skid ramps (TruckArt)

export type Profile = {
	accel: number,
	brake: number,
	coast: number,
	climb: number, -- 0..1 and a bit: how hard Drive pushes, and how well it climbs
	tipResist: number, -- 0..1: blend the ground's lean back toward upright
	steerLow: number, -- turnRate scale below a crawl
	steerHigh: number, -- turnRate scale at top speed
	suspension: number, -- how fast the lean follows the ground (per second)
}

local function profile(
	accel: number,
	brake: number,
	coast: number,
	climb: number,
	tipResist: number,
	steerLow: number,
	steerHigh: number,
	suspension: number
): Profile
	return {
		accel = accel,
		brake = brake,
		coast = coast,
		climb = climb,
		tipResist = tipResist,
		steerLow = steerLow,
		steerHigh = steerHigh,
		suspension = suspension,
	}
end

-- Rustbucket: sluggish, weak climb, never tips.
-- Pickup: quicker, climbs better, a tight low-speed turn.
-- Scout ATV: fastest response, steepest climb, loosest lean (no bed).
-- Flatbed: a wider, steadier turn.
-- Logging Rig: planted, climbs any slope, the widest turn.
local PROFILES: { [string]: Profile } = {
	Rustbucket = profile(9, 28, 7, 0.22, 0.85, 1.02, 0.9, 8),
	Pickup = profile(16, 36, 6, 0.55, 0.7, 1.18, 0.96, 11),
	ScoutATV = profile(22, 40, 5, 0.9, 0.55, 1.2, 1.0, 14),
	Flatbed = profile(12, 34, 7, 0.4, 0.8, 1.0, 0.88, 9),
	LoggingRig = profile(11, 32, 8, 0.85, 0.95, 0.95, 0.85, 7),
}

function Handling.For(truckId: string?): Profile
	-- The Timber Classic is the Pickup's body and feel. A pass truck must
	-- not climb, turn or accelerate past the tier it copies.
	if truckId == "TimberClassic" then
		return PROFILES.Pickup
	end
	return PROFILES[truckId or ""] or PROFILES.Rustbucket
end

local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

-- DriveMath.Speed with this truck's accel, brake and coast.
function Handling.Speed(
	speed: number,
	throttle: number,
	topSpeed: number,
	dt: number,
	actual: number?,
	feel: Profile?
): number
	local rates = feel or Handling.For(nil)
	local target = if throttle >= 0 then throttle * topSpeed else throttle * topSpeed * GameConfig.ReverseFactor
	local rate: number
	if math.abs(throttle) < 0.05 then
		rate = rates.coast
		target = 0
	elseif speed * throttle < 0 then
		rate = rates.brake
	else
		rate = rates.accel
	end
	local nextSpeed = approach(speed, target, rate * dt)
	if actual then
		nextSpeed = math.clamp(nextSpeed, actual - 6, actual + 6)
	end
	return nextSpeed
end

-- turnRate scaled down as speed rises (steady on a road, tighter in a bay).
function Handling.SteerScale(speed: number, topSpeed: number, feel: Profile): number
	local u = math.clamp(math.abs(speed) / math.max(topSpeed, 1), 0, 1)
	return feel.steerLow + (feel.steerHigh - feel.steerLow) * u
end

function Handling.Turn(
	speed: number,
	steer: number,
	turnRate: number,
	dt: number,
	minRadius: number?,
	feel: Profile?,
	topSpeed: number?
): number
	local rates = feel or Handling.For(nil)
	local scale = Handling.SteerScale(speed, topSpeed or 26, rates)
	return DriveMath.Turn(speed, steer, turnRate * scale, dt, minRadius)
end

-- A hitched trailer widens the circle a little. No trailer: unchanged.
function Handling.TowRadius(minRadius: number?, hitched: boolean): number?
	if not hitched or minRadius == nil then
		return minRadius
	end
	return minRadius * Handling.TowFactor
end

-- LinearVelocity MaxForce / mass. Every tier clears a kerb; the rig and
-- the ATV push harder up a slope than the Rustbucket.
function Handling.DriveForce(feel: Profile): number
	return math.max(Handling.ForceFloor, 80 + 90 * feel.climb)
end

-- AlignOrientation MaxTorque / mass. A high tipResist holds the truck down.
function Handling.HoldTorque(feel: Profile): number
	return 2000 + 5000 * feel.tipResist
end

-- The up the truck should lean to: the ground's, pulled back toward the
-- world up by tipResist, then clamped. A planted truck barely leans, so
-- a loaded Rustbucket or rig does not roll on a normal road.
function Handling.Lean(groundUp: Vector3, tipResist: number, maxTilt: number): Vector3
	local up = if groundUp.Magnitude > 1e-4 then groundUp.Unit else Vector3.yAxis
	local blended = up * (1 - tipResist) + Vector3.yAxis * tipResist
	if blended.Magnitude < 1e-4 then
		return Vector3.yAxis
	end
	local resist = math.clamp(tipResist, 0, 1)
	return VehicleLogic.ClampTilt(blended.Unit, maxTilt * (1 - 0.65 * resist))
end

-- Trailer yaw (radians) chasing the truck's yaw rate. Clamped short of
-- a jackknife. `speed` in studs/s, `yawRate` in rad/s, `dt` in seconds.
function Handling.TrailerSwing(angle: number, yawRate: number, speed: number, dt: number): number
	local gain = if math.abs(speed) > 12 then 0.35 else 0.55
	local target = if math.abs(speed) > 1
		then math.clamp(-yawRate * gain, -Handling.SwingLimit, Handling.SwingLimit)
		else 0
	local follow = 1 - math.exp(-4 * math.max(dt, 0))
	local nextAngle = angle + (target - angle) * follow
	return math.clamp(nextAngle, -Handling.SwingLimit, Handling.SwingLimit)
end

return Handling
