--!strict
-- TrailerAxleData (T421): where each trailer's axles and wheels are. The numbers are not written here: they are
-- VehicleStats, generated from assets/vehicles/t421/glb/<Trailer>/<Truck>/stats.json (axles and wheelCentres).
-- Studs, trailer-local: the bed's middle is Z 0 and the hitch end is toward -Z, so a positive value is behind the
-- bed's middle. One wheel pair per axle (TruckArt.AddTrailer). Pony {1.30}, Ranch {0.26, 3.38}, HeavyHauler {0.91, 4.29};
-- the wheel X differs per tow-truck variant (bbox_check.md).

local VehicleStats = require(script.Parent.Art.VehicleStats)

local TrailerAxleData = {}

-- The trailer variant a truck body style tows with (TruckLayout styles).
TrailerAxleData.VariantOfStyle = {
	farm = "Rustbucket",
	pickup = "Pickup",
	flatbed = "Flatbed",
	rig = "LoggingRig",
} :: { [string]: string }

-- The trailer id of a TruckLayout trailer style.
TrailerAxleData.ByStyle = {
	pony = "PonyTrailer",
	ranch = "RanchTrailer",
	heavy = "HeavyHauler",
} :: { [string]: string }

local function stats(trailerId: string, variant: string): VehicleStats.TrailerStats
	local byVariant = VehicleStats.Trailers[trailerId]
	local s = if byVariant then byVariant[variant] else nil
	assert(s ~= nil, "no stats for " .. trailerId .. "/" .. variant)
	return s
end

-- Every variant has the same axles; the Rustbucket's are read.
function TrailerAxleData.For(trailerId: string): { number }
	return stats(trailerId, "Rustbucket").axles
end

function TrailerAxleData.WheelX(trailerId: string, variant: string): number
	return stats(trailerId, variant).wheelX
end

return TrailerAxleData
