--!strict
-- TollLogic: the north-strip line check. Pure. GateService keeps the last
-- sample per character and per vehicle and asks Crossed before it moves
-- anyone. Payment itself is a later batch; this only decides the crossing.

local WorldLayout = require(script.Parent.World.WorldLayout)

local TollLogic = {}

-- True only when a move goes from south of the line to on or past it,
-- inside the strip's x range. Southbound (newZ < prevZ) is always free.
-- One sample per tick, so a 40-stud jump still counts.
function TollLogic.Crossed(prevZ: number, newZ: number, x: number): boolean
	if newZ < prevZ then
		return false
	end
	if prevZ >= WorldLayout.TollLineZ or newZ < WorldLayout.TollLineZ then
		return false
	end
	return x >= WorldLayout.TollLineX0 and x <= WorldLayout.TollLineX1
end

-- One translation: the lead point lands on the push-back, and every other
-- point keeps its offset. A seated player moves the whole assembly.
function TollLogic.MoveAssembly(points: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	local lead = points[1]
	if not lead then
		return out
	end
	local dx = WorldLayout.TollPushX - lead.X
	local dz = WorldLayout.TollPushZ - lead.Z
	for _, point in ipairs(points) do
		table.insert(out, Vector3.new(point.X + dx, point.Y, point.Z + dz))
	end
	return out
end

-- A driver in a seat takes the vehicle with them. On foot, only that player.
function TollLogic.MovesWholeAssembly(seated: boolean): boolean
	return seated
end

return TollLogic
