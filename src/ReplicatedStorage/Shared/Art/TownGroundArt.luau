--!strict
-- TownGroundArt (T402): builds the town's ground parts from the pieces
-- Shared/World/TownGround computes (roads, yards, curbs, footpaths, lines and
-- the plots' lawn edges). One Model per material group (same-material runs
-- share a Model), every part anchored; roads, curbs and paths collide, the
-- paint and the lawn edge do not. Nothing casts a shadow (they are flat).
-- MapBuilder parents the result under the map; tools/preview builds the same.

local Kit = require(script.Parent.Kit)
local TownGround = require(script.Parent.Parent.World.TownGround)

local TownGroundArt = {}

local MODEL_ORDER = { "TownRoads", "TownCurbs", "TownPaths", "TownLines", "PlotEdges" }

-- The CFrame of a block piece: its centre line at the top surface, the part
-- hung `thick` under it, tilted along the slope of its run.
local function blockCFrame(piece: TownGround.Piece): (CFrame, Vector3)
	local mid = Vector3.new((piece.a.X + piece.b.X) / 2, (piece.ya + piece.yb) / 2, (piece.a.Y + piece.b.Y) / 2)
	local run = Vector3.new(piece.b.X - piece.a.X, piece.yb - piece.ya, piece.b.Y - piece.a.Y)
	local cf = CFrame.lookAt(mid, mid + run) * CFrame.new(0, -piece.thick / 2, 0)
	return cf, Vector3.new(piece.width, piece.thick, run.Magnitude)
end

function TownGroundArt.PartFor(piece: TownGround.Piece, parent: Instance): BasePart
	local material = (Enum.Material :: any)[piece.material]
	local part: Part
	if piece.shape == "Cylinder" then
		local cf = CFrame.new(piece.a.X, piece.ya - piece.thick / 2, piece.a.Y) * CFrame.Angles(0, 0, math.pi / 2)
		part = Kit.cylinder(parent, piece.name, piece.thick, piece.width, cf, piece.color, material)
	else
		local cf, size = blockCFrame(piece)
		part = Kit.part(parent, piece.name, size, cf, piece.color, material)
	end
	part.CastShadow = false
	part.CanCollide = piece.collide
	if not piece.collide then
		part.CanQuery = false
		part.CanTouch = false
	end
	return part
end

-- All the ground parts. `pieces` defaults to TownGround.Pieces().
function TownGroundArt.Build(pieces: { TownGround.Piece }?): Model
	local root = Kit.model("TownGround")
	local groups: { [string]: Model? } = {}
	for _, name in ipairs(MODEL_ORDER) do
		groups[name] = Kit.model(name, root)
	end
	for _, piece in ipairs(pieces or TownGround.Pieces()) do
		local group = groups[piece.group]
		if group == nil then
			group = Kit.model(piece.group, root)
			groups[piece.group] = group
		end
		TownGroundArt.PartFor(piece, group :: Model)
	end
	return root
end

return TownGroundArt
