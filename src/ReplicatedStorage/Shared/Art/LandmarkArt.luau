--!strict
-- LandmarkArt: the open country's landmarks, a little toward Lumber
-- Tycoon 2's look (phase 10, STY-03 and STY-04): brown boulders for the
-- clusters scattered over the grass, a sturdy timber footbridge over the
-- river, plank docks with a moored rowboat, and a lighthouse on the coast.
-- Pure (see Kit), so tools/preview draws exactly what MapBuilder builds
-- (scenes "landmarks", "meadow" and "roads").
--
-- Every builder returns a Model built around the origin: ground at y = 0,
-- the front facing -Z. What players stand on or bump into collides (decks,
-- posts, rails, the lighthouse's tower, rocks); the rest is Kit.decor, and
-- parts under a stud cast no shadow. Named parts other code finds: the
-- docks' "LanternGlow", the lighthouse's "LampGlow" and "WindowGlass"
-- (LightingController lights them at dusk). Part budgets
-- (tests/LandmarkArt.spec.luau): Footbridge 110, Dock 60, Rowboat 14,
-- Lighthouse 75.

local FerryLogic = require(script.Parent.Parent.FerryLogic)
local Kit = require(script.Parent.Kit)
local PropArt = require(script.Parent.PropArt)
local TerrainGen = require(script.Parent.Parent.World.TerrainGen)
local TownMeshes = require(script.Parent.TownMeshes)
local TownModels = require(script.Parent.TownModels)
local WorldLayout = require(script.Parent.Parent.World.WorldLayout)

local LandmarkArt = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local MAT = Enum.Material

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- BuildingArt's palette (its single construction style), for the timber.
local PLANK = { hex("#A4693E"), hex("#B07548"), hex("#985F37"), hex("#BC804D") }
local TIMBER = hex("#5B3920")
local TIMBER_LIGHT = hex("#7A4C2B")
local STONE = { hex("#9C968D"), hex("#ABA498"), hex("#89837B") }
local TRIM = hex("#F2E7CF")
local BRICK = hex("#A8553D")
local IRON = hex("#3B3634")
local DOOR = hex("#6E4426")
local ROOF = { hex("#8A4532"), hex("#7E402C"), hex("#9A5338") }
local GLASS = hex("#9CCBE0")
local LAMP = Color3.fromRGB(255, 214, 130) -- the lamp's glow (LightingController keeps a Neon part's own colour)
local BOAT_PAINT = { hex("#3F6F80"), hex("#A8553D"), hex("#4E7A4C") }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- CFrame.lookAt from its axes (Lune's CFrame.lookAt disagrees with
-- Roblox's, so the preview needs this; same result in the game).
local function lookAt(pos: Vector3, target: Vector3): CFrame
	local look = (target - pos).Unit
	local up = if math.abs(look.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

-- A block: solid (collides) or looks only (small ones cast no shadow).
local function box(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material,
	solid: boolean
): Part
	local p = Kit.part(model, name, size, cf, color, mat)
	if not solid then
		Kit.decor(p, if math.max(size.X, size.Y, size.Z) < 1 then false else nil)
	end
	return p
end

-- A block from a to b, `w` x `h` across.
local function beam(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	mat: Enum.Material,
	solid: boolean
): Part
	return box(model, name, V3(w, h, (b - a).Magnitude), lookAt((a + b) / 2, b), color, mat, solid)
end

-- An upright square post from y0 to y1 at (x, z).
local function post(
	model: Model,
	name: string,
	x: number,
	z: number,
	y0: number,
	y1: number,
	w: number,
	color: Color3,
	solid: boolean
): Part
	return box(model, name, V3(w, y1 - y0, w), CF(x, (y0 + y1) / 2, z), color, MAT.Wood, solid)
end

-- An upright cylinder from y0 to y1, `d` across, on the model's axis.
local function drum(
	model: Model,
	name: string,
	y0: number,
	y1: number,
	d: number,
	color: Color3,
	mat: Enum.Material,
	solid: boolean
): Part
	local p = Kit.cylinder(model, name, y1 - y0, d, CF(0, (y0 + y1) / 2, 0) * ANG(0, 0, PI / 2), color, mat)
	if not solid then
		Kit.decor(p)
	end
	return p
end

---------------------------------------------------------------------------
-- Brown boulders (STY-03)
---------------------------------------------------------------------------

-- Brown rock: the open country's boulders are brown, not grey. Two tones, so a field of
-- clusters isn't one flat colour: a warm brown and a greyer umber (shared
-- with the lone boulders and the outcrops: PropArt.BrownTones).
LandmarkArt.ROCK_TONES = PropArt.BrownTones
local MOSS = Color3.fromRGB(104, 146, 66)

-- One brown boulder `size` studs across (PropArt.Rock, as the lone
-- boulders: its three "Rock" blocks collide, its pebbles and moss are
-- looks only), in tone 1 or 2, with a mossy cap when `mossy`.
function LandmarkArt.BrownRock(size: number, seed: number, tone: number, mossy: boolean): Model
	local tones = LandmarkArt.ROCK_TONES
	local palette = tones[math.clamp(math.floor(tone), 1, #tones)]
	return PropArt.Rock(size, seed, palette, if mossy then MOSS else nil)
end

---------------------------------------------------------------------------
-- The timber footbridge (STY-04a)
---------------------------------------------------------------------------

LandmarkArt.BRIDGE_DECK = 0.35 -- the deck's top over the ground at each end
LandmarkArt.BRIDGE_PLANK = 0.4 -- how thick its planks are
LandmarkArt.BRIDGE_RAIL = 3.0 -- the top rail over the deck
LandmarkArt.BRIDGE_UNDER = 1.2 -- the deck's planks and stringers reach this far under its top

-- The deck's top over end a's ground at `t` (0 at end a, 1 at end b): a
-- gentle arch `rise` high over the straight line from end to end (end b's
-- ground is `drop` over end a's).
function LandmarkArt.DeckTop(t: number, drop: number, rise: number): number
	return LandmarkArt.BRIDGE_DECK + drop * t + rise * math.sin(PI * t)
end

-- A sturdy timber footbridge `span` studs from end a (the origin, on its
-- bank) to end b (at -Z `span`, `drop` higher), `width` wide inside its
-- rails, arched `rise`: planks board by board across two stringers, square
-- posts at #beds stations from end to end (each reaching down to its bed:
-- `beds[i]` is the ground or river bed under station i, over end a's
-- ground), a top and a mid rail outside the deck on both sides, and a
-- truss of braces rising toward the middle. The planks, posts and rails
-- collide; stringers, braces, cross beams, caps and footings are looks.
function LandmarkArt.Footbridge(span: number, drop: number, width: number, rise: number, beds: { number }): Model
	local model = Kit.model("Footbridge")
	local rng = Kit.rng(math.floor(span * 97 + drop * 13) + 11)
	local deck = function(t: number): number
		return LandmarkArt.DeckTop(t, drop, rise)
	end
	local thick = LandmarkArt.BRIDGE_PLANK
	-- The planks across (the walking surface).
	local n = math.max(4, math.floor(span / 1.25))
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local a = V3(0, deck(t0) - thick / 2, -span * t0)
		local b = V3(0, deck(t1) - thick / 2, -span * t1)
		local cf = lookAt((a + b) / 2, b) * ANG(0, rng:range(-0.025, 0.025), 0)
		box(
			model,
			"Plank",
			V3(width + rng:range(-0.15, 0.15), thick, (b - a).Magnitude - 0.12),
			cf,
			Kit.vary(rng:pick(PLANK), rng, 0.05),
			MAT.WoodPlanks,
			true
		)
	end
	local stations = math.max(2, #beds)
	local postX = width / 2 + 0.35
	local function along(s: number): number
		return (s - 1) / (stations - 1)
	end
	for s = 1, stations do
		local t = along(s)
		local z = -span * t
		local top = deck(t) + LandmarkArt.BRIDGE_RAIL + 0.4
		for _, side in ipairs({ -1, 1 }) do
			local x = side * postX
			post(model, "Post", x, z, (beds[s] or 0) - 0.6, top, 0.7, TIMBER, true)
			box(model, "PostCap", V3(0.9, 0.3, 0.9), CF(x, top + 0.15, z), TIMBER_LIGHT, MAT.Wood, false)
			if s == 1 or s == stations then
				box(model, "Footing", V3(1.5, 0.6, 1.5), CF(x, (beds[s] or 0) + 0.1, z), STONE[1], MAT.Slate, false)
			end
		end
		if s > 1 and s < stations then -- a cross beam under the deck at each bent
			box(model, "CrossBeam", V3(width + 1.6, 0.6, 0.6), CF(0, deck(t) - thick - 0.5, z), TIMBER, MAT.Wood, false)
		end
	end
	-- Each bay: stringers under the deck, rails outside it, a brace.
	for s = 1, stations - 1 do
		local t0, t1 = along(s), along(s + 1)
		local z0, z1 = -span * t0, -span * t1
		for _, side in ipairs({ -1, 1 }) do
			local sx = side * (width / 2 - 0.9)
			beam(
				model,
				"Stringer",
				V3(sx, deck(t0) - thick - 0.35, z0),
				V3(sx, deck(t1) - thick - 0.35, z1),
				0.5,
				0.7,
				TIMBER,
				MAT.Wood,
				false
			)
			local x = side * postX
			for _, rail in ipairs({ { LandmarkArt.BRIDGE_RAIL, 0.45 }, { 1.5, 0.3 } }) do
				beam(
					model,
					"Rail",
					V3(x, deck(t0) + rail[1], z0),
					V3(x, deck(t1) + rail[1], z1),
					0.35,
					rail[2],
					TIMBER_LIGHT,
					MAT.Wood,
					true
				)
			end
			-- The truss: braces rising toward the middle of the span.
			local low, high = if t0 < 0.5 then t0 else t1, if t0 < 0.5 then t1 else t0
			beam(
				model,
				"Brace",
				V3(x, deck(low) + 0.15, -span * low),
				V3(x, deck(high) + LandmarkArt.BRIDGE_RAIL - 0.2, -span * high),
				0.3,
				0.3,
				TIMBER,
				MAT.Wood,
				false
			)
		end
	end
	TownMeshes.Dress(model, "Footbridge", {
		pivot = CF(0, 0, -span / 2),
		scale = V3(1, 1, span / TownModels.FootSpan),
	})
	return model
end

---------------------------------------------------------------------------
-- Plank docks and a rowboat (STY-04b)
---------------------------------------------------------------------------

LandmarkArt.DOCK_PLANK = 0.3 -- how thick its planks are

-- A plank dock `length` studs out over the water from its land end (the
-- origin, on the bank) along -Z, `width` wide, its deck's top `deck` over
-- the land end's ground: planks across, two stringers, square posts down
-- to the bed at #beds stations (`beds[i]` over the land end's ground, the
-- first at the land end, the last at the far end), stubby bollards at the
-- far end, a ladder down into the water there (the water's surface is
-- `water` over the land end's ground) and a lantern on a tall post at its
-- far corner (its glass is "LanternGlow": lit at dusk). Planks, posts and
-- the lantern post collide; the rest is looks.
function LandmarkArt.Dock(length: number, width: number, deck: number, water: number, beds: { number }): Model
	local model = Kit.model("Dock")
	local rng = Kit.rng(math.floor(length * 31 + width * 7) + 3)
	local thick = LandmarkArt.DOCK_PLANK
	local n = math.max(4, math.floor(length / 1.15))
	local step = length / n
	for i = 0, n - 1 do
		box(
			model,
			"Plank",
			V3(width + rng:range(-0.2, 0.2), thick, step - 0.12),
			CF(rng:range(-0.1, 0.1), deck - thick / 2, -step * (i + 0.5)) * ANG(0, rng:range(-0.03, 0.03), 0),
			Kit.vary(rng:pick(PLANK), rng, 0.05),
			MAT.WoodPlanks,
			true
		)
	end
	for _, side in ipairs({ -1, 1 }) do
		box(
			model,
			"Stringer",
			V3(0.5, 0.6, length),
			CF(side * (width / 2 - 0.7), deck - thick - 0.3, -length / 2),
			TIMBER,
			MAT.Wood,
			false
		)
	end
	local stations = math.max(2, #beds)
	local postX = width / 2 - 0.1
	for s = 1, stations do
		local z = -0.6 - (length - 1.2) * (s - 1) / (stations - 1)
		local last = s == stations
		for _, side in ipairs({ -1, 1 }) do
			local x = side * postX
			local top = deck + (if last then 1.1 else 0.45)
			if last and side > 0 then
				top = deck + 5.4 -- the lantern post
			end
			post(model, "Post", x, z, (beds[s] or 0) - 0.6, top, 0.75, TIMBER, true)
		end
		box(model, "CrossBeam", V3(width + 0.6, 0.5, 0.5), CF(0, deck - thick - 0.45, z), TIMBER, MAT.Wood, false)
	end
	-- The lantern: an iron arm off the tall post, a lantern hanging over the deck.
	local endZ = -0.6 - (length - 1.2)
	box(model, "LanternArm", V3(1.9, 0.25, 0.25), CF(postX - 0.85, deck + 5.0, endZ), IRON, MAT.Metal, false)
	Kit.lantern(model, CF(postX - 1.6, deck + 4.1, endZ), 1)
	-- A ladder down the far end into the water.
	local ladderZ = -length - 0.25
	local foot = water - 1.6
	for _, x in ipairs({ -0.7, 0.7 }) do
		box(
			model,
			"LadderRail",
			V3(0.2, deck - foot, 0.2),
			CF(x, (deck + foot) / 2, ladderZ),
			TIMBER_LIGHT,
			MAT.Wood,
			false
		)
	end
	for k = 1, 3 do
		local y = deck - k * (deck - foot) / 4
		box(model, "LadderRung", V3(1.4, 0.15, 0.15), CF(0, y, ladderZ), TIMBER_LIGHT, MAT.Wood, false)
	end
	-- A mooring cleat by the boat's side.
	box(model, "Cleat", V3(0.3, 0.3, 1.1), CF(-postX + 0.5, deck + 0.15, endZ + 4), IRON, MAT.Metal, false)
	-- The mesh is 20 long. A longer dock (the coast is 26) stretches on Z.
	TownMeshes.Dress(model, "Dock", {
		pivot = CF(0, 0, -length / 2),
		scale = V3(1, 1, length / TownModels.DockLength),
	})
	return model
end

-- A little rowboat, looks only, floating with its waterline at the origin,
-- its bow toward -Z: a painted hull (a floor, two flared sides, a pointed
-- bow and a transom), two thwarts and a pair of oars.
function LandmarkArt.Rowboat(seed: number): Model
	local model = Kit.model("Rowboat")
	local rng = Kit.rng(seed)
	local paint = rng:pick(BOAT_PAINT)
	local wood = Kit.vary(PLANK[2], rng, 0.04)
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3)
		Kit.decor(Kit.part(model, name, size, cf, color, MAT.Wood))
	end
	piece("Hull", V3(2.0, 0.3, 5.4), CF(0, -0.45, 0.2), paint)
	for _, side in ipairs({ -1, 1 }) do
		piece("Hull", V3(0.25, 1.0, 5.6), CF(side * 1.15, -0.05, 0.2) * ANG(0, 0, side * 0.22), paint)
	end
	local bow = Kit.wedge(model, "Bow", V3(2.5, 1.1, 1.8), CF(0, -0.05, -3.3) * ANG(0, 0, PI), paint, MAT.Wood)
	Kit.decor(bow)
	piece("Transom", V3(2.6, 0.95, 0.25), CF(0, -0.05, 3.0), paint)
	piece("Gunwale", V3(2.9, 0.15, 0.3), CF(0, 0.5, 3.0), wood)
	for _, z in ipairs({ -1.2, 1.2 }) do
		piece("Thwart", V3(2.3, 0.18, 0.6), CF(0, 0.12, z), wood)
	end
	for _, side in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.rod(model, "Oar", V3(side * 0.6, 0.35, 2.2), V3(side * 0.3, 0.35, -2.4), 0.16, wood, MAT.Wood),
			false
		)
	end
	TownMeshes.Dress(model, "Rowboat")
	return model
end

---------------------------------------------------------------------------
-- The lighthouse (STY-04c)
---------------------------------------------------------------------------

LandmarkArt.LIGHTHOUSE_LAMP = 49.4 -- the lamp's middle over the ground
LandmarkArt.LIGHTHOUSE_TOP = 55 -- its finial
LandmarkArt.LIGHTHOUSE_RADIUS = 12.5 -- everything, its rocks too, stands this near its middle

-- A banded lighthouse: a stone plinth, a tapering tower of cream and red
-- bands with a door (-Z) and three warm windows ("WindowGlass"), an iron
-- gallery with a rail, a glass lamp room round the lamp ("LampGlow",
-- Neon, its PointLight reaching 60: LightingController lights it at dusk)
-- under a faceted red cap, and three brown rocks at its foot. The plinth,
-- tower, gallery and rocks collide.
function LandmarkArt.Lighthouse(): Model
	local model = Kit.model("Lighthouse")
	local rng = Kit.rng(4747)
	drum(model, "Plinth", -0.8, 2, 11, STONE[1], MAT.Slate, true)
	-- Four bands, tapering, cream and red in turn.
	local widths = { 8.2, 7.5, 6.8, 6.1 }
	for i, width in ipairs(widths) do
		local y0 = 2 + (i - 1) * 11
		drum(model, "Tower", y0, y0 + 11, width, if i % 2 == 1 then TRIM else BRICK, MAT.Plaster, true)
	end
	-- The door, and the windows up the tower (front, back, side).
	box(model, "Door", V3(2.2, 3.6, 0.4), CF(0, 3.8, -4.0), DOOR, MAT.Wood, false)
	local windows = { { 18, 3.75, 0 }, { 29, 3.4, PI }, { 40, 3.05, PI / 2 } }
	for _, w in ipairs(windows) do
		local turn = CF(0, w[1], 0) * ANG(0, w[3], 0)
		box(model, "WindowFrame", V3(1.5, 2.1, 0.2), turn * CF(0, 0, -w[2] + 0.02), TIMBER, MAT.Wood, false)
		box(
			model,
			"WindowGlass",
			V3(1.1, 1.7, 0.2),
			turn * CF(0, 0, -w[2] - 0.06),
			Color3.fromRGB(150, 190, 210),
			MAT.Glass,
			false
		)
	end
	-- The gallery and its rail.
	drum(model, "Gallery", 46, 46.6, 8.6, IRON, MAT.Metal, true)
	local railR = 4.0
	for k = 0, 7 do
		local a0, a1 = k * PI / 4, (k + 1) * PI / 4
		local p0 = V3(math.cos(a0) * railR, 0, math.sin(a0) * railR)
		local p1 = V3(math.cos(a1) * railR, 0, math.sin(a1) * railR)
		box(model, "RailPost", V3(0.2, 1.4, 0.2), CF(p0 + V3(0, 47.3, 0)), IRON, MAT.Metal, false)
		beam(model, "Rail", p0 + V3(0, 47.95, 0), p1 + V3(0, 47.95, 0), 0.18, 0.18, IRON, MAT.Metal, false)
	end
	-- The lamp room.
	drum(model, "LampBase", 46.6, 47.6, 4.8, TRIM, MAT.Plaster, false)
	local glass = drum(model, "LampRoom", 47.6, 51.2, 4.4, GLASS, MAT.Glass, false)
	glass.Transparency = 0.45
	glass.CastShadow = false
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		box(
			model,
			"Mullion",
			V3(0.25, 3.6, 0.25),
			CF(math.cos(a) * 2.2, 49.4, math.sin(a) * 2.2),
			IRON,
			MAT.Metal,
			false
		)
	end
	local lamp = Kit.ball(model, "LampGlow", 2.2, CF(0, LandmarkArt.LIGHTHOUSE_LAMP, 0), LAMP, MAT.Neon)
	Kit.decor(lamp, false)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 60
	light.Brightness = 3
	light.Shadows = false
	light.Parent = lamp
	-- The cap.
	drum(model, "Eave", 51.2, 51.5, 5.8, ROOF[1], MAT.SmoothPlastic, false)
	Kit.cone(model, CF(0, 51.5, 0), 2.9, 2.8, 6, function(i: number): Color3
		return ROOF[(i - 1) % #ROOF + 1]
	end, MAT.SmoothPlastic, 0.3)
	Kit.decor(Kit.ball(model, "Finial", 0.7, CF(0, 54.6, 0), IRON, MAT.Metal), false)
	-- Brown rocks at its foot (STY-03's), clear of the door.
	for i, a in ipairs({ 0.35, 2.4, 3.5 }) do
		local size = ({ 5, 6, 4 })[i]
		local rock = LandmarkArt.BrownRock(size, 900 + i * 37, 1 + i % 2, i == 2)
		local r = 5.5 + size * 0.25
		Kit.placeAt(rock, CF(math.cos(a) * r, -(0.5 + 0.1 * size), math.sin(a) * r) * ANG(0, rng:range(0, 6), 0))
		rock.Parent = model
	end
	TownMeshes.Dress(model, "Lighthouse")
	return model
end

---------------------------------------------------------------------------
-- W2: toll, gorge, ferry, cave, deep water, heat
---------------------------------------------------------------------------

local TOLL_TIMBER = hex("#6B4423")
local TOLL_PLANK = hex("#A4693E")
local TOLL_IRON = hex("#2A2726")
local TOLL_BOOTH = hex("#7A4C2B")
local DOCK_PLANK = hex("#8C6239")
local CAVE_ROCK = hex("#2A2628")
local CAVE_DARK = hex("#141216")
local LANTERN = hex("#FFC45C")
local DEEP = hex("#071018")
local HEAT = hex("#FF6A1A")
local BOULDER = hex("#6B6560")
local PATH = hex("#C4A36A")

local ARM_THICK = 0.6
local ARM_HIGH = 2.2 -- above the deck top
local RAIL_THICK = 1
local POST = 1.2
local DOCK_W = 16
local DOCK_L = 10
local DOCK_T = 1
local CAVE_W = 36 -- every fog axis stays under FogAtomicMax
local CAVE_H = 14
local CAVE_D = 28
local FOG_W = 24
local FOG_H = 10
local FOG_D = 18
local WATER_T = 6
local HEAT_D = 30
local BOULDER_S = 8
local PATH_W = 6
local PATH_T = 0.4
local LIP_THICK = 4
local WATER_INSET = 12 -- deep-water bands sit inside the rim
local PATH_PLANKS = 4
local BOOTH_W = 10
local BOOTH_D = 8
local BOOTH_H = 7
local WALL_T = 1
local FLOOR_T = 1
local ROOF_T = 1
local ROOF_OVER = 2
local COUNTER_W = 6
local COUNTER_H = 3
local COUNTER_Z = -2

local function solid(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return box(model, name, size, cf, color, mat, true)
end

local function ghost(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local part = box(model, name, size, cf, color, mat, false)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Deck along Z, rails, and a barrier arm across the full width. The arm
-- does not push. Ground (y = 0) is the bank.
function LandmarkArt.TollBridge(): Model
	local model = Kit.model("TollBridge")
	local thick = WorldLayout.BridgeDeckThick
	local width = WorldLayout.BridgeWidth
	local length = WorldLayout.BridgeLength
	local railH = WorldLayout.BridgeRailHeight
	solid(model, "Deck", V3(width, thick, length), CF(0, thick / 2, 0), TOLL_PLANK, MAT.WoodPlanks)
	local railY = thick + railH / 2
	local railX = width / 2 - RAIL_THICK / 2
	solid(model, "Rail", V3(RAIL_THICK, railH, length), CF(railX, railY, 0), TOLL_TIMBER, MAT.Wood)
	solid(model, "Rail", V3(RAIL_THICK, railH, length), CF(-railX, railY, 0), TOLL_TIMBER, MAT.Wood)
	local armZ = WorldLayout.TollLineZ - WorldLayout.BridgeCenterZ
	local arm =
		ghost(model, "BarrierArm", V3(width, ARM_THICK, ARM_THICK), CF(0, thick + ARM_HIGH, armZ), TOLL_IRON, MAT.Metal)
	arm:SetAttribute("TollGate", true)
	-- Two piers, so the deck reads as a bridge over the cut.
	for _, z in ipairs({ -length / 4, length / 4 }) do
		solid(
			model,
			"Pier",
			V3(POST, WorldLayout.GorgeDepth, POST),
			CF(0, -WorldLayout.GorgeDepth / 2, z),
			STONE[1],
			MAT.Slate
		)
	end
	local deck = model:FindFirstChild("Deck") :: BasePart?
	if deck then
		model.PrimaryPart = deck
	end
	return model
end

-- A hut. Its origin is the bank under the floor, front facing -Z.
function LandmarkArt.TollBooth(): Model
	local model = Kit.model("TollBooth")
	solid(model, "Floor", V3(BOOTH_W, FLOOR_T, BOOTH_D), CF(0, FLOOR_T / 2, 0), TOLL_PLANK, MAT.WoodPlanks)
	local wallY = FLOOR_T + BOOTH_H / 2
	solid(model, "Wall", V3(BOOTH_W, BOOTH_H, WALL_T), CF(0, wallY, BOOTH_D / 2 - WALL_T / 2), TOLL_BOOTH, MAT.Wood)
	solid(model, "Wall", V3(WALL_T, BOOTH_H, BOOTH_D), CF(-(BOOTH_W / 2 - WALL_T / 2), wallY, 0), TOLL_BOOTH, MAT.Wood)
	solid(model, "Wall", V3(WALL_T, BOOTH_H, BOOTH_D), CF(BOOTH_W / 2 - WALL_T / 2, wallY, 0), TOLL_BOOTH, MAT.Wood)
	solid(
		model,
		"Roof",
		V3(BOOTH_W + ROOF_OVER, ROOF_T, BOOTH_D + ROOF_OVER),
		CF(0, FLOOR_T + BOOTH_H + ROOF_T / 2, 0),
		ROOF[1],
		MAT.Wood
	)
	solid(
		model,
		"Counter",
		V3(COUNTER_W, COUNTER_H, WALL_T),
		CF(0, FLOOR_T + COUNTER_H / 2, COUNTER_Z),
		TOLL_TIMBER,
		MAT.Wood
	)
	local floor = model:FindFirstChild("Floor") :: BasePart?
	if floor then
		model.PrimaryPart = floor
	end
	return model
end

function LandmarkArt.FerryDock(): Model
	local model = Kit.model("FerryDock")
	solid(model, "Deck", V3(DOCK_W, DOCK_T, DOCK_L), CF(0, DOCK_T / 2, 0), DOCK_PLANK, MAT.WoodPlanks)
	local postH = 4
	for _, side in ipairs({ -1, 1 }) do
		for _, along in ipairs({ -1, 1 }) do
			solid(
				model,
				"Post",
				V3(POST, postH, POST),
				CF(side * (DOCK_W / 2 - 1), -postH / 2, along * (DOCK_L / 2 - 1)),
				TOLL_TIMBER,
				MAT.Wood
			)
		end
	end
	local deck = model:FindFirstChild("Deck") :: BasePart?
	if deck then
		model.PrimaryPart = deck
	end
	return model
end

-- Cap'n Moss's ferry (FerryService builds it at the mainland berth and
-- moves it). Its origin is the Deck's centre, the bow toward -Z. The Deck
-- is FerryLogic.DeckWidth x FerryLogic.DeckLength and the primary part;
-- riders stand on it. Budget: 80 parts (tests/LandmarkArt.spec.luau).
function LandmarkArt.FerryBoat(): Model
	local model = Kit.model("FerryBoat")
	local w, l = FerryLogic.DeckWidth, FerryLogic.DeckLength
	local deck = solid(model, "Deck", V3(w, 1, l), CF(0, 0, 0), DOCK_PLANK, MAT.WoodPlanks)
	local hull = solid(model, "Hull", V3(w - 1, 2, l - 1), CF(0, -1.5, 0), BOAT_PAINT[1], MAT.Wood)
	hull.CanCollide = false
	for _, side in ipairs({ -1, 1 }) do
		solid(model, "Rail", V3(0.6, 2, l - 6), CF(side * (w / 2 - 0.3), 1.5, 2), TOLL_TIMBER, MAT.Wood)
		solid(model, "Rail", V3(0.6, 2, 3), CF(side * (w / 2 - 0.3), 1.5, -l / 2 + 1.5), TOLL_TIMBER, MAT.Wood)
	end
	solid(model, "Stern", V3(w, 2, 0.6), CF(0, 1.5, l / 2 - 0.3), TOLL_TIMBER, MAT.Wood)
	for _, side in ipairs({ -1, 1 }) do
		solid(model, "CabinPost", V3(0.6, 5, 0.6), CF(side * (w / 2 - 1.5), 3.5, l / 2 - 3), TOLL_TIMBER, MAT.Wood)
	end
	solid(model, "CabinRoof", V3(w - 1, 0.6, 5), CF(0, 6.3, l / 2 - 3), ROOF[1], MAT.Wood)
	solid(model, "Mast", V3(0.8, 9, 0.8), CF(0, 5, -l / 2 + 4), TOLL_TIMBER, MAT.Wood)
	local lamp = ghost(model, "Lantern", V3(1.2, 1.2, 1.2), CF(0, 9.8, -l / 2 + 4), LANTERN, MAT.Neon)
	lamp.Name = "LanternGlow"
	model.PrimaryPart = deck
	return model
end

-- One part. MapBuilder tags it Breakable.
function LandmarkArt.CrackedBoulder(): Model
	local model = Kit.model("BreakableBoulder")
	local rock =
		solid(model, "Boulder", V3(BOULDER_S, BOULDER_S, BOULDER_S), CF(0, BOULDER_S / 2, 0), BOULDER, MAT.Slate)
	model.PrimaryPart = rock
	return model
end

-- Dark room. The fog part's longest axis stays under FogAtomicMax so the
-- cave model can stay Atomic.
function LandmarkArt.SecretCave(): Model
	local model = Kit.model("SecretCave")
	solid(model, "Floor", V3(CAVE_W, 2, CAVE_D), CF(0, 1, 0), CAVE_ROCK, MAT.Slate)
	solid(model, "Ceiling", V3(CAVE_W, 2, CAVE_D), CF(0, CAVE_H, 0), CAVE_DARK, MAT.Slate)
	solid(model, "Wall", V3(2, CAVE_H, CAVE_D), CF(-CAVE_W / 2, CAVE_H / 2, 0), CAVE_ROCK, MAT.Slate)
	solid(model, "Wall", V3(2, CAVE_H, CAVE_D), CF(CAVE_W / 2, CAVE_H / 2, 0), CAVE_ROCK, MAT.Slate)
	solid(model, "Wall", V3(CAVE_W, CAVE_H, 2), CF(0, CAVE_H / 2, CAVE_D / 2), CAVE_ROCK, MAT.Slate)
	local fog = solid(model, "Fog", V3(FOG_W, FOG_H, FOG_D), CF(0, FOG_H / 2 + 2, 0), CAVE_DARK, MAT.SmoothPlastic)
	fog.CanCollide = false
	fog.CanTouch = false
	fog.Transparency = 1
	fog:SetAttribute("FogPreset", "cave")
	fog:SetAttribute("FogZone", true)
	local floor = model:FindFirstChild("Floor") :: BasePart?
	if floor then
		model.PrimaryPart = floor
	end
	local lamp = ghost(model, "Lantern", V3(1.2, 1.6, 1.2), CF(0, 8, -4), LANTERN, MAT.Neon)
	local light = Instance.new("PointLight")
	light.Color = LANTERN
	light.Range = 14
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = lamp
	return model
end

-- Lips along the gorge with a gap the width of the deck, plus end walls
-- so the cut has no walkable end. Parts are already in world space.
function LandmarkArt.GorgeWalls(shelfY: number): Model
	local model = Kit.model("GorgeWalls")
	local strip = WorldLayout.NorthStrip
	local gap = WorldLayout.BridgeWidth
	local span = (strip.x1 - strip.x0 - gap) / 2
	local height = WorldLayout.GorgeWallHeight
	local function lip(x: number, z: number)
		solid(model, "Lip", V3(span, height, LIP_THICK), CF(x, shelfY + height / 2, z), STONE[2], MAT.Rock)
	end
	local z0 = WorldLayout.TollLineZ
	local z1 = z0 + WorldLayout.GorgeWidth
	local left = (strip.x0 + (WorldLayout.BridgeCenterX - gap / 2)) / 2
	local right = ((WorldLayout.BridgeCenterX + gap / 2) + strip.x1) / 2
	lip(left, z0)
	lip(right, z0)
	lip(left, z1)
	lip(right, z1)
	local endZ = (z0 + z1) / 2
	local endH = WorldLayout.GorgeDepth + height
	local endY = shelfY + (height - WorldLayout.GorgeDepth) / 2
	solid(model, "End", V3(LIP_THICK, endH, WorldLayout.GorgeWidth), CF(strip.x0, endY, endZ), STONE[1], MAT.Rock)
	solid(model, "End", V3(LIP_THICK, endH, WorldLayout.GorgeWidth), CF(strip.x1, endY, endZ), STONE[1], MAT.Rock)
	return model
end

function LandmarkArt.DeepWater(): Model
	local model = Kit.model("DeepWater")
	local y = WorldLayout.SeaLevel - WATER_T / 2
	local edge = WorldLayout.WorldHalf - WATER_INSET
	local function band(name: string, size: Vector3, cf: CFrame)
		local part = ghost(model, name, size, cf, DEEP, MAT.SmoothPlastic)
		part.Transparency = 0.45
		part.Color = DEEP
	end
	band("East", V3(24, WATER_T, 600), CF(edge, y, 200))
	band("EastIsle", V3(16, WATER_T, 80), CF(edge, y, WorldLayout.Island.z))
	band("South", V3(600, WATER_T, 24), CF(0, y, -edge))
	return model
end

function LandmarkArt.HeatColumn(): Model
	local model = Kit.model("HeatColumn")
	local part = ghost(
		model,
		"Heat",
		V3(HEAT_D, WorldLayout.HeatHeight, HEAT_D),
		CF(0, WorldLayout.HeatHeight / 2, 0),
		HEAT,
		MAT.Neon
	)
	part.Transparency = 0.65
	model.PrimaryPart = part
	return model
end

function LandmarkArt.FerryPath(): Model
	local model = Kit.model("FerryPath")
	local length = WorldLayout.FerryPathLength
	local step = length / PATH_PLANKS
	local anchor = ghost(model, "Anchor", V3(PATH_T, PATH_T, PATH_T), CF(0, 0, 0), PATH, MAT.Sand)
	model.PrimaryPart = anchor
	for i = 1, PATH_PLANKS do
		local fill = 0.8
		ghost(model, "Plank", V3(PATH_W, PATH_T, step * fill), CF(0, PATH_T / 2, -step * (i - 0.5)), PATH, MAT.Sand)
	end
	return model
end

local function tag(part: Instance, name: string)
	local ok, service = pcall(function()
		return game:GetService("CollectionService")
	end)
	if ok and service then
		service:AddTag(part, name)
	end
	part:SetAttribute(name, true)
end

local function stream(model: Model, mode: Enum.ModelStreamingMode): Model
	model.ModelStreamingMode = mode
	return model
end

-- Every W2 model, parented and standing on the terrain. MapBuilder and the
-- part-budget spec both call this.
function LandmarkArt.BuildW2(parent: Instance)
	local shelf = TerrainGen.HeightAt(WorldLayout.BridgeCenterX, WorldLayout.ShelfProbeZ)
	local bank = CFrame.new(WorldLayout.BridgeCenterX, shelf, WorldLayout.BridgeCenterZ)
	local strip = stream(Kit.model("NorthStrip", parent), Enum.ModelStreamingMode.Default)
	local walls = LandmarkArt.GorgeWalls(shelf)
	walls.Parent = strip
	-- A trigger across the whole cut. CanTouch only: it does not hold
	-- anyone up. GateService sends whoever falls in back to the south bank.
	local cutY = shelf - WorldLayout.GorgeDepth
	local gorgeZ = WorldLayout.TollLineZ + WorldLayout.GorgeWidth / 2
	local spanX = WorldLayout.NorthStripX1 - WorldLayout.NorthStripX0
	local trigger =
		solid(strip, "GorgeFloor", V3(spanX, 2, WorldLayout.GorgeWidth), CF(0, cutY + 1, gorgeZ), STONE[2], MAT.Rock)
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = true
	trigger:SetAttribute("GorgeFloor", true)
	local bridge = stream(LandmarkArt.TollBridge(), Enum.ModelStreamingMode.Default)
	Kit.placeAt(bridge, bank)
	bridge.Parent = strip
	local arm = bridge:FindFirstChild("BarrierArm")
	if arm then
		tag(arm, "TollGate")
	end

	local booth = stream(LandmarkArt.TollBooth(), Enum.ModelStreamingMode.Atomic)
	local boothY = TerrainGen.HeightAt(WorldLayout.BoothX, WorldLayout.BoothZ)
	Kit.placeAt(booth, CFrame.new(WorldLayout.BoothX, boothY, WorldLayout.BoothZ))
	booth.Parent = parent

	local function dockAt(x: number, z: number): Model
		local dock = stream(LandmarkArt.FerryDock(), Enum.ModelStreamingMode.Atomic)
		local y = TerrainGen.HeightAt(x, z)
		Kit.placeAt(dock, CFrame.new(x, y, z))
		dock.Parent = parent
		local deck = dock:FindFirstChild("Deck")
		if deck then
			tag(deck, "FerryDock")
		end
		return dock
	end
	dockAt(WorldLayout.FerryDockX, WorldLayout.FerryDockZ)
	local lx, lz = WorldLayout.FerryLanding()
	dockAt(lx, lz)

	local isle = stream(Kit.model("FerryIsland", parent), Enum.ModelStreamingMode.Default)
	local path = LandmarkArt.FerryPath()
	local faceX, faceZ = WorldLayout.FerryFacing()
	local yaw = math.atan2(faceX, faceZ)
	Kit.placeAt(path, CFrame.new(lx, TerrainGen.HeightAt(lx, lz), lz) * CFrame.Angles(0, yaw, 0))
	path.Parent = isle

	local cave = stream(LandmarkArt.SecretCave(), Enum.ModelStreamingMode.Atomic)
	local caveDef = WorldLayout.SecretCave
	local caveY = TerrainGen.HeightAt(caveDef.x, caveDef.z)
	Kit.placeAt(cave, CFrame.new(caveDef.x, caveY, caveDef.z))
	cave.Parent = parent
	local fog = cave:FindFirstChild("Fog")
	if fog then
		tag(fog, "FogZone")
	end

	for _, spot in ipairs(WorldLayout.Breakables) do
		local rock = stream(LandmarkArt.CrackedBoulder(), Enum.ModelStreamingMode.Atomic)
		local y = TerrainGen.HeightAt(spot.x, spot.z)
		Kit.placeAt(rock, CFrame.new(spot.x, y, spot.z))
		rock.Parent = parent
		local part = rock:FindFirstChild("Boulder")
		if part then
			tag(part, "Breakable")
		end
	end

	local water = stream(LandmarkArt.DeepWater(), Enum.ModelStreamingMode.Persistent)
	water.Parent = parent
	for _, part in ipairs(water:GetChildren()) do
		if part:IsA("BasePart") then
			tag(part, "HazardWater")
		end
	end

	local cone = WorldLayout.VolcanoCone
	local heat = stream(LandmarkArt.HeatColumn(), Enum.ModelStreamingMode.Atomic)
	local floorY = TerrainGen.HeightAt(cone.x, cone.z)
	Kit.placeAt(heat, CFrame.new(cone.x, floorY, cone.z))
	heat.Parent = parent
	local heatPart = heat:FindFirstChild("Heat")
	if heatPart then
		tag(heatPart, "HeatZone")
	end
end

return LandmarkArt
