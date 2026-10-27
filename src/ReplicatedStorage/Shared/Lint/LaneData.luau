--!strict
-- LaneData: the lane, door and path boxes the part-built models are checked against (Lanes.luau).
-- The boxes are assets/meshes/lanes.json's, in the model's own studs (the mesh frame: the part build is the
-- same shape at the same size), and tests/LaneData.spec checks the two files agree, so the mesh lint and the
-- part lint see one set of lanes. `Riders` are the parts that belong in a lane (a rail, the carriage, a log, the
-- blade and its welded parts), and only inside the lane's own model. `Allow` would name a known part that stands in
-- a lane (by its place in the model); it is empty and stays empty (tests/AllowlistCap.spec): the part build was
-- changed until nothing stood in a lane. The GLB's own known hits are the `pending` boxes in lanes.json, each
-- with the Blender edit that fixes it.

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
	-- The town mill's belt is the carriage (T411). It is the one collider that belongs in that lane.
	Conveyor = true,
} :: { [string]: boolean }

-- None: every part in a lane box is a hit (T409: the part build was changed until none was left).
LaneData.Allow = {} :: { Allow }

return LaneData
