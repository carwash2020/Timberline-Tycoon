--!strict
-- LaneData: the lane, door and path boxes the part-built models are checked against (Lanes.luau).
-- The boxes are assets/meshes/lanes.json's, in the model's own studs (the mesh frame: the part build is the
-- same shape at the same size), and tests/LaneData.spec checks the two files agree, so the mesh lint and the
-- part lint see one set of lanes. `riders` are the parts that belong in a lane (a rail, the carriage, a log, the
-- blade and its welded parts); `allow` names one known part that stands in a lane today (by its place in the
-- model, within 0.5 stud), with the reason, so a part moved INTO a lane is still a hit.

local LaneData = {}

export type Box = { name: string, kind: string, min: Vector3, max: Vector3 }
export type Allow = { lane: string, part: string, at: Vector3, reason: string }

LaneData.Boxes = {
	Sawmill = {
		{ name = "slip", kind = "lane", min = Vector3.new(17.4, 0.45, -3), max = Vector3.new(33, 6.9, 1.2) },
		{ name = "carriage", kind = "lane", min = Vector3.new(-16.2, 1.5, -3), max = Vector3.new(16.2, 7.35, 1.2) },
		{ name = "outfeed", kind = "lane", min = Vector3.new(-16.2, 1.5, -3), max = Vector3.new(-5.4, 5.4, 1.2) },
		{
			name = "front",
			kind = "door",
			min = Vector3.new(-23.2125, 1.5, -12),
			max = Vector3.new(-19.0875, 10.5, -10),
		},
	},
} :: { [string]: { Box } }

-- Parts that belong in a lane (by name).
LaneData.Riders = {
	Rail = true,
	Carriage = true,
	Wheel = true,
	Knee = true,
	Log = true,
	SlipRail = true,
	SlipChain = true,
	SlipLeg = true,
	SawBlade = true,
	SawTooth = true,
	BladeHub = true,
	BladeRivet = true,
} :: { [string]: boolean }

LaneData.Allow = {
	{
		lane = "carriage",
		part = "Post",
		at = Vector3.new(-16.5, 10.5, 1.125),
		reason = "known on main: the west wall post stands at z 0.08..2.18, 0.75 inside the lane edge, at the wall opening (the mesh has the same column); Builder follow-up",
	},
	{
		lane = "carriage",
		part = "Post",
		at = Vector3.new(16.5, 10.5, 1.125),
		reason = "known on main: the east wall post stands at z 0.08..2.18, 0.75 inside the lane edge, at the wall opening (the mesh has the same column); Builder follow-up",
	},
	{
		lane = "outfeed",
		part = "Post",
		at = Vector3.new(-16.5, 10.5, 1.125),
		reason = "known on main: the west wall post (see carriage); Builder follow-up",
	},
	{
		lane = "slip",
		part = "Post",
		at = Vector3.new(16.5, 10.5, 1.125),
		reason = "known on main: the east wall post touches the lane's west end by 0.15; Builder follow-up",
	},
	{
		lane = "carriage",
		part = "Wall",
		at = Vector3.new(-16.5, 2.7857, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "carriage",
		part = "Wall",
		at = Vector3.new(-16.5, 5.3571, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "carriage",
		part = "Wall",
		at = Vector3.new(-16.5, 7.9286, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "outfeed",
		part = "Wall",
		at = Vector3.new(-16.5, 2.7857, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "outfeed",
		part = "Wall",
		at = Vector3.new(-16.5, 5.3571, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "outfeed",
		part = "Wall",
		at = Vector3.new(-16.5, 7.9286, 1.125),
		reason = "known on main: the west wall planks overlap the lane's end by 0.15 (x -16.95..-16.05 against -16.2)",
	},
	{
		lane = "carriage",
		part = "SawGuard",
		at = Vector3.new(-5.85, 9.825, 2.025),
		reason = "the saw guard is an invisible blocker over the blade disc (InvisibleBlocker); its box starts at z 0.25, 0.8 inside the lane edge; Builder to pull it back",
	},
	{
		lane = "outfeed",
		part = "SawGuard",
		at = Vector3.new(-5.85, 9.825, 2.025),
		reason = "the saw guard (see carriage)",
	},
	{
		lane = "carriage",
		part = "GuardRail",
		at = Vector3.new(14.55, 5.475, -0.75),
		reason = "known on main: the east guard rail stands at x 14.3..14.8, inside the carriage lane (x to 16.2); the carriage rests at x 5 and never reaches it; Builder follow-up",
	},
	{
		lane = "front",
		part = "Wall",
		at = Vector3.new(-23.475, 3, -10.5),
		reason = "known on main: in the part build the office wall runs across the door (the door part does not collide); the mesh has an opening, so this is the fallback model only; Builder follow-up",
	},
	{
		lane = "front",
		part = "Wall",
		at = Vector3.new(-23.475, 6, -10.545),
		reason = "known on main: office wall across the door (see above)",
	},
	{
		lane = "front",
		part = "Wall",
		at = Vector3.new(-23.475, 9, -10.5),
		reason = "known on main: office wall across the door (see above)",
	},
} :: { Allow }

return LaneData
