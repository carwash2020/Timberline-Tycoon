--!nocheck
-- Ore rocks, at most four a frame, three-quarter view. Plaques face the camera.

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
		local function group(list, originZ)
			local gap = 6.5
			local mid = (#list - 1) * gap / 2
			Kit.part(
				root,
				"Ground",
				V3.new(#list * gap + 6, 1, 16),
				CF.new(mid, -0.5, originZ + 1),
				C3.fromRGB(92, 88, 82),
				Enum.Material.Slate
			)
			for i, ore in ipairs(list) do
				local x = (i - 1) * gap
				local node = MiningArt.Node(ore)
				node:PivotTo(CF.new(x, 0, originZ))
				node.Parent = root
				local chunk = MiningArt.Chunk(ore)
				chunk:PivotTo(CF.new(x - 1.1, 0, originZ + 2.4))
				chunk.Parent = root
				local ingot = MiningArt.Ingot(ore)
				if ingot then
					ingot:PivotTo(CF.new(x + 1.1, 0, originZ + 2.4))
					ingot.Parent = root
				end
				local sign = Kit.part(
					root,
					"Label",
					V3.new(3.4, 0.7, 0.12),
					CF.new(x, 0.55, originZ + 3.6),
					C3.fromRGB(60, 40, 28),
					Enum.Material.Wood
				)
				-- Back faces +Z, which is where the camera sits.
				Kit.signText(sign, ore.name, ore.color, { Enum.NormalId.Back })
			end
			return mid
		end
		local first = {}
		local second = {}
		for i, ore in ipairs(ores) do
			if i <= 4 then
				table.insert(first, ore)
			else
				table.insert(second, ore)
			end
		end
		local midA = group(first, 0)
		local midB = group(second, 50)
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = 34 }
		end
		return {
			root = root,
			shadowRadius = 40,
			fov = 34,
			cameras = {
				cam(midA - 4, 5.5, 18, midA, 1.3, 1, "first four ores"),
				cam(midB - 3, 5.2, 68, midB, 1.3, 51, "last three ores"),
			},
		}
	end,
}
