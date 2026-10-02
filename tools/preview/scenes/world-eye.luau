--!nocheck
-- The world from a player's eye (WLD-19): the same build as world.luau
-- (_world.luau), seen from about 5.5 studs up where players stand. 1 the
-- spawn looking north at the sawmill, 2 the spawn looking south-east, 3 the
-- Snow Road at (30, 450), 4 the beach at (1150, 0), 5 the town gondola
-- station, 6 on the main isle, 7 arriving in the Hills, 8 the Volcano
-- Road's end, 9 view 1 at night. _eye.luau places the cameras.
-- Heavy like world: up to about 3 minutes a view, so shoot one at a time.

local Eye = require("./_eye")
local World = require("./_world")

return {
	build = function(ctx)
		local built = World.build(ctx, { forest = true })
		built.cameras = Eye.cameras(ctx)
		return built
	end,
}
