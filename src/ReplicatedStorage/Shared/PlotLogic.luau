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
	y: number?, -- base height; missing means the ground (0)
	wood: string?, -- the wood it shows; missing means the authored look
	fill: { units: number }?, -- kit only; missing means already built
	paid: number?, -- the fee charged to place it; missing on a kit piece means the legacy price
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

-- Height on the 0.2-stud stack grid.
function PlotLogic.SnapY(value: number): number
	local step = PlotData.HeightStep
	return math.floor(value / step + 0.5) * step
end

function PlotLogic.HeightOk(y: number): boolean
	if y ~= y or y == math.huge or y == -math.huge then
		return false
	end
	if y < -1e-6 or y > PlotData.MaxBuildY + 1e-6 then
		return false
	end
	local steps = y / PlotData.HeightStep
	return math.abs(steps - math.floor(steps + 0.5)) < 1e-3
end

-- Quarter turns about Y, matching CFrame.Angles(0, rot * pi/2, 0).
local function rotateXZ(x: number, z: number, rot: number): (number, number)
	if rot == 1 then
		return z, -x
	elseif rot == 2 then
		return -x, -z
	elseif rot == 3 then
		return -z, x
	end
	return x, z
end

export type Volume = {
	size: Vector3,
	offset: Vector3,
}

-- The solid the overlap test uses. Edge pieces lose 0.5 at each end of
-- their length. Roofs lose the visual overhang. Neither changes the mesh.
function PlotLogic.OverlapBox(bp: Blueprint, box: PlotData.Box): Volume
	local sx, sy, sz = box.size.X, box.size.Y, box.size.Z
	if bp.roof then
		local hang = PlotData.RoofOverhang
		sx = math.max(0.05, sx - hang * 2)
		sz = math.max(0.05, sz - hang * 2)
	end
	if bp.edge then
		sx = math.max(0.05, sx - PlotData.EdgeTrim * 2)
	end
	return { size = Vector3.new(sx, sy, sz), offset = box.offset }
end

local function worldBox(
	x: number,
	y: number,
	z: number,
	rot: number,
	vol: Volume
): (number, number, number, number, number, number)
	local ox, oz = rotateXZ(vol.offset.X, vol.offset.Z, rot)
	local sx, sz = vol.size.X, vol.size.Z
	if rot % 2 == 1 then
		sx, sz = sz, sx
	end
	return x + ox, y + vol.offset.Y, z + oz, sx, vol.size.Y, sz
end

local function separated(c1: number, s1: number, c2: number, s2: number): boolean
	-- Touching is fine. Any shared length is not.
	return math.abs(c1 - c2) * 2 >= s1 + s2 - 1e-3
end

local function boxesHit(a: { number }, b: { number }): boolean
	return not separated(a[1], a[4], b[1], b[4])
		and not separated(a[2], a[5], b[2], b[5])
		and not separated(a[3], a[6], b[3], b[6])
end

local function itemY(item: Placed): number
	return item.y or 0
end

local function contained(outer: { number }, inner: { number }): boolean
	local function inside(c1: number, s1: number, c2: number, s2: number): boolean
		return math.abs(c1 - c2) + s2 / 2 <= s1 / 2 + 1e-3
	end
	return inside(outer[1], outer[4], inner[1], inner[4])
		and inside(outer[2], outer[5], inner[2], inner[5])
		and inside(outer[3], outer[6], inner[3], inner[6])
end

-- True when every solid of `bp` sits inside some placed opening of kind `fits`.
function PlotLogic.InSlot(
	bp: Blueprint,
	x: number,
	y: number,
	z: number,
	rot: number,
	placed: { Placed },
	ignoreUid: string?
): boolean
	local kind = bp.fits
	if kind ~= "Door" and kind ~= "Window" then
		return true
	end
	local want = if kind == "Door" then "DoorWall8" else "WindowWall8"
	for _, item in ipairs(placed) do
		if item.uid ~= ignoreUid and item.blueprintId == want and item.rot == rot then
			local host = PlotLogic.Blueprint(item.blueprintId)
			local slot = if host then host.slot else nil
			if host and slot then
				local opening = { worldBox(item.x, itemY(item), item.z, item.rot, slot) }
				local fits = true
				for _, box in ipairs(bp.boxes) do
					local solid = { worldBox(x, y, z, rot, { size = box.size, offset = box.offset }) }
					if not contained(opening, solid) then
						fits = false
						break
					end
				end
				if fits then
					return true
				end
			end
		end
	end
	return false
end

function PlotLogic.IsBuilt(bp: Blueprint, item: Placed): boolean
	if bp.kit ~= true then
		return true
	end
	local fill = item.fill
	if fill == nil then
		return true
	end
	return fill.units >= (bp.woodUnits or 0)
end

export type SellPlan = {
	cash: number,
	planks: number, -- u³ to put back on the ground; never also cash
	wood: string?,
}

-- What selling gives back. An empty kit piece returns the fee. A partly
-- filled one returns the planks and no cash. A finished one returns half
-- of what was paid, or half the legacy price when the save has no `paid`.
function PlotLogic.SellPlan(bp: Blueprint, item: Placed): SellPlan
	if bp.kit == true then
		local need = bp.woodUnits or 0
		local fill = item.fill
		local filled = if fill then fill.units else need
		if fill and filled <= 0 then
			return { cash = item.paid or PlotData.Price(bp), planks = 0, wood = nil }
		end
		if fill and filled < need then
			return { cash = 0, planks = filled, wood = item.wood }
		end
		local basis = item.paid or PlotData.LegacyPrice(bp)
		return { cash = math.floor(basis * PlotData.SellBack), planks = 0, wood = nil }
	end
	if bp.unlock then
		return { cash = 0, planks = 0, wood = nil }
	end
	return { cash = math.floor(bp.priceCash * PlotData.SellBack), planks = 0, wood = nil }
end

function PlotLogic.InBounds(rect: Rect, plotSize: number): boolean
	local half = plotSize / 2
	return math.abs(rect.x) + rect.w / 2 <= half and math.abs(rect.z) + rect.d / 2 <= half
end

-- Whether `bp` may go at (x, y, z, rot) on a plot of `tier` holding `placed`
-- (ignoring the item `ignoreUid`, for moves). `y` defaults to the ground.
-- Returns (ok, reason). Touching is allowed; overlapping is not. Pieces may
-- float. A door or window must sit in a matching opening.
function PlotLogic.Check(
	bp: Blueprint,
	x: number,
	z: number,
	rot: number,
	tier: number,
	placed: { Placed },
	ignoreUid: string?,
	y: number?
): (boolean, string?)
	local py = y or 0
	if rot ~= math.floor(rot) or rot < 0 or rot > 3 or x ~= x or z ~= z or not PlotLogic.HeightOk(py) then
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
	local kitCount, otherCount = 0, 0
	for _, item in ipairs(placed) do
		if item.uid ~= ignoreUid then
			local other = PlotLogic.Blueprint(item.blueprintId)
			if other and other.kit then
				kitCount += 1
			else
				otherCount += 1
			end
		end
	end
	if not ignoreUid then
		if bp.kit then
			if kitCount >= PlotData.MaxKit then
				return false, string.format("Your plot holds %d kit pieces at most", PlotData.MaxKit)
			end
		elseif otherCount >= PlotData.MaxItems then
			return false, string.format("Your plot holds %d things at most", PlotData.MaxItems)
		end
	end
	local rect = PlotLogic.RectOf(bp, x, z, rot)
	if not PlotLogic.InBounds(rect, tierDef.size) then
		return false, "Outside your plot"
	end
	if bp.fits and not PlotLogic.InSlot(bp, x, py, z, rot, placed, ignoreUid) then
		return false, if bp.fits == "Door" then "Needs a door opening" else "Needs a window opening"
	end
	local mine = {}
	for _, box in ipairs(bp.boxes) do
		table.insert(mine, { worldBox(x, py, z, rot, PlotLogic.OverlapBox(bp, box)) })
	end
	for _, item in ipairs(placed) do
		if item.uid ~= ignoreUid then
			local other = PlotLogic.Blueprint(item.blueprintId)
			if other then
				for _, box in ipairs(other.boxes) do
					local theirs = { worldBox(item.x, itemY(item), item.z, item.rot, PlotLogic.OverlapBox(other, box)) }
					for _, mineBox in ipairs(mine) do
						if boxesHit(mineBox, theirs) then
							return false, "Something's in the way"
						end
					end
				end
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
