--!strict
-- PlotRedraw: which plot pads may be redrawn right now. When the plot kit's
-- meshes land after the pads were built, PlotService redraws every pad
-- (its platform slabs and ramps are cleared and built again). Doing that
-- under a player's feet drops them through the floor for a frame, so a pad
-- with a player near it waits and is tried again. Pure.

local PlotRedraw = {}

PlotRedraw.NearRadius = 90 -- a player this close (studs, flat) holds the redraw back
PlotRedraw.RetrySeconds = 2
PlotRedraw.MaxRetries = 300 -- 10 minutes of tries, then the pad is left as it is

export type Pad = { index: number, x: number, z: number }
export type Point = { x: number, z: number }

-- Splits the pads into the ones to redraw now and the ones to hold back
-- (anyone within `radius` of the pad, its owner included).
function PlotRedraw.Split(pads: { Pad }, players: { Point }, radius: number?): ({ number }, { number })
	local reach = radius or PlotRedraw.NearRadius
	local now: { number } = {}
	local later: { number } = {}
	for _, pad in ipairs(pads) do
		local near = false
		for _, p in ipairs(players) do
			local dx, dz = p.x - pad.x, p.z - pad.z
			if dx * dx + dz * dz <= reach * reach then
				near = true
				break
			end
		end
		if near then
			table.insert(later, pad.index)
		else
			table.insert(now, pad.index)
		end
	end
	return now, later
end

return PlotRedraw
