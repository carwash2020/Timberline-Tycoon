--!nocheck
-- The five Blender NPCs (Hermit, Old Tolly, Cap'n Moss, Old Hank, the
-- Foreman) ride the same MeshKit path as the other townsfolk: a TownModels
-- row, a MeshTemplates file per id, NPCMeshes.Dress, and the part-built
-- NPC when an id is missing.
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local NPCMeshes = t.load("ReplicatedStorage/Shared/Art/NPCMeshes")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local NPCData = t.shared("NPCData")
	local roblox = t.roblox

	local FIVE = { "Hermit", "OldTolly", "CapnMoss", "OldHank", "Foreman" }

	t.test("a spec name maps to its uploaded model id", function()
		t.eq(NPCMeshes.AssetId("Old Tolly"), "OldTolly")
		t.eq(NPCMeshes.AssetId("The Hermit"), "Hermit")
		t.eq(NPCMeshes.AssetId("Cap'n Moss"), "CapnMoss")
		t.eq(NPCMeshes.AssetId("Old Hank"), "OldHank")
		t.eq(NPCMeshes.AssetId("Rook Calloway"), "Foreman")
		t.eq(NPCMeshes.AssetId("Murph"), "Murph")
	end)

	t.test("each Blender NPC has a row with real ids and a template file for every piece", function()
		local fs = require("@lune/fs")
		for _, id in ipairs(FIVE) do
			local asset = TownModels.Get(id)
			t.ok(asset ~= nil, id .. " row")
			t.eq(asset.category, "npc")
			t.ok(asset.modelId > 0, id .. " model id")
			local seen = {}
			for _, piece in ipairs(asset.pieces) do
				t.ok(piece.meshId > 0, id .. " " .. piece.name .. " is not 0")
				t.ok(not seen[piece.name], id .. " " .. piece.name .. " once")
				seen[piece.name] = true
				t.ok(
					fs.isFile("src/ReplicatedStorage/MeshTemplates/" .. tostring(piece.meshId) .. ".model.json"),
					id .. " " .. piece.name .. " template"
				)
			end
			for _, name in ipairs({ "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }) do
				t.ok(seen[name], id .. " has " .. name)
			end
		end
	end)

	t.test("every Blender NPC in the roster dresses with its meshes, or keeps the part build", function()
		local wired = 0
		for _, npc in ipairs(NPCData.List) do
			local id = NPCMeshes.AssetId(npc.look.name)
			if table.find(FIVE, id) then
				wired += 1
				MeshKit.Reset()
				local plain = CharacterArt.Build(npc.look)
				t.eq(plain:GetAttribute("TownMesh"), nil, npc.id .. " part-built without meshes")
				t.eq(plain:GetAttribute("MeshFallback"), id, npc.id .. " notes the miss (logged once per asset in the engine)")
				t.ok(plain.Torso.Transparency < 1, npc.id .. " keeps the part look")
				MeshKit.Reset() -- the part-built pass cached its misses
				MeshKit.Override = function(_id, name, size)
					local part = roblox.Instance.new("MeshPart")
					part.Name = name
					part.Size = size
					return part
				end
				local dressed = CharacterArt.Build(npc.look)
				MeshKit.Override = nil
				MeshKit.Reset()
				t.eq(dressed:GetAttribute("TownMesh"), id, npc.id .. " dressed")
			end
		end
		t.ok(wired >= 4, "the roster holds the Blender NPCs (the Foreman joins it with his own spec)")
	end)
end
