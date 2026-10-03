--!strict
-- MeshKit: one way to get a MeshPart. A script cannot set MeshPart.MeshId,
-- so this clones a Rojo template under ReplicatedStorage.MeshTemplates or
-- asks AssetService. Both sit in a pcall. meshId 0, a failed load, or a
-- test run with no override returns nil and the caller keeps its old parts.
-- Tests set Override to hand back a MeshPart without the engine.
--
-- Each meshId is loaded once per server. Later uses clone that MeshPart.
-- A failed id is remembered and not tried again; the caller keeps the
-- part-built model. Collision is Box unless the caller passes Hull
-- (a wheel, or any shape a box would misrepresent).

local MeshKit = {}

export type OverrideFn = (meshId: number, name: string, size: Vector3) -> MeshPart?

MeshKit.Override = nil :: OverrideFn?

-- One loaded MeshPart per meshId, and ids that already failed.
local masters: { [number]: MeshPart } = {}
local failed: { [number]: boolean } = {}

-- Lune has no AssetService. Remember that so every tree doesn't pay for the miss.
local noAssetService = false

-- Looks-only. Ticket I uses this same helper. CanCollide, CanTouch and
-- CanQuery are off, and the part is Massless, so it stays out of raycasts
-- (TruckLoad, the sell zone, the sawmill). WoodService.partsIn skips these.
-- meshId is stored as text: a number attribute truncates ids this large.
function MeshKit.Visual(part: BasePart, meshId: number)
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part:SetAttribute("VisualMesh", true)
	if type(meshId) == "number" and meshId == meshId and meshId ~= 0 then
		part:SetAttribute("MeshId", tostring(meshId))
	end
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

-- Drops the load cache. Tests call this so one spec does not count as the server.
function MeshKit.Reset()
	for _, part in pairs(masters) do
		part:Destroy()
	end
	table.clear(masters)
	table.clear(failed)
end

local function finish(part: MeshPart, name: string, size: Vector3, collision: Enum.CollisionFidelity): MeshPart
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
	pcall(function()
		part.CollisionFidelity = collision
	end)
	return part
end

local function fromTemplate(meshId: number): MeshPart?
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
		return clone
	end)
	if ok then
		return part
	end
	return nil
end

local function fromAssetService(meshId: number, collision: Enum.CollisionFidelity): MeshPart?
	if noAssetService then
		return nil
	end
	local okService, assetService = pcall(function()
		return game:GetService("AssetService")
	end)
	if not okService or assetService == nil then
		noAssetService = true
		return nil
	end
	local uri = "rbxassetid://" .. tostring(meshId)
	local options = {
		CollisionFidelity = collision,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	}
	local function take(value: any): MeshPart?
		if typeof(value) == "Instance" and value:IsA("MeshPart") then
			return value
		end
		return nil
	end
	local firstOk, first = pcall(function()
		return (assetService :: any):CreateMeshPartAsync((Content :: any).fromUri(uri), options)
	end)
	local created = if firstOk then take(first) else nil
	if not created then
		local secondOk, second = pcall(function()
			return (assetService :: any):CreateMeshPartAsync(uri, collision, Enum.RenderFidelity.Automatic)
		end)
		created = if secondOk then take(second) else nil
	end
	return created
end

local function remember(meshId: number, part: MeshPart)
	part.Name = "MeshCache"
	masters[meshId] = part
end

-- A MeshPart named `name` at `size`, or nil. Never throws.
-- `collision` defaults to Box. Pass Hull for a shape a box would get wrong.
function MeshKit.Create(meshId: number, name: string, size: Vector3, collision: Enum.CollisionFidelity?): MeshPart?
	if type(meshId) ~= "number" or meshId == 0 or meshId ~= meshId then
		return nil
	end
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return nil
	end
	if failed[meshId] then
		return nil
	end
	local fidelity = collision or Enum.CollisionFidelity.Box
	local master = masters[meshId]
	if master then
		return finish(master:Clone(), name, size, fidelity)
	end

	local override = MeshKit.Override
	if override then
		local ok, part = pcall(override, meshId, name, size)
		if not ok or typeof(part) ~= "Instance" or not part:IsA("MeshPart") then
			failed[meshId] = true
			return nil
		end
		remember(meshId, part)
		return finish(part:Clone(), name, size, fidelity)
	end

	-- The engine's import pivot (CreateMeshPartAsync) beats a template,
	-- which only has the mesh id. The template is the fallback.
	local made = fromAssetService(meshId, fidelity) or fromTemplate(meshId)
	if not made then
		failed[meshId] = true
		return nil
	end
	remember(meshId, made)
	return finish(made:Clone(), name, size, fidelity)
end

return MeshKit
