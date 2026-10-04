--!strict
-- BlueprintModels: builds a blueprint's model from its PlotData boxes, for
-- the server (placed items) and the client (the ghost preview), so the two
-- always match. The model's pivot is its ground centre.
--
-- When a mesh template exists, visual meshes are welded to Root and the
-- boxes go invisible. The boxes stay the collider. No template (or a mesh
-- that failed to load) keeps the boxes as the look.

local CollectionService = game:GetService("CollectionService")

local ItemMeshes = require(script.Parent.ItemMeshes)
local PlotData = require(script.Parent.PlotData)

local BlueprintModels = {}

function BlueprintModels.Build(bp: PlotData.Blueprint, ghost: boolean): Model
	local model = Instance.new("Model")
	model.Name = bp.id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(bp.footprint.X, 0.2, bp.footprint.Y)
	root.CFrame = CFrame.new(0, 0.1, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Parent = model
	for i, box in ipairs(bp.boxes) do
		local p: BasePart
		if box.shape == "Wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
			if box.shape == "Cylinder" then
				(p :: Part).Shape = Enum.PartType.Cylinder
			elseif box.shape == "Ball" then
				(p :: Part).Shape = Enum.PartType.Ball
			end
		end
		p.Name = "Part" .. i
		p.Size = box.size
		p.CFrame = CFrame.new(box.offset)
		p.Color = Color3.fromHex(box.color)
		local named = (Enum.Material :: any)[box.material]
		local mat: Enum.Material = Enum.Material.SmoothPlastic
		if typeof(named) == "EnumItem" then
			mat = named :: Enum.Material
		end
		p.Material = mat
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if ghost then
			p.Transparency = 0.45
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
		if box.light and not ghost then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 214, 140)
			light.Range = 18
			light.Parent = p
		end
		if box.smoke and not ghost then
			p:SetAttribute("HearthSmoke", true)
			CollectionService:AddTag(p, "HearthSmoke")
		end
		p.Parent = model
	end
	model.PrimaryPart = root
	ItemMeshes.Attach(model, root, bp.id, ghost)
	return model
end

-- Puts a built model at plot-local (x, z) with `rot` quarter turns.
function BlueprintModels.Place(model: Model, plotCFrame: CFrame, x: number, z: number, rot: number)
	model:PivotTo(plotCFrame * CFrame.new(x, 0, z) * CFrame.Angles(0, rot * math.pi / 2, 0))
end

return BlueprintModels
