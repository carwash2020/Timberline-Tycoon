--!strict
-- BlueprintModels: builds a blueprint's model from its PlotData boxes, for
-- the server (placed items) and the client (the ghost preview), so the two
-- always match. The model's pivot is its ground centre.
--
-- A kit piece with a loaded mesh hides the boxes that the mesh replaces.
-- DoorWall8 keeps two jambs. FenceGate4 keeps two posts. A door or gate
-- leaf is the only swinging collider. No mesh keeps the boxes as the look.
--
-- The GHOST (ghost = true: the placer's preview) is never dressed. It is the
-- blueprint's own boxes, every one visible, no mesh, no extra part, then
-- Hologram(). A PLACED blueprint is Build(bp, false): the same boxes plus the
-- meshes; while it holds no material (FillUnits 0) SetFaded turns it into the
-- same hologram, and the first material puts the real wood back.

local CollectionService = game:GetService("CollectionService")

local EditLogic = require(script.Parent.EditLogic)
local ItemMeshes = require(script.Parent.ItemMeshes)
local KitPaint = require(script.Parent.KitPaint)
local KitMeshes = require(script.Parent.KitMeshes)
local LogicItems = require(script.Parent.LogicItems)
local ModelSlots = require(script.Parent.Art.ModelSlots)
local Palette = require(script.Parent.Art.Palette)
local PlotData = require(script.Parent.PlotData)
local StoreModelArt = require(script.Parent.Art.StoreModelArt)
local TreeArt = require(script.Parent.Art.TreeArt)
local WoodData = require(script.Parent.WoodData)

local BlueprintModels = {}

-- The hologram look (UITheme.Colors carries the same three hex values; a spec
-- keeps them equal). Shared code cannot read UITheme, so they live here too.
BlueprintModels.HoloColor = Color3.fromHex("#4FA8FF") -- BlueprintBlue
BlueprintModels.HoloEdge = Color3.fromHex("#CFE8FF") -- BlueprintEdge
BlueprintModels.HoloBad = Color3.fromHex("#FF5A4F") -- BlueprintBad
BlueprintModels.HoloTransparency = 0.6
BlueprintModels.HoloFill = 0.75

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
	if ghost then
		model:SetAttribute("Ghost", true)
	end
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
		-- Furniture: parts under one stud cast no shadow (a lamp's bolt, a lock).
		if bp.category == "Decor" and math.min(box.size.X, box.size.Y, box.size.Z) < 1 then
			p.CastShadow = false
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
	if ghost then
		-- The ghost is the boxes and nothing else (no KitMeshes, ItemMeshes,
		-- model slot, shop model or logic dressing), so it always shows the
		-- whole blueprint.
		BlueprintModels.Hologram(model)
		return model
	end
	if bp.kit then
		KitMeshes.Dress(model, bp.id, false)
	else
		ItemMeshes.Attach(model, root, bp.id, false)
	end
	-- The Wood Sign has a model slot (Art/ModelSlots): with a real model set it stands here, the boxes
	-- stay as the (invisible) collider; meshId 0 keeps the part-built look. (The Shed's model is the
	-- plan you carry, not the shed you build: its ghost stays part-built.)
	local slot = ModelSlots.For("Blueprint", bp.id)
	if slot and slot.placedAs == "plot" then
		local options: ModelSlots.DressOptions = {
			weldTo = root :: BasePart,
			onDressed = function(mesh: MeshPart)
				mesh:SetAttribute("ItemVisual", true)
				mesh:SetAttribute("Role", "Prop")
				mesh.Transparency = 0
				for _, child in ipairs(model:GetChildren()) do
					if child:IsA("BasePart") and string.sub(child.Name, 1, 4) == "Part" then
						child:SetAttribute("Role", nil)
						child:SetAttribute("Collider", true)
						child.Transparency = 1
					end
				end
			end,
		}
		ModelSlots.Dress(model, slot, CFrame.new(0, slot.size.Y / 2, 0), "placed", options)
	end
	-- The item's one model slot (StoreModelSlots): the same model the shop box shows.
	-- No mesh id yet, or a mesh still loading, keeps the boxes above as the look.
	if not bp.kit then
		StoreModelArt.DressPlaced(model, root, bp.id, false)
	end
	local applyMeshes = (LogicItems :: any).ApplyMeshes
	if type(applyMeshes) == "function" then
		applyMeshes(model, bp.id, false)
	end
	local dress = (LogicItems :: any).Dress
	if type(dress) == "function" then
		dress(model, bp.id)
	end
	return model
end

-- The blue hologram: every visible part becomes BlueprintBlue SmoothPlastic at
-- Transparency 0.6 with no shadow, plus one Highlight (Fill blue 0.75, Outline
-- the pale edge, Occluded). Used by the ghost and by a placed blueprint that
-- holds no material yet. It changes looks only: a ghost (attribute Ghost) is
-- also made non-colliding; a placed model's collision is never touched here.
-- The look each part had is kept in Holo* attributes so SetFaded can put it
-- back when the first material goes in (a part ApplyWood or ApplyPaint
-- repaints while it is a hologram updates those, not the blue).
local HOLO_NAME = "Hologram"

local function holoSkips(part: BasePart): boolean
	return part.Name == "Root" or part.Transparency >= 1
end

function BlueprintModels.Hologram(model: Model)
	local ghost = model:GetAttribute("Ghost") == true
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not holoSkips(d) then
			if d:GetAttribute("Holo") ~= true then
				d:SetAttribute("Holo", true)
				d:SetAttribute("HoloColor", d.Color)
				d:SetAttribute("HoloMaterial", d.Material.Name)
				d:SetAttribute("HoloCast", d.CastShadow)
			end
			d.Color = BlueprintModels.HoloColor
			d.Material = Enum.Material.SmoothPlastic
			d.Transparency = BlueprintModels.HoloTransparency
			d.CastShadow = false
			if ghost then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
	end
	local found = model:FindFirstChild(HOLO_NAME)
	local hl: Highlight
	if found and found:IsA("Highlight") then
		hl = found
	else
		hl = Instance.new("Highlight")
		hl.Name = HOLO_NAME
		hl.Parent = model
	end
	hl.FillColor = BlueprintModels.HoloColor
	hl.FillTransparency = BlueprintModels.HoloFill
	hl.OutlineColor = BlueprintModels.HoloEdge
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
end

-- The ghost's verdict: blue where it can go, BlueprintBad where it cannot
-- (parts and Highlight). Never green.
function BlueprintModels.HologramTint(model: Model, valid: boolean)
	local color = if valid then BlueprintModels.HoloColor else BlueprintModels.HoloBad
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Holo") == true then
			d.Color = color
		end
	end
	local light = model:FindFirstChild(HOLO_NAME)
	if light and light:IsA("Highlight") then
		light.FillColor = color
		light.OutlineColor = if valid then BlueprintModels.HoloEdge else BlueprintModels.HoloBad
	end
end

-- Puts back what Hologram changed (Color, Material, shadow). Transparency is
-- SetFaded's own.
local function release(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Holo") == true then
			local color = d:GetAttribute("HoloColor")
			if typeof(color) == "Color3" then
				d.Color = color
			end
			d.Material = materialOf(tostring(d:GetAttribute("HoloMaterial")))
			d.CastShadow = d:GetAttribute("HoloCast") ~= false
			d:SetAttribute("Holo", nil)
			d:SetAttribute("HoloColor", nil)
			d:SetAttribute("HoloMaterial", nil)
			d:SetAttribute("HoloCast", nil)
		end
	end
	local light = model:FindFirstChild(HOLO_NAME)
	if light and light:IsA("Highlight") then
		light:Destroy()
	end
end

-- Repaints a part; while it is a hologram the blue stays and the new look is
-- kept for when the hologram goes.
local function setLook(part: BasePart, color: Color3, material: Enum.Material)
	if part:GetAttribute("Holo") == true then
		part:SetAttribute("HoloColor", color)
		part:SetAttribute("HoloMaterial", material.Name)
	else
		part.Color = color
		part.Material = material
	end
end

-- An unfilled kit piece is a ghost: half see-through, no collision.
-- CanTouch stays on so a plank can still land on it. While it holds nothing
-- (FillUnits 0 or not set) it is the blue hologram; with any material in, it
-- is faded real wood, and with the last unit in it is solid.
function BlueprintModels.SetFaded(model: Model, faded: boolean)
	local holo = faded and ((model:GetAttribute("FillUnits") :: number?) or 0) == 0
	if not holo then
		release(model)
	end
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
	if holo then
		BlueprintModels.Hologram(model)
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
	-- An effect wood (WoodData.Effect): its Door parts take the accent colour,
	-- and are marked NightGlow only when the wood's glow is neon. It sets only
	-- the tag, WoodId, NightGlow, Color and Material: no light, no part.
	local effect = WoodData.EffectOf(woodId)
	local accent: Color3? = nil
	if effect and effect.accent then
		accent = Palette.Get(effect.accent)
	end
	if lantern then
		if not model:HasTag("Lanternwood") then
			model:AddTag("Lanternwood")
		end
		model:SetAttribute("NightHost", "plank")
		model:SetAttribute("WoodId", woodId)
	elseif effect then
		if not model:HasTag("WoodEffect") then
			model:AddTag("WoodEffect")
		end
		model:SetAttribute("NightHost", "plank")
		model:SetAttribute("WoodId", woodId)
	end
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("Role")
			if role == "Wood" or role == "Door" then
				local paint = color
				if effect and role == "Door" and not lantern and accent then
					paint = accent
				end
				setLook(child, paint, material)
				if lantern then
					child:SetAttribute("NightGlow", true)
				elseif effect and role == "Door" then
					if effect.neon then
						child:SetAttribute("NightGlow", true)
					end
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
			setLook(child, color, material)
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
					child.CFrame = CFrame.new(box.offset.X, child.CFrame.Y, box.offset.Z)
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
					local pos = child.CFrame.Position
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
