--!strict
-- TimberClassicData (T421): the Timber Classic's measured numbers, in the truck's own frame (the front faces -Z, the
-- wheels touch y = 0, x = 0 is the middle).
-- PROVENANCE: the T421 brief's figures for the approved meshes (hitch, wheel centres, bed footprint). They match
-- TruckLayout's own pickup layout (tests/TimberClassic.spec checks the wheels against it within 0.01). The mesh sizes
-- and `at` offsets of its Body, Glass, Lights and Bed come from TimberClassic/stats.json, which is NOT in the repo, so
-- they are not written here (VehicleMeshGate.ClassicStats stays false until they are).

local TimberClassicData = {}

TimberClassicData.Hitch = Vector3.new(0, 2.005, 12.875)
TimberClassicData.WheelCentres = {
	Vector3.new(-4.713, 1.755, -9.685),
	Vector3.new(4.713, 1.755, -9.685),
	Vector3.new(-4.713, 1.755, 7.085),
	Vector3.new(4.713, 1.755, 7.085),
}
-- The bed's footprint (x, z): inside the Pickup's (VehicleModels Pickup Bed, 9 x 15.815).
TimberClassicData.BedFootprint = Vector2.new(7.22, 15.5)
-- It tows the Pickup's trailer variants.
TimberClassicData.TowVariant = "Pickup"

return TimberClassicData
