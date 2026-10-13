--!nocheck
-- Every truck with every trailer it can tow (the twelve by_truck variants),
-- real meshes, six views each: both sides, the two three-quarters, a trailer
-- wheel close up and a low side view. Rigs run Rustbucket, Pickup, Flatbed,
-- LoggingRig, each with PonyTrailer, RanchTrailer, HeavyHauler (views 1-6 are
-- the Rustbucket + Pony, 7-12 the Rustbucket + Ranch, and so on).
local Vehicles = require("./_vehicles")

return {
	build = function(ctx)
		local specimens = {}
		for _, truck in ipairs({ "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }) do
			for _, trailer in ipairs({ "PonyTrailer", "RanchTrailer", "HeavyHauler" }) do
				table.insert(specimens, { id = truck .. "+" .. trailer, truck = truck, trailer = trailer })
			end
		end
		local root, cameras = Vehicles.build(ctx, specimens, "rig")
		return Vehicles.scene(root, cameras)
	end,
}
