--!strict
-- SnapLogic: where the client ghost lands. Pure. The server's checks are
-- unchanged (PlotLogic.Check); a spec runs the same placements through
-- SnapLogic then PlotLogic.Check so the ghost and the server agree (QA BL8).
--   - A wall end snaps to an existing wall end within SnapLogic.EndReach.
--   - A piece's base snaps to the top of the floor, foundation or tall wall
--     under it (0.4 on Floor4, 2 on Foundation8, 10 on TallWall8).
-- The grid stays: centres on PlotData.Grid, heights on HeightStep, quarter
-- turns.

local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)

local SnapLogic = {}

SnapLogic.EndReach = 1 -- studs: a wall end this close to another snaps onto it
SnapLogic.StepUp = 1 -- studs: a support top this far above the ghost still counts

type Placed = PlotLogic.Placed

-- The plot axis a piece's local X lies along after `rot` quarter turns.
-- Only the line matters for the two ends, not its sign.
local function axis(rot: number): (number, number)
	if rot % 2 == 0 then
		return 1, 0
	end
	return 0, 1
end

-- The two ends of an edge piece (a wall, beam, railing) in plot space.
function SnapLogic.Ends(bp: PlotData.Blueprint, x: number, z: number, rot: number, len: number?): { Vector2 }
	local ax, az = axis(rot)
	local half = (len or bp.footprint.X) / 2
	return { Vector2.new(x - ax * half, z - az * half), Vector2.new(x + ax * half, z + az * half) }
end

-- Snap an edge piece so one of its ends sits on the nearest other wall end
-- within EndReach. Returns the (maybe moved) centre.
function SnapLogic.SnapEnds(
	bp: PlotData.Blueprint,
	x: number,
	z: number,
	rot: number,
	placed: { Placed }
): (number, number)
	if bp.edge ~= true then
		return x, z
	end
	local mine = SnapLogic.Ends(bp, x, z, rot)
	local best: Vector2? = nil
	local bestDist = SnapLogic.EndReach + 1e-6
	for _, item in ipairs(placed) do
		local other = PlotData.Blueprint(item.blueprintId)
		if other and other.edge == true then
			for _, theirs in ipairs(SnapLogic.Ends(other, item.x, item.z, item.rot, item.len)) do
				for _, end_ in ipairs(mine) do
					local d = (theirs - end_).Magnitude
					if d > 1e-6 and d < bestDist then
						bestDist = d
						best = theirs - end_
					end
				end
			end
		end
	end
	if best then
		return PlotLogic.Snap(x + best.X), PlotLogic.Snap(z + best.Y)
	end
	return x, z
end

-- The top of a piece's boxes above its own base.
function SnapLogic.TopOf(bp: PlotData.Blueprint): number
	local top = 0
	for _, box in ipairs(bp.boxes) do
		top = math.max(top, box.offset.Y + box.size.Y / 2)
	end
	return top
end

-- Which pieces carry another on top: floors, foundations, tall walls.
function SnapLogic.Supports(bp: PlotData.Blueprint): boolean
	if bp.kit ~= true or bp.roof == true then
		return false
	end
	local id = bp.id
	return id == "Floor"
		or id == "Floor4"
		or id == "Foundation8"
		or id == "SandFloor4"
		or id == "TallWall8"
		or id == "TallWall4"
end

local function covers(bp: PlotData.Blueprint, item: Placed, x: number, z: number): boolean
	local w, d = bp.footprint.X, bp.footprint.Y
	if item.rot % 2 == 1 then
		w, d = d, w
	end
	return math.abs(x - item.x) <= w / 2 + 1e-6 and math.abs(z - item.z) <= d / 2 + 1e-6
end

-- The height a ghost at (x, z) should sit at: the top of the highest support
-- under the centre whose base is at or below `y + StepUp` (so a ghost aimed
-- into a foundation rises onto it), unless the ghost is raised more than
-- StepUp above it; else `y` on the 0.2 grid.
function SnapLogic.BaseY(x: number, z: number, y: number, placed: { Placed }): number
	local best: number? = nil
	for _, item in ipairs(placed) do
		local bp = PlotData.Blueprint(item.blueprintId)
		if bp and SnapLogic.Supports(bp) and covers(bp, item, x, z) then
			local base = item.y or 0
			local top = base + SnapLogic.TopOf(bp)
			if base <= y + SnapLogic.StepUp and (best == nil or top > best) then
				best = top
			end
		end
	end
	-- Raised well above every support, the ghost keeps its height.
	if best ~= nil and y > best + SnapLogic.StepUp then
		best = nil
	end
	local out = PlotLogic.SnapY(best or y)
	if out > PlotData.MaxBuildY then
		out = PlotData.MaxBuildY
	end
	return math.max(0, out)
end

-- Where the ghost goes: grid centre, wall ends joined, base on the support.
function SnapLogic.Place(
	bp: PlotData.Blueprint,
	x: number,
	z: number,
	rot: number,
	y: number,
	placed: { Placed }
): (number, number, number)
	local sx, sz = PlotLogic.Snap(x), PlotLogic.Snap(z)
	sx, sz = SnapLogic.SnapEnds(bp, sx, sz, rot, placed)
	local sy = SnapLogic.BaseY(sx, sz, y, placed)
	return sx, sz, sy
end

return SnapLogic
