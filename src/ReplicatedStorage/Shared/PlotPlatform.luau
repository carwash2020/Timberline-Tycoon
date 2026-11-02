--!strict
-- PlotPlatform: the raised dark grey build platform every homestead stands
-- on (Connor, 7 October 2026: "normal grass with a raised dark grey platform
-- for players to build on, very slightly raised like 1 stud").
--
-- The platform is exactly the buildable area: the tier's square, plus every
-- bought 40-stud square (PlotLogic), so it grows with the plot. Plot-local
-- y = 0 is the platform's TOP. Saved layouts are in plot-local studs, so
-- they load on the platform exactly as they loaded on the old ground (the
-- plot's origin is lifted by PlotData.PlatformHeight, nothing is migrated).
--
-- Geometry, all anchored Parts (no terrain):
--   * "Pad": a slab the size of the tier. "Land": slabs for the bought
--     squares that stick out past the tier, merged into disjoint rectangles
--     so no two slabs share a face (no z-fighting). Each slab is
--     PlatformThick tall: its top is PlatformHeight above the grass and the
--     rest sinks into the ground, so a slab never shows a gap.
--   * T416: no sloped skirt. Each exposed edge is a StoneBase "Curb"
--     block whose top is flush with the pad top, CurbWidth deep, then
--     RimTreads flat TrailDirt "Rim" treads down to the grass, each tread
--     RiseStep lower than the one before. The pad stands PlatformHeight (1
--     stud, Connor's lock) over the grass, so the drop is taken in risers of
--     at most RiseStep (0.25) and nothing is a wedge. Curb and treads cover
--     the same PlatformRamp (6) studs the old ramp did, so no footprint
--     moved. A convex corner is left open, as before. MaxLip is the number
--     the spec holds under 0.25.
-- Layout is pure (testable); Build makes the Parts.

local GameConfig = require(script.Parent.GameConfig)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)
local TerrainGen = require(script.Parent.World.TerrainGen)
local Palette = require(script.Parent.Art.Palette)

local PlotPlatform = {}

PlotPlatform.Cell = 5 -- studs: every tier and square edge is a multiple of this
PlotPlatform.Inset = 0.05 -- a ramp's back tucks this far under its slab (no hairline gap)
PlotPlatform.CurbWidth = 0.75 -- studs: the stone curb along the pad's edge, its top flush with the pad top
PlotPlatform.RimTreads = 3 -- flat dirt treads between the curb and the grass
PlotPlatform.Sink = 0.3 -- studs: every curb and tread block reaches this far below the grass, so no gap shows

export type Rect = { x0: number, x1: number, z0: number, z1: number }
-- A ramp along one exposed edge. (dx, dz) is the way down (outward). The
-- edge runs from `from` to `to` along the other axis, at `at` on the axis it
-- faces (z when dz ~= 0, x when dx ~= 0).
export type Ramp = { dx: number, dz: number, at: number, from: number, to: number }
export type Layout = {
	tier: Rect,
	land: { Rect }, -- bought squares past the tier, as disjoint rectangles
	ramps: { Ramp },
	extent: number, -- the platform's width counting every square (PlotLogic.Extent)
}

local CELL = PlotPlatform.Cell
-- Cells run from LO to HI on both axes: the whole 5x5 grid and one spare
-- cell either side.
local GRID = math.floor((PlotLogic.GridHalf() + 0.5) * GameConfig.PlotSquare / CELL + 0.5)
local LO, HI = -GRID - 1, GRID

-- Disjoint rectangles covering exactly the cells `cell` says are set.
local function mergeCells(cell: (number, number) -> boolean): { Rect }
	local rects: { Rect } = {}
	local open: { [string]: Rect } = {} -- rects that ended on the previous z row, by their x run
	for j = LO, HI do
		local nextOpen: { [string]: Rect } = {}
		local i = LO
		while i <= HI do
			if cell(i, j) then
				local i0 = i
				while i + 1 <= HI and cell(i + 1, j) do
					i += 1
				end
				local key = i0 .. ":" .. i
				local rect: Rect? = open[key]
				if rect then
					rect.z1 = (j + 1) * CELL
				else
					local fresh: Rect = { x0 = i0 * CELL, x1 = (i + 1) * CELL, z0 = j * CELL, z1 = (j + 1) * CELL }
					table.insert(rects, fresh)
					rect = fresh
				end
				nextOpen[key] = rect :: Rect
			end
			i += 1
		end
		open = nextOpen
	end
	return rects
end

-- The platform for a tier and the bought squares (PlotLogic keys "ix,iz").
function PlotPlatform.Layout(tierSize: number, squares: { string }?): Layout
	local half = tierSize / 2
	local owned: { Rect } = {}
	for _, key in ipairs(squares or {}) do
		local ix, iz = PlotLogic.ParseKey(key)
		if ix and iz and PlotLogic.InGrid(ix, iz) then
			local x0, x1, z0, z1 = PlotLogic.SquareBox(ix, iz)
			table.insert(owned, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
		end
	end
	local function inTier(i: number, j: number): boolean
		local cx, cz = (i + 0.5) * CELL, (j + 0.5) * CELL
		return math.abs(cx) < half and math.abs(cz) < half
	end
	local function inSquare(i: number, j: number): boolean
		local cx, cz = (i + 0.5) * CELL, (j + 0.5) * CELL
		for _, r in ipairs(owned) do
			if cx > r.x0 and cx < r.x1 and cz > r.z0 and cz < r.z1 then
				return true
			end
		end
		return false
	end
	local function covered(i: number, j: number): boolean
		return inTier(i, j) or inSquare(i, j)
	end

	local land = mergeCells(function(i, j)
		return inSquare(i, j) and not inTier(i, j)
	end)

	local ramps: { Ramp } = {}
	-- Edges facing +z / -z: runs along x, one z row at a time.
	for _, dz in ipairs({ 1, -1 }) do
		for j = LO, HI do
			local i = LO
			while i <= HI do
				if covered(i, j) and not covered(i, j + dz) then
					local i0 = i
					while i + 1 <= HI and covered(i + 1, j) and not covered(i + 1, j + dz) do
						i += 1
					end
					table.insert(ramps, {
						dx = 0,
						dz = dz,
						at = (if dz > 0 then j + 1 else j) * CELL,
						from = i0 * CELL,
						to = (i + 1) * CELL,
					})
				end
				i += 1
			end
		end
	end
	-- Edges facing +x / -x: runs along z, one x column at a time.
	for _, dx in ipairs({ 1, -1 }) do
		for i = LO, HI do
			local j = LO
			while j <= HI do
				if covered(i, j) and not covered(i + dx, j) then
					local j0 = j
					while j + 1 <= HI and covered(i, j + 1) and not covered(i + dx, j + 1) do
						j += 1
					end
					table.insert(ramps, {
						dx = dx,
						dz = 0,
						at = (if dx > 0 then i + 1 else i) * CELL,
						from = j0 * CELL,
						to = (j + 1) * CELL,
					})
				end
				j += 1
			end
		end
	end

	return {
		tier = { x0 = -half, x1 = half, z0 = -half, z1 = half },
		land = land,
		ramps = ramps,
		extent = PlotLogic.Extent(tierSize, squares or {}),
	}
end

-- The riser between the curb, each tread and the grass: PlatformHeight over RimTreads + 1 steps.
function PlotPlatform.RiseStep(): number
	return PlotData.PlatformHeight / (PlotPlatform.RimTreads + 1)
end

-- How deep (outward) each rim tread is: what the curb leaves of PlatformRamp, shared out.
function PlotPlatform.TreadWidth(): number
	return (PlotData.PlatformRamp - PlotPlatform.CurbWidth) / PlotPlatform.RimTreads
end

-- How far above the grass the platform is at plot-local (x, z): 0 off it,
-- PlatformHeight on a slab and on its curb, and one RiseStep less on each
-- rim tread out from it (the higher of two where edges cross). Pure; the specs read the walkable slope from it.
function PlotPlatform.RiseAt(layout: Layout, x: number, z: number): number
	local height = PlotData.PlatformHeight
	local function onRect(r: Rect): boolean
		return x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
	end
	if onRect(layout.tier) then
		return height
	end
	for _, r in ipairs(layout.land) do
		if onRect(r) then
			return height
		end
	end
	local best = 0
	local run = PlotData.PlatformRamp
	local step = PlotPlatform.RiseStep()
	local tread = PlotPlatform.TreadWidth()
	for _, ramp in ipairs(layout.ramps) do
		local along, depth
		if ramp.dz ~= 0 then
			along, depth = x, (z - ramp.at) * ramp.dz
		else
			along, depth = z, (x - ramp.at) * ramp.dx
		end
		if along >= ramp.from and along <= ramp.to and depth >= 0 and depth <= run then
			local k = if depth < PlotPlatform.CurbWidth
				then 0
				else math.min(math.floor((depth - PlotPlatform.CurbWidth) / tread) + 1, PlotPlatform.RimTreads + 1)
			best = math.max(best, height - step * k)
		end
	end
	return best
end

-- The plot's origin: centre of homestead `index`, at the platform TOP (the
-- terrain's height under the pad plus PlatformHeight). Server and clients
-- both use it, so a ghost, a wire or a hammer aims at the place the server
-- builds. (The client used y = 0 before, which is only right on a plot whose
-- ground happens to be level with the origin: most are not, Orchard Edge
-- sits 7 studs up.)
function PlotPlatform.Origin(index: number): CFrame?
	local center = PlotData.Slots[index]
	if not center then
		return nil
	end
	return CFrame.new(center.X, TerrainGen.HeightAt(center.X, center.Y) + PlotData.PlatformHeight, center.Y)
end

local function setSlab(p: Part, rect: Rect, origin: CFrame, color: Color3)
	local thick = PlotData.PlatformThick
	p.Size = Vector3.new(rect.x1 - rect.x0, thick, rect.z1 - rect.z0)
	p.CFrame = origin * CFrame.new((rect.x0 + rect.x1) / 2, -thick / 2, (rect.z0 + rect.z1) / 2)
	p.Color = color
end

local function slab(name: string, rect: Rect, origin: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	setSlab(p, rect, origin, color)
	p.Material = Enum.Material.Concrete
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function topColor(look: PlotData.Look): Color3
	return Color3.fromRGB(look.top[1], look.top[2], look.top[3])
end

-- A new "Pad" slab for the tier's square (not parented: the plot model owns
-- it and makes it the PrimaryPart).
function PlotPlatform.NewPad(layout: Layout, origin: CFrame, look: PlotData.Look): Part
	return slab("Pad", layout.tier, origin, topColor(look))
end

-- Refits an existing Pad to a new layout (the tier grew) and look.
function PlotPlatform.FitPad(pad: Part, layout: Layout, origin: CFrame, look: PlotData.Look)
	setSlab(pad, layout.tier, origin, topColor(look))
end

-- One flat block along an exposed edge, from `d0` to `d1` studs out of the slab's edge, its top `top`
-- (plot-local, the pad top is 0) and its bottom Sink under the grass.
local function band(
	r: Ramp,
	origin: CFrame,
	name: string,
	d0: number,
	d1: number,
	top: number,
	color: Color3,
	material: Enum.Material,
	height: number?
): Part
	local bottom = if height then top - height else -PlotData.PlatformHeight - PlotPlatform.Sink
	local thick = top - bottom
	local mid = (r.from + r.to) / 2
	local out = (d0 + d1) / 2
	local x, z
	local size
	if r.dz ~= 0 then
		x, z = mid, r.at + r.dz * out
		size = Vector3.new(r.to - r.from, thick, d1 - d0)
	else
		x, z = r.at + r.dx * out, mid
		size = Vector3.new(d1 - d0, thick, r.to - r.from)
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = origin * CFrame.new(x, top - thick / 2, z)
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- The most any one riser on the pad edge stands: curb to tread, tread to tread, last tread to grass.
-- Pure, for the spec.
function PlotPlatform.MaxLip(): number
	return PlotPlatform.RiseStep()
end

local function curb(r: Ramp, origin: CFrame): Part
	-- one StoneBase Slate riser, RiseStep tall, standing on the first rim tread
	return band(
		r,
		origin,
		"Curb",
		0,
		PlotPlatform.CurbWidth,
		0,
		Palette.StoneBase,
		Enum.Material.Slate,
		PlotPlatform.RiseStep()
	)
end

local function rims(r: Ramp, origin: CFrame): { Part }
	local out: { Part } = {}
	local tread = PlotPlatform.TreadWidth()
	local step = PlotPlatform.RiseStep()
	for k = 1, PlotPlatform.RimTreads do
		-- (the first tread also runs under the curb, which stands on it)
		local d0 = if k == 1 then 0 else PlotPlatform.CurbWidth + (k - 1) * tread
		local d1 = PlotPlatform.CurbWidth + k * tread
		table.insert(out, band(r, origin, "Rim", d0, d1, -step * k, Palette.TrailDirt, Enum.Material.Ground))
	end
	return out
end

-- The "Land" slabs, the curbs and the rim treads for `layout` (everything but the Pad), parented to
-- `parent`.
function PlotPlatform.BuildEdges(
	parent: Instance,
	layout: Layout,
	origin: CFrame,
	look: PlotData.Look
): ({ Part }, { Part }, { Part })
	local top = topColor(look)
	local lands: { Part } = {}
	for _, rect in ipairs(layout.land) do
		local p = slab("Land", rect, origin, top)
		p.Parent = parent
		table.insert(lands, p)
	end
	local curbs: { Part } = {}
	local treads: { Part } = {}
	for _, r in ipairs(layout.ramps) do
		local c = curb(r, origin)
		c.Parent = parent
		table.insert(curbs, c)
		for _, p in ipairs(rims(r, origin)) do
			p.Parent = parent
			table.insert(treads, p)
		end
	end
	return lands, curbs, treads
end

-- All of it into `parent` at `origin` (the platform's top centre), for the
-- previews and specs: the Pad, the Land slabs, the curbs and the rim treads.
function PlotPlatform.Build(
	parent: Instance,
	layout: Layout,
	origin: CFrame,
	look: PlotData.Look
): (Part, { Part }, { Part }, { Part })
	local pad = PlotPlatform.NewPad(layout, origin, look)
	pad.Parent = parent
	local lands, curbs, treads = PlotPlatform.BuildEdges(parent, layout, origin, look)
	return pad, lands, curbs, treads
end

return PlotPlatform
