--!strict
-- MeshKit: one way to get a MeshPart. A script cannot set MeshPart.MeshId,
-- so this clones a Rojo template under ReplicatedStorage.MeshTemplates or
-- asks AssetService. Both sit in a pcall. meshId 0, a failed load, or a
-- test run with no override returns nil and the caller keeps its old parts.
-- Tests set Override to hand back a MeshPart without the engine.
--
-- Failures are never silent: the first few are warned with the engine's own
-- error text, and MeshKit.Stats / MeshKit.Report give the totals (MapBuilder
-- prints them in the build check). The usual cause is asset permission: a
-- mesh only loads for an experience its owner allows (see PHASE2_NOTES.md,
-- "Creator Hub: mesh permissions"). A load is retried once; after
-- BlockAfter failures in a row with not one success, the kit stops asking
-- (each miss is slow) and says so once.
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

-- Load accounting (engine path only; an Override never counts).
local loadedCount = 0
local failedCount = 0
local failStreak = 0
local blocked = false
local firstError: string? = nil
local failedIds: { number } = {}
local WARN_LIMIT = 5
MeshKit.BlockAfter = 8 -- failures in a row, none ever loaded, before giving up
MeshKit.Retries = 1 -- extra tries after a failed load, only until one has loaded

export type Stats = {
	loaded: number,
	failed: number,
	blocked: boolean,
	firstError: string?,
	failedIds: { number },
}

function MeshKit.Stats(): Stats
	return {
		loaded = loadedCount,
		failed = failedCount,
		blocked = blocked,
		firstError = firstError,
		failedIds = failedIds,
	}
end

-- One line for the build check.
function MeshKit.Report(): string
	if noAssetService and loadedCount == 0 and failedCount == 0 then
		return "no AssetService here, part-built art"
	end
	local line = string.format("%d mesh assets loaded, %d failed", loadedCount, failedCount)
	if failedCount > 0 then
		line ..= " (first error: " .. tostring(firstError) .. ")"
		if blocked then
			line ..= "; gave up after " .. tostring(MeshKit.BlockAfter) .. " misses in a row: check asset permissions"
		end
	end
	return line
end

local PERMISSION_HELP = "Creator Hub > Creations > Assets: open each asset, Permissions, and allow this experience"
	.. " (and open Studio as the account that owns the assets). See PHASE2_NOTES.md."

local function noteFailure(meshId: number, err: string)
	failedCount += 1
	failStreak += 1
	table.insert(failedIds, meshId)
	if firstError == nil then
		firstError = err
	end
	if failedCount <= WARN_LIMIT then
		warn(string.format("[MeshKit] mesh %d did not load (%s). %s", meshId, err, PERMISSION_HELP))
	end
	if loadedCount == 0 and failStreak >= MeshKit.BlockAfter and not blocked then
		blocked = true
		warn(
			string.format(
				"[MeshKit] %d meshes in a row failed and none has loaded: no more tries this server."
					.. " Everything stays part-built. %s",
				failStreak,
				PERMISSION_HELP
			)
		)
	end
end

local function noteSuccess()
	loadedCount += 1
	failStreak = 0
end

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
	loadedCount = 0
	failedCount = 0
	failStreak = 0
	blocked = false
	firstError = nil
	table.clear(failedIds)
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

-- (part, nil) or (nil, why). `why` is the engine's own error text.
local function fromAssetService(meshId: number, collision: Enum.CollisionFidelity): (MeshPart?, string?)
	if noAssetService then
		return nil, "no AssetService"
	end
	local okService, assetService = pcall(function()
		return game:GetService("AssetService")
	end)
	if not okService or assetService == nil then
		noAssetService = true
		return nil, "no AssetService"
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
	local why: string? = nil
	local firstOk, first = pcall(function()
		return (assetService :: any):CreateMeshPartAsync((Content :: any).fromUri(uri), options)
	end)
	local created = if firstOk then take(first) else nil
	if not firstOk then
		why = tostring(first)
	end
	if not created then
		local secondOk, second = pcall(function()
			return (assetService :: any):CreateMeshPartAsync(uri, collision, Enum.RenderFidelity.Automatic)
		end)
		created = if secondOk then take(second) else nil
		if not secondOk and why == nil then
			why = tostring(second)
		end
	end
	if created then
		return created, nil
	end
	return nil, why or "no mesh came back"
end

-- Loads with a retry (a busy moment is not a permission problem). The
-- retries stop once any mesh has loaded: a miss after that is this id.
local function load(meshId: number, collision: Enum.CollisionFidelity): MeshPart?
	if blocked then
		return nil
	end
	local made, why = fromAssetService(meshId, collision)
	local tries = 0
	while not made and why ~= "no AssetService" and loadedCount == 0 and tries < MeshKit.Retries do
		tries += 1
		pcall(function()
			task.wait(0.5)
		end)
		made, why = fromAssetService(meshId, collision)
	end
	if made then
		noteSuccess()
		return made
	end
	local template = fromTemplate(meshId)
	if template then
		noteSuccess()
		return template
	end
	if why ~= "no AssetService" then
		noteFailure(meshId, tostring(why))
	end
	return nil
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
	local made = load(meshId, fidelity)
	if not made then
		failed[meshId] = true
		return nil
	end
	remember(meshId, made)
	return finish(made:Clone(), name, size, fidelity)
end

return MeshKit
