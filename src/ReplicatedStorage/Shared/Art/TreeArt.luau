--!strict
-- TreeArt: the low-poly tree, stump, sapling and log models for every wood
-- (GAME_DESIGN §13: every wood has its own silhouette and colour, readable
-- at 50 studs; rare trees are landmarks). Pure (see Kit), so the preview
-- tool draws exactly what the game spawns.
--
-- Crowns are crystal-cut: layered wedges, not Lumber Tycoon cube clusters.
-- The section skeleton (square Section parts, attributes, collision) is
-- unchanged, so chopping still cuts the same wood. Each species keeps its
-- silhouette and adds one signature (TreeArt.Signatures). A seasonal tint
-- and a couple of motes are client extras, and only on the higher quality
-- tiers (TreeArt.Cosmetics).
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
-- The v2 section trees (FromSkeleton, CutFace, Notch, the grown-up
-- Sapling) are at the bottom, with their own contract; Build, Stump and
-- Log stay as they are for the v1 loop until the flip.

local GameConfig = require(script.Parent.Parent.GameConfig)
local TreeGen = require(script.Parent.Parent.TreeGen)
local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)
local TreeMeshes = require(script.Parent.TreeMeshes)

type WoodDef = WoodData.WoodDef
type Rng = Kit.Rng
type Skeleton = TreeGen.Skeleton
type Dress = TreeGen.Dress

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
		-- Deep blue so a frostwood reads against the snowfield (NAT-07).
		leaves = { hex("#3F7FA6"), hex("#4F90B5"), hex("#2F6E96"), hex("#5B9CC0") },
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
	lanternwood = {
		-- Day only. The night neon is WoodData.LanternGlow, swapped on the client.
		leaves = {
			hex(WoodData.LanternLeaf),
			hex(WoodData.LanternLeafShade),
			hex(WoodData.LanternLeafLight),
		},
		heart = hex(WoodData.LanternCore),
	},
}

-- The one detail you can name from the road. The part that carries it has
-- attribute Signature set to this (a leaf wedge, a bark strip, a snow cap).
TreeArt.Signatures = {
	oak = "sap-knot", -- a heartwood facet in the crown, the cut showing the wood
	birch = "bark-stripe", -- dark bands across the white trunk
	pine = "resin-facet", -- one lighter facet on each needle tier
	maple = "flame-plate", -- a bright plate on the flat autumn crown
	palmwood = "cut-frond", -- a wedge frond, wide at the stem and sharp at the tip
	frostwood = "frost-tip", -- snow wedges on the upper tiers
	emberwood = "ember-vein", -- neon cracks in the charred bark
	phantomwood = "wisp-shard", -- a glowing pod under a glass shard
	lumenwood = "light-plate", -- a golden vein, and flat crystal plates
	lanternwood = "heart-band", -- a thin collar that goes neon at night, on the client
} :: { [string]: string }

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

-- One season is two in-game days.
-- 0 spring, 1 summer (the painted colours), 2 autumn, 3 winter.
TreeArt.SeasonSeconds = 2 * GameConfig.DayCycleMinutes * 60

function TreeArt.SeasonIndex(unix: number): number
	local len = TreeArt.SeasonSeconds
	if len <= 0 then
		return 1
	end
	return math.floor(unix / len) % 4
end

-- A gentle shift of a leaf colour toward the season. `amount` is 0..1
-- (the quality tier's tint). Summer, and amount 0, leave the colour as painted.
function TreeArt.TintLeaf(color: Color3, woodId: string, season: number, amount: number): Color3
	if amount <= 0 or season == 1 then
		return color
	end
	local target: Color3
	local strength: number
	if season == 2 then
		target = Color3.fromRGB(196, 112, 42)
		strength = if woodId == "maple" then 0.28 elseif woodId == "oak" or woodId == "birch" then 0.16 else 0.05
	elseif season == 3 then
		target = Color3.fromRGB(150, 176, 198)
		strength = if woodId == "pine" or woodId == "frostwood" then 0.2 else 0.06
	else
		target = Color3.fromRGB(176, 206, 96)
		strength = if woodId == "oak" or woodId == "birch" or woodId == "pine" then 0.12 else 0.04
	end
	local t = math.clamp(strength * amount, 0, 1)
	return Color3.new(
		color.R + (target.R - color.R) * t,
		color.G + (target.G - color.G) * t,
		color.B + (target.B - color.B) * t
	)
end

export type Cosmetics = { tint: number, accents: boolean }

-- What a quality tier (Shared/QualityBudgets, PLAY-05) may add on top of
-- the server-built crown. Low (phones) adds nothing. Medium tints.
-- High tints and may hang one mote on maple and frostwood. Never a new part.
function TreeArt.Cosmetics(tier: string): Cosmetics
	if tier == "low" then
		return { tint = 0, accents = false }
	elseif tier == "medium" then
		return { tint = 0.55, accents = false }
	end
	return { tint = 1, accents = true }
end

-- A high-quality mote, only for woods that don't already drift sparks.
function TreeArt.AccentColor(woodId: string): Color3?
	if woodId == "frostwood" then
		return hex("#E7F6FF")
	elseif woodId == "maple" then
		return hex("#E5A33B")
	end
	return nil
end

-- The dust a felled tree throws up, by the ground of its home biome
-- (TreeFX): earth in the forests, sand on the coast, powder snow, volcanic
-- ash, the Gloam Hollow's violet loam, pale isle soil.
local EARTH_DUST = Color3.fromRGB(196, 174, 140)
local DUST: { [string]: Color3 } = {
	starter = EARTH_DUST,
	hills = Color3.fromRGB(198, 168, 128),
	island = Color3.fromRGB(228, 210, 164),
	snow = Color3.fromRGB(242, 246, 250),
	volcano = Color3.fromRGB(118, 112, 108),
	grove = Color3.fromRGB(150, 138, 168),
	sky = Color3.fromRGB(236, 228, 198),
	-- Ferry shore, not the palm coast's sand and not the forest's earth.
	ferryisle = Color3.fromRGB(214, 196, 150),
	-- Lane R: the Bayou's dark silt, Red Mesa's red sandstone grit.
	bayou = Color3.fromRGB(92, 82, 58),
	mesa = Color3.fromRGB(200, 124, 84),
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

-- Filled in below, once the dress box helpers exist. Called when a tree
-- is built, which is after this module has finished loading.
local crystalCluster: (
	parent: Instance,
	name: string,
	d: Dress,
	colors: { Color3 },
	transparency: number?,
	woodId: string,
	material: Enum.Material,
	knot: Color3?
) -> { BasePart }

-- A crystal-cut canopy that can be clicked (so pointing at the leaves
-- targets the tree) but doesn't collide. `count` wedges, the same budget
-- the cube blob used to spend.
local function canopy(
	model: Model,
	center: CFrame,
	size: Vector3,
	count: number,
	rng: Rng,
	colors: { Color3 },
	woodId: string?
): { BasePart }
	local id = woodId or "oak"
	local def = WoodData.Get(id)
	local knot = if def and id == "oak" then TreeArt.HeartColor(def) else nil
	local parts = crystalCluster(model, "Leaves", {
		kind = "leaves",
		section = 0,
		cf = center,
		size = size,
		parts = count,
		seed = rng:int(1, 1000000),
	}, colors, nil, id, Enum.Material.SmoothPlastic, knot)
	for _, p in ipairs(parts) do
		p.CanCollide = false
		p.CanTouch = false
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
	canopy(model, CFrame.new(0, H + F * 0.32, 0), Vector3.new(F, F * 0.72, F), 9, rng, pal.leaves, "oak")
	local start = rng:range(0, math.pi * 2)
	for i = 1, 3 do
		local a = start + (i - 1) * math.pi * 2 / 3 + rng:range(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = top + dir * F * 0.42 + Vector3.new(0, F * rng:range(0.05, 0.25), 0)
		branch(model, top - Vector3.new(0, H * 0.18, 0), tip, D * 0.38, def.trunkColor)
		canopy(model, CFrame.new(tip + Vector3.new(0, F * 0.08, 0)), Vector3.one * F * 0.52, 3, rng, pal.leaves, "oak")
	end
end

-- Birch: a slim white trunk with dark marks and a tall, airy crown.
builders.birch = function(model, def, pal, H, F, rng)
	local D = 0.13 * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, 3, rng)
	local marks = pal.accent or Color3.new(0.15, 0.15, 0.15)
	for _ = 1, 6 do
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
	canopy(model, CFrame.new(0, H * 0.92, 0), Vector3.new(F, F * 0.7, F), 4, rng, pal.leaves, "birch")
	canopy(
		model,
		CFrame.new(rng:range(-0.6, 0.6), H * 1.22, rng:range(-0.6, 0.6)),
		Vector3.new(F * 0.85, F * 0.7, F * 0.85),
		4,
		rng,
		pal.leaves,
		"birch"
	)
	canopy(model, CFrame.new(0, H * 1.5, 0), Vector3.new(F * 0.6, F * 0.6, F * 0.6), 3, rng, pal.leaves, "birch")
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
-- A cap's base radius, as a fraction of its tier's: narrow enough that the
-- blue shows under it (NAT-07; it was 0.56).
TreeArt.SnowCapRadius = 0.45

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
			-- A white cap over the top of the tier. It starts where the tier
			-- has narrowed to the cap's width (its corners a hair outside),
			-- so blue shows under it and its tip clears the tier's by 0.22.
			local h = tierH * (1 - i * 0.08)
			local capFrom = h * (1 - TreeArt.SnowCapRadius * 0.72)
			local capBase = base * CFrame.new(0, capFrom, 0)
			Kit.cone(
				model,
				capBase,
				r * TreeArt.SnowCapRadius,
				h - capFrom + 0.22,
				TreeArt.SnowCapSides,
				function(): Color3
					return Kit.vary(pal.accent or Color3.new(1, 1, 1), rng, 0.02)
				end,
				Enum.Material.Snow,
				0.1
			)
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
			pal.leaves,
			"maple"
		)
	end
	canopy(
		model,
		CFrame.new(0, H + F * 0.38, 0),
		Vector3.new(F * 1.05, F * 0.55, F * 1.05),
		9,
		rng,
		pal.leaves,
		"maple"
	)
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
			local from, to = seg[1], seg[2]
			local length = math.max((to - from).Magnitude, 0.2)
			local leaf = Kit.wedge(
				model,
				"Frond",
				Vector3.new(1.7, 0.42, length),
				CFrame.lookAt((from + to) / 2, to, Vector3.yAxis),
				Kit.vary(rng:pick(pal.leaves), rng, 0.05),
				Enum.Material.SmoothPlastic
			)
			leaf:SetAttribute("Signature", TreeArt.Signatures.palmwood)
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
	local lit: BasePart? = nil
	for i = 1, 3 do
		local a = start + (i - 1) * math.pi * 2 / 3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local elbow = top + dir * F * 0.18 + Vector3.new(0, H * 0.12, 0)
		local tip = elbow + dir * F * 0.22 + Vector3.new(0, H * 0.18, 0)
		branch(model, top - Vector3.new(0, 1, 0), elbow, D * 0.45, def.trunkColor)
		branch(model, elbow, tip, D * 0.32, def.trunkColor)
		local cluster = canopy(
			model,
			CFrame.new(tip + Vector3.new(0, F * 0.1, 0)),
			Vector3.one * F * 0.55,
			6,
			rng,
			pal.leaves,
			"emberwood"
		)
		cluster[1].Material = Enum.Material.Neon
		cluster[1].Color = glow
		lit = cluster[2]
	end
	local crown = canopy(
		model,
		CFrame.new(0, H + F * 0.42, 0),
		Vector3.new(F * 0.75, F * 0.6, F * 0.75),
		6,
		rng,
		pal.leaves,
		"emberwood"
	)
	crown[1].Material = Enum.Material.Neon
	crown[1].Color = glow
	glowLight(crown[2], glow, 18, 1.6)
	if lit then
		particles(lit, hex("#FFB050"), 2, 1.5, 2.5, 0.25)
	end
end

-- Gloamwood: a twisted dead tree, wisps of violet and glowing pods.
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
	local lower =
		canopy(model, CFrame.new(0, H + F * 0.15, 0), Vector3.new(F, F * 0.45, F), 6, rng, pal.leaves, "lumenwood")
	local upper = canopy(
		model,
		CFrame.new(0, H + F * 0.55, 0),
		Vector3.new(F * 0.7, F * 0.5, F * 0.7),
		4,
		rng,
		pal.leaves,
		"lumenwood"
	)
	canopy(
		model,
		CFrame.new(0, H + F * 0.9, 0),
		Vector3.new(F * 0.35, F * 0.35, F * 0.35),
		2,
		rng,
		pal.leaves,
		"lumenwood"
	)
	lower[2].Material = Enum.Material.Neon
	lower[2].Color = glow
	upper[1].Material = Enum.Material.Neon
	upper[1].Color = glow
	glowLight(upper[2], glow, 22, 1.8)
	particles(lower[1], glow, 8, 0.8, 1.2, 0.35)
end

-- Lanternwood's v1 silhouette.
local LANTERN_TRUNK = 0.18 -- trunk diameter over its height
local LANTERN_CROWN_LIFT = 0.28 -- of the crown size, above the trunk
local LANTERN_CROWN_Y = 0.7 -- crown height over its width
local LANTERN_LEAF_PARTS = 8
local LANTERN_FLARES = 4

-- Lanternwood: a plain broadleaf by day. Leaves and a thin core band are
-- marked for the client to turn neon at night. No server light, no Neon.
builders.lanternwood = function(model, def, pal, H, F, rng)
	local D = LANTERN_TRUNK * H
	trunk(model, def, H, D)
	rootFlares(model, def.trunkColor, D, LANTERN_FLARES, rng)
	local leaves = canopy(
		model,
		CFrame.new(0, H + F * LANTERN_CROWN_LIFT, 0),
		Vector3.new(F, F * LANTERN_CROWN_Y, F),
		LANTERN_LEAF_PARTS,
		rng,
		pal.leaves,
		def.id
	)
	for _, leaf in ipairs(leaves) do
		leaf:SetAttribute("NightGlow", true)
	end
	local thin = math.max(TreeGen.CoreBandMin, D * TreeGen.CoreBandThin)
	local band = Kit.decor(
		Kit.cylinder(
			model,
			"CoreBand",
			thin,
			D * TreeGen.CoreBandOver,
			CFrame.new(0, H * TreeGen.CoreBandAlong, 0) * CFrame.Angles(0, 0, math.pi / 2),
			def.trunkColor,
			Enum.Material.Wood
		),
		false
	)
	band:SetAttribute("Signature", TreeArt.Signatures.lanternwood)
	band:SetAttribute("NightGlow", true)
	model:AddTag("Lanternwood")
	model:SetAttribute("NightHost", "tree")
	model:SetAttribute("WoodId", def.id)
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
-- Given `growth` (0-1, the v2 loop), the grown-up sapling instead: see
-- the section trees below.
function TreeArt.Sapling(def: WoodDef, seed: number, growth: number?): Model
	if growth ~= nil then
		return TreeArt.GrowingSapling(def, seed, growth)
	end
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
		local leaves = canopy(model, CFrame.new(0, 2.4, 0), Vector3.new(1.6, 1.3, 1.6), 3, rng, pal.leaves, def.id)
		for _, leaf in ipairs(leaves) do
			leaf.CanQuery = false
		end
	end
	model.PrimaryPart = stem
	return model
end

---------------------------------------------------------------------------
-- v2: section trees (V2_PLAN.md §3c, §3e), built from a TreeGen skeleton
---------------------------------------------------------------------------
-- Contract with SectionTrees / WoodService / WoodFX / CutController (M1.3):
--   * FromSkeleton returns a Model tagged "Tree" (ModelStreamingMode
--     Atomic) whose PrimaryPart is section 1. Each section is a Block named
--     "Section" (tag "WoodSection", attribute Section = its id), its length
--     up the part's Y axis, bark-coloured (Wood, or SmoothPlastic / Concrete
--     for the pale and glassy woods — TreeArt.BarkMaterial), anchored, colliding,
--     queryable, untouchable, in collision group "Wood".
--   * Everything else is dress: parts named Leaves, Frond or Facet (inside
--     "Tier" models too: WindSway and CanopyFade find those names), Root,
--     BarkMark, Crack, Vein, CoreBand, PalmRing, Coconut, Pod, PodStem. Every dress
--     part has attribute Section (the section it rides on), never collides
--     or fires touches, can be queried (pointing at leaves finds the tree),
--     and sits in collision group "Leaves". The server's sight ray is in
--     group Wood, so the crown doesn't block it; the client's pointer ray
--     is not, so a click on the crown still finds this tree.
--   * Model attributes: WoodId, Seed, Stage, Scale, Elder, Felled, Dormant,
--     and Uid when given; the service adds HomePivot once the tree is placed.
--     Lanternwood also carries tag Lanternwood and NightHost "tree".
--   * The wood's core (WoodData v2.core and coreMaterial) shows only on cut
--     faces (CutFace) and in notches (Notch).

TreeArt.WoodGroup = "Wood"
TreeArt.LeavesGroup = "Leaves"
TreeArt.CutFaceThickness = 0.06
TreeArt.CutFaceInset = 0.86 -- of the section's width
TreeArt.NotchHeight = 0.35
TreeArt.NotchMaxDepth = 0.95 -- of the section's width
TreeArt.NotchShade = -0.25

-- Bark on a standing section. Most woods stay Wood (grain reads as bark).
-- Frostwood and lumenwood are pale enough that Wood's grain muddies them,
-- so they go SmoothPlastic; phantomwood's glassy bark is Concrete.
function TreeArt.BarkMaterial(def: WoodDef): Enum.Material
	if def.id == "frostwood" or def.id == "lumenwood" then
		return Enum.Material.SmoothPlastic
	elseif def.id == "phantomwood" then
		return Enum.Material.Concrete
	end
	return Enum.Material.Wood
end

-- The wood's core colour and material (cut faces, notches, planks).
function TreeArt.Core(def: WoodDef): (Color3, Enum.Material)
	local v2 = def.v2
	if not v2 then
		return TreeArt.HeartColor(def), Enum.Material.Wood
	end
	local material = Enum.Material.Wood
	local ok, found = pcall(function(): any
		return (Enum.Material :: any)[v2.coreMaterial]
	end)
	if ok and typeof(found) == "EnumItem" then
		material = found :: any
	end
	return Color3.fromHex(v2.core), material
end

local function hexList(list: { string }): { Color3 }
	local out: { Color3 } = {}
	for i, h in ipairs(list) do
		out[i] = Color3.fromHex(h)
	end
	return out
end

-- What a section tree is painted with: WoodData v2.shape's colours (today's
-- palettes), the palette's glow and accent where the shape has none.
type Paint = {
	bark: Color3,
	leaves: { Color3 },
	accent: Color3,
	glow: Color3?,
}

local function paintOf(def: WoodDef): Paint
	local pal = TreeArt.Palette(def)
	local v2 = def.v2
	local shape = v2 and v2.shape
	if not shape then
		return {
			bark = def.trunkColor,
			leaves = pal.leaves,
			accent = pal.accent or Kit.shade(def.trunkColor, -0.3),
			glow = pal.glow,
		}
	end
	return {
		bark = Color3.fromHex(shape.bark),
		leaves = hexList(shape.leafColors),
		accent = if shape.accent then Color3.fromHex(shape.accent) else pal.accent or Kit.shade(def.trunkColor, -0.3),
		glow = if shape.glow then Color3.fromHex(shape.glow) else pal.glow,
	}
end

-- Dress never collides or fires touches, can be queried, rides its section.
local function asDress(p: BasePart, section: number): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CollisionGroup = TreeArt.LeavesGroup
	p:SetAttribute("Section", section)
	local s = p.Size
	if math.max(s.X, s.Y, s.Z) < 1 then
		p.CastShadow = false
	end
	return p
end

-- The half-size, along the axes of `frame`, of a box `size` turned `rot`.
local function extents(rot: CFrame, size: Vector3): Vector3
	local x, y, z = rot.XVector, rot.YVector, rot.ZVector
	return Vector3.new(
		math.abs(x.X) * size.X + math.abs(y.X) * size.Y + math.abs(z.X) * size.Z,
		math.abs(x.Y) * size.X + math.abs(y.Y) * size.Y + math.abs(z.Y) * size.Z,
		math.abs(x.Z) * size.X + math.abs(y.Z) * size.Y + math.abs(z.Z) * size.Z
	) / 2
end

-- The lightest and darkest of a leaf palette, so a crown alternates
-- instead of blending into one mid green.
local function lightDark(colors: { Color3 }): (Color3, Color3)
	local function lum(c: Color3): number
		return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
	end
	local light, dark = colors[1], colors[1]
	for _, c in ipairs(colors) do
		if lum(c) > lum(light) then
			light = c
		end
		if lum(c) < lum(dark) then
			dark = c
		end
	end
	return light, dark
end

-- How a species cuts the wedges inside a crown box. The box is still the
-- silhouette; the cut is what you see instead of a cube.
type Cut = { pitch: number, wide: number, tall: number, deep: number, jag: number }

local CUTS: { [string]: Cut } = {
	-- Narrow wedges with a steep pitch: the slope reads as a cut face,
	-- not a cube, while the tips still sit on the dress box.
	oak = { pitch = 1.02, wide = 0.58, tall = 0.66, deep = 0.42, jag = 0.08 },
	birch = { pitch = 1.12, wide = 0.46, tall = 1.15, deep = 0.36, jag = 0.05 },
	maple = { pitch = 0.48, wide = 1.15, tall = 0.32, deep = 0.55, jag = 0.05 },
	emberwood = { pitch = 1.05, wide = 0.5, tall = 0.72, deep = 0.38, jag = 0.24 },
	phantomwood = { pitch = 1.15, wide = 0.38, tall = 1.28, deep = 0.32, jag = 0.08 },
	lumenwood = { pitch = 0.34, wide = 1.05, tall = 0.28, deep = 0.5, jag = 0.04 },
}

local function cutFor(woodId: string, flat: boolean?): Cut
	if flat then
		return { pitch = 0.38, wide = 1.05, tall = 0.28, deep = 0.48, jag = 0.04 }
	end
	return CUTS[woodId] or CUTS.oak
end

-- Directions that push a facet out to the dress box, so the silhouette
-- stays what TreeGen measured. The first six fill the box; the rest are
-- the species' crystal habit on top of that.
local FILL: { Vector3 } = {
	Vector3.yAxis,
	Vector3.new(0, -0.2, 0),
	Vector3.new(1, 0.12, 0),
	Vector3.new(-1, 0.12, 0),
	Vector3.new(0, 0.12, 1),
	Vector3.new(0, 0.12, -1),
	Vector3.new(0.78, 0.55, 0.78),
	Vector3.new(-0.78, 0.55, 0.78),
	Vector3.new(0.78, -0.28, -0.78),
	Vector3.new(-0.78, -0.28, 0.78),
}

local function facetDir(woodId: string, i: number, n: number, ang: number): Vector3
	local base = if i <= #FILL then FILL[i] else FILL[(i - 1) % #FILL + 1]
	-- The first six facets sit on the box, so the silhouette TreeGen measured
	-- still holds. Anything past that is the species' crystal habit.
	if i <= 6 then
		return base
	end
	local u = if n <= 1 then 0.5 else (i - 1) / (n - 1)
	if woodId == "birch" or woodId == "phantomwood" then
		return Vector3.new(base.X * 0.7, math.clamp(u * 2 - 1, -1, 1), base.Z * 0.7)
	elseif woodId == "maple" or woodId == "lumenwood" then
		return Vector3.new(base.X, base.Y * 0.2, base.Z)
	elseif woodId == "oak" then
		local out = 0.55 + 0.45 * math.sin(u * math.pi)
		return Vector3.new(math.cos(ang) * out, math.clamp((u - 0.4) * 1.4, -1, 1), math.sin(ang) * out)
	elseif woodId == "emberwood" then
		local j = 0.7 + 0.3 * math.sin(ang * 3)
		return Vector3.new(base.X * j, base.Y, base.Z * j)
	end
	return base
end

-- `d.parts` wedges inside the dress box (its centre is `d.cf`). Does not
-- set collision: the caller does, because a v1 canopy and a section tree
-- don't share a collision group.
crystalCluster = function(
	parent: Instance,
	name: string,
	d: Dress,
	colors: { Color3 },
	transparency: number?,
	woodId: string,
	material: Enum.Material,
	knot: Color3?
): { BasePart }
	local rng = Kit.rng(d.seed)
	local half = d.size / 2
	local n = math.max(1, d.parts)
	local cut = cutFor(woodId, d.flat)
	local light, dark = lightDark(colors)
	local side = (d.size.X + d.size.Z) / 2
	local spin = rng:range(0, math.pi * 2)
	local out: { BasePart } = {}
	for i = 1, n do
		local ang = spin + (i - 1) / n * math.pi * 2
		local dir = facetDir(woodId, i, n, ang)
		-- Slope faces outward: the low edge of the wedge points out of the crown.
		local rot = CFrame.Angles(0, ang, 0) * CFrame.Angles(-cut.pitch, 0, 0)
		local frac = if i == 1 then math.clamp(0.64 - 0.02 * n, 0.48, 0.64) else rng:range(0.4, 0.52)
		local jag = 1 + rng:range(-cut.jag, cut.jag)
		local c = math.min(side * frac, d.grain or math.huge) * jag
		local dims = Vector3.new(c * cut.wide, math.min(c * cut.tall, d.size.Y * 0.92), c * cut.deep)
		local e = extents(rot, dims)
		local fit =
			math.min(1, half.X / math.max(e.X, 1e-4), half.Y / math.max(e.Y, 1e-4), half.Z / math.max(e.Z, 1e-4))
		dims *= fit
		e *= fit
		local room = half - e
		local reach = if i <= 2 then 1 else 0.94
		local offset = Vector3.new(dir.X * room.X, dir.Y * room.Y, dir.Z * room.Z) * reach
		local color = Kit.vary(if i % 2 == 0 then dark else light, rng, 0.06)
		local mat = material
		local signature: string? = nil
		if i == n and knot then
			color = knot
			mat = Enum.Material.Wood
			signature = TreeArt.Signatures.oak
		elseif woodId == "maple" and i == n then
			color = light
			signature = TreeArt.Signatures.maple
		end
		local p = Kit.wedge(parent, name, dims, d.cf * CFrame.new(offset) * rot, color, mat)
		p.CanCollide = false
		p.CanTouch = false
		if transparency then
			p.Transparency = transparency
		end
		if signature then
			p:SetAttribute("Signature", signature)
		end
		table.insert(out, p)
	end
	return out
end

local function leafCluster(
	model: Instance,
	name: string,
	d: Dress,
	colors: { Color3 },
	transparency: number?,
	woodId: string,
	knot: Color3?
): { BasePart }
	local parts = crystalCluster(model, name, d, colors, transparency, woodId, Enum.Material.SmoothPlastic, knot)
	for _, p in ipairs(parts) do
		asDress(p, d.section)
	end
	return parts
end

-- A conifer tier (or a snow cap) as a ring of crystal wedges. `d.cf` is
-- the tier's base; centres sit at 0.42 of the radius, so a stack of tiers
-- still narrows. Named Facet, so WindSway and the tier tests find them.
-- Exactly `d.parts` wedges (a tier's budget is sides * 2).
local function coneDress(
	parent: Instance,
	d: Dress,
	colors: { Color3 },
	material: Enum.Material,
	woodId: string
): { BasePart }
	local rng = Kit.rng(d.seed)
	local n = math.max(1, d.parts)
	local radius = d.size.X / 2
	local height = d.size.Y
	local reach = math.max(0.35, radius * 0.42)
	local light, dark = lightDark(colors)
	local spin = rng:range(0, math.pi * 2)
	local snow = material == Enum.Material.Snow
	local pitch = if snow then 0.85 else 0.62
	local boxMin = Vector3.new(-radius, 0, -radius)
	local boxMax = Vector3.new(radius, height, radius)
	local made: { BasePart } = {}
	for i = 1, n do
		local ang = spin + (i - 1) / n * math.pi * 2
		local rot = CFrame.Angles(0, ang, 0) * CFrame.Angles(pitch, 0, 0)
		local wide = math.max(0.55, math.min(radius * 0.62, height * 0.75))
		local deep = math.max(0.4, radius * 0.46)
		local dims = Vector3.new(wide, height * 0.9, deep)
		local want = Vector3.new(math.cos(ang) * reach, height * 0.5, math.sin(ang) * reach)
		local e = extents(rot, dims)
		local function axisFit(center: number, ext: number, lo: number, hi: number): number
			if ext < 1e-4 then
				return 1
			end
			local s = 1
			if center + ext > hi then
				s = math.min(s, math.max(0, (hi - center) / ext))
			end
			if center - ext < lo then
				s = math.min(s, math.max(0, (center - lo) / ext))
			end
			return s
		end
		local fit = math.min(
			1,
			axisFit(want.X, e.X, boxMin.X, boxMax.X),
			axisFit(want.Y, e.Y, boxMin.Y, boxMax.Y),
			axisFit(want.Z, e.Z, boxMin.Z, boxMax.Z)
		)
		dims *= math.max(fit, 0.15)
		local color = Kit.vary(if i % 2 == 0 then dark else light, rng, if snow then 0.02 else 0.05)
		local p = Kit.wedge(parent, "Facet", dims, d.cf * CFrame.new(want) * rot, color, material)
		if snow then
			p:SetAttribute("Signature", TreeArt.Signatures.frostwood)
		elseif woodId == "pine" and i == 1 then
			p.Color = light
			p:SetAttribute("Signature", TreeArt.Signatures.pine)
		elseif woodId == "pine" and i == 2 and d.size.X > 14 then
			-- A brown needle disc on the wide bottom tier. Not the signature facet.
			p.Color = Kit.hex("#6B5A3A")
		end
		asDress(p, d.section)
		table.insert(made, p)
	end
	return made
end

local function addLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- One dress entry's parts. Returns them (the first is where a light goes).
local function buildDress(model: Model, def: WoodDef, paint: Paint, d: Dress): { BasePart }
	local kind = d.kind
	local glow = paint.glow or paint.accent
	if kind == "leaves" then
		local knot = if def.id == "oak" then TreeArt.HeartColor(def) else nil
		local parts = leafCluster(model, "Leaves", d, paint.leaves, nil, def.id, knot)
		if d.glow and parts[1] then
			-- One facet glows through the cuts (never a whole crown).
			parts[1].Material = Enum.Material.Neon
			parts[1].Color = glow
		elseif def.id == WoodData.LanternId then
			-- Day colour stays. The client swaps these to neon at night.
			for _, leaf in ipairs(parts) do
				leaf:SetAttribute("NightGlow", true)
			end
		end
		return parts
	elseif kind == "wisp" then
		return leafCluster(model, "Leaves", d, paint.leaves, 0.3, def.id, nil)
	elseif kind == "tier" then
		local tierModel = Instance.new("Model")
		tierModel.Name = "Tier"
		tierModel:SetAttribute("Section", d.section)
		tierModel.Parent = model
		return coneDress(tierModel, d, paint.leaves, Enum.Material.SmoothPlastic, def.id)
	elseif kind == "cap" then
		return coneDress(model, d, { paint.accent }, Enum.Material.Snow, def.id)
	elseif kind == "frond" then
		local pts = d.points or { d.cf.Position, d.cf.Position + Vector3.yAxis }
		local rng = Kit.rng(d.seed)
		local out: { BasePart } = {}
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local length = math.max((b - a).Magnitude, 0.2)
			local width = d.size.X * (if i == 1 then 1 else 0.72)
			local leaf = Kit.wedge(
				model,
				"Frond",
				Vector3.new(width, math.max(d.size.Y * 2.4, 0.32), length),
				CFrame.lookAt((a + b) / 2, b, Vector3.yAxis),
				Kit.vary(rng:pick(paint.leaves), rng, 0.05),
				Enum.Material.SmoothPlastic
			)
			leaf:SetAttribute("Signature", TreeArt.Signatures.palmwood)
			table.insert(out, asDress(leaf, d.section))
		end
		return out
	elseif kind == "coconut" then
		return { asDress(Kit.ball(model, "Coconut", d.size.X, d.cf, hex("#6B4A2B")), d.section) }
	elseif kind == "ring" then
		return { asDress(Kit.part(model, "PalmRing", d.size, d.cf, paint.accent, Enum.Material.Wood), d.section) }
	elseif kind == "pod" then
		local ball = d.size.X
		local stemTop = d.cf.Position + Vector3.new(0, d.size.Y - ball / 2, 0)
		local pod = Kit.ball(model, "Pod", ball, d.cf, glow, Enum.Material.Neon)
		pod:SetAttribute("Signature", TreeArt.Signatures.phantomwood)
		local stem = Kit.rod(
			model,
			"PodStem",
			stemTop,
			d.cf.Position + Vector3.new(0, ball * 0.4, 0),
			0.1,
			paint.bark,
			Enum.Material.Wood
		)
		return { asDress(pod, d.section), asDress(stem, d.section) }
	elseif kind == "flare" then
		local rng = Kit.rng(d.seed)
		local p = Kit.wedge(
			model,
			"Root",
			d.size,
			d.cf,
			Kit.vary(Kit.shade(paint.bark, -0.08), rng, 0.03),
			Enum.Material.Wood
		)
		return { asDress(p, d.section) }
	elseif kind == "mark" then
		-- A birch stripe: a thin dark band across the face, wider than the
		-- dash TreeGen sized, still one part.
		local wide = math.max(d.size.X * 1.85, 0.45)
		local thin = math.max(0.06, math.min(d.size.Y, 0.16))
		local mark =
			Kit.part(model, "BarkMark", Vector3.new(wide, thin, 0.05), d.cf, paint.accent, Enum.Material.SmoothPlastic)
		mark:SetAttribute("Signature", TreeArt.Signatures.birch)
		return { asDress(mark, d.section) }
	elseif kind == "crack" then
		local crack = Kit.part(model, "Crack", d.size, d.cf, glow, Enum.Material.Neon)
		crack:SetAttribute("Signature", TreeArt.Signatures.emberwood)
		return { asDress(crack, d.section) }
	elseif kind == "vein" then
		local vein = paint.accent
		if def.id == "lumenwood" then
			vein = TreeArt.Palette(def).accent or vein
		end
		local strip = Kit.part(model, "Vein", d.size, d.cf, vein, Enum.Material.Neon)
		strip:SetAttribute("Signature", TreeArt.Signatures.lumenwood)
		return { asDress(strip, d.section) }
	elseif kind == "coreband" then
		-- Day bark colour and Wood. The client turns it neon at night.
		local band = Kit.cylinder(model, "CoreBand", d.size.X, d.size.Y, d.cf, paint.bark, Enum.Material.Wood)
		band:SetAttribute("Signature", TreeArt.Signatures.lanternwood)
		band:SetAttribute("NightGlow", true)
		return { asDress(band, d.section) }
	end
	return {}
end

export type SkeletonOptions = {
	uid: string?,
	only: { [number]: boolean }?, -- build just these sections (a piece) and their dress
}

-- A section tree (see the contract above), built around the origin with
-- the ground at y = 0.
function TreeArt.FromSkeleton(def: WoodDef, skel: Skeleton, opts: SkeletonOptions?): Model
	local o: SkeletonOptions = opts or {}
	local only = o.only
	local paint = paintOf(def)
	local rng = Kit.rng(skel.seed + 61)
	local model = Instance.new("Model")
	model.Name = "Tree_" .. def.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("Tree")
	model:SetAttribute("WoodId", def.id)
	model:SetAttribute("Seed", skel.seed)
	model:SetAttribute("Stage", skel.stage)
	model:SetAttribute("Scale", skel.scale)
	model:SetAttribute("Elder", skel.elder)
	model:SetAttribute("Felled", false)
	model:SetAttribute("Dormant", false)
	if def.id == WoodData.LanternId then
		model:AddTag("Lanternwood")
		model:SetAttribute("NightHost", "tree")
	end
	if o.uid then
		model:SetAttribute("Uid", o.uid)
	end
	local first: BasePart? = nil
	local lit: { BasePart } = {}
	for _, sec in ipairs(skel.sections) do
		if only and not only[sec.id] then
			continue
		end
		local p = Kit.part(
			model,
			"Section",
			Vector3.new(sec.thickness, sec.length, sec.thickness),
			sec.cf * CFrame.new(0, sec.length / 2, 0),
			Kit.vary(paint.bark, rng, 0.04),
			TreeArt.BarkMaterial(def)
		)
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = false
		p.CollisionGroup = TreeArt.WoodGroup
		p:SetAttribute("Section", sec.id)
		p:AddTag("WoodSection")
		first = first or p
		for _, d in ipairs(sec.dress) do
			local parts = buildDress(model, def, paint, d)
			if d.glow and parts[2] then
				table.insert(lit, parts[2])
			end
		end
	end
	model.PrimaryPart = first
	-- Lights and drifting motes, where today's trees have them (no shadows).
	local glow = paint.glow
	if glow and first then
		if def.id == "emberwood" then
			if lit[1] then
				addLight(lit[1], glow, 18, 1.6)
				particles(lit[#lit], hex("#FFB050"), 3, 1.5, 2.5, 0.25)
			end
		elseif def.id == "phantomwood" then
			addLight(first, TreeArt.Palette(def).accent or hex("#B58CFF"), 16, 0.8)
			particles(first, glow, 2, 1, 0.6, 0.3)
		elseif def.id == "lumenwood" then
			if lit[1] then
				addLight(lit[1], glow, 22, 1.8)
				particles(lit[#lit], glow, 4, 0.8, 1.2, 0.35)
			end
		end
	end
	-- Uploaded meshes when every one loads. A miss keeps this part-built tree.
	TreeMeshes.Apply(model, def, skel)
	return model
end

-- A section part's thickness (the square's side).
local function widthOf(section: BasePart): number
	return math.min(section.Size.X, section.Size.Z)
end

-- Anchored on a standing section, welded and massless on a loose one.
local function ride(p: BasePart, section: BasePart)
	p.Massless = true
	if section.Anchored then
		p.Anchored = true
		return
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = section
	weld.Part1 = p
	weld.Parent = p
	p.Anchored = false
end

-- The fresh face on one end of a cut section (`top` = its +Y end): a thin
-- plate of the wood's core, 0.86 of the section's width, just proud of the
-- end. Parented beside the section; never collides, can't be queried.
function TreeArt.CutFace(def: WoodDef, section: BasePart, top: boolean): Part
	local color, material = TreeArt.Core(def)
	local t = widthOf(section) * TreeArt.CutFaceInset
	local th = TreeArt.CutFaceThickness
	local y = (section.Size.Y / 2 + th / 2 - 0.01) * (if top then 1 else -1)
	local p = Kit.part(
		section.Parent or section,
		"CutFace",
		Vector3.new(t, th, t),
		section.CFrame * CFrame.new(0, y, 0),
		color,
		material
	)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("Section", section:GetAttribute("Section"))
	ride(p, section)
	return p
end

-- How deep a notch is cut into a section `width` wide, with `damage` of
-- the `required` dealt.
function TreeArt.NotchDepth(width: number, damage: number, required: number): number
	if required <= 0 then
		return width * TreeArt.NotchMaxDepth
	end
	return width * math.clamp(damage / required, 0, TreeArt.NotchMaxDepth)
end

-- A notch: a strip of shaded core across the face of `section` nearest
-- `normal` (world space), `height` studs up from its bottom, cut in as
-- deep as the damage so far. Its ends show on the side faces too, so you
-- can see the cut grow. Attributes Section, Height, Damage, Required for
-- the progress ring.
function TreeArt.Notch(
	def: WoodDef,
	section: BasePart,
	height: number,
	normal: Vector3,
	damage: number,
	required: number
): Part
	local color, material = TreeArt.Core(def)
	local cf = section.CFrame
	local lx, lz = cf.XVector:Dot(normal), cf.ZVector:Dot(normal)
	local t = widthOf(section)
	local depth = TreeArt.NotchDepth(t, damage, required)
	local y = math.clamp(height, 0, section.Size.Y) - section.Size.Y / 2
	local size: Vector3
	local at: Vector3
	if math.abs(lx) >= math.abs(lz) then
		local side = if lx >= 0 then 1 else -1
		size = Vector3.new(depth + 0.02, TreeArt.NotchHeight, t + 0.04)
		at = Vector3.new(side * (t / 2 - depth / 2 + 0.01), y, 0)
	else
		local side = if lz >= 0 then 1 else -1
		size = Vector3.new(t + 0.04, TreeArt.NotchHeight, depth + 0.02)
		at = Vector3.new(0, y, side * (t / 2 - depth / 2 + 0.01))
	end
	local p = Kit.part(
		section.Parent or section,
		"Notch",
		size,
		cf * CFrame.new(at),
		Kit.shade(color, TreeArt.NotchShade),
		material
	)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("Section", section:GetAttribute("Section"))
	p:SetAttribute("Height", height)
	p:SetAttribute("Damage", damage)
	p:SetAttribute("Required", required)
	ride(p, section)
	return p
end

-- A v2 sapling, `growth` (0-1) of the way from a sprout to the size of its
-- tree's first growth stage (TreeGen.Stages[1]). Not cuttable: every part
-- is decoration. Ground at y = 0; PrimaryPart "Stem".
function TreeArt.GrowingSapling(def: WoodDef, seed: number, growth: number): Model
	local u = math.clamp(growth, 0, 1)
	local rng = Kit.rng(seed + 13)
	local paint = paintOf(def)
	local model = Instance.new("Model")
	model.Name = "Sapling_" .. def.id
	local v2 = def.v2
	local shape = v2 and v2.shape
	local h = 1.6 + u * 2.6
	local w = 0.22 + u * 0.18
	local stem = Kit.part(
		model,
		"Stem",
		Vector3.new(w, h, w),
		CFrame.new(0, h / 2, 0) * CFrame.Angles(0, rng:range(0, math.pi / 2), 0),
		paint.bark,
		Enum.Material.Wood
	)
	Kit.decor(stem, false)
	model.PrimaryPart = stem
	local coneShaped = shape ~= nil and (shape.canopy == "tiers" or shape.canopy == "snowtiers")
	if coneShaped then
		local tiers = if u < 0.5 then 1 else 2
		for i = 1, tiers do
			local r = (0.9 + u * 1.3) * (1 - (i - 1) * 0.35)
			local th = 1.8 + u * 1.6
			local base = h * (0.35 + (i - 1) * 0.3)
			Kit.cone(
				model,
				CFrame.new(0, base, 0) * CFrame.Angles(0, rng:range(0, math.pi), 0),
				r,
				th,
				5,
				function(k: number): Color3
					return Kit.vary(paint.leaves[(k - 1) % #paint.leaves + 1], rng, 0.04)
				end,
				Enum.Material.SmoothPlastic,
				0.08
			)
		end
	elseif shape and shape.canopy == "fronds" then
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + rng:range(-0.2, 0.2)
			local top = Vector3.new(0, h, 0)
			local tipAt = top
				+ Vector3.new(math.cos(a), 0, math.sin(a)) * (1.2 + u * 1.6)
				- Vector3.new(0, 0.5 + u * 0.4, 0)
			local length = math.max((tipAt - top).Magnitude, 0.2)
			Kit.decor(
				Kit.wedge(
					model,
					"Frond",
					Vector3.new(0.7 + u * 0.35, 0.28, length),
					CFrame.lookAt((top + tipAt) / 2, tipAt, Vector3.yAxis),
					rng:pick(paint.leaves),
					Enum.Material.SmoothPlastic
				),
				false
			)
		end
	elseif shape and shape.canopy == "wisps" then
		for i = 1, 2 do
			local a = i * math.pi + rng:range(-0.3, 0.3)
			local tipAt = Vector3.new(math.cos(a) * (0.5 + u * 0.6), h + 0.4 + u * 0.4, math.sin(a) * (0.5 + u * 0.6))
			Kit.decor(
				Kit.rod(model, "Twig", Vector3.new(0, h * 0.8, 0), tipAt, 0.14, paint.bark, Enum.Material.Wood),
				false
			)
			Kit.decor(
				Kit.ball(model, "Pod", 0.32, CFrame.new(tipAt), paint.glow or paint.accent, Enum.Material.Neon),
				false
			)
		end
	else
		local size = 1.5 + u * 1.9
		local blob = crystalCluster(
			model,
			"Leaves",
			{
				kind = "leaves",
				section = 0,
				cf = CFrame.new(0, h + size * 0.15, 0),
				size = Vector3.new(size, size * 0.85, size),
				parts = 3,
				seed = rng:int(1, 1000000),
			},
			paint.leaves,
			nil,
			def.id,
			Enum.Material.SmoothPlastic,
			if def.id == "oak" then TreeArt.HeartColor(def) else nil
		)
		if paint.glow and def.id ~= "frostwood" and blob[1] then
			blob[1].Material = Enum.Material.Neon
			blob[1].Color = paint.glow
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			Kit.decor(d, false)
		end
	end
	return model
end

-- Far forest trees. Same part counts as PropArt.FillerTree (ForestFiller.spec
-- compares those counts): conifer and snowpine 5, birch and dead 3, broadleaf
-- and maple 4. Decoration only.
local FILLER_KINDS = { broad = true, birch = true, maple = true, conifer = true, snowpine = true, dead = true }

function TreeArt.FillerTree(kind: string, variant: number): Model
	if not FILLER_KINDS[kind] then
		kind = "broad"
	end
	local model = Kit.model("FillerTree")
	local seed = 9001 + variant * 131
	for i = 1, #kind do
		seed += string.byte(kind, i) * i * 17
	end
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	local function block(name: string, size: Vector3, cf: CFrame, color: Color3)
		Kit.decor(Kit.part(model, name, size, cf, color, Enum.Material.SmoothPlastic), false)
	end
	local trunkColor = Kit.hex("#5E4130")
	local leaf = Kit.hex("#4E8E3E")
	if kind == "birch" then
		trunkColor = Kit.hex("#DCD6C8")
		leaf = Kit.hex("#A6CE5C")
	elseif kind == "maple" then
		trunkColor = Kit.hex("#5A3E2C")
		leaf = Kit.hex("#D88F2C")
	elseif kind == "conifer" or kind == "snowpine" then
		trunkColor = Kit.hex("#5A4030")
		leaf = Kit.hex("#2F7A3D")
	elseif kind == "dead" then
		trunkColor = Kit.hex("#6F6258")
		leaf = Kit.hex("#6F6258")
	end
	local function fillerTrunk(w: number, h: number)
		block(
			"FillerTrunk",
			Vector3.new(w, h + 1.5, w),
			CFrame.new(0, (h - 1.5) / 2, 0) * CFrame.Angles(0, yaw, 0),
			trunkColor
		)
	end
	if kind == "conifer" or kind == "snowpine" then
		local h = rng:range(7, 9)
		fillerTrunk(rng:range(1, 1.25), h)
		local w = rng:range(9, 10.5)
		local y = h - 1
		for t = 1, 4 do
			local tw = w * (1 - (t - 1) * 0.24)
			local th = if t == 4 then 4 else 3.6
			local snowy = kind == "snowpine" and t >= 3
			local color = if snowy then Kit.hex("#E3ECF1") else leaf
			if t == 1 then
				color = Kit.hex("#6B5A3A")
			end
			block(
				"FillerCrown",
				Vector3.new(tw, th, tw),
				CFrame.new(0, y + th / 2, 0) * CFrame.Angles(0, yaw + t * math.pi / 4, 0),
				color
			)
			y += th * 0.92
		end
	elseif kind == "dead" then
		local h = rng:range(9, 12)
		fillerTrunk(rng:range(1, 1.3), h)
		for i = 1, 2 do
			local a = yaw + i * math.pi * 0.9
			local len = rng:range(3.5, 5)
			local at = Vector3.new(math.cos(a) * len * 0.3, h * (0.55 + i * 0.15), math.sin(a) * len * 0.3)
			block(
				"FillerBranch",
				Vector3.new(0.5, len, 0.5),
				CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(rng:range(40, 55))),
				leaf
			)
		end
	elseif kind == "birch" then
		local h = rng:range(10, 12)
		fillerTrunk(rng:range(0.8, 1), h)
		block("FillerCrown", Vector3.new(7, 8, 7), CFrame.new(0, h + 1, 0), leaf)
		block("FillerCrown", Vector3.new(5, 5.5, 5), CFrame.new(0.6, h + 5.5, -0.4), Kit.hex("#BCD96B"))
	else
		local h = rng:range(8, 10)
		fillerTrunk(rng:range(1.3, 1.6), h)
		local w = rng:range(10, 12)
		block("FillerCrown", Vector3.new(w, w * 0.65, w), CFrame.new(0, h + 2.5, 0), leaf)
		block("FillerCrown", Vector3.new(w * 0.62, w * 0.5, w * 0.62), CFrame.new(1.2, h + 6.2, 0), leaf)
		block("FillerCrown", Vector3.new(w * 0.5, w * 0.4, w * 0.5), CFrame.new(-w * 0.3, h + 2, 0.4), leaf)
	end
	return model
end

return TreeArt
