--!strict
-- BuilderBar: where the phone build bar sits. Eight buttons, 56×56 with an
-- 8px gap, scaled down so the row stays between the thumbstick and the
-- Jump button. The readout sits just above the buttons.

local PlotPickerLogic = require(script.Parent.PlotPickerLogic)

local BuilderBar = {}

BuilderBar.Button = 56
BuilderBar.Gap = 8
BuilderBar.Count = 8
BuilderBar.Readout = 28
BuilderBar.Names = { "Rotate", "Move", "Shorter", "Longer", "Copy", "Delete", "Undo", "Done" }
BuilderBar.Refuse = { 255, 80, 80 }
BuilderBar.GhostTransparency = 0.45

local function nominalWidth(): number
	return BuilderBar.Count * BuilderBar.Button + (BuilderBar.Count - 1) * BuilderBar.Gap
end

export type Layout = {
	x: number,
	y: number,
	w: number,
	h: number,
	button: number,
	gap: number,
	scale: number,
	readout: number,
}

function BuilderBar.Layout(screenW: number, screenH: number): Layout
	local width = nominalWidth()
	local blocks = PlotPickerLogic.TouchBlockers(screenW, screenH)
	local stick, jump = blocks[1], blocks[2]
	local left = stick.x + stick.w
	local right = jump.x
	local safe = math.max(0, right - left - 16)
	local scale = math.min(1, safe / width)
	local w = width * scale
	local button = BuilderBar.Button * scale
	local gap = BuilderBar.Gap * scale
	local readout = BuilderBar.Readout * scale
	local clusterH = readout + gap + button
	local x = (screenW - w) / 2
	if x < left + 8 then
		x = left + 8
	end
	if x + w > right - 8 then
		x = right - 8 - w
	end
	local y = screenH - clusterH - 10
	return {
		x = x,
		y = y,
		w = w,
		h = clusterH,
		button = button,
		gap = gap,
		scale = scale,
		readout = readout,
	}
end

export type Gate = {
	count: number,
	filled: boolean,
	shorter: boolean,
	longer: boolean,
}

-- Gray when the button doesn't apply: a filled piece, a fixed size, or a
-- group (only Copy, Delete, Undo and Done work on more than one).
function BuilderBar.Enabled(name: string, gate: Gate): boolean
	if name == "Done" or name == "Undo" then
		return true
	end
	if gate.filled or gate.count < 1 or gate.count > 20 then
		return false
	end
	if name == "Copy" or name == "Delete" then
		return true
	end
	if gate.count ~= 1 then
		return false
	end
	if name == "Rotate" or name == "Move" then
		return true
	end
	if name == "Shorter" then
		return gate.shorter
	end
	if name == "Longer" then
		return gate.longer
	end
	return false
end

function BuilderBar.Fits(screenW: number, screenH: number): boolean
	local layout = BuilderBar.Layout(screenW, screenH)
	if layout.x < 0 or layout.y < 0 or layout.x + layout.w > screenW + 0.5 or layout.y + layout.h > screenH + 0.5 then
		return false
	end
	local box = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
	for _, block in ipairs(PlotPickerLogic.TouchBlockers(screenW, screenH)) do
		if PlotPickerLogic.BoxesOverlap(box, block) then
			return false
		end
	end
	return true
end

return BuilderBar
