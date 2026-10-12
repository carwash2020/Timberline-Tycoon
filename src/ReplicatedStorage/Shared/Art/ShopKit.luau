--!strict
-- ShopKit: the one kit every store interior is built from, so all stores read
-- as one family (Timberline timber, brass and pine). Pure art code (Kit,
-- Instance.new, datatypes), everything in FINAL studs from the shop's origin
-- (ground y = 0, the door on -Z); nothing here is scaled again.
--
-- Only tables, shelf units and the counter collide (a player walks between
-- them); signs, beams, lamps, flags and floor trim are looks only (Kit.decor).
--
-- The kit, in one place:
--   ShopKit.HeaderSign / SubSign       big section sign, small category sign
--   ShopKit.SectionSigns               the signs of a store's own sections
--   ShopKit.TierStand                  a slot's stand: plinth in the tier colour,
--                                      a tier flag (T1..T9), a lock chip, hover tag
--   ShopKit.SteppedUnit                the display unit, a stand per placement (or, with
--                                      style "table", a DisplayTable per row and a SpotTag per item)
--   ShopKit.DisplayTable               a wood-top table with a trim edge, sized for 2 or 3 display spots
--   ShopKit.SpotTag                    a small price card on a table (and a lock card for a gated item)
--   ShopKit.SpotLamp                   a small warm spot hung over a table
--   ShopKit.HoverAnchor                an aim target that carries a hover tag
--   ShopKit.CheckoutSign               the counter's sign and the keeper's mat
--   ShopKit.WarmLamp / Light           a hanging lantern with a modest warm light
--   ShopKit.Beams / Rafter             the ceiling beam set
--   ShopKit.MeshProp                   a real mesh with a part-built fallback
--   ShopKit.CountParts / Budget        the part budget helper
-- plus the floor, runner, plant, crate and back-door helpers the older
-- interiors use. Colours: the Timberline palette (UITheme / Palette) and
-- StoreTier's tier ramp.

local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.Kit)
local BoxLook = require(script.Parent.Parent.BoxLook)
local GameConfig = require(script.Parent.Parent.GameConfig)
local HoverTag = require(script.Parent.Parent.HoverTag)
local MeshKit = require(script.Parent.MeshKit)
local ShelfLayout = require(script.Parent.Parent.ShelfLayout)
local StoreStock = require(script.Parent.Parent.StoreStock)
local StoreTier = require(script.Parent.Parent.StoreTier)
local TownMeshes = require(script.Parent.TownMeshes)
local TownModels = require(script.Parent.TownModels)
local Util = require(script.Parent.Parent.Util)

local ShopKit = {}

export type Frame = {
	floorTop: number, -- y of the floor surface
	halfW: number, -- inner half width (x)
	halfD: number, -- inner half depth (z)
	ceilY: number, -- y of the underside of the ceiling beams' level
}

ShopKit.Budget = 400 -- parts one store interior may use (ShopKit.CountParts)

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex

local TABLE = hex("#8C6239")
local TABLE_TOP = hex("#C69C6D")
local TIMBER = hex("#5A3E26")
local IRON = hex("#3B3634")
local PAPER = hex("#F4ECD8")
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

-- What one placement covers along z: its box, or the whole row of boxes a
-- limited item shows.
local function placeDepth(place: StoreStock.Placement): number
	return place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
end

local STEP_SLAB = 0.3 -- the thinnest a step is: the top board
local STEP_GAP = 0.45 -- a step reaches this far past its boxes toward the next row
local STEP_END = 0.8 -- and this far past the first and last rows

-- The display unit a lane is: a solid table body (legs and apron) up to just
-- under the lowest step, and on it a STEP per row of boxes, each a little
-- higher than the one in front of it (StoreStock.RowStep), so the rows behind
-- show over the rows in front. Each box stands on a PLINTH, a solid block in
-- the item's accent colour (BoxLook: the colour of its band and its edge),
-- the way Lumber Tycoon 2's display case stands each item on a colour block.
-- Steps are the walls' height and never move: the plinths' tops are exactly
-- where StoreStock puts the boxes' feet. Returns the z extent of each lane.
function ShopKit.SteppedUnit(
	parent: Instance,
	shop: string,
	frame: Frame,
	name: string,
	body: Color3,
	top: Color3,
	style: string? -- "stand" (default: a coloured plinth and tier flag per box) or "table" (a DisplayTable per row, a SpotTag per box)
): { [string]: { lo: number, hi: number } }
	local asTable = style == "table"
	local out: { [string]: { lo: number, hi: number } } = {}
	local placements = StoreStock.Placements(shop)
	for _, lane in ipairs(StoreStock.Lanes(shop)) do
		local rows: { [number]: { lo: number, hi: number, surface: number } } = {}
		local last = 0
		-- The top of the tallest box in each row: the tier flags of a row stand level over it.
		local rowTops: { [string]: number } = {}
		for _, place in ipairs(placements) do
			if place.lane == lane.name then
				local key = lane.name .. place.row
				rowTops[key] = math.max(rowTops[key] or -math.huge, place.y + place.size.Y / 2)
			end
		end
		for _, place in ipairs(placements) do
			if place.lane == lane.name then
				local half = placeDepth(place) / 2
				local row = rows[place.row]
				if row == nil then
					row = { lo = place.z - half, hi = place.z + half, surface = place.surface }
					rows[place.row] = row
				else
					row.lo = math.min(row.lo, place.z - half)
					row.hi = math.max(row.hi, place.z + half)
				end
				last = math.max(last, place.row)
				-- The stand: the plinth in the tier colour, with its tier flag and lock chip.
				local slot = StoreStock.Get(place.slotId)
				if slot and not asTable then -- (a table's tags are built with the row, below)
					local accent = BoxLook.Accent(slot.itemKind, slot.itemId)
					local m = StoreStock.PlinthMargin
					ShopKit.TierStand(parent, {
						slot = slot,
						size = V3(place.size.X + 2 * m, StoreStock.PlinthHeight, 2 * half + 2 * m),
						at = V3(place.x, place.surface + StoreStock.PlinthHeight / 2, place.z),
						aisle = if (lane.x0 + lane.x1) / 2 < 0 then 1 else -1,
						flagY = (rowTops[lane.name .. place.row] or place.y) + 1.0,
						accent = accent,
					})
				end
			end
		end
		if last == 0 then
			continue
		end
		local lo = math.max(lane.z0, rows[1].lo - STEP_END)
		local hi = math.min(lane.z1, rows[last].hi + STEP_END)
		out[lane.name] = { lo = lo, hi = hi }
		local w = lane.x1 - lane.x0
		local cx = (lane.x0 + lane.x1) / 2
		local bodyH = lane.y - STEP_SLAB - frame.floorTop
		Kit.part(
			parent,
			name,
			V3(w - 0.4, bodyH, hi - lo - 0.4),
			CF(cx, frame.floorTop + bodyH / 2, (lo + hi) / 2),
			body,
			MAT.WoodPlanks
		)
		for r = 1, last do
			local row = rows[r]
			if row == nil then
				continue
			end
			local z0 = if r == 1 then lo else row.lo - STEP_GAP
			local z1 = if r == last then hi else row.hi + STEP_GAP
			local base = lane.y - STEP_SLAB
			local thick = row.surface - base
			if asTable then
				-- A DisplayTable: its top is where the boxes' feet are (surface + PlinthHeight), the band under it
				-- reaches down to the unit's body. One SpotTag per box, on the table's front edge.
				local tableSpec: TableSpec = {
					cx = cx,
					cz = (z0 + z1) / 2,
					width = w,
					depth = z1 - z0,
					topY = row.surface + StoreStock.PlinthHeight,
					topThick = thick + StoreStock.PlinthHeight, -- one thick plank top from the unit's body to where the boxes stand
					apronH = 0,
				}
				ShopKit.DisplayTable(parent, tableSpec)
				for _, place in ipairs(placements) do
					local slot = StoreStock.Get(place.slotId)
					if slot and place.lane == lane.name and place.row == r then
						ShopKit.SpotTag(parent, {
							slot = slot,
							x = place.x,
							z = z0 + 0.25,
							topY = tableSpec.topY,
							locked = StoreTier.LockOf(slot.itemKind, slot.itemId) ~= nil,
						})
					end
				end
				continue
			end
			local step = Kit.part(
				parent,
				name .. "Step",
				V3(w, thick, z1 - z0),
				CF(cx, base + thick / 2, (z0 + z1) / 2),
				top,
				MAT.Wood
			)
			step.CanQuery = false
		end
		-- The front edge of the first step: a trim board, as the tables had.
		if not asTable then
			dBox(parent, name .. "Trim", V3(w + 0.1, 0.5, 0.18), CF(cx, lane.y - 0.5, lo - 0.04), TIMBER)
		end
	end
	return out
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

-- (No price plaques on the tables and shelves: a box's one price is on its
-- own label, BoxArt. A plaque on the aisle face could only ever speak for the
-- box nearest the aisle, and two boxes side by side drew theirs on top of each
-- other.)

---------------------------------------------------------------------------

-- The cash desk's furnishings: a brass bell, a balance scale, a receipt spike
-- and two jars on the counter top, and a stool behind it for the keeper. Read
-- from the real Counter part (it may be anywhere in the shop). Looks only.
local function counterDetail(model: Model, frame: Frame)
	-- The shell's counter already carries the bell, the till and the ledger.
	-- Keeping this call checks the counter is the one the shell built.
	local counter = model:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") and frame.ceilY > frame.floorTop then
		return
	end
	return
end

-- A door to the back room on a wall (looks only; nothing opens): `onZ` for the
-- back wall (+Z, facing -Z), else a side wall at x with `side` +1 (east) or -1.
local function backDoor(model: Model, frame: Frame, x: number, z: number, onZ: boolean, side: number)
	-- The frame is three bars AROUND the leaf, standing a tenth proud: no
	-- frame face lies on the leaf's plane, so there is never a second texture
	-- to fight with the door's (the specs scan for it).
	local size = if onZ then V3(3.2, 8, 0.3) else V3(0.3, 8, 3.2)
	local cy = frame.floorTop + 4
	local at = CF(x, cy, z)
	dBox(model, "BackRoomDoor", size, at, hex("#6E4A2E"), MAT.Wood)
	-- The room is on the -Z side of the back wall and on the -side side of a side wall.
	local depth = 0.3
	local shift = CF(if onZ then 0 else -side * 0.1, 0, if onZ then -0.1 else 0)
	local function bar(name: string, w: number, h: number, dx: number, dy: number)
		local barSize = if onZ then V3(w, h, depth) else V3(depth, h, w)
		local offset = if onZ then CF(dx, dy, 0) else CF(0, dy, dx)
		dBox(model, name, barSize, at * shift * offset, TRIM, MAT.Wood)
	end
	for _, s in ipairs({ -1, 1 }) do
		bar("BackRoomDoorFrame", 0.4, 8, s * 1.8, 0)
	end
	bar("BackRoomDoorFrame", 4, 0.6, 0, 4.3)
	local knob = if onZ then CF(1.2, -0.2, -0.25) else CF(-side * 0.25, -0.2, 1.2)
	Kit.decor(Kit.ball(model, "BackRoomKnob", 0.35, at * knob, hex("#C9A24A"), MAT.Metal), false)
end

local function banner(parent: Instance, x: number, y: number, z: number, color: Color3, text: string)
	dBox(parent, "BannerRod", V3(2.6, 0.18, 0.18), CF(x, y + 2.7, z), IRON, MAT.Metal)
	local b = dBox(parent, "Banner", V3(2.2, 4.8, 0.08), CF(x, y, z), color, MAT.Fabric)
	Kit.signText(b, text, PAPER, nil, Enum.Font.FredokaOne, 0.2)
end

---------------------------------------------------------------------------
-- The family kit: signs, tier stands, counter, lights, beams, mesh props
---------------------------------------------------------------------------

local WALNUT = hex("#2A1F17") -- UITheme Panel: the sign boards
local CREAM = hex("#F3E7C9") -- UITheme Cream: sign text
local BRASS = hex("#C9A24A") -- UITheme AmberEdge: frames
local PINE = hex("#2F5D3A") -- Palette PineTrim: the small signs
local INK = hex("#2A2420") -- Palette SignInk: text on brass
local WARM = Color3.fromRGB(255, 206, 150)

ShopKit.Colors = {
	Walnut = WALNUT,
	Cream = CREAM,
	Brass = BRASS,
	Pine = PINE,
	Ink = INK,
	Timber = TIMBER,
	Iron = IRON,
	Warm = WARM,
} :: { [string]: Color3 }

-- The warm light every lamp in the family uses: modest, never a white-out.
-- (ShowroomLight's caps, 1 brightness and 22 range, hold for every store.)
ShopKit.Light = { Brightness = 0.9, Range = 16, Color = WARM }

-- Signs hang with this much chain at least, and nothing over a header sign
-- is closer than this to the ceiling line.
ShopKit.MinChain = 1.2

-- How tall the text of a sign reads at 667 x 375: header signs are at least
-- this tall (studs); sub-signs at least ShopKit.SubMinHeight.
ShopKit.HeaderMinHeight = 2.2
ShopKit.SubMinHeight = 1.0

-- The viewing rule the signs are checked against (667 x 375 phone, a 70 degree
-- camera): a header's text is at least ShopKit.MinTextPx tall from
-- ShopKit.HeaderViewDist studs, a sub-sign's from ShopKit.SubViewDist.
ShopKit.MinTextPx = 14
ShopKit.HeaderViewDist = 25
ShopKit.SubViewDist = 15
ShopKit.PhoneHeight = 375
ShopKit.PhoneFov = 70
ShopKit.SubSetback = 6 -- sub-signs hang no nearer than this many studs from a lane's front end

-- The caps no interior light or glow may pass (spec: StoreInterior.*): a light is
-- at most this bright and reaches this far, and a Neon part is never near-white.
ShopKit.MaxLightBrightness = 1
ShopKit.MaxLightRange = 22
ShopKit.MaxNeonLuma = 0.86 -- a Neon part's colour luma (0 to 1) stays under this: warm cream or amber, never white

-- Whether a Neon colour is too white (blows out at day and night).
function ShopKit.NearWhite(c: Color3): boolean
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B > ShopKit.MaxNeonLuma
end

-- How many pixels tall a sign's text is on a phone screen: the board is `h`
-- studs tall, the text fills 0.84 of it (Kit.signText's padding), seen from
-- `dist` studs.
function ShopKit.TextPx(h: number, dist: number): number
	local pxPerStud = ShopKit.PhoneHeight / (2 * dist * math.tan(math.rad(ShopKit.PhoneFov) / 2))
	return 0.84 * h * pxPerStud
end

export type SignSpec = {
	cx: number,
	cy: number, -- the board's middle
	z: number,
	w: number,
	h: number,
	text: string,
	accent: Color3, -- the bar under the board
	ceilY: number, -- the chains run up to here
	board: Color3?,
	ink: Color3?,
	name: string?,
}

-- A board hung on two chains, facing -Z, the text on both faces (so it reads
-- walking in and walking out), a brass bar over it and an accent bar under it.
local function hung(parent: Instance, s: SignSpec, name: string, thick: number): Part
	local board = dBox(parent, s.name or name, V3(s.w, s.h, 0.3), CF(s.cx, s.cy, s.z), s.board or WALNUT, MAT.Wood)
	board:SetAttribute("SignText", s.text)
	Kit.signText(board, s.text, s.ink or CREAM, nil, Enum.Font.FredokaOne, 0.2)
	dBox(
		parent,
		name .. "Frame",
		V3(s.w + 0.5, thick, 0.5),
		CF(s.cx, s.cy + s.h / 2 + thick / 2 - 0.02, s.z),
		BRASS,
		MAT.Metal
	)
	dBox(
		parent,
		name .. "Accent",
		V3(s.w + 0.5, thick * 1.4, 0.5),
		CF(s.cx, s.cy - s.h / 2 - thick * 0.7 + 0.02, s.z),
		s.accent,
		MAT.SmoothPlastic
	)
	local top = s.cy + s.h / 2 + thick
	for _, side in ipairs({ -1, 1 }) do
		local len = math.max(s.ceilY - top, 0.2)
		dBox(
			parent,
			name .. "Chain",
			V3(0.12, len, 0.12),
			CF(s.cx + side * (s.w / 2 - 0.5), top + len / 2, s.z),
			IRON,
			MAT.Metal
		)
	end
	return board
end

-- The big sign over a section: 2.2+ studs tall, readable from the door.
function ShopKit.HeaderSign(parent: Instance, s: SignSpec): Part
	return hung(parent, s, "HeaderSign", 0.3)
end

-- The small sign for a category inside a section.
function ShopKit.SubSign(parent: Instance, s: SignSpec): Part
	local spec = table.clone(s)
	spec.board = s.board or PINE
	return hung(parent, spec, "SubSign", 0.2)
end

---------------------------------------------------------------------------
-- Hover-tag anchors
---------------------------------------------------------------------------

export type HoverSpec = { key: string, name: string, kind: string, itemId: string, shop: string }

-- An invisible aim target (looks only) that carries a hover tag, for a thing
-- with no part of its own to mark. The tag sits over it.
function ShopKit.HoverAnchor(parent: Instance, spec: HoverSpec, size: Vector3, cf: CFrame): Part
	local p = decor(Kit.part(parent, "HoverAnchor", size, cf, CREAM, MAT.SmoothPlastic))
	p.Transparency = 1
	p.CastShadow = false
	local tag: HoverTag.Spec = {
		key = spec.key,
		name = spec.name,
		kind = spec.kind,
		itemId = spec.itemId,
		shop = spec.shop,
		anchor = true,
	}
	HoverTag.Mark(p, tag)
	return p
end

---------------------------------------------------------------------------
-- Tier stands
---------------------------------------------------------------------------

export type StandSpec = {
	slot: StoreStock.Slot,
	size: Vector3, -- the plinth's size
	at: Vector3, -- the plinth's middle
	aisle: number, -- +1 when the aisle is on the +X side, -1 on the -X side
	flagY: number, -- the flag board's middle (uniform along a row)
	accent: Color3, -- the stand's colour when the item has no tier
}

ShopKit.FlagSize = Vector3.new(1.7, 1.0, 0.16)
ShopKit.ChipSize = Vector3.new(2.6, 0.6, 0.14) -- (narrower: from the door the chips of two rows never overlap on the screen)
ShopKit.FlagYaw = math.rad(40) -- the flag is turned this far to the aisle, so it reads from the door and from the aisle

-- One slot's stand: the PLINTH (the box's block, in the tier colour or, for an
-- item with no tier, its category colour), a TIER FLAG on a short post at the
-- plinth's aisle-side front corner (the badge, "T3", reads over the box), and
-- for an item that can be locked a LOCK CHIP over the flag. Everything is
-- looks only and marked with the item's hover tag (name and price from the
-- shop's own price rules). The stand parts carry attributes the client reads
-- to grey them while the item is locked (StoreStandState).
function ShopKit.TierStand(parent: Instance, s: StandSpec): Part
	local slot = s.slot
	local tier = StoreTier.Of(slot.itemKind, slot.itemId)
	local color = if tier then StoreTier.Color(tier) else s.accent
	local lock = StoreTier.LockOf(slot.itemKind, slot.itemId)
	local plinth = dBox(parent, "Plinth", s.size, CF(s.at), color, MAT.SmoothPlastic)
	local hover: HoverTag.Spec = {
		key = "Stand:" .. slot.slotId,
		name = slot.displayName,
		kind = slot.itemKind,
		itemId = slot.itemId,
		shop = slot.shop,
		limited = if slot.limited then true else nil,
	}
	local function standPart(p: Part, role: string, open: Color3)
		p:SetAttribute("StandRole", role)
		p:SetAttribute("StandKind", slot.itemKind)
		p:SetAttribute("StandItem", slot.itemId)
		p:SetAttribute("StandOpen", open)
		pcall(function()
			CollectionService:AddTag(p, "StoreStand")
		end)
	end
	if lock then
		standPart(plinth, "base", color)
	end
	if tier == nil then
		hover.anchor = true
		HoverTag.Mark(plinth, hover)
		return plinth
	end
	HoverTag.Mark(plinth, hover)
	plinth:SetAttribute("StandTier", tier)
	-- The flag: a post at the aisle-side front corner, standing in the plinth's margin.
	local px = s.at.X + s.aisle * (s.size.X / 2 - 0.12)
	local pz = s.at.Z - s.size.Z / 2 + 0.12
	local base = s.at.Y + s.size.Y / 2
	local postTop = s.flagY - ShopKit.FlagSize.Y / 2
	local post =
		dBox(parent, "TierPost", V3(0.16, postTop - base, 0.16), CF(px, (base + postTop) / 2, pz), BRASS, MAT.Metal)
	local yaw = CFrame.Angles(0, -s.aisle * ShopKit.FlagYaw, 0)
	local at = CF(px, s.flagY, pz) * yaw
	-- the brass backing is thinner than the board so no face is coplanar with another
	dBox(parent, "TierBacking", ShopKit.FlagSize + V3(0.2, 0.2, -0.08), at, BRASS, MAT.Metal)
	local flag = dBox(parent, "TierFlag", ShopKit.FlagSize, at, color, MAT.SmoothPlastic)
	Kit.signText(flag, StoreTier.Label(tier), StoreTier.InkOn(color), nil, Enum.Font.FredokaOne, 0.2)
	flag:SetAttribute("StandTier", tier)
	if lock then
		standPart(flag, "flag", color)
	end
	hover.anchor = true
	HoverTag.Mark(flag, hover)
	hover.anchor = false
	HoverTag.Mark(post, hover)
	if lock then
		-- (the chip stands on the flag's backing: 0.6 over the flag's middle, plus half the chip)
		local chipAt = CF(px, s.flagY + ShopKit.FlagSize.Y / 2 + 0.4, pz) * yaw
		local chip = dBox(parent, "LockChip", ShopKit.ChipSize, chipAt, StoreTier.LockedColor, MAT.SmoothPlastic)
		Kit.signText(chip, lock.text, StoreTier.LockedInk, nil, Enum.Font.FredokaOne, 0.2)
		chip:SetAttribute("LockText", lock.text)
		standPart(chip, "chip", StoreTier.LockedColor)
	end
	return plinth
end

---------------------------------------------------------------------------
-- Display tables, price tags and spot lamps
---------------------------------------------------------------------------

-- The wood a display table is made of: a light plank top, a dark apron, a cream trim.
ShopKit.TableWood = {
	top = hex("#D6AD78"),
	apron = TIMBER,
	trim = hex("#EBDDBB"),
} :: { [string]: Color3 }

ShopKit.TableOverhang = 0.12 -- the top reaches this far past the apron on every side
ShopKit.SpotWidth = 3.4 -- the width one display spot is given (a box is at most about 3.1 wide)

export type TableSpec = {
	cx: number, -- the middle of the top, x
	cz: number, -- and z
	width: number?, -- along x; default spots * SpotWidth + 0.8
	depth: number, -- along z
	topY: number, -- the top surface: where the items stand
	spots: number?, -- how many items it carries (2 or 3 is the design; 1 for an odd row)
	topThick: number?, -- default 0.3
	apronH: number?, -- the dark band under the top (default 0.5; 0 for none, when the top is thick enough to stand on the unit below)
	legs: number?, -- with `floorY`, this many stud-wide legs from the floor to the apron (4 for a free-standing table)
	floorY: number?,
	solid: boolean?, -- the top collides (default true); the apron, trim and legs never do
	name: string?,
}

export type TableParts = { top: Part, apron: Part?, trim: Part, legs: { Part } }

-- A display table: a PLANK TOP (WoodPlanks, in the light wood, a little wider than what is under it), an APRON band
-- under it in dark timber, a TRIM board along the front edge in cream, and optionally four LEGS to the floor.
-- It is only the table: items and tags are placed by the caller (ShopKit.SpotTag). Three parts without legs
-- (two when apronH = 0).
-- Reusable: ShopKit.DisplayTable(parent, { cx, cz, depth, topY, spots = 3 }).
function ShopKit.DisplayTable(parent: Instance, s: TableSpec): TableParts
	local name = s.name or "Table"
	local thick = s.topThick or 0.3
	local apronH = s.apronH or 0.5
	local width = s.width or ((s.spots or 2) * ShopKit.SpotWidth + 0.8)
	local o = ShopKit.TableOverhang
	local topMid = s.topY - thick / 2
	local top = Kit.part(
		parent,
		name .. "Top",
		V3(width, thick, s.depth),
		CF(s.cx, topMid, s.cz),
		ShopKit.TableWood.top,
		MAT.WoodPlanks
	)
	top.CanQuery = false
	if s.solid == false then
		decor(top)
	end
	local apron: Part? = nil
	if apronH > 0.01 then
		apron = dBox(
			parent,
			name .. "Apron",
			V3(width - 2 * o, apronH, s.depth - 2 * o),
			CF(s.cx, s.topY - thick - apronH / 2, s.cz),
			ShopKit.TableWood.apron
		)
	end
	local trim = dBox(
		parent,
		name .. "Trim",
		V3(width, thick, 0.1),
		CF(s.cx, topMid, s.cz - s.depth / 2 - 0.05),
		ShopKit.TableWood.trim
	)
	local legs: { Part } = {}
	if s.legs and s.floorY then
		local bottom = s.topY - thick - apronH
		local h = bottom - s.floorY
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(
					legs,
					dBox(
						parent,
						name .. "Leg",
						V3(0.5, h, 0.5),
						CF(s.cx + sx * (width / 2 - 0.45), s.floorY + h / 2, s.cz + sz * (s.depth / 2 - 0.45)),
						ShopKit.TableWood.apron
					)
				)
			end
		end
	end
	return { top = top, apron = apron, trim = trim, legs = legs }
end

ShopKit.TagSize = Vector3.new(1.45, 0.42, 0.06) -- a price card: width, slope length, thickness
ShopKit.TagTilt = math.rad(60) -- it leans back this far from standing, so it reads from the aisle and from above

export type TagSpec = {
	slot: StoreStock.Slot,
	x: number, -- the middle of the item's spot
	z: number, -- the middle of the card's footprint (on the table's front margin)
	topY: number, -- the table top
	locked: boolean?, -- the item can be locked: a lock card sits beside the price card
}

-- The price card of one display spot, and for an item that can be locked (StoreTier.LockOf: "S5 SMITH", "NEEDS
-- STEEL") a LOCK CARD beside it that the client shows only while the item is locked for you (StoreStandState).
-- Both lean on the table's front margin, inside the table, never taller than a few tenths of a stud. The price is
-- StoreStock.UnitPrice (the one price the server charges), read here, never typed. The card carries the item's hover
-- tag, so aiming at it (or tapping it on a phone) names the item and shows the price too. Returns the price card.
function ShopKit.SpotTag(parent: Instance, s: TagSpec): Part
	local slot = s.slot
	local tier = StoreTier.Of(slot.itemKind, slot.itemId)
	local color = if tier then StoreTier.Color(tier) else WALNUT
	local ink = if tier then StoreTier.InkOn(color) else CREAM
	local lock = StoreTier.LockOf(slot.itemKind, slot.itemId)
	local price = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, GameConfig.CoreLoop)
	local text = if price then Util.formatCash(price) else slot.displayName
	local size = ShopKit.TagSize
	-- (the card's lowest edge rests on the table top: half its slope's height plus half its thickness' share)
	local lift = size.Y / 2 * math.cos(ShopKit.TagTilt) + size.Z / 2 * math.sin(ShopKit.TagTilt)
	local tilt = CFrame.Angles(ShopKit.TagTilt, 0, 0)
	local function standPart(p: Part, role: string, open: Color3)
		p:SetAttribute("StandRole", role)
		p:SetAttribute("StandKind", slot.itemKind)
		p:SetAttribute("StandItem", slot.itemId)
		p:SetAttribute("StandOpen", open)
		pcall(function()
			CollectionService:AddTag(p, "StoreStand")
		end)
	end
	local shift = if s.locked and lock then -0.78 else 0
	local card = dBox(parent, "SpotTag", size, CF(s.x + shift, s.topY + lift, s.z) * tilt, color, MAT.SmoothPlastic)
	Kit.signText(card, text, ink, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
	card:SetAttribute("SignText", text)
	if tier then
		card:SetAttribute("StandTier", tier)
	end
	local hover: HoverTag.Spec = {
		key = "Stand:" .. slot.slotId,
		name = slot.displayName,
		kind = slot.itemKind,
		itemId = slot.itemId,
		shop = slot.shop,
		limited = if slot.limited then true else nil,
		anchor = true,
	}
	HoverTag.Mark(card, hover)
	if lock then
		standPart(card, "base", color)
		local chip = dBox(
			parent,
			"LockChip",
			size,
			CF(s.x + 0.78, s.topY + lift, s.z) * tilt,
			StoreTier.LockedColor,
			MAT.SmoothPlastic
		)
		Kit.signText(chip, lock.text, StoreTier.LockedInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		chip:SetAttribute("LockText", lock.text)
		hover.anchor = false
		HoverTag.Mark(chip, hover)
		standPart(chip, "chip", StoreTier.LockedColor)
	end
	return card
end

-- A small warm spot over a table: a brass shade, on a chain (or, with the shade at the ceiling, flush like a can light), with the family's modest light (at most
-- MaxLightBrightness and MaxLightRange, warm, no shadows). `y` is the middle of the shade, `ceilY` where the
-- chain ends (a beam, a tie or the ceiling boards).
function ShopKit.SpotLamp(parent: Instance, x: number, y: number, z: number, ceilY: number): Part
	local len = ceilY - y - 0.25
	if len > 0.4 then
		dBox(parent, "SpotChain", V3(0.08, len, 0.08), CF(x, ceilY - len / 2, z), IRON, MAT.Metal)
	end
	local shade = Kit.cylinder(
		parent,
		"SpotShade",
		0.4,
		0.75,
		CF(x, y, z) * CFrame.Angles(0, 0, math.pi / 2),
		hex("#7A5A2A"),
		MAT.Metal
	)
	decor(shade)
	local light = Instance.new("PointLight")
	light.Name = "SpotLight"
	light.Brightness = 0.7
	light.Range = 15
	light.Color = ShopKit.Light.Color
	light.Shadows = false
	light.Parent = shade
	return shade
end

---------------------------------------------------------------------------
-- Section signs from a store's own sections
---------------------------------------------------------------------------

export type Sub = { text: string, ids: { string } } -- the item ids a category sign covers
export type Section = {
	lane: string, -- the StoreStock lane the header stands over
	header: string,
	accent: Color3,
	subs: { Sub },
	subW: number?, -- sub-sign width (default 5.4)
	subStagger: number?, -- when set, sub-signs alternate this far left and right of the lane's middle, so two signs in one lane do not hide each other from the door
	headerW: number?, -- the header's width (default: the lane's width less 0.6)
	headerCx: number?, -- and its middle x (default: the lane's middle): a header can stand nearer the aisle so it is not cut off at the door
	subAbove: number?, -- studs from a box top to the middle of this section's sub-signs (default SUB_ABOVE; lower for a unit with no tier flags)
}

-- The header over each lane (at its front end) and a sub-sign over each
-- category, over the category's first rows. Every sign hangs on chains from a
-- timber TIE beam across its lane at `cfg.tieY` (a collar tie of the barn, up
-- where nothing else is), so the signs stand well over the stands and their
-- flags: a header's middle is `cfg.headerY` at `cfg.headerZ`, a sub-sign hangs
-- at least SUB_ABOVE over the tallest box in the first rows of its category
-- and always under the header. A sub-sign at the very front of a lane is set
-- back so it never stands in the header's plane.
local SUB_ABOVE = 3.7 -- from the top of a box to the middle of a sub-sign: over the tier flag (1.0 + 0.5 + the lock chip 0.8) and the sign's own bar
function ShopKit.SectionSigns(
	parent: Instance,
	shop: string,
	sections: { Section },
	cfg: { headerY: number, headerZ: number, tieY: number, subShift: number?, tieTop: number? }
)
	local placements = StoreStock.Placements(shop)
	local lanes: { [string]: ShelfLayout.Lane? } = {}
	for _, lane in ipairs(StoreStock.Lanes(shop)) do
		lanes[lane.name] = lane
	end
	local headerH = ShopKit.HeaderMinHeight + 0.4
	local subH = ShopKit.SubMinHeight + 0.2
	local chainTop = cfg.tieY - 0.25
	local shift = cfg.subShift or 1.3
	local tied: { [string]: boolean } = {}
	local function tie(cx: number, w: number, z: number)
		local key = string.format("%.2f:%.2f", cx, z)
		if tied[key] then
			return
		end
		tied[key] = true
		-- (with cfg.tieTop the tie is a deep beam that reaches up to the roof's underside)
		local bottom = cfg.tieY - 0.25
		local height = if cfg.tieTop then cfg.tieTop - bottom else 0.5
		dBox(parent, "SignTie", V3(w + 1.4, height, 0.5), CF(cx, bottom + height / 2, z), TIMBER)
	end
	for _, section in ipairs(sections) do
		local lane = lanes[section.lane]
		if lane == nil then
			continue
		end
		local cx = section.headerCx or (lane.x0 + lane.x1) / 2
		local w = section.headerW or (lane.x1 - lane.x0 - 0.6)
		tie(cx, w, cfg.headerZ)
		ShopKit.HeaderSign(parent, {
			cx = cx,
			cy = cfg.headerY,
			z = cfg.headerZ,
			w = w,
			h = headerH,
			text = section.header,
			accent = section.accent,
			ceilY = chainTop,
		})
		for subIndex, sub in ipairs(section.subs) do
			local want: { [string]: boolean } = {}
			for _, id in ipairs(sub.ids) do
				want[id] = true
			end
			local z0 = math.huge
			for _, place in ipairs(placements) do
				local slot = StoreStock.Get(place.slotId)
				if slot and place.lane == section.lane and want[slot.itemId] then
					z0 = math.min(z0, place.z - place.size.Z / 2)
				end
			end
			if z0 == math.huge then
				continue
			end
			-- the tallest box among the category's first rows, near the sign
			-- never in the first SUB_SETBACK studs of the lane (that is the open entrance: the
			-- phone camera stands there), and never in the header's plane
			local z = math.max(z0 - 0.6, lane.z0 + ShopKit.SubSetback)
			if math.abs(z - cfg.headerZ) < 2.4 then
				z = cfg.headerZ + 2.4
			end
			local top = -math.huge
			for _, place in ipairs(placements) do
				local slot = StoreStock.Get(place.slotId)
				if
					slot
					and place.lane == section.lane
					and want[slot.itemId]
					and place.z - place.size.Z / 2 < z + 6.5
				then
					top = math.max(top, place.y + place.size.Y / 2)
				end
			end
			local cy = top + (section.subAbove or SUB_ABOVE)
			local stagger = if section.subStagger then (if subIndex % 2 == 1 then -1 else 1) * section.subStagger else 0
			tie(cx, w, z)
			ShopKit.SubSign(parent, {
				cx = cx + (if cx < 0 then -shift else shift) + stagger, -- toward the wall (cfg.subShift, 1.3 by default; 0 for a lane against a wall), so it never covers the header's inner end from the aisle
				cy = cy,
				z = z,
				w = math.min(w, section.subW or 5.4),
				h = subH,
				text = sub.text,
				accent = section.accent,
				ceilY = chainTop,
			})
		end
	end
end

---------------------------------------------------------------------------
-- The counter
---------------------------------------------------------------------------

-- The counter's CHECKOUT sign and the keeper's mat. Reads the real Counter
-- part; nothing when the model has none. The sign is a brass plaque on the
-- counter's front face (it never blocks the wall behind the counter); with
-- `hang` a bigger brass board also hangs over the aisle in front of it (for a
-- store whose back wall is clear). The mat is where NPCData.BehindCounter
-- stands the keeper.
export type CheckoutOpts = {
	plaque: boolean?, -- the brass plaque on the counter's front face (default true)
	cy: number?, -- the hung board's middle y (default 10.4 or just under the ceiling)
	z: number?, -- and its z (default 3.4 in front of the counter)
	w: number?, -- and its width
	h: number?, -- and its height
	ceilY: number?, -- where its chains end (default under the ceiling beams)
	onCounter: boolean?, -- instead of hanging: a board on two posts standing on the counter's top at its front edge, `cy` over the floor
}

function ShopKit.CheckoutSign(model: Model, frame: Frame, hang: (boolean | CheckoutOpts)?)
	local counter = model:FindFirstChild("Counter")
	if not (counter and counter:IsA("BasePart")) then
		return
	end
	local cf, size = counter.CFrame, counter.Size
	local front = cf.Position.Z - size.Z / 2
	local width = math.min(size.X - 1.2, 6.4)
	local opts: CheckoutOpts = if type(hang) == "table" then hang else {}
	local wantHung = hang == true or type(hang) == "table"
	local showPlaque = if type(hang) == "table" then opts.plaque ~= false else true
	if showPlaque then
		local plaque = dBox(
			model,
			"CheckoutPlaque",
			V3(width, 1.5, 0.14),
			CF(cf.Position.X, cf.Position.Y - 0.1, front - 0.08),
			BRASS,
			MAT.Metal
		)
		Kit.signText(plaque, "CHECKOUT", INK, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		dBox(
			model,
			"CheckoutPlaqueAccent",
			V3(width + 0.3, 0.22, 0.2),
			CF(cf.Position.X, cf.Position.Y - 0.95, front - 0.1),
			hex("#4CC36A"),
			MAT.SmoothPlastic
		)
	end
	if type(hang) == "table" and opts.onCounter == true then
		-- A board on two posts standing on the counter's front edge: always over the counter, nothing in front of it
		-- (no chains to cross another sign on screen), clear of the register, till and bell at the counter's middle.
		local w = opts.w or 7
		local h = opts.h or 1.5
		local cy = opts.cy or (cf.Position.Y + size.Y / 2 + 3.4)
		local z = cf.Position.Z - size.Z / 2 + 0.2
		local topY = cf.Position.Y + size.Y / 2
		local board = dBox(model, "CheckoutSign", V3(w, h, 0.3), CF(cf.Position.X, cy, z), BRASS, MAT.Metal)
		Kit.signText(board, "CHECKOUT", INK, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		board:SetAttribute("SignText", "CHECKOUT")
		dBox(
			model,
			"CheckoutSignAccent",
			V3(w + 0.3, 0.26, 0.4),
			CF(cf.Position.X, cy - h / 2 - 0.1, z),
			hex("#4CC36A"),
			MAT.SmoothPlastic
		)
		for _, s in ipairs({ -1, 1 }) do
			local px = cf.Position.X + s * (w / 2 - 0.4)
			local top = cy - h / 2 - 0.2
			dBox(model, "CheckoutPost", V3(0.3, top - topY, 0.3), CF(px, (top + topY) / 2, z), TIMBER)
		end
	elseif wantHung then
		ShopKit.HeaderSign(model, {
			cx = cf.Position.X,
			cy = opts.cy or math.min(frame.ceilY - 3.2, 10.4),
			z = opts.z or (front - 3.4),
			w = opts.w or math.min(size.X - 1, 8.4),
			h = opts.h or 1.8,
			text = "CHECKOUT",
			accent = hex("#4CC36A"),
			ceilY = opts.ceilY or (frame.ceilY - 0.9),
			board = BRASS,
			ink = INK,
			name = "CheckoutSign",
		})
	end
	local mat = dBox(
		model,
		"KeeperMat",
		V3(4.2, 0.06, 2.6),
		CF(cf.Position.X, frame.floorTop + LAYER2, cf.Position.Z + size.Z / 2 + 1.5),
		PINE,
		MAT.Fabric
	)
	mat:SetAttribute("KeeperSpot", true)
	dBox(
		model,
		"KeeperMatEdge",
		V3(4.5, 0.07, 0.3),
		CF(cf.Position.X, frame.floorTop + LAYER3, cf.Position.Z + size.Z / 2 + 0.32),
		BRASS,
		MAT.Fabric
	)
end

---------------------------------------------------------------------------
-- Lights and beams
---------------------------------------------------------------------------

-- A lantern on a chain with the family's modest warm light.
function ShopKit.WarmLamp(parent: Instance, x: number, y: number, z: number, ceilY: number): Part
	local len = ceilY - y - 0.6
	dBox(parent, "LampChain", V3(0.1, len, 0.1), CF(x, ceilY - len / 2, z), IRON, MAT.Metal)
	local glow = Kit.lantern(parent, CF(x, y, z), 1.1)
	for _, d in ipairs(glow:GetChildren()) do
		if d:IsA("PointLight") then
			d.Brightness = ShopKit.Light.Brightness
			d.Range = ShopKit.Light.Range
			d.Color = ShopKit.Light.Color
			d.Shadows = false
		end
	end
	return glow
end

-- Ceiling beams across the room at each z (a 0.9 timber square).
function ShopKit.Beams(parent: Instance, frame: Frame, zs: { number }, y: number?)
	for _, z in ipairs(zs) do
		dBox(parent, "CeilingBeam", V3(2 * frame.halfW - 0.6, 0.9, 0.9), CF(0, (y or frame.ceilY - 0.45), z), TIMBER)
	end
end

-- A rafter along the room (z) at x, tying the cross beams together.
function ShopKit.Rafter(parent: Instance, frame: Frame, x: number, y: number?)
	dBox(
		parent,
		"CeilingRafter",
		V3(0.7, 0.7, 2 * frame.halfD - 0.8),
		CF(x, (y or frame.ceilY - 0.45) + 0.1, 0),
		TIMBER
	)
end

---------------------------------------------------------------------------
-- Real meshes with a part-built fallback
---------------------------------------------------------------------------

local function meshNow(parent: Instance, assetId: string, pivot: CFrame, fallback: Instance?): boolean
	if not TownMeshes.Enabled then
		return false
	end
	local asset = TownModels.Get(assetId)
	if not asset then
		return false
	end
	local made: { MeshPart } = {}
	local ids: { number } = {}
	for _, piece in ipairs(TownModels.Visual(asset)) do
		local part = MeshKit.Create(piece.meshId, piece.name, piece.size)
		if not part then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		table.insert(made, part)
		table.insert(ids, piece.meshId)
	end
	for i, part in ipairs(made) do
		-- (TownMeshes' own placement: a mesh whose import pivot survived is moved by its pivot.)
		if part:GetAttribute("MeshPivot") == "authored" then
			part:PivotTo(pivot)
		else
			part.CFrame = pivot * CFrame.new(0, part.Size.Y / 2, 0)
		end
		MeshKit.Visual(part, ids[i])
		MeshKit.Fidelity(part, TownMeshes.FidelityFor(part.Name, asset.tris))
		part.Anchored = true
		part.Parent = parent
	end
	if fallback ~= nil and #made > 0 then
		fallback:Destroy()
	end
	return #made > 0
end

-- Dresses `parent` with a town mesh standing on `pivot` (its base at the
-- pivot, the way TownMeshes.Adorn places one). `fallback` (the part-built
-- prop, a Model or a Part under `parent`) stays until the mesh has loaded and
-- is then dropped: the same fallback-then-swap path the shops use (MeshKit.
-- Attempt), never a yielding load. Returns whether the mesh is up now.
function ShopKit.MeshProp(parent: Instance, assetId: string, pivot: CFrame, fallback: Instance?): boolean
	return MeshKit.Attempt(parent, function()
		return meshNow(parent, assetId, pivot, fallback)
	end)
end

---------------------------------------------------------------------------
-- Budget helper
---------------------------------------------------------------------------

-- How many parts a built interior uses (every BasePart under `root`).
function ShopKit.CountParts(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- What the per-store builders (Shared/Art/ShopInteriors/*) share
---------------------------------------------------------------------------

ShopKit.decor = decor
ShopKit.dBox = dBox
ShopKit.hangSign = hangSign
ShopKit.beam = beam
ShopKit.lamp = lamp
ShopKit.plankFloor = plankFloor
ShopKit.floorBorder = floorBorder
ShopKit.runner = runner
ShopKit.plant = plant
ShopKit.crateStack = crateStack
ShopKit.trashCan = trashCan
ShopKit.counterDetail = counterDetail
ShopKit.backDoor = backDoor
ShopKit.banner = banner
ShopKit.Table = {
	body = TABLE,
	top = TABLE_TOP,
	timber = TIMBER,
	iron = IRON,
	paper = PAPER,
	trim = TRIM,
	runner = RUNNER,
	runnerEdge = RUNNER_EDGE,
} :: { [string]: Color3 }
ShopKit.Layer = { LAYER1, LAYER2, LAYER3 }

return ShopKit
