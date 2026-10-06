--!strict
-- BuildingArt: the town's buildings and set dressing (GAME_DESIGN §10, §13)
-- in the cozy low-poly look of concept-art/sawmill-vista: chunky stone
-- footings, honey plank walls where every board is its own tone, shingled
-- roofs with deep overhangs, dark timber frames, warm glowing windows,
-- lanterns, sawdust and stacked lumber. Pure (see Kit), so tools/preview
-- draws exactly what the game builds (scenes "buildings" and "town").
--
-- Every builder returns a Model built around the origin: ground at y = 0,
-- the front (door, counter, open side) facing -Z. Only GondolaStation has a
-- PrimaryPart, so place the others with Kit.placeAt right after building.
-- MapBuilder adds the gameplay bits (attachments, tags, zones). Parts other
-- systems look up by name are listed per builder: keep them.
--
-- Only what players stand on or bump into collides (floors, walls, posts,
-- roofs, counters, big props); everything else is Kit.decor, and small
-- parts cast no shadow. Part budgets (tests/BuildingArt.spec.luau holds
-- them): Sawmill 400, each Shop 227, GondolaStation 140, Campsite 110,
-- a TownTree 70. The extra shop part is the hours board.
--
-- The sawmill and the shops are built at their design size, then scaled up
-- by BuildingArt.Scale (TWN-13: Connor wanted the town's buildings much
-- bigger) with Kit.scaleModel, which adds no parts. A shop's counter, and
-- what stands on it, keeps its size: people still lean on it.

local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local RobuxShelf = require(script.Parent.Parent.RobuxShelf)
local ShopHoursLogic = require(script.Parent.Parent.ShopHoursLogic)
local StoreStock = require(script.Parent.Parent.StoreStock)
local Util = require(script.Parent.Parent.Util)
local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)
local DealershipLot = require(script.Parent.DealershipLot)
local ShopFacade = require(script.Parent.ShopFacade)
local PropArt = require(script.Parent.PropArt)
local ShopDoor = require(script.Parent.ShopDoor)
local ShopInterior = require(script.Parent.ShopInterior)
local TownMeshes = require(script.Parent.TownMeshes)
local TownModels = require(script.Parent.TownModels)
local TreeArt = require(script.Parent.TreeArt)

type Rng = Kit.Rng

local BuildingArt = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local MAT = Enum.Material

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

---------------------------------------------------------------------------
-- Palette (warm, toy-like; see concept-art/sawmill-vista)
---------------------------------------------------------------------------

local PLANK = { hex("#A4693E"), hex("#B07548"), hex("#985F37"), hex("#BC804D") }
local PLANK_DARK = { hex("#7E502E"), hex("#885731"), hex("#724828") }
local CABIN = { hex("#9A5733"), hex("#A6623A"), hex("#8C4F2E"), hex("#B06B40") }
local TIMBER = hex("#5B3920")
local TIMBER_LIGHT = hex("#7A4C2B")
local STONE = { hex("#9C968D"), hex("#ABA498"), hex("#89837B"), hex("#B4AB9D") }
local MORTAR = hex("#6F6A63")
local SHINGLE = { hex("#8B4831"), hex("#9A5338"), hex("#7E402C"), hex("#A65E3D") }
local BARN_ROOF = { hex("#5E4B45"), hex("#6A5650"), hex("#54433E"), hex("#715C55") }
local SLATE_ROOF = { hex("#5D6B7C"), hex("#687889"), hex("#53606F"), hex("#72839A") }
local TIN_ROOF = { hex("#8D99A3"), hex("#97A3AD"), hex("#83909A") }
local ROOF_DECK = hex("#4E3220")
local TRIM = hex("#F2E7CF")
local IRON = hex("#3B3634")
local STEEL = hex("#C9CED3")
local STEEL_DARK = hex("#8E959C")
local BRICK = hex("#A8553D")
local BRICK_DARK = hex("#8A4532")
local SOOT = hex("#3F3633")
local BARK = hex("#76492A")
local HEART = hex("#E4BD83")
local LUMBER = hex("#D9AE72")
local SAWDUST = { hex("#EAC686"), hex("#DFB670"), hex("#F3D79D") }
local CANVAS = hex("#E8D9B8")
local CANVAS_DARK = hex("#CDBB97")
local SOIL = hex("#5C3F2E")
local LEAF = { hex("#5DA24A"), hex("#6FB352"), hex("#4C8F3E") }
local FLOWERS = { hex("#F2728C"), hex("#FFD256"), hex("#8FB8F2"), hex("#FFF3E6"), hex("#E85A4F"), hex("#C58BF2") }
local GLOW = hex("#FFC872")
local EMBER = hex("#FF7A2E")
local FLAME = { hex("#FFD35A"), hex("#FF8A2A"), hex("#FF6A1A") }
local SIGN_BOARD = hex("#4A2D1A")
local SIGN_INK = hex("#F8E7C5")
local DOOR = hex("#6E4426")
local SHUTTER = hex("#4E7A4C")
local HANDLE = hex("#A0703F")
local ROPE = hex("#B89A6A")
local BRASS = hex("#C9A24A")
local PAPER = hex("#F4ECD8")
local CONCRETE = hex("#B3ABA0")
local TYRE = hex("#2E2B2B")
local HAY = hex("#DDB65C")
local WATER = hex("#7CC4F2")
local STAR = hex("#B5D3FF")
local ANVIL = hex("#3C3F48")
local PAD = hex("#D9AE63")
local PAD_INK = hex("#5A3820")

-- How much bigger than its design size each building is built (TWN-13).
-- WorldPlan.Town() places them so their fronts stay where they were.
BuildingArt.Scale = {
	Sawmill = 1.5,
	ToolShed = 1.5,
	Dealership = 1, -- the showroom hall is built at its real size (DealershipLot.Hall)
	HearthAndHome = 1.5,
} :: { [string]: number }

-- The Tool Shed's half depth at design size. It was 7; the aisles and the
-- Robux table need more floor, so the barn grew backward (the front stays
-- put). Its uploaded meshes stretch by the same factor along Z only (the
-- ridge runs that way), see MeshStretch.
-- A name sign's bottom edge stands at least this far above the roof under it
-- (design studs; the Tool Shed and Hearth & Home are scaled 1.5x after).
BuildingArt.SignRise = 3
-- The Dealership's counter: this far in from the lobby's west wall, and this far
-- from the back wall (the counter's middle).
BuildingArt.DealerLobbyCounterX = 13
BuildingArt.DealerCounterBack = 4.8
BuildingArt.ToolShedHalfDepth = 15.0
BuildingArt.ToolShedCounterZ = 13.6 -- the counter's middle, final studs from the shop's middle
BuildingArt.ToolShedHalfWidth = 9.7
local TOOL_SHED_OLD_HALF_DEPTH = 7

-- How far a shop's uploaded meshes are stretched past their authored size
-- (Dress takes a scale). Parts are built to size; the meshes were authored
-- for the old design, so a shop that grew needs its meshes grown to match.
function BuildingArt.MeshStretch(kind: string): Vector3
	if kind == "ToolShed" then
		return Vector3.new(1, 1, BuildingArt.ToolShedHalfDepth / TOOL_SHED_OLD_HALF_DEPTH)
	end
	return Vector3.one
end

-- A closed door leaf. Colour and transparency only; no new parts.
BuildingArt.LockedDoorRed = 40
BuildingArt.LockedDoorGreen = 48
BuildingArt.LockedDoorBlue = 62
BuildingArt.LockedDoorTransparency = 0.35

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- Looks only (Kit.decor); small parts cast no shadow.
local function dec(p: BasePart)
	local s = p.Size
	Kit.decor(p, if math.max(s.X, s.Y, s.Z) < 3 or s.X * s.Y * s.Z < 4 then false else nil)
end

local function dBox(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Kit.part(parent, name, size, cf, color, mat or MAT.Wood)
	dec(p)
	return p
end

local function dWedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
): WedgePart
	local p = Kit.wedge(parent, name, size, cf, color, mat or MAT.Wood)
	dec(p)
	return p
end

-- A looks-only cylinder `length` long along cf's X.
local function dCyl(
	parent: Instance,
	name: string,
	length: number,
	dia: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
): Part
	local p = Kit.cylinder(parent, name, length, dia, cf, color, mat or MAT.Wood)
	dec(p)
	return p
end

local function dBall(parent: Instance, name: string, dia: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Kit.ball(parent, name, dia, cf, color, mat or MAT.SmoothPlastic)
	dec(p)
	return p
end

-- CFrame.lookAt built from its axes. Same result as Roblox's, but Lune's
-- CFrame.lookAt (0.10) disagrees with Roblox, so the preview needs this.
local function lookAt(pos: Vector3, target: Vector3, up: Vector3?): CFrame
	local look = (target - pos).Unit
	local u = up or Vector3.yAxis
	if math.abs(look:Dot(u)) > 0.99 then
		u = if math.abs(look.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	end
	local right = look:Cross(u).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

-- A frame halfway from a to b with its -Z pointing at b.
local function between(a: Vector3, b: Vector3): CFrame
	return lookAt((a + b) / 2, b, if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis)
end

-- A solid box from a to b (`w` x `h` cross-section).
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	mat: Enum.Material?
): Part
	return Kit.part(parent, name, V3(w, h, (b - a).Magnitude), between(a, b), color, mat or MAT.Wood)
end

local function dRod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	dia: number,
	color: Color3,
	mat: Enum.Material?
)
	local cf = between(a, b) * ANG(0, PI / 2, 0) -- the cylinder runs along X
	dec(Kit.cylinder(parent, name, (b - a).Magnitude, dia, cf, color, mat or MAT.Wood))
end

local function dBeam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	mat: Enum.Material?
)
	dec(beam(parent, name, a, b, w, h, color, mat))
end

local function dEllipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?)
	dec(Kit.ellipsoid(parent, name, size, cf, color, mat or MAT.SmoothPlastic))
end

local function light(part: BasePart, range: number, brightness: number, color: Color3?)
	local l = Instance.new("PointLight")
	l.Color = color or Color3.fromRGB(255, 190, 120)
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

---------------------------------------------------------------------------
-- Building pieces
---------------------------------------------------------------------------

-- A course of chunky stones along cf's X; `cf` is the middle of the
-- course's base line. Stones never stand taller than `height`.
local function stones(
	parent: Instance,
	cf: CFrame,
	length: number,
	height: number,
	depth: number,
	rng: Rng,
	minW: number,
	maxW: number,
	colors: { Color3 }?
)
	local x = -length / 2
	while x < length / 2 - 0.25 do
		local w = math.min(rng:range(minW, maxW), length / 2 - x)
		local h = height * rng:range(0.78, 0.98)
		dBox(
			parent,
			"Stone",
			V3(math.max(0.3, w - 0.14), h, depth * rng:range(0.9, 1.1)),
			cf * CF(x + w / 2, h / 2, 0) * ANG(0, rng:range(-0.04, 0.04), rng:range(-0.03, 0.03)),
			Kit.vary(rng:pick(colors or STONE), rng, 0.05),
			MAT.Slate
		)
		x += w
	end
end

type Faces = { front: boolean?, back: boolean?, left: boolean?, right: boolean? }

-- A solid footing under a building (its top is the floor) with chunky
-- stones on the listed faces. `cf` is the middle of its base.
local function plinth(
	parent: Instance,
	cf: CFrame,
	w: number,
	d: number,
	h: number,
	rng: Rng,
	faces: Faces,
	stoneW: number
)
	Kit.part(parent, "Footing", V3(w, h, d), cf * CF(0, h / 2, 0), MORTAR, MAT.Slate)
	local function course(face: CFrame, length: number)
		stones(parent, face, length + 0.4, h, 0.7, rng, stoneW * 0.65, stoneW * 1.25)
	end
	if faces.front then
		course(cf * CF(0, 0, -d / 2), w)
	end
	if faces.back then
		course(cf * CF(0, 0, d / 2) * ANG(0, PI, 0), w)
	end
	if faces.left then
		course(cf * CF(-w / 2, 0, 0) * ANG(0, PI / 2, 0), d)
	end
	if faces.right then
		course(cf * CF(w / 2, 0, 0) * ANG(0, -PI / 2, 0), d)
	end
end

-- A plank wall section (solid) in a wall's own frame: `wall` is the wall's
-- base line (y = 0 at the ground) facing -Z; x0..x1 by y0..y1 is filled.
local function panel(
	parent: Instance,
	wall: CFrame,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	thick: number,
	rng: Rng,
	colors: { Color3 },
	boardH: number
)
	local h = y1 - y0
	local boards = math.max(1, math.floor(h / boardH + 0.5))
	Kit.plankWall(parent, "Wall", wall * CF((x0 + x1) / 2, (y0 + y1) / 2, 0), x1 - x0, h, thick, boards, rng, colors)
end

-- A triangular gable (two solid wedges) in a wall frame: base `span` wide
-- along the frame's X at y = 0, apex `rise` above the middle.
local function gable(
	parent: Instance,
	wall: CFrame,
	span: number,
	rise: number,
	thick: number,
	color: Color3,
	mat: Enum.Material?
)
	local size = V3(thick, rise, span / 2)
	Kit.wedge(
		parent,
		"Gable",
		size,
		wall * CF(-span / 4, rise / 2, 0) * ANG(0, PI / 2, 0),
		color,
		mat or MAT.WoodPlanks
	)
	Kit.wedge(
		parent,
		"Gable",
		size,
		wall * CF(span / 4, rise / 2, 0) * ANG(0, -PI / 2, 0),
		color,
		mat or MAT.WoodPlanks
	)
end

-- Vertical battens over a gable's face (board-and-batten texture).
local function battens(
	parent: Instance,
	wall: CFrame,
	span: number,
	rise: number,
	thick: number,
	gap: number,
	color: Color3
)
	local n = math.floor(span / gap)
	for i = 1, n - 1 do
		local x = -span / 2 + i * span / n
		local h = rise * (1 - math.abs(x) / (span / 2)) - 0.35
		if h > 0.8 then
			dBox(parent, "Batten", V3(0.3, h, 0.16), wall * CF(x, h / 2 + 0.05, -thick / 2 - 0.06), color)
		end
	end
end

type RoofStyle = {
	colors: { Color3 }, -- shingle tones
	deck: Color3, -- the roof boards seen from below
	trim: Color3, -- ridge cap and barge boards
	rowLen: number, -- shingle row depth down the slope
	pieceLen: number, -- shingle length along a row
}

-- One roof plane: a solid slab whose top surface runs from the edge
-- through `top` (centred on it) down `down` for `slopeLen`, `length` wide
-- along `along`, with overlapping rows of shingles on it. `barge` puts
-- boards on the sloping ends: nil = both, 0 = none, +1/-1 = the end at
-- +along / -along only.
local function roofPlane(
	parent: Instance,
	top: Vector3,
	along: Vector3,
	down: Vector3,
	length: number,
	slopeLen: number,
	rng: Rng,
	style: RoofStyle,
	barge: number?
)
	local normal = along:Cross(down).Unit
	if normal.Y < 0 then
		normal = -normal
	end
	local x = along
	if x:Cross(normal):Dot(down) > 0 then
		x = -x
	end
	-- local -Z runs down the slope, +Y out of the roof
	local frame = CFrame.fromMatrix(top, x, normal, x:Cross(normal))
	Kit.part(parent, "Roof", V3(length, 0.4, slopeLen), frame * CF(0, -0.2, -slopeLen / 2), style.deck, MAT.WoodPlanks)
	local rows = math.max(2, math.floor(slopeLen / style.rowLen + 0.5))
	local rl = slopeLen / rows
	local pieces = math.max(1, math.floor(length / style.pieceLen + 0.5))
	local pl = length / pieces
	for r = 1, rows do
		local z = -(r - 0.5) * rl
		local edge = -length / 2
		local first = true
		while edge < length / 2 - 0.05 do
			local w = if first
				then pl * (if r % 2 == 0 then rng:range(0.45, 0.7) else rng:range(0.85, 1.05))
				else pl * rng:range(0.85, 1.15)
			if length / 2 - edge - w < pl * 0.35 then
				w = length / 2 - edge -- no slivers at the far end
			end
			first = false
			dBox(
				parent,
				"Shingle",
				V3(w - 0.08, 0.26, rl * 1.22),
				frame
					* CF(edge + w / 2, 0.15 + r * 0.004, z)
					* ANG(0.1 + rng:range(-0.025, 0.025), rng:range(-0.012, 0.012), 0),
				Kit.vary(rng:pick(style.colors), rng, 0.05),
				MAT.WoodPlanks
			)
			edge += w
		end
	end
	for _, e in ipairs({ -1, 1 }) do
		if barge == nil or barge == e then
			local a = top + along * (e * (length / 2 + 0.13)) - normal * 0.2
			dBeam(parent, "Barge", a, a + down * slopeLen, 0.3, 0.85, style.trim)
		end
	end
end

-- A gable roof: `cf` = the middle of the wall tops, ridge along cf's X;
-- `length` along the ridge (gable overhangs included); `wallSpan` = outside
-- face to outside face across it; `rise` = wall top to ridge; `overhang` =
-- how far the eaves reach past the walls (they drop below the wall top).
-- gable(wall, wallSpan, rise) fits underneath it exactly.
local function gableRoof(
	parent: Instance,
	cf: CFrame,
	length: number,
	wallSpan: number,
	rise: number,
	overhang: number,
	rng: Rng,
	style: RoofStyle,
	barge: number?
)
	local w2 = wallSpan / 2
	local drop = rise * overhang / w2
	local ridge = (cf * CF(0, rise, 0)).Position
	for _, side in ipairs({ -1, 1 }) do
		local eave = (cf * CF(0, -drop, side * (w2 + overhang))).Position
		roofPlane(parent, ridge, cf.XVector, (eave - ridge).Unit, length, (eave - ridge).Magnitude, rng, style, barge)
	end
	dBox(parent, "RidgeCap", V3(length + 0.3, 0.75, 0.75), cf * CF(0, rise + 0.12, 0) * ANG(PI / 4, 0, 0), style.trim)
end

-- A lantern on an iron bracket out of a wall face (`cf` on the face,
-- facing -Z, at the lantern's height). Returns the glowing part.
local function wallLantern(parent: Instance, cf: CFrame, s: number): Part
	dBox(parent, "Bracket", V3(0.2, 0.2, 1.4) * s, cf * CF(0, 0.95 * s, -0.65 * s), IRON, MAT.Metal)
	dBox(parent, "Bracket", V3(0.3, 1.1, 0.16) * s, cf * CF(0, 0.6 * s, -0.04 * s), IRON, MAT.Metal)
	return Kit.lantern(parent, cf * CF(0, 0, -1.25 * s), s)
end

-- A lantern hanging on a chain from a beam's underside at `top`.
local function hangingLantern(parent: Instance, top: Vector3, chain: number, s: number): Part
	dBox(parent, "Chain", V3(0.12, chain, 0.12), CF(top - V3(0, chain / 2, 0)), IRON, MAT.Metal)
	return Kit.lantern(parent, CF(top - V3(0, chain + 0.82 * s, 0)), s)
end

-- A painted box of flowers; `cf` = the middle of the box.
local function flowerBox(parent: Instance, cf: CFrame, w: number, rng: Rng)
	dBox(parent, "FlowerBox", V3(w, 0.8, 0.9), cf, PLANK_DARK[1])
	dEllipsoid(parent, "Leaves", V3(w - 0.2, 0.75, 0.8), cf * CF(0, 0.45, 0), rng:pick(LEAF))
	local n = math.max(3, math.floor(w / 0.75))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n + rng:range(-0.12, 0.12)
		dBall(
			parent,
			"Flower",
			rng:range(0.4, 0.55),
			cf * CF(x, rng:range(0.75, 0.95), rng:range(-0.2, 0.15)),
			rng:pick(FLOWERS)
		)
	end
end

-- A glowing window on a wall face (`cf` = its middle on the face, facing
-- -Z) with optional shutters and a flower box under it.
local function window(
	parent: Instance,
	cf: CFrame,
	w: number,
	h: number,
	frame: Color3,
	shutters: Color3?,
	flowers: Rng?
)
	Kit.window(parent, cf * CF(0, 0, -0.08), w, h, frame, true)
	if shutters then
		for _, s in ipairs({ -1, 1 }) do
			dBox(parent, "Shutter", V3(w * 0.42, h + 0.2, 0.16), cf * CF(s * (w * 0.71 + 0.3), 0, -0.1), shutters)
		end
	end
	if flowers then
		flowerBox(parent, cf * CF(0, -h / 2 - 0.7, -0.6), w + 0.5, flowers)
	end
end

-- A plank door with a frame and a brass knob; `cf` = the middle of its
-- bottom edge on the wall face.
local function markHoursLeaf(part: BasePart)
	part:SetAttribute("HoursLeaf", true)
end

local function door(parent: Instance, cf: CFrame, w: number, h: number, color: Color3, frame: Color3)
	local leaf = dBox(parent, "Door", V3(w, h, 0.25), cf * CF(0, h / 2, -0.1), color, MAT.WoodPlanks)
	markHoursLeaf(leaf)
	dBox(parent, "DoorFrame", V3(w + 0.7, 0.35, 0.4), cf * CF(0, h + 0.15, -0.15), frame)
	for _, s in ipairs({ -1, 1 }) do
		dBox(parent, "DoorFrame", V3(0.35, h, 0.4), cf * CF(s * (w / 2 + 0.15), h / 2, -0.15), frame)
	end
	dBox(parent, "DoorBrace", V3(w - 0.3, 0.3, 0.1), cf * CF(0, h * 0.3, -0.27), Kit.shade(color, -0.12))
	dBox(parent, "DoorBrace", V3(w - 0.3, 0.3, 0.1), cf * CF(0, h * 0.75, -0.27), Kit.shade(color, -0.12))
	dBox(parent, "DoorKnob", V3(0.25, 0.25, 0.25), cf * CF(w / 2 - 0.45, h * 0.5, -0.33), BRASS, MAT.Metal)
end

-- A painted sign board with a frame; `cf` = its middle, facing -Z. The
-- board is named `name` and carries the text (front, or both faces).
local function signBoard(
	parent: Instance,
	name: string,
	cf: CFrame,
	w: number,
	h: number,
	text: string,
	board: Color3,
	frame: Color3,
	ink: Color3,
	bothSides: boolean
): Part
	local b = dBox(parent, name, V3(w, h, 0.4), cf, board)
	Kit.signText(b, text, ink, if bothSides then nil else { Enum.NormalId.Front })
	for _, s in ipairs({ -1, 1 }) do
		dBox(parent, "SignFrame", V3(w + 0.6, 0.3, 0.55), cf * CF(0, s * (h / 2 + 0.15), 0), frame)
		dBox(parent, "SignFrame", V3(0.3, h, 0.55), cf * CF(s * (w / 2 + 0.15), 0, 0), frame)
	end
	return b
end

-- A gooseneck lamp shining down on a sign; `cf` = where the arm leaves
-- the sign's top edge, facing -Z. Its "LampBulb" is one of
-- LightingController's night lights: Neon with its light on after dark,
-- plain and unlit by day.
local function gooseneck(parent: Instance, cf: CFrame)
	dRod(parent, "LampArm", (cf * CF(0, -0.1, 0.1)).Position, (cf * CF(0, 0.9, -1.0)).Position, 0.18, IRON, MAT.Metal)
	dBox(parent, "LampShade", V3(0.9, 0.35, 0.7), cf * CF(0, 0.95, -1.25) * ANG(-0.45, 0, 0), IRON, MAT.Metal)
	light(dBall(parent, "LampBulb", 0.42, cf * CF(0, 0.72, -1.32), GLOW, MAT.Neon), 10, 1.2)
end

-- A shop's or the sawmill's name sign (phase 12): a big, bold board in the
-- building's colours with a thick frame, its name on the front (or both
-- faces), up where the street and the lot can read it. Looks only, like
-- every sign (nothing of it collides). `cf` = the board's middle, facing
-- -Z. The board is named "Sign"; fitNameSign sizes its text once the
-- building is scaled.
local NAME_FRAME = 0.45 -- a name sign's frame (a plain board's is 0.3)
local function nameSign(
	parent: Instance,
	cf: CFrame,
	w: number,
	h: number,
	text: string,
	board: Color3,
	frame: Color3,
	ink: Color3,
	bothSides: boolean,
	thick: number?
): Part
	local b = dBox(parent, "Sign", V3(w, h, thick or 0.5), cf, board)
	Kit.signText(b, text, ink, if bothSides then nil else { Enum.NormalId.Front })
	local f = NAME_FRAME
	for _, s in ipairs({ -1, 1 }) do
		dBox(parent, "SignFrame", V3(w + 2 * f, f, 0.7), cf * CF(0, s * (h + f) / 2, 0), frame)
		dBox(parent, "SignFrame", V3(f, h, 0.7), cf * CF(s * (w + f) / 2, 0, 0), frame)
	end
	return b
end

-- Roblox draws TextScaled text 100 pixels tall at most, so at Kit.signText's
-- 40 pixels a stud a sign's letters never grow past about 2.5 studs, however
-- big its board. A name sign's text gets as many pixels a stud as fit the
-- board's height into NAME_SIGN_PIXELS (its text box, inside the padding,
-- about 100), so its letters fill the board the way a small sign's do. Run
-- it on the finished (scaled) board.
local NAME_SIGN_PIXELS = 120
local function fitNameSign(board: BasePart)
	local pixelsPerStud = math.clamp(NAME_SIGN_PIXELS / board.Size.Y, 10, 40)
	for _, gui in ipairs(board:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			gui.PixelsPerStud = pixelsPerStud
		end
	end
end

-- A log along cf's X with pale end caps (`caps` 0, 1 = the +X end, 2).
local function log(
	parent: Instance,
	cf: CFrame,
	length: number,
	dia: number,
	rng: Rng,
	caps: number,
	solid: boolean?
): Part
	local p = Kit.cylinder(parent, "Log", length, dia, cf, Kit.vary(BARK, rng, 0.06), MAT.Wood)
	if not solid then
		dec(p)
	end
	for i, side in ipairs({ 1, -1 }) do
		if i <= caps then
			dCyl(
				parent,
				"LogEnd",
				0.08,
				dia * 0.8,
				cf * CF(side * (length / 2 + 0.03), 0, 0),
				Kit.vary(HEART, rng, 0.04)
			)
		end
	end
	return p
end

-- A stack of sawn boards on spacer sticks; `cf` = the middle of its base,
-- boards along its X, `boards` side by side in each layer.
local function lumberStack(
	parent: Instance,
	cf: CFrame,
	length: number,
	width: number,
	layers: number,
	boards: number,
	rng: Rng
)
	local y = 0
	for _ = 1, layers do
		for _, x in ipairs({ -length * 0.34, length * 0.34 }) do
			dBox(parent, "Sticker", V3(0.4, 0.25, width + 0.3), cf * CF(x, y + 0.125, 0), PLANK_DARK[2])
		end
		y += 0.25
		local bw = width / boards
		for b = 1, boards do
			local p = Kit.part(
				parent,
				"Lumber",
				V3(length * rng:range(0.94, 1), 0.5, bw - 0.06),
				cf * CF(rng:range(-0.2, 0.2), y + 0.25, -width / 2 + (b - 0.5) * bw),
				Kit.vary(LUMBER, rng, 0.05),
				MAT.WoodPlanks
			)
			p.CastShadow = true
		end
		y += 0.5
	end
end

-- A mound of sawdust (half buried ellipsoids) with a few chips around it.
local function sawdust(parent: Instance, cf: CFrame, size: number, rng: Rng)
	dEllipsoid(parent, "Sawdust", V3(size * 1.7, size * 0.95, size * 1.4), cf, rng:pick(SAWDUST), MAT.Sand)
	dEllipsoid(
		parent,
		"Sawdust",
		V3(size * 1.0, size * 0.7, size * 0.9),
		cf * CF(size * rng:range(-0.5, 0.5), 0, size * rng:range(0.25, 0.5)),
		rng:pick(SAWDUST),
		MAT.Sand
	)
	for _ = 1, 1 do
		local a = rng:range(0, PI * 2)
		dBox(
			parent,
			"Chip",
			V3(0.5, 0.12, 0.3),
			cf * CF(math.cos(a) * size * 1.05, 0.06, math.sin(a) * size * 0.9) * ANG(0, a, 0),
			Kit.vary(LUMBER, rng, 0.06)
		)
	end
end

-- A barrel (body + iron hoops + lid); `cf` = the middle of its base.
local function barrel(parent: Instance, cf: CFrame, rng: Rng, solid: boolean, color: Color3?)
	local base = cf.Position
	local body =
		Kit.post(parent, "Barrel", base, 2.5, 2.0, color or Kit.vary(hex("#8E5A33"), rng, 0.06), MAT.WoodPlanks)
	if not solid then
		dec(body)
	end
	for _, y in ipairs({ 0.45, 2.05 }) do
		dec(Kit.post(parent, "Hoop", base + V3(0, y - 0.1, 0), 0.2, 2.1, IRON, MAT.Metal))
	end
	dec(Kit.post(parent, "Lid", base + V3(0, 2.5, 0), 0.06, 1.7, PLANK_DARK[1], MAT.Wood))
end

-- A wooden crate with banded edges and a brace; `cf` = the middle of its
-- base, `s` its size.
local function crate(parent: Instance, cf: CFrame, s: number, rng: Rng, solid: boolean)
	local body = Kit.part(
		parent,
		"Crate",
		V3(s, s, s),
		cf * CF(0, s / 2, 0),
		Kit.vary(hex("#C08A55"), rng, 0.05),
		MAT.WoodPlanks
	)
	if not solid then
		dec(body)
	end
	local band = Kit.vary(hex("#7E5230"), rng, 0.04)
	for _, y in ipairs({ 0.18, s - 0.18 }) do
		dBox(parent, "CrateBand", V3(s + 0.1, 0.3, s + 0.1), cf * CF(0, y, 0), band)
	end
	dBox(parent, "CrateBrace", V3(0.3, s * 1.2, 0.1), cf * CF(0, s / 2, -s / 2 - 0.05) * ANG(0, 0, PI / 4), band)
end

-- An axe hanging head-up: handle up from `cf`, the bit toward cf's -X.
local function rackAxe(parent: Instance, cf: CFrame, len: number, color: Color3, mat: Enum.Material)
	dBox(parent, "AxeHandle", V3(0.26, len, 0.26), cf * CF(0, len / 2, 0), HANDLE)
	local head = dBox(parent, "AxeHead", V3(0.95, 0.85, 0.3), cf * CF(-0.4, len - 0.45, 0), color, mat)
	if mat == MAT.Neon then
		light(head, 6, 0.8, color)
	end
end

-- A brass cash register; `cf` = the middle of its base on a counter.
local function register(parent: Instance, cf: CFrame)
	dBox(parent, "Register", V3(1.6, 0.85, 1.2), cf * CF(0, 0.42, 0), BRASS, MAT.Metal)
	dBox(
		parent,
		"Register",
		V3(1.4, 0.55, 0.6),
		cf * CF(0, 1.0, 0.25) * ANG(-0.45, 0, 0),
		Kit.shade(BRASS, -0.15),
		MAT.Metal
	)
	dBox(parent, "RegisterTag", V3(0.8, 0.4, 0.08), cf * CF(0, 1.5, 0.42), PAPER, MAT.SmoothPlastic)
end

-- An open ledger book; `cf` = its middle on a counter.
local function ledger(parent: Instance, cf: CFrame)
	dBox(parent, "LedgerCover", V3(2.0, 0.08, 1.35), cf * CF(0, 0.04, 0), hex("#3F5E3A"))
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			parent,
			"LedgerPage",
			V3(0.92, 0.1, 1.2),
			cf * CF(s * 0.47, 0.12, 0) * ANG(0, 0, -s * 0.07),
			PAPER,
			MAT.SmoothPlastic
		)
	end
end

-- A grindstone: a stone wheel turning in a trough on splayed legs. The
-- trough and the wheel collide (the legs stand under them).
local function grindstone(parent: Instance, cf: CFrame)
	Kit.solid(dBox(parent, "GrindTrough", V3(2.6, 0.7, 1.3), cf * CF(0, 1.9, 0), TIMBER_LIGHT))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			dBeam(
				parent,
				"GrindLeg",
				(cf * V3(sx * 1.25, 0, sz * 0.7)),
				(cf * V3(sx * 0.95, 1.7, sz * 0.45)),
				0.3,
				0.3,
				TIMBER
			)
		end
	end
	Kit.solid(dCyl(parent, "Grindstone", 0.55, 2.6, cf * CF(0, 2.9, 0), hex("#B9AE98"), MAT.Sandstone))
	dCyl(parent, "Axle", 2.9, 0.25, cf * CF(0, 2.9, 0), IRON, MAT.Metal)
	dBox(parent, "Crank", V3(0.2, 0.9, 0.2), cf * CF(1.5, 2.55, 0), IRON, MAT.Metal)
	dCyl(parent, "CrankHandle", 0.7, 0.25, cf * CF(1.8, 2.15, 0), HANDLE)
end

-- A chopping block (a solid stump) with an axe sunk in its top.
local function choppingBlock(parent: Instance, cf: CFrame, rng: Rng)
	local base = cf.Position
	Kit.post(parent, "ChoppingBlock", base, 1.5, 2.0, Kit.vary(BARK, rng, 0.05), MAT.Wood)
	dec(Kit.post(parent, "StumpTop", base + V3(0, 1.5, 0), 0.06, 1.7, HEART, MAT.Wood))
	dRod(parent, "AxeHandle", (cf * V3(0.15, 1.55, 0)), (cf * V3(1.6, 3.0, -0.2)), 0.26, HANDLE)
	dBox(parent, "AxeHead", V3(0.3, 0.75, 1.0), cf * CF(0.05, 1.55, 0.05) * ANG(0, 0, 0.78), hex("#A7ADB4"), MAT.Metal)
	for i = 1, 2 do
		local a = rng:range(0, PI * 2)
		dWedge(
			parent,
			"Split",
			V3(0.6, 0.6, 1.4),
			cf * CF(math.cos(a) * 1.7, 0.3, math.sin(a) * 1.7) * ANG(0, a + i, 0),
			Kit.vary(HEART, rng, 0.05)
		)
	end
end

-- A potted shrub in a half barrel; `cf` = the middle of its base.
local function planter(parent: Instance, cf: CFrame, rng: Rng)
	local base = cf.Position
	Kit.post(parent, "Planter", base, 1.3, 2.0, Kit.vary(PLANK_DARK[1], rng, 0.05), MAT.WoodPlanks)
	dec(Kit.post(parent, "Hoop", base + V3(0, 0.9, 0), 0.18, 2.08, IRON, MAT.Metal))
	dec(Kit.post(parent, "Soil", base + V3(0, 1.3, 0), 0.08, 1.8, SOIL, MAT.Ground))
	Kit.blob(parent, "Shrub", cf * CF(0, 2.05, 0), V3(2.0, 1.7, 2.0), 3, rng, LEAF)
	for _ = 1, 2 do
		local a = rng:range(0, PI * 2)
		dBall(
			parent,
			"Flower",
			0.45,
			cf * CF(math.cos(a) * 0.75, rng:range(2.1, 2.7), math.sin(a) * 0.75),
			rng:pick(FLOWERS)
		)
	end
end

---------------------------------------------------------------------------
-- The sawmill
---------------------------------------------------------------------------

-- The sawmill: at its design size (scale 1) about 43 x 29 studs (x
-- -21..22, z -14..15), the mill shed's open front (-Z) on the sell side.
-- Below 8 studs up, nothing within |x| < 12 reaches past z = -13, so the
-- sell pad can start 13 studs in front of the centre. `scale` (default
-- BuildingArt.Scale.Sawmill) scales all of it about the origin, those
-- numbers included.
--   * the mill shed (x -11..11): plank deck at y = 1 up a front ramp, the
--     headrig inside (log carriage on rails, the saw, a steam engine and
--     boiler), a "TIMBERLINE SAWMILL" crest sign above the roof ridge;
--   * the office cabin on the west side, the log slip and log deck under a
--     lean-to on the east, lumber stacks, sawdust, barrels, lanterns.
-- Named parts:
--   "SawBlade": a cylinder (9 across) whose axis is its own X axis,
--     pointing along world Z (the blade faces the sell pad). Spin it on
--     clients with blade.CFrame *= CFrame.Angles(step, 0, 0). Its teeth,
--     hub and rivets are welded to it (unanchored, massless), so they turn
--     with it. Not collidable. "SawGuard" is an invisible box over the
--     blade, and "GuardRail" closes the front of the headrig and the east
--     opening: players and loose logs bump those instead of walking into
--     the saw.
--   "Smokestack": the top of the brick stack (y 25.7..27.9), holding the
--     Smoke.
function BuildingArt.Sawmill(scale: number?): Model
	local model = Kit.model("Sawmill")
	local rng = Kit.rng(1907)
	local roofStyle: RoofStyle = { colors = SHINGLE, deck = ROOF_DECK, trim = TIMBER, rowLen = 2.3, pieceLen = 9 }

	-- The mill shed: x -11..11, z -11.5..13, deck at y = 1, walls to 13.
	local X0, X1, Z0, Z1 = -11, 11, -11.5, 13
	local FLOOR, TOP, RISE = 1, 13, 7
	local zMid, depth = (Z0 + Z1) / 2, Z1 - Z0
	plinth(model, CF(0, 0, zMid), 22, depth, FLOOR - 0.2, rng, { front = true, right = true, back = true }, 3.4)
	for i = 0, 3 do
		Kit.part(
			model,
			"Deck",
			V3(5.44, 0.2, depth),
			CF(X0 + 2.75 + i * 5.5, FLOOR - 0.1, zMid),
			Kit.vary(PLANK[1], rng, 0.05),
			MAT.WoodPlanks
		)
	end
	Kit.wedge(model, "Ramp", V3(18, FLOOR, 1.5), CF(0, FLOOR / 2, Z0 - 0.75), PLANK[2], MAT.WoodPlanks)
	for _, x in ipairs({ X0, X1 }) do
		for _, z in ipairs({ Z0, 0.75, Z1 }) do
			Kit.part(model, "Post", V3(1.4, TOP - FLOOR, 1.4), CF(x, (TOP + FLOOR) / 2, z), TIMBER, MAT.Wood)
		end
	end
	panel(model, CF(0, 0, Z1) * ANG(0, PI, 0), X0, X1, FLOOR, TOP, 0.6, rng, PLANK, 1.75)
	panel(model, CF(X0, 0, 0) * ANG(0, PI / 2, 0), -Z1, -Z0, FLOOR, TOP, 0.6, rng, PLANK, 1.75)
	local east = CF(X1, 0, 0) * ANG(0, -PI / 2, 0) -- local x = world z
	panel(model, east, Z0, -3.6, FLOOR, TOP, 0.6, rng, PLANK, 1.75)
	panel(model, east, 2.4, Z1, FLOOR, TOP, 0.6, rng, PLANK, 1.75)
	panel(model, east, -3.6, 2.4, 7.4, TOP, 0.6, rng, PLANK, 1.75)
	local front = CF(0, TOP, Z0)
	gable(model, front, 22, RISE, 0.6, PLANK[3])
	battens(model, front, 22, RISE, 0.6, 2.6, PLANK_DARK[1])
	gable(model, CF(0, TOP, Z1) * ANG(0, PI, 0), 22, RISE, 0.6, PLANK[3])
	Kit.part(model, "Header", V3(23.4, 1.4, 1.5), CF(0, TOP - 0.7, Z0), TIMBER, MAT.Wood)
	for _, s in ipairs({ -1, 1 }) do
		dBeam(model, "Brace", V3(s * 10.4, 8.6, Z0), V3(s * 7.2, TOP - 1.3, Z0), 0.7, 0.7, TIMBER)
	end
	dBox(model, "TieBeam", V3(21.4, 1, 1), CF(0, TOP - 0.5, -2.6), TIMBER)
	-- A log-slice medallion on the front gable.
	local slice = front * CF(0, 2.6, -0.42) * ANG(0, PI / 2, 0)
	dCyl(model, "Medallion", 0.3, 3.4, slice, BARK)
	dCyl(model, "Medallion", 0.36, 2.9, slice, HEART)
	dCyl(model, "Medallion", 0.42, 1.7, slice, Kit.shade(HEART, -0.1))
	dCyl(model, "Medallion", 0.48, 0.6, slice, Kit.shade(HEART, -0.25))
	gableRoof(model, CF(0, TOP, zMid) * ANG(0, PI / 2, 0), depth + 2.4, 23.4, RISE, 1.4, rng, roofStyle)

	-- The crest sign above the ridge (phase 12: bigger and bolder, still
	-- cream on dark brown, now in a honey frame), its frame clear of the
	-- ridge cap, on two posts standing on the roof, lit by two goosenecks.
	local signW, signH = 26.4, 4.6
	local signY, signZ = TOP + RISE + 0.85 + NAME_FRAME + signH / 2, Z0 - 0.3
	local crest =
		nameSign(model, CF(0, signY, signZ), signW, signH, "TIMBERLINE SAWMILL", SIGN_BOARD, LUMBER, SIGN_INK, true)
	for _, s in ipairs({ -1, 1 }) do
		local roofY = TOP + RISE * (1 - 8 / 11.7)
		local h = signY - signH / 2 - roofY + 0.6
		Kit.part(model, "SignPost", V3(0.7, h, 0.7), CF(s * 8, roofY - 0.6 + h / 2, signZ + 0.6), TIMBER, MAT.Wood)
		gooseneck(model, CF(s * 8.8, signY + (signH + NAME_FRAME) / 2, signZ - 0.2))
	end

	-- The office cabin (west): x -20..-11.3, z -7..9.
	local CX0, CX1, CZ0, CZ1, CTOP = -20, -11.3, -7, 9, 9
	local cw, cd = CX1 - CX0, CZ1 - CZ0
	local ccx, ccz = (CX0 + CX1) / 2, (CZ0 + CZ1) / 2
	local cabinRoof: RoofStyle = { colors = SHINGLE, deck = ROOF_DECK, trim = TIMBER, rowLen = 2.1, pieceLen = 6.5 }
	plinth(model, CF(ccx, 0, ccz), cw, cd, FLOOR, rng, { front = true, left = true, back = true }, 2.9)
	panel(model, CF(0, 0, CZ0), CX0, CX1, FLOOR, CTOP, 0.6, rng, CABIN, 1.9)
	panel(model, CF(CX0, 0, 0) * ANG(0, PI / 2, 0), -CZ1, -CZ0, FLOOR, CTOP, 0.6, rng, CABIN, 1.9)
	panel(model, CF(0, 0, CZ1) * ANG(0, PI, 0), -CX1, -CX0, FLOOR, CTOP, 0.6, rng, CABIN, 1.9)
	for _, c in ipairs({ { CX0, CZ0 }, { CX0, CZ1 }, { CX1, CZ0 } }) do
		Kit.part(model, "Post", V3(1, CTOP - FLOOR, 1), CF(c[1], (CTOP + FLOOR) / 2, c[2]), TIMBER, MAT.Wood)
	end
	gable(model, CF(CX0, CTOP, ccz) * ANG(0, PI / 2, 0), cd, 4.6, 0.6, CABIN[3])
	gableRoof(model, CF(ccx - 0.5, CTOP, ccz), cw + 1, cd + 0.6, 4.6, 1.2, rng, cabinRoof, -1)
	door(model, CF(-14.1, FLOOR, CZ0 - 0.3), 2.8, 6, DOOR, TIMBER_LIGHT)
	window(model, CF(-17.6, 5.4, CZ0 - 0.3), 2.5, 2.4, TIMBER_LIGHT, nil, rng)
	window(model, CF(CX0 - 0.3, 5.4, 1) * ANG(0, PI / 2, 0), 2.6, 2.4, TIMBER_LIGHT, SHUTTER, nil)
	wallLantern(model, CF(CX1, 6.6, CZ0 - 0.5), 0.9)

	-- The smokestack behind the cabin, fed by the boiler's flue.
	local sx, sz = -15.4, 12.4
	Kit.part(model, "StackBase", V3(4.4, 3, 4.4), CF(sx, 1.5, sz), STONE[2], MAT.Slate)
	dBox(model, "StackBase", V3(4.9, 0.5, 4.9), CF(sx, 3.1, sz), STONE[1], MAT.Slate)
	Kit.part(model, "StackShaft", V3(3, 22.4, 3), CF(sx, 14.5, sz), BRICK, MAT.Brick)
	for _, y in ipairs({ 10, 18 }) do
		dBox(model, "StackBand", V3(3.35, 0.5, 3.35), CF(sx, y, sz), BRICK_DARK, MAT.Brick)
	end
	dBox(model, "StackBand", V3(3.7, 0.8, 3.7), CF(sx, 25.4, sz), BRICK_DARK, MAT.Brick)
	local stack = Kit.part(model, "Smokestack", V3(3.2, 2.2, 3.2), CF(sx, 26.8, sz), SOOT, MAT.Brick)
	dBox(model, "StackRim", V3(3.6, 0.4, 3.6), CF(sx, 28, sz), IRON, MAT.Metal)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(226, 220, 212)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 5
	smoke.Size = 4
	smoke.Parent = stack

	-- The lean-to over the log slip and the log deck (east).
	for _, z in ipairs({ -10.2, -0.6, 10.2 }) do
		Kit.part(model, "Post", V3(1, 7, 1), CF(19.6, 3.5, z), TIMBER, MAT.Wood)
	end
	dBox(model, "Plate", V3(1.1, 0.8, 21.4), CF(19.6, 7.2, 0), TIMBER)
	local hi, lo = V3(11.5, 10.6, 0), V3(20.9, 7.25, 0)
	roofPlane(model, hi, Vector3.zAxis, (lo - hi).Unit, 22, (lo - hi).Magnitude, rng, roofStyle)
	dBox(model, "Fascia", V3(0.35, 0.8, 22.3), CF(21.05, 6.9, 0), TIMBER)
	-- The log slip: logs ride up it onto the carriage.
	local slipZ = -0.6
	local slipA, slipB = V3(21.6, 0.3, slipZ), V3(11.6, 2.1, slipZ)
	for _, dz in ipairs({ -1, 1 }) do
		dBeam(model, "SlipRail", slipA + V3(0, 0, dz), slipB + V3(0, 0, dz), 0.45, 0.6, TIMBER)
		Kit.part(model, "SlipLeg", V3(0.5, 1.7, 0.5), CF(12.8, 0.85, slipZ + dz), TIMBER, MAT.Wood)
	end
	dBeam(model, "SlipChain", slipA + V3(0, 0.25, 0), slipB + V3(0, 0.25, 0), 0.35, 0.25, IRON, MAT.Metal)
	local slipDir = (slipB - slipA).Unit
	local onSlip = slipA:Lerp(slipB, 0.45) + V3(0, 1.45, 0)
	log(model, lookAt(onSlip, onSlip + slipDir) * ANG(0, PI / 2, 0), 6.5, 2.2, rng, 2, true)
	-- The log deck: a pyramid of logs, cut ends to the front (all of it
	-- solid, inside the bottom row's footprint).
	for row = 0, 2 do
		for i = 0, 2 - row do
			local x = 16.3 + (i - (2 - row) / 2) * 2.1
			log(model, CF(x, 1.0 + row * 1.75, -6.6) * ANG(0, PI / 2, 0), 6.4, 2.0, rng, 1, true)
		end
	end

	-- The headrig: carriage on rails, the log, the saw, its drive.
	for _, z in ipairs({ -1.6, 0.4 }) do
		dBox(model, "Rail", V3(21.6, 0.25, 0.3), CF(0, FLOOR + 0.125, z), STEEL_DARK, MAT.Metal)
	end
	local carX = 3.4
	Kit.part(model, "Carriage", V3(6.6, 0.55, 2.9), CF(carX, FLOOR + 0.78, -0.6), TIMBER, MAT.Wood)
	for _, dx in ipairs({ -2.5, 2.5 }) do
		for _, z in ipairs({ -1.6, 0.4 }) do
			dCyl(model, "Wheel", 0.4, 0.9, CF(carX + dx, FLOOR + 0.7, z) * ANG(0, PI / 2, 0), IRON, MAT.Metal)
		end
		dBox(model, "Knee", V3(0.7, 2.2, 0.6), CF(carX + dx * 0.76, FLOOR + 2.15, -1.75), TIMBER_LIGHT)
	end
	log(model, CF(carX, FLOOR + 2.35, -0.1), 6.2, 2.6, rng, 2, true)

	local bladeCf = CF(-3.2, 6, 1.35) * ANG(0, PI / 2, 0)
	local blade = Kit.cylinder(model, "SawBlade", 0.3, 9, bladeCf, hex("#DDE2E6"), MAT.Metal)
	Kit.decor(blade)
	local function onBlade(p: BasePart)
		dec(p)
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = blade
		weld.Part1 = p
		weld.Parent = p
	end
	local hub = bladeCf.Position
	for i = 0, 15 do
		local a = i / 16 * PI * 2
		local radial = V3(math.cos(a), math.sin(a), 0)
		onBlade(
			Kit.wedge(
				model,
				"SawTooth",
				V3(0.26, 0.6, 0.9),
				CFrame.fromMatrix(hub + radial * 4.7, Vector3.zAxis, radial, V3(-radial.Y, radial.X, 0)),
				STEEL_DARK,
				MAT.Metal
			)
		)
	end
	onBlade(Kit.cylinder(model, "BladeHub", 0.5, 1.8, bladeCf, IRON, MAT.Metal))
	-- One rivet: the teeth and the hub already meet the weld count.
	local a = 0.5
	onBlade(
		Kit.cylinder(
			model,
			"BladeRivet",
			0.34,
			0.6,
			CF(hub + V3(math.cos(a), math.sin(a), 0) * 2.6) * ANG(0, PI / 2, 0),
			IRON,
			MAT.Metal
		)
	)
	dCyl(model, "Arbor", 3.4, 0.55, CF(-3.2, 6, 3) * ANG(0, PI / 2, 0), STEEL_DARK, MAT.Metal)
	Kit.part(model, "SawFrame", V3(1.6, 4.6, 1.4), CF(-3.2, FLOOR + 2.3, 3.4), TIMBER, MAT.Wood)
	dBox(model, "Bearing", V3(1.9, 0.9, 1.6), CF(-3.2, 6, 3.4), IRON, MAT.Metal)
	dCyl(model, "Pulley", 0.6, 2.2, CF(-3.2, 6, 4.5) * ANG(0, PI / 2, 0), IRON, MAT.Metal)
	dCyl(model, "Flywheel", 0.5, 3, CF(-3.2, FLOOR + 1.6, 4.5) * ANG(0, PI / 2, 0), hex("#8E3426"), MAT.Metal)
	for _, s in ipairs({ -1, 1 }) do
		dBeam(
			model,
			"Belt",
			V3(-3.2 + s * 1.12, 6, 4.5),
			V3(-3.2 + s * 1.5, FLOOR + 1.6, 4.5),
			0.5,
			0.14,
			hex("#4A2F22")
		)
	end
	Kit.part(model, "Engine", V3(3, 1.2, 1.8), CF(-7, FLOOR + 0.6, 4.5), IRON, MAT.Metal)
	dCyl(model, "SteamCylinder", 2.4, 1.5, CF(-7.2, FLOOR + 1.95, 4.5), hex("#8E3426"), MAT.Metal)
	dRod(model, "PistonRod", V3(-6, FLOOR + 1.95, 4.5), V3(-3.7, FLOOR + 2.3, 4.1), 0.25, STEEL, MAT.Metal)
	Kit.post(model, "Boiler", V3(-8, FLOOR, 9.8), 5.6, 3.2, hex("#3E3936"), MAT.Metal)
	dEllipsoid(model, "BoilerDome", V3(3.2, 1.4, 3.2), CF(-8, FLOOR + 5.6, 9.8), hex("#4A4542"), MAT.Metal)
	local firebox = dBox(model, "Firebox", V3(1.3, 1.0, 0.25), CF(-8, FLOOR + 1.0, 8.15), EMBER, MAT.Neon)
	light(firebox, 9, 1.4, Color3.fromRGB(255, 140, 70))
	dRod(model, "Flue", V3(-8, FLOOR + 6, 9.8), V3(-8, 9.6, 9.8), 0.9, IRON, MAT.Metal)
	dRod(model, "Flue", V3(-8, 9.6, 9.8), V3(-13.9, 9.6, 12.4), 0.9, IRON, MAT.Metal)
	dRod(model, "SteamPipe", V3(-7.6, FLOOR + 4.2, 8.3), V3(-7.2, FLOOR + 2.6, 5.4), 0.35, STEEL_DARK, MAT.Metal)

	-- The blade doesn't collide (it has to spin). An invisible box covers
	-- the disc down to the deck, short of the log on the carriage. A rail
	-- across the front of the headrig and one in the east opening keep
	-- people on the deck side of the saw.
	local sawGuard = Kit.part(model, "SawGuard", V3(8.2, 11, 2.2), CF(-3.9, 6.55, 1.35), TIMBER, MAT.Wood)
	sawGuard.Transparency = 1
	sawGuard.CastShadow = false
	sawGuard.CanTouch = false
	local frontRail = Kit.part(model, "GuardRail", V3(14, 3.4, 0.4), CF(-2, 2.75, -3.1), TIMBER, MAT.Wood)
	frontRail.CanTouch = false
	local eastRail = Kit.part(model, "GuardRail", V3(0.45, 5.2, 6.2), CF(9.7, 3.65, -0.5), TIMBER, MAT.Wood)
	eastRail.CanTouch = false

	-- Inside: cut lumber, sawdust, barrels, lanterns from the tie beam.
	lumberStack(model, CF(-7.4, FLOOR, -8.4), 5.6, 2.4, 3, 2, rng)
	sawdust(model, CF(-5.8, FLOOR, -3.5), 2, rng)
	barrel(model, CF(8.4, FLOOR, -9.3), rng, true)
	barrel(model, CF(9.1, FLOOR, -7.1), rng, true)
	for _, x in ipairs({ -5, 5 }) do
		hangingLantern(model, V3(x, TOP - 1, -2.6), 1.2, 0.9)
	end

	-- Outside: lanterns on the front posts, sawdust, the office's yard.
	for _, s in ipairs({ -1, 1 }) do
		wallLantern(model, CF(s * 11, 9.4, Z0 - 0.7), 1)
	end
	sawdust(model, CF(15.4, 0, -11), 2.8, rng)
	lumberStack(model, CF(-16.4, 0, -10.5), 5.4, 2.2, 3, 2, rng)
	barrel(model, CF(-12.6, 0, -8.6), rng, true)
	crate(model, CF(-19, 0, -8.4) * ANG(0, 0.2, 0), 1.8, rng, true)
	crate(model, CF(-19.1, 1.8, -8.5) * ANG(0, -0.25, 0), 1.3, rng, true)
	Kit.scaleModel(model, scale or BuildingArt.Scale.Sawmill)
	fitNameSign(crest)
	-- Authored at 1.5 already: do not scale the meshes again.
	TownMeshes.Dress(model, "Sawmill")
	return model
end

---------------------------------------------------------------------------
-- The shops
---------------------------------------------------------------------------

-- The Tool Shed: a red barn workshop with a gambrel roof, its barn doors
-- slid open on the counter, the axe ladder on the back wall (every axe the
-- shop sells, from ItemCatalog), a grindstone and a chopping block out
-- front, logs stacked by the east wall.
local function toolShed(model: Model, title: string, accent: Color3)
	local rng = Kit.rng(311)
	local red = { accent, Kit.shade(accent, 0.07), Kit.shade(accent, -0.07), Kit.vary(accent, rng, 0.05) }
	local roofStyle: RoofStyle = { colors = BARN_ROOF, deck = ROOF_DECK, trim = TRIM, rowLen = 2.4, pieceLen = 11 }
	-- Deep enough for two display tables with a carried box between them
	-- and the Robux table at the back: 25.6 studs (38.4 once scaled), up
	-- from 14 (BuildingArt.MeshStretch carries the same depth to the mesh),
	-- and 19.4 wide (29.1 scaled) so the tables take the bigger boxes.
	local HX, HZ, FLOOR, TOP = BuildingArt.ToolShedHalfWidth, BuildingArt.ToolShedHalfDepth, 0.5, 9

	plinth(model, CF(0, 0, 0), 2 * HX, 2 * HZ, FLOOR, rng, { left = true, right = true, back = true }, 3.2)
	for _, s in ipairs({ -1, 1 }) do
		stones(model, CF(s * 7, 0, -HZ), 4, FLOOR, 0.7, rng, 1.3, 2.3)
	end
	Kit.wedge(model, "Ramp", V3(10, FLOOR, 1.2), CF(0, FLOOR / 2, -HZ - 0.6), PLANK_DARK[1], MAT.WoodPlanks)

	-- Walls: red boards; the front opens on a 10-wide barn door.
	panel(model, CF(-HX, 0, 0) * ANG(0, PI / 2, 0), -HZ, HZ, FLOOR, TOP, 0.6, rng, red, 1.7)
	panel(model, CF(HX, 0, 0) * ANG(0, -PI / 2, 0), -HZ, HZ, FLOOR, TOP, 0.6, rng, red, 1.7)
	panel(model, CF(0, 0, HZ) * ANG(0, PI, 0), -HX, HX, FLOOR, TOP, 0.6, rng, red, 1.7)
	local front = CF(0, 0, -HZ)
	panel(model, front, -HX, -5, FLOOR, TOP, 0.6, rng, red, 1.7)
	panel(model, front, 5, HX, FLOOR, TOP, 0.6, rng, red, 1.7)
	panel(model, front, -5, 5, 7.6, TOP, 0.6, rng, red, 1.7)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			dBox(
				model,
				"Trim",
				V3(0.5, TOP - FLOOR, 0.5),
				CF(sx * (HX + 0.1), (TOP + FLOOR) / 2, sz * (HZ + 0.1)),
				TRIM
			)
		end
	end

	-- The gambrel roof: steep lower slopes, shallow upper ones.
	local KX, KY, RY = 5.6, 13, 14.8
	local length = 2 * HZ + 2
	local ridge = V3(0, RY, 0)
	for _, s in ipairs({ -1, 1 }) do
		local knee = V3(s * KX, KY, 0)
		local eave = V3(s * (HX + 0.3), TOP, 0)
		roofPlane(model, knee, Vector3.zAxis, (eave - knee).Unit, length, (eave - knee).Magnitude + 0.9, rng, roofStyle)
		roofPlane(
			model,
			ridge,
			Vector3.zAxis,
			(knee - ridge).Unit,
			length,
			(knee - ridge).Magnitude + 0.35,
			rng,
			roofStyle
		)
	end
	dBox(model, "RidgeCap", V3(0.75, 0.75, length + 0.3), CF(0, RY + 0.12, 0) * ANG(0, 0, PI / 4), TRIM)
	for _, z in ipairs({ -HZ, HZ }) do
		local wall = CF(0, 0, z) * (if z > 0 then ANG(0, PI, 0) else CFrame.identity)
		panel(model, wall, -KX, KX, TOP, KY, 0.6, rng, red, 1.7)
		for _, s in ipairs({ -1, 1 }) do
			Kit.wedge(
				model,
				"Gable",
				V3(0.6, KY - TOP, HX - KX),
				wall * CF(s * (KX + (HX - KX) / 2), (TOP + KY) / 2, 0) * ANG(0, -s * PI / 2, 0),
				red[2],
				MAT.WoodPlanks
			)
		end
		gable(model, wall * CF(0, KY, 0), 2 * KX, RY - KY, 0.6, red[1])
	end

	-- The doorway: a header beam (the leaf the shop hours recolour) and the
	-- track the two barn-door leaves slide on. The leaves, the blocker and
	-- the closed sign are added once the shop is scaled (ShopDoor).
	dBox(model, "DoorTrack", V3(2 * HX + 0.6, 0.3, 0.3), CF(0, 7.9, -HZ - 0.5), IRON, MAT.Metal)
	markHoursLeaf(dBox(model, "DoorHeader", V3(11, 0.5, 0.9), CF(0, 7.35, -HZ - 0.1), TRIM))
	for _, s in ipairs({ -1, 1 }) do
		dBox(model, "DoorJamb", V3(0.5, 7.1, 0.9), CF(s * 5.25, FLOOR + 3.55, -HZ - 0.1), TRIM)
	end

	-- The name sign up on the ridge (phase 12): a big board in the barn's
	-- red, framed in white like its doors, its frame clear of the ridge cap,
	-- on two posts standing on the roof, lit by two goosenecks (kept in from
	-- the east end, where the AXES marker floats). Then the hay hoist on the
	-- gable, windows, lanterns.
	local signW, signH = 17, 3.8
	-- (the sign stands where the stretched mesh sign stands: in front of the front wall by the old 0.4, stretched with the barn)
	local signY, signZ =
		RY + 0.5 + BuildingArt.SignRise + NAME_FRAME + signH / 2,
		-HZ * (TOOL_SHED_OLD_HALF_DEPTH + 0.4) / TOOL_SHED_OLD_HALF_DEPTH - 0.4
	nameSign(model, CF(0, signY, signZ), signW, signH, title, accent, TRIM, TRIM, false, 0.7)
	for _, s in ipairs({ -1, 1 }) do
		local roofY = RY - (RY - KY) * 4.6 / KX -- the upper roof, 4.6 out from the ridge
		local h = signY - signH / 2 - roofY + 0.5
		dBox(model, "SignPost", V3(0.5, h, 0.5), CF(s * 4.6, roofY - 0.5 + h / 2, signZ + 0.5), TIMBER)
		gooseneck(model, CF(s * 5.2, signY + (signH + NAME_FRAME) / 2, signZ - 0.2))
	end
	dBox(model, "HoistBeam", V3(0.7, 0.7, 2.8), CF(0, 13.45, -HZ - 1.1), TIMBER)
	dCyl(model, "Pulley", 0.3, 0.8, CF(0, 12.85, -HZ - 2.2), IRON, MAT.Metal)
	dBox(model, "Rope", V3(0.12, 0.7, 0.12), CF(0, 12.2, -HZ - 2.55), ROPE, MAT.Fabric)
	dBox(model, "Hook", V3(0.35, 0.35, 0.35), CF(0, 11.75, -HZ - 2.55), IRON, MAT.Metal)
	for _, s in ipairs({ -1, 1 }) do
		window(model, CF(s * (HX + 0.3), 5.2, 0) * ANG(0, -s * PI / 2, 0), 2.6, 2.6, TRIM, nil, nil)
		hangingLantern(model, V3(s * 3.8, 7.6, -HZ + 0.1), 0.6, 0.85)
	end
	dBox(model, "TieBeam", V3(2 * HX - 0.6, 0.8, 0.8), CF(0, TOP - 0.4, 3.6), TIMBER)
	-- The counter stands at the back (final studs: BuildingArt.ToolShedCounterZ),
	-- the keeper behind it and the Robux table behind her, against the far wall.
	local CZ = BuildingArt.ToolShedCounterZ / BuildingArt.Scale.ToolShed
	hangingLantern(model, V3(0, TOP - 0.8, CZ - 2.2), 0.9, 0.9)

	-- Inside: the counter, the axe rack (the display tables go in once the
	-- shop is scaled).
	Kit.part(model, "Counter", V3(9, 3, 2), CF(0, FLOOR + 1.5, CZ), PLANK_DARK[1], MAT.WoodPlanks)
	dBox(model, "CounterTop", V3(9.6, 0.3, 2.6), CF(0, FLOOR + 3.15, CZ), PLANK[4])
	for _, x in ipairs({ -3, 0, 3 }) do
		dBox(model, "CounterTrim", V3(0.3, 2.7, 0.14), CF(x, FLOOR + 1.45, CZ - 1.07), PLANK_DARK[3])
	end
	register(model, CF(2.7, FLOOR + 3.3, CZ + 0.2))
	ledger(model, CF(-2.5, FLOOR + 3.3, CZ - 0.2))
	-- (The axe rack on the back wall, with every axe's real model, is built by
	-- ShopInterior once the shop is scaled.)
	-- (The workbench and the barrel of handles that stood along the side
	-- walls are gone: the display tables (displayTables) and the aisle
	-- between them need that floor.)

	-- Out front: the grindstone and the chopping block; firewood stacked by
	-- the east wall (all of it solid).
	grindstone(model, CF(-7.6, 0, -HZ - 2.2))
	choppingBlock(model, CF(7.6, 0, -HZ - 2.2), rng)
	for row = 0, 1 do
		for i = 0, 1 - row do
			local z = -2 + (i - (1 - row) / 2) * 1.55
			log(model, CF(HX + 1.25, 0.75 + row * 1.32, z), 2, 1.5, rng, 1, true)
		end
	end
end

-- The Dealership: a showroom hall (built at its real size, scale 1: see
-- BuildingArt.Scale) on the old display lot, with a lobby at the west end
-- (the counter, the paint swatches, the door), and every truck and trailer
-- on a plinth inside, behind its box (DealershipLot builds those and
-- MapBuilder stands them in the hall). Nothing is parked outside. The
-- lobby door is 14 wide and 11.5 tall. Its extents come from
-- DealershipLot.Hall so the hall is always as big as the bays need.
local function dealership(model: Model, title: string, accent: Color3)
	local hall = DealershipLot.Hall()
	local hx, hz = hall.innerW / 2, hall.innerD / 2
	local cream = hex("#EEDFC3")
	local dark = Kit.shade(accent, -0.35)
	local FLOOR, H, T = 0.4, 15, 0.8
	local doorX0 = -hx + 0.75
	local doorX1 = doorX0 + 15
	local doorCx = (doorX0 + doorX1) / 2
	local OPEN = 11.9 -- top of the door opening

	Kit.part(model, "Slab", V3(2 * hx + 2 * T, FLOOR, 2 * hz + 2 * T), CF(0, FLOOR / 2, 0), CONCRETE, MAT.Concrete)
	local function wall(name: string, x0: number, x1: number, y0: number, y1: number, z: number)
		return Kit.part(model, name, V3(x1 - x0, y1 - y0, T), CF((x0 + x1) / 2, (y0 + y1) / 2, z), cream, MAT.Plaster)
	end
	local function side(name: string, x: number)
		return Kit.part(model, name, V3(T, H - FLOOR, 2 * hz + T), CF(x, (H + FLOOR) / 2, 0), cream, MAT.Plaster)
	end
	side("Wall", -hx - T / 2)
	-- A glass band (y 6 to 14.4) runs along the front and down the east wall:
	-- the showroom windows. It is see-through (the view from the spawn to the
	-- lighthouse crosses the east end of the hall), solid glass you cannot walk
	-- through, with solid wall below and above it.
	local GLASS_LO, GLASS_HI = 6, 14.4
	local glass = Color3.fromRGB(170, 205, 225)
	local function glassBand(name: string, size: Vector3, cf: CFrame)
		local g = Kit.part(model, name, size, cf, glass, MAT.Glass)
		g.Transparency = 0.92
		g.CastShadow = false
		return g
	end
	local eastZ0, eastLen = -hz - T, 2 * hz + 2 * T
	Kit.part(
		model,
		"Wall",
		V3(T, GLASS_LO - FLOOR, eastLen),
		CF(hx + T / 2, (GLASS_LO + FLOOR) / 2, 0),
		cream,
		MAT.Plaster
	)
	Kit.part(model, "Wall", V3(T, H - GLASS_HI, eastLen), CF(hx + T / 2, (H + GLASS_HI) / 2, 0), cream, MAT.Plaster)
	glassBand(
		"ShowroomGlass",
		V3(T, GLASS_HI - GLASS_LO, eastLen),
		CF(hx + T / 2, (GLASS_HI + GLASS_LO) / 2, eastZ0 + eastLen / 2)
	)
	wall("Wall", -hx - T, hx + T, FLOOR, H, hz + T / 2)
	-- The front: the lobby door at the west end, windows along the rest.
	wall("Wall", doorX1, hx + T, FLOOR, GLASS_LO, -hz - T / 2)
	wall("Wall", doorX1, hx + T, GLASS_HI, H, -hz - T / 2)
	glassBand(
		"ShowroomGlass",
		V3(hx + T - doorX1, GLASS_HI - GLASS_LO, T),
		CF((doorX1 + hx + T) / 2, (GLASS_HI + GLASS_LO) / 2, -hz - T / 2)
	)
	wall("Wall", -hx - T, doorX0, FLOOR, H, -hz - T / 2)
	wall("Wall", doorX0, doorX1, OPEN, H, -hz - T / 2)
	markHoursLeaf(
		dBox(model, "DoorHeader", V3(15.8, 0.5, 1.1), CF(doorCx, OPEN - 0.25, -hz - T / 2 - 0.2), dark, MAT.Metal)
	)
	for _, x in ipairs({ doorX0 - 0.4, doorX1 + 0.4 }) do
		dBox(
			model,
			"DoorJamb",
			V3(0.7, OPEN - FLOOR, 1.1),
			CF(x, (OPEN + FLOOR) / 2, -hz - T / 2 - 0.2),
			dark,
			MAT.Metal
		)
	end
	-- A stone footing round the foot of every wall, and the accent stripe.
	local foot = Kit.shade(CONCRETE, -0.2)
	dBox(model, "Footing", V3(2 * hx + 2 * T + 0.6, 1.4, 0.5), CF(0, FLOOR + 0.7, hz + T + 0.15), foot, MAT.Slate)
	dBox(
		model,
		"Footing",
		V3(hx - doorX1 + T + 0.6, 1.4, 0.5),
		CF((doorX1 + hx) / 2, FLOOR + 0.7, -hz - T - 0.15),
		foot,
		MAT.Slate
	)
	for _, s in ipairs({ -1, 1 }) do
		dBox(model, "Footing", V3(0.5, 1.4, 2 * hz + 2 * T), CF(s * (hx + T + 0.15), FLOOR + 0.7, 0), foot, MAT.Slate)
	end
	dBox(model, "Stripe", V3(2 * hx + 2 * T + 0.4, 0.7, 0.3), CF(0, H - 1.6, -hz - T - 0.1), accent, MAT.SmoothPlastic)
	dBox(model, "Stripe", V3(2 * hx + 2 * T + 0.4, 0.7, 0.3), CF(0, H - 1.6, hz + T + 0.1), accent, MAT.SmoothPlastic)
	-- Roof: a flat slab. No skylight: the hall stands north of the spawn's line
	-- to the lighthouse (z 96 at its front, the line is south of that along its
	-- whole length), so the roof can be solid.
	local roofW = 2 * hx + 2 * T + 1
	Kit.part(model, "Roof", V3(roofW, 0.8, 2 * hz + 2 * T + 0.2), CF(0, H + 0.4, 0), TIN_ROOF[1], MAT.Metal)
	-- The name sign over the lobby door, lit by two goosenecks, and a second
	-- board for the trade over the windows.
	local signW, signH = 24, 4.2
	-- Raised on posts, its bottom edge SignRise above the roof (ShopSignClearance spec).
	local signY, signZ = H + 0.8 + BuildingArt.SignRise + NAME_FRAME + signH / 2, -hz - T - 0.1
	nameSign(model, CF(doorCx + 4, signY, signZ), signW, signH, title, accent, TRIM, TRIM, false)
	for _, s in ipairs({ -1, 1 }) do
		gooseneck(model, CF(doorCx + 4 + s * 7, signY + (signH + NAME_FRAME) / 2, signZ - 0.2))
		local postH = BuildingArt.SignRise + 0.4
		dBox(
			model,
			"SignPost",
			V3(0.5, postH, 0.5),
			CF(doorCx + 4 + s * 10, H + 0.8 + postH / 2, signZ + 0.2),
			dark,
			MAT.Metal
		)
	end
	signBoard(
		model,
		"OfficeSign",
		CF(doorCx + 36, 12.2, -hz - T - 0.55),
		24,
		1.6,
		"TRUCKS & TRAILERS",
		TRIM,
		dark,
		dark,
		false
	)

	-- The lobby (the west column): the counter against the back wall, facing
	-- the door, the keeper behind it, the paint swatches on the wall above.
	local counterX, counterZ = -hx + BuildingArt.DealerLobbyCounterX, hz - BuildingArt.DealerCounterBack
	Kit.part(model, "Counter", V3(8, 3, 1.8), CF(counterX, FLOOR + 1.5, counterZ), dark, MAT.WoodPlanks)
	dBox(model, "CounterTop", V3(8.6, 0.3, 2.3), CF(counterX, FLOOR + 3.15, counterZ), PLANK[4])
	register(model, CF(counterX + 2.2, FLOOR + 3.3, counterZ - 0.1))
	ledger(model, CF(counterX - 2.2, FLOOR + 3.3, counterZ - 0.1))
	dBox(model, "SwatchBoard", V3(11, 3.2, 0.2), CF(counterX, 7.6, hz - 0.1), SIGN_BOARD)
	local trucks = ItemCatalog.TruckList()
	for i, truck in ipairs(trucks) do
		local sx = counterX + (i - (#trucks + 1) / 2) * 1.8
		dBox(model, "PaintSwatch", V3(1.4, 1.8, 0.14), CF(sx, 7.6, hz - 0.28), hex(truck.look.color), MAT.SmoothPlastic)
	end
	Kit.part(model, "ToolChest", V3(2.4, 2.6, 1.3), CF(-hx + 2.4, FLOOR + 1.3, hz - 2), hex("#C8402F"), MAT.Metal)
	for i = 1, 3 do
		dBox(model, "Drawer", V3(2.2, 0.12, 0.1), CF(-hx + 2.4, FLOOR + 0.6 * i, hz - 2.7), IRON, MAT.Metal)
	end
	local rng = Kit.rng(512)
	-- A tyre stack (every tyre solid), by the toolchest.
	for i = 1, 4 do
		local tyre =
			Kit.post(model, "Tyre", V3(-hx + 22, FLOOR + (i - 1) * 0.78, hz - 2.4), 0.76, 2.3, TYRE, MAT.Rubber)
		if i > 1 then
			tyre.CastShadow = false
		end
	end
	barrel(model, CF(-hx + 19.4, FLOOR, hz - 2), rng, true, accent)
	barrel(model, CF(-hx + 24.4, FLOOR, hz - 2.4), rng, true, hex("#C8402F"))
end

-- General Store (still the HearthAndHome model): 33 x 26 at design size,
-- 49.5 x 39 once scaled (it was 32 x 24). The counter sits by the open door
-- so you can read it from the entrance, and the door is 10 wide (15 once
-- scaled) so a carried box walks in. The shelf units and the islands the
-- boxes stand on are added once the shop is scaled (ShopInterior), with
-- the aisle signs, the ceiling beams and the lamps. Each price board hangs
-- on the back wall facing the door, at least 4 studs wide, with one sample
-- of that item on the ledge under it; its text comes from the shop's own
-- prices (StoreStock), never typed here.
BuildingArt.HearthHalfWidth = 16.5
BuildingArt.HearthHalfDepth = 14.5
BuildingArt.HearthCounterZ = 15.3 -- the counter's middle, final studs from the shop's middle

local function hearthAndHome(model: Model, title: string, accent: Color3)
	local plaster = hex("#F0E2C6")
	local wood = Kit.shade(accent, -0.32)
	local HX, HZ, FLOOR, TOP = BuildingArt.HearthHalfWidth, BuildingArt.HearthHalfDepth, 0.4, 10
	local mid = (FLOOR + TOP) / 2
	local wallH = TOP - FLOOR
	local DOOR_HALF, DOOR_H = 5, 8

	Kit.part(model, "Floor", V3(2 * HX, FLOOR, 2 * HZ), CF(0, FLOOR / 2, 0), PLANK[2], MAT.WoodPlanks)
	local function wall(cf: CFrame, w: number, h: number): Part
		return Kit.part(model, "Wall", V3(w, h, 0.6), cf, plaster, MAT.Plaster)
	end
	wall(CF(-HX, mid, 0) * ANG(0, PI / 2, 0), 2 * HZ, wallH)
	wall(CF(HX, mid, 0) * ANG(0, PI / 2, 0), 2 * HZ, wallH)
	wall(CF(0, mid, HZ), 2 * HX, wallH)
	-- Front opens on a 10-stud door, tall enough to see the counter. The
	-- header beam is the leaf the hours lock recolours; the two door leaves
	-- are added once the shop is scaled (ShopDoor).
	local sideW = HX - DOOR_HALF
	wall(CF(-(DOOR_HALF + sideW / 2), mid, -HZ), sideW, wallH)
	wall(CF(DOOR_HALF + sideW / 2, mid, -HZ), sideW, wallH)
	wall(CF(0, (DOOR_H + TOP) / 2, -HZ), 2 * DOOR_HALF, TOP - DOOR_H)
	markHoursLeaf(dBox(model, "DoorHeader", V3(2 * DOOR_HALF + 1, 0.5, 0.9), CF(0, DOOR_H - 0.25, -HZ - 0.15), TRIM))
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"DoorJamb",
			V3(0.5, DOOR_H - FLOOR, 0.9),
			CF(s * (DOOR_HALF + 0.25), (DOOR_H + FLOOR) / 2, -HZ - 0.15),
			TRIM
		)
	end
	Kit.part(model, "Roof", V3(2 * HX + 2, 0.5, 2 * HZ + 2), CF(0, TOP + 0.4, 0), SLATE_ROOF[1], MAT.Slate)

	-- Above the roof, and no further south than the roof's overhang, so the
	-- board doesn't hang past the front or sit inside the roof.
	local signW, signH = 20, 3
	local signY, signZ = TOP + 0.65 + BuildingArt.SignRise + NAME_FRAME + signH / 2, -HZ - 0.6
	nameSign(model, CF(0, signY, signZ), signW, signH, title, hex("#3E6A3A"), wood, TRIM, false)
	for _, x in ipairs({ -5, 5 }) do
		gooseneck(model, CF(x, signY + (signH + NAME_FRAME) / 2, signZ - 0.2))
		-- Two posts carry the board up off the roof.
		local top = signY - signH / 2 - NAME_FRAME
		local base = TOP + 0.65
		dBox(
			model,
			"SignPost",
			V3(0.4, top - base + 0.3, 0.4),
			CF(x * 1.6, (top + base - 0.3) / 2 + 0.3, signZ + 0.1),
			wood
		)
	end

	-- The counter stands at the back (customer side faces -Z, the entrance),
	-- the keeper behind it; the shelf units stop short of it.
	local counterZ = BuildingArt.HearthCounterZ / BuildingArt.Scale.HearthAndHome
	Kit.part(model, "Counter", V3(8, 3, 1.8), CF(0, FLOOR + 1.5, counterZ), Kit.shade(accent, -0.1), MAT.WoodPlanks)
	dBox(model, "CounterTop", V3(8.6, 0.3, 2.3), CF(0, FLOOR + 3.15, counterZ), PLANK[4])
	register(model, CF(2.2, FLOOR + 3.3, counterZ + 0.2))
	ledger(model, CF(-2.2, FLOOR + 3.3, counterZ - 0.1))

	-- Prices hang on the back wall, facing the door, each above a sample
	-- of that item on the ledge. Wide enough to read from the entrance.
	local function sample(x: number, y: number, z: number, kind: string)
		local top = y + 0.16
		local function show(size: Vector3, cf: CFrame, color: Color3, surface: Enum.Material)
			local p = Kit.part(model, "Display", size, cf, color, surface)
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
		if kind == "fence" then
			show(V3(0.35, 1.2, 0.35), CF(x - 0.5, top + 0.6, z), wood, MAT.Wood)
			show(V3(1.4, 0.16, 0.16), CF(x + 0.25, top + 0.8, z), hex("#C4B49A"), MAT.Wood)
		elseif kind == "shed" then
			show(V3(1.15, 0.8, 0.9), CF(x, top + 0.4, z), hex("#8C6A45"), MAT.WoodPlanks)
			show(V3(1.35, 0.14, 1.05), CF(x, top + 0.87, z), SLATE_ROOF[1], MAT.Slate)
		elseif kind == "lantern" then
			show(V3(0.18, 0.95, 0.18), CF(x, top + 0.48, z), wood, MAT.Wood)
			show(V3(0.48, 0.36, 0.48), CF(x, top + 1.05, z), hex("#F6D58A"), MAT.Neon)
		else
			show(V3(0.16, 1.15, 0.16), CF(x, top + 0.5, z) * ANG(0, 0, 0.7), wood, MAT.Wood)
			show(V3(0.6, 0.3, 0.12), CF(x + 0.22, top + 0.95, z), hex("#C0C6CE"), MAT.Metal)
		end
	end
	local ledge = Kit.part(model, "Ledge", V3(30, 0.22, 1.5), CF(0, 3.35, HZ - 1.45), wood, MAT.Wood)
	ledge.CanQuery = false
	local function offerText(kind: string, itemId: string): string
		local slot = StoreStock.Find(kind, itemId)
		if slot == nil then
			return string.upper(itemId)
		end
		local price = StoreStock.UnitPrice(kind, itemId, slot.limited, 2)
		return string.upper(slot.displayName) .. "\n" .. (if price then Util.formatCash(price) else "")
	end
	local offers = {
		{ x = -11.4, label = offerText("Blueprint", "WoodSign"), kind = "fence" },
		{ x = -3.8, label = offerText("Blueprint", "Shed"), kind = "shed" },
		{ x = 3.8, label = offerText("Gear", "Lantern"), kind = "lantern" },
		{ x = 11.4, label = offerText("Gear", "Flashlight"), kind = "axe" },
	}
	for _, offer in ipairs(offers) do
		local board =
			Kit.part(model, "PriceTag", V3(5.6, 2.3, 0.16), CF(offer.x, 6.15, HZ - 0.58), hex("#3E2A18"), MAT.Wood)
		board.CanCollide = false
		board.CanQuery = false
		board.CanTouch = false
		Kit.signText(board, offer.label, TRIM, { Enum.NormalId.Front, Enum.NormalId.Back })
		sample(offer.x, 3.35, HZ - 1.65, offer.kind)
	end
end

-- Shelf slots are attachments on the counter (they are not parts, so the
-- shop stays inside its part budget). The store zone is attributes in
-- build space; BoxService turns them into a world volume with the pivot
-- the model had while it still sat at the origin. The Robux shelf's slots
-- are "RobuxSlot" attachments, so the cash shelves' count stays theirs.
local function placeShelfSlots(model: Model, kind: string, scale: number)
	-- Slots are in final studs; only the zone (design size) takes the scale.
	local host = model:FindFirstChild("Counter")
	if not host or not host:IsA("BasePart") then
		return
	end
	local function attach(name: string, slotId: string, x: number, y: number, z: number)
		local at = Vector3.new(x, y, z)
		local att = Instance.new("Attachment")
		att.Name = name
		att:SetAttribute("SlotId", slotId)
		att.Position = host.CFrame:PointToObjectSpace(at)
		att.Parent = host
	end
	for _, place in ipairs(StoreStock.Placements(kind)) do
		attach("ShelfSlot", place.slotId, place.x, place.y, place.z)
	end
	if kind == "ToolShed" then
		for _, place in ipairs(RobuxShelf.Placements()) do
			attach("RobuxSlot", place.slotId, place.x, place.y, place.z)
		end
	end
	local zone = StoreStock.Zone(kind)
	local pivot = model:GetPivot().Position
	model:SetAttribute("BuildPivotX", pivot.X)
	model:SetAttribute("BuildPivotY", pivot.Y)
	model:SetAttribute("BuildPivotZ", pivot.Z)
	if zone then
		model:SetAttribute("ZoneCenterX", zone.center.X)
		model:SetAttribute("ZoneCenterY", zone.center.Y)
		model:SetAttribute("ZoneCenterZ", zone.center.Z)
		model:SetAttribute("ZoneSizeX", zone.size.X * scale)
		model:SetAttribute("ZoneSizeY", zone.size.Y)
		model:SetAttribute("ZoneSizeZ", zone.size.Z * scale)
	end
end

-- Colour and transparency only. The leaf's first colour is remembered so an
-- open door can come back. No parts are added or moved.
function BuildingArt.PaintDoor(model: Instance, locked: boolean)
	if type((model :: any).GetDescendants) ~= "function" then
		return
	end
	local tint = Color3.fromRGB(BuildingArt.LockedDoorRed, BuildingArt.LockedDoorGreen, BuildingArt.LockedDoorBlue)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("HoursLeaf") == true then
			if d:GetAttribute("HoursBaseR") == nil then
				d:SetAttribute("HoursBaseR", d.Color.R)
				d:SetAttribute("HoursBaseG", d.Color.G)
				d:SetAttribute("HoursBaseB", d.Color.B)
				d:SetAttribute("HoursBaseT", d.Transparency)
			end
			if locked then
				d.Color = tint
				d.Transparency = BuildingArt.LockedDoorTransparency
			else
				local r = d:GetAttribute("HoursBaseR")
				local g = d:GetAttribute("HoursBaseG")
				local b = d:GetAttribute("HoursBaseB")
				local t = d:GetAttribute("HoursBaseT")
				if type(r) == "number" and type(g) == "number" and type(b) == "number" then
					d.Color = Color3.new(r, g, b)
				end
				if type(t) == "number" then
					d.Transparency = t
				end
			end
		end
	end
end

-- A 4 x 2 board on the front-most hours leaf, added after the shop is
-- scaled so the stud size stays put. Text is filled later by
-- ShopHoursLogic.WriteSigns. Not parented to the name Sign: fitNameSign
-- would overwrite that board's pixels per stud.
local function addHoursBoard(model: Model, shopId: string)
	local host: BasePart? = nil
	local hostZ = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("HoursLeaf") == true and d.CFrame.Position.Z < hostZ then
			host = d
			hostZ = d.CFrame.Position.Z
		end
	end
	if host == nil then
		return
	end
	local w = ShopHoursLogic.SignWidthStuds
	local h = ShopHoursLogic.SignHeightStuds
	local depth = ShopHoursLogic.SignDepthStuds
	local at = host.CFrame.Position
	local top = at.Y + host.Size.Y / 2
	local y = top + h / 2
	local clear = ShopHoursLogic.SignClearY + h / 2
	if y < clear then
		y = clear
	end
	local board = Kit.part(model, "HoursBoard", V3(w, h, depth), CF(at.X, y, at.Z), SIGN_BOARD, MAT.Wood)
	Kit.decor(board)
	board:SetAttribute("ShopId", shopId)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "HoursGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ShopHoursLogic.SignPixelsPerStud
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Hours"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = SIGN_INK
		label.Text = ""
		label.Parent = gui
	end
end

-- The final-stud frame the interior is built in (see ShopInterior.Frame),
-- from the same design numbers the shop is built with.
function BuildingArt.InteriorFrame(kind: string, s: number): { frame: ShopInterior.Frame, extra: { number }? }
	if kind == "ToolShed" then
		return {
			frame = {
				floorTop = 0.5 * s,
				halfW = BuildingArt.ToolShedHalfWidth * s - 0.6,
				halfD = BuildingArt.ToolShedHalfDepth * s - 0.45,
				ceilY = 9 * s,
			},
		}
	elseif kind == "Dealership" then
		local hall = DealershipLot.Hall()
		local hx, hz = hall.innerW / 2, hall.innerD / 2
		return {
			frame = { floorTop = 0.4, halfW = hx - 0.4, halfD = hz - 0.4, ceilY = 15 },
			extra = { -hx + 0.4, hx - 0.4, -hz + 0.4, hz - 0.4 },
		}
	end
	return {
		frame = {
			floorTop = 0.4 * s,
			halfW = BuildingArt.HearthHalfWidth * s - 0.45,
			halfD = BuildingArt.HearthHalfDepth * s - 0.45,
			ceilY = 10 * s - 0.4,
		},
	}
end

-- The Dealership's bays in the hall's own space (origin at the hall's middle),
-- for the lights over them and the aisle stripes between the rows.
function BuildingArt.DealershipBays(): { ShopInterior.Bay }
	local hall = DealershipLot.Hall()
	local layout = DealershipLot.Layout()
	local out: { ShopInterior.Bay } = {}
	for _, bay in ipairs(layout.bays) do
		local aisleSide = if bay.row == 1 then 1 else -1
		table.insert(out, {
			x = DealershipLot.OriginX + layout.width / 2 + bay.x - hall.cx,
			z = DealershipLot.OriginZ + bay.vz - hall.cz,
			row = bay.row,
			aisleZ = DealershipLot.OriginZ + bay.z + aisleSide * bay.depth / 2 - hall.cz,
		})
	end
	return out
end

-- What ShopFacade needs to dress a shop's street side, in final studs.
function BuildingArt.FacadeSpec(kind: string, s: number, accent: Color3): ShopFacade.Spec
	if kind == "ToolShed" then
		return {
			kind = kind,
			halfW = BuildingArt.ToolShedHalfWidth * s,
			frontZ = -(BuildingArt.ToolShedHalfDepth * s + 0.45),
			doorCx = 0,
			doorHalf = 5 * s,
			doorTop = 7.1 * s,
			wallTop = 9 * s,
			roofTop = 14.8 * s + 0.75,
			groundY = 0.5 * s,
			accent = accent,
		}
	elseif kind == "Dealership" then
		local hall = DealershipLot.Hall()
		local hx, hz = hall.innerW / 2, hall.innerD / 2
		return {
			kind = kind,
			halfW = hx,
			frontZ = -hz - 0.8,
			doorCx = -hx + 0.75 + 7.5,
			doorHalf = 7.5,
			doorTop = 11.9,
			wallTop = 15,
			roofTop = 15.8,
			groundY = 0.4,
			accent = accent,
		}
	end
	return {
		kind = kind,
		halfW = BuildingArt.HearthHalfWidth * s,
		frontZ = -(BuildingArt.HearthHalfDepth * s + 0.45),
		doorCx = 0,
		doorHalf = 5 * s,
		doorTop = 7.5 * s,
		wallTop = 10 * s,
		roofTop = 10.65 * s,
		groundY = 0.4 * s,
		accent = accent,
	}
end

-- The front door of a shop in final studs (see ShopDoor.Spec): the opening
-- is the gap in the front wall, the plane is where the leaves stand.
function BuildingArt.DoorSpec(kind: string, s: number, accent: Color3): ShopDoor.Spec
	if kind == "ToolShed" then
		return {
			style = "slide",
			x0 = -5 * s,
			x1 = 5 * s,
			y0 = 0.5 * s,
			y1 = 7.1 * s,
			z = -(BuildingArt.ToolShedHalfDepth + 0.5) * s,
			color = Kit.shade(accent, -0.2),
			trim = TRIM,
		}
	elseif kind == "Dealership" then
		local hall = DealershipLot.Hall()
		local hx, hz = hall.innerW / 2, hall.innerD / 2
		local x0 = -hx + 0.75
		return {
			style = "roll",
			x0 = x0,
			x1 = x0 + 15,
			y0 = 0.4,
			y1 = 11.65,
			z = -hz + 0.5,
			color = STEEL_DARK,
			trim = Kit.shade(accent, -0.35),
		}
	end
	return {
		style = "swing",
		x0 = -5 * s,
		x1 = 5 * s,
		y0 = 0.4 * s,
		y1 = 7.5 * s,
		z = -(BuildingArt.HearthHalfDepth + 0.15) * s,
		color = Kit.shade(accent, -0.05),
		trim = Kit.shade(accent, -0.4),
	}
end

-- A shop: about 18 x 14 studs, its front (-Z) open on the counter. `kind`
-- is "ToolShed", "Dealership" or "HearthAndHome" (anything else builds a
-- Hearth & Home style store); `title` goes on the sign; `accent` is the
-- shop's colour (the Tool Shed's walls, the Dealership's paint, Hearth &
-- Home's timbers). Named parts:
--   "Counter": a direct child, axis-aligned with the model, collides; its
--     -Z face is the customer side (MapBuilder puts the ShopPoint there,
--     and the floor in front of it is clear to the open front).
-- `scale` (default BuildingArt.Scale[kind], else 1) scales the shop about
-- its origin, all but the counter: it, its top and what stands on it keep
-- their size, at the same height over the (raised) floor, so it stays
-- waist high and the keeper behind it shows.
function BuildingArt.Shop(kind: string, title: string, accent: Color3, scale: number?): Model
	local model = Kit.model(kind)
	if kind == "ToolShed" then
		toolShed(model, title, accent)
	elseif kind == "Dealership" then
		dealership(model, title, accent)
	else
		hearthAndHome(model, title, accent)
	end
	local s = scale or BuildingArt.Scale[kind] or 1
	local counter = model:FindFirstChild("Counter")
	local rigid: { [BasePart]: Vector3 } = {}
	if counter and counter:IsA("BasePart") then
		-- The counter group: every part whose middle is over the counter
		-- (half a stud round it) and from its bottom to 2 studs over its top.
		local ccf, size = counter.CFrame, counter.Size
		local bottom = ccf.Position.Y - size.Y / 2
		local anchor = Vector3.new(ccf.Position.X, bottom, ccf.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local p = ccf:PointToObjectSpace(d.CFrame.Position)
				local y = d.CFrame.Position.Y
				if
					math.abs(p.X) <= size.X / 2 + 0.5
					and math.abs(p.Z) <= size.Z / 2 + 0.5
					and y >= bottom
					and y <= bottom + size.Y + 2
				then
					rigid[d] = anchor
				end
			end
		end
	end
	Kit.scaleModel(model, s, rigid)
	local sign = model:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		fitNameSign(sign)
	end
	addHoursBoard(model, kind)
	-- Tool Shed, Dealership, and Hearth & Home meshes are already 1.5x.
	if kind ~= "Dealership" then -- the hall has no uploaded mesh
		TownMeshes.Dress(model, TownModels.ShopAsset(kind), { scale = BuildingArt.MeshStretch(kind) })
	end
	if kind == "ToolShed" or kind == "HearthAndHome" then
		placeShelfSlots(model, kind, s)
	end
	local frame = BuildingArt.InteriorFrame(kind, s)
	ShopInterior.Add(
		model,
		kind,
		frame.frame,
		frame.extra,
		if kind == "Dealership" then BuildingArt.DealershipBays() else nil
	)
	ShopDoor.Add(model, BuildingArt.DoorSpec(kind, s, accent))
	ShopFacade.Add(model, BuildingArt.FacadeSpec(kind, s, accent))
	return model
end

---------------------------------------------------------------------------
-- The gondola station
---------------------------------------------------------------------------

-- A gondola station: a stone platform under a timber A-frame with a
-- shingled roof and the cable's bullwheel overhead. The cabin hangs at the
-- platform's middle and leaves through the open back gable (+Z): turn the
-- model so +Z points along the cable. Steps up on the front (-Z).
-- Named parts: "Platform" (the PrimaryPart: 10 x 1 x 10, its top at
-- y = 1, collides).
function BuildingArt.GondolaStation(): Model
	local model = Kit.model("GondolaStation")
	local rng = Kit.rng(2207)
	local roofStyle: RoofStyle = { colors = SHINGLE, deck = ROOF_DECK, trim = TIMBER, rowLen = 2, pieceLen = 4.6 }
	local platform = Kit.part(model, "Platform", V3(10, 1, 10), CF(0, 0.5, 0), hex("#A39C92"), MAT.Slate)
	model.PrimaryPart = platform
	for _, f in ipairs({
		CF(0, 0, 5) * ANG(0, PI, 0),
		CF(-5, 0, 0) * ANG(0, PI / 2, 0),
		CF(5, 0, 0) * ANG(0, -PI / 2, 0),
	}) do
		stones(model, f, 10.4, 0.95, 0.6, rng, 1.8, 2.8)
	end
	Kit.wedge(model, "Steps", V3(6, 1, 1.8), CF(0, 0.5, -5.9), STONE[2], MAT.Slate)

	local PX, PZ, TOP, RISE = 5.6, 4.4, 10.5, 3.6
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.part(model, "Post", V3(0.9, TOP, 0.9), CF(sx * PX, TOP / 2, sz * PZ), TIMBER, MAT.Wood)
			dBox(model, "Footing", V3(1.6, 0.8, 1.6), CF(sx * PX, 0.4, sz * PZ), STONE[1], MAT.Slate)
			dBeam(
				model,
				"Brace",
				V3(sx * PX, TOP - 3, sz * (PZ - 0.1)),
				V3(sx * PX, TOP - 0.7, sz * (PZ - 2.3)),
				0.5,
				0.5,
				TIMBER
			)
		end
		dBox(model, "Plate", V3(1, 0.9, 2 * PZ + 1), CF(sx * PX, TOP - 0.45, 0), TIMBER)
		-- a railing along the platform's side
		for _, z in ipairs({ -3.6, 0, 3.6 }) do
			dBox(model, "RailPost", V3(0.35, 3, 0.35), CF(sx * 4.6, 2.5, z), TIMBER_LIGHT)
		end
		Kit.part(model, "Rail", V3(0.3, 0.3, 7.6), CF(sx * 4.6, 3.85, 0), TIMBER_LIGHT, MAT.Wood)
		dBox(model, "Rail", V3(0.25, 0.25, 7.6), CF(sx * 4.6, 2.5, 0), TIMBER_LIGHT)
		wallLantern(model, CF(sx * PX, 7.6, -PZ - 0.45), 0.9)
	end
	dBox(model, "TieBeam", V3(2 * PX + 1, 0.9, 1), CF(0, TOP - 0.45, -PZ), TIMBER)
	gable(model, CF(0, TOP, -PZ), 2 * PX, RISE, 0.5, PLANK[2])
	battens(model, CF(0, TOP, -PZ), 2 * PX, RISE, 0.5, 1.6, PLANK_DARK[1])
	gableRoof(model, CF(0, TOP, -0.55) * ANG(0, PI / 2, 0), 2 * PZ + 2.1, 2 * PX + 0.9, RISE, 1.2, rng, roofStyle)

	-- The bullwheel: a ring in front of the cabin's hanging point, on a
	-- shaft from a bearer beam.
	local wheelY, wheelZ, r = 8.9, -3.4, 3.4
	for i = 0, 7 do
		local a0, a1 = i / 8 * PI * 2, (i + 1) / 8 * PI * 2
		dBeam(
			model,
			"Bullwheel",
			V3(math.cos(a0) * r, wheelY, wheelZ + math.sin(a0) * r),
			V3(math.cos(a1) * r, wheelY, wheelZ + math.sin(a1) * r),
			0.7,
			0.8,
			hex("#8E3426"),
			MAT.Metal
		)
	end
	for _, a in ipairs({ 0, PI / 2 }) do
		local d = V3(math.cos(a), 0, math.sin(a)) * r
		dBeam(model, "Spoke", V3(0, wheelY, wheelZ) - d, V3(0, wheelY, wheelZ) + d, 0.3, 0.3, STEEL_DARK, MAT.Metal)
	end
	dec(Kit.post(model, "Hub", V3(0, wheelY - 0.45, wheelZ), 0.9, 1.2, IRON, MAT.Metal))
	dBox(model, "Shaft", V3(0.45, TOP - wheelY, 0.45), CF(0, (TOP + wheelY) / 2, wheelZ), STEEL_DARK, MAT.Metal)
	dBox(model, "Bearer", V3(2 * PX, 0.8, 0.8), CF(0, TOP - 0.4, wheelZ), TIMBER)

	-- The crest sign and a ticket lectern with a bell.
	signBoard(
		model,
		"Sign",
		CF(0, TOP + RISE + 1.4, -PZ - 1.3),
		6.4,
		1.5,
		"GONDOLA",
		SIGN_BOARD,
		TIMBER_LIGHT,
		SIGN_INK,
		true
	)
	Kit.solid(dBox(model, "Lectern", V3(1.2, 2.6, 0.9), CF(3.2, 2.3, -3.6), TIMBER_LIGHT)) -- its stand collides
	dBox(model, "Lectern", V3(1.5, 0.2, 1.1), CF(3.2, 3.7, -3.6) * ANG(-0.3, 0, 0), PLANK[4])
	dBall(model, "Bell", 0.55, CF(3.5, 4.0, -3.5), BRASS, MAT.Metal)
	TownMeshes.Dress(model, "GondolaStation")
	return model
end

---------------------------------------------------------------------------
-- Street furniture
---------------------------------------------------------------------------

-- A signpost: two posts with a framed board between them facing -Z (text
-- on both faces) under a little shingled cap. Named parts: "Board" (the
-- 9 x 4.4 text board, its middle 7 studs up, so its bottom is 4.8 up).
-- `lit` adds two gooseneck lamps over the front face (night lights: see
-- gooseneck). The posts collide. The board only collides when asked
-- (`solidBoard`, for the biome signs out by the roads: COL-01): people
-- walk under the town's (TO THE WOODS stands across the walk from the
-- spawn to Murph) and a Logging Rig drives under SELL LOGS HERE's. The
-- rocks at the posts' feet are looks only (SELL LOGS HERE's stand by the
-- pad's lane, some road signs' 1.5 studs off the road).
function BuildingArt.Signpost(text: string, lit: boolean?, solidBoard: boolean?): Model
	local model = Kit.model("Signpost")
	local rng = Kit.rng(#text * 13 + 5)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(model, "Post", V3(0.7, 9.8, 0.7), CF(s * 4.95, 4.9, 0), TIMBER, MAT.Wood)
		dBox(model, "PostCap", V3(0.95, 0.3, 0.95), CF(s * 4.95, 9.9, 0), TIMBER_LIGHT)
	end
	local board = signBoard(model, "Board", CF(0, 7, 0), 9, 4.4, text, PLANK[2], TIMBER, SIGN_INK, true)
	if solidBoard then
		Kit.solid(board)
	end
	if lit then
		-- Two goosenecks over the front (-Z) face, under the cap (TWN-07).
		for _, x in ipairs({ -2.5, 2.5 }) do
			gooseneck(model, CF(x, 8.7, -0.3))
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		dWedge(
			model,
			"Cap",
			V3(10.6, 0.7, 0.75),
			CF(0, 9.75, s * 0.37) * ANG(0, if s > 0 then PI else 0, 0),
			SHINGLE[1]
		)
	end
	for _, s in ipairs({ -1, 1 }) do
		for _, p in ipairs(Kit.rock(model, CF(s * 5.6, 0, rng:range(-0.4, 0.4)), rng:range(0.9, 1.3), rng, STONE)) do
			Kit.decor(p)
		end
	end
	TownMeshes.Dress(model, "Signpost")
	return model
end

-- The paint and lights on one parking bay (TWN-06). `slot` is MapBuilder's
-- ParkingSlot part: VehicleService reads its tag, Index, CFrame and Size.Y,
-- so it keeps all of those and only goes invisible here; the bay is drawn
-- by looks-only children of it (no collide, query, touch or shadow), flat
-- on the ground in the slot's own height band: a cream bay line down each
-- side, a stop bar across the head (the -Z end, where the truck's nose
-- points; it runs a stud past the slot's width, so a row of 10-wide slots
-- 11 apart reads as one bar), the bay's number painted just behind it (read from
-- the driver's seat), and a lamp: a flat "LanternGlow" plate at the head
-- that glows after dark (LightingController), with a second, invisible
-- LanternGlow 3 studs over it holding the dim PointLight (built switched
-- off), so the light falls on the ground instead of grazing along it.
local BAY_PAINT = Color3.fromRGB(230, 222, 200)
local BAY_LAMP_DAY = Color3.fromRGB(247, 217, 165) -- LightingController's daytime LanternGlow
local BAY_LINE = 0.35
function BuildingArt.ParkingBay(slot: BasePart, index: number)
	slot.Transparency = 1
	local cf, size = slot.CFrame, slot.Size
	local hx, hz = size.X / 2, size.Z / 2
	local function paint(name: string, partSize: Vector3, at: CFrame, color: Color3): Part
		return Kit.decor(Kit.part(slot, name, partSize, cf * at, color, MAT.SmoothPlastic), false)
	end
	for _, s in ipairs({ -1, 1 }) do
		paint("BayLine", V3(BAY_LINE, size.Y, size.Z), CF(s * (hx - BAY_LINE / 2), 0, 0), BAY_PAINT)
	end
	paint("StopBar", V3(size.X + 1, size.Y, 0.5), CF(0, 0, -hz + 0.25), BAY_PAINT)
	local number = paint("BayNumber", V3(2.4, size.Y, 2), CF(0, 0, -hz + 3.6), BAY_PAINT)
	number.Transparency = 1 -- only its painted digits show
	Kit.signText(number, tostring(index), BAY_PAINT, { Enum.NormalId.Top })
	paint("LanternGlow", V3(2.6, size.Y + 0.02, 0.7), CF(0, 0.01, -hz + 1.2), BAY_LAMP_DAY)
	local holder = paint("LanternGlow", V3(0.2, 0.2, 0.2), CF(0, 3, -hz + 1.2), BAY_LAMP_DAY)
	holder.Transparency = 1
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 190, 120)
	l.Range = 16
	l.Brightness = 0.8
	l.Shadows = false
	l.Enabled = false -- LightingController switches it on at dusk
	l.Parent = holder
	TownMeshes.Adorn(slot, "ParkingBay", cf)
end

-- A street lamp: a stone footing, a timber post, an iron arm reaching out
-- toward -Z with a lantern hanging from it (lit; clients may switch the
-- glow by time of day). The post collides. Named parts: "LampGlow" (the
-- lantern's neon glass, with the PointLight), 8.4 up and 2.3 out (-Z).
function BuildingArt.LampPost(): Model
	local model = Kit.model("LampPost")
	Kit.part(model, "Footing", V3(1.6, 0.7, 1.6), CF(0, 0.35, 0), STONE[1], MAT.Slate)
	dBox(model, "Footing", V3(1.9, 0.25, 1.9), CF(0, 0.15, 0), STONE[3], MAT.Slate)
	Kit.part(model, "Post", V3(0.7, 9.6, 0.7), CF(0, 5.5, 0), TIMBER, MAT.Wood)
	dBox(model, "PostCap", V3(1, 0.35, 1), CF(0, 10.45, 0), TIMBER_LIGHT)
	dBox(model, "Arm", V3(0.35, 0.35, 2.7), CF(0, 9.8, -1.25), IRON, MAT.Metal)
	dBeam(model, "Brace", V3(0, 8.3, -0.35), V3(0, 9.7, -1.7), 0.22, 0.22, IRON, MAT.Metal)
	dBox(model, "Chain", V3(0.12, 0.4, 0.12), CF(0, 9.43, -2.3), IRON, MAT.Metal)
	local glow = Kit.lantern(model, CF(0, 8.4, -2.3), 1.1)
	glow.Name = "LampGlow"
	TownMeshes.Dress(model, "LampPost")
	return model
end

-- A split-rail fence `length` studs long along X (posts and rails
-- collide).
function BuildingArt.Fence(length: number): Model
	local model = Kit.model("Fence")
	local rng = Kit.rng(math.floor(length * 10) + 3)
	local posts = math.max(2, math.floor(length / 6) + 1)
	local step = length / (posts - 1)
	for i = 0, posts - 1 do
		local x = -length / 2 + i * step
		local h = 3.3 + rng:range(-0.15, 0.15)
		Kit.part(
			model,
			"Post",
			V3(0.55, h, 0.55),
			CF(x, h / 2, 0) * ANG(0, rng:range(-0.15, 0.15), rng:range(-0.03, 0.03)),
			Kit.vary(TIMBER_LIGHT, rng, 0.05),
			MAT.Wood
		)
	end
	for i = 0, posts - 2 do
		local x0 = -length / 2 + i * step
		for _, y in ipairs({ 1.15, 2.4 }) do
			local rail = beam(
				model,
				"Rail",
				V3(x0 - 0.15, y + rng:range(-0.1, 0.1), -0.32),
				V3(x0 + step + 0.15, y + rng:range(-0.1, 0.1), -0.32),
				0.24,
				0.34,
				Kit.vary(PLANK[3], rng, 0.05),
				MAT.Wood
			)
			rail.CastShadow = true
		end
	end
	TownMeshes.Dress(model, "Fence", { scale = V3(length / TownModels.FenceLength, 1, 1) })
	return model
end

-- The sell pad's plank floor with its timber border, iron corners and
-- drive-in chevrons (at each x in `chevrons`): flat paint, nothing of it
-- collides or stands taller than 0.3. Returns "SellPad" (w x 0.2 x d,
-- CanCollide off) with "SELL LOGS HERE" on its top face; the pad is turned
-- half a turn so the text reads upright from the -Z side (the street).
local function sellPadBase(model: Model, w: number, d: number, chevrons: { number }): Part
	local pad = Kit.part(model, "SellPad", V3(w, 0.2, d), CF(0, 0.1, 0) * ANG(0, PI, 0), PAD, MAT.WoodPlanks)
	pad.CanCollide = false
	Kit.signText(pad, "SELL LOGS HERE", PAD_INK, { Enum.NormalId.Top })
	for _, s in ipairs({ -1, 1 }) do
		dBox(model, "PadBorder", V3(w + 1.6, 0.24, 0.8), CF(0, 0.12, s * (d / 2 + 0.4)), PLANK_DARK[1])
		dBox(model, "PadBorder", V3(0.8, 0.24, d), CF(s * (w / 2 + 0.4), 0.12, 0), PLANK_DARK[2])
		for _, t in ipairs({ -1, 1 }) do
			dBox(
				model,
				"PadCorner",
				V3(1.3, 0.26, 1.3),
				CF(s * (w / 2 + 0.4), 0.13, t * (d / 2 + 0.4)),
				IRON,
				MAT.Metal
			)
		end
	end
	for _, x in ipairs(chevrons) do
		for _, s in ipairs({ -1, 1 }) do
			dBox(
				model,
				"Chevron",
				V3(2.2, 0.22, 0.45),
				CF(x + s * 0.75, 0.11, -d / 2 + 1.5) * ANG(0, s * 0.6, 0),
				SIGN_INK,
				MAT.SmoothPlastic
			)
		end
	end
	return pad
end

-- The painted sell pad (w x d) with a timber border and drive-in chevrons;
-- nothing on it collides or stands taller than 0.25. Named parts:
-- "SellPad" (w x 0.2 x d, CanCollide off) with "SELL LOGS HERE" on its
-- top face. The pad is turned half a turn so the text reads upright from
-- the -Z side (the spawn). The town builds BuildingArt.SellStation now (it
-- uses this pad's floor); the 24 x 18 pad is what the uploaded mesh fits.
function BuildingArt.SellPad(w: number, d: number): Model
	local model = Kit.model("SellPadArt")
	sellPadBase(model, w, d, { -w / 3.4, 0, w / 3.4 })
	TownMeshes.Dress(model, "SellPad")
	return model
end

-- The sell station (Connor: "move the sell logs here pad to the side of the
-- sawmill, and add more to it"): a w x d sell pad with a clear drive-in
-- lane down the middle (the Logging Rig and the biggest beds back onto it
-- from the street, -Z) and marked slots to either side where hand-dragged
-- logs (LOGS, west) and plank piles (PLANKS, east) can be left, a log rack
-- across the back, a platform scale, a Weigh House with Millie's window on
-- the east side, rails behind, and lanterns. Everything on the pad is flat
-- paint; what collides stands at its edges and along the back (the rack,
-- the scale's post, the rails, the weigh house), clear of the lane.
-- Named parts: "SellPad" (as sellPadBase, CanCollide off), "SlotLabel"
-- (one per slot), "LogRack", "ScalePost", "WeighHouse" (a Model, its
-- window on the west, toward the pad). There is no Sky Bin here any more: it
-- is an item you place on your plot (BuildingArt.SkyBin is its art, built by
-- MachineArt.BuildSkyBin). Built around the pad's middle, ground at y = 0, the
-- street at -Z.
function BuildingArt.SellStation(w: number, d: number): Model
	local model = Kit.model("SellStationArt")
	local hw, hd = w / 2, d / 2
	local pad = sellPadBase(model, w, d, { 0 })
	-- On the big pad the name is painted in the lane's middle, as wide as
	-- the lane, not across the whole floor over the slots.
	local name = pad:FindFirstChildOfClass("SurfaceGui")
	local title = if name then name:FindFirstChildOfClass("TextLabel") else nil
	if title then
		title.Size = UDim2.fromScale(0.36, 0.1)
		title.Position = UDim2.fromScale(0.32, 0.45)
	end

	-- The lane the trucks use, between two painted lines.
	for _, s in ipairs({ -1, 1 }) do
		dBox(model, "LaneLine", V3(0.3, 0.22, d - 5), CF(s * 5.6, 0.11, 0.5), SIGN_INK, MAT.SmoothPlastic)
	end

	-- Marked slots: a painted box and a label plate each.
	local function slot(cx: number, cz: number, label: string)
		local sw, sd = 7, 6.5
		for _, s in ipairs({ -1, 1 }) do
			dBox(model, "SlotLine", V3(sw, 0.22, 0.25), CF(cx, 0.11, cz + s * sd / 2), SIGN_INK, MAT.SmoothPlastic)
			dBox(model, "SlotLine", V3(0.25, 0.22, sd), CF(cx + s * sw / 2, 0.11, cz), SIGN_INK, MAT.SmoothPlastic)
		end
		local tag = dBox(
			model,
			"SlotLabel",
			V3(4.4, 0.08, 1.3),
			CF(cx, 0.24, cz - sd / 2 + 1.2) * ANG(0, PI, 0),
			PLANK_DARK[1],
			MAT.WoodPlanks
		)
		Kit.signText(tag, label, SIGN_INK, { Enum.NormalId.Top })
	end
	for _, z in ipairs({ -10, -2.5, 5 }) do
		slot(-10.2, z, "LOGS")
	end
	for _, z in ipairs({ -10, -2.5 }) do
		slot(10.2, z, "PLANKS")
	end

	-- The platform scale in the east column: a steel plate on the pad with a
	-- post and a dial behind it (the post collides, the plate is flat).
	local sx, sz = 10.2, 5.5
	dBox(model, "ScaleRim", V3(5.9, 0.2, 5.3), CF(sx, 0.3, sz), IRON, MAT.Metal)
	dBox(model, "ScalePlate", V3(5.6, 0.12, 5), CF(sx, 0.46, sz), STEEL_DARK, MAT.Metal)
	Kit.part(model, "ScalePost", V3(0.5, 4.2, 0.5), CF(sx, 2.3, sz + 2.1), STEEL_DARK, MAT.Metal)
	dCyl(model, "ScaleDial", 0.3, 2.4, CF(sx, 4.9, sz + 1.85) * ANG(0, PI / 2, 0), IRON, MAT.Metal)
	dCyl(model, "ScaleFace", 0.1, 2, CF(sx, 4.9, sz + 1.68) * ANG(0, PI / 2, 0), PAPER)
	dBox(model, "ScaleNeedle", V3(0.12, 0.85, 0.08), CF(sx + 0.25, 5.0, sz + 1.6) * ANG(0, 0, -0.55), SOOT)

	-- The log rack across the back: three tiers of logs between stakes,
	-- stakes lit by lanterns. The logs and stakes collide (it is a wall).
	local rz, rl = hd - 1.8, 14
	local rack = Kit.rng(2027)
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			Kit.part(model, "LogRack", V3(0.6, 4.6, 0.6), CF(x * (rl / 2 + 0.5), 2.5, rz + z * 2.5), TIMBER, MAT.Wood)
		end
		Kit.lantern(model, CF(x * (rl / 2 + 0.5), 5.6, rz), 0.9)
	end
	local tiers: { { y: number, zs: { number } } } = {
		{ y = 0.95, zs = { -1.6, 0, 1.6 } },
		{ y = 2.2, zs = { -0.8, 0.8 } },
		{ y = 3.45, zs = { 0 } },
	}
	for _, tier in ipairs(tiers) do
		for _, dz in ipairs(tier.zs) do
			local tone = Kit.vary(BARK, rack, 0.06)
			Kit.cylinder(model, "RackLog", rl, 1.5, CF(0, tier.y, rz + dz), tone, MAT.Wood)
			for _, x in ipairs({ -1, 1 }) do
				dCyl(model, "RackEnd", 0.1, 1.3, CF(x * (rl / 2 + 0.03), tier.y, rz + dz), HEART)
			end
		end
	end

	-- Rails behind the pad (a split-rail fence, as the lot's): across the
	-- back and a stretch of the west side.
	local function rail(len: number, cf: CFrame)
		local f = BuildingArt.Fence(len)
		Kit.placeAt(f, cf)
		f.Parent = model
	end
	rail(w + 3, CF(0, 0, hd + 1.7))
	rail(8, CF(-(hw + 1.7), 0, hd - 2.3) * ANG(0, PI / 2, 0))

	-- The Weigh House on the east side, its window toward the pad (turned so
	-- its front faces -X): a counter under a lean-to roof, a name board and
	-- two lanterns on its front posts.
	local house = Kit.model("WeighHouse", model)
	local hc = CF(hw + 9, 0, hd - 7) * ANG(0, PI / 2, 0)
	local function at(x: number, y: number, z: number): CFrame
		return hc * CF(x, y, z)
	end
	local H0, H1 = 0.5, 6.4
	Kit.part(house, "HouseFloor", V3(7.6, 0.5, 7.6), at(0, 0.25, 0), STONE[2], MAT.Slate)
	Kit.part(house, "HouseWall", V3(7, H1 - H0, 0.4), at(0, (H0 + H1) / 2, 3.3), PLANK[1], MAT.WoodPlanks)
	for i, s in ipairs({ -1, 1 }) do
		Kit.part(house, "HouseWall", V3(0.4, H1 - H0, 6.2), at(s * 3.3, (H0 + H1) / 2, 0), PLANK[i + 1], MAT.WoodPlanks)
	end
	Kit.part(house, "HouseCounter", V3(4.4, 2.9, 0.5), at(-1.1, 1.95, -3.3), PLANK[3], MAT.WoodPlanks)
	dBox(house, "HouseLedge", V3(4.8, 0.25, 1.1), at(-1.1, 3.5, -3.85), TIMBER_LIGHT)
	Kit.part(house, "HouseHeader", V3(7.2, 0.6, 0.6), at(0, 6.1, -3.3), TIMBER, MAT.Wood)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(house, "HousePost", V3(0.6, 5.9, 0.6), at(s * 3.3, 3.45, -3.3), TIMBER, MAT.Wood)
	end
	Kit.wedge(house, "HouseRoof", V3(8.6, 1.5, 8.8), at(0, H1 + 0.75, 0.2), SHINGLE[1], MAT.Slate)
	dBox(house, "RoofTrim", V3(8.8, 0.3, 0.4), at(0, H1 + 0.15, -4.25), TIMBER)
	signBoard(house, "HouseSign", at(0, 5.45, -3.8), 5.6, 0.8, "WEIGH HOUSE", PLANK[2], TIMBER, SIGN_INK, false)
	for _, s in ipairs({ -1, 1 }) do
		Kit.lantern(house, at(s * 3.3, 4.2, -4.1), 0.9)
	end
	dBox(house, "Ledger", V3(1.2, 0.12, 0.9), at(-1.1, 3.69, -3.85), PAPER)
	dBox(house, "Stool", V3(1.1, 1.4, 1.1), at(1.9, 1.2, 1.4), TIMBER_LIGHT)

	return model
end

---------------------------------------------------------------------------
-- Murph's camp
---------------------------------------------------------------------------

-- A campfire: a ring of stones, crossed logs, glowing embers and three
-- low-poly flame shapes (neon "Flame" parts; clients may flicker them).
-- Named parts: "Embers" (with the Fire and a warm PointLight).
function BuildingArt.Campfire(dress: boolean?): Model
	local model = Kit.model("Campfire")
	local rng = Kit.rng(5)
	for i = 1, 8 do
		local a = i / 8 * PI * 2 + rng:range(-0.1, 0.1)
		dBox(
			model,
			"FireStone",
			V3(0.85, 0.55, 0.7) * rng:range(0.85, 1.1),
			CF(math.cos(a) * 1.7, 0.24, math.sin(a) * 1.75) * ANG(rng:range(-0.1, 0.1), -a, rng:range(-0.1, 0.1)),
			Kit.vary(rng:pick(STONE), rng, 0.06),
			MAT.Slate
		)
	end
	dec(Kit.post(model, "Ash", V3(0, 0, 0), 0.1, 2.8, hex("#4A4440"), MAT.Slate))
	for i = 1, 4 do
		local a = i / 4 * PI * 2 + 0.4
		dRod(
			model,
			"FireLog",
			V3(math.cos(a) * 1.3, 0.2, math.sin(a) * 1.3),
			V3(math.cos(a) * 0.15, 1.35, math.sin(a) * 0.15),
			0.45,
			Kit.vary(BARK, rng, 0.06)
		)
	end
	local embers = Kit.part(model, "Embers", V3(1.6, 0.3, 1.6), CF(0, 0.2, 0), EMBER, MAT.Neon)
	Kit.decor(embers, false)
	local corner = ANG(math.rad(35.26), math.rad(45), 0) -- a cube on its corner: a faceted flame
	for i, f in ipairs({ { 0, 0.95, 0, 1 }, { 0, 1.4, 0, 0.6 }, { 0.38, 0.75, 0.2, 0.55 }, { -0.3, 0.72, -0.3, 0.5 } }) do
		local p = Kit.part(
			model,
			"Flame",
			V3(f[4], f[4], f[4]),
			CF(f[1], f[2], f[3]) * ANG(0, i * 0.6, 0) * corner,
			FLAME[if i == 2 then 1 else i % 2 + 2],
			MAT.Neon
		)
		Kit.decor(p, false)
	end
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Parent = embers
	light(embers, 18, 1.6, Color3.fromRGB(255, 160, 80))
	if dress ~= false then
		TownMeshes.Dress(model, "Campfire")
	end
	return model
end

-- Murph's camp by the spawn: the campfire at the origin, a canvas tent
-- behind it (+Z, its door toward the fire), log seats either side
-- (x = +-3.4), an axe in a chopping stump, a lantern on a hook, a kettle
-- on a tripod over the fire, his pack, firewood and a little sign. Leave
-- (0, 0, -3) clear for Murph himself. Named parts: "Embers" (see Campfire).
function BuildingArt.Campsite(): Model
	local model = Kit.model("MurphsCamp")
	local rng = Kit.rng(1931)
	BuildingArt.Campfire(false).Parent = model

	-- The tent: two canvas sheets over a ridge pole, closed at the back.
	local tent = CF(0, 0, 5.4)
	local TW, TH, TL = 2.8, 4.2, 6
	local tilt = math.atan2(TW, TH)
	local sheet = math.sqrt(TW * TW + TH * TH)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(
			model,
			"Canvas",
			V3(0.18, sheet + 0.3, TL),
			tent * CF(s * TW / 2, TH / 2, 0) * ANG(0, 0, s * tilt),
			if s < 0 then CANVAS else Kit.shade(CANVAS, -0.04),
			MAT.Fabric
		)
		dWedge(
			model,
			"Flap",
			V3(0.12, TH * 0.85, 1.6),
			tent * CF(s * (TW - 0.2), TH * 0.42, -TL / 2 - 0.55) * ANG(0, s * 0.9 + (if s > 0 then PI else 0), 0),
			CANVAS_DARK,
			MAT.Fabric
		)
	end
	gable(model, tent * CF(0, 0, TL / 2 - 0.1) * ANG(0, PI, 0), 2 * TW - 0.3, TH - 0.2, 0.15, CANVAS_DARK, MAT.Fabric)
	dCyl(model, "RidgePole", TL + 0.8, 0.25, tent * CF(0, TH + 0.08, 0) * ANG(0, PI / 2, 0), TIMBER)
	for _, s in ipairs({ -1, 1 }) do
		local z = s * (TL / 2 + 0.25)
		dBox(model, "TentPole", V3(0.22, TH + 0.3, 0.22), tent * CF(0, (TH + 0.3) / 2, z), TIMBER)
		dRod(model, "GuyRope", (tent * V3(0, TH + 0.2, z)), (tent * V3(0, 0.15, z + s * 2.4)), 0.1, ROPE, MAT.Fabric)
		dBox(model, "Peg", V3(0.2, 0.5, 0.2), tent * CF(0, 0.2, z + s * 2.45), TIMBER_LIGHT)
	end
	dCyl(model, "Bedroll", 2.4, 0.9, tent * CF(-0.6, 0.45, 1.2), hex("#A63A30"), MAT.Fabric)

	-- Log seats round the fire and Murph's pack against one.
	for _, s in ipairs({ -1, 1 }) do
		log(model, CF(s * 3.4, 0.65, -0.4) * ANG(0, PI / 2, 0), 3.6, 1.3, rng, 2, true)
	end
	dBox(model, "Pack", V3(1.1, 1.4, 0.7), CF(4.3, 0.7, 1.6) * ANG(0, -0.4, -0.12), hex("#6E7F46"), MAT.Fabric)
	dBox(model, "PackFlap", V3(1.15, 0.5, 0.75), CF(4.32, 1.3, 1.6) * ANG(0, -0.4, -0.12), hex("#5A6A38"), MAT.Fabric)
	dCyl(model, "PackRoll", 1.3, 0.55, CF(4.4, 1.65, 1.6) * ANG(0, -0.4, -0.12), hex("#A63A30"), MAT.Fabric)

	-- A kettle on a tripod over the fire.
	for i = 0, 2 do
		local a = i / 3 * PI * 2 + 0.3
		dRod(model, "Tripod", V3(math.cos(a) * 2.1, 0, math.sin(a) * 2.1), V3(0, 3.7, 0), 0.18, TIMBER_LIGHT)
	end
	dBox(model, "Chain", V3(0.1, 1.0, 0.1), CF(0, 3.15, 0), IRON, MAT.Metal)
	dEllipsoid(model, "Kettle", V3(1.1, 0.9, 1.1), CF(0, 2.25, 0), hex("#4A4F57"), MAT.Metal)
	dCyl(model, "KettleLid", 0.2, 0.6, CF(0, 2.7, 0) * ANG(0, 0, PI / 2), hex("#5B616A"), MAT.Metal)
	dRod(model, "Spout", V3(0.4, 2.2, 0), V3(0.85, 2.55, 0), 0.18, hex("#4A4F57"), MAT.Metal)

	-- The chopping stump, the lantern hook, firewood, rocks, the sign.
	choppingBlock(model, CF(4.6, 0, 4.2), rng)
	local hook = CF(-4, 0, 3.4)
	dBox(model, "HookPost", V3(0.25, 5.2, 0.25), hook * CF(0, 2.6, 0), IRON, MAT.Metal)
	dBox(model, "Hook", V3(0.2, 0.2, 1.2), hook * CF(0, 5.1, -0.5), IRON, MAT.Metal)
	hangingLantern(model, (hook * V3(0, 5, -1.0)), 0.35, 0.8)
	for row = 0, 1 do
		for i = 0, 2 - row do
			log(
				model,
				CF(-4.3 + (i - (2 - row) / 2) * 0.85, 0.4 + row * 0.72, 7.2) * ANG(0, PI / 2, 0),
				2,
				0.8,
				rng,
				1,
				true
			)
		end
	end
	Kit.rock(model, CF(-5.6, 0, -1.4), 1.6, rng, STONE) -- the rocks collide (Kit.rock)
	Kit.rock(model, CF(6, 0, -0.8), 1.2, rng, STONE)
	dBox(model, "SignStake", V3(0.3, 2, 0.3), CF(5.9, 1.0, -2.4), TIMBER)
	signBoard(
		model,
		"CampSign",
		CF(5.9, 1.9, -2.6) * ANG(0, -0.6, -0.04),
		2.6,
		0.8,
		"MURPH'S CAMP",
		PLANK[2],
		TIMBER,
		SIGN_INK,
		true
	)
	TownMeshes.Dress(model, "MurphsCamp")
	return model
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------

type PropBuilder = (model: Model, rng: Rng) -> ()

local PROPS: { [string]: PropBuilder } = {}

-- A log pile, cut ends to the front (-Z); every log collides.
PROPS.LogPile = function(model, rng)
	local dia, len = rng:range(1.2, 1.5), rng:range(5, 6.5)
	for row = 0, 2 do
		for i = 0, 2 - row do
			local x = (i - (2 - row) / 2) * (dia + 0.06)
			local cf = CF(x, dia / 2 + row * dia * 0.86, rng:range(-0.25, 0.25)) * ANG(0, PI / 2, 0)
			log(model, cf, len * rng:range(0.92, 1.04), dia * rng:range(0.92, 1.05), rng, 2, true)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		dWedge(model, "Chock", V3(0.5, 0.7, 0.8), CF(s * (1.5 * dia + 0.3), 0.35, 0) * ANG(0, -s * PI / 2, 0), TIMBER)
	end
end

PROPS.Crate = function(model, rng)
	crate(model, CF(0, 0, 0) * ANG(0, rng:range(-0.25, 0.25), 0), rng:range(1.9, 2.4), rng, true)
	if rng:next() < 0.5 then
		crate(
			model,
			CF(rng:range(-0.2, 0.2), 1.9, rng:range(-0.2, 0.2)) * ANG(0, rng:range(-0.6, 0.6), 0),
			1.4,
			rng,
			true
		)
	end
end

PROPS.Barrel = function(model, rng)
	barrel(model, CFrame.identity, rng, true)
end

-- A bench you'd sit on facing -Z (the seat and the back collide).
PROPS.Bench = function(model, rng)
	for i, z in ipairs({ -0.35, 0.35 }) do
		Kit.part(model, "Seat", V3(5, 0.25, 0.65), CF(0, 1.55, z), Kit.vary(PLANK[i], rng, 0.04), MAT.WoodPlanks)
	end
	for _, x in ipairs({ -2, 2 }) do
		dBox(model, "BenchLeg", V3(0.35, 1.45, 1.4), CF(x, 0.72, 0), TIMBER)
		dBox(model, "BenchLeg", V3(0.3, 2, 0.25), CF(x, 2.4, 0.8) * ANG(-0.15, 0, 0), TIMBER)
	end
	for _, y in ipairs({ 2.35, 3.05 }) do
		Kit.solid(
			dBox(model, "BenchBack", V3(5, 0.45, 0.2), CF(0, y, 0.9) * ANG(-0.15, 0, 0), Kit.vary(PLANK[3], rng, 0.04))
		)
	end
end

-- A stone well with a little shingled roof, a windlass and a bucket (the
-- ring and the posts collide).
PROPS.Well = function(model, rng)
	for i = 0, 7 do
		local a = i / 8 * PI * 2
		Kit.part(
			model,
			"WellStone",
			V3(1.65, 2.2, 0.8),
			CF(math.cos(a) * 2, 1.1, math.sin(a) * 2) * ANG(0, PI / 2 - a, 0),
			Kit.vary(rng:pick(STONE), rng, 0.05),
			MAT.Slate
		)
	end
	dec(Kit.post(model, "WellWater", V3(0, 0, 0), 1.6, 3.4, hex("#3F7FA8"), MAT.Glass))
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(model, "WellPost", V3(0.5, 5.4, 0.5), CF(s * 2.25, 2.7, 0), TIMBER, MAT.Wood)
	end
	dCyl(model, "Windlass", 4.6, 0.5, CF(0, 4.1, 0), TIMBER_LIGHT)
	dBox(model, "Crank", V3(0.2, 0.9, 0.2), CF(2.65, 3.75, 0), IRON, MAT.Metal)
	dBox(model, "Rope", V3(0.1, 1.2, 0.1), CF(0.3, 3.4, 0), ROPE, MAT.Fabric)
	dec(Kit.post(model, "Bucket", V3(0.3, 2.3, 0), 0.6, 0.75, PLANK_DARK[2], MAT.WoodPlanks))
	local style: RoofStyle = { colors = SHINGLE, deck = ROOF_DECK, trim = TIMBER, rowLen = 1.2, pieceLen = 6 }
	gableRoof(model, CF(0, 5.4, 0), 5.8, 3.2, 1.5, 0.4, rng, style)
end

-- A hand cart loaded with logs (the bed, its sides, the wheels and the
-- logs collide; the spokes, hubs, shafts and axle are looks only).
PROPS.Cart = function(model, rng)
	Kit.part(model, "CartBed", V3(3.4, 0.3, 5), CF(0, 1.95, 0), PLANK[1], MAT.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		Kit.solid(dBox(model, "CartSide", V3(0.25, 0.9, 5), CF(s * 1.6, 2.5, 0), PLANK[3]))
		Kit.solid(dBox(model, "CartSide", V3(3.4, 0.9, 0.25), CF(0, 2.5, s * 2.45), PLANK[2]))
		local wheel = CF(s * 2, 1.6, 0.4)
		Kit.solid(dCyl(model, "Wheel", 0.3, 3.2, wheel, TIMBER_LIGHT))
		for _, a in ipairs({ PI / 4, -PI / 4 }) do
			dBox(model, "Spoke", V3(0.36, 2.9, 0.3), wheel * ANG(a, 0, 0), TIMBER)
		end
		dCyl(model, "Hub", 0.5, 0.8, wheel, IRON, MAT.Metal)
		dRod(model, "Shaft", V3(s * 1.2, 1.9, -2.4), V3(s * 1, 0.3, -5.4), 0.3, TIMBER_LIGHT)
	end
	dCyl(model, "Axle", 4.4, 0.3, CF(0, 1.6, 0.4), IRON, MAT.Metal)
	for i = -1, 1 do
		log(model, CF(i * 0.95, 2.6 + (if i == 0 then 0.6 else 0), 0) * ANG(0, PI / 2, 0), 4.6, 0.95, rng, 2, true)
	end
end

PROPS.SawdustPile = function(model, rng)
	sawdust(model, CFrame.identity, rng:range(2, 3), rng)
end

-- A wooden water tank on a trestle with a ladder (the legs and tank
-- collide).
PROPS.WaterTower = function(model, rng)
	local H = 9
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			beam(model, "Leg", V3(sx * 2.7, 0, sz * 2.7), V3(sx * 2, H, sz * 2), 0.7, 0.7, TIMBER, MAT.Wood)
		end
	end
	for i, f in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
		local fx, fz = f[1], f[2]
		local function at(t: number, y: number): Vector3
			local w = 2.7 - 0.7 * y / H
			return if fx ~= 0 then V3(fx * w, y, t * w) else V3(t * w, y, fz * w)
		end
		dBeam(model, "Brace", at(-1, 0.8), at(1, H - 0.8), 0.3, 0.3, TIMBER_LIGHT)
		dBeam(model, "Girt", at(-1, 4.6), at(1, 4.6), 0.3, 0.35, TIMBER_LIGHT)
		if i == 3 then
			for _, t in ipairs({ -0.25, 0.25 }) do
				dBeam(model, "Ladder", at(t, 0) + V3(0, 0, -0.4), at(t, H) + V3(0, 0, -0.4), 0.18, 0.18, TIMBER)
			end
			for y = 1.2, H - 0.5, 1.5 do
				dBox(model, "Rung", V3(1.3, 0.15, 0.15), CF(0, y, -(2.7 - 0.7 * y / H) - 0.4), TIMBER)
			end
		end
	end
	Kit.post(model, "TankFloor", V3(0, H, 0), 0.5, 5.8, TIMBER, MAT.WoodPlanks)
	Kit.post(model, "Tank", V3(0, H + 0.5, 0), 5, 5, PLANK[2], MAT.WoodPlanks)
	for _, y in ipairs({ 1.4, 3, 4.6 }) do
		dec(Kit.post(model, "Hoop", V3(0, H + 0.5 + y - 0.1, 0), 0.2, 5.12, IRON, MAT.Metal))
	end
	Kit.cone(model, CF(0, H + 5.5, 0), 3, 2.3, 8, function(i: number): Color3
		return Kit.vary(SHINGLE[(i - 1) % #SHINGLE + 1], rng, 0.04)
	end, MAT.WoodPlanks, 0.15)
	dBall(model, "Finial", 0.5, CF(0, H + 7.9, 0), IRON, MAT.Metal)
	dRod(model, "Spout", V3(2.4, H + 1.2, 0), V3(3.6, H + 0.4, 0), 0.45, IRON, MAT.Metal)
	dRod(model, "Spout", V3(3.6, H + 0.4, 0), V3(3.6, H - 1.4, 0), 0.45, IRON, MAT.Metal)
end

-- A mailbox on a post. The box collides: it overhangs the thin post all
-- round at chest height (3.4 to 4 up), so it stops anyone walking into the
-- mailbox, and the post stays looks only, no obstacle at ground level for
-- the town's flower bed at its foot (TWN-01 keeps those 4 studs apart).
PROPS.Mailbox = function(model, rng)
	local green = Kit.vary(hex("#4E7A4C"), rng, 0.05)
	dBox(model, "Post", V3(0.4, 3.4, 0.4), CF(0, 1.7, 0), TIMBER)
	Kit.solid(dBox(model, "Mailbox", V3(1.05, 0.6, 1.7), CF(0, 3.7, 0), green, MAT.Metal))
	dCyl(model, "Mailbox", 1.7, 1.05, CF(0, 4, 0) * ANG(0, PI / 2, 0), green, MAT.Metal)
	dBox(model, "MailDoor", V3(0.9, 0.85, 0.08), CF(0, 3.85, -0.88), Kit.shade(green, -0.15), MAT.Metal)
	dBox(model, "Flag", V3(0.1, 1, 0.12), CF(0.6, 4.1, 0.3), hex("#C8402F"), MAT.Metal)
	dBox(model, "Flag", V3(0.1, 0.35, 0.55), CF(0.6, 4.45, 0.05), hex("#C8402F"), MAT.Metal)
end

PROPS.FlowerBox = function(model, rng)
	flowerBox(model, CF(0, 0.4, 0), rng:range(2.6, 3.4), rng)
end

-- A straw bale (sometimes two); collides.
PROPS.Haybale = function(model, rng)
	local count = if rng:next() < 0.4 then 2 else 1
	for i = 1, count do
		local cf = CF(0, 0.7 + (i - 1) * 1.4, 0) * ANG(0, rng:range(-0.3, 0.3) + (i - 1) * PI / 2, 0)
		Kit.part(model, "Haybale", V3(2.6, 1.4, 1.6), cf, Kit.vary(HAY, rng, 0.04), MAT.Grass)
		for _, x in ipairs({ -0.7, 0.7 }) do
			dBox(model, "Twine", V3(0.15, 1.45, 1.65), cf * CF(x, 0, 0), hex("#A8843C"), MAT.Fabric)
		end
	end
end

-- A wheelbarrow of sawdust. Looks only: the town's stands on the plaza by
-- the sell pad, where nothing may collide (TWN-08) and trucks swing past.
PROPS.Wheelbarrow = function(model, rng)
	local tray = CF(0, 1.45, 0.2)
	dBox(model, "Tray", V3(1.9, 0.9, 1.6), tray, hex("#7E8A72"), MAT.Metal)
	dWedge(model, "Tray", V3(1.9, 0.9, 1.0), tray * CF(0, 0, -1.3) * ANG(0, PI, 0), hex("#7E8A72"), MAT.Metal)
	dBox(model, "Load", V3(1.7, 0.2, 1.5), tray * CF(0, 0.4, 0), rng:pick(SAWDUST), MAT.Sand)
	dCyl(model, "Wheel", 0.35, 1.2, CF(0, 0.6, -1.9), TYRE, MAT.Rubber)
	dCyl(model, "Hub", 0.45, 0.4, CF(0, 0.6, -1.9), IRON, MAT.Metal)
	for _, s in ipairs({ -1, 1 }) do
		dRod(model, "Handle", V3(s * 0.5, 0.6, -1.9), V3(s * 0.85, 1.25, 2.6), 0.22, TIMBER_LIGHT)
		dBox(model, "Leg", V3(0.2, 1.0, 0.2), CF(s * 0.65, 0.5, 1.1), TIMBER_LIGHT)
	end
end

-- A tool rack: two posts and rails with an axe, a shovel, a rake and a
-- crosscut saw hung on it (the posts and rails collide).
PROPS.ToolRack = function(model, rng)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(model, "Post", V3(0.4, 4.6, 0.4), CF(s * 2.2, 2.3, 0), TIMBER, MAT.Wood)
	end
	for _, y in ipairs({ 1.2, 4 }) do
		Kit.solid(dBox(model, "Rail", V3(4.8, 0.3, 0.3), CF(0, y, -0.1), PLANK[3]))
	end
	rackAxe(model, CF(-1.5, 0.6, -0.4), 3.4, hex("#A7ADB4"), MAT.Metal)
	dBox(model, "ShovelHandle", V3(0.22, 3.6, 0.22), CF(-0.4, 2.4, -0.4), HANDLE)
	dBox(model, "ShovelBlade", V3(0.9, 1.1, 0.12), CF(-0.4, 0.75, -0.45), STEEL_DARK, MAT.Metal)
	dBox(model, "RakeHandle", V3(0.22, 3.8, 0.22), CF(0.6, 2.2, -0.4), HANDLE)
	dBox(model, "RakeHead", V3(1.4, 0.3, 0.3), CF(0.6, 4.2, -0.45), IRON, MAT.Metal)
	dBox(model, "SawBlade", V3(2.2, 0.7, 0.08), CF(1.4, 3.1, -0.3) * ANG(0, 0, -0.2), STEEL, MAT.Metal)
	dBox(model, "SawHandle", V3(0.4, 0.6, 0.18), CF(2.5, 3.3, -0.3), HANDLE)
	if rng:next() < 0.5 then
		dBox(model, "Coil", V3(0.9, 0.9, 0.3), CF(1.6, 1.6, -0.3), ROPE, MAT.Fabric)
	end
end

-- A lantern on a shepherd's hook (lit).
PROPS.Lantern = function(model, rng)
	local h = rng:range(4.8, 5.4)
	dBox(model, "Base", V3(1, 0.25, 1), CF(0, 0.12, 0), IRON, MAT.Metal)
	dBox(model, "Post", V3(0.25, h, 0.25), CF(0, h / 2, 0), IRON, MAT.Metal)
	dBox(model, "Hook", V3(0.2, 0.2, 1.2), CF(0, h - 0.1, -0.5), IRON, MAT.Metal)
	hangingLantern(model, V3(0, h - 0.2, -1.0), 0.35, 0.8)
end

PROPS.Planter = function(model, rng)
	planter(model, CFrame.identity, rng)
end

-- A brass bell on a timber post, the grove gate's marker (the post
-- collides; the bell is looks only).
PROPS.MillBell = function(model, rng)
	local post = Kit.part(model, "Post", V3(0.55, 5.2, 0.55), CF(0, 2.6, 0), TIMBER, MAT.Wood)
	post.CanTouch = false
	dBox(model, "Cap", V3(0.85, 0.22, 0.85), CF(0, 5.28, 0), TIMBER_LIGHT)
	dBall(model, "Bell", 0.85, CF(0, 4.45, 0.55), Kit.vary(BRASS, rng, 0.04), MAT.Metal)
	dBox(model, "Clapper", V3(0.12, 0.35, 0.12), CF(0, 4.1, 0.55), IRON, MAT.Metal)
end

-- Town dressing, by name: "LogPile", "Crate", "Barrel", "Bench", "Well",
-- "Cart", "SawdustPile", "WaterTower", "Mailbox", "FlowerBox", "Haybale",
-- "Wheelbarrow", "ToolRack", "Lantern", "Planter", "MillBell". An unknown
-- name builds a crate. Each is built on the ground at the origin; `seed`
-- varies it.
function BuildingArt.Prop(name: string, seed: number): Model
	local model = Kit.model(name)
	local build = PROPS[name] or PROPS.Crate
	build(model, Kit.rng(seed))
	if TownModels.Get(name) then
		TownMeshes.Dress(model, name)
	end
	return model
end

-- Every name Prop knows (for tests and the preview).
function BuildingArt.PropNames(): { string }
	local names = {}
	for name in pairs(PROPS) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- A saw-cut log round set into a path: one flat disc, looks only. The
-- town's shop paths are paved with these (Timberline's own walk, not a
-- plain dirt track).
function BuildingArt.PathRound(): Model
	local model = Kit.model("PathRound")
	local round = Kit.cylinder(model, "Round", 0.1, 1.6, CF(0, 0.08, 0) * ANG(0, 0, PI / 2), HEART, MAT.Wood)
	Kit.decor(round, false)
	local body = TownModels.Piece(TownModels.Get("PathRound") :: TownModels.Asset, "Body")
	if body then
		TownMeshes.Dress(model, "PathRound", {
			scale = V3(1.6 / body.size.X, 0.1 / body.size.Y, 1.6 / body.size.Z),
		})
	end
	return model
end

---------------------------------------------------------------------------
-- The town's greenery
---------------------------------------------------------------------------

-- A ring of chunky stones round a bed of soil, `radius` studs to the
-- stones' middle (looks only).
local function stoneRing(parent: Instance, radius: number, rng: Rng)
	dCyl(parent, "RingSoil", 0.2, radius * 2, CF(0, 0.05, 0) * ANG(0, 0, PI / 2), SOIL, MAT.Ground)
	local count = math.clamp(math.floor(radius * 2 * PI / 1.6), 7, 12)
	local start = rng:range(0, PI * 2)
	for i = 1, count do
		local a = start + (i - 1) / count * PI * 2 + rng:range(-0.05, 0.05)
		local w = radius * 2 * PI / count * rng:range(0.8, 0.92)
		local h = rng:range(0.45, 0.65)
		-- Its long side along the ring (tangent at angle a).
		dBox(
			parent,
			"RingStone",
			V3(w, h, rng:range(0.6, 0.8)),
			CF(math.cos(a) * radius, h / 2 - 0.05, math.sin(a) * radius)
				* ANG(rng:range(-0.06, 0.06), -a - PI / 2, rng:range(-0.06, 0.06)),
			Kit.vary(rng:pick(STONE), rng, 0.05),
			MAT.Slate
		)
	end
end

-- How far a town tree's stone ring sits from its middle (to the stones'
-- middle): just outside the root flares, which reach at most 1.15 trunk
-- diameters from it (TreeArt: 0.45-0.65 diameters past the bark).
function BuildingArt.TreeRingRadius(trunkDiameter: number): number
	return trunkDiameter * 1.15 + 0.6
end

-- An ornamental tree for the town: TreeArt's `woodId` tree at `scale`,
-- seated in a stone ring. Only its Trunk collides (and can be clicked);
-- everything else is decoration. It carries no tag or attribute, so
-- nothing can chop it (ChopController targets models tagged Tree), and it
-- must stay out of TimberlineMap.Trees (WindSway, CanopyFade, TreeService).
-- An unknown wood grows a birch.
function BuildingArt.TownTree(woodId: string, seed: number, scale: number): Model
	local def = WoodData.Get(woodId) or WoodData.Get("birch")
	assert(def, "[BuildingArt] no birch in WoodData")
	local model = TreeArt.Build(def, seed, scale)
	model.Name = "TownTree"
	Kit.decorAll(model, { Trunk = true })
	local trunk = model.PrimaryPart
	local diameter = if trunk then math.min(trunk.Size.Y, trunk.Size.Z) else 1.5
	stoneRing(model, BuildingArt.TreeRingRadius(diameter), Kit.rng(seed + 31))
	TownMeshes.Dress(model, "TownTree")
	return model
end

-- A flower bed `size` studs across: a mound of soil with two or three
-- patches of PropArt.Flowers on it (looks only).
local function flowerBed(size: number, seed: number): Model
	local model = Kit.model("FlowerBed")
	local rng = Kit.rng(seed)
	dCyl(model, "BedSoil", 0.3, size, CF(0, 0.08, 0) * ANG(0, 0, PI / 2), SOIL, MAT.Ground)
	local patches = if size >= 2.4 then 3 else 2
	local start = rng:range(0, PI * 2)
	for i = 1, patches do
		local a = start + (i - 1) / patches * PI * 2
		local r = size * 0.22
		local patch = PropArt.Flowers(seed * 7 + i, FLOWERS)
		Kit.placeAt(patch, CF(math.cos(a) * r, 0.2, math.sin(a) * r) * ANG(0, rng:range(0, PI * 2), 0))
		patch.Parent = model
	end
	return model
end

-- A piece of the town's greenery (WorldPlan.Town().greenery) by kind:
-- "tree" (TownTree: `woodId` at scale `size`), "bush" (PropArt.Bush `size`
-- studs across, in the planters' greens), "flowers" (a bed `size` studs
-- across) or "rock" (PropArt.Rock `size` studs across). All of it is looks
-- only (no collisions, clicks or touches) but a tree's Trunk and a rock's
-- three "Rock" stones (COL-01), which collide and can be clicked. An
-- unknown kind builds a bush. On the ground at the origin.
function BuildingArt.Greenery(kind: string, size: number, seed: number, woodId: string?): Model
	if kind == "tree" then
		return BuildingArt.TownTree(woodId or "birch", seed, size)
	elseif kind == "flowers" then
		return flowerBed(size, seed)
	elseif kind == "rock" then
		local rock = PropArt.Rock(size, seed, STONE)
		Kit.decorAll(rock, { Rock = true })
		return rock
	end
	return PropArt.Bush(size, seed, LEAF)
end

-- The Sky Bin item's art (MachineArt.BuildSkyBin wraps it for the plot),
-- where wood sent down the Cloud Chute lands: a sky-blue banded bin under
-- the end of a flume that drops out of a puff of cloud behind it (+Z). Named parts:
-- "SkyBin" (4 x 4 x 4 centred at y = 2, collides; "SKY BIN" on SurfaceGuis
-- on its front and back, each with a TextLabel clients may rewrite).
function BuildingArt.SkyBin(): Model
	local model = Kit.model("SkyBinArt")
	local rng = Kit.rng(61)
	dBox(model, "BinBase", V3(4.8, 0.3, 4.8), CF(0, 0.15, 0), STONE[2], MAT.Slate)
	local bin = Kit.part(model, "SkyBin", V3(4, 4, 4), CF(0, 2, 0), hex("#5D86B8"), MAT.WoodPlanks)
	Kit.signText(bin, "SKY BIN", TRIM)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			dBox(model, "BinStrap", V3(0.35, 4.1, 0.35), CF(sx * 2, 2.05, sz * 2), IRON, MAT.Metal)
		end
		dBox(model, "BinRim", V3(4.5, 0.35, 0.4), CF(0, 4.1, sx * 2.05), TRIM)
		dBox(model, "BinRim", V3(0.4, 0.35, 4.5), CF(sx * 2.05, 4.1, 0), TRIM)
	end
	Kit.part(model, "FlumePost", V3(0.6, 8.6, 0.6), CF(0, 4.3, 3.6), TIMBER, MAT.Wood)
	local a, b = V3(0, 8.4, 3.4), V3(0, 4.9, 0.6)
	dBeam(model, "Flume", a, b, 1.8, 0.25, PLANK_DARK[1])
	for _, s in ipairs({ -1, 1 }) do
		dBeam(model, "Flume", a + V3(s * 0.9, 0.4, 0), b + V3(s * 0.9, 0.4, 0), 0.2, 0.8, PLANK[3])
	end
	local water = beam(model, "FlumeWater", a + V3(0, 0.25, 0), b + V3(0, 0.25, 0), 1.3, 0.12, WATER, MAT.Neon)
	dec(water)
	water.Transparency = 0.2
	for _ = 1, 3 do
		dEllipsoid(
			model,
			"Cloud",
			V3(2.6, 1.6, 2.2) * rng:range(0.8, 1.15),
			CF(rng:range(-0.9, 0.9), 9 + rng:range(-0.2, 0.4), 3.6 + rng:range(-0.6, 0.6)),
			Color3.fromRGB(250, 250, 255)
		)
	end
	TownMeshes.Dress(model, "SkyBin")
	return model
end

---------------------------------------------------------------------------
-- The Aether Isles
---------------------------------------------------------------------------

-- The Cloud Chute on an isle's edge: a banded wooden hopper full of water,
-- a step up to it on the -Z side, and a flume on trestles running off the
-- +Z side and down over the edge into a puff of cloud (place it with +Z
-- pointing off the isle; the flume's end is at (0, -2.6, 13.6)). Named
-- parts: "CloudChute" (the hopper box, 4 x 3 x 4 centred at y = 1.5,
-- collides; MapBuilder tags it).
function BuildingArt.CloudChute(): Model
	local model = Kit.model("CloudChuteArt")
	local rng = Kit.rng(41)
	local hopper = Kit.part(model, "CloudChute", V3(4, 3, 4), CF(0, 1.5, 0), PLANK[2], MAT.WoodPlanks)
	Kit.signText(hopper, "CLOUD CHUTE", SIGN_INK, { Enum.NormalId.Front })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			dBox(model, "ChutePost", V3(0.55, 3.7, 0.55), CF(sx * 2.05, 1.85, sz * 2.05), TIMBER)
		end
		dBox(model, "ChuteRim", V3(4.5, 0.35, 0.35), CF(0, 3.15, sx * 2.1), TIMBER_LIGHT)
		dBox(model, "ChuteRim", V3(0.35, 0.35, 4.5), CF(sx * 2.1, 3.15, 0), TIMBER_LIGHT)
	end
	dBox(model, "ChuteBand", V3(4.15, 0.3, 4.15), CF(0, 0.8, 0), IRON, MAT.Metal)
	local water = dBox(model, "ChuteWater", V3(3.4, 0.2, 3.4), CF(0, 3.05, 0), WATER, MAT.Neon)
	water.Transparency = 0.15
	Kit.part(model, "ChuteStep", V3(3, 1.2, 1.4), CF(0, 0.6, -2.8), PLANK_DARK[1], MAT.WoodPlanks)

	-- The flume: two trough runs, the second tipping over the edge.
	local function trough(a: Vector3, b: Vector3)
		dBeam(model, "Flume", a, b, 2.1, 0.3, PLANK_DARK[1])
		for _, s in ipairs({ -1, 1 }) do
			dBeam(model, "Flume", a + V3(s * 1.0, 0.6, 0), b + V3(s * 1.0, 0.6, 0), 0.24, 1.2, TIMBER_LIGHT)
		end
		local w = beam(model, "FlumeWater", a + V3(0, 0.3, 0), b + V3(0, 0.3, 0), 1.6, 0.14, WATER, MAT.Neon)
		dec(w)
		w.Transparency = 0.15
	end
	trough(V3(0, 2.5, 1.8), V3(0, 1.5, 9))
	trough(V3(0, 1.5, 9), V3(0, -2.6, 13.6))
	for _, z in ipairs({ 5.2, 9 }) do
		local y = if z < 6 then 2.0 else 1.35
		for _, s in ipairs({ -1, 1 }) do
			Kit.part(model, "Trestle", V3(0.4, y, 0.4), CF(s * 1.05, y / 2, z), TIMBER, MAT.Wood)
		end
		dBox(model, "Trestle", V3(2.6, 0.3, 0.35), CF(0, y - 0.1, z), TIMBER_LIGHT)
	end
	for i = 1, 4 do
		local a = i / 4 * PI * 2 + rng:range(-0.3, 0.3)
		dEllipsoid(
			model,
			"Cloud",
			V3(3.2, 2.0, 3.0) * rng:range(0.75, 1.15),
			CF(math.cos(a) * 1.6, -3.8 + rng:range(-0.4, 0.4), 14.2 + math.sin(a) * 1.6),
			Color3.fromRGB(250, 250, 255)
		)
	end
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255))
	spray.LightEmission = 0.5
	spray.Rate = 14
	spray.Lifetime = NumberRange.new(0.8, 1.6)
	spray.Speed = NumberRange.new(4, 7)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Parent = water
	return model
end

-- The Starfall Forge: a stone hearth with star-white coals under a hood
-- and chimney, bellows, a quench trough and a basket of Sky Shards, and in
-- front of it the anvil on a stump with a glowing star-metal ingot and
-- drifting sparkles. Named parts: "StarfallForge" (the anvil's top, 3 x
-- 0.8 x 1.4 at y = 2.9, with the light and sparkles; MapBuilder tags it).
function BuildingArt.StarfallForge(): Model
	local model = Kit.model("StarfallForgeArt")
	local rng = Kit.rng(88)
	Kit.post(model, "AnvilStump", V3(0, 0, 0), 1.3, 2.2, BARK, MAT.Wood)
	dec(Kit.post(model, "StumpTop", V3(0, 1.3, 0), 0.05, 1.9, HEART, MAT.Wood))
	dBox(model, "AnvilFoot", V3(2.4, 0.5, 1.5), CF(0, 1.55, 0), ANVIL, MAT.Metal)
	dBox(model, "AnvilWaist", V3(1.3, 0.75, 0.9), CF(0, 2.15, 0), ANVIL, MAT.Metal)
	local anvil = Kit.part(model, "StarfallForge", V3(3, 0.8, 1.4), CF(0, 2.9, 0), ANVIL, MAT.Metal)
	dWedge(model, "AnvilHorn", V3(1.2, 0.8, 1.4), CF(-2.2, 2.9, 0) * ANG(0, PI / 2, 0), ANVIL, MAT.Metal)
	dBox(model, "StarIngot", V3(1.3, 0.35, 0.6), CF(0.4, 3.48, 0.1), STAR, MAT.Neon)
	dBox(model, "HammerHead", V3(0.9, 0.5, 0.5), CF(-0.9, 3.55, -0.2), IRON, MAT.Metal)
	dBox(model, "HammerHandle", V3(0.2, 0.2, 1.8), CF(-0.9, 3.55, -1.2) * ANG(0, 0.2, 0), HANDLE)
	light(anvil, 16, 2, Color3.fromRGB(191, 216, 255))
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(220, 235, 255), Color3.fromRGB(255, 230, 160))
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Rate = 8
	sparkles.Lifetime = NumberRange.new(1.2, 2.4)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Acceleration = Vector3.new(0, 1.5, 0)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Parent = anvil

	-- The hearth behind (+Z): a stone table with a bed of star-white coals,
	-- a back wall, a sloping iron hood and a chimney.
	local dark = { hex("#6F6A65"), hex("#7C766F"), hex("#625E5A"), hex("#857E75") }
	Kit.part(model, "ForgeHearth", V3(5.6, 2.8, 3.6), CF(0, 1.4, 4.4), MORTAR, MAT.Slate)
	stones(model, CF(0, 0, 2.6), 5.9, 1.4, 0.6, rng, 1.2, 2, dark)
	stones(model, CF(0, 1.4, 2.6), 5.9, 1.4, 0.6, rng, 1.2, 2, dark)
	dBox(model, "HearthRim", V3(6, 0.4, 3.9), CF(0, 2.95, 4.4), dark[4], MAT.Slate)
	Kit.part(model, "ForgeWall", V3(5.6, 4.4, 1), CF(0, 5.3, 5.7), dark[2], MAT.Slate)
	dWedge(model, "Hood", V3(5, 2, 2.3), CF(0, 5.8, 4.15), hex("#B8733F"), MAT.Metal)
	dBox(model, "HoodBand", V3(5.6, 0.35, 0.35), CF(0, 4.85, 2.55), BRASS, MAT.Metal)
	Kit.part(model, "ForgeChimney", V3(1.7, 5, 1.7), CF(0, 9.3, 5.4), BRICK, MAT.Brick)
	dBox(model, "ChimneyCap", V3(2.3, 0.4, 2.3), CF(0, 11.95, 5.4), BRICK_DARK, MAT.Brick)
	local coals = dBox(model, "ForgeCoals", V3(3.4, 0.3, 2.2), CF(0, 3.2, 4.2), STAR, MAT.Neon)
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(150, 200, 255)
	fire.SecondaryColor = Color3.fromRGB(255, 255, 255)
	fire.Size = 3
	fire.Heat = 5
	fire.Parent = coals
	light(coals, 14, 1.5, Color3.fromRGB(200, 225, 255))

	-- Bellows (east), quench trough (west), a basket of Sky Shards.
	dWedge(model, "Bellows", V3(1.4, 1.1, 2.4), CF(3.7, 2.2, 4.2) * ANG(0, PI, 0), hex("#7A4A2E"), MAT.Leather)
	dBox(model, "BellowsBoard", V3(1.5, 0.15, 2.5), CF(3.7, 1.6, 4.2), TIMBER)
	dRod(model, "BellowsHandle", V3(3.7, 2.7, 3), V3(3.7, 3.2, 1.6), 0.2, HANDLE)
	Kit.part(model, "Trough", V3(1.6, 1.4, 3), CF(-3.9, 0.7, 3.8), PLANK_DARK[2], MAT.WoodPlanks)
	dBox(model, "TroughWater", V3(1.3, 0.1, 2.7), CF(-3.9, 1.42, 3.8), WATER, MAT.Glass)
	barrel(model, CF(3.4, 0, -1.6), rng, true, PLANK_DARK[1])
	for i = 1, 4 do
		local a = i / 4 * PI * 2
		dBox(
			model,
			"SkyShard",
			V3(0.5, rng:range(1, 1.6), 0.5),
			CF(3.4 + math.cos(a) * 0.4, 2.9, -1.6 + math.sin(a) * 0.4)
				* ANG(rng:range(-0.4, 0.4), a, rng:range(-0.4, 0.4)),
			hex("#7FB6FF"),
			MAT.Neon
		)
	end
	return model
end

-- How high a rope bridge's invisible side guards stand over its planks
-- (the rope rails' height at the posts).
BuildingArt.BridgeGuardHeight = 3.2

-- A rope bridge from `a` to `b` (world points; the planks' tops run
-- through both), `width` wide: planks on two stringers, a post at each
-- corner, sagging rope rails with hangers down to the deck. Built in world
-- space. Named parts: "Deck" (the stringers; it and the planks collide),
-- "BridgeGuard" (one each side under the rope, from the planks' tops up
-- to BridgeGuardHeight, end post to end post: invisible, it collides, so
-- nobody walks off through the rope; COL-01).
function BuildingArt.Bridge(a: Vector3, b: Vector3, width: number): Model
	local model = Kit.model("Bridge")
	local span = (b - a).Magnitude
	if span < 0.5 then
		return model
	end
	local rng = Kit.rng(Kit.seedAt(a.X + b.X, a.Z + b.Z))
	local frame = lookAt((a + b) / 2, b) -- -Z toward b, X across
	Kit.part(model, "Deck", V3(width - 0.8, 0.5, span), frame * CF(0, -0.5, 0), TIMBER, MAT.Wood)
	local n = math.max(2, math.floor(span / 1.15))
	for i = 0, n - 1 do
		local z = -span / 2 + (i + 0.5) * span / n
		Kit.part(
			model,
			"Plank",
			V3(width + rng:range(-0.25, 0.25), 0.25, span / n - 0.14),
			frame * CF(rng:range(-0.12, 0.12), -0.125, z) * ANG(0, rng:range(-0.04, 0.04), 0),
			Kit.vary(rng:pick(PLANK), rng, 0.05),
			MAT.WoodPlanks
		)
	end
	local right = frame.RightVector
	local flat = V3(b.X - a.X, 0, b.Z - a.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local sag = math.clamp(span * 0.05, 0.3, 1.6)
	local segments = math.clamp(math.floor(span / 6), 2, 8)
	for _, s in ipairs({ -1, 1 }) do
		local side = right * (s * (width / 2 + 0.25))
		local ends = { a + side, b + side }
		for _, e in ipairs(ends) do
			local base = e - V3(0, 0.6, 0)
			Kit.part(
				model,
				"Post",
				V3(0.6, 4.2, 0.6),
				lookAt(base + V3(0, 2.1, 0), base + V3(0, 2.1, 0) + look),
				TIMBER,
				MAT.Wood
			)
			dBox(
				model,
				"PostCap",
				V3(0.8, 0.3, 0.8),
				lookAt(base + V3(0, 4.3, 0), base + V3(0, 4.3, 0) + look),
				TIMBER_LIGHT
			)
		end
		local function rail(t: number): Vector3
			return ends[1]:Lerp(ends[2], t) + V3(0, 3.2 - sag * 4 * t * (1 - t), 0)
		end
		for i = 0, segments - 1 do
			dRod(model, "Rope", rail(i / segments), rail((i + 1) / segments), 0.22, ROPE, MAT.Fabric)
		end
		local hangers = math.max(1, math.floor(span / 3))
		for i = 1, hangers - 1 do
			local t = i / hangers
			local top = rail(t)
			dRod(model, "Hanger", top, ends[1]:Lerp(ends[2], t) + V3(0, -0.1, 0), 0.1, ROPE, MAT.Fabric)
		end
		-- The guard under this side's rope: from the planks' undersides up to
		-- the rail's height at the posts, the bridge's whole length.
		local h = BuildingArt.BridgeGuardHeight
		local guard = Kit.part(
			model,
			"BridgeGuard",
			V3(0.5, h + 0.25, span),
			frame * CF(s * (width / 2 + 0.25), (h - 0.25) / 2, 0),
			ROPE,
			MAT.SmoothPlastic
		)
		guard.Transparency = 1
		guard.CastShadow = false
		guard.CanTouch = false
		-- Roblox ignores this while the part collides (raycasts still hit it),
		-- but it says what's meant: nothing to click.
		guard.CanQuery = false
	end
	TownMeshes.Dress(model, "RopeBridge", {
		pivot = frame * CF(0, -0.75, 0),
		scale = V3(1, 1, span / TownModels.RopeSpan),
	})
	return model
end

return BuildingArt
