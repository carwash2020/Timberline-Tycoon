--!nocheck
-- T415: after load, no part-built fallback shows where an uploaded mesh stands in. For every dressed
-- model a visible plain part may not carry the name of a piece that has a nonzero MeshId. Two named
-- exceptions: the Counter (a shop's gameplay part, drawn by the shop interior) and the General Store's
-- Chimney (its mesh is only the 0.75 stud cap; the part-built brick stack under it is meant and holds
-- the smoke emitter).
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local TownBuild = t.load("ReplicatedStorage/Shared/Lint/TownBuild")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local NPCData = t.shared("NPCData")
	local roblox = t.roblox
	local KEPT = { Counter = true, Chimney = true }

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		TownMeshes.Enabled = true
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function fallbacks(model, asset)
		local pieces = {}
		for _, piece in ipairs(TownModels.Visual(asset)) do
			if piece.meshId ~= 0 then
				pieces[piece.name] = true
			end
		end
		local out = {}
		for _, p in ipairs(model:GetDescendants()) do
			if
				p:IsA("BasePart")
				and p:GetAttribute("VisualMesh") ~= true
				and p.Transparency < 1
				and pieces[p.Name]
				and not KEPT[p.Name]
			then
				table.insert(out, model.Name .. "." .. p.Name)
			end
		end
		return out
	end

	t.test("every dressed model in the built town shows no part-built twin of a meshed piece", function()
		withMeshes(function()
			local map = TownBuild.Build()
			local dressed = 0
			for _, d in ipairs(map:GetDescendants()) do
				local id = if d:IsA("Model") then d:GetAttribute("TownMesh") else nil
				local asset = if id then TownModels.Get(id) else nil
				if asset then
					dressed += 1
					t.eq(fallbacks(d, asset), {}, d.Name)
				end
			end
			t.ok(dressed > 40, "dressed models: " .. dressed)
		end)
	end)

	t.test("every townsperson with meshes shows no part-built body", function()
		withMeshes(function()
			local seen = 0
			for _, npc in ipairs(NPCData.List or {}) do
				local person = CharacterArt.Build(npc.look)
				local asset = TownModels.Get(npc.id)
				if asset then
					seen += 1
					t.eq(fallbacks(person, asset), {}, npc.id)
				end
			end
			t.ok(seen > 0 or NPCData.List == nil)
		end)
	end)

	t.test("control: the same model with the load failed does show its part-built look", function()
		MeshKit.Reset()
		local plain = TownBuild.Build()
		local sawmill = plain:FindFirstChild("Sawmill")
		local visible = 0
		for _, p in ipairs(sawmill:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 and p:GetAttribute("VisualMesh") ~= true then
				visible += 1
			end
		end
		t.ok(visible > 5, "the fallback shows while no mesh is in: " .. visible)
	end)
end
