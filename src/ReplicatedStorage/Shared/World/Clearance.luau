--!strict
-- Clearance: 2D footprints and a spatial hash, so "does anything overlap" is a
-- check that runs in a spec and in tools/overlap_report (never at boot).
--   * A shape is a disc (a tree trunk, a boulder, a scenery piece) or a polygon
--     (a building or prop rectangle, a cluster outline). Distance is in studs on
--     the ground plane: 0 when two shapes touch or overlap, and for two discs the
--     gap between their edges (negative when they overlap).
--   * Grid is a hash of CELL-stud squares (24), each shape in every square its
--     bounds touch, so a query reads only the few squares near it: O(n) for the
--     whole map instead of O(n^2).
--   * Sources: a generator registers its footprints here (Clearance.Register),
--     and the overlap check walks every source. A generator that cannot pass
--     moves its own output, never an existing tree, rock or building.
-- Pure: no services, no terrain.

local Clearance = {}

Clearance.Cell = 24

export type Shape = {
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	r: number?, -- a disc: its centre is the middle of the bounds
	pts: { Vector2 }?, -- a polygon (not a disc)
}

function Clearance.Disc(x: number, z: number, r: number): Shape
	return { x0 = x - r, z0 = z - r, x1 = x + r, z1 = z + r, r = r }
end

function Clearance.Poly(pts: { Vector2 }): Shape
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(pts) do
		x0, z0 = math.min(x0, p.X), math.min(z0, p.Y)
		x1, z1 = math.max(x1, p.X), math.max(z1, p.Y)
	end
	return { x0 = x0, z0 = z0, x1 = x1, z1 = z1, pts = pts }
end

function Clearance.Rect(x0: number, z0: number, x1: number, z1: number): Shape
	return Clearance.Poly({ Vector2.new(x0, z0), Vector2.new(x1, z0), Vector2.new(x1, z1), Vector2.new(x0, z1) })
end

-- The shape pushed out by `m` studs on every side.
function Clearance.Grow(shape: Shape, m: number): Shape
	local r = shape.r
	if r then
		return Clearance.Disc((shape.x0 + shape.x1) / 2, (shape.z0 + shape.z1) / 2, r + m)
	end
	return { x0 = shape.x0 - m, z0 = shape.z0 - m, x1 = shape.x1 + m, z1 = shape.z1 + m, pts = shape.pts, r = nil }
end

local function centre(s: Shape): (number, number)
	return (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
end

local function segDist(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-12 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function inside(p: Vector2, pts: { Vector2 }): boolean
	local hit = false
	local n = #pts
	local j = n
	for i = 1, n do
		local a, b = pts[i], pts[j]
		if (a.Y > p.Y) ~= (b.Y > p.Y) and p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X then
			hit = not hit
		end
		j = i
	end
	return hit
end

local function cross(o: Vector2, a: Vector2, b: Vector2): number
	return (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X)
end

local function segmentsCross(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local d1, d2 = cross(a, b, c), cross(a, b, d)
	local d3, d4 = cross(c, d, a), cross(c, d, b)
	return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end

-- Distance from a point to a polygon: 0 inside it.
local function pointPoly(p: Vector2, pts: { Vector2 }): number
	if inside(p, pts) then
		return 0
	end
	local best = math.huge
	local n = #pts
	for i = 1, n do
		best = math.min(best, segDist(p, pts[i], pts[i % n + 1]))
	end
	return best
end

local function polyPoly(a: { Vector2 }, b: { Vector2 }): number
	for _, p in ipairs(a) do
		if inside(p, b) then
			return 0
		end
	end
	for _, p in ipairs(b) do
		if inside(p, a) then
			return 0
		end
	end
	local na, nb = #a, #b
	for i = 1, na do
		local a1, a2 = a[i], a[i % na + 1]
		for j = 1, nb do
			if segmentsCross(a1, a2, b[j], b[j % nb + 1]) then
				return 0
			end
		end
	end
	local best = math.huge
	for i = 1, na do
		for j = 1, nb do
			best = math.min(best, segDist(a[i], b[j], b[j % nb + 1]), segDist(b[j], a[i], a[i % na + 1]))
		end
	end
	return best
end

-- Studs between the edges of two shapes: 0 when they touch or overlap (for two
-- discs, negative when they overlap).
function Clearance.Distance(a: Shape, b: Shape): number
	local ar, br = a.r, b.r
	if ar and br then
		local ax, az = centre(a)
		local bx, bz = centre(b)
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) - ar - br
	end
	if ar then
		local ax, az = centre(a)
		return math.max(0, pointPoly(Vector2.new(ax, az), (b.pts :: any) :: { Vector2 }) - ar)
	end
	if br then
		return Clearance.Distance(b, a)
	end
	return polyPoly((a.pts :: any) :: { Vector2 }, (b.pts :: any) :: { Vector2 })
end

-- True when the two shapes are closer than `gap` studs (0: overlapping or touching).
function Clearance.Closer(a: Shape, b: Shape, gap: number): boolean
	if a.x0 - gap >= b.x1 or b.x0 - gap >= a.x1 or a.z0 - gap >= b.z1 or b.z0 - gap >= a.z1 then
		return false
	end
	return Clearance.Distance(a, b) < gap
end

---------------------------------------------------------------------------
-- The grid
---------------------------------------------------------------------------

export type Entry = { id: string, kind: string, shape: Shape, tag: any? }
export type Grid = {
	cell: number,
	cells: { [number]: { Entry } },
	all: { Entry },
}

local SPAN = 8192
local BIAS = 4096

local function key(cx: number, cz: number): number
	return (cx + BIAS) * SPAN + (cz + BIAS)
end

function Clearance.NewGrid(cell: number?): Grid
	return { cell = cell or Clearance.Cell, cells = {}, all = {} }
end

function Clearance.Add(grid: Grid, id: string, kind: string, shape: Shape, tag: any?): Entry
	local entry: Entry = { id = id, kind = kind, shape = shape, tag = tag }
	table.insert(grid.all, entry)
	local c = grid.cell
	for cx = math.floor(shape.x0 / c), math.floor(shape.x1 / c) do
		for cz = math.floor(shape.z0 / c), math.floor(shape.z1 / c) do
			local k = key(cx, cz)
			local list = grid.cells[k]
			if not list then
				list = {}
				grid.cells[k] = list
			end
			table.insert(list, entry)
		end
	end
	return entry
end

-- Every entry within `gap` studs of `shape` (each once), optionally of one kind.
function Clearance.Near(grid: Grid, shape: Shape, gap: number, kind: string?): { Entry }
	local out: { Entry } = {}
	local seen: { [Entry]: boolean } = {}
	local c = grid.cell
	for cx = math.floor((shape.x0 - gap) / c), math.floor((shape.x1 + gap) / c) do
		for cz = math.floor((shape.z0 - gap) / c), math.floor((shape.z1 + gap) / c) do
			for _, entry in ipairs(grid.cells[key(cx, cz)] or {}) do
				if not seen[entry] and (kind == nil or entry.kind == kind) then
					seen[entry] = true
					if Clearance.Closer(shape, entry.shape, gap) then
						table.insert(out, entry)
					end
				end
			end
		end
	end
	return out
end

export type Hit = { a: Entry, b: Entry, gap: number }

-- Every pair (a of kind `kindA`, b of kind `kindB`) closer than `gap`. With
-- kindA == kindB each pair is listed once. `ignore` (optional) skips a pair.
function Clearance.Hits(
	grid: Grid,
	kindA: string,
	kindB: string,
	gap: number,
	ignore: ((a: Entry, b: Entry) -> boolean)?
): { Hit }
	local out: { Hit } = {}
	local same = kindA == kindB
	local order: { [Entry]: number } = {}
	for i, entry in ipairs(grid.all) do
		order[entry] = i
	end
	for _, a in ipairs(grid.all) do
		if a.kind == kindA then
			for _, b in ipairs(Clearance.Near(grid, a.shape, gap, kindB)) do
				if b ~= a and (not same or order[a] < order[b]) and not (ignore and ignore(a, b)) then
					table.insert(out, { a = a, b = b, gap = Clearance.Distance(a.shape, b.shape) })
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------

-- A generator's footprints: name -> function(grid) adding its entries.
Clearance.Sources = {} :: { [string]: (grid: Grid) -> () }

function Clearance.Register(name: string, fill: (grid: Grid) -> ())
	Clearance.Sources[name] = fill
end

function Clearance.Build(): Grid
	local grid = Clearance.NewGrid()
	local names: { string } = {}
	for name in pairs(Clearance.Sources) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		Clearance.Sources[name](grid)
	end
	return grid
end

return Clearance
