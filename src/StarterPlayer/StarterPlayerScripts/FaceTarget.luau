--!strict
-- FaceTarget: the turn ChopController gives your character so a swing
-- lands on the tree instead of the air beside it. Turning only happens
-- when the tree is more than Tolerance off to the side, and only about +Y:
-- the root part keeps its position and stands upright. Pure maths on
-- datatypes (no services, and CFrame.fromMatrix rather than CFrame.lookAt,
-- which Lune 0.10.5 gets wrong), so the Lune tests check it.

local FaceTarget = {}

FaceTarget.Tolerance = math.rad(15) -- this close to straight ahead: no turn

-- The flat (XZ) unit direction from `from` to `to`, or nil when `to` is
-- (nearly) straight above or below `from`, or isn't a real position.
function FaceTarget.FlatDirection(from: Vector3, to: Vector3): Vector3?
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length ~= length or length < 1e-3 or length == math.huge then
		return nil
	end
	return flat / length
end

-- How far (radians, 0..pi) the flat unit direction `dir` is off the flat
-- part of `look`. A look straight up or down has no flat part, so it
-- counts as all the way off.
function FaceTarget.OffAngle(look: Vector3, dir: Vector3): number
	local flat = Vector3.new(look.X, 0, look.Z)
	local length = flat.Magnitude
	if length ~= length or length < 1e-3 then
		return math.pi
	end
	return math.acos(math.clamp(flat:Dot(dir) / length, -1, 1))
end

-- The CFrame `root` should take to face `target`: the same position,
-- upright, looking along the flat direction to it. Nil when it already
-- faces within `tolerance` (default Tolerance), or the target is right
-- above or below it (nothing to turn toward).
function FaceTarget.Turn(root: CFrame, target: Vector3, tolerance: number?): CFrame?
	local dir = FaceTarget.FlatDirection(root.Position, target)
	if not dir then
		return nil
	end
	if FaceTarget.OffAngle(root.LookVector, dir) <= (tolerance or FaceTarget.Tolerance) then
		return nil
	end
	-- Right = look x up, so (right, up, -look) is a right-handed upright frame.
	return CFrame.fromMatrix(root.Position, dir:Cross(Vector3.yAxis), Vector3.yAxis, -dir)
end

return FaceTarget
