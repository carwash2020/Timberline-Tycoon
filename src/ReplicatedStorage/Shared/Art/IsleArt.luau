--!strict
-- IsleArt: the Skyroot (the colossal tree the whole map points at), the
-- floating Aether Isles it holds up, and their dressing: the waterfall, the
-- cloud banks, lantern posts (GAME_DESIGN §10, §13: white-gold light, soft
-- cloud banks, Lumenwood motes drifting upward). Pure (see Kit).
--
-- Contract (MapBuilder, the previews and IsleArt.spec rely on it):
--   * Skyroot(height, isles?, clearDir?, fall?): a Model on the ground at
--     the origin. PrimaryPart "SkyrootTrunk" (the trunk's lowest core
--     segment). "SkyrootRoots" is one of the root fins. The trunk, its
--     strands and its roots collide (you bump into a giant tree); the
--     limbs ("SkyrootLimb"), leaves ("SkyrootLeaves"), vines and pods are
--     decoration. No leaf rises above `height` (the main isle's top is 12
--     studs higher), and none rises within 25 studs of an isle's top over
--     its footprint, so the canopy never pokes through walkable ground.
--     Roots and leaves keep clear of the gondola cables on the clear side.
--     Under ~180 parts (it's Persistent).
--   * Isle(radius, seed, options?): its walkable top at y = 0: "IsleTop",
--     a flat cylinder covering the whole radius that collides (and the
--     PrimaryPart). Everything else is decoration; nothing but flowers,
--     tufts and stones rises above the top, and only near the rim. With
--     options.spout: "SpringPool" and "Stream". Under ~120 parts.
--   * Waterfall(height, width): origin at the top lip, the water falling
--     to y = -height in front of it (-Z); place it with -Z pointing away
--     from the isle. Named parts "Waterfall" (the sheet, top 40 studs),
--     "WaterfallCurtain" (invisible, the whole height: its attachments
--     hold the "Curtain" emitters), "WaterfallSpray" (invisible, the mist
--     band; "Veil" emitter) and "WaterfallMist" (at the bottom: the "Mist"
--     and "Spray" emitters). Every emitter's full rate is in its
--     "BaseRate" attribute (the client halves it on low quality).
--   * CloudBank(size, seed): a cloud about `size` studs long (X), its base
--     at y = 0. Decoration. CloudSpots(...) says where they go.
--   * LanternPost(seed): a crooked post with a lantern; "LanternGlow".

local Kit = require(script.Parent.Kit)

type Rng = Kit.Rng

local IsleArt = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- The isles' rock, from the rim down to the tip: how deep each tier ends
-- (fraction of the underside's depth) and how wide it is there (fraction of
-- the radius). Skyroot tucks its limbs into this shape.
local DEPTH = 1.2 -- underside depth, in radii
local PROFILE = {
	{ depth = 0.0, radius = 0.97 },
	{ depth = 0.33, radius = 0.74 },
	{ depth = 0.6, radius = 0.47 },
	{ depth = 0.8, radius = 0.24 },
}

-- Palette: honey-brown bark, pale gold-green leaves, cream sandstone.
local BARK = { hex("#7E5C3E"), hex("#8A6646"), hex("#735337") }
local CORE = hex("#6A4C33")
local ROOT = hex("#6E4F34")
local LEAVES = { hex("#D6E486"), hex("#C2D86A"), hex("#E8EA9C"), hex("#B2CF5E"), hex("#E2DC7E") }
local GOLD = hex("#FFE7A0")
local GRASS_TOP = hex("#B2D46A")
local TURF = { hex("#9CC45A"), hex("#A8CC60"), hex("#8FB852") }
local SOIL = { hex("#8B6643"), hex("#7C5939"), hex("#96714C") }
local TIERS = {
	{ colors = { hex("#DCCCB0"), hex("#D0BEA0"), hex("#E5D7BE") }, material = Enum.Material.Sandstone },
	{ colors = { hex("#C2B19C"), hex("#B6A590"), hex("#CBBCA8") }, material = Enum.Material.Rock },
	{ colors = { hex("#A6968A"), hex("#9A8A7E"), hex("#AF9F92") }, material = Enum.Material.Rock },
}
local TIP = { hex("#8E7F74"), hex("#83756B"), hex("#978879") }
local SOFT_CANOPY = true
local CRYSTAL = hex("#9FE6FF")
local CRYSTAL_GLASS = hex("#D8F5FF")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function polar(angle: number, r: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
end

-- The horizontal unit vector of v (nil when v is (nearly) vertical).
local function flat(v: Vector3): Vector3?
	local h = Vector3.new(v.X, 0, v.Z)
	if h.Magnitude < 1e-3 then
		return nil
	end
	return h.Unit
end

local function angleOf(v: Vector3): number
	return math.atan2(v.Z, v.X)
end

-- The smallest difference between two angles (radians, 0..pi).
local function angleGap(a: number, b: number): number
	local d = (a - b) % (math.pi * 2)
	return math.min(d, math.pi * 2 - d)
end

-- The highest point of a part's bounding box (exact for blocks).
function IsleArt.TopOf(p: BasePart): number
	local cf, s = p.CFrame, p.Size
	return cf.Y + 0.5 * (math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z)
end

-- CFrame.lookAt built from fromMatrix: the same frame in Roblox, and right
-- in the preview too (Lune 0.10's CFrame.lookAt returns wrong rotations).
local function lookAt(at: Vector3, target: Vector3): CFrame
	local look = (target - at).Unit
	local ref = if math.abs(look.Y) > 0.999 then Vector3.zAxis else Vector3.yAxis
	local right = look:Cross(ref).Unit
	return CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

-- A cylinder from a to b (Kit.rod, via lookAt above).
local function rod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	local cf = lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return Kit.cylinder(parent, name, (b - a).Magnitude, diameter, cf, color, material)
end

-- A box from a to b (Kit.beam, via lookAt above).
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.part(
		parent,
		name,
		Vector3.new(width, height, (b - a).Magnitude),
		lookAt((a + b) / 2, b),
		color,
		material
	)
end

-- A rod `from` to `to`, lengthened by `extend` at both ends so the joints
-- between segments don't show gaps.
local function limb(
	model: Model,
	name: string,
	from: Vector3,
	to: Vector3,
	diameter: number,
	color: Color3,
	extend: number?
): Part
	local dir = (to - from).Unit
	local e = extend or diameter * 0.3
	return rod(model, name, from - dir * e, to + dir * e, diameter, color, Enum.Material.Wood)
end

local function emitter(parent: BasePart, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Parent = parent
	return e
end

-- Lumenwood motes drifting upward from a glowing part.
local function motes(part: BasePart, size: number, rate: number)
	local e = emitter(part, "Motes")
	e.Color = ColorSequence.new(GOLD, hex("#FFF6D6"))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(6, 10)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 1.6, 0)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.15)
end

-- A leaf cluster `size` across: a corner-up core cube and two smaller ones
-- leaning off it, a little flattened (the house's faceted canopy, big).
local function leafCluster(model: Model, center: Vector3, size: number, rng: Rng): { Part }
	local out: { Part } = {}
	local yaw = rng:range(0, math.pi * 2)
	local turn = CFrame.Angles(0, yaw, 0)
	local specs = {
		{ offset = Vector3.new(0, 0, 0), s = 0.62 },
		{ offset = Vector3.new(0.33, -0.1, 0.06), s = 0.46 },
		{ offset = Vector3.new(-0.3, 0.05, -0.14), s = 0.42 },
	}
	for i, sp in ipairs(specs) do
		local e = size * sp.s
		local color = Kit.vary(LEAVES[(i + math.floor(yaw * 3)) % #LEAVES + 1], rng, 0.05)
		local p
		if SOFT_CANOPY then
			p = Kit.ellipsoid(
				model,
				"SkyrootLeaves",
				Vector3.new(e * 1.3, e * 0.95, e * 1.2),
				CFrame.new(center + turn:VectorToWorldSpace(sp.offset * size)) * CFrame.Angles(0, yaw, 0),
				color,
				Enum.Material.SmoothPlastic
			)
		else
			local tilt = if i == 2
				then CFrame.Angles(rng:range(-0.4, 0.4), 0, rng:range(-0.4, 0.4))
				else CFrame.Angles(math.rad(35.26), math.rad(45), 0)
			local cf = CFrame.new(center + turn:VectorToWorldSpace(sp.offset * size))
				* CFrame.Angles(0, yaw + rng:range(-1, 1), 0)
				* tilt
			p = Kit.part(model, "SkyrootLeaves", Vector3.new(e, e * 0.85, e), cf, color, Enum.Material.SmoothPlastic)
		end
		Kit.decor(p)
		table.insert(out, p)
	end
	return out
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

---------------------------------------------------------------------------
-- The Skyroot
---------------------------------------------------------------------------

-- The Skyroot: a braided trunk from the ground (y = 0 at the origin) up to
-- `height`, flaring into buttress roots, splitting into great limbs that
-- cradle the main isle on top and reach out under the others, and a canopy
-- of pale gold leaves under the isles.
--   isles: isle centres relative to the origin (the main isle, straight
--     above the trunk, may be included or not); a limb grows to the
--     underside of each outer one. Without it, three limbs reach out where
--     WorldPlan puts the isles.
--   clearDir: a horizontal direction kept clear of roots and leaves (the
--     gondola cable climbs the trunk on that side). Without it: the widest
--     gap between the isles.
--   fall: where a waterfall drops past the canopy (relative to the origin;
--     only X and Z matter): leaves part around it.
function IsleArt.Skyroot(height: number, isles: { Vector3 }?, clearDir: Vector3?, fall: Vector3?): Model
	local model = Kit.model("Skyroot")
	local rng = Kit.rng(5150)
	local H = height
	local R0 = math.clamp(H * 0.056, 14, 40) -- trunk radius at the ground
	local Rt = R0 * 0.48 -- where the limbs split off
	local Hs = H - math.clamp(H * 0.16, 30, 115) -- the split
	local mainR = 50 -- the main isle (WorldPlan): its top is 12 above H
	local outerR = 40
	local leafLimit = H - 4

	-- The outer isles (relative centres), and the clear side.
	local outer: { Vector3 } = {}
	local mainTop = H + 12
	if isles then
		for _, p in ipairs(isles) do
			if Vector3.new(p.X, 0, p.Z).Magnitude < 30 then
				mainTop = p.Y
			else
				table.insert(outer, p)
			end
		end
	end
	local clear: Vector3? = if clearDir then flat(clearDir) else nil
	if #outer == 0 then
		-- Where WorldPlan puts them: 70, 180 and 290 degrees round from the
		-- clear side, a sixth of the height out, a little above the main isle.
		local base = if clear then angleOf(clear) else 0
		for i, turn in ipairs({ 70, 180, 290 }) do
			table.insert(outer, polar(base + math.rad(turn), H * 0.17, mainTop + ({ 5, -5, 10 })[i]))
		end
	end
	-- The gaps between the outer isles (by angle); the widest is the clear
	-- side unless one was given.
	local isleAngles: { number } = {}
	for _, p in ipairs(outer) do
		table.insert(isleAngles, angleOf(p))
	end
	table.sort(isleAngles)
	local gaps: { { mid: number, width: number } } = {}
	for i, a in ipairs(isleAngles) do
		local b = if i == #isleAngles then isleAngles[1] + math.pi * 2 else isleAngles[i + 1]
		table.insert(gaps, { mid = (a + b) / 2, width = b - a })
	end
	if not clear and #gaps >= 2 then
		local widest = gaps[1]
		for _, g in ipairs(gaps) do
			if g.width > widest.width then
				widest = g
			end
		end
		clear = polar(widest.mid, 1, 0)
	end
	local clearAngle = if clear then angleOf(clear) else rng:range(0, math.pi * 2)
	local function inClear(angle: number, degrees: number): boolean
		return clear ~= nil and angleGap(angle, clearAngle) < math.rad(degrees)
	end

	-- The trunk's axis sways a little (sideways to the clear side) and its
	-- radius tapers, flaring at the foot.
	local swayDir = polar(clearAngle + math.pi / 2, 1, 0)
	local function axisAt(y: number): Vector3
		local t = math.clamp(y / Hs, 0, 1)
		return swayDir * (math.sin(t * math.pi) * R0 * 0.22) + Vector3.new(0, y, 0)
	end
	local function radiusAt(y: number): number
		local t = math.clamp(y / Hs, 0, 1)
		local flare = math.max(0, 1 - math.max(y, 0) / (R0 * 1.8))
		return R0 + (Rt - R0) * t ^ 0.75 + R0 * 0.4 * flare * flare
	end

	-- The core: a stack of tapering cylinders, mostly hidden by the strands.
	local cuts = { -6, 0.1, 0.27, 0.45, 0.63, 0.82, 1.0 }
	for i = 1, #cuts - 1 do
		local y0 = if i == 1 then cuts[1] else cuts[i] * Hs
		local y1 = cuts[i + 1] * Hs
		local d = 2 * 0.66 * radiusAt((y0 + y1) / 2)
		local seg = limb(model, if i == 1 then "SkyrootTrunk" else "SkyrootCore", axisAt(y0), axisAt(y1), d, CORE, 1.5)
		seg.CanTouch = false
		if i == 1 then
			model.PrimaryPart = seg
		end
	end

	-- Five strands braided round the core; each flares into a root at the
	-- foot. They sit either side of the clear side, so a groove (and the
	-- hollow) faces the gondola.
	local S = 5
	local twist = math.pi * 0.75
	local tops: { { point: Vector3, angle: number, diameter: number } } = {}
	local bases: { number } = {}
	for k = 0, S - 1 do
		local phi = clearAngle + math.pi / S + k * math.pi * 2 / S
		table.insert(bases, phi)
		local prev: Vector3? = nil
		local prevD = 0
		local J = 5
		for j = 0, J do
			local f = (j / J) ^ 1.2
			local y = -4 + f * (Hs + 4)
			local a = phi + twist * f
			local rho = if j == 0 then 0.95 * radiusAt(0) else 0.6 * radiusAt(y)
			local d = 0.82 * radiusAt(y)
			local pt = axisAt(y) + polar(a, rho, 0)
			if prev then
				limb(model, "SkyrootBark", prev, pt, (prevD + d) / 2 * 0.95, BARK[k % #BARK + 1]).CanTouch = false
			end
			prev, prevD = pt, d
			if j == J then
				table.insert(tops, { point = pt, angle = a, diameter = d })
			end
		end
	end

	-- Buttress fins, and roots running out across the ground (none on the
	-- clear side, where the gondola's base station stands).
	for k, phi in ipairs(bases) do
		local finH = R0 * rng:range(1.0, 1.35)
		local finL = R0 * rng:range(0.85, 1.1) * (if inClear(phi, 42) then 0.6 else 1) -- short by the station
		Kit.wedge(
			model,
			if k == 1 then "SkyrootRoots" else "SkyrootRoot",
			Vector3.new(R0 * 0.42, finH, finL),
			CFrame.Angles(0, -phi - math.pi / 2, 0) * CFrame.new(0, finH / 2 - 1, -(R0 * 1.05 + finL / 2)),
			ROOT,
			Enum.Material.Wood
		).CanTouch =
			false
		if not inClear(phi, 42) then
			local a1 = phi + rng:range(-0.12, 0.12)
			local p0 = polar(a1, R0 * 1.6, 3)
			local p1 = polar(a1 + rng:range(-0.2, 0.2), R0 * rng:range(2.1, 2.4), -1)
			local p2 = polar(a1 + rng:range(-0.35, 0.35), R0 * rng:range(2.55, 2.8), -6)
			limb(model, "SkyrootRoot", p0, p1, R0 * 0.36, ROOT).CanTouch = false
			Kit.decor(limb(model, "SkyrootRoot", p1, p2, R0 * 0.22, ROOT))
		end
	end

	-- A hollow at the foot, facing the clear side: dark, with glowing
	-- mushrooms and a warm light inside.
	do
		local y = R0 * 0.32
		local at = axisAt(y) + polar(clearAngle, 0.66 * radiusAt(y) + 1, 0)
		local facing = lookAt(at, at + polar(clearAngle, 1, 0))
		Kit.decor(
			Kit.ellipsoid(
				model,
				"SkyrootHollow",
				Vector3.new(R0 * 0.38, R0 * 0.62, R0 * 0.3),
				facing,
				hex("#2A1D13"),
				Enum.Material.SmoothPlastic
			)
		)
		for i, offset in ipairs({ -1, 1 }) do
			local cap = Kit.ball(
				model,
				"HollowMushroom",
				R0 * (if i == 1 then 0.07 else 0.05),
				facing * CFrame.new(offset * R0 * 0.07, -R0 * 0.24, -R0 * 0.1),
				if i == 1 then GOLD else hex("#9FF2E4"),
				Enum.Material.Neon
			)
			Kit.decor(cap, false)
			if i == 1 then
				light(cap, hex("#FFD58A"), 26, 1.6)
			end
		end
	end

	-- Knots and bracket fungi on the strands: details you see looking up.
	for i = 1, 5 do
		local k = rng:int(1, S)
		local y = if i <= 2 then rng:range(0.2, 0.7) * Hs else rng:range(R0 * 2, R0 * 5)
		local f = math.clamp((y + 4) / (Hs + 4), 0, 1)
		local a = bases[k] + twist * f + rng:range(-0.25, 0.25)
		local surface = radiusAt(y)
		if i <= 2 then
			local d = radiusAt(y) * 0.5
			Kit.decor(
				Kit.ellipsoid(
					model,
					"SkyrootKnot",
					Vector3.new(d, d * 1.3, d * 0.7),
					lookAt(axisAt(y) + polar(a, surface - d * 0.18, 0), axisAt(y) + polar(a, surface * 2, 0)),
					hex("#5F4430"),
					Enum.Material.Wood
				)
			)
		else
			local d = R0 * rng:range(0.22, 0.34)
			Kit.decor(
				Kit.cylinder(
					model,
					"SkyrootFungus",
					d * 0.12,
					d,
					CFrame.new(axisAt(y) + polar(a, surface - d * 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					if i % 2 == 0 then hex("#EBC892") else hex("#DCA46A"),
					Enum.Material.SmoothPlastic
				)
			)
		end
	end

	-- Limbs. Each outer isle takes the strand whose top points closest to it.
	local used: { [number]: boolean } = {}
	local leaves: { { center: Vector3, size: number } } = {}
	local function leafAt(center: Vector3, size: number)
		table.insert(leaves, { center = center, size = size })
	end
	for _, P in ipairs(outer) do
		local u = flat(P) :: Vector3
		local perp = Vector3.new(-u.Z, 0, u.X)
		local rho = Vector3.new(P.X, 0, P.Z).Magnitude
		local best, bestGap = 1, math.huge
		for k, top in ipairs(tops) do
			local gap = angleGap(top.angle, angleOf(u))
			if not used[k] and gap < bestGap then
				best, bestGap = k, gap
			end
		end
		used[best] = true
		local start = tops[best]
		local rise = P.Y - Hs
		local q1 = u * (rho * 0.36) + Vector3.new(0, Hs + rise * 0.1, 0)
		local q2 = u * (rho * 0.7) + Vector3.new(0, Hs + rise * 0.42, 0)
		local tip = u * (rho - 7) + Vector3.new(0, P.Y - outerR * DEPTH * 0.5, 0)
		local d = start.diameter * 1.25
		Kit.decor(limb(model, "SkyrootLimb", start.point, q1, d, BARK[1]))
		Kit.decor(limb(model, "SkyrootLimb", q1, q2, d * 0.82, BARK[2]))
		Kit.decor(limb(model, "SkyrootLimb", q2, tip, d * 0.62, BARK[3]))
		for _, side in ipairs({ -1, 1 }) do
			local fork = u * (rho - 3) + perp * (side * outerR * 0.38) + Vector3.new(0, P.Y - outerR * DEPTH * 0.56, 0)
			Kit.decor(limb(model, "SkyrootLimb", q2, fork, d * 0.42, BARK[2]))
		end
		-- Leaves along the limb and nestled under the isle (their tops
		-- reach the isle's tip, never its top).
		leafAt(q1 + Vector3.new(0, R0 * 0.3, 0) + perp * rng:range(-6, 6), R0 * 1.6)
		leafAt(u * (rho - 6) + perp * (outerR * 0.42) + Vector3.new(0, P.Y - outerR * 1.55, 0), R0 * 1.85)
		leafAt(u * (rho - 14) - perp * (outerR * 0.45) + Vector3.new(0, P.Y - outerR * 1.75, 0), R0 * 1.7)
	end

	-- The crown cradling the main isle: the free strands and three more
	-- limbs from the core's top rise to the rock under its middle.
	local cradle: { { from: Vector3, angle: number, diameter: number } } = {}
	for k, top in ipairs(tops) do
		if not used[k] then
			table.insert(cradle, { from = top.point, angle = top.angle, diameter = top.diameter })
		end
	end
	local coreTop = axisAt(Hs)
	for i = 1, 3 do
		local a = clearAngle + math.pi / 3 + (i - 1) * math.pi * 2 / 3 + rng:range(-0.2, 0.2)
		table.insert(cradle, { from = coreTop + polar(a, Rt * 0.3, -Rt * 0.5), angle = a, diameter = Rt * 1.1 })
	end
	for _, c in ipairs(cradle) do
		-- Up to just under the isle's point, then spreading along its
		-- underside like fingers cupping it.
		local elbow = polar(c.angle, mainR * 0.24, mainTop - mainR * DEPTH * 1.1)
		local tip = polar(c.angle, mainR * 0.66, mainTop - mainR * 0.4)
		Kit.decor(limb(model, "SkyrootLimb", c.from, elbow, c.diameter * 1.05, BARK[3]))
		Kit.decor(limb(model, "SkyrootLimb", elbow, tip, c.diameter * 0.8, BARK[1]))
	end

	-- Spreading limbs into the gaps between the isles carry the outer
	-- canopy. On the clear side the limb swings well off the gondola's
	-- line and runs lower, under the cable that comes down from the top
	-- station toward town.
	for _, g in ipairs(gaps) do
		local low = inClear(g.mid, 35)
		local a = g.mid + (if low then 0.8 else 0)
		local y0 = Hs - R0 * (if low then 2.6 else 1.4)
		local from = axisAt(y0) + polar(a, radiusAt(y0) * 0.5, 0)
		local elbow = polar(a, H * 0.11, y0 + R0 * (if low then 0.3 else 0.8))
		local tip = polar(a + rng:range(-0.1, 0.1), H * 0.25, y0 + R0 * (if low then 0.6 else 1.5))
		Kit.decor(limb(model, "SkyrootLimb", from, elbow, Rt * 1.1, BARK[2]))
		Kit.decor(limb(model, "SkyrootLimb", elbow, tip, Rt * 0.8, BARK[1]))
		local side = polar(a + math.pi / 2, 1, 0)
		local s = if low then 2.0 else 2.4
		leafAt(tip + Vector3.new(0, R0 * 0.25, 0), R0 * s)
		leafAt((elbow + tip) / 2 + side * R0 * 1.2 + Vector3.new(0, R0 * 0.2, 0), R0 * (s - 0.2))
		if not low then
			leafAt((elbow + tip) / 2 - side * R0 * 1.3 - Vector3.new(0, R0 * 0.3, 0), R0 * (s - 0.35))
		end
	end

	-- A ring of clusters tucked under the main isle's rim, and two either
	-- side of the gondola's line so the crown stays full seen from town.
	for i = 1, 6 do
		local a = clearAngle + (i - 0.5) / 6 * math.pi * 2 + rng:range(-0.12, 0.12)
		leafAt(polar(a, mainR * rng:range(1.15, 1.4), Hs + R0 * rng:range(0.5, 1.0)), R0 * rng:range(1.9, 2.25))
	end
	for _, s in ipairs({ -1, 1 }) do
		leafAt(polar(clearAngle + s * 0.95, mainR * 2, Hs - R0 * 0.5), R0 * 2)
	end

	-- A lower tier of three limbs, each ending in a tuft of leaves: from
	-- afar the crown steps down the trunk like a giant bonsai's.
	for i = 1, 3 do
		local a = clearAngle + math.pi * (0.55 + (i - 1) * 0.45) + rng:range(-0.15, 0.15)
		local y0 = H * (0.48 + i * 0.06)
		local from = axisAt(y0) + polar(a, radiusAt(y0) * 0.55, 0)
		local elbow = axisAt(y0) + polar(a, H * 0.075, R0 * 0.6)
		local tip = polar(a, H * rng:range(0.13, 0.16), y0 + R0 * 1.3)
		Kit.decor(limb(model, "SkyrootLimb", from, elbow, Rt * 0.85, BARK[3]))
		Kit.decor(limb(model, "SkyrootLimb", elbow, tip, Rt * 0.6, BARK[2]))
		leafAt(tip + Vector3.new(0, R0 * 0.3, 0), R0 * 1.8)
		leafAt((elbow + tip) / 2 + polar(a + math.pi / 2, R0 * 0.9, R0 * 0.35), R0 * 1.35)
	end

	-- Leaves part round the waterfall's column.
	local fallAt: Vector3? = if fall then Vector3.new(fall.X, 0, fall.Z) else nil
	local function partForFall(c: Vector3, size: number): Vector3
		if not fallAt then
			return c
		end
		local away = Vector3.new(c.X, 0, c.Z) - fallAt
		local room = size * 0.75 + 8
		if away.Magnitude >= room then
			return c
		end
		local dir = if away.Magnitude > 0.1 then away.Unit else (flat(c) or Vector3.xAxis)
		local moved = fallAt + dir * room
		return Vector3.new(moved.X, c.Y, moved.Z)
	end

	-- On the clear side, leaves keep away from both cables: the one that
	-- climbs beside the trunk (from the base station about 1.25 isle radii
	-- out to the top station on the main isle's rim) and the one that runs
	-- down toward town (somewhere between these two slopes).
	local cableBase = polar(clearAngle, mainR * 1.24, 8)
	local cableTop = polar(clearAngle, mainR * 0.88, mainTop + 9)
	local cableOut = {
		polar(clearAngle, mainR * 9, mainTop + 9 - mainR * 8.12 * 0.4),
		polar(clearAngle, mainR * 9, mainTop + 9 - mainR * 8.12 * 0.65),
	}
	local function nearSegment(p: Vector3, a: Vector3, b: Vector3): number
		local ab = b - a
		local f = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		return (p - (a + ab * f)).Magnitude
	end
	local function blocksCable(c: Vector3, size: number): boolean
		if not clear then
			return false
		end
		local room = size * 0.8 + 8
		if nearSegment(c, cableBase, cableTop) < room then
			return true
		end
		for _, out in ipairs(cableOut) do
			if nearSegment(c, cableTop, out) < room then
				return true
			end
		end
		return false
	end

	-- Build them: soft pale gold-green clusters, every third with a glowing
	-- heart (some trailing Lumenwood motes); none above the limit: under H
	-- everywhere, and 25 under an isle's top over its footprint.
	local hanging: { Vector3 } = {}
	local glowing = 0
	for i, leaf in ipairs(leaves) do
		local c = partForFall(leaf.center, leaf.size)
		if not blocksCable(c, leaf.size) then
			local parts = leafCluster(model, c, leaf.size, rng)
			if i % 3 == 0 then
				local heart = parts[#parts]
				heart.Material = Enum.Material.Neon
				heart.Color = GOLD
				glowing += 1
				if glowing % 2 == 1 then
					motes(heart, 2.4, 4)
				end
			end
			local limit = leafLimit
			local reach = leaf.size * 0.75
			if Vector3.new(c.X, 0, c.Z).Magnitude - reach < mainR + 6 then
				limit = math.min(limit, mainTop - 25)
			end
			for _, P in ipairs(outer) do
				if Vector3.new(c.X - P.X, 0, c.Z - P.Z).Magnitude - reach < outerR + 6 then
					limit = math.min(limit, P.Y - 25)
				end
			end
			local highest = -math.huge
			for _, p in ipairs(parts) do
				highest = math.max(highest, IsleArt.TopOf(p))
			end
			if highest > limit then
				for _, p in ipairs(parts) do
					p.CFrame = p.CFrame + Vector3.new(0, limit - highest, 0)
				end
			end
			table.insert(hanging, parts[1].CFrame.Position - Vector3.new(0, leaf.size * 0.3, 0))
		end
	end

	-- Vines hanging from the canopy with glowing pods: lanterns overhead.
	for i = 1, 3 do
		local from = hanging[(i * 5) % #hanging + 1]
		if from then
			local to = from - Vector3.new(rng:range(-2, 2), rng:range(R0 * 0.8, R0 * 1.7), rng:range(-2, 2))
			Kit.decor(
				rod(model, "SkyrootVine", from, to, R0 * 0.03, hex("#93B560"), Enum.Material.SmoothPlastic),
				false
			)
			Kit.decor(Kit.ball(model, "SkyrootPod", R0 * 0.1, CFrame.new(to), GOLD, Enum.Material.Neon), false)
		end
	end

	return model
end

---------------------------------------------------------------------------
-- A floating isle
---------------------------------------------------------------------------

export type IsleOptions = {
	-- A horizontal direction: a spring pool and a stream run to the rim
	-- there, where a Waterfall pours off (MapBuilder places it).
	spout: Vector3?,
	-- Points on the top (relative to the centre) that stay free of
	-- decoration and drifting rocks: bridge ends, chutes, stations.
	clear: { Vector3 }?,
}

-- A band of tilted slabs: a faceted ring whose faces run from distance
-- rTop at yTop down to rBot at yBot, `sides` faces, `thick` deep; each
-- face's ends wander up to `jitter` studs in or out (craggy, not crumpled).
local function band(
	model: Model,
	name: string,
	yTop: number,
	yBot: number,
	rTop: number,
	rBot: number,
	sides: number,
	thick: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material,
	phase: number,
	jitter: number
)
	for i = 1, sides do
		local a = phase + (i - 0.5) / sides * math.pi * 2
		local out = polar(a, 1, 0)
		local tangent = Vector3.new(-out.Z, 0, out.X)
		local top = out * (rTop + rng:range(-0.4, 1) * jitter) + Vector3.new(0, yTop, 0)
		local bot = out * (rBot + rng:range(-1, 1) * jitter * 1.5) + Vector3.new(0, yBot, 0)
		local up = (top - bot).Unit
		local normal = tangent:Cross(up)
		if normal:Dot(out) < 0 then
			normal = -normal
		end
		local width = 2 * rTop * math.tan(math.pi / sides) * 1.03
		local len = (top - bot).Magnitude + thick * 0.15
		Kit.decor(
			Kit.part(
				model,
				name,
				Vector3.new(width, len, thick),
				CFrame.fromMatrix((top + bot) / 2 - normal * (thick / 2), tangent, up),
				Kit.vary(colors[(i - 1) % #colors + 1], rng, 0.03),
				material
			)
		)
	end
end

-- A crystal shard `length` long growing from `base` along `dir`.
local function shard(model: Model, base: Vector3, dir: Vector3, length: number, width: number, glow: boolean): Part
	local side = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else dir:Cross(Vector3.yAxis).Unit
	local cf = CFrame.fromMatrix(base + dir * (length / 2), side, dir) * CFrame.Angles(0, math.pi / 4, 0)
	local p = Kit.part(
		model,
		"Crystal",
		Vector3.new(width, length, width),
		cf,
		if glow then CRYSTAL else CRYSTAL_GLASS,
		if glow then Enum.Material.Neon else Enum.Material.Glass
	)
	Kit.decor(p, false)
	if not glow then
		p.Transparency = 0.2
	end
	-- A chisel point.
	local tipLen = width * 1.3
	Kit.decor(
		Kit.wedge(
			model,
			"CrystalTip",
			Vector3.new(width, tipLen, width),
			cf * CFrame.new(0, length / 2 + tipLen / 2, 0),
			p.Color,
			p.Material
		),
		false
	).Transparency =
		p.Transparency
	return p
end

-- A floating island: its walkable top at y = 0 ("IsleTop", collides, the
-- PrimaryPart), a grassy faceted rim, an earth band, and a rocky underside
-- tapering to a point about 1.2 radii down, with dangling roots and vines,
-- glowing crystals, flowers near the rim and a few rocks drifting round it.
function IsleArt.Isle(radius: number, seed: number, options: IsleOptions?): Model
	local model = Kit.model("Isle")
	local rng = Kit.rng(seed * 31 + 7)
	local opts: IsleOptions = options or {}
	local r = radius
	local D = r * DEPTH

	local top = Kit.cylinder(
		model,
		"IsleTop",
		4,
		r * 2,
		CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		GRASS_TOP,
		Enum.Material.Grass
	)
	top.CanTouch = false
	model.PrimaryPart = top

	-- Where decoration mustn't go.
	local spoutAngle: number? = nil
	if opts.spout then
		local u = flat(opts.spout)
		if u then
			spoutAngle = angleOf(u)
		end
	end
	local clearPoints: { Vector3 } = opts.clear or {}
	local function nearSpout(a: number, degrees: number): boolean
		return spoutAngle ~= nil and angleGap(a, spoutAngle) < math.rad(degrees)
	end
	local function free(at: Vector3, room: number): boolean
		for _, c in ipairs(clearPoints) do
			if Vector3.new(at.X - c.X, 0, at.Z - c.Z).Magnitude < room then
				return false
			end
		end
		return not nearSpout(angleOf(at), 17)
	end
	local function freeAngle(a: number, degrees: number): boolean
		for _, c in ipairs(clearPoints) do
			if Vector3.new(c.X, 0, c.Z).Magnitude > 1 and angleGap(a, angleOf(c)) < math.rad(degrees) then
				return false
			end
		end
		return not nearSpout(a, degrees)
	end

	-- The grassy rim: a faceted bevel just outside the top's edge, never
	-- above it.
	local rimSides = math.clamp(math.floor(r / 4.5), 8, 14)
	local phase = rng:range(0, math.pi * 2)
	for i = 1, rimSides do
		local a = phase + (i - 0.5) / rimSides * math.pi * 2
		local out = polar(a, 1, 0)
		local width = 2 * (r + 1) * math.tan(math.pi / rimSides) * 1.04
		local tilt = math.rad(rng:range(14, 22))
		-- Drop it so its highest corner sits just under the top surface.
		local lift = 1.2 * math.cos(tilt) + 1.7 * math.sin(tilt)
		local at = out * (r - 0.6) + Vector3.new(0, -0.05 - lift, 0)
		Kit.decor(
			Kit.part(
				model,
				"IsleRim",
				Vector3.new(width, 2.4, 3.4),
				lookAt(at, at + out) * CFrame.Angles(tilt, 0, 0),
				Kit.vary(TURF[(i - 1) % #TURF + 1], rng, 0.03),
				Enum.Material.Grass
			)
		)
	end

	-- The earth band, then the rock tiers, then the tip.
	band(
		model,
		"IsleSoil",
		-3,
		-8,
		r,
		r * 0.975,
		math.max(12, rimSides + 2),
		4,
		rng,
		SOIL,
		Enum.Material.Ground,
		phase + 0.2,
		0
	)
	for t = 1, 3 do
		local a, b = PROFILE[t], PROFILE[t + 1]
		band(
			model,
			"IsleRock",
			if t == 1 then -7.5 else -a.depth * D + 0.6,
			-b.depth * D,
			r * a.radius,
			r * b.radius,
			({ 9, 8, 6 })[t],
			math.max(4, r * 0.16),
			rng,
			TIERS[t].colors,
			TIERS[t].material,
			rng:range(0, math.pi * 2),
			r * 0.025
		)
	end
	do
		local last = PROFILE[#PROFILE]
		local base = CFrame.new(0, -last.depth * D + 0.6, 0)
			* CFrame.Angles(math.pi + rng:range(-0.12, 0.12), rng:range(0, math.pi), rng:range(-0.12, 0.12))
		local jit: { number } = {}
		for i = 1, 5 do
			jit[i] = rng:range(0.92, 1.1)
		end
		local folder = Kit.model("IsleTip", model)
		Kit.cone(
			folder,
			base,
			r * last.radius * 1.08,
			D * (1 - last.depth) + 0.6,
			5,
			function(i: number): Color3
				return Kit.vary(TIP[(i - 1) % #TIP + 1], rng, 0.03)
			end,
			Enum.Material.Slate,
			1.2,
			function(i: number): number
				return jit[i]
			end
		)
	end

	-- Chunky boulders breaking up the tiers' outline.
	for _ = 1, 3 do
		local t = rng:range(0.12, 0.7)
		local a = rng:range(0, math.pi * 2)
		local s = r * rng:range(0.14, 0.22)
		local tier = if t < 0.33 then 1 elseif t < 0.6 then 2 else 3
		Kit.decor(
			Kit.part(
				model,
				"IsleBoulder",
				Vector3.new(s, s * 0.8, s),
				CFrame.new(polar(a, r * (0.95 - t * 0.85), -t * D))
					* CFrame.Angles(math.rad(35.26), a + math.rad(45), rng:range(-0.3, 0.3)),
				Kit.vary(TIERS[tier].colors[1], rng, 0.05),
				Enum.Material.Rock
			)
		)
	end

	-- Roots dangling from the earth band and the tiers, two from the tip;
	-- two of them are green vines.
	local rootStarts: { { at: Vector3, len: number } } = {}
	for i = 1, 4 do
		local a = phase + i * 1.55 + rng:range(-0.3, 0.3)
		local depth = ({ 6, 7, 0.33 * D, 0.6 * D })[i]
		local rad = r * ({ 0.93, 0.93, 0.72, 0.46 })[i]
		table.insert(rootStarts, { at = polar(a, rad, -depth), len = rng:range(8, 16) })
	end
	table.insert(rootStarts, { at = Vector3.new(r * 0.04, -D * 0.95, 0), len = rng:range(10, 16) })
	for i, root in ipairs(rootStarts) do
		local out = flat(root.at) or Vector3.xAxis
		local p1 = root.at + out * rng:range(0.5, 2) - Vector3.new(0, root.len * 0.55, 0)
		local p2 = p1 + Vector3.new(rng:range(-1.5, 1.5), -root.len * 0.45, rng:range(-1.5, 1.5))
		local vine = i == 2 or i == 4
		local name = if vine then "IsleVine" else "IsleRoot"
		local color = if vine then hex("#6E9E48") else hex("#6B4A30")
		Kit.decor(rod(model, name, root.at, p1, if vine then 0.5 else 1.3, color, Enum.Material.Wood), false)
		Kit.decor(rod(model, name, p1, p2, if vine then 0.4 else 0.8, color, Enum.Material.Wood), false)
	end

	-- Glowing crystals on the underside: two clusters.
	for c = 1, 2 do
		local a = phase + c * math.pi + rng:range(-0.5, 0.5)
		local t = if c == 1 then 0.47 else 0.7
		local base = polar(a, r * (if c == 1 then 0.6 else 0.36), -t * D)
		local out = polar(a, 1, 0)
		local dir = (out * 0.75 - Vector3.new(0, 0.66, 0)).Unit
		local big = shard(model, base, dir, r * 0.2, r * 0.06, true)
		if c == 1 then
			light(big, hex("#A8E8FF"), r * 0.7, 1.3)
		end
		local tangent = Vector3.new(-out.Z, 0, out.X)
		shard(model, base + tangent * r * 0.05, (dir + tangent * 0.6).Unit, r * 0.12, r * 0.045, false)
	end

	-- Small rocks drifting round the isle (below the bridges' decks, away
	-- from the chutes' flumes and the waterfall).
	local count = 2 + math.floor(seed) % 3
	local placed = 0
	for i = 1, 10 do
		if placed >= count then
			break
		end
		local a = phase + i * 2.39996
		if freeAngle(a, 28) then
			placed += 1
			local s = rng:range(2.5, 5.5)
			local at = polar(a, r + rng:range(7, 16), -rng:range(9, 24))
			Kit.decor(
				Kit.cylinder(
					model,
					"FloatingRock",
					0.9,
					s * 2,
					CFrame.new(at) * CFrame.Angles(rng:range(-0.1, 0.1), rng:range(0, 3), math.pi / 2),
					GRASS_TOP,
					Enum.Material.Grass
				)
			)
			Kit.decor(
				Kit.part(
					model,
					"FloatingRock",
					Vector3.new(s * 1.3, s * 1.3, s * 1.3),
					CFrame.new(at - Vector3.new(0, s * 0.75, 0))
						* CFrame.Angles(0, rng:range(0, 3), 0)
						* CFrame.Angles(math.rad(35.26 + 180), math.rad(45), 0),
					Kit.vary(TIERS[2].colors[1], rng, 0.05),
					Enum.Material.Rock
				)
			)
		end
	end

	-- Flowers, tufts, little bushes and stones near the rim (the middle
	-- stays open for trees, the forge and the stations).
	local decorCount = math.max(7, math.floor(r / 6))
	local FLOWERS = { hex("#FFF3B0"), hex("#FFFFFF"), hex("#CDB8F0"), hex("#A8D8F0"), hex("#FFD27A") }
	local BUSH = { hex("#8FBF55"), hex("#A2CC62"), hex("#7FB04C") }
	for i = 1, decorCount do
		local a = phase + (i - 0.5) / decorCount * math.pi * 2 + rng:range(-0.2, 0.2)
		local at = polar(a, r * rng:range(0.8, 0.92), 0)
		if free(at, 8) then
			local kind = rng:next()
			if kind < 0.4 then
				local petal = rng:pick(FLOWERS)
				for f = 1, 2 do
					local h = rng:range(0.8, 1.3)
					local p = at + polar(a + f * 2.2, 0.5, 0)
					Kit.decor(
						Kit.part(
							model,
							"IsleFlower",
							Vector3.new(0.14, h, 0.14),
							CFrame.new(p + Vector3.new(0, h / 2, 0)),
							hex("#6E9E48")
						),
						false
					)
					Kit.decor(
						Kit.part(
							model,
							"IsleFlower",
							Vector3.new(0.75, 0.18, 0.75),
							CFrame.new(p + Vector3.new(0, h, 0)) * CFrame.Angles(0, math.pi / 4 + a + f, 0),
							if f == 1 then petal else rng:pick(FLOWERS),
							Enum.Material.SmoothPlastic
						),
						false
					)
				end
			elseif kind < 0.7 then
				for b = 1, 3 do
					local h = rng:range(1.0, 1.7)
					Kit.decor(
						Kit.wedge(
							model,
							"IsleGrass",
							Vector3.new(0.14, h, 0.55),
							CFrame.new(at + polar(a + b * 2.1, 0.3, h / 2))
								* CFrame.Angles(0, a + b * 2.1, 0)
								* CFrame.Angles(rng:range(-0.3, 0.1), 0, rng:range(-0.25, 0.25)),
							Kit.vary(TURF[b], rng, 0.05),
							Enum.Material.SmoothPlastic
						),
						false
					)
				end
			elseif kind < 0.85 then
				for s = 1, 2 do
					local size = if s == 1 then rng:range(1.3, 2.1) else rng:range(0.6, 1.0)
					Kit.decor(
						Kit.part(
							model,
							"IsleStone",
							Vector3.new(size, size * 0.65, size * 0.9),
							CFrame.new(at + polar(a + 1.6, (s - 1) * 1.3, size * 0.2))
								* CFrame.Angles(rng:range(-0.3, 0.3), rng:range(0, 3), rng:range(-0.2, 0.2)),
							Kit.vary(TIERS[1].colors[2], rng, 0.05),
							Enum.Material.Rock
						),
						false
					)
				end
			else
				for s = 1, 2 do
					local size = if s == 1 then rng:range(1.8, 2.6) else rng:range(1.1, 1.6)
					Kit.decor(
						Kit.part(
							model,
							"IsleBush",
							Vector3.new(size, size * 0.8, size),
							CFrame.new(at + polar(a - 1.4, (s - 1) * size, size * 0.42))
								* CFrame.Angles(math.rad(35.26), rng:range(0, 3), 0),
							Kit.vary(BUSH[s], rng, 0.05),
							Enum.Material.SmoothPlastic
						),
						false
					)
				end
			end
		end
	end

	-- The spring: a pool and a stream running to the rim, where the
	-- waterfall pours off.
	if spoutAngle then
		local u = polar(spoutAngle, 1, 0)
		local perp = Vector3.new(-u.Z, 0, u.X)
		local poolAt = u * (r * 0.72)
		local pool = Kit.cylinder(
			model,
			"SpringPool",
			0.3,
			7,
			CFrame.new(poolAt + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			hex("#7FCBEF"),
			Enum.Material.Glass
		)
		Kit.decor(pool, false)
		pool.Transparency = 0.15
		local stream = beam(
			model,
			"Stream",
			poolAt + Vector3.new(0, 0.07, 0),
			u * (r + 0.8) + Vector3.new(0, 0.07, 0),
			2.6,
			0.3,
			hex("#8AD2F2"),
			Enum.Material.Glass
		)
		Kit.decor(stream, false)
		stream.Transparency = 0.15
		for _, side in ipairs({ -1, 1 }) do
			local s = rng:range(1.3, 1.9)
			Kit.decor(
				Kit.part(
					model,
					"SpringStone",
					Vector3.new(s, s * 0.7, s),
					CFrame.new(u * (r - 1) + perp * (side * 2.4) + Vector3.new(0, s * 0.25, 0))
						* CFrame.Angles(0.2, rng:range(0, 3), 0.15),
					Kit.vary(TIERS[1].colors[1], rng, 0.05),
					Enum.Material.Rock
				),
				false
			)
		end
		Kit.decor(
			Kit.ellipsoid(
				model,
				"SpringFoam",
				Vector3.new(3, 0.35, 2.4),
				CFrame.new(poolAt + u * 2.6 + Vector3.new(0, 0.2, 0)),
				Color3.new(1, 1, 1),
				Enum.Material.SmoothPlastic
			),
			false
		)
	end

	return model
end

---------------------------------------------------------------------------
-- Waterfall, clouds, lanterns
---------------------------------------------------------------------------

-- WLD-05: the waterfall's particle numbers (IsleArt.spec pins them; the
-- client halves every rate on low quality: see FALL_RATE_ATTRIBUTE).
IsleArt.FallStreams = 3 -- curtain emitters across the width
IsleArt.FallStreamRate = 60 -- particles a second, each stream
IsleArt.FallSpeed = { 55, 65 } -- studs a second, straight down
IsleArt.FallSheet = 40 -- studs: the one translucent sheet, at the top only
IsleArt.FallMistBand = { 0.6, 0.9 } -- the mist band, as fractions of the fall from the lip
-- Every waterfall emitter carries its full (high quality) rate in this
-- attribute; WeatherController sets Rate = BaseRate x the Quality tier's
-- WeatherRate (WeatherSchedule.MapEmitterRate), so phones get half.
IsleArt.FallRateAttribute = "BaseRate"

local FALL_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- A Rate the client can scale (see IsleArt.FallRateAttribute).
local function setRate(e: ParticleEmitter, rate: number)
	e.Rate = rate
	e:SetAttribute(IsleArt.FallRateAttribute, rate)
end

-- A stylized waterfall that moves (WLD-05): a foam lip and one translucent
-- sheet for the top 40 studs, then a curtain of falling water streaks
-- (several emitters across the width, on an invisible "WaterfallCurtain"
-- spanning the height) that frays into a mist band ("WaterfallSpray",
-- 60-90% of the way down) and lands in foam and spray ("WaterfallMist").
-- The origin is the top lip; the water falls to y = -height in front of it
-- (-Z), arriving from +Z (the isle side).
function IsleArt.Waterfall(height: number, width: number): Model
	local model = Kit.model("Waterfall")
	local rng = Kit.rng(math.floor(height + width * 7))
	local w = width
	local deep = hex("#79C3EA")
	local pale = hex("#BFE6FA")
	local white = Color3.new(1, 1, 1)
	local front = -w * 0.4 -- z of the falling water's face

	-- The lip: water curling over the edge, and foam where it breaks.
	local lip =
		Kit.wedge(model, "WaterfallLip", Vector3.new(w, 2.4, 3), CFrame.new(0, -1.2, 1.5), pale, Enum.Material.Glass)
	Kit.decor(lip, false)
	lip.Transparency = 0.2
	for i = 1, 3 do
		local s = w * rng:range(0.28, 0.4)
		local foam = Kit.part(
			model,
			"Foam",
			Vector3.new(s, s * 0.55, s * 0.8),
			CFrame.new((i - 2) * w * 0.32, -0.6, -0.4)
				* CFrame.Angles(math.rad(35.26), math.rad(45) + rng:range(-0.3, 0.3), 0),
			white,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(foam, false)
		foam.Transparency = 0.05
	end

	-- One translucent sheet, for the top stretch only: the water leaving
	-- the lip as a glassy tongue before it breaks into streaks.
	local sheetHeight = math.min(IsleArt.FallSheet, height)
	local sheet = Kit.part(
		model,
		"Waterfall",
		Vector3.new(w, sheetHeight, w * 0.4),
		CFrame.new(0, -sheetHeight / 2, -w * 0.3),
		deep,
		Enum.Material.Glass
	)
	Kit.decor(sheet, false)
	sheet.Transparency = 0.35

	-- The curtain: an invisible part spanning the fall, with a row of
	-- emitters along its top edge pouring soft streaks straight down. Each
	-- streak lives as long as the fall takes at the middle speed, so the
	-- water reaches the foot (the mist band and the spray hide the ragged
	-- end), and a small spread widens the column as it falls.
	local curtain = Kit.part(
		model,
		"WaterfallCurtain",
		Vector3.new(w, height, 1),
		CFrame.new(0, -height / 2, front),
		white,
		Enum.Material.SmoothPlastic
	)
	Kit.decor(curtain, false)
	curtain.Transparency = 1
	local speedLow, speedHigh = IsleArt.FallSpeed[1], IsleArt.FallSpeed[2]
	local fallTime = height / ((speedLow + speedHigh) / 2)
	local streams = IsleArt.FallStreams
	for i = 1, streams do
		local at = Instance.new("Attachment")
		at.Name = "Stream" .. i
		at.CFrame = CFrame.new(((i - 0.5) / streams - 0.5) * w * 0.8, height / 2 - 0.5, 0)
		at.Parent = curtain
		local e = Instance.new("ParticleEmitter")
		e.Name = "Curtain"
		e.Texture = FALL_TEXTURE
		e.Color = ColorSequence.new(hex("#DDF2FF"), hex("#F4FBFF"))
		e.LightEmission = 0.3
		e.LightInfluence = 0.6
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		e.Speed = NumberRange.new(speedLow, speedHigh)
		e.SpreadAngle = Vector2.new(1, 1)
		e.Lifetime = NumberRange.new(fallTime * 0.97, fallTime)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, w * 0.35),
			NumberSequenceKeypoint.new(1, w * 0.6),
		})
		e.Squash = NumberSequence.new({ -- stretched tall: streaks, not puffs
			NumberSequenceKeypoint.new(0, 1.6),
			NumberSequenceKeypoint.new(1, 1.1),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.05, 0.3),
			NumberSequenceKeypoint.new(0.85, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Rotation = NumberRange.new(-8, 8)
		setRate(e, IsleArt.FallStreamRate)
		e.Parent = at
	end

	-- The mist band: the long fall frays into spray before it lands.
	local mistBand = IsleArt.FallMistBand
	if height > 40 then
		local bandHeight = height * (mistBand[2] - mistBand[1])
		local veil = Kit.part(
			model,
			"WaterfallSpray",
			Vector3.new(w * 1.6, bandHeight, w * 1.2),
			CFrame.new(0, -height * (mistBand[1] + mistBand[2]) / 2, front),
			white,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(veil, false)
		veil.Transparency = 1
		local e = emitter(veil, "Veil")
		e.Texture = FALL_TEXTURE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Color = ColorSequence.new(hex("#F2FAFF"))
		e.LightEmission = 0.3
		e.LightInfluence = 0.7
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, w * 0.8), NumberSequenceKeypoint.new(1, w * 1.6) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(2.5, 3.5)
		e.Speed = NumberRange.new(4, 9)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-20, 20)
		setRate(e, math.clamp(math.floor(bandHeight / 10), 4, 24))
	end

	-- The foot: foam on the water, spray bursting out and mist rising.
	local splashY = -height
	Kit.decor(
		Kit.cylinder(
			model,
			"Foam",
			0.4,
			w * 1.7,
			CFrame.new(0, splashY + 0.2, front) * CFrame.Angles(0, 0, math.pi / 2),
			white,
			Enum.Material.SmoothPlastic
		),
		false
	).Transparency =
		0.35
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2 + rng:range(-0.3, 0.3)
		local s = w * rng:range(0.25, 0.4)
		Kit.decor(
			Kit.part(
				model,
				"Foam",
				Vector3.new(s, s * 0.6, s),
				CFrame.new(math.cos(a) * w * 0.8, splashY + s * 0.15, front + math.sin(a) * w * 0.8)
					* CFrame.Angles(math.rad(35.26), a, 0),
				white,
				Enum.Material.SmoothPlastic
			),
			false
		)
	end
	local mist = Kit.part(
		model,
		"WaterfallMist",
		Vector3.new(w * 1.6, 1, w * 1.6),
		CFrame.new(0, splashY + 1, front),
		white,
		Enum.Material.SmoothPlastic
	)
	Kit.decor(mist, false)
	mist.Transparency = 1
	local e = emitter(mist, "Mist")
	e.Texture = FALL_TEXTURE
	e.Color = ColorSequence.new(hex("#F2FAFF"))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, w * 0.6), NumberSequenceKeypoint.new(1, w * 2.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(3, 5)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(70, 70)
	e.LightInfluence = 0.7
	setRate(e, 8)
	local spray = emitter(mist, "Spray")
	spray.Texture = FALL_TEXTURE
	spray.Color = ColorSequence.new(white)
	spray.LightEmission = 0.3
	spray.LightInfluence = 0.6
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, w * 0.2), NumberSequenceKeypoint.new(1, w * 0.5) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.8, 1.4)
	spray.Speed = NumberRange.new(10, 18)
	spray.SpreadAngle = Vector2.new(55, 55)
	spray.Acceleration = Vector3.new(0, -25, 0)
	setRate(spray, 24)
	return model
end

-- A soft cloud bank about `size` studs long (along X), its base at y = 0:
-- puffy white ellipsoids, the big one in the middle, smaller toward the
-- ends, a few in front and behind for depth.
function IsleArt.CloudBank(size: number, seed: number): Model
	local model = Kit.model("CloudBank")
	local rng = Kit.rng(seed * 13 + 5)
	local L = size
	local WHITE = { hex("#FFFFFF"), hex("#FFFCF4"), hex("#FBFBFF"), hex("#F6F7FC") }
	local puffs = {
		{ x = 0, z = 0, d = 0.44 },
		{ x = 0.22, z = 0.04, d = 0.32 },
		{ x = -0.23, z = -0.04, d = 0.33 },
		{ x = 0.4, z = -0.02, d = 0.21 },
		{ x = -0.41, z = 0.03, d = 0.23 },
	}
	for _ = 1, rng:int(1, 3) do
		table.insert(
			puffs,
			{ x = rng:range(-0.24, 0.24), z = rng:sign() * rng:range(0.12, 0.18), d = rng:range(0.22, 0.28) }
		)
	end
	for i, p in ipairs(puffs) do
		local d = L * p.d * rng:range(0.9, 1.1)
		local puff = Kit.ellipsoid(
			model,
			"Cloud",
			Vector3.new(d, d * 0.72, d * 0.85),
			CFrame.new((p.x + rng:range(-0.03, 0.03)) * L, d * 0.38, p.z * L),
			WHITE[(i - 1) % #WHITE + 1],
			Enum.Material.SmoothPlastic
		)
		Kit.decor(puff, false)
		puff.Transparency = if i == 1 then 0 else 0.03
	end
	return model
end

-- Where cloud banks drift round the Skyroot, relative to its foot (pure
-- layout, so MapBuilder and the preview agree): one under each outer isle,
-- a ring out beyond the canopy, and a lower ring the trunk rises through.
-- `isles` and `clearDir` are as for Skyroot; nothing goes on the clear
-- side (the gondola cables).
function IsleArt.CloudSpots(
	isles: { Vector3 },
	height: number,
	seed: number,
	clearDir: Vector3?
): { { cframe: CFrame, size: number } }
	local rng = Kit.rng(seed)
	local out: { { cframe: CFrame, size: number } } = {}
	local clearAngle: number? = nil
	if clearDir then
		local u = flat(clearDir)
		if u then
			clearAngle = angleOf(u)
		end
	end
	local function add(pos: Vector3, size: number)
		local a = angleOf(pos)
		if clearAngle and angleGap(a, clearAngle) < math.rad(32) then
			return
		end
		table.insert(
			out,
			{ cframe = CFrame.new(pos) * CFrame.Angles(0, -a + math.pi / 2 + rng:range(-0.4, 0.4), 0), size = size }
		)
	end
	for _, p in ipairs(isles) do
		local u = flat(p)
		if u then
			add(
				Vector3.new(p.X, 0, p.Z) + u * rng:range(10, 30) + Vector3.new(0, p.Y - rng:range(70, 95), 0),
				rng:range(70, 95)
			)
		end
	end
	for i = 1, 7 do
		local a = (i - 0.5) / 7 * math.pi * 2 + rng:range(-0.25, 0.25)
		add(polar(a, height * rng:range(0.26, 0.34), height * rng:range(0.78, 0.93)), rng:range(90, 140))
	end
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2 + rng:range(-0.3, 0.3)
		add(polar(a, height * rng:range(0.1, 0.17), height * rng:range(0.48, 0.58)), rng:range(60, 95))
	end
	return out
end

-- A crooked lantern post for the isles: bridge heads, the station, the
-- forge. Named parts: "LanternGlow" (Neon, has a PointLight).
function IsleArt.LanternPost(seed: number): Model
	local model = Kit.model("LanternPost")
	local rng = Kit.rng(seed * 17 + 3)
	local wood = hex("#8A6A48")
	Kit.decor(
		Kit.part(
			model,
			"PostStone",
			Vector3.new(1.8, 0.8, 1.8),
			CFrame.new(0, 0.3, 0) * CFrame.Angles(0, rng:range(0, 1.5), 0),
			TIERS[1].colors[1],
			Enum.Material.Rock
		),
		false
	)
	local top = Vector3.new(rng:range(-0.3, 0.3), 6.4, rng:range(-0.3, 0.3))
	rod(model, "Post", Vector3.new(0, 0.4, 0), top, 0.6, wood, Enum.Material.Wood).CanTouch = false
	local hook = top + Vector3.new(1.5, 0.35, 0)
	Kit.decor(rod(model, "PostArm", top - Vector3.new(0, 0.3, 0), hook, 0.35, wood, Enum.Material.Wood), false)
	Kit.decor(rod(model, "Chain", hook, hook - Vector3.new(0, 0.7, 0), 0.1, hex("#3A3432"), Enum.Material.Metal), false)
	Kit.lantern(model, CFrame.new(hook - Vector3.new(0, 1.5, 0)), 0.85).Color = hex("#FFE2A0")
	return model
end

return IsleArt
