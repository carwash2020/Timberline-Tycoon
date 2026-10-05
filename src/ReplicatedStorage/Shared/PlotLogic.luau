--!strict
-- PlotLogic: where a blueprint may go on a plot (PlotData). Pure, so the
-- server (which decides) and the client's ghost preview (which shows green
-- or red) agree, and tests can run it.

local ChopSawLogic = require(script.Parent.ChopSawLogic)
local GameConfig = require(script.Parent.GameConfig)
local PieceSize = require(script.Parent.PieceSize)
local PlotData = require(script.Parent.PlotData)
local SawmillLogic = require(script.Parent.SawmillLogic)
local WorldLayout = require(script.Parent.World.WorldLayout)

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
	len: number?, -- resized length along local X; missing means the base length
	lenX: number?, -- floor width; missing means the base
	lenZ: number?, -- floor depth; missing means the base
	data: { x: number, y: number }?,
}

-- A decor blueprint, a sawmill, or a chop saw (they place on the same grid).
function PlotLogic.Blueprint(id: string): Blueprint?
	return PlotData.Blueprint(id) or SawmillLogic.Blueprint(id) or ChopSawLogic.Blueprint(id)
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
	return fill.units >= PieceSize.Units(bp, item)
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
		local need = PieceSize.Units(bp, item)
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

---------------------------------------------------------------------------
-- Yard squares. The five tiers stay the base. Beyond that base, a 5×5
-- grid of PlotSquare studs is bought one square at a time, outward, each
-- one pricier than the last. The first square is FirstPlotPrice. Square
-- k after that costs ExpansionPriceStep × k. Check, spend, then grant,
-- with no yield in between: money never leaves without the square.
---------------------------------------------------------------------------

-- Phone land-office cells and the buy control are at least this tall.
PlotLogic.LandTap = 48

-- Studs past the north edge where a visitor with visit off is set down.
PlotLogic.EjectGap = 8

export type Purse = {
	cash: () -> number,
	spend: (number) -> boolean,
	refund: (number) -> (),
}

function PlotLogic.GridHalf(): number
	return math.floor((GameConfig.PlotGrid - 1) / 2)
end

function PlotLogic.Key(ix: number, iz: number): string
	return string.format("%d,%d", ix, iz)
end

function PlotLogic.ParseKey(key: string): (number?, number?)
	local xs, zs = string.match(key, "^(%-?%d+),(%-?%d+)$")
	if not xs or not zs then
		return nil, nil
	end
	return tonumber(xs), tonumber(zs)
end

function PlotLogic.InGrid(ix: number, iz: number): boolean
	if ix ~= math.floor(ix) or iz ~= math.floor(iz) then
		return false
	end
	local half = PlotLogic.GridHalf()
	return math.abs(ix) <= half and math.abs(iz) <= half
end

-- Plot-local edges of square (ix, iz): min x, max x, min z, max z.
function PlotLogic.SquareBox(ix: number, iz: number): (number, number, number, number)
	local s = GameConfig.PlotSquare
	return ix * s - s / 2, ix * s + s / 2, iz * s - s / 2, iz * s + s / 2
end

function PlotLogic.Owns(squares: { string }, ix: number, iz: number): boolean
	return table.find(squares, PlotLogic.Key(ix, iz)) ~= nil
end

function PlotLogic.SquareInsideTier(ix: number, iz: number, tierSize: number): boolean
	local x0, x1, z0, z1 = PlotLogic.SquareBox(ix, iz)
	local half = tierSize / 2
	return x0 >= -half - 1e-3 and x1 <= half + 1e-3 and z0 >= -half - 1e-3 and z1 <= half + 1e-3
end

-- How wide the yard is, counting the tier and every bought square.
function PlotLogic.Extent(tierSize: number, squares: { string }): number
	local half = tierSize / 2
	for _, key in ipairs(squares) do
		local ix, iz = PlotLogic.ParseKey(key)
		if ix and iz then
			local x0, x1, z0, z1 = PlotLogic.SquareBox(ix, iz)
			half = math.max(half, math.abs(x0), math.abs(x1), math.abs(z0), math.abs(z1))
		end
	end
	return half * 2
end

-- Plot-local spot just north of the yard.
function PlotLogic.EjectLocal(tierSize: number, squares: { string }): (number, number)
	local half = PlotLogic.Extent(tierSize, squares) / 2
	return 0, half + PlotLogic.EjectGap
end

-- North, east, west, south, then a step further north, then further out
-- on every side and the corners (B15: a plot by the water or a road has
-- more places to try). The first that isn't on a road or in the water is
-- where a visitor is put down.
function PlotLogic.EjectCandidates(tierSize: number, squares: { string }): { { number } }
	local half = PlotLogic.Extent(tierSize, squares) / 2
	local gap = PlotLogic.EjectGap
	local north = half + gap
	return {
		{ 0, north },
		{ north, 0 },
		{ -north, 0 },
		{ 0, -(half + gap) },
		{ 0, north + gap },
		{ north + gap, 0 },
		{ -(north + gap), 0 },
		{ 0, -(half + 2 * gap) },
		{ north, north },
		{ -north, north },
		{ north, -north },
		{ -north, -north },
	}
end

function PlotLogic.EjectSpot(tierSize: number, squares: { string }, bad: (number, number) -> boolean): (number, number)
	for _, spot in ipairs(PlotLogic.EjectCandidates(tierSize, squares)) do
		if not bad(spot[1], spot[2]) then
			return spot[1], spot[2]
		end
	end
	return PlotLogic.EjectLocal(tierSize, squares)
end

function PlotLogic.OnRoad(x: number, z: number): boolean
	local p = Vector2.new(x, z)
	for _, road in ipairs(WorldLayout.Roads) do
		if WorldLayout.PolylineDistance(p, road.points) <= road.width / 2 + 2 then
			return true
		end
	end
	return false
end

function PlotLogic.InWater(x: number, z: number): boolean
	local function pool(w: { x: number, z: number, radius: number }): boolean
		local dx, dz = x - w.x, z - w.z
		return dx * dx + dz * dz <= w.radius * w.radius
	end
	if pool(WorldLayout.Lake) or pool(WorldLayout.Pond) then
		return true
	end
	local p = Vector2.new(x, z)
	if WorldLayout.PolylineDistance(p, WorldLayout.River.points) <= WorldLayout.River.width / 2 then
		return true
	end
	return WorldLayout.PolylineDistance(p, WorldLayout.LakeOutflow.points) <= WorldLayout.LakeOutflow.width / 2
end

function PlotLogic.GroundBad(inWater: boolean, onRoad: boolean): boolean
	return inWater or onRoad
end

local NEIGHBOR = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function PlotLogic.TouchesLand(ix: number, iz: number, tierSize: number, squares: { string }): boolean
	for _, step in ipairs(NEIGHBOR) do
		local jx, jz = ix + step[1], iz + step[2]
		if PlotLogic.InGrid(jx, jz) then
			if PlotLogic.SquareInsideTier(jx, jz, tierSize) or PlotLogic.Owns(squares, jx, jz) then
				return true
			end
		end
	end
	return false
end

-- Price of the next square when `bought` are already owned. Nil when the
-- grid is full. The first is FirstPlotPrice; later ones step up by
-- ExpansionPriceStep, so the number on the button is the number spent.
function PlotLogic.ExpansionPrice(bought: number): number?
	local cap = GameConfig.PlotGrid * GameConfig.PlotGrid
	if bought < 0 or bought ~= math.floor(bought) or bought >= cap then
		return nil
	end
	if bought == 0 then
		return GameConfig.FirstPlotPrice
	end
	return GameConfig.ExpansionPriceStep * bought
end

-- (key, nil) when (ix, iz) can be bought, else (nil, reason).
function PlotLogic.ExpansionBlock(tier: number, squares: { string }, ix: number, iz: number): (string?, string?)
	if ix ~= ix or iz ~= iz or not PlotLogic.InGrid(ix, iz) then
		return nil, "bad"
	end
	local tierDef = PlotData.Tier(tier)
	if not tierDef then
		return nil, "bad"
	end
	if PlotLogic.SquareInsideTier(ix, iz, tierDef.size) then
		return nil, "yours"
	end
	if PlotLogic.Owns(squares, ix, iz) then
		return nil, "owned"
	end
	if not PlotLogic.ExpansionPrice(#squares) then
		return nil, "full"
	end
	if not PlotLogic.TouchesLand(ix, iz, tierDef.size, squares) then
		return nil, "away"
	end
	return PlotLogic.Key(ix, iz), nil
end

function PlotLogic.ExpansionMessage(why: string?, _price: number?): string?
	if why == "cash" then
		return "You don't have enough for that square."
	elseif why == "yours" then
		return "That ground is already part of your yard."
	elseif why == "owned" then
		return "You already bought that square."
	elseif why == "away" then
		return "Buy a square that touches your yard."
	elseif why == "full" then
		return "Your yard already covers every square."
	end
	return nil
end

local function overlapArea(a0: number, a1: number, b0: number, b1: number): number
	return math.min(a1, b1) - math.max(a0, b0)
end

-- True when the footprint sits on the tier, on bought squares, or both.
function PlotLogic.OnLand(rect: Rect, tierSize: number, squares: { string }): boolean
	local half = tierSize / 2
	local x0, x1 = rect.x - rect.w / 2, rect.x + rect.w / 2
	local z0, z1 = rect.z - rect.d / 2, rect.z + rect.d / 2
	if x0 >= -half - 1e-3 and x1 <= half + 1e-3 and z0 >= -half - 1e-3 and z1 <= half + 1e-3 then
		return true
	end
	local gridHalf = PlotLogic.GridHalf()
	local edge = (gridHalf + 0.5) * GameConfig.PlotSquare
	if x0 < -edge - 1e-3 or x1 > edge + 1e-3 or z0 < -edge - 1e-3 or z1 > edge + 1e-3 then
		return false
	end
	for ix = -gridHalf, gridHalf do
		for iz = -gridHalf, gridHalf do
			local sx0, sx1, sz0, sz1 = PlotLogic.SquareBox(ix, iz)
			local ox = overlapArea(x0, x1, sx0, sx1)
			local oz = overlapArea(z0, z1, sz0, sz1)
			if ox > 1e-3 and oz > 1e-3 then
				local ix0, ix1 = math.max(x0, sx0), math.min(x1, sx1)
				local iz0, iz1 = math.max(z0, sz0), math.min(z1, sz1)
				local inTier = ix0 >= -half - 1e-3 and ix1 <= half + 1e-3 and iz0 >= -half - 1e-3 and iz1 <= half + 1e-3
				if not inTier and not PlotLogic.Owns(squares, ix, iz) then
					return false
				end
			end
		end
	end
	return true
end

local function dropKey(squares: { string }, key: string)
	local at = table.find(squares, key)
	if at then
		table.remove(squares, at)
	end
end

-- Check, then spend, then grant, in this call. A spend that fails or throws
-- after taking cash is refunded, and the square is not added.
function PlotLogic.TryExpand(
	plot: { tier: number, squares: { string } },
	ix: number,
	iz: number,
	purse: Purse
): (boolean, string?, number?)
	if type(plot.squares) ~= "table" then
		plot.squares = {}
	end
	local key, why = PlotLogic.ExpansionBlock(plot.tier, plot.squares, ix, iz)
	if not key then
		return false, why, nil
	end
	local price = PlotLogic.ExpansionPrice(#plot.squares)
	if not price or price <= 0 then
		return false, "bad", nil
	end
	local before = purse.cash()
	if before < price then
		return false, "cash", price
	end
	local paidOk, paid = pcall(function()
		return purse.spend(price)
	end)
	if not paidOk or paid ~= true then
		local now = purse.cash()
		if now < before then
			purse.refund(before - now)
		end
		return false, "cash", price
	end
	table.insert(plot.squares, key)
	if not PlotLogic.Owns(plot.squares, ix, iz) then
		dropKey(plot.squares, key)
		purse.refund(price)
		return false, "grant", price
	end
	return true, nil, price
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
	y: number?,
	squares: { string }?
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
	local onYard = if squares
		then PlotLogic.OnLand(rect, tierDef.size, squares)
		else PlotLogic.InBounds(rect, tierDef.size)
	if not onYard then
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
				local shaped = PieceSize.Shape(other, item)
				for _, box in ipairs(shaped.boxes) do
					local theirs =
						{ worldBox(item.x, itemY(item), item.z, item.rot, PlotLogic.OverlapBox(shaped, box)) }
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
