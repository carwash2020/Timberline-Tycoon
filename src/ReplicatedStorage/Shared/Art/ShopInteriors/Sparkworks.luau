--!strict
-- Sparkworks: the automation shop's interior (Shared/Art/ShopInterior
-- dispatches here). Built from the older helpers; to apply the new look see
-- ShopInteriors/ToolShed (the pilot) and the recipe in STATUS.md.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local StoreStock = require(script.Parent.Parent.Parent.StoreStock)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local hangSign = ShopKit.hangSign
local beam = ShopKit.beam
local lamp = ShopKit.lamp
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local counterDetail = ShopKit.counterDetail
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local PAPER = ShopKit.Table.paper

local Sparkworks = {}

-- A shelf unit down each side wall (the west one the belt fittings and the
-- first logic pieces, the east one the rest), a copper-edged runner down the
-- aisle, two hanging lamps and two aisle boards. The shelves are the same
-- stepped units the other shops use, read from StoreStock's lanes.
local COPPER = hex("#B87333")
local TEAL = hex("#2E8B8B")

function Sparkworks.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2607)
	local extents = ShopKit.SteppedUnit(model, "Sparkworks", frame, "Shelf", TABLE, TABLE_TOP)
	for _, lane in ipairs(StoreStock.Lanes("Sparkworks")) do
		local ext = extents[lane.name]
		if ext then
			-- Tall back shelving on the wall behind the unit: an upright panel
			-- and two boards, looks only.
			local lo, hi = ext.lo, ext.hi
			local wallX = if lane.x0 < 0 then -frame.halfW + 0.3 else frame.halfW - 0.3
			local cz = (lo + hi) / 2
			dBox(model, "ShelfBack", V3(0.3, 9.5, hi - lo), CF(wallX, frame.floorTop + 4.75 + 0.3, cz), TABLE)
			for _, y in ipairs({ 6.6, 9.6 }) do
				dBox(
					model,
					"WallShelf",
					V3(1.6, 0.25, hi - lo),
					CF(wallX + (if lane.x0 < 0 then 0.8 else -0.8), y, cz),
					TABLE_TOP
				)
			end
		end
	end
	counterDetail(model, frame)
	plankFloor(model, frame, hex("#B98C58"), { hex("#A37A49"), hex("#CB9D68"), hex("#946B3F") }, 2.8, rng)
	floorBorder(model, frame, 0.8, COPPER, MAT.Metal)
	runner(model, frame, 3.2, -frame.halfD + 1.6, 11)
	local y = frame.ceilY
	beam(model, y - 0.45, 0, 2 * frame.halfW - 0.6)
	lamp(model, -11.3, y - 3.4, -5.25, y - 0.9)
	lamp(model, 11.3, y - 3.4, -5.25, y - 0.9)
	hangSign(model, -11.3, y - 3.4, -17.1, 7.2, 1.5, y - 0.9, "BELTS + SWITCHES", TEAL, PAPER)
	hangSign(model, 11.3, y - 3.4, -17.1, 7.2, 1.5, y - 0.9, "GATES + OUTPUTS", hex("#8E5BB5"), PAPER)
end

return Sparkworks
