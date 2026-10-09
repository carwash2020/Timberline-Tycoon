--!nocheck
-- SpecBuild: rows become parts, small ones are decor, cylinders lie on X.
return function(t)
	local roblox = t.roblox
	local V3, CF = roblox.Vector3, roblox.CFrame
	local SpecBuild = t.load("ReplicatedStorage/Shared/Art/SpecBuild")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")

	local function model()
		local m = roblox.Instance.new("Model")
		m.Name = "Spec"
		return m
	end

	t.test("parts, wedges, cylinders, balls and ellipsoids land on the origin", function()
		local parent = model()
		local origin = CF.new(10, 0, -4)
		local rows = {
			{
				name = "Block",
				kind = "part",
				size = V3.new(4, 2, 1),
				at = CF.new(0, 1, 0),
				color = "TimberBrown",
				mat = roblox.Enum.Material.Wood,
			},
			{
				name = "Slope",
				kind = "wedge",
				size = V3.new(4, 1, 2),
				at = CF.new(0, 3, 0),
				color = "RoofSlate",
			},
			{
				name = "Log",
				kind = "cyl",
				size = V3.new(6, 1.2, 1.2),
				at = CF.new(0, 2, 2),
				color = "#7A5230",
			},
			{
				name = "Orb",
				kind = "ball",
				size = V3.new(1.5, 1.5, 1.5),
				at = CF.new(2, 2, 0),
				color = "Brass",
			},
			{
				name = "Egg",
				kind = "ellipsoid",
				size = V3.new(1.2, 2, 1.2),
				at = CF.new(-2, 2, 0),
				color = "StoneBase",
			},
		}
		local made = SpecBuild.Build(parent, rows, origin)
		t.eq(#made, 5)
		t.eq(made[1].CFrame.Position, V3.new(10, 1, -4))
		t.eq(made[1].Color, Palette.TimberBrown)
		t.eq(made[1].Material, roblox.Enum.Material.Wood)
		t.eq(made[1].CanCollide, true)
		t.eq(made[2].ClassName, "WedgePart")
		t.eq(made[3].Shape, roblox.Enum.PartType.Cylinder)
		t.eq(made[3].Size.X, 6)
		t.eq(made[3].Color, Kit.hex("#7A5230"))
		t.eq(made[4].Shape, roblox.Enum.PartType.Ball)
		t.ok(made[5]:FindFirstChildOfClass("SpecialMesh") ~= nil, "ellipsoid mesh")
	end)

	t.test("a part under 1 stud is decor and casts no shadow", function()
		local parent = model()
		local made = SpecBuild.Build(parent, {
			{
				name = "Peg",
				kind = "part",
				size = V3.new(0.4, 0.8, 0.2),
				at = CF.new(0, 0.4, 0),
				color = "IronBlack",
			},
			{
				name = "Nail",
				kind = "part",
				size = V3.new(0.3, 0.3, 0.3),
				at = CF.new(1, 0.2, 0),
				color = "IronBlack",
				decor = false,
			},
		}, CF.identity)
		t.eq(made[1].CanCollide, false)
		t.eq(made[1].CanQuery, false)
		t.eq(made[1].CastShadow, false)
		t.eq(made[2].CanCollide, true, "decor = false keeps the collision")
		t.eq(made[2].CastShadow, false, "still no shadow under 1 stud")
		t.eq(made[2].Shape, roblox.Enum.PartType.Block)
	end)

	t.test("decor = true forces a large part to be looks only", function()
		local parent = model()
		local made = SpecBuild.Build(parent, {
			{
				name = "Strip",
				kind = "part",
				size = V3.new(6, 0.15, 0.1),
				at = CF.new(0, 2, 0),
				color = "SparkTeal",
				mat = roblox.Enum.Material.Neon,
				decor = true,
			},
		}, CF.identity)
		t.eq(made[1].CanCollide, false)
		t.eq(made[1].Material, roblox.Enum.Material.Neon)
		t.eq(made[1].Size.X, 6)
	end)

	t.test("a cone adds facets and an unknown kind or colour fails", function()
		local parent = model()
		local made = SpecBuild.Build(parent, {
			{
				name = "Spire",
				kind = "cone",
				size = V3.new(2, 4, 2),
				at = CF.new(0, 0, 0),
				color = "BarnRed",
			},
		}, CF.identity)
		t.ok(#made >= 6, "facets: " .. #made)
		t.eq(made[1].Name, "Spire")
		t.fails(function()
			SpecBuild.Build(parent, {
				{ name = "X", kind = "mesh", size = V3.new(1, 1, 1), at = CF.identity, color = "Brass" },
			}, CF.identity)
		end, "unknown spec kind")
		t.fails(function()
			SpecBuild.Build(parent, {
				{ name = "X", kind = "part", size = V3.new(1, 1, 1), at = CF.identity, color = "Nope" },
			}, CF.identity)
		end, "unknown")
	end)
end
