--!strict
-- NatureArt: the rocks, plants and cave dressing built on the client
-- (AmbientLife). Part-built, so Lane H can swap meshes later. Every part
-- is decoration: anchored, no collision, no query, no touch, no shadow.
-- Rocks are 3 to 8 parts. Plants and cave pieces are 2 to 6. A PointLight,
-- when a piece has one, never casts shadows.

local Kit = require(script.Parent.Kit)

local NatureArt = {}

local hex = Kit.hex

NatureArt.CliffRock = hex("#7E766C")
NatureArt.QuarrySlate = hex("#5B5650")
NatureArt.FlowerCream = hex("#F3E7C9")
NatureArt.FlowerGold = hex("#F2C14E")
NatureArt.FlowerRed = hex("#D9534F")
NatureArt.WispViolet = hex("#9468E0")
NatureArt.NeedleDisc = hex("#6B5A3A")

-- Part counts the scatter budget uses. Keep these equal to what Build makes.
NatureArt.Parts = {
	Boulder = 5,
	Slab = 4,
	Spire = 4,
	WedgeRock = 4,
	Stack = 6,
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

NatureArt.RockShapes = { "Boulder", "Slab", "Spire", "WedgeRock", "Stack" }
NatureArt.Sizes = { "small", "mid", "large" }
NatureArt.PlantKinds =
	{ "Bush", "Fern", "Flowers", "Mushroom", "Reeds", "SnowShrub", "AshShrub", "GloamCap", "IsleCrystal" }
NatureArt.CaveKinds = { "CaveMushroom", "GlowFungus", "CrystalRock", "Roots", "Bat" }

local SIZE_SCALE = { small = 0.62, mid = 1, large = 1.45 }

local function model(kind: string): Model
	local m = Kit.model(kind)
	m:SetAttribute("Nature", kind)
	return m
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(parent, name, size, cf, color, material or Enum.Material.SmoothPlastic)
	return Kit.decor(p, false)
end

local function ball(
	parent: Instance,
	name: string,
	d: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.decor(Kit.ball(parent, name, d, cf, color, material or Enum.Material.SmoothPlastic), false)
end

local function wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.decor(Kit.wedge(parent, name, size, cf, color, material or Enum.Material.SmoothPlastic), false)
end

local function scaleOf(sizeName: string?): number
	return SIZE_SCALE[sizeName or "mid"] or 1
end

local function rockColor(seed: number): Color3
	return if seed % 2 == 0 then NatureArt.CliffRock else NatureArt.QuarrySlate
end

local function boulder(parent: Model, s: number, rng: Kit.Rng, color: Color3)
	ball(parent, "Core", 2.4 * s, CFrame.new(0, 1.05 * s, 0), color, Enum.Material.Rock)
	ball(parent, "Side", 1.5 * s, CFrame.new(0.9 * s, 0.7 * s, 0.3 * s), Kit.shade(color, -0.08), Enum.Material.Rock)
	ball(parent, "Side", 1.2 * s, CFrame.new(-0.7 * s, 0.55 * s, -0.4 * s), Kit.shade(color, 0.06), Enum.Material.Rock)
	part(
		parent,
		"Chip",
		Vector3.new(0.7, 0.35, 0.5) * s,
		CFrame.new(-0.2 * s, 0.2 * s, 0.9 * s) * CFrame.Angles(0.2, rng:range(0, 1), 0.4),
		Kit.shade(color, -0.12),
		Enum.Material.Rock
	)
	part(
		parent,
		"Chip",
		Vector3.new(0.45, 0.22, 0.4) * s,
		CFrame.new(0.6 * s, 0.15 * s, -0.7 * s),
		Kit.shade(color, 0.04),
		Enum.Material.Slate
	)
end

local function slab(parent: Model, s: number, color: Color3)
	part(parent, "Bed", Vector3.new(3.2, 0.45, 2.1) * s, CFrame.new(0, 0.22 * s, 0), color, Enum.Material.Slate)
	part(
		parent,
		"Bed",
		Vector3.new(2.2, 0.38, 1.4) * s,
		CFrame.new(0.4 * s, 0.5 * s, 0.2 * s) * CFrame.Angles(0, 0.4, 0.08),
		Kit.shade(color, 0.05),
		Enum.Material.Slate
	)
	part(
		parent,
		"Lip",
		Vector3.new(1.4, 0.28, 0.8) * s,
		CFrame.new(-0.8 * s, 0.35 * s, 0.5 * s) * CFrame.Angles(0.1, -0.3, 0),
		Kit.shade(color, -0.1),
		Enum.Material.Rock
	)
	wedge(
		parent,
		"Nose",
		Vector3.new(1.1 * s, 0.5 * s, 1.3 * s),
		CFrame.new(1.2 * s, 0.3 * s, -0.2 * s) * CFrame.Angles(0, 0.6, 0),
		Kit.shade(color, -0.06),
		Enum.Material.Slate
	)
end

local function spire(parent: Model, s: number, color: Color3)
	part(parent, "Shaft", Vector3.new(0.9, 3.4, 0.8) * s, CFrame.new(0, 1.7 * s, 0), color, Enum.Material.Rock)
	wedge(
		parent,
		"Tip",
		Vector3.new(0.7 * s, 1.3 * s, 0.7 * s),
		CFrame.new(0, 3.6 * s, 0),
		Kit.shade(color, 0.08),
		Enum.Material.Rock
	)
	part(
		parent,
		"Foot",
		Vector3.new(1.6, 0.4, 1.3) * s,
		CFrame.new(0.1 * s, 0.2 * s, 0),
		Kit.shade(color, -0.08),
		Enum.Material.Slate
	)
	part(
		parent,
		"Shard",
		Vector3.new(0.35, 1.6, 0.3) * s,
		CFrame.new(0.55 * s, 1.1 * s, 0.2 * s) * CFrame.Angles(0, 0, 0.25),
		Kit.shade(color, -0.12),
		Enum.Material.Rock
	)
end

local function wedgeRock(parent: Model, s: number, color: Color3)
	wedge(
		parent,
		"Face",
		Vector3.new(2.4 * s, 1.5 * s, 1.8 * s),
		CFrame.new(0, 0.7 * s, 0) * CFrame.Angles(0, 0.4, 0),
		color,
		Enum.Material.Slate
	)
	wedge(
		parent,
		"Face",
		Vector3.new(1.6 * s, 1.1 * s, 1.2 * s),
		CFrame.new(-0.5 * s, 0.5 * s, 0.4 * s) * CFrame.Angles(0, -0.8, 0),
		Kit.shade(color, -0.08),
		Enum.Material.Rock
	)
	part(
		parent,
		"Base",
		Vector3.new(2.2, 0.3, 1.6) * s,
		CFrame.new(0, 0.15 * s, 0),
		Kit.shade(color, -0.1),
		Enum.Material.Slate
	)
	part(
		parent,
		"Flake",
		Vector3.new(0.6, 0.2, 0.45) * s,
		CFrame.new(0.8 * s, 0.2 * s, 0.5 * s),
		Kit.shade(color, 0.06),
		Enum.Material.Rock
	)
end

local function stack(parent: Model, s: number, color: Color3)
	part(parent, "Course", Vector3.new(2.6, 0.55, 1.8) * s, CFrame.new(0, 0.28 * s, 0), color, Enum.Material.Slate)
	part(
		parent,
		"Course",
		Vector3.new(2.1, 0.5, 1.4) * s,
		CFrame.new(0.1 * s, 0.75 * s, 0.05 * s) * CFrame.Angles(0, 0.3, 0),
		Kit.shade(color, 0.04),
		Enum.Material.Rock
	)
	part(
		parent,
		"Course",
		Vector3.new(1.5, 0.42, 1.05) * s,
		CFrame.new(-0.05 * s, 1.15 * s, -0.05 * s) * CFrame.Angles(0, -0.2, 0),
		Kit.shade(color, -0.06),
		Enum.Material.Slate
	)
	part(
		parent,
		"Cap",
		Vector3.new(0.9, 0.35, 0.7) * s,
		CFrame.new(0.05 * s, 1.48 * s, 0),
		Kit.shade(color, 0.08),
		Enum.Material.Rock
	)
	part(
		parent,
		"Rubble",
		Vector3.new(0.55, 0.28, 0.4) * s,
		CFrame.new(1.1 * s, 0.16 * s, 0.4 * s),
		Kit.shade(color, -0.1),
		Enum.Material.Slate
	)
	part(
		parent,
		"Rubble",
		Vector3.new(0.4, 0.22, 0.35) * s,
		CFrame.new(-1.0 * s, 0.14 * s, -0.35 * s),
		Kit.shade(color, -0.04),
		Enum.Material.Rock
	)
end

local ROCKS: { [string]: (Model, number, Kit.Rng, Color3) -> () } = {
	Boulder = boulder,
	Slab = function(parent, s, _rng, color)
		slab(parent, s, color)
	end,
	Spire = function(parent, s, _rng, color)
		spire(parent, s, color)
	end,
	WedgeRock = function(parent, s, _rng, color)
		wedgeRock(parent, s, color)
	end,
	Stack = function(parent, s, _rng, color)
		stack(parent, s, color)
	end,
}

local function leaf(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	return part(parent, name, size, cf, color, Enum.Material.Grass)
end

local function bush(parent: Model, s: number, rng: Kit.Rng)
	local green = hex("#4C8F3E")
	ball(parent, "Crown", 1.7 * s, CFrame.new(0, 0.85 * s, 0), green, Enum.Material.Grass)
	ball(parent, "Crown", 1.25 * s, CFrame.new(0.55 * s, 0.7 * s, 0.2 * s), hex("#5DA24A"), Enum.Material.Grass)
	ball(parent, "Crown", 1.05 * s, CFrame.new(-0.45 * s, 0.6 * s, -0.15 * s), hex("#6FB352"), Enum.Material.Grass)
	part(
		parent,
		"Stem",
		Vector3.new(0.18, 0.45, 0.18) * s,
		CFrame.new(0, 0.2 * s, 0),
		Kit.vary(hex("#5A4030"), rng, 0.04),
		Enum.Material.Wood
	)
end

local function fern(parent: Model, s: number)
	local green = hex("#3A8A47")
	for i, side in ipairs({ -0.7, 0, 0.7 }) do
		wedge(
			parent,
			"Frond",
			Vector3.new(0.35 * s, 0.9 * s, 0.55 * s),
			CFrame.new(side * s, 0.4 * s, 0) * CFrame.Angles(0.4, i * 0.8, side * 0.3),
			if i == 2 then hex("#2F7A3D") else green,
			Enum.Material.Grass
		)
	end
end

local function flowers(parent: Model, s: number, rng: Kit.Rng)
	local colors = { NatureArt.FlowerCream, NatureArt.FlowerGold, NatureArt.FlowerRed }
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		ball(
			parent,
			"Bloom",
			0.38 * s,
			CFrame.new(math.cos(a) * 0.45 * s, 0.55 * s, math.sin(a) * 0.45 * s),
			rng:pick(colors),
			Enum.Material.SmoothPlastic
		)
	end
	leaf(parent, "Bed", Vector3.new(1.3, 0.18, 1.1) * s, CFrame.new(0, 0.1 * s, 0), hex("#4C8F3E"))
end

local function mushroom(parent: Model, s: number, cap: Color3, stem: Color3, glow: boolean)
	ball(
		parent,
		"Cap",
		0.7 * s,
		CFrame.new(0, 0.7 * s, 0),
		cap,
		if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	part(
		parent,
		"Stem",
		Vector3.new(0.22, 0.55, 0.22) * s,
		CFrame.new(0, 0.28 * s, 0),
		stem,
		Enum.Material.SmoothPlastic
	)
	part(parent, "Gill", Vector3.new(0.4, 0.08, 0.4) * s, CFrame.new(0, 0.48 * s, 0), Kit.shade(cap, 0.15))
end

local function reeds(parent: Model, s: number)
	local green = hex("#6B8F4A")
	for i, x in ipairs({ -0.35, -0.1, 0.15, 0.4 }) do
		part(
			parent,
			"Reed",
			Vector3.new(0.08, 1.3 + (i % 2) * 0.35, 0.08) * s,
			CFrame.new(x * s, 0.7 * s, (i - 2) * 0.12 * s) * CFrame.Angles(0, 0, x * 0.15),
			if i % 2 == 0 then hex("#C8B56A") else green,
			Enum.Material.Grass
		)
	end
end

local function shrub(parent: Model, s: number, color: Color3, tip: Color3)
	ball(parent, "Clump", 1.15 * s, CFrame.new(0, 0.55 * s, 0), color, Enum.Material.Grass)
	ball(
		parent,
		"Clump",
		0.8 * s,
		CFrame.new(0.4 * s, 0.45 * s, 0.15 * s),
		Kit.shade(color, -0.08),
		Enum.Material.Grass
	)
	part(parent, "Cap", Vector3.new(0.7, 0.2, 0.55) * s, CFrame.new(0, 1.05 * s, 0), tip, Enum.Material.SmoothPlastic)
end

local function crystal(parent: Model, s: number, color: Color3, material: Enum.Material)
	wedge(parent, "Shard", Vector3.new(0.45 * s, 1.6 * s, 0.4 * s), CFrame.new(0, 0.8 * s, 0), color, material)
	wedge(
		parent,
		"Shard",
		Vector3.new(0.32 * s, 1.15 * s, 0.3 * s),
		CFrame.new(0.28 * s, 0.55 * s, 0.1 * s) * CFrame.Angles(0, 0.5, 0.35),
		Kit.shade(color, 0.1),
		material
	)
	wedge(
		parent,
		"Shard",
		Vector3.new(0.28 * s, 0.9 * s, 0.26 * s),
		CFrame.new(-0.25 * s, 0.45 * s, -0.05 * s) * CFrame.Angles(0, -0.4, -0.3),
		Kit.shade(color, -0.08),
		material
	)
	part(
		parent,
		"Bed",
		Vector3.new(0.9, 0.16, 0.7) * s,
		CFrame.new(0, 0.08 * s, 0),
		NatureArt.QuarrySlate,
		Enum.Material.Slate
	)
end

local function roots(parent: Model, s: number)
	local bark = hex("#5A4030")
	for i, a in ipairs({ 0.2, 1.4, 2.6, 4.0 }) do
		part(
			parent,
			"Root",
			Vector3.new(0.28, 0.22, 1.3) * s,
			CFrame.new(math.cos(a) * 0.55 * s, 0.12 * s, math.sin(a) * 0.55 * s)
				* CFrame.Angles(0, -a, 0.15 * (i % 2 == 0 and 1 or -1)),
			Kit.shade(bark, if i % 2 == 0 then -0.08 else 0.05),
			Enum.Material.Wood
		)
	end
end

local function bat(parent: Model, s: number)
	local body = hex("#2A2830")
	ball(parent, "Body", 0.45 * s, CFrame.new(0, 0, 0), body, Enum.Material.SmoothPlastic)
	part(
		parent,
		"Wing",
		Vector3.new(0.9, 0.08, 0.45) * s,
		CFrame.new(-0.6 * s, 0.05 * s, 0) * CFrame.Angles(0, 0, 0.4),
		hex("#3A3544")
	)
	part(
		parent,
		"Wing",
		Vector3.new(0.9, 0.08, 0.45) * s,
		CFrame.new(0.6 * s, 0.05 * s, 0) * CFrame.Angles(0, 0, -0.4),
		hex("#3A3544")
	)
	ball(parent, "Ear", 0.16 * s, CFrame.new(-0.1 * s, 0.22 * s, -0.08 * s), body)
	ball(parent, "Ear", 0.16 * s, CFrame.new(0.1 * s, 0.22 * s, -0.08 * s), body)
	ball(parent, "Eye", 0.08 * s, CFrame.new(0, 0.05 * s, -0.2 * s), NatureArt.WispViolet, Enum.Material.Neon)
end

local function glowLight(host: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = color
	light.Range = range
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = host
end

-- One decoration model at the origin, sitting on y = 0. `sizeName` is
-- "small", "mid" or "large" (rocks). Plants ignore it and stay hand-sized.
function NatureArt.Build(kind: string, seed: number, sizeName: string?): Model
	local rng = Kit.rng(seed)
	local s = scaleOf(sizeName)
	local m = model(kind)
	local color = rockColor(seed)
	local rock = ROCKS[kind]
	if rock then
		rock(m, s, rng, color)
		return m
	end
	if kind == "Bush" then
		bush(m, 1, rng)
	elseif kind == "Fern" then
		fern(m, 1)
	elseif kind == "Flowers" then
		flowers(m, 1, rng)
	elseif kind == "Mushroom" then
		mushroom(m, 1, hex("#C4483A"), hex("#E8D2B0"), false)
	elseif kind == "Reeds" then
		reeds(m, 1)
	elseif kind == "SnowShrub" then
		shrub(m, 1, hex("#7FA0B0"), Color3.fromRGB(236, 242, 246))
	elseif kind == "AshShrub" then
		shrub(m, 1, hex("#5C514C"), hex("#8A7A72"))
	elseif kind == "GloamCap" then
		mushroom(m, 1.15, NatureArt.WispViolet, hex("#3A3050"), true)
		part(m, "Ring", Vector3.new(0.9, 0.08, 0.9), CFrame.new(0, 0.62, 0), hex("#C8A8FF"), Enum.Material.Neon)
	elseif kind == "IsleCrystal" then
		crystal(m, 1, hex("#FFF4C2"), Enum.Material.Neon)
	elseif kind == "CaveMushroom" then
		mushroom(m, 0.9, hex("#8A6A4A"), hex("#D8C8A8"), false)
	elseif kind == "GlowFungus" then
		mushroom(m, 1, hex("#7AF2C8"), hex("#D8C8A8"), true)
		ball(m, "Speck", 0.22, CFrame.new(0.2, 0.4, 0.15), hex("#C8FFF0"), Enum.Material.Neon)
	elseif kind == "CrystalRock" then
		crystal(m, 0.85, hex("#9AD0FF"), Enum.Material.Glass)
		part(m, "Glint", Vector3.new(0.2, 0.7, 0.16), CFrame.new(0.05, 0.7, 0.05), hex("#E8F6FF"), Enum.Material.Neon)
	elseif kind == "Roots" then
		roots(m, 1)
	elseif kind == "Bat" then
		bat(m, 1)
	else
		bush(m, 1, rng)
	end
	local host = m:FindFirstChildWhichIsA("BasePart")
	if host and (kind == "GlowFungus" or kind == "CrystalRock" or kind == "GloamCap" or kind == "IsleCrystal") then
		local range = if kind == "IsleCrystal" then 10 elseif kind == "GloamCap" then 8 else 7
		glowLight(host, if kind == "GlowFungus" then hex("#7AF2C8") else NatureArt.WispViolet, range)
	end
	return m
end

-- Six mushrooms in a ring, for a gloamwood's foot (client-only).
function NatureArt.MushroomRing(seed: number): Model
	local ring = model("MushroomRing")
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		local cap = NatureArt.Build("CaveMushroom", seed + i * 17)
		Kit.placeAt(cap, CFrame.new(math.cos(a) * 1.6, 0, math.sin(a) * 1.6))
		cap.Parent = ring
	end
	return ring
end

-- Three neon pods for a lanternwood at night. No PointLight: WoodFX already
-- budgets those, and a phone still reads the neon in a dark cave.
function NatureArt.LanternPods(seed: number): Model
	local pods = model("LanternPods")
	local glow = hex("#F2C14E")
	for i = 1, 3 do
		local a = (i - 1) / 3 * math.pi * 2 + seed * 0.01
		local p = ball(
			pods,
			"Pod",
			0.45,
			CFrame.new(math.cos(a) * 1.1, 1.4 + (i % 2) * 0.35, math.sin(a) * 1.1),
			glow,
			Enum.Material.Neon
		)
		p:SetAttribute("NightGlow", true)
	end
	return pods
end

export type RainStyle = "blobs" | "streaks"

-- A box of rain the preview can draw (the screenshot tool does not draw
-- particles). "blobs" is today's puff. "streaks" is the thin angled fall.
-- `tier` "low" uses fewer, shorter marks. Sheltered skips the middle, under
-- a roof the caller can sit on y = 4.
function NatureArt.RainField(style: RainStyle, tier: string, sheltered: boolean): Model
	local field = model("RainField")
	local low = tier == "low"
	local count = if style == "blobs" then (if low then 18 else 36) else (if low then 16 else 40)
	local rng = Kit.rng(if style == "blobs" then 3 else 11)
	for i = 1, count do
		local x = rng:range(-10, 10)
		local z = rng:range(-8, 8)
		local y = rng:range(4, 16)
		local under = sheltered and math.abs(x) < 4.2 and math.abs(z) < 3.2 and y < 12
		if not under then
			if style == "blobs" then
				local puff = ball(
					field,
					"Blob",
					0.42,
					CFrame.new(x, y, z),
					Color3.fromRGB(205, 220, 238),
					Enum.Material.SmoothPlastic
				)
				puff.Transparency = 0.45
			else
				local length = if low then 0.7 else 1.35
				local streak = part(
					field,
					"Streak",
					Vector3.new(0.06, length, 0.06),
					CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(12)),
					Color3.fromRGB(198, 214, 232),
					Enum.Material.SmoothPlastic
				)
				streak.Transparency = 0.28
			end
		end
	end
	if style == "streaks" and not sheltered then
		local splashes = if low then 4 else 8
		for i = 1, splashes do
			local splash = part(
				field,
				"Splash",
				Vector3.new(0.35, 0.04, 0.35),
				CFrame.new(rng:range(-3, 3), 0.05, rng:range(-2, 2)),
				Color3.fromRGB(210, 222, 236),
				Enum.Material.SmoothPlastic
			)
			splash.Transparency = 0.4
		end
	end
	return field
end

return NatureArt
