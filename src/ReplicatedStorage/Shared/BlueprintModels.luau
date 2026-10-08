--!strict
-- BlueprintModels: builds a blueprint's model from its PlotData boxes, for
-- the server (placed items) and the client (the ghost preview), so the two
-- always match. The model's pivot is its ground centre.
--
-- A kit piece with a loaded mesh hides the boxes that the mesh replaces.
-- DoorWall8 keeps two jambs. FenceGate4 keeps two posts. A door or gate
-- leaf is the only swinging collider. No mesh keeps the boxes as the look.

local CollectionService = game:GetService("CollectionService")

local EditLogic = require(script.Parent.EditLogic)
local ItemMeshes = require(script.Parent.ItemMeshes)
local KitPaint = require(script.Parent.KitPaint)
local KitMeshes = require(script.Parent.KitMeshes)
local LogicItems = require(script.Parent.LogicItems)
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
	local applyMeshes = (LogicItems :: any).ApplyMeshes
	if type(applyMeshes) == "function" then
		applyMeshes(model, bp.id, ghost)
	end
	local dress = (LogicItems :: any).Dress
	if type(dress) == "function" then
		dress(model, bp.id)
	end
	return model
end

-- An unfilled kit piece is a ghost: half see-through, no collision.
-- CanTouch stays on so a plank can still land on it.
function BlueprintModels.SetFaded(model: Model, faded: boolean)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Root" then
			-- The full-length fence collider stays invisible. The mesh it was
			-- cloned from stays hidden too; the tiles are the fence you see.
			if child:GetAttribute("Span") == true or child:GetAttribute("TileSource") == true then
				child.Transparency = 1
				child.CanCollide = child:GetAttribute("Span") == true and not faded
				child.CanTouch = child.CanCollide
				child.CanQuery = child.CanCollide
				continue
			end
			local visual = child:GetAttribute("ItemVisual") == true
			if faded then
				if visual or child:GetAttribute("Role") ~= nil then
					child.Transparency = 0.45
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
	local lantern = woodId == WoodData.LanternId
	if lantern then
		if not model:HasTag("Lanternwood") then
			model:AddTag("Lanternwood")
		end
		model:SetAttribute("NightHost", "plank")
		model:SetAttribute("WoodId", woodId)
	end
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("Role")
			if role == "Wood" or role == "Door" then
				child.Color = color
				child.Material = material
				if lantern then
					child:SetAttribute("NightGlow", true)
				end
			end
		end
	end
end

-- Covers a kit piece's wood, door and trim parts with a palette colour
-- (KitPaint). Glass and glow are left alone, and so is a piece with no paint:
-- it keeps the wood it was filled with. Run it after ApplyWood so paint wins.
-- Cosmetic only: it sets Color and Material and nothing else.
function BlueprintModels.ApplyPaint(model: Model, paintId: string?)
	local swatch = KitPaint.Get(paintId)
	if swatch == nil or swatch.id == KitPaint.Natural then
		return
	end
	local color = Color3.fromHex(swatch.color)
	local material = materialOf(KitPaint.Material)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") and KitPaint.TakesPaint(child:GetAttribute("Role")) then
			child.Color = color
			child.Material = material
			child:SetAttribute("NightGlow", nil) -- paint covers a Lanternwood glow
			child:SetAttribute("Painted", true)
		end
	end
end

-- Stretches a wall, beam or floor along its length. Height and thickness stay
-- put. A fence or railing is N copies, each len/N long, over one full-length
-- collider. The collider's Size is set to that box. It is not scaled from
-- whatever size it had. Door and gate swing boxes are not in here.
function BlueprintModels.ApplySize(model: Model, bp: PlotData.Blueprint, len: number?, lenX: number?, lenZ: number?)
	if not EditLogic.CanResize(bp.id) then
		return
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:GetAttribute("Tile") == true then
			child:Destroy()
		end
	end
	local probe = {
		uid = model.Name,
		blueprintId = bp.id,
		x = 0,
		z = 0,
		rot = 0,
		len = len,
		lenX = lenX,
		lenZ = lenZ,
	}
	local shaped = EditLogic.Shape(bp, probe)
	local box = shaped.boxes[1]
	if not box then
		return
	end
	local fullX = shaped.footprint.X
	local tiling = EditLogic.Tiled(bp.id)
	local tiles = if tiling then EditLogic.Tiles(fullX, bp.footprint.X) else 1
	local tileLen = fullX / tiles
	local template: BasePart? = nil
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Root" and child:GetAttribute("Tile") ~= true then
			local collider = child:GetAttribute("Collider") == true or child.Name == "Col"
			local partBox = string.sub(child.Name, 1, 4) == "Part"
			local visual = child:GetAttribute("ItemVisual") == true or child.Name == "Wood"
			if tiling and tiles == 1 then
				-- One copy, drawn at the new length. Height and thickness stay.
				if visual and not collider then
					child.Size = Vector3.new(fullX, child.Size.Y, child.Size.Z)
					child.CFrame = CFrame.new(box.offset.X, child.Position.Y, box.offset.Z)
				else
					child.Size = Vector3.new(fullX, box.size.Y, box.size.Z)
					child.CFrame = CFrame.new(box.offset)
				end
			elseif tiling and (collider or partBox) and not visual then
				child.Size = Vector3.new(fullX, box.size.Y, box.size.Z)
				child.CFrame = CFrame.new(box.offset)
				child.Transparency = 1
				child.CanCollide = true
				child.CanTouch = true
				child.CanQuery = true
				child:SetAttribute("Collider", true)
				child:SetAttribute("Span", true)
			elseif tiling and visual then
				if template == nil then
					template = child
				end
				child:SetAttribute("TileSource", true)
				child.Transparency = 1
				child.CanCollide = false
			elseif not tiling then
				if visual and not collider then
					local thick = if bp.id == "Floor" or bp.id == "Floor4" then shaped.footprint.Y else child.Size.Z
					child.Size = Vector3.new(fullX, child.Size.Y, thick)
					local pos = child.Position
					child.CFrame = CFrame.new(box.offset.X, pos.Y, box.offset.Z)
				else
					local match = box
					local index = tonumber(string.sub(child.Name, 5))
					if index and shaped.boxes[index] then
						match = shaped.boxes[index]
					end
					child.Size = match.size
					child.CFrame = CFrame.new(match.offset)
				end
			end
		end
	end
	if tiles <= 1 then
		return
	end
	if template == nil then
		local part = model:FindFirstChild("Part1")
		if part and part:IsA("BasePart") then
			template = part
		end
	end
	if not template then
		return
	end
	for i = 1, tiles do
		local tile = template:Clone()
		tile.Name = "Tile" .. tostring(i)
		tile:SetAttribute("Tile", true)
		tile:SetAttribute("Span", nil)
		tile:SetAttribute("TileSource", nil)
		tile:SetAttribute("Collider", nil)
		tile:SetAttribute("MeshOwnsCollision", nil)
		tile:SetAttribute("Role", "Wood")
		tile:SetAttribute("ItemVisual", true)
		tile.Size = Vector3.new(tileLen, box.size.Y, box.size.Z)
		local x = -fullX / 2 + tileLen * (i - 0.5)
		tile.CFrame = CFrame.new(x, box.offset.Y, box.offset.Z)
		tile.Transparency = 0
		tile.CanCollide = false
		tile.CanTouch = false
		tile.CanQuery = false
		tile.Parent = model
	end
end

function BlueprintModels.Place(model: Model, plotCFrame: CFrame, x: number, z: number, rot: number, y: number?)
	model:PivotTo(plotCFrame * CFrame.new(x, y or 0, z) * CFrame.Angles(0, rot * math.pi / 2, 0))
end

return BlueprintModels
