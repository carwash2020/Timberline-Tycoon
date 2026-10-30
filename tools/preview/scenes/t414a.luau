-- T414a town ground, midday. The plaza, the street and one kerb, on the real terrain.
-- Before: flat strips. After: cobble and asphalt paint, a slate kerb, dirt paths.

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
				{ pos = { 0, 220, 80 }, target = { 0, 0, 80 }, fov = 40, label = "midday plaza, top down" },
				{ pos = { 2, 5.5, 40 }, target = { 0, 1, 78 }, fov = 55, label = "midday street, spawn walk" },
				{ pos = { -70, 6, 42 }, target = { -80, 0.5, 57 }, fov = 35, label = "midday kerb" },
				{ pos = { 20, 260, 30 }, target = { 20, 0, 30 }, fov = 45, label = "midday overlap" },
			},
		}
	end,
}
