--!strict
-- StumpMeshes (T420): loads the 16 stump frustum meshes (Shared/StumpMeshIds)
-- on the server with InsertService:LoadAsset, once per id, and hands out the
-- cached MeshPart template (CollisionFidelity Hull) for TreeArt.StumpDress to
-- clone. Loads run in the background (Request), never inside a swing; a
-- request for a template that has not arrived waits for it. A load that
-- fails (offline, not approved for this experience) is remembered, warned
-- once, and answered with nil: the stump then has no visual (only its
-- invisible hitbox), never a stand-in built from parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StumpMeshIds = require(ReplicatedStorage.Shared.StumpMeshIds)

local StumpMeshes = {}

local templates: { [number]: MeshPart } = {}
local failed: { [number]: boolean } = {}
local waiting: { [number]: { (MeshPart?) -> () } } = {}

StumpMeshes.Loads = 0 -- LoadAsset calls made (specs)

-- Replaced by specs.
StumpMeshes.LoadModel = function(id: number): Instance?
	local service = game:GetService("InsertService") :: InsertService
	return service:LoadAsset(id)
end

local function firstMeshPart(root: Instance): MeshPart?
	if root:IsA("MeshPart") then
		return root
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("MeshPart") then
			return d
		end
	end
	return nil
end

local function finish(index: number, template: MeshPart?)
	if template then
		templates[index] = template
	else
		failed[index] = true
	end
	local list = waiting[index]
	waiting[index] = nil
	if list then
		for _, fn in ipairs(list) do
			local ok, err = pcall(function(): any
				fn(template)
				return nil
			end)
			if not ok then
				warn("[StumpMeshes] a waiting stump failed: " .. tostring(err))
			end
		end
	end
end

local function load(index: number)
	local id = StumpMeshIds.IdFor(index)
	if not id then
		finish(index, nil)
		return
	end
	StumpMeshes.Loads += 1
	local ok, model = pcall(StumpMeshes.LoadModel, id)
	local mesh = if ok and model then firstMeshPart(model :: Instance) else nil
	if not mesh then
		warn(
			string.format(
				"[StumpMeshes] model %d (ratio %.2f) did not load (%s); stumps of this shape have no visual",
				id,
				index / 100 + 0.84,
				tostring(if ok then "no MeshPart in it" else model)
			)
		)
		finish(index, nil)
		return
	end
	local template = mesh:Clone()
	template:ClearAllChildren()
	-- Hull collision: a round stump's box would be wider than it looks.
	local fidelityOk, fidelityErr = pcall(function()
		template.CollisionFidelity = Enum.CollisionFidelity.Hull
	end)
	if not fidelityOk then
		warn("[StumpMeshes] CollisionFidelity Hull could not be set: " .. tostring(fidelityErr))
	end
	finish(index, template)
end

-- The template for frustum `index` (1..16 = ratio 0.85..1.00), or nil when
-- it is not here (yet, or ever).
function StumpMeshes.Get(index: number): MeshPart?
	return templates[index]
end

-- Calls `done` with the template (at once when it is cached, or when it
-- fails: nil), loading it in the background first if need be.
function StumpMeshes.Request(index: number, done: (MeshPart?) -> ())
	local have = templates[index]
	if have then
		done(have)
		return
	end
	if failed[index] then
		done(nil)
		return
	end
	local list = waiting[index]
	if list then
		table.insert(list, done)
		return
	end
	waiting[index] = { done }
	task.spawn(load, index)
end

-- The one line the boot check prints, and a line for each model that
-- failed (its ratio and id), e.g. "[Stump] 16/16 frustum meshes loaded".
function StumpMeshes.Lines(loaded: number, failures: { string }): { string }
	local lines = { string.format("[Stump] %d/16 frustum meshes loaded", loaded) }
	for _, failure in ipairs(failures) do
		table.insert(lines, "[Stump] FAILED " .. failure)
	end
	return lines
end

local function describe(index: number, why: string): string
	return string.format("ratio %.2f model %s: %s", 0.84 + index / 100, tostring(StumpMeshIds.IdFor(index)), why)
end

-- Starts every load now (server start) so the first stump has its mesh, and
-- when the last has answered prints the boot-check line (warns for each
-- failure). `done(loaded, failures)` is called then (specs).
function StumpMeshes.Preload(done: ((number, { string }) -> ())?)
	local answered, loaded = 0, 0
	local failures: { string } = {}
	for index = 1, 16 do
		StumpMeshes.Request(index, function(template: MeshPart?)
			answered += 1
			if template and template:IsA("MeshPart") then
				loaded += 1
			else
				table.insert(failures, describe(index, "did not load as a MeshPart"))
			end
			if answered == 16 then
				local lines = StumpMeshes.Lines(loaded, failures)
				print(lines[1])
				for i = 2, #lines do
					warn(lines[i])
				end
				if done then
					done(loaded, failures)
				end
			end
		end)
	end
end

-- The same check, for the cloud test (it runs with a real InsertService and
-- yields): loads every model afresh, expects each to hold a MeshPart. Returns
-- the failure lines (empty = pass). Hook: #257's runner adds
-- `StumpMeshes.CloudCheck()` to its failures list.
function StumpMeshes.CloudCheck(): { string }
	local failures: { string } = {}
	for index = 1, 16 do
		local id = StumpMeshIds.IdFor(index)
		if not id then
			table.insert(failures, describe(index, "no model id in StumpMeshIds"))
			continue
		end
		local ok, model = pcall(StumpMeshes.LoadModel, id)
		local mesh = if ok and model then firstMeshPart(model :: Instance) else nil
		if not mesh then
			table.insert(failures, describe(index, if ok then "no MeshPart in the model" else tostring(model)))
		end
	end
	return failures
end

function StumpMeshes.Failed(index: number): boolean
	return failed[index] == true
end

-- For the specs.
function StumpMeshes._reset()
	table.clear(templates)
	table.clear(failed)
	table.clear(waiting)
	StumpMeshes.Loads = 0
end

return StumpMeshes
