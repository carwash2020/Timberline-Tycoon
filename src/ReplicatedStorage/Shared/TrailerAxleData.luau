--!strict
-- TrailerAxleData (T421): where each trailer's axles are, the only place these numbers are written.
-- Studs, trailer-local: the bed's middle is Z 0 and the hitch end is toward -Z, so a positive value is behind the
-- bed's middle. One wheel pair per axle (TruckArt.AddTrailer).
--
-- PROVENANCE: the values are the ones the T421 brief states for the approved meshes' stats.json (axles and
-- wheelCentres): Pony {1.30}, Ranch {0.26, 3.38}, HeavyHauler {0.91, 4.29}. The stats.json files themselves were
-- not in the repo when this was written (see docs/T421_PLAN.md); when they land, tests/TrailerAxles.spec.luau is where
-- the two get compared.
--
-- MISSING (not guessed): the wheel X of each tow-truck variant, which bbox_check.md holds. Until then the wheels
-- stand at TruckLayout's own wheelX (tests/TrailerAxles.spec.luau has an expected-fail for the bbox_check match).

local TrailerAxleData = {}

TrailerAxleData.Axles = {
	PonyTrailer = { 1.30 },
	RanchTrailer = { 0.26, 3.38 },
	HeavyHauler = { 0.91, 4.29 },
} :: { [string]: { number } }

-- The axles of a trailer style (TruckLayout's "pony" | "ranch" | "heavy"), so a trailer made up in a spec still has some.
TrailerAxleData.ByStyle = {
	pony = "PonyTrailer",
	ranch = "RanchTrailer",
	heavy = "HeavyHauler",
} :: { [string]: string }

function TrailerAxleData.For(trailerId: string): { number }
	local axles = TrailerAxleData.Axles[trailerId]
	assert(axles ~= nil, "no axle data for " .. trailerId)
	return axles
end

return TrailerAxleData
