--!strict
-- HearthAndHome: the General Store's interior, in the new store look (Shared/
-- Art/ShopInterior dispatches here). Built from ShopKit like the Tool Shed
-- pilot: a tier stand per slot on the four units (gear, lamps and the two plan
-- islands), a header over each unit and a sub-sign per category, warm beams and
-- lanterns, a CHECKOUT plaque on the counter, wall shelving behind the side
-- units, plants and a stock corner. The lanes are StoreStock's and are not
-- moved; the two 3.2-stud side aisles stay open by keeping every sign
-- high and every light over the aisle, never at head height.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local BoxLook = require(script.Parent.Parent.Parent.BoxLook)
local StoreStock = require(script.Parent.Parent.Parent.StoreStock)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local counterDetail = ShopKit.counterDetail
local backDoor = ShopKit.backDoor
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber

local Hearth = {}

-- The roof is flat here (the underside is the frame's ceiling), so the signs'
-- collar ties sit just under the beams.
Hearth.TieY = 14.1
Hearth.HeaderY = 12.3
Hearth.StoreSignY = 12.2 -- the middle of the shop's name board on the back wall
-- The roof's underside, from BuildingArt's General Store (the roof slab is 0.5 thick, its middle
-- at (10 + 0.4) x scale): the beams and ties reach up to it so nothing of the ceiling hangs loose.
Hearth.RoofUnder = (10 + 0.4 - 0.25) * 1.5
Hearth.BeamY = Hearth.RoofUnder - 0.45 -- the beams' middle (they are 0.9 deep)
Hearth.TopY = Hearth.RoofUnder -- the highest part the interior adds

-- What the signs say, from the shop's real stock (ids are ItemCatalog ids; a
-- spec checks every slot of the shop is under exactly one sign).
Hearth.Sections = {
	{
		lane = "GearShelf",
		header = "GEAR",
		accent = BoxLook.Categories.Gear,
		subAbove = 3.0,
		subW = 4.6,
		subStagger = -1.2, -- toward the aisle, clear of the wall shelving
		subs = {
			{
				text = "WEAR & LIGHT",
				ids = { "FeatherfallCloak", "Flashlight", "HeatBoots", "InsulatedCoat", "Lantern" },
			},
		},
	},
	{
		lane = "PlanIslandW",
		header = "BUILD PLANS",
		accent = BoxLook.Categories.Blueprint,
		subAbove = 2.4, -- no tier flags on the plans, so the sign hangs lower and stays under the header
		subW = 4.4,
		subStagger = 3.4,
		subs = {
			{ text = "SHED & YARD", ids = { "Shed", "WoodSign", "PaintCan", "Mailbox" } },
			{ text = "INDOORS", ids = { "PictureWall8", "Table", "Chair" } },
		},
	},
	{
		lane = "PlanIslandE",
		header = "HOME PLANS",
		accent = BoxLook.Categories.Blueprint,
		subAbove = 2.4,
		subW = 4.4,
		subStagger = 3.4,
		subs = {
			{ text = "HOME DECOR", ids = { "Bookshelf", "Rug", "Barrel", "Crate" } },
			{ text = "FIRE & LAMP", ids = { "FirePit", "SparkSwitch", "SparkLamp" } },
		},
	},
	{
		lane = "LampShelf",
		header = "LAMPS",
		accent = BoxLook.Categories.Cosmetic,
		subAbove = 2.8,
		subW = 4.6,
		subStagger = 1.2,
		subs = {
			{ text = "LAMP POST", ids = { "LampPost" } },
		},
	},
} :: { ShopKit.Section }

-- A crate or barrel in the stock corner: the real mesh with a part-built
-- stand-in dropped when it has loaded (ShopKit.MeshProp).
local function stockProp(model: Model, asset: string, x: number, y: number, z: number, yaw: number)
	local fallback = Instance.new("Model")
	fallback.Name = asset .. "Fallback"
	local at = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
	if asset == "Crate" then
		dBox(fallback, "Crate", V3(2, 2.4, 2), at * CF(0, 1.2, 0), TABLE_TOP)
		dBox(fallback, "CrateBand", V3(2.06, 0.2, 2.06), at * CF(0, 1.2, 0), TIMBER)
	else
		dBox(fallback, "Barrel", V3(1.6, 2.2, 1.6), at * CF(0, 1.1, 0), TABLE)
		dBox(fallback, "BarrelHoop", V3(1.7, 0.16, 1.7), at * CF(0, 1.1, 0), ShopKit.Table.iron)
	end
	fallback.Parent = model
	ShopKit.MeshProp(model, asset, at, fallback)
end

function Hearth.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2605)
	local ceil = frame.ceilY
	local fy = frame.floorTop
	local lampTop = Hearth.BeamY - 0.45 -- chains end on the beams' underside
	local extents = ShopKit.SteppedUnit(model, "HearthAndHome", frame, "Shelf", TABLE, TABLE_TOP)
	for _, lane in ipairs(StoreStock.Lanes("HearthAndHome")) do
		local ext = extents[lane.name]
		if ext and (lane.name == "GearShelf" or lane.name == "LampShelf") then
			local lo, hi = ext.lo, ext.hi
			-- Tall back shelving on the wall behind the unit: an upright
			-- panel and two boards, looks only.
			local wallX = if lane.x0 < 0 then -frame.halfW + 0.3 else frame.halfW - 0.3
			local cz = (lo + hi) / 2
			dBox(model, "ShelfBack", V3(0.3, 9.5, hi - lo), CF(wallX, fy + 4.75 + 0.3, cz), TABLE)
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

	-- Floor: warm boards, a green border, the long runner down the middle.
	plankFloor(model, frame, hex("#C8995F"), { hex("#B3874F"), hex("#D8AB72"), hex("#A57A47") }, 2.8, rng)
	floorBorder(model, frame, 0.8, hex("#4E7A3E"), MAT.Wood)
	runner(model, frame, 3.6, -frame.halfD + 1.6, 12)

	-- Warm timber beams (none at a sign's z), the lanterns hung from them.
	-- (a beam at every z a lamp or the back-wall sign hangs from, so no chain ends in the air)
	ShopKit.Beams(model, frame, { -19, -14.5, -9, -2.2, 3, 8.5, 14.5, 20.2 }, Hearth.BeamY)
	ShopKit.Rafter(model, frame, 0, Hearth.BeamY - 0.1)
	-- Over the central aisle and over the two side aisles; none in the first 9
	-- studs (the entrance stays open) and none at a sign's end.
	for _, z in ipairs({ -2.2, 3 }) do
		ShopKit.WarmLamp(model, -15.6, ceil - 3.4, z, lampTop)
		ShopKit.WarmLamp(model, 15.6, ceil - 3.4, z, lampTop)
	end
	ShopKit.WarmLamp(model, -2.6, ceil - 3.4, -9, lampTop)
	ShopKit.WarmLamp(model, 2.6, ceil - 3.4, -9, lampTop)
	ShopKit.WarmLamp(model, -2.6, ceil - 3.4, 3, lampTop)
	ShopKit.WarmLamp(model, 2.6, ceil - 3.4, 3, lampTop)
	-- Over the counter end and the back corners, so no corner is dark.
	for _, x in ipairs({ -15.6, -7, 7, 15.6 }) do
		ShopKit.WarmLamp(model, x, ceil - 3.4, 14.5, lampTop)
	end

	-- Signs: a header over each unit, a sub-sign over each category, CHECKOUT.
	ShopKit.SectionSigns(model, "HearthAndHome", Hearth.Sections, {
		headerY = Hearth.HeaderY,
		headerZ = -12.5,
		tieY = Hearth.TieY,
		tieTop = Hearth.RoofUnder,
		subShift = 0, -- the side units are 6.8 wide against a wall: centred, a sub-sign stays in the room
	})
	ShopKit.CheckoutSign(model, frame)
	-- The shop's own name over the counter, readable from the door.
	ShopKit.HeaderSign(model, {
		cx = 0,
		cy = Hearth.StoreSignY,
		z = 20.2,
		w = 13,
		h = 2.6,
		text = "HEARTH & HOME",
		accent = ShopKit.Colors.Brass,
		ceilY = lampTop,
		name = "StoreSign",
	})

	-- Plants at the front corners of the shelving, and a stock corner by the
	-- east back wall (clear of the back-room door in the west wall).
	ShopKit.plant(model, -frame.halfW + 2, fy, -frame.halfD + 2, 1.2)
	ShopKit.plant(model, frame.halfW - 2, fy, -frame.halfD + 2, 1.2)
	stockProp(model, "Crate", 21.2, fy, 18.6, 0.1)
	stockProp(model, "Crate", 21.2, fy, 16.4, -0.15)
	stockProp(model, "Barrel", 18.2, fy, 19.6, 0)
end

return Hearth
