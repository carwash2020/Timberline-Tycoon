--!strict
-- MeshKit: one way to get a MeshPart. A script cannot set MeshPart.MeshId,
-- so this clones a Rojo template under ReplicatedStorage.MeshTemplates or
-- asks AssetService. Both sit in a pcall. meshId 0, a failed load, or a
-- test run with no override returns nil and the caller keeps its old parts.
-- Tests set Override to hand back a MeshPart without the engine.

local MeshKit = {}

export type OverrideFn = (meshId: number, name: string, size: Vector3) -> MeshPart?

MeshKit.Override = nil :: OverrideFn?

-- Looks-only: welded, no physics, and out of raycasts (TruckLoad, the sell
-- zone, the sawmill). WoodService.partsIn skips these.
function MeshKit.Visual(part: BasePart)
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part:SetAttribute("VisualMesh", true)
end

-- True when a part counts toward a gameplay budget (a section, a chassis).
function MeshKit.Counts(part: BasePart): boolean
	return part:GetAttribute("VisualMesh") ~= true
end

function MeshKit.Fidelity(part: MeshPart, name: Enum.RenderFidelity)
	pcall(function()
		part.RenderFidelity = name
	end)
end

local function finish(part: MeshPart, name: string, size: Vector3): MeshPart
	part.Name = name
	local native = part.Size
	local pivot = part.PivotOffset
	part.Size = size
	if native.X > 0.05 and native.Y > 0.05 and native.Z > 0.05 then
		local p = pivot.Position
		local scaled = Vector3.new(p.X * size.X / native.X, p.Y * size.Y / native.Y, p.Z * size.Z / native.Z)
		if scaled.Magnitude > 0.05 then
			part.PivotOffset = CFrame.new(scaled) * (pivot - p)
			part:SetAttribute("MeshPivot", "authored")
		end
	end
	return part
end

local function fromTemplate(meshId: number, name: string, size: Vector3): MeshPart?
	local ok, part = pcall(function(): MeshPart?
		local storage = game:GetService("ReplicatedStorage")
		local folder = storage:FindFirstChild("MeshTemplates")
		local template = if folder then folder:FindFirstChild(tostring(meshId)) else nil
		if not template or not template:IsA("MeshPart") then
			return nil
		end
		local clone = template:Clone()
		if not clone:IsA("MeshPart") then
			clone:Destroy()
			return nil
		end
		return finish(clone, name, size)
	end)
	if ok then
		return part
	end
	return nil
end

-- Lune has no AssetService. Remember that so every tree doesn't pay for the miss.
local noAssetService = false

local function fromAssetService(meshId: number, name: string, size: Vector3): MeshPart?
	if noAssetService then
		return nil
	end
	local ok, part = pcall(function(): MeshPart?
		local assetService = game:GetService("AssetService") :: any
		local uri = "rbxassetid://" .. tostring(meshId)
		local created: MeshPart? = nil
		local function take(value: any): MeshPart?
			if typeof(value) == "Instance" and value:IsA("MeshPart") then
				return value
			end
			return nil
		end
		local firstOk, first = pcall(function()
			return assetService:CreateMeshPartAsync((Content :: any).fromUri(uri))
		end)
		created = if firstOk then take(first) else nil
		if not created then
			local secondOk, second = pcall(function()
				return assetService:CreateMeshPartAsync(uri)
			end)
			created = if secondOk then take(second) else nil
		end
		if not created then
			return nil
		end
		return finish(created, name, size)
	end)
	if ok then
		return part
	end
	noAssetService = true
	return nil
end

-- A MeshPart named `name` at `size`, or nil. Never throws.
function MeshKit.Create(meshId: number, name: string, size: Vector3): MeshPart?
	if type(meshId) ~= "number" or meshId == 0 or meshId ~= meshId then
		return nil
	end
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return nil
	end
	local override = MeshKit.Override
	if override then
		local ok, part = pcall(override, meshId, name, size)
		if not ok or typeof(part) ~= "Instance" or not part:IsA("MeshPart") then
			return nil
		end
		part.Name = name
		part.Size = size
		return part
	end
	-- The engine's import pivot (CreateMeshPartAsync) beats a template,
	-- which only has the mesh id. The template is the fallback.
	local made = fromAssetService(meshId, name, size)
	if made then
		return made
	end
	return fromTemplate(meshId, name, size)
end

return MeshKit
