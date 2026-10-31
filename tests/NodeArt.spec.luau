--!nocheck
-- T414e: a mining node is a rock outcrop with ore veins, not a crystal cluster or a cube. The look is
-- decor inside the hit box NodeService makes; the hit box, the attributes and the payout are
-- NodeService.spec's.
return function(t)
	local roblox = t.roblox
	local Vector3, Enum = roblox.Vector3, roblox.Enum
	local NodeArt = t.load("ReplicatedStorage/Shared/Art/NodeArt")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- The world-axis half extents of a part's turned box: exact for a wedge, and the true bound of
	-- an ellipsoid, whose sphere mesh fills the same box's inscribed ellipsoid.
	local function reach(p)
		local c, h = p.CFrame, p.Size / 2
		local function along(axis)
			return math.sqrt((c.XVector[axis] * h.X) ^ 2 + (c.YVector[axis] * h.Y) ^ 2 + (c.ZVector[axis] * h.Z) ^ 2)
		end
		return along("X"), along("Y"), along("Z")
	end

	t.test("the body is CliffRock and QuarrySlate stone, no cube, no Neon, no glass", function()
		for seed = 1, 12 do
			local model = NodeArt.Build(seed)
			local rocks, veins = 0, 0
			for _, p in ipairs(parts(model)) do
				t.ok(p.Material ~= Enum.Material.Neon and p.Material ~= Enum.Material.Glass, p.Name)
				if p.Name == "Rock" or p.Name == "RockFace" then
					rocks += 1
					t.ok(p.Color == Palette.CliffRock or p.Color == Palette.QuarrySlate, "rock colour")
					t.eq(p.Material, Enum.Material.Slate)
					t.ok(
						p:IsA("WedgePart") or p:FindFirstChildWhichIsA("SpecialMesh") ~= nil,
						"a boulder or a wedge, never a bare block"
					)
				elseif p.Name == "Vein" then
					veins += 1
				end
			end
			t.ok(rocks >= 3, "a cluster of boulders")
			t.ok(veins >= 3, "with ore running through it")
		end
	end)

	t.test("veins are ore colours, Amber or Garnet, and a node shows one ore", function()
		local seen = {}
		for seed = 1, 12 do
			local model = NodeArt.Build(seed)
			local colour
			for _, p in ipairs(parts(model)) do
				if p.Name == "Vein" then
					t.ok(
						p.Color == t.load("ReplicatedStorage/Shared/Art/Kit").hex("#D98A1E")
							or p.Color == t.load("ReplicatedStorage/Shared/Art/Kit").hex("#7A2038"),
						"an ore hex"
					)
					colour = colour or p.Color
					t.eq(p.Color, colour, "one ore per node")
				end
			end
			seen[tostring(colour)] = true
		end
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		t.eq(n, 2, "both ores turn up")
		t.eq(NodeArt.VeinHex.Amber, "#D98A1E")
		t.eq(NodeArt.VeinHex.Garnet, "#7A2038")
	end)

	t.test("looks only, standing on the ground, not floating, wrapped by the hit box", function()
		local half = NodeArt.Footprint
		for seed = 1, 12 do
			local lowest, highest = math.huge, -math.huge
			for _, p in ipairs(parts(NodeArt.Build(seed))) do
				t.eq(p.CanCollide, false, p.Name .. " is decor: the hit box collides")
				t.eq(p.CanQuery, false)
				local rx, ry, rz = reach(p)
				local at = p.CFrame.Position
				lowest = math.min(lowest, at.Y - ry)
				highest = math.max(highest, at.Y + ry)
				t.ok(math.abs(at.X) + rx <= half.X / 2 + 0.01, "inside the hit box in x, seed " .. seed)
				t.ok(math.abs(at.Z) + rz <= half.Z / 2 + 0.01, "inside the hit box in z, seed " .. seed)
			end
			t.ok(lowest >= -0.3 and lowest <= 0.35, "sits on the ground, " .. lowest)
			t.ok(highest <= NodeArt.Height, "under the hit box top, " .. highest)
		end
	end)

	-- T416 item 4: the body is faceted. Wedge clusters, turned off the axes, in Slate; no ellipsoid
	-- (a sphere mesh), no bare block, and the veins and hit-box footprint are as before.
	local function alignedToAxes(cf)
		local function axisAligned(v)
			return math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) > 0.995
		end
		return axisAligned(cf.XVector) and axisAligned(cf.YVector) and axisAligned(cf.ZVector)
	end

	t.test(
		"T416: the rock is faceted wedge clusters in Slate: no sphere mesh, no block, none left square to the axes",
		function()
			local colours = {}
			for seed = 1, 12 do
				local model = NodeArt.Build(seed)
				local rocks = 0
				for _, d in ipairs(model:GetDescendants()) do
					t.ok(not d:IsA("SpecialMesh"), "no sphere or mesh stand-in (" .. d.Name .. ")")
					if d:IsA("BasePart") and (d.Name == "Rock" or d.Name == "RockFace") then
						rocks += 1
						t.eq(d.ClassName, "WedgePart", d.Name .. " is a wedge facet")
						t.eq(d.Material, Enum.Material.Slate)
						t.ok(not alignedToAxes(d.CFrame), "a facet turned off the axes")
						colours[tostring(d.Color)] = true
					end
				end
				t.ok(rocks >= 8, "a cluster of facets: " .. rocks)
			end
			t.ok(colours[tostring(Palette.CliffRock)] and colours[tostring(Palette.QuarrySlate)], "both stone colours")
		end
	)

	t.test("T416: no part of a node is a ball, a bare block or a cylinder except the thin ore bars", function()
		for seed = 1, 12 do
			for _, p in ipairs(parts(NodeArt.Build(seed))) do
				if p.Name ~= "Vein" then
					t.eq(p.ClassName, "WedgePart", p.Name)
				end
			end
		end
	end)
end
