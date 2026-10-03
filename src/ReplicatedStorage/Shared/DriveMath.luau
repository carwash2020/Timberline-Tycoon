--!strict
-- DriveMath: how a truck's speed and heading respond to the seat's throttle
-- and steer. Used by the physics driver (VehicleController, on the
-- driver's device) and by the arcade fallback (VehicleService), so both
-- feel the same (the arcade fallback passes no turning circle, so it keeps
-- the plain turnRate rule). Rates live in GameConfig; top speed and turning
-- per truck in ItemCatalog; the turning circle from TruckLayout.

local GameConfig = require(script.Parent.GameConfig)

local DriveMath = {}

local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

-- The new forward speed (studs/s, negative = reversing) after `dt` seconds
-- of `throttle` (-1..1). `actual` is how fast the truck really moves
-- forward: the commanded speed never runs more than a few studs/s ahead of
-- it, so a truck stopped by a tree doesn't lunge when it breaks free.
function DriveMath.Speed(speed: number, throttle: number, topSpeed: number, dt: number, actual: number?): number
	local target = if throttle >= 0 then throttle * topSpeed else throttle * topSpeed * GameConfig.ReverseFactor
	local rate: number
	if math.abs(throttle) < 0.05 then
		rate = GameConfig.VehicleCoast
		target = 0
	elseif speed * throttle < 0 then
		rate = GameConfig.VehicleBrake -- pressing against the way it's rolling
	else
		rate = GameConfig.VehicleAccel
	end
	local nextSpeed = approach(speed, target, rate * dt)
	if actual then
		nextSpeed = math.clamp(nextSpeed, actual - 6, actual + 6)
	end
	return nextSpeed
end

DriveMath.GripSpeed = 10 -- studs/s: below this a truck turns in proportion to its speed

-- A truck's tightest turning circle (studs, the radius its rear axle
-- follows at full steer) is at least this many times its wheelbase
-- (TruckLayout.Wheelbase: front axle to the axle it turns about), so a
-- long rig sweeps a wider circle than a short truck, as a real one does
-- (wheelbase / tan(max steer), here about 64 degrees of lock). It was
-- 0.75 before the trucks grew (M1.5, V2_PLAN §4c), then 0.62; the trucks
-- grew 1.3x again in phase 12 and at 0.477 (0.62 / 1.3) every truck turns
-- the circle it did in M1.5, within 10% of its first (DriveMath.spec): the
-- Logging Rig's 33.15-stud wheelbase gives 15.8 (was 14.8), the
-- Rustbucket's 16.12 gives 7.7 (was its own 10 / turnRate = 7.1). The town
-- and the roads didn't grow, so the circles mustn't either.
DriveMath.TurnRadiusPerWheelbase = 0.477

function DriveMath.MinTurnRadius(wheelbase: number): number
	return DriveMath.TurnRadiusPerWheelbase * math.max(wheelbase, 0)
end

-- How far (radians, around +Y) the truck turns in `dt` seconds of `steer`
-- (-1..1, positive = right). Standing still it can't turn; reversing
-- flips the direction, like a real car. Below GripSpeed it turns in
-- proportion to its speed, on a circle GripSpeed / turnRate studs in
-- radius; `minRadius` (DriveMath.MinTurnRadius), when given, keeps the
-- circle at least that wide at any speed. Top speed and turnRate at speed
-- are untouched: the cap only bites while |speed| < turnRate * minRadius.
function DriveMath.Turn(speed: number, steer: number, turnRate: number, dt: number, minRadius: number?): number
	local grip = math.clamp(math.abs(speed) / DriveMath.GripSpeed, 0, 1)
	local rate = turnRate * grip
	if minRadius and minRadius > 0 then
		rate = math.min(rate, math.abs(speed) / minRadius)
	end
	local direction = if speed < 0 then -1 else 1
	return -steer * rate * dt * direction
end

return DriveMath
