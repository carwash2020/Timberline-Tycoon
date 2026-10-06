--!strict
-- HeadLook: where a head should turn to look at a point. Pure maths on
-- numbers and Vector3/CFrame (no services, no CFrame.lookAt, which Lune
-- disagrees with Roblox about), so the Lune tests check it.
--
-- Conventions (CharacterArt, FacingLogic): a figure's front is -Z in the
-- space of the neck pivot (`torso.CFrame * neck.C0`). Motor6D.Transform of
-- CFrame.Angles(0, yaw, 0) turns the face toward -X for yaw > 0, and
-- CFrame.Angles(pitch, 0, 0) tips it up for pitch > 0. Aim returns exactly
-- those two angles, so the neck transform is Transform(yaw, pitch).

local HeadLook = {}

HeadLook.MaxYaw = math.rad(70) -- the furthest a head turns to the side
HeadLook.MaxPitch = math.rad(35) -- the furthest it looks up or down
HeadLook.GiveUp = math.rad(110) -- a target further round than this is behind: look ahead
HeadLook.Rate = 6 -- smoothing: 1/s, the exponential approach rate

-- Signed angle (radians) the flat direction (dx, dz) is off `front`
-- (also flat, a unit-ish (x, z) pair; default -Z), positive toward -X
-- (the head's left), matching CFrame.Angles(0, yaw, 0).
local function flatYaw(dx: number, dz: number, fx: number, fz: number): number
	-- yaw of the target and of the front, both as CFrame.Angles(0, y, 0) looks
	local target = math.atan2(-dx, -dz)
	local rest = math.atan2(-fx, -fz)
	local d = target - rest
	return (d + math.pi) % (2 * math.pi) - math.pi
end

-- The yaw and pitch that point a head's front at `target`.
--   pivot      the neck pivot in world space (torso * C0): -Z is straight ahead
--   target     world point to look at (the player's head)
--   lift       how far above the pivot the head's eyes sit (studs), so the
--              pitch aims at the target from the eyes rather than the neck
--   restFront  the head's front in pivot space; default -Z. Only the flat
--              part is used.
-- Returns yaw, pitch (both clamped to MaxYaw / MaxPitch), and whether the
-- target is within reach (false when it is behind: then yaw and pitch are 0
-- and the head should settle straight ahead).
function HeadLook.Aim(pivot: CFrame, target: Vector3, lift: number?, restFront: Vector3?): (number, number, boolean)
	local rel = pivot:PointToObjectSpace(target)
	local dx, dy, dz = rel.X, rel.Y - (lift or 0), rel.Z
	local front = restFront or Vector3.new(0, 0, -1)
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat < 1e-3 or dx ~= dx or dy ~= dy or dz ~= dz then
		return 0, 0, false
	end
	local yaw = flatYaw(dx, dz, front.X, front.Z)
	if math.abs(yaw) > HeadLook.GiveUp then
		return 0, 0, false
	end
	local pitch = math.atan2(dy, flat)
	return math.clamp(yaw, -HeadLook.MaxYaw, HeadLook.MaxYaw),
		math.clamp(pitch, -HeadLook.MaxPitch, HeadLook.MaxPitch),
		true
end

-- Ease `current` toward `want` (frame-rate independent).
function HeadLook.Approach(current: number, want: number, dt: number, rate: number?): number
	return current + (want - current) * (1 - math.exp(-(rate or HeadLook.Rate) * dt))
end

-- The Motor6D.Transform for a yaw and pitch (plus a little roll).
function HeadLook.Transform(yaw: number, pitch: number, roll: number?): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll or 0)
end

-- Where the head's front points in the pivot's space after a neck
-- Transform(yaw, pitch): the rest front turned by the transform.
function HeadLook.FrontAfter(yaw: number, pitch: number, restFront: Vector3?): Vector3
	return HeadLook.Transform(yaw, pitch):VectorToWorldSpace(restFront or Vector3.new(0, 0, -1))
end

return HeadLook
