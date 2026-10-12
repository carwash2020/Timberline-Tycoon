--!strict
-- HearthAndHome: the General Store's interior, in the new store look (Shared/
-- Art/ShopInterior dispatches here). Built from ShopKit like the Tool Shed
-- pilot: a wood-top DisplayTable per row of boxes on the four units (gear, lamps
-- and the two plan islands) with a small price card (and, for a gated item, a lock
-- card) per box and a warm spot over each table, a header over each unit, warm
-- beams and lanterns, a CHECKOUT board hung over the counter, wall shelving with
-- jars, books and baskets, framed pictures, a rug, plants and a stock corner. The lanes are StoreStock's and are not
-- moved; the two 3.2-stud side aisles stay open by keeping every sign
-- high and every light over the aisle, never at head height.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local BoxLook = require(script.Parent.Parent.Parent.BoxLook)
local StoreStock = require(script.Parent.Parent.Parent.StoreStock)
local ShopEventKit = require(script.Parent.Parent.ShopEventKit)

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
Hearth.StoreSignY = 12.5 -- the middle of the shop's name board on the back wall
-- The roof's underside, from BuildingArt's General Store (the roof slab is 0.5 thick, its middle
-- at (10 + 0.4) x scale). A plank ceiling fills the 0.6 between the frame's ceiling line and it, so the
-- beams, ties and every chain hang from something solid and no sky shows through.
Hearth.RoofUnder = (10 + 0.4 - 0.25) * 1.5
Hearth.TopY = Hearth.RoofUnder -- the highest part the interior adds

-- What the signs say: one header over each unit (every slot of the shop stands in one of the four lanes,
-- so every item is under exactly one header; a spec checks it). The small category signs the first pass
-- hung under the headers are gone (Connor: too many signs, too close together): each box carries its own
-- name tag and each stand its T-badge and unlock label, so the categories added nothing a player needs.
-- (The two plan headers stand 7.2 wide and nearer the aisle (their lanes are 9 wide, 5 to 14 out), so from the door and
-- from a phone the whole word is on screen and not cut by the door frame or the edge of the view.)
Hearth.Sections = {
	{
		lane = "GearShelf",
		header = "GEAR",
		accent = BoxLook.Categories.Gear,
		subs = {},
		headerW = 5.6,
		headerCx = -19.6,
	},
	{
		lane = "PlanIslandW",
		header = "BUILD PLANS",
		accent = BoxLook.Categories.Blueprint,
		subs = {},
		headerW = 7.2,
		headerCx = -8.6,
	},
	{
		lane = "PlanIslandE",
		header = "HOME PLANS",
		accent = BoxLook.Categories.Blueprint,
		subs = {},
		headerW = 7.2,
		headerCx = 8.6,
	},
	{
		lane = "LampShelf",
		header = "LAMPS",
		accent = BoxLook.Categories.Cosmetic,
		subs = {},
		headerW = 5.6,
		headerCx = 19.6,
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

-- A warm spot over each table: one per row of the plan islands and the lamp shelf, and over every other row of the
-- gear shelf (a single box a row; the spot between lights its neighbour). The shade is 5.6 over the table top.
Hearth.SpotRise = 5.6 -- (until the shade is this high over the table; the shades hang flush under the ceiling boards: no chain, one part each)
function Hearth.SpotLamps(model: Model, frame: Frame)
	local rows: { [string]: { x: number, z: number, y: number, n: number, row: number, lane: string } } = {}
	for _, place in ipairs(StoreStock.Placements("HearthAndHome")) do
		local key = place.lane .. place.row
		local r = rows[key]
		if r == nil then
			rows[key] = {
				x = place.x,
				z = place.z,
				y = place.surface + StoreStock.PlinthHeight,
				n = 1,
				row = place.row,
				lane = place.lane,
			}
		else
			r.x += place.x
			r.z += place.z
			r.n += 1
		end
	end
	local keys: { string } = {}
	for key in pairs(rows) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local r = rows[key]
		if r.lane ~= "GearShelf" or r.row % 2 == 1 then
			ShopKit.SpotLamp(model, r.x / r.n, frame.ceilY - 0.2, r.z / r.n, frame.ceilY)
		end
	end
end

local JAR = { hex("#7FB7A4"), hex("#D9A441"), hex("#B5594A"), hex("#9DB87A") }
local BASKET = hex("#B88A4E")

-- A wall shelf unit on a side wall (x is the wall's inner face, `side` -1 west / +1 east): a back panel, two boards
-- and what stands on them (jars, books, baskets). Looks only; z0..z1 is its length along the wall.
local function wallShelves(
	model: Model,
	wallX: number,
	side: number,
	z0: number,
	z1: number,
	lowY: number,
	seed: number
)
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	local inward = -side -- toward the room
	local panelX = wallX + inward * 0.1
	dBox(model, "NookPanel", V3(0.2, 4.4, len), CF(panelX, lowY + 1.9, cz), TABLE)
	local boardX = wallX + inward * 0.7
	local ys = { lowY, lowY + 2.6 }
	for _, y in ipairs(ys) do
		dBox(model, "NookBoard", V3(1.2, 0.25, len), CF(boardX, y, cz), TABLE_TOP)
	end
	local top1, top2 = ys[1] + 0.125, ys[2] + 0.125
	local function put(name: string, size: Vector3, topY: number, dz: number, color: Color3, mat: Enum.Material?)
		return dBox(model, name, size, CF(boardX, topY + size.Y / 2, cz + dz), color, mat or MAT.SmoothPlastic)
	end
	local u = len / 8
	-- lower board: a basket, two jars, a basket
	put("NookBasket", V3(0.95, 0.8, 1.5), top1, -3 * u, BASKET, MAT.Wood)
	put("NookJar", V3(0.7, 1.1, 0.7), top1, -0.9 * u, JAR[1 + seed % 4], MAT.Glass)
	put("NookJar", V3(0.7, 0.8, 0.7), top1, 0.9 * u, JAR[1 + (seed + 1) % 4], MAT.Glass)
	put("NookBasket", V3(0.95, 0.95, 1.5), top1, 3 * u, BASKET, MAT.Wood)
	-- upper board: two jars
	put("NookJar", V3(0.65, 1.0, 0.65), top2, -1.5 * u, JAR[1 + (seed + 2) % 4], MAT.Glass)
	put("NookJar", V3(0.65, 0.7, 0.65), top2, 1.5 * u, JAR[1 + (seed + 3) % 4], MAT.Glass)
end

-- A framed picture flat on a wall facing -Z (the back wall): a wood frame and a canvas just proud of it.
local function picture(model: Model, x: number, y: number, wallZ: number, w: number, h: number, canvas: Color3)
	dBox(model, "PictureFrame", V3(w, h, 0.2), CF(x, y, wallZ - 0.1), TABLE)
	dBox(model, "PictureArt", V3(w - 0.5, h - 0.5, 0.1), CF(x, y, wallZ - 0.22), canvas, MAT.SmoothPlastic)
end

-- The room's furnishings beyond the stock: wall shelves with jars, books and baskets, framed pictures on the back
-- wall over the price boards, a rug in the east nook and two more plants. All looks only, all inside the walls, none
-- in the entrance aisle or the lanes.
function Hearth.Dressing(model: Model, frame: Frame)
	local fy = frame.floorTop
	wallShelves(model, -frame.halfW, -1, 6.4, 14.8, 5.2, 0)
	wallShelves(model, frame.halfW, 1, -3.4, 12.4, 5.2, 1)
	local backZ = frame.halfD
	picture(model, -13.2, 12.0, backZ, 3.4, 2.4, hex("#9CC3D8"))
	picture(model, 13.2, 12.0, backZ, 3.4, 2.4, hex("#E0B77A"))
	picture(model, -19.6, 12.0, backZ, 2.6, 2.6, hex("#C98B7B"))
	picture(model, 19.6, 12.0, backZ, 2.6, 2.6, hex("#8DB08A"))
	-- a rug in the east nook, by the crates
	dBox(model, "NookRug", V3(7.4, 0.06, 4.4), CF(19.0, fy + ShopKit.Layer[2], 11.6), hex("#3E5F7A"), MAT.Fabric)
	dBox(model, "NookRugEdge", V3(6.4, 0.07, 3.4), CF(19.0, fy + ShopKit.Layer[3], 11.6), hex("#D9C28A"), MAT.Fabric)
	ShopKit.plant(model, 22.2, fy, 7.2, 1.1)
	ShopKit.plant(model, -22.2, fy, 5.0, 1.1)
end

function Hearth.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2605)
	local ceil = frame.ceilY
	local fy = frame.floorTop
	local lampTop = ceil - 0.9 -- chains end on the beams' underside
	local extents = ShopKit.SteppedUnit(model, "HearthAndHome", frame, "Shelf", TABLE, TABLE_TOP, "table")
	Hearth.SpotLamps(model, frame)
	for _, lane in ipairs(StoreStock.Lanes("HearthAndHome")) do
		local ext = extents[lane.name]
		if ext and (lane.name == "GearShelf" or lane.name == "LampShelf") then
			local lo, hi = ext.lo, ext.hi
			-- Tall back shelving on the wall behind the unit: an upright
			-- panel and two boards, looks only.
			local wallX = if lane.x0 < 0 then -frame.halfW + 0.15 else frame.halfW - 0.15 -- (the panel stands against the wall, behind the unit: not in it)
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

	-- The plank ceiling (looks only), from the beams' top to the roof's underside.
	dBox(
		model,
		"CeilingBoards",
		V3(2 * frame.halfW - 0.2, Hearth.RoofUnder - ceil, 2 * frame.halfD - 0.2),
		CF(0, (ceil + Hearth.RoofUnder) / 2, 0),
		hex("#6B4A2E"),
		MAT.WoodPlanks
	)

	-- Floor: warm boards, a green border, the long runner down the middle.
	plankFloor(model, frame, hex("#C8995F"), { hex("#B3874F"), hex("#D8AB72"), hex("#A57A47") }, 2.8, rng)
	floorBorder(model, frame, 0.8, hex("#4E7A3E"), MAT.Wood)
	runner(model, frame, 3.6, -frame.halfD + 1.6, 12)

	-- Warm timber beams (none at a sign's z), the lanterns hung from them.
	-- (a beam at every z a lamp or the back-wall sign hangs from, so no chain ends in the air)
	ShopKit.Beams(model, frame, { -19, -14.5, -9, -2.2, 3, 8.5, 14.5, 20.2 })
	ShopKit.Rafter(model, frame, 0)
	-- Over the central aisle and over the two side aisles; none in the first 9
	-- studs (the entrance stays open) and none at a sign's end.
	-- (the side aisles: one lamp each side at z -2.2; the spots over the tables light the rest, and the part budget is tight)
	ShopKit.WarmLamp(model, -15.6, ceil - 3.4, -2.2, lampTop)
	ShopKit.WarmLamp(model, 15.6, ceil - 3.4, -2.2, lampTop)
	ShopKit.WarmLamp(model, -4.2, ceil - 3.4, 3, lampTop) -- (4.2 out: from the door these stay clear of the name board over the counter)
	ShopKit.WarmLamp(model, 4.2, ceil - 3.4, 3, lampTop)
	-- Over the counter end and the back corners, so no corner is dark.
	for _, x in ipairs({ -15.6, -9, 9, 15.6 }) do
		ShopKit.WarmLamp(model, x, ceil - 3.4, 14.5, lampTop)
	end

	-- Signs: a header over each unit, a sub-sign over each category, CHECKOUT.
	ShopKit.SectionSigns(model, "HearthAndHome", Hearth.Sections, {
		headerY = Hearth.HeaderY,
		headerZ = -12.5,
		tieY = Hearth.TieY,
		tieTop = ceil,
		subShift = 0, -- the side units are 6.8 wide against a wall: centred, a sub-sign stays in the room
	})
	-- CHECKOUT stands on two posts on the counter's front edge, above the register and the bell and under the shop's own
	-- name board (which hangs 6 studs further back), so it reads from the door over the counter; no plaque on the face.
	ShopKit.CheckoutSign(model, frame, { plaque = false, onCounter = true, cy = 7.7, w = 5.4, h = 1.5 })
	-- The shop's own name over the counter, readable from the door.
	ShopKit.HeaderSign(model, {
		cx = 0,
		cy = Hearth.StoreSignY,
		z = 20.2,
		w = 11,
		h = 2.0, -- the price boards on the back wall top out at 10.95: this hangs clear of them
		text = "HEARTH & HOME",
		accent = ShopKit.Colors.Brass,
		ceilY = lampTop,
		name = "StoreSign",
	})

	-- Plants at the front corners of the shelving, and a stock corner by the
	-- east back wall (clear of the back-room door in the west wall).
	ShopKit.plant(model, -frame.halfW + 2, fy, -frame.halfD + 2, 1.2)
	ShopKit.plant(model, frame.halfW - 2, fy, -frame.halfD + 2, 1.2)
	Hearth.Dressing(model, frame)
	stockProp(model, "Crate", 21.2, fy, 18.6, 0.1)
	stockProp(model, "Crate", 21.2, fy, 16.4, -0.15)
	stockProp(model, "Barrel", 18.2, fy, 19.6, 0)

	-- The event expansion room (EVENTS.md, ShopEventKit): a roped-off 16 x 9 area in the back west corner, its open front
	-- toward the door and its back against the back wall, between the counter and the west wall (clear of the gear shelf,
	-- the island, the back-room door and the counter); and the event banner in the front west corner, off the doorway
	-- aisle, facing the door.
	ShopEventKit.BuildZone(model, "HearthAndHome", CF(-14.6, fy, 15.8), V3(16, 0, 9))
	ShopEventKit.BuildBanner(model, "HearthAndHome", CF(-15.6, fy, -19.6) * CFrame.Angles(0, math.pi, 0), 4.4)
end

return Hearth
