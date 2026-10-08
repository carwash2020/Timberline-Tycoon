--!nocheck
-- Six picks, three a frame, each head a different shape. Nothing cut off.

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
		local function row(list, originZ)
			local gap = 5.2
			local mid = (#list - 1) * gap / 2
			Kit.part(
				root,
				"Ground",
				V3.new(#list * gap + 8, 1, 14),
				CF.new(mid, -0.5, originZ),
				C3.fromRGB(120, 100, 72),
				Enum.Material.WoodPlanks
			)
			for i, pick in ipairs(list) do
				local x = (i - 1) * gap
				local model = MiningArt.Pickaxe(pick)
				model:PivotTo(CF.new(x, 0.15, originZ) * CF.Angles(0, math.rad(70), 0))
				model.Parent = root
				local sign = Kit.part(
					root,
					"Label",
					V3.new(3.2, 0.62, 0.12),
					CF.new(x, 0.4, originZ + 2.3),
					C3.fromRGB(60, 40, 28),
					Enum.Material.Wood
				)
				Kit.signText(sign, pick.name, C3.fromRGB(245, 235, 215), { Enum.NormalId.Back })
			end
			return mid
		end
		local a, b = {}, {}
		for i, pick in ipairs(picks) do
			if i <= 3 then
				table.insert(a, pick)
			else
				table.insert(b, pick)
			end
		end
		local midA = row(a, 0)
		local midB = row(b, 40)
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = 32 }
		end
		return {
			root = root,
			shadowRadius = 24,
			fov = 32,
			cameras = {
				cam(midA - 2, 3.4, 12, midA, 1.6, 0, "rusty copper iron"),
				cam(midB - 2, 3.4, 52, midB, 1.6, 40, "steel obsidian lux"),
			},
		}
	end,
}
