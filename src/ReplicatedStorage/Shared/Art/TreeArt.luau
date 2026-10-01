--!strict
-- TreeArt: the low-poly tree, stump, sapling and log models for every wood
-- (GAME_DESIGN §13: every wood has its own silhouette and colour, readable
-- at 50 studs; rare trees are landmarks). Pure (see Kit), so the preview
-- tool draws exactly what the game spawns.
--
-- Contract with TreeService / TreeFX / TreeUI / ChopController:
--   * Build returns a Model whose PrimaryPart is "Trunk": an upright
--     cylinder from the ground (y = 0 at the model's origin) to
--     trunkHeight * scale (a palm's straight lower trunk is shorter: the
--     curved rods above it are decoration), so its centre is the tree's
--     pivot and pivot - Trunk.Size.X/2 is the ground point under it.
--   * The trunk and canopy can be clicked (CanQuery) but only the trunk
--     collides; everything else is decoration.
--   * Log returns a Model whose PrimaryPart is "LogPart" (a cylinder along
--     X); its end caps are welded to it, unanchored and massless, so the
--     whole log moves when LogPart is welded to a player or a truck.

local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)

type WoodDef = WoodData.WoodDef
type Rng = Kit.Rng

local TreeArt = {}

-- How much of a palm's height its straight Trunk part takes; the curved,
-- ringed rods above it are decoration.
local PALM_TRUNK = 0.35

-- Extra colours per wood beyond WoodData's leaf and trunk colours: the
-- hand-painted variety that makes a canopy read as many leaves, the pale
-- cut-wood colour of log ends and stumps, and any glow.
type Palette = {
	leaves: { Color3 },
	heart: Color3, -- fresh-cut wood (log ends, stump tops)
	glow: Color3?, -- neon accents (rare woods)
	accent: Color3?, -- bark marks, snow, veins
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local PALETTES: { [string]: Palette } = {
	oak = {
		leaves = { hex("#5DA24A"), hex("#6FB352"), hex("#4C8F3E"), hex("#86BF57") },
		heart = hex("#E2BE84"),
	},
	birch = {
		leaves = { hex("#A6CE5C"), hex("#BCD96B"), hex("#8EBF4E"), hex("#D2DF7A") },
		heart = hex("#F1E3C2"),
		accent = hex("#2E2A28"),
	},
	pine = {
		leaves = { hex("#2F7A3D"), hex("#3A8A47"), hex("#276B36"), hex("#45975A") },
		heart = hex("#E8C98F"),
	},
	maple = {
		leaves = { hex("#D88F2C"), hex("#C8642A"), hex("#E5A33B"), hex("#B84A24"), hex("#EDBB4C") },
		heart = hex("#E6C38E"),
	},
	palmwood = {
		leaves = { hex("#3FAE5A"), hex("#52BF66"), hex("#33964B") },
		heart = hex("#EFD6A2"),
		accent = hex("#7A5A36"),
	},
	frostwood = {
		leaves = { hex("#7FB8D8"), hex("#6AA8CC"), hex("#93C7E2"), hex("#5E9DC4") },
		heart = hex("#E4F2FA"),
		accent = hex("#FFFFFF"),
		glow = hex("#B9F1FF"),
	},
	emberwood = {
		leaves = { hex("#FF7A1A"), hex("#F2601A"), hex("#FF9A33"), hex("#E04A12") },
		heart = hex("#FFB25A"),
		glow = hex("#FF8A2A"),
		accent = hex("#FF5A10"),
	},
	phantomwood = {
		leaves = { hex("#7A4FD0"), hex("#6A3FC0"), hex("#9468E0"), hex("#5A34A8") },
		heart = hex("#C8B5F0"),
		glow = hex("#55F2E0"),
		accent = hex("#B58CFF"),
	},
	lumenwood = {
		leaves = { hex("#FFF4C2"), hex("#FFE89A"), hex("#FFF9DC"), hex("#F7D97A") },
		heart = hex("#FFF6DA"),
		glow = hex("#FFE7A0"),
		accent = hex("#FFD36A"),
	},
}

function TreeArt.Palette(def: WoodDef): Palette
	return PALETTES[def.id]
		or {
			leaves = { def.leafColor, Kit.shade(def.leafColor, 0.12), Kit.shade(def.leafColor, -0.12) },
			heart = Kit.shade(def.trunkColor, 0.45),
		}
end

-- The pale cut-wood colour of this wood (log ends, stumps, chips).
function TreeArt.HeartColor(def: WoodDef): Color3
	return TreeArt.Palette(def).heart
end

-- The dust a felled tree throws up, by the ground of its home biome
-- (TreeFX): earth in the forests, sand on the coast, powder snow, volcanic
-- ash, the Phantom Grove's violet loam, pale isle soil.
local EARTH_DUST = Color3.fromRGB(196, 174, 140)
local DUST: { [string]: Color3 } = {
	starter = EARTH_DUST,
	hills = Color3.fromRGB(198, 168, 128),
	island = Color3.fromRGB(228, 210, 164),
	snow = Color3.fromRGB(242, 246, 250),
	volcano = Color3.fromRGB(118, 112, 108),
	grove = Color3.fromRGB(150, 138, 168),
	sky = Color3.fromRGB(236, 228, 198),
}

function TreeArt.DustColor(def: WoodDef): Color3
	return DUST[def.biome] or EARTH_DUST
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------

-- The trunk: the pivot part every system relies on (see the contract above).
local function trunk(model: Model, def: WoodDef, height: number, diameter: number): Part
	local p = Kit.cylinder(
		model,
		"Trunk",
		height,
		diameter,
		CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		def.trunkColor,
		Enum.Material.Wood
	)
	p.CanTouch = false
	model.PrimaryPart = p
	return p
end

-- Wedges flaring out from the trunk's foot, 0.55-0.8 diameters tall and
-- 0.45-0.65 out. A stump passes `maxHeight` (no flare tops its cut) and a
-- `lengthFactor` for shorter ones; the rng draws are the same either way.
local function rootFlares(
	model: Model,
	color: Color3,
	diameter: number,
	count: number,
	rng: Rng,
	maxHeight: number?,
	lengthFactor: number?
)
	local start = rng:range(0, math.pi * 2)
	for i = 1, count do
		local a = start + (i - 1) / count * math.pi * 2 + rng:range(-0.2, 0.2)
		local h = diameter * rng:range(0.55, 0.8)
		if maxHeight then
			h = math.min(h, maxHeight)
		end
		local len = diameter * rng:range(0.45, 0.65) * (lengthFactor or 1)
		Kit.decor(
			Kit.wedge(
				model,
				"Root",
				Vector3.new(diameter * 0.32, h, len),
				CFrame.Angles(0, a, 0) * CFrame.new(0, h / 2 - 0.05, -(diameter / 2 + len / 2 - 0.15)),
				Kit.shade(color, -0.08),
				Enum.Material.Wood
			),
			false
		)
	end
end

-- A canopy cluster that can be clicked (so pointing at the leaves targets
-- the tree) but doesn't collide.
local function canopy(
	model: Model,
	center: CFrame,
	size: Vector3,
	count: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material?
): { Part }
	local parts = Kit.blob(model, "Leaves", center, size, count, rng, colors, material or Enum.Material.SmoothPlastic)
	for _, p in ipairs(parts) do
		p.CanQuery = true
	end
	return parts
end

local function branch(model: Model, from: Vector3, to: Vector3, diameter: number, color: Color3)
	Kit.decor(Kit.rod(model, "Branch", from, to, diameter, color, Enum.Material.Wood), false)
end

-- A faceted cone tier (pines) whose faces can be clicked.
local function tier(
	model: Model,
	base: CFrame,
	radius: number,
	height: number,
	sides: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material?
)
	local folder = Instance.new("Model")
	folder.Name = "Tier"
	folder.Parent = model
	local jit: { number } = {}
	for i = 1, sides do
		jit[i] = rng:range(0.88, 1.08)
	end
	Kit.cone(
		folder,
		base,
		radius,
		height,
		sides,
		function(i: number): Color3
			return Kit.vary(colors[(i - 1) % #colors + 1], rng, 0.04)
		end,
		material or Enum.Material.SmoothPlastic,
		0.12,
		function(i: number): number
			return jit[i]
		end
	)
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			p.CanQuery = true
		end
	end
end

local function glowLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- Drifting sparks / motes / wisps from a canopy (ParticleEmitter).
local function particles(part: BasePart, color: Color3, rate: number, speed: number, rise: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Ambient"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(2.5, 4.5)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, rise, 0)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.2)
	e.Parent = part
end

---------------------------------------------------------------------------
-- One builder per wood
---------------------------------------------------------------------------

type Builder = (model: Model, def: WoodDef, pal: Palette, H: number, F: number, rng: Rng) -> ()

local builders: { [string]: Builder } = {}

-- Oak: a stout trunk, three limbs and a big round crown.
builders.oak = function(model, def, pal, H, F, rng)
	local D = 0.24 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 4, rng)
	local top = Vector3.new(0, H, 0)
	Kit.decor(
		Kit.cylinder(
			model,
			"TrunkTop",
			H * 0.35,
			D * 0.72,
			CFrame.new(0, H * 1.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
			def.trunkColor,
			Enum.Material.Wood
		),
		false
	)
	canopy(model, CFrame.new(0, H + F * 0.32, 0), Vector3.new(F, F * 0.72, F), 9, rng, pal.leaves)
	local start = rng:range(0, math.pi * 2)
	for i = 1, 3 do
		local a = start + (i - 1) * math.pi * 2 / 3 + rng:range(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = top + dir * F * 0.42 + Vector3.new(0, F * rng:range(0.05, 0.25), 0)
		branch(model, top - Vector3.new(0, H * 0.18, 0), tip, D * 0.38, def.trunkColor)
		canopy(model, CFrame.new(tip + Vector3.new(0, F * 0.08, 0)), Vector3.one * F * 0.52, 3, rng, pal.leaves)
	end
end

-- Birch: a slim white trunk with dark marks and a tall, airy crown.
builders.birch = function(model, def, pal, H, F, rng)
	local D = 0.13 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 3, rng)
	local marks = pal.accent or Color3.new(0.15, 0.15, 0.15)
	for _ = 1, 8 do
		local a = rng:range(0, math.pi * 2)
		local y = rng:range(0.8, H * 0.95)
		Kit.decor(
			Kit.part(
				model,
				"BarkMark",
				Vector3.new(D * rng:range(0.35, 0.6), rng:range(0.12, 0.28), 0.12),
				CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -D / 2 + 0.03),
				marks,
				Enum.Material.SmoothPlastic
			),
			false
		)
	end
	Kit.decor(
		Kit.cylinder(
			model,
			"TrunkTop",
			H * 0.5,
			D * 0.7,
			CFrame.new(0, H * 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			def.trunkColor,
			Enum.Material.Wood
		),
		false
	)
	canopy(model, CFrame.new(0, H * 0.92, 0), Vector3.new(F, F * 0.7, F), 4, rng, pal.leaves)
	canopy(
		model,
		CFrame.new(rng:range(-0.6, 0.6), H * 1.22, rng:range(-0.6, 0.6)),
		Vector3.new(F * 0.85, F * 0.7, F * 0.85),
		4,
		rng,
		pal.leaves
	)
	canopy(model, CFrame.new(0, H * 1.5, 0), Vector3.new(F * 0.6, F * 0.6, F * 0.6), 3, rng, pal.leaves)
end

-- Pine: a straight trunk under stacked faceted cones. Every face is two
-- wedges, so the side counts set the part budget (NAT-17, TreeArt.spec):
-- a pine is a trunk, 3 root flares and 4 five-sided tiers (44 parts); a
-- frostwood adds four-sided snow caps on its top two tiers only (60). The
-- lower tiers' tops sit inside the tier above, so caps there barely showed.
TreeArt.ConiferTiers = 4
TreeArt.ConiferSides = 5
TreeArt.SnowCapSides = 4
TreeArt.SnowCappedTiers = 2

local function conifer(model: Model, def: WoodDef, pal: Palette, H: number, F: number, rng: Rng, snow: boolean)
	local D = 0.12 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 3, rng)
	local tiers = TreeArt.ConiferTiers
	local tierH = H * 0.5
	for i = 0, tiers - 1 do
		local y = H * 0.32 + i * H * 0.3
		local r = F / 2 * (1 - i * 0.2)
		local base = CFrame.new(0, y, 0) * CFrame.Angles(0, rng:range(0, math.pi), 0)
		tier(model, base, r, tierH * (1 - i * 0.08), TreeArt.ConiferSides, rng, pal.leaves)
		if snow and i >= tiers - TreeArt.SnowCappedTiers then
			-- A white cap over the top of the tier, a hair outside it.
			local capH = tierH * (1 - i * 0.08) * 0.5
			local capBase = base * CFrame.new(0, tierH * (1 - i * 0.08) - capH + 0.08, 0)
			Kit.cone(model, capBase, r * 0.56, capH + 0.14, TreeArt.SnowCapSides, function(): Color3
				return Kit.vary(pal.accent or Color3.new(1, 1, 1), rng, 0.02)
			end, Enum.Material.Snow, 0.1)
		end
	end
end

builders.pine = function(model, def, pal, H, F, rng)
	conifer(model, def, pal, H, F, rng, false)
end

-- Frostwood: a snow-capped conifer. Its four glass ice shards at the foot
-- went for the 60-part budget (NAT-17): the caps say "snow" from the road,
-- the shards only up close.
builders.frostwood = function(model, def, pal, H, F, rng)
	conifer(model, def, pal, H, F, rng, true)
end

-- Maple: a forked trunk under a wide, flaming autumn crown.
builders.maple = function(model, def, pal, H, F, rng)
	local D = 0.22 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 4, rng)
	local top = Vector3.new(0, H, 0)
	local a = rng:range(0, math.pi)
	for _, side in ipairs({ -1, 1 }) do
		local dir = Vector3.new(math.cos(a) * side, 0, math.sin(a) * side)
		local tip = top + dir * F * 0.28 + Vector3.new(0, H * 0.32, 0)
		branch(model, top - Vector3.new(0, 0.6, 0), tip, D * 0.55, def.trunkColor)
		canopy(
			model,
			CFrame.new(tip + Vector3.new(0, F * 0.12, 0)),
			Vector3.new(F * 0.7, F * 0.5, F * 0.7),
			6,
			rng,
			pal.leaves
		)
	end
	canopy(model, CFrame.new(0, H + F * 0.38, 0), Vector3.new(F * 1.05, F * 0.55, F * 1.05), 9, rng, pal.leaves)
end

-- Palm: a curved, ringed trunk and drooping fronds.
builders.palmwood = function(model, def, pal, H, F, rng)
	local D = 0.11 * H
	trunk(model, def, H * PALM_TRUNK, D * 1.15)
	local lean = rng:range(0.12, 0.22)
	local dir = rng:range(0, math.pi * 2)
	local pos = Vector3.new(0, H * PALM_TRUNK, 0)
	local segments = 5
	for i = 1, segments do
		local t = i / segments
		local step = Vector3.new(math.cos(dir) * lean * t * 3, 1, math.sin(dir) * lean * t * 3).Unit
		local nextPos = pos + step * (H * 0.65 / segments)
		Kit.decor(
			Kit.rod(model, "PalmTrunk", pos, nextPos, D * (1.05 - t * 0.25), def.trunkColor, Enum.Material.Wood),
			false
		)
		Kit.decor(
			Kit.rod(
				model,
				"PalmRing",
				nextPos - step * 0.15,
				nextPos + step * 0.15,
				D * (1.18 - t * 0.25),
				pal.accent or Kit.shade(def.trunkColor, -0.2),
				Enum.Material.Wood
			),
			false
		)
		pos = nextPos
	end
	for i = 1, 7 do
		local a = (i - 1) / 7 * math.pi * 2 + rng:range(-0.2, 0.2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = pos + out * F * 0.32 + Vector3.new(0, 0.9, 0)
		local tip = pos + out * F * 0.62 - Vector3.new(0, F * 0.22, 0)
		for _, seg in ipairs({ { pos, mid }, { mid, tip } }) do
			local leaf = Kit.beam(
				model,
				"Frond",
				seg[1],
				seg[2],
				1.6,
				0.15,
				Kit.vary(rng:pick(pal.leaves), rng, 0.05),
				Enum.Material.SmoothPlastic
			)
			Kit.decor(leaf)
			leaf.CanQuery = true
		end
	end
	for i = 1, 3 do
		local a = i * 2.1
		Kit.decor(
			Kit.ball(
				model,
				"Coconut",
				0.9,
				CFrame.new(pos + Vector3.new(math.cos(a) * 0.6, -0.5, math.sin(a) * 0.6)),
				hex("#6B4A2B"),
				Enum.Material.SmoothPlastic
			),
			false
		)
	end
end

-- Emberwood: a charred, cracked trunk under smouldering, glowing leaves.
builders.emberwood = function(model, def, pal, H, F, rng)
	local D = 0.2 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 5, rng)
	local glow = pal.glow or hex("#FF8A2A")
	-- Glowing cracks running up the bark.
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2 + rng:range(-0.3, 0.3)
		local y0 = rng:range(0.5, H * 0.4)
		local len = rng:range(H * 0.25, H * 0.5)
		Kit.decor(
			Kit.part(
				model,
				"Crack",
				Vector3.new(0.18, len, 0.1),
				CFrame.new(0, y0 + len / 2, 0)
					* CFrame.Angles(0, a, 0)
					* CFrame.new(0, 0, -D / 2 + 0.02)
					* CFrame.Angles(0, 0, rng:range(-0.25, 0.25)),
				glow,
				Enum.Material.Neon
			),
			false
		)
	end
	local top = Vector3.new(0, H, 0)
	local start = rng:range(0, math.pi * 2)
	local lit: Part? = nil
	for i = 1, 3 do
		local a = start + (i - 1) * math.pi * 2 / 3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local elbow = top + dir * F * 0.18 + Vector3.new(0, H * 0.12, 0)
		local tip = elbow + dir * F * 0.22 + Vector3.new(0, H * 0.18, 0)
		branch(model, top - Vector3.new(0, 1, 0), elbow, D * 0.45, def.trunkColor)
		branch(model, elbow, tip, D * 0.32, def.trunkColor)
		local cluster =
			canopy(model, CFrame.new(tip + Vector3.new(0, F * 0.1, 0)), Vector3.one * F * 0.55, 6, rng, pal.leaves)
		cluster[1].Material = Enum.Material.Neon
		cluster[1].Color = glow
		lit = cluster[2]
	end
	local crown =
		canopy(model, CFrame.new(0, H + F * 0.42, 0), Vector3.new(F * 0.75, F * 0.6, F * 0.75), 6, rng, pal.leaves)
	crown[1].Material = Enum.Material.Neon
	crown[1].Color = glow
	glowLight(crown[2], glow, 18, 1.6)
	if lit then
		particles(lit, hex("#FFB050"), 3, 1.5, 2.5, 0.25)
	end
end

-- Phantomwood: a twisted dead tree, wisps of violet and glowing pods.
builders.phantomwood = function(model, def, pal, H, F, rng)
	local D = 0.16 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 5, rng)
	local glow = pal.glow or hex("#55F2E0")
	local top = Vector3.new(0, H, 0)
	local start = rng:range(0, math.pi * 2)
	local tips: { Vector3 } = {}
	for i = 1, 5 do
		local a = start + (i - 1) * math.pi * 2 / 5 + rng:range(-0.25, 0.25)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local y0 = H * rng:range(0.6, 0.95)
		local elbow = Vector3.new(0, y0, 0) + dir * F * 0.2 + Vector3.new(0, H * 0.15, 0)
		local tip = elbow
			+ (dir + Vector3.new(rng:range(-0.4, 0.4), 0, rng:range(-0.4, 0.4))).Unit * F * 0.25
			+ Vector3.new(0, rng:range(-0.5, 1.8), 0)
		branch(model, Vector3.new(0, y0, 0), elbow, D * 0.42, def.trunkColor)
		branch(model, elbow, tip, D * 0.26, def.trunkColor)
		table.insert(tips, tip)
	end
	branch(
		model,
		top - Vector3.new(0, 0.5, 0),
		top + Vector3.new(rng:range(-1, 1), H * 0.3, rng:range(-1, 1)),
		D * 0.4,
		def.trunkColor
	)
	for i, tip in ipairs(tips) do
		local wisp = canopy(model, CFrame.new(tip), Vector3.one * F * 0.38, 2, rng, pal.leaves)
		for _, p in ipairs(wisp) do
			p.Transparency = 0.3
		end
		if i % 2 == 1 then
			local pod = Kit.ball(model, "Pod", 0.8, CFrame.new(tip - Vector3.new(0, 1.6, 0)), glow, Enum.Material.Neon)
			Kit.decor(pod, false)
			Kit.decor(
				Kit.rod(model, "PodStem", tip, tip - Vector3.new(0, 1.3, 0), 0.08, def.trunkColor, Enum.Material.Wood),
				false
			)
		end
	end
	local trunkPart = model.PrimaryPart :: BasePart
	glowLight(trunkPart, pal.accent or hex("#B58CFF"), 16, 0.8)
	particles(trunkPart, glow, 2, 1, 0.6, 0.3)
end

-- Lumenwood: a tall, pale tree with golden veins and a crown of light.
builders.lumenwood = function(model, def, pal, H, F, rng)
	local D = 0.16 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 5, rng)
	local vein = pal.accent or hex("#FFD36A")
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		for s = 0, 2 do
			local y = 1 + s * H * 0.3
			Kit.decor(
				Kit.part(
					model,
					"Vein",
					Vector3.new(0.14, H * 0.32, 0.08),
					CFrame.new(0, y + H * 0.16, 0)
						* CFrame.Angles(0, a + s * 0.5, 0)
						* CFrame.new(0, 0, -D / 2 + 0.02)
						* CFrame.Angles(0, 0, 0.35),
					vein,
					Enum.Material.Neon
				),
				false
			)
		end
	end
	Kit.decor(
		Kit.cylinder(
			model,
			"TrunkTop",
			H * 0.4,
			D * 0.65,
			CFrame.new(0, H * 1.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
			def.trunkColor,
			Enum.Material.Wood
		),
		false
	)
	local glow = pal.glow or hex("#FFE7A0")
	local lower = canopy(model, CFrame.new(0, H + F * 0.15, 0), Vector3.new(F, F * 0.45, F), 6, rng, pal.leaves)
	local upper =
		canopy(model, CFrame.new(0, H + F * 0.55, 0), Vector3.new(F * 0.7, F * 0.5, F * 0.7), 4, rng, pal.leaves)
	canopy(model, CFrame.new(0, H + F * 0.9, 0), Vector3.new(F * 0.35, F * 0.35, F * 0.35), 2, rng, pal.leaves)
	lower[2].Material = Enum.Material.Neon
	lower[2].Color = glow
	upper[1].Material = Enum.Material.Neon
	upper[1].Color = glow
	glowLight(upper[2], glow, 22, 1.8)
	particles(lower[1], glow, 4, 0.8, 1.2, 0.35)
end

-- Fallback for a wood without its own builder: by silhouette.
local function fallback(model: Model, def: WoodDef, pal: Palette, H: number, F: number, rng: Rng)
	if def.silhouette == "pine" then
		conifer(model, def, pal, H, F, rng, false)
	else
		builders.oak(model, def, pal, H, F, rng)
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- A standing tree at the origin (ground at y = 0). `seed` picks its shape
-- variation; `scale` grows or shrinks the whole tree (1 = WoodData size).
function TreeArt.Build(def: WoodDef, seed: number, scale: number?): Model
	local s = scale or 1
	local rng = Kit.rng(seed)
	local model = Instance.new("Model")
	model.Name = "Tree_" .. def.id
	local H, F = def.trunkHeight * s, def.foliageSize * s
	local build = builders[def.id]
	if build then
		build(model, def, TreeArt.Palette(def), H, F, rng)
	else
		fallback(model, def, TreeArt.Palette(def), H, F, rng)
	end
	return model
end

-- How high the HP bar floats above the ground: just over a player's head
-- (an avatar is about 5.3 studs), so it stays on screen while you chop.
TreeArt.BarAboveGround = 7

-- Where the HP bar floats on a tree of this size (TreeService's BarOffset
-- attribute): TreeUI adds it to the Trunk part's centre, half the trunk's
-- length above the ground, so every wood and size class (an Elder too)
-- gets its bar BarAboveGround studs up.
function TreeArt.BarHeight(def: WoodDef, scale: number?): number
	local H = def.trunkHeight * (scale or 1)
	local trunkLength = if def.id == "palmwood" then H * PALM_TRUNK else H
	return TreeArt.BarAboveGround - trunkLength / 2
end

-- A stump's root flares reach 0.77 as far as a standing tree's (0.35-0.5
-- diameters instead of 0.45-0.65).
local STUMP_FLARE_LENGTH = 0.77

-- The stump left behind until the tree regrows.
function TreeArt.Stump(def: WoodDef, seed: number, scale: number?): Model
	local s = scale or 1
	local rng = Kit.rng(seed + 7)
	local model = Instance.new("Model")
	model.Name = "Stump_" .. def.id
	local diameters = {
		oak = 0.24,
		birch = 0.13,
		pine = 0.12,
		maple = 0.22,
		palmwood = 0.13,
		frostwood = 0.12,
		emberwood = 0.2,
		phantomwood = 0.16,
		lumenwood = 0.16,
	}
	local D = (diameters[def.id] or 0.18) * def.trunkHeight * s
	local h = math.max(0.8, D * 0.45)
	local stump = Kit.cylinder(
		model,
		"Stump",
		h,
		D,
		CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		def.trunkColor,
		Enum.Material.Wood
	)
	Kit.decor(stump)
	stump.CanCollide = true -- something to trip over, not a ghost
	local heart = TreeArt.HeartColor(def)
	Kit.decor(
		Kit.cylinder(
			model,
			"StumpTop",
			0.08,
			D * 0.86,
			CFrame.new(0, h + 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2),
			heart,
			Enum.Material.Wood
		),
		false
	)
	Kit.decor(
		Kit.cylinder(
			model,
			"StumpRing",
			0.1,
			D * 0.45,
			CFrame.new(0, h + 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Kit.shade(heart, -0.12),
			Enum.Material.Wood
		),
		false
	)
	-- Below the cut (its tops at most 0.8 of the stump's height, less the
	-- 0.05 they sink), and 0.35-0.5 diameters out.
	rootFlares(model, def.trunkColor, D, 3, rng, h * 0.8, STUMP_FLARE_LENGTH)
	model.PrimaryPart = stump
	return model
end

-- A one-part-per-piece log `length` long (along X) with pale end caps.
-- Caps are welded to LogPart, so moving LogPart moves the whole log.
function TreeArt.Log(def: WoodDef, length: number, diameter: number): Model
	local model = Instance.new("Model")
	model.Name = "Log_" .. def.id
	local log = Kit.cylinder(model, "LogPart", length, diameter, CFrame.identity, def.trunkColor, Enum.Material.Wood)
	log.CanCollide = false
	model.PrimaryPart = log
	TreeArt.AddLogCaps(log, def)
	return model
end

-- Pale end caps (and a glow for rare woods) welded onto a log cylinder.
function TreeArt.AddLogCaps(log: BasePart, def: WoodDef)
	local pal = TreeArt.Palette(def)
	local length, diameter = log.Size.X, log.Size.Y
	local glowing = pal.glow ~= nil and def.id ~= "frostwood"
	for _, side in ipairs({ -1, 1 }) do
		local cap = Kit.cylinder(
			log,
			"LogCap",
			0.06,
			diameter * 0.84,
			log.CFrame * CFrame.new(side * (length / 2 + 0.02), 0, 0),
			if glowing then pal.glow :: Color3 else pal.heart,
			if glowing then Enum.Material.Neon else Enum.Material.Wood
		)
		Kit.decor(cap, false)
		cap.Anchored = false
		cap.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = log
		weld.Part1 = cap
		weld.Parent = cap
	end
end

-- A sapling (the first moment of a regrowing tree, and Sapling Plots).
function TreeArt.Sapling(def: WoodDef, seed: number): Model
	local rng = Kit.rng(seed + 13)
	local pal = TreeArt.Palette(def)
	local model = Instance.new("Model")
	model.Name = "Sapling_" .. def.id
	local stem = Kit.post(model, "Stem", Vector3.zero, 2.2, 0.3, def.trunkColor, Enum.Material.Wood)
	Kit.decor(stem, false)
	if def.silhouette == "pine" then
		Kit.cone(model, CFrame.new(0, 0.8, 0), 0.9, 2.2, 5, function(i: number): Color3
			return pal.leaves[(i - 1) % #pal.leaves + 1]
		end, Enum.Material.SmoothPlastic, 0.08)
	else
		Kit.blob(model, "Leaves", CFrame.new(0, 2.4, 0), Vector3.new(1.6, 1.3, 1.6), 3, rng, pal.leaves)
	end
	model.PrimaryPart = stem
	return model
end

return TreeArt
