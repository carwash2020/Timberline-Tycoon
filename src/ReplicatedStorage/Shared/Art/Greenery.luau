--!strict
-- Greenery (T414d-2): the town's ornamental greenery (BuildingArt.Greenery
-- delegates here) and the roadside decor Scatter plans: grass, ferns,
-- shrubs, flowers, pebbles, reeds and dry scrub (client cover, under 4
-- studs); stumps, large rocks, saplings and dead snags (the server's, built
-- once). Pure (see Kit): the preview shows what the game builds.
--   * Cover never collides, is not queried, cannot be touched and casts no
--     shadow. A stump and a large rock collide (they are what a truck must
--     not drive through); a sapling and a snag do not.
--   * Every model stands on y = 0, its origin on the ground. A rock sinks
--     30% of its height; a stump's body runs 0.45 below the ground (the
--     0.05 seat and a 0.4 skirt that hides the slope).
--   * A stump is a square Block (the LT2 rule): bark on the sides, the
--     species core on a thin cut face with a crack darkened 25%, and on
--     some a DeepMeadow moss cap.
--   * Colours come from Palette and Kit.hex (no raw Color3).

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local PerfPolicy = require(script.Parent.Parent.PerfPolicy)
local PropArt = require(script.Parent.PropArt)
local TreeArt = require(script.Parent.TreeArt)
local WoodData = require(script.Parent.Parent.WoodData)

local Greenery = {}

local hex = Kit.hex
local TIP = hex("#7FB052") -- sunlit tips
local PINK = hex("#E9A9BC")
local AMBER = hex("#D98A1E")
local SCRUB = hex("#9C8466") -- Red Mesa dry scrub
local STONES = { Palette.CliffRock, Palette.QuarrySlate, Palette.CliffRock }
local SAND_STONES = { Palette.ShoreSand, Palette.CliffRock, Palette.ShoreSand }

Greenery.SeatDepth = 0.05
Greenery.Skirt = 0.4
Greenery.RockSink = 0.3

-- The town's pieces (WorldPlan.Town().greenery): `tree` is BuildingArt.TownTree and `bed`
-- BuildingArt's flower bed (both build on BuildingArt's own helpers, so they are passed in).
function Greenery.Build(
	kind: string,
	size: number,
	seed: number,
	woodId: string?,
	tree: (string, number, number) -> Model,
	bed: (number, number) -> Model
): Model
	if kind == "tree" then
		return tree(woodId or "birch", seed, size)
	elseif kind == "flowers" then
		return bed(size, seed)
	elseif kind == "rock" then
		local base = Palette.StoneBase -- the town's own stone, as before
		local rock = PropArt.Rock(size, seed, {
			base,
			Kit.shade(base, 0.08),
			Kit.shade(base, -0.1),
			Palette.TownCobble,
		})
		Kit.decorAll(rock, { Rock = true })
		return rock
	end
	return PropArt.Bush(size, seed, { Palette.MeadowGrass, Palette.DeepMeadow, Palette.PineTrim })
end

---------------------------------------------------------------------------
-- Cover (client, under 4 studs, never collides)
---------------------------------------------------------------------------

local function cover(model: Model): Model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			Kit.decor(d, false)
		end
	end
	return model
end

local GREENS = { Palette.MeadowGrass, Palette.DeepMeadow, Palette.MeadowGrass }

-- An irregular clump of overlapping rounded blobs, 2 to 3.8 studs across and never a ball.
local function clump(name: string, variant: number, greens: { Color3 }, cap: Color3?, material: Enum.Material): Model
	local model = Kit.model(name)
	local rng = Kit.rng(variant * 53 + 11)
	local count = rng:int(5, 7)
	local width = 2 + variant * 0.3
	for i = 1, count do
		local a = i / count * math.pi * 2 + rng:range(-0.4, 0.4)
		local r = if i == 1 then 0 else rng:range(0.25, 0.4) * width
		local w = rng:range(0.45, 0.75) * width
		local h = rng:range(0.5, 0.9) * width * 0.7
		local color = Kit.vary(if i % 3 == 0 then TIP else greens[(i % #greens) + 1], rng, 0.05)
		Kit.ellipsoid(
			model,
			"Blob",
			Vector3.new(w, h, w * rng:range(0.8, 1.15)),
			CFrame.new(math.cos(a) * r, h * 0.42, math.sin(a) * r)
				* CFrame.Angles(0, rng:range(0, 3), rng:range(-0.2, 0.2)),
			color,
			material
		)
	end
	if cap then
		Kit.ellipsoid(
			model,
			"Cap",
			Vector3.new(width * 0.7, width * 0.18, width * 0.62),
			CFrame.new(0, width * 0.52, 0),
			cap,
			Enum.Material.Snow
		)
	end
	return model
end

local function stalks(variant: number, region: string): Model
	local model = Kit.model("Reeds")
	local rng = Kit.rng(variant * 29 + 5)
	Kit.ellipsoid(model, "Mud", Vector3.new(2.4, 0.3, 2.2), CFrame.new(0, 0.05, 0), Palette.WetMud, Enum.Material.Mud)
	for _ = 1, 7 do
		local h = rng:range(2.2, 3.6)
		local a = rng:range(0, math.pi * 2)
		local d = rng:range(0, 0.9)
		Kit.part(
			model,
			"Reed",
			Vector3.new(0.1, h, 0.1),
			CFrame.new(math.cos(a) * d, h / 2, math.sin(a) * d)
				* CFrame.Angles(rng:range(-0.12, 0.12), 0, rng:range(-0.12, 0.12)),
			Kit.vary(if region == "bayou" then Palette.DeepMeadow else TIP, rng, 0.06),
			Enum.Material.Grass
		)
	end
	return model
end

local function flowers(variant: number): Model
	local model = Kit.model("Flowers")
	local rng = Kit.rng(variant * 71 + 3)
	local accent = ({ PINK, Palette.LumenGlow, AMBER })[(variant % 3) + 1]
	for i = 1, 3 do
		local a = i * 2.1 + rng:range(-0.3, 0.3)
		local h = rng:range(0.7, 1.2)
		local x, z = math.cos(a) * 0.4, math.sin(a) * 0.4
		Kit.part(
			model,
			"Stem",
			Vector3.new(0.06, h, 0.06),
			CFrame.new(x, h / 2, z),
			Palette.DeepMeadow,
			Enum.Material.Grass
		)
		Kit.ball(model, "Bloom", 0.28, CFrame.new(x, h + 0.05, z), accent, Enum.Material.SmoothPlastic)
	end
	return model
end

local function rockPiece(size: number, seed: number, palette: { Color3 }): Model
	local rock = PropArt.Rock(size, seed, palette)
	rock.Name = "Rock"
	return rock
end

-- Ground cover for `kind` in `region`; nil for a kind this is not (a built piece).
function Greenery.Cover(kind: string, region: string, variant: number): Model?
	local model: Model
	if kind == "grass" then
		model = PropArt.GrassTuft(variant * 7 + 1, GREENS[(variant % #GREENS) + 1])
	elseif kind == "fern" then
		model = PropArt.FernClump(variant * 5 + 2, Palette.PineTrim)
	elseif kind == "shrub" then
		local snowy = region == "snow"
		model = clump(
			"Shrub",
			variant,
			{ Palette.PineTrim, Palette.DeepMeadow, Palette.MeadowGrass },
			if snowy then Palette.FreshSnow else nil,
			Enum.Material.Grass
		)
	elseif kind == "scrub" then
		model = clump("Scrub", variant, { SCRUB, Palette.ShoreSand, SCRUB }, nil, Enum.Material.Sand)
	elseif kind == "reed" then
		model = stalks(variant, region)
	elseif kind == "flower" then
		model = flowers(variant)
	elseif kind == "pebble" then
		model = rockPiece(1.4 + variant * 0.2, variant * 3 + 1, if region == "mesa" then SAND_STONES else STONES)
		model:PivotTo(CFrame.new(0, -0.25, 0) * model:GetPivot())
	else
		return nil
	end
	return cover(model)
end

---------------------------------------------------------------------------
-- Built pieces (the server, once)
---------------------------------------------------------------------------

local WOODS: { [string]: { string } } = {
	starter = { "oak", "birch" },
	hills = { "pine", "oak" },
	snow = { "pine", "frostwood" },
	gloam = { "phantomwood" },
	volcano = { "emberwood" },
}

local function woodFor(region: string, variant: number): WoodData.WoodDef
	local list = WOODS[region] or { "oak", "maple", "birch" }
	local def = WoodData.Get(list[(variant % #list) + 1]) or WoodData.Get("oak")
	assert(def, "[Greenery] no oak in WoodData")
	return def
end

-- A square Block stump `width` across: bark sides, the species core on a thin cut face with a
-- crack, and on every third variant a moss cap. Collides; the cut face and crack do not.
function Greenery.Stump(region: string, variant: number, width: number): Model
	local def = woodFor(region, variant)
	local rng = Kit.rng(variant * 37 + 9)
	local model = Kit.model("Stump")
	local h = 1.0 + (variant % 4) * 0.25
	local depth = Greenery.SeatDepth + Greenery.Skirt
	local body = Kit.part(
		model,
		"StumpBody",
		Vector3.new(width, h + depth, width),
		CFrame.new(0, (h - depth) / 2, 0),
		Kit.vary(def.trunkColor, rng, 0.03),
		Enum.Material.Wood
	)
	Kit.solid(body)
	body.CanTouch = false
	local face, material = TreeArt.FaceLook(def)
	Kit.decor(
		Kit.part(model, "StumpTop", Vector3.new(width * 0.9, 0.1, width * 0.9), CFrame.new(0, h, 0), face, material),
		false
	)
	Kit.decor(
		Kit.part(
			model,
			"StumpCrack",
			Vector3.new(width * 0.5, 0.04, 0.12),
			CFrame.new(width * 0.05, h + 0.06, 0) * CFrame.Angles(0, rng:range(0, 3), 0),
			Kit.shade(face, -0.25),
			material
		),
		false
	)
	if variant % 3 == 0 then
		Kit.decor(
			Kit.part(
				model,
				"StumpMoss",
				Vector3.new(width * 0.55, 0.14, width * 0.4),
				CFrame.new(-width * 0.18, h + 0.08, width * 0.2),
				Palette.DeepMeadow,
				Enum.Material.Grass
			),
			false
		)
	end
	model.PrimaryPart = body
	return model
end

-- A large rock `size` across, sunk 30% of its height into the ground. Its stones collide.
function Greenery.Rock(region: string, variant: number, size: number): Model
	local rock = rockPiece(size, variant * 11 + 4, if region == "mesa" then SAND_STONES else STONES)
	Kit.decorAll(rock, { Rock = true })
	for _, d in ipairs(rock:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Rock" then
			d.CanTouch = false
		end
	end
	local cf, extent = rock:GetBoundingBox()
	local bottom = cf.Position.Y - extent.Y / 2
	rock:PivotTo(CFrame.new(0, -Greenery.RockSink * extent.Y - bottom, 0) * rock:GetPivot())
	return rock
end

-- A young tree 3.4 to 4.8 studs tall: a square trunk and a few leaf blobs. Looks only.
function Greenery.Sapling(region: string, variant: number, height: number): Model
	local def = woodFor(region, variant)
	local rng = Kit.rng(variant * 41 + 13)
	local model = Kit.model("Sapling")
	local t = 0.3
	Kit.part(
		model,
		"Trunk",
		Vector3.new(t, height * 0.7, t),
		CFrame.new(0, height * 0.35, 0),
		def.trunkColor,
		Enum.Material.Wood
	)
	for i = 1, 4 do
		local a = i * 1.6 + rng:range(-0.3, 0.3)
		local w = rng:range(1.1, 1.6)
		Kit.ellipsoid(
			model,
			"Leaves",
			Vector3.new(w, w * 0.8, w),
			CFrame.new(math.cos(a) * 0.35, height * (0.62 + i * 0.08), math.sin(a) * 0.35),
			Kit.vary(if region == "snow" then Palette.PineTrim else Palette.MeadowGrass, rng, 0.05),
			Enum.Material.Grass
		)
	end
	return cover(model)
end

-- A dead tree 5 to 7 studs tall: a weathered square trunk and bare branches. Looks only.
function Greenery.Snag(_region: string, variant: number, height: number): Model
	local rng = Kit.rng(variant * 43 + 17)
	local model = Kit.model("Snag")
	local bark = Palette.TimberBrown:Lerp(Palette.CliffRock, 0.55)
	local t = 0.7
	Kit.part(model, "Trunk", Vector3.new(t, height, t), CFrame.new(0, height / 2, 0), bark, Enum.Material.Wood)
	for i = 1, 3 do
		local a = i * 2.2 + rng:range(-0.4, 0.4)
		local len = rng:range(1.4, 2.4)
		local at = height * (0.55 + i * 0.12)
		Kit.part(
			model,
			"Branch",
			Vector3.new(0.22, len, 0.22),
			CFrame.new(math.cos(a) * 0.5, at, math.sin(a) * 0.5)
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, -0.9)
				* CFrame.new(0, len / 2, 0),
			bark,
			Enum.Material.Wood
		)
	end
	return cover(model)
end

-- Any planned item's model, by kind (cover or built). Parts too small for a shadow to read cast none (T415).
function Greenery.Item(kind: string, region: string, variant: number, size: number): Model?
	local model: Model?
	if kind == "stump" then
		model = Greenery.Stump(region, variant, size)
	elseif kind == "rock" then
		model = Greenery.Rock(region, variant, size)
	elseif kind == "sapling" then
		model = Greenery.Sapling(region, variant, size)
	elseif kind == "snag" then
		model = Greenery.Snag(region, variant, size)
	else
		model = Greenery.Cover(kind, region, variant)
	end
	if model then
		PerfPolicy.TrimShadows(model)
	end
	return model
end

return Greenery
