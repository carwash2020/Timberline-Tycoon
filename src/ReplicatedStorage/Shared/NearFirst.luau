--!strict
-- NearFirst: "build what is nearest the players first". One tested place for
-- the ordering the forest planter, the terrain writer and the mesh swaps use.
--
--   * Distances are measured on the ground (x, z) to the NEAREST of the focus
--     points (the players), or to `fallback` (the spawn) when there are none.
--   * Ties keep the order the items were given in, so the order never depends
--     on table iteration or on a sort's whim.
--   * Queue: a pool of items taken nearest-first. The focus is asked again on
--     every Next; when a player has moved more than `resortDistance` studs
--     since the last sort the pool is sorted again (cheap: a few hundred
--     items, only when someone actually moved), so a player who runs off
--     toward the volcano pulls the volcano's trees forward. Items can be added
--     while it is being drained (the planner hands over a batch at a time).
--
-- Pure: the focus is injected.

local NearFirst = {}

export type Point = { x: number, z: number }

-- Squared distance from (x, z) to the nearest of `focus`, or to `fallback`.
function NearFirst.Distance2(x: number, z: number, focus: { Point }?, fallback: Point): number
	local points = focus
	if points == nil or #points == 0 then
		local dx, dz = x - fallback.x, z - fallback.z
		return dx * dx + dz * dz
	end
	local best = math.huge
	for _, p in ipairs(points) do
		local dx, dz = x - p.x, z - p.z
		local d = dx * dx + dz * dz
		if d < best then
			best = d
		end
	end
	return best
end

-- Whether the focus has moved: a different number of points, or one point
-- more than `distance` studs from where it was (`was` nil: yes).
function NearFirst.Moved(now: { Point }, was: { Point }?, distance: number): boolean
	if was == nil or #now ~= #was then
		return true
	end
	for i, p in ipairs(now) do
		local q = was[i]
		local dx, dz = p.x - q.x, p.z - q.z
		if dx * dx + dz * dz > distance * distance then
			return true
		end
	end
	return false
end

-- `items` nearest first (a new list; `items` is not touched). `tier` (lower
-- first) is optional: a tier always beats distance.
function NearFirst.Order<T>(
	items: { T },
	positionOf: (item: T) -> Point,
	focus: { Point }?,
	fallback: Point,
	tier: ((item: T) -> number)?
): { T }
	local key: { [number]: number } = {}
	local rank: { [number]: number } = {}
	local indices: { number } = {}
	for i, item in ipairs(items) do
		local p = positionOf(item)
		key[i] = NearFirst.Distance2(p.x, p.z, focus, fallback)
		rank[i] = if tier then tier(item) else 0
		indices[i] = i
	end
	table.sort(indices, function(a: number, b: number): boolean
		if rank[a] ~= rank[b] then
			return rank[a] < rank[b]
		end
		if key[a] ~= key[b] then
			return key[a] < key[b]
		end
		return a < b
	end)
	local out: { T } = {}
	for _, i in ipairs(indices) do
		table.insert(out, items[i])
	end
	return out
end

export type QueueOptions = {
	focus: (() -> { Point })?, -- where the players are (empty or none: `fallback`)
	fallback: Point?, -- default the origin
	resortDistance: number?, -- studs a focus point may move before a re-sort (default 40)
}

export type Queue<T> = {
	Add: (items: { T }) -> (),
	Next: () -> T?, -- the nearest item, removed (nil when empty)
	Remaining: () -> number,
	Resorts: () -> number, -- how many times the pool has been sorted
}

function NearFirst.Queue<T>(positionOf: (item: T) -> Point, options: QueueOptions?): Queue<T>
	local focusFn = options and options.focus
	local fallback = (options and options.fallback) or { x = 0, z = 0 }
	local resortDistance = (options and options.resortDistance) or 40
	-- `pool` is kept with the NEAREST LAST (cheap to pop); `order` is each
	-- item's arrival number (`order`, parallel to it), the tie-break.
	local pool: { T } = {}
	local order: { number } = {} -- parallel to pool
	local nextSerial = 0
	local sortedFor: { Point }? = nil
	local dirty = false
	local resorts = 0

	local function sortPool(focus: { Point })
		resorts += 1
		local n = #pool
		local key: { number } = table.create(n)
		local indices: { number } = table.create(n)
		for i = 1, n do
			local p = positionOf(pool[i])
			key[i] = NearFirst.Distance2(p.x, p.z, focus, fallback)
			indices[i] = i
		end
		table.sort(indices, function(a: number, b: number): boolean
			if key[a] ~= key[b] then
				return key[a] > key[b] -- farthest first, so the nearest is last
			end
			return order[a] > order[b] -- the later arrival first, so the earlier one is nearer the end
		end)
		local newPool: { T } = table.create(n)
		local newOrder: { number } = table.create(n)
		for i, from in ipairs(indices) do
			newPool[i] = pool[from]
			newOrder[i] = order[from]
		end
		pool, order = newPool, newOrder
		sortedFor = table.clone(focus)
		dirty = false
	end

	local queue = {} :: Queue<T>
	queue.Add = function(items: { T })
		for _, item in ipairs(items) do
			nextSerial += 1
			table.insert(pool, item)
			table.insert(order, nextSerial)
		end
		if #items > 0 then
			dirty = true
		end
	end
	queue.Next = function(): T?
		if #pool == 0 then
			return nil
		end
		local focus: { Point } = if focusFn then focusFn() else {}
		if dirty or NearFirst.Moved(focus, sortedFor, resortDistance) then
			sortPool(focus)
		end
		table.remove(order)
		return table.remove(pool) :: T
	end
	queue.Remaining = function(): number
		return #pool
	end
	queue.Resorts = function(): number
		return resorts
	end
	return queue
end

return NearFirst
