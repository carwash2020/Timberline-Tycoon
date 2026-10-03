--!strict
-- BlueprintModels: builds a blueprint's model from its PlotData boxes, for
-- the server (placed items) and the client (the ghost preview), so the two
-- always match. The model's pivot is its ground centre.
--
-- A kit piece with a loaded mesh hides the boxes that the mesh replaces.
-- DoorWall8 keeps two jambs. FenceGate4 keeps two posts. A door or gate
-- leaf is the only swinging collider. No mesh keeps the boxes as the look.

local CollectionService = game:GetService("CollectionService")

local ItemMeshes = require(script.Parent.ItemMeshes)
local KitMeshes = require(script.Parent.KitMeshes)
local PlotData = require(script.Parent.PlotData)
local TreeArt = require(script.Parent.Art.TreeArt)
local WoodData = require(script.Parent.WoodData)

local BlueprintModels = {}

local function materialOf(name: string): Enum.Material
	local named = (Enum.Material :: any)[name]
	local mat: Enum.Material = Enum.Material.SmoothPlastic
	if typeof(named) == "EnumItem" then
		mat = named :: Enum.Material
	end
	return mat
end

local function roleOf(box: PlotData.Box): string
	if box.role then
		return box.role
	end
	if box.material == "Glass" then
		return "Glass"
	elseif box.material == "Neon" then
		return "Glow"
	elseif box.material == "Fabric" then
		return "Flag"
	elseif
		box.material == "Metal"
		or box.material == "CorrodedMetal"
		or box.material == "DiamondPlate"
		or box.material == "Slate"
	then
		return "Metal"
	elseif box.material == "Wood" or box.material == "WoodPlanks" then
		return "Wood"
	end
	return "Prop"
end

local function makePart(box: PlotData.Box): BasePart
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
	p.Size = box.size
	p.CFrame = CFrame.new(box.offset)
	p.Color = Color3.fromHex(box.color)
	p.Material = materialOf(box.material)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

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
		local p = makePart(box)
		p.Name = "Part" .. i
		local role = roleOf(box)
		if bp.kit then
			p:SetAttribute("Role", role)
			p:SetAttribute("OX", box.offset.X)
			p:SetAttribute("OY", box.offset.Y)
			p:SetAttribute("OZ", box.offset.Z)
			if box.leaf then
				p:SetAttribute("Leaf", true)
				p:SetAttribute("Swings", true)
				p:SetAttribute("HingeX", bp.hinge or -1.6)
			elseif bp.id == "DoorWall8" then
				p:SetAttribute("Jamb", true)
			elseif bp.id == "FenceGate4" then
				p:SetAttribute("Post", true)
			end
			if role == "Glass" then
				p.Transparency = if ghost then 0.45 else 0.4
			elseif ghost then
				p.Transparency = 0.45
			end
			p.CanCollide = not ghost
			p.CanTouch = not ghost
			p.CanQuery = not ghost
		elseif ghost then
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
	if bp.kit then
		KitMeshes.Dress(model, bp.id, ghost)
	else
		ItemMeshes.Attach(model, root, bp.id, ghost)
	end
	return model
end

-- An unfilled kit piece is a ghost: half see-through, no collision.
-- CanTouch stays on so a plank can still land on it.
function BlueprintModels.SetFaded(model: Model, faded: boolean)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Root" then
			local visual = child:GetAttribute("ItemVisual") == true
			if faded then
				if visual or child:GetAttribute("Role") ~= nil then
					child.Transparency = 0.5
				end
				child.CanCollide = false
			elseif child:GetAttribute("MeshOwnsCollision") == true then
				child.Transparency = 1
				child.CanCollide = false
			elseif visual then
				child.Transparency = if child:GetAttribute("Role") == "Glass" then 0.4 else 0
				child.CanCollide = false
			elseif child:GetAttribute("Collider") == true then
				child.Transparency = 1
				child.CanCollide = true
				child.CanTouch = true
				child.CanQuery = true
			elseif string.sub(child.Name, 1, 4) == "Part" then
				child.Transparency = if child:GetAttribute("Role") == "Glass" then 0.4 else 0
				child.CanCollide = true
				child.CanTouch = true
				child.CanQuery = true
			end
		end
	end
end

-- Paints wood parts with that wood's core. Glass, glow, signs, metal,
-- trim and anything else are left as authored.
function BlueprintModels.ApplyWood(model: Model, woodId: string?)
	if type(woodId) ~= "string" then
		return
	end
	local def = WoodData.Get(woodId)
	if not def then
		return
	end
	local color, material = TreeArt.Core(def)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("Role")
			if role == "Wood" or role == "Door" then
				child.Color = color
				child.Material = material
			end
		end
	end
end

-- Puts a built model at plot-local (x, y, z) with `rot` quarter turns.
function BlueprintModels.Place(model: Model, plotCFrame: CFrame, x: number, z: number, rot: number, y: number?)
	model:PivotTo(plotCFrame * CFrame.new(x, y or 0, z) * CFrame.Angles(0, rot * math.pi / 2, 0))
end

return BlueprintModels
