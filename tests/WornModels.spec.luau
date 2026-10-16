--!nocheck
-- WornModels: the 14 worn-gear meshes uploaded on 16 October 2026, exactly as
-- given (MeshPart ids, never the Model containers), each with sizes and a
-- MeshTemplates file; and the part-built fallbacks stay when an id is 0.
return function(t)
	local WornModels = t.load("ReplicatedStorage/Shared/Art/WornModels")
	local fs = require("@lune/fs")

	local EXPECTED = {
		{ "CoatBody", "Body", 115269271855313, { 2.36, 2.197, 1.617 } },
		{ "CoatSleeve", "Body", 73589596256678, { 1.26, 1.34, 1.26 } },
		{ "HeatBoot", "Body", 116105552771338, { 1.07, 1.18, 1.6 } },
		{ "HeatBoot", "Glow", 124000816344542, { 1.05, 0.045, 1.51 } },
		{ "WaderBoot", "Body", 134517002979770, { 1.07, 1.48, 1.605 } },
		{ "CloakWorn", "Body", 124573428780738, { 3.08, 3.96, 1.89 } },
		{ "CloakWorn", "Glow", 75740144633857, { 0.228, 0.24, 0.228 } },
		{ "HardhatWorn", "Body", 98991863528912, { 1.832, 0.806, 2.217 } },
		{ "HardhatWorn", "Glow", 125383985331389, { 0.266, 0.28, 0.07 } },
		{ "GearBelt", "Body", 114698783853944, { 2.12, 0.53, 1.655 } },
		{ "RopeLadderSeg", "Body", 110300531040960, { 1.68, 4, 0.28 } },
		{ "RopeLadderTop", "Body", 121098136699219, { 2.3, 0.74, 1.09 } },
		{ "BlueprintScrollV2", "Handle", 119840415336807, { 0.628, 2.561, 0.628 } },
		{ "BlueprintScrollV2", "Seal", 87992443568498, { 0.312, 0.641, 0.28 } },
	}

	-- The Model containers: never a MeshId.
	local CONTAINERS = {
		74780230357114,
		113160315145800,
		115215111678291,
		93430836423109,
		101907625065167,
		127336723567348,
		123076361795913,
		77255199536845,
		103511895718371,
		108370546004395,
	}

	t.test("every row is the uploaded MeshPart id and size, in the order given", function()
		for _, row in ipairs(EXPECTED) do
			local piece = WornModels.Piece(row[1], row[2])
			t.ok(piece ~= nil, row[1] .. "." .. row[2] .. " exists")
			t.eq(piece.meshId, row[3], row[1] .. "." .. row[2] .. " MeshId")
			t.ok(
				math.abs(piece.size.X - row[4][1]) < 1e-6
					and math.abs(piece.size.Y - row[4][2]) < 1e-6
					and math.abs(piece.size.Z - row[4][3]) < 1e-6,
				row[1] .. "." .. row[2] .. " size " .. tostring(piece.size)
			)
		end
		local n = 0
		for _, asset in ipairs(WornModels.All) do
			n += #asset.pieces
		end
		t.eq(n, 14, "exactly the 14 meshes")
		t.eq(#WornModels.MeshIds(), 14)
	end)

	t.test("no Model container id is used as a MeshId, and every id is non-zero", function()
		for _, asset in ipairs(WornModels.All) do
			for _, piece in ipairs(asset.pieces) do
				t.ok(piece.meshId ~= 0, asset.id .. "." .. piece.name .. " is not pending")
				t.ok(piece.size.X > 0 and piece.size.Y > 0 and piece.size.Z > 0, asset.id .. " has sizes")
				for _, container in ipairs(CONTAINERS) do
					t.ok(piece.meshId ~= container, asset.id .. "." .. piece.name .. " uses a container id")
				end
			end
		end
	end)

	t.test("every mesh has a MeshTemplates file in the shape of the others", function()
		for _, row in ipairs(EXPECTED) do
			local text = fs.readFile("src/ReplicatedStorage/MeshTemplates/" .. row[3] .. ".model.json")
			t.eq(
				text,
				'{\n\t"className": "MeshPart",\n\t"properties": {\n\t\t"MeshId": "rbxassetid://'
					.. row[3]
					.. '"\n\t}\n}\n',
				row[1] .. "." .. row[2]
			)
		end
	end)

	t.test("the join preload lists the 14 worn ids", function()
		local Manifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
		local listed = {}
		for _, entry in ipairs(Manifest.Flat(false)) do
			listed[entry.id] = true
		end
		for _, row in ipairs(EXPECTED) do
			t.ok(listed[row[3]], row[3] .. " is preloaded")
		end
	end)
end
