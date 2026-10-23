--!strict
-- The cloud runner (T409). tools/cloud/run_task.py publishes a Saved version of the test place and runs
-- this module in an Open Cloud Luau Execution task on it: `return require(ServerStorage.CloudTests.entry)()`.
-- It requires the real game modules, builds the town the way MapBuilder does (Shared/Lint/TownBuild:
-- MapBuilder is a Script and cannot be required), puts it in the real Workspace and checks it with the
-- real engine:
--   * overlap: GetPartBoundsInBox on every colliding part (the engine's own answer, besides the
--     lint's box maths),
--   * the lint itself (Shared/Lint/Geometry, the same code the lune specs run, with the same allowlist),
--   * door, path and lane passability (Shared/Lint/Lanes),
--   * MustKeep (tests/mustkeep.json, the town's entries),
--   * mesh loads: every mesh of the town's buildings loads here (the engine, the asset permissions).
-- Physics does not run in a task: geometry and logic only. It returns { passed, failed, failures } and
-- calls error() when anything failed, which fails the task.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lint = ReplicatedStorage.Shared.Lint
local CloudCheck = require(Lint.CloudCheck)
local Geometry = require(Lint.Geometry)
local TownBuild = require(Lint.TownBuild)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local MeshKit = require(ReplicatedStorage.Shared.Art.MeshKit)
local TownModels = require(ReplicatedStorage.Shared.Art.TownModels)

local allowData = require(script.Parent.geometry_allow) :: any
local mustKeepData = require(script.Parent.mustkeep) :: any

local function engineOverlaps(map: Instance, allow: { Geometry.AllowEntry }): { string }
	local ids, byId = Geometry.Pieces(map)
	local pieceOf: { [BasePart]: string } = {}
	local parts: { BasePart } = {}
	for _, id in ipairs(ids) do
		local piece = byId[id]
		local list: { Instance } = if piece:IsA("BasePart") then { piece } else piece:GetDescendants()
		for _, d in ipairs(list) do
			if d:IsA("BasePart") and Geometry.Solid(d) then
				pieceOf[d] = id
				table.insert(parts, d)
			end
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.RespectCanCollide = true
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, part in ipairs(parts) do
		-- A box 0.1 smaller all round: the engine reports what overlaps by more than 0.05.
		local size = Vector3.new(
			math.max(part.Size.X - 0.1, 0.01),
			math.max(part.Size.Y - 0.1, 0.01),
			math.max(part.Size.Z - 0.1, 0.01)
		)
		for _, other in ipairs(workspace:GetPartBoundsInBox(part.CFrame, size, params)) do
			local ida, idb = pieceOf[part], pieceOf[other]
			if other ~= part and idb ~= nil and ida ~= idb and not Geometry.Allowed(allow, ida, idb) then
				local key = if ida < idb
					then ida .. "|" .. idb .. "|" .. part.Name .. "|" .. other.Name
					else idb .. "|" .. ida .. "|" .. other.Name .. "|" .. part.Name
				if not seen[key] then
					seen[key] = true
					local at = part.CFrame.Position
					table.insert(
						out,
						string.format(
							"[GeometryLint] %s (%s) x %s (%s) at (%.1f, %.1f, %.1f), engine GetPartBoundsInBox, rule 2b",
							part.Name,
							ida,
							other.Name,
							idb,
							at.X,
							at.Y,
							at.Z
						)
					)
				end
			end
		end
	end
	table.sort(out)
	return out
end

local function meshLoads(): ({ string }, number)
	local failures: { string } = {}
	local checked = 0
	for _, id in ipairs(TownModels.Ids("building")) do
		local asset = TownModels.Get(id)
		if asset then
			for _, piece in ipairs(asset.pieces) do
				checked += 1
				local mesh = MeshKit.CreateAwait(piece.meshId, piece.name, piece.size)
				if not mesh then
					table.insert(
						failures,
						string.format("[MeshLoad] %s/%s (mesh %d) did not load", id, piece.name, piece.meshId)
					)
				end
			end
		end
	end
	return failures, checked
end

return function(): CloudCheck.Report
	local map = TownBuild.Build()
	map.Parent = workspace
	local report = CloudCheck.Run(map, workspace, { allow = allowData :: any, mustkeep = mustKeepData :: any }, {
		engineOverlaps = engineOverlaps,
		meshLoads = meshLoads,
		buildMachine = MachineArt.BuildAny,
		log = print,
	})
	map:Destroy()
	print(string.format("[cloud-test] done: %d check(s) passed, %d failure(s)", report.passed, report.failed))
	if report.failed > 0 then
		error(string.format("cloud-test: %d failure(s):\n%s", report.failed, table.concat(report.failures, "\n")), 0)
	end
	return report
end
