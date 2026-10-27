--!nocheck
-- T409 before/after: Frostpeak against Skyroot, the gate lodge, and one belt.
local Common = require("./_common")

return {
	build = function(ctx)
		local root = ctx.roblox.Instance.new("Model")
		return {
			root = root,
			terrain = Common.terrain(ctx, -520, -240, 80, 1220, 8),
			shadowRadius = 40,
			lighting = { fogNear = 4000, fogFar = 9000 },
			fov = 40,
			cameras = {
				{
					pos = { -200, 1400, 900 },
					target = { -200, 40, 900 },
					label = "Frostpeak meets Skyroot, top down",
				},
				{
					pos = { -40, 280, 620 },
					target = { -40, 20, 720 },
					label = "gate lodge on the Skyroot approach",
				},
				{
					pos = { 40, 90, -160 },
					target = { -36, 8, -160 },
					label = "Valley Trunk belt, cross section",
				},
			},
		}
	end,
}
