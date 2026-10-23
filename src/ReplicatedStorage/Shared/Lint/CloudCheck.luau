--!strict
-- CloudCheck: what the cloud test runs, as a function of a built town (T409). tests/cloud/entry is the
-- thin caller in the Luau Execution task (it hands in the engine's own overlap query and the mesh
-- loader); tests/CloudCheck.spec calls it in lune with neither, on a town with a crate in a wall, and
-- sees the failures list fill. Findings are lines; `failed` counts them; `passed` counts the checks that
-- found nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Geometry = require(script.Parent.Geometry)
local Lanes = require(script.Parent.Lanes)
local MustKeep = require(script.Parent.MustKeep)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)

local CloudCheck = {}

export type Report = { passed: number, failed: number, failures: { string } }

export type Deps = {
	-- The engine's overlap query over the town (GetPartBoundsInBox); nil in lune.
	engineOverlaps: ((map: Instance, allow: { Geometry.AllowEntry }) -> { string })?,
	-- Loads every mesh of the town's buildings; nil in lune. Returns the failures and how many it tried.
	meshLoads: (() -> ({ string }, number))?,
	-- Builds a machine by id for MustKeep's machine entries.
	buildMachine: ((string) -> Model?)?,
	log: ((string) -> ())?,
}

-- `map` is the built town (a Folder named TimberlineMap); `root` is what MustKeep's paths start from
-- (the Workspace: it holds `map`). `data` is the two JSON files, decoded.
function CloudCheck.Run(
	map: Instance,
	root: Instance,
	data: { allow: { Geometry.AllowEntry }, mustkeep: MustKeep.List },
	deps: Deps
): Report
	local failures: { string } = {}
	local passed = 0
	local log = deps.log or function(_: string) end
	local function section(name: string, lines: { string })
		log(string.format("[cloud-test] %s: %d finding(s)", name, #lines))
		if #lines == 0 then
			passed += 1
		end
		for _, line in ipairs(lines) do
			log(line)
			table.insert(failures, line)
		end
	end

	section("lint (2b, 2c)", Geometry.Run(map, data.allow, nil, { skipStale = true }).failures)
	if deps.engineOverlaps then
		section("engine overlap (GetPartBoundsInBox)", deps.engineOverlaps(map, data.allow))
	end
	section("lanes, doors, paths", Lanes.Run(map, { Sawmill = WorldPlan.Town().sawmill }).failures)

	local list: MustKeep.List = { world = {}, machines = data.mustkeep.machines }
	for _, entry in ipairs(data.mustkeep.world) do
		if (entry :: any).town ~= false then
			table.insert(list.world, entry)
		end
	end
	section("MustKeep", MustKeep.Run(root, list, deps.buildMachine))

	if deps.meshLoads then
		local lines, checked = deps.meshLoads()
		log(string.format("[cloud-test] meshes checked: %d", checked))
		section("mesh loads", lines)
	end
	return { passed = passed, failed = #failures, failures = failures }
end

return CloudCheck
