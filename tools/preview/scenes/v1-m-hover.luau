--!nocheck
-- Depicts the HoverTag lines on ore rocks. The live label is HoverTagUI;
-- this scene only paints that text so a render can show it.

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
		Kit.part(root, "Ground", V3.new(24, 1, 16), CF.new(4, -0.5, 0), C3.fromRGB(80, 76, 70), Enum.Material.Slate)
		local danger = C3.fromRGB(192, 80, 58)
		local cream = C3.fromRGB(245, 235, 215)
		local function card(ore, x, pickLevel)
			local node = MiningArt.Node(ore)
			node:PivotTo(CF.new(x, 0, 0))
			node.Parent = root
			local _, line, style = HoverTag.Lines({
				key = "Ore:" .. ore.id,
				name = ore.name,
				kind = "Ore",
				itemId = ore.id,
				tier = ore.tier,
				need = ore.hardness,
			}, { hour = 12, loop = 2, pickLevel = pickLevel })
			local board = Kit.part(
				root,
				"Tag",
				V3.new(5.5, 1.6, 0.12),
				CF.new(x, 4.2, 0),
				C3.fromRGB(60, 40, 28),
				Enum.Material.Wood
			)
			local lineColor = if style and style.needs then danger else cream
			Kit.signText(board, ore.name .. "\n" .. line, lineColor, { Enum.NormalId.Front, Enum.NormalId.Back })
		end
		card(OreData.Get("Iron"), 0, 1)
		card(OreData.Get("Iron"), 8, 3)
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 24,
			fov = 32,
			cameras = {
				cam(4, 4, 14, 4, 2, 0, "pc hover lines"),
				cam(4, 3.2, 8, 4, 2.2, 0, "phone hover lines"),
			},
		}
	end,
}
