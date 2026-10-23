--!strict
-- StumpMeshes (T420): loads the 96 stump frustum meshes (Shared/StumpMeshIds:
-- radius sets R13 and R22 x 16 tapers x heights 3, 5, 8) on the server with InsertService:LoadAsset,
-- once per row, and hands out the cached MeshPart template (CollisionFidelity
-- Hull) for TreeArt.StumpDress to clone. A template is named by its key
-- (StumpMeshIds.Key). Loads run in the background (Request), never inside a
-- swing; a request for a template that has not arrived waits for it. A load
-- that fails (offline, not approved for this experience) is remembered,
-- warned once, and answered with nil: the stump then has no visual (only its
-- invisible hitbox), never a stand-in built from parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StumpLogic = require(ReplicatedStorage.Shared.StumpLogic)
local StumpMeshIds = require(ReplicatedStorage.Shared.StumpMeshIds)

local StumpMeshes = {}

StumpMeshes.Count = 96

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

local function describe(key: number, why: string): string
	local row = StumpMeshIds.Row(key)
	if not row then
		return string.format("key %d: %s", key, why)
	end
	return string.format(
		"%s (set %s, taper %.2f, height %d) model %d: %s",
		row.name,
		row.set,
		row.taper / 100,
		row.height,
		row.id,
		why
	)
end

local function finish(key: number, template: MeshPart?)
	if template then
		templates[key] = template
	else
		failed[key] = true
	end
	local list = waiting[key]
	waiting[key] = nil
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

local function load(key: number)
	local row = StumpMeshIds.Row(key)
	if not row then
		finish(key, nil)
		return
	end
	StumpMeshes.Loads += 1
	local ok, model = pcall(StumpMeshes.LoadModel, row.id)
	local mesh = if ok and model then firstMeshPart(model :: Instance) else nil
	if not mesh then
		warn(
			"[StumpMeshes] "
				.. describe(
					key,
					"did not load ("
						.. tostring(if ok then "no MeshPart in it" else model)
						.. "); stumps of this shape have no visual"
				)
		)
		finish(key, nil)
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
	finish(key, template)
end

-- The template for `key` (1..48), or nil when it is not here (yet, or ever).
function StumpMeshes.Get(key: number): MeshPart?
	return templates[key]
end

-- Calls `done` with the template (at once when it is cached, or when it
-- fails: nil), loading it in the background first if need be.
function StumpMeshes.Request(key: number, done: (MeshPart?) -> ())
	local have = templates[key]
	if have then
		done(have)
		return
	end
	if failed[key] then
		done(nil)
		return
	end
	local list = waiting[key]
	if list then
		table.insert(list, done)
		return
	end
	waiting[key] = { done }
	task.spawn(load, key)
end

-- Calls `done` with one template per key (nil for one that failed) when all
-- have answered.
function StumpMeshes.RequestMany(keys: { number }, done: ({ MeshPart? }) -> ())
	local out: { MeshPart? } = {}
	local answered = 0
	local total = #keys
	if total == 0 then
		done(out)
		return
	end
	for i, key in ipairs(keys) do
		StumpMeshes.Request(key, function(template: MeshPart?)
			out[i] = template
			answered += 1
			if answered == total then
				done(out)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Choosing the meshes of a stump, and what to do when some are missing
---------------------------------------------------------------------------

-- What could not be had, as lines: "<set> taper <t> height <h> (model <id>)".
-- Recorded when a stump finds its meshes missing and cannot fall back, and by
-- the boot check; StumpMeshes.Missing() returns it (and the workspace
-- attribute StumpMeshesMissing counts it).
local missing: { string } = {}
local missingSeen: { [string]: boolean } = {}

local function noteMissing(line: string)
	if missingSeen[line] then
		return
	end
	missingSeen[line] = true
	table.insert(missing, line)
	warn("[Stump] stumpMeshesMissing: " .. line)
	pcall(function()
		workspace:SetAttribute("StumpMeshesMissing", #missing)
	end)
end

function StumpMeshes.Missing(): { string }
	return table.clone(missing)
end

local function keysOf(shape: StumpLogic.Shape, set: string): { number }
	local keys: { number } = {}
	for _, sleeve in ipairs(shape.sleeves) do
		table.insert(keys, StumpMeshIds.Key(set, sleeve.index, sleeve.bucket) :: number)
	end
	return keys
end

-- Whether the other radius set can stand in: every sleeve's stretch with the
-- other set's reference radius stays inside 1/1.3 to 1.3, round and up.
function StumpMeshes.FallbackOk(shape: StumpLogic.Shape, set: string): boolean
	for _, sleeve in ipairs(shape.sleeves) do
		local round, up = StumpLogic.BarkStretch(sleeve, set)
		if not StumpLogic.StretchOk(round, up) then
			return false
		end
	end
	return true
end

-- Hands `done` one template per sleeve of `shape`, from the shape's own set;
-- if any of those is missing, from the other set when its stretch is fine
-- (FallbackOk). With nothing usable it records stumpMeshesMissing (a loud
-- warning) and answers nil: the stump has no visual, never a part-built
-- stand-in. The second argument says which set was used.
function StumpMeshes.Resolve(shape: StumpLogic.Shape, done: ({ MeshPart? }?, string?) -> ())
	local own = shape.set
	StumpMeshes.RequestMany(keysOf(shape, own), function(got: { MeshPart? })
		local complete = true
		for i = 1, #shape.sleeves do
			if got[i] == nil then
				complete = false
			end
		end
		if complete then
			done(got, own)
			return
		end
		local other = if own == "R13" then "R22" else "R13"
		if StumpMeshes.FallbackOk(shape, other) then
			StumpMeshes.RequestMany(keysOf(shape, other), function(spare: { MeshPart? })
				for i = 1, #shape.sleeves do
					if spare[i] == nil then
						noteMissing(
							string.format(
								"%s and %s taper %.2f height %d (base radius %.3f)",
								own,
								other,
								shape.sleeves[i].ratio,
								shape.sleeves[i].bucket,
								shape.baseRadius
							)
						)
						done(nil, nil)
						return
					end
				end
				done(spare, other)
			end)
			return
		end
		for i, sleeve in ipairs(shape.sleeves) do
			if got[i] == nil then
				local row = StumpMeshIds.Row(StumpMeshIds.Key(own, sleeve.index, sleeve.bucket) :: number)
				local round, up = StumpLogic.BarkStretch(sleeve, other)
				noteMissing(
					string.format(
						"%s taper %.2f height %d (model %s), no %s fallback (stretch %.2f round, %.2f up)",
						own,
						sleeve.ratio,
						sleeve.bucket,
						tostring(if row then row.id else "?"),
						other,
						round,
						up
					)
				)
			end
		end
		done(nil, nil)
	end)
end

-- The one line the boot check prints, and a line for each model that
-- failed (its name, taper, height and id), e.g.
-- "[Stump] 48/48 frustum meshes loaded".
function StumpMeshes.Lines(loaded: number, failures: { string }): { string }
	local lines = { string.format("[Stump] %d/%d frustum meshes loaded", loaded, StumpMeshes.Count) }
	for _, failure in ipairs(failures) do
		table.insert(lines, "[Stump] FAILED " .. failure)
	end
	return lines
end

-- Starts every load now (server start) so the first stump has its mesh, and
-- when the last has answered prints the boot-check line (warns for each
-- failure). `done(loaded, failures)` is called then (specs).
function StumpMeshes.Preload(done: ((number, { string }) -> ())?)
	local answered, loaded = 0, 0
	local failures: { string } = {}
	for key = 1, StumpMeshes.Count do
		StumpMeshes.Request(key, function(template: MeshPart?)
			answered += 1
			if template and template:IsA("MeshPart") then
				loaded += 1
			else
				table.insert(failures, describe(key, "did not load as a MeshPart"))
			end
			if answered == StumpMeshes.Count then
				local lines = StumpMeshes.Lines(loaded, failures)
				print(lines[1])
				for i = 2, #lines do
					warn(lines[i])
				end
				-- A missing mesh is loud: unless the other set can stand in for
				-- every stump that would use it (it never can across a set's
				-- whole radius range), say so, once, by name.
				for _, failure in ipairs(failures) do
					noteMissing(failure)
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
-- the failure lines (empty = pass), and how many it tried. Hooked in
-- tests/cloud/entry (Shared/Lint/CloudCheck's `stumpMeshes`).
function StumpMeshes.CloudCheck(): ({ string }, number)
	local failures: { string } = {}
	for key = 1, StumpMeshes.Count do
		local row = StumpMeshIds.Row(key)
		if not row then
			table.insert(failures, describe(key, "no row in StumpMeshIds"))
			continue
		end
		local ok, model = pcall(StumpMeshes.LoadModel, row.id)
		local mesh = if ok and model then firstMeshPart(model :: Instance) else nil
		if not mesh then
			table.insert(failures, describe(key, if ok then "no MeshPart in the model" else tostring(model)))
		end
	end
	return failures, StumpMeshes.Count
end

function StumpMeshes.Failed(key: number): boolean
	return failed[key] == true
end

-- For the specs.
function StumpMeshes._reset()
	table.clear(templates)
	table.clear(failed)
	table.clear(waiting)
	table.clear(missing)
	table.clear(missingSeen)
	StumpMeshes.Loads = 0
end

return StumpMeshes
