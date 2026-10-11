--!strict
-- UndergroundData: caves, the truck tunnel, mine tiers, rubble, ore
-- anchors, the furnace pad and the secrets. Lane G reads this. Lane M
-- removes Rubble; this module does not.
--
-- Sizes are multiples of 4 studs. Y is the floor. A passage that holds
-- rubble is at least 12 studs wide.

local WorldLayout = require(script.Parent.WorldLayout)

local UndergroundData = {}

export type Cave = {
	id: string,
	name: string,
	tier: number,
	x: number,
	z: number,
	floorY: number,
	height: number,
	sx: number,
	sz: number,
	lights: number,
}

export type Rubble = {
	id: string,
	tier: number,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	yaw: number,
	leadsTo: string,
	passageWidth: number,
}

export type Link = {
	a: string,
	b: string,
	rubble: string?,
}

export type Anchor = {
	id: string,
	tier: number,
	x: number,
	y: number,
	z: number,
}

export type Secret = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	pay: number,
	gear: string?,
	night: boolean,
	parts: number,
}

UndergroundData.PhoneLights = 6
UndergroundData.PhoneDecor = 120
UndergroundData.TunnelLights = 8
UndergroundData.FloorSolid = 24
UndergroundData.CeilingRock = 16

local function cave(
	id: string,
	name: string,
	tier: number,
	x: number,
	z: number,
	floorY: number,
	height: number,
	sx: number,
	sz: number,
	lights: number
): Cave
	return {
		id = id,
		name = name,
		tier = tier,
		x = x,
		z = z,
		floorY = floorY,
		height = height,
		sx = sx,
		sz = sz,
		lights = lights,
	}
end

-- Upper tier is the walk-in mine. Mid and deep sit behind rubble.
-- Hidden mouths are rubble too. Nothing here blocks the truck tunnel.
UndergroundData.Caves = {
	cave("mine-upper", "Upper mine", 1, 150, -220, -48, 24, 48, 48, 4),
	cave("mine-mid", "Mid mine", 2, 80, -280, -76, 24, 44, 44, 4),
	cave("mine-deep", "Deep mine", 3, 80, -360, -108, 24, 52, 40, 6),
	cave("hills-cave", "Hills cave", 2, -400, 80, -40, 24, 40, 40, 3),
	cave("peak-cave", "Peak cave", 3, 90, 840, -36, 24, 40, 40, 3),
	cave("lava-cave", "Lava cave", 3, 540, 680, -36, 24, 40, 40, 3),
	cave("grotto", "Lanternwood grotto", 1, -240, -420, -20, 36, 48, 56, 4),
	cave("waterfall", "Waterfall hollow", 1, 250, 260, -28, 16, 24, 24, 2),
	cave("camp", "Old logging camp", 1, -360, -90, -24, 20, 36, 28, 2),
	cave("ice", "Ice cave", 1, 190, 880, -32, 20, 32, 32, 2),
	cave("tube", "Lava tube", 1, 700, 720, -28, 16, 28, 48, 2),
} :: { Cave }

local byCave: { [string]: Cave } = {}
for _, c in ipairs(UndergroundData.Caves) do
	byCave[c.id] = c
end

function UndergroundData.Cave(id: string): Cave?
	return byCave[id]
end

-- Mouth of the main mine: open, no rubble. 16 x 16. The cave-mouth model
-- (NatureArt.CaveMouth) stands here, turned half a circle so its door faces
-- +Z (toward town) and its throat runs toward -Z, into the hill.
UndergroundData.MineMouth = { x = 150, z = -150, width = 16, height = 16 }

-- The decline from the mouth down to the upper mine (ring map, Oct 10; it
-- was a 16 x 16 shaft straight down for 56 studs). A walkable bore 16 wide
-- and 14 tall: level under the model's arch, then a steady grade round a
-- bend and a U-turn to the upper chamber's east wall. The grade is gentle
-- (about 18 degrees) and the ground over it is raised into a hill
-- (UndergroundData.HillAt) so the bore is roofed, never an open cut.
UndergroundData.Ramp = {
	width = 16,
	height = 14,
	top = 1.5, -- the ground at the door (TerrainGen.HeightAt(150, -143) is 1.44; it was 3.2 before the river and pads moved)
	doorZ = -143, -- the door's front plane, where the walk-in starts
	landing = 15, -- level studs from the door, under the arch (the arch is 15 deep)
	cover = 6, -- studs of rock the hill keeps over the bore's roof
	step = 2, -- spacing of the air boxes along the bore
	lights = 5,
}

local function rampPoints(): { Vector2 }
	local pts: { Vector2 } = { Vector2.new(150, UndergroundData.Ramp.doorZ) }
	local function add(x: number, z: number)
		table.insert(pts, Vector2.new(x, z))
	end
	-- Straight back from the door, a right turn (radius 20), a straight run
	-- east, a U-turn (radius 20) and a straight run west into the chamber.
	add(150, -166)
	for a = 195, 270, 15 do
		local r = math.rad(a)
		add(170 + 20 * math.cos(r), -166 + 20 * math.sin(r))
	end
	add(200, -186)
	for a = 75, -90, -15 do
		local r = math.rad(a)
		add(200 + 20 * math.cos(r), -206 + 20 * math.sin(r))
	end
	add(178, -226)
	return pts
end

-- The bore's centre line, a sample every `step` studs: { x, z, s (studs from
-- the door), y (the floor) }.
export type RampSample = { x: number, z: number, s: number, y: number }
local rampSamples: { RampSample } = {}
local rampLength = 0
do
	local ramp = UndergroundData.Ramp
	local pts = rampPoints()
	local total = 0
	for i = 1, #pts - 1 do
		total += (pts[i + 1] - pts[i]).Magnitude
	end
	rampLength = total
	-- The grade runs from the end of the landing to 8 studs before the
	-- chamber wall's centre line (the last 8 are level, on the chamber floor).
	local upper = byCave["mine-upper"]
	local bottom = if upper then upper.floorY else -48
	local startS = ramp.landing
	local endS = total - 8
	local function floorAt(s: number): number
		if s <= startS then
			return ramp.top
		elseif s >= endS then
			return bottom
		end
		return ramp.top + (bottom - ramp.top) * (s - startS) / (endS - startS)
	end
	local walked = 0
	local n = math.floor(total / ramp.step)
	local seg = 1
	for k = 0, n do
		local s = math.min(k * ramp.step, total)
		while seg < #pts - 1 and walked + (pts[seg + 1] - pts[seg]).Magnitude < s - 1e-6 do
			walked += (pts[seg + 1] - pts[seg]).Magnitude
			seg += 1
		end
		local a, b = pts[seg], pts[seg + 1]
		local len = (b - a).Magnitude
		local p = a:Lerp(b, if len > 0 then math.clamp((s - walked) / len, 0, 1) else 0)
		table.insert(rampSamples, { x = p.X, z = p.Y, s = s, y = floorAt(s) })
	end
end
UndergroundData.RampSamples = rampSamples
UndergroundData.RampLength = rampLength
-- The grade as rise over run (the descent only).
UndergroundData.RampGrade = (UndergroundData.Ramp.top - rampSamples[#rampSamples].y)
	/ (rampLength - 8 - UndergroundData.Ramp.landing)

-- The ground the hill gives the bore: at least floor + height + cover over
-- the centre line, full for 10 studs either side, then falling away 1.3
-- studs of run per stud of height. TerrainGen takes the larger of this and the country's own height.
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
function UndergroundData.HillAt(x: number, z: number): number
	if x < 100 or x > 262 or z > -108 or z < -258 then
		return 0
	end
	local ramp = UndergroundData.Ramp
	local best = 0
	for _, p in ipairs(rampSamples) do
		local need = p.y + ramp.height + ramp.cover
		if need > 6 then
			local dx, dz = x - p.x, z - p.z
			local d2 = dx * dx + dz * dz
			local reach = 10 + need * 1.3
			if d2 < reach * reach then
				local d = math.sqrt(d2)
				local w = if d <= 10 then 1 else 1 - smooth((d - 10) / (need * 1.3))
				best = math.max(best, need * w)
			end
		end
	end
	-- None at or in front of the door's plane, so the ground before the arch
	-- stays level; the hill rises over the arch's own 8 studs of depth, where
	-- the model's body stands over it.
	if z > ramp.doorZ - 8 then
		best *= smooth((ramp.doorZ - z) / 8)
	end
	return best
end

-- Where the bore's floor is under (x, z): the lowest sample within the
-- bore's half width, or nil. TerrainBuilder keeps rock under it.
function UndergroundData.RampFloorAt(x: number, z: number): number?
	local half = UndergroundData.Ramp.width / 2 + 2
	if x < 130 or x > 230 or z > -140 or z < -240 then
		return nil
	end
	local best: number? = nil
	for _, p in ipairs(rampSamples) do
		local dx, dz = x - p.x, z - p.z
		if dx * dx + dz * dz <= half * half then
			best = if best then math.min(best, p.y) else p.y
		end
	end
	return best
end

UndergroundData.Rubble = {
	{
		id = "mine-mid",
		tier = 2,
		x = 116,
		y = -40,
		z = -250,
		sx = 16,
		sy = 12,
		sz = 6,
		yaw = 0,
		leadsTo = "mid",
		passageWidth = 16,
	},
	{
		id = "mine-deep",
		tier = 3,
		x = 80,
		y = -72,
		z = -320,
		sx = 16,
		sy = 12,
		sz = 6,
		yaw = 0,
		leadsTo = "deep",
		passageWidth = 16,
	},
	{
		id = "hidden-hills",
		tier = 2,
		x = -400,
		y = 4,
		z = 40,
		sx = 16,
		sy = 12,
		sz = 6,
		yaw = 0,
		leadsTo = "mid",
		passageWidth = 16,
	},
	{
		id = "hidden-peak",
		tier = 3,
		x = 90,
		y = 8,
		z = 800,
		sx = 16,
		sy = 12,
		sz = 6,
		yaw = 0,
		leadsTo = "deep",
		passageWidth = 16,
	},
	{
		id = "hidden-lava",
		tier = 3,
		x = 540,
		y = 6,
		z = 640,
		sx = 16,
		sy = 12,
		sz = 6,
		yaw = 0,
		leadsTo = "deep",
		passageWidth = 16,
	},
} :: { Rubble }

-- surface is the walk-in mouth. An open link needs no rubble removed.
UndergroundData.Links = {
	{ a = "surface", b = "mine-upper" },
	{ a = "mine-upper", b = "mine-mid", rubble = "mine-mid" },
	{ a = "mine-mid", b = "mine-deep", rubble = "mine-deep" },
	{ a = "surface", b = "hills-cave", rubble = "hidden-hills" },
	{ a = "hills-cave", b = "mine-mid" },
	{ a = "surface", b = "peak-cave", rubble = "hidden-peak" },
	{ a = "peak-cave", b = "mine-deep" },
	{ a = "surface", b = "lava-cave", rubble = "hidden-lava" },
	{ a = "lava-cave", b = "mine-deep" },
} :: { Link }

UndergroundData.Tiers = {
	{ id = "upper", depth = 1, danger = 1, chambers = { "mine-upper", "grotto" } },
	{ id = "mid", depth = 2, danger = 2, chambers = { "mine-mid", "hills-cave" } },
	{ id = "deep", depth = 3, danger = 3, chambers = { "mine-deep", "peak-cave", "lava-cave" } },
}

-- Flat 30 x 24 pad beside the south link, for Lane M's furnace. Not the
-- sell station (that stays at the sawmill plus 53, 1).
UndergroundData.FurnaceSite = { x = 48, z = -110, sx = 30, sz = 24 }

UndergroundData.Secrets = {
	{
		id = "waterfall",
		name = "Waterfall hollow",
		x = 250,
		z = 260,
		radius = 18,
		pay = 300,
		gear = nil,
		night = false,
		parts = 40,
	},
	{
		id = "camp",
		name = "Old logging camp",
		x = -360,
		z = -90,
		radius = 18,
		pay = 2000,
		gear = nil,
		night = false,
		parts = 48,
	},
	{
		id = "ice",
		name = "Ice cave",
		x = 190,
		z = 880,
		radius = 18,
		pay = 4000,
		gear = "InsulatedCoat",
		night = false,
		parts = 36,
	},
	{
		id = "lava",
		name = "Lava tube",
		x = 700,
		z = 720,
		radius = 18,
		pay = 8000,
		gear = "HeatBoots",
		night = false,
		parts = 36,
	},
	{
		id = "ravine",
		name = "Ravine floor",
		x = 200,
		z = -820,
		radius = 18,
		pay = 3000,
		gear = "Lantern",
		night = true,
		parts = 24,
	},
} :: { Secret }

local function wallAnchors(c: Cave, step: number, out: { Anchor })
	local y = c.floorY + 6
	local hz, hx = c.sz / 2 - 2, c.sx / 2 - 2
	local z = -hz
	while z <= hz do
		table.insert(out, { id = c.id .. "-n-" .. z, tier = c.tier, x = c.x, y = y, z = c.z + z })
		table.insert(out, { id = c.id .. "-s-" .. z, tier = c.tier, x = c.x, y = y, z = c.z - z })
		z += step
	end
	local x = -hx + step / 2
	while x <= hx do
		table.insert(out, { id = c.id .. "-e-" .. x, tier = c.tier, x = c.x + x, y = y, z = c.z })
		x += step
	end
end

local anchors: { Anchor } = {}
for _, c in ipairs(UndergroundData.Caves) do
	if
		c.tier >= 1 and string.sub(c.id, 1, 4) == "mine"
		or c.id == "hills-cave"
		or c.id == "peak-cave"
		or c.id == "lava-cave"
	then
		local step = if c.tier >= 3 then 24 else 40
		wallAnchors(c, step, anchors)
	end
end
UndergroundData.MineAnchors = anchors

local TUNNEL_LINE = WorldLayout.FastLine(WorldLayout.TunnelPoints)

function UndergroundData.LowestFloor(x: number, z: number): number?
	local best: number? = nil
	for _, c in ipairs(UndergroundData.Caves) do
		if math.abs(x - c.x) <= c.sx / 2 and math.abs(z - c.z) <= c.sz / 2 then
			best = if best then math.min(best, c.floorY) else c.floorY
		end
	end
	local d = WorldLayout.FastDistance(TUNNEL_LINE, x, z, WorldLayout.TunnelWidth)
	if d < WorldLayout.TunnelWidth / 2 then
		local floor = WorldLayout.TunnelFloorY
		best = if best then math.min(best, floor) else floor
	end
	local ramp = UndergroundData.RampFloorAt(x, z)
	if ramp then
		best = if best then math.min(best, ramp) else ramp
	end
	return best
end

function UndergroundData.CaveAt(x: number, z: number, y: number): Cave?
	for _, c in ipairs(UndergroundData.Caves) do
		if math.abs(x - c.x) <= c.sx / 2 and math.abs(z - c.z) <= c.sz / 2 then
			if y >= c.floorY and y <= c.floorY + c.height then
				return c
			end
		end
	end
	return nil
end

-- Chambers still joined to "surface" when rubble in `blocked` is still up.
function UndergroundData.Reachable(blocked: { [string]: boolean }): { [string]: boolean }
	local open: { [string]: boolean } = { surface = true }
	local changed = true
	while changed do
		changed = false
		for _, link in ipairs(UndergroundData.Links) do
			local closed = link.rubble ~= nil and blocked[link.rubble] == true
			if not closed then
				if open[link.a] and not open[link.b] then
					open[link.b] = true
					changed = true
				elseif open[link.b] and not open[link.a] then
					open[link.a] = true
					changed = true
				end
			end
		end
	end
	return open
end

export type AirBox = {
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	kind: string,
}

local function snap4(n: number): number
	return math.max(4, math.floor(n / 4 + 0.5) * 4)
end

-- Air the second pass cuts. Sizes are multiples of 4 (the ramp's boxes are
-- 16 wide and 14 tall). Chambers, the passages that hold rubble, the mouth's
-- decline, and the truck bore.
function UndergroundData.AirBoxes(): { AirBox }
	local boxes: { AirBox } = {}
	for _, c in ipairs(UndergroundData.Caves) do
		table.insert(boxes, {
			x = c.x,
			y = c.floorY + c.height / 2,
			z = c.z,
			sx = snap4(c.sx),
			sy = snap4(c.height),
			sz = snap4(c.sz),
			kind = "chamber",
		})
	end
	for _, rubble in ipairs(UndergroundData.Rubble) do
		local sx = snap4(math.max(rubble.passageWidth, rubble.sx + 4))
		local sy = snap4(math.max(12, rubble.sy + 4))
		local sz = snap4(math.max(rubble.passageWidth, rubble.sz + 4))
		table.insert(boxes, {
			x = rubble.x,
			y = rubble.y + sy / 2,
			z = rubble.z,
			sx = sx,
			sy = sy,
			sz = sz,
			kind = "passage",
		})
	end
	-- The decline from the mouth: one box per sample, its floor on the grade.
	local ramp = UndergroundData.Ramp
	for _, p in ipairs(rampSamples) do
		table.insert(boxes, {
			x = p.x,
			y = p.y + ramp.height / 2,
			z = p.z,
			sx = ramp.width,
			sy = ramp.height,
			sz = ramp.width,
			kind = "ramp",
		})
	end
	local floor = WorldLayout.TunnelFloorY
	local height = WorldLayout.TunnelHeight
	local width = snap4(WorldLayout.TunnelWidth)
	local pts = WorldLayout.TunnelPoints
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		local steps = math.max(1, math.floor(len / 8))
		for s = 0, steps do
			local p = a:Lerp(b, s / steps)
			table.insert(boxes, {
				x = p.X,
				y = floor + height / 2,
				z = p.Y,
				sx = width,
				sy = snap4(height),
				sz = width,
				kind = "tunnel",
			})
		end
	end
	return boxes
end

-- True when the rubble's block sits inside a carved passage.
function UndergroundData.RubbleInPassage(rubble: Rubble): boolean
	for _, box in ipairs(UndergroundData.AirBoxes()) do
		if box.kind == "passage" then
			local inside = math.abs(rubble.x - box.x) + rubble.sx / 2 <= box.sx / 2
				and math.abs(rubble.y + rubble.sy / 2 - box.y) + rubble.sy / 2 <= box.sy / 2
				and math.abs(rubble.z - box.z) + rubble.sz / 2 <= box.sz / 2
			if inside and box.sx >= 12 and box.sy >= 12 then
				return true
			end
		end
	end
	return false
end

function UndergroundData.TunnelLength(): number
	local pts = WorldLayout.TunnelPoints
	local total = 0
	for i = 1, #pts - 1 do
		total += (pts[i + 1] - pts[i]).Magnitude
	end
	return total
end

return UndergroundData
