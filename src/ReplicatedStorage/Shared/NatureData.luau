--!strict
-- NatureData: where client rocks, plants, cave dressing and shelter live.
-- Positions come from ScatterZones when Lane B has merged that module, and
-- from WorldPlan until then. Specs pass a stub; this file never ships one.
-- Cells are 64 studs. The same cell always scatters the same pieces.
-- Nothing is placed where `blocked` says the ground is taken (roads, pads,
-- town, water). Cave pieces share AmbientLife's MaxDecor model cap and
-- stay at or under CavePartCap parts per cave, with at most CaveLightCap
-- lights (the client turns the extras off).

local NatureData = {}

export type Kind = "meadow" | "forest" | "shore" | "snow" | "volcano" | "gloam" | "isle" | "town" | "cave"

export type Zone = {
	id: string,
	kind: Kind,
	center: Vector2,
	radius: number,
	density: number,
	shelter: string?, -- "cave" | "tunnel" | "grotto" when rain must stop
	below: number?, -- sheltered when the camera is at or under this Y
	floor: number?, -- place pieces on this Y instead of the terrain
}

export type Spot = {
	kind: string,
	variant: number,
	x: number,
	z: number,
	yaw: number,
	seed: number,
	y: number?,
	caveId: string?,
	parts: number,
	light: boolean,
	look: Kind?, -- zone kind; picks the rock palette
}

-- Lane B's modules are not in the game until that branch merges. A static
-- require would be a type error while the ModuleScript is missing, so the
-- call goes through a function value.
function NatureData.TryModule(inst: Instance?): any
	if inst and inst:IsA("ModuleScript") then
		local load: (ModuleScript) -> any = require
		return load(inst)
	end
	return nil
end

NatureData.Cell = 64
NatureData.CavePartCap = 120
NatureData.CaveLightCap = 6
NatureData.RoadMargin = 4

-- What a zone kind is dressed with. Town is empty on purpose.
NatureData.Menu = {
	meadow = { "Bush", "Fern", "Flowers", "Boulder", "Mushroom" },
	forest = { "Fern", "Mushroom", "Bush", "Slab", "Outcrop" },
	shore = { "Reeds", "Slab", "PebbleCluster", "Flowers" },
	snow = { "SnowShrub", "Spire", "CrackedBoulder" },
	volcano = { "AshShrub", "Boulder", "Outcrop" },
	gloam = { "GloamCap", "Mushroom", "Spire", "Fern" },
	isle = { "IsleCrystal", "Fern", "Flowers" },
	town = {},
	cave = { "CaveMushroom", "GlowFungus", "CrystalRock", "Roots", "Bat", "Boulder" },
} :: { [string]: { string } }

-- Must match NatureArt.Parts. The spec checks both.
NatureData.PartCost = {
	Boulder = 6,
	CrackedBoulder = 6,
	Spire = 6,
	Slab = 6,
	PebbleCluster = 6,
	Outcrop = 6,
	Bush = 4,
	Fern = 3,
	Flowers = 5,
	Mushroom = 3,
	Reeds = 4,
	SnowShrub = 3,
	AshShrub = 3,
	GloamCap = 4,
	IsleCrystal = 4,
	CaveMushroom = 3,
	GlowFungus = 4,
	CrystalRock = 5,
	Roots = 4,
	Bat = 6,
} :: { [string]: number }

NatureData.LightKinds = {
	GlowFungus = true,
	CrystalRock = true,
	GloamCap = true,
	IsleCrystal = true,
} :: { [string]: boolean }

local function hash(cx: number, cz: number, i: number): number
	local n = (cx * 73856093 + cz * 19349663 + i * 83492791) % 2147483647
	if n < 0 then
		n = -n
	end
	if n == 0 then
		n = 1
	end
	return n
end

function NatureData.Inside(zone: Zone, x: number, z: number): boolean
	local dx = x - zone.center.X
	local dz = z - zone.center.Y
	return dx * dx + dz * dz <= zone.radius * zone.radius
end

function NatureData.OverlapsCell(zone: Zone, cx: number, cz: number): boolean
	local x = (cx + 0.5) * NatureData.Cell
	local z = (cz + 0.5) * NatureData.Cell
	local dx = x - zone.center.X
	local dz = z - zone.center.Y
	local reach = zone.radius + NatureData.Cell * 0.72
	return dx * dx + dz * dz <= reach * reach
end

-- ScatterZones wins once it has rows. Until then, WorldPlan's zones.
-- Underground rooms are appended only while ScatterZones is absent, so B's
-- table is not decorated twice.
function NatureData.Assemble(scatter: { Zone }?, plan: { Zone }, rooms: { Zone }?): { Zone }
	if scatter and #scatter > 0 then
		return scatter
	end
	local out: { Zone } = {}
	for _, zone in ipairs(plan) do
		table.insert(out, zone)
	end
	for _, room in ipairs(rooms or {}) do
		table.insert(out, room)
	end
	return out
end

-- Map a WorldPlan-shaped table (the real module, or a spec stub) into zones.
-- Missing methods are skipped. No coordinates are written here.
function NatureData.FromWorldPlan(plan: any): { Zone }
	local zones: { Zone } = {}
	if type(plan) ~= "table" then
		return zones
	end
	if type(plan.GroveDiscs) == "function" then
		for i, disc in ipairs(plan.GroveDiscs()) do
			table.insert(zones, {
				id = "grove-" .. tostring(i),
				kind = "forest",
				center = Vector2.new(disc.cx, disc.cz),
				radius = disc.radius,
				density = 0.4,
			})
		end
	end
	if type(plan.Crater) == "function" then
		local center, radius = plan.Crater()
		if typeof(center) == "Vector3" then
			table.insert(zones, {
				id = "volcano",
				kind = "volcano",
				center = Vector2.new(center.X, center.Z),
				radius = math.max((radius or 20) * 4, 70),
				density = 0.28,
			})
		end
	end
	if type(plan.Sky) == "function" then
		local sky = plan.Sky()
		if type(sky) == "table" and typeof(sky.root) == "Vector3" then
			table.insert(zones, {
				id = "isles",
				kind = "isle",
				center = Vector2.new(sky.root.X, sky.root.Z),
				radius = 180,
				density = 0.32,
				floor = sky.top,
			})
		end
	end
	if type(plan.FerryPalms) == "function" then
		local palms = plan.FerryPalms()
		if type(palms) == "table" and #palms > 0 then
			local sx, sz = 0, 0
			for _, tree in ipairs(palms) do
				local p = tree.position
				sx += p.X
				sz += p.Z
			end
			local n = #palms
			table.insert(zones, {
				id = "ferry-shore",
				kind = "shore",
				center = Vector2.new(sx / n, sz / n),
				radius = 80,
				density = 0.35,
			})
		end
	end
	if type(plan.PointsOfInterest) == "function" then
		for _, poi in ipairs(plan.PointsOfInterest()) do
			if poi.kind == "Cave" and typeof(poi.cframe) == "CFrame" then
				local p = poi.cframe.Position
				table.insert(zones, {
					id = tostring(poi.id),
					kind = "cave",
					center = Vector2.new(p.X, p.Z),
					radius = 36,
					density = 0.65,
					shelter = "cave",
					below = p.Y - 6,
					floor = p.Y - 8,
				})
			end
		end
	end
	if type(plan.Lanternwood) == "function" then
		local trees = plan.Lanternwood()
		if type(trees) == "table" and #trees > 0 and trees[1].position then
			local p = trees[1].position
			table.insert(zones, {
				id = "lantern-grotto",
				kind = "cave",
				center = Vector2.new(p.X, p.Z),
				radius = 28,
				density = 0.7,
				shelter = "grotto",
				below = p.Y - 8,
				floor = p.Y - 10,
			})
		end
	end
	if type(plan.Underground) == "function" then
		for _, room in ipairs(plan.Underground()) do
			if type(room) == "table" and room.center and room.id then
				local c = room.center
				local shelter = room.shelter or "cave"
				table.insert(zones, {
					id = tostring(room.id),
					kind = "cave",
					center = if typeof(c) == "Vector3" then Vector2.new(c.X, c.Z) else c,
					radius = room.radius or 24,
					density = room.density or 0.6,
					shelter = shelter,
					below = room.below,
					floor = room.floor,
				})
			end
		end
	end
	return zones
end

-- Rooms from UndergroundData (B). Each room needs id, center, radius.
function NatureData.FromRooms(rooms: { any }?): { Zone }
	local zones: { Zone } = {}
	for _, room in ipairs(rooms or {}) do
		if type(room) == "table" and room.id and room.center then
			local c = room.center
			local center = if typeof(c) == "Vector3"
				then Vector2.new(c.X, c.Z)
				elseif typeof(c) == "Vector2" then c
				else nil
			if center then
				table.insert(zones, {
					id = tostring(room.id),
					kind = "cave",
					center = center,
					radius = room.radius or 24,
					density = room.density or 0.6,
					shelter = room.shelter or "cave",
					below = room.below,
					floor = room.floor or (if typeof(c) == "Vector3" then c.Y else nil),
				})
			end
		end
	end
	return zones
end

-- True when rain should be off: a ceiling was hit, or the camera is inside
-- a cave, tunnel or grotto (under that zone's `below` when it has one).
function NatureData.Sheltered(zones: { Zone }, x: number, y: number, z: number, ceilingHit: boolean): boolean
	if ceilingHit then
		return true
	end
	for _, zone in ipairs(zones) do
		if zone.shelter and NatureData.Inside(zone, x, z) then
			if zone.below == nil or y <= zone.below then
				return true
			end
		end
	end
	return false
end

function NatureData.Find(zones: { Zone }, kind: Kind, x: number, z: number): Zone?
	local best: Zone? = nil
	local bestD = math.huge
	for _, zone in ipairs(zones) do
		if zone.kind == kind and NatureData.Inside(zone, x, z) then
			local dx = x - zone.center.X
			local dz = z - zone.center.Y
			local d = dx * dx + dz * dz
			if d < bestD then
				best = zone
				bestD = d
			end
		end
	end
	return best
end

-- Load a cell whose terrain is far below the camera when the camera is
-- inside a cave or on an isle over that cell. Surface cells keep the old
-- 160-stud band.
function NatureData.WatchCell(zones: { Zone }, cx: number, cz: number, focus: Vector3, groundY: number): boolean
	if math.abs(focus.Y - groundY) < 160 then
		return true
	end
	for _, zone in ipairs(zones) do
		if NatureData.OverlapsCell(zone, cx, cz) and NatureData.Inside(zone, focus.X, focus.Z) then
			if zone.kind == "isle" or zone.kind == "cave" or zone.shelter ~= nil then
				return true
			end
		end
	end
	return false
end

local function slotsFor(zone: Zone): number
	local n = math.floor(zone.density * 4 + 0.5)
	if zone.kind == "cave" then
		return math.clamp(n, 0, 4)
	end
	return math.clamp(n, 0, 3)
end

-- Deterministic spots in cell (cx, cz). `blocked(x, z)` skips surface
-- ground. Cave spots ignore it (they sit on the cave floor) but still
-- stop at CavePartCap parts for that cave id, using `caveParts` as the
-- running total. Surface spots stop at `natureLeft` parts.
function NatureData.CellSpots(
	cx: number,
	cz: number,
	zones: { Zone },
	blocked: (number, number) -> boolean,
	caveParts: { [string]: number },
	natureLeft: number
): { Spot }
	local hitting: { Zone } = {}
	for _, zone in ipairs(zones) do
		if NatureData.OverlapsCell(zone, cx, cz) and zone.density > 0 then
			table.insert(hitting, zone)
		end
	end
	local spots: { Spot } = {}
	if #hitting == 0 then
		return spots
	end
	local x0 = cx * NatureData.Cell
	local z0 = cz * NatureData.Cell
	local left = natureLeft
	local budget = table.clone(caveParts)
	local slot = 0
	for _, zone in ipairs(hitting) do
		local menu = NatureData.Menu[zone.kind]
		local count = if menu then slotsFor(zone) else 0
		for _ = 1, count do
			slot += 1
			if not menu or #menu == 0 then
				break
			end
			local h = hash(cx, cz, slot)
			local kind = menu[(h % #menu) + 1]
			local cost = NatureData.PartCost[kind] or 4
			local x = x0 + 3 + (h % 58)
			local z = z0 + 3 + (math.floor(h / 58) % 58)
			if not NatureData.Inside(zone, x, z) then
				continue
			end
			local caveId: string? = if zone.kind == "cave" then zone.id else nil
			if caveId then
				local used = budget[caveId] or 0
				if used + cost > NatureData.CavePartCap then
					continue
				end
				budget[caveId] = used + cost
			else
				if blocked(x, z) then
					continue
				end
				if left < cost then
					continue
				end
				left -= cost
			end
			table.insert(spots, {
				kind = kind,
				variant = (math.floor(h / 7) % 3) + 1,
				x = x,
				z = z,
				yaw = (h % 628) / 100,
				seed = h,
				y = zone.floor,
				caveId = caveId,
				parts = cost,
				light = NatureData.LightKinds[kind] == true,
				look = zone.kind,
			})
		end
	end
	return spots
end

return NatureData
