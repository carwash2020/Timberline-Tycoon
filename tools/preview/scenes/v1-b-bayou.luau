--!nocheck
-- Bayou basin: top-down and a three-quarter view. Lane R fills it later.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		return {
			root = root,
			terrain = Common.terrain(ctx, -980, -920, -540, -480, 8),
			shadowRadius = 500,
			lighting = { fogNear = 500, fogFar = 1600 },
			fov = 42,
			cameras = {
				{ pos = { -760, 900, -700 }, target = { -760, 0, -700 }, label = "top" },
				{ pos = { -480, 280, -420 }, target = { -760, -4, -700 }, label = "three-quarter" },
			},
		}
	end,
}
