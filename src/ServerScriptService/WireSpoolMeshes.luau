--!strict
-- WireSpoolMeshes (T420): loads the wire spool's uploaded Model once, at boot,
-- with InsertService:LoadAsset inside pcall with retries, and keeps the five
-- MeshPart templates (Band, Coil, FlangeLeft, FlangeRight, Hub) for
-- WireArt.Build to clone. Each template's Size is the mesh's InitialSize / 100
-- (the engine reports it 100 times too big, in cm). The ids are in
-- WireArt.Config and nowhere else.
-- A load that fails (offline, not approved for this experience) is warned
-- once, and the spool is simply not shown: never a stand-in built from parts.
-- This is the second file allowed to use InsertService (the first is
-- StumpMeshes); the map build path may not (tests/BuildBudget).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WireArt = require(ReplicatedStorage.Shared.Art.WireArt)

local WireSpoolMeshes = {}

WireSpoolMeshes.Attempts = 4 -- LoadAsset tries before the spool is given up on
WireSpoolMeshes.RetryDelay = 2 -- seconds before the second try, doubling after that
WireSpoolMeshes.Loads = 0 -- LoadAsset calls made (specs)

-- Replaced by specs.
WireSpoolMeshes.LoadModel = function(id: number): Instance?
	local service = game:GetService("InsertService") :: InsertService
	return service:LoadAsset(id)
end
WireSpoolMeshes.Wait = function(seconds: number)
	task.wait(seconds)
end

local state = "idle" -- idle | loading | ready | failed
local templates: { [string]: MeshPart }? = nil
local waiting: { ({ [string]: MeshPart }?) -> () } = {}
local why = ""

local function meshNamed(root: Instance, name: string): MeshPart?
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name and d:IsA("MeshPart") then
			return d
		end
	end
	if root.Name == name and root:IsA("MeshPart") then
		return root
	end
	return nil
end

-- The five templates from a loaded model, or nil and why. Pure of the engine's
-- loader (the cloud check and the specs call it with a model they hold).
function WireSpoolMeshes.Extract(model: Instance): ({ [string]: MeshPart }?, string)
	local out: { [string]: MeshPart } = {}
	for _, piece in ipairs(WireArt.Config.Pieces) do
		local mesh = meshNamed(model, piece.name)
		if mesh == nil then
			return nil, "no MeshPart named " .. piece.name .. " in model " .. tostring(WireArt.Config.ModelId)
		end
		local template = mesh:Clone()
		template:ClearAllChildren()
		local initial: Vector3? = nil
		pcall(function()
			initial = (mesh :: any).InitialSize -- (not in the type definitions)
		end)
		template.Size = WireArt.ScaledSize(initial, piece.size)
		local expected = "rbxassetid://" .. tostring(piece.meshId)
		if template.MeshId ~= expected then
			warn(string.format("[WireSpool] %s has MeshId %s, expected %s", piece.name, template.MeshId, expected))
		end
		out[piece.name] = template
	end
	return out, ""
end

local function finish(result: { [string]: MeshPart }?, reason: string)
	templates = result
	state = if result then "ready" else "failed"
	why = reason
	local list = waiting
	waiting = {}
	for _, fn in ipairs(list) do
		local ok, err = pcall(function(): any
			fn(result)
			return nil
		end)
		if not ok then
			warn("[WireSpool] a waiting spool failed: " .. tostring(err))
		end
	end
end

-- Loads the model (blocks the calling thread through the retries); runs once.
function WireSpoolMeshes.Load()
	if state ~= "idle" then
		return
	end
	state = "loading"
	local reason = "not tried"
	local delay = WireSpoolMeshes.RetryDelay
	for attempt = 1, WireSpoolMeshes.Attempts do
		WireSpoolMeshes.Loads += 1
		local ok, model = pcall(WireSpoolMeshes.LoadModel, WireArt.Config.ModelId)
		if ok and model then
			local got, missing = WireSpoolMeshes.Extract(model :: Instance)
			if got then
				finish(got, "")
				return
			end
			reason = missing
			break -- the model loaded but is not the spool: trying again will not change that
		end
		reason = tostring(if ok then "no model came back" else model)
		if attempt < WireSpoolMeshes.Attempts then
			WireSpoolMeshes.Wait(delay)
			delay *= 2
		end
	end
	warn(
		string.format(
			"[WireSpool] model %d did not load (%s); the spool is not shown, wiring still works",
			WireArt.Config.ModelId,
			reason
		)
	)
	finish(nil, reason)
end

-- Server start: the one load, on its own thread. Safe to call twice.
function WireSpoolMeshes.Init()
	if state ~= "idle" then
		return
	end
	task.spawn(WireSpoolMeshes.Load)
end

-- The five templates when they are here, else nil.
function WireSpoolMeshes.Get(): { [string]: MeshPart }?
	return templates
end

function WireSpoolMeshes.State(): string
	return state
end

function WireSpoolMeshes.Why(): string
	return why
end

-- Calls `fn` with the templates (nil when the load failed): at once when it has
-- answered, else when it does.
function WireSpoolMeshes.OnReady(fn: ({ [string]: MeshPart }?) -> ())
	if state == "ready" or state == "failed" then
		fn(templates)
		return
	end
	table.insert(waiting, fn)
	if state == "idle" then
		WireSpoolMeshes.Init()
	end
end

-- For the cloud test (a real InsertService; it yields): loads the model afresh and checks
-- it is the spool: five named MeshParts with the listed MeshIds whose InitialSize / 100 is the listed
-- size, and whose assembled bounding box is the spool's. Returns the failure lines (empty = pass).
function WireSpoolMeshes.CloudCheck(): ({ string }, number)
	local failures: { string } = {}
	local ok, model = pcall(WireSpoolMeshes.LoadModel, WireArt.Config.ModelId)
	if not ok or not model then
		table.insert(
			failures,
			string.format("[WireSpool] model %d did not load: %s", WireArt.Config.ModelId, tostring(model))
		)
		return failures, 1
	end
	local got, missing = WireSpoolMeshes.Extract(model :: Instance)
	if not got then
		table.insert(failures, "[WireSpool] " .. missing)
		return failures, 1
	end
	for _, piece in ipairs(WireArt.Config.Pieces) do
		local mesh = got[piece.name] :: MeshPart
		if mesh.MeshId ~= "rbxassetid://" .. tostring(piece.meshId) then
			table.insert(failures, string.format("[WireSpool] %s has MeshId %s", piece.name, mesh.MeshId))
		end
		if (mesh.Size - piece.size).Magnitude > 0.05 then
			table.insert(
				failures,
				string.format(
					"[WireSpool] %s is %s studs (InitialSize / 100), the spool lists %s",
					piece.name,
					tostring(mesh.Size),
					tostring(piece.size)
				)
			)
		end
	end
	local spool = WireArt.Build(got)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(spool:GetDescendants()) do
		if d:IsA("MeshPart") then
			local h = d.Size / 2
			lo = Vector3.new(
				math.min(lo.X, d.Position.X - h.X),
				math.min(lo.Y, d.Position.Y - h.Y),
				math.min(lo.Z, d.Position.Z - h.Z)
			)
			hi = Vector3.new(
				math.max(hi.X, d.Position.X + h.X),
				math.max(hi.Y, d.Position.Y + h.Y),
				math.max(hi.Z, d.Position.Z + h.Z)
			)
		end
	end
	if ((hi - lo) - WireArt.Config.Bounds).Magnitude > 0.1 then
		table.insert(
			failures,
			string.format(
				"[WireSpool] assembled box is %s, expected %s",
				tostring(hi - lo),
				tostring(WireArt.Config.Bounds)
			)
		)
	end
	spool:Destroy()
	return failures, 1
end

-- For the specs.
function WireSpoolMeshes._reset()
	state = "idle"
	templates = nil
	waiting = {}
	why = ""
	WireSpoolMeshes.Loads = 0
end

return WireSpoolMeshes
