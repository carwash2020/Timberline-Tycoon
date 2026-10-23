--!nocheck
-- T420: Old Hank at his new spot (153.5, 100), on the grass south of the East
-- Link, beside the PLOT DISTRICT sign, facing south. Views:
--   1, 2 the approach path   3 the district corner   4 Hank's front
--   5 the sign's middle line (shoot at 844x390 for the phone crop)
local District = require("./_district")
return {
	build = function(ctx)
		local V3 = ctx.roblox.Vector3
		return District.scene(ctx, V3.new(153.5, 0, 100), V3.new(153.5, 0, 200), function(eye)
			return {
				{
					pos = eye(130.6, 4.6, 81.6),
					target = eye(150, 4, 102),
					label = "approach path (walking the East Link), Hank beside the sign",
					fov = 50,
				},
				{
					pos = eye(130, 4.6, 87.9),
					target = eye(150, 4, 102),
					label = "approach path, a little nearer, Hank beside the sign",
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
				{
					pos = eye(130.5, 8, 96.8),
					target = eye(147, 7.2, 104),
					label = "the sign's middle line, straight on",
					fov = 30,
				},
			}
		end)
	end,
}
