--!strict
-- DoorLogic: opening a door or a fence gate. The leaf swings toward +Z
-- around the hinge at local x = -1.6, z = 0. Open is not saved.
--
-- A placed piece in the open quarter refuses the open. The quarter is a
-- box that starts at the hinge: 3 x 5.8 x 3 for a Door and 3 x 2.8 x 3 for
-- a FenceGate4, then 0.1 off every face so a floor under it and a floor
-- at y = 6 only touch. A touch does not count. Players never block an
-- open. A character in the closed doorway blocks the shut.

local DoorLogic = {}

DoorLogic.Cooldown = 0.4
DoorLogic.HingeX = -1.6
DoorLogic.Inset = 0.1
DoorLogic.Hint = "Something is blocking this door."
-- BlueprintModels' Root sits 0.1 above the ground centre.
DoorLogic.RootDrop = 0.1

-- Nominal box, before the inset. The min XZ corner is the hinge and the
-- box covers the quarter toward +X (where the leaf rests) and +Z (where
-- it opens). Y is seated so the shrunk box runs from 0.4 to the top of
-- the piece: a 0.4 floor and a ceiling whose base is at the piece top
-- only touch it.
local NOMINAL: { [string]: Vector3 } = {
	Door = Vector3.new(3, 5.8, 3),
	FenceGate4 = Vector3.new(3, 2.8, 3),
}

local TOP: { [string]: number } = {
	Door = 6,
	FenceGate4 = 3,
}

function DoorLogic.MayToggle(ownerId: number, playerId: number, now: number, last: number?): (boolean, string?)
	if playerId ~= ownerId then
		return false, "owner"
	end
	if last and now - last < DoorLogic.Cooldown then
		return false, "cooldown"
	end
	return true, nil
end

function DoorLogic.MayClose(occupied: boolean): boolean
	return not occupied
end

-- Centre and size of the open-quarter box in the piece's ground space.
function DoorLogic.Arc(id: string): (Vector3, Vector3)
	local nominal = NOMINAL[id]
	local top = TOP[id]
	if not nominal or not top then
		return Vector3.zero, Vector3.zero
	end
	local inset = DoorLogic.Inset
	local size = nominal - Vector3.new(inset * 2, inset * 2, inset * 2)
	local center = Vector3.new(DoorLogic.HingeX + nominal.X / 2, 0.4 + size.Y / 2, nominal.Z / 2)
	-- Keep the top on the piece top when the inset would push past it.
	if center.Y + size.Y / 2 > top then
		center = Vector3.new(center.X, top - size.Y / 2, center.Z)
	end
	return center, size
end

local function rotateXZ(x: number, z: number, rot: number): (number, number)
	local r = rot % 4
	if r == 1 then
		return z, -x
	elseif r == 2 then
		return -x, -z
	elseif r == 3 then
		return -z, x
	end
	return x, z
end

export type Solid = { number }

function DoorLogic.WorldSolid(x: number, y: number, z: number, rot: number, centre: Vector3, size: Vector3): Solid
	local ox, oz = rotateXZ(centre.X, centre.Z, rot)
	local sx, sz = size.X, size.Z
	if rot % 2 == 1 then
		sx, sz = sz, sx
	end
	return { x + ox, y + centre.Y, z + oz, sx, size.Y, sz }
end

local function separated(c1: number, s1: number, c2: number, s2: number): boolean
	return math.abs(c1 - c2) * 2 >= s1 + s2 - 1e-3
end

function DoorLogic.SolidsHit(a: Solid, b: Solid): boolean
	return not separated(a[1], a[4], b[1], b[4])
		and not separated(a[2], a[5], b[2], b[5])
		and not separated(a[3], a[6], b[3], b[6])
end

-- True when any solid overlaps the open quarter. Touching does not.
function DoorLogic.ArcBlocked(id: string, x: number, y: number, z: number, rot: number, solids: { Solid }): boolean
	local centre, size = DoorLogic.Arc(id)
	if size.X <= 0 then
		return false
	end
	local mine = DoorLogic.WorldSolid(x, y, z, rot, centre, size)
	for _, solid in ipairs(solids) do
		if DoorLogic.SolidsHit(mine, solid) then
			return true
		end
	end
	return false
end

-- Leaf CFrame in world space. `offset` is the closed centre. `pivot` is
-- the model's pivot (the Root, 0.1 above the ground centre).
function DoorLogic.WorldCF(pivot: CFrame, offset: Vector3, hingeX: number, open: boolean): CFrame
	local localCF = CFrame.new(offset)
	if open then
		local hinge = CFrame.new(hingeX, offset.Y, offset.Z)
		localCF = hinge * CFrame.Angles(0, -math.pi / 2, 0) * hinge:Inverse() * localCF
	end
	return pivot * CFrame.new(0, -DoorLogic.RootDrop, 0) * localCF
end

-- The closed doorway a character must not be standing in.
function DoorLogic.Doorway(id: string): (Vector3, Vector3)
	if id == "FenceGate4" then
		return Vector3.new(0, 1.5, 0), Vector3.new(3.2, 2.8, 0.8)
	end
	return Vector3.new(0, 3, 0), Vector3.new(3.2, 5.6, 0.8)
end

return DoorLogic
