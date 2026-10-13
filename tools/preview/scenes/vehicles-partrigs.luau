--!nocheck
-- The part-built trailers (no mesh) behind a Pickup: Pony, Ranch, Heavy
-- Hauler, six views each (the Dealership's trailer copies look like this).
local Vehicles = require("./_vehicles")

return {
	build = function(ctx)
		local specimens = {}
		for _, trailer in ipairs({ "PonyTrailer", "RanchTrailer", "HeavyHauler" }) do
			table.insert(
				specimens,
				{ id = "Pickup+" .. trailer, truck = "Pickup", trailer = trailer, partBuilt = true }
			)
		end
		local root, cameras = Vehicles.build(ctx, specimens, "rig")
		return Vehicles.scene(root, cameras)
	end,
}
