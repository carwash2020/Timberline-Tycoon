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

local ItemCatalog = require(script.Parent.ItemCatalog)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local TruckLayout = {}

TruckLayout.CabLength = 7 -- the default cab (hood + seat); see STYLES for each truck's own
TruckLayout.LogDiameter = 0.9
-- The chassis's centre above the ground (VehicleService's WHEEL_CLEARANCE):
-- just over the biggest wheels' axles (the Rig's 1.75), so every wheel's
-- centre is below it. Its underside, half a stud lower, is the top of the
-- skids TruckArt hangs under it.
TruckLayout.ChassisY = 1.8
TruckLayout.BedFloorThickness = 0.5
local TAIL = 0.5 -- chassis behind the bed
local ATV_REAR = 2 -- the Scout ATV's rear rack instead of a bed
-- Along the bed, centre to centre: each truck's bed holds as many logs a
-- layer as it did before the beds grew (M1.5), spread out along them.
local LOG_SPACING = 1.5
local BED_FLOOR_TOP = 0.25 -- above the bed floor part's centre (it's 0.5 thick)
TruckLayout.Tongue = 2 -- gap between the truck's back and the trailer's bed

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
-- it was before the trucks grew (DriveMath.spec).
local STYLES: { [Style]: StyleSpec } = {
	farm = {
		cabLength = 7,
		wheelRadius = 1.3,
		tyreWidth = 1,
		frontAxle = 2.4,
		rearAxle = 2.7,
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.75, -- floor top 3.0
		wall = 0.3, -- 5.6 inside
		wallHeight = 1.4,
	},
	pickup = {
		cabLength = 7.4,
		wheelRadius = 1.35,
		tyreWidth = 1.05,
		frontAxle = 2.5,
		rearAxle = 4.5, -- two thirds of the way back along the bed, as on a real pickup
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.85, -- floor top 3.1
		wall = 0.3, -- 6.0 inside
		wallHeight = 1.6,
	},
	atv = {
		cabLength = 6.5,
		wheelRadius = 1.25,
		tyreWidth = 1.4,
		frontAxle = 1.7,
		rearAxle = 1.7,
		tandem = false,
		tandemGap = 0,
		bedFloorY = 2.75,
		wall = 0,
		wallHeight = 0,
	},
	flatbed = {
		cabLength = 7.8,
		wheelRadius = 1.4, -- the deck's underside (2.8) clears the tyre tops
		tyreWidth = 1.1,
		frontAxle = 2.9,
		rearAxle = 4.6,
		tandem = true,
		tandemGap = 3.2,
		bedFloorY = 3.05, -- deck top 3.3
		wall = 0.2, -- the stakes: 6.8 inside
		wallHeight = 2.5,
	},
	rig = {
		cabLength = 9.4,
		wheelRadius = 1.75, -- the biggest wheels: the top of the ladder (ACT-07)
		tyreWidth = 1.15,
		frontAxle = 3.6, -- under the long nose
		rearAxle = 4.9, -- the tandem under the back bunks, the load hanging over
		tandem = true,
		tandemGap = 3.8,
		bedFloorY = 3.75, -- a raised deck (top 4.0), its underside clear of the big wheels' tops
		wall = 0.3, -- the bunk stakes: 7.2 inside
		wallHeight = 3.2,
	},
}

local STYLE_FOR: { [string]: Style } = {
	Rustbucket = "farm",
	Pickup = "pickup",
	ScoutATV = "atv",
	Flatbed = "flatbed",
	LoggingRig = "rig",
}

-- A truck's body style: its own for the five trucks, else guessed from the
-- look, so a new ItemCatalog truck still builds.
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
	local perLayer = math.max(1, math.floor((bedLength - 0.4) / LOG_SPACING))
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
		-- The tyre tucks 0.2 studs under the body's side.
		wheelX = width / 2 + spec.tyreWidth / 2 - 0.2,
		wheelZ = wheelZ,
		logLength = width - 0.8,
		logSlots = logSlots(bedLength, def.bedCapacity),
	}
end

---------------------------------------------------------------------------
-- The v2 loop: loose wood rides on the beds (V2_PLAN §4b, M1.6)
---------------------------------------------------------------------------

-- How tall a bed's BedZone stands over the bed floor's top: a piece whose
-- centre is inside it rides on that bed (TruckLoad).
TruckLayout.BedZoneHeight = 4

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
-- tools/economy2's "u³ a trip"; the HUD's bed chip shows it as the bed's
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
	pony = { wheelRadius = 1.15, tyreWidth = 0.85, tandemGap = 0, wall = 0.25, wallHeight = 1.2 },
	ranch = { wheelRadius = 1.2, tyreWidth = 0.85, tandemGap = 0, wall = 0.26, wallHeight = 2 },
	heavy = { wheelRadius = 1.25, tyreWidth = 0.9, tandemGap = 2.6, wall = 0.32, wallHeight = 2.5 },
}
local TRAILER_FLOOR_Y = 2.25 -- the trailer bed floor's centre (top 2.5)
-- A trailer's tyres tuck this far under its deck, so a trailer as wide as
-- the Rig, fenders and all, still fits a parking slot.
local TRAILER_TUCK = 0.3

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
