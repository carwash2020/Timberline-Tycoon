--!strict
-- TownGround (T402): the town's roads, curbs, footpaths and lines as parts,
-- and the plots' lawn-edge borders. Terrain voxels are 4 studs and blend, so
-- a painted road edge can never be crisp; a part's edge is. Pure: it
-- computes piece specs from WorldLayout and TerrainGen.HeightAt, and
-- Art/TownGroundArt turns them into parts (so a spec can read the same
-- pieces without a Roblox place).
--
-- What is a part (inside WorldLayout.TownZone):
--   * Roads: MainStreet (the plaza's cobbles cut it in two), the East Link
--     and South Link stretches, the three 16-22 stud lanes (Forest Path,
--     Mill Road, Lot Loop), the yards (the sawmill apron, the sell yard, the
--     three mouths) and the parking lot's pavement. Asphalt #55585A, 0.2
--     thick, the top 0.05 over the graded ground, one part per straight run
--     of at most 64 studs (the lot's slab and the yards are one part wide
--     and long, split only past 64 studs across). A bend of a lane gets a
--     disc (one part) over its outer corner, where two straight runs leave
--     a gap.
--   * Curbs: CurbConcrete #9A968C, 0.3 wide and 0.15 tall, on both edges of
--     the straight main roads (MainStreet, East Link, South Link). The lanes
--     and yards have none: a 16 stud lane cannot leave a 20 stud gap, and a
--     lane or yard a truck turns in needs none. Wherever another road, yard,
--     path, the plaza or the lot meets a curbed edge the curb stops, and a
--     gap shorter than 20 studs where a vehicle can enter is widened to 20.
--   * The lot's edge: a 0.5 wide, 0.4 tall CurbConcrete curb on the lot's
--     perimeter except across every bay's mouth and wherever a road meets
--     it (gaps widened to 20 the same way), grass right up to it.
--   * Footpaths: TrailDirt #8E6C4A, Material Ground, 6 wide, 0.1 proud, no
--     curb.
--   * Line paint #E8E2D0, 0.3 wide: a centre line down the main roads, cut
--     where anything crosses.
--   * Plot borders: a 1 wide Grass strip (#5A8A3C) round each homestead pad,
--     flush (0.05 proud), broken by a 24 stud driveway gap where the pad's
--     lane meets it.
-- The terrain under every road part is Grass (TerrainGen paints no Asphalt
-- in the zone). Country roads stay terrain.

local PlotData = require(script.Parent.Parent.PlotData)
local TerrainGen = require(script.Parent.TerrainGen)
local WorldLayout = require(script.Parent.WorldLayout)

local TownGround = {}

TownGround.RoadColor = Color3.fromRGB(85, 88, 90) -- #55585A
TownGround.CurbColor = Color3.fromRGB(154, 150, 140) -- #9A968C (CurbConcrete)
TownGround.PathColor = Color3.fromRGB(142, 108, 74) -- #8E6C4A (TrailDirt)
TownGround.LineColor = Color3.fromRGB(232, 226, 208) -- #E8E2D0
TownGround.EdgeColor = Color3.fromRGB(90, 138, 60) -- #5A8A3C (the lawn's edge)

TownGround.RoadThick = 0.2
TownGround.RoadProud = 0.05 -- a road's top over the graded ground
TownGround.CurbWidth = 0.3
TownGround.CurbHeight = 0.15 -- over the road
TownGround.LotCurbWidth = 0.5
TownGround.LotCurbHeight = 0.4
TownGround.PathWidth = 6
TownGround.PathProud = 0.1
TownGround.LineWidth = 0.3
TownGround.EdgeWidth = 1
TownGround.EdgeProud = 0.05
TownGround.MaxRun = 64 -- studs: the longest straight run of one road part
TownGround.MinGap = 20 -- studs: the narrowest curb gap where a vehicle can enter
TownGround.PlotGap = 24 -- the driveway gap in a plot border (a lane is 22)
TownGround.Fit = 0.025 -- studs a road part's top may stray from the ground along a run (two touching parts then differ by at most 0.05)
TownGround.PlotFit = 0.1 -- ... and a plot's lawn edge's (nothing touches it)
TownGround.Budget = 150 -- parts: the most this adds

export type Piece = {
	name: string,
	kind: string, -- Road | Yard | Curb | LotCurb | Path | Line | PlotEdge
	group: string, -- the Model a part goes in (one per material)
	material: string, -- an Enum.Material name
	color: Color3,
	shape: string, -- Block (a Cylinder, a flat disc with a = b its centre, is supported by the builder but unused)
	a: Vector2, -- (x, z) at one end of the run's centre line
	b: Vector2,
	width: number, -- across the run (a disc's diameter)
	thick: number,
	ya: number, -- the top surface's y at a
	yb: number, -- ... and at b
	collide: boolean,
}

-- A gap in a curb or border: somewhere a vehicle (or walker) may cross it.
export type Gap = {
	name: string,
	centre: Vector2, -- on the curb's line
	normal: Vector2, -- the way in: from outside the road/lot/pad toward its inside
	width: number,
	vehicle: boolean,
}

type Shape = {
	kind: string, -- strip | disc | rect
	owner: string,
	path: boolean, -- a footpath (a walker's gap, not a vehicle's)
	ax: number,
	az: number,
	bx: number,
	bz: number,
	hw: number, -- half width (a disc's radius)
}

local function ground(x: number, z: number): number
	return TerrainGen.HeightAt(x, z)
end

local function inside(s: Shape, x: number, z: number, grow: number): boolean
	if s.kind == "rect" then
		return x >= s.ax - grow and x <= s.bx + grow and z >= s.az - grow and z <= s.bz + grow
	elseif s.kind == "disc" then
		local dx, dz = x - s.ax, z - s.az
		return dx * dx + dz * dz <= (s.hw + grow) ^ 2
	end
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-9 then
		return false
	end
	local ux, uz = dx / len, dz / len
	local px, pz = x - s.ax, z - s.az
	local along = px * ux + pz * uz
	local across = math.abs(px * -uz + pz * ux)
	return along >= -grow and along <= len + grow and across <= s.hw + grow
end

-- A rectangle as a strip whose run is along its shorter side (so it is one
-- part unless that side passes `maxRun`; the part is as wide as the longer).
local function rectStrip(x0: number, x1: number, z0: number, z1: number): (Vector2, Vector2, number)
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	if d <= w then
		return Vector2.new(cx, z0), Vector2.new(cx, z1), w -- run along z
	end
	return Vector2.new(x0, cz), Vector2.new(x1, cz), d -- run along x
end

-- Splits the line a -> b into runs of at most maxRun studs whose top
-- (ground + offset) a straight part follows to within TownGround.Fit.
type Run = { a: Vector2, b: Vector2, ya: number, yb: number }
local function fitRuns(a: Vector2, b: Vector2, offset: number, maxRun: number, step: number?, fit: number?): { Run }
	local total = (b - a).Magnitude
	if total < 1e-6 then
		return {}
	end
	-- Equal chunks no longer than maxRun (so no 2 stud stub is left over)...
	local chunks = math.max(1, math.ceil(total / maxRun - 1e-9))
	local runs: { Run } = {}
	for c = 1, chunks do
		local ca, cb = a:Lerp(b, (c - 1) / chunks), a:Lerp(b, c / chunks)
		local len = (cb - ca).Magnitude
		local n = math.max(1, math.ceil(len / (step or 2)))
		local ys: { number } = table.create(n + 1)
		for i = 0, n do
			local p = ca:Lerp(cb, i / n)
			ys[i + 1] = ground(p.X, p.Y) + offset
		end
		-- ...each cut further where a straight part would stray from the ground.
		local i = 0
		while i < n do
			local j = i + 1
			while j < n do
				local k = j + 1
				local ok = true
				for m = i + 1, k - 1 do
					local lin = ys[i + 1] + (ys[k + 1] - ys[i + 1]) * (m - i) / (k - i)
					if math.abs(ys[m + 1] - lin) > (fit or TownGround.Fit) then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				j = k
			end
			table.insert(runs, { a = ca:Lerp(cb, i / n), b = ca:Lerp(cb, j / n), ya = ys[i + 1], yb = ys[j + 1] })
			i = j
		end
	end
	return runs
end

-- The part of the segment a -> b inside the town zone (Liang-Barsky), or nil.
local function clipToZone(a: Vector2, b: Vector2): (Vector2?, Vector2?)
	local z = WorldLayout.TownZone
	local t0, t1 = 0, 1
	local dx, dz = b.X - a.X, b.Y - a.Y
	local function clip(p: number, q: number): boolean
		if p == 0 then
			return q >= 0
		end
		local r = q / p
		if p < 0 then
			if r > t1 then
				return false
			end
			t0 = math.max(t0, r)
		else
			if r < t0 then
				return false
			end
			t1 = math.min(t1, r)
		end
		return true
	end
	if clip(-dx, a.X - z.x0) and clip(dx, z.x1 - a.X) and clip(-dz, a.Y - z.z0) and clip(dz, z.z1 - a.Y) then
		if t1 - t0 < 1e-6 then
			return nil, nil
		end
		return Vector2.new(a.X + dx * t0, a.Y + dz * t0), Vector2.new(a.X + dx * t1, a.Y + dz * t1)
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- The network
---------------------------------------------------------------------------

type RoadDef = {
	name: string,
	class: string, -- Road (straight, curbed, lined) | Lane | Yard | Lot
	a: Vector2,
	b: Vector2,
	width: number,
}

local function paintNamed(name: string): WorldLayout.Paint?
	for _, p in ipairs(WorldLayout.TownPaint) do
		if p.name == name then
			return p
		end
	end
	return nil, nil
end

local function paintsNamed(name: string): { WorldLayout.Paint }
	local out: { WorldLayout.Paint } = {}
	for _, p in ipairs(WorldLayout.TownPaint) do
		if p.name == name then
			table.insert(out, p)
		end
	end
	return out
end

local YARDS = { "ForestMouth", "HillsMouth", "PlazaEastMouth", "MillYard" }
local PATHS = { "SpawnWalk", "HearthAndHomePath", "ToolShedPath", "SparkworksPath" }
local LANES = { ForestPath = true, MillRoad = true, LotLoop = true }
local MAINS = { SouthLink = true, EastLink = true }

local Built: { pieces: { Piece }, gaps: { Gap }, covers: { Shape } }? = nil

local function newPiece(
	name: string,
	kind: string,
	group: string,
	material: string,
	color: Color3,
	a: Vector2,
	b: Vector2,
	width: number,
	thick: number,
	ya: number,
	yb: number,
	collide: boolean
): Piece
	return {
		name = name,
		kind = kind,
		group = group,
		material = material,
		color = color,
		shape = "Block",
		a = a,
		b = b,
		width = width,
		thick = thick,
		ya = ya,
		yb = yb,
		collide = collide,
	}
end

-- Curb/line exposure along a line: which sample points are free of any
-- cover (other than `owner`'s own), in steps of 0.5 studs. Returns the
-- array of booleans (true = exposed) and, per sample, whether a vehicle
-- cover (not only a footpath) caused the cover.
local SAMPLE = 0.5
local function exposure(
	covers: { Shape },
	owner: string,
	from: Vector2,
	to: Vector2,
	testFrom: Vector2,
	testTo: Vector2
): ({ boolean }, { boolean })
	local len = (to - from).Magnitude
	local n = math.max(1, math.ceil(len / SAMPLE))
	local exposed: { boolean } = table.create(n + 1)
	local byVehicle: { boolean } = table.create(n + 1)
	for i = 0, n do
		local q = testFrom:Lerp(testTo, i / n)
		local covered, vehicle = false, false
		for _, s in ipairs(covers) do
			if s.owner ~= owner and inside(s, q.X, q.Y, 0) then
				covered = true
				if not s.path then
					vehicle = true
				end
			end
		end
		exposed[i + 1] = not covered
		byVehicle[i + 1] = vehicle
	end
	return exposed, byVehicle
end

-- Trims short exposed stubs and widens vehicle gaps to at least `minGap`
-- studs; returns the runs as { s0, s1 } in studs along the line, and the
-- interior gaps as { s0, s1, vehicle }.
type Span = { number }
local function runsAndGaps(
	exposed: { boolean },
	byVehicle: { boolean },
	length: number,
	minRun: number,
	minGap: number
): ({ Span }, { Span })
	local n = #exposed - 1
	local per = if n > 0 then length / n else 0
	local function gapsOf(): { { number } }
		local out: { { number } } = {}
		local i = 0
		while i <= n do
			if not exposed[i + 1] then
				local j = i
				while j + 1 <= n and not exposed[j + 2] do
					j += 1
				end
				if i > 0 and j < n then
					table.insert(out, { i, j })
				end
				i = j + 1
			else
				i += 1
			end
		end
		return out
	end
	local function vehicleIn(i: number, j: number): boolean
		for k = i, j do
			if byVehicle[k + 1] then
				return true
			end
		end
		return false
	end
	for _ = 1, 8 do
		local changed = false
		for _, g in ipairs(gapsOf()) do
			local i, j = g[1], g[2]
			if vehicleIn(i, j) and (j - i + 1) * per < minGap then
				local mid = (i + j) / 2
				local half = math.ceil(minGap / per / 2)
				for k = math.max(0, math.floor(mid - half)), math.min(n, math.ceil(mid + half)) do
					if exposed[k + 1] then
						exposed[k + 1] = false
						byVehicle[k + 1] = true
						changed = true
					end
				end
			end
		end
		-- Stubs under minRun studs are dropped.
		local i = 0
		while i <= n do
			if exposed[i + 1] then
				local j = i
				while j + 1 <= n and exposed[j + 2] do
					j += 1
				end
				if (j - i) * per < minRun then
					for k = i, j do
						exposed[k + 1] = false
					end
					changed = true
				end
				i = j + 1
			else
				i += 1
			end
		end
		if not changed then
			break
		end
	end
	local runs: { Span } = {}
	local i = 0
	while i <= n do
		if exposed[i + 1] then
			local j = i
			while j + 1 <= n and exposed[j + 2] do
				j += 1
			end
			table.insert(runs, { i * per, j * per })
			i = j + 1
		else
			i += 1
		end
	end
	local gaps: { Span } = {}
	for _, g in ipairs(gapsOf()) do
		table.insert(gaps, { g[1] * per, g[2] * per + per, if vehicleIn(g[1], g[2]) then 1 else 0 })
	end
	return runs, gaps
end

local function build(): { pieces: { Piece }, gaps: { Gap }, covers: { Shape } }
	local pieces: { Piece } = {}
	local gaps: { Gap } = {}
	local covers: { Shape } = {}
	local RC, CC, PC, LC, EC =
		TownGround.RoadColor, TownGround.CurbColor, TownGround.PathColor, TownGround.LineColor, TownGround.EdgeColor
	local zone = WorldLayout.TownZone

	local plaza = paintNamed("Plaza")
	local defs: { RoadDef } = {}

	-- MainStreet, in two: the plaza's cobbles run across it.
	local street = paintNamed("MainStreet")
	if street then
		local x0 = math.max(street.x0, zone.x0)
		local zc = (street.z0 + street.z1) / 2
		local w = street.z1 - street.z0
		local cuts: { { number } } = { { x0, street.x1 } }
		if plaza and plaza.z0 < street.z1 and plaza.z1 > street.z0 then
			cuts = { { x0, plaza.x0 }, { plaza.x1, street.x1 } }
		end
		for i, cut in ipairs(cuts) do
			table.insert(defs, {
				name = "MainStreet" .. (if #cuts > 1 then (if i == 1 then " west" else " east") else ""),
				class = "Road",
				a = Vector2.new(cut[1], zc),
				b = Vector2.new(cut[2], zc),
				width = w,
			})
		end
	end
	-- The country roads' stretches inside the zone. A bend: both runs reach
	-- past the corner by half the width times tan(half the turn), which
	-- fills the outer corner to a mitre (see the header).
	for _, road in ipairs(WorldLayout.Roads) do
		local class = if MAINS[road.name] then "Road" elseif LANES[road.name] then "Lane" else nil
		if class then
			local prev: RoadDef? = nil
			for i = 1, #road.points - 1 do
				local sa, sb = clipToZone(road.points[i], road.points[i + 1])
				if sa and sb and (sb - sa).Magnitude >= 3 then
					-- The slab stays on the plan bed. The drive width is wider,
					-- and a slab that wide leaves the flat grade.
					local bed = WorldLayout.PlanWidth(road)
					local def: RoadDef = { name = road.name, class = class, a = sa, b = sb, width = bed }
					if prev and (prev.b - sa).Magnitude < 0.01 then
						local d1, d2 = (prev.b - prev.a).Unit, (sb - sa).Unit
						local cosTurn = math.clamp(d1:Dot(d2), -1, 1)
						if cosTurn < 0.9995 then
							local reach = bed / 2 * math.tan(math.acos(cosTurn) / 2)
							prev.b = prev.b + d1 * reach
							def.a = sa - d2 * reach
						end
					end
					table.insert(defs, def)
					prev = def
				end
			end
		end
	end
	-- Yards: the sawmill apron, the sell yard, the mouths.
	local yardRects: { { name: string, x0: number, x1: number, z0: number, z1: number } } = {}
	for _, name in ipairs(YARDS) do
		for _, p in ipairs(paintsNamed(name)) do
			local z0 = p.z0
			-- The plaza's cobbles are painted first: the yard starts where they end.
			if plaza and p.x1 > plaza.x0 and p.x0 < plaza.x1 and z0 < plaza.z1 and p.z1 > plaza.z0 then
				z0 = math.max(z0, plaza.z1)
			end
			table.insert(yardRects, { name = name, x0 = math.max(p.x0, zone.x0), x1 = p.x1, z0 = z0, z1 = p.z1 })
		end
	end
	for _, floor in ipairs(WorldLayout.TownFloors) do
		if floor.name == "SellStationFloor" then
			table.insert(yardRects, { name = "SellYard", x0 = floor.x0, x1 = floor.x1, z0 = floor.z0, z1 = floor.z1 })
		end
	end
	for _, y in ipairs(yardRects) do
		local a, b, w = rectStrip(y.x0, y.x1, y.z0, y.z1)
		table.insert(defs, { name = y.name, class = "Yard", a = a, b = b, width = w })
	end
	-- The parking lot's pavement. Its north-west corner overlaps the plaza's
	-- cobbles (x up to 26, z from 64): the slab stops at z 64 there and carries on
	-- east of the cobbles, so no asphalt lies on the square.
	do
		local lot = WorldLayout.ParkingLot
		local rects: { { x0: number, x1: number, z0: number, z1: number } } = { lot }
		if plaza and lot.x0 < plaza.x1 and lot.z1 > plaza.z0 and lot.z0 < plaza.z1 and lot.x1 > plaza.x0 then
			rects = {
				{ x0 = lot.x0, x1 = lot.x1, z0 = lot.z0, z1 = plaza.z0 },
				{ x0 = plaza.x1 + 2, x1 = lot.x1, z0 = plaza.z0, z1 = lot.z1 },
			}
		end
		for _, r in ipairs(rects) do
			local a, b, w = rectStrip(r.x0, r.x1, r.z0, r.z1)
			local pieceCount = math.ceil((b - a).Magnitude / TownGround.MaxRun)
			for i = 1, pieceCount do
				table.insert(defs, {
					name = "Lot",
					class = "Lot",
					a = a:Lerp(b, (i - 1) / pieceCount),
					b = a:Lerp(b, i / pieceCount),
					width = w,
				})
			end
		end
	end

	-- Covers: every road, yard, the plaza and the lot, each as the exact shape the part will be.
	local function addStrip(owner: string, a: Vector2, b: Vector2, width: number, path: boolean)
		table.insert(
			covers,
			{ kind = "strip", owner = owner, path = path, ax = a.X, az = a.Y, bx = b.X, bz = b.Y, hw = width / 2 }
		)
	end
	for _, d in ipairs(defs) do
		addStrip(d.name, d.a, d.b, d.width, false)
	end
	if plaza then
		table.insert(covers, {
			kind = "rect",
			owner = "Plaza",
			path = false,
			ax = plaza.x0,
			az = plaza.z0,
			bx = plaza.x1,
			bz = plaza.z1,
			hw = 0,
		})
	end

	-- Footpaths (the 6 wide TrailDirt strips), trimmed back to the road they meet.
	local pathDefs: { RoadDef } = {}
	for _, name in ipairs(PATHS) do
		for _, p in ipairs(paintsNamed(name)) do
			if p.x1 > zone.x0 and p.x0 < zone.x1 and p.z1 > zone.z0 and p.z0 < zone.z1 then
				local w, d = p.x1 - p.x0, p.z1 - p.z0
				local a, b
				if d >= w then
					a, b = Vector2.new((p.x0 + p.x1) / 2, p.z0), Vector2.new((p.x0 + p.x1) / 2, p.z1)
				else
					a, b = Vector2.new(p.x0, (p.z0 + p.z1) / 2), Vector2.new(p.x1, (p.z0 + p.z1) / 2)
				end
				local dir = (b - a).Unit
				local len = (b - a).Magnitude
				local function coveredAt(pt: Vector2): boolean
					for _, s in ipairs(covers) do
						if not s.path and inside(s, pt.X, pt.Y, -0.01) then
							return true
						end
					end
					return false
				end
				local t0, t1 = 0, len
				while t0 < t1 and coveredAt(a + dir * (t0 + 0.01)) do
					t0 += 0.5
				end
				while t1 > t0 and coveredAt(a + dir * (t1 - 0.01)) do
					t1 -= 0.5
				end
				if t1 - t0 >= 3 then
					table.insert(pathDefs, {
						name = name,
						class = "Path",
						a = a + dir * t0,
						b = a + dir * t1,
						width = TownGround.PathWidth,
					})
				end
			end
		end
	end
	for _, d in ipairs(pathDefs) do
		addStrip(d.name, d.a, d.b, d.width, true)
	end

	-- Roads, yards and the lot's pavement.
	local proud = TownGround.RoadProud
	for _, d in ipairs(defs) do
		for _, run in ipairs(fitRuns(d.a, d.b, proud, TownGround.MaxRun)) do
			table.insert(
				pieces,
				newPiece(
					d.name,
					if d.class == "Yard" or d.class == "Lot" then "Yard" else "Road",
					"TownRoads",
					"Asphalt",
					RC,
					run.a,
					run.b,
					d.width,
					TownGround.RoadThick,
					run.ya,
					run.yb,
					true
				)
			)
		end
	end

	-- Curbs and lines along the straight main roads.
	local halfCurb = TownGround.CurbWidth / 2
	for _, d in ipairs(defs) do
		if d.class == "Road" then
			local dir = (d.b - d.a).Unit
			local normal = Vector2.new(-dir.Y, dir.X)
			local len = (d.b - d.a).Magnitude
			for _, side in ipairs({ 1, -1 }) do
				local off = d.width / 2 - halfCurb
				local from, to = d.a + normal * (side * off), d.b + normal * (side * off)
				local testOff = d.width / 2 + 1
				local exposed, byVehicle =
					exposure(covers, d.name, from, to, d.a + normal * (side * testOff), d.b + normal * (side * testOff))
				local runs, gapSpans = runsAndGaps(exposed, byVehicle, len, 3, TownGround.MinGap)
				for _, r in ipairs(runs) do
					for _, run in
						ipairs(
							fitRuns(
								from + dir * r[1],
								from + dir * r[2],
								proud + TownGround.CurbHeight,
								TownGround.MaxRun
							)
						)
					do
						table.insert(
							pieces,
							newPiece(
								d.name .. " curb",
								"Curb",
								"TownCurbs",
								"Concrete",
								CC,
								run.a,
								run.b,
								TownGround.CurbWidth,
								TownGround.CurbHeight,
								run.ya,
								run.yb,
								true
							)
						)
					end
				end
				for _, g in ipairs(gapSpans) do
					local mid = (g[1] + g[2]) / 2
					table.insert(gaps, {
						name = d.name .. " curb, " .. (if side > 0 then "left" else "right"),
						centre = from + dir * mid,
						normal = normal * -side,
						width = g[2] - g[1],
						vehicle = g[3] == 1,
					})
				end
			end
			-- The centre line (MainStreet's; the East and South Link stretches are too short to need one).
			if string.find(d.name, "MainStreet", 1, true) then
				local exposed, byVehicle = exposure(covers, d.name, d.a, d.b, d.a, d.b)
				-- Keep a stud clear of whatever crosses it.
				local runs = runsAndGaps(exposed, byVehicle, len, 6, 0)
				for _, r in ipairs(runs) do
					local ra, rb = d.a + dir * (r[1] + 1), d.a + dir * (r[2] - 1)
					if (rb - ra).Magnitude >= 4 then
						for _, run in ipairs(fitRuns(ra, rb, proud + 0.02, TownGround.MaxRun)) do
							table.insert(
								pieces,
								newPiece(
									d.name .. " line",
									"Line",
									"TownLines",
									"SmoothPlastic",
									LC,
									run.a,
									run.b,
									TownGround.LineWidth,
									0.02,
									run.ya,
									run.yb,
									false
								)
							)
						end
					end
				end
			end
		end
	end

	-- Footpaths.
	for _, d in ipairs(pathDefs) do
		for _, run in ipairs(fitRuns(d.a, d.b, TownGround.PathProud, TownGround.MaxRun)) do
			table.insert(
				pieces,
				newPiece(d.name, "Path", "TownPaths", "Ground", PC, run.a, run.b, d.width, 0.2, run.ya, run.yb, true)
			)
		end
	end

	-- The lot's edge.
	do
		local lot = WorldLayout.ParkingLot
		local inset = TownGround.LotCurbWidth / 2
		-- Every bay's footprint, grown 3 studs past both ends, is a mouth: no
		-- curb across it (a bay's head and tail are where a rig drives in or out).
		local WorldPlan = require(script.Parent.WorldPlan)
		local town = WorldPlan.Town()
		local lotCovers: { Shape } = table.clone(covers)
		for i, cf in ipairs(town.parkingSlots) do
			local size = town.parkingSizes[i] or WorldPlan.ParkingSlotSize
			local p = cf.Position
			table.insert(lotCovers, {
				kind = "rect",
				owner = "Bay",
				path = false,
				ax = p.X - size.X / 2,
				az = p.Z - size.Z / 2 - 3,
				bx = p.X + size.X / 2,
				bz = p.Z + size.Z / 2 + 3,
				hw = 0,
			})
		end
		local sides = {
			{
				name = "south",
				a = Vector2.new(lot.x0, lot.z0),
				b = Vector2.new(lot.x1, lot.z0),
				out = Vector2.new(0, -1),
			},
			{
				name = "east",
				a = Vector2.new(lot.x1, lot.z0),
				b = Vector2.new(lot.x1, lot.z1),
				out = Vector2.new(1, 0),
			},
			{
				name = "north",
				a = Vector2.new(lot.x1, lot.z1),
				b = Vector2.new(lot.x0, lot.z1),
				out = Vector2.new(0, 1),
			},
			{
				name = "west",
				a = Vector2.new(lot.x0, lot.z1),
				b = Vector2.new(lot.x0, lot.z0),
				out = Vector2.new(-1, 0),
			},
		}
		for _, side in ipairs(sides) do
			local dir = (side.b - side.a).Unit
			local len = (side.b - side.a).Magnitude
			local from, to = side.a - side.out * inset, side.b - side.out * inset
			local exposed, byVehicle =
				exposure(lotCovers, "Lot", from, to, side.a + side.out * 1, side.b + side.out * 1)
			local runs, gapSpans = runsAndGaps(exposed, byVehicle, len, 3, TownGround.MinGap)
			for _, r in ipairs(runs) do
				for _, run in
					ipairs(fitRuns(from + dir * r[1], from + dir * r[2], TownGround.LotCurbHeight, TownGround.MaxRun))
				do
					table.insert(
						pieces,
						newPiece(
							"Lot curb",
							"LotCurb",
							"TownCurbs",
							"Concrete",
							CC,
							run.a,
							run.b,
							TownGround.LotCurbWidth,
							TownGround.LotCurbHeight,
							run.ya,
							run.yb,
							true
						)
					)
				end
			end
			for _, g in ipairs(gapSpans) do
				table.insert(gaps, {
					name = "Lot " .. side.name .. " edge",
					centre = from + dir * ((g[1] + g[2]) / 2),
					normal = side.out * -1,
					width = g[2] - g[1],
					vehicle = g[3] == 1,
				})
			end
		end
	end

	-- Each homestead pad's 1 wide lawn edge, broken at its driveway.
	for index, slot in ipairs(PlotData.Slots) do
		local half = PlotData.Pad / 2
		local drive = WorldLayout.Drives[index]
		local e = TownGround.EdgeWidth
		local sx, sz = slot.X, slot.Y
		local sideDefs = {
			{
				a = Vector2.new(sx - half, sz + half - e / 2),
				b = Vector2.new(sx + half, sz + half - e / 2),
				out = Vector2.new(0, 1),
			},
			{
				a = Vector2.new(sx - half, sz - half + e / 2),
				b = Vector2.new(sx + half, sz - half + e / 2),
				out = Vector2.new(0, -1),
			},
			{
				a = Vector2.new(sx + half - e / 2, sz - half + e),
				b = Vector2.new(sx + half - e / 2, sz + half - e),
				out = Vector2.new(1, 0),
			},
			{
				a = Vector2.new(sx - half + e / 2, sz - half + e),
				b = Vector2.new(sx - half + e / 2, sz + half - e),
				out = Vector2.new(-1, 0),
			},
		}
		for _, side in ipairs(sideDefs) do
			local dir = (side.b - side.a).Unit
			local len = (side.b - side.a).Magnitude
			local spans: { Span } = { { 0, len } }
			if drive and drive.ux == side.out.X and drive.uz == side.out.Y then
				-- The lane is centred on the pad: the gap is too.
				local mid = len / 2
				local g0, g1 = mid - TownGround.PlotGap / 2, mid + TownGround.PlotGap / 2
				spans = { { 0, g0 }, { g1, len } }
				table.insert(gaps, {
					name = string.format("Plot %d driveway", index),
					centre = side.a + dir * mid,
					normal = side.out * -1,
					width = TownGround.PlotGap,
					vehicle = true,
				})
			end
			for _, span in ipairs(spans) do
				if span[2] - span[1] >= 1 then
					for _, run in
						ipairs(
							fitRuns(
								side.a + dir * span[1],
								side.a + dir * span[2],
								TownGround.EdgeProud,
								400,
								8,
								TownGround.PlotFit
							)
						)
					do
						-- Only along the pad's own flat shelf: where a hill climbs over the edge there is no lawn edge to draw.
						if math.max(run.ya, run.yb) > TownGround.EdgeProud + 0.25 then
							continue
						end
						table.insert(
							pieces,
							newPiece(
								string.format("Plot %d edge", index),
								"PlotEdge",
								"PlotEdges",
								"Grass",
								EC,
								run.a,
								run.b,
								e,
								0.1,
								run.ya,
								run.yb,
								false
							)
						)
					end
				end
			end
		end
	end
	return { pieces = pieces, gaps = gaps, covers = covers }
end

local function built()
	if not Built then
		Built = build()
	end
	return Built :: { pieces: { Piece }, gaps: { Gap }, covers: { Shape } }
end

-- Every piece, in building order. Cached.
function TownGround.Pieces(): { Piece }
	return built().pieces
end

TownGround._covers = function(): { Shape }
	return built().covers
end

-- Every curb or border gap, with the way in.
function TownGround.Gaps(): { Gap }
	return built().gaps
end

-- The top of the road part (Road, Yard) over (x, z), or nil.
function TownGround.RoadTopAt(x: number, z: number): number?
	local best: number? = nil
	for _, p in ipairs(built().pieces) do
		if p.kind == "Road" or p.kind == "Yard" then
			local top = TownGround.TopAt(p, x, z)
			if top and (best == nil or top > best) then
				best = top
			end
		end
	end
	return best
end

-- The top of one piece over (x, z) (its run's slope followed), or nil off it.
function TownGround.TopAt(p: Piece, x: number, z: number): number?
	if p.shape == "Cylinder" then
		local dx, dz = x - p.a.X, z - p.a.Y
		if dx * dx + dz * dz <= (p.width / 2) ^ 2 then
			return p.ya
		end
		return nil
	end
	local d = p.b - p.a
	local len = d.Magnitude
	if len < 1e-9 then
		return nil
	end
	local ux, uz = d.X / len, d.Y / len
	local px, pz = x - p.a.X, z - p.a.Y
	local along = px * ux + pz * uz
	local across = math.abs(px * -uz + pz * ux)
	if along < 0 or along > len or across > p.width / 2 then
		return nil
	end
	return p.ya + (p.yb - p.ya) * along / len
end

-- Whether (x, z) is on a road, yard, bend, path, curb... piece of `kinds`
-- (a set), with `grow` studs of slack.
function TownGround.Covers(x: number, z: number, kinds: { [string]: boolean }, grow: number?): boolean
	for _, p in ipairs(built().pieces) do
		if kinds[p.kind] then
			if p.shape == "Cylinder" then
				local dx, dz = x - p.a.X, z - p.a.Y
				if dx * dx + dz * dz <= (p.width / 2 + (grow or 0)) ^ 2 then
					return true
				end
			else
				local d = p.b - p.a
				local len = d.Magnitude
				local ux, uz = d.X / len, d.Y / len
				local px, pz = x - p.a.X, z - p.a.Y
				local along = px * ux + pz * uz
				local across = math.abs(px * -uz + pz * ux)
				if along >= -(grow or 0) and along <= len + (grow or 0) and across <= p.width / 2 + (grow or 0) then
					return true
				end
			end
		end
	end
	return false
end

-- The pieces' bounding area inside the town zone: how many parts the town
-- zone has, and how many the plots' borders have (all counted in Budget).
function TownGround.Counts(): (number, number)
	local zoneCount, plotCount = 0, 0
	for _, p in ipairs(built().pieces) do
		if p.kind == "PlotEdge" then
			plotCount += 1
		else
			zoneCount += 1
		end
	end
	return zoneCount, plotCount
end

return TownGround
