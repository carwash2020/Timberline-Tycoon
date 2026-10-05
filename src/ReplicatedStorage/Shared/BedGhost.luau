--!strict
-- BedGhost: while you hold a piece, the truck bed's sides (walls, stakes,
-- gate, rack) let it pass and show through, so you can lower it in from any
-- side. The floor is not one of them: it stays solid and the piece rests on
-- it. Pure: DragController applies it to your own client only.

local BedGhost = {}

-- How see-through the sides are while you hold something (local only).
BedGhost.Transparency = 0.65
-- Only trucks this close to you are changed.
BedGhost.Range = 60

local SIDES: { [string]: boolean } = {
	BedBoard = true,
	BedWall = true,
	BedPost = true,
	Tailgate = true,
	BedCap = true,
	BedFront = true,
	Stake = true,
	StakeRail = true,
	StakePocket = true,
	Stanchion = true,
	Chain = true,
	HeadacheRack = true,
	TrailerStake = true,
}

-- A bed side (not the floor, not the cab or the wheels).
function BedGhost.IsSide(name: string): boolean
	return SIDES[name] == true
end

function BedGhost.Near(distance: number): boolean
	return distance <= BedGhost.Range
end

return BedGhost
