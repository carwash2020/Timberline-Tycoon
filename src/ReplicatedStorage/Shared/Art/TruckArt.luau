--!strict
-- TruckArt: the low-poly bodies of every truck and trailer (GAME_DESIGN
-- §13: "the Rustbucket is visibly held together by hope; the Logging rig
-- gleams"). Pure (see Kit), so the preview tool draws exactly what the game
-- spawns. Sizes come from TruckLayout; colours from each ItemCatalog look.
--
--   Rustbucket   open-top 1940s farm truck: narrow hood between big
--                separate fenders, a primer-green door, a dented fender,
--                rust patches, a rope-tied tailgate, a smoky exhaust.
--   Pickup       rounded enclosed cab with glass all round, cream roof,
--                chrome bumpers and trim, whitewall-cream wheels.
--   Scout ATV    a quad: fat tyres, handlebars, front and rear racks, a
--                supply crate and a tall orange scout flag.
--   Flatbed      boxy work truck: roof beacon, headache rack, wooden stake
--                sides, tandem rear axle.
--   Logging Rig  long-nose big rig: chrome grille, bumper, tanks and twin
--                stacks, roof marker lights, log stanchions, a stub crane.
--   Trailers     Pony (wooden farm trailer), Ranch (stake sides), Heavy
--                Hauler (steel stanchions, tandem axle).
--
-- Contract with VehicleService / VehicleController / VehicleFX:
--   * Build returns a Model named def.id around the origin: ground y = 0,
--     front -Z. PrimaryPart "Chassis" (invisible, W x 1 x L, centre at
--     TruckLayout.ChassisY); "Skid" (invisible, frictionless) under it,
--     its bottom flush with the wheel bottoms (y = 0).
--   * "DriverSeat": a VehicleSeat, a direct child of the model.
--   * "BedFloor" (0.5 thick, centred at layout.bedFloorY) when the truck has
--     a bed; layout.logSlots are relative to it. A towed trailer adds
--     "TrailerBed" (same rule, TrailerLayout) and "TrailerSkid".
--   * Exactly one Attachment "LoadPoint", on the last bed part.
--   * "Headlight" and "Taillight" parts (Neon), "Exhaust" parts each with an
--     Attachment "ExhaustOut" (its +Y points out of the pipe) and a "Smoke"
--     attribute (how smoky: 1 = the Rustbucket).
--   * Wheels: a part "Wheel" per wheel (a cylinder along X, the tyre) with
--     attributes Radius, Steer (front wheels) and Rear; its rim and hub are
--     its children. Rig joins each Wheel to the chassis with a Motor6D
--     "Axle" (so clients can spin and steer it through Transform).
--   * Only the chassis, skids, bed floors and bed walls collide (CanTouch
--     off); everything else is decoration (Kit.decor). Nothing near the
--     seat collides, so getting in and out never snags.
--   * Build leaves every part anchored (previews, tests); Rig makes it one
--     rigid body: the chassis anchored, the rest unanchored, massless and
--     welded (WeldConstraint) or motored to it.

local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local TruckLayout = require(script.Parent.Parent.TruckLayout)
local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)
local TreeArt = require(script.Parent.TreeArt)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef
type Layout = TruckLayout.Layout
type TrailerLayout = TruckLayout.TrailerLayout
type WoodDef = WoodData.WoodDef
type Rng = Kit.Rng

local TruckArt = {}

local V3 = Vector3.new
local CF = CFrame.new
local hex = Kit.hex
local M = Enum.Material

-- Shared colours: warm, slightly desaturated, toy-like.
local TYRE = hex("#2A2624")
local FRAME = hex("#33302D")
local BLACK = hex("#242321")
local CHROME = hex("#D3D8DC")
local CHROME_HI = hex("#EEF0F2")
local GLASS = hex("#9CCBE0")
local HEADLIGHT = hex("#FFE9B0")
local TAILLIGHT = hex("#B0241C")
local AMBER = hex("#FFB23F")
local ROPE = hex("#C8AE78")
local RUST = hex("#8C4A26")

TruckArt.HeadlightColor = HEADLIGHT
TruckArt.TaillightColor = TAILLIGHT

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

-- Small parts cast no shadow (phones); big ones do.
local function shadowFor(size: Vector3): boolean?
	return if math.max(size.X, size.Y, size.Z) < 1.6 then false else nil
end

local function deco(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(parent, name, size, cf, color, material)
	Kit.decor(p, shadowFor(size))
	return p
end

local function decoWedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local p = Kit.wedge(parent, name, size, cf, color, material)
	Kit.decor(p, shadowFor(size))
	return p
end

local function decoCyl(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.cylinder(parent, name, length, diameter, cf, color, material)
	Kit.decor(p, shadowFor(p.Size))
	return p
end

-- A frame at the middle of a -> b whose X axis runs from a to b, its Y as
-- close to world up as it can be. Built with fromMatrix (not lookAt) so it
-- is the same in Roblox and in Lune's previews, vertical rods included.
local function alongX(a: Vector3, b: Vector3): CFrame
	local x = (b - a).Unit
	local ref = if math.abs(x.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z)
end

-- The same with Z along a -> b (boxes: planks, beams), X kept level.
local function alongZ(a: Vector3, b: Vector3): CFrame
	local z = (b - a).Unit
	local ref = if math.abs(z.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local x = ref:Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z)
end

-- A cylinder from a to b (pipes, ropes, tubes).
local function decoRod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.cylinder(parent, name, (b - a).Magnitude, diameter, alongX(a, b), color, material)
	Kit.decor(p, shadowFor(p.Size))
	return p
end

-- Something you can stand on or bump into (bed floors, bed walls): it
-- collides and can be clicked, but touching it does nothing.
local function hull(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(parent, name, size, cf, color, material)
	p.CanTouch = false
	return p
end

local function glass(parent: Instance, name: string, size: Vector3, cf: CFrame, transparency: number?): Part
	local p = deco(parent, name, size, cf, GLASS, M.Glass)
	p.Transparency = transparency or 0.45
	p.CastShadow = false
	return p
end

-- Glossy paint: every part of `model` painted `paint` turns to clean
-- SmoothPlastic with a little shine (Metal reads brushed and scratched).
local function gloss(model: Model, paint: Color3, shine: number)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Color == paint then
			d.Material = M.SmoothPlastic
			d.Reflectance = shine
		end
	end
end

-- A box from a to b (`width` across, `thick` thick): booms, beams.
local function plank(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(parent, name, V3(width, thick, (b - a).Magnitude), alongZ(a, b), color, material)
	Kit.decor(p, shadowFor(p.Size))
	return p
end

-- A chunky fender over a wheel (or a run of wheels from z0 to z1) at x:
-- a cap `thick` thick whose top is at `top`, with a sloped wedge running
-- down in front (front = { reach, low }) and behind (back = { reach, low }).
-- The wedges wrap the tyre's shoulders like an old pontoon fender.
type FenderStyle = {
	r: number,
	width: number,
	top: number,
	thick: number,
	front: { number },
	back: { number },
	color: Color3,
	material: Enum.Material?,
	tilt: CFrame?, -- a knock or two (the Rustbucket)
}

local function fender(parent: Instance, x: number, z0: number, z1: number, s: FenderStyle)
	local inset = s.r * 0.66
	local za, zb = z0 - inset, z1 + inset
	local tilt = s.tilt or CFrame.identity
	deco(
		parent,
		"Fender",
		V3(s.width, s.thick, zb - za),
		CF(x, s.top - s.thick / 2, (za + zb) / 2) * tilt,
		s.color,
		s.material
	)
	local fh, bh = s.top - s.front[2], s.top - s.back[2]
	decoWedge(
		parent,
		"Fender",
		V3(s.width, fh, s.front[1]),
		CF(x, s.top - fh / 2, za - s.front[1] / 2) * tilt,
		s.color,
		s.material
	)
	decoWedge(
		parent,
		"Fender",
		V3(s.width, bh, s.back[1]),
		CF(x, s.top - bh / 2, zb + s.back[1] / 2) * CFrame.Angles(0, math.pi, 0),
		s.color,
		s.material
	)
end

-- A wheel: the tyre (named "Wheel", the part Rig motors) with its rim and a
-- square hub as children, so the whole wheel spins as one. The hub's
-- corners make the spin readable.
type WheelStyle = {
	rim: Color3,
	rimMaterial: Enum.Material?,
	rimScale: number?,
	hub: Color3?,
	steer: boolean,
	rear: boolean,
}

local function wheel(parent: Instance, center: Vector3, r: number, w: number, s: WheelStyle): Part
	local cf = CF(center)
	local tyre = Kit.cylinder(parent, "Wheel", w, r * 2, cf, TYRE, M.Rubber)
	Kit.decor(tyre)
	tyre:SetAttribute("Radius", r)
	tyre:SetAttribute("Steer", s.steer)
	tyre:SetAttribute("Rear", s.rear)
	decoCyl(tyre, "Rim", w + 0.06, r * 2 * (s.rimScale or 0.6), cf, s.rim, s.rimMaterial or M.Metal)
	if s.hub then
		local h = r * 0.5
		deco(tyre, "Hub", V3(w + 0.16, h, h), cf * CFrame.Angles(math.rad(45), 0, 0), s.hub, M.Metal)
	end
	return tyre
end

-- Every wheel of a truck: the first axle steers, the last ones are "Rear".
local function wheels(model: Model, lay: Layout, front: WheelStyle, rear: WheelStyle)
	for i, z in ipairs(lay.wheelZ) do
		local style = if i == 1 then front else rear
		for _, side in ipairs({ -1, 1 }) do
			wheel(model, V3(side * lay.wheelX, lay.wheelRadius, z), lay.wheelRadius, lay.tyreWidth, style)
		end
	end
end

-- A round lamp facing -Z (front) or +Z (back): a bezel and a Neon lens
-- named `name` ("Headlight" / "Taillight").
local function roundLamp(
	parent: Instance,
	name: string,
	cf: CFrame,
	dia: number,
	depth: number,
	bezel: Color3,
	lens: Color3,
	facing: number
)
	local toZ = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's X axis onto Z
	decoCyl(parent, "LampBezel", depth, dia, cf * toZ, bezel, M.Metal)
	decoCyl(parent, name, 0.08, dia * 0.78, cf * CF(0, 0, facing * (depth / 2 + 0.03)) * toZ, lens, M.Neon)
end

-- An exhaust pipe from a to b; smoke comes out of b. `smoke` is how smoky
-- (VehicleFX scales its puffs by it), `smokeColor` its tint.
local function exhaust(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	dia: number,
	color: Color3,
	material: Enum.Material,
	smoke: number,
	smokeColor: Color3
): Part
	local pipe = decoRod(parent, "Exhaust", a, b, dia, color, material)
	pipe:SetAttribute("Smoke", smoke)
	pipe:SetAttribute("SmokeColor", smokeColor)
	-- alongX runs X down the pipe; a quarter turn about Z puts +Y there.
	local out = (alongX(a, b) - (a + b) / 2 + b) * CFrame.Angles(0, 0, -math.pi / 2)
	local att = Instance.new("Attachment")
	att.Name = "ExhaustOut"
	att.CFrame = pipe.CFrame:ToObjectSpace(out)
	att.Parent = pipe
	return pipe
end

local function steeringWheel(parent: Instance, center: Vector3, dia: number)
	local dir = V3(0, 0.55, 0.835).Unit -- tilted toward the driver
	decoRod(parent, "SteeringWheel", center - dir * 0.05, center + dir * 0.05, dia, BLACK, M.SmoothPlastic)
end

local function driverSeat(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = size
	seat.CFrame = cf
	seat.Color = color
	seat.Material = material
	seat.Anchored = true
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CanCollide = false
	seat.CanTouch = false -- no sitting by bumping into it: the Drive prompt seats the owner
	seat.HeadsUpDisplay = false
	seat.Parent = model
	return seat
end

local function bedFloor(model: Model, name: string, width: number, length: number, y: number, z: number, color: Color3)
	return hull(model, name, V3(width, TruckLayout.BedFloorThickness, length), CF(0, y, z), color, M.WoodPlanks)
end

local function frictionlessSkid(model: Model, name: string, size: Vector3, cf: CFrame)
	local skid = Kit.part(model, name, size, cf, FRAME, M.SmoothPlastic)
	skid.Transparency = 1
	skid.CanQuery = false
	skid.CanTouch = false
	skid.CastShadow = false
	-- Slides over the ground; the Drive constraint supplies the grip.
	skid.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	return skid
end

---------------------------------------------------------------------------
-- One builder per style
---------------------------------------------------------------------------

type Ctx = {
	model: Model,
	def: TruckDef,
	lay: Layout,
	paint: Color3,
	rng: Rng,
}

local builders: { [string]: (Ctx) -> () } = {}

-- The Rustbucket: held together by hope.
builders.farm = function(c: Ctx)
	local m, lay, paint, rng = c.model, c.lay, c.paint, c.rng
	local W, f = lay.width, lay.front
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF, zR = lay.wheelZ[1], lay.wheelZ[2]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local primer = hex("#7F8E6E") -- the replacement door, never painted
	local cream = hex("#D8C6A0")
	local oldMetal = hex("#6E5D50")
	local wood = hex("#7C5A3A")
	local hoodW = W * 0.5

	deco(m, "Frame", V3(W - 1.2, 0.8, lay.length - 0.8), CF(0, 1.4, 0), FRAME, M.Metal)

	-- Front: a narrow hood between big separate fenders, a cream grille
	-- shell and a bumper that has met a few stumps.
	deco(
		m,
		"Bumper",
		V3(W + 0.5, 0.42, 0.45),
		CF(0, 1.25, f + 0.2) * CFrame.Angles(0, 0.04, 0.05),
		oldMetal,
		M.CorrodedMetal
	)
	deco(m, "Hood", V3(hoodW, 1.2, 2.5), CF(0, 2.4, f + 1.8), paint, M.Metal)
	deco(m, "HoodCrown", V3(hoodW - 0.5, 0.22, 2.5), CF(0, 3.11, f + 1.8), Kit.shade(paint, 0.04), M.Metal)
	deco(m, "Grille", V3(hoodW + 0.12, 1.55, 0.3), CF(0, 2.35, f + 0.45), cream, M.Metal)
	deco(m, "GrilleSlats", V3(hoodW - 0.35, 1.15, 0.08), CF(0, 2.3, f + 0.27), hex("#2B2420"), M.Metal)
	deco(m, "EngineBay", V3(W - 0.7, 0.5, 2.4), CF(0, 1.95, f + 1.8), hex("#2B2420"), M.Metal)
	local fenderTop = 2 * r + 0.5
	for _, side in ipairs({ -1, 1 }) do
		local dented = side < 0
		fender(m, side * wx, zF, zF, {
			r = r,
			width = tw + 0.35,
			top = fenderTop,
			thick = 0.42,
			front = { 0.85, 1.35 },
			back = { 0.75, 1.5 },
			color = if dented then Kit.shade(paint, -0.14) else paint,
			material = M.Metal,
			tilt = if dented then CFrame.Angles(0.07, 0, -0.06) else nil,
		})
	end
	-- Bug-eye headlights on the fender crowns; the right one knocked askew.
	for _, side in ipairs({ -1, 1 }) do
		local tilt = if side > 0 then CFrame.Angles(-0.1, 0.16, 0) else CFrame.identity
		roundLamp(
			m,
			"Headlight",
			CF(side * (wx - 0.45), fenderTop + 0.36, zF - 0.25) * tilt,
			0.7,
			0.4,
			oldMetal,
			HEADLIGHT,
			-1
		)
	end

	-- Open cab: cowl, a raked windshield frame, doors (one of them from a
	-- different truck), a bench seat and the canvas top, rolled up for good.
	deco(m, "Cowl", V3(W - 0.2, 1.25, 0.5), CF(0, 2.6, f + 3.3), paint, M.Metal)
	local rake = CFrame.Angles(0.12, 0, 0)
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"WindshieldPost",
			V3(0.16, 1.5, 0.16),
			CF(side * (W / 2 - 0.25), 3.95, f + 3.42) * rake,
			oldMetal,
			M.Metal
		)
	end
	deco(m, "WindshieldTop", V3(W - 0.34, 0.16, 0.16), CF(0, 3.95, f + 3.42) * rake * CF(0, 0.75, 0), oldMetal, M.Metal)
	glass(m, "Windshield", V3(W - 0.66, 1.3, 0.06), CF(0, 3.95, f + 3.42) * rake, 0.5)
	deco(m, "Mirror", V3(0.14, 0.38, 0.5), CF(-(W / 2 - 0.05), 4.1, f + 3.5), oldMetal, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Door",
			V3(0.2, 1.25, 1.75),
			CF(side * (W / 2 - 0.1), 2.6, f + 4.4),
			if side < 0 then primer else paint,
			M.Metal
		)
	end
	driverSeat(m, V3(2.6, 0.5, 1.35), CF(0, 2.1, f + 4.45), hex("#6E4A33"), M.Leather)
	deco(m, "SeatBack", V3(2.7, 1.3, 0.3), CF(0, 2.95, f + 5.15) * CFrame.Angles(0.12, 0, 0), hex("#6E4A33"), M.Leather)
	steeringWheel(m, V3(0, 3.15, f + 3.75), 0.9)
	deco(m, "CabBack", V3(W, 1.5, 0.3), CF(0, 2.75, bedStart + 0.15), paint, M.Metal)
	deco(m, "CanvasTop", V3(W - 0.4, 0.38, 0.62), CF(0, 3.69, bedStart + 0.15), hex("#7D7A52"), M.Fabric)

	-- Bed: weathered side boards with gaps, rusty corner posts, and a
	-- tailgate that hangs open on two bits of rope.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, wood)
	for _, side in ipairs({ -1, 1 }) do
		for _, y in ipairs({ 2.75, 3.45 }) do
			hull(
				m,
				"BedBoard",
				V3(0.22, 0.5, lay.bedLength - 0.3),
				CF(side * (W / 2 - 0.11), y, lay.bedCenterZ + 0.15),
				Kit.vary(wood, rng, 0.06),
				M.WoodPlanks
			)
		end
		deco(
			m,
			"BedPost",
			V3(0.28, 1.45, 0.28),
			CF(side * (W / 2 - 0.14), 3.22, bedEnd - 0.14),
			oldMetal,
			M.CorrodedMetal
		)
	end
	local hinge = CF(0, 2.5, bedEnd - 0.1) * CFrame.Angles(0.22, 0, 0)
	hull(m, "Tailgate", V3(W - 0.62, 1.1, 0.2), hinge * CF(0, 0.55, 0), Kit.vary(wood, rng, 0.05), M.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		decoRod(
			m,
			"Rope",
			(hinge * CF(side * ((W - 0.62) / 2 - 0.12), 1.05, 0)).Position,
			V3(side * (W / 2 - 0.14), 3.85, bedEnd - 0.14),
			0.09,
			ROPE,
			M.Fabric
		)
	end
	for _, side in ipairs({ -1, 1 }) do
		fender(m, side * wx, zR, zR, {
			r = r,
			width = tw + 0.35,
			top = 2 * r + 0.45,
			thick = 0.38,
			front = { 0.7, 1.5 },
			back = { 0.6, 1.6 },
			color = Kit.vary(paint, rng, 0.05),
			material = M.Metal,
		})
		local z0, z1 = zF + 0.66 * r + 0.75, zR - 0.66 * r - 0.7
		deco(
			m,
			"RunningBoard",
			V3(1.0, 0.16, z1 - z0),
			CF(side * (wx - 0.05), 1.42, (z0 + z1) / 2),
			Kit.vary(wood, rng, 0.05),
			M.WoodPlanks
		)
	end

	-- Rust, and lights that don't match.
	deco(m, "Rust", V3(0.05, 0.5, 0.75), CF(-(hoodW / 2 + 0.02), 2.45, f + 2.2), RUST, M.CorrodedMetal)
	deco(m, "Rust", V3(0.7, 0.45, 0.05), hinge * CF(0.75, 0.45, 0.12), RUST, M.CorrodedMetal)
	decoCyl(
		m,
		"Taillight",
		0.1,
		0.34,
		CF(-(W / 2 - 0.14), 3.3, bedEnd + 0.02) * CFrame.Angles(0, math.pi / 2, 0),
		TAILLIGHT,
		M.Neon
	)
	deco(m, "Taillight", V3(0.3, 0.24, 0.08), CF(W / 2 - 0.14, 3.3, bedEnd + 0.02), TAILLIGHT, M.Neon)
	exhaust(
		m,
		V3(-1.2, 1.15, bedEnd - 1.2),
		V3(-1.3, 1.02, lay.length / 2 + 0.45),
		0.3,
		oldMetal,
		M.CorrodedMetal,
		1,
		hex("#4F4842")
	)

	local hub = hex("#3A322C")
	wheels(
		m,
		lay,
		{ rim = cream, hub = hub, steer = true, rear = false },
		{ rim = cream, hub = hub, steer = false, rear = true }
	)
	-- One wheel came off another truck.
	for _, d in ipairs(m:GetChildren()) do
		if d.Name == "Wheel" and d:IsA("BasePart") and d.CFrame.X > 0 and d.CFrame.Z < 0 then
			local rim = d:FindFirstChild("Rim")
			if rim and rim:IsA("BasePart") then
				rim.Color = paint
			end
		end
	end
end

-- The Pickup: a rounded, enclosed cab and plenty of chrome.
builders.pickup = function(c: Ctx)
	local m, lay, paint = c.model, c.lay, c.paint
	local W, L, f = lay.width, lay.length, lay.front
	local wx = lay.wheelX
	local zF, zR = lay.wheelZ[1], lay.wheelZ[2]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local cream = hex("#EFE6D2")

	deco(m, "Frame", V3(W - 1.4, 0.8, L - 1.0), CF(0, 1.4, 0), FRAME, M.Metal)
	deco(m, "Bumper", V3(W + 0.35, 0.45, 0.45), CF(0, 1.35, f + 0.22), CHROME, M.Metal)
	deco(m, "Nose", V3(W - 0.8, 1.2, 3.0), CF(0, 2.2, f + 1.9), paint, M.Metal)
	deco(m, "Hood", V3(W - 1.7, 0.5, 2.6), CF(0, 3.05, f + 2.1), paint, M.Metal)
	decoWedge(m, "HoodNose", V3(W - 1.7, 0.5, 0.4), CF(0, 3.05, f + 0.6), paint, M.Metal)
	deco(m, "Grille", V3(W - 1.9, 1.0, 0.14), CF(0, 2.15, f + 0.35), CHROME_HI, M.Metal)
	deco(m, "GrilleBars", V3(W - 2.3, 0.65, 0.06), CF(0, 2.15, f + 0.27), hex("#2A2D33"), M.Metal)

	-- Pontoon front fenders with the headlights in their noses.
	local fz0, fz1 = f + 0.55, zF + 0.95
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (wx + 0.05)
		deco(m, "Fender", V3(1.3, 0.6, fz1 - fz0), CF(x, 2.5, (fz0 + fz1) / 2), paint, M.Metal)
		decoWedge(m, "Fender", V3(1.3, 0.6, 0.9), CF(x, 2.5, fz1 + 0.45) * CFrame.Angles(0, math.pi, 0), paint, M.Metal)
		roundLamp(m, "Headlight", CF(x, 2.5, fz0), 0.55, 0.24, CHROME, HEADLIGHT, -1)
	end

	-- Cab: glass all round under a cream roof, from the body's top (`belt`)
	-- to the roof's underside: 4 studs over the seat, room for a seated
	-- avatar in a hat (TruckArt.spec). The windshield leans back from the
	-- body's front edge to just under the roof.
	local belt, roofY = 3.3, 6.05
	deco(m, "Cab", V3(W, 1.65, 2.2), CF(0, 2.475, f + 4.5), paint, M.Metal)
	glass(m, "CabGlass", V3(W - 0.3, roofY - belt, 1.7), CF(0, (belt + roofY) / 2, f + 4.7), 0.45)
	local screenLo, screenHi = V3(0, belt, f + 3.42), V3(0, roofY - 0.05, f + 3.8)
	local rise = screenHi - screenLo
	local screen = CF((screenLo + screenHi) / 2) * CFrame.Angles(math.atan2(rise.Z, rise.Y), 0, 0)
	glass(m, "Windshield", V3(W - 0.5, rise.Magnitude, 0.06), screen, 0.4)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "Pillar", V3(0.2, rise.Magnitude + 0.05, 0.2), CF(side * (W / 2 - 0.2), 0, 0) * screen, cream, M.Metal)
		deco(
			m,
			"Pillar",
			V3(0.25, roofY - belt, 0.3),
			CF(side * (W / 2 - 0.17), (belt + roofY) / 2, f + 5.45),
			cream,
			M.Metal
		)
		deco(m, "Mirror", V3(0.14, 0.36, 0.5), CF(side * (W / 2 + 0.12), 3.6, f + 3.62), CHROME_HI, M.Metal)
	end
	deco(m, "Roof", V3(W - 0.15, 0.32, 2.15), CF(0, roofY + 0.16, f + 4.62), cream, M.Metal)
	driverSeat(m, V3(2.4, 0.45, 1.25), CF(0, 1.8, f + 4.55), hex("#8C6A4A"), M.Leather)
	deco(m, "SeatBack", V3(2.5, 1.3, 0.28), CF(0, 2.65, f + 5.3) * CFrame.Angles(0.1, 0, 0), hex("#8C6A4A"), M.Leather)
	steeringWheel(m, V3(0, 3.1, f + 3.95), 0.85)

	-- Chrome spear down each side, black running boards.
	local trimZ0 = f + 3.4
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Trim",
			V3(0.06, 0.12, bedEnd - trimZ0),
			CF(side * (W / 2 + 0.03), 2.95, (trimZ0 + bedEnd) / 2),
			CHROME_HI,
			M.Metal
		)
		local z0, z1 = fz1 + 0.9, zR - 1.45
		deco(m, "RunningBoard", V3(0.9, 0.14, z1 - z0), CF(side * (W / 2 + 0.25), 1.45, (z0 + z1) / 2), BLACK, M.Rubber)
	end

	-- Bed: smooth painted walls with chrome caps; a flared rear fender over
	-- each wheel.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#5E4632"))
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 - 0.125)
		hull(m, "BedWall", V3(0.25, 1.3, lay.bedLength), CF(x, 3.15, lay.bedCenterZ), paint, M.Metal)
		deco(m, "BedCap", V3(0.36, 0.1, lay.bedLength), CF(x, 3.85, lay.bedCenterZ), CHROME_HI, M.Metal)
		local fx = side * (W / 2 + 0.32)
		deco(m, "Fender", V3(0.75, 0.55, 2.3), CF(fx, 2.45, zR), paint, M.Metal)
		decoWedge(m, "Fender", V3(0.75, 0.55, 0.7), CF(fx, 2.45, zR - 1.5), paint, M.Metal)
		decoWedge(
			m,
			"Fender",
			V3(0.75, 0.55, 0.7),
			CF(fx, 2.45, zR + 1.5) * CFrame.Angles(0, math.pi, 0),
			paint,
			M.Metal
		)
		deco(m, "Taillight", V3(0.26, 0.6, 0.08), CF(x, 3.3, bedEnd + 0.02), TAILLIGHT, M.Neon)
	end
	deco(m, "BedFront", V3(W - 0.5, 1.3, 0.25), CF(0, 3.15, bedStart + 0.125), paint, M.Metal)
	hull(m, "Tailgate", V3(W - 0.5, 1.3, 0.25), CF(0, 3.15, bedEnd - 0.125), paint, M.Metal)
	deco(m, "RearBumper", V3(W + 0.2, 0.42, 0.4), CF(0, 1.5, L / 2 - 0.15), CHROME, M.Metal)
	exhaust(m, V3(1.3, 1.25, bedEnd - 0.6), V3(1.35, 1.2, L / 2 + 0.25), 0.24, CHROME, M.Metal, 0.3, hex("#8A8580"))

	local front = { rim = cream, rimScale = 0.64, hub = CHROME_HI, steer = true, rear = false }
	local back = { rim = cream, rimScale = 0.64, hub = CHROME_HI, steer = false, rear = true }
	wheels(m, lay, front, back)
	gloss(m, paint, 0.05)
end

-- The Scout ATV: a quad built for the trail, nothing to carry.
builders.atv = function(c: Ctx)
	local m, lay, paint = c.model, c.lay, c.paint
	local f, b = lay.front, lay.length / 2
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF, zR = lay.wheelZ[1], lay.wheelZ[2]
	local plastic = hex("#34372F")
	local rack = hex("#45484A")

	deco(m, "Frame", V3(1.5, 0.8, 3.6), CF(0, 1.35, 0), FRAME, M.Metal)
	decoCyl(m, "Engine", 1.8, 0.85, CF(0, 1.45, 0.2), hex("#7E8287"), M.Metal)

	-- Plastic fenders over all four wheels; racks on top front and back.
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (wx - 0.08)
		local style: FenderStyle = {
			r = r,
			width = tw + 0.2,
			top = 2 * r + 0.32,
			thick = 0.26,
			front = { 0.55, 1.55 },
			back = { 0.45, 1.75 },
			color = paint,
			material = M.SmoothPlastic,
		}
		fender(m, x, zF, zF, style)
		style.front, style.back = { 0.45, 1.75 }, { 0.55, 1.55 }
		fender(m, x, zR, zR, style)
		deco(m, "Footrest", V3(0.85, 0.12, 1.8), CF(side * 1.25, 1.62, 0), plastic, M.DiamondPlate)
		deco(m, "Headlight", V3(0.5, 0.26, 0.1), CF(side * 0.55, 2.05, f + 0.22), HEADLIGHT, M.Neon)
		deco(m, "Taillight", V3(0.32, 0.18, 0.06), CF(side * 0.5, 2.05, b - 0.12), TAILLIGHT, M.Neon)
	end
	deco(m, "Nose", V3(2.2, 0.55, 1.6), CF(0, 2.0, f + 1.05), paint, M.SmoothPlastic)
	deco(m, "RearFascia", V3(1.7, 0.5, 0.3), CF(0, 2.0, b - 0.3), plastic, M.SmoothPlastic)

	-- Brush guard and racks (tube). The front rack stops short of a seated
	-- rider's feet (straight legs reach 2 studs ahead of the seat's middle).
	local rackY = 2.55
	local seatZ = 0.45
	decoRod(m, "Guard", V3(-1.05, 1.55, f + 0.05), V3(1.05, 1.55, f + 0.05), 0.16, BLACK, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		decoRod(m, "Guard", V3(side * 0.9, 1.55, f + 0.05), V3(side * 0.95, rackY, f + 0.35), 0.14, BLACK, M.Metal)
	end
	local function rackFrame(z0: number, z1: number, y: number)
		for _, side in ipairs({ -1, 1 }) do
			decoRod(m, "Rack", V3(side * 1.45, y, z0), V3(side * 1.45, y, z1), 0.12, rack, M.Metal)
		end
		decoRod(m, "Rack", V3(-1.45, y, z0), V3(1.45, y, z0), 0.12, rack, M.Metal)
		decoRod(m, "Rack", V3(-1.45, y, z1), V3(1.45, y, z1), 0.12, rack, M.Metal)
	end
	rackFrame(f + 0.35, seatZ - 2.2, rackY)
	rackFrame(zR - 0.75, b - 0.05, rackY + 0.05)
	deco(m, "SupplyBox", V3(1.3, 0.6, 0.95), CF(0, 2.93, zR + 0.15), hex("#9B6B3E"), M.WoodPlanks)

	-- Tank, bars and the saddle. The bars ride just over a seated rider's
	-- straight legs (the seat's top + 0.5).
	local barY = 3.4
	deco(m, "Tank", V3(1.25, 0.55, 0.95), CF(0, 2.45, -1.0), paint, M.SmoothPlastic)
	decoCyl(m, "TankCap", 0.12, 0.3, CF(0, 2.78, -1.05) * CFrame.Angles(0, 0, math.pi / 2), CHROME, M.Metal)
	decoRod(m, "SteeringColumn", V3(0, 2.3, -1.55), V3(0, barY - 0.05, -1.15), 0.14, BLACK, M.Metal)
	decoRod(m, "Handlebar", V3(-1.0, barY, -1.1), V3(1.0, barY, -1.1), 0.13, rack, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		decoRod(m, "Grip", V3(side * 0.8, barY, -1.1), V3(side * 1.15, barY, -1.1), 0.22, BLACK, M.Rubber)
	end
	deco(m, "SeatBase", V3(1.35, 0.5, 2.1), CF(0, 2.05, 0.45), plastic, M.SmoothPlastic)
	driverSeat(m, V3(1.15, 0.45, 1.9), CF(0, 2.525, seatZ), hex("#6B4A33"), M.Leather)

	exhaust(m, V3(0.85, 1.75, 1.5), V3(0.95, 1.95, b + 0.1), 0.24, hex("#55595C"), M.Metal, 0.35, hex("#9A958F"))
	-- The scout's flag: seen over the brush from far away.
	local poleTop = V3(-1.5, 6.2, b - 0.15)
	decoRod(m, "FlagPole", V3(-1.45, rackY, b - 0.2), poleTop, 0.1, BLACK, M.Metal)
	decoWedge(
		m,
		"Flag",
		V3(0.05, 0.7, 1.1),
		CF(poleTop.X, poleTop.Y - 0.4, poleTop.Z + 0.55) * CFrame.Angles(0, math.pi, 0),
		hex("#F08A24"),
		M.Fabric
	)

	local rim = hex("#B5B9B4")
	wheels(
		m,
		lay,
		{ rim = rim, rimScale = 0.55, hub = plastic, steer = true, rear = false },
		{ rim = rim, rimScale = 0.55, hub = plastic, steer = false, rear = true }
	)
end

-- A boxy cab with glass all round: lower body, glass, pillars, roof.
local function boxCab(
	m: Model,
	W: number,
	z: number,
	length: number,
	y0: number,
	y1: number,
	y2: number,
	paint: Color3,
	pillar: Color3,
	roof: Color3
)
	deco(m, "Cab", V3(W, y1 - y0, length), CF(0, (y0 + y1) / 2, z), paint, M.Metal)
	glass(m, "CabGlass", V3(W - 0.4, y2 - y1, length - 0.3), CF(0, (y1 + y2) / 2, z), 0.45)
	for _, side in ipairs({ -1, 1 }) do
		for _, end_ in ipairs({ -1, 1 }) do
			deco(
				m,
				"Pillar",
				V3(0.24, y2 - y1, 0.24),
				CF(side * (W / 2 - 0.32), (y1 + y2) / 2, z + end_ * (length / 2 - 0.25)),
				pillar,
				M.Metal
			)
		end
	end
	deco(m, "Roof", V3(W - 0.1, 0.32, length + 0.1), CF(0, y2 + 0.16, z), roof, M.Metal)
end

-- The Flatbed: a square-jawed work truck with stake sides.
builders.flatbed = function(c: Ctx)
	local m, lay, paint, rng = c.model, c.lay, c.paint, c.rng
	local W, L, f, b = lay.width, lay.length, lay.front, lay.length / 2
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF = lay.wheelZ[1]
	local zRear, zTandem = lay.wheelZ[2], lay.wheelZ[3] or lay.wheelZ[2]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local deckTop = lay.bedFloorY + 0.25
	local steel = hex("#6A6E72")
	local stake = hex("#A0703F")

	deco(m, "Frame", V3(W - 1.8, 0.8, L - 1.2), CF(0, 1.4, 0), FRAME, M.Metal)
	deco(m, "Bumper", V3(W + 0.5, 0.55, 0.5), CF(0, 1.4, f + 0.22), BLACK, M.Metal)
	deco(m, "Hood", V3(W - 0.5, 1.4, 3.0), CF(0, 2.35, f + 1.95), paint, M.Metal)
	deco(m, "Grille", V3(W - 2.2, 0.95, 0.1), CF(0, 2.3, f + 0.42), BLACK, M.Metal)
	deco(m, "GrilleBar", V3(W - 2.4, 0.12, 0.06), CF(0, 2.35, f + 0.36), CHROME, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "Headlight", V3(0.6, 0.42, 0.1), CF(side * 1.85, 2.35, f + 0.42), HEADLIGHT, M.Neon)
		-- Squared-off fenders, front and over the tandem.
		fender(m, side * wx, zF, zF, {
			r = r,
			width = tw + 0.45,
			top = 2 * r + 0.5,
			thick = 0.45,
			front = { 0.5, 1.75 },
			back = { 0.5, 1.85 },
			color = paint,
			material = M.Metal,
		})
		fender(m, side * wx, zTandem, zRear, {
			r = r,
			width = tw + 0.45,
			top = 2 * r + 0.32,
			thick = 0.3,
			front = { 0.45, 1.85 },
			back = { 0.45, 1.85 },
			color = BLACK,
			material = M.Metal,
		})
		deco(m, "Mirror", V3(0.15, 0.8, 0.45), CF(side * (W / 2 + 0.2), 3.9, f + 3.7), BLACK, M.Metal)
	end

	-- Cab (its roof 4 studs over the seat: room for a driver in a hat) and
	-- roof beacon; the stack stands clear of the roof.
	local cabTop = 6.2
	boxCab(m, W, f + 4.6, 2.3, 1.65, 3.25, cabTop, paint, BLACK, hex("#EEEBE3"))
	deco(m, "Beacon", V3(0.8, 0.32, 0.4), CF(0, cabTop + 0.48, f + 4.4), AMBER, M.Neon)
	driverSeat(m, V3(2.4, 0.5, 1.3), CF(0, 1.95, f + 4.65), hex("#4A4440"), M.Fabric)
	steeringWheel(m, V3(0, 3.2, f + 3.95), 0.9)
	exhaust(
		m,
		V3(W / 2 + 0.2, 1.8, f + 5.55),
		V3(W / 2 + 0.2, cabTop + 0.8, f + 5.55),
		0.3,
		steel,
		M.Metal,
		0.45,
		hex("#7D7873")
	)

	-- Headache rack behind the cab.
	local rackZ = bedStart + 0.2
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "HeadacheRack", V3(0.3, 2.8, 0.3), CF(side * (W / 2 - 0.25), deckTop + 1.4, rackZ), steel, M.Metal)
	end
	deco(m, "HeadacheRack", V3(W - 0.2, 0.3, 0.3), CF(0, deckTop + 2.8, rackZ), steel, M.Metal)
	deco(m, "HeadacheRack", V3(W - 0.5, 0.2, 0.2), CF(0, deckTop + 1.6, rackZ), steel, M.Metal)

	-- Deck and stake sides (open at the back).
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#8A6038"))
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 - 0.13)
		for _, z in ipairs({ bedStart + 0.7, lay.bedCenterZ, bedEnd - 0.4 }) do
			hull(m, "Stake", V3(0.26, 2.3, 0.3), CF(x, deckTop + 1.15, z), Kit.vary(stake, rng, 0.05), M.Wood)
		end
		for _, y in ipairs({ deckTop + 0.75, deckTop + 1.7 }) do
			hull(
				m,
				"StakeRail",
				V3(0.2, 0.42, lay.bedLength - 0.5),
				CF(x, y, lay.bedCenterZ + 0.15),
				Kit.vary(stake, rng, 0.06),
				M.WoodPlanks
			)
		end
		deco(
			m,
			"Taillight",
			V3(0.4, 0.3, 0.08),
			CF(side * (W / 2 - 0.35), lay.bedFloorY, bedEnd + 0.02),
			TAILLIGHT,
			M.Neon
		)
	end
	deco(m, "RearBumper", V3(W + 0.2, 0.45, 0.45), CF(0, 1.55, b - 0.2), BLACK, M.Metal)

	local rimColor = hex("#E2E0D8")
	wheels(
		m,
		lay,
		{ rim = rimColor, hub = BLACK, steer = true, rear = false },
		{ rim = rimColor, steer = false, rear = true }
	)
end

-- The Logging Rig: chrome everywhere, built to haul a forest.
builders.rig = function(c: Ctx)
	local m, lay, paint = c.model, c.lay, c.paint
	local W, L, f, b = lay.width, lay.length, lay.front, lay.length / 2
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF = lay.wheelZ[1]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local deckTop = lay.bedFloorY + 0.25
	local steel = hex("#3D4045")
	local post = hex("#A2A8AE")
	local crane = hex("#E3A72F")

	deco(m, "Frame", V3(W - 2.0, 0.9, L - 1.0), CF(0, 1.45, 0), BLACK, M.Metal)
	deco(m, "DeckBeam", V3(W - 1.4, 0.5, lay.bedLength), CF(0, lay.bedFloorY - 0.5, lay.bedCenterZ), steel, M.Metal)

	-- Long nose: chrome bumper and grille, a crowned hood.
	deco(m, "Bumper", V3(W + 0.5, 0.65, 0.6), CF(0, 1.4, f + 0.3), CHROME_HI, M.Foil)
	deco(m, "Hood", V3(3.8, 1.3, 4.0), CF(0, 2.55, f + 2.6), paint, M.Metal)
	deco(m, "HoodTop", V3(3.4, 0.35, 3.2), CF(0, 3.375, f + 3.0), paint, M.Metal)
	decoWedge(m, "HoodNose", V3(3.4, 0.35, 0.8), CF(0, 3.375, f + 1.0), paint, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "Pinstripe", V3(0.04, 0.2, 3.9), CF(side * 1.91, 2.85, f + 2.62), hex("#F1E6CC"), M.SmoothPlastic)
	end
	deco(m, "Grille", V3(2.8, 2.0, 0.25), CF(0, 2.6, f + 0.55), CHROME_HI, M.Foil)
	deco(m, "GrilleBars", V3(2.4, 1.6, 0.06), CF(0, 2.6, f + 0.41), BLACK, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		fender(m, side * wx, zF, zF, {
			r = r,
			width = tw + 0.5,
			top = 2 * r + 0.55,
			thick = 0.45,
			front = { 0.9, 1.55 },
			back = { 0.8, 1.8 },
			color = paint,
			material = M.Metal,
		})
		deco(m, "Headlight", V3(0.75, 0.38, 0.12), CF(side * 2.2, 1.92, f + 0.38), HEADLIGHT, M.Neon)
		-- Polished fuel tanks under the doors, twin stacks at the cab's back
		-- corners, west-coast mirrors.
		decoCyl(
			m,
			"FuelTank",
			2.0,
			0.95,
			CF(side * 2.25, 1.55, f + 5.8) * CFrame.Angles(0, math.pi / 2, 0),
			CHROME_HI,
			M.Foil
		)
		exhaust(
			m,
			V3(side * (W / 2 + 0.25), 2.1, f + 6.75),
			V3(side * (W / 2 + 0.25), 8.0, f + 6.75),
			0.42,
			CHROME_HI,
			M.Foil,
			0.2,
			hex("#A8A39D")
		)
		deco(m, "Mirror", V3(0.15, 0.95, 0.45), CF(side * (W / 2 + 0.22), 4.9, f + 4.75), CHROME_HI, M.Foil)
	end

	-- A tall day cab (its roof 4 studs over the seat: room for a driver in
	-- a hat): roof markers, sun visor.
	local cabTop = 7.0
	boxCab(m, W, f + 5.8, 2.4, 1.9, 4.0, cabTop, paint, paint, paint)
	deco(
		m,
		"Visor",
		V3(W - 0.2, 0.14, 0.55),
		CF(0, cabTop - 0.02, f + 4.45) * CFrame.Angles(0.15, 0, 0),
		BLACK,
		M.Metal
	)
	for _, x in ipairs({ -1.2, 0, 1.2 }) do
		deco(m, "Marker", V3(0.32, 0.16, 0.2), CF(x, cabTop + 0.4, f + 4.75), AMBER, M.Neon)
	end
	driverSeat(m, V3(2.4, 0.5, 1.3), CF(0, 2.75, f + 5.95), hex("#3B2F2A"), M.Leather)
	steeringWheel(m, V3(0, 4.3, f + 5.15), 1.0)

	-- Bulkhead, as tall as the cab, with a stub knuckle crane parked on top
	-- (its turret clear of the cab's glass): turret, mast, a boom reaching
	-- back over the load and a grapple hanging off its end.
	local bulkTop = cabTop
	local cz = bedStart + 0.15
	local bulkH = bulkTop - deckTop
	deco(m, "Bulkhead", V3(W, bulkH, 0.3), CF(0, deckTop + bulkH / 2, cz), hex("#5C6166"), M.DiamondPlate)
	Kit.decor(Kit.post(m, "Crane", V3(0.9, bulkTop, cz), 0.5, 1.15, crane, M.Metal), false)
	Kit.decor(Kit.post(m, "Crane", V3(0.9, bulkTop + 0.5, cz), 1.5, 0.5, crane, M.Metal), false)
	local tip = V3(0.9, bulkTop + 2.4, cz + 4.6)
	plank(m, "Crane", V3(0.9, bulkTop + 1.8, cz - 0.3), tip, 0.5, 0.5, crane, M.Metal)
	plank(m, "Crane", tip, tip - V3(0, 1.3, 0), 0.32, 0.32, Kit.shade(crane, -0.15), M.Metal)
	deco(m, "Grapple", V3(0.75, 0.45, 0.6), CF(tip - V3(0, 1.5, 0)), BLACK, M.Metal)

	-- Deck with steel stanchions.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#5E4636"))
	for _, z in ipairs({ bedStart + 6.0, bedStart + 12.0, bedEnd - 0.25 }) do
		for _, side in ipairs({ -1, 1 }) do
			hull(m, "Stanchion", V3(0.28, 3.1, 0.28), CF(side * (W / 2 - 0.14), deckTop + 1.55, z), post, M.Metal)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Taillight",
			V3(0.45, 0.32, 0.08),
			CF(side * (W / 2 - 0.4), lay.bedFloorY, bedEnd + 0.02),
			TAILLIGHT,
			M.Neon
		)
	end
	deco(m, "RearBumper", V3(W, 0.45, 0.45), CF(0, 1.6, b - 0.25), BLACK, M.Metal)

	wheels(
		m,
		lay,
		{ rim = CHROME_HI, rimMaterial = M.Foil, rimScale = 0.62, hub = CHROME, steer = true, rear = false },
		{ rim = CHROME, rimScale = 0.62, steer = false, rear = true }
	)
	gloss(m, paint, 0.08) -- it gleams
end

---------------------------------------------------------------------------
-- Trailers
---------------------------------------------------------------------------

-- Adds a trailer to `model` (a truck built by TruckArt.Build), behind the
-- truck in truck-local studs: tongue, bed ("TrailerBed"), skid
-- ("TrailerSkid"), axle(s), fenders, lights and the style's sides.
function TruckArt.AddTrailer(model: Model, trailer: TrailerDef, tl: TrailerLayout)
	local W = tl.width
	local bs, be, bc, y = tl.bedStart, tl.bedStart + tl.bedLength, tl.bedCenterZ, tl.bedFloorY
	local r, tw = tl.wheelRadius, tl.tyreWidth
	local paint = hex(trailer.look.color)
	local rng = Kit.rng(#trailer.id * 97 + tl.bedLength)
	local deckTop = y + 0.25
	local wood = hex("#8A6038")

	local deckColor = if tl.style == "heavy" then hex("#5B4A3C") else wood
	bedFloor(model, "TrailerBed", W, tl.bedLength, y, bc, deckColor)
	frictionlessSkid(model, "TrailerSkid", V3(W - 0.4, 1, tl.bedLength - 1), CF(0, 0.5, bc))
	deco(model, "TrailerFrame", V3(W - 1.2, 0.35, tl.bedLength), CF(0, y - 0.42, bc), FRAME, M.Metal)

	-- A-frame tongue to a coupler at the truck's back.
	local hitchZ = tl.hitchZ
	for _, side in ipairs({ -1, 1 }) do
		decoRod(
			model,
			"Tongue",
			V3(side * (W / 2 - 0.7), 1.35, bs + 0.2),
			V3(side * 0.15, 1.35, hitchZ + 0.5),
			0.22,
			FRAME,
			M.Metal
		)
	end
	deco(model, "Coupler", V3(0.45, 0.35, 0.7), CF(0, 1.35, hitchZ + 0.3), BLACK, M.Metal)

	-- Axles, wheels and flat-topped fenders just outside the deck.
	local heavy = tl.style == "heavy"
	local rim = if heavy then hex("#C9CDD1") else hex("#D8C6A0")
	for _, z in ipairs(tl.axleZ) do
		decoRod(model, "Axle", V3(-tl.wheelX, r, z), V3(tl.wheelX, r, z), 0.2, FRAME, M.Metal)
		for _, side in ipairs({ -1, 1 }) do
			wheel(model, V3(side * tl.wheelX, r, z), r, tw, {
				rim = rim,
				hub = if heavy then nil else hex("#3A322C"),
				steer = false,
				rear = true,
			})
		end
	end
	local z0, z1 = tl.axleZ[1], tl.axleZ[#tl.axleZ]
	local fenderColor = if heavy then hex("#8E949A") else paint
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 + (tw + 0.3) / 2 - 0.05)
		fender(model, x, z0, z1, {
			r = r,
			width = tw + 0.3,
			top = 2 * r + 0.24,
			thick = 0.2,
			front = { 0.45, 1.5 },
			back = { 0.4, 1.55 },
			color = fenderColor,
			material = if heavy then M.DiamondPlate else M.Metal,
		})
		deco(model, "Taillight", V3(0.4, 0.28, 0.08), CF(side * (W / 2 - 0.35), y, be + 0.02), TAILLIGHT, M.Neon)
	end

	if tl.style == "pony" then
		-- A little wooden farm trailer: plank sides, a drop-down back.
		for _, side in ipairs({ -1, 1 }) do
			for _, by in ipairs({ deckTop + 0.21, deckTop + 0.76 }) do
				hull(
					model,
					"TrailerBoard",
					V3(0.22, 0.42, tl.bedLength),
					CF(side * (W / 2 - 0.11), by, bc),
					Kit.vary(paint, rng, 0.06),
					M.WoodPlanks
				)
			end
			deco(
				model,
				"TrailerPost",
				V3(0.28, 1.15, 0.28),
				CF(side * (W / 2 - 0.14), deckTop + 0.575, be - 0.14),
				FRAME,
				M.Metal
			)
		end
		hull(
			model,
			"TrailerFront",
			V3(W, 0.97, 0.22),
			CF(0, deckTop + 0.485, bs + 0.11),
			Kit.vary(paint, rng, 0.05),
			M.WoodPlanks
		)
		hull(
			model,
			"TrailerGate",
			V3(W - 0.56, 0.97, 0.22),
			CF(0, deckTop + 0.485, be - 0.11),
			Kit.vary(paint, rng, 0.05),
			M.WoodPlanks
		)
	elseif tl.style == "ranch" then
		-- Painted stake posts with two wooden rails, a tall headboard.
		local rail = hex("#A77B4C")
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (W / 2 - 0.12)
			for _, z in ipairs({ bs + 0.3, bc, be - 0.3 }) do
				hull(model, "TrailerStake", V3(0.24, 1.8, 0.24), CF(x, deckTop + 0.9, z), paint, M.Metal)
			end
			for _, ry in ipairs({ deckTop + 0.75, deckTop + 1.5 }) do
				hull(
					model,
					"TrailerRail",
					V3(0.18, 0.35, tl.bedLength - 0.2),
					CF(x, ry, bc),
					Kit.vary(rail, rng, 0.06),
					M.WoodPlanks
				)
			end
		end
		hull(model, "TrailerFront", V3(W, 1.8, 0.2), CF(0, deckTop + 0.9, bs + 0.1), paint, M.Metal)
	else
		-- Heavy Hauler: a steel headboard, tall stanchions, amber markers.
		local steel = hex("#9AA1A8")
		for _, side in ipairs({ -1, 1 }) do
			for _, z in ipairs({ bs + 0.35, bc + 0.6, be - 0.3 }) do
				hull(
					model,
					"TrailerStanchion",
					V3(0.3, 2.6, 0.3),
					CF(side * (W / 2 - 0.15), deckTop + 1.3, z),
					steel,
					M.Metal
				)
			end
			deco(model, "Marker", V3(0.08, 0.2, 0.35), CF(side * (W / 2 + 0.01), y, bc), AMBER, M.Neon)
		end
		hull(model, "TrailerFront", V3(W, 2.0, 0.25), CF(0, deckTop + 1.0, bs + 0.125), paint, M.Metal)
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

local function seedOf(id: string): number
	local n = 0
	for i = 1, #id do
		n += string.byte(id, i) * i
	end
	return n
end

-- A truck (and its trailer, when given) at the origin, ground y = 0, front
-- -Z. Every part is anchored; Rig turns it into one rigid body.
function TruckArt.Build(def: TruckDef, layout: Layout?, trailer: TrailerDef?, trailerLayout: TrailerLayout?): Model
	local lay = layout or TruckLayout.For(def)
	local model = Instance.new("Model")
	model.Name = def.id

	-- The chassis carries the truck (its only massive part); the frictionless
	-- skid under it is what touches the ground.
	local chassis = Kit.part(
		model,
		"Chassis",
		V3(lay.width - 0.2, 1, lay.length - 0.4),
		CF(0, TruckLayout.ChassisY, 0),
		FRAME,
		M.Wood
	)
	chassis.Transparency = 1
	chassis.CanTouch = false
	chassis.CastShadow = false
	model.PrimaryPart = chassis
	frictionlessSkid(model, "Skid", V3(lay.width - 0.4, 1, lay.length - 1), CF(0, 0.5, 0))

	local build = builders[lay.style] or builders.flatbed
	build({
		model = model,
		def = def,
		lay = lay,
		paint = hex(def.look.color),
		rng = Kit.rng(seedOf(def.id)),
	})

	if trailer then
		TruckArt.AddTrailer(model, trailer, trailerLayout or TruckLayout.ForTrailer(trailer, lay))
	end

	-- Where the "Load logs" prompt hangs: just behind the last bed.
	local lastBed = model:FindFirstChild("TrailerBed") or model:FindFirstChild("BedFloor")
	if lastBed and lastBed:IsA("BasePart") then
		local point = Instance.new("Attachment")
		point.Name = "LoadPoint"
		point.CFrame = CF(0, 1, lastBed.Size.Z / 2 + 0.6)
		point.Parent = lastBed
	end
	return model
end

-- Makes a built truck one rigid body: the chassis anchored (parked), every
-- other part unanchored and massless, welded to the chassis (or to the
-- part it's a child of), and each wheel joined to the chassis by a Motor6D
-- "Axle" whose Transform spins and steers it (VehicleFX, on each client).
function TruckArt.Rig(model: Model)
	local chassis = model.PrimaryPart
	assert(chassis, "[TruckArt] Rig: the model has no Chassis")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis then
			d.Anchored = false
			d.Massless = true
			local parent = d.Parent
			if d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
				local axle = Instance.new("Motor6D")
				axle.Name = "Axle"
				axle.Part0 = chassis
				axle.Part1 = d
				axle.C0 = chassis.CFrame:ToObjectSpace(d.CFrame)
				axle.C1 = CFrame.identity
				axle.MaxVelocity = 0 -- only Transform turns it
				axle.Parent = d
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = if parent and parent:IsA("BasePart") then parent else chassis
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	chassis.Anchored = true
end

-- A log lying across a bed at `slot` (relative to `floor`, a bed floor
-- part): TreeArt's log, bark and pale end caps, nudged a little so a full
-- load looks stacked by hand. Anchored; VehicleService welds it.
function TruckArt.BedLog(floor: BasePart, slot: Vector3, wood: WoodDef, length: number, index: number): Model
	local rng = Kit.rng(index * 31 + seedOf(wood.id))
	local log = TreeArt.Log(wood, length * rng:range(0.92, 1), TruckLayout.LogDiameter)
	local nudge = CF(rng:range(-0.06, 0.06), 0, rng:range(-0.03, 0.03)) * CFrame.Angles(0, rng:range(-0.03, 0.03), 0)
	log:PivotTo(floor.CFrame * CF(slot) * nudge)
	log.Name = "BedLog"
	return log
end

return TruckArt
