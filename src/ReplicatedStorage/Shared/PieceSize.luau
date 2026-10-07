--!strict
-- PieceSize: how long a kit piece is, and what that costs. PlotLogic and
-- EditLogic both need it, so it lives on its own and requires neither.

local PlotData = require(script.Parent.PlotData)

local PieceSize = {}

export type Sized = {
	len: number?,
	lenX: number?,
	lenZ: number?,
}

-- Length along local X, or both plan axes for a floor. Openings, doors,
-- stairs, ramps, roofs, posts and gates stay the size they were built.
local MODE: { [string]: string } = {
	Wall = "x",
	Wall4 = "x",
	Wall12 = "x",
	TallWall4 = "x",
	TallWall8 = "x",
	HalfWall8 = "x",
	Beam8 = "x",
	Fence = "x",
	Railing8 = "x",
	Fascia8 = "x",
	Floor = "xz",
	Floor4 = "xz",
}

local TILE = { Fence = true, Railing8 = true }

function PieceSize.CanResize(id: string): boolean
	return MODE[id] ~= nil
end

function PieceSize.Tiled(id: string): boolean
	return TILE[id] == true
end

function PieceSize.Floor(id: string): boolean
	return MODE[id] == "xz"
end

function PieceSize.Tiles(len: number, base: number): number
	if base <= 0 then
		return 1
	end
	return math.max(1, math.round(len / base))
end

local function snapLen(base: number, value: number): number?
	if value ~= value or value <= 0 or value == math.huge then
		return nil
	end
	local snapped = math.floor(value / 2 + 0.5) * 2
	local minL = base / 2
	local maxL = base * 2
	if snapped < minL - 1e-3 or snapped > maxL + 1e-3 then
		return nil
	end
	if math.abs(snapped - base) < 1e-3 then
		return nil
	end
	return snapped
end

-- A saved length that is junk becomes nil (the base size). A number outside
-- half..double is clamped onto that range, on a 2-stud step.
function PieceSize.CleanLen(base: number, value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value <= 0 or value == math.huge or value == -math.huge then
		return nil
	end
	local snapped = math.floor(value / 2 + 0.5) * 2
	local minL = base / 2
	local maxL = base * 2
	if snapped < minL then
		snapped = math.ceil(minL / 2) * 2
		if snapped < minL then
			snapped += 2
		end
	end
	if snapped > maxL then
		snapped = math.floor(maxL / 2) * 2
	end
	if snapped < minL - 1e-3 or snapped > maxL + 1e-3 then
		return nil
	end
	if math.abs(snapped - base) < 1e-3 then
		return nil
	end
	return snapped
end

function PieceSize.Lengths(bp: PlotData.Blueprint, item: Sized?): (number, number)
	local mode = MODE[bp.id]
	local lenX = bp.footprint.X
	local lenZ = bp.footprint.Y
	if item and mode == "x" and type(item.len) == "number" then
		lenX = item.len
	elseif item and mode == "xz" then
		if type(item.lenX) == "number" then
			lenX = item.lenX
		end
		if type(item.lenZ) == "number" then
			lenZ = item.lenZ
		end
	end
	return lenX, lenZ
end

function PieceSize.Units(bp: PlotData.Blueprint, item: Sized?): number
	local base = bp.woodUnits or 1
	if MODE[bp.id] == nil then
		return base
	end
	local lenX, lenZ = PieceSize.Lengths(bp, item)
	local ratio = (lenX * lenZ) / (bp.footprint.X * bp.footprint.Y)
	return math.max(1, math.ceil(base * ratio - 1e-9))
end

function PieceSize.Fee(bp: PlotData.Blueprint, item: Sized?): number
	return PieceSize.Units(bp, item) * PlotData.KitCashPerUnit
end

function PieceSize.Shape(bp: PlotData.Blueprint, item: Sized?): PlotData.Blueprint
	if not item or MODE[bp.id] == nil then
		return bp
	end
	local lenX, lenZ = PieceSize.Lengths(bp, item)
	if math.abs(lenX - bp.footprint.X) < 1e-4 and math.abs(lenZ - bp.footprint.Y) < 1e-4 then
		return bp
	end
	local sx = lenX / bp.footprint.X
	local sz = lenZ / bp.footprint.Y
	local boxes = {}
	for _, box in ipairs(bp.boxes) do
		local copy = table.clone(box)
		copy.size = Vector3.new(box.size.X * sx, box.size.Y, box.size.Z * sz)
		copy.offset = Vector3.new(box.offset.X * sx, box.offset.Y, box.offset.Z * sz)
		table.insert(boxes, copy)
	end
	local out = table.clone(bp)
	out.footprint = Vector2.new(lenX, lenZ)
	out.boxes = boxes
	out.woodUnits = PieceSize.Units(bp, item)
	return out
end

function PieceSize.LengthOk(base: number, len: number): boolean
	if math.abs(len - base) < 1e-3 then
		return true
	end
	local snapped = snapLen(base, len)
	return snapped ~= nil and math.abs(snapped - len) < 1e-3
end

-- The next length, two studs shorter (dir -1) or longer (dir 1).
-- Nil when the piece doesn't resize or the step would leave half..double.
function PieceSize.Step(bp: PlotData.Blueprint, item: Sized, dir: number): (number?, number?, number?)
	if MODE[bp.id] == nil or dir == 0 then
		return nil, nil, nil
	end
	local lenX, lenZ = PieceSize.Lengths(bp, item)
	if MODE[bp.id] == "xz" then
		local nextX = lenX + dir * 2
		local nextZ = lenZ + dir * 2
		if not PieceSize.LengthOk(bp.footprint.X, nextX) or not PieceSize.LengthOk(bp.footprint.Y, nextZ) then
			return nil, nil, nil
		end
		return nil, nextX, nextZ
	end
	local nextLen = lenX + dir * 2
	if not PieceSize.LengthOk(bp.footprint.X, nextLen) then
		return nil, nil, nil
	end
	return nextLen, nil, nil
end

return PieceSize
