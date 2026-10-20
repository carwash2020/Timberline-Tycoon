--!strict
-- Sparkworks: the automation shop's interior (Shared/Art/ShopInterior dispatches here), in the new store look of
-- the General Store (ShopInteriors/HearthAndHome) with the Sparkworks' own spark-teal and copper: a wood-top
-- DisplayTable per row of boxes down both shelf units (belts and inputs down the west wall, gates, timers, outputs
-- and lasers down the east one) with a small price card per box (a lock card for a gated item) and a warm spot over
-- every table, one header over each unit, a CHECKOUT board on the counter and the shop's name over it, warm beams and
-- lanterns, copper conduit and fuse boxes on the side walls, wall shelves with coils, cells and jars, framed
-- circuit pictures on the back wall, a rug, plants, wire spools on a pallet and a stock corner. The back west corner is
-- the roped-off event room and the event banner stands by the counter (ShopEventKit). Looks only: nothing here
-- moves a lane, a slot or a price. The two lanes are StoreStock's; the aisle between them stays open.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local StoreStock = require(script.Parent.Parent.Parent.StoreStock)
local ShopEventKit = require(script.Parent.Parent.ShopEventKit)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local counterDetail = ShopKit.counterDetail
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber

local Sparkworks = {}

local COPPER = hex("#B87333")
local TEAL = hex("#2E8B8B")
local FUSE = hex("#3A332D")

-- The room is 15 high: the roof rests on the walls, so its underside is the frame's ceiling and the beams, ties and
-- chains all reach up to it. The signs hang from deep ties under the roof.
Sparkworks.TieY = 14.2
Sparkworks.HeaderY = 12.2
Sparkworks.StoreSignY = 12.0 -- the middle of the shop's name board on the back wall
Sparkworks.TopY = 15 -- the highest part the interior adds (the roof's underside)

-- What the signs say: one header over each unit (every slot of the shop stands in one of the two lanes, so every item
-- is under exactly one header; a spec checks it). The small category signs the first pass hung under the headers are
-- gone (Connor: too many signs, too close together): each box carries its own name card and each table its price cards.
-- The headers are 10 wide, fully inside the room, with their ties.
Sparkworks.Sections = {
	{
		lane = "FittingShelf",
		header = "BELTS & INPUTS",
		accent = TEAL,
		subs = {},
		headerW = 10,
		headerCx = -11.3,
	},
	{
		lane = "LogicShelf",
		header = "LOGIC & OUTPUTS",
		accent = COPPER,
		subs = {},
		headerW = 10,
		headerCx = 11.3,
	},
} :: { ShopKit.Section }

-- The event room (a roped-off area in the back west corner, its open front toward the aisle: the zone is turned a
-- quarter so its local -Z faces +X) and the banner by the counter, off the aisle, facing the door.
Sparkworks.EventZone = { x = -12.5, z = 11.5, size = V3(12, 0, 10) }
Sparkworks.BannerAt = { x = 8.2, z = 11.6, width = 4.4 }

-- A warm spot over every table (one per row of boxes), the shade flush under the roof.
function Sparkworks.SpotLamps(model: Model, frame: Frame)
	local rows: { [string]: { x: number, z: number, n: number } } = {}
	for _, place in ipairs(StoreStock.Placements("Sparkworks")) do
		local key = place.lane .. place.row
		local r = rows[key]
		if r == nil then
			rows[key] = { x = place.x, z = place.z, n = 1 }
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
		ShopKit.SpotLamp(model, r.x / r.n, frame.ceilY - 0.2, r.z / r.n, frame.ceilY)
	end
end

-- The shop's wiring on a side wall behind a shelf unit: a copper conduit running along the wall over the boxes and
-- two drops, each to a fuse box with a teal light. Looks only.
local function wallWork(model: Model, frame: Frame, west: boolean, lo: number, hi: number)
	local wallX = if west then -frame.halfW else frame.halfW
	local into = if west then 1 else -1
	local cz = (lo + hi) / 2
	dBox(model, "Conduit", V3(0.4, 0.4, hi - lo - 0.6), CF(wallX + into * 0.2, 11.4, cz), COPPER, MAT.Metal)
	for _, z in ipairs({ lo + 3, hi - 3 }) do
		dBox(model, "ConduitDrop", V3(0.3, 0.9, 0.3), CF(wallX + into * 0.2, 10.8, z), COPPER, MAT.Metal)
		dBox(model, "FuseBox", V3(0.5, 1.5, 1.2), CF(wallX + into * 0.25, 9.6, z), FUSE, MAT.Metal)
		dBox(model, "FuseLight", V3(0.2, 0.3, 0.3), CF(wallX + into * 0.58, 9.9, z), TEAL, MAT.SmoothPlastic)
	end
end

local CELL = { hex("#3FC9C0"), hex("#D9A441"), hex("#B5594A"), hex("#7FB7A4") }

-- Wall shelves on a side wall: a thin back panel, two boards and what stands on them (coils of wire, battery cells
-- and glass jars of bolts). Looks only; z0..z1 is its length along the wall.
local function wallShelves(model: Model, frame: Frame, west: boolean, z0: number, z1: number, seed: number)
	local wallX = if west then -frame.halfW else frame.halfW
	local into = if west then 1 else -1
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	dBox(model, "ShelfPanel", V3(0.15, 4.6, len), CF(wallX + into * 0.075, 8.0, cz), TABLE)
	local boardX = wallX + into * 0.7
	local ys = { 6.6, 9.4 }
	for _, y in ipairs(ys) do
		dBox(model, "WallBoard", V3(1.1, 0.25, len), CF(boardX, y, cz), TABLE_TOP)
	end
	local u = len / 6
	for i, y in ipairs(ys) do
		local top = y + 0.125
		for k = 1, 3 do
			local dz = (k - 2) * 2 * u + (if i == 2 then 0.8 * u else 0)
			local pick = (seed + i + k) % 3
			if pick == 0 then
				Kit.decor(Kit.ball(model, "ShelfCoil", 1.0, CF(boardX, top + 0.5, cz + dz), COPPER, MAT.Metal), false)
			elseif pick == 1 then
				dBox(
					model,
					"ShelfCell",
					V3(0.8, 0.9, 0.8),
					CF(boardX, top + 0.45, cz + dz),
					CELL[1 + (seed + k + i) % 4],
					MAT.SmoothPlastic
				)
			else
				dBox(
					model,
					"ShelfJar",
					V3(0.7, 1.0, 0.7),
					CF(boardX, top + 0.5, cz + dz),
					CELL[1 + (seed + 2 * k) % 4],
					MAT.Glass
				)
			end
		end
	end
end

-- A framed picture flat on the back wall (facing -Z): a wood frame and a canvas just proud of it.
local function picture(model: Model, x: number, y: number, wallZ: number, w: number, h: number, canvas: Color3)
	dBox(model, "PictureFrame", V3(w, h, 0.2), CF(x, y, wallZ - 0.1), TABLE)
	dBox(model, "PictureArt", V3(w - 0.5, h - 0.5, 0.1), CF(x, y, wallZ - 0.22), canvas, MAT.SmoothPlastic)
end

-- A framed picture flat on a side wall (facing the room): the same frame and canvas, on the wall's inside face.
local function sidePicture(
	model: Model,
	frame: Frame,
	west: boolean,
	y: number,
	z: number,
	w: number,
	h: number,
	canvas: Color3
)
	local wallX = if west then -frame.halfW else frame.halfW
	local into = if west then 1 else -1
	dBox(model, "PictureFrame", V3(0.2, h, w), CF(wallX + into * 0.1, y, z), TABLE)
	dBox(model, "PictureArt", V3(0.1, h - 0.5, w - 0.5), CF(wallX + into * 0.22, y, z), canvas, MAT.SmoothPlastic)
end

-- A wire spool on its side: two timber discs and a copper-wound core.
local function spool(model: Model, x: number, y: number, z: number)
	local at = CF(x, y + 1.3, z)
	Kit.decor(Kit.cylinder(model, "Spool", 1.6, 2.0, at * CFrame.Angles(0, math.pi / 2, 0), COPPER, MAT.Metal), false)
	for _, s in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.cylinder(
				model,
				"SpoolDisc",
				0.2,
				2.6,
				at * CF(0, 0, s * 0.9) * CFrame.Angles(0, math.pi / 2, 0),
				TIMBER,
				MAT.Wood
			),
			false
		)
	end
end

-- A stock crate or barrel: the real mesh, with a part-built stand-in dropped once the mesh has loaded
-- (ShopKit.MeshProp).
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

-- The room's furnishings beyond the stock: wall shelves over the event room and in the east corner, framed circuit
-- pictures on the back wall, a rug by the banner, plants, wire spools on a pallet and a stock corner. All looks only,
-- all inside the walls, none in the entrance aisle or the lanes.
function Sparkworks.Dressing(model: Model, frame: Frame)
	local fy = frame.floorTop
	wallShelves(model, frame, true, 8.2, 17.0, 0)
	wallShelves(model, frame, false, 9.8, 17.0, 1)
	local backZ = frame.halfD
	-- (the shell's row of spark lamps and switches fills the middle of the wall, to x 10.9: the pictures hang beyond it)
	picture(model, -13.3, 9.4, backZ, 2.4, 2.6, hex("#1F5A5A"))
	picture(model, 13.3, 9.4, backZ, 2.4, 2.6, hex("#7A4A2A"))
	picture(model, -16.2, 9.4, backZ, 2.4, 2.6, hex("#2A4A66"))
	picture(model, 16.2, 9.4, backZ, 2.4, 2.6, hex("#5A3D6E"))
	-- two pictures on each side wall over the units, between the fuse boxes (the boxes below top out at 8.8)
	for _, z in ipairs({ -10.4, -3.6 }) do
		sidePicture(model, frame, true, 10.1, z, 2.6, 2.2, hex("#1F5A5A"))
		sidePicture(model, frame, false, 10.1, z, 2.6, 2.2, hex("#7A4A2A"))
	end
	-- a rug under the banner and the counter's east end
	dBox(model, "SparkRug", V3(5.0, 0.06, 2.4), CF(8.7, fy + ShopKit.Layer[2], 13.8), hex("#1F4A4A"), MAT.Fabric)
	dBox(model, "SparkRugEdge", V3(4.0, 0.07, 1.6), CF(8.7, fy + ShopKit.Layer[3], 13.8), hex("#D9C28A"), MAT.Fabric)
	ShopKit.plant(model, -6.5, fy, 16.6, 1.1)
	ShopKit.plant(model, 16.6, fy, 9.9, 1.1)
	-- wire spools on a pallet in the east back corner
	dBox(model, "SpoolPallet", V3(5.8, 0.3, 3.4), CF(14.3, fy + 0.15, 14.8), TIMBER)
	spool(model, 12.9, fy + 0.3, 14.8)
	spool(model, 15.7, fy + 0.3, 14.8)
	stockProp(model, "Crate", 7.7, fy, 16.2, 0)
	stockProp(model, "Crate", 9.9, fy, 16.2, 0.1)
	stockProp(model, "Barrel", 5.8, fy, 16.5, 0)
end

function Sparkworks.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2607)
	local ceil = frame.ceilY
	local fy = frame.floorTop
	local lampTop = ceil - 0.9 -- chains end on the beams' underside
	-- The shelf units: a wood-top display table per row of boxes, a price card per box.
	local extents = ShopKit.SteppedUnit(model, "Sparkworks", frame, "Shelf", TABLE, TABLE_TOP, "table")
	Sparkworks.SpotLamps(model, frame)
	for _, name in ipairs({ "FittingShelf", "LogicShelf" }) do
		local ext = extents[name]
		if ext then
			wallWork(model, frame, name == "FittingShelf", ext.lo, ext.hi)
		end
	end
	counterDetail(model, frame)

	-- Floor: warm boards, a copper border and the aisle runner.
	plankFloor(model, frame, hex("#B07F4F"), { hex("#94683F"), hex("#C69660"), hex("#85603C") }, 2.8, rng)
	floorBorder(model, frame, 0.8, COPPER, MAT.Metal)
	runner(model, frame, 3.2, -frame.halfD + 1.6, 11)

	-- Warm timber beams (the lanterns and the name board hang from them), a rafter along the room.
	ShopKit.Beams(model, frame, { -12, -6.8, -1.6, 3.8, 9.2, 13.5, 16.9 })
	ShopKit.Rafter(model, frame, 0)
	-- (none in the first studs: the entrance stays open; the spots over the tables light the rest)
	-- (the pair at z 3.8 stands 4.8 out: from the door they stay clear of the name board over the counter)
	for _, x in ipairs({ -2, 2 }) do
		ShopKit.WarmLamp(model, x, ceil - 3.4, -6.8, lampTop)
	end
	for _, x in ipairs({ -4.8, 4.8 }) do
		ShopKit.WarmLamp(model, x, ceil - 3.4, 3.8, lampTop)
	end
	ShopKit.WarmLamp(model, 11, ceil - 3.4, 13.5, lampTop)

	-- Signs: a header over each unit, CHECKOUT on the counter, the shop's name over it.
	ShopKit.SectionSigns(model, "Sparkworks", Sparkworks.Sections, {
		headerY = Sparkworks.HeaderY,
		headerZ = -8,
		tieY = Sparkworks.TieY,
		tieTop = ceil,
		subShift = 0,
	})
	-- CHECKOUT hangs flat on the back wall over the keeper, 3 studs over his head, so it reads from the door over the
	-- counter and nothing stands on the counter's top (no plaque on the counter's face).
	ShopKit.CheckoutSign(model, frame, { plaque = false, onCounter = true, w = 5.4, h = 1.5 })
	ShopKit.HeaderSign(model, {
		cx = 0,
		cy = Sparkworks.StoreSignY,
		z = 16.9,
		w = 11,
		h = 2.0,
		text = "SPARKWORKS",
		accent = TEAL,
		ceilY = lampTop,
		name = "StoreSign",
	})

	Sparkworks.Dressing(model, frame)

	-- The event expansion room (EVENTS.md, ShopEventKit): a roped-off 12 x 10 area in the back west corner against the
	-- west wall, its open front toward the aisle, between the west unit and the back wall (clear of the counter, the
	-- unit and the aisle); and the event banner by the counter's east end, off the aisle, facing the door.
	local zone = Sparkworks.EventZone
	ShopEventKit.BuildZone(model, "Sparkworks", CF(zone.x, fy, zone.z) * CFrame.Angles(0, -math.pi / 2, 0), zone.size)
	local banner = Sparkworks.BannerAt
	ShopEventKit.BuildBanner(model, "Sparkworks", CF(banner.x, fy, banner.z), banner.width)
end

return Sparkworks
