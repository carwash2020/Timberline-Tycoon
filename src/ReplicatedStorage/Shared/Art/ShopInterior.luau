--!strict
-- ShopInterior: what goes inside a shop once BuildingArt has built and
-- scaled it: the tables and shelf units the boxes stand on, the aisle
-- signs, the ceiling beams, the lamps, a wood floor and an aisle runner.
-- Pure art code (Kit, Instance.new, datatypes). Everything is in FINAL
-- studs from the shop's origin (ground y = 0, the door on -Z), so a table
-- is exactly as big as StoreStock's lane for it and a box on it never
-- overhangs; nothing here is scaled again.
--
-- Only tables, shelf units and the counter collide (a player walks between
-- them); signs, beams, lamps and floor trim are looks only (Kit.decor).

local Kit = require(script.Parent.Kit)
local AxeArt = require(script.Parent.AxeArt)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local RobuxShelf = require(script.Parent.Parent.RobuxShelf)
local ShelfLayout = require(script.Parent.Parent.ShelfLayout)
local ShowroomLight = require(script.Parent.Parent.ShowroomLight)
local StoreStock = require(script.Parent.Parent.StoreStock)
local Util = require(script.Parent.Parent.Util)

local ShopInterior = {}

export type Frame = {
	floorTop: number, -- y of the floor surface
	halfW: number, -- inner half width (x)
	halfD: number, -- inner half depth (z)
	ceilY: number, -- y of the underside of the ceiling beams' level
}

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex

local TABLE = hex("#8C6239")
local TABLE_TOP = hex("#C69C6D")
local TIMBER = hex("#5A3E26")
local IRON = hex("#3B3634")
local PAPER = hex("#F4ECD8")
local GOLD = hex("#E3B73C")
local GOLD_INK = hex("#6B4A12")
local TRIM = hex("#F2E7CF")
local RUNNER = hex("#9A3D2E")
local RUNNER_EDGE = hex("#E3C98A")

local function decor(p: Part): Part
	Kit.decor(p, if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 3 then false else nil)
	return p
end

local function dBox(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return decor(Kit.part(parent, name, size, cf, color, mat or MAT.Wood))
end

-- The floor rectangle a lane's boxes actually cover, grown a little.
function ShopInterior.LaneRect(lane: ShelfLayout.Lane, spots: { ShelfLayout.Spot }): (number?, number?)
	local lo, hi = math.huge, -math.huge
	for _, spot in ipairs(spots) do
		if spot.lane == lane.name then
			lo = math.min(lo, spot.z - spot.d / 2)
			hi = math.max(hi, spot.z + spot.d / 2)
		end
	end
	if lo > hi then
		return nil
	end
	return math.max(lane.z0, lo - 0.8), math.min(lane.z1, hi + 0.8)
end

-- The spots of a shop as ShelfLayout.Spot (for the table extents).
local function spotsOf(kind: string): { ShelfLayout.Spot }
	local out: { ShelfLayout.Spot } = {}
	local lanes = StoreStock.Lanes(kind)
	for _, place in ipairs(StoreStock.Placements(kind)) do
		local laneName = ""
		for _, lane in ipairs(lanes) do
			if place.x >= lane.x0 and place.x <= lane.x1 and place.z >= lane.z0 and place.z <= lane.z1 then
				laneName = lane.name
				break
			end
		end
		local depth = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
		table.insert(out, {
			id = place.slotId,
			lane = laneName,
			x = place.x,
			y = place.y,
			z = place.z,
			w = place.size.X,
			h = place.size.Y,
			d = depth,
		})
	end
	return out
end

-- A table: legs and apron (a body, solid), a top board that overhangs a
-- little, and a trim along its front edge. `topY` is the surface.
local function furniture(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	floorTop: number,
	topY: number,
	body: Color3,
	top: Color3
)
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local bodyH = topY - floorTop - 0.3
	Kit.part(parent, name, V3(w - 0.4, bodyH, d - 0.4), CF(cx, floorTop + bodyH / 2, cz), body, MAT.WoodPlanks)
	local board = Kit.part(parent, name .. "Top", V3(w, 0.3, d), CF(cx, topY - 0.15, cz), top, MAT.Wood)
	board.CanQuery = false
	dBox(parent, name .. "Trim", V3(w + 0.1, 0.5, 0.18), CF(cx, topY - 0.5, z0 - 0.04), TIMBER)
end

-- A board hung on two chains from the ceiling, facing -Z, with `text` on
-- both faces so it reads walking in and walking out.
local function hangSign(
	parent: Instance,
	cx: number,
	cy: number,
	z: number,
	w: number,
	h: number,
	ceilY: number,
	text: string,
	board: Color3,
	ink: Color3
)
	local b = dBox(parent, "AisleSign", V3(w, h, 0.3), CF(cx, cy, z), board)
	Kit.signText(b, text, ink)
	dBox(parent, "AisleSignFrame", V3(w + 0.4, 0.22, 0.42), CF(cx, cy + h / 2 + 0.1, z), TIMBER)
	dBox(parent, "AisleSignFrame", V3(w + 0.4, 0.22, 0.42), CF(cx, cy - h / 2 - 0.1, z), TIMBER)
	for _, s in ipairs({ -1, 1 }) do
		local top = cy + h / 2 + 0.2
		dBox(
			parent,
			"AisleSignChain",
			V3(0.1, ceilY - top, 0.1),
			CF(cx + s * (w / 2 - 0.4), (ceilY + top) / 2, z),
			IRON,
			MAT.Metal
		)
	end
end

local function beam(parent: Instance, y: number, z: number, width: number)
	dBox(parent, "CeilingBeam", V3(width, 0.9, 0.9), CF(0, y, z), TIMBER)
end

local function lamp(parent: Instance, x: number, y: number, z: number, ceilY: number)
	local len = ceilY - y - 0.6
	dBox(parent, "LampChain", V3(0.1, len, 0.1), CF(x, ceilY - len / 2, z), IRON, MAT.Metal)
	Kit.lantern(parent, CF(x, y, z), 1.1)
end

---------------------------------------------------------------------------
-- Floors, trim and small furnishings (all looks only, final studs)
---------------------------------------------------------------------------

-- Floor layers, all above the building's own floor (frame.floorTop), none
-- coplanar with another: the base boards (0 to 0.06), then stripes, border
-- and runner (0.06 to 0.12), then the runner's edge stripes (0.12 to 0.19).
local LAYER1, LAYER2, LAYER3 = 0.03, 0.09, 0.155

-- Warm floorboards: a base of WoodPlanks and a few long boards in two other
-- tones (alternate stripes), so the floor reads as boards laid side by side.
local function plankFloor(parent: Instance, frame: Frame, base: Color3, tones: { Color3 }, boardW: number, rng: Kit.Rng)
	local w, d = 2 * frame.halfW - 0.4, 2 * frame.halfD - 0.4
	dBox(parent, "FloorBoards", V3(w, 0.06, d), CF(0, frame.floorTop + LAYER1, 0), base, MAT.WoodPlanks)
	local n = math.floor(w / boardW)
	local x0 = -n * boardW / 2 + boardW / 2
	for i = 0, n - 1 do
		if i % 3 == 1 then
			-- a long board in a darker or lighter tone, with a gap each side
			local tone = Kit.vary(tones[(i % #tones) + 1], rng, 0.03)
			dBox(
				parent,
				"FloorPlank",
				V3(boardW - 0.12, 0.05, d - 0.2),
				CF(x0 + i * boardW, frame.floorTop + LAYER2 - 0.005, 0),
				tone,
				MAT.WoodPlanks
			)
		end
	end
end

-- A border of trim round the walls, `width` studs wide.
local function floorBorder(parent: Instance, frame: Frame, width: number, color: Color3, mat: Enum.Material)
	local w, d = 2 * frame.halfW - 0.4, 2 * frame.halfD - 0.4
	local y = frame.floorTop + LAYER2
	for _, s in ipairs({ -1, 1 }) do
		dBox(parent, "FloorBorder", V3(w, 0.06, width), CF(0, y, s * (d / 2 - width / 2)), color, mat)
		dBox(parent, "FloorBorder", V3(width, 0.06, d - 2 * width), CF(s * (w / 2 - width / 2), y, 0), color, mat)
	end
end

-- A runner down the middle aisle, with an edge stripe each side.
local function runner(parent: Instance, frame: Frame, halfWidth: number, z0: number, z1: number)
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	dBox(parent, "AisleRunner", V3(2 * halfWidth, 0.06, len), CF(0, frame.floorTop + LAYER2, cz), RUNNER, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			parent,
			"AisleRunnerEdge",
			V3(0.35, 0.07, len),
			CF(s * (halfWidth - 0.3), frame.floorTop + LAYER3, cz),
			RUNNER_EDGE,
			MAT.Fabric
		)
	end
end

local LEAF = hex("#4E7A3E")
local LEAF2 = hex("#6E9B4A")
local POT = hex("#A8553A")

local function plant(parent: Instance, x: number, y: number, z: number, scale: number)
	dBox(parent, "PlantPot", V3(0.9, 0.9, 0.9) * scale, CF(x, y + 0.45 * scale, z), POT, MAT.Slate)
	Kit.decor(Kit.ball(parent, "PlantLeaves", 1.6 * scale, CF(x, y + 1.5 * scale, z), LEAF, MAT.Grass), false)
	Kit.decor(
		Kit.ball(parent, "PlantLeaves", 1.0 * scale, CF(x + 0.3 * scale, y + 2.2 * scale, z), LEAF2, MAT.Grass),
		false
	)
end

local function stool(parent: Instance, x: number, y: number, z: number)
	Kit.decor(Kit.post(parent, "StoolSeat", V3(x, y + 1.5, z), 0.3, 1.5, TABLE_TOP, MAT.Wood), false)
	for _, d in ipairs({ { -0.45, -0.45 }, { 0.45, -0.45 }, { -0.45, 0.45 }, { 0.45, 0.45 } }) do
		dBox(parent, "StoolLeg", V3(0.18, 1.5, 0.18), CF(x + d[1], y + 0.75, z + d[2]), TIMBER)
	end
end

local function crateStack(parent: Instance, x: number, y: number, z: number, n: number, rng: Kit.Rng)
	for i = 1, n do
		local c = Kit.vary(TABLE_TOP, rng, 0.05)
		local dx = (i == 3) and 0.25 or 0
		dBox(
			parent,
			"Crate",
			V3(1.8, 1.5, 1.8),
			CF(x + dx, y + 0.75 + (if i == 3 then 1.5 else 0), z + (i - 1) % 2 * 1.95),
			c,
			MAT.Wood
		)
		dBox(
			parent,
			"CrateBand",
			V3(1.86, 0.18, 1.86),
			CF(x + dx, y + 0.75 + (if i == 3 then 1.5 else 0), z + (i - 1) % 2 * 1.95),
			TIMBER,
			MAT.Wood
		)
	end
end

local function trashCan(parent: Instance, x: number, y: number, z: number)
	Kit.decor(Kit.post(parent, "TrashCan", V3(x, y, z), 1.9, 1.3, IRON, MAT.Metal), false)
	Kit.decor(Kit.post(parent, "TrashLid", V3(x, y + 1.9, z), 0.15, 1.5, TIMBER, MAT.Metal), false)
end

-- A row of three coat hooks on a board on the wall. `facing` is +1 for a wall at +X
-- (the hooks stand out toward -X), -1 for -X, 0 for the back wall (+Z), whose hooks
-- stand out toward -Z.
local function wallBoard(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	w: number,
	h: number,
	onZ: boolean,
	color: Color3
)
	local size = if onZ then V3(w, h, 0.2) else V3(0.2, h, w)
	return dBox(parent, name, size, CF(cx, cy, cz), color, MAT.Wood)
end

-- A paper poster or notice (looks only), text on the face toward the room.
local function poster(
	parent: Instance,
	cx: number,
	cy: number,
	cz: number,
	w: number,
	h: number,
	onZ: boolean,
	text: string,
	face: Enum.NormalId,
	color: Color3
)
	local p = wallBoard(parent, "Poster", cx, cy, cz, w, h, onZ, color)
	Kit.signText(p, text, TIMBER, { face }, Enum.Font.FredokaOne, 0.2)
	return p
end

-- Rope coils and a lantern or two hung from a beam (hanging goods).
local function hangGoods(parent: Instance, x: number, z: number, y: number, kind: number)
	dBox(parent, "GoodsChain", V3(0.08, 1.4, 0.08), CF(x, y + 0.7, z), IRON, MAT.Metal)
	if kind == 1 then
		Kit.decor(
			Kit.cylinder(
				parent,
				"RopeCoil",
				0.5,
				1.5,
				CF(x, y - 0.2, z) * CFrame.Angles(0, 0, math.pi / 2),
				hex("#C9B27A"),
				MAT.Fabric
			),
			false
		)
	elseif kind == 2 then
		Kit.lantern(parent, CF(x, y - 0.3, z), 0.8)
	else
		dBox(parent, "HangTool", V3(0.2, 1.6, 0.2), CF(x, y - 0.4, z), TIMBER)
		dBox(parent, "HangToolHead", V3(0.9, 0.5, 0.25), CF(x + 0.3, y - 1.0, z), hex("#A7ADB4"), MAT.Metal)
	end
end

-- A price tag on the aisle face of a lane's table or shelf, under each box.
local function priceTags(parent: Instance, kind: string)
	for _, place in ipairs(StoreStock.Placements(kind)) do
		local slot = StoreStock.Get(place.slotId)
		if slot then
			local price = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)
			local text = if price and price > 0 then Util.formatCash(price) else "FREE"
			local lane: ShelfLayout.Lane? = nil
			for _, l in ipairs(StoreStock.Lanes(kind)) do
				if place.x >= l.x0 and place.x <= l.x1 and place.z >= l.z0 and place.z <= l.z1 then
					lane = l
				end
			end
			if lane then
				local westLane = (lane.x0 + lane.x1) / 2 < 0
				local edgeX = if westLane then lane.x1 else lane.x0
				-- Only the lanes with an aisle face (the middle islands and the side tables).
				local sign = if westLane then 1 else -1
				local tag = dBox(
					parent,
					"PriceTag",
					V3(math.min(2.4, place.size.X), 0.8, 0.08),
					CF(edgeX + sign * 0.06, lane.y - 0.75, place.z) * CFrame.Angles(0, -sign * math.pi / 2, 0),
					PAPER,
					MAT.SmoothPlastic
				)
				Kit.signText(tag, text, TIMBER, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
			end
		end
	end
end

local function laneFurniture(parent: Instance, kind: string, frame: Frame, name: string, body: Color3, top: Color3)
	local spots = spotsOf(kind)
	for _, lane in ipairs(StoreStock.Lanes(kind)) do
		local lo, hi = ShopInterior.LaneRect(lane, spots)
		if lo and hi then
			furniture(parent, name, lane.x0, lane.x1, lo, hi, frame.floorTop, lane.y, body, top)
		end
	end
end

---------------------------------------------------------------------------
-- The Tool Shed
---------------------------------------------------------------------------

-- The cash desk's furnishings: a brass bell, a balance scale, a receipt spike
-- and two jars on the counter top, and a stool behind it for the keeper. Read
-- from the real Counter part (it may be anywhere in the shop). Looks only.
local function counterDetail(model: Model, frame: Frame)
	local counter = model:FindFirstChild("Counter")
	if not counter or not counter:IsA("BasePart") then
		return
	end
	local c = counter.CFrame.Position
	local top = c.Y + counter.Size.Y / 2 + 0.3 -- over the counter-top board
	local brass = hex("#C9A24A")
	-- A bell: a base and a dome.
	Kit.decor(Kit.post(model, "CounterBellBase", V3(c.X - 0.5, top, c.Z - 0.55), 0.12, 0.9, brass, MAT.Metal), false)
	Kit.decor(Kit.ball(model, "CounterBell", 0.7, CF(c.X - 0.5, top + 0.3, c.Z - 0.55), brass, MAT.Metal), false)
	-- A balance scale: base, post, beam, two pans.
	local sx = c.X - 3.5
	dBox(model, "ScaleBase", V3(1.3, 0.18, 0.8), CF(sx, top + 0.09, c.Z + 0.1), IRON, MAT.Metal)
	dBox(model, "ScalePost", V3(0.12, 1.5, 0.12), CF(sx, top + 0.9, c.Z + 0.1), IRON, MAT.Metal)
	dBox(model, "ScaleBeam", V3(1.9, 0.1, 0.1), CF(sx, top + 1.6, c.Z + 0.1), brass, MAT.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.post(model, "ScalePan", V3(sx + s * 0.85, top + 1.0, c.Z + 0.1), 0.1, 0.8, brass, MAT.Metal),
			false
		)
	end
	-- A receipt spike and two jars.
	dBox(model, "ReceiptSpike", V3(0.07, 0.9, 0.07), CF(c.X + 1.4, top + 0.55, c.Z - 0.5), IRON, MAT.Metal)
	dBox(model, "ReceiptBase", V3(0.5, 0.1, 0.5), CF(c.X + 1.4, top + 0.05, c.Z - 0.5), TIMBER)
	for i = 1, 2 do
		local jz = c.Z - 0.6 + (i - 1) * 1.1
		local jar = Kit.post(model, "CounterJar", V3(c.X + 3.2, top, jz), 1.2, 0.9, hex("#BFD9E6"), MAT.Glass)
		jar.Transparency = 0.4
		Kit.decor(jar, false)
		local lid = if i == 1 then hex("#C8402F") else TIMBER
		Kit.decor(Kit.post(model, "JarLid", V3(c.X + 3.2, top + 1.2, jz), 0.15, 0.95, lid, MAT.Metal), false)
	end
	-- The keeper's stool, behind the counter.
	stool(model, c.X + 3.4, frame.floorTop, c.Z + counter.Size.Z / 2 + 1.7)
end

-- A door to the back room on a wall (looks only; nothing opens): `onZ` for the
-- back wall (+Z, facing -Z), else a side wall at x with `side` +1 (east) or -1.
local function backDoor(model: Model, frame: Frame, x: number, z: number, onZ: boolean, side: number)
	local size = if onZ then V3(3.2, 8, 0.3) else V3(0.3, 8, 3.2)
	local at = CF(x, frame.floorTop + 4, z)
	dBox(model, "BackRoomDoor", size, at, hex("#6E4A2E"), MAT.Wood)
	local frameSize = if onZ then V3(4, 8.6, 0.2) else V3(0.2, 8.6, 4)
	dBox(
		model,
		"BackRoomDoorFrame",
		frameSize,
		at * CF(0, 0.3, 0) * CF(if onZ then 0 else -side * 0.05, 0, if onZ then -0.05 else 0),
		TRIM,
		MAT.Wood
	)
	local knob = if onZ then CF(1.2, -0.2, -0.25) else CF(-side * 0.25, -0.2, 1.2)
	Kit.decor(Kit.ball(model, "BackRoomKnob", 0.35, at * knob, hex("#C9A24A"), MAT.Metal), false)
end

-- The axe rack on the back wall: every axe the shop sells (ItemCatalog's
-- ladder, in order), each its real AxeArt model (the part-built or mesh art the
-- held tools use; AxeArt falls back to parts if a mesh fails), hung head up on a
-- plank rack, with a name and one price plate under it.
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
	local pitch = 3.1
	local width = #axes * pitch + 1.4
	local wallZ = frame.halfD
	local panelY = 9.4
	dBox(model, "AxeRack", V3(width, 6.6, 0.3), CF(0, panelY, wallZ - 0.2), TABLE)
	for _, y in ipairs({ panelY - 3.3, panelY + 3.3 }) do
		dBox(model, "AxeRackRail", V3(width + 0.3, 0.35, 0.5), CF(0, y, wallZ - 0.4), TIMBER)
	end
	for i, axe in ipairs(axes) do
		local x = (i - (#axes + 1) / 2) * pitch
		local art = AxeArt.Build(axe)
		local handle = art.PrimaryPart
		local len = if handle then handle.Size.Y else 3.3
		-- Foot on the lower hanger, head up, blade toward -X so the side shows.
		art:PivotTo(CF(x, 8.3 + len / 2, wallZ - 0.75) * CFrame.Angles(0, math.pi / 2, 0))
		art.Name = "RackAxe"
		art:SetAttribute("ItemId", axe.id)
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("BasePart") then
				Kit.decor(d, false)
			elseif d:IsA("Weld") or d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") then
				-- (A hanging axe is a display: no glow lights or sparks, which the
				-- client would pay for at every rack.)
				d:Destroy()
			end
		end
		art.Parent = model
		dBox(model, "AxePeg", V3(0.5, 0.3, 0.5), CF(x, 8.15, wallZ - 0.75), IRON, MAT.Metal)
		local price = StoreStock.UnitPrice("Axe", axe.id, false, 2)
		local plate = dBox(model, "AxePlate", V3(2.8, 1.5, 0.15), CF(x, 7.1, wallZ - 0.5), PAPER, MAT.SmoothPlastic)
		local label = axe.displayName .. "\n" .. (if price and price > 0 then Util.formatCash(price) else "FREE")
		Kit.signText(plate, label, TIMBER, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
	end
end

local function toolShed(model: Model, frame: Frame)
	local rng = Kit.rng(2604)
	laneFurniture(model, "ToolShed", frame, "DisplayTable", TABLE, TABLE_TOP)
	priceTags(model, "ToolShed")
	-- The Robux table: the same table as the cash shelves with a gold top, along
	-- the back wall behind the counter and its keeper. Its boxes are the gold
	-- boxes, one name label and one price tag each.
	local entries = RobuxShelf.List()
	if #entries > 0 then
		local width = RobuxShelf.RowWidth()
		local cz = RobuxShelf.TableZ
		local depth = RobuxShelf.TableDepth
		furniture(
			model,
			"GoldTable",
			-width / 2,
			width / 2,
			cz - depth / 2,
			cz + depth / 2,
			frame.floorTop,
			RobuxShelf.TableTop,
			TIMBER,
			GOLD
		)
		-- The gold shelf's name on a board across the table's front (a hanging
		-- sign here would hide the axes on the rack behind).
		local board = dBox(
			model,
			"RobuxSign",
			V3(math.max(8.4, width - 1), 1.1, 0.12),
			CF(0, RobuxShelf.TableTop - 0.9, cz - depth / 2 - 0.1),
			GOLD,
			MAT.SmoothPlastic
		)
		Kit.signText(board, "ROBUX SHELF", GOLD_INK, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
	end
	axeRack(model, frame)
	counterDetail(model, frame)
	backDoor(model, frame, frame.halfW - 0.3, 19, false, 1)

	-- Floor: warm boards with darker planks, a border, and the aisle runner.
	plankFloor(model, frame, hex("#B07F4F"), { hex("#94683F"), hex("#C69660"), hex("#85603C") }, 2.6, rng)
	floorBorder(model, frame, 0.7, hex("#5A3E26"), MAT.Wood)
	runner(model, frame, 2.6, -frame.halfD + 1.4, 11.2)
	local y = frame.ceilY
	for _, z in ipairs({ -17.5, -5.5, 6.5, 17 }) do
		beam(model, y - 0.45, z, 2 * frame.halfW - 0.6)
	end
	for _, z in ipairs({ -17.5, -5.5, 6.5 }) do
		for _, x in ipairs({ -9.6, 9.6 }) do
			lamp(model, x, y - 3.1, z, y - 0.9)
		end
	end
	lamp(model, 0, y - 3.1, 17, y - 0.9)
	hangSign(model, -9.6, y - 3.7, -19.7, 7.8, 1.6, y - 0.9, "AXES", hex("#8E3B2B"), PAPER)
	hangSign(model, 9.6, y - 3.7, -19.7, 7.8, 1.6, y - 0.9, "SAWMILLS & MACHINES", hex("#3E4A62"), PAPER)
	-- Hanging goods on the beams: rope coils, lanterns, a row of tools.
	for i, x in ipairs({ -3.4, 0, 3.4 }) do
		hangGoods(model, x, -5.5, y - 1.6, i)
		hangGoods(model, x + 1.2, 6.5, y - 1.6, (i % 3) + 1)
	end
	-- Walls: a pegboard of tools, a notice, a coat-hook board, a stool and
	-- stacked crates by the door, a plant, a bin.
	local hw = frame.halfW
	wallBoard(model, "Pegboard", -hw + 0.3, 7.4, -9, 7, 4, false, TABLE)
	for i = 1, 5 do
		hangGoods(model, -hw + 0.7, -9 + (i - 3) * 1.3, 8.8, i % 3 + 1)
	end
	poster(model, hw - 0.25, 7.6, -12, 4.2, 3, false, "BUY AN AXE\nCHOP A TREE", Enum.NormalId.Left, PAPER)
	wallBoard(model, "CoatHooks", hw - 0.25, 7, 9, 5, 0.5, false, TIMBER)
	crateStack(model, hw - 2, frame.floorTop, -20.4, 3, rng)
	plant(model, -hw + 1.2, frame.floorTop, -20.6, 1.1)
	trashCan(model, hw - 1, frame.floorTop, 10)
	stool(model, 7.2, frame.floorTop, 17.2)
end

---------------------------------------------------------------------------
-- Hearth & Home
---------------------------------------------------------------------------

local function hearth(model: Model, frame: Frame)
	local rng = Kit.rng(2605)
	local spots = spotsOf("HearthAndHome")
	for _, lane in ipairs(StoreStock.Lanes("HearthAndHome")) do
		local lo, hi = ShopInterior.LaneRect(lane, spots)
		if lo and hi then
			furniture(model, "Shelf", lane.x0, lane.x1, lo, hi, frame.floorTop, lane.y, TABLE, TABLE_TOP)
			if lane.name == "GearShelf" or lane.name == "LampShelf" then
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
	end
	priceTags(model, "HearthAndHome")
	counterDetail(model, frame)
	backDoor(model, frame, -frame.halfW + 0.3, 18.5, false, -1)
	plankFloor(model, frame, hex("#C8995F"), { hex("#B3874F"), hex("#D8AB72"), hex("#A57A47") }, 2.8, rng)
	floorBorder(model, frame, 0.8, hex("#4E7A3E"), MAT.Wood)
	runner(model, frame, 3.6, -frame.halfD + 1.6, 12)
	local y = frame.ceilY
	for _, z in ipairs({ -14.25, -5.25, 3.75, 12.5 }) do
		beam(model, y - 0.45, z, 2 * frame.halfW - 0.6)
	end
	for _, z in ipairs({ -14.25, 3.75 }) do
		for _, x in ipairs({ -19, -10, 10, 19 }) do
			lamp(model, x, y - 3.4, z, y - 0.9)
		end
	end
	lamp(model, 0, y - 3.4, 12.5, y - 0.9)
	hangSign(model, -20.6, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "GEAR", hex("#2E8B7A"), PAPER)
	hangSign(model, -10.2, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "PLANS", hex("#3B6FB6"), PAPER)
	hangSign(model, 10.2, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "BLUEPRINTS", hex("#3B6FB6"), PAPER)
	hangSign(model, 20.6, y - 3.4, -19.05, 6.4, 1.5, y - 0.9, "LAMPS", hex("#8E5BB5"), PAPER)
	-- Hanging goods, a rug at the entrance, plants, a stool for the keeper,
	-- a bin, coat hooks and notices.
	for i, x in ipairs({ -6, 0, 6 }) do
		hangGoods(model, x, -5.25, y - 1.6, i)
		hangGoods(model, x, 3.75, y - 1.6, (i % 3) + 1)
	end
	local hw = frame.halfW
	dBox(model, "Rug", V3(8, 0.06, 5), CF(0, frame.floorTop + LAYER3, -frame.halfD + 4.5), hex("#2F6B5C"), MAT.Fabric)
	plant(model, -6.2, frame.floorTop, -frame.halfD + 1.6, 1.3)
	plant(model, 6.2, frame.floorTop, -frame.halfD + 1.6, 1.3)
	plant(model, -hw + 1.2, frame.floorTop, 16, 1.2)
	stool(model, 5.4, frame.floorTop, 18.4)
	trashCan(model, hw - 1, frame.floorTop, 16.5)
	wallBoard(model, "CoatHooks", -hw + 0.25, 7.2, -17, 5, 0.5, false, TIMBER)
	poster(model, hw - 0.25, 7.6, -17, 4.2, 3, false, "SALE\nTODAY", Enum.NormalId.Left, PAPER)
	crateStack(model, hw - 2.2, frame.floorTop, -frame.halfD + 1.8, 3, rng)
end

---------------------------------------------------------------------------
-- The Dealership showroom
---------------------------------------------------------------------------

local function bayLight(parent: Instance, x: number, y: number, z: number)
	dBox(parent, "BayLightCan", V3(1.2, 0.9, 1.2), CF(x, y, z), IRON, MAT.Metal)
	local lens = dBox(parent, "BayLightLens", V3(0.9, 0.1, 0.9), CF(x, y - 0.5, z), hex("#E4D6BC"), MAT.SmoothPlastic)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = ShowroomLight.SpotRange
	spot.Brightness = ShowroomLight.SpotBrightness
	spot.Color = Color3.fromRGB(255, 240, 215)
	spot.Shadows = false
	spot.Parent = lens
	dBox(parent, "BayLightRod", V3(0.12, 14.8 - y, 0.12), CF(x, (14.8 + y) / 2, z), IRON, MAT.Metal)
end

local function banner(parent: Instance, x: number, y: number, z: number, color: Color3, text: string)
	dBox(parent, "BannerRod", V3(2.6, 0.18, 0.18), CF(x, y + 2.7, z), IRON, MAT.Metal)
	local b = dBox(parent, "Banner", V3(2.2, 4.8, 0.08), CF(x, y, z), color, MAT.Fabric)
	Kit.signText(b, text, PAPER, nil, Enum.Font.FredokaOne, 0.2)
end

-- `bays` are the vehicle bays in hall space (see BuildingArt.dealership):
-- x, z (the plinth's middle), row, zNear / zFar (the plinth's edge facing the
-- central aisle, and its far edge).
export type Bay = { x: number, z: number, row: number, aisleZ: number }

local function dealership(model: Model, frame: Frame, west: number, east: number, zf: number, zb: number, bays: { Bay })
	local rng = Kit.rng(2606)
	local width = east - west
	local cx = (east + west) / 2
	local depth = zb - zf
	local fy = frame.floorTop
	-- Polished marble floor with a slate border, a runner and safety stripes
	-- along the central aisle.
	dBox(
		model,
		"FloorBoards",
		V3(width - 0.4, 0.06, depth - 0.4),
		CF(cx, fy + LAYER1, (zf + zb) / 2),
		hex("#DCD6CB"),
		MAT.Marble
	)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"FloorBorder",
			V3(width - 0.4, 0.06, 1.0),
			CF(cx, fy + LAYER2, (zf + zb) / 2 + s * (depth / 2 - 0.7)),
			hex("#4B5560"),
			MAT.Slate
		)
		dBox(
			model,
			"FloorBorder",
			V3(1.0, 0.06, depth - 2.4),
			CF(cx + s * (width / 2 - 0.7), fy + LAYER2, (zf + zb) / 2),
			hex("#4B5560"),
			MAT.Slate
		)
	end
	local lobbyW = 26
	local lobbyCx = west + 12.6
	-- The central walkway between the rows: a pale lane edged with yellow
	-- stripes, with a few blue bars across it.
	local aisleLo, aisleHi = math.huge, -math.huge
	for _, bay in ipairs(bays) do
		if bay.row == 1 then
			aisleLo = math.min(aisleLo, bay.aisleZ)
		else
			aisleHi = math.max(aisleHi, bay.aisleZ)
		end
	end
	if aisleLo < aisleHi then
		local ax0, ax1 = west + lobbyW, east - 1.5
		local acx = (ax0 + ax1) / 2
		local acz = (aisleLo + aisleHi) / 2
		dBox(
			model,
			"AisleLane",
			V3(ax1 - ax0, 0.06, aisleHi - aisleLo - 1.6),
			CF(acx, fy + LAYER2, acz),
			hex("#C3BDB1"),
			MAT.Marble
		)
		for _, z in ipairs({ aisleLo + 0.5, aisleHi - 0.5 }) do
			dBox(
				model,
				"AisleStripe",
				V3(ax1 - ax0, 0.07, 0.4),
				CF(acx, fy + LAYER3, z),
				hex("#E3B73C"),
				MAT.SmoothPlastic
			)
		end
		local x = ax0 + 6
		while x < ax1 - 4 do
			dBox(
				model,
				"AisleMark",
				V3(0.5, 0.07, aisleHi - aisleLo - 3.2),
				CF(x, fy + LAYER3, acz),
				hex("#7FA3C8"),
				MAT.SmoothPlastic
			)
			x += 14
		end
	end
	-- A runner down the lobby from the door to the counter.
	dBox(model, "AisleRunner", V3(5, 0.06, depth - 8), CF(lobbyCx, fy + LAYER2, (zf + zb) / 2), RUNNER, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"AisleRunnerEdge",
			V3(0.35, 0.07, depth - 8),
			CF(lobbyCx + s * 2.2, fy + LAYER3, (zf + zb) / 2),
			RUNNER_EDGE,
			MAT.Fabric
		)
	end
	local ceil = frame.ceilY
	-- Beams across the hall with strip lights along them.
	for _, z in ipairs({ zf + 20, zf + 36, zf + 52 }) do
		dBox(model, "CeilingBeam", V3(width - 0.6, 0.9, 0.9), CF(cx, ceil - 0.45, z), TIMBER)
		local x = west + 12
		while x < east - 6 do
			local strip =
				dBox(model, "StripLight", V3(9, 0.2, 0.5), CF(x, ceil - 1.1, z), ShowroomLight.StripColor, MAT.Neon)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 236, 205)
			light.Range = ShowroomLight.StripRange
			light.Brightness = ShowroomLight.StripBrightness
			light.Shadows = false
			light.Parent = strip
			x += 28
		end
	end
	-- A spot over every bay.
	for _, bay in ipairs(bays) do
		bayLight(model, bay.x, ceil - 2.4, bay.z)
	end
	hangSign(model, lobbyCx, ceil - 3.6, zf + 5, 9, 1.7, ceil - 0.9, "SHOWROOM", hex("#2F6DB5"), PAPER)
	-- Lobby: banners, brochure racks, reception chairs and a low table, plants.
	banner(model, west + 3, ceil - 5, zf + 12, hex("#2F6DB5"), "NEW\nRIGS")
	banner(model, west + 23, ceil - 5, zf + 12, hex("#C8402F"), "SALE")
	banner(model, west + 3, ceil - 5, zf + 30, hex("#E3B73C"), "TRUCKS")
	for i, x in ipairs({ west + 1.5, west + 1.5 }) do
		dBox(model, "BrochureRack", V3(2.4, 4.2, 0.8), CF(x, fy + 2.1, zf + 22 + (i - 1) * 3.5), TABLE, MAT.Wood)
		for r = 1, 3 do
			dBox(
				model,
				"Brochure",
				V3(1.9, 0.9, 0.12),
				CF(x, fy + 0.9 + r * 0.95, zf + 21.55 + (i - 1) * 3.5),
				if (i + r) % 2 == 0 then PAPER else hex("#7FA3C8"),
				MAT.SmoothPlastic
			)
		end
	end
	-- Reception: chairs and a low table by the west wall.
	dBox(model, "ReceptionTable", V3(3.6, 1.2, 2), CF(west + 4, fy + 0.6, zb - 24), TABLE_TOP, MAT.Wood)
	for _, z in ipairs({ zb - 28, zb - 20 }) do
		dBox(model, "ReceptionChair", V3(2, 1.2, 2), CF(west + 4, fy + 0.6, z), hex("#2F6DB5"), MAT.Fabric)
		dBox(model, "ReceptionChairBack", V3(0.4, 1.8, 2), CF(west + 2.6, fy + 1.5, z), hex("#2F6DB5"), MAT.Fabric)
	end
	plant(model, west + 1.8, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zb - 12, 1.4)
	trashCan(model, west + lobbyW - 2, fy, zb - 1.5)
	-- Flags along the front wall, inside the hall.
	for i, x in ipairs({ west + 36, west + 66, west + 96, west + 126 }) do
		dBox(model, "FlagPole", V3(0.2, 5, 0.2), CF(x, fy + 2.5, zf + 0.6), IRON, MAT.Metal)
		dBox(
			model,
			"FlagCloth",
			V3(2.4, 1.5, 0.1),
			CF(x + 1.3, fy + 4.2, zf + 0.6),
			if i % 2 == 0 then hex("#2F6DB5") else hex("#C8402F"),
			MAT.Fabric
		)
	end
	crateStack(model, east - 4, fy, zb - 3, 3, rng)
	counterDetail(model, frame)
	backDoor(model, frame, west + 5.7, zb, true, 0)
end

-- Adds the interior. `frame` is the shop's final-stud frame (see Frame);
-- for the Dealership `extra` is the showroom's inner west x, east x, front
-- z and back z.
function ShopInterior.Add(model: Model, kind: string, frame: Frame, extra: { number }?, bays: { Bay }?)
	if kind == "ToolShed" then
		toolShed(model, frame)
	elseif kind == "HearthAndHome" then
		hearth(model, frame)
	elseif kind == "Dealership" then
		local span = extra or { -frame.halfW, frame.halfW, -frame.halfD, frame.halfD }
		dealership(model, frame, span[1], span[2], span[3], span[4], bays or {})
	end
end

return ShopInterior
