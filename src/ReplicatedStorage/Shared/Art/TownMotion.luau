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

-- Low quality stops the windmill. The saw and the bullwheel still turn.
function TownMotion.WindmillSpins(tier: string): boolean
	return tier ~= "low"
end

return TownMotion
