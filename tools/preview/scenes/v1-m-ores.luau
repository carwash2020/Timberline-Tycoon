--!nocheck
-- The seven ores as rocks, with a chunk and an ingot in front of each.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local OreData = ctx.shared("Mining/OreData")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		local ores = OreData.All()
		local gap = 7
		Kit.part(
			root,
			"Ground",
			V3.new(#ores * gap + 8, 1, 18),
			CF.new((#ores - 1) * gap / 2, -0.5, 1),
			C3.fromRGB(90, 86, 80),
			Enum.Material.Slate
		)
		for i, ore in ipairs(ores) do
			local x = (i - 1) * gap
			local node = MiningArt.Node(ore)
			node:PivotTo(CF.new(x, 0, 0))
			node.Parent = root
			local chunk = MiningArt.Chunk(ore)
			chunk:PivotTo(CF.new(x - 1.2, 0, 3.2))
			chunk.Parent = root
			local ingot = MiningArt.Ingot(ore)
			if ingot then
				ingot:PivotTo(CF.new(x + 1.2, 0, 3.2))
				ingot.Parent = root
			end
			local sign = Kit.part(
				root,
				"Label",
				V3.new(4.2, 0.9, 0.2),
				CF.new(x, 0.5, 5.2),
				C3.fromRGB(60, 40, 28),
				Enum.Material.Wood
			)
			Kit.signText(sign, ore.name, ore.color, { Enum.NormalId.Front, Enum.NormalId.Back })
		end
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local mid = (#ores - 1) * gap / 2
		return {
			root = root,
			shadowRadius = 40,
			fov = 32,
			cameras = {
				cam(mid, 6, 22, mid, 1.5, 0, "ore rocks, chunks, ingots"),
				cam(0, 3, 8, 0, 1.2, 0, "coal and copper"),
				cam(mid, 3.2, 9, 3 * gap, 1.4, 0, "opal and heartstone"),
			},
		}
	end,
}
