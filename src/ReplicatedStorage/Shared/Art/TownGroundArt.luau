--!strict
-- TownGroundArt (T402, T414a): the roads, yards, paths, lines and lawn edges
-- are terrain paint (TownGround.MaterialAt). This builds only the kerbs, as
-- an on-style slate bar until KerbMeshId is a real mesh. One Model per
-- material group stays, so MapBuilder can still find TownPaths. Kerbs do
-- not collide and cast no shadow. Pure decor, so streaming stays Default.

local Kit = require(script.Parent.Kit)
local MeshKit = require(script.Parent.MeshKit)
local TownGround = require(script.Parent.Parent.World.TownGround)

local TownGroundArt = {}

-- 0 until Connor uploads the kerb strip. MeshKit.Create refuses 0, and the
-- slate bar below is the look until then.
TownGroundArt.KerbMeshId = 0

local MODEL_ORDER = { "TownRoads", "TownCurbs", "TownPaths", "TownLines", "PlotEdges" }
local PAINTED = { Road = true, Yard = true, Path = true, Line = true, PlotEdge = true }

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
		-- Pull each end back by the kerb's own width so a sloped joint or a
		-- corner does not lay two bars on the same patch of ground.
		if piece.kind == "Curb" or piece.kind == "LotCurb" then
			local pull = piece.width * 2
			if size.Z > pull + 0.5 then
				size = Vector3.new(size.X, size.Y, size.Z - pull)
			end
		end
		part = Kit.part(parent, piece.name, size, cf, piece.color, material)
	end
	part.CastShadow = false
	part.CanCollide = piece.collide
	if not piece.collide then
		part.CanQuery = false
		part.CanTouch = false
	end
	part:SetAttribute("MeshId", tostring(TownGroundArt.KerbMeshId))
	-- Id 0 keeps the slate bar. A real id swaps in through Attempt, so a mesh
	-- that is still loading does not leave the bar behind for good.
	local meshId = TownGroundArt.KerbMeshId
	if meshId ~= 0 then
		local pieceName = piece.name
		local size = part.Size
		local cf = part.CFrame
		local color = part.Color
		local barMaterial = part.Material
		MeshKit.Attempt(parent, function(): boolean
			if part.Parent == nil then
				return true
			end
			local mesh = MeshKit.Create(meshId, pieceName, size)
			if not mesh then
				return false
			end
			mesh.CFrame = cf
			mesh.Color = color
			mesh.Material = barMaterial
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CastShadow = false
			mesh:SetAttribute("MeshId", tostring(meshId))
			mesh.Parent = parent
			part:Destroy()
			return true
		end)
	end
	return part
end

-- Kerbs only. Roads, paths, lines and lawn edges are terrain paint.
function TownGroundArt.Build(pieces: { TownGround.Piece }?): Model
	local root = Kit.model("TownGround")
	local groups: { [string]: Model? } = {}
	for _, name in ipairs(MODEL_ORDER) do
		groups[name] = Kit.model(name, root)
	end
	for _, piece in ipairs(pieces or TownGround.Pieces()) do
		if not PAINTED[piece.kind] then
			local group = groups[piece.group]
			if group == nil then
				group = Kit.model(piece.group, root)
				groups[piece.group] = group
			end
			TownGroundArt.PartFor(piece, group :: Model)
		end
	end
	return root
end

return TownGroundArt
