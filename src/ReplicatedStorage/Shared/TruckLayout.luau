--!strict
-- TruckLayout: where each part of a truck goes, worked out from its
-- ItemCatalog entry (look + bedCapacity). VehicleService builds the model
-- from it and tests check it (every log fits in the bed, and so on).
--
-- Truck-local studs: the front faces -Z, the wheels touch y = 0 and x = 0
-- is the middle. Every truck has the same cab up front (hood, dash, seat,
-- roll bar); the bed behind it is as long as the look says.

local ItemCatalog = require(script.Parent.ItemCatalog)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local TruckLayout = {}

TruckLayout.CabLength = 5.4 -- hood (2.6) + seat and roll bar (2.8)
TruckLayout.LogDiameter = 0.9
local TAIL = 0.4 -- chassis behind the bed
local ATV_REAR = 1.6 -- the Scout ATV's rear rack instead of a bed
local LOG_SPACING = 1 -- along the bed, centre to centre
local BED_FLOOR_TOP = 0.25 -- above the bed floor part's centre (it's 0.5 thick)
TruckLayout.Tongue = 1.5 -- gap between the truck's back and the trailer's bed

export type Layout = {
	width: number,
	length: number,
	front: number, -- z of the front bumper (-length / 2)
	bedLength: number,
	bedStart: number, -- z where the bed begins, behind the cab
	bedCenterZ: number,
	wheelX: number,
	wheelZ: { number }, -- one axle per entry
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
	local width, bedLength = look.width, look.bedLength
	local length = TruckLayout.CabLength + (if bedLength > 0 then bedLength + TAIL else ATV_REAR)
	local front = -length / 2
	local bedStart = front + TruckLayout.CabLength

	local wheelZ = { front + 1.6, length / 2 - 1.8 }
	if bedLength >= 12 then
		table.insert(wheelZ, length / 2 - 4.2) -- long beds get a second rear axle
	end

	return {
		width = width,
		length = length,
		front = front,
		bedLength = bedLength,
		bedStart = bedStart,
		bedCenterZ = bedStart + bedLength / 2,
		wheelX = width / 2 + 0.2,
		wheelZ = wheelZ,
		logLength = width - 0.8,
		logSlots = logSlots(bedLength, def.bedCapacity),
	}
end

export type TrailerLayout = {
	width: number,
	bedLength: number,
	bedCenterZ: number, -- truck-local z of the trailer bed's centre
	length: number, -- tongue + bed, behind the truck
	wheelZ: number,
	logSlots: { Vector3 }, -- relative to the trailer bed floor's centre
}

-- Where a trailer sits behind `truck` (a Layout): as wide as the truck, its
-- bed starting a tongue's length behind the truck's back.
function TruckLayout.ForTrailer(trailer: TrailerDef, truck: Layout): TrailerLayout
	local bedLength = trailer.look.bedLength
	local bedStart = truck.length / 2 + TruckLayout.Tongue
	return {
		width = truck.width,
		bedLength = bedLength,
		bedCenterZ = bedStart + bedLength / 2,
		length = TruckLayout.Tongue + bedLength,
		wheelZ = bedStart + bedLength * 0.6,
		logSlots = logSlots(bedLength, trailer.extraCapacity),
	}
end

return TruckLayout
