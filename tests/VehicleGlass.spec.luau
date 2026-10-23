--!nocheck
-- T421: every glass MeshPart (the part is named MeshGlass, the role is Glass) is see-through (Transparency 0.4) and casts no shadow, set in code because a GLB
-- cannot store either. Fake ids make the mesh path run (MeshKit.Override).
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local TruckLayout = t.shared("TruckLayout")
	local ItemCatalog = t.shared("ItemCatalog")

	local function withMeshes(fn)
		MeshKit.Reset()
		VehicleMeshes.ResetWarnings()
		Gate.SetIds(Gate.FakeIds())
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			-- what a freshly loaded template looks like: opaque and shadow-casting
			part.Transparency = 0
			part.CastShadow = true
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		Gate.SetIds(nil)
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	t.test("every Glass mesh reads Transparency 0.4 and CastShadow false", function()
		withMeshes(function()
			local seen = 0
			for _, def in ipairs(ItemCatalog.TruckList()) do
				local lay = TruckLayout.For(def)
				local model = TruckArt.Build(def, lay)
				t.eq(model:GetAttribute("VehicleMesh"), true, def.id .. " is meshed")
				for _, d in ipairs(model:GetDescendants()) do
					if
						d:IsA("MeshPart")
						and d:GetAttribute("VisualMesh") == true
						and string.find(d.Name, "Glass$") ~= nil
					then
						seen += 1
						t.ok(math.abs(d.Transparency - 0.4) < 1e-6, def.id .. " glass transparency " .. d.Transparency)
						t.eq(d.CastShadow, false, def.id .. " glass shadow")
					end
				end
			end
			t.ok(seen >= 5, "the trucks' glass was found: " .. seen)
		end)
	end)

	t.test("the Glass flags come from VehicleMeshes, not the template", function()
		t.eq(VehicleMeshes.GlassTransparency, 0.4)
	end)
end
