--!nocheck
-- Lane D: one stepped shelf unit, 8 wide by 3 deep.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local ShelfLayout = ctx.shared("ShelfLayout")
		local root = roblox.Instance.new("Model")
		local shelf = ShelfLayout.Build()
		shelf.Parent = root
		Kit.part(
			root,
			"Ground",
			V3.new(16, 1, 12),
			CF.new(0, -0.5, 1.5),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)
		local function cam(px, py, pz, tx, ty, tz, label)
			return { pos = { px, py, pz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 20,
			fov = 32,
			cameras = {
				cam(0, 2.4, -10, 0, 2.2, 1.5, "shelf from the front"),
				cam(8, 3.2, -4, 0, 2.2, 1.5, "shelf from the side"),
			},
		}
	end,
}
