--!strict
-- TownMotion: how a town mesh turns, with no Instances. TownFX uses it,
-- and the ticket I tests check the same numbers.
-- A spin with no hinge turns about the part's centre. A hinge is a point
-- in the part's object space (a door's edge, the windmill hub) and stays
-- put. Axis is "X", "Y", or "Z" in that same object space.

local TownMotion = {}

function TownMotion.Spin(axis: string, angle: number): CFrame
	if axis == "Y" then
		return CFrame.Angles(0, angle, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(angle, 0, 0)
end

-- `cf` after rotating `angle` radians about `axis` through `hinge`
-- (object space). A zero hinge is the part's centre.
function TownMotion.Step(cf: CFrame, axis: string, hinge: Vector3, angle: number): CFrame
	local spin = TownMotion.Spin(axis, angle)
	if hinge.Magnitude < 1e-4 then
		return cf * spin
	end
	local pivot = cf * CFrame.new(hinge)
	return pivot * spin * pivot:Inverse() * cf
end

-- Turning speeds, radians per second. The saw blade is slow enough to read
-- as a spinning disc (about half a turn a second), the bullwheel a little over
-- a third of that. They are advanced EVERY frame by dt (TownFX), never in
-- quality-throttled steps: a 2 or 20 Hz step of a fast spin looks like lag.
TownMotion.BladeSpeed = 3
TownMotion.WheelSpeed = TownMotion.BladeSpeed * 0.35
TownMotion.SailSpeed = 0.6
-- A frame longer than this (a hitch, a tab switch) turns no further than
-- this, so the blade never leaps.
TownMotion.MaxFrame = 0.1

-- The angle a part at `speed` rad/s turns in a frame of `dt` seconds.
function TownMotion.Advance(speed: number, dt: number): number
	if dt ~= dt or dt <= 0 then
		return 0
	end
	return speed * math.min(dt, TownMotion.MaxFrame)
end

-- Low quality stops the windmill. The saw and the bullwheel still turn.
function TownMotion.WindmillSpins(tier: string): boolean
	return tier ~= "low"
end

return TownMotion
