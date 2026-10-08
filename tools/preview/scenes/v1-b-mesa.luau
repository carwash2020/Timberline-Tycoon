--!nocheck
-- Red Mesa pad: top-down and a three-quarter view. Lane R fills it later.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		return {
			root = root,
			terrain = Common.terrain(ctx, 400, -980, 780, -600, 8),
			shadowRadius = 420,
			lighting = { fogNear = 500, fogFar = 1600 },
			fov = 42,
			cameras = {
				{ pos = { 590, 800, -790 }, target = { 590, 0, -790 }, label = "top" },
				{ pos = { 360, 260, -520 }, target = { 590, 0, -790 }, label = "three-quarter" },
			},
		}
	end,
}
