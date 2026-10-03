--!strict
-- PlotPickerLogic: choosing a homestead when you join (LT2-style).
-- Pure. PlotService applies it; the picker UI only shows what an offer says.
--
-- Builds are saved in plot-local studs, so a rejoin picks again from
-- whatever is still open. A save-slot swap while you already stand on a
-- pad keeps that pad. Two claims of one pad in the same breath: the first
-- one in TryClaim wins, and the other is "taken". Closing the picker or
-- letting it time out takes the first open pad.

local PlotPickerLogic = {}

PlotPickerLogic.TimeoutSeconds = 60

-- The join panel, in pixels. PlotPickerUI uses these same numbers, and the
-- spec checks the cluster stays off the thumbstick and the jump button.
PlotPickerLogic.PanelTop = 4
PlotPickerLogic.PanelHeight = 132
PlotPickerLogic.PanelWidthScale = 0.7

export type Box = { x: number, y: number, w: number, h: number }

export type OfferPlot = {
	index: number,
	name: string,
	region: string,
	x: number,
	z: number,
	y: number,
	taken: boolean,
	owner: string,
}

export type Offer = {
	timeout: number,
	plots: { OfferPlot },
	notice: string?, -- "taken" when the claim you just sent lost
}

-- True when this join should open the picker. A player who already has a
-- pad this session (a save-slot swap) does not pick again.
function PlotPickerLogic.ShouldPick(hasPlot: boolean): boolean
	return not hasPlot
end

-- Next/Previous, including pads that are already taken (the screen says so).
function PlotPickerLogic.Step(index: number, count: number, delta: number): number
	if count < 1 then
		return 1
	end
	return ((index - 1 + delta) % count + count) % count + 1
end

-- Claim is only for an open pad. Taken ones stay on the list so you can
-- see who has them.
function PlotPickerLogic.CanClaim(taken: boolean): boolean
	return not taken
end

-- `taken[index]` is whether that pad already has an owner. Sets it when
-- the claim lands. "taken" means someone else won the same pad.
function PlotPickerLogic.TryClaim(taken: { boolean }, index: number): (boolean, string)
	if taken[index] == nil then
		return false, "missing"
	end
	if taken[index] then
		return false, "taken"
	end
	taken[index] = true
	return true, "ok"
end

-- The first open pad, in slot order. Nil when the server is full.
function PlotPickerLogic.FirstFree(taken: { boolean }): number?
	for index, isTaken in ipairs(taken) do
		if not isTaken then
			return index
		end
	end
	return nil
end

function PlotPickerLogic.TimedOut(startedAt: number, now: number): boolean
	return now - startedAt >= PlotPickerLogic.TimeoutSeconds
end

-- An integer slot in 1..count. Anything else is ignored (no claim).
function PlotPickerLogic.ClaimIndex(index: unknown, count: number): number?
	if type(index) ~= "number" or index ~= index or index ~= math.floor(index) then
		return nil
	end
	if index < 1 or index > count then
		return nil
	end
	return index
end

-- The next pad that is still open, after `fromIndex`, wrapping. Stays put
-- when every pad is taken.
function PlotPickerLogic.NextOpen(plots: { OfferPlot }, fromIndex: number): number
	local count = #plots
	if count < 1 then
		return 1
	end
	for step = 1, count do
		local index = ((fromIndex - 1 + step) % count) + 1
		if plots[index].taken ~= true then
			return index
		end
	end
	return fromIndex
end

function PlotPickerLogic.Cluster(screenW: number, _screenH: number): Box
	local w = math.floor(screenW * PlotPickerLogic.PanelWidthScale)
	return {
		x = (screenW - w) / 2,
		y = PlotPickerLogic.PanelTop,
		w = w,
		h = PlotPickerLogic.PanelHeight,
	}
end

-- Where a phone's thumbstick and jump button sit. Landscape keeps them
-- in the lower corners; portrait drops them further down the long side.
function PlotPickerLogic.TouchBlockers(screenW: number, screenH: number): { Box }
	if screenW > screenH then
		return {
			{ x = 0, y = screenH - 150, w = 150, h = 150 },
			{ x = screenW - 120, y = screenH - 140, w = 120, h = 140 },
		}
	end
	return {
		{ x = 0, y = screenH - 190, w = 170, h = 190 },
		{ x = screenW - 120, y = screenH - 170, w = 120, h = 170 },
	}
end

function PlotPickerLogic.BoxesOverlap(a: Box, b: Box): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- True when the picker cluster misses the thumbstick and the jump button.
function PlotPickerLogic.ControlsClear(screenW: number, screenH: number): boolean
	local cluster = PlotPickerLogic.Cluster(screenW, screenH)
	for _, block in ipairs(PlotPickerLogic.TouchBlockers(screenW, screenH)) do
		if PlotPickerLogic.BoxesOverlap(cluster, block) then
			return false
		end
	end
	return true
end

return PlotPickerLogic
