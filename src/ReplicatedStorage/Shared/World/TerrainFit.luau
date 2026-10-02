--!strict
-- TerrainFit: getting the engine to draw the ground where TerrainGen says
-- (TER-01, TER-04).
--
-- TerrainBuilder writes heights as voxel occupancies (TerrainGen.Voxel);
-- how the engine meshes them is up to the engine. On the live game the
-- flat town (written at y = 0) was drawn 2 studs high: half a voxel. NPCs
-- and parked trucks stood in it, the tent and campfire were buried, the
-- parking paint was gone and players spawned inside it. Small test pads
-- far below the map didn't measure it (Studio still read 2.00 after them),
-- so TerrainBuilder now measures the town itself: it writes the chunks
-- under the town, casts rays onto the ground (TerrainBuilder.TownProbes),
-- and shifts every height it writes until the town reads 0. NextShift is
-- that search; the same shift then goes on every height and water level
-- in the world.

local TerrainFit = {}

-- How close to y = 0 the town has to read: any nearer is noise.
TerrainFit.Tolerance = 0.15

-- Most writes of the town's chunks before settling for the best so far.
TerrainFit.MaxTries = 5

-- The biggest believable shift (past it a ray hit something else).
TerrainFit.MaxShift = 6

export type Try = { shift: number, error: number } -- error: the town read minus 0

-- The shift to try next, given the tries so far (at least one). A secant
-- step through the last two (the drawn ground follows the written one,
-- give or take the engine's rounding), a plain step the first time, both
-- held to MaxShift. Returns nil once the last try is close enough.
function TerrainFit.NextShift(tries: { Try }): number?
	local last = tries[#tries]
	if math.abs(last.error) <= TerrainFit.Tolerance then
		return nil
	end
	local slope = 1
	local prev = tries[#tries - 1]
	if prev and math.abs(last.shift - prev.shift) > 1e-6 then
		local s = (last.error - prev.error) / (last.shift - prev.shift)
		if s == s then
			slope = math.clamp(s, 0.25, 4)
		end
	end
	local nextShift = math.clamp(last.shift - last.error / slope, -TerrainFit.MaxShift, TerrainFit.MaxShift)
	-- A step that goes nowhere (pinned at the clamp, or the engine rounding
	-- the same way twice): nudge by a quarter voxel instead.
	for _, t in ipairs(tries) do
		if math.abs(t.shift - nextShift) < 0.05 then
			nextShift =
				math.clamp(last.shift - (if last.error > 0 then 1 else -1), -TerrainFit.MaxShift, TerrainFit.MaxShift)
			break
		end
	end
	return nextShift
end

-- The try whose town read nearest 0.
function TerrainFit.Best(tries: { Try }): Try
	local best = tries[1]
	for _, t in ipairs(tries) do
		if math.abs(t.error) < math.abs(best.error) then
			best = t
		end
	end
	return best
end

return TerrainFit
