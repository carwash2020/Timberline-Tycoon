--!strict
-- ShelfLayout: where boxes stand on a shop's tables and shelves. Pure.
-- A lane is a flat strip (a table top, a shelf board). Boxes go on it in
-- rows from the front (-Z) backward, in the order they are handed in, and
-- every box is spaced by its OWN width and depth plus BoxSize.Gap, so a
-- large box never overlaps its neighbours and a lane with small boxes
-- holds more of them. A box that does not fit goes to the next lane that
-- takes its kind. Coordinates are final studs, relative to the shop's
-- origin; boxes face -Z like the shop.
--
-- A lane may be a STEPPED display (Lane.step): every row stands a little
-- higher than the one in front of it (to the back, +Z), up to Lane.maxRise,
-- so the rows behind show over the rows in front. Spot.y is the box's middle
-- on its own step.

local BoxSize = require(script.Parent.BoxSize)

local ShelfLayout = {}

export type Lane = {
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y: number, -- the surface the first row's boxes stand on
	kinds: { string }?, -- item kinds this lane takes (nil: any)
	step: number?, -- each row stands this much higher than the one in front (nil: flat)
	maxRise: number?, -- the most the back rows rise over the first (nil: no limit)
}

export type Item = {
	id: string,
	kind: string,
	w: number, -- along x
	h: number,
	d: number, -- along z (the whole group for a slot with several boxes)
}

export type Spot = {
	id: string,
	lane: string,
	row: number, -- 1 = the front row of its lane
	x: number,
	y: number, -- the box's middle, on its row's step
	z: number,
	w: number,
	h: number,
	d: number,
}

type Row = { start: number, items: { Item }, width: number, depth: number }

type State = {
	lane: Lane,
	rows: { Row },
}

local function takes(lane: Lane, kind: string): boolean
	local kinds = lane.kinds
	if kinds == nil then
		return true
	end
	return table.find(kinds, kind) ~= nil
end

-- How high row `row` (1 = front) stands over the lane's first row.
function ShelfLayout.Rise(lane: Lane, row: number): number
	local rise = (lane.step or 0) * (row - 1)
	local cap = lane.maxRise
	if cap ~= nil then
		rise = math.min(rise, cap)
	end
	return rise
end

-- The room a lane has for a row: its width less the edge gap at each side.
local function rowRoom(lane: Lane): number
	return (lane.x1 - lane.x0) - 2 * BoxSize.EdgeGap
end

local function length(lane: Lane): number
	return lane.z1 - lane.z0 - BoxSize.EdgeGap
end

-- Lays `items` onto `lanes`. Returns every spot, and the items nothing had
-- room for (the specs keep that list empty).
function ShelfLayout.Fill(lanes: { Lane }, items: { Item }): ({ Spot }, { Item })
	local states: { State } = {}
	for _, lane in ipairs(lanes) do
		table.insert(states, { lane = lane, rows = {} })
	end
	local overflow: { Item } = {}
	for _, item in ipairs(items) do
		local placed = false
		for _, state in ipairs(states) do
			local lane = state.lane
			if not takes(lane, item.kind) or item.w > rowRoom(lane) then
				continue
			end
			local last = state.rows[#state.rows]
			if last and last.width + BoxSize.Gap + item.w <= rowRoom(lane) + 1e-6 then
				local deeper = math.max(last.depth, item.d)
				if last.start + deeper <= length(lane) + 1e-6 then
					table.insert(last.items, item)
					last.width += BoxSize.Gap + item.w
					last.depth = deeper
					placed = true
					break
				end
			end
			local start = if last then last.start + last.depth + BoxSize.Gap else BoxSize.EdgeGap
			if start + item.d <= length(lane) + 1e-6 then
				table.insert(state.rows, { start = start, items = { item }, width = item.w, depth = item.d })
				placed = true
				break
			end
		end
		if not placed then
			table.insert(overflow, item)
		end
	end
	local spots: { Spot } = {}
	for _, state in ipairs(states) do
		local lane = state.lane
		local cx = (lane.x0 + lane.x1) / 2
		for rowIndex, row in ipairs(state.rows) do
			local x = cx - row.width / 2
			local rise = ShelfLayout.Rise(lane, rowIndex)
			for _, item in ipairs(row.items) do
				table.insert(spots, {
					id = item.id,
					lane = lane.name,
					row = rowIndex,
					x = x + item.w / 2,
					y = lane.y + rise + item.h / 2,
					z = lane.z0 + row.start + row.depth / 2,
					w = item.w,
					h = item.h,
					d = item.d,
				})
				x += item.w + BoxSize.Gap
			end
		end
	end
	return spots, overflow
end

-- Whether two spots overlap on the floor plan (their gap is under `gap`).
function ShelfLayout.Overlap(a: Spot, b: Spot, gap: number?): boolean
	local g = gap or 0
	local dx = math.abs(a.x - b.x) - (a.w + b.w) / 2
	local dz = math.abs(a.z - b.z) - (a.d + b.d) / 2
	return dx < g - 1e-6 and dz < g - 1e-6
end

return ShelfLayout
