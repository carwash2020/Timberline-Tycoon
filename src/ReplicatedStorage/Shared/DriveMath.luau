--!strict
-- DriveMath: how a truck's speed and heading respond to the seat's throttle
-- and steer. Used by the physics driver (VehicleController, on the
-- driver's device) and by the arcade fallback (VehicleService), so both
-- feel the same. Rates live in GameConfig; top speed and turning per truck
-- in ItemCatalog.

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

-- How far (radians, around +Y) the truck turns in `dt` seconds of `steer`
-- (-1..1, positive = right). Standing still it can't turn; reversing
-- flips the direction, like a real car.
function DriveMath.Turn(speed: number, steer: number, turnRate: number, dt: number): number
	local grip = math.clamp(math.abs(speed) / 10, 0, 1)
	local direction = if speed < 0 then -1 else 1
	return -steer * turnRate * dt * grip * direction
end

return DriveMath
