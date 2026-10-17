--!nocheck
-- Cherry and Willow meshes (WORLD-T323): three sections and three crown
-- alternatives each; a tree wears exactly one crown, chosen by its seed; the
-- crown sits at the trunk foot plus its centre (scaled with the tree) and is
-- coloured by the piece, not by the grayscale mesh; older woods build every
-- crown piece as before.
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local TreeModels = t.load("ReplicatedStorage/Shared/Art/TreeModels")
	local TreeMeshes = t.load("ReplicatedStorage/Shared/Art/TreeMeshes")
	local WoodData = t.shared("WoodData")
	local TreeGen = t.shared("TreeGen")
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function visuals(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				table.insert(out, d)
			end
		end
		return out
	end

	local EXPECT = {
		cherry = {
			sections = { 113366252051468, 97477811876012, 79356553290404 },
			crowns = { 101745006486253, 92180340298006, 85408796934215 },
			color = "E9A9BC",
		},
		willow = {
			sections = { 137219565562843, 96586093008955, 107944902995245 },
			crowns = { 122744791844738, 118587333632223, 121020528796354 },
			color = "8FA8A0",
		},
	}

	t.test("cherry and willow have 3 section meshes and 3 crown alternatives, ids as uploaded", function()
		for id, want in pairs(EXPECT) do
			for i = 1, 3 do
				t.eq(TreeModels.SectionMesh(id, i), want.sections[i], id .. " section " .. i)
			end
			local crown = TreeModels.Crown(id)
			t.eq(#crown, 3, id .. " crown pieces")
			for i, piece in ipairs(crown) do
				t.eq(piece.meshId, want.crowns[i], id .. " crown " .. i)
				t.eq(piece.variant, i, "the pieces are alternatives, one per variant")
				t.ok(piece.centre ~= nil, "each has its own centre")
				t.eq(piece.color:ToHex():upper(), want.color)
			end
		end
		t.eq(TreeModels.Crown("cherry")[1].centre, Vector3.new(0.160, 14.774, 0.011))
		t.eq(TreeModels.Crown("willow")[2].centre, Vector3.new(0.015, 15.731, 0.000))
	end)

	t.test("every new id is a preloaded mesh", function()
		local ids = {}
		for _, id in ipairs(TreeModels.MeshIds()) do
			ids[id] = true
		end
		for _, want in pairs(EXPECT) do
			for _, id in ipairs(want.sections) do
				t.ok(ids[id], "section " .. id)
			end
			for _, id in ipairs(want.crowns) do
				t.ok(ids[id], "crown " .. id)
			end
		end
	end)

	t.test("the variant is (seed % 3) + 1, and a tree builds exactly that one crown", function()
		t.eq(TreeMeshes.VariantFor(0), 1)
		t.eq(TreeMeshes.VariantFor(1), 2)
		t.eq(TreeMeshes.VariantFor(2), 3)
		t.eq(TreeMeshes.VariantFor(3), 1)
		for id, want in pairs(EXPECT) do
			local def = WoodData.Get(id)
			for seed = 1, 6 do
				withMeshes(function()
					local skel = TreeGen.Skeleton(id, seed, 1)
					local model = TreeArt.FromSkeleton(def, skel)
					local crowns = visuals(model)
					t.eq(#crowns, 1, id .. " seed " .. seed .. " wears one crown")
					t.eq(crowns[1]:GetAttribute("MeshId"), tostring(want.crowns[TreeMeshes.VariantFor(skel.seed)]))
					t.eq(crowns[1].Color:ToHex():upper(), want.color, "coloured by the piece")
				end)
			end
		end
		-- Three different crowns across a group.
		local seen = {}
		for seed = 1, 3 do
			withMeshes(function()
				local skel = TreeGen.Skeleton("cherry", seed, 1)
				local model = TreeArt.FromSkeleton(WoodData.Get("cherry"), skel)
				seen[visuals(model)[1]:GetAttribute("MeshId")] = true
			end)
		end
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		t.eq(n, 3, "three seeds in a row give three different crowns")
	end)

	t.test("the crown sits at the trunk foot plus its centre, scaled with the tree", function()
		for id, _ in pairs(EXPECT) do
			for _, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi }) do
				withMeshes(function()
					local skel = TreeGen.Skeleton(id, 4, scale)
					local model = TreeArt.FromSkeleton(WoodData.Get(id), skel)
					local crown = visuals(model)[1]
					local piece = TreeModels.Crown(id)[TreeMeshes.VariantFor(skel.seed)]
					-- The foot: the primary section's axis at the lowest underside.
					local root = model.PrimaryPart
					local low = math.huge
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Section" then
							low = math.min(low, d.CFrame.Position.Y - d.Size.Y / 2)
						end
					end
					local p = root.CFrame.Position
					local want = Vector3.new(p.X, low, p.Z) + piece.centre * skel.scale
					t.ok((crown.CFrame.Position - want).Magnitude < 1e-3, id .. " scale " .. scale)
					t.ok(
						(crown.Size - piece.size * skel.scale).Magnitude < 1e-3,
						"the crown's bounds scale with the tree"
					)
				end)
			end
		end
	end)

	t.test("older woods still build every crown piece, with no centre or colour override", function()
		for _, id in ipairs({ "oak", "bogcypress", "ironwood" }) do
			for _, piece in ipairs(TreeModels.Crown(id)) do
				t.eq(piece.variant, nil, id)
				t.eq(piece.centre, nil, id)
				t.eq(piece.color, nil, id)
			end
		end
		withMeshes(function()
			local skel = TreeGen.Skeleton("oak", 3, 1)
			local model = TreeArt.FromSkeleton(WoodData.Get("oak"), skel)
			t.eq(#visuals(model), #TreeModels.Crown("oak"))
		end)
	end)
end
