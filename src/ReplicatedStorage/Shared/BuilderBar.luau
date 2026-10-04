--!strict
-- BuilderBar: where the phone build bar sits. Eight buttons, 56×56 with an
-- 8px gap. One row stays between the thumbstick and Jump while the buttons
-- stay at least 48px. Below that, two rows of four stay at 56px (248px
-- wide). A tall phone has no gap that wide, so the bar sits above the
-- controls. Buttons never shrink below 44px. The cluster sits 8px above
-- the hotbar (UITheme.Bottom()). Build mode hides the hint row, so the
-- bar does not reserve space for it. The readout sits on top.

local PlotPickerLogic = require(script.Parent.PlotPickerLogic)

local BuilderBar = {}

BuilderBar.Button = 56
BuilderBar.Gap = 8
BuilderBar.Count = 8
BuilderBar.Readout = 28
BuilderBar.MinButton = 44
-- One row switches to two once a button would drop under this.
BuilderBar.RowFloor = 48
BuilderBar.Names = { "Rotate", "Move", "Shorter", "Longer", "Copy", "Delete", "Undo", "Done" }
BuilderBar.Refuse = { 255, 80, 80 }
BuilderBar.GhostTransparency = 0.45
-- UITheme.Bottom() on a phone: the 12px margin plus the 58px tool hotbar.
BuilderBar.PhoneBottom = 70
-- Air between the cluster and the hotbar.
BuilderBar.Air = 8

local function rowWidth(count: number, button: number, gap: number): number
	return count * button + (count - 1) * gap
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
	rows: number,
}

function BuilderBar.Layout(screenW: number, screenH: number, bottom: number?): Layout
	local blocks = PlotPickerLogic.TouchBlockers(screenW, screenH)
	local stick, jump = blocks[1], blocks[2]
	local left = stick.x + stick.w
	local right = jump.x
	local safe = math.max(0, right - left - 16)
	local oneWide = rowWidth(BuilderBar.Count, BuilderBar.Button, BuilderBar.Gap)
	local oneScale = math.min(1, safe / oneWide)
	local rows = 1
	local perRow = BuilderBar.Count
	local scale = oneScale
	local lifted = false
	if BuilderBar.Button * oneScale < BuilderBar.RowFloor then
		rows = 2
		perRow = BuilderBar.Count / 2
		local twoWide = rowWidth(perRow, BuilderBar.Button, BuilderBar.Gap)
		local twoScale = math.min(1, safe / twoWide)
		if BuilderBar.Button * twoScale < BuilderBar.MinButton then
			scale = 1
			lifted = true
		else
			scale = twoScale
		end
	end
	local button = BuilderBar.Button * scale
	local gap = BuilderBar.Gap * scale
	local readout = BuilderBar.Readout * scale
	local w = rowWidth(perRow, button, gap)
	if lifted then
		local room = math.max(0, screenW - 16)
		if w > room and room > 0 then
			scale = math.max(BuilderBar.MinButton / BuilderBar.Button, math.min(1, room / w))
			button = BuilderBar.Button * scale
			gap = BuilderBar.Gap * scale
			readout = BuilderBar.Readout * scale
			w = rowWidth(perRow, button, gap)
		end
	end
	local clusterH = readout + rows * button + rows * gap
	local x = (screenW - w) / 2
	-- Above the hotbar (UITheme.Bottom(); PhoneBottom when the caller
	-- doesn't pass it). A tall phone then moves up again so the cluster
	-- stays off the controls.
	local inset = if type(bottom) == "number" then bottom else BuilderBar.PhoneBottom
	local y = screenH - inset - clusterH - BuilderBar.Air
	if lifted then
		local ceiling = math.min(stick.y, jump.y)
		if y + clusterH > ceiling then
			y = ceiling - clusterH
		end
		if x < 8 then
			x = 8
		end
		if x + w > screenW - 8 then
			x = screenW - 8 - w
		end
	else
		if x < left + 8 then
			x = left + 8
		end
		if x + w > right - 8 then
			x = right - 8 - w
		end
	end
	if y < 0 then
		y = 0
	end
	return {
		x = x,
		y = y,
		w = w,
		h = clusterH,
		button = button,
		gap = gap,
		scale = scale,
		readout = readout,
		rows = rows,
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
	if layout.button + 1e-3 < BuilderBar.MinButton or (layout.rows ~= 1 and layout.rows ~= 2) then
		return false
	end
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
