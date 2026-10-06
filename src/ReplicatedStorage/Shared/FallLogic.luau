--!strict
-- Pure rules for how a felled tree moves, so a fall topples as one rigid
-- trunk and never flings itself apart. WoodService applies them.
--   * The first push is a slow spin about the cut edge, capped.
--   * Every frame of the watched fall, linear and angular speed are held
--     under a cap (a depenetration kick or a stray bounce cannot launch it).
--   * The freed trunk starts a hair above the stump, so it never begins
--     overlapping it.

local FallLogic = {}

FallLogic.MaxSpin = 2.2 -- rad/s: the fastest a trunk may turn while it falls
FallLogic.MaxSpeed = 45 -- studs/s: the fastest any part of it may travel
FallLogic.LiftGap = 0.06 -- studs: a freed trunk starts this far above its stump
FallLogic.CapSec = 6 -- how long the caps are held

-- The first spin: impulse / reach, never above `maxSpin`.
function FallLogic.StartSpin(impulse: number, reach: number, maxSpin: number?): number
	local limit = maxSpin or FallLogic.MaxSpin
	if reach ~= reach or impulse ~= impulse then
		return 0
	end
	local spin = impulse / math.max(1, reach)
	return math.clamp(spin, 0, limit)
end

-- `v` scaled down to `max` long when it is longer, else unchanged. A NaN
-- vector is zeroed.
function FallLogic.Clamp(v: Vector3, max: number): Vector3
	local m = v.Magnitude
	if m ~= m then
		return Vector3.zero
	end
	if m <= max or m == 0 then
		return v
	end
	return v * (max / m)
end

-- The (linear, angular) velocity to set on a falling piece, or nil when
-- both are already inside the caps (both results nil).
function FallLogic.Capped(linear: Vector3, angular: Vector3): (Vector3?, Vector3?)
	local lm, am = linear.Magnitude, angular.Magnitude
	if lm == lm and am == am and lm <= FallLogic.MaxSpeed and am <= FallLogic.MaxSpin then
		return nil
	end
	return FallLogic.Clamp(linear, FallLogic.MaxSpeed), FallLogic.Clamp(angular, FallLogic.MaxSpin)
end

return FallLogic
