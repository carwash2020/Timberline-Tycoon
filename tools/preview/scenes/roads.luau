--!nocheck
-- The haul roads close up (STY-02): where the Volcano Road leaves the Snow
-- Road at (30, 450), on terrain sampled every 2 studs, with the trees,
-- boulders and scenery MapBuilder builds there. 1 up the Snow Road from a
-- player's eye, 2 along the Volcano Road, 3 the fork from above, 4 the fork
-- looking down.

local Site = require("./_site")

return {
	build = function(ctx)
		local built = Site.build(ctx, -150, 330, 250, 620, 2)
		local function at(x, z, up)
			local e = Site.eye(ctx, x, z)
			e[2] += up or 0
			return e
		end
		built.cameras = {
			{ pos = at(23, 390), target = at(9, 580), label = "eye: up the Snow Road to the fork", fov = 70 },
			{ pos = at(80, 477), target = at(230, 558), label = "eye: along the Volcano Road", fov = 70 },
			{ pos = { 150, 70, 380 }, target = { 30, 0, 470 }, label = "the fork from above", fov = 60 },
			{ pos = { 40, 150, 420 }, target = { 30, 0, 455 }, label = "the fork looking down", fov = 60 },
		}
		return built
	end,
}
