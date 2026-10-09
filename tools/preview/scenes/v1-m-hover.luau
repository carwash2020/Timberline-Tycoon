--!nocheck
-- One ore tag at a time. Name on its own board, the pick line under it.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local HoverTag = ctx.shared("HoverTag")
		local OreData = ctx.shared("Mining/OreData")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		local cream = C3.fromRGB(245, 235, 215)
		local danger = C3.fromRGB(192, 80, 58)
		local bark = C3.fromRGB(60, 40, 28)
		local function one(ore, x, z, pickLevel)
			Kit.part(root, "Ground", V3.new(14, 1, 14), CF.new(x, -0.5, z), C3.fromRGB(80, 76, 70), Enum.Material.Slate)
			local node = MiningArt.Node(ore)
			node:PivotTo(CF.new(x, 0, z))
			node.Parent = root
			local _, line, style = HoverTag.Lines({
				key = "Ore:" .. ore.id,
				name = ore.name,
				kind = "Ore",
				itemId = ore.id,
				tier = ore.tier,
				need = ore.hardness,
			}, { hour = 12, loop = 2, pickLevel = pickLevel })
			local nameBoard =
				Kit.part(root, "TagName", V3.new(4.2, 0.7, 0.08), CF.new(x, 4.15, z), bark, Enum.Material.Wood)
			Kit.signText(nameBoard, ore.name, ore.color, { Enum.NormalId.Back })
			local lineBoard =
				Kit.part(root, "TagLine", V3.new(4.2, 0.55, 0.08), CF.new(x, 3.35, z), bark, Enum.Material.Wood)
			local lineColor = if style and style.needs then danger else cream
			Kit.signText(lineBoard, line, lineColor, { Enum.NormalId.Back })
		end
		local iron = OreData.Get("Iron")
		one(iron, 0, 0, 1)
		one(iron, 0, 40, 3)
		local function cam(x, y, z, tx, ty, tz, label, fov)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = fov }
		end
		return {
			root = root,
			shadowRadius = 20,
			fov = 30,
			cameras = {
				cam(-2.2, 3.6, 11, 0, 2.2, 0, "needs iron pick", 30),
				cam(-1.6, 3.2, 49, 0, 2.2, 40, "iron pick met", 32),
			},
		}
	end,
}
