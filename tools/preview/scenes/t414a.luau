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
			-- Step 1, not 4: a 4-stud sample draws the paving edge as stairs.
			terrain = Common.terrain(ctx, -140, -80, 180, 210, 1),
			shadowRadius = 160,
			fov = 50,
			cameras = {
				{ pos = { 0, 220, 80 }, target = { 0, 0, 80 }, fov = 40, label = "midday plaza, top down" },
				{ pos = { 2, 5.5, 40 }, target = { 0, 1, 78 }, fov = 55, label = "midday street, spawn walk" },
				{ pos = { -70, 6, 42 }, target = { -80, 0.5, 57 }, fov = 35, label = "midday kerb" },
				{ pos = { 20, 260, 30 }, target = { 20, 0, 30 }, fov = 45, label = "midday overlap" },
				{ pos = { -20, 1.8, 66 }, target = { -50, 1.2, 80 }, fov = 70, label = "midday eye level, plaza" },
				{
					pos = { 141, 1.8, 52 },
					target = { 160, 0.6, 64 },
					fov = 45,
					label = "midday East Link kerb, outside the drive edge",
				},
				{ pos = { 60, 1.8, 0 }, target = { 100, 0.4, 30 }, fov = 65, label = "midday lot cobble, eye height" },
			},
		}
	end,
}
