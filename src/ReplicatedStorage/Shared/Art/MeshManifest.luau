--!strict
-- MeshManifest: every uploaded mesh the server will ask MeshKit for, in the
-- order it is needed, so MapBuilder can start loading ALL of them side by
-- side the moment the server starts (MeshKit.Preload) while the terrain is
-- being written, instead of each builder loading its own one at a time later.
-- Studio's log of 7 October 2026: the NPCs' meshes alone held NPCService.Init
-- for 60 s and the plot kit's held PlotService.Init for 10 s, one mesh at a
-- time at about a third of a second each.
--
-- Pure data over the model modules (no engine calls). An entry's `hull` is
-- the collision MeshKit creates the master with (a wheel or a kit piece that
-- says Hull; a mesh's collision can't be changed after it loads), so it must
-- match what the builder asks for; the spec checks the sources it can.
--
-- Groups, most urgent first:
--   town     the shops' and props' uploaded meshes (only when TownMeshes is on)
--   vehicles the dealership lot's trucks and trailers (built with the town)
--   axes     the shop racks and every axe tool
--   murph    Murph's pieces (he is the tutorial's first stop)
--   npcs     the other townsfolk
--   items    the plot kit's shell and blueprint pieces (PlotService)
--   trees    section and crown meshes (the forest, the Lumenwood)
--   kit      the building kit's meshes (a player's own plot)
--   blender  ids only the Blender registry supplies (BlenderAssets.MeshIds;
--            empty while its ids are 0, so nothing changes in game)

local AxeModels = require(script.Parent.AxeModels)
local BlenderAssets = require(script.Parent.BlenderAssets)
local RockModels = require(script.Parent.RockModels)
local ItemMeshData = require(script.Parent.Parent.ItemMeshData)
local KitMeshData = require(script.Parent.Parent.KitMeshData)
local TownModels = require(script.Parent.TownModels)
local TreeModels = require(script.Parent.TreeModels)
local VehicleModels = require(script.Parent.VehicleModels)

local MeshManifest = {}

export type Entry = { id: number, hull: boolean? }
export type Group = { name: string, entries: { Entry } }

-- The id of an asset piece list: every visual piece (not "Collision").
local function assetEntries(id: string, out: { Entry })
	local asset = TownModels.Get(id)
	if not asset then
		return
	end
	for _, piece in ipairs(TownModels.Visual(asset)) do
		table.insert(out, { id = piece.meshId, hull = false })
	end
end

local function numeric(uri: string): number?
	return tonumber(string.match(uri, "%d+"))
end

-- The groups, with ids repeated in a later group dropped from it (so the
-- total is each mesh once). `town` adds the building and environment meshes.
function MeshManifest.Groups(town: boolean?): { Group }
	local groups: { Group } = {}
	local seen: { [number]: boolean } = {}
	local function add(name: string, build: (out: { Entry }) -> ())
		local raw: { Entry } = {}
		build(raw)
		local entries: { Entry } = {}
		for _, entry in ipairs(raw) do
			if entry.id ~= 0 and not seen[entry.id] then
				seen[entry.id] = true
				table.insert(entries, entry)
			end
		end
		table.insert(groups, { name = name, entries = entries })
	end

	if town then
		add("town", function(out)
			for _, category in ipairs({ "building", "environment" }) do
				for _, id in ipairs(TownModels.Ids(category :: any)) do
					assetEntries(id, out)
				end
			end
		end)
	end
	add("vehicles", function(out)
		for _, piece in ipairs(VehicleModels.AllPieces()) do
			table.insert(out, { id = piece.meshId, hull = piece.wheel })
		end
	end)
	add("axes", function(out)
		for _, id in ipairs(AxeModels.MeshIds()) do
			table.insert(out, { id = id, hull = false })
		end
	end)
	add("murph", function(out)
		assetEntries("Murph", out)
	end)
	add("npcs", function(out)
		for _, id in ipairs(TownModels.Ids("npc")) do
			assetEntries(id, out)
		end
	end)
	add("items", function(out)
		local ids: { string } = {}
		for id in pairs(ItemMeshData.Items) do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			for _, def in ipairs(ItemMeshData.List(id)) do
				local n = numeric(def.meshId)
				if n then
					table.insert(out, { id = n, hull = false })
				end
			end
		end
	end)
	add("trees", function(out)
		for _, id in ipairs(TreeModels.MeshIds()) do
			table.insert(out, { id = id, hull = false })
		end
	end)
	add("rocks", function(out)
		for _, id in ipairs(RockModels.MeshIds()) do
			table.insert(out, { id = id, hull = false })
		end
	end)
	add("kit", function(out)
		local ids: { string } = {}
		for id in pairs(KitMeshData.Pieces) do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			for _, def in ipairs(KitMeshData.Pieces[id].meshes) do
				table.insert(out, { id = def.meshId, hull = def.fidelity == "Hull" })
			end
		end
	end)
	add("blender", function(out)
		for _, id in ipairs(BlenderAssets.MeshIds()) do
			table.insert(out, { id = id, hull = false })
		end
	end)
	return groups
end

-- All entries in one list, group by group.
function MeshManifest.Flat(town: boolean?): { Entry }
	local out: { Entry } = {}
	for _, group in ipairs(MeshManifest.Groups(town)) do
		for _, entry in ipairs(group.entries) do
			table.insert(out, entry)
		end
	end
	return out
end

-- The NPC pieces of one townsperson (by TownModels id), for NPCService's
-- own bounded wait on the ones it is about to build.
function MeshManifest.ForNpcs(ids: { string }): { Entry }
	local out: { Entry } = {}
	for _, id in ipairs(ids) do
		assetEntries(id, out)
	end
	return out
end

return MeshManifest
