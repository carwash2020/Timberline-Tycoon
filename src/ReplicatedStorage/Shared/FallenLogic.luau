--!strict
-- FallenLogic: a log, plank, board, slab, ingot or truck that falls out of the
-- world (through the ground, or toward the engine's destroy height) comes back
-- at its owner's plot instead of being lost. Pure; WoodService, VehicleService
-- and BaseBoot's rescue loop apply it. Lane F (strandedLoad's sibling: wood
-- that a map remake parked comes back the same way).

local FallenLogic = {}

-- Below this the piece is out of the world. The lowest ground and the lake
-- beds are well above it; Roblox destroys a part at -500, so there is time.
FallenLogic.VoidY = -80

-- A piece that fell and came back is kept off its spot for this long, so a
-- stubborn piece cannot be thrown back every frame.
FallenLogic.RecoverGapSec = 2

-- Spots around the plot's middle, 5 studs up, so several pieces rescued in
-- one pass do not land inside each other.
FallenLogic.SpotRadius = 6
FallenLogic.SpotRise = 6

function FallenLogic.Fell(y: number): boolean
	return type(y) == "number" and (y < FallenLogic.VoidY or y ~= y)
end

-- Is it ok to rescue this piece now? `lastAt` is when it last came back.
function FallenLogic.MayRecover(now: number, lastAt: number?): boolean
	return lastAt == nil or now - lastAt >= FallenLogic.RecoverGapSec
end

-- The n-th spot (1-based) on a ring around the plot's middle: x, y, z offsets
-- in the plot's own axes.
function FallenLogic.Offset(n: number): (number, number, number)
	local index = math.max(1, math.floor(n))
	local ring = (index - 1) // 8
	local slot = (index - 1) % 8
	local radius = FallenLogic.SpotRadius + ring * 3
	local angle = slot / 8 * math.pi * 2
	return math.cos(angle) * radius, FallenLogic.SpotRise + ring * 2, math.sin(angle) * radius
end

FallenLogic.Texts = {
	wood = "Your wood fell out of the world. It's back on your plot.",
	truck = "Your truck fell out of the world. It's back on its pad.",
	stone = "A slab fell out of the world. It's back on your plot.",
} :: { [string]: string }

return FallenLogic
