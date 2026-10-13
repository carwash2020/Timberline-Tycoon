--!nocheck
-- The part-built art of every truck and trailer (no mesh): the look a vehicle
-- has while its meshes load, the Timber Classic's look for good, and the look
-- of the Dealership's trailer copies. Ten views each for the six trucks, in
-- the order Rustbucket, Pickup, ScoutATV, Flatbed, LoggingRig, TimberClassic;
-- then six views of each trailer behind a Pickup (Pony, Ranch, Heavy Hauler).
local Vehicles = require("./_vehicles")

return {
	build = function(ctx)
		local specimens = {
			{ id = "Rustbucket", truck = "Rustbucket", partBuilt = true },
			{ id = "Pickup", truck = "Pickup", partBuilt = true },
			{ id = "ScoutATV", truck = "ScoutATV", partBuilt = true },
			{ id = "Flatbed", truck = "Flatbed", partBuilt = true },
			{ id = "LoggingRig", truck = "LoggingRig", partBuilt = true },
			{ id = "TimberClassic", truck = "TimberClassic", partBuilt = true, extras = { doorName = "Timber & Co" } },
		}
		local root, cameras = Vehicles.build(ctx, specimens, "full")
		return Vehicles.scene(root, cameras)
	end,
}
