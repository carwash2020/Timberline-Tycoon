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
--     its bottom flush with the wheel bottoms (y = 0), with a "Ramp"
--     wedge (its child, same rules) at each end so ledges ride under it.
--   * "DriverSeat": a VehicleSeat, a direct child of the model.
--   * "BedFloor" (0.5 thick, centred at layout.bedFloorY) when the truck has
--     a bed; layout.logSlots are relative to it. A towed trailer adds
--     "TrailerBed" (same rule, TrailerLayout) and "TrailerSkid" (ramped
--     the same way). Each bed part has one child "BedZone" (AddBedZone):
--     invisible, never colliding or queried, the box the v2 loop's loose
--     wood rides in (TruckLoad). ApplyBedFriction (v2 only) grips the beds.
--   * Exactly one Attachment "LoadPoint", on the last bed part.
--   * "Headlight" and "Taillight" parts (Neon), "Exhaust" parts each with an
--     Attachment "ExhaustOut" (its +Y points out of the pipe) and a "Smoke"
--     attribute (how smoky: 1 = the Rustbucket).
--   * Wheels: a part "Wheel" per wheel (a cylinder along X, the tyre) with
--     attributes Radius, Steer (front wheels) and Rear; its rim, hub cap and
--     bolt are its children. Rig joins each Wheel to the chassis with a Motor6D
--     "Axle" (so clients can spin and steer it through Transform).
--   * Only the chassis, skids, bed floors and bed walls collide (CanTouch
--     off); everything else is decoration (Kit.decor). Nothing near the
--     seat collides, so getting in and out never snags.
--   * Build leaves every part anchored (previews, tests); Rig makes it one
--     rigid body: the chassis anchored, the rest unanchored, massless and
--     welded (WeldConstraint) or motored to it.
--   * Timber Classic (def.classic), added after the body is organized:
--     two DoorPlate parts, each with a BillboardGui "DoorTag" and a
--     TextLabel "DoorName" (MaxDistance 60, TextScaled, wrapped), and a
--     LoadGauge on the dash (SurfaceGui "GaugeGui", Enabled false, TextLabel
--     "Readout"). The gauge is in the world, not a screen HUD.
--
-- Sizes (M1.5, V2_PLAN §4c): each body is drawn round its layout (width,
-- cab, bed, wheels, the walls' height), and each cab round a seated driver
-- who stays avatar-sized: the seat (SEAT_TOP) and the roof (HEADROOM over
-- it) are set per truck, so a hat clears every roof (TruckArt.spec).
-- Phase 12 grew every truck and trailer TruckLayout.Scale (1.3) times
-- again: the builders below still draw in M1.5's units, round the layout
-- shrunk by Scale (designOf), and Build grows the drawn body by Scale
-- (grow, the way Kit.scaleModel grows the shops), so each truck keeps its
-- look; the chassis, the skids, the BedZones and the LoadPoint are added
-- at full size after. A seated driver sits higher and has more room.

local ClassicGauge = require(script.Parent.Parent.ClassicGauge)
local GameConfig = require(script.Parent.Parent.GameConfig)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local TruckLayout = require(script.Parent.Parent.TruckLayout)
local WoodData = require(script.Parent.Parent.WoodData)
local Kit = require(script.Parent.Kit)
local TreeArt = require(script.Parent.TreeArt)
local VehicleMeshes = require(script.Parent.VehicleMeshes)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef
type Layout = TruckLayout.Layout
type TrailerLayout = TruckLayout.TrailerLayout
type WoodDef = WoodData.WoodDef
type Rng = Kit.Rng

local TruckArt = {}

export type BuildExtras = {
	paint: string?, -- a Paint Shop hex; otherwise the catalog color
	doorName: string?, -- Timber Classic: the owner's display name
}

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

TruckArt.HeadlightColor = HEADLIGHT
TruckArt.TaillightColor = TAILLIGHT

-- The builders draw in M1.5's units (see Sizes above); Build grows them
-- by S. A bed floor's thickness in those units, so it's TruckLayout's once
-- grown (and a wall stands on its top).
local S = TruckLayout.Scale
local FLOOR = TruckLayout.BedFloorThickness / S

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
	simple: boolean?, -- one cap, no shoulder wedges (the part budget)
}

local function fender(parent: Instance, x: number, z0: number, z1: number, s: FenderStyle)
	local inset = s.r * 0.66
	local za, zb = z0 - inset, z1 + inset
	local tilt = s.tilt or CFrame.identity
	if s.simple then
		deco(
			parent,
			"Fender",
			V3(s.width, s.thick, zb - za),
			CF(x, s.top - s.thick / 2, (za + zb) / 2) * tilt,
			s.color,
			s.material
		)
		return
	end
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

-- A wheel: the tyre (named "Wheel", the part Rig motors) with its rim and,
-- when the style has a hub colour, a round hub cap and one bolt off its
-- centre as children, so the whole wheel spins as one. The dark bolt on the
-- pale rim makes the spin readable.
local HUB_CAP = 0.42 -- the cap's diameter, times the tyre's radius
local HUB_BOLT = 0.14 -- the bolt's diameter, times the radius
local HUB_BOLT_AT = 0.36 -- the bolt's centre out from the axle, times the radius
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
		decoCyl(tyre, "Hub", w + 0.12, r * HUB_CAP, cf, s.hub, M.Metal)
		decoCyl(tyre, "HubBolt", w + 0.16, r * HUB_BOLT, cf * CF(0, r * HUB_BOLT_AT, 0), BLACK, M.Metal)
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
	return hull(model, name, V3(width, FLOOR, length), CF(0, y, z), color, M.WoodPlanks)
end

-- Skids: what a truck rests and slides on. Each is a flat box with a
-- wedge ("Ramp", its child) at either end, so the outline seen from the
-- side is a sled runner: the bottom on the ground between the ramps, each
-- ramp's underside rising from y 0 to the skid's top (the chassis's
-- underside) at the skid's end. A kerb, a road edge, a terrain step or a
-- rock up to SKID_HEIGHT tall meets a slope, not a wall, and the truck
-- rides up onto it. Why this slope: everything is frictionless and Drive
-- pushes with at most mass * 120 (VehicleService) against gravity's
-- 196.2, so a truck lifting itself up a ramp from a standstill needs
-- tan(slope) < 120 / 196.2 = 0.61 (31 degrees), and the truck's own lean
-- onto the step (VehicleController's ground rays) adds a few degrees.
-- Each ramp rises the skid's height over twice that, 26.6 degrees: 1.84
-- over 3.68 studs since the chassis rose with the bigger wheels again
-- (phase 12; 1.3 over 2.6 in M1.5, 1 over 2 before). Steeper ramps (or
-- balls at the wheels, whose contact with a 0.5 step is nearly a wall)
-- climb only at speed.
local SKID_HEIGHT = TruckLayout.ChassisY - 0.5 -- up to the chassis's underside (it's 1 tall)
TruckArt.SkidRampRun = 2 * SKID_HEIGHT -- studs along the truck that each ramp rises over
local SKID_MIN_FLAT = 1 -- a short skid keeps at least this much flat bottom

local function slippery(p: BasePart)
	p.Transparency = 1
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	-- Slides over the ground; the Drive constraint supplies the grip.
	p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
end

-- A skid `width` wide spanning `length` along the truck (ramp tip to ramp
-- tip), centred at truck-local `z`, bottom at y 0. Returns the flat part.
local function frictionlessSkid(model: Model, name: string, width: number, length: number, z: number): Part
	local run = math.min(TruckArt.SkidRampRun, (length - SKID_MIN_FLAT) / 2)
	local flat = length - 2 * run
	local y = SKID_HEIGHT / 2
	local skid = Kit.part(model, name, V3(width, SKID_HEIGHT, flat), CF(0, y, z), FRAME, M.SmoothPlastic)
	slippery(skid)
	-- Kit.wedge's slope faces up and to -Z, its full back face at +Z.
	-- Turned over about Z it faces down and to the front (the leading
	-- ramp); turned over about X, down and to the back (the trailing one).
	-- Either way the full face is against the skid's end.
	local size = V3(width, SKID_HEIGHT, run)
	local ends = {
		CF(0, y, z - flat / 2 - run / 2) * CFrame.Angles(0, 0, math.pi),
		CF(0, y, z + flat / 2 + run / 2) * CFrame.Angles(math.pi, 0, 0),
	}
	for _, cf in ipairs(ends) do
		local ramp = Kit.wedge(skid, "Ramp", size, cf, FRAME, M.SmoothPlastic)
		slippery(ramp)
		ramp.Massless = true
	end
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

-- Each style's driver seat (its top, over the ground) and, under a roof, the
-- roof's underside over that, in M1.5's units (Build grows them by S: seat
-- tops 3.4 to 4.8, roofs 6 to 6.6 over them). A seated avatar's head tops
-- out about 3.25 over the seat and a hat adds more, so the roofs stand well
-- over it, the bigger the truck the more (V2_PLAN §4c, TruckArt.spec).
-- (The Rustbucket's bench rose a tenth in phase 12: an avatar's straight legs
-- end under its cowl, not in the gap in front of the grown seat.)
local SEAT_TOP = { farm = 2.95, pickup = 2.6, atv = 3.5, flatbed = 2.8, rig = 3.7 }
local HEADROOM = { pickup = 4.65, flatbed = 4.9, rig = 5.05 }

-- The Rustbucket: held together by hope.
builders.farm = function(c: Ctx)
	local m, lay, paint, rng = c.model, c.lay, c.paint, c.rng
	local W, f = lay.width, lay.front
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF, zR = lay.wheelZ[1], lay.wheelZ[2]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local floorTop = lay.bedFloorY + FLOOR / 2
	local wall = (W - lay.bedWidth) / 2
	local seatTop, seatZ = SEAT_TOP.farm, f + 5.8
	local primer = hex("#9A9A94") -- the one replacement door, primer grey
	local cream = hex("#D8C6A0")
	local oldMetal = hex("#6E5D50")
	local wood = hex("#7C5A3A")
	local hoodW = W * 0.5

	deco(m, "Frame", V3(W - 1.6, 0.9, lay.length - 1.0), CF(0, 1.95, 0), FRAME, M.Metal)

	-- Front: a narrow hood between big separate fenders, a cream grille
	-- shell and a bumper that has met a few stumps.
	deco(
		m,
		"Bumper",
		V3(W + 0.6, 0.55, 0.55),
		CF(0, 1.65, f + 0.25) * CFrame.Angles(0, 0.04, 0.05),
		oldMetal,
		M.CorrodedMetal
	)
	deco(m, "Hood", V3(hoodW, 1.6, 3.4), CF(0, 3.1, f + 2.45), paint, M.Metal)
	deco(m, "Grille", V3(hoodW + 0.15, 2.0, 0.35), CF(0, 3.05, f + 0.6), cream, M.Metal)
	deco(m, "GrilleSlats", V3(hoodW - 0.45, 1.5, 0.1), CF(0, 3.0, f + 0.4), hex("#2B2420"), M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "BumperBlock", V3(0.7, 0.4, 0.5), CF(side * (W / 2 - 0.55), 1.2, f + 0.2), wood, M.SmoothPlastic)
	end
	local fenderTop = 2 * r + 0.6
	for _, side in ipairs({ -1, 1 }) do
		local dented = side < 0
		fender(m, side * wx, zF, zF, {
			r = r,
			width = tw + 0.45,
			top = fenderTop,
			thick = 0.5,
			front = { 1.1, 1.75 },
			back = { 1.0, 1.95 },
			color = if dented then Kit.shade(paint, -0.14) else paint,
			material = M.Metal,
			tilt = if dented then CFrame.Angles(0.07, 0, -0.06) else nil,
			simple = true,
		})
	end
	-- Bug-eye headlights on the fender crowns; the right one knocked askew.
	for _, side in ipairs({ -1, 1 }) do
		local tilt = if side > 0 then CFrame.Angles(-0.1, 0.16, 0) else CFrame.identity
		roundLamp(
			m,
			"Headlight",
			CF(side * (wx - 0.55), fenderTop + 0.45, zF - 0.3) * tilt,
			0.9,
			0.5,
			oldMetal,
			HEADLIGHT,
			-1
		)
	end

	-- Open cab: cowl, a raked windshield frame, doors (one of them from a
	-- different truck), a bench seat and the canvas top, rolled up for good
	-- behind the seat (nothing over the driver's head).
	deco(m, "Cowl", V3(W - 0.3, 1.6, 0.7), CF(0, 3.3, f + 4.5), paint, M.Metal)
	local rake = CFrame.Angles(0.12, 0, 0)
	local screen = CF(0, 4.95, f + 4.75) * rake
	deco(m, "WindshieldTop", V3(W - 0.4, 0.2, 0.2), screen * CF(0, 0.95, 0), oldMetal, M.Metal)
	glass(m, "Windshield", V3(W - 0.8, 1.65, 0.07), screen, 0.6)
	deco(m, "Crack", V3(0.04, 0.7, 0.02), screen * CF(0.55, -0.15, 0.05), hex("#2A241C"), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Door",
			V3(0.22, 1.7, 2.2),
			CF(side * (W / 2 - 0.11), 3.35, f + 5.9),
			if side < 0 then primer else paint,
			M.Metal
		)
	end
	driverSeat(m, V3(2.8, 0.5, 1.4), CF(0, seatTop - 0.25, seatZ), hex("#6E4A33"), M.Leather)
	deco(
		m,
		"SeatBack",
		V3(2.9, 1.4, 0.3),
		CF(0, seatTop + 0.7, seatZ + 0.85) * CFrame.Angles(0.12, 0, 0),
		hex("#6E4A33"),
		M.Leather
	)
	steeringWheel(m, V3(0, seatTop + 0.85, seatZ - 0.75), 1.0)
	deco(m, "CabBack", V3(W, 2.0, 0.3), CF(0, 3.5, bedStart + 0.15), paint, M.Metal)

	-- Bed: weathered side boards with gaps, rusty corner posts, and a
	-- tailgate that hangs open on two bits of rope.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, wood)
	local boardH = (lay.wallHeight - 0.2) / 2 -- two boards a side, a gap between
	local postH = lay.wallHeight + 0.15
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 1 do
			hull(
				m,
				"BedBoard",
				V3(wall, boardH, lay.bedLength - 0.3),
				CF(side * (W / 2 - wall / 2), floorTop + boardH / 2 + i * (boardH + 0.2), lay.bedCenterZ + 0.15),
				Kit.vary(wood, rng, 0.06),
				M.WoodPlanks
			)
		end
		deco(
			m,
			"BedPost",
			V3(0.34, postH, 0.34),
			CF(side * (W / 2 - 0.17), floorTop + postH / 2, bedEnd - 0.17),
			oldMetal,
			M.CorrodedMetal
		)
	end
	local hinge = CF(0, floorTop, bedEnd - 0.12) * CFrame.Angles(0.22, 0, 0)
	local gateW, gateH = W - 0.7, lay.wallHeight - 0.05
	hull(m, "Tailgate", V3(gateW, gateH, 0.24), hinge * CF(0, gateH / 2, 0), Kit.vary(wood, rng, 0.05), M.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		fender(m, side * wx, zR, zR, {
			r = r,
			width = tw + 0.45,
			top = 2 * r + 0.4,
			thick = 0.42,
			front = { 0.9, 1.95 },
			back = { 0.8, 2.1 },
			color = Kit.vary(paint, rng, 0.05),
			material = M.Metal,
			simple = true,
		})
		local z0, z1 = zF + 0.66 * r + 1.0, zR - 0.66 * r - 0.9
		deco(
			m,
			"RunningBoard",
			V3(1.2, 0.2, z1 - z0),
			CF(side * (wx - 0.05), 1.9, (z0 + z1) / 2),
			Kit.vary(wood, rng, 0.05),
			M.WoodPlanks
		)
	end

	-- Lights that don't match: the right headlamp is out.
	decoCyl(
		m,
		"Taillight",
		0.12,
		0.44,
		CF(-(W / 2 - 0.17), floorTop + 0.75, bedEnd + 0.03) * CFrame.Angles(0, math.pi / 2, 0),
		TAILLIGHT,
		M.Neon
	)
	deco(m, "Taillight", V3(0.38, 0.3, 0.1), CF(W / 2 - 0.17, floorTop + 0.75, bedEnd + 0.03), TAILLIGHT, M.Neon)
	exhaust(
		m,
		V3(-1.6, 1.5, bedEnd - 1.6),
		V3(-1.7, 1.35, lay.length / 2 + 0.5),
		0.38,
		oldMetal,
		M.CorrodedMetal,
		1,
		hex("#4F4842")
	)

	local hub = hex("#3A322C")
	wheels(m, lay, { rim = cream, hub = hub, steer = true, rear = false }, { rim = cream, steer = false, rear = true })
	for _, d in ipairs(m:GetChildren()) do
		if d.Name == "Headlight" and d:IsA("BasePart") and d.CFrame.X > 0 then
			d:SetAttribute("Out", true)
			d.Color = hex("#3A3428")
		end
	end
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
	local floorTop = lay.bedFloorY + FLOOR / 2
	local wall = (W - lay.bedWidth) / 2
	local wallY = floorTop + lay.wallHeight / 2
	local seatTop, seatZ = SEAT_TOP.pickup, f + 6.1
	local cream = hex("#EFE6D2")

	deco(m, "Frame", V3(W - 1.8, 0.9, L - 1.2), CF(0, 1.95, 0), FRAME, M.Metal)
	deco(m, "Bumper", V3(W + 0.45, 0.6, 0.55), CF(0, 1.75, f + 0.27), CHROME, M.Metal)
	deco(m, "Nose", V3(W - 1.0, 1.6, 4.0), CF(0, 2.85, f + 2.5), paint, M.Metal)
	deco(m, "Hood", V3(W - 2.2, 0.65, 3.5), CF(0, 3.975, f + 2.75), paint, M.Metal)
	decoWedge(m, "HoodNose", V3(W - 2.2, 0.65, 0.5), CF(0, 3.975, f + 0.75), paint, M.Metal)
	deco(m, "Grille", V3(W - 2.4, 1.3, 0.16), CF(0, 2.85, f + 0.45), CHROME_HI, M.Metal)
	for i = 0, 3 do
		deco(m, "GrilleSlat", V3(W - 2.9, 0.1, 0.06), CF(0, 2.45 + i * 0.26, f + 0.36), hex("#2A2D33"), M.Metal)
	end

	-- Pontoon front fenders with the headlights in their noses.
	local fz0, fz1 = f + 0.7, zF + 1.25
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (wx + 0.05)
		deco(m, "Fender", V3(1.6, 0.8, fz1 - fz0), CF(x, 3.2, (fz0 + fz1) / 2), paint, M.Metal)
		decoWedge(m, "Fender", V3(1.6, 0.8, 1.2), CF(x, 3.2, fz1 + 0.6) * CFrame.Angles(0, math.pi, 0), paint, M.Metal)
		roundLamp(m, "Headlight", CF(x, 3.2, fz0), 0.7, 0.3, CHROME, HEADLIGHT, -1)
	end

	-- Cab: glass all round under a cream roof, from the body's top (`belt`)
	-- to the roof's underside, HEADROOM over the seat: room for a seated
	-- avatar in a hat (TruckArt.spec). The windshield leans back from the
	-- body's front edge to just under the roof's front edge.
	local belt, roofY = seatTop + 1.3, seatTop + HEADROOM.pickup
	local cabZ0 = f + 4.45
	deco(m, "Cab", V3(W, belt - 1.9, bedStart - cabZ0), CF(0, (belt + 1.9) / 2, (cabZ0 + bedStart) / 2), paint, M.Metal)
	local screenLo, screenHi = V3(0, belt, cabZ0), V3(0, roofY - 0.05, cabZ0 + 0.65)
	local rise = screenHi - screenLo
	local screen = CF((screenLo + screenHi) / 2) * CFrame.Angles(math.atan2(rise.Z, rise.Y), 0, 0)
	local glassZ0, glassZ1 = screenHi.Z + 0.05, bedStart - 0.1
	glass(
		m,
		"CabGlass",
		V3(W - 0.4, roofY - belt, glassZ1 - glassZ0),
		CF(0, (belt + roofY) / 2, (glassZ0 + glassZ1) / 2),
		0.45
	)
	glass(m, "Windshield", V3(W - 0.6, rise.Magnitude, 0.07), screen, 0.4)
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Pillar",
			V3(0.24, rise.Magnitude + 0.05, 0.24),
			CF(side * (W / 2 - 0.24), 0, 0) * screen,
			cream,
			M.Metal
		)
		deco(
			m,
			"Pillar",
			V3(0.3, roofY - belt, 0.36),
			CF(side * (W / 2 - 0.2), (belt + roofY) / 2, bedStart - 0.25),
			cream,
			M.Metal
		)
		deco(m, "Mirror", V3(0.18, 0.5, 0.65), CF(side * (W / 2 + 0.15), belt + 0.6, cabZ0 + 0.3), CHROME_HI, M.Metal)
	end
	deco(
		m,
		"Roof",
		V3(W - 0.2, 0.34, bedStart - screenHi.Z + 0.05),
		CF(0, roofY + 0.17, (screenHi.Z + bedStart + 0.05) / 2),
		cream,
		M.Metal
	)
	deco(m, "RoofRack", V3(W - 1.4, 0.1, 1.4), CF(0, roofY + 0.5, (screenHi.Z + bedStart) / 2), BLACK, M.Metal)
	driverSeat(m, V3(2.6, 0.5, 1.4), CF(0, seatTop - 0.25, seatZ), hex("#8C6A4A"), M.Leather)
	deco(
		m,
		"SeatBack",
		V3(2.7, 1.4, 0.3),
		CF(0, seatTop + 0.7, seatZ + 0.85) * CFrame.Angles(0.1, 0, 0),
		hex("#8C6A4A"),
		M.Leather
	)
	steeringWheel(m, V3(0, seatTop + 1.05, seatZ - 0.75), 0.95)

	-- Chrome spear down each side, black running boards.
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Trim",
			V3(0.07, 0.15, bedEnd - cabZ0),
			CF(side * (W / 2 + 0.035), belt - 0.3, (cabZ0 + bedEnd) / 2),
			CHROME_HI,
			M.Metal
		)
		deco(m, "MudFlap", V3(0.7, 0.85, 0.08), CF(side * (W / 2 + 0.15), 1.35, zR + 1.7), BLACK, M.SmoothPlastic)
	end

	-- Bed: smooth painted walls with chrome caps; a flared rear fender over
	-- each wheel.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#5E4632"))
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 - wall / 2)
		hull(m, "BedWall", V3(wall, lay.wallHeight, lay.bedLength), CF(x, wallY, lay.bedCenterZ), paint, M.Metal)
		deco(
			m,
			"BedCap",
			V3(wall + 0.12, 0.12, lay.bedLength),
			CF(x, floorTop + lay.wallHeight + 0.06, lay.bedCenterZ),
			CHROME_HI,
			M.Metal
		)
		local fx = side * (W / 2 + 0.4)
		deco(m, "Fender", V3(0.95, 0.7, 3.0), CF(fx, 3.15, zR), paint, M.Metal)
		decoWedge(m, "Fender", V3(0.95, 0.7, 0.9), CF(fx, 3.15, zR - 1.95), paint, M.Metal)
		decoWedge(
			m,
			"Fender",
			V3(0.95, 0.7, 0.9),
			CF(fx, 3.15, zR + 1.95) * CFrame.Angles(0, math.pi, 0),
			paint,
			M.Metal
		)
		deco(m, "Taillight", V3(0.32, 0.8, 0.1), CF(x, floorTop + 1.0, bedEnd + 0.03), TAILLIGHT, M.Neon)
	end
	deco(m, "BedFront", V3(W - 2 * wall, lay.wallHeight, 0.3), CF(0, wallY, bedStart + 0.15), paint, M.Metal)
	hull(m, "Tailgate", V3(W - 2 * wall, lay.wallHeight, 0.3), CF(0, wallY, bedEnd - 0.15), paint, M.Metal)
	deco(m, "RearBumper", V3(W + 0.25, 0.55, 0.5), CF(0, 1.95, L / 2 - 0.2), CHROME, M.Metal)
	exhaust(m, V3(1.7, 1.6, bedEnd - 0.8), V3(1.75, 1.55, L / 2 + 0.3), 0.3, CHROME, M.Metal, 0.3, hex("#8A8580"))

	local front = { rim = cream, rimScale = 0.64, hub = CHROME_HI, steer = true, rear = false }
	local back = { rim = cream, rimScale = 0.64, steer = false, rear = true }
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

	deco(m, "Frame", V3(2.0, 1.0, 4.7), CF(0, 1.85, 0), FRAME, M.Metal)
	decoCyl(m, "Engine", 2.35, 1.1, CF(0, 1.95, 0.25), hex("#7E8287"), M.Metal)

	-- One fender cap over each wheel. Knobs go on the tyres below.
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (wx - 0.1)
		local style: FenderStyle = {
			r = r,
			width = tw + 0.26,
			top = 2 * r + 0.42,
			thick = 0.34,
			front = { 0.72, 2.0 },
			back = { 0.6, 2.3 },
			color = paint,
			material = M.SmoothPlastic,
			simple = true,
		}
		fender(m, x, zF, zF, style)
		fender(m, x, zR, zR, style)
		deco(m, "Headlight", V3(0.65, 0.34, 0.12), CF(side * 0.72, 2.65, f + 0.27), HEADLIGHT, M.Neon)
		deco(m, "Taillight", V3(0.42, 0.24, 0.08), CF(side * 0.65, 2.65, b - 0.15), TAILLIGHT, M.Neon)
	end
	deco(m, "Nose", V3(2.9, 0.7, 2.1), CF(0, 2.6, f + 1.35), paint, M.SmoothPlastic)

	-- A front basket, clear of a seated rider's feet, and the whip.
	local rackY = 3.3
	local seatTop, seatZ = SEAT_TOP.atv, 0.6
	deco(m, "Basket", V3(2.2, 0.12, 0.9), CF(0, rackY, f + 0.9), rack, M.Metal)
	deco(m, "Basket", V3(2.2, 0.35, 0.1), CF(0, rackY + 0.2, f + 0.45), rack, M.Metal)

	-- Tank, bars and the saddle. The bars ride just over a seated rider's
	-- straight legs (the seat's top + 0.5).
	local barY = seatTop + 0.7
	deco(m, "Tank", V3(1.6, 0.7, 1.25), CF(0, 3.2, -1.3), paint, M.SmoothPlastic)
	decoRod(m, "Handlebar", V3(-1.3, barY, -1.45), V3(1.3, barY, -1.45), 0.17, rack, M.Metal)
	deco(m, "SeatBase", V3(1.75, 0.65, 2.75), CF(0, seatTop - 0.875, seatZ), plastic, M.SmoothPlastic)
	driverSeat(m, V3(1.5, 0.55, 2.4), CF(0, seatTop - 0.275, seatZ), hex("#6B4A33"), M.Leather)

	exhaust(m, V3(1.1, 2.3, 1.95), V3(1.25, 2.55, b + 0.13), 0.3, hex("#55595C"), M.Metal, 0.35, hex("#9A958F"))
	-- The scout's flag: seen over the brush from far away.
	local poleTop = V3(-1.95, 8.0, b - 0.2)
	decoRod(m, "FlagPole", V3(-1.9, rackY + 0.07, b - 0.26), poleTop, 0.13, BLACK, M.Metal)
	decoWedge(
		m,
		"Flag",
		V3(0.06, 0.9, 1.4),
		CF(poleTop.X, poleTop.Y - 0.5, poleTop.Z + 0.7) * CFrame.Angles(0, math.pi, 0),
		hex("#F08A24"),
		M.Fabric
	)

	local rim = hex("#B5B9B4")
	wheels(
		m,
		lay,
		{ rim = rim, rimScale = 0.55, hub = plastic, steer = true, rear = false },
		{ rim = rim, rimScale = 0.55, steer = false, rear = true }
	)
	for _, d in ipairs(m:GetChildren()) do
		if d.Name == "Wheel" and d:IsA("BasePart") then
			decoCyl(d, "Knobby", d.Size.X + 0.08, d.Size.Y * 0.92, d.CFrame, hex("#2A2C28"), M.SmoothPlastic)
		end
	end
end

-- A boxy cab with glass all round: lower body, glass, pillars, roof. Its
-- roof's underside is at y2.
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
				V3(0.3, y2 - y1, 0.3),
				CF(side * (W / 2 - 0.35), (y1 + y2) / 2, z + end_ * (length / 2 - 0.3)),
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
	local deckTop = lay.bedFloorY + FLOOR / 2
	local wall = (W - lay.bedWidth) / 2
	local seatTop, seatZ = SEAT_TOP.flatbed, f + 6.3
	local steel = hex("#6A6E72")
	local stake = hex("#A0703F")

	deco(m, "Frame", V3(W - 2.4, 0.9, L - 1.4), CF(0, 1.95, 0), FRAME, M.Metal)
	deco(m, "Bumper", V3(W + 0.6, 0.7, 0.6), CF(0, 1.85, f + 0.28), BLACK, M.Metal)
	deco(m, "Hood", V3(W - 0.6, 1.9, 4.05), CF(0, 3.1, f + 2.525), paint, M.Metal)
	deco(m, "Grille", V3(W - 3.4, 1.3, 0.12), CF(0, 3.05, f + 0.46), BLACK, M.Metal)
	deco(m, "GrilleBar", V3(W - 3.7, 0.16, 0.08), CF(0, 3.1, f + 0.39), CHROME, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "Headlight", V3(0.8, 0.56, 0.12), CF(side * 2.5, 3.1, f + 0.46), HEADLIGHT, M.Neon)
		-- Squared-off fenders, front and over the tandem.
		fender(m, side * wx, zF, zF, {
			r = r,
			width = tw + 0.55,
			top = 2 * r + 0.65,
			thick = 0.55,
			front = { 0.65, 2.3 },
			back = { 0.65, 2.4 },
			color = paint,
			material = M.Metal,
		})
		fender(m, side * wx, zTandem, zRear, {
			r = r,
			width = tw + 0.55,
			top = 2 * r + 0.4,
			thick = 0.38,
			front = { 0.6, 2.4 },
			back = { 0.6, 2.4 },
			color = BLACK,
			material = M.Metal,
		})
		deco(m, "Mirror", V3(0.18, 1.0, 0.55), CF(side * (W / 2 + 0.25), 5.0, f + 4.7), BLACK, M.Metal)
	end

	-- Cab (its roof HEADROOM over the seat: room for a driver in a hat,
	-- and a clear step up from the Pickup's roof, ACT-07) and roof beacon;
	-- the stack stands clear of the roof.
	local cabZ0 = f + 4.55
	local roofY = seatTop + HEADROOM.flatbed
	boxCab(m, W, (cabZ0 + bedStart) / 2, bedStart - cabZ0, 2.15, seatTop + 1.1, roofY, paint, BLACK, hex("#EEEBE3"))
	deco(m, "Beacon", V3(1.0, 0.4, 0.5), CF(0, roofY + 0.52, f + 5.4), AMBER, M.Neon)
	deco(m, "LightBar", V3(W - 1.2, 0.16, 0.28), CF(0, roofY + 0.55, f + 5.4), BLACK, M.Metal)
	driverSeat(m, V3(2.6, 0.5, 1.4), CF(0, seatTop - 0.25, seatZ), hex("#4A4440"), M.Fabric)
	steeringWheel(m, V3(0, seatTop + 1.05, seatZ - 0.75), 1.0)
	exhaust(
		m,
		V3(W / 2 + 0.25, 2.3, bedStart - 0.4),
		V3(W / 2 + 0.25, roofY + 1.1, bedStart - 0.4),
		0.38,
		steel,
		M.Metal,
		0.45,
		hex("#7D7873")
	)

	-- Headache rack behind the cab.
	local rackZ = bedStart + 0.25
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "HeadacheRack", V3(0.36, 3.6, 0.36), CF(side * (W / 2 - 0.3), deckTop + 1.8, rackZ), steel, M.Metal)
	end
	deco(m, "HeadacheRack", V3(W - 0.25, 0.36, 0.36), CF(0, deckTop + 3.6, rackZ), steel, M.Metal)
	deco(m, "HeadacheRack", V3(W - 0.6, 0.24, 0.24), CF(0, deckTop + 2.1, rackZ), steel, M.Metal)

	-- Deck and stake sides (open at the back).
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#161616"))
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 - wall / 2)
		for _, z in ipairs({ bedStart + 0.9, lay.bedCenterZ, bedEnd - 0.5 }) do
			hull(
				m,
				"Stake",
				V3(wall, lay.wallHeight, 0.36),
				CF(x, deckTop + lay.wallHeight / 2, z),
				Kit.vary(stake, rng, 0.05),
				M.Wood
			)
			deco(m, "StakePocket", V3(wall + 0.08, 0.22, 0.48), CF(x, deckTop + 0.11, z), BLACK, M.Metal)
		end
		for _, y in ipairs({ deckTop + 0.85, deckTop + 1.95 }) do
			hull(
				m,
				"StakeRail",
				V3(wall - 0.04, 0.5, lay.bedLength - 0.6),
				CF(x, y, lay.bedCenterZ + 0.2),
				Kit.vary(stake, rng, 0.06),
				M.WoodPlanks
			)
		end
		deco(
			m,
			"Taillight",
			V3(0.5, 0.38, 0.1),
			CF(side * (W / 2 - 0.45), lay.bedFloorY, bedEnd + 0.03),
			TAILLIGHT,
			M.Neon
		)
	end
	deco(m, "RearBumper", V3(W + 0.25, 0.6, 0.55), CF(0, 2.0, b - 0.25), BLACK, M.Metal)

	local rimColor = hex("#E2E0D8")
	wheels(
		m,
		lay,
		{ rim = rimColor, hub = BLACK, steer = true, rear = false },
		{ rim = rimColor, steer = false, rear = true }
	)
	gloss(m, paint, 0.03) -- fresh enamel, a step under the Rig's shine
end

-- The Logging Rig: chrome everywhere, built to haul a forest.
builders.rig = function(c: Ctx)
	local m, lay, paint = c.model, c.lay, c.paint
	local W, L, f, b = lay.width, lay.length, lay.front, lay.length / 2
	local r, tw, wx = lay.wheelRadius, lay.tyreWidth, lay.wheelX
	local zF = lay.wheelZ[1]
	local bedStart, bedEnd = lay.bedStart, lay.bedStart + lay.bedLength
	local deckTop = lay.bedFloorY + FLOOR / 2
	local wall = (W - lay.bedWidth) / 2
	local seatTop, seatZ = SEAT_TOP.rig, f + 7.9
	local steel = hex("#3D4045")
	local post = hex("#A2A8AE")
	local crane = hex("#E3A72F")

	deco(m, "Frame", V3(W - 2.6, 1.0, L - 1.2), CF(0, 1.95, 0), BLACK, M.Metal)
	deco(m, "DeckBeam", V3(W - 1.8, 0.6, lay.bedLength), CF(0, lay.bedFloorY - 0.55, lay.bedCenterZ), steel, M.Metal)

	-- Long nose: chrome bumper and grille, a crowned hood.
	deco(m, "Bumper", V3(W + 0.6, 0.85, 0.75), CF(0, 1.9, f + 0.38), CHROME_HI, M.Foil)
	deco(m, "Hood", V3(5.0, 1.8, 5.4), CF(0, 3.4, f + 3.4), paint, M.Metal)
	deco(m, "HoodTop", V3(4.5, 0.45, 4.4), CF(0, 4.525, f + 3.9), paint, M.Metal)
	decoWedge(m, "HoodNose", V3(4.5, 0.45, 1.0), CF(0, 4.525, f + 1.2), paint, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		deco(m, "Pinstripe", V3(0.05, 0.26, 5.3), CF(side * 2.52, 3.75, f + 3.42), hex("#F1E6CC"), M.SmoothPlastic)
	end
	deco(m, "Grille", V3(3.4, 3.3, 0.32), CF(0, 3.55, f + 0.66), CHROME_HI, M.Metal)
	deco(m, "GrilleBars", V3(2.9, 2.7, 0.08), CF(0, 3.55, f + 0.48), BLACK, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		-- Set in a little, so the rig, fenders and all, fits its parking slot.
		fender(m, side * (wx - 0.1), zF, zF, {
			r = r,
			width = tw + 0.4,
			top = 2 * r + 0.7,
			thick = 0.55,
			front = { 1.15, 2.0 },
			back = { 1.0, 2.35 },
			color = paint,
			material = M.Metal,
		})
		deco(m, "Headlight", V3(0.9, 0.5, 0.12), CF(side * 2.3, 2.55, f + 0.47), HEADLIGHT, M.Neon)
		-- Polished fuel tanks under the doors, twin stacks at the cab's back
		-- corners, west-coast mirrors.
		decoCyl(
			m,
			"FuelTank",
			2.6,
			1.25,
			CF(side * 3.0, 2.15, f + 7.75) * CFrame.Angles(0, math.pi / 2, 0),
			CHROME_HI,
			M.Foil
		)
		exhaust(
			m,
			V3(side * (W / 2 + 0.3), 2.8, bedStart - 0.3),
			V3(side * (W / 2 + 0.3), 11.3, bedStart - 0.3), -- tall chrome stacks, well over the roof
			0.58,
			CHROME_HI,
			M.Foil,
			0.2,
			hex("#A8A39D")
		)
		deco(m, "Mirror", V3(0.19, 1.25, 0.58), CF(side * (W / 2 + 0.28), 6.3, f + 6.3), CHROME_HI, M.Foil)
	end

	-- A tall day cab (its roof HEADROOM over the seat: room for a driver in
	-- a hat, and the tallest roof on the lot, ACT-07): roof markers, sun
	-- visor.
	local cabZ0 = f + 6.1
	local roofY = seatTop + HEADROOM.rig
	boxCab(m, W, (cabZ0 + bedStart) / 2, bedStart - cabZ0, 2.5, seatTop + 1.1, roofY, paint, paint, paint)
	deco(
		m,
		"Visor",
		V3(W - 0.25, 0.18, 0.7),
		CF(0, roofY - 0.02, cabZ0 - 0.1) * CFrame.Angles(0.15, 0, 0),
		BLACK,
		M.Metal
	)
	for _, x in ipairs({ -1.6, 0, 1.6 }) do
		deco(m, "Marker", V3(0.42, 0.2, 0.26), CF(x, roofY + 0.42, cabZ0 + 0.35), AMBER, M.Neon)
	end
	driverSeat(m, V3(2.6, 0.5, 1.4), CF(0, seatTop - 0.25, seatZ), hex("#3B2F2A"), M.Leather)
	steeringWheel(m, V3(0, seatTop + 1.05, seatZ - 0.75), 1.05)

	-- Bulkhead, as tall as the cab, with a stub knuckle crane parked on top
	-- (its turret clear of the cab's glass): turret, mast, a boom reaching
	-- back over the load and a grapple hanging off its end.
	local bulkTop = roofY
	local cz = bedStart + 0.2
	local bulkH = bulkTop - deckTop
	deco(m, "Bulkhead", V3(W, bulkH, 0.4), CF(0, deckTop + bulkH / 2, cz), hex("#5C6166"), M.Metal)
	deco(m, "HeadacheRack", V3(W - 0.3, 0.35, 0.4), CF(0, deckTop + bulkH + 0.15, cz), steel, M.Metal)
	Kit.decor(Kit.post(m, "Crane", V3(1.2, bulkTop, cz), 0.65, 1.5, crane, M.Metal), false)
	Kit.decor(Kit.post(m, "Crane", V3(1.2, bulkTop + 0.65, cz), 1.95, 0.65, crane, M.Metal), false)
	local tip = V3(1.2, bulkTop + 3.1, cz + 6.0)
	plank(m, "Crane", V3(1.2, bulkTop + 2.35, cz - 0.4), tip, 0.65, 0.65, crane, M.Metal)
	plank(m, "Crane", tip, tip - V3(0, 1.7, 0), 0.42, 0.42, Kit.shade(crane, -0.15), M.Metal)
	deco(m, "Grapple", V3(1.0, 0.6, 0.8), CF(tip - V3(0, 1.95, 0)), BLACK, M.Metal)

	-- Deck with steel bunk stakes, a pair at each third and at the back.
	bedFloor(m, "BedFloor", W, lay.bedLength, lay.bedFloorY, lay.bedCenterZ, hex("#5E4636"))
	for _, z in ipairs({ bedStart + lay.bedLength / 3, bedStart + lay.bedLength * 2 / 3, bedEnd - 0.3 }) do
		for _, side in ipairs({ -1, 1 }) do
			hull(
				m,
				"Stanchion",
				V3(wall, lay.wallHeight, wall),
				CF(side * (W / 2 - wall / 2), deckTop + lay.wallHeight / 2, z),
				post,
				M.Metal
			)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 + 0.08)
		decoRod(
			m,
			"Chain",
			V3(x, deckTop + lay.wallHeight * 0.62, bedStart + lay.bedLength / 3),
			V3(x, deckTop + lay.wallHeight * 0.62, bedEnd - 0.3),
			0.08,
			BLACK,
			M.Metal
		)
	end
	for _, side in ipairs({ -1, 1 }) do
		deco(
			m,
			"Taillight",
			V3(0.58, 0.42, 0.1),
			CF(side * (W / 2 - 0.5), lay.bedFloorY, bedEnd + 0.03),
			TAILLIGHT,
			M.Neon
		)
	end
	deco(m, "RearBumper", V3(W, 0.6, 0.6), CF(0, 2.05, b - 0.3), BLACK, M.Metal)

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

-- Draws a trailer's body into `model` in M1.5's units (`tl` is a
-- TrailerLayout shrunk by S: trailerDesignOf), behind the truck in
-- truck-local studs: tongue, bed ("TrailerBed"), axle(s), fenders, lights
-- and the style's sides. AddTrailer grows it and adds the skid.
local function drawTrailer(model: Model, trailer: TrailerDef, tl: TrailerLayout)
	local W = tl.width
	local bs, be, bc, y = tl.bedStart, tl.bedStart + tl.bedLength, tl.bedCenterZ, tl.bedFloorY
	local r, tw = tl.wheelRadius, tl.tyreWidth
	local paint = hex(trailer.look.color)
	local rng = Kit.rng(#trailer.id * 97 + math.floor(tl.bedLength + 0.5)) -- M1.5's seeds: the same boards
	local deckTop = y + FLOOR / 2
	local wall = (W - tl.bedWidth) / 2
	local wallH = tl.wallHeight
	local wood = hex("#8A6038")

	local deckColor = if tl.style == "heavy" then hex("#5B4A3C") else wood
	bedFloor(model, "TrailerBed", W, tl.bedLength, y, bc, deckColor)
	deco(model, "TrailerFrame", V3(W - 1.5, 0.45, tl.bedLength), CF(0, y - 0.5, bc), FRAME, M.Metal)

	-- A-frame tongue to a coupler at the truck's back.
	local hitchZ, hitchY = tl.hitchZ, 1.75
	for _, side in ipairs({ -1, 1 }) do
		decoRod(
			model,
			"Tongue",
			V3(side * (W / 2 - 0.9), hitchY, bs + 0.25),
			V3(side * 0.2, hitchY, hitchZ + 0.6),
			0.28,
			FRAME,
			M.Metal
		)
	end
	deco(model, "Coupler", V3(0.6, 0.45, 0.9), CF(0, hitchY, hitchZ + 0.4), BLACK, M.Metal)

	-- Axles, wheels and flat-topped fenders just outside the deck.
	local heavy = tl.style == "heavy"
	local rim = if heavy then hex("#C9CDD1") else hex("#D8C6A0")
	for _, z in ipairs(tl.axleZ) do
		decoRod(model, "Axle", V3(-tl.wheelX, r, z), V3(tl.wheelX, r, z), 0.26, FRAME, M.Metal)
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
	local fenderW = tw + 0.24
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (W / 2 + fenderW / 2 - 0.1)
		fender(model, x, z0, z1, {
			r = r,
			width = fenderW,
			top = 2 * r + 0.3,
			thick = 0.25,
			front = { 0.55, 1.9 },
			back = { 0.5, 1.95 },
			color = fenderColor,
			material = if heavy then M.DiamondPlate else M.Metal,
		})
		deco(model, "Taillight", V3(0.5, 0.36, 0.1), CF(side * (W / 2 - 0.45), y, be + 0.03), TAILLIGHT, M.Neon)
	end

	if tl.style == "pony" then
		-- A little wooden farm trailer: plank sides, a drop-down back.
		local boardH = (wallH - 0.16) / 2 -- two boards a side, a gap between
		for _, side in ipairs({ -1, 1 }) do
			for i = 0, 1 do
				hull(
					model,
					"TrailerBoard",
					V3(wall, boardH, tl.bedLength),
					CF(side * (W / 2 - wall / 2), deckTop + boardH / 2 + i * (boardH + 0.16), bc),
					Kit.vary(paint, rng, 0.06),
					M.WoodPlanks
				)
			end
			deco(
				model,
				"TrailerPost",
				V3(0.32, wallH + 0.05, 0.32),
				CF(side * (W / 2 - 0.16), deckTop + (wallH + 0.05) / 2, be - 0.16),
				FRAME,
				M.Metal
			)
		end
		hull(
			model,
			"TrailerFront",
			V3(W, wallH, 0.25),
			CF(0, deckTop + wallH / 2, bs + 0.125),
			Kit.vary(paint, rng, 0.05),
			M.WoodPlanks
		)
		hull(
			model,
			"TrailerGate",
			V3(W - 2 * wall - 0.14, wallH, 0.25),
			CF(0, deckTop + wallH / 2, be - 0.125),
			Kit.vary(paint, rng, 0.05),
			M.WoodPlanks
		)
	elseif tl.style == "ranch" then
		-- Painted stake posts with two wooden rails, a tall headboard.
		local rail = hex("#A77B4C")
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (W / 2 - wall / 2)
			for _, z in ipairs({ bs + 0.35, bc, be - 0.35 }) do
				hull(model, "TrailerStake", V3(wall, wallH, wall), CF(x, deckTop + wallH / 2, z), paint, M.Metal)
			end
			for _, ry in ipairs({ deckTop + 0.85, deckTop + 1.7 }) do
				hull(
					model,
					"TrailerRail",
					V3(wall - 0.06, 0.42, tl.bedLength - 0.25),
					CF(x, ry, bc),
					Kit.vary(rail, rng, 0.06),
					M.WoodPlanks
				)
			end
		end
		hull(model, "TrailerFront", V3(W, wallH, 0.25), CF(0, deckTop + wallH / 2, bs + 0.125), paint, M.Metal)
	else
		-- Heavy Hauler: a steel headboard, tall stanchions, amber markers.
		local steel = hex("#9AA1A8")
		for _, side in ipairs({ -1, 1 }) do
			for _, z in ipairs({ bs + 0.4, bc + 0.8, be - 0.35 }) do
				hull(
					model,
					"TrailerStanchion",
					V3(wall, wallH, wall),
					CF(side * (W / 2 - wall / 2), deckTop + wallH / 2, z),
					steel,
					M.Metal
				)
			end
			deco(model, "Marker", V3(0.1, 0.26, 0.45), CF(side * (W / 2 + 0.02), y, bc), AMBER, M.Neon)
		end
		hull(model, "TrailerFront", V3(W, wallH, 0.3), CF(0, deckTop + wallH / 2, bs + 0.15), paint, M.Metal)
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

local function shrunk(list: { number }): { number }
	local out: { number } = table.create(#list)
	for i, v in ipairs(list) do
		out[i] = v / S
	end
	return out
end

-- A truck's layout in M1.5's units, the builders' (every length / S).
local function designOf(lay: Layout): Layout
	local slots: { Vector3 } = table.create(#lay.logSlots)
	for i, v in ipairs(lay.logSlots) do
		slots[i] = v / S
	end
	return {
		style = lay.style,
		width = lay.width / S,
		length = lay.length / S,
		front = lay.front / S,
		cabLength = lay.cabLength / S,
		bedLength = lay.bedLength / S,
		bedStart = lay.bedStart / S,
		bedCenterZ = lay.bedCenterZ / S,
		bedFloorY = lay.bedFloorY / S,
		bedWidth = lay.bedWidth / S,
		wallHeight = lay.wallHeight / S,
		wheelRadius = lay.wheelRadius / S,
		tyreWidth = lay.tyreWidth / S,
		wheelX = lay.wheelX / S,
		wheelZ = shrunk(lay.wheelZ),
		logLength = lay.logLength / S,
		logSlots = slots,
	}
end

-- A trailer's layout in M1.5's units (every length / S).
local function trailerDesignOf(tl: TrailerLayout): TrailerLayout
	local slots: { Vector3 } = table.create(#tl.logSlots)
	for i, v in ipairs(tl.logSlots) do
		slots[i] = v / S
	end
	return {
		style = tl.style,
		width = tl.width / S,
		bedLength = tl.bedLength / S,
		bedStart = tl.bedStart / S,
		bedCenterZ = tl.bedCenterZ / S,
		bedFloorY = tl.bedFloorY / S,
		bedWidth = tl.bedWidth / S,
		wallHeight = tl.wallHeight / S,
		length = tl.length / S,
		hitchZ = tl.hitchZ / S,
		wheelRadius = tl.wheelRadius / S,
		tyreWidth = tl.tyreWidth / S,
		wheelX = tl.wheelX / S,
		wheelZ = tl.wheelZ / S,
		axleZ = shrunk(tl.axleZ),
		logSlots = slots,
	}
end

-- Grows a body drawn in M1.5's units at the origin to full size, as
-- Kit.scaleModel grows a shop: every part's size and position (its turn
-- kept), each attachment's offset (the exhausts' ExhaustOut; set by CFrame,
-- which Lune's previews can read) and each wheel's Radius.
local function grow(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size = d.Size * S
			d.CFrame = CF(cf.Position * S) * (cf - cf.Position)
			local radius = d:GetAttribute("Radius")
			if d.Name == "Wheel" and type(radius) == "number" then
				d:SetAttribute("Radius", radius * S)
			end
		elseif d:IsA("Attachment") then
			local cf = d.CFrame
			d.CFrame = CF(cf.Position * S) * (cf - cf.Position)
		end
	end
end

-- Adds a trailer to `model` (a truck built by TruckArt.Build), behind the
-- truck in truck-local studs (`tl`, its TrailerLayout): its body (drawn in
-- M1.5's units and grown, drawTrailer) and its skid ("TrailerSkid").
function TruckArt.AddTrailer(model: Model, trailer: TrailerDef, tl: TrailerLayout)
	local body = Instance.new("Model")
	drawTrailer(body, trailer, trailerDesignOf(tl))
	grow(body)
	for _, child in ipairs(body:GetChildren()) do
		child:SetAttribute("TrailerBody", true)
		child.Parent = model
	end
	body:Destroy()
	frictionlessSkid(model, "TrailerSkid", tl.width - 0.4, tl.bedLength - 1, tl.bedCenterZ)
end

-- Declared below Build; assigned before Build ever runs.
local sanitize: (Model) -> ()
local parkTrailer: (Model) -> ()
local organize: (Model) -> ()

-- The owner's name on both doors, readable out to 60 studs, and the
-- dashboard estimate. Added after organize so these stay direct children.
-- TODO: a horn, once there is an original sound for it. Not on the pass.
local function addClassic(model: Model, doorName: string?)
	local cab = model:FindFirstChild("Cab", true)
	if not cab or not cab:IsA("BasePart") then
		return
	end
	local text = if type(doorName) == "string" then doorName else ""
	local cf, size = cab.CFrame, cab.Size
	local plateSize = Vector3.new(0.05, math.clamp(size.Y * 0.42, 0.8, 1.6), math.clamp(size.Z * 0.5, 1, 2.4))
	for _, side in ipairs({ -1, 1 }) do
		local plate = Kit.part(
			model,
			"DoorPlate",
			plateSize,
			cf * CFrame.new(side * (size.X / 2 - 0.04), 0, 0),
			Color3.fromRGB(28, 26, 24),
			Enum.Material.SmoothPlastic
		)
		Kit.decor(plate, false)
		local tag = Instance.new("BillboardGui")
		tag.Name = "DoorTag"
		tag.Size = UDim2.fromOffset(180, 48)
		tag.StudsOffset = Vector3.zero
		tag.MaxDistance = 60
		tag.LightInfluence = 0
		tag.ClipsDescendants = true
		tag.AlwaysOnTop = false
		tag.Parent = plate
		local label = Instance.new("TextLabel")
		label.Name = "DoorName"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(245, 235, 215)
		label.Text = text
		label.Parent = tag
	end
	-- In front of the driver (truck front is -Z). The face they see is +Z.
	local gauge = Kit.part(
		model,
		"LoadGauge",
		Vector3.new(1.4, 0.55, 0.06),
		cf * CFrame.new(0, size.Y * 0.12, -size.Z * 0.28),
		Color3.fromRGB(20, 22, 26),
		Enum.Material.SmoothPlastic
	)
	Kit.decor(gauge, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GaugeGui"
	gui.Face = Enum.NormalId.Back
	gui.Enabled = false
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	gui.Parent = gauge
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.BackgroundTransparency = 1
	readout.Size = UDim2.fromScale(1, 1)
	readout.Font = Enum.Font.GothamBold
	readout.TextScaled = true
	readout.TextWrapped = true
	readout.TextColor3 = Color3.fromRGB(120, 220, 140)
	readout.Text = ""
	readout.Parent = gui
	ClassicGauge.Apply(model, 0)
end

-- A truck (and its trailer, when given) at the origin, ground y = 0, front
-- -Z. Every part is anchored; Rig turns it into one rigid body.
function TruckArt.Build(
	def: TruckDef,
	layout: Layout?,
	trailer: TrailerDef?,
	trailerLayout: TrailerLayout?,
	extras: BuildExtras?
): Model
	local lay = layout or TruckLayout.For(def)
	local model = Instance.new("Model")
	model.Name = def.id

	-- The body, drawn in M1.5's units round the layout shrunk by S, grown.
	local build = builders[lay.style] or builders.flatbed
	local paintHex = def.look.color
	if extras and type(extras.paint) == "string" then
		paintHex = extras.paint
	end
	local paint = hex(paintHex)
	model:SetAttribute("PaintHex", paintHex)
	build({
		model = model,
		def = def,
		lay = designOf(lay),
		paint = paint,
		rng = Kit.rng(seedOf(def.id)),
	})
	grow(model)

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
	frictionlessSkid(model, "Skid", lay.width - 0.4, lay.length - 1, 0)

	local bed = model:FindFirstChild("BedFloor")
	if bed and bed:IsA("BasePart") then
		TruckArt.AddBedZone(bed, lay.bedWidth, lay.bedLength, lay.wallHeight)
	end
	if trailer then
		local tl = trailerLayout or TruckLayout.ForTrailer(trailer, lay)
		TruckArt.AddTrailer(model, trailer, tl)
		local trailerBed = model:FindFirstChild("TrailerBed")
		if trailerBed and trailerBed:IsA("BasePart") then
			TruckArt.AddBedZone(trailerBed, tl.bedWidth, tl.bedLength, tl.wallHeight)
		end
	end

	-- Where the "Load logs" prompt hangs: just behind the last bed.
	local lastBed = model:FindFirstChild("TrailerBed") or model:FindFirstChild("BedFloor")
	if lastBed and lastBed:IsA("BasePart") then
		local point = Instance.new("Attachment")
		point.Name = "LoadPoint"
		point.CFrame = CF(0, 1, lastBed.Size.Z / 2 + 0.6)
		point.Parent = lastBed
	end
	sanitize(model)
	parkTrailer(model)
	organize(model)
	if def.classic == true then
		addClassic(model, if extras then extras.doorName else nil)
	end
	-- Uploaded meshes when every one loads. A miss keeps this part-built truck.
	-- Door plates and the load gauge are already on the model; VehicleMeshes keeps them.
	VehicleMeshes.Apply(model, def.id, if trailer then trailer.id else nil)
	return model
end

-- Only these materials. Neon stays on light lenses; everything else that
-- isn't glass or metal becomes SmoothPlastic. No textures, decals or meshes.
local LIGHT_FACE = { Headlight = true, Taillight = true, Marker = true, Beacon = true }
local METALISH = { CorrodedMetal = true, Foil = true, DiamondPlate = true }

function sanitize(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local name = d.Material.Name
			local lit = name == "Neon" and LIGHT_FACE[d.Name] == true
			if name == "Glass" or name == "Metal" or name == "SmoothPlastic" or lit then
				continue
			elseif METALISH[name] == true then
				d.Material = M.Metal
			else
				d.Material = M.SmoothPlastic
			end
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SpecialMesh") then
			d:Destroy()
		end
	end
end

-- Trailer body (not the skid) hangs off the trailer bed, so it can swing
-- on the hitch as one piece. The bed and the skid stay direct children.
function parkTrailer(model: Model)
	local bed = model:FindFirstChild("TrailerBed")
	if not bed or not bed:IsA("BasePart") then
		return
	end
	for _, child in ipairs(model:GetChildren()) do
		-- The coupler and tongue stay on the truck, at the hitch. The bed
		-- and everything on it swings. Coupler stays a direct child: the
		-- tow test finds it there.
		if
			child:GetAttribute("TrailerBody") == true
			and child ~= bed
			and child.Name ~= "Coupler"
			and child.Name ~= "Tongue"
		then
			child.Parent = bed
		end
	end
end

local CONTRACT = {
	Chassis = true,
	Skid = true,
	TrailerSkid = true,
	DriverSeat = true,
	BedFloor = true,
	TrailerBed = true,
}
local LIGHTS = { Headlight = true, Taillight = true, LampBezel = true, Beacon = true, Marker = true, LightBar = true }
local BED = {
	BedBoard = true,
	BedWall = true,
	BedPost = true,
	Tailgate = true,
	BedCap = true,
	BedFront = true,
	Stake = true,
	StakeRail = true,
	StakePocket = true,
	Stanchion = true,
	Chain = true,
	HeadacheRack = true,
}

local function folderNamed(model: Model, name: string): Folder
	local found = model:FindFirstChild(name)
	if found and found:IsA("Folder") then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = model
	return folder
end

-- Body, Wheels, Bed, Lights. Contract parts stay direct children, and a
-- part already parented to another part (a rim, a ramp, the trailer) stays.
function organize(model: Model)
	local body = folderNamed(model, "Body")
	local wheelFolder = folderNamed(model, "Wheels")
	local bed = folderNamed(model, "Bed")
	local lights = folderNamed(model, "Lights")
	for _, child in ipairs(model:GetChildren()) do
		if not child:IsA("BasePart") or CONTRACT[child.Name] or child.Name == "Coupler" or child.Name == "Tongue" then
			continue
		end
		if child.Name == "Wheel" then
			child.Parent = wheelFolder
		elseif LIGHTS[child.Name] then
			child.Parent = lights
		elseif BED[child.Name] then
			child.Parent = bed
		elseif child.Name ~= "Body" and child.Name ~= "Wheels" and child.Name ~= "Bed" and child.Name ~= "Lights" then
			child.Parent = body
		end
	end
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
			if d.Name == "TrailerBed" then
				-- The hitch, not a weld: VehicleFX swings it. It never folds.
				local hitch = Instance.new("Motor6D")
				hitch.Name = "Hitch"
				hitch.Part0 = chassis
				hitch.Part1 = d
				hitch.C0 = chassis.CFrame:ToObjectSpace(d.CFrame)
				hitch.C1 = CFrame.identity
				hitch.Parent = d
			elseif d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
				local hung = if parent and parent:IsA("BasePart") then parent else chassis
				local axle = Instance.new("Motor6D")
				axle.Name = "Axle"
				axle.Part0 = hung
				axle.Part1 = d
				axle.C0 = hung.CFrame:ToObjectSpace(d.CFrame)
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

---------------------------------------------------------------------------
-- The v2 loop: loose wood rides on the beds (V2_PLAN §4b, M1.6)
---------------------------------------------------------------------------

-- The parts a load lies on or leans against: bed floors, walls, boards,
-- tailgates and stakes (the hull, but for the chassis and the skids).
TruckArt.BedParts = {
	BedFloor = true,
	BedBoard = true,
	BedWall = true,
	Tailgate = true,
	Stake = true,
	StakeRail = true,
	Stanchion = true,
	TrailerBed = true,
	TrailerBoard = true,
	TrailerFront = true,
	TrailerGate = true,
	TrailerStake = true,
	TrailerRail = true,
	TrailerStanchion = true,
} :: { [string]: boolean }

-- Adds a bed's BedZone: an invisible box over `bed` (a bed floor part),
-- `width` (inside its walls or stakes) x TruckLayout.BedZoneHeight x
-- `length`, its bottom on the floor's top. A piece of wood whose centre is
-- inside it rides on that bed (TruckLoad). It never collides, can't be
-- hit by rays or clicked, fires no touches and casts no shadow, so it
-- changes nothing about how the truck looks or drives; Rig welds it to
-- its bed. Attributes: Room (the u³ the bed carries a trip,
-- TruckLayout.BedRoomU3) and Length (the bed's, in studs). Returns it.
function TruckArt.AddBedZone(bed: BasePart, width: number, length: number, wallHeight: number): Part
	local offset, size = TruckLayout.BedZone(width, length)
	local zone = Kit.part(bed, "BedZone", size, bed.CFrame * offset, Color3.new(1, 1, 1), M.SmoothPlastic)
	Kit.decor(zone, false)
	zone.Transparency = 1
	zone:SetAttribute("Room", TruckLayout.BedRoomU3(length, width, wallHeight, GameConfig.WoodUnit))
	zone:SetAttribute("Length", length)
	return zone
end

-- Every BedZone on a built truck, each with the bed part it sits on.
function TruckArt.BedZones(model: Model): { { zone: BasePart, bed: BasePart } }
	local out: { { zone: BasePart, bed: BasePart } } = {}
	for _, name in ipairs({ "BedFloor", "TrailerBed" }) do
		local bed = model:FindFirstChild(name)
		local zone = if bed then bed:FindFirstChild("BedZone") else nil
		if bed and bed:IsA("BasePart") and zone and zone:IsA("BasePart") then
			table.insert(out, { zone = zone, bed = bed })
		end
	end
	return out
end

-- Gives every bed part (TruckArt.BedParts) of a built truck the grip of
-- `friction`: CustomPhysicalProperties with a heavy friction weight, so
-- wood resting on it feels `friction` itself, and no bounce. The v2 loop
-- does this to each player's truck (TruckLoad, BedFriction); the v1 loop
-- never does, so its trucks keep their materials' own physics. The beds
-- are massless once rigged, so the density changes nothing.
TruckArt.BedFrictionWeight = 100
function TruckArt.ApplyBedFriction(model: Model, friction: number)
	local props = PhysicalProperties.new(0.7, friction, 0, TruckArt.BedFrictionWeight, TruckArt.BedFrictionWeight)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and TruckArt.BedParts[d.Name] then
			d.CustomPhysicalProperties = props
		end
	end
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
