--!nocheck
-- The whole 3,000-stud map: terrain and water.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		return {
			root = root,
			terrain = Common.terrain(ctx, -1500, -1500, 1500, 1500, 12),
			shadowRadius = 1600,
			lighting = { fogNear = 2500, fogFar = 9000 },
			fov = 50,
			cameras = {
				{ pos = { 0, 2600, -1900 }, target = { 0, 0, 100 }, label = "whole map from the south" },
				{ pos = { 0, 3800, 1 }, target = { 0, 0, 0 }, label = "top down" },
				{ pos = { 300, 260, -420 }, target = { 0, 0, 110 }, label = "town + starter forest" },
				{ pos = { -150, 300, 300 }, target = { -500, 20, 300 }, label = "hills + river" },
				{ pos = { 400, 400, 700 }, target = { 1150, 60, 1250 }, label = "volcano" },
				{ pos = { -250, 220, -150 }, target = { -600, 0, -400 }, label = "grove + lake" },
				-- The 14 homestead shelves, from Mill Meadow east of town out to the far pads.
				{ pos = { 40, 1450, -520 }, target = { -20, 0, 140 }, label = "all 14 homesteads" },
				-- Mill Meadow, south of the dealership display lot, and the lane west to the loop.
				{ pos = { 560, 150, -300 }, target = { 360, 0, -40 }, label = "Mill Meadow south of the display lot" },
				-- The Snowfields' plateau edge, where the country changes material.
				{ pos = { 180, 160, 860 }, target = { 0, 30, 1080 }, label = "snowfields border" },
			},
		}
	end,
}
