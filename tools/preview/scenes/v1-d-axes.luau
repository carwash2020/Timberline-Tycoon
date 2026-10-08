--!nocheck
-- Lane D: the axe ladder side-on, so each silhouette reads on its own.
-- Order is the cash ladder, then the Lux Axe, then the Hermit's Maul.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local axes = {}
		for _, def in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(axes, def)
		end
		local lux = ItemCatalog.GetAxe("LuxAxe")
		local maul = ItemCatalog.GetAxe("HermitsMaul")
		if lux then
			table.insert(axes, lux)
		end
		if maul then
			table.insert(axes, maul)
		end

		local GAP = 3.4
		local width = (#axes - 1) * GAP
		Kit.part(
			root,
			"Ground",
			V3.new(width + 18, 1, 20),
			CF.new(width / 2, -0.5, -1),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)
		for i, def in ipairs(axes) do
			local x = (i - 1) * GAP
			local axe = AxeArt.Build(def)
			axe:PivotTo(CF.new(x, 0, 0) * CF.Angles(0, math.pi / 2, 0))
			axe.Parent = root
			local sign = Kit.part(
				root,
				"Label",
				V3.new(2.8, 0.7, 0.12),
				CF.new(x, 0.42, -5.4),
				C3.fromHex("#F3E7C9"), -- SignCream
				Enum.Material.SmoothPlastic
			)
			Kit.signText(sign, def.displayName, C3.fromHex("#2A2420"), { Enum.NormalId.Front }) -- SignInk
		end

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local function at(i)
			return (i - 1) * GAP
		end
		local cameras = {
			cam(width / 2, 3.4, -24, width / 2, 1.7, 0, "eleven axes side-on"),
			cam(at(2), 2.4, -8, at(2), 2.0, 0, "Rusty, Steel, Hardened"),
			cam(at(5), 2.4, -8, at(5), 2.0, 0, "Silver, Cobalt, Gold"),
			cam(at(8), 2.4, -8, at(8), 2.2, 0, "Obsidian, Inferno, Starfall"),
			cam(at(10.5), 2.4, -8, at(10.5), 2.0, 0, "Lux and the Hermit's Maul"),
		}
		for i, def in ipairs(axes) do
			local x = at(i)
			table.insert(cameras, cam(x, 2.1, -6.2, x, 2.0, 0, def.displayName))
		end
		return {
			root = root,
			shadowRadius = 70,
			fov = 32,
			cameras = cameras,
		}
	end,
}
