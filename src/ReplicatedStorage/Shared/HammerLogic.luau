--!strict
-- HammerLogic: what using the hammer does, and how it swings. Pure, so the
-- client (which acts) and the tests agree. BUILD_SYSTEM.md is the design.
--
--   * Use: one decision for a click, RT or tap. It opens the blueprint
--     list, or the sheet for a piece you aimed at, or hands an unfilled kit
--     ghost to the BuilderTools bar, or does nothing while a ghost or a
--     panel already has the player's attention.
--   * PieceActions: the sheet for a placed piece (Move, Turn, Sell), with
--     the same locks the server enforces (a filled kit piece cannot move).
--   * Swing: the head's pitch through one swing, and when it lands.
--   * FX: who sees and hears a swing.

local EditLogic = require(script.Parent.EditLogic)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)
local Util = require(script.Parent.Util)

local HammerLogic = {}

---------------------------------------------------------------------------
-- Use
---------------------------------------------------------------------------

export type Hit = {
	mine: boolean, -- a piece on your own plot
	ghost: boolean, -- an unfilled kit piece (BuilderTools edits those)
}

export type UseState = {
	placing: boolean, -- BlueprintPlacer has a ghost out
	panelOpen: boolean, -- the list or a sheet is already up
	hit: Hit?, -- what the aim is on
}

export type UseResult = "none" | "plans" | "piece" | "kit"

function HammerLogic.Use(state: UseState): UseResult
	if state.placing or state.panelOpen then
		return "none"
	end
	local hit = state.hit
	if hit and hit.mine then
		return if hit.ghost then "kit" else "piece"
	end
	return "plans"
end

---------------------------------------------------------------------------
-- The sheet for a placed piece
---------------------------------------------------------------------------

export type Action = {
	id: string, -- "move" | "turn" | "sell"
	label: string,
	enabled: boolean,
	why: string?, -- what to tell the player when it is greyed out
}

function HammerLogic.Turn(rot: number): number
	return (math.floor(rot) + 1) % 4
end

-- A kit piece with wood in it is fixed in place (EditLogic.Locked): it can
-- be sold (the planks come back) but not moved or turned.
function HammerLogic.Fixed(bp: PlotData.Blueprint, item: PlotLogic.Placed): boolean
	return bp.kit == true and EditLogic.Locked(item :: any)
end

function HammerLogic.PieceActions(bp: PlotData.Blueprint, item: PlotLogic.Placed): { Action }
	local fixed = HammerLogic.Fixed(bp, item)
	local why = if fixed then EditLogic.Message("filled") else nil
	local plan = PlotLogic.SellPlan(bp, item)
	local sell = "Sell"
	if plan.planks > 0 then
		sell = "Take apart (planks back)"
	elseif plan.cash > 0 then
		sell = "Sell +" .. Util.formatCash(plan.cash)
	end
	return {
		{ id = "move", label = "Move", enabled = not fixed, why = why },
		{ id = "turn", label = "Turn", enabled = not fixed, why = why },
		{ id = "sell", label = sell, enabled = true, why = nil },
	}
end

---------------------------------------------------------------------------
-- The swing
---------------------------------------------------------------------------

HammerLogic.SwingSeconds = 0.42
-- Where in the swing (0 to 1) the head lands, and so when the knock and the
-- dust happen.
HammerLogic.ImpactAt = 0.55
HammerLogic.RaiseRadians = 1.0 -- the head lifted back at the top of the wind-up
HammerLogic.StrikeRadians = -0.45 -- and past level at the knock

local function ease(u: number): number
	return u * u * (3 - 2 * u)
end

-- The head's pitch (radians, positive = raised) at `u` through the swing,
-- 0 to 1. Starts and ends at 0.
function HammerLogic.Swing(u: number): number
	if u ~= u or u <= 0 or u >= 1 then
		return 0
	end
	local hit = HammerLogic.ImpactAt
	local top = hit * 0.7 -- the head is highest here
	if u < top then
		return HammerLogic.RaiseRadians * ease(u / top)
	elseif u < hit then
		local f = (u - top) / (hit - top)
		return HammerLogic.RaiseRadians + (HammerLogic.StrikeRadians - HammerLogic.RaiseRadians) * f * f
	end
	local f = (u - hit) / (1 - hit)
	return HammerLogic.StrikeRadians * (1 - ease(f))
end

---------------------------------------------------------------------------
-- The dust
---------------------------------------------------------------------------

HammerLogic.DustMin = 4
HammerLogic.DustMax = 14

-- Puffs per knock. `chips` is the device's chip budget (Quality.Budget()):
-- a phone on low still gets a few, a strong machine never more than the max.
function HammerLogic.DustCount(chips: number): number
	if chips ~= chips then
		return HammerLogic.DustMin
	end
	return math.clamp(math.floor(chips / 2), HammerLogic.DustMin, HammerLogic.DustMax)
end

---------------------------------------------------------------------------
-- Who sees it
---------------------------------------------------------------------------

HammerLogic.FxRange = 150 -- studs: a knock is told to players this near

function HammerLogic.Hears(distance: number): boolean
	return distance == distance and distance >= 0 and distance <= HammerLogic.FxRange
end

return HammerLogic
