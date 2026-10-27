--!strict
-- SectionMetrics: the logical frame of a wood section.
-- Gameplay, prices and saves use a Y-up box of size (t, L, t): length along
-- local Y, square side t. The part is that box. PartType.Block, Size (t, L, t).
-- A priced volume is t^2 * L. There is no round radius on this path.
-- Planks stay Blocks of their own (not necessarily square) size.
-- A MeshPart named Section, if one is ever parented here, stays in the same
-- Y-up frame. It is not a cylinder and it is not the shipped section: bark
-- and canopy are child meshes, and they do not change this part's shape.

local SectionMetrics = {}

SectionMetrics.SquareSideAttr = "SquareSide"

function SectionMetrics.IsPlank(part: BasePart): boolean
	if part:GetAttribute("Kind") == "plank" then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:GetAttribute("Kind") == "plank"
end

-- Wood is square. A section is never a cylinder.
function SectionMetrics.IsCylinder(part: BasePart): boolean
	return part.ClassName == "CylinderSection"
end

-- Wood is square. A section mesh is dress, not a round log.
function SectionMetrics.IsRound(part: BasePart): boolean
	return SectionMetrics.IsCylinder(part)
end

-- Logical centre CFrame (Y along the trunk) and logical size (t, L, t),
-- or the plank's own size.
function SectionMetrics.BlockFrame(part: BasePart): (CFrame, Vector3)
	if part:IsA("MeshPart") and part.Name == "Section" and not SectionMetrics.IsPlank(part) then
		local attr = part:GetAttribute(SectionMetrics.SquareSideAttr)
		local side = if type(attr) == "number" then attr else math.min(part.Size.X, part.Size.Z)
		return part.CFrame, Vector3.new(side, part.Size.Y, side)
	end
	return part.CFrame, part.Size
end

function SectionMetrics.Length(part: BasePart): number
	local _, size = SectionMetrics.BlockFrame(part)
	return size.Y
end

function SectionMetrics.SquareSide(part: BasePart): number
	local _, size = SectionMetrics.BlockFrame(part)
	return math.min(size.X, size.Z)
end

-- Half the square side: the rest height and the mill's half-width.
-- Not a round radius.
function SectionMetrics.Radius(part: BasePart): number
	return SectionMetrics.SquareSide(part) / 2
end

-- The pose CargoLock reads. Wood is a box: the part's own CFrame and Size.
-- The shape is nil, so the lock uses the box, not a cylinder.
function SectionMetrics.CargoPose(part: BasePart): (CFrame, Vector3, string?)
	return part.CFrame, part.Size, nil
end

-- Writes the logical frame onto `part`. A plank stays a board. Any other
-- section is a Block of size (t, L, t), Y along the trunk.
function SectionMetrics.ApplyBlockFrame(part: BasePart, logicalCf: CFrame, logicalSize: Vector3)
	if SectionMetrics.IsPlank(part) then
		part.Size = logicalSize
		part.CFrame = logicalCf
		if part:IsA("Part") then
			part.Shape = Enum.PartType.Block
		end
		return
	end
	local side = math.min(logicalSize.X, logicalSize.Z)
	local length = logicalSize.Y
	part.Size = Vector3.new(side, length, side)
	part.CFrame = logicalCf
	if part:IsA("Part") then
		part.Shape = Enum.PartType.Block
	end
	part:SetAttribute(SectionMetrics.SquareSideAttr, side)
end

return SectionMetrics
