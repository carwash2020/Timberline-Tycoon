--!strict
-- ForestArt: the Living Forest's models (GAME_DESIGN §16). Pure (see Kit):
-- the same code decorates the game's trees and draws tools/preview.
--
--   * BarkClue(parent, trunk, def, figure, seed): the bark tell of a hidden
--     figure, sized to a tree's trunk (its "Trunk" part): wavy strips
--     (curly), dark eyes (birdseye), scalloped plates (quilted), a knobbly
--     swelling at the foot (burl), a star-speckled burl (starfall), glowing
--     cracks and sparks (stormgrain, same as StormGlow). Parts are placed in
--     world space on the trunk; ForestService adds them with
--     TreeService.Decorate so they hide, fall and regrow with the tree.
--   * StormGlow(parent, trunk, def, seed): a storm-struck tree's cracks,
--     sparks and blue light (ParticleEmitter "StormSparks", PointLight).
--   * NameStake(name, seed): the planter's little stake (ground at y = 0,
--     the sign facing -Z); PrimaryPart "Post".
--   * ElderAura(radius, color?): an Elder's ring of glowing stones, rising
--     motes and a pillar of light (ground at y = 0); PrimaryPart "AuraCore"
--     (holds the light and the "ElderMotes" emitter).
--   * Sprout(def, seed, stumpDiameter?): a Heartseed sprouting in a mound
--     (ground at y = 0), sized to the stump it's on; PrimaryPart "Mound".
--     SproutScale(u) is how big it's drawn as it grows (at most 1).
--   * SeedOrb(): the glowing Heartseed that pops out and flies to you.
--   * FigureBand(logPart, figure): the coloured band round a figured log,
--     welded to it like the log's caps (unanchored, massless).
-- Everything here is decoration (Kit.decor): no collisions, no clicks.

local ForestData = require(script.Parent.Parent.ForestData)
local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)
local TreeArt = require(script.Parent.TreeArt)

type WoodDef = WoodData.WoodDef
type Rng = Kit.Rng

local ForestArt = {}

ForestArt.HeartseedColor = Color3.fromRGB(206, 238, 112) -- a fresh lime gold
ForestArt.ElderColor = Color3.fromRGB(255, 226, 140)
ForestArt.StormColor = Color3.fromRGB(108, 206, 255)

local DARK_EYE = Color3.fromRGB(46, 30, 20)

local function figureColor(id: string): Color3
	for _, f in ipairs(ForestData.Figures) do
		if f.id == id then
			return f.color
		end
	end
	return Color3.new(1, 1, 1)
end
ForestArt.FigureColor = figureColor

---------------------------------------------------------------------------
-- Placing things on a trunk
---------------------------------------------------------------------------

-- A trunk's shape: its upright frame (Y up the trunk, origin at its centre),
-- height, radius, and the band of bark you can see under the canopy.
type Trunk = { frame: CFrame, height: number, radius: number, low: number, high: number }

local function trunkOf(trunk: BasePart, def: WoodDef): Trunk
	local height, diameter = trunk.Size.X, trunk.Size.Y
	-- Pines and frostwood hide their trunks under the cone tiers from about
	-- a third of the way up; the broadleaf woods show most of theirs.
	local top = if def.silhouette == "pine" then 0.3 elseif def.silhouette == "palm" then 0.9 else 0.78
	return {
		frame = trunk.CFrame * CFrame.Angles(0, 0, -math.pi / 2),
		height = height,
		radius = diameter / 2,
		low = height * 0.06,
		high = height * top,
	}
end

-- On the bark: `y` studs up from the trunk's foot, `angle` round it, `out`
-- studs past the bark. The CFrame's LookVector points straight out.
local function onBark(t: Trunk, y: number, angle: number, out: number): CFrame
	return t.frame
		* CFrame.new(0, y - t.height / 2, 0)
		* CFrame.Angles(0, angle, 0)
		* CFrame.new(0, 0, -(t.radius + out))
end

local function point(t: Trunk, y: number, angle: number, out: number): Vector3
	return onBark(t, y, angle, out).Position
end

-- Straight out of the bark at height `y`, angle `angle`.
local function outward(t: Trunk, y: number, angle: number): Vector3
	return (point(t, y, angle, 0) - point(t, y, angle, -t.radius)).Unit
end

-- A flat strip lying on the bark from `a` to `b` (`thick` out of the bark,
-- `width` across it). Built with fromMatrix so the axes are explicit: X
-- out of the bark, Z along the strip.
local function strip(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	out: Vector3,
	thick: number,
	width: number,
	color: Color3,
	material: Enum.Material
): Part
	local along = b - a
	local length = along.Magnitude
	local z = along / math.max(length, 1e-4)
	local x = out - z * out:Dot(z)
	x = if x.Magnitude > 1e-4 then x.Unit else z:Cross(Vector3.yAxis).Unit
	local y = z:Cross(x)
	local p = Kit.part(
		model,
		name,
		Vector3.new(thick, width, length + width * 0.4),
		CFrame.fromMatrix((a + b) / 2, x, y, z),
		color,
		material
	)
	return Kit.decor(p, false)
end

local function holder(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

---------------------------------------------------------------------------
-- The bark clues
---------------------------------------------------------------------------

-- Curly: three wavy strips spiralling up the trunk, a warm, paler grain.
local function curly(model: Model, t: Trunk, def: WoodDef, rng: Rng)
	local color = Kit.shade(def.trunkColor:Lerp(figureColor("curly"), 0.4), 0.2)
	local width = math.clamp(t.radius * 0.42, 0.22, 0.6)
	local start = rng:range(0, math.pi * 2)
	local turns = rng:range(0.9, 1.15) * math.pi
	local segments = 10
	for s = 0, 2 do
		local a0 = start + s * math.pi * 2 / 3
		local phase = rng:range(0, math.pi * 2)
		local prev: Vector3? = nil
		local prevY, prevAngle = 0, 0
		for i = 0, segments do
			local u = i / segments
			local y = t.low + (t.high - t.low) * u
			local angle = a0 + turns * u + math.sin(u * math.pi * 4 + phase) * 0.22
			local p = point(t, y, angle, 0.05)
			if prev then
				local out = outward(t, (y + prevY) / 2, (angle + prevAngle) / 2)
				strip(model, "CurlyStrip", prev, p, out, 0.1, width, Kit.vary(color, rng, 0.04), Enum.Material.Wood)
			end
			prev, prevY, prevAngle = p, y, angle
		end
	end
end

-- Birdseye: small dark eyes, each in a paler ring, dotted over the bark.
local function birdseye(model: Model, t: Trunk, def: WoodDef, rng: Rng)
	local span = t.high - t.low
	local count = math.clamp(math.floor(span * t.radius * 1.4 + 0.5), 12, 22)
	local eye = math.clamp(t.radius * 0.36, 0.26, 0.5)
	-- The ring around each eye contrasts with the bark: paler on dark bark,
	-- warm brown on pale bark (birch's own marks are dark dashes, not rings).
	local _, _, value = def.trunkColor:ToHSV()
	local ring = if value > 0.6 then Color3.fromRGB(150, 104, 64) else Kit.shade(def.trunkColor, 0.32)
	-- Spread evenly round the trunk (a little jitter), so every side shows some.
	local start = rng:range(0, math.pi * 2)
	for i = 1, count do
		local y = t.low + ((i - 0.5) / count + rng:range(-0.03, 0.03)) * span
		local angle = start + i * 2.399 + rng:range(-0.2, 0.2) -- golden angle
		local size = eye * rng:range(0.8, 1.15)
		-- A flat disc: the cylinder's X axis turned to point out of the bark.
		local turn = CFrame.Angles(0, math.pi / 2, 0)
		Kit.decor(
			Kit.cylinder(model, "EyeRing", 0.06, size * 1.7, onBark(t, y, angle, 0.01) * turn, ring, Enum.Material.Wood),
			false
		)
		Kit.decor(
			Kit.cylinder(model, "Eye", 0.08, size, onBark(t, y, angle, 0.05) * turn, DARK_EYE, Enum.Material.Wood),
			false
		)
	end
end

-- Quilted: rows of rounded plates overlapping like scales.
local function quilted(model: Model, t: Trunk, def: WoodDef, rng: Rng)
	local perRow = math.clamp(math.floor(math.pi * t.radius * 2 / 0.95 + 0.5), 6, 10)
	local w = math.pi * t.radius * 2 / perRow * 1.25
	local h = w * 0.7
	local rows = math.clamp(math.floor((t.high - t.low) / (h * 0.75)), 3, 6)
	local light, deep = Kit.shade(def.trunkColor, 0.16), Kit.shade(def.trunkColor, 0.02)
	local start = rng:range(0, math.pi * 2)
	for r = 0, rows - 1 do
		local y = t.low + h * 0.5 + r * h * 0.75
		local shift = if r % 2 == 0 then 0 else math.pi / perRow
		for i = 0, perRow - 1 do
			local angle = start + shift + i * math.pi * 2 / perRow
			local color = Kit.vary(if (i + r) % 2 == 0 then light else deep, rng, 0.03)
			Kit.decor(
				Kit.ellipsoid(
					model,
					"QuiltPlate",
					Vector3.new(w, h, 0.3),
					onBark(t, y, angle, -0.07),
					color,
					Enum.Material.Wood
				),
				false
			)
		end
	end
end

-- Burl: a big knobbly swelling low on one side. Returns the swelling's
-- centre and size, for the Starfall Burl's stars.
local function burl(model: Model, t: Trunk, def: WoodDef, rng: Rng, color: Color3?): (CFrame, Vector3)
	local base = color or Kit.shade(def.trunkColor, -0.14)
	local d = t.radius * 2
	local y = math.max(t.low + d * 0.45, t.height * 0.12)
	local angle = rng:range(0, math.pi * 2)
	local size = Vector3.new(d * 1.25, d * 1.05, d * 1.4)
	local center = onBark(t, y, angle, -t.radius * 0.25)
	Kit.decor(Kit.ellipsoid(model, "Burl", size, center, base, Enum.Material.Wood))
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + rng:range(-0.3, 0.3)
		local lift = rng:range(-0.35, 0.45)
		local dir = Vector3.new(math.cos(a) * 0.8, lift, -math.abs(math.sin(a)) - 0.25).Unit
		local at = center * CFrame.new(dir.X * size.X * 0.42, dir.Y * size.Y * 0.42, dir.Z * size.Z * 0.42)
		Kit.decor(
			Kit.ball(model, "Knob", d * rng:range(0.3, 0.46), at, Kit.vary(base, rng, 0.06), Enum.Material.Wood),
			false
		)
	end
	-- Two dark knots on its face.
	for k = -1, 1, 2 do
		local at = center * CFrame.new(k * size.X * 0.16, rng:range(-0.1, 0.15) * size.Y, -size.Z * 0.48)
		Kit.decor(Kit.ball(model, "Knot", d * 0.18, at, DARK_EYE, Enum.Material.Wood), false)
	end
	return center, size
end

-- Starfall Burl: a pale burl speckled with little glowing stars.
local function starfall(model: Model, t: Trunk, def: WoodDef, rng: Rng)
	-- A deep amber swelling, so the gold stars stand out even on pale wood.
	local amber = Color3.fromRGB(150, 100, 52):Lerp(def.trunkColor, 0.15)
	local center, size = burl(model, t, def, rng, amber)
	local gold = figureColor("starfall")
	local first: BasePart? = nil
	for _ = 1, 16 do
		-- A point on the front half of the swelling's surface.
		local theta = rng:range(0, math.pi * 2)
		local z = rng:range(0.15, 1)
		local r = math.sqrt(1 - z * z)
		local at = center
			* CFrame.new(math.cos(theta) * r * size.X * 0.5, math.sin(theta) * r * size.Y * 0.5, -z * size.Z * 0.5)
			* CFrame.Angles(math.rad(45), math.rad(45), 0)
		local s = rng:range(0.2, 0.34)
		local star = Kit.decor(
			Kit.part(model, "Star", Vector3.new(s, s, s), at, Kit.vary(gold, rng, 0.05), Enum.Material.Neon),
			false
		)
		first = first or star
	end
	if first then
		local light = Instance.new("PointLight")
		light.Color = gold
		light.Range = 9
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = first
	end
end

-- Stormgrain: jagged glowing cracks up the bark, sparks and a blue light.
local function storm(model: Model, t: Trunk, rng: Rng)
	local color = ForestArt.StormColor
	local first: BasePart? = nil
	local start = rng:range(0, math.pi * 2)
	local top = math.max(t.high, t.height * 0.55)
	local width = math.clamp(t.radius * 0.22, 0.16, 0.3)
	for c = 0, 4 do
		local angle = start + c * math.pi * 2 / 5 + rng:range(-0.3, 0.3)
		local y = t.low * 0.5 + rng:range(0, 0.12) * t.height
		local prev = point(t, y, angle, 0.05)
		for _ = 1, 4 do
			local y2 = math.min(top, y + rng:range(0.1, 0.18) * t.height)
			local angle2 = angle + rng:range(-0.4, 0.4)
			local p = point(t, y2, angle2, 0.05)
			local out = outward(t, (y + y2) / 2, (angle + angle2) / 2)
			local crack = strip(model, "StormCrack", prev, p, out, 0.1, width, color, Enum.Material.Neon)
			first = first or crack
			prev, y, angle = p, y2, angle2
		end
	end
	if not first then
		return
	end
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "StormSparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(220, 246, 255), color)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Rate = 7
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -14, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = first
	local light = Instance.new("PointLight")
	light.Name = "StormLight"
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Shadows = false
	light.Parent = first
end

-- The bark clue for `figureId` on a tree's trunk (its "Trunk" part), in a
-- Model named "BarkClue" under `parent`. `seed` varies its look.
function ForestArt.BarkClue(parent: Instance, trunk: BasePart, def: WoodDef, figureId: string, seed: number): Model
	local model = holder(parent, "BarkClue")
	model:SetAttribute("Figure", figureId)
	local t = trunkOf(trunk, def)
	local rng = Kit.rng(seed + 4049)
	if figureId == "curly" then
		curly(model, t, def, rng)
	elseif figureId == "birdseye" then
		birdseye(model, t, def, rng)
	elseif figureId == "quilted" then
		quilted(model, t, def, rng)
	elseif figureId == "burl" then
		burl(model, t, def, rng)
	elseif figureId == "starfall" then
		starfall(model, t, def, rng)
	elseif figureId == "stormgrain" then
		storm(model, t, rng)
	end
	return model
end

-- A storm-struck tree's glow (Model "StormGlow" under `parent`).
function ForestArt.StormGlow(parent: Instance, trunk: BasePart, def: WoodDef, seed: number): Model
	local model = holder(parent, "StormGlow")
	storm(model, trunkOf(trunk, def), Kit.rng(seed + 977))
	return model
end

---------------------------------------------------------------------------
-- The planter's stake
---------------------------------------------------------------------------

-- A little wooden stake with the planter's name on a board and a sprout
-- tied to the top. Ground at y = 0, the board facing -Z.
function ForestArt.NameStake(name: string, seed: number): Model
	local rng = Kit.rng(seed + 31)
	local model = Kit.model("NameStake")
	local wood = Kit.vary(Color3.fromRGB(150, 108, 66), rng, 0.04)
	local post = Kit.post(model, "Post", Vector3.new(0, -0.3, 0), 2.9, 0.24, wood, Enum.Material.Wood)
	Kit.decor(post, false)
	model.PrimaryPart = post
	local tilt = CFrame.Angles(rng:range(-0.04, 0.04), 0, rng:range(-0.05, 0.05))
	local board = Kit.part(
		model,
		"Board",
		Vector3.new(2.1, 0.8, 0.14),
		tilt * CFrame.new(0, 2.05, -0.2),
		Color3.fromRGB(226, 196, 146),
		Enum.Material.Wood
	)
	Kit.decor(board, false)
	local label = string.sub(name, 1, 18)
	Kit.signText(board, label, Color3.fromRGB(70, 44, 24), { Enum.NormalId.Front, Enum.NormalId.Back })
	-- Twine, and a sprout on top (a Heartseed's mark).
	Kit.decor(
		Kit.cylinder(
			model,
			"Twine",
			0.18,
			0.3,
			CFrame.new(0, 1.45, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(196, 150, 84),
			Enum.Material.Fabric
		),
		false
	)
	local leaf = ForestArt.HeartseedColor:Lerp(Color3.fromRGB(96, 170, 70), 0.55)
	for _, side in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.wedge(
				model,
				"Leaf",
				Vector3.new(0.08, 0.32, 0.5),
				CFrame.new(side * 0.2, 2.75, 0) * CFrame.Angles(0, side * math.pi / 2, side * -0.5),
				leaf,
				Enum.Material.SmoothPlastic
			),
			false
		)
	end
	Kit.decor(
		Kit.ball(model, "Seed", 0.26, CFrame.new(0, 2.66, 0), ForestArt.HeartseedColor, Enum.Material.Neon),
		false
	)
	return model
end

---------------------------------------------------------------------------
-- The Elder's aura
---------------------------------------------------------------------------

-- A ring of glowing stones `radius` studs out, motes rising inside it and
-- a faint pillar of light, for an Elder tree. Ground at y = 0.
function ForestArt.ElderAura(radius: number, color: Color3?): Model
	local glow = color or ForestArt.ElderColor
	local model = Kit.model("ElderAura")
	local core = Kit.part(
		model,
		"AuraCore",
		Vector3.new(radius * 2, 0.2, radius * 2),
		CFrame.new(0, 0.3, 0),
		glow,
		Enum.Material.SmoothPlastic
	)
	core.Transparency = 1
	Kit.decor(core, false)
	model.PrimaryPart = core
	local stones = 14
	for i = 0, stones - 1 do
		local a = i / stones * math.pi * 2
		local s = if i % 2 == 0 then 0.8 else 0.55
		Kit.decor(
			Kit.part(
				model,
				"AuraStone",
				Vector3.new(s, s * 0.9, s),
				CFrame.new(math.cos(a) * radius, s * 0.2, math.sin(a) * radius)
					* CFrame.Angles(math.rad(35), a, math.rad(45)),
				glow,
				Enum.Material.Neon
			),
			false
		)
	end
	local pillar = Kit.cylinder(
		model,
		"AuraPillar",
		90,
		3,
		CFrame.new(0, 45, 0) * CFrame.Angles(0, 0, math.pi / 2),
		glow,
		Enum.Material.Neon
	)
	pillar.Transparency = 0.82
	Kit.decor(pillar, false)
	local light = Instance.new("PointLight")
	light.Name = "ElderLight"
	light.Color = glow
	light.Range = math.max(20, radius * 3)
	light.Brightness = 2.2
	light.Shadows = false
	light.Parent = core
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "ElderMotes"
	motes.Color = ColorSequence.new(glow)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Rate = 10
	motes.Lifetime = NumberRange.new(3, 5)
	motes.Speed = NumberRange.new(1, 2.5)
	motes.SpreadAngle = Vector2.new(20, 20)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Acceleration = Vector3.new(0, 1.5, 0)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Parent = core
	return model
end

---------------------------------------------------------------------------
-- Heartseeds: the sprout and the orb
---------------------------------------------------------------------------

-- A Heartseed sprouting: a mound of fresh soil, the glowing seed and a
-- sapling of the wood. Ground at y = 0 (the stump's cut). Given the
-- stump's diameter, the mound (0.8 of it) and a thin glowing ring round
-- the cut (0.95 of it) stay on the stump, so nothing hangs in mid-air
-- past a small one, even at full size; without it, the old fixed-size
-- mound and halo. The pivot (the Mound) sits 0.1 up, so a ScaleTo grows
-- it from the cut.
function ForestArt.Sprout(def: WoodDef, seed: number, stumpDiameter: number?): Model
	local d: number? = if stumpDiameter and stumpDiameter > 0 and stumpDiameter < math.huge then stumpDiameter else nil
	local model = Kit.model("Sprout")
	local mound = Kit.ellipsoid(
		model,
		"Mound",
		if d then Vector3.new(d * 0.8, 0.35, d * 0.8) else Vector3.new(2.6, 0.7, 2.6),
		CFrame.new(0, 0.1, 0),
		Color3.fromRGB(92, 64, 42),
		Enum.Material.Ground
	)
	Kit.decor(mound, false)
	model.PrimaryPart = mound
	-- On a stump the halo is a collar round the mound's foot, just over the
	-- cut's rings (0.07-0.1 up), so only a thin ring of it shows.
	local halo = Kit.cylinder(
		model,
		"Halo",
		if d then 0.04 else 0.05,
		if d then d * 0.95 else 3.6,
		CFrame.new(0, if d then 0.12 else 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2),
		ForestArt.HeartseedColor,
		Enum.Material.Neon
	)
	halo.Transparency = 0.6
	Kit.decor(halo, false)
	-- The seed rests on the mound beside the stem (on a stump, a fifth of
	-- the way out, sized to it).
	local heartSize = if d then math.clamp(d * 0.3, 0.32, 0.55) else 0.55
	local heartAt = if d
		then CFrame.new(d * 0.2 * 0.857, 0.25 + heartSize * 0.2, -d * 0.2 * 0.514)
		else CFrame.new(0.5, 0.42, -0.3)
	local heart = Kit.ball(model, "Heartseed", heartSize, heartAt, ForestArt.HeartseedColor, Enum.Material.Neon)
	Kit.decor(heart, false)
	local light = Instance.new("PointLight")
	light.Color = ForestArt.HeartseedColor
	light.Range = 10
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = heart
	local sapling = TreeArt.Sapling(def, seed)
	Kit.placeAt(sapling, CFrame.new(0, 0.2, 0))
	for _, part in ipairs(sapling:GetDescendants()) do
		if part:IsA("BasePart") then
			Kit.decor(part, false)
		end
	end
	sapling.Parent = model
	return model
end

-- How big a sprout is drawn `u` (0-1) of the way through its growth: a
-- seedling at 0.25, easing out to full size (1, which fits the stump it's
-- on) and never past it.
function ForestArt.SproutScale(u: number): number
	local x = math.clamp(u, 0, 1)
	return 0.25 + 0.75 * (1 - (1 - x) ^ 2)
end

-- The glowing seed that pops out of a felled tree and flies to you.
function ForestArt.SeedOrb(): Part
	local orb = Instance.new("Part")
	orb.Name = "HeartseedOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(0.7, 0.7, 0.7)
	orb.Color = ForestArt.HeartseedColor
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.TopSurface = Enum.SurfaceType.Smooth
	orb.BottomSurface = Enum.SurfaceType.Smooth
	Kit.decor(orb, false)
	local light = Instance.new("PointLight")
	light.Color = ForestArt.HeartseedColor
	light.Range = 7
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = orb
	return orb
end

---------------------------------------------------------------------------
-- Figured logs
---------------------------------------------------------------------------

-- A coloured band round a figured log (its "LogPart", a cylinder along X),
-- welded to it like its caps. Replaces any band it had. Returns the band.
function ForestArt.FigureBand(log: BasePart, figureId: string): Part
	local old = log:FindFirstChild("FigureBand")
	if old then
		old:Destroy()
	end
	local length, diameter = log.Size.X, log.Size.Y
	local glowing = figureId == "stormgrain" or figureId == "starfall"
	local band = Kit.cylinder(
		log,
		"FigureBand",
		math.min(0.5, length * 0.18),
		diameter * 1.08,
		log.CFrame * CFrame.new(length * 0.22, 0, 0),
		figureColor(figureId),
		if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	Kit.decor(band, false)
	band.Massless = true
	band:SetAttribute("Figure", figureId)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = log
	weld.Part1 = band
	weld.Parent = band
	band.Anchored = false -- after the weld, so it never drops on its own
	return band
end

return ForestArt
