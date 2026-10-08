--!nocheck
-- Lane D: temper colours on a Steel Axe, so the trim reads on its own.
-- Swift, Keen, Prosperous, each at tiers 1, 2 and 3.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local steel = ItemCatalog.GetAxe("SteelAxe")
		local looks = {
			{ "Swift", 1 },
			{ "Swift", 2 },
			{ "Swift", 3 },
			{ "Keen", 1 },
			{ "Keen", 2 },
			{ "Keen", 3 },
			{ "Prosperous", 1 },
			{ "Prosperous", 2 },
			{ "Prosperous", 3 },
		}
		local roman = { "I", "II", "III" }
		local GAP = 3.4
		local width = (#looks - 1) * GAP
		Kit.part(
			root,
			"Ground",
			V3.new(width + 16, 1, 16),
			CF.new(width / 2, -0.5, -1),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)
		for i, row in ipairs(looks) do
			local x = (i - 1) * GAP
			local axe = AxeArt.Build(steel)
			AxeArt.ApplyTemper(axe, row[1], row[2])
			axe:PivotTo(CF.new(x, 0, 0) * CF.Angles(0, math.pi / 2, 0))
			axe.Parent = root
			local sign = Kit.part(
				root,
				"Label",
				V3.new(2.8, 0.7, 0.12),
				CF.new(x, 0.42, -5.2),
				C3.fromHex("#F3E7C9"), -- SignCream
				Enum.Material.SmoothPlastic
			)
			Kit.signText(sign, row[1] .. " " .. roman[row[2]], C3.fromHex("#2A2420"), { Enum.NormalId.Front }) -- SignInk
		end

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local function at(i)
			return (i - 1) * GAP
		end
		local cameras = {
			cam(width / 2, 3.2, -22, width / 2, 1.8, 0, "nine temper looks"),
		}
		for i, row in ipairs(looks) do
			local x = at(i)
			table.insert(cameras, cam(x, 2.1, -6.2, x, 2.0, 0, row[1] .. " " .. roman[row[2]]))
		end
		return {
			root = root,
			shadowRadius = 60,
			fov = 32,
			cameras = cameras,
		}
	end,
}
