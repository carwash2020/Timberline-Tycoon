--!strict
-- PropArt: nature's small things, so the world never looks empty: rocks,
-- bushes, flowers, ferns, grass tufts, reeds and cattails, lily pads,
-- fallen logs and old stumps, pebbles, pinecones, berry bushes, snow
-- piles, lava rocks, crystals. Pure (see Kit). Clients scatter most of
-- these around the player (AmbientLife, via PropArt.Scatter); MapBuilder
-- places the landmarks (boulders, the grove's mushrooms).
--
-- Every builder returns a Model on the ground at the origin (y = 0; a
-- LilyPad's origin is the water's surface), decoration only (no
-- collisions, clicks or touches; small parts cast no shadow) unless noted.
-- Only Rock and the open-country set pieces' big bodies (stones, walls,
-- towers: see below) collide; Scatter's are all decoration, Rock
-- included. They're cheap: Rock and most others are under 10
-- parts, so hundreds can stand round a player. Colours come in as
-- parameters so each biome can tint them (PropArt.Tints has a palette per
-- biome).

local Kit = require(script.Parent.Kit)

type Rng = Kit.Rng

local PropArt = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local STONE = { Color3.fromRGB(140, 134, 126), Color3.fromRGB(120, 116, 110), Color3.fromRGB(158, 150, 140) }
-- Brown rock for the open country (STY-03: brown boulders on green, not
-- grey): a warm brown and a greyer umber, so a field of rocks isn't one
-- flat colour. The lone boulders, the scenery outcrops and the boulder
-- clusters (LandmarkArt.BrownRock) all use these.
PropArt.BrownTones = {
	{ Color3.fromRGB(132, 102, 78), Color3.fromRGB(116, 90, 70), Color3.fromRGB(148, 118, 90) },
	{ Color3.fromRGB(118, 100, 84), Color3.fromRGB(102, 88, 76), Color3.fromRGB(134, 116, 98) },
} :: { { Color3 } }
local MOSS = hex("#7FA650")
PropArt.Moss = MOSS -- a mossy cap's colour (PropArt.Rock's `moss`)
local STEM = hex("#5E9442")
local LEAF = hex("#6FAE4E")
local BARK = hex("#6E5038")
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- A looks-only part (no shadow unless asked).
local function bit(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?
): Part
	local p = Kit.part(model, name, size, cf, color, material)
	Kit.decor(p, shadow == true)
	return p
end

local function wedgeBit(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local p = Kit.wedge(model, name, size, cf, color, material)
	Kit.decor(p, false)
	return p
end

-- CFrame.lookAt from fromMatrix (the same frame in Roblox; also right in
-- the preview, where Lune 0.10's lookAt isn't).
local function lookAt(at: Vector3, target: Vector3): CFrame
	local look = (target - at).Unit
	local ref = if math.abs(look.Y) > 0.999 then Vector3.zAxis else Vector3.yAxis
	local right = look:Cross(ref).Unit
	return CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

-- A looks-only cylinder from a to b.
local function rod(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	d: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.cylinder(
		model,
		name,
		(b - a).Magnitude,
		d,
		lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material
	)
	Kit.decor(p, false)
	return p
end

-- An upright looks-only cylinder (axis vertical) centred at `at`.
local function disc(
	model: Model,
	name: string,
	at: Vector3,
	thickness: number,
	d: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.decor(
		Kit.cylinder(model, name, thickness, d, CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), color, material),
		false
	)
end

-- The frame of a cube standing on a corner at `at` (the round, faceted
-- look of leaves and boulders).
local function cornerUp(at: Vector3, yaw: number): CFrame
	return CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(35.26), math.rad(45), 0)
end

-- A small flower: a stem, a four-petal head (a square turned 45 degrees)
-- and, if `center` is given, a heart. Returns how many parts it made.
local function flower(model: Model, at: Vector3, h: number, petal: Color3, center: Color3?, yaw: number): number
	bit(model, "Stem", Vector3.new(0.1, h, 0.1), CFrame.new(at + Vector3.new(0, h / 2, 0)), STEM)
	bit(
		model,
		"Petals",
		Vector3.new(0.55, 0.12, 0.55),
		CFrame.new(at + Vector3.new(0, h, 0)) * CFrame.Angles(0, yaw + math.pi / 4, 0) * CFrame.Angles(0.15, 0, 0),
		petal
	)
	if center then
		bit(model, "FlowerHeart", Vector3.new(0.2, 0.14, 0.2), CFrame.new(at + Vector3.new(0, h + 0.07, 0)), center)
		return 3
	end
	return 2
end

---------------------------------------------------------------------------
-- Stones
---------------------------------------------------------------------------

-- A faceted boulder about `size` studs across, sunk a little into the
-- ground so it sits on slopes. Its three big stones collide (you can climb
-- it); the pebbles and moss are decoration. With the default stone colours
-- one in three wears a cap of moss; pass `moss` to give any rock one.
function PropArt.Rock(size: number, seed: number, colors: { Color3 }?, moss: Color3?): Model
	local model = Kit.model("Rock")
	local rng = Kit.rng(seed)
	local palette = colors or STONE
	local s = size
	local yaw = rng:range(0, math.pi * 2)
	local turn = CFrame.Angles(0, yaw, 0)
	local function stone(name: string, dims: Vector3, offset: Vector3, tilt: CFrame, color: Color3): Part
		return Kit.part(
			model,
			name,
			dims,
			CFrame.new(turn:VectorToWorldSpace(offset)) * turn * tilt,
			Kit.vary(color, rng, 0.04),
			Enum.Material.Slate
		)
	end
	-- The body (tipped so its top is a slanting facet), a corner-up cap and
	-- a shoulder leaning on it: they collide.
	stone(
		"Rock",
		Vector3.new(s * 0.92, s * 0.62, s * 0.78),
		Vector3.new(0, s * 0.14, 0),
		CFrame.Angles(rng:range(0.22, 0.34) * rng:sign(), 0, rng:range(0.15, 0.26) * rng:sign()),
		palette[1]
	)
	local cap = stone(
		"Rock",
		Vector3.new(s * 0.62, s * 0.5, s * 0.58),
		Vector3.new(s * 0.08, s * 0.4, -s * 0.04),
		CFrame.Angles(math.rad(35.26), math.rad(45), rng:range(-0.2, 0.2)),
		palette[3] or palette[1]
	)
	stone(
		"Rock",
		Vector3.new(s * 0.52, s * 0.44, s * 0.48),
		Vector3.new(-s * 0.4, s * 0.1, s * 0.18),
		CFrame.Angles(rng:range(0.35, 0.55), rng:range(0.4, 0.9), rng:range(0.3, 0.5)),
		palette[2] or palette[1]
	)
	-- Pebbles at its foot (looks only).
	for i = 1, 2 do
		local a = yaw + i * 2.4 + rng:range(-0.3, 0.3)
		local p = s * rng:range(0.14, 0.22)
		bit(
			model,
			"RockPebble",
			Vector3.new(p, p * 0.6, p * 0.85),
			CFrame.new(math.cos(a) * s * 0.62, p * 0.15, math.sin(a) * s * 0.55)
				* CFrame.Angles(rng:range(-0.5, 0.5), rng:range(0, 3), rng:range(-0.5, 0.5)),
			Kit.vary(palette[(i % #palette) + 1], rng, 0.05),
			Enum.Material.Slate
		)
	end
	local mossColor = moss or (if palette == STONE and seed % 3 == 0 then MOSS else nil)
	if mossColor then
		local m = Kit.part(
			model,
			"Moss",
			Vector3.new(s * 0.6, s * 0.12, s * 0.5),
			cap.CFrame * CFrame.new(0, s * 0.2, 0),
			Kit.vary(mossColor, rng, 0.04),
			Enum.Material.Grass
		)
		Kit.decor(m, false)
	end
	return model
end

-- A scatter of 4-6 small flat stones.
function PropArt.Pebbles(seed: number, colors: { Color3 }?): Model
	local model = Kit.model("Pebbles")
	local rng = Kit.rng(seed)
	local palette = colors or STONE
	for i = 1, rng:int(4, 6) do
		local a, r = rng:range(0, math.pi * 2), rng:range(0.2, 1.6)
		local p = rng:range(0.25, 0.6)
		bit(
			model,
			"Pebble",
			Vector3.new(p, p * 0.45, p * 0.8),
			CFrame.new(math.cos(a) * r, p * 0.15, math.sin(a) * r)
				* CFrame.Angles(rng:range(-0.45, 0.45), rng:range(0, 3), rng:range(-0.45, 0.45)),
			Kit.vary(palette[(i - 1) % #palette + 1], rng, 0.06),
			Enum.Material.Slate
		)
	end
	return model
end

-- Dark volcanic rock split by glowing cracks, an ember glow at its foot.
function PropArt.LavaRock(seed: number, size: number): Model
	local model = Kit.model("LavaRock")
	local rng = Kit.rng(seed)
	local s = size
	local DARK = { hex("#3A3330"), hex("#2E2826"), hex("#4A403B") }
	local GLOW = hex("#FF7A1A")
	local yaw = rng:range(0, math.pi * 2)
	local body = bit(
		model,
		"LavaRock",
		Vector3.new(s, s * 0.62, s * 0.84),
		CFrame.new(0, s * 0.2, 0) * CFrame.Angles(rng:range(-0.1, 0.1), yaw, rng:range(-0.1, 0.1)),
		Kit.vary(DARK[1], rng, 0.03),
		Enum.Material.Basalt,
		true
	)
	local cap = bit(
		model,
		"LavaRock",
		Vector3.new(s * 0.6, s * 0.5, s * 0.55),
		cornerUp(Vector3.new(math.cos(yaw) * s * 0.1, s * 0.45, math.sin(yaw) * s * 0.1), yaw),
		Kit.vary(DARK[2], rng, 0.03),
		Enum.Material.Basalt,
		true
	)
	bit(
		model,
		"LavaRock",
		Vector3.new(s * 0.45, s * 0.36, s * 0.4),
		CFrame.new(math.cos(yaw + 2) * s * 0.42, s * 0.12, math.sin(yaw + 2) * s * 0.4)
			* CFrame.Angles(rng:range(-0.3, 0.3), rng:range(0, 3), rng:range(-0.3, 0.3)),
		Kit.vary(DARK[3], rng, 0.03),
		Enum.Material.Basalt
	)
	-- Cracks: glowing seams across the top and down a side.
	local sz = body.Size
	for i = 1, 2 do
		bit(
			model,
			"LavaCrack",
			Vector3.new(s * 0.07, 0.06, sz.Z * rng:range(0.5, 0.8)),
			body.CFrame
				* CFrame.new(rng:range(-0.25, 0.25) * sz.X, sz.Y / 2 + 0.01, 0)
				* CFrame.Angles(0, rng:range(-0.6, 0.6) + i, 0),
			GLOW,
			Enum.Material.Neon
		)
	end
	bit(
		model,
		"LavaCrack",
		Vector3.new(0.06, sz.Y * 0.8, s * 0.07),
		body.CFrame
			* CFrame.new(sz.X / 2 + 0.01, 0, rng:range(-0.2, 0.2) * sz.Z)
			* CFrame.Angles(rng:range(-0.4, 0.4), 0, 0),
		GLOW,
		Enum.Material.Neon
	)
	bit(
		model,
		"LavaCrack",
		Vector3.new(s * 0.06, 0.06, s * 0.3),
		cap.CFrame * CFrame.new(0, cap.Size.Y / 2 + 0.01, 0),
		GLOW,
		Enum.Material.Neon
	)
	-- Embers glowing in the ground at its foot.
	disc(model, "Embers", Vector3.new(0, 0.02, 0), 0.05, s * 1.3, hex("#C2400E"), Enum.Material.Neon).Transparency =
		0.35
	return model
end

-- A crystal cluster: pointed shards round a glowing one, on a stone base
-- (Sky Shard look, ice in the snow, embers by the lava).
function PropArt.Crystal(seed: number, color: Color3, size: number): Model
	local model = Kit.model("Crystal")
	local rng = Kit.rng(seed)
	local s = size
	bit(
		model,
		"CrystalBase",
		Vector3.new(s * 0.8, s * 0.3, s * 0.7),
		CFrame.new(0, s * 0.08, 0) * CFrame.Angles(0, rng:range(0, 3), rng:range(-0.1, 0.1)),
		Kit.shade(color, -0.55),
		Enum.Material.Slate
	)
	local shards = {
		{ h = 1.15, w = 0.26, r = 0, glow = true },
		{ h = 0.8, w = 0.22, r = 0.28, glow = false },
		{ h = 0.6, w = 0.18, r = 0.3, glow = false },
		{ h = 0.45, w = 0.16, r = 0.32, glow = false },
	}
	local yaw = rng:range(0, math.pi * 2)
	for i, sh in ipairs(shards) do
		local a = yaw + i * 2.1
		local h, w = sh.h * s * rng:range(0.85, 1.1), sh.w * s
		local lean = if i == 1 then rng:range(-0.12, 0.12) else 0.35 + rng:range(-0.1, 0.15)
		local cf = CFrame.new(math.cos(a) * sh.r * s, s * 0.1, math.sin(a) * sh.r * s)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, -lean)
			* CFrame.Angles(0, math.pi / 4, 0)
		local body = bit(
			model,
			"Shard",
			Vector3.new(w, h, w),
			cf * CFrame.new(0, h / 2, 0),
			if sh.glow then color else Kit.shade(color, 0.25),
			if sh.glow then Enum.Material.Neon else Enum.Material.Glass
		)
		if not sh.glow then
			body.Transparency = 0.15
		end
		if i <= 2 then
			local tip = wedgeBit(
				model,
				"ShardTip",
				Vector3.new(w, w * 1.2, w),
				cf * CFrame.new(0, h + w * 0.6, 0),
				body.Color,
				body.Material
			)
			tip.Transparency = body.Transparency
		end
	end
	return model
end

---------------------------------------------------------------------------
-- Green things
---------------------------------------------------------------------------

-- A leafy bush about `size` studs across: a corner-up core and three
-- smaller cubes round its foot, in the given greens.
function PropArt.Bush(size: number, seed: number, colors: { Color3 }): Model
	local model = Kit.model("Bush")
	local rng = Kit.rng(seed)
	local s = size
	local yaw = rng:range(0, math.pi * 2)
	local shadow = s >= 3
	bit(
		model,
		"Bush",
		Vector3.new(s * 0.62, s * 0.55, s * 0.62),
		cornerUp(Vector3.new(0, s * 0.42, 0), yaw),
		Kit.vary(colors[1], rng, 0.04),
		Enum.Material.SmoothPlastic,
		shadow
	)
	for i = 1, 3 do
		local a = yaw + i * 2.1 + rng:range(-0.3, 0.3)
		local e = s * rng:range(0.4, 0.48)
		bit(
			model,
			"Bush",
			Vector3.new(e, e * 0.85, e),
			cornerUp(Vector3.new(math.cos(a) * s * 0.3, e * 0.42, math.sin(a) * s * 0.3), a),
			Kit.vary(colors[(i % #colors) + 1], rng, 0.05),
			Enum.Material.SmoothPlastic,
			shadow
		)
	end
	return model
end

-- A bush hung with berries: a forage hint (red, or blue by seed).
function PropArt.BerryBush(seed: number, colors: { Color3 }?): Model
	local model = Kit.model("BerryBush")
	local rng = Kit.rng(seed)
	local greens = colors or { hex("#3F7F38"), hex("#4C8F3E"), hex("#5A9A45") }
	local berry = if seed % 2 == 0 then hex("#D8404A") else hex("#5468C8")
	local s = rng:range(2.2, 3)
	local yaw = rng:range(0, math.pi * 2)
	local centers: { { at: Vector3, e: number } } = {}
	for i = 1, 3 do
		local a = yaw + i * 2.1
		local r = if i == 1 then 0 else s * 0.28
		local e = if i == 1 then s * 0.62 else s * 0.46
		local at = Vector3.new(math.cos(a) * r, e * 0.48, math.sin(a) * r)
		table.insert(centers, { at = at, e = e })
		bit(model, "Bush", Vector3.new(e, e * 0.85, e), cornerUp(at, a), Kit.vary(greens[i], rng, 0.04))
	end
	for i = 1, 5 do
		local c = centers[(i - 1) % #centers + 1]
		local a = rng:range(0, math.pi * 2)
		local up = rng:range(-0.1, 0.5)
		local dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit
		Kit.decor(
			Kit.ball(model, "Berry", 0.45, CFrame.new(c.at + dir * c.e * 0.74), Kit.vary(berry, rng, 0.04)),
			false
		)
	end
	return model
end

-- The same as BerryBush (the name the forage code may look for).
PropArt.Berries = PropArt.BerryBush

-- A small patch of flowers (petal colours from the list) and a leaf.
function PropArt.Flowers(seed: number, colors: { Color3 }): Model
	local model = Kit.model("Flowers")
	local rng = Kit.rng(seed)
	local heart = hex("#FFD84D")
	for i = 1, 3 do
		local a = i * 2.1 + rng:range(-0.4, 0.4)
		local r = if i == 1 then 0.1 else rng:range(0.45, 0.8)
		local petal = rng:pick(colors)
		flower(
			model,
			Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
			rng:range(0.6, 1.1),
			petal,
			if petal == heart then WHITE else heart,
			rng:range(0, 3)
		)
	end
	wedgeBit(
		model,
		"Leaf",
		Vector3.new(0.08, 0.35, 0.7),
		CFrame.Angles(0, rng:range(0, 6), 0) * CFrame.new(0, 0.12, -0.35) * CFrame.Angles(0.3, 0, math.pi / 2),
		Kit.vary(LEAF, rng, 0.05),
		Enum.Material.SmoothPlastic
	)
	return model
end

-- A tuft of grass (FOR-04): five to seven thin pointed blades fanned out
-- from one root, the tall middle ones lighter, the two tallest with a
-- sunlit yellow-green tip (a little wedge over the blade's point, nudged
-- forward so its faces never fight the blade's). Shadowless decoration.
local TIP = hex("#E4E28C")
function PropArt.GrassTuft(seed: number, color: Color3): Model
	local model = Kit.model("GrassTuft")
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	local n = rng:int(5, 7)
	local spread = rng:range(0.42, 0.6) -- radians between neighbouring blades
	local blades: { { h: number, cf: CFrame, size: Vector3 } } = {}
	for i = 1, n do
		local mid = 1 - math.abs(i - (n + 1) / 2) / ((n + 1) / 2) -- 1 in the middle, ~0 at the ends
		local h = rng:range(0.7, 1.0) + mid * rng:range(0.5, 0.8)
		local a = yaw + (i - (n + 1) / 2) * spread
		local size = Vector3.new(rng:range(0.1, 0.13), h, rng:range(0.32, 0.46))
		-- Rooted together, each leaning out along its own side of the fan.
		local cf = CFrame.new(math.cos(a) * 0.12, 0, math.sin(a) * 0.12)
			* CFrame.Angles(0, -a - math.pi / 2, 0) -- its front (-Z) toward (cos a, sin a)
			* CFrame.Angles(-(0.12 + (1 - mid) * rng:range(0.25, 0.45)), 0, rng:range(-0.12, 0.12))
			* CFrame.new(0, h / 2 - 0.05, 0)
		local shade = Kit.shade(Kit.vary(color, rng, 0.05), -0.08 + mid * 0.16)
		wedgeBit(model, "Blade", size, cf, shade, Enum.Material.SmoothPlastic)
		table.insert(blades, { h = h, cf = cf, size = size })
	end
	table.sort(blades, function(p, q)
		return p.h > q.h
	end)
	for k = 1, 2 do
		local b = blades[k]
		local tip = b.size * Vector3.new(1.12, 0.32, 0.32)
		wedgeBit(
			model,
			"BladeTip",
			tip,
			b.cf * CFrame.new(0, (b.size.Y - tip.Y) / 2, (b.size.Z - tip.Z) / 2 - 0.02),
			Kit.vary(color:Lerp(TIP, 0.55), rng, 0.04),
			Enum.Material.SmoothPlastic
		)
	end
	return model
end

-- A fern: five or six tapering fronds arching out from a curled heart.
function PropArt.Fern(seed: number, color: Color3): Model
	local model = Kit.model("Fern")
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	local n = rng:int(5, 6)
	for i = 1, n do
		local a = yaw + i / n * math.pi * 2 + rng:range(-0.2, 0.2)
		local L = rng:range(1.6, 2.4)
		local pitch = math.rad(rng:range(28, 42))
		-- A wedge lying flat: wide at the heart, pointed at the tip.
		wedgeBit(
			model,
			"Frond",
			Vector3.new(0.07, rng:range(0.5, 0.65), L),
			CFrame.new(0, 0.06, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(pitch, 0, 0)
				* CFrame.new(0, 0, -L / 2)
				* CFrame.Angles(0, 0, math.pi / 2),
			Kit.vary(color, rng, 0.05),
			Enum.Material.SmoothPlastic
		)
	end
	Kit.decor(Kit.ball(model, "Fiddlehead", 0.3, CFrame.new(0, 0.3, 0), Kit.shade(color, -0.1)), false)
	return model
end

-- Riverbank reeds: a clump of tall, thin, leaning blades.
function PropArt.Reeds(seed: number): Model
	local model = Kit.model("Reeds")
	local rng = Kit.rng(seed)
	local greens = { hex("#7A9A4A"), hex("#8EA858"), hex("#6A8A40"), hex("#A8A868") }
	for i = 1, rng:int(5, 7) do
		local a, r = rng:range(0, math.pi * 2), rng:range(0, 0.7)
		local h = rng:range(2.6, 4.4)
		wedgeBit(
			model,
			"Reed",
			Vector3.new(0.12, h, rng:range(0.3, 0.42)),
			CFrame.new(math.cos(a) * r, h / 2 - 0.1, math.sin(a) * r)
				* CFrame.Angles(0, rng:range(0, 6), 0)
				* CFrame.Angles(rng:range(-0.2, 0.05), 0, rng:range(-0.12, 0.12)),
			Kit.vary(greens[(i - 1) % #greens + 1], rng, 0.04),
			Enum.Material.SmoothPlastic
		)
	end
	return model
end

-- Cattails: tall stems with brown velvet heads, and a couple of blades.
function PropArt.Cattails(seed: number): Model
	local model = Kit.model("Cattails")
	local rng = Kit.rng(seed)
	for i = 1, rng:int(3, 4) do
		local a, r = i * 2.2 + rng:range(-0.3, 0.3), rng:range(0.15, 0.6)
		local base = Vector3.new(math.cos(a) * r, -0.1, math.sin(a) * r)
		local h = rng:range(3, 4.2)
		local top = base + Vector3.new(rng:range(-0.25, 0.25), h, rng:range(-0.25, 0.25))
		rod(model, "CattailStem", base, top, 0.1, hex("#7A9248"), Enum.Material.SmoothPlastic)
		local dir = (top - base).Unit
		rod(
			model,
			"CattailHead",
			top - dir * 1.1,
			top - dir * 0.2,
			0.3,
			Kit.vary(hex("#6B4428"), rng, 0.05),
			Enum.Material.Fabric
		)
	end
	for b = 1, 2 do
		local h = rng:range(2, 2.8)
		wedgeBit(
			model,
			"Blade",
			Vector3.new(0.1, h, 0.35),
			CFrame.new(0, h / 2 - 0.1, 0) * CFrame.Angles(0, b * 2.5, 0) * CFrame.Angles(-0.25, 0, 0),
			hex("#7FA050"),
			Enum.Material.SmoothPlastic
		)
	end
	return model
end

-- A lily pad or two floating on the water (origin: the surface), and, one
-- time in two, a pink water lily.
function PropArt.LilyPad(seed: number): Model
	local model = Kit.model("LilyPad")
	local rng = Kit.rng(seed)
	local pad = hex("#4F9A48")
	local d = rng:range(1.8, 2.8)
	disc(model, "Pad", Vector3.new(0, 0.05, 0), 0.1, d, Kit.vary(pad, rng, 0.05), Enum.Material.SmoothPlastic)
	-- The notch: a sliver of the pad's darker underside, like a cut.
	bit(
		model,
		"PadVein",
		Vector3.new(0.06, 0.04, d * 0.48),
		CFrame.Angles(0, rng:range(0, 6), 0) * CFrame.new(0, 0.11, -d * 0.24),
		Kit.shade(pad, -0.25)
	)
	local a = rng:range(0, math.pi * 2)
	local d2 = d * rng:range(0.55, 0.75)
	disc(
		model,
		"Pad",
		Vector3.new(math.cos(a) * (d + d2) * 0.48, 0.04, math.sin(a) * (d + d2) * 0.48),
		0.1,
		d2,
		Kit.vary(pad, rng, 0.07),
		Enum.Material.SmoothPlastic
	)
	if seed % 2 == 0 then
		local at = Vector3.new(rng:range(-0.3, 0.3), 0.16, rng:range(-0.3, 0.3))
		local yaw = rng:range(0, 3)
		for k = 0, 1 do
			bit(
				model,
				"Lily",
				Vector3.new(0.75 - k * 0.25, 0.22, 0.75 - k * 0.25),
				CFrame.new(at + Vector3.new(0, k * 0.16, 0)) * CFrame.Angles(0, yaw + k * math.pi / 4, 0),
				if k == 0 then hex("#F4A7C8") else hex("#FBD3E4")
			)
		end
		bit(model, "LilyHeart", Vector3.new(0.2, 0.12, 0.2), CFrame.new(at + Vector3.new(0, 0.34, 0)), hex("#FFD84D"))
	end
	return model
end

-- A mushroom with a stepped, faceted cap (and a little one beside it).
-- Glowing ones (the Gloam Hollow's) are Neon teal or violet with a soft
-- light; the rest are red with white spots.
function PropArt.Mushroom(seed: number, glowing: boolean): Model
	local model = Kit.model("Mushroom")
	local rng = Kit.rng(seed)
	local capColor = if glowing then (if seed % 2 == 0 then hex("#55F2E0") else hex("#B58CFF")) else hex("#C4483A")
	local capMat = if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local function shroom(at: Vector3, h: number, w: number, main: boolean): Part
		bit(
			model,
			"Stalk",
			Vector3.new(w * 0.28, h, w * 0.28),
			CFrame.new(at + Vector3.new(0, h / 2, 0)),
			hex("#EDE4CC")
		)
		local yaw = rng:range(0, 3)
		local brim = bit(
			model,
			"Cap",
			Vector3.new(w, w * 0.26, w),
			CFrame.new(at + Vector3.new(0, h, 0)) * CFrame.Angles(0, yaw + math.pi / 4, 0),
			capColor,
			capMat
		)
		if main then
			bit(
				model,
				"Cap",
				Vector3.new(w * 0.62, w * 0.26, w * 0.62),
				CFrame.new(at + Vector3.new(0, h + w * 0.2, 0)) * CFrame.Angles(0, yaw, 0),
				Kit.shade(capColor, 0.06),
				capMat
			)
		end
		return brim
	end
	local h = rng:range(0.8, 1.4)
	local w = rng:range(1.0, 1.5)
	local cap = shroom(Vector3.zero, h, w, true)
	local a = rng:range(0, math.pi * 2)
	shroom(Vector3.new(math.cos(a) * w * 0.7, 0, math.sin(a) * w * 0.7), h * 0.55, w * 0.55, false)
	if glowing then
		local l = Instance.new("PointLight")
		l.Color = capColor
		l.Range = 8
		l.Brightness = 0.8
		l.Shadows = false
		l.Parent = cap
	else
		for i = 1, 2 do
			local sa = rng:range(0, math.pi * 2)
			bit(
				model,
				"Spot",
				Vector3.new(w * 0.14, 0.06, w * 0.14),
				CFrame.new(math.cos(sa) * w * 0.22 * i, h + w * 0.14 + (2 - i) * w * 0.2, math.sin(sa) * w * 0.22 * i),
				WHITE
			)
		end
	end
	return model
end

-- Pinecones under the pines: two to four little faceted cones.
function PropArt.Pinecones(seed: number): Model
	local model = Kit.model("Pinecones")
	local rng = Kit.rng(seed)
	for _ = 1, rng:int(2, 4) do
		local a, r = rng:range(0, math.pi * 2), rng:range(0, 1.2)
		local at = Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)
		local lie = CFrame.new(at) * CFrame.Angles(0, rng:range(0, 6), 0) * CFrame.Angles(math.pi / 2 - 0.15, 0, 0)
		bit(
			model,
			"Pinecone",
			Vector3.new(0.38, 0.62, 0.38),
			lie * CFrame.Angles(0, math.pi / 4, 0),
			Kit.vary(hex("#7A5232"), rng, 0.05)
		)
		bit(
			model,
			"Pinecone",
			Vector3.new(0.26, 0.3, 0.26),
			lie * CFrame.new(0, 0.42, 0),
			Kit.vary(hex("#8C6240"), rng, 0.05)
		)
	end
	return model
end

-- A snow drift about `size` studs across: soft mounds.
function PropArt.SnowPile(seed: number, size: number): Model
	local model = Kit.model("SnowPile")
	local rng = Kit.rng(seed)
	local s = size
	local SNOW = { hex("#F4F8FC"), hex("#E8F0F7"), hex("#FFFFFF") }
	local yaw = rng:range(0, math.pi * 2)
	for i = 1, 3 do
		local a = yaw + i * 2.1
		local r = if i == 1 then 0 else s * 0.32
		local w = if i == 1 then s else s * rng:range(0.5, 0.65)
		local m = Kit.ellipsoid(
			model,
			"Snow",
			Vector3.new(w, w * 0.42, w * 0.78),
			CFrame.new(math.cos(a) * r, w * 0.08, math.sin(a) * r) * CFrame.Angles(0, a, 0),
			Kit.vary(SNOW[i], rng, 0.02),
			Enum.Material.Snow
		)
		Kit.decor(m, s >= 4)
	end
	return model
end

---------------------------------------------------------------------------
-- Wood on the forest floor
---------------------------------------------------------------------------

-- Decor logs and stumps have lain here for years, so they must never pass
-- for a fresh one you can chop or haul (NAT-13): bark weathered 35% toward
-- grey-olive, rotten or mossy wood where a fresh cut would be pale, sunk
-- 0.2 studs into the ground, mushrooms.
local WEATHERED = hex("#6E6A58")
local WEATHERING = 0.35
local SINK = 0.2
local ROT = hex("#5B4A36") -- soft, dark old wood
local HOLLOW = hex("#33281D")

local function weathered(bark: Color3): Color3
	return bark:Lerp(WEATHERED, WEATHERING)
end

-- A small brown mushroom: a pale stalk and a squat cap. Two parts.
local function toadstool(model: Model, at: Vector3, h: number, w: number, color: Color3)
	bit(model, "Mushroom", Vector3.new(w * 0.3, h, w * 0.3), CFrame.new(at + Vector3.new(0, h / 2, 0)), hex("#EDE4CC"))
	bit(
		model,
		"Mushroom",
		Vector3.new(w, w * 0.3, w),
		CFrame.new(at + Vector3.new(0, h + w * 0.08, 0)) * CFrame.Angles(0, math.pi / 4, 0),
		color
	)
end

-- A long-fallen log, sunk into the ground: weathered bark, one end rotted
-- hollow, the other broken, moss along the top, a branch stub, a bracket
-- fungus and a mushroom.
function PropArt.FallenLog(seed: number, barkColor: Color3?, moss: Color3?): Model
	local model = Kit.model("FallenLog")
	local rng = Kit.rng(seed)
	local bark = weathered(barkColor or BARK)
	local L = rng:range(6, 10)
	local d = rng:range(1.4, 2.2)
	local yaw = rng:range(0, math.pi * 2)
	local base = CFrame.new(0, d / 2 - 0.15 - SINK, 0)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(0, 0, rng:range(-0.04, 0.04))
	Kit.decor(Kit.cylinder(model, "Log", L, d, base, Kit.vary(bark, rng, 0.03), Enum.Material.Wood))
	-- The old cut end: soft, dark rotten wood round a hollow core.
	local endCF = base * CFrame.new(L / 2 + 0.02, 0, 0)
	Kit.decor(Kit.cylinder(model, "LogEnd", 0.06, d * 0.86, endCF, ROT, Enum.Material.Wood), false)
	Kit.decor(
		Kit.cylinder(model, "LogHollow", 0.08, d * 0.5, endCF * CFrame.new(0.01, 0, 0), HOLLOW, Enum.Material.Wood),
		false
	)
	-- The broken end: a few splinters.
	wedgeBit(
		model,
		"Splinter",
		Vector3.new(d * 0.3, d * 0.5, d * 0.5),
		base * CFrame.new(-L / 2 - d * 0.1, d * 0.12, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Kit.shade(bark, 0.1),
		Enum.Material.Wood
	)
	-- Moss along the top.
	for i = 1, 2 do
		local x = (i - 1.5) * L * 0.4 + rng:range(-0.5, 0.5)
		Kit.decor(
			Kit.ellipsoid(
				model,
				"Moss",
				Vector3.new(L * rng:range(0.22, 0.32), d * 0.22, d * 0.7),
				base * CFrame.new(x, d * 0.42, rng:range(-0.1, 0.1)),
				Kit.vary(moss or MOSS, rng, 0.05),
				Enum.Material.Grass
			),
			false
		)
	end
	-- A branch stub and a bracket fungus.
	local stubAt = (base * CFrame.new(rng:range(-0.2, 0.2) * L, 0, d * 0.4)).Position
	rod(
		model,
		"Stub",
		stubAt,
		stubAt + base:VectorToWorldSpace(Vector3.new(0.3, 0.9, 1.0)),
		d * 0.3,
		bark,
		Enum.Material.Wood
	)
	disc(
		model,
		"Fungus",
		(base * CFrame.new(rng:range(-0.3, 0.1) * L, 0, -d * 0.5)).Position,
		0.12,
		d * 0.5,
		hex("#E9C892"),
		Enum.Material.SmoothPlastic
	)
	-- A mushroom on the ground against the log's flank.
	local mAt = (base * CFrame.new(rng:range(0.05, 0.35) * L, 0, -d * 0.62)).Position
	toadstool(model, Vector3.new(mAt.X, 0, mAt.Z), rng:range(0.35, 0.5), rng:range(0.4, 0.55), hex("#A8683E"))
	return model
end

-- An old stump, sunk into the ground: weathered bark, a rotten top half
-- grown over with moss, jagged splinters, roots and a little mushroom.
function PropArt.Stump(seed: number, barkColor: Color3?, moss: Color3?): Model
	local model = Kit.model("OldStump")
	local rng = Kit.rng(seed)
	local bark = weathered(barkColor or BARK)
	local d = rng:range(1.6, 2.4)
	local h = rng:range(0.9, 1.5)
	local top = h - SINK
	Kit.decor(
		Kit.cylinder(
			model,
			"StumpBody",
			h + 0.2,
			d,
			CFrame.new(0, h / 2 - 0.1 - SINK, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Kit.vary(bark, rng, 0.03),
			Enum.Material.Wood
		)
	)
	disc(model, "StumpTop", Vector3.new(0, top + 0.02, 0), 0.06, d * 0.84, ROT, Enum.Material.Wood)
	-- Splinters standing up round the rim where it broke.
	local yaw = rng:range(0, math.pi * 2)
	for i = 1, 2 do
		local a = yaw + i * 2.4
		local sh = rng:range(0.5, 0.9)
		wedgeBit(
			model,
			"Splinter",
			Vector3.new(0.18, sh, d * 0.3),
			CFrame.new(math.cos(a) * d * 0.36, top + sh / 2, math.sin(a) * d * 0.36)
				* CFrame.Angles(0, -a + math.pi / 2, 0),
			Kit.shade(bark, 0.08),
			Enum.Material.Wood
		)
	end
	-- Moss over most of the top.
	Kit.decor(
		Kit.ellipsoid(
			model,
			"Moss",
			Vector3.new(d * 0.72, 0.22, d * 0.6),
			CFrame.new(math.cos(yaw + 1) * d * 0.1, top + 0.05, math.sin(yaw + 1) * d * 0.1),
			Kit.vary(moss or MOSS, rng, 0.05),
			Enum.Material.Grass
		),
		false
	)
	-- Roots.
	for i = 1, 3 do
		local a = yaw + 0.6 + i * 2.1 + rng:range(-0.2, 0.2)
		local rh, rl = h * rng:range(0.45, 0.7), d * rng:range(0.45, 0.6)
		wedgeBit(
			model,
			"Root",
			Vector3.new(d * 0.24, rh, rl),
			CFrame.Angles(0, -a - math.pi / 2, 0) * CFrame.new(0, rh / 2 - 0.08 - SINK, -(d / 2 + rl / 2 - 0.15)),
			Kit.shade(bark, -0.06),
			Enum.Material.Wood
		)
	end
	-- A little mushroom at its foot.
	local ma = yaw + 3.6
	local mAt = Vector3.new(math.cos(ma) * d * 0.62, 0, math.sin(ma) * d * 0.62)
	bit(model, "Mushroom", Vector3.new(0.12, 0.4, 0.12), CFrame.new(mAt + Vector3.new(0, 0.2, 0)), hex("#EDE4CC"))
	bit(
		model,
		"Mushroom",
		Vector3.new(0.4, 0.12, 0.4),
		CFrame.new(mAt + Vector3.new(0, 0.42, 0)) * CFrame.Angles(0, math.pi / 4, 0),
		hex("#C4483A")
	)
	return model
end

-- A dead branch lying on the ground, with two twigs.
function PropArt.DeadBranch(seed: number): Model
	local model = Kit.model("DeadBranch")
	local rng = Kit.rng(seed)
	local color = Kit.vary(hex("#7A6A58"), rng, 0.05)
	local L = rng:range(3, 5)
	local d = rng:range(0.3, 0.45)
	local yaw = rng:range(0, math.pi * 2)
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local a = -dir * (L / 2) + Vector3.new(0, d * 0.4, 0)
	local b = dir * (L / 2) + Vector3.new(0, d * 0.35, 0)
	rod(model, "Branch", a, b, d, color, Enum.Material.Wood)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for i, t in ipairs({ 0.25, 0.6 }) do
		local from = a:Lerp(b, t)
		local s = if i == 1 then 1 else -1
		local to = from
			+ dir * rng:range(0.5, 0.9)
			+ side * s * rng:range(0.6, 1.1)
			+ Vector3.new(0, rng:range(0.05, 0.4), 0)
		rod(model, "Twig", from, to, d * 0.45, color, Enum.Material.Wood)
	end
	return model
end

---------------------------------------------------------------------------
-- Biome tints and scattering
---------------------------------------------------------------------------

export type Tints = {
	grass: Color3, -- tufts, ferns
	leaves: { Color3 }, -- bushes
	flowers: { Color3 },
	stone: { Color3 },
	bark: Color3, -- fallen logs, stumps
	moss: Color3,
}

local TINTS: { [string]: Tints } = {
	starter = {
		grass = hex("#7CB850"),
		leaves = { hex("#5DA24A"), hex("#6FB352"), hex("#86BF57") },
		flowers = { hex("#FFD84D"), hex("#FFFFFF"), hex("#F28AB0"), hex("#A98BE0") },
		stone = STONE,
		bark = hex("#6E5038"),
		moss = hex("#7FA650"),
	},
	hills = {
		grass = hex("#5E9A44"),
		leaves = { hex("#4C8F3E"), hex("#5A9A45"), hex("#3F7F38") },
		flowers = { hex("#E5A33B"), hex("#FFFFFF"), hex("#D86A3A"), hex("#F2C14E") },
		stone = STONE,
		bark = hex("#5E4632"),
		moss = hex("#6E9A48"),
	},
	snow = {
		grass = hex("#9DB8A8"),
		leaves = { hex("#6F9A8C"), hex("#7FA898"), hex("#5E8A7C") },
		flowers = { hex("#BFE6FF"), hex("#FFFFFF"), hex("#D8E8FF") },
		stone = { hex("#E8EEF5"), hex("#C8D0DA"), hex("#969AA0") },
		bark = hex("#5A4A40"),
		moss = hex("#9CB8A0"),
	},
	volcano = {
		grass = hex("#7A6A44"),
		leaves = { hex("#4A4A36"), hex("#5B5238"), hex("#3E3A2C") },
		flowers = { hex("#FF8A2A"), hex("#FFB050"), hex("#FF6A2A") },
		stone = { hex("#3A3330"), hex("#2E2826"), hex("#4A403B") },
		bark = hex("#3A2E28"),
		moss = hex("#6B6A3A"),
	},
	grove = {
		grass = hex("#5A4A7A"),
		leaves = { hex("#5A3F8C"), hex("#6A4FA0"), hex("#47336F") },
		flowers = { hex("#55F2E0"), hex("#B58CFF"), hex("#E0C8FF") },
		stone = { hex("#4A4258"), hex("#3C3648"), hex("#5A5068") },
		bark = hex("#3E3248"),
		moss = hex("#4FA89A"),
	},
	sky = {
		grass = hex("#A8CC62"),
		leaves = { hex("#CFE08E"), hex("#BCD27A"), hex("#A9C76C") },
		flowers = { hex("#FFF3B0"), hex("#FFFFFF"), hex("#CDB8F0"), hex("#A8D8F0") },
		stone = { hex("#DCCCB0"), hex("#C2B19C"), hex("#E5D7BE") },
		bark = hex("#C8B48E"),
		moss = hex("#B8D47A"),
	},
	island = {
		grass = hex("#8CC45A"),
		leaves = { hex("#3FAE5A"), hex("#52BF66"), hex("#33964B") },
		flowers = { hex("#FF6F91"), hex("#FFD84D"), hex("#FFFFFF") },
		stone = { hex("#E2CD96"), hex("#CDB98A"), hex("#EBDDB0") },
		bark = hex("#7A5A36"),
		moss = hex("#7FB04C"),
	},
}
TINTS.beach = TINTS.island

-- The palette props use in a biome (BiomeData ids, plus "beach"); the
-- Starter Forest's for anything unknown.
function PropArt.Tints(biomeId: string?): Tints
	return TINTS[biomeId or ""] or TINTS.starter
end

-- What grows where, and how often: (prop, weight). "shore" and "water"
-- are the riverbanks and the water itself, in any biome.
local MIX: { [string]: { { name: string, weight: number } } } = {
	starter = {
		{ name = "GrassTuft", weight = 30 },
		{ name = "Flowers", weight = 18 },
		{ name = "Fern", weight = 8 },
		{ name = "Bush", weight = 10 },
		{ name = "Pebbles", weight = 7 },
		{ name = "Mushroom", weight = 4 },
		{ name = "BerryBush", weight = 3 },
		{ name = "DeadBranch", weight = 4 },
		{ name = "FallenLog", weight = 2 },
		{ name = "Stump", weight = 2 },
		{ name = "Rock", weight = 3 },
	},
	hills = {
		{ name = "GrassTuft", weight = 28 },
		{ name = "Fern", weight = 14 },
		{ name = "Flowers", weight = 10 },
		{ name = "Pinecones", weight = 10 },
		{ name = "Bush", weight = 8 },
		{ name = "Pebbles", weight = 8 },
		{ name = "BerryBush", weight = 3 },
		{ name = "DeadBranch", weight = 5 },
		{ name = "FallenLog", weight = 3 },
		{ name = "Stump", weight = 3 },
		{ name = "Rock", weight = 5 },
	},
	snow = {
		{ name = "SnowPile", weight = 30 },
		{ name = "Pinecones", weight = 10 },
		{ name = "Pebbles", weight = 10 },
		{ name = "GrassTuft", weight = 8 },
		{ name = "Crystal", weight = 4 },
		{ name = "DeadBranch", weight = 5 },
		{ name = "Rock", weight = 6 },
	},
	volcano = {
		{ name = "LavaRock", weight = 20 },
		{ name = "Pebbles", weight = 20 },
		{ name = "DeadBranch", weight = 8 },
		{ name = "GrassTuft", weight = 6 },
		{ name = "Crystal", weight = 3 },
		{ name = "Rock", weight = 8 },
	},
	grove = {
		{ name = "Mushroom", weight = 20 },
		{ name = "Fern", weight = 16 },
		{ name = "GrassTuft", weight = 14 },
		{ name = "Flowers", weight = 8 },
		{ name = "Stump", weight = 5 },
		{ name = "FallenLog", weight = 4 },
		{ name = "Pebbles", weight = 6 },
	},
	sky = {
		{ name = "GrassTuft", weight = 26 },
		{ name = "Flowers", weight = 24 },
		{ name = "Bush", weight = 8 },
		{ name = "Pebbles", weight = 6 },
		{ name = "Crystal", weight = 3 },
	},
	island = {
		{ name = "GrassTuft", weight = 22 },
		{ name = "Fern", weight = 14 },
		{ name = "Flowers", weight = 12 },
		{ name = "Bush", weight = 8 },
		{ name = "Pebbles", weight = 10 },
	},
	shore = {
		{ name = "Reeds", weight = 30 },
		{ name = "Cattails", weight = 18 },
		{ name = "GrassTuft", weight = 18 },
		{ name = "Pebbles", weight = 14 },
	},
	water = {
		{ name = "LilyPad", weight = 1 },
	},
}
MIX.beach = MIX.island

-- Builds one prop by name, tinted for the biome (nil for an unknown name).
function PropArt.Build(name: string, seed: number, biomeId: string?): Model?
	local t = PropArt.Tints(biomeId)
	local rng = Kit.rng(seed + 77)
	local glow = biomeId == "grove"
	local crystal = if biomeId == "snow"
		then hex("#BFEFFF")
		elseif biomeId == "volcano" then hex("#FF8A2A")
		else hex("#9FE6FF")
	if name == "Rock" then
		return PropArt.Rock(rng:range(1.6, 3.2), seed, t.stone)
	elseif name == "Bush" then
		return PropArt.Bush(rng:range(2, 4), seed, t.leaves)
	elseif name == "Flowers" then
		return PropArt.Flowers(seed, t.flowers)
	elseif name == "Mushroom" then
		return PropArt.Mushroom(seed, glow)
	elseif name == "Crystal" then
		return PropArt.Crystal(seed, crystal, rng:range(1.2, 2.2))
	elseif name == "GrassTuft" then
		return PropArt.GrassTuft(seed, t.grass)
	elseif name == "Fern" then
		return PropArt.Fern(seed, t.leaves[1])
	elseif name == "Reeds" then
		return PropArt.Reeds(seed)
	elseif name == "LilyPad" then
		return PropArt.LilyPad(seed)
	elseif name == "FallenLog" then
		return PropArt.FallenLog(seed, t.bark, t.moss)
	elseif name == "Pebbles" then
		return PropArt.Pebbles(seed, t.stone)
	elseif name == "SnowPile" then
		return PropArt.SnowPile(seed, rng:range(2.5, 5))
	elseif name == "LavaRock" then
		return PropArt.LavaRock(seed, rng:range(1.5, 3))
	elseif name == "Pinecones" then
		return PropArt.Pinecones(seed)
	elseif name == "BerryBush" then
		return PropArt.BerryBush(seed, t.leaves)
	elseif name == "Stump" then
		return PropArt.Stump(seed, t.bark, t.moss)
	elseif name == "Cattails" then
		return PropArt.Cattails(seed)
	elseif name == "DeadBranch" then
		return PropArt.DeadBranch(seed)
	end
	return nil
end

-- The prop names a biome's mix can pick (for tests and tools).
function PropArt.Mix(biomeId: string): { { name: string, weight: number } }
	return MIX[biomeId] or MIX.starter
end

-- One scattered prop for a spot: picked by weight from the biome's mix
-- (or the "shore"/"water" mix when `spot` says so), tinted for the biome,
-- the same on every client for the same seed. Everything it returns is
-- decoration, Rock included (a client-only rock mustn't stop a truck).
function PropArt.Scatter(biomeId: string?, seed: number, spot: string?): Model
	local mix = PropArt.Mix(spot or biomeId or "starter")
	local total = 0
	for _, entry in ipairs(mix) do
		total += entry.weight
	end
	local roll = Kit.rng(seed):next() * total
	local name = mix[#mix].name
	for _, entry in ipairs(mix) do
		roll -= entry.weight
		if roll < 0 then
			name = entry.name
			break
		end
	end
	local model = PropArt.Build(name, seed, biomeId) or PropArt.GrassTuft(seed, PropArt.Tints(biomeId).grass)
	Kit.decorAll(model)
	return model
end

---------------------------------------------------------------------------
-- Open-country set pieces (WLD-01): WorldPlan.Scenery places them out
-- between the biomes and along the haul roads, 25 parts at most each, on
-- the ground at the origin, front to -Z. What looks solid collides and
-- can be clicked (COL-01: an outcrop's stones, a ruined cabin's footing,
-- floor, wall logs, corner posts, chimney and fallen roof, a windmill's
-- base and tower, a lookout tower's legs, deck, rails and ladder); the
-- trim (sails, braces, rungs, boards, the ridge beam) is looks only, and
-- parts under a stud cast no shadow.
---------------------------------------------------------------------------

local SET_PLANK = { hex("#A4693E"), hex("#B07548"), hex("#985F37") }
local SET_OLD = { hex("#7E6A55"), hex("#8A7660"), hex("#6F5D4A") } -- weathered boards
local SET_TIMBER = hex("#5B3920")
local SET_STONE = { hex("#9C968D"), hex("#ABA498"), hex("#8E887F") }
local SET_SHINGLE = { hex("#8B4831"), hex("#9A5338") }
local SAILCLOTH = hex("#F2E7CF")

-- A looks-only box from a to b (`w` x `h` across), e.g. a beam or a leg.
local function plank(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(model, name, Vector3.new(w, h, (b - a).Magnitude), lookAt((a + b) / 2, b), color, material)
	Kit.decor(p, math.max(w, h, (b - a).Magnitude) >= 1)
	return p
end

-- A looks-only block (casts a shadow unless it's under a stud).
local function block(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(model, name, size, cf, color, material)
	Kit.decor(p, math.max(size.X, size.Y, size.Z) >= 1)
	return p
end

-- Makes a set piece's parts named in `names` solid again (Kit.solid): its
-- big bodies, built by the looks-only helpers above.
local function solidParts(model: Model, names: { [string]: boolean })
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and names[d.Name] then
			Kit.solid(d)
		end
	end
end

-- An outcrop: three or four big rocks (6 to 14 studs) huddled together.
-- Like a lone boulder, each rock's three stones collide; the pebbles and
-- moss are looks only.
-- (brown, PropArt.BrownTones, unless `colors` says otherwise).
function PropArt.Outcrop(seed: number, colors: { Color3 }?): Model
	local model = Kit.model("Outcrop")
	local rng = Kit.rng(seed)
	local count = rng:int(3, 4)
	local start = rng:range(0, math.pi * 2)
	for i = 1, count do
		local size = if i == 1 then rng:range(10, 14) else rng:range(6, 10)
		local a = start + i * 2.1 + rng:range(-0.3, 0.3)
		local r = if i == 1 then 0 else rng:range(5.5, 8)
		local rock = PropArt.Rock(size, seed * 7 + i, colors or PropArt.BrownTones[seed % 2 + 1])
		Kit.placeAt(rock, CFrame.new(math.cos(a) * r, 0, math.sin(a) * r))
		rock.Parent = model
	end
	Kit.decorAll(model, { Rock = true })
	return model
end

-- A ruined log cabin (about 12 x 10): a stone footing, broken log walls,
-- a stone chimney still standing, the roof fallen in. The footing, the
-- floor, the wall logs, the corner posts, the chimney and the fallen roof
-- collide.
local CABIN_SOLID: { [string]: boolean } =
	{ Footing = true, Floor = true, WallLog = true, CornerPost = true, Chimney = true, FallenRoof = true }
function PropArt.RuinedCabin(seed: number): Model
	local model = Kit.model("RuinedCabin")
	local rng = Kit.rng(seed)
	local W, D = 12, 10
	local logD = 1.1
	-- The footing: four low stone courses round the floor.
	for _, s in ipairs({ -1, 1 }) do
		block(
			model,
			"Footing",
			Vector3.new(W + 1, 0.9, 1.1),
			CFrame.new(0, 0.35, s * D / 2),
			rng:pick(SET_STONE),
			Enum.Material.Slate
		)
		block(
			model,
			"Footing",
			Vector3.new(1.1, 0.9, D - 1),
			CFrame.new(s * W / 2, 0.35, 0),
			rng:pick(SET_STONE),
			Enum.Material.Slate
		)
	end
	block(model, "Floor", Vector3.new(W - 1, 0.2, D - 1), CFrame.new(0, 0.6, 0), SET_OLD[3], Enum.Material.WoodPlanks)
	local function log(name: string, a: Vector3, b: Vector3)
		rod(model, name, a, b, logD * rng:range(0.92, 1.05), Kit.vary(rng:pick(SET_OLD), rng, 0.05), Enum.Material.Wood)
	end
	-- The back wall (+Z): three courses, each shorter than the last.
	for row = 0, 2 do
		local y = 1.3 + row * logD
		local cut = row * rng:range(1.5, 2.5)
		log("WallLog", Vector3.new(-W / 2 - 0.4, y, D / 2), Vector3.new(W / 2 + 0.4 - cut, y, D / 2))
	end
	-- The left wall: two courses; the right: one, broken off.
	for row = 0, 1 do
		local y = 1.3 + row * logD
		log("WallLog", Vector3.new(-W / 2, y, -D / 2 - 0.4), Vector3.new(-W / 2, y, D / 2 + 0.4 - row * 3))
	end
	log("WallLog", Vector3.new(W / 2, 1.3, D / 2 + 0.4), Vector3.new(W / 2, 1.3, -D / 2 + 3))
	-- Corner posts at the front, one snapped short.
	for i, x in ipairs({ -W / 2, W / 2 }) do
		local h = if i == 1 then 4.6 else 2.2
		block(
			model,
			"CornerPost",
			Vector3.new(0.8, h, 0.8),
			CFrame.new(x, 0.8 + h / 2, -D / 2),
			SET_TIMBER,
			Enum.Material.Wood
		)
	end
	-- The chimney at the back right, still standing.
	block(
		model,
		"Chimney",
		Vector3.new(2.6, 5, 2.4),
		CFrame.new(W / 2 - 1.8, 2.6, D / 2 + 0.6),
		SET_STONE[1],
		Enum.Material.Slate
	)
	block(
		model,
		"Chimney",
		Vector3.new(1.9, 2.4, 1.8),
		CFrame.new(W / 2 - 1.8, 6.3, D / 2 + 0.6),
		SET_STONE[2],
		Enum.Material.Slate
	)
	-- The roof fallen in: one slope leans from the back wall to the floor,
	-- the ridge beam lies across it, and loose boards lie about.
	local roof = block(
		model,
		"Roof",
		Vector3.new(W - 3, 0.35, 7),
		CFrame.new(-0.8, 2.4, 1.6) * CFrame.Angles(math.rad(-28), rng:range(-0.08, 0.08), rng:range(-0.05, 0.05)),
		rng:pick(SET_SHINGLE),
		Enum.Material.WoodPlanks
	)
	roof.Name = "FallenRoof"
	plank(
		model,
		"Ridge",
		Vector3.new(-W / 2 + 1, 0.9, -1.5),
		Vector3.new(W / 2 - 1.5, 3.4, 3.2),
		0.7,
		0.7,
		SET_TIMBER,
		Enum.Material.Wood
	)
	for i = 1, 3 do
		local a = rng:range(0, math.pi * 2)
		local at =
			Vector3.new(rng:range(-W / 2 + 1, W / 2 - 1), 0.12, -D / 2 - rng:range(1, 3) * (if i == 3 then -1 else 1))
		block(
			model,
			"Board",
			Vector3.new(0.9, 0.2, rng:range(3, 5)),
			CFrame.new(at) * CFrame.Angles(0, a, 0),
			Kit.vary(rng:pick(SET_OLD), rng, 0.05),
			Enum.Material.WoodPlanks
		)
	end
	solidParts(model, CABIN_SOLID)
	return model
end

-- An old windmill (about 15 tall, 7 across): a stone base, a boarded
-- tower, a little roof, and four sails on a hub facing -Z. The base and
-- the tower collide; the rest is looks only.
function PropArt.Windmill(seed: number): Model
	local model = Kit.model("Windmill")
	local rng = Kit.rng(seed)
	local base = Kit.post(model, "Base", Vector3.new(0, -0.5, 0), 4.5, 8, SET_STONE[1], Enum.Material.Slate)
	base.Name = "MillBase"
	Kit.post(model, "Tower", Vector3.new(0, 4, 0), 6.5, 6.6, rng:pick(SET_PLANK), Enum.Material.WoodPlanks)
	Kit.post(model, "Tower", Vector3.new(0, 10.5, 0), 3, 5.6, rng:pick(SET_PLANK), Enum.Material.WoodPlanks)
	block(model, "Door", Vector3.new(2, 3.2, 0.3), CFrame.new(0, 1.6 + 0.1, -3.95), SET_TIMBER, Enum.Material.Wood)
	block(model, "Window", Vector3.new(1.2, 1.4, 0.3), CFrame.new(0, 7.2, -3.35), SET_TIMBER, Enum.Material.Wood)
	-- The cap: a ridge roof over the top.
	for _, s in ipairs({ -1, 1 }) do
		block(
			model,
			"MillRoof",
			Vector3.new(4.2, 0.4, 7),
			CFrame.new(s * 1.55, 14.4, 0) * CFrame.Angles(0, 0, -s * math.rad(38)),
			SET_SHINGLE[1],
			Enum.Material.WoodPlanks
		)
	end
	block(model, "Gable", Vector3.new(5.6, 1.2, 5.6), CFrame.new(0, 13.6, 0), SET_PLANK[3], Enum.Material.WoodPlanks)
	-- The hub and the sails, turned a little so each mill looks different.
	local hub = CFrame.new(0, 12.4, -3.9)
	Kit.decor(
		Kit.cylinder(model, "Hub", 1.4, 1.3, hub * CFrame.Angles(0, math.pi / 2, 0), SET_TIMBER, Enum.Material.Wood)
	)
	local turn = rng:range(0, math.pi / 2)
	for i = 0, 3 do
		local a = turn + i * math.pi / 2
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local side = Vector3.new(-dir.Y, dir.X, 0)
		local at = hub.Position + Vector3.new(0, 0, -0.5)
		plank(model, "Spar", at, at + dir * 9, 0.4, 0.4, SET_TIMBER, Enum.Material.Wood)
		local mid = at + dir * 5.6 + side * 0.9 + Vector3.new(0, 0, 0.05)
		block(
			model,
			"Sail",
			Vector3.new(6.4, 1.6, 0.15),
			CFrame.fromMatrix(mid, dir, side, Vector3.zAxis),
			SAILCLOTH,
			Enum.Material.Fabric
		)
	end
	return model
end

-- A timber lookout tower (about 17 tall): four splayed legs, cross braces,
-- a railed deck, a little roof and a ladder up the front (-Z). The legs,
-- the deck, its rails and the ladder's sides collide.
local LOOKOUT_SOLID: { [string]: boolean } = { Leg = true, Deck = true, Rail = true, Ladder = true }
function PropArt.LookoutTower(seed: number): Model
	local model = Kit.model("LookoutTower")
	local rng = Kit.rng(seed)
	local DECK = 11
	local timber = Kit.vary(SET_TIMBER, rng, 0.04)
	local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
	local function foot(c: { number }): Vector3
		return Vector3.new(c[1] * 3, -0.4, c[2] * 3)
	end
	local function top(c: { number }, y: number): Vector3
		return Vector3.new(c[1] * 2.2, y, c[2] * 2.2)
	end
	for i, c in ipairs(corners) do
		plank(model, "Leg", foot(c), top(c, DECK + 4.2), 0.6, 0.6, timber, Enum.Material.Wood)
		-- One brace per side, from this foot up to the next corner.
		local n = corners[i % 4 + 1]
		plank(
			model,
			"Brace",
			foot(c) + Vector3.new(0, 1, 0),
			top(n, DECK - 1),
			0.35,
			0.35,
			SET_PLANK[3],
			Enum.Material.Wood
		)
		-- The deck's rail on this side.
		plank(model, "Rail", top(c, DECK + 1.4), top(n, DECK + 1.4), 0.3, 0.3, SET_PLANK[2], Enum.Material.Wood)
	end
	block(model, "Deck", Vector3.new(5.6, 0.4, 5.6), CFrame.new(0, DECK, 0), SET_PLANK[1], Enum.Material.WoodPlanks)
	block(
		model,
		"LookoutRoof",
		Vector3.new(6.4, 0.4, 6.4),
		CFrame.new(0, DECK + 4.4, 0),
		SET_SHINGLE[1],
		Enum.Material.WoodPlanks
	)
	block(
		model,
		"LookoutRoof",
		Vector3.new(4, 0.9, 4),
		CFrame.new(0, DECK + 5, 0) * CFrame.Angles(0, math.pi / 4, 0),
		SET_SHINGLE[2],
		Enum.Material.WoodPlanks
	)
	-- The ladder up the front.
	for _, x in ipairs({ -0.55, 0.55 }) do
		plank(
			model,
			"Ladder",
			Vector3.new(x, -0.2, -3.6),
			Vector3.new(x, DECK, -2.9),
			0.25,
			0.25,
			SET_TIMBER,
			Enum.Material.Wood
		)
	end
	for _, y in ipairs({ 3, 6.5 }) do
		local z = -3.6 + 0.7 * (y / DECK)
		block(model, "Rung", Vector3.new(1.3, 0.2, 0.2), CFrame.new(0, y, z), SET_TIMBER, Enum.Material.Wood)
	end
	solidParts(model, LOOKOUT_SOLID)
	return model
end

-- A set piece by name ("Outcrop", "RuinedCabin", "Windmill",
-- "LookoutTower"), or nil for a name it doesn't know.
function PropArt.SetPiece(name: string, seed: number): Model?
	if name == "Outcrop" then
		return PropArt.Outcrop(seed)
	elseif name == "RuinedCabin" then
		return PropArt.RuinedCabin(seed)
	elseif name == "Windmill" then
		return PropArt.Windmill(seed)
	elseif name == "LookoutTower" then
		return PropArt.LookoutTower(seed)
	end
	return nil
end

---------------------------------------------------------------------------
-- Ground cover (AmbientLife's second layer, EnvironmentData.DecorCoverSpots)
---------------------------------------------------------------------------
-- Small clusters that texture the ground between the bigger props: each
-- spreads over a few studs, so one pooled model covers more ground than a
-- single tuft. Decoration only, no shadows, 16 parts or fewer.

-- 2-3 of `colors`, chosen by the seed (a drift reads as a few kinds, not
-- confetti).
local function someOf(rng: Rng, colors: { Color3 }): { Color3 }
	local out: { Color3 } = {}
	local start = rng:int(1, #colors)
	for i = 0, math.min(#colors, rng:int(2, 3)) - 1 do
		table.insert(out, colors[(start + i - 1) % #colors + 1])
	end
	return out
end

-- One grass blade, leaning out from `at`.
local function blade(model: Model, rng: Rng, at: Vector3, h: number, a: number, color: Color3)
	wedgeBit(
		model,
		"Blade",
		Vector3.new(0.12, h, rng:range(0.3, 0.5)),
		CFrame.new(at + Vector3.new(0, h / 2 - 0.05, 0))
			* CFrame.Angles(0, a, 0)
			* CFrame.Angles(rng:range(-0.4, -0.05), 0, rng:range(-0.2, 0.2)),
		Kit.vary(color, rng, 0.07),
		Enum.Material.SmoothPlastic
	)
end

-- A patch of meadow about 6 studs across: three or four tufts of grass,
-- a couple of tiny flowers and maybe a pebble.
function PropArt.GroundCover(seed: number, grass: Color3, petals: { Color3 }): Model
	local model = Kit.model("GroundCover")
	local rng = Kit.rng(seed)
	local colors = someOf(rng, petals)
	for i = 1, rng:int(3, 4) do
		local a, r = i * 1.9 + rng:range(-0.5, 0.5), rng:range(0.6, 2.8)
		local at = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local shade = Kit.shade(grass, rng:range(-0.06, 0.05))
		for j = 1, 2 do
			blade(model, rng, at, rng:range(0.6, 1.2), a + j * 2.4, shade)
		end
	end
	for i = 1, rng:int(1, 2) do
		local a, r = rng:range(0, math.pi * 2), rng:range(0.4, 2.4)
		flower(model, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:range(0.35, 0.6), colors[i], nil, a)
	end
	if rng:next() < 0.5 then
		local a, r = rng:range(0, math.pi * 2), rng:range(0.8, 2.6)
		local p = rng:range(0.3, 0.55)
		bit(
			model,
			"Pebble",
			Vector3.new(p, p * 0.45, p * 0.8),
			CFrame.new(math.cos(a) * r, p * 0.15, math.sin(a) * r) * CFrame.Angles(0, a, 0.2),
			Kit.vary(STONE[rng:int(1, #STONE)], rng, 0.05),
			Enum.Material.Slate
		)
	end
	return model
end

-- A drift of five to seven small flowers in two or three of `colors`,
-- with a blade or two of grass among them.
function PropArt.Wildflowers(seed: number, colors: { Color3 }): Model
	local model = Kit.model("Wildflowers")
	local rng = Kit.rng(seed)
	local picked = someOf(rng, colors)
	local yaw = rng:range(0, math.pi * 2)
	for i = 1, rng:int(5, 7) do
		local a, r = yaw + i * 2.4, rng:range(0.2, 1.9)
		flower(
			model,
			Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
			rng:range(0.45, 0.85),
			picked[(i - 1) % #picked + 1],
			nil,
			a
		)
	end
	blade(model, rng, Vector3.new(math.cos(yaw) * 0.6, 0, math.sin(yaw) * 0.6), rng:range(0.6, 0.9), yaw, LEAF)
	return model
end

-- A low, spreading shrub, knee high: three or four squashed leaf clumps.
function PropArt.LowBush(seed: number, colors: { Color3 }): Model
	local model = Kit.model("LowBush")
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	local w = rng:range(1.3, 1.8)
	for i = 1, rng:int(3, 4) do
		local a = yaw + i * 2.2 + rng:range(-0.3, 0.3)
		local r = if i == 1 then 0 else w * rng:range(0.45, 0.65)
		local e = w * (if i == 1 then 1 else rng:range(0.65, 0.8))
		bit(
			model,
			"Bush",
			Vector3.new(e, e * 0.5, e),
			CFrame.new(math.cos(a) * r, e * 0.22, math.sin(a) * r)
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(0, math.pi / 4, 0),
			Kit.vary(colors[(i - 1) % #colors + 1], rng, 0.05),
			Enum.Material.SmoothPlastic
		)
	end
	return model
end

-- Two or three young ferns together, the kind that crowds a tree's feet.
function PropArt.FernClump(seed: number, color: Color3): Model
	local model = Kit.model("FernClump")
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	for f = 1, rng:int(2, 3) do
		local fa = yaw + f * 2.1
		local fr = if f == 1 then 0 else rng:range(1, 1.6)
		local at = Vector3.new(math.cos(fa) * fr, 0.05, math.sin(fa) * fr)
		local c = Kit.vary(color, rng, 0.06)
		for i = 1, 4 do
			local a = fa + i / 4 * math.pi * 2 + rng:range(-0.25, 0.25)
			local L = rng:range(1, 1.6)
			wedgeBit(
				model,
				"Frond",
				Vector3.new(0.07, rng:range(0.4, 0.55), L),
				CFrame.new(at)
					* CFrame.Angles(0, a, 0)
					* CFrame.Angles(math.rad(rng:range(28, 45)), 0, 0)
					* CFrame.new(0, 0, -L / 2)
					* CFrame.Angles(0, 0, math.pi / 2),
				c,
				Enum.Material.SmoothPlastic
			)
		end
	end
	return model
end

-- A little ring of three to five brown or red toadstools.
function PropArt.MushroomCluster(seed: number): Model
	local model = Kit.model("MushroomCluster")
	local rng = Kit.rng(seed)
	local caps = { hex("#9A6A44"), hex("#B98A58"), hex("#C4483A"), hex("#7E5A3C") }
	local color = caps[seed % #caps + 1]
	local yaw = rng:range(0, math.pi * 2)
	for i = 1, rng:int(3, 5) do
		local a, r = yaw + i * 1.7, if i == 1 then 0 else rng:range(0.35, 0.9)
		local w = rng:range(0.3, 0.6)
		toadstool(
			model,
			Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
			w * rng:range(0.8, 1.3),
			w,
			Kit.vary(color, rng, 0.05)
		)
	end
	return model
end

---------------------------------------------------------------------------
-- The forest's filler trees (phase 10, FOR-02)
---------------------------------------------------------------------------
-- The trees that make the forest ring a forest: every client builds them
-- round its camera (StarterPlayerScripts/ForestFiller, from
-- WorldPlan.FillerCellTrees), so they're looks only and cheap. Lumber
-- Tycoon 2's blocky style: a trunk and two to four tilted blocks, 3 to 5
-- parts, every one SmoothPlastic, decoration (no collisions, clicks or
-- touches: a collider only one client has would fight the trucks) and
-- shadowless. A step darker than the choppable woods' palettes, so a
-- tree you can chop stands out at the forest's edge. Never named Leaves,
-- Frond, Tier or Facet (WindSway and CanopyFade's names), never tagged.
-- On the ground at the origin, about as tall as a choppable tree at size 1.

PropArt.FillerKinds = { "broad", "birch", "maple", "conifer", "snowpine", "dead" }
PropArt.FillerVariants = 6 -- looks per kind (ForestFiller builds each once)

local FILLER_PALETTES: { [string]: { crown: { Color3 }, trunk: Color3, snow: Color3? } } = {
	broad = { crown = { hex("#4E8E3E"), hex("#5A9A44"), hex("#437F37"), hex("#6AA54C") }, trunk = hex("#5E4130") },
	birch = { crown = { hex("#94BC52"), hex("#A6C65E"), hex("#83AE48"), hex("#B4CC66") }, trunk = hex("#DCD6C8") },
	maple = { crown = { hex("#C27A28"), hex("#B45A26"), hex("#CC8E34"), hex("#A84422") }, trunk = hex("#5A3E2C") },
	conifer = { crown = { hex("#2A6A37"), hex("#337A40"), hex("#245E31"), hex("#3C8550") }, trunk = hex("#5A4030") },
	snowpine = {
		crown = { hex("#2A6A37"), hex("#245E31"), hex("#2F7040") },
		trunk = hex("#5A4030"),
		snow = hex("#E3ECF1"),
	},
	dead = { crown = { hex("#6F6258"), hex("#5E534A") }, trunk = hex("#6F6258") },
}

-- The colour of a far stand-in block over a stretch of `kind` (darker than
-- the trees: far canopy reads as shade).
local FILLER_FAR: { [string]: Color3 } = {
	broad = hex("#3E7434"),
	birch = hex("#6E9442"),
	maple = hex("#99582A"),
	conifer = hex("#24572F"),
	snowpine = hex("#3A5E4A"),
	dead = hex("#5A5048"),
}
function PropArt.FillerFarColor(kind: string): Color3
	return FILLER_FAR[kind] or FILLER_FAR.broad
end

local function fillerBlock(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3)
	Kit.decor(Kit.part(model, name, size, cf, color, Enum.Material.SmoothPlastic), false)
end

-- One filler tree of `kind` (PropArt.FillerKinds; anything else is a
-- broad one), look `variant` (1..FillerVariants).
function PropArt.FillerTree(kind: string, variant: number): Model
	local pal = FILLER_PALETTES[kind] or FILLER_PALETTES.broad
	local model = Kit.model("FillerTree")
	local seed = 9001 + variant * 131
	for i = 1, #kind do
		seed += string.byte(kind, i) * i * 17
	end
	local rng = Kit.rng(seed)
	local yaw = rng:range(0, math.pi * 2)
	local function crown(): Color3
		return Kit.vary(pal.crown[rng:int(1, #pal.crown)], rng, 0.05)
	end
	-- A trunk `w` across, from 1.5 under the ground to `h` over it.
	local function trunk(w: number, h: number)
		fillerBlock(
			model,
			"FillerTrunk",
			Vector3.new(w, h + 1.5, w),
			CFrame.new(0, (h - 1.5) / 2, 0) * CFrame.Angles(0, yaw, 0),
			Kit.vary(pal.trunk, rng, 0.04)
		)
	end
	-- A tilted crown block.
	local function crownBlock(size: Vector3, at: Vector3, tilt: number, color: Color3)
		fillerBlock(
			model,
			"FillerCrown",
			size,
			CFrame.new(at)
				* CFrame.Angles(0, yaw + rng:range(-0.8, 0.8), 0)
				* CFrame.Angles(rng:range(-tilt, tilt), 0, rng:range(-tilt, tilt)),
			color
		)
	end
	if kind == "conifer" or kind == "snowpine" then
		-- Stacked square tiers, each turned 45 degrees on the one below.
		local h = rng:range(7, 9)
		trunk(rng:range(1, 1.25), h)
		local w = rng:range(9, 10.5)
		local y = h - 1
		for t = 1, 4 do
			local tw = w * (1 - (t - 1) * 0.24)
			local th = if t == 4 then 4 else 3.6
			local snowy = kind == "snowpine" and t >= 3
			local color = if snowy and pal.snow then Kit.vary(pal.snow, rng, 0.03) else crown()
			fillerBlock(
				model,
				"FillerCrown",
				Vector3.new(tw, th, tw),
				CFrame.new(0, y + th / 2, 0) * CFrame.Angles(0, yaw + t * math.pi / 4, 0),
				color
			)
			y += th * 0.92
		end
	elseif kind == "dead" then
		-- A bare grey trunk and two broken limbs.
		local h = rng:range(9, 12)
		trunk(rng:range(1, 1.3), h)
		for i = 1, 2 do
			local a = yaw + i * math.pi * 0.9
			local len = rng:range(3.5, 5)
			local at = Vector3.new(math.cos(a) * len * 0.3, h * (0.55 + i * 0.15), math.sin(a) * len * 0.3)
			fillerBlock(
				model,
				"FillerBranch",
				Vector3.new(0.5, len, 0.5),
				CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(rng:range(40, 55))),
				Kit.vary(pal.crown[i], rng, 0.04)
			)
		end
	elseif kind == "birch" then
		-- A slim pale trunk and a tall crown of two blocks.
		local h = rng:range(10, 12)
		trunk(rng:range(0.8, 1), h)
		crownBlock(Vector3.new(7, 8, 7) * rng:range(0.9, 1.1), Vector3.new(0, h + 1, 0), 0.25, crown())
		crownBlock(Vector3.new(5, 5.5, 5) * rng:range(0.9, 1.1), Vector3.new(0.6, h + 5.5, -0.4), 0.3, crown())
	else
		-- Broadleaf (and maple, in autumn colours): a stout trunk under a
		-- big crown, a top block and a side block.
		local h = rng:range(8, 10)
		trunk(rng:range(1.3, 1.6), h)
		local w = rng:range(10, 12)
		crownBlock(Vector3.new(w, w * 0.65, w), Vector3.new(0, h + 2.5, 0), 0.22, crown())
		local a = rng:range(0, math.pi * 2)
		crownBlock(
			Vector3.new(w * 0.62, w * 0.5, w * 0.62),
			Vector3.new(math.cos(a) * 1.4, h + 6.2, math.sin(a) * 1.4),
			0.3,
			crown()
		)
		a += rng:range(2, 4)
		crownBlock(
			Vector3.new(w * 0.5, w * 0.4, w * 0.5),
			Vector3.new(math.cos(a) * w * 0.42, h + 2, math.sin(a) * w * 0.42),
			0.3,
			crown()
		)
	end
	return model
end

return PropArt
