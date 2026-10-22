--!strict
-- GroundLift (T406): the rule that keeps the town's flat ground parts (footpaths
-- above all) on top of the terrain. TownGround plans a part's top from
-- TerrainGen.HeightAt (0.1 over it for a footpath); the engine's terrain is
-- 4-stud voxels, and where the drawn surface sits at or above a part's top the
-- part is buried and never shows (a footpath is only 0.1 proud). MapBuilder
-- casts a ray at the part and asks Needed for the lift. Pure.

local GroundLift = {}

GroundLift.Proud = 0.05 -- a lifted part's top stands this far over the drawn terrain
GroundLift.Visible = 0.03 -- a part's top must clear the drawn terrain by at least this
GroundLift.MaxLift = 3 -- studs: a bigger gap is a different problem (a hill), left alone

-- How far to raise a part whose top is `topY` where the drawn terrain is at
-- `terrainY` (nil: no hit). 0 when it already shows.
function GroundLift.Needed(topY: number, terrainY: number?): number
	if terrainY == nil or terrainY ~= terrainY or topY ~= topY then
		return 0
	end
	if topY - terrainY >= GroundLift.Visible then
		return 0
	end
	local lift = terrainY + GroundLift.Proud - topY
	if lift <= 0 or lift > GroundLift.MaxLift then
		return 0
	end
	return lift
end

return GroundLift
