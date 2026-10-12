--!strict
-- TreeIndex: a ground-plane grid of the things (trees) a 10 Hz look needs
-- to ask "which stand near this line?" about, so the look visits the few
-- cells round the line instead of every tree in the forest (1,400 and
-- growing). Pure: positions come from an injected `homeOf`, so the specs run
-- it without a world.
--   * Sync(index, children, homeOf, budget) learns new children, at most
--     `budget` `homeOf` calls a time (the per-frame work stays bounded when a
--     few hundred trees stream in at once; the rest come on the next calls),
--     and forgets the ones that are gone. Known children cost a table lookup.
--     A child `homeOf` can't place yet (nil) is asked again next time; one it
--     says is never a tree (false) is not asked again while it stays.
--   * Near(index, a, b, reach) returns the known children whose home stands
--     within `reach` of the segment a-b on the ground plane: exactly what a
--     scan of every child with DistanceXZ would give, in no particular order.

local TreeIndex = {}

TreeIndex.Cell = 48 -- studs a cell side (twice a canopy's reach)
TreeIndex.MaxCells = 400 -- a query wider than this many cells scans every known child instead

export type Entry = { home: Vector3, cx: number, cz: number, stamp: number }

export type Index<T> = {
	size: number,
	known: { [T]: Entry },
	cells: { [number]: { [T]: boolean } },
	stamp: number,
	count: number,
	never: { [T]: number }, -- children that are not trees, and the stamp they were last seen at
}

local function key(cx: number, cz: number): number
	return cx * 65536 + cz -- |cx|, |cz| stay well under 32768 for a 2,200-stud world at 48-stud cells
end

function TreeIndex.new<T>(cell: number?): Index<T>
	return {
		size = cell or TreeIndex.Cell,
		known = {},
		cells = {},
		stamp = 0,
		count = 0,
		never = {},
	}
end

local function drop<T>(self: Index<T>, child: T, entry: Entry)
	local k = key(entry.cx, entry.cz)
	local cell = self.cells[k]
	if cell then
		cell[child] = nil
		if next(cell) == nil then
			self.cells[k] = nil
		end
	end
	self.known[child] = nil
	self.count -= 1
end

-- Learns the new children (at most `budget` homeOf calls) and forgets the
-- ones missing from `children`. Returns how many homeOf calls it made.
function TreeIndex.Sync<T>(self: Index<T>, children: { T }, homeOf: (T) -> any, budget: number): number
	self.stamp += 1
	local stamp = self.stamp
	local asked = 0
	for _, child in ipairs(children) do
		local entry = self.known[child]
		if entry then
			entry.stamp = stamp
		elseif self.never[child] then
			self.never[child] = stamp
		elseif asked < budget then
			asked += 1
			local home = homeOf(child)
			if home == false then
				self.never[child] = stamp
			elseif home ~= nil then
				local at = home :: Vector3
				local cx, cz = math.floor(at.X / self.size), math.floor(at.Z / self.size)
				self.known[child] = { home = at, cx = cx, cz = cz, stamp = stamp }
				local k = key(cx, cz)
				local cell = self.cells[k]
				if not cell then
					cell = {}
					self.cells[k] = cell
				end
				cell[child] = true
				self.count += 1
			end
		end
	end
	-- Whatever was not in this list is gone.
	for child, entry in pairs(self.known) do
		if entry.stamp ~= stamp then
			drop(self, child, entry)
		end
	end
	for child, seen in pairs(self.never) do
		if seen ~= stamp then
			self.never[child] = nil
		end
	end
	return asked
end

-- How far a point is from the segment a-b on the ground plane (the same
-- numbers as CanopyLogic.DistanceXZ, kept here so the index has no
-- dependency; the spec pins that they agree).
local function distanceXZ(point: Vector3, a: Vector3, b: Vector3): number
	local px, pz = point.X - a.X, point.Z - a.Z
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len2 = dx * dx + dz * dz
	local s = if len2 > 1e-9 then math.clamp((px * dx + pz * dz) / len2, 0, 1) else 0
	local ex, ez = px - dx * s, pz - dz * s
	return math.sqrt(ex * ex + ez * ez)
end

-- The known children whose home is within `reach` (ground plane) of a-b.
-- Also returns how many entries it looked at (the work, for the specs).
function TreeIndex.Near<T>(self: Index<T>, a: Vector3, b: Vector3, reach: number): ({ T }, number)
	local out: { T } = {}
	local looked = 0
	local size = self.size
	local cx0 = math.floor((math.min(a.X, b.X) - reach) / size)
	local cx1 = math.floor((math.max(a.X, b.X) + reach) / size)
	local cz0 = math.floor((math.min(a.Z, b.Z) - reach) / size)
	local cz1 = math.floor((math.max(a.Z, b.Z) + reach) / size)
	if (cx1 - cx0 + 1) * (cz1 - cz0 + 1) > TreeIndex.MaxCells then
		for child, entry in pairs(self.known) do
			looked += 1
			if distanceXZ(entry.home, a, b) <= reach then
				table.insert(out, child)
			end
		end
		return out, looked
	end
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local cell = self.cells[key(cx, cz)]
			if cell then
				for child in pairs(cell) do
					looked += 1
					if distanceXZ(self.known[child].home, a, b) <= reach then
						table.insert(out, child)
					end
				end
			end
		end
	end
	return out, looked
end

return TreeIndex
