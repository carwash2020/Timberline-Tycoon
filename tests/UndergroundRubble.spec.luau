--!nocheck
-- T414e: the mine's rubble is boulders in CliffRock and QuarrySlate, not eight identical cubes. It
-- still plugs its passage until Lane M clears it: same tag, attributes, part cap and footprint.
return function(t)
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local UndergroundData = t.load("ReplicatedStorage/Shared/World/UndergroundData")

	t.test("every rubble is stone boulders with no bare cube, and it still fills its passage", function()
		local builder = t.server("UndergroundBuilder")
		local folder = t.roblox.Instance.new("Folder")
		local built = builder.Build(folder)
		local seen = 0
		for _, d in ipairs(built:GetDescendants()) do
			if d:IsA("Model") and d:HasTag("Rubble") then
				seen += 1
				local data
				for _, r in ipairs(UndergroundData.Rubble) do
					if r.id == d:GetAttribute("RubbleId") then
						data = r
					end
				end
				t.ok(data ~= nil)
				local n, minX, maxX, minZ, maxZ = 0, math.huge, -math.huge, math.huge, -math.huge
				for _, p in ipairs(d:GetChildren()) do
					n += 1
					t.eq(p.Name, "Stone")
					t.ok(p.Color == Palette.CliffRock or p.Color == Palette.QuarrySlate, "stone colour")
					t.eq(p.Material, t.roblox.Enum.Material.Slate)
					t.eq(p.Anchored, true)
					t.eq(p.CanCollide, true, "it blocks the passage")
					local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
					t.ok(
						p:IsA("WedgePart") or (mesh ~= nil and mesh.MeshType == t.roblox.Enum.MeshType.Sphere),
						"a boulder, not a cube"
					)
					local at = p.CFrame.Position
					local reach = math.max(p.Size.X, p.Size.Z) / 2
					minX, maxX = math.min(minX, at.X - reach), math.max(maxX, at.X + reach)
					minZ, maxZ = math.min(minZ, at.Z - reach), math.max(maxZ, at.Z + reach)
				end
				t.ok(n >= 6 and n <= 12, n .. " boulders")
				local span = math.max(maxX - minX, maxZ - minZ)
				t.ok(span >= 14, "the heap spans the passage, " .. span)
			end
		end
		t.eq(seen, #UndergroundData.Rubble)
	end)
end
