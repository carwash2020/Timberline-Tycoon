--!nocheck
-- Craft bench in the world, and a flat stand-in of the craft panel
-- (the live panel is CraftUI; the renderer draws parts).

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		Kit.part(
			root,
			"Ground",
			V3.new(30, 1, 16),
			CF.new(-6, -0.5, 0),
			C3.fromRGB(120, 104, 78),
			Enum.Material.WoodPlanks
		)
		local bench = MiningArt.CraftBench()
		bench:PivotTo(CF.new(-8, 0, 0))
		bench.Parent = root
		local paper = C3.fromRGB(240, 225, 195)
		local ink = C3.fromRGB(60, 40, 20)
		local bark = C3.fromRGB(90, 62, 36)
		local muted = C3.fromRGB(140, 124, 104)
		local panel = Kit.part(root, "Panel", V3.new(10, 6, 0.2), CF.new(4, 3.2, 0), paper, Enum.Material.SmoothPlastic)
		Kit.signText(panel, "Craft", ink, { Enum.NormalId.Back })
		local rows =
			{ "Miner's Lamp", "Hardhat", "Bomb Bundle", "Rope Ladder", "Copper Lamp Post", "Gold-banded Chest" }
		for i, name in ipairs(rows) do
			local y = 5.2 - i * 0.85
			local row = Kit.part(
				root,
				"Row",
				V3.new(9.2, 0.7, 0.16),
				CF.new(4, y, 0.35),
				C3.fromRGB(214, 196, 164),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(row, name, ink, { Enum.NormalId.Back })
			local soon = i >= 5
			local button = Kit.part(
				root,
				"Soon",
				V3.new(1.8, 0.7, 0.18),
				CF.new(7.6, y, 0.55),
				if soon then muted else C3.fromRGB(63, 122, 52),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(button, if soon then "Soon" else "Craft", C3.fromRGB(245, 235, 215), { Enum.NormalId.Back })
		end
		local close =
			Kit.part(root, "Close", V3.new(1.6, 0.7, 0.18), CF.new(7.8, 5.5, 0.55), bark, Enum.Material.SmoothPlastic)
		Kit.signText(close, "Close", C3.fromRGB(245, 235, 215), { Enum.NormalId.Back })
		local function cam(x, y, z, tx, ty, tz, label, fov)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = fov }
		end
		return {
			root = root,
			shadowRadius = 24,
			fov = 32,
			cameras = {
				cam(-2, 4, 14, -2, 2, 0, "bench and panel", 36),
				cam(4, 3.2, 8.5, 4, 3.2, 0, "craft panel", 28),
			},
		}
	end,
}
