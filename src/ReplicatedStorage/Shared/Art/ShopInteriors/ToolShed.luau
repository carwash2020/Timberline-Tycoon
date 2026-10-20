--!strict
-- ToolShed: the Tool Shed's interior, in the Hearth & Home restyle (Shared/Art/
-- ShopInterior dispatches here). Built from ShopKit: a wood-top DisplayTable per
-- row of boxes on both units (plank top, cream trim edge, two legs) with a small
-- price card (and a lock card for a gated axe) per box and a warm spot over each
-- table, a header over each unit, warm beams and lanterns, CHECKOUT on the counter,
-- the axe rack on the back wall, wall pegboards, shelves and framed pictures, a rug,
-- plants, the back-room door and a stock corner behind the counter, and the event room (ShopEventKit): a roped zone in the
-- back east corner and a blank banner at the aisle's west edge by the door.
-- The recipe for the other stores is in STATUS.md (Store interiors).

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local AxeArt = require(script.Parent.Parent.AxeArt)
local RobuxTableArt = require(script.Parent.Parent.RobuxTableArt)
local BoxLook = require(script.Parent.Parent.Parent.BoxLook)
local HoverTag = require(script.Parent.Parent.Parent.HoverTag)
local ItemCatalog = require(script.Parent.Parent.Parent.ItemCatalog)
local StoreStock = require(script.Parent.Parent.Parent.StoreStock)
local ShopEventKit = require(script.Parent.Parent.ShopEventKit)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local counterDetail = ShopKit.counterDetail
local backDoor = ShopKit.backDoor
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber
local PAPER = ShopKit.Table.paper

local ToolShed = {}

-- The headers hang on short chains from a cross beam built at their z (ToolShed.HeaderBeamZ), under the beams' level:
-- the chains end on that beam's underside (frame.ceilY - 0.9), so a header is held by the building and not by a tie
-- floating in the barn's roof space. Everything the interior adds stays under frame.ceilY.
ToolShed.HeaderBeamZ = -8
ToolShed.HeaderY = 10.8 -- the header board's middle: its frame's top is 0.2 under the beam
ToolShed.TieY = 12.85 -- (ShopKit.SectionSigns ends the chains 0.25 under this: on the beam's underside, 12.6)
ToolShed.TopY = 13.6 -- the highest part the interior adds (the cross beams' tops)

-- The axe rack on the back wall, as Lumber Tycoon 2 shows its axes: every axe
-- the shop sells (ItemCatalog's ladder, in order), each its real AxeArt model
-- (the part-built or mesh art the held tools use; AxeArt falls back to parts
-- if a mesh fails), standing whole on its own STEP of a stepped wall shelf,
-- each step a little higher than the one before (the ladder climbs), in front
-- of a solid backing block in the axe's tier colour (BoxLook.AxeTiers) with its
-- name plate on it. The price is not printed: aiming at an axe shows it in a
-- tag (Shared/HoverTag).
local RACK_STEP = 0.22 -- each axe's step is this much higher than the last
local RACK_BLOCK = 2.4 -- the tier-colour block behind each axe (and its step) is this wide (an axe's head and handle show up to 2.4 wide)
ToolShed.RackGap = 1.5 -- clear studs between one axe's block and the next (it was 0.3)
local RACK_AXE_SHIFT = 0.4 -- the axes' heads stick out to -x, so the pivot stands this far toward +x to centre one on its block
local RACK_PLATE = 2.4 -- the name plate: as wide as the block (slimmer than the first pass), so a plate stands well clear of the next
local RACK_BASE = 7.5 -- the first step's top
local RACK_PANEL_Y = 9.7
local RACK_PANEL_H = 6.8
local function axeRack(model: Model, frame: Frame)
	local axes: { ItemCatalog.AxeDef } = {}
	for _, axe in ipairs(ItemCatalog.AxeLadder()) do
		if axe.sold ~= false then
			table.insert(axes, axe)
		end
	end
	if #axes == 0 then
		return
	end
	-- Each axe has its own block, ToolShed.RackGap from the next, so a plate, a
	-- block and an axe read as one item and not as one strip.
	local pitch = RACK_BLOCK + ToolShed.RackGap
	local width = (#axes - 1) * pitch + RACK_BLOCK + 1.4
	local wallZ = frame.halfD
	dBox(model, "Pegboard", V3(width, RACK_PANEL_H, 0.3), CF(0, RACK_PANEL_Y, wallZ - 0.2), TABLE)
	for _, y in ipairs({ RACK_PANEL_Y - RACK_PANEL_H / 2, RACK_PANEL_Y + RACK_PANEL_H / 2 }) do
		dBox(model, "AxeRackRail", V3(width + 0.3, 0.35, 0.3), CF(0, y, wallZ - 0.3), TIMBER) -- (0.3 deep: the name plates stand clear of it)
	end
	for i, axe in ipairs(axes) do
		local x = (i - (#axes + 1) / 2) * pitch
		local stepY = RACK_BASE + (i - 1) * RACK_STEP -- the top of this axe's step
		local accent = BoxLook.Accent("Axe", axe.id)
		local art = AxeArt.Build(axe)
		local handle = art.PrimaryPart
		local len = if handle then handle.Size.Y else 3.3
		-- The backing block: a solid panel in the tier colour behind the axe
		-- and its plate, standing a hair off the rack.
		local blockLo = stepY - 1.7
		local blockH = len + 1.9
		local block = dBox(
			model,
			"AxeBlock",
			V3(RACK_BLOCK, blockH, 0.2),
			CF(x, blockLo + blockH / 2, wallZ - 0.45),
			accent,
			MAT.SmoothPlastic
		)
		-- The step the axe stands on: a ledge out of the block, darker.
		dBox(
			model,
			"AxeStep",
			V3(RACK_BLOCK, 0.3, 1.5),
			CF(x, stepY - 0.15, wallZ - 1.3),
			Kit.shade(accent, -0.45),
			MAT.SmoothPlastic
		)
		-- Foot on the step, head up, blade toward -X so the side shows.
		art:PivotTo(CF(x + RACK_AXE_SHIFT, stepY + len / 2, wallZ - 1.3) * CFrame.Angles(0, math.pi / 2, 0))
		art.Name = "RackAxe"
		art:SetAttribute("ItemId", axe.id)
		-- Two parts each (haft + the blade, the piece furthest to -X). A full
		-- AxeArt model is ~20 parts and eight of them do not fit a 250-part shop.
		local pivot = art:GetPivot()
		local primary = art.PrimaryPart
		local blade: BasePart? = nil
		local bladeX = math.huge
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("BasePart") and d ~= primary then
				local xObj = pivot:PointToObjectSpace(d.CFrame.Position).X
				if xObj < bladeX then
					bladeX = xObj
					blade = d
				end
			end
		end
		local keep: { [Instance]: boolean } = {}
		if primary then
			keep[primary] = true
		end
		if blade then
			keep[blade] = true
		end
		local drop: { Instance } = {}
		for _, d in ipairs(art:GetDescendants()) do
			if
				(d:IsA("BasePart") and not keep[d])
				or d:IsA("JointInstance")
				or d:IsA("Light")
				or d:IsA("ParticleEmitter")
				or d:IsA("Fire")
				or d:IsA("Smoke")
			then
				table.insert(drop, d)
			end
		end
		for _, d in ipairs(drop) do
			d:Destroy()
		end
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("BasePart") then
				Kit.decor(d, false)
			end
		end
		art.Parent = model
		local plate = dBox(
			model,
			"AxePlate",
			V3(RACK_PLATE, 1.0, 0.15),
			CF(x, stepY - 1.1, wallZ - 0.62),
			PAPER,
			MAT.SmoothPlastic
		)
		Kit.signText(plate, axe.displayName, TIMBER, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		-- The axe, its block and its plate tag as one item: the tag sits over the axe.
		local hover: HoverTag.Spec = {
			key = "Rack:" .. axe.id,
			name = axe.displayName,
			kind = "Axe",
			itemId = axe.id,
			shop = "ToolShed",
		}
		HoverTag.Mark(plate, hover)
		HoverTag.Mark(block, hover)
		hover.anchor = true
		HoverTag.Mark(art, hover)
	end
end

-- What the signs say: one header over each unit (every slot of the shop stands on one of the two tables' lanes, so
-- every item is under exactly one header; a spec checks it). The small category signs the first pass hung under the
-- headers are gone (too many signs, too close): each box carries its own name card and each table a price card per
-- spot, so the categories added nothing a player needs. The headers are 8.6 wide and stand toward the aisle (the
-- lanes are 12.1 wide), so from the door and from a phone the whole word is on screen, not cut by the door frame.
ToolShed.Sections = {
	{
		lane = "AxeTable",
		header = "AXES & BELTS",
		accent = BoxLook.Categories.Axe,
		subs = {},
		headerW = 8.6,
		headerCx = -9.4,
	},
	{
		lane = "MachineTable",
		header = "MACHINES",
		accent = BoxLook.Categories.Sawmill,
		subs = {},
		headerW = 8.6,
		headerCx = 9.4,
	},
} :: { ShopKit.Section }

-- A barrel in the stock corner: the real mesh (Barrel), with a part-built stand-in that is dropped when the mesh has
-- loaded (ShopKit.MeshProp: fallback first, swap later, never a yielding load).
local function stockBarrel(model: Model, x: number, y: number, z: number, yaw: number)
	local fallback = Instance.new("Model")
	fallback.Name = "BarrelFallback"
	local at = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
	dBox(fallback, "Barrel", V3(1.6, 2.2, 1.6), at * CF(0, 1.1, 0), TABLE)
	dBox(fallback, "BarrelHoop", V3(1.7, 0.16, 1.7), at * CF(0, 1.1, 0), ShopKit.Table.iron)
	fallback.Parent = model
	ShopKit.MeshProp(model, "Barrel", at, fallback)
end

-- A small stock crate, part-built only: the Crate mesh is 2.4 x 2.45 and does not fit the lane the stock stands in.
local function stockCrate(model: Model, x: number, y: number, z: number, side: number, yaw: number)
	local at = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
	dBox(model, "Crate", V3(side, side, side), at * CF(0, side / 2, 0), TABLE_TOP)
	dBox(model, "CrateBand", V3(side + 0.06, 0.16, side + 0.06), at * CF(0, side / 2, 0), TIMBER)
end

-- The side walls' inner face stands this far past frame.halfW (the shell's 0.9 walls are built 0.6 apart from it).
local WALL_IN = 0.15
local BLUEPRINT = hex("#9CC3D8")
local GRAIN = hex("#B88A4E")
local CAN = { hex("#B5472F"), hex("#4E7A3E"), hex("#D9A441"), hex("#3E5F7A") }

-- A framed picture flat on a side wall (`side` -1 west, +1 east; `wallX` its inner face): a wood frame and a canvas
-- just proud of it, facing the room. Looks only.
local function sidePicture(
	model: Model,
	wallX: number,
	side: number,
	z: number,
	y: number,
	w: number,
	h: number,
	canvas: Color3
)
	dBox(model, "ShedPictureFrame", V3(0.2, h, w), CF(wallX - side * 0.1, y, z), TABLE)
	dBox(model, "ShedPictureArt", V3(0.1, h - 0.5, w - 0.5), CF(wallX - side * 0.22, y, z), canvas, MAT.SmoothPlastic)
end

-- A shelf on a side wall, over the tables' boxes: a plank board on two brackets with a tool box, a can and a crate on
-- it. z0..z1 is its length along the wall. Looks only.
local function wallShelf(model: Model, wallX: number, side: number, z0: number, z1: number, y: number, seed: number)
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	local boardX = wallX - side * 0.6
	dBox(model, "ShedShelfBoard", V3(1.2, 0.25, len), CF(boardX, y, cz), TABLE_TOP)
	for _, z in ipairs({ z0 + 0.8, z1 - 0.8 }) do
		dBox(model, "ShedShelfBracket", V3(1.0, 0.45, 0.25), CF(wallX - side * 0.5, y - 0.35, z), TIMBER)
	end
	local top = y + 0.125
	local function put(name: string, size: Vector3, dz: number, color: Color3, mat: Enum.Material?)
		dBox(model, name, size, CF(boardX, top + size.Y / 2, cz + dz), color, mat or MAT.Metal)
	end
	put("ShedToolBox", V3(0.9, 0.75, 1.9), -len * 0.3, hex("#B5472F"))
	put("ShedCan", V3(0.6, 1.2, 0.6), 0, CAN[1 + seed % 4])
	put("ShedCrate", V3(0.95, 0.8, 1.3), len * 0.3, GRAIN, MAT.Wood)
end

-- A pegboard on the front wall's inside, beside the door (`cx` its middle x): a panel with a saw, a hammer and a
-- wrench hung on it. Looks only.
local function pegboard(model: Model, frame: Frame, cx: number, y: number)
	local z = -frame.halfD + 0.1 -- (the panel stands on the wall's inner face, toward the room: +z)
	local zt = z + 0.18 -- the tools stand proud of the panel
	dBox(model, "PegPanel", V3(6.8, 3.4, 0.2), CF(cx, y, z), TABLE)
	dBox(model, "PegSawBlade", V3(2.3, 0.6, 0.1), CF(cx - 1.7, y + 0.5, zt), hex("#A9B0B6"), MAT.Metal)
	dBox(model, "PegSawGrip", V3(0.55, 0.95, 0.16), CF(cx - 3.0, y + 0.5, zt), TIMBER)
	dBox(model, "PegHammerHandle", V3(0.22, 1.7, 0.12), CF(cx + 0.4, y - 0.1, zt), TABLE_TOP)
	dBox(model, "PegHammerHead", V3(1.0, 0.42, 0.2), CF(cx + 0.4, y + 0.9, zt + 0.03), hex("#5C5650"), MAT.Metal)
	dBox(model, "PegWrench", V3(0.3, 2.0, 0.1), CF(cx + 2.1, y - 0.1, zt), hex("#A9B0B6"), MAT.Metal)
end

-- Where the cross beams are (z, in the final studs the frame is in): each one carries a spot over the middle of both
-- tables, and the aisle lanterns hang from three of them. Clear of the headers (z -8) and of the shell's own tie beam
-- (z 5.4), and each stands over a row (or two) of boxes in each unit.
ToolShed.BeamZs = { -19.6, -13.6, -4.8, 2.4, 8.8, 14.6 }
ToolShed.SpotRise = 1.1 -- a spot's shade is this far under the ceiling line: its top rests on the beam's underside

-- A warm spot over the middle of each table at every beam.
function ToolShed.SpotLamps(model: Model, frame: Frame)
	for _, lane in ipairs(StoreStock.Lanes("ToolShed")) do
		local x = (lane.x0 + lane.x1) / 2
		for _, z in ipairs(ToolShed.BeamZs) do
			ShopKit.SpotLamp(model, x, frame.ceilY - ToolShed.SpotRise, z, frame.ceilY - 0.9)
		end
	end
end

-- The room's furnishings beyond the stock: shelves and framed pictures on the side walls over the tables, pegboards
-- with tools beside the door, a rug and plants by the counter, and a plant by the door. All looks only, all inside the
-- walls, none in the doorway aisle or on a table.
function ToolShed.Dressing(model: Model, frame: Frame)
	local fy = frame.floorTop
	local wallX = frame.halfW + WALL_IN
	local seed = 0
	for _, side in ipairs({ -1, 1 }) do
		for _, run in ipairs({ { -17.5, -8.5 }, { 0.5, 9.5 } }) do
			seed += 1
			wallShelf(model, side * wallX, side, run[1], run[2], 9.2, seed)
		end
		sidePicture(model, side * wallX, side, -4.0, 11.8, 3.4, 2.4, if side < 0 then BLUEPRINT else hex("#E0B77A"))
		sidePicture(
			model,
			side * wallX,
			side,
			12.0,
			11.8,
			2.6,
			2.6,
			if side < 0 then hex("#C98B7B") else hex("#8DB08A")
		)
		pegboard(model, frame, side * 12.4, 9.4)
	end
	-- a rug before the counter and plants at its sides
	dBox(model, "ShedRug", V3(7.6, 0.06, 3.0), CF(0, fy + ShopKit.Layer[2], 9.6), hex("#3E5F7A"), MAT.Fabric)
	dBox(model, "ShedRugEdge", V3(6.6, 0.07, 2.0), CF(0, fy + ShopKit.Layer[3], 9.6), hex("#D9C28A"), MAT.Fabric)
	ShopKit.plant(model, -4.1, fy, 9.6, 0.8)
	ShopKit.plant(model, 4.1, fy, 9.6, 0.8)
	ShopKit.plant(model, 3.9, fy, -19.6, 0.9)
end

function ToolShed.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2604)
	local ceil = frame.ceilY
	-- The display tables: a wood-top DisplayTable per row of boxes, a price card per box (and a lock card for a gated
	-- axe), no tier flags or plinths.
	ShopKit.SteppedUnit(model, "ToolShed", frame, "DisplayTable", TABLE, TABLE_TOP, "table")
	RobuxTableArt.Build(model, frame.floorTop) -- Lane P (unchanged)
	axeRack(model, frame)
	counterDetail(model, frame)
	-- (the counter's top overhangs its body by 0.2 each side, into the tables' ends at x +-5: trimmed to the body's width)
	local counterTop = model:FindFirstChild("CounterTop")
	if counterTop and counterTop:IsA("BasePart") then
		counterTop.Size = V3(10.0, counterTop.Size.Y, counterTop.Size.Z)
	end

	-- (the back-room door stands on the west wall behind the gold table's west end, where it stood before the nine-box
	-- table: the event room takes the east back corner)
	backDoor(model, frame, -frame.halfW, 19, false, -1)

	-- Floor: warm boards with darker planks, a border, and the aisle runner.
	plankFloor(model, frame, hex("#B07F4F"), { hex("#94683F"), hex("#C69660"), hex("#85603C") }, 2.6, rng)
	floorBorder(model, frame, 0.7, hex("#5A3E26"), MAT.Wood)
	runner(model, frame, 2.6, -frame.halfD + 1.4, 8)

	-- Warm timber beams: each carries a spot over both tables and, over the aisle, a lantern.
	-- (the beams run into the walls: the shell's walls are 0.15 thicker inside than the frame says)
	for _, z in ipairs(ToolShed.BeamZs) do
		dBox(model, "CeilingBeam", V3(2 * (frame.halfW + WALL_IN) + 0.1, 0.9, 0.9), CF(0, ceil - 0.45, z), TIMBER)
	end
	ShopKit.Rafter(model, frame, 0)
	ToolShed.SpotLamps(model, frame)
	-- (staggered either side of the middle so, from the door, they do not stack in one line on the screen)
	for _, at in ipairs({ { 1.8, -13.6 }, { -2.6, 2.4 }, { 3.9, 8.8 } }) do
		ShopKit.WarmLamp(model, at[1], ceil - 3.4, at[2], ceil - 0.9)
	end

	-- Signs: a header over each table, and CHECKOUT on the counter.
	dBox(
		model,
		"CeilingBeam",
		V3(2 * (frame.halfW + WALL_IN) + 0.1, 0.9, 0.9),
		CF(0, ceil - 0.45, ToolShed.HeaderBeamZ),
		TIMBER
	)
	ShopKit.SectionSigns(model, "ToolShed", ToolShed.Sections, {
		headerY = ToolShed.HeaderY,
		headerZ = ToolShed.HeaderBeamZ,
		tieY = ToolShed.TieY,
		noTie = true,
	})
	-- (the back wall is the axe rack, so the board hangs from the last beam, at the counter's back edge, over the keeper)
	ShopKit.CheckoutSign(model, frame, {
		plaque = false,
		onCounter = true,
		w = 5.4,
		h = 1.5,
		z = ToolShed.BeamZs[#ToolShed.BeamZs] + 0.3,
		ceilY = ceil - 0.9,
	})

	local fy = frame.floorTop
	ToolShed.Dressing(model, frame)

	-- The stock corner stands in the keeper's lane behind the counter (the gold table took the old corner by the west
	-- wall): z 15.0 to 16.7 is clear between the counter's back face and the gold table's sign, x 2.1 to 5.2 east and
	-- -5.2 to -2.1 west of the keeper's mat. A barrel and a small crate each side; the player cannot walk there.
	for _, side in ipairs({ -1, 1 }) do
		stockBarrel(model, side * 3.0, fy, 15.85, 0)
		stockCrate(model, side * 4.55, fy, 15.85, 1.2, 0)
	end

	-- The event expansion room (EVENTS.md, ShopEventKit). The tables fill both sides of the shop, so there is no 14 x 8
	-- clear floor: the roped zone takes the back east corner (the machine table ends at z 12.5, the counter at x 5, the
	-- gold table at x 4.8, the wall at x 17.4) at 11.9 x 8.6 (ShopEventKit.BuildZone's optional minSize), its open front
	-- toward the aisle; and the blank banner stands at the aisle's west edge just inside the door, facing it, clear of
	-- the table (x -5) and the runner's lanterns.
	ShopEventKit.BuildZone(model, "ToolShed", CF(11.3, fy, 17.4), V3(11.9, 0, 8.6), V3(11, 0, 8))
	ShopEventKit.BuildBanner(model, "ToolShed", CF(-3.25, fy, -18), 3.0)
end

return ToolShed
