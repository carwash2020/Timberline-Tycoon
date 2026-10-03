--!strict
-- TruckLayout: where each part of a truck goes, worked out from its
-- ItemCatalog entry (look + bedCapacity). TruckArt draws the body from it,
-- VehicleService builds the physics from it, and tests check it (every log
-- fits in the bed, every rig fits a parking slot, and so on).
--
-- Truck-local studs: the front faces -Z, the wheels touch y = 0 and x = 0
-- is the middle. Each truck has a style (farm truck, pickup, quad, flatbed,
-- log rig) that sets its cab length, wheel size, bed height and how tall
-- its bed's walls or stakes stand; the bed behind the cab is as long as
-- the look says.
--
-- M1.5 (V2_PLAN §4c): the trucks and trailers grew to carry the bigger
-- trees. Drivers didn't, so the cabs grew taller round them (TruckArt.spec:
-- a seated driver's hat clears every roof).
--
-- Phase 12 (Connor, after seeing the live build: "Cars can get upsized
-- again"): every truck and trailer is Scale (1.3) times its M1.5 size,
-- cab, bed, wheels, walls and all, so a 5-stud character stands by chunky
-- trucks. The proportions below are M1.5's, times Scale; TruckArt still
-- draws each body in M1.5's units and grows it by Scale, so each one keeps
-- its look. Drivers stay avatar-sized, sat a little higher in bigger cabs.

local ItemCatalog = require(script.Parent.ItemCatalog)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local TruckLayout = {}

TruckLayout.Scale = 1.3
local S = TruckLayout.Scale

TruckLayout.CabLength = 7 * S -- the default cab (hood + seat); see STYLES for each truck's own
TruckLayout.LogDiameter = 0.9 -- the v1 bed's logs (TreeService's): they didn't grow
-- The chassis's centre above the ground (VehicleService's WHEEL_CLEARANCE):
-- just over the biggest wheels' axles (the Rig's 2.275), so every wheel's
-- centre is below it. Its underside, half a stud lower, is the top of the
-- skids TruckArt hangs under it.
TruckLayout.ChassisY = 1.8 * S
TruckLayout.BedFloorThickness = 0.5
local TAIL = 0.5 * S -- chassis behind the bed
local ATV_REAR = 2 * S -- the Scout ATV's rear rack instead of a bed
-- Along the bed, centre to centre: each truck's bed holds as many logs a
-- layer as it did before the beds grew (M1.5, phase 12), spread out along
-- them.
local LOG_SPACING = 1.5 * S
local BED_FLOOR_TOP = 0.25 -- above the bed floor part's centre (it's 0.5 thick)
TruckLayout.Tongue = 2 * S -- gap between the truck's back and the trailer's bed

-- Body styles: "farm" | "pickup" | "atv" | "flatbed" | "rig" (trucks),
-- "pony" | "ranch" | "heavy" (trailers). TruckArt has a builder for each.
export type Style = string
export type TrailerStyle = string

type StyleSpec = {
	cabLength: number,
	wheelRadius: number,
	tyreWidth: number,
	frontAxle: number, -- front axle, behind the front bumper
	rearAxle: number, -- last axle, in front of the back
	tandem: boolean, -- a second rear axle (the long open decks)
	tandemGap: number, -- between the two rear axles
	bedFloorY: number, -- bed floor part's centre height
	wall: number, -- how thick the bed's walls (or stakes) are, each side
	wallHeight: number, -- how far they stand over the bed floor's top
}

-- The axles set each truck's wheelbase, and with it its tightest turning
-- circle (DriveMath.MinTurnRadius): each truck's stays within 10% of what
-- it was before the trucks grew (DriveMath.spec). In studs: M1.5's sizes
-- times Scale.
local STYLES: { [Style]: StyleSpec } = {
	farm = {
		cabLength = 7 * S,
		wheelRadius = 1.3 * S,
		tyreWidth = 1 * S,
		frontAxle = 2.4 * S,
		rearAxle = 2.7 * S,
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.75 * S, -- floor top 3.825
		wall = 0.3 * S, -- 7.28 inside
		wallHeight = 1.4 * S,
	},
	pickup = {
		cabLength = 7.4 * S,
		wheelRadius = 1.35 * S,
		tyreWidth = 1.05 * S,
		frontAxle = 2.5 * S,
		rearAxle = 4.5 * S, -- two thirds of the way back along the bed, as on a real pickup
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.85 * S, -- floor top 3.955
		wall = 0.3 * S, -- 7.8 inside
		wallHeight = 1.6 * S,
	},
	atv = {
		cabLength = 6.5 * S,
		wheelRadius = 1.25 * S,
		tyreWidth = 1.4 * S,
		frontAxle = 1.7 * S,
		rearAxle = 1.7 * S,
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.75 * S,
		wall = 0,
		wallHeight = 0,
	},
	flatbed = {
		cabLength = 7.8 * S,
		wheelRadius = 1.4 * S, -- the deck's underside (3.715) clears the tyre tops (3.64)
		tyreWidth = 1.1 * S,
		frontAxle = 2.9 * S,
		rearAxle = 4.6 * S,
		tandem = true,
		tandemGap = 3.2 * S,
		bedFloorY = 3.05 * S, -- deck top 4.215
		wall = 0.2 * S, -- the stakes: 8.84 inside
		wallHeight = 2.5 * S,
	},
	rig = {
		cabLength = 9.4 * S,
		wheelRadius = 1.75 * S, -- the biggest wheels: the top of the ladder (ACT-07)
		tyreWidth = 1.15 * S,
		frontAxle = 3.6 * S, -- under the long nose
		rearAxle = 4.9 * S, -- the tandem under the back bunks, the load hanging over
		tandem = true,
		tandemGap = 3.8 * S,
		bedFloorY = 3.75 * S, -- a raised deck (top 5.125), its underside clear of the big wheels' tops
		wall = 0.3 * S, -- the bunk stakes: 9.36 inside
		wallHeight = 3.2 * S,
	},
}

local STYLE_FOR: { [string]: Style } = {
	Rustbucket = "farm",
	Pickup = "pickup",
	ScoutATV = "atv",
	Flatbed = "flatbed",
	LoggingRig = "rig",
	TimberClassic = "pickup",
}

-- A truck's body style: its own for each catalog truck, else guessed from
-- the look, so a new ItemCatalog truck still builds.
function TruckLayout.StyleOf(def: TruckDef): Style
	local style = STYLE_FOR[def.id]
	if style then
		return style
	end
	local look = def.look
	if look.bedLength <= 0 then
		return "atv"
	elseif look.bedWalls then
		return if look.bedLength <= 7 then "farm" else "pickup"
	end
	return if look.bedLength >= 15 then "rig" else "flatbed"
end

export type Layout = {
	style: Style,
	width: number,
	length: number,
	front: number, -- z of the front bumper (-length / 2)
	cabLength: number,
	bedLength: number,
	bedStart: number, -- z where the bed begins, behind the cab
	bedCenterZ: number,
	bedFloorY: number, -- height of the bed floor part's centre (0.5 thick)
	bedWidth: number, -- inside the bed's walls or stakes (0 without a bed)
	wallHeight: number, -- the walls' or stakes' height over the bed floor's top
	wheelRadius: number,
	tyreWidth: number,
	wheelX: number, -- centre of a tyre, either side
	wheelZ: { number }, -- one axle per entry; the first one steers
	logLength: number,
	logSlots: { Vector3 }, -- log centres, relative to the bed floor part's centre
}

-- Log centres for `count` logs on a bed `bedLength` long, relative to the
-- bed floor part's centre: across the bed, side by side along it, in layers.
local function logSlots(bedLength: number, count: number): { Vector3 }
	local slots: { Vector3 } = {}
	if bedLength <= 0 then
		return slots
	end
	local perLayer = math.max(1, math.floor((bedLength - 0.4 * S) / LOG_SPACING))
	for i = 1, count do
		local layer = (i - 1) // perLayer
		local col = (i - 1) % perLayer
		local z = -(perLayer - 1) * LOG_SPACING / 2 + col * LOG_SPACING
		local y = BED_FLOOR_TOP + TruckLayout.LogDiameter / 2 + layer * TruckLayout.LogDiameter
		table.insert(slots, Vector3.new(0, y, z))
	end
	return slots
end

function TruckLayout.For(def: TruckDef): Layout
	local look = def.look
	local style = TruckLayout.StyleOf(def)
	local spec = STYLES[style]
	local width, bedLength = look.width, look.bedLength
	local cabLength = spec.cabLength
	local length = cabLength + (if bedLength > 0 then bedLength + TAIL else ATV_REAR)
	local front = -length / 2
	local bedStart = front + cabLength

	local rear = length / 2 - spec.rearAxle
	local wheelZ = { front + spec.frontAxle, rear }
	if spec.tandem then
		table.insert(wheelZ, rear - spec.tandemGap) -- the long decks get a second rear axle
	end

	return {
		style = style,
		width = width,
		length = length,
		front = front,
		cabLength = cabLength,
		bedLength = bedLength,
		bedStart = bedStart,
		bedCenterZ = bedStart + bedLength / 2,
		bedFloorY = spec.bedFloorY,
		bedWidth = if bedLength > 0 then width - 2 * spec.wall else 0,
		wallHeight = spec.wallHeight,
		wheelRadius = spec.wheelRadius,
		tyreWidth = spec.tyreWidth,
		-- The tyre tucks 0.26 studs under the body's side.
		wheelX = width / 2 + spec.tyreWidth / 2 - 0.2 * S,
		wheelZ = wheelZ,
		logLength = width - 0.8 * S,
		logSlots = logSlots(bedLength, def.bedCapacity),
	}
end

---------------------------------------------------------------------------
-- The v2 loop: loose wood rides on the beds (V2_PLAN §4b, M1.6)
---------------------------------------------------------------------------

-- How tall a bed's BedZone stands over the bed floor's top: a piece whose
-- centre is inside it rides on that bed (TruckLoad). Over the tallest
-- walls (the Rig's bunk stakes, 4.16): 4 before the trucks grew again.
TruckLayout.BedZoneHeight = 4 * S

-- A bed's BedZone, relative to its bed floor part (0.5 thick): `width`
-- (the inside of the walls or stakes) x BedZoneHeight x `length` (the
-- bed's), its bottom on the floor's top. Returns its offset and size.
function TruckLayout.BedZone(width: number, length: number): (CFrame, Vector3)
	local h = TruckLayout.BedZoneHeight
	return CFrame.new(0, BED_FLOOR_TOP + h / 2, 0), Vector3.new(width, h, length)
end

-- The wood a bed carries a trip, in u³ (`unit` studs a side): its length x
-- its inside width x (its walls + BedPileOver studs piled over them) x
-- BedPacking (how much of that a load of logs fills). The same estimate as
-- tools/economy's "u³ a trip"; the HUD's bed chip shows it as the bed's
-- room (TruckLoad publishes it as BedRoom).
TruckLayout.BedPileOver = 2
TruckLayout.BedPacking = 0.4
function TruckLayout.BedRoomU3(length: number, width: number, wallHeight: number, unit: number): number
	if length <= 0 or width <= 0 or unit <= 0 then
		return 0
	end
	return length * width * (wallHeight + TruckLayout.BedPileOver) * TruckLayout.BedPacking / (unit * unit * unit)
end

-- Truck-local z of the rear axle, the point a truck turns about (where
-- VehicleService hangs its DriveAttachment): the second axle, or the
-- middle of the tandem pair on a long bed. wheelZ is { front, rear } plus
-- `rear - tandemGap` for the tandem's front axle, so the last entry is not
-- the rear axle on a three-axle truck. A layout with only a front axle
-- turns about its middle.
function TruckLayout.DriveAxleZ(layout: Layout): number
	local z = layout.wheelZ
	if #z >= 3 then
		return (z[2] + z[3]) / 2
	elseif #z == 2 then
		return z[2]
	end
	return 0
end

-- Front axle to the axle the truck turns about (DriveAxleZ), in studs:
-- what sets its tightest turning circle (DriveMath.MinTurnRadius). 0 with
-- a single axle.
function TruckLayout.Wheelbase(layout: Layout): number
	if #layout.wheelZ < 2 then
		return 0
	end
	return TruckLayout.DriveAxleZ(layout) - layout.wheelZ[1]
end

export type TrailerLayout = {
	style: TrailerStyle,
	width: number,
	bedLength: number,
	bedStart: number, -- truck-local z of the trailer bed's front edge
	bedCenterZ: number, -- truck-local z of the trailer bed's centre
	bedFloorY: number, -- height of the trailer bed part's centre (0.5 thick)
	bedWidth: number, -- inside its walls or stakes
	wallHeight: number, -- the walls' or stakes' height over the bed floor's top
	length: number, -- tongue + bed, behind the truck
	hitchZ: number, -- truck-local z of the truck's back, where the tongue couples
	wheelRadius: number,
	tyreWidth: number,
	wheelX: number,
	wheelZ: number, -- the axle (the middle of a tandem pair)
	axleZ: { number }, -- every axle
	logSlots: { Vector3 }, -- relative to the trailer bed floor's centre
}

local TRAILER_STYLE_FOR: { [string]: TrailerStyle } = {
	PonyTrailer = "pony",
	RanchTrailer = "ranch",
	HeavyHauler = "heavy",
}

type TrailerSpec = {
	wheelRadius: number,
	tyreWidth: number,
	tandemGap: number, -- 0: one axle
	wall: number,
	wallHeight: number,
}

local TRAILERS: { [TrailerStyle]: TrailerSpec } = {
	pony = { wheelRadius = 1.15 * S, tyreWidth = 0.85 * S, tandemGap = 0, wall = 0.25 * S, wallHeight = 1.2 * S },
	ranch = { wheelRadius = 1.2 * S, tyreWidth = 0.85 * S, tandemGap = 0, wall = 0.26 * S, wallHeight = 2 * S },
	heavy = { wheelRadius = 1.25 * S, tyreWidth = 0.9 * S, tandemGap = 2.6 * S, wall = 0.32 * S, wallHeight = 2.5 * S },
}
local TRAILER_FLOOR_Y = 2.25 * S -- the trailer bed floor's centre (top 3.175)
-- A trailer's tyres tuck this far under its deck, so a trailer as wide as
-- the Rig, fenders and all, still fits a parking slot.
local TRAILER_TUCK = 0.3 * S

-- A rig's footprint seen from above, in studs: its length (the truck and
-- its trailer end to end) and width (its body or its tyres, whichever
-- stick out further). Fenders and mirrors add a few tenths (TruckArt.spec).
-- What VehicleService fits to a parking bay (VehicleLogic.BayChoices).
function TruckLayout.RigSize(layout: Layout, trailer: TrailerLayout?): (number, number)
	local length = layout.length + (if trailer then trailer.length else 0)
	local width = math.max(layout.width, 2 * layout.wheelX + layout.tyreWidth)
	if trailer then
		width = math.max(width, 2 * trailer.wheelX + trailer.tyreWidth)
	end
	return length, width
end

function TruckLayout.TrailerStyleOf(trailer: TrailerDef): TrailerStyle
	local style = TRAILER_STYLE_FOR[trailer.id]
	if style then
		return style
	end
	if trailer.extraCapacity >= 20 then
		return "heavy"
	end
	return if trailer.extraCapacity >= 10 then "ranch" else "pony"
end

-- Where a trailer sits behind `truck` (a Layout): as wide as the truck, its
-- bed starting a tongue's length behind the truck's back.
function TruckLayout.ForTrailer(trailer: TrailerDef, truck: Layout): TrailerLayout
	local style = TruckLayout.TrailerStyleOf(trailer)
	local spec = TRAILERS[style]
	local bedLength = trailer.look.bedLength
	local bedStart = truck.length / 2 + TruckLayout.Tongue
	local wheelZ = bedStart + bedLength * 0.6
	local axleZ = if spec.tandemGap > 0
		then { wheelZ - spec.tandemGap / 2, wheelZ + spec.tandemGap / 2 }
		else { wheelZ }
	return {
		style = style,
		width = truck.width,
		bedLength = bedLength,
		bedStart = bedStart,
		bedCenterZ = bedStart + bedLength / 2,
		bedFloorY = TRAILER_FLOOR_Y,
		bedWidth = truck.width - 2 * spec.wall,
		wallHeight = spec.wallHeight,
		length = TruckLayout.Tongue + bedLength,
		hitchZ = truck.length / 2,
		wheelRadius = spec.wheelRadius,
		tyreWidth = spec.tyreWidth,
		wheelX = truck.width / 2 + spec.tyreWidth / 2 - TRAILER_TUCK,
		wheelZ = wheelZ,
		axleZ = axleZ,
		logSlots = logSlots(bedLength, trailer.extraCapacity),
	}
end

return TruckLayout
