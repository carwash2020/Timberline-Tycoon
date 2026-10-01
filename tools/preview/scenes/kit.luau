--!nocheck
-- The art kit's primitives: a triangle, a cone, a blob, a little cabin.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 80)
		-- A lone triangle (two wedges) and a faceted cone: if the wedge
		-- geometry were wrong, these would show gaps and spikes.
		Kit.triangle(root, V3.new(-20, 1, 0), V3.new(-12, 1, 0), V3.new(-16, 9, 0), C3.fromRGB(230, 120, 60), nil, 0.2)
		local rng = Kit.rng(7)
		Kit.cone(root, CF.new(-4, 0, 0), 4, 9, 7, function(i)
			return Kit.shade(C3.fromRGB(60, 130, 70), (i % 2) * 0.12)
		end, nil, 0.1)
		Kit.blob(
			root,
			"Leaves",
			CF.new(8, 6, 0),
			V3.new(7, 6, 7),
			6,
			rng,
			{ C3.fromRGB(110, 170, 70), C3.fromRGB(90, 150, 60) }
		)
		-- A tiny cabin.
		local cabin = CF.new(0, 0, 18)
		Kit.plankWall(
			root,
			"Wall",
			cabin * CF.new(0, 3, -4),
			10,
			6,
			0.6,
			6,
			rng,
			{ C3.fromRGB(140, 95, 60), C3.fromRGB(125, 85, 52) }
		)
		Kit.plankWall(root, "Wall", cabin * CF.new(0, 3, 4), 10, 6, 0.6, 6, rng, { C3.fromRGB(140, 95, 60) })
		Kit.plankWall(
			root,
			"Wall",
			cabin * CF.new(-5, 3, 0) * CF.Angles(0, math.pi / 2, 0),
			8,
			6,
			0.6,
			6,
			rng,
			{ C3.fromRGB(140, 95, 60) }
		)
		Kit.plankWall(
			root,
			"Wall",
			cabin * CF.new(5, 3, 0) * CF.Angles(0, math.pi / 2, 0),
			8,
			6,
			0.6,
			6,
			rng,
			{ C3.fromRGB(140, 95, 60) }
		)
		Kit.gableRoof(
			root,
			"Roof",
			cabin * CF.new(0, 6, 0),
			12,
			10,
			3.5,
			C3.fromRGB(110, 70, 50),
			roblox.Enum.Material.WoodPlanks
		)
		Kit.window(root, cabin * CF.new(2.5, 3.2, -4.4), 2, 2, C3.fromRGB(90, 60, 40), true)
		Kit.lantern(root, cabin * CF.new(-2.5, 4.5, -4.9))
		local sign = Kit.part(
			root,
			"Sign",
			V3.new(6, 2, 0.3),
			CF.new(0, 4, 10),
			C3.fromRGB(120, 80, 50),
			roblox.Enum.Material.Wood
		)
		Kit.signText(sign, "KIT TEST", C3.fromRGB(250, 240, 220))
		Kit.rock(root, CF.new(14, 0, 10), 3, rng, { C3.fromRGB(130, 128, 120) })
		return {
			root = root,
			cameras = {
				{ pos = { 0, 18, -38 }, target = { 0, 4, 6 }, label = "front" },
				{ pos = { 30, 22, 40 }, target = { 0, 3, 10 }, label = "back" },
			},
		}
	end,
}
