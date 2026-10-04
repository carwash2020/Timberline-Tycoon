--!strict
-- ItemMeshes: visual meshes for plot pieces. MeshId cannot be set while
-- the game is running, so the server builds a template once with
-- AssetService:CreateMeshPartAsync (inside pcall) and everyone else clones
-- it. A missing or failed mesh leaves the gameplay parts as they are.
-- Visuals are massless and do not collide, touch, or query. They are not
-- wood, so they never count toward a wood part cap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemMeshData = require(script.Parent.ItemMeshData)

export type ShellOpts = {
	scaleX: number?, -- stretch a rail along its length
	yaw: number?, -- radians, applied before the host offset
	color: Color3?, -- PlotRail claimed/free tint
	hostOffset: CFrame?, -- mesh pivot relative to the host part
}

local ItemMeshes = {}

ItemMeshes.FolderName = "ItemMeshTemplates"
ItemMeshes.VisualName = "ItemVisual"

local cache: { [string]: Model } = {}

local function folder(): Folder?
	local found = ReplicatedStorage:FindFirstChild(ItemMeshes.FolderName)
	if found and found:IsA("Folder") then
		return found
	end
	return nil
end

function ItemMeshes.Template(id: string): Model?
	local cached = cache[id]
	if cached then
		return cached
	end
	local box = folder()
	local inst = if box then box:FindFirstChild(id) else nil
	if inst and inst:IsA("Model") then
		cache[id] = inst
		return inst
	end
	return nil
end

-- Tests install a stand-in. Passing nil forgets one id; no args forgets all.
function ItemMeshes.Install(id: string?, model: Model?)
	if id == nil then
		table.clear(cache)
		return
	end
	cache[id] = model :: Model
end

local function style(part: BasePart, role: ItemMeshData.MeshRole, ghost: boolean)
	part.Color = Color3.new(1, 1, 1)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part:SetAttribute("Role", role)
	part:SetAttribute(ItemMeshes.VisualName, true)
	if role == "Glass" then
		part.Material = Enum.Material.Glass
		part.Transparency = if ghost then 0.45 else 0.4
	elseif role == "Glow" then
		part.Material = Enum.Material.Neon
		part.Transparency = if ghost then 0.45 else 0
	elseif role == "Flag" then
		part.Material = Enum.Material.Fabric
		part.Transparency = if ghost then 0.45 else 0
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = if ghost then 0.45 else 0
	end
end

local function weld(host: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Name = "MeshWeld"
	w.Part0 = host
	w.Part1 = part
	w.Parent = part
end

-- Clones `id`'s visible meshes onto `model`, welded to `host` (the gameplay
-- root). Returns how many meshes were added. Zero means "keep the old parts".
function ItemMeshes.Attach(model: Model, host: BasePart, id: string, ghost: boolean): number
	local template = ItemMeshes.Template(id)
	local defs = ItemMeshData.List(id)
	if not template or #defs == 0 then
		return 0
	end
	local added = 0
	for _, def in ipairs(defs) do
		local src = template:FindFirstChild(def.name)
		if src and src:IsA("BasePart") and src.Name ~= "Collision" then
			local part = src:Clone()
			part.Name = def.name
			part.Size = def.size
			style(part, def.role, ghost)
			part:PivotTo(CFrame.new(0, 0, 0))
			part.Parent = model
			weld(host, part)
			added += 1
		end
	end
	if added == 0 then
		return 0
	end
	-- Gameplay boxes stay as the collider and go invisible. Root stays as it was.
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child ~= host and child:GetAttribute(ItemMeshes.VisualName) ~= true then
			child.Transparency = 1
		end
	end
	-- The lamp's light rides the glowing glass, not the hidden box.
	local glow = model:FindFirstChild("Glow")
	if glow then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				local light = child:FindFirstChildOfClass("PointLight")
				if light and light.Parent ~= glow then
					light.Parent = glow
				end
			end
		end
	end
	return added
end

-- One mesh welded to an existing plot-shell part (rail, corner, sign board).
-- The host stays the collider (or the prompt). Returns false if there is no mesh.
function ItemMeshes.AttachTo(host: BasePart, id: string, opts: ShellOpts?): boolean
	local template = ItemMeshes.Template(id)
	local defs = ItemMeshData.List(id)
	if not template or #defs == 0 then
		return false
	end
	local scaleX = if opts then opts.scaleX else nil
	local yaw = if opts then opts.yaw else nil
	local tint = if opts then opts.color else nil
	local hostOffset = if opts then opts.hostOffset else nil
	local parent = host.Parent
	if not parent then
		return false
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute(ItemMeshes.VisualName) == true then
			local existing = child:FindFirstChild("MeshWeld")
			if existing and existing:IsA("WeldConstraint") and existing.Part0 == host then
				child:Destroy()
			end
		end
	end
	local added = 0
	for _, def in ipairs(defs) do
		local src = template:FindFirstChild(def.name)
		if src and src:IsA("BasePart") and src.Name ~= "Collision" then
			local part = src:Clone()
			part.Name = def.name
			local size = def.size
			if scaleX and def.name == "Body" then
				size = Vector3.new(scaleX, size.Y, size.Z)
			end
			part.Size = size
			style(part, def.role, false)
			if tint and id == "PlotRail" then
				part.Color = tint
			end
			local spin = CFrame.Angles(0, yaw or 0, 0)
			local offset = hostOffset or CFrame.identity
			part:PivotTo(host.CFrame * offset * spin)
			part.Parent = parent
			weld(host, part)
			added += 1
		end
	end
	if added == 0 then
		return false
	end
	host.Transparency = 1
	return true
end

-- Builds templates under ReplicatedStorage. A failed mesh is skipped and
-- that item keeps its parts. Safe to call when AssetService cannot create meshes.
function ItemMeshes.LoadAsync()
	local ok, service = pcall(function()
		return game:GetService("AssetService")
	end)
	if not ok or service == nil or type((service :: any).CreateMeshPartAsync) ~= "function" then
		return
	end
	local box = folder()
	if not box then
		local created = Instance.new("Folder")
		created.Name = ItemMeshes.FolderName
		created.Parent = ReplicatedStorage
		box = created
	end
	for id, defs in pairs(ItemMeshData.Items) do
		if ItemMeshes.Template(id) then
			continue
		end
		local model = Instance.new("Model")
		model.Name = id
		local good = true
		for _, def in ipairs(defs) do
			local createdOk, part = pcall(function()
				-- MeshId cannot be assigned on a live MeshPart. CreateMeshPartAsync
				-- is the supported way; the string overload is the one this
				-- toolchain's types still describe.
				local asset = service :: any
				return asset:CreateMeshPartAsync(
					def.meshId,
					Enum.CollisionFidelity.Box,
					Enum.RenderFidelity.Performance
				)
			end)
			if not createdOk or typeof(part) ~= "Instance" then
				good = false
				break
			end
			local mesh = part :: MeshPart
			mesh.Name = def.name
			mesh.Size = def.size
			mesh.Parent = model
		end
		if good and #model:GetChildren() > 0 then
			model.Parent = box
			cache[id] = model
		else
			model:Destroy()
		end
	end
end

return ItemMeshes
