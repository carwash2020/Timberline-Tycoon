--!nocheck
-- Every truck on its own, real meshes, ten views each (front, both sides, the
-- two three-quarters, two wheel close-ups, three low views). Views run in the
-- order of `specimens`: Rustbucket 1-10, Pickup 11-20, ScoutATV 21-30,
-- Flatbed 31-40, LoggingRig 41-50, TimberClassic (part-built, no mesh) 51-60.
local Vehicles = require("./_vehicles")

return {
	build = function(ctx)
		local root, cameras = Vehicles.build(ctx, {
			{ id = "Rustbucket", truck = "Rustbucket" },
			{ id = "Pickup", truck = "Pickup" },
			{ id = "ScoutATV", truck = "ScoutATV" },
			{ id = "Flatbed", truck = "Flatbed" },
			{ id = "LoggingRig", truck = "LoggingRig" },
			{ id = "TimberClassic", truck = "TimberClassic", extras = { doorName = "Timber & Co" } },
		}, "full")
		return Vehicles.scene(root, cameras)
	end,
}
