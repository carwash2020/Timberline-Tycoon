--!nocheck
-- T420, the "before": Old Hank at (149.4, 86.7), where he stood behind the
-- Land Office counter, which was ON the East Link. The counter box is a
-- PlotService build and is not drawn here: only Hank, the sign and the road.
-- Same cameras as district-after (views 1 to 4).
local District = require("./_district")
return {
	build = function(ctx)
		local V3 = ctx.roblox.Vector3
		return District.scene(ctx, V3.new(149.4, 0, 86.7), V3.new(0, 0, 40), function(eye)
			return {
				{
					pos = eye(130.6, 4.6, 81.6),
					target = eye(149.4, 4, 86.7),
					label = "approach path (walking the East Link), Hank on the road",
					fov = 50,
				},
				{
					pos = eye(130, 4.6, 87.9),
					target = eye(149.4, 4, 86.7),
					label = "approach path, a little nearer, Hank on the road",
					fov = 50,
				},
				{
					pos = eye(125, 22, 70),
					target = eye(152, 4, 100),
					label = "the district corner from the north-west: the East Link, the sign, Hank",
					fov = 60,
				},
				{
					pos = eye(170, 7, 128),
					target = eye(151, 5, 100),
					label = "from the south-east: Hank's front, the sign behind him",
					fov = 55,
				},
			}
		end)
	end,
}
