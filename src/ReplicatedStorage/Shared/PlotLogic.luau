--!strict
-- PlotLogic: where a blueprint may go on a plot (PlotData). Pure, so the
-- server (which decides) and the client's ghost preview (which shows green
-- or red) agree, and tests can run it.

local PlotData = require(script.Parent.PlotData)
local SawmillLogic = require(script.Parent.SawmillLogic)

type Blueprint = PlotData.Blueprint

local PlotLogic = {}

export type Placed = {
	uid: string,
	blueprintId: string,
	x: number,
	z: number,
	rot: number,
	data: { x: number, y: number }?,
}

-- A decor blueprint, or a sawmill (they place on the same grid).
function PlotLogic.Blueprint(id: string): Blueprint?
	return PlotData.Blueprint(id) or SawmillLogic.Blueprint(id)
end

export type Rect = { x: number, z: number, w: number, d: number } -- centre + size

-- The footprint at a rotation (quarter turns swap width and depth).
function PlotLogic.Footprint(bp: Blueprint, rot: number): (number, number)
	if rot % 2 == 1 then
		return bp.footprint.Y, bp.footprint.X
	end
	return bp.footprint.X, bp.footprint.Y
end

function PlotLogic.RectOf(bp: Blueprint, x: number, z: number, rot: number): Rect
	local w, d = PlotLogic.Footprint(bp, rot)
	return { x = x, z = z, w = w, d = d }
end

-- Snaps a plot-local coordinate to the grid (PlotData.Grid).
function PlotLogic.Snap(value: number): number
	local grid = PlotData.Grid
	return math.floor(value / grid + 0.5) * grid
end

local function overlaps(a: Rect, b: Rect): boolean
	-- Touching edges is fine; any shared area is not.
	return math.abs(a.x - b.x) * 2 < a.w + b.w and math.abs(a.z - b.z) * 2 < a.d + b.d
end

function PlotLogic.InBounds(rect: Rect, plotSize: number): boolean
	local half = plotSize / 2
	return math.abs(rect.x) + rect.w / 2 <= half and math.abs(rect.z) + rect.d / 2 <= half
end

-- Whether `bp` may go at (x, z, rot) on a plot of `tier` holding `placed`
-- (ignoring the item `ignoreUid`, for moves). Returns (ok, reason).
function PlotLogic.Check(
	bp: Blueprint,
	x: number,
	z: number,
	rot: number,
	tier: number,
	placed: { Placed },
	ignoreUid: string?
): (boolean, string?)
	if rot ~= math.floor(rot) or rot < 0 or rot > 3 or x ~= x or z ~= z then
		return false, "bad"
	end
	local tierDef = PlotData.Tier(tier)
	if not tierDef then
		return false, "bad"
	end
	if bp.tier > tier then
		local needed = PlotData.Tier(bp.tier)
		return false, string.format("Needs a %s plot", if needed then needed.name else "bigger")
	end
	if #placed >= PlotData.MaxItems and not ignoreUid then
		return false, string.format("Your plot holds %d things at most", PlotData.MaxItems)
	end
	local rect = PlotLogic.RectOf(bp, x, z, rot)
	if not PlotLogic.InBounds(rect, tierDef.size) then
		return false, "Outside your plot"
	end
	for _, item in ipairs(placed) do
		if item.uid ~= ignoreUid then
			local other = PlotLogic.Blueprint(item.blueprintId)
			if other and overlaps(rect, PlotLogic.RectOf(other, item.x, item.z, item.rot)) then
				return false, "Something's in the way"
			end
		end
	end
	return true, nil
end

-- What selling a placed item pays back.
function PlotLogic.SellValue(bp: Blueprint): number
	if bp.unlock then
		return 0 -- copies of a store unlock don't pay cash back
	end
	return math.floor(bp.priceCash * PlotData.SellBack)
end

-- Cash to place one. An unlock the player already bought is free. An unlock
-- they haven't bought can't be placed from here (the store sells it once).
function PlotLogic.PlacePrice(bp: Blueprint, unlocked: boolean): number?
	if bp.unlock then
		return if unlocked then 0 else nil
	end
	return PlotData.Price(bp)
end

return PlotLogic
