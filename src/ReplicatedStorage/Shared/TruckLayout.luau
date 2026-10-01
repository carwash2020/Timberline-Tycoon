--!strict
-- TruckLayout: where each part of a truck goes, worked out from its
-- ItemCatalog entry (look + bedCapacity). TruckArt draws the body from it,
-- VehicleService builds the physics from it, and tests check it (every log
-- fits in the bed, every rig fits a parking slot, and so on).
--
-- Truck-local studs: the front faces -Z, the wheels touch y = 0 and x = 0
-- is the middle. Each truck has a style (farm truck, pickup, quad, flatbed,
-- log rig) that sets its cab length, wheel size and bed height; the bed
-- behind the cab is as long as the look says.

local ItemCatalog = require(script.Parent.ItemCatalog)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local TruckLayout = {}

TruckLayout.CabLength = 5.4 -- the default cab (hood + seat); see STYLES for each truck's own
TruckLayout.LogDiameter = 0.9
TruckLayout.ChassisY = 1.5 -- chassis centre above the ground (VehicleService's WHEEL_CLEARANCE)
TruckLayout.BedFloorThickness = 0.5
local TAIL = 0.4 -- chassis behind the bed
local ATV_REAR = 1.6 -- the Scout ATV's rear rack instead of a bed
local LOG_SPACING = 1 -- along the bed, centre to centre
local BED_FLOOR_TOP = 0.25 -- above the bed floor part's centre (it's 0.5 thick)
TruckLayout.Tongue = 1.5 -- gap between the truck's back and the trailer's bed

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
	tandemGap: number, -- between the two rear axles of a long bed
	bedFloorY: number, -- bed floor part's centre height
}

local STYLES: { [Style]: StyleSpec } = {
	farm = {
		cabLength = 5.4,
		wheelRadius = 1,
		tyreWidth = 0.8,
		frontAxle = 1.7,
		rearAxle = 1.9,
		tandemGap = 2.4,
		bedFloorY = 2.25,
	},
	pickup = {
		cabLength = 5.6,
		wheelRadius = 1.05,
		tyreWidth = 0.85,
		frontAxle = 1.8,
		rearAxle = 2,
		tandemGap = 2.4,
		bedFloorY = 2.25,
	},
	atv = {
		cabLength = 5,
		wheelRadius = 0.95,
		tyreWidth = 1.15,
		frontAxle = 1.3,
		rearAxle = 1.3,
		tandemGap = 2.4,
		bedFloorY = 2.25,
	},
	flatbed = {
		cabLength = 5.8,
		wheelRadius = 1.1,
		tyreWidth = 0.9,
		frontAxle = 1.9,
		rearAxle = 2,
		tandemGap = 2.5,
		bedFloorY = 2.45,
	},
	rig = {
		cabLength = 7,
		wheelRadius = 1.4, -- the biggest wheels: the top of the ladder (ACT-07)
		tyreWidth = 0.9,
		frontAxle = 2.2,
		-- Wide enough apart for the big tyres, and the tandem's middle (the
		-- axle it turns about, DriveAxleZ) where it was: 2.0 + 2.9 / 2 =
		-- 2.1 + 2.7 / 2, so the wheelbase and turning circle don't change.
		rearAxle = 2,
		tandemGap = 2.9,
		bedFloorY = 3.05, -- a raised deck, its underside clear of the big wheels' tops
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
	if bedLength >= 12 then
		table.insert(wheelZ, rear - spec.tandemGap) -- long beds get a second rear axle
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
		wheelRadius = spec.wheelRadius,
		tyreWidth = spec.tyreWidth,
		-- The tyre tucks 0.2 studs under the body's side.
		wheelX = width / 2 + spec.tyreWidth / 2 - 0.2,
		wheelZ = wheelZ,
		logLength = width - 0.8,
		logSlots = logSlots(bedLength, def.bedCapacity),
	}
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
	local bedLength = trailer.look.bedLength
	local bedStart = truck.length / 2 + TruckLayout.Tongue
	local wheelRadius = if style == "heavy" then 0.95 else 0.9
	local tyreWidth = if style == "heavy" then 0.8 else 0.7
	local wheelZ = bedStart + bedLength * 0.6
	local axleZ = if style == "heavy" then { wheelZ - 1.05, wheelZ + 1.05 } else { wheelZ }
	return {
		style = style,
		width = truck.width,
		bedLength = bedLength,
		bedStart = bedStart,
		bedCenterZ = bedStart + bedLength / 2,
		bedFloorY = 1.75,
		length = TruckLayout.Tongue + bedLength,
		hitchZ = truck.length / 2,
		wheelRadius = wheelRadius,
		tyreWidth = tyreWidth,
		wheelX = truck.width / 2 + tyreWidth / 2 - 0.2,
		wheelZ = wheelZ,
		axleZ = axleZ,
		logSlots = logSlots(bedLength, trailer.extraCapacity),
	}
end

return TruckLayout
