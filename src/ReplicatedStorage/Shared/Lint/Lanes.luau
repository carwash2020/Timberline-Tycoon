--!strict
-- Lanes: nothing solid stands where wood or a person has to pass. The boxes are LaneData's (the
-- same ones tools/blender/meshlint.py tests the GLBs with); this checks the part-built model in the
-- built world: every part with CanCollide on, bar the lane's own riders (LaneData.Riders) and the
-- named known hits (LaneData.Allow), that overlaps a lane, door or path box by more than 0.05 studs
-- is a failure: "<part> (<model>) x lane <model>.<lane>". Pure: takes the root Instance and the
-- frame (a CFrame) each model's own coordinates sit at.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Clearance = require(ReplicatedStorage.Shared.World.Clearance)
local Geometry = require(script.Parent.Geometry)
local LaneData = require(script.Parent.LaneData)

local Lanes = {}

Lanes.MinDepth = 0.05

export type Result = { failures: { string }, checked: number }

local function listed(allow: { LaneData.Allow }, lane: string, part: BasePart, frame: CFrame): boolean
	local local_ = frame:PointToObjectSpace(part.CFrame.Position)
	for _, entry in ipairs(allow) do
		if entry.lane == lane and entry.part == part.Name and (entry.at - local_).Magnitude < 0.5 then
			return true
		end
	end
	return false
end

-- `frames`: model name -> the CFrame its own coordinates sit at (the town's sawmill CFrame for
-- "Sawmill"). `data` (default LaneData.Boxes) and `allow` (default LaneData.Allow) exist for specs.
function Lanes.Run(
	root: Instance,
	frames: { [string]: CFrame },
	data: { [string]: { LaneData.Box } }?,
	allow: { LaneData.Allow }?
): Result
	local boxes = data or LaneData.Boxes
	local known = allow or LaneData.Allow
	local failures: { string } = {}
	local checked = 0
	for modelName, lanes in pairs(boxes) do
		local model = root:FindFirstChild(modelName)
		local frame = frames[modelName]
		if not model or not frame then
			table.insert(
				failures,
				string.format("[GeometryLint] model %s or its frame is missing: its lanes were not checked", modelName)
			)
			continue
		end
		local parts: { BasePart } = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide and not d:IsA("WedgePart") and not LaneData.Riders[d.Name] then
				table.insert(parts, d)
			end
		end
		for _, lane in ipairs(lanes) do
			checked += 1
			local box = Clearance.Box(frame * CFrame.new((lane.min + lane.max) / 2), lane.max - lane.min)
			for _, part in ipairs(parts) do
				local shape = Geometry.BoxOf(part)
				local depth = Clearance.BoxDepth(box, shape)
				if depth > Lanes.MinDepth + 1e-4 and not listed(known, lane.name, part, frame) then
					local at = part.CFrame.Position
					table.insert(
						failures,
						string.format(
							"[GeometryLint] %s (%s) x lane %s.%s at (%.1f, %.1f, %.1f), depth %.2f, %s",
							part.Name,
							modelName,
							modelName,
							lane.name,
							at.X,
							at.Y,
							at.Z,
							depth,
							lane.kind
						)
					)
				end
			end
		end
	end
	table.sort(failures)
	return { failures = failures, checked = checked }
end

return Lanes
