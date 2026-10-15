--!nocheck
-- AxeHeadPlacement: the uploaded axe meshes do not share one blade plane, so
-- every head (and glow) carries an authored `at`, its centre measured from the
-- Handle mesh's centre (AxeModels.Piece.at). AxeArt puts each piece exactly
-- there, the head overlaps the top of the haft, and the half turn
-- (MeshYaw) is untouched.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")
	local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local ItemCatalog = t.shared("ItemCatalog")

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

	local EXPECTED = {
		RustyAxe = { Head = Vector3.new(0, 1.336, -0.394) },
		SteelAxe = { Head = Vector3.new(0, 1.398, -0.463) },
		HardenedAxe = { Head = Vector3.new(0, 0.913, -0.336) },
		SilverAxe = { Head = Vector3.new(0, 1.219, -0.536) },
		CobaltAxe = { Head = Vector3.new(0, 1.518, -0.256) },
		GoldAxe = { Head = Vector3.new(0, 1.464, -0.031) },
		ObsidianAxe = { Head = Vector3.new(0, 1.501, -0.671) },
		InfernoAxe = { Head = Vector3.new(0, 1.446, -0.479), Glow = Vector3.new(0, 1.072, -0.663) },
		StarfallAxe = { Head = Vector3.new(0, 1.565, -0.082), Glow = Vector3.new(0, 1.565, -0.771) },
		LuxAxe = { Head = Vector3.new(0, 1.497, -0.508), Glow = Vector3.new(0, 1.497, -0.482) },
		HermitsMaul = { Head = Vector3.new(0, 1.503, -0.253) },
	}

	t.test("every axe piece has its authored `at`, and every axe has Handle and Head sizes", function()
		for id, pieces in pairs(EXPECTED) do
			local spec = AxeModels.Get(id)
			t.ok(spec ~= nil, id .. " has a mesh entry")
			t.ok(spec.Handle.size.Y > 0 and spec.Head.size.Y > 0, id .. " has Handle and Head sizes")
			for key, want in pairs(pieces) do
				local at = spec[key].at
				t.ok(at ~= nil, id .. "." .. key .. " has an `at`")
				t.ok((at - want).Magnitude < 1e-6, id .. "." .. key .. " is the authored " .. tostring(want))
			end
			if spec.Glow then
				t.ok(pieces.Glow ~= nil, id .. "'s glow is authored")
			end
		end
	end)

	t.test("built axes put the head and glow at handle centre + at, over the top of the haft", function()
		withMeshes(function()
			local checked = 0
			for id, pieces in pairs(EXPECTED) do
				local def = ItemCatalog.GetAxe(id)
				local model = AxeArt.Build(def)
				local handle = model:FindFirstChild("MeshHandle")
				t.ok(handle ~= nil, id .. " is meshed")
				for key, at in pairs(pieces) do
					local mesh = model:FindFirstChild("Mesh" .. key)
					t.ok(mesh ~= nil, id .. " has Mesh" .. key)
					local off = mesh.CFrame.Position - handle.CFrame.Position
					t.ok((off - at).Magnitude < 0.01, id .. "." .. key .. " off by " .. tostring(off - at))
				end
				local head = model:FindFirstChild("MeshHead")
				local top = handle.CFrame.Position.Y + handle.Size.Y / 2
				local lo, hi = head.CFrame.Position.Y - head.Size.Y / 2, head.CFrame.Position.Y + head.Size.Y / 2
				t.ok(hi > top - 1.2 and lo < top, id .. ": the head's Y range overlaps the haft's top 1.2 studs")
				checked += 1
			end
			t.eq(checked, 11, "ten axes and the Maul")
		end)
	end)

	t.test("the half turn is untouched and the Lux trail points still sit on the blade", function()
		t.ok(math.abs(math.abs(AxeModels.MeshYaw) - math.pi) < 1e-6)
		for name, point in pairs(AxeModels.LuxPoints) do
			t.ok(point.Z < 0, name .. " is on the blade side (-Z)")
		end
	end)
end
