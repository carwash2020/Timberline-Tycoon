--!nocheck
-- AxeHandle (T406): a meshed axe's part-built Handle (the Tool's required part)
-- is not drawn, so it cannot flicker against the mesh haft at the hilt. With no
-- mesh the part-built axe is all there is and stays visible. Built through
-- AxeArt.Held, the Tool's own art, for every axe.
return function(t)
	local roblox = t.roblox
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local ItemCatalog = t.shared("ItemCatalog")

	local function allAxes()
		local out = {}
		for _, def in pairs(ItemCatalog.Axes) do
			table.insert(out, def)
		end
		table.sort(out, function(a, b)
			return a.id < b.id
		end)
		return out
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = roblox.Instance.new("MeshPart")
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

	t.test("meshed: the Handle is invisible and no other plain part is drawn over the mesh haft", function()
		withMeshes(function()
			local meshed = 0
			for _, def in ipairs(allAxes()) do
				local model = AxeArt.Held(def)
				local handle = model.PrimaryPart
				if model:FindFirstChild("MeshHandle") then
					meshed += 1
					t.eq(handle.Transparency, 1, def.id .. ": Handle is not drawn under its mesh")
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true then
							t.ok(d.Transparency == 1, def.id .. ": " .. d.Name .. " is not drawn over the mesh")
						end
					end
				end
			end
			t.ok(meshed > 0, "at least one axe has its meshes")
		end)
	end)

	t.test("part-built (no mesh): the Handle is drawn, it is the axe", function()
		MeshKit.Reset()
		for _, def in ipairs(allAxes()) do
			local model = AxeArt.Held(def)
			if not model:FindFirstChild("MeshHandle") then
				t.ok(model.PrimaryPart.Transparency < 1, def.id .. ": the part-built haft shows")
			end
		end
	end)
end
