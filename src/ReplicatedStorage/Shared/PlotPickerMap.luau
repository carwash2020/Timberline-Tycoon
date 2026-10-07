--!strict
-- PlotPickerMap: the schematic map card in the plot picker, and the numbers
-- the camera and the in-world marker share. Pure. It needs only the offer's
-- plot coordinates, so it works when the world is not streamed in.
--
-- Roblox's +X is east and +Z is south; the card puts north at the top, so a
-- larger z is lower on the card.

local PlotPickerLogic = require(script.Parent.PlotPickerLogic)

local PlotPickerMap = {}

export type Dot = {
	index: number,
	fx: number, -- 0..1 across the card
	fy: number, -- 0..1 down the card
	state: string, -- "selected", "open" or "taken"
}

-- The card, in pixels (the panel's right side).
PlotPickerMap.CardSize = 112
PlotPickerMap.DotSize = 10
PlotPickerMap.SelectedDotSize = 18
PlotPickerMap.Margin = 0.1 -- empty border, as a fraction of the card

-- The camera shot: where it sits relative to the pad, and what it looks at.
PlotPickerMap.CameraBack = { x = -78, y = 62, z = 96 }
PlotPickerMap.FocusUp = 4
-- The marker pillar (client-only, made from the offer's coordinates).
PlotPickerMap.PillarHeight = 220
PlotPickerMap.PillarWidth = 6

-- What the pad's dot looks like: the chosen one wins over taken or open.
function PlotPickerMap.State(taken: boolean, selected: boolean): string
	if selected then
		return "selected"
	end
	if taken then
		return "taken"
	end
	return "open"
end

-- Every pad's place on the card, in 0..1, with the margin kept clear. One
-- scale for both axes so the shape is true; the short axis is centred.
function PlotPickerMap.Layout(plots: { PlotPickerLogic.OfferPlot }, selected: number): { Dot }
	local dots: { Dot } = {}
	if #plots == 0 then
		return dots
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, plot in ipairs(plots) do
		minX = math.min(minX, plot.x)
		maxX = math.max(maxX, plot.x)
		minZ = math.min(minZ, plot.z)
		maxZ = math.max(maxZ, plot.z)
	end
	local span = math.max(maxX - minX, maxZ - minZ, 1)
	local inner = 1 - 2 * PlotPickerMap.Margin
	local offX = (1 - (maxX - minX) / span * inner) / 2
	local offZ = (1 - (maxZ - minZ) / span * inner) / 2
	for i, plot in ipairs(plots) do
		table.insert(dots, {
			index = i,
			fx = offX + (plot.x - minX) / span * inner,
			fy = offZ + (plot.z - minZ) / span * inner,
			state = PlotPickerMap.State(plot.taken == true, i == selected),
		})
	end
	return dots
end

-- The dot nearest a tap on the card (fractions 0..1), for tap-to-select.
-- Nil when the card has no pads.
function PlotPickerMap.Nearest(dots: { Dot }, fx: number, fy: number): number?
	local best: number? = nil
	local bestD = math.huge
	for _, dot in ipairs(dots) do
		local d = (dot.fx - fx) ^ 2 + (dot.fy - fy) ^ 2
		if d < bestD then
			bestD = d
			best = dot.index
		end
	end
	return best
end

-- Where the camera sits and what it looks at for a pad, as plain numbers
-- (x, y, z for each; the UI turns them into Vector3s).
export type Shot = { fromX: number, fromY: number, fromZ: number, atX: number, atY: number, atZ: number }

function PlotPickerMap.Shot(plot: { x: number, y: number, z: number }): Shot
	return {
		fromX = plot.x + PlotPickerMap.CameraBack.x,
		fromY = plot.y + PlotPickerMap.CameraBack.y,
		fromZ = plot.z + PlotPickerMap.CameraBack.z,
		atX = plot.x,
		atY = plot.y + PlotPickerMap.FocusUp,
		atZ = plot.z,
	}
end

-- One step of a smooth move: a fraction of the remaining way, by frame time,
-- so it is the same speed at any frame rate. `rate` is per second.
function PlotPickerMap.Ease(dt: number, rate: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-rate * dt)
end

-- The fade after a claim (seconds): out to black, then back in.
PlotPickerMap.FadeSeconds = 0.4

function PlotPickerMap.ClaimedText(name: string): string
	return string.format("Claimed %s!", name)
end

function PlotPickerMap.LoadingText(loading: boolean): string
	if loading then
		return "Loading view…"
	end
	return ""
end

return PlotPickerMap
