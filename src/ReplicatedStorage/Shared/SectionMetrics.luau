--!strict
-- SectionMetrics: the logical frame of a wood section.
-- Gameplay, prices and saves use a Y-up box of size (t, L, t): length along
-- local Y, square side t. A round log is a Part whose Shape is Cylinder.
-- Roblox cylinders run along local X, so the part is the logical frame
-- turned 90 degrees about Z, with Size (L, d, d) and d = 2 * RoundRadius(t).
-- The engine's mass is then pi*r^2*L = t^2*L, the same volume the prices use.
-- Planks stay Blocks. MeshParts stay in the logical Y-up frame (uploaded
-- section meshes are authored that way).

local StumpLogic = require(script.Parent.StumpLogic)

local SectionMetrics = {}

SectionMetrics.SquareSideAttr = "SquareSide"

-- Cylinder local +X is the logical +Y (the trunk axis).
local TO_CYLINDER = CFrame.Angles(0, 0, math.pi / 2)
local FROM_CYLINDER = CFrame.Angles(0, 0, -math.pi / 2)

function SectionMetrics.IsPlank(part: BasePart): boolean
	if part:GetAttribute("Kind") == "plank" then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:GetAttribute("Kind") == "plank"
end

-- A round log (not a plank, not a cut-face disc).
function SectionMetrics.IsCylinder(part: BasePart): boolean
	return part:IsA("Part")
		and part.Shape == Enum.PartType.Cylinder
		and part.Name == "Section"
		and not SectionMetrics.IsPlank(part)
end

function SectionMetrics.IsRound(part: BasePart): boolean
	if SectionMetrics.IsPlank(part) or part.Name ~= "Section" then
		return false
	end
	if part:IsA("MeshPart") then
		return true
	end
	return SectionMetrics.IsCylinder(part)
end

function SectionMetrics.Diameter(side: number): number
	return 2 * StumpLogic.RoundRadius(side)
end

-- Logical centre CFrame (Y along the trunk) and logical size (t, L, t).
function SectionMetrics.BlockFrame(part: BasePart): (CFrame, Vector3)
	if SectionMetrics.IsCylinder(part) then
		local logical = part.CFrame * FROM_CYLINDER
		local length = part.Size.X
		local diameter = math.min(part.Size.Y, part.Size.Z)
		local attr = part:GetAttribute(SectionMetrics.SquareSideAttr)
		local side = if type(attr) == "number" then attr else diameter * math.sqrt(math.pi) / 2
		return logical, Vector3.new(side, length, side)
	end
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

function SectionMetrics.Radius(part: BasePart): number
	if SectionMetrics.IsCylinder(part) then
		return math.min(part.Size.Y, part.Size.Z) / 2
	end
	return StumpLogic.RoundRadius(SectionMetrics.SquareSide(part))
end

-- Writes the logical frame onto `part`. A plank stays a block. A MeshPart
-- stays Y-up. Any other section becomes a cylinder of the same priced volume.
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
	if part:IsA("MeshPart") then
		part.Size = Vector3.new(side, length, side)
		part.CFrame = logicalCf
		part:SetAttribute(SectionMetrics.SquareSideAttr, side)
		return
	end
	if part:IsA("Part") then
		local diameter = SectionMetrics.Diameter(side)
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(length, diameter, diameter)
		part.CFrame = logicalCf * TO_CYLINDER
		part:SetAttribute(SectionMetrics.SquareSideAttr, side)
	end
end

return SectionMetrics
