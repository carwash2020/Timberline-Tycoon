--!strict
-- NatureArt: the rocks, plants and cave dressing built on the client
-- (AmbientLife). Rocks and ore rocks try a MeshTemplates piece per slot
-- (RockModels: host, two veins, moss, snow, heartstone glow). A missing
-- id keeps the part build and is logged once. Every part is decoration:
-- anchored, no collision, no query, no touch, no shadow. A rock is one of
-- six families, 7 parts (8 for a pebble cluster), tilted 8 to 20 degrees
-- and sunk 20 to 30 percent. Meadow moss and a snow cap are two thin
-- wedges on the crown, at most 0.3 studs proud. No block is taller than
-- 1.5 times its width. An ore rock is the body plus 2 vein wedges, each
-- about a fifth of its face, 8 parts at most. Plants and cave pieces are
-- 2 to 6. A PointLight never casts shadows.

local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.Kit)
local MeshKit = require(script.Parent.MeshKit)
local OreData = require(script.Parent.Parent.OreData)
local RockModels = require(script.Parent.RockModels)

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
	Boulder = 7,
	CrackedBoulder = 7,
	Spire = 7,
	Slab = 7,
	PebbleCluster = 8,
	Outcrop = 7,
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

NatureArt.RockShapes = { "Boulder", "CrackedBoulder", "Spire", "Slab", "PebbleCluster", "Outcrop" }
-- Grass (meadow) moss, snow cap, shore sandstone, volcano basalt, gloam, cave.
NatureArt.RockLooks = { "meadow", "snow", "shore", "volcano", "gloam", "cave" }
NatureArt.OrePartCap = 8
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
): WedgePart
	return Kit.decor(Kit.wedge(parent, name, size, cf, color, material or Enum.Material.SmoothPlastic), false)
end

local function corner(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): CornerWedgePart
	local p = Instance.new("CornerWedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Rock
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return Kit.decor(p, false)
end

local function scaleOf(sizeName: string?): number
	return SIZE_SCALE[sizeName or "mid"] or 1
end

type RockLook = {
	stone: Color3,
	dark: Color3,
	light: Color3,
	cap: Color3,
	stoneMat: Enum.Material,
	bandMat: Enum.Material,
	capMat: Enum.Material,
}

local ROCK: Enum.Material = Enum.Material.Rock
local SLATE: Enum.Material = Enum.Material.Slate
local BASALT: Enum.Material = Enum.Material.Basalt
local LIME: Enum.Material = Enum.Material.Limestone

local LOOKS: { [string]: RockLook } = {
	meadow = {
		stone = hex("#7A7368"),
		dark = hex("#544E48"),
		light = hex("#91897C"),
		cap = hex("#667552"),
		stoneMat = ROCK,
		bandMat = SLATE,
		capMat = Enum.Material.Grass,
	},
	snow = {
		stone = hex("#8A93A0"),
		dark = hex("#646E7C"),
		light = hex("#C5CED8"),
		cap = hex("#F4F7FB"),
		stoneMat = ROCK,
		bandMat = SLATE,
		capMat = Enum.Material.Snow,
	},
	shore = {
		stone = hex("#C6B48A"),
		dark = hex("#A08C64"),
		light = hex("#E0D0AC"),
		cap = hex("#E6D4A4"),
		stoneMat = Enum.Material.Sandstone,
		bandMat = LIME,
		capMat = Enum.Material.Sand,
	},
	volcano = {
		stone = hex("#3A3532"),
		dark = hex("#221E1C"),
		light = hex("#5A534E"),
		cap = hex("#2C2826"),
		stoneMat = BASALT,
		bandMat = BASALT,
		capMat = SLATE,
	},
	gloam = {
		stone = hex("#3A4158"),
		dark = hex("#282E44"),
		light = hex("#6A7390"),
		cap = hex("#4C4068"),
		stoneMat = SLATE,
		bandMat = BASALT,
		capMat = SLATE,
	},
	cave = {
		stone = hex("#2C2A32"),
		dark = hex("#1A181E"),
		light = hex("#5A6270"),
		cap = hex("#465060"),
		stoneMat = SLATE,
		bandMat = LIME,
		capMat = SLATE,
	},
	-- Plain stone for the ore lineup's host rock. Not a scatter look.
	host = {
		stone = hex("#B7B3AC"),
		dark = hex("#8E8A84"),
		light = hex("#D4D0C8"),
		cap = hex("#A39E96"),
		stoneMat = ROCK,
		bandMat = SLATE,
		capMat = SLATE,
	},
}

local LOOK_ALIAS: { [string]: string } = {
	grass = "meadow",
	forest = "meadow",
	beach = "shore",
}

local function palette(look: string?): RockLook
	local name = look or "meadow"
	local alias = LOOK_ALIAS[name]
	if alias then
		name = alias
	end
	return LOOKS[name] or LOOKS.meadow
end

-- Body only. Build adds two crown patches and one accent. OreRock adds
-- veins instead of the patches, so a cave host does not wear moss.
local function boulderBody(parent: Model, s: number, look: RockLook)
	ball(parent, "Core", 2.3 * s, CFrame.new(0, 0.82 * s, 0), look.stone, look.stoneMat)
	ball(parent, "Shoulder", 1.35 * s, CFrame.new(0.78 * s, 0.5 * s, 0.28 * s), look.dark, look.stoneMat)
	wedge(
		parent,
		"Haunch",
		Vector3.new(1.15, 0.62, 0.95) * s,
		CFrame.new(-0.72 * s, 0.36 * s, -0.28 * s) * CFrame.Angles(0.25, -0.7, 0.2),
		look.light,
		look.bandMat
	)
	part(
		parent,
		"Strata",
		Vector3.new(1.7, 0.14, 0.32) * s,
		CFrame.new(0.05 * s, 0.62 * s, 0.82 * s) * CFrame.Angles(0.2, 0.15, 0),
		look.dark,
		look.bandMat
	)
end

local function crackedBody(parent: Model, s: number, look: RockLook)
	ball(parent, "Core", 1.7 * s, CFrame.new(-0.48 * s, 0.62 * s, 0), look.stone, look.stoneMat)
	ball(parent, "Lobe", 1.45 * s, CFrame.new(0.55 * s, 0.55 * s, 0.08 * s), look.dark, look.stoneMat)
	wedge(
		parent,
		"Crack",
		Vector3.new(0.55, 0.2, 0.85) * s,
		CFrame.new(0.02 * s, 0.48 * s, 0.02 * s) * CFrame.Angles(0.1, 0.2, 0.9),
		look.dark,
		look.bandMat
	)
	part(
		parent,
		"Strata",
		Vector3.new(1.35, 0.12, 0.28) * s,
		CFrame.new(-0.2 * s, 0.7 * s, 0.55 * s) * CFrame.Angles(0.25, -0.3, 0),
		look.light,
		LIME
	)
end

-- A standing stone of stacked, offset courses. Each course is wider than it is tall.
local function spireBody(parent: Model, s: number, look: RockLook)
	part(parent, "Core", Vector3.new(1.65, 0.68, 1.35) * s, CFrame.new(0, 0.34 * s, 0), look.stone, look.stoneMat)
	part(
		parent,
		"Course",
		Vector3.new(1.15, 0.82, 1.05) * s,
		CFrame.new(0.1 * s, 1.0 * s, -0.06 * s) * CFrame.Angles(0, 0.4, 0.08),
		look.dark,
		look.stoneMat
	)
	part(
		parent,
		"Head",
		Vector3.new(0.86, 0.74, 0.78) * s,
		CFrame.new(-0.08 * s, 1.68 * s, 0.05 * s) * CFrame.Angles(0, -0.5, -0.05),
		look.light,
		look.bandMat
	)
	wedge(
		parent,
		"Shoulder",
		Vector3.new(0.62, 0.34, 0.5) * s,
		CFrame.new(0.55 * s, 0.7 * s, 0.15 * s) * CFrame.Angles(0.1, 0.6, 0.35),
		look.dark,
		look.bandMat
	)
end

local function slabBody(parent: Model, s: number, look: RockLook)
	part(parent, "Core", Vector3.new(3.1, 0.42, 2.05) * s, CFrame.new(0, 0.21 * s, 0), look.stone, look.stoneMat)
	part(
		parent,
		"Lift",
		Vector3.new(2.0, 0.32, 1.25) * s,
		CFrame.new(0.25 * s, 0.48 * s, 0.1 * s) * CFrame.Angles(0, 0.35, 0.06),
		look.light,
		look.bandMat
	)
	wedge(
		parent,
		"Nose",
		Vector3.new(1.2, 0.48, 1.0) * s,
		CFrame.new(1.15 * s, 0.28 * s, -0.15 * s) * CFrame.Angles(0, 0.5, 0),
		look.dark,
		look.stoneMat
	)
	part(
		parent,
		"Strata",
		Vector3.new(2.4, 0.1, 0.22) * s,
		CFrame.new(0.1 * s, 0.38 * s, 0.7 * s) * CFrame.Angles(0.15, 0.1, 0),
		look.dark,
		look.bandMat
	)
end

local function pebbleBody(parent: Model, s: number, look: RockLook)
	ball(parent, "Core", 0.95 * s, CFrame.new(0, 0.38 * s, 0), look.stone, look.stoneMat)
	ball(parent, "Pebble", 0.72 * s, CFrame.new(0.55 * s, 0.28 * s, 0.18 * s), look.dark, look.stoneMat)
	ball(parent, "Pebble", 0.58 * s, CFrame.new(-0.42 * s, 0.24 * s, 0.22 * s), look.light, look.bandMat)
	ball(parent, "Pebble", 0.5 * s, CFrame.new(0.1 * s, 0.22 * s, -0.48 * s), look.dark, LIME)
	wedge(
		parent,
		"Chip",
		Vector3.new(0.4, 0.18, 0.32) * s,
		CFrame.new(0.7 * s, 0.14 * s, -0.3 * s) * CFrame.Angles(0.2, 0.8, 0.3),
		look.light,
		look.bandMat
	)
end

local function outcropBody(parent: Model, s: number, look: RockLook)
	part(parent, "Core", Vector3.new(2.4, 0.4, 1.5) * s, CFrame.new(0, 0.2 * s, 0), look.stone, look.stoneMat)
	wedge(
		parent,
		"Mass",
		Vector3.new(1.6, 0.7, 1.2) * s,
		CFrame.new(-0.3 * s, 0.42 * s, 0.1 * s) * CFrame.Angles(0.15, -0.4, 0),
		look.dark,
		look.stoneMat
	)
	corner(
		parent,
		"Nose",
		Vector3.new(0.8, 0.36, 0.7) * s,
		CFrame.new(0.85 * s, 0.28 * s, 0.35 * s) * CFrame.Angles(0, 0.7, 0.08),
		look.light,
		look.bandMat
	)
	part(
		parent,
		"Strata",
		Vector3.new(1.8, 0.1, 0.2) * s,
		CFrame.new(0.05 * s, 0.32 * s, 0.55 * s) * CFrame.Angles(0.2, -0.15, 0),
		look.dark,
		look.bandMat
	)
end

local function boulderAccent(parent: Model, s: number, look: RockLook)
	corner(
		parent,
		"Nose",
		Vector3.new(0.7, 0.38, 0.6) * s,
		CFrame.new(0.35 * s, 0.28 * s, 0.95 * s) * CFrame.Angles(0, 0.9, 0.1),
		look.light,
		look.stoneMat
	)
end

local function crackedAccent(parent: Model, s: number, look: RockLook)
	corner(
		parent,
		"Flake",
		Vector3.new(0.5, 0.28, 0.42) * s,
		CFrame.new(0.85 * s, 0.22 * s, -0.35 * s) * CFrame.Angles(0.15, -0.6, 0.4),
		look.light,
		look.stoneMat
	)
end

local function spireAccent(parent: Model, s: number, look: RockLook)
	part(
		parent,
		"Flake",
		Vector3.new(0.5, 0.32, 0.42) * s,
		CFrame.new(-0.48 * s, 1.15 * s, 0.22 * s) * CFrame.Angles(0.1, 0.5, -0.2),
		look.dark,
		LIME
	)
end

local function slabAccent(parent: Model, s: number, look: RockLook)
	part(
		parent,
		"Lip",
		Vector3.new(1.1, 0.22, 0.7) * s,
		CFrame.new(-0.9 * s, 0.32 * s, 0.45 * s) * CFrame.Angles(0.08, -0.4, 0),
		look.light,
		look.stoneMat
	)
end

local function pebbleAccent(parent: Model, s: number, look: RockLook)
	ball(parent, "Pebble", 0.4 * s, CFrame.new(-0.15 * s, 0.16 * s, 0.45 * s), look.cap, look.capMat)
end

local function outcropAccent(parent: Model, s: number, look: RockLook)
	wedge(
		parent,
		"Rubble",
		Vector3.new(0.45, 0.2, 0.36) * s,
		CFrame.new(1.15 * s, 0.14 * s, -0.4 * s) * CFrame.Angles(0.2, 1.1, 0.3),
		look.light,
		look.stoneMat
	)
end

local BODIES: { [string]: (Model, number, RockLook) -> () } = {
	Boulder = boulderBody,
	CrackedBoulder = crackedBody,
	Spire = spireBody,
	Slab = slabBody,
	PebbleCluster = pebbleBody,
	Outcrop = outcropBody,
}

local ACCENTS: { [string]: (Model, number, RockLook) -> () } = {
	Boulder = boulderAccent,
	CrackedBoulder = crackedAccent,
	Spire = spireAccent,
	Slab = slabAccent,
	PebbleCluster = pebbleAccent,
	Outcrop = outcropAccent,
}

local function eachPart(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function boundsOf(list: { BasePart }): (Vector3, Vector3)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, p in ipairs(list) do
		local hs = p.Size * 0.5
		local cf = p.CFrame
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = cf:PointToWorldSpace(Vector3.new(hs.X * sx, hs.Y * sy, hs.Z * sz))
					minX = math.min(minX, w.X)
					minY = math.min(minY, w.Y)
					minZ = math.min(minZ, w.Z)
					maxX = math.max(maxX, w.X)
					maxY = math.max(maxY, w.Y)
					maxZ = math.max(maxZ, w.Z)
				end
			end
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

-- Yaw, an 8-20 degree tilt, a little scale jitter, then a 20-30 percent sink.
local function settle(root: Model, seed: number)
	local list = eachPart(root)
	if #list == 0 then
		return
	end
	local minV, maxV = boundsOf(list)
	local pivot = Vector3.new((minV.X + maxV.X) * 0.5, 0, (minV.Z + maxV.Z) * 0.5)
	local jitter = 0.92 + (seed % 7) * 0.02
	for _, p in ipairs(list) do
		local at = p.CFrame.Position
		local rel = at - pivot
		local rotOnly = p.CFrame - at
		p.Size = p.Size * jitter
		p.CFrame = CFrame.new(pivot + rel * jitter) * rotOnly
	end
	local tiltDeg = 8 + (seed % 13)
	local axis = if seed % 2 == 0 then Vector3.xAxis else Vector3.zAxis
	local yaw = (seed % 628) / 100
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(axis, math.rad(tiltDeg))
	for _, p in ipairs(list) do
		p.CFrame = CFrame.new(pivot) * rot * CFrame.new(-pivot) * p.CFrame
	end
	minV, maxV = boundsOf(list)
	local height = math.max(maxV.Y - minV.Y, 0.01)
	local sink = 0.20 + (seed % 11) * 0.01
	local dy = -sink * height - minV.Y
	for _, p in ipairs(list) do
		p.CFrame = p.CFrame + Vector3.new(0, dy, 0)
	end
	root:SetAttribute("TiltDeg", tiltDeg)
	root:SetAttribute("Sink", sink)
end

local function faceCf(origin: Vector3, normal: Vector3, reach: number): CFrame
	local n = normal.Unit
	local center = origin + n * reach
	local hint = if math.abs(n.Y) > 0.85 then Vector3.xAxis else Vector3.yAxis
	local right = n:Cross(hint).Unit
	local back = right:Cross(n).Unit
	return CFrame.fromMatrix(center, right, n, back)
end

-- A crown patch is 0.2 studs thick and set 0.08 studs into the stone, so
-- about 0.02 studs stands proud before the tilt. The corners of a wedge
-- this small stay inside 0.3 studs of the rock.
local CAP_THICK = 0.2
local CAP_INSET = 0.08

local function crownPatch(
	parent: Model,
	s: number,
	look: RockLook,
	x: number,
	y: number,
	z: number,
	nx: number,
	ny: number,
	nz: number,
	wide: number,
	deep: number
)
	local origin = Vector3.new(x, y, z) * s
	wedge(
		parent,
		"Cap",
		Vector3.new(wide * s, CAP_THICK, deep * s),
		faceCf(origin, Vector3.new(nx, ny, nz), -CAP_INSET),
		look.cap,
		look.capMat
	)
end

-- Two patches per family, on the high curve. Coordinates are the surface
-- in the same unscaled units as the body.
local CROWNS: { [string]: (Model, number, RockLook) -> () } = {
	Boulder = function(parent, s, look)
		crownPatch(parent, s, look, 0.52, 1.74, 0.26, 0.45, 0.80, 0.22, 0.70, 0.44)
		crownPatch(parent, s, look, -0.36, 1.78, -0.30, -0.34, 0.86, -0.26, 0.62, 0.40)
	end,
	CrackedBoulder = function(parent, s, look)
		crownPatch(parent, s, look, -0.48, 1.47, 0.18, 0.02, 0.92, 0.22, 0.58, 0.38)
		crownPatch(parent, s, look, 0.72, 1.16, 0.22, 0.28, 0.84, 0.22, 0.52, 0.36)
	end,
	Spire = function(parent, s, look)
		crownPatch(parent, s, look, -0.02, 2.05, 0.10, 0.18, 0.92, 0.16, 0.48, 0.34)
		crownPatch(parent, s, look, -0.16, 2.02, -0.08, -0.22, 0.90, -0.12, 0.42, 0.32)
	end,
	Slab = function(parent, s, look)
		crownPatch(parent, s, look, 0.15, 0.64, -0.22, 0.12, 0.94, -0.18, 0.70, 0.40)
		crownPatch(parent, s, look, -0.35, 0.42, 0.15, -0.08, 0.96, 0.16, 0.62, 0.36)
	end,
	PebbleCluster = function(parent, s, look)
		crownPatch(parent, s, look, 0.16, 0.82, 0.10, 0.28, 0.88, 0.18, 0.40, 0.30)
		crownPatch(parent, s, look, -0.12, 0.78, -0.14, -0.22, 0.90, -0.24, 0.36, 0.28)
	end,
	Outcrop = function(parent, s, look)
		crownPatch(parent, s, look, -0.15, 0.78, 0.12, -0.10, 0.92, 0.18, 0.62, 0.38)
		crownPatch(parent, s, look, 0.28, 0.70, -0.08, 0.22, 0.88, -0.16, 0.50, 0.34)
	end,
}

-- About a fifth of the face the wedge sits on. Two veins, so the rock
-- stays at or under 8 parts (the pebble body is already 5).
local VEIN_SHARE = 0.2

local function embedVeins(parent: Model, shape: string, color: Color3, material: Enum.Material)
	local function onFace(partName: string, axis: string, sign: number, shift: Vector3?)
		local host = parent:FindFirstChild(partName)
		if not (host and host:IsA("BasePart")) then
			return
		end
		local size = host.Size
		local normal: Vector3
		local faceW: number
		local faceH: number
		local half: number
		if axis == "X" then
			normal = host.CFrame.XVector * sign
			faceW, faceH, half = size.Y, size.Z, size.X * 0.5
		elseif axis == "Y" then
			normal = host.CFrame.YVector * sign
			faceW, faceH, half = size.X, size.Z, size.Y * 0.5
		else
			normal = host.CFrame.ZVector * sign
			faceW, faceH, half = size.X, size.Y, size.Z * 0.5
		end
		local area = faceW * faceH * VEIN_SHARE
		local wide = math.sqrt(area * 1.6)
		local deep = area / wide
		local thick = math.min(wide, deep) * 0.18
		local inset = math.min(thick * 0.5, half * 0.4)
		local cf = host.CFrame
		local center = cf.Position + normal * (half - inset)
		if shift then
			center += cf.XVector * shift.X + cf.YVector * shift.Y + cf.ZVector * shift.Z
		end
		wedge(parent, "Vein", Vector3.new(wide, thick, deep), faceCf(center, normal, 0), color, material)
	end
	-- Faces the 3/4 camera sees, kept off a neighbour that would swallow them.
	if shape == "CrackedBoulder" then
		onFace("Core", "X", -1, Vector3.new(0, 0.15, 0))
		onFace("Lobe", "Z", -1, Vector3.new(0, 0.12, 0))
	elseif shape == "Spire" then
		onFace("Core", "Z", -1, Vector3.new(0, 0.08, 0))
		onFace("Head", "X", -1, nil)
	elseif shape == "Slab" then
		onFace("Core", "Y", 1, Vector3.new(0, 0, -0.45))
		onFace("Core", "Z", -1, nil)
	elseif shape == "PebbleCluster" then
		onFace("Core", "X", -1, Vector3.new(0, 0.08, 0))
		onFace("Core", "Z", 1, Vector3.new(0, 0.06, 0))
	elseif shape == "Outcrop" then
		onFace("Core", "Y", 1, Vector3.new(0.35, 0, -0.2))
		onFace("Core", "Z", -1, nil)
	else
		onFace("Core", "X", -1, Vector3.new(0, 0.2, 0))
		onFace("Core", "Z", -1, Vector3.new(0, 0.15, 0))
	end
end

local function veinMaterial(oreMaterial: Enum.Material, glow: boolean?): Enum.Material
	if glow == true then
		return Enum.Material.Neon
	end
	if oreMaterial == Enum.Material.Neon then
		return Enum.Material.SmoothPlastic
	end
	return oreMaterial
end

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

-- One log per shape and slot. A forest of part-built rocks should not
-- repeat the same missing mesh.
local meshTold: { [string]: boolean } = {}
local oreTold: { [string]: boolean } = {}

local function logFallback(shape: string, slot: string, meshId: number)
	local key = shape .. "/" .. slot
	if meshTold[key] then
		return
	end
	meshTold[key] = true
	warn(
		string.format(
			"[NatureArt] %s %s mesh is missing (id %s); keeping the part build.",
			shape,
			slot,
			tostring(meshId)
		)
	)
end

local function logUnknownOre(oreId: string)
	if oreTold[oreId] then
		return
	end
	oreTold[oreId] = true
	warn(string.format("[NatureArt] ore %q is not in OreData; the part build uses the colors it was given.", oreId))
end

local function lookName(look: string?): string
	local name = look or "meadow"
	local alias = LOOK_ALIAS[name]
	if alias then
		return alias
	end
	if LOOKS[name] then
		return name
	end
	return "meadow"
end

-- One uploaded piece of a rock. MeshHost is placed at the build origin plus
-- hostCentre * scale; every other piece sits at MeshHost.CFrame * offset *
-- scale (unrotated offsets, so the pieces follow the host's rotation).
type MeshSlot = {
	name: string,
	label: string,
	meshId: number,
	size: Vector3,
	offset: Vector3,
	color: Color3?,
	material: Enum.Material?,
}

local function slotOf(
	name: string,
	label: string,
	piece: RockModels.Piece,
	scale: number,
	color: Color3?,
	material: Enum.Material?
): MeshSlot
	return {
		name = name,
		label = label,
		meshId = piece.meshId,
		size = piece.size * scale,
		offset = piece.offset * scale,
		color = color,
		material = material,
	}
end

-- Clone every slot or leave the part build alone. A 0 id or a failed load
-- counts as missing. slots[1] is MeshHost. The part-built parts are dropped
-- only once every mesh exists.
local function applySlots(root: Model, shape: string, slots: { MeshSlot }, hostCentre: Vector3): boolean
	for _, slot in ipairs(slots) do
		if not RockModels.UsesMesh(slot.meshId) then
			logFallback(shape, slot.label, slot.meshId)
			root:SetAttribute("MeshFallback", slot.label)
			return false
		end
	end
	local made: { MeshPart } = {}
	local function abandon(slot: MeshSlot): boolean
		for _, mesh in ipairs(made) do
			mesh:Destroy()
		end
		logFallback(shape, slot.label, slot.meshId)
		root:SetAttribute("MeshFallback", slot.label)
		return false
	end
	local hostCf = CFrame.new(hostCentre)
	for index, slot in ipairs(slots) do
		local fidelity = if index == 1 then Enum.CollisionFidelity.Hull else nil
		local mesh = MeshKit.Create(slot.meshId, slot.name, slot.size, fidelity)
		if not mesh then
			return abandon(slot)
		end
		MeshKit.Visual(mesh, slot.meshId)
		mesh.Anchored = true
		if index == 1 then
			mesh.CFrame = hostCf
		else
			mesh.CFrame = hostCf * CFrame.new(slot.offset)
		end
		Kit.decor(mesh, false)
		if slot.color then
			mesh.Color = slot.color
		end
		if slot.material then
			mesh.Material = slot.material
		end
		mesh.Parent = root
		table.insert(made, mesh)
	end
	local drop: { Instance } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
	root:SetAttribute("RockMesh", true)
	return true
end

local function luminance(color: Color3): number
	return color.R * 0.299 + color.G * 0.587 + color.B * 0.114
end

local function oreGlow(host: BasePart, color: Color3)
	local pale = luminance(color) > 0.7
	local lamp = Instance.new("PointLight")
	lamp.Name = "Glow"
	lamp.Color = color
	lamp.Range = if pale then 6 else 11
	lamp.Brightness = if pale then 0.22 else 1
	lamp.Shadows = false
	lamp.Parent = host
end

local function applyNatureMeshes(
	root: Model,
	shape: string,
	variant: RockModels.Variant,
	look: string,
	rockLook: RockLook,
	scale: number
)
	local spec = RockModels.Get(shape, variant)
	if not spec then
		return
	end
	local tag = shape .. variant
	local slots: { MeshSlot } = {
		slotOf("MeshHost", "host", spec.Host, scale, rockLook.stone, rockLook.stoneMat),
	}
	if look == "meadow" then
		table.insert(slots, slotOf("MeshMoss", "moss", spec.Moss, scale, rockLook.cap, rockLook.capMat))
	elseif look == "snow" then
		table.insert(slots, slotOf("MeshSnow", "snow", spec.Snow, scale, rockLook.cap, rockLook.capMat))
	end
	applySlots(root, tag, slots, spec.hostCentre * scale)
end

local function applyOreMeshes(
	root: Model,
	shape: string,
	variant: RockModels.Variant,
	moss: boolean,
	scale: number,
	hostLook: RockLook,
	color: Color3,
	material: Enum.Material,
	useGlow: boolean,
	heartstone: boolean
): boolean
	local spec = RockModels.Get(shape, variant)
	if not spec then
		return false
	end
	local tag = shape .. variant
	local veinMat = veinMaterial(material, useGlow)
	local slots: { MeshSlot } = {
		slotOf("MeshHost", "host", spec.Host, scale, hostLook.stone, hostLook.stoneMat),
		slotOf("MeshVein1", "vein 1", spec.Vein1, scale, color, veinMat),
		slotOf("MeshVein2", "vein 2", spec.Vein2, scale, color, veinMat),
	}
	if moss then
		table.insert(slots, slotOf("MeshMoss", "moss", spec.Moss, scale, hostLook.cap, Enum.Material.Grass))
	end
	if heartstone then
		table.insert(slots, slotOf("MeshGlow", "heartstone glow", spec.Glow, scale, color, Enum.Material.Neon))
	end
	if not applySlots(root, tag, slots, spec.hostCentre * scale) then
		return false
	end
	if useGlow then
		local host = root:FindFirstChild(if heartstone then "MeshGlow" else "MeshVein1")
		if host and host:IsA("BasePart") then
			oreGlow(host, color)
		end
	end
	return true
end

-- Same seed, same variant.
local function variantFor(seed: number): RockModels.Variant
	return if math.floor(seed / 2) % 2 == 0 then "A" else "B"
end

-- One decoration model at the origin. `sizeName` is "small", "mid" or
-- "large" (rocks). `look` is a biome palette (meadow, snow, shore, volcano,
-- gloam, cave). Plants ignore both and stay hand-sized. A rock is tilted
-- and sunk so it sits in the ground.
local function buildOne(kind: string, seed: number, sizeName: string?, look: string?, tilt: boolean): Model
	local rng = Kit.rng(seed)
	local s = scaleOf(sizeName)
	local m = model(kind)
	local body = BODIES[kind]
	if body then
		local rockLook = palette(look)
		body(m, s, rockLook)
		local crown = CROWNS[kind]
		if crown then
			crown(m, s, rockLook)
		end
		local accent = ACCENTS[kind]
		if accent then
			accent(m, s, rockLook)
		end
		applyNatureMeshes(m, kind, variantFor(seed), lookName(look), rockLook, s)
		if tilt then
			settle(m, seed)
		end
		return m
	end
	if kind == "Fern" then
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
		-- Bush, and any kind this builder does not know yet.
		bush(m, 1, rng)
	end
	local host = m:FindFirstChildWhichIsA("BasePart")
	if host and (kind == "GlowFungus" or kind == "CrystalRock" or kind == "GloamCap" or kind == "IsleCrystal") then
		local range = if kind == "IsleCrystal" then 10 elseif kind == "GloamCap" then 8 else 7
		glowLight(host, if kind == "GlowFungus" then hex("#7AF2C8") else NatureArt.WispViolet, range)
	end
	return m
end

function NatureArt.Build(kind: string, seed: number, sizeName: string?, look: string?): Model
	return buildOne(kind, seed, sizeName, look, true)
end

-- Build without the tilt, jitter and sink: the rock stands at its build
-- origin. For specs and previews that check where the mesh pieces sit.
function NatureArt.BuildFlat(kind: string, seed: number, sizeName: string?, look: string?): Model
	return buildOne(kind, seed, sizeName, look, false)
end

local function oreSeed(shape: string, sizeName: string): number
	local n = 0
	for i = 1, #shape do
		n += string.byte(shape, i) * i
	end
	return n + #sizeName * 17
end

-- The host is chosen so the vein reads: black ore on light grey, bright
-- ore on dark stone, the middle ores on a mid grey.
local HOST_LIGHT: RockLook = {
	stone = hex("#C9CDD4"),
	dark = hex("#AEB3BC"),
	light = hex("#E2E6EC"),
	cap = hex("#B7BCC4"),
	stoneMat = ROCK,
	bandMat = SLATE,
	capMat = SLATE,
}
local HOST_MID: RockLook = {
	stone = hex("#8A8680"),
	dark = hex("#6A6662"),
	light = hex("#A8A39C"),
	cap = hex("#7A766F"),
	stoneMat = ROCK,
	bandMat = SLATE,
	capMat = SLATE,
}
local HOST_DARK: RockLook = {
	stone = hex("#3C3A38"),
	dark = hex("#2A2826"),
	light = hex("#5C5854"),
	cap = hex("#454240"),
	stoneMat = ROCK,
	bandMat = SLATE,
	capMat = SLATE,
}

local function oreHost(oreColor: Color3): RockLook
	local lum = luminance(oreColor)
	if lum < 0.22 then
		return HOST_LIGHT
	elseif lum > 0.62 then
		return HOST_DARK
	end
	return HOST_MID
end

-- A rock with ore showing. `shape` is one of RockShapes. Veins are 2 thin
-- wedges, each about a fifth of the face they sit on. The whole model is
-- 8 parts or fewer. `oreId`, when it is an OreData row, wins the vein
-- color, the material and the glow, and is stored as OreId. With no id,
-- OreId stays "" for Lane M and the colors passed in are used. Neon and a
-- PointLight are added only when the ore glows, and that light casts no
-- shadow. A pale vein gets a dim light; a saturated one shines. A missing
-- mesh keeps this part build.
function NatureArt.OreRock(
	shape: string,
	sizeName: string,
	oreColor: Color3,
	oreMaterial: Enum.Material,
	glow: boolean?,
	oreId: string?
): Model
	local m = model("OreRock")
	CollectionService:AddTag(m, "OreRockArt")
	local color = oreColor
	local material = oreMaterial
	local useGlow = glow == true
	local heartstone = false
	if oreId ~= nil and oreId ~= "" then
		local ore = OreData.Get(oreId)
		if ore then
			color = ore.color
			material = ore.material
			useGlow = ore.glow
			heartstone = ore.id == "heartstone"
			m:SetAttribute("OreId", ore.id)
		else
			logUnknownOre(oreId)
			m:SetAttribute("OreId", "")
		end
	else
		m:SetAttribute("OreId", "")
	end
	local s = scaleOf(sizeName)
	local kind, variantRaw, moss = RockModels.KindFor(shape)
	local variant: RockModels.Variant = variantRaw :: any
	local body = BODIES[kind] or BODIES.Boulder
	local hostLook = oreHost(color)
	body(m, s, hostLook)
	embedVeins(m, kind, color, veinMaterial(material, useGlow))
	local meshed = applyOreMeshes(m, kind, variant, moss, s, hostLook, color, material, useGlow, heartstone)
	if not meshed and useGlow then
		local host = m:FindFirstChild("Vein")
		if host and host:IsA("BasePart") then
			oreGlow(host, color)
		end
	end
	settle(m, oreSeed(shape, sizeName))
	return m
end

-- Scenery built from RockModels.Scenery pieces (Body, Frame, Glow, Collision).
-- `at` is the pivot (ground height at the mouth), the opening faces model -Z
-- and the throat runs to +Z. Pieces sit at the Body centre plus their offset.
-- Body, Frame and Glow are looks only (no collision); Collision is the
-- invisible blocker. A 0 id or a failed load keeps a plain part-built frame
-- of the same opening, logged once.
local MOUTH_WIDTH = 16
local MOUTH_HEIGHT = 12

local function caveMouthParts(m: Model, spec: RockModels.Scenery)
	local base = CFrame.new(spec.hostCentre)
	local body = spec.pieces.Body
	local function at(piece: RockModels.SceneryPiece): CFrame
		return base * CFrame.new(piece.offset)
	end
	local stone = hex("#7E766C")
	local timber = hex("#6B4A2B")
	local sideW = (body.size.X - MOUTH_WIDTH) * 0.5
	local y = body.size.Y * 0.5
	local depth = body.size.Z
	part(
		m,
		"Body",
		Vector3.new(sideW, body.size.Y, depth),
		base * CFrame.new(-(MOUTH_WIDTH + sideW) * 0.5, 0, 0),
		stone,
		ROCK
	)
	part(
		m,
		"Body",
		Vector3.new(sideW, body.size.Y, depth),
		base * CFrame.new((MOUTH_WIDTH + sideW) * 0.5, 0, 0),
		stone,
		ROCK
	)
	local lintel = body.size.Y - MOUTH_HEIGHT
	part(
		m,
		"Body",
		Vector3.new(MOUTH_WIDTH, lintel, depth),
		base * CFrame.new(0, -y + MOUTH_HEIGHT + lintel * 0.5, 0),
		stone,
		ROCK
	)
	part(
		m,
		"Frame",
		Vector3.new(MOUTH_WIDTH + 1.6, 0.8, 0.8),
		base * CFrame.new(0, -y + MOUTH_HEIGHT + 0.4, -depth * 0.5),
		timber,
		Enum.Material.Wood
	)
	for _, sx in ipairs({ -1, 1 }) do
		part(
			m,
			"Frame",
			Vector3.new(0.8, MOUTH_HEIGHT, 0.8),
			base * CFrame.new(sx * (MOUTH_WIDTH + 0.8) * 0.5, -y + MOUTH_HEIGHT * 0.5, -depth * 0.5),
			timber,
			Enum.Material.Wood
		)
	end
	local glow = spec.pieces.Glow
	part(m, "Glow", Vector3.new(glow.size.X, 0.4, 0.3), at(glow), hex("#FFC873"), Enum.Material.Neon)
end

local function caveMouthLight(parent: BasePart)
	local lamp = Instance.new("PointLight")
	lamp.Name = "MouthLight"
	lamp.Range = 14
	lamp.Brightness = 1
	lamp.Color = hex("#FFC873")
	lamp.Shadows = false
	lamp.Parent = parent
end

function NatureArt.CaveMouth(): Model
	local m = model("CaveMouth")
	local spec = RockModels.Scenery("CaveMouth")
	assert(spec, "CaveMouth spec missing")
	local base = CFrame.new(spec.hostCentre)
	local order = { "Body", "Frame", "Glow", "Collision" }
	local ok = true
	for _, name in ipairs(order) do
		if not RockModels.UsesMesh(spec.pieces[name].meshId) then
			logFallback("CaveMouth", name, spec.pieces[name].meshId)
			m:SetAttribute("MeshFallback", name)
			ok = false
			break
		end
	end
	local made: { MeshPart } = {}
	if ok then
		for _, name in ipairs(order) do
			local piece = spec.pieces[name]
			local fidelity = if name == "Body" or name == "Collision" then Enum.CollisionFidelity.Hull else nil
			local mesh = MeshKit.Create(piece.meshId, name, piece.size, fidelity)
			if not mesh then
				logFallback("CaveMouth", name, piece.meshId)
				m:SetAttribute("MeshFallback", name)
				for _, d in ipairs(made) do
					d:Destroy()
				end
				ok = false
				break
			end
			MeshKit.Visual(mesh, piece.meshId)
			mesh.Anchored = true
			mesh.CFrame = if name == "Body" then base else base * CFrame.new(piece.offset)
			Kit.decor(mesh, false)
			if name == "Body" then
				mesh.Color = NatureArt.CliffRock
				mesh.Material = ROCK
			elseif name == "Frame" then
				mesh.Color = Color3.new(1, 1, 1)
			elseif name == "Glow" then
				mesh.Material = Enum.Material.Neon
				mesh.Color = hex("#FFC873")
			elseif name == "Collision" then
				mesh.Transparency = 1
				mesh.CanCollide = true
				mesh.CanQuery = true
			end
			mesh.Parent = m
			table.insert(made, mesh)
		end
	end
	if ok then
		local glow = m:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then
			caveMouthLight(glow)
		end
		m:SetAttribute("RockMesh", true)
		return m
	end
	caveMouthParts(m, spec)
	local lit = m:FindFirstChild("Glow")
	if lit and lit:IsA("BasePart") then
		caveMouthLight(lit)
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
	for _ = 1, count do
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
		for _ = 1, splashes do
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
