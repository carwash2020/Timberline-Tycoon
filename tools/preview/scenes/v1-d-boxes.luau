--!nocheck
-- Lane D: shop boxes, front on, so the band, the windows and the plate read.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local ItemBox = ctx.shared("ItemBox")
		local root = roblox.Instance.new("Model")
		local goods = {
			{ "Axe", "SteelAxe", "Steel Axe" },
			{ "Axe", "InfernoAxe", "Inferno Axe" },
			{ "Sawmill", "Millmaster100", "Millmaster 100" },
			{ "Gear", "Lantern", "Lantern" },
			{ "Truck", "Rustbucket", "Rustbucket" },
		}
		local gap = 2
		local x = 0
		local centers = {}
		for i, row in ipairs(goods) do
			local size = ItemBox.Size(row[1], row[2])
			local model = roblox.Instance.new("Model")
			model.Name = row[2]
			local body = Kit.part(
				model,
				"Box",
				size,
				CF.new(0, size.Y / 2, 0),
				C3.fromRGB(34, 36, 41),
				Enum.Material.SmoothPlastic
			)
			body.CanCollide = false
			BoxArt.Dress(model, body, { name = row[3], kind = row[1], itemId = row[2] })
			model:PivotTo(CF.new(x, 0, 0))
			model.Parent = root
			centers[i] = x
			x += size.X + gap
		end
		local width = x
		Kit.part(
			root,
			"Ground",
			V3.new(width + 8, 1, 24),
			CF.new(width / 2 - gap, -0.5, 0),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)
		local function cam(px, py, pz, tx, ty, tz, label)
			return { pos = { px, py, pz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 40,
			fov = 32,
			cameras = {
				cam(width / 2, 3.2, -18, width / 2, 2.2, 0, "five boxes"),
				cam(centers[1], 2.2, -7, centers[1], 1.6, 0, "Steel Axe box"),
				cam(centers[3], 2.6, -9, centers[3], 2.0, 0, "sawmill box"),
			},
		}
	end,
}
