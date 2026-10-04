--!strict
-- TollLogic: the north-strip line check. Pure. GateService keeps the last
-- sample per character and per vehicle and asks Crossed before it moves
-- anyone. Payment itself is a later batch; this only decides the crossing.

local TerrainGen = require(script.Parent.World.TerrainGen)
local WorldLayout = require(script.Parent.World.WorldLayout)

local TollLogic = {}

-- The south-bank landing. Y is the ground there plus clearance, so a
-- pushed truck or a body pulled out of the gorge is not left inside it.
function TollLogic.Landing(): Vector3
	local y = TerrainGen.HeightAt(WorldLayout.TollPushX, WorldLayout.TollPushZ) + WorldLayout.TollClearance
	return Vector3.new(WorldLayout.TollPushX, y, WorldLayout.TollPushZ)
end

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
-- point keeps its offset. Y is the ground at that spot plus clearance,
-- not the height they fell from. A seated player moves the whole assembly.
function TollLogic.MoveAssembly(points: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	local lead = points[1]
	if not lead then
		return out
	end
	local land = TollLogic.Landing()
	local dx = land.X - lead.X
	local dy = land.Y - lead.Y
	local dz = land.Z - lead.Z
	for _, point in ipairs(points) do
		table.insert(out, Vector3.new(point.X + dx, point.Y + dy, point.Z + dz))
	end
	return out
end

-- A driver in a seat takes the vehicle with them. On foot, only that player.
function TollLogic.MovesWholeAssembly(seated: boolean): boolean
	return seated
end

return TollLogic
