--!strict
-- FacingLogic: which way a figure faces. This project's models are built
-- with their front on -Z (art builders, CharacterArt), so a CFrame made by
-- CFrame.Angles(0, yaw, 0) looks along its LookVector (-Z at yaw 0). Every
-- NPC heading (walking, standing, turning to talk) goes through here so the
-- sign lives in one tested place. Pure: numbers and Vector3 only.

local FacingLogic = {}

-- The yaw (radians) that faces along (dx, dz): CFrame.Angles(0, yaw, 0)
-- looks that way (0 = -Z). A zero vector faces -Z.
function FacingLogic.YawOf(dx: number, dz: number): number
	if dx == 0 and dz == 0 then
		return 0
	end
	return math.atan2(-dx, -dz)
end

-- The yaw that faces `to` from `from` (flat; heights ignored).
function FacingLogic.Face(from: Vector3, to: Vector3): number
	return FacingLogic.YawOf(to.X - from.X, to.Z - from.Z)
end

-- The flat unit direction a yaw looks along.
function FacingLogic.Direction(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- A CFrame at `pos` facing `to` (upright; not CFrame.lookAt, which Lune
-- disagrees with Roblox about).
function FacingLogic.CFrameFacing(pos: Vector3, to: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, FacingLogic.Face(pos, to), 0)
end

return FacingLogic
