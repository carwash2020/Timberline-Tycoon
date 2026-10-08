--!nocheck
-- Lane D: the town store board, from the front.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local StoreBoard = ctx.shared("StoreBoard")
		local root = roblox.Instance.new("Model")
		local board = StoreBoard.Build()
		board.Parent = root
		Kit.part(root, "Ground", V3.new(24, 1, 16), CF.new(0, -0.5, 2), C3.fromRGB(116, 164, 84), Enum.Material.Grass)
		local function cam(px, py, pz, tx, ty, tz, label)
			return { pos = { px, py, pz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 30,
			fov = 32,
			cameras = {
				cam(0, 4.2, -16, 0, 4.5, 0, "store board"),
			},
		}
	end,
}
