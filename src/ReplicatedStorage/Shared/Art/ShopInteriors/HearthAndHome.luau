--!strict
-- HearthAndHome: the General Store's interior (Shared/Art/ShopInterior
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
local backDoor = ShopKit.backDoor
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local PAPER = ShopKit.Table.paper

local Hearth = {}

function Hearth.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2605)
	local extents = ShopKit.SteppedUnit(model, "HearthAndHome", frame, "Shelf", TABLE, TABLE_TOP)
	for _, lane in ipairs(StoreStock.Lanes("HearthAndHome")) do
		local ext = extents[lane.name]
		if ext and (lane.name == "GearShelf" or lane.name == "LampShelf") then
			local lo, hi = ext.lo, ext.hi
			-- Tall back shelving on the wall behind the unit: an upright
			-- panel and two boards, looks only.
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
	backDoor(model, frame, -frame.halfW + 0.3, 18.5, false, -1)
	plankFloor(model, frame, hex("#C8995F"), { hex("#B3874F"), hex("#D8AB72"), hex("#A57A47") }, 2.8, rng)
	floorBorder(model, frame, 0.8, hex("#4E7A3E"), MAT.Wood)
	runner(model, frame, 3.6, -frame.halfD + 1.6, 12)
	local y = frame.ceilY
	beam(model, y - 0.45, 0, 2 * frame.halfW - 0.6)
	lamp(model, -10, y - 3.4, -5.25, y - 0.9)
	lamp(model, 10, y - 3.4, 3.75, y - 0.9)
	hangSign(model, -10.2, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "GEAR", hex("#2E8B7A"), PAPER)
	hangSign(model, 10.2, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "LAMPS", hex("#8E5BB5"), PAPER)
end

return Hearth
