-- T414a town ground. The plaza, the street and one kerb, on the real terrain.
-- Before: flat strips. After: terrain paint and a low stone kerb.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		local TownGroundArt = ctx.art("TownGroundArt")
		TownGroundArt.Build().Parent = root
		return {
			root = root,
			terrain = Common.terrain(ctx, -140, -80, 180, 210, 4),
			shadowRadius = 160,
			fov = 50,
			cameras = {
				{ pos = { 0, 220, 80 }, target = { 0, 0, 80 }, fov = 40, label = "spawn plaza, top down" },
				{ pos = { 2, 5.5, 40 }, target = { 0, 1, 78 }, fov = 55, label = "street level, spawn walk" },
				{ pos = { -80, 2.4, 54 }, target = { -80, 0.4, 63 }, fov = 40, label = "kerb close-up" },
				{ pos = { 20, 260, 30 }, target = { 20, 0, 30 }, fov = 45, label = "overlap map, top down" },
			},
		}
	end,
}
