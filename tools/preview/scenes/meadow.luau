--!nocheck
-- The open meadow west of the Starter Forest (STY-03), on terrain sampled
-- every 2 studs, with what MapBuilder builds there: the brown boulder
-- clusters at about (-124, -177) and (-261, -189), the trees, the lone
-- boulders and the scenery. 1 and 2 from a player's eye, 3 from above.

local Site = require("./_site")

return {
	build = function(ctx)
		local built = Site.build(ctx, -360, -330, -40, -20, 2)
		built.cameras = {
			{
				pos = Site.eye(ctx, -150, -150),
				target = Site.eye(ctx, -124, -177),
				label = "eye: a boulder cluster by the Starter Forest",
				fov = 70,
			},
			{
				pos = Site.eye(ctx, -200, -120),
				target = Site.eye(ctx, -261, -189),
				label = "eye: west over the meadow",
				fov = 70,
			},
			{ pos = { -110, 90, -60 }, target = { -200, 0, -190 }, label = "the meadow from above", fov = 60 },
		}
		return built
	end,
}
