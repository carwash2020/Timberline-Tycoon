--!strict
-- PlotPickerLogic: choosing a homestead when you join (LT2-style).
-- Pure. PlotService applies it; the picker UI only shows what an offer says.
--
-- Nobody is given a plot. A player who has never owned one buys the first
-- at the Land Office in town (GameConfig.PlotPrice); the picker opens from
-- that counter and shows the price. A player whose save already has a plot
-- (profile.plot.claimed) picks a pad again for free when they join, as
-- before, and only that player's timeout takes the first open pad. Builds
-- are saved in plot-local studs, so a rejoin picks again from whatever is
-- still open. Two claims of one pad in the same breath: the first one in
-- TryClaim wins, and the other is "taken".

local PlotPickerLogic = {}

PlotPickerLogic.TimeoutSeconds = 60

-- The join panel, in pixels. PlotPickerUI uses these same numbers, and the
-- spec checks the cluster stays off the thumbstick and the jump button.
PlotPickerLogic.PanelTop = 8
PlotPickerLogic.PanelHeight = 148
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
	price: number, -- what the claim costs this player (0: they already own a plot in their save)
	plots: { OfferPlot },
	notice: string?, -- "taken" when the claim you just sent lost
}

-- True when this join should open the picker. A player who already has a
-- pad this session (a save-slot swap) does not pick again.
function PlotPickerLogic.ShouldPick(hasPlot: boolean): boolean
	return not hasPlot
end

-- What claiming costs: nothing for a save that already had a plot, the
-- first-plot price for everyone else.
function PlotPickerLogic.Price(ownedBefore: boolean, plotPrice: number): number
	if ownedBefore then
		return 0
	end
	return plotPrice
end

-- The server's verdict on one claim, in the order it checks. `inRange` is
-- the Land Office check (a returning player's join picker has none).
-- Returns "ok", "owned", "range", "taken" or "cash", and the dollars short.
function PlotPickerLogic.Decide(
	hasPlot: boolean,
	inRange: boolean,
	taken: boolean,
	price: number,
	cash: number
): (string, number)
	if hasPlot then
		return "owned", 0
	end
	if not inRange then
		return "range", 0
	end
	if taken then
		return "taken", 0
	end
	if cash < price then
		return "cash", math.ceil(price - cash)
	end
	return "ok", 0
end

-- The picker's words. The price is on the button and the detail line, so
-- what you see is what the server charges.
function PlotPickerLogic.ClaimLabel(price: number): string
	if price > 0 then
		return string.format("BUY PLOT $%d", price)
	end
	return "CLAIM PLOT"
end

function PlotPickerLogic.OpenText(region: string, price: number): string
	if price > 0 then
		return string.format("%s\nOpen plot · $%d", region, price)
	end
	return string.format("%s\nOpen plot", region)
end

-- The line under the buttons: a buyer can leave, an owner takes any pad.
function PlotPickerLogic.AnyText(price: number): string
	if price > 0 then
		return "Not now"
	end
	return "Give me any open plot"
end

-- The refusal toast for a short purse.
function PlotPickerLogic.ShortText(short: number): string
	return string.format("You need $%d more for a plot.", short)
end

-- Next/Previous, including pads that are already taken (the screen says so).
function PlotPickerLogic.Step(index: number, count: number, delta: number): number
	if count < 1 then
		return 1
	end
	return ((index - 1 + delta) % count + count) % count + 1
end

-- The walk speed the picker gives back when it closes. The picker holds the
-- character still (WalkSpeed 0) while it is open; what it saved must never
-- be a stuck zero (a second lock that read the first one's 0, a save made
-- as the character respawned), or the player could not move again.
PlotPickerLogic.DefaultWalkSpeed = 16

function PlotPickerLogic.SafeSpeed(saved: unknown): number
	if type(saved) ~= "number" or saved ~= saved or saved <= 0 or saved == math.huge then
		return PlotPickerLogic.DefaultWalkSpeed
	end
	return saved
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
