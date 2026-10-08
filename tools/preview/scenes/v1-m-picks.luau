--!nocheck
-- The pick ladder, Lux last. No light on the Lux pick.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local PickaxeData = ctx.shared("Mining/PickaxeData")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		local picks = PickaxeData.All()
		local gap = 4
		Kit.part(
			root,
			"Ground",
			V3.new(#picks * gap + 6, 1, 14),
			CF.new((#picks - 1) * gap / 2, -0.5, 0),
			C3.fromRGB(120, 100, 72),
			Enum.Material.WoodPlanks
		)
		for i, pick in ipairs(picks) do
			local x = (i - 1) * gap
			local model = MiningArt.Pickaxe(pick)
			model:PivotTo(CF.new(x, 0.2, 0) * CF.Angles(0, math.pi / 2, 0))
			model.Parent = root
			local sign = Kit.part(
				root,
				"Label",
				V3.new(3.2, 0.7, 0.15),
				CF.new(x, 0.4, 2.4),
				C3.fromRGB(60, 40, 28),
				Enum.Material.Wood
			)
			Kit.signText(sign, pick.name, C3.fromRGB(245, 235, 215), { Enum.NormalId.Front, Enum.NormalId.Back })
		end
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local mid = (#picks - 1) * gap / 2
		return {
			root = root,
			shadowRadius = 30,
			fov = 32,
			cameras = {
				cam(mid, 4, 14, mid, 1.2, 0, "pickaxe tiers"),
				cam(mid + 6, 3, 8, (#picks - 1) * gap, 1.2, 0, "lux pickaxe"),
			},
		}
	end,
}
