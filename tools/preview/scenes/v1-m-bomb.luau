--!nocheck
-- A sealed-looking rubble wall and a bomb with its fuse lit.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		Kit.part(root, "Floor", V3.new(28, 1, 20), CF.new(0, -0.5, 4), C3.fromRGB(70, 66, 62), Enum.Material.Slate)
		local wall = MiningArt.Rubble("mine-mid", 2)
		wall:PivotTo(CF.new(0, 0, 0))
		wall.Parent = root
		local bomb = MiningArt.Bomb(true)
		bomb:PivotTo(CF.new(0, 0, 8))
		bomb.Parent = root
		local dust = MiningArt.Dust()
		dust:PivotTo(CF.new(2, 2, 2))
		dust.Parent = root
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 30,
			fov = 36,
			cameras = {
				cam(0, 6, 18, 0, 4, 2, "bomb and rubble"),
			},
		}
	end,
}
