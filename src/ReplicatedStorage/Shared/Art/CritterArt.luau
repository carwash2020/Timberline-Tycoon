--!strict
-- CritterArt: the world's small wildlife, part-built in the cozy low-poly
-- style (GAME_DESIGN §13, §16 "thriving groves come alive"): songbirds,
-- butterflies, rabbits, deer, ducks, fish, the Phantom Grove's wisps, the
-- Volcano's ember sprites, and firefly / mote clouds. Pure (see Kit), so
-- the preview (tools/preview/scenes/critters.luau) shows exactly what
-- AmbientLife animates. Critters exist only on clients and never collide.
--
-- Contract with AmbientLife:
--   * Each builder returns a Model around the origin, front facing -Z.
--     Walkers stand on y = 0; flyers and swimmers are centred on it.
--   * Parts that move on their own carry attributes:
--       Anim  = "WingL" | "WingR"  flap about the body's long (Z) axis
--               "Head"             nods about X (pecking, grazing, dipping)
--               "Leg"              swings about X (walking, bounding)
--               "Tail"             wags about Y
--       Hinge = Vector3            the pivot, in model space
--       Phase = number             0..1, legs only (diagonal pairs trot)
--     Everything else moves rigidly with the body.
--   * Particle clouds (Fireflies, Motes) are one invisible part named
--     "Cloud" holding a ParticleEmitter named "Particles"; the Splash is a
--     part named "Splash" with one to Emit() from.
--   * The model's "Critter" attribute names its kind.
--   * Wings are built spread for flight. WingPose turns a wing about its
--     hinge (flap and fold); FoldWings tucks a fresh bird's wings along its
--     back, for a bird sitting still.

local Kit = require(script.Parent.Kit)

local CritterArt = {}

local hex = Kit.hex
local BLACK = Color3.fromRGB(28, 24, 22)

local function anim(p: BasePart, kind: string, hinge: Vector3, phase: number?)
	p:SetAttribute("Anim", kind)
	p:SetAttribute("Hinge", hinge)
	if phase then
		p:SetAttribute("Phase", phase)
	end
end

local function blob(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.decor(Kit.ellipsoid(model, name, size, cf, color, material), false)
end

local function block(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.decor(Kit.part(model, name, size, cf, color, material), false)
end

local function bead(model: Model, name: string, d: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	return Kit.decor(Kit.ball(model, name, d, CFrame.new(at), color, material), false)
end

local function critter(kind: string): Model
	local m = Kit.model(kind)
	m:SetAttribute("Critter", kind)
	return m
end

---------------------------------------------------------------------------
-- Birds
---------------------------------------------------------------------------

local BIRD_LOOKS = {
	{ back = hex("#7A5A3A"), belly = hex("#E8803A"), head = hex("#5A4030") }, -- robin
	{ back = hex("#3A78C8"), belly = hex("#F0E2C8"), head = hex("#3A78C8") }, -- bluebird
	{ back = hex("#E8C83A"), belly = hex("#F5E070"), head = hex("#2A2420") }, -- goldfinch
	{ back = hex("#8A6A4A"), belly = hex("#D8C8A8"), head = hex("#7A5A3A") }, -- sparrow
	{ back = hex("#C8302A"), belly = hex("#D84A3A"), head = hex("#C8302A") }, -- cardinal
}

-- A songbird about a stud long (`scale` grows it: flock birds fly high,
-- so they're bigger). Stands on y = 0; `flying` tucks the legs away.
-- Named parts: Body, Belly, Head, Beak, EyeL/EyeR, Tail, WingL, WingR, Leg.
function CritterArt.Bird(seed: number, scale: number?, flying: boolean?): Model
	local s = scale or 1
	local rng = Kit.rng(seed)
	local look = BIRD_LOOKS[(seed % #BIRD_LOOKS) + 1]
	local model = critter("Bird")
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * s
	end
	blob(model, "Body", v(0.55, 0.5, 0.85), CFrame.new(v(0, 0.45, 0)), Kit.vary(look.back, rng, 0.04))
	blob(model, "Belly", v(0.47, 0.4, 0.6), CFrame.new(v(0, 0.39, -0.12)), look.belly)
	local headAt = v(0, 0.72, -0.36)
	local hinge = v(0, 0.55, -0.2)
	anim(bead(model, "Head", 0.42 * s, headAt, look.head), "Head", hinge)
	anim(block(model, "Beak", v(0.1, 0.09, 0.22), CFrame.new(v(0, 0.69, -0.62)), hex("#F0A030")), "Head", hinge)
	for _, side in ipairs({ -1, 1 }) do
		anim(
			bead(model, if side < 0 then "EyeL" else "EyeR", 0.08 * s, v(side * 0.16, 0.78, -0.5), BLACK),
			"Head",
			hinge
		)
	end
	local tail = block(
		model,
		"Tail",
		v(0.28, 0.06, 0.42),
		CFrame.new(v(0, 0.52, 0.56)) * CFrame.Angles(math.rad(22), 0, 0),
		Kit.shade(look.back, -0.1)
	)
	anim(tail, "Tail", v(0, 0.5, 0.38))
	for _, side in ipairs({ -1, 1 }) do
		local name = if side < 0 then "WingL" else "WingR"
		local shoulder = v(side * 0.24, 0.53, 0)
		local wing =
			block(model, name, v(0.62, 0.06, 0.44), CFrame.new(v(side * 0.55, 0.53, 0.02)), Kit.shade(look.back, -0.06))
		anim(wing, name, shoulder)
		-- Darker flight feathers along the trailing edge.
		local tip =
			block(model, name, v(0.4, 0.07, 0.16), CFrame.new(v(side * 0.66, 0.53, 0.2)), Kit.shade(look.back, -0.28))
		anim(tip, name, shoulder)
	end
	if not flying then
		for _, side in ipairs({ -1, 1 }) do
			block(model, "Leg", v(0.05, 0.24, 0.05), CFrame.new(v(side * 0.1, 0.12, 0)), hex("#D08A3A"))
		end
	end
	return model
end

-- The turn (in model space, about the wing's hinge) for a wing on `side`
-- (-1 left, 1 right): flapped `flap` degrees up (negative = down), swept
-- `sweep` degrees back along the body, then rolled `roll` degrees about
-- the body's axis (negative tips the swept wing down against the flank).
-- Folded on a perched bird: FoldedSweep and FoldedRoll, no flap.
function CritterArt.WingPose(hinge: Vector3, side: number, flap: number, sweep: number, roll: number?): CFrame
	return CFrame.new(hinge)
		* CFrame.Angles(0, 0, math.rad(side * (roll or 0)))
		* CFrame.Angles(0, math.rad(-side * sweep), 0)
		* CFrame.Angles(0, 0, math.rad(side * flap))
		* CFrame.new(-hinge)
end

CritterArt.FoldedSweep = 82
CritterArt.FoldedRoll = -65

-- Tucks a freshly built bird's wings along its back (in place; the model
-- must still be at the origin).
function CritterArt.FoldWings(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("Anim")
			local hinge = d:GetAttribute("Hinge")
			if (kind == "WingL" or kind == "WingR") and typeof(hinge) == "Vector3" then
				local side = if kind == "WingL" then -1 else 1
				d.CFrame = CritterArt.WingPose(hinge, side, 0, CritterArt.FoldedSweep, CritterArt.FoldedRoll) * d.CFrame
			end
		end
	end
end

---------------------------------------------------------------------------
-- Butterflies
---------------------------------------------------------------------------

local BUTTERFLY_LOOKS = {
	{ wing = hex("#F08A24"), spot = hex("#2A2420") }, -- monarch
	{ wing = hex("#3A8AF0"), spot = hex("#1E3A7A") }, -- blue
	{ wing = hex("#F5E35A"), spot = hex("#C8A030") }, -- lemon
	{ wing = hex("#F8F4EC"), spot = hex("#B8B0A8") }, -- cabbage white
	{ wing = hex("#F0A0C8"), spot = hex("#B05A90") }, -- pink
}

-- A butterfly centred on the origin, about 1.3 studs across.
-- Named parts: Body, WingL/WingR (fore, hind and spot), Antenna.
function CritterArt.Butterfly(seed: number): Model
	local look = BUTTERFLY_LOOKS[(seed % #BUTTERFLY_LOOKS) + 1]
	local model = critter("Butterfly")
	local s = 1.25
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * s
	end
	block(model, "Body", v(0.08, 0.08, 0.5), CFrame.new(v(0, 0, 0)), hex("#2A2420"))
	for _, side in ipairs({ -1, 1 }) do
		local name = if side < 0 then "WingL" else "WingR"
		local hinge = v(side * 0.03, 0, 0)
		local fore = CFrame.new(v(side * 0.32, 0, -0.08)) * CFrame.Angles(0, math.rad(side * 18), 0)
		anim(blob(model, name, v(0.62, 0.04, 0.5), fore, look.wing), name, hinge)
		local hind = CFrame.new(v(side * 0.24, -0.006, 0.2)) * CFrame.Angles(0, math.rad(side * -24), 0)
		anim(blob(model, name, v(0.44, 0.04, 0.38), hind, Kit.shade(look.wing, -0.12)), name, hinge)
		anim(blob(model, name, v(0.18, 0.05, 0.16), CFrame.new(v(side * 0.44, 0.006, -0.14)), look.spot), name, hinge)
		anim(blob(model, name, v(0.1, 0.05, 0.09), CFrame.new(v(side * 0.27, 0.006, 0.24)), look.spot), name, hinge)
		Kit.decor(
			Kit.rod(
				model,
				"Antenna",
				v(side * 0.03, 0.03, -0.24),
				v(side * 0.11, 0.16, -0.46),
				0.025 * s,
				hex("#2A2420")
			),
			false
		)
	end
	return model
end

---------------------------------------------------------------------------
-- Rabbits
---------------------------------------------------------------------------

-- A rabbit sitting on y = 0, about 1.5 studs tall to the ear tips.
-- `snowy` makes it a white winter hare. Named parts: Body, Haunch, Head,
-- EarL, EarR, Tail, EyeL, EyeR, Nose, Paw.
function CritterArt.Rabbit(seed: number, snowy: boolean?): Model
	local rng = Kit.rng(seed)
	local coat = if snowy then hex("#F4F2EE") else rng:pick({ hex("#9A7A5A"), hex("#8A8580"), hex("#A88A68") })
	local model = critter("Rabbit")
	blob(model, "Body", Vector3.new(0.9, 0.8, 1.15), CFrame.new(0, 0.48, 0.05), coat)
	blob(model, "Haunch", Vector3.new(0.86, 0.72, 0.62), CFrame.new(0, 0.4, 0.36), Kit.shade(coat, -0.05))
	local hinge = Vector3.new(0, 0.8, -0.3)
	anim(blob(model, "Head", Vector3.new(0.6, 0.55, 0.62), CFrame.new(0, 0.9, -0.5), coat), "Head", hinge)
	for _, side in ipairs({ -1, 1 }) do
		local ear = blob(
			model,
			if side < 0 then "EarL" else "EarR",
			Vector3.new(0.15, 0.62, 0.24),
			CFrame.new(side * 0.13, 1.38, -0.4) * CFrame.Angles(math.rad(-12), 0, math.rad(side * 10)),
			coat
		)
		anim(ear, "Head", hinge)
		anim(
			blob(
				model,
				"EarInner",
				Vector3.new(0.08, 0.46, 0.12),
				CFrame.new(side * 0.13, 1.4, -0.47) * CFrame.Angles(math.rad(-12), 0, math.rad(side * 10)),
				hex("#E8A8A8")
			),
			"Head",
			hinge
		)
		anim(
			bead(model, if side < 0 then "EyeL" else "EyeR", 0.1, Vector3.new(side * 0.24, 0.98, -0.66), BLACK),
			"Head",
			hinge
		)
		blob(model, "Paw", Vector3.new(0.18, 0.14, 0.32), CFrame.new(side * 0.18, 0.07, -0.32), Kit.shade(coat, 0.1))
	end
	anim(bead(model, "Nose", 0.09, Vector3.new(0, 0.88, -0.82), hex("#E07A8A")), "Head", hinge)
	bead(model, "Tail", 0.32, Vector3.new(0, 0.58, 0.64), hex("#FAF8F4"))
	return model
end

---------------------------------------------------------------------------
-- Deer
---------------------------------------------------------------------------

-- A deer standing on y = 0, about 4.5 studs to the ears (a buck, with
-- antlers, on odd seeds). Named parts: Body, Belly, Rump, Neck, Head,
-- Snout, Nose, EarL, EarR, EyeL, EyeR, Antler, Thigh, Leg, Hoof, Tail.
function CritterArt.Deer(seed: number): Model
	local rng = Kit.rng(seed)
	local coat = Kit.vary(hex("#B07A4A"), rng, 0.05)
	local pale = hex("#EAD6B4")
	local dark = hex("#4A3020")
	local model = critter("Deer")
	blob(model, "Body", Vector3.new(1.55, 1.45, 2.9), CFrame.new(0, 2.55, 0), coat)
	blob(model, "Belly", Vector3.new(1.25, 0.8, 2.3), CFrame.new(0, 2.2, 0), pale)
	blob(model, "Chest", Vector3.new(1.3, 1.3, 1.0), CFrame.new(0, 2.6, -1.05), coat)
	blob(model, "Rump", Vector3.new(1.05, 0.95, 0.55), CFrame.new(0, 2.7, 1.32), pale)
	local hinge = Vector3.new(0, 2.9, -1.0)
	anim(
		blob(
			model,
			"Neck",
			Vector3.new(0.72, 1.35, 0.78),
			CFrame.new(0, 3.35, -1.25) * CFrame.Angles(math.rad(-30), 0, 0),
			coat
		),
		"Head",
		hinge
	)
	anim(blob(model, "Head", Vector3.new(0.84, 0.82, 1.15), CFrame.new(0, 3.98, -1.62), coat), "Head", hinge)
	anim(
		blob(model, "Snout", Vector3.new(0.52, 0.5, 0.66), CFrame.new(0, 3.82, -2.12), Kit.shade(coat, -0.08)),
		"Head",
		hinge
	)
	anim(bead(model, "Nose", 0.22, Vector3.new(0, 3.9, -2.44), dark), "Head", hinge)
	for _, side in ipairs({ -1, 1 }) do
		anim(
			blob(
				model,
				if side < 0 then "EarL" else "EarR",
				Vector3.new(0.18, 0.62, 0.34),
				CFrame.new(side * 0.48, 4.36, -1.45) * CFrame.Angles(0, 0, math.rad(side * -40)),
				coat
			),
			"Head",
			hinge
		)
		anim(
			bead(model, if side < 0 then "EyeL" else "EyeR", 0.15, Vector3.new(side * 0.37, 4.08, -1.86), BLACK),
			"Head",
			hinge
		)
	end
	if seed % 2 == 1 then
		local antler = hex("#E2D2B2")
		for _, side in ipairs({ -1, 1 }) do
			local base = Vector3.new(side * 0.22, 4.32, -1.52)
			local mid = Vector3.new(side * 0.55, 4.95, -1.32)
			local tip = Vector3.new(side * 0.72, 5.45, -1.62)
			local tine = Vector3.new(side * 0.9, 5.2, -1.0)
			local brow = Vector3.new(side * 0.38, 4.75, -1.9)
			for _, seg in ipairs({ { base, mid }, { mid, tip }, { mid, tine }, { base + (mid - base) * 0.3, brow } }) do
				local r = Kit.decor(
					Kit.rod(model, "Antler", seg[1], seg[2], 0.15, antler, Enum.Material.SmoothPlastic),
					false
				)
				anim(r, "Head", hinge)
			end
		end
	end
	for _, leg in ipairs({
		{ x = -0.46, z = -0.95, phase = 0 },
		{ x = 0.46, z = -0.95, phase = 0.5 },
		{ x = -0.46, z = 0.95, phase = 0.5 },
		{ x = 0.46, z = 0.95, phase = 0 },
	}) do
		local top = Vector3.new(leg.x, 2.3, leg.z)
		local back = leg.z > 0
		anim(
			blob(
				model,
				"Thigh",
				if back then Vector3.new(0.6, 1.3, 0.8) else Vector3.new(0.52, 1.1, 0.62),
				CFrame.new(leg.x, 1.85, leg.z + (if back then 0.08 else 0)),
				coat
			),
			"Leg",
			top,
			leg.phase
		)
		anim(
			block(model, "Leg", Vector3.new(0.22, 1.35, 0.24), CFrame.new(leg.x, 0.88, leg.z), coat),
			"Leg",
			top,
			leg.phase
		)
		anim(
			block(model, "Hoof", Vector3.new(0.26, 0.22, 0.3), CFrame.new(leg.x, 0.11, leg.z - 0.02), dark),
			"Leg",
			top,
			leg.phase
		)
	end
	anim(
		blob(
			model,
			"Tail",
			Vector3.new(0.34, 0.55, 0.2),
			CFrame.new(0, 2.95, 1.58) * CFrame.Angles(math.rad(20), 0, 0),
			pale
		),
		"Tail",
		Vector3.new(0, 3.15, 1.5)
	)
	return model
end

---------------------------------------------------------------------------
-- Ducks and fish
---------------------------------------------------------------------------

-- A duck floating with the waterline at y = 0 (a mallard drake on even
-- seeds, a brown hen on odd). Named parts: Body, Breast, Wing, Tail, Neck,
-- NeckRing, Head, Bill, EyeL, EyeR.
function CritterArt.Duck(seed: number): Model
	local drake = seed % 2 == 0
	local body = if drake then hex("#9A8E80") else hex("#9A7A5A")
	local head = if drake then hex("#2E7A3A") else hex("#8A6A4A")
	local breast = if drake then hex("#7A4A3A") else hex("#A8865E")
	local model = critter("Duck")
	blob(model, "Body", Vector3.new(0.86, 0.62, 1.3), CFrame.new(0, 0.12, 0), body)
	blob(model, "Breast", Vector3.new(0.72, 0.56, 0.62), CFrame.new(0, 0.22, -0.42), breast)
	for _, side in ipairs({ -1, 1 }) do
		blob(model, "Wing", Vector3.new(0.18, 0.42, 0.9), CFrame.new(side * 0.37, 0.3, 0.1), Kit.shade(body, -0.15))
	end
	blob(
		model,
		"Tail",
		Vector3.new(0.36, 0.2, 0.5),
		CFrame.new(0, 0.32, 0.66) * CFrame.Angles(math.rad(28), 0, 0),
		Kit.shade(body, -0.25)
	)
	if drake then
		bead(model, "Curl", 0.12, Vector3.new(0, 0.46, 0.74), hex("#1E2A20"))
	end
	local hinge = Vector3.new(0, 0.42, -0.45)
	anim(blob(model, "Neck", Vector3.new(0.3, 0.52, 0.3), CFrame.new(0, 0.55, -0.52), head), "Head", hinge)
	if drake then
		anim(
			blob(model, "NeckRing", Vector3.new(0.34, 0.08, 0.34), CFrame.new(0, 0.5, -0.52), hex("#F4F2EE")),
			"Head",
			hinge
		)
	end
	anim(bead(model, "Head", 0.5, Vector3.new(0, 0.86, -0.56), head), "Head", hinge)
	anim(block(model, "Bill", Vector3.new(0.22, 0.08, 0.34), CFrame.new(0, 0.8, -0.88), hex("#E8B830")), "Head", hinge)
	for _, side in ipairs({ -1, 1 }) do
		anim(
			bead(model, if side < 0 then "EyeL" else "EyeR", 0.08, Vector3.new(side * 0.2, 0.93, -0.7), BLACK),
			"Head",
			hinge
		)
	end
	return model
end

-- A fish centred on the origin, about 1.6 studs long (a trout, or a
-- golden carp on seeds divisible by 3). Named parts: Body, Stripe, Tail,
-- Fin, EyeL, EyeR.
function CritterArt.Fish(seed: number): Model
	local golden = seed % 3 == 0
	local color = if golden then hex("#E8A040") else hex("#8AA89A")
	local model = critter("Fish")
	blob(model, "Body", Vector3.new(0.36, 0.62, 1.5), CFrame.new(0, 0, 0), color)
	blob(
		model,
		"Stripe",
		Vector3.new(0.37, 0.14, 1.2),
		CFrame.new(0, 0, -0.02),
		if golden then hex("#F8D080") else hex("#E89A9A")
	)
	anim(
		block(
			model,
			"Tail",
			Vector3.new(0.06, 0.42, 0.42),
			CFrame.new(0, 0, 0.86) * CFrame.Angles(math.rad(45), 0, 0),
			Kit.shade(color, -0.15)
		),
		"Tail",
		Vector3.new(0, 0, 0.7)
	)
	Kit.decor(
		Kit.wedge(model, "Fin", Vector3.new(0.05, 0.24, 0.42), CFrame.new(0, 0.38, 0.05), Kit.shade(color, -0.15)),
		false
	)
	for _, side in ipairs({ -1, 1 }) do
		bead(model, if side < 0 then "EyeL" else "EyeR", 0.08, Vector3.new(side * 0.17, 0.08, -0.52), BLACK)
	end
	return model
end

---------------------------------------------------------------------------
-- Magic: wisps and ember sprites
---------------------------------------------------------------------------

local function trail(part: BasePart, color: Color3, rate: number, texture: string)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Trail"
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2)
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = rate
	e.Parent = part
end

local function glow(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- A Phantom Grove wisp: a glowing violet orb with a trailing tail,
-- centred on the origin. Named parts: Core (light + Trail emitter), Halo,
-- Tail.
function CritterArt.Wisp(seed: number): Model
	local teal = seed % 3 == 0
	local core = if teal then hex("#7AF2E0") else hex("#C8A8FF")
	local halo = if teal then hex("#3AC8C0") else hex("#8A5AE0")
	local model = critter("Wisp")
	local c = bead(model, "Core", 0.7, Vector3.zero, core, Enum.Material.Neon)
	local h = bead(model, "Halo", 1.25, Vector3.zero, halo, Enum.Material.Neon)
	h.Transparency = 0.8
	local t1 = bead(model, "Tail", 0.46, Vector3.new(0, -0.08, 0.55), core, Enum.Material.Neon)
	t1.Transparency = 0.35
	anim(t1, "Tail", Vector3.new(0, 0, 0.2))
	local t2 = bead(model, "Tail", 0.28, Vector3.new(0, -0.18, 1.0), halo, Enum.Material.Neon)
	t2.Transparency = 0.5
	anim(t2, "Tail", Vector3.new(0, 0, 0.2))
	glow(c, core, 11, 1.3)
	trail(c, core, 5, "rbxasset://textures/particles/sparkles_main.dds")
	return model
end

-- A Volcano ember sprite: a little living coal with a flickering flame
-- for hair and two black eyes, centred on the origin. Named parts: Body,
-- Flame, EyeL, EyeR.
function CritterArt.EmberSprite(seed: number): Model
	local rng = Kit.rng(seed)
	local model = critter("EmberSprite")
	local body = bead(model, "Body", 0.8, Vector3.zero, Kit.vary(hex("#FF7A1A"), rng, 0.04), Enum.Material.Neon)
	anim(
		blob(
			model,
			"Flame",
			Vector3.new(0.48, 0.9, 0.48),
			CFrame.new(0, 0.55, 0.05),
			hex("#FFC24A"),
			Enum.Material.Neon
		),
		"Tail",
		Vector3.new(0, 0.3, 0)
	)
	anim(
		blob(
			model,
			"Flame",
			Vector3.new(0.26, 0.5, 0.26),
			CFrame.new(0, 0.95, 0.08),
			hex("#FFE7A0"),
			Enum.Material.Neon
		),
		"Tail",
		Vector3.new(0, 0.3, 0)
	)
	for _, side in ipairs({ -1, 1 }) do
		bead(model, if side < 0 then "EyeL" else "EyeR", 0.15, Vector3.new(side * 0.16, 0.08, -0.34), BLACK)
	end
	glow(body, hex("#FF8A3A"), 8, 1)
	trail(body, hex("#FFB050"), 6, "rbxasset://textures/particles/fire_sparks_main.dds")
	return model
end

---------------------------------------------------------------------------
-- Particle clouds and splashes
---------------------------------------------------------------------------

local function cloudPart(model: Model, size: Vector3): Part
	local p = Kit.decor(Kit.part(model, "Cloud", size, CFrame.identity, Color3.new(1, 1, 1)), false)
	p.Transparency = 1
	return p
end

-- A cloud of fireflies over a `size` box (centred on the origin): yellow-
-- green sparks that wander and blink.
function CritterArt.Fireflies(size: Vector3, rate: number): Model
	local model = critter("Fireflies")
	local p = cloudPart(model, size)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Particles"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(214, 255, 120), Color3.fromRGB(255, 236, 120))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32, 0.08), NumberSequenceKeypoint.new(1, 0.32, 0.08) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0),
		NumberSequenceKeypoint.new(0.28, 0.95),
		NumberSequenceKeypoint.new(0.45, 0.05),
		NumberSequenceKeypoint.new(0.62, 1),
		NumberSequenceKeypoint.new(0.8, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(3, 6)
	e.Speed = NumberRange.new(0.4, 1.2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.15, 0)
	e.Drag = 0.8
	e.Rate = rate
	e.Parent = p
	return model
end

-- A cloud of glowing motes drifting upward (the Skyroot, its Bloom).
function CritterArt.Motes(size: Vector3, color: Color3, rate: number, moteSize: number): Model
	local model = critter("Motes")
	local p = cloudPart(model, size)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Particles"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, moteSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 0.2
	e.Rate = rate
	e.Parent = p
	return model
end

-- A splash to Emit() from (a fish leaving or hitting the water), at the
-- origin on the surface.
function CritterArt.Splash(): Model
	local model = critter("Splash")
	local p = Kit.decor(Kit.part(model, "Splash", Vector3.new(1, 0.2, 1), CFrame.identity, Color3.new(1, 1, 1)), false)
	p.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Name = "Particles"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(225, 240, 250))
	e.LightInfluence = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(5, 9)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -28, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = p
	return model
end

return CritterArt
