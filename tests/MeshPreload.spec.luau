--!nocheck
-- MeshManifest and MeshKit.Preload: every uploaded mesh starts loading side
-- by side when the server starts, so no builder waits on one. Studio's log of
-- 7 October 2026: NPCService.Init took 60 s because the nine townsfolk's 153
-- meshes loaded one at a time (about 0.4 s each); PlotService.Init took 10.7 s
-- for the plot kit's the same way.
return function(t)
	local roblox = t.roblox

	local function kit()
		local loader = t.loader()
		return loader:shared("Art/MeshKit"), loader:shared("Art/MeshManifest"), loader
	end

	t.test("the manifest lists every NPC piece, once each, townsfolk after Murph", function()
		local _, MeshManifest, loader = kit()
		local TownModels = loader:shared("Art/TownModels")
		local groups = MeshManifest.Groups(false)
		local byName = {}
		for _, group in ipairs(groups) do
			byName[group.name] = group
		end
		t.ok(byName.murph and #byName.murph.entries > 0, "Murph's pieces")
		t.ok(byName.npcs and #byName.npcs.entries > 0, "the other townsfolk")
		local distinct, pieces = {}, 0
		local count = 0
		for _, id in ipairs(TownModels.Ids("npc")) do
			for _, piece in ipairs(TownModels.Visual(TownModels.Get(id))) do
				pieces += 1
				if not distinct[piece.meshId] then
					distinct[piece.meshId] = true
					count += 1
				end
			end
		end
		t.eq(#byName.murph.entries + #byName.npcs.entries, count, "every NPC mesh, none twice")
		t.eq(pieces, 153 + 86, "nine townsfolk of 17 pieces (153 serial loads that took 60 s), plus the five Blender NPCs")
	end)

	t.test("no mesh id appears twice in the whole manifest, and none is zero", function()
		local _, MeshManifest = kit()
		for _, town in ipairs({ false, true }) do
			local seen = {}
			for _, entry in ipairs(MeshManifest.Flat(town)) do
				t.ok(type(entry.id) == "number" and entry.id ~= 0, "a real id")
				t.ok(not seen[entry.id], "mesh " .. tostring(entry.id) .. " listed twice")
				seen[entry.id] = true
			end
		end
	end)

	t.test("the town's building meshes are listed only when TownMeshes is on", function()
		local _, MeshManifest = kit()
		local off, on = #MeshManifest.Flat(false), #MeshManifest.Flat(true)
		t.ok(on > off, "the town group adds ids")
		t.eq(MeshManifest.Groups(true)[1].name, "town")
		t.eq(MeshManifest.Groups(false)[1].name, "vehicles")
	end)

	t.test("the plot kit's, the axes', the trees' and the kit's meshes are all in it", function()
		local _, MeshManifest, loader = kit()
		local ItemMeshData = loader:shared("ItemMeshData")
		local AxeModels = loader:shared("Art/AxeModels")
		local TreeModels = loader:shared("Art/TreeModels")
		local KitMeshData = loader:shared("KitMeshData")
		local listed = {}
		for _, entry in ipairs(MeshManifest.Flat(false)) do
			listed[entry.id] = entry
		end
		for _, defs in pairs(ItemMeshData.Items) do
			for _, def in ipairs(defs) do
				t.ok(listed[tonumber(string.match(def.meshId, "%d+"))], "item mesh " .. def.meshId)
			end
		end
		for _, id in ipairs(AxeModels.MeshIds()) do
			t.ok(listed[id], "axe mesh " .. id)
		end
		for _, id in ipairs(TreeModels.MeshIds()) do
			t.ok(listed[id], "tree mesh " .. id)
		end
		for _, piece in pairs(KitMeshData.Pieces) do
			for _, def in ipairs(piece.meshes) do
				local entry = listed[def.meshId]
				t.ok(entry, "kit mesh " .. def.meshId)
				t.eq(entry.hull == true, def.fidelity == "Hull", "kit mesh " .. def.meshId .. " keeps its collision")
			end
		end
	end)

	t.test("a wheel loads with Hull collision, everything else Box (a mesh's collision can't change later)", function()
		local _, MeshManifest, loader = kit()
		local VehicleModels = loader:shared("Art/VehicleModels")
		local listed = {}
		for _, entry in ipairs(MeshManifest.Flat(false)) do
			listed[entry.id] = entry
		end
		local wheels = 0
		for _, piece in ipairs(VehicleModels.AllPieces()) do
			t.eq(listed[piece.meshId].hull == true, piece.wheel, "vehicle mesh " .. piece.meshId)
			if piece.wheel then
				wheels += 1
			end
		end
		t.ok(wheels >= 4, wheels .. " wheel meshes")
	end)

	t.test("Preload asks for each id once and a later Create reuses the loaded mesh", function()
		local MeshKit = kit()
		local asked = {}
		MeshKit.Override = function(id, name, size)
			asked[id] = (asked[id] or 0) + 1
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			return part
		end
		MeshKit.Reset()
		local result = MeshKit.Preload({ { id = 11 }, { id = 22 }, { id = 11 }, { id = 33, hull = true }, { id = 0 } })
		t.eq(result.total, 3, "three distinct real ids (the repeat and the zero are skipped)")
		t.eq(result.loaded, 3)
		t.eq(result.failed, 0)
		t.eq(result.timedOut, false)
		t.eq(asked[11], 1, "a repeated id is loaded once")
		local part = MeshKit.Create(22, "Head", roblox.Vector3.new(1, 2, 3))
		t.ok(part, "a Create after the preload gets its mesh")
		t.eq(asked[22], 1, "...without asking again")
		-- Already cached ids cost nothing the second time.
		MeshKit.Preload({ { id = 11 }, { id = 22 } })
		t.eq(asked[11], 1)
		MeshKit.Override = nil
		MeshKit.Reset()
	end)

	t.test("a failed id is counted, not retried by the next preload, and never throws", function()
		local MeshKit = kit()
		local asked = 0
		MeshKit.Override = function(id)
			asked += 1
			if id == 2 then
				error("no permission")
			end
			return roblox.Instance.new("MeshPart")
		end
		MeshKit.Reset()
		local result = MeshKit.Preload({ { id = 1 }, { id = 2 }, { id = 3 } })
		t.eq(result.loaded, 2)
		t.eq(result.failed, 1)
		local before = asked
		MeshKit.Preload({ { id = 2 } })
		t.eq(asked, before, "a remembered failure is not asked again")
		MeshKit.Override = nil
		MeshKit.Reset()
	end)

	t.test("an empty preload is fine", function()
		local MeshKit = kit()
		local result = MeshKit.Preload({})
		t.eq(result.total, 0)
		t.eq(result.timedOut, false)
	end)
end
