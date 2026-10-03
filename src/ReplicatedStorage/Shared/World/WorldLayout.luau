--!strict
-- WorldLayout: where things are in the 3,000-stud world (GAME_DESIGN §10),
-- shared by the terrain generator (TerrainGen), MapBuilder, the ambient
-- life on clients and the preview tool. Biome centres and radii stay in
-- BiomeData (the economy model reads their haul distances); this adds the
-- shapes between them: flat building zones, roads, the river and lake,
-- the coast, and the mountains that frame the map.
--
-- Axes: +X is east, +Z is north. The sawmill hub is at (0, 110).

local BiomeData = require(script.Parent.Parent.BiomeData)
local PlotData = require(script.Parent.Parent.PlotData)

local WorldLayout = {}

-- On while the first 322 trees are placed. Their X and Z were worked out
-- against the old district; saves and planted stakes point at them.
local legacyLayout = false

function WorldLayout.SetLegacyLayout(on: boolean)
	legacyLayout = on
end

WorldLayout.WorldHalf = 1500 -- the world runs from -1500 to 1500 on both axes
WorldLayout.Sawmill = Vector3.new(0, 0, 110)
WorldLayout.SeaLevel = -3 -- ocean surface
WorldLayout.LakeLevel = -2 -- river and lake surface

-- A rectangle (x0..x1, z0..z1) the terrain keeps perfectly flat, blending
-- back to the countryside over `blend` studs. Town pads sit at y = 0.
-- A homestead with `terrace` sits at the broad height of its centre
-- (TerrainGen fills in `y`) so a pad in the hills is a shelf, not a pit.
export type FlatZone = {
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	blend: number,
	terrace: boolean?,
	y: number?,
	cx: number?,
	cz: number?,
}

-- A road: a dirt track along these points, `width` studs wide; the terrain
-- under it is smoothed so trucks have an easy ride.
export type Road = { name: string, points: { Vector2 }, width: number }

-- The 4×3 district those first trees were placed around (spacing 220, the
-- road at z = 50). Widths are the pre-phase-12 ones. The live homesteads
-- are scattered; this lawn exists only while those 322 trees are placed.
WorldLayout.LegacyPlots = { name = "Plots", x0 = 126, x1 = 1034, z0 = -624, z1 = 74, blend = 50 } :: FlatZone
WorldLayout.LegacyPlotRoads = {
	{ name = "PlotRoad", points = { Vector2.new(118, 50), Vector2.new(1010, 50) }, width = 10 },
	{ name = "PlotLane", points = { Vector2.new(360, 50), Vector2.new(360, -600) }, width = 8 },
	{ name = "PlotLane", points = { Vector2.new(580, 50), Vector2.new(580, -600) }, width = 8 },
	{ name = "PlotLane", points = { Vector2.new(800, 50), Vector2.new(800, -600) }, width = 8 },
	{ name = "PlotLane", points = { Vector2.new(150, -170), Vector2.new(1010, -170) }, width = 8 },
	{ name = "PlotLane", points = { Vector2.new(150, -390), Vector2.new(1010, -390) }, width = 8 },
} :: { Road }

-- One 200×200 shelf per homestead. The blend is at least 50 studs, so
-- the country rises back up outside the yard instead of a cliff. Not one
-- lawn: the old grid's rectangle would have flattened every region.
local function plotZones(): { FlatZone }
	local half = PlotData.Pad / 2
	local zones: { FlatZone } = {}
	for _, slot in ipairs(PlotData.Slots) do
		table.insert(zones, {
			name = "Plot",
			x0 = slot.X - half,
			x1 = slot.X + half,
			z0 = slot.Y - half,
			z1 = slot.Y + half,
			blend = PlotData.Blend,
			terrace = true,
			cx = slot.X,
			cz = slot.Y,
		})
	end
	return zones
end

WorldLayout.FlatZones = {
	-- Town: spawn, sawmill, shops, parking, gondola station. Left as the
	-- town work laid it out.
	{ name = "Town", x0 = -125, x1 = 140, z0 = -32, z1 = 205, blend = 45 },
	-- The dealership's display lot, on the lawn north of the plot road.
	-- Blend 1, so it flattens the trucks' ground and does not grow the
	-- forest hub (the hub names Town only). The homesteads are shelves,
	-- not this lawn.
	{ name = "DealershipLot", x0 = 184, x1 = 296, z0 = 64, z1 = 123, blend = 1 },
	-- The lot's east rail and the turnaround (the loop ends at x 172, z 50)
	-- used to sit on the district lawn. Keep that patch level so the town's
	-- driveway doesn't climb. It stops short of the dealership display lot
	-- and the path up to it: the blend ends before that ground. Not a homestead.
	{ name = "LotApron", x0 = 126, x1 = 178, z0 = -70, z1 = 52, blend = 12 },
} :: { FlatZone }
for _, zone in ipairs(plotZones()) do
	table.insert(WorldLayout.FlatZones, zone)
end

-- Ground the dealership job owns. The display lot is the open lawn north
-- of the old plot road. The approach is the path from the showroom (the
-- building spans x 35 to 69.5) to that lot's west side. A homestead shelf,
-- its blend, and a lane must not change either one. The town flat zone is
-- left as the town laid it out.
export type ReservedBox = { name: string, x0: number, x1: number, z0: number, z1: number }
WorldLayout.Reserved = {
	{ name = "DealershipLot", x0 = 184, x1 = 296, z0 = 64, z1 = 123 },
	{ name = "DealershipApproach", x0 = 69.5, x1 = 184, z0 = 64, z1 = 123 },
} :: { ReservedBox }

-- Distance from rectangle (x0, z0)-(x1, z1) to a reserved box. 0 when they
-- share ground.
function WorldLayout.ReservedDistance(x0: number, z0: number, x1: number, z1: number, box: ReservedBox): number
	local sepX = math.max(x0 - box.x1, box.x0 - x1)
	local sepZ = math.max(z0 - box.z1, box.z0 - z1)
	if sepX < 0 and sepZ < 0 then
		return 0
	end
	return math.sqrt(math.max(sepX, 0) ^ 2 + math.max(sepZ, 0) ^ 2)
end

-- Biome centres, for the roads below.
local function center(id: string): Vector2
	local def = BiomeData.Get(id)
	local area = if def then def.area else nil
	return if area then Vector2.new(area.x, area.z) else Vector2.zero
end

local hills, snow, volcano, sky = center("hills"), center("snow"), center("volcano"), center("sky")

WorldLayout.Roads = {
	-- Town to the Starter Forest (south, a short walk). Wide enough for the
	-- Logging Rig (phase 12).
	{ name = "ForestPath", points = { Vector2.new(0, 20), Vector2.new(-6, -30) }, width = 16 },
	-- West to the Hills, curving past Hearth & Home. A haul road: 28 studs,
	-- so two rigs can pass on a bend.
	{
		name = "HillsRoad",
		points = { Vector2.new(-20, 20), Vector2.new(-140, 40), Vector2.new(-230, 90), hills + Vector2.new(120, 0) },
		width = 28,
	},
	-- North from behind the sawmill, up onto the Snowfields plateau.
	{
		name = "SnowRoad",
		points = { Vector2.new(0, 205), Vector2.new(30, 450), Vector2.new(-20, 760), snow - Vector2.new(0, 160) },
		width = 28,
	},
	-- North-east to the Volcano, branching off the snow road.
	{
		name = "VolcanoRoad",
		points = { Vector2.new(30, 450), Vector2.new(380, 640), Vector2.new(760, 900), volcano - Vector2.new(150, 120) },
		width = 28,
	},
	-- West-north-west from the snow road to the Skyroot's foot.
	{
		name = "SkyrootRoad",
		points = { Vector2.new(-20, 760), Vector2.new(-420, 860), Vector2.new(-760, 960), sky + Vector2.new(120, -40) },
		width = 24,
	},
	-- East of the Dealership, then north to the Snow Road's start. The mill
	-- yard and the shop fill x 22 to 70, so the way stays east of them.
	{
		name = "MillRoad",
		points = {
			Vector2.new(64, 76),
			Vector2.new(102, 76),
			Vector2.new(102, 158),
			Vector2.new(48, 186),
			Vector2.new(14, 200),
			Vector2.new(0, 205),
		},
		width = 22,
	},
	-- South of the lot's pull-outs, around to the plot road, so a long rig
	-- can turn without backing the length of the lot.
	{
		name = "LotLoop",
		points = {
			Vector2.new(-6, -30),
			Vector2.new(8, -58),
			Vector2.new(160, -58),
			Vector2.new(172, -10),
			Vector2.new(172, 50),
			Vector2.new(130, 50),
		},
		width = 16,
	},
} :: { Road }

-- Flared turns where a haul road splits, wide enough for the Logging Rig.
-- Discs, not extra roads: a short segment would fail the "runs through the
-- country" sample. TerrainGen paints and grades them with the haul roads.
export type Junction = { name: string, at: Vector2, radius: number, haul: boolean }
WorldLayout.Junctions = {
	{ name = "SnowVolcano", at = Vector2.new(30, 450), radius = 32, haul = true },
	{ name = "SnowSkyroot", at = Vector2.new(-20, 760), radius = 32, haul = true },
} :: { Junction }

-- A cliff ring outside a biome's trees, with one angular gap (the road).
-- `gap` is the opening's centre angle (atan2 of z, x from the centre);
-- `half` is how far either side of it the wall stays down.
export type Rim = {
	kind: string,
	cx: number,
	cz: number,
	inner: number,
	outer: number,
	height: number,
	gap: number,
	half: number,
}
WorldLayout.Rims = {
	{
		kind = "snow",
		cx = snow.X,
		cz = snow.Y,
		inner = 246,
		outer = 316,
		height = 16,
		gap = -math.pi / 2,
		half = 0.62,
	},
	{
		kind = "volcano",
		cx = volcano.X,
		cz = volcano.Y,
		inner = 228,
		outer = 302,
		height = 24,
		gap = math.atan2(-120, -150),
		half = 0.7,
	},
} :: { Rim }

-- Where a bought truck is delivered: the centre of a clear pad on the
-- road edge of the yard, and the flat direction out to that road.
export type Drive = {
	index: number,
	x: number,
	z: number,
	ux: number,
	uz: number,
}

-- A lane from each homestead to the nearest haul road (not another lane,
-- and not a point inside town). The centreline starts just outside the
-- pad, so the lane never paves the yard. The delivery pad sits on the
-- inside of that same edge.
WorldLayout.Drives = {} :: { Drive }
do
	local town = WorldLayout.FlatZones[1]
	local half = PlotData.Pad / 2
	local mouth = half + PlotData.LaneWidth / 2 + 2
	local haul: { Road } = table.clone(WorldLayout.Roads)
	local function inTown(x: number, z: number): boolean
		return x >= town.x0 and x <= town.x1 and z >= town.z0 and z <= town.z1
	end
	local function hitsSquare(px: number, pz: number, sx: number, sz: number, reach: number): boolean
		local dx = math.max(math.abs(px - sx) - half, 0)
		local dz = math.max(math.abs(pz - sz) - half, 0)
		return dx * dx + dz * dz < reach * reach
	end
	-- A straight lane. It has to miss every yard, including its own.
	local function laneClear(ax: number, az: number, bx: number, bz: number): boolean
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local steps = math.max(1, math.ceil(len / 8))
		local reach = PlotData.LaneWidth / 2 - 0.5
		for _, other in ipairs(PlotData.Slots) do
			for s = 0, steps do
				local u = s / steps
				local x = ax + (bx - ax) * u
				local z = az + (bz - az) * u
				if hitsSquare(x, z, other.X, other.Y, reach) then
					return false
				end
				-- The lane's body, not only its centreline, stays off the
				-- dealership lot and the path from the showroom.
				local laneReach = PlotData.LaneWidth / 2
				for _, box in ipairs(WorldLayout.Reserved) do
					local dx = math.max(box.x0 - x, 0, x - box.x1)
					local dz = math.max(box.z0 - z, 0, z - box.z1)
					if dx * dx + dz * dz < laneReach * laneReach then
						return false
					end
				end
				-- The maple past the south pull-outs. A lane up to the lot
				-- loop used to pave it. The centreline stays clear of its crown.
				local treeX, treeZ, treeR = 132, -80, 28
				local tdx, tdz = x - treeX, z - treeZ
				if tdx * tdx + tdz * tdz < treeR * treeR then
					return false
				end
			end
		end
		return true
	end
	-- The delivery pad is a rectangle, so it sits on the north, south, east
	-- or west edge: the side the road is nearest. A diagonal pad would hang
	-- off the square.
	local function cardinal(dx: number, dz: number): (number, number)
		if math.abs(dx) >= math.abs(dz) then
			return if dx >= 0 then 1 else -1, 0
		end
		return 0, if dz >= 0 then 1 else -1
	end
	-- Goals sit on the haul roads, outside town. A lane may bend around
	-- yards; it still has to arrive on the road itself.
	local STEP = 16
	local goals: { Vector2 } = {}
	local goalAt: { [number]: Vector2 } = {}
	local goalDist: { [number]: number } = {}
	local function cellKey(x: number, z: number): number
		return math.floor(x / STEP) * 10000 + math.floor(z / STEP)
	end
	for _, road in ipairs(haul) do
		local pts = road.points
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			local steps = math.max(1, math.ceil(len / 12))
			for s = 0, steps do
				local p = a:Lerp(b, s / steps)
				local endX, endZ = road.points[#road.points].X, road.points[#road.points].Y
				local fromEnd = (p.X - endX) * (p.X - endX) + (p.Y - endZ) * (p.Y - endZ)
				-- The biome signs stand on the last stretch of a haul road.
				-- A lane joins further back, so it doesn't pave their posts.
				if not inTown(p.X, p.Y) and fromEnd > 90 * 90 and laneClear(p.X, p.Y, p.X, p.Y) then
					table.insert(goals, p)
					local gx, gz = math.floor(p.X / STEP), math.floor(p.Y / STEP)
					for ox = -1, 1 do
						for oz = -1, 1 do
							local key = (gx + ox) * 10000 + (gz + oz)
							local cx = (gx + ox) * STEP + STEP / 2
							local cz = (gz + oz) * STEP + STEP / 2
							local dist = (p.X - cx) * (p.X - cx) + (p.Y - cz) * (p.Y - cz)
							local prev = goalDist[key]
							if not prev or dist < prev then
								goalDist[key] = dist
								goalAt[key] = p
							end
						end
					end
				end
			end
		end
	end
	local function simplify(points: { Vector2 }): { Vector2 }
		if #points <= 2 then
			return points
		end
		local simple = { points[1] }
		for i = 2, #points - 1 do
			local a, b, c = simple[#simple], points[i], points[i + 1]
			local cross = (b.X - a.X) * (c.Y - b.Y) - (b.Y - a.Y) * (c.X - b.X)
			if math.abs(cross) > 1 then
				table.insert(simple, b)
			end
		end
		table.insert(simple, points[#points])
		return simple
	end
	-- Grid search from just outside one edge of the yard to the nearest
	-- haul road. Straight shots and single elbows miss yards that sit
	-- between a pad and the road; walking the gap does not.
	local function findPath(sx: number, sz: number, ux: number, uz: number): { Vector2 }?
		local mouthX, mouthZ = sx + ux * mouth, sz + uz * mouth
		if not laneClear(mouthX, mouthZ, mouthX, mouthZ) then
			return nil
		end
		local startKey = cellKey(mouthX, mouthZ)
		local direct = goalAt[startKey]
		if direct and laneClear(mouthX, mouthZ, direct.X, direct.Y) then
			return { Vector2.new(mouthX, mouthZ), direct }
		end
		local xs = { mouthX }
		local zs = { mouthZ }
		local parent = { 0 }
		local seen: { [number]: boolean } = { [startKey] = true }
		local head = 1
		local found: number? = nil
		local foundGoal: Vector2? = nil
		while head <= #xs and #xs < 6000 do
			local here = head
			local x, z = xs[here], zs[here]
			head += 1
			local steps = {
				{ x + STEP, z },
				{ x - STEP, z },
				{ x, z + STEP },
				{ x, z - STEP },
			}
			for _, step in ipairs(steps) do
				local nx, nz = step[1], step[2]
				if math.abs(nx) < 1500 and math.abs(nz) < 1500 and not inTown(nx, nz) then
					local key = cellKey(nx, nz)
					if not seen[key] and laneClear(x, z, nx, nz) then
						seen[key] = true
						table.insert(xs, nx)
						table.insert(zs, nz)
						table.insert(parent, here)
						local goal = goalAt[key]
						if goal and laneClear(nx, nz, goal.X, goal.Y) then
							found = #xs
							foundGoal = goal
							break
						end
					end
				end
			end
			if found then
				break
			end
		end
		if not found or not foundGoal then
			return nil
		end
		local points = { foundGoal }
		local cursor: number? = found
		while cursor and cursor > 0 do
			table.insert(points, Vector2.new(xs[cursor], zs[cursor]))
			local prev = parent[cursor]
			cursor = if prev > 0 then prev else nil
		end
		local ordered = {}
		for i = #points, 1, -1 do
			table.insert(ordered, points[i])
		end
		return simplify(ordered)
	end
	for index, slot in ipairs(PlotData.Slots) do
		local nearestGoal: Vector2? = nil
		local nearestDist = math.huge
		for _, goal in ipairs(goals) do
			local dist = (goal.X - slot.X) ^ 2 + (goal.Y - slot.Y) ^ 2
			if dist < nearestDist then
				nearestDist = dist
				nearestGoal = goal
			end
		end
		local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
		if nearestGoal then
			local preferX, preferZ = cardinal(nearestGoal.X - slot.X, nearestGoal.Y - slot.Y)
			table.sort(dirs, function(a, b)
				local ap = if a[1] == preferX and a[2] == preferZ then 0 else 1
				local bp = if b[1] == preferX and b[2] == preferZ then 0 else 1
				return ap < bp
			end)
		end
		local points: { Vector2 }? = nil
		local ux, uz = 0, 1
		for _, dir in ipairs(dirs) do
			local routed = findPath(slot.X, slot.Y, dir[1], dir[2])
			if routed then
				points = routed
				ux, uz = dir[1], dir[2]
				break
			end
		end
		if points then
			local inset = PlotData.DeliveryWidth / 2
			WorldLayout.Drives[index] = {
				index = index,
				x = slot.X + ux * (half - inset),
				z = slot.Y + uz * (half - inset),
				ux = ux,
				uz = uz,
			}
			table.insert(WorldLayout.Roads, {
				name = "PlotSpur",
				points = points,
				width = PlotData.LaneWidth,
			})
		end
	end
end

-- The delivery pad's centre, looking out along the lane. `y` is the shelf.
function WorldLayout.DeliveryCFrame(index: number, y: number): CFrame?
	local drive = WorldLayout.Drives[index]
	if not drive then
		return nil
	end
	local at = Vector3.new(drive.x, y, drive.z)
	local ahead = at + Vector3.new(drive.ux, 0, drive.uz)
	return CFrame.lookAt(at, ahead)
end

-- The parking lot east of the spawn (a gravel lot; MapBuilder paints the
-- slots on it). M1.5 grew it east (it ended at x 112) for one row of 12
-- slots 10 wide, 11 apart (WorldPlan.Town), its east rail at x 145. The
-- LotApron keeps that rail and the turnaround level.
WorldLayout.ParkingLot = { x0 = 8, x1 = 146, z0 = -18, z1 = 68 }

-- The town's ground (TerrainGen paints it): a cobbled plaza round the sell
-- pad, packed dirt for the main street, the shop paths, the spawn walk, the
-- mill yard and the gondola path. Edges get a little noise. The first
-- that covers a spot paints it (the plaza's cobbles run across the
-- street). `name` is for the specs: nothing that collides stands on the
-- street, plaza, paths or walk (WorldPlan.spec). Patches that meet overlap
-- by a stud or two: edge noise can pull both back, and a seam would grow
-- a strip of grass between them.
export type Paint = { name: string, x0: number, x1: number, z0: number, z1: number, material: string }
WorldLayout.TownPaint = {
	{ name = "Plaza", x0 = -26, x1 = 26, z0 = 64, z1 = 97, material = "Cobblestone" },
	-- 22 studs wide (was 14): a Logging Rig has room to line up on the sell pad.
	{ name = "MainStreet", x0 = -104, x1 = 64, z0 = 62, z1 = 84, material = "Ground" },
	-- Where the Forest Path meets the town, wider than the spawn walk.
	{ name = "ForestMouth", x0 = -18, x1 = 6, z0 = 14, z1 = 36, material = "Ground" },
	-- Where the Hills Road meets the town, south of Murph's camp.
	{ name = "HillsMouth", x0 = -42, x1 = 4, z0 = 6, z1 = 34, material = "Ground" },
	-- The turn off the street's east end onto the way north (the mill road).
	{ name = "PlazaEastMouth", x0 = 70, x1 = 112, z0 = 68, z1 = 96, material = "Ground" },
	-- Showroom east wall (DealershipFloor ends at x 69.5) to the lot's west
	-- edge, then along the lot's south side. The jog stays west of the birch
	-- at (130, 98) and south of the one at (160, 84).
	{ name = "TruckLotPath", x0 = 69.5, x1 = 124, z0 = 90, z1 = 98, material = "Ground" },
	{ name = "TruckLotPath", x0 = 116, x1 = 124, z0 = 64, z1 = 98, material = "Ground" },
	{ name = "TruckLotPath", x0 = 116, x1 = 296, z0 = 64, z1 = 70, material = "Ground" },
	-- The shop paths lead to each counter (TWN-13: the shops grew 1.5x).
	{ name = "HearthAndHomePath", x0 = -106, x1 = -94, z0 = 84, z1 = 98, material = "Ground" },
	{ name = "ToolShedPath", x0 = -63, x1 = -51, z0 = 82, z1 = 93, material = "Ground" },
	{ name = "DealershipPath", x0 = 42, x1 = 54, z0 = 82, z1 = 93, material = "Ground" },
	{ name = "SpawnWalk", x0 = -6, x1 = 6, z0 = 34, z1 = 66, material = "Ground" },
	{ name = "MillYard", x0 = -32, x1 = 33, z0 = 95, z1 = 140, material = "Ground" },
	{ name = "GondolaPath", x0 = -39, x1 = -33, z0 = 82, z1 = 142, material = "Ground" },
	{ name = "GondolaPath", x0 = -46, x1 = -33, z0 = 136, z1 = 142, material = "Ground" },
} :: { Paint }

-- Packed dirt under each building, a stud or two past its walls, so the
-- engine's grass (Terrain.Decoration grows on Grass) never pokes up through
-- a shop floor or hides its front (TER-02). The sawmill stands on the
-- MillYard. TerrainGen paints these after TownPaint.
WorldLayout.TownFloors = {
	{ name = "ToolShedFloor", x0 = -73.5, x1 = -38.5, z0 = 88.5, z1 = 119.5, material = "Ground" },
	{ name = "HearthAndHomeFloor", x0 = -128, x1 = -70, z0 = 94, z1 = 144, material = "Ground" },
	{ name = "DealershipFloor", x0 = 35, x1 = 69.5, z0 = 89, z1 = 118, material = "Ground" },
	{ name = "GondolaStationFloor", x0 = -50.5, x1 = -29, z0 = 139, z1 = 160.5, material = "Ground" },
} :: { Paint }

-- The river runs from the pool under the Aether Isles' waterfall, south
-- past the Hills' west side, into Mirror Lake, then out to the west edge.
WorldLayout.River = {
	points = {
		sky + Vector2.new(-20, -110),
		Vector2.new(-930, 760),
		Vector2.new(-820, 480),
		Vector2.new(-770, 200),
		Vector2.new(-800, -60),
	},
	width = 26,
	depth = 7,
}
WorldLayout.Lake = { x = -830, z = -190, radius = 135, depth = 12 }
WorldLayout.LakeOutflow = {
	points = { Vector2.new(-930, -250), Vector2.new(-1200, -320), Vector2.new(-1520, -300) },
	width = 24,
	depth = 6,
}
-- A little pond at the Starter Forest's edge (ducks, lily pads).
WorldLayout.Pond = { x = 78, z = -182, radius = 16, depth = 4 }

-- The east coast: beach then ocean. The coastline wanders with noise; the
-- ocean starts east of `shoreX` south of the volcano.
WorldLayout.Coast = { shoreX = 1190, beachWidth = 70, northZ = 820 }

-- An island offshore (the palmwood teaser; boats come after V1).
WorldLayout.Island = { x = 1395, z = -760, radius = 70, height = 9 }

-- The Volcano's cone sits on the far side of its biome, away from town. Its
-- crater (radius `crater`) has a level lava pool (radius `pool`) in the
-- middle of its floor.
WorldLayout.VolcanoCone =
	{ x = volcano.X + 105, z = volcano.Y + 115, radius = 150, height = 175, crater = 30, pool = 14 }

-- The Gloam Hollow sits in a hollow ringed by ridges (no road in).
WorldLayout.GroveRidge = { inner = 132, outer = 205, height = 34, gapAngle = math.rad(35) }

-- Mountains frame the map's north and west edges (a backdrop; the world
-- walls stop players before the steep part).
WorldLayout.Mountains = { start = 1180, peak = 210 }

-- Distance from point p to segment a-b, and how far along it (0..1).
function WorldLayout.SegmentDistance(p: Vector2, a: Vector2, b: Vector2): (number, number)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude, 0
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude, t
end

-- A polyline flattened to numbers for fast distance checks (the terrain
-- asks millions of times while the world builds; Vector2s are slow there).
export type FastLine = {
	segs: { number }, -- ax, az, bx, bz, ... per segment
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

function WorldLayout.FastLine(points: { Vector2 }): FastLine
	local segs: { number } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, #points do
		local p = points[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
		if i < #points then
			local q = points[i + 1]
			table.insert(segs, p.X)
			table.insert(segs, p.Y)
			table.insert(segs, q.X)
			table.insert(segs, q.Y)
		end
	end
	return { segs = segs, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- Distance from (x, z) to a FastLine, or `cap` if it's farther than cap
-- (cheap rejection by bounding box).
function WorldLayout.FastDistance(line: FastLine, x: number, z: number, cap: number): number
	if x < line.minX - cap or x > line.maxX + cap or z < line.minZ - cap or z > line.maxZ + cap then
		return cap
	end
	local best = cap * cap
	local segs = line.segs
	for i = 1, #segs, 4 do
		local ax, az, bx, bz = segs[i], segs[i + 1], segs[i + 2], segs[i + 3]
		local abx, abz = bx - ax, bz - az
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
		local dx, dz = x - (ax + abx * t), z - (az + abz * t)
		local d2 = dx * dx + dz * dz
		if d2 < best then
			best = d2
		end
	end
	return math.sqrt(best)
end

-- Distance from p to a polyline.
function WorldLayout.PolylineDistance(p: Vector2, points: { Vector2 }): number
	local best = math.huge
	for i = 1, #points - 1 do
		local d = WorldLayout.SegmentDistance(p, points[i], points[i + 1])
		if d < best then
			best = d
		end
	end
	return best
end

-- While the first 322 trees are placed, the ground they avoid is the old
-- district lawn, not today's shelves.
local function flatZonesNow(): { FlatZone }
	if not legacyLayout then
		return WorldLayout.FlatZones
	end
	local zones: { FlatZone } = {}
	for _, zone in ipairs(WorldLayout.FlatZones) do
		if zone.name == "Town" then
			table.insert(zones, zone)
		end
	end
	table.insert(zones, WorldLayout.LegacyPlots)
	return zones
end

-- How flat (x, z) is (0 at a zone's blend edge, 1 deep inside) and the
-- height that flat pulls toward. Town and the old lawn pull to 0.
function WorldLayout.FlatAt(x: number, z: number): (number, number)
	local weight, target = 0, 0
	for _, zone in ipairs(flatZonesNow()) do
		local dx = math.max(zone.x0 - x, 0, x - zone.x1)
		local dz = math.max(zone.z0 - z, 0, z - zone.z1)
		local outside = math.sqrt(dx * dx + dz * dz)
		local w = 1 - math.clamp(outside / zone.blend, 0, 1)
		w = w * w * (3 - 2 * w) -- smoothstep
		if w > weight then
			weight = w
			target = zone.y or 0
		end
	end
	return weight, target
end

function WorldLayout.FlatWeight(x: number, z: number): number
	local weight = WorldLayout.FlatAt(x, z)
	return weight
end

-- Inside a homestead's biggest pad (not the blend, not the old lawn).
function WorldLayout.OnPlotPad(x: number, z: number): boolean
	if legacyLayout then
		return false
	end
	local half = PlotData.Tiers[#PlotData.Tiers].size / 2
	for _, slot in ipairs(PlotData.Slots) do
		if math.abs(x - slot.X) <= half and math.abs(z - slot.Y) <= half then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The forest (phase 10, FOR-01): "a forest with the main area open and
-- then the wild landscapes" (Connor). Three bands, as data:
--   * the hub: open lawn round the town (spawn, sawmill, shops, parking)
--     and the plot district, `hub` studs past each side of their flat
--     zones, its edge wandering `hubNoise` either way. The town's own
--     ornamental trees stand in it; nothing else grows there.
--   * the forest ring: canopy from the lawn's edge out to `ring` (give or
--     take `ringNoise`) past it, thickening over `edge` studs at every
--     edge. Noise opens clearings in it (`clearing`), roads cut through it
--     as clear corridors (WorldPlan keeps its trees off them), and the
--     Starter Forest is its front step south of the spawn.
--   * the wild landscapes beyond, and the biomes the ring wraps round:
--     each biome keeps its own ground `wild[id]` studs past its edge (the
--     Phantom Grove past its ridge), so the Hills stay rolling stands, the
--     Snowfields, the Volcano, the grove's hollow and the Skyroot's foot
--     stay themselves; out here only small copses (`copse`) grow. The
--     forest also stops short of the water (`water`), the beach
--     (`coast`) and the mountains (`mountains`), and leaves `lanes` open:
--     the view from the spawn to the lighthouse, and a trail out of the
--     grove's ridge gap toward town.
-- WorldLayout.ForestCover reads it (TerrainGen paints the forest floor,
-- WorldPlan grows the trees). tests/Forest.spec.luau.
---------------------------------------------------------------------------

export type HubPad = { zone: string, west: number, east: number, south: number, north: number }
export type Lane = { name: string, a: Vector2, b: Vector2, half: number }
export type ForestPlan = {
	hub: { HubPad },
	hubNoise: number,
	edge: number,
	ring: number,
	ringNoise: number,
	clearing: { scale: number, fine: number, from: number, soft: number, keep: number },
	wild: { [string]: number },
	water: number,
	coast: number,
	mountains: number,
	lanes: { Lane },
	copse: { scale: number, from: number, soft: number },
}

local grove = center("grove")
-- The grove's ridge opens toward the sawmill (TerrainGen reads this too).
WorldLayout.GroveGap = math.atan2(WorldLayout.Sawmill.Z - grove.Y, WorldLayout.Sawmill.X - grove.X)
-- Shallow bowls on the hollow's floor, off the trail through the gap.
export type Pool = { x: number, z: number, radius: number, depth: number }
WorldLayout.GrovePools = {
	{ x = grove.X + 48, z = grove.Y - 18, radius = 8, depth = 1.15 },
	{ x = grove.X - 36, z = grove.Y + 42, radius = 7, depth = 1.05 },
	{ x = grove.X + 18, z = grove.Y + 58, radius = 6.5, depth = 1.0 },
} :: { Pool }
local toTown = (Vector2.new(WorldLayout.Sawmill.X, WorldLayout.Sawmill.Z) - grove).Unit
local gapFoot = grove + toTown * (WorldLayout.GroveRidge.inner - 10)

WorldLayout.Forest = {
	hub = {
		-- North of the town the lawn runs past the pine band to about z 315;
		-- west to the Hills' edge; south a strip past the town's edge (the
		-- Starter Forest starts there); east it meets the plot district.
		-- Every pad is at least hubNoise, so the wander never eats a zone.
		{ zone = "Town", west = 80, east = 30, south = 30, north = 110 },
	},
	hubNoise = 30,
	edge = 50,
	ring = 600,
	ringNoise = 90,
	-- Noise above `from` opens a clearing (fully open `soft` above it), but
	-- not within `keep` studs of the hub's lawn: the edge facing the town
	-- and the plots stays a wall of trees.
	clearing = { scale = 110, fine = 40, from = 0.1, soft = 0.14, keep = 70 },
	-- Studs past each biome's area the forest keeps off (the grove's from its
	-- ridge's outer foot). The Starter Forest's own trees are its edge.
	wild = { starter = 8, hills = 40, snow = 170, volcano = 140, grove = 25, sky = 90 },
	water = 16, -- studs off the river, its outflow, the lake and the pond
	coast = 130, -- studs inland of the shore line (its wander and the beach inside it)
	mountains = 1170, -- the forest fades out by here (|x| or |z|; the mountains rise at 1180)
	lanes = {
		-- From the spawn to the lighthouse on the coast's headland
		-- (WorldPlan.Lighthouse): its lamp stays in sight (Forest.spec).
		{ name = "LighthouseVista", a = Vector2.new(0, 40), b = Vector2.new(1203, 236), half = 45 },
		-- A trail out of the Phantom Grove's ridge gap toward town, so the
		-- curious still find it.
		{ name = "GroveTrail", a = gapFoot, b = gapFoot + toTown * 300, half = 18 },
	},
	-- Out in the wild landscapes: small copses where this noise is high.
	copse = { scale = 95, from = 0.2, soft = 0.08 },
} :: ForestPlan

local FOREST = WorldLayout.Forest
local noise = math.noise

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The hub's padded rectangles, flattened (x0, x1, z0, z1 each).
local HUB_RECTS: { { number } } = {}
for _, pad in ipairs(FOREST.hub) do
	for _, zone in ipairs(WorldLayout.FlatZones) do
		if zone.name == pad.zone then
			table.insert(
				HUB_RECTS,
				{ zone.x0 - pad.west, zone.x1 + pad.east, zone.z0 - pad.south, zone.z1 + pad.north }
			)
		end
	end
end
-- The near east of town used to be the district lawn, so a phone at the
-- spawn didn't grow a forest there. Keep that patch of the ring open.
-- The homesteads further out sit in the country.
table.insert(HUB_RECTS, { 126, 380, -200, 80 })

-- Each wild biome's disc (x, z, the radius the forest keeps out of).
local WILD_DISCS: { { number } } = {}
for id, margin in pairs(FOREST.wild) do
	local def = BiomeData.Get(id)
	local a = if def then def.area else nil
	if a then -- (the sky's is the Skyroot's foot, under its isles)
		local r = if id == "grove" then WorldLayout.GroveRidge.outer + margin else a.radius + margin
		table.insert(WILD_DISCS, { a.x, a.z, r })
	end
end
table.sort(WILD_DISCS, function(p: { number }, q: { number }): boolean
	return p[1] * 7 + p[2] < q[1] * 7 + q[2] -- a fixed order (pairs isn't)
end)

local WATER_LINES = {
	{ line = WorldLayout.FastLine(WorldLayout.River.points), half = WorldLayout.River.width / 2 + 4 },
	{ line = WorldLayout.FastLine(WorldLayout.LakeOutflow.points), half = WorldLayout.LakeOutflow.width / 2 + 4 },
}
local WATER_POOLS = { WorldLayout.Lake, WorldLayout.Pond }
local LANE_LINES: { { number } } = {}
for _, lane in ipairs(FOREST.lanes) do
	table.insert(LANE_LINES, { lane.a.X, lane.a.Y, lane.b.X, lane.b.Y, lane.half })
end

-- How far (x, z) is outside the hub's lawn (negative inside), before its
-- edge's wander.
function WorldLayout.HubDistance(x: number, z: number): number
	local best = math.huge
	for _, r in ipairs(HUB_RECTS) do
		local dx = math.max(r[1] - x, 0, x - r[2])
		local dz = math.max(r[3] - z, 0, z - r[4])
		local d
		if dx > 0 or dz > 0 then
			d = math.sqrt(dx * dx + dz * dz)
		else
			d = -math.min(x - r[1], r[2] - x, z - r[3], r[4] - z)
		end
		if d < best then
			best = d
		end
	end
	return best
end

-- Distance from (x, z) to segment (ax, az)-(bx, bz), as plain numbers.
local function segment(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	local t = if len2 > 1e-6 then math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) else 0
	local dx, dz = x - (ax + abx * t), z - (az + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- The forest's canopy over (x, z), 0 (open) to 1 (deep forest); 0.5 is a
-- forest edge. Also how much (x, z) belongs to the forest ring, clearings
-- and all (0 out in the wild landscapes and in the hub; there `cover`
-- comes from the copses alone). Pure and cheap: TerrainGen asks once per
-- terrain column that reaches the meadow. Roads aren't in it (WorldPlan
-- keeps the trees off them; TerrainGen paints them first).
function WorldLayout.ForestCover(x: number, z: number): (number, number)
	local edge = FOREST.edge
	local wander = noise(x / 130, z / 130, 31.7) * FOREST.hubNoise * 2
	-- The world's edge and the beach first: cheap and often enough final.
	local far = math.max(math.abs(x), math.abs(z))
	local w = smooth((FOREST.mountains - far) / edge)
	if w <= 0 then
		return 0, 0
	end
	local coast = WorldLayout.Coast
	if z < coast.northZ + 150 then
		w = math.min(w, smooth((coast.shoreX - FOREST.coast - x + wander) / edge))
		if w <= 0 then
			return 0, 0
		end
	end
	-- The hub's lawn, then the ring's outer edge.
	local hub = WorldLayout.HubDistance(x, z) + wander
	if hub <= 0 then
		return 0, 0
	end
	local ringEdge = FOREST.ring + noise(x / 320, z / 320, 7.3) * FOREST.ringNoise * 2
	local ring = math.min(smooth(hub / edge), smooth((ringEdge - hub) / edge))
	-- The wild biomes, the water and the lanes stay open.
	local open = w
	for _, d in ipairs(WILD_DISCS) do
		local dx, dz = x - d[1], z - d[2]
		local reach = d[3] + edge
		if dx * dx + dz * dz < reach * reach then
			open = math.min(open, smooth((math.sqrt(dx * dx + dz * dz) - d[3] + wander) / edge))
			if open <= 0 then
				return 0, 0
			end
		end
	end
	local margin = FOREST.water
	for _, water in ipairs(WATER_LINES) do
		local cap = water.half + margin + 20
		local d = WorldLayout.FastDistance(water.line, x, z, cap)
		if d < cap then
			open = math.min(open, smooth((d - water.half - margin) / 20))
		end
	end
	for _, pool in ipairs(WATER_POOLS) do
		local dx, dz = x - pool.x, z - pool.z
		local r = pool.radius * 1.15 + margin
		if dx * dx + dz * dz < (r + 20) ^ 2 then
			open = math.min(open, smooth((math.sqrt(dx * dx + dz * dz) - r) / 20))
		end
	end
	for _, lane in ipairs(LANE_LINES) do
		local d = segment(x, z, lane[1], lane[2], lane[3], lane[4])
		if d < lane[5] + 30 then
			open = math.min(open, smooth((d - lane[5]) / 30))
		end
	end
	if open <= 0 then
		return 0, 0
	end
	ring = math.min(ring, open)
	if ring > 0 then
		local c = FOREST.clearing
		local n = noise(x / c.scale, z / c.scale, 3.9) + noise(x / c.fine, z / c.fine, 9.1) * 0.35
		local wall = smooth((hub - c.keep) / c.keep)
		return ring * (1 - smooth((n - c.from) / c.soft) * wall), ring
	end
	-- Out in the wild landscapes: a copse here and there.
	local k = FOREST.copse
	local n = noise(x / k.scale, z / k.scale, 17.3) + noise(x / 31, z / 31, 2.1) * 0.25
	return open * smooth((n - k.from) / k.soft), 0
end

return WorldLayout
