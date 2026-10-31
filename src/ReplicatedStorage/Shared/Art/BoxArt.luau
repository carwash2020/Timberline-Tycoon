--!strict
-- BoxArt: the look of a shop box: a taped kraft cardboard box (T414e; it was a
-- dark box with glass windows after Lumber Tycoon 2). Pure code (Instance.new
-- and datatypes only), so the game and the previews build the same box.
--
-- The box (front faces -Z), in at most BoxLogic.BoxPartCap parts:
--   Box         the body BoxService makes: the collision, the hover and
--               grab target, the carried assembly. Invisible (Transparency 1):
--               the cardboard below is what you see
--   Base        the floor, in the item's ACCENT colour, a hair wider than the
--               box all round (the coloured edge), with the tier line on its
--               front when the item has tiers (a sawmill, a planer)
--   Back, Left, Right   the walls: KraftTan Cardboard
--   Window      the front face and WindowTop the lid, KraftTan Cardboard
--               (the names are the old window names: BoxArt.Open, BoxWindows
--               and the specs find them), solid, collide like the box
--   SideWindow  a kraft panel on the side that faces the aisle, in place of
--               that side's wall, when the box stands on a shelf
--   Tape        a SignCream strip along the lid
--   Strip       the name label across the top of the front: a SignCream
--               label in SignInk print (the accent band in the wood look)
--   PriceTag    the cream plate under the strip, opposite the brass plate,
--               printing the item's real price (Spec.price, the one the shop
--               charges) in a SurfaceGui. The server builds the text; the
--               client recolours it per player (CoinGold or StopRed, the
--               client's BoxPriceState). The hover tag still shows it too.
--   Contents    a Model of the item itself, scaled to fit with a margin
--               (ItemModel: low-detail copy, at most ModelBudget parts). It
--               stands inside the closed cardboard, out of sight, until the
--               box is opened.
-- Everything but the body is welded to it, never more massive than the box
-- (Massless), and only the walls and faces can be touched; the contents
-- are decor that collides with nothing, answers no raycast and weighs
-- nothing, so a carried, dropped or loaded box behaves exactly as before.
-- No two visible faces share a plane: the faces stand `proud` off the walls
-- and the box, the tape stands `proud` over the lid.

local BoxLook = require(script.Parent.Parent.BoxLook)
local BoxSize = require(script.Parent.Parent.BoxSize)
local ItemBox = require(script.Parent.Parent.ItemBox)
local ItemModel = require(script.Parent.ItemModel)
local ModelSlots = require(script.Parent.ModelSlots)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Util = require(script.Parent.Parent.Util)
local RobuxBoxArt = require(script.Parent.RobuxBoxArt)
local StoreModelArt = require(script.Parent.StoreModelArt)
local StoreModelSlots = require(script.Parent.Parent.StoreModelSlots)

local BoxArt = {}

export type Spec = {
	name: string, -- shown on the strip
	tier: string?, -- a second line (a sawmill's "MILL, TIER 3 OF 5"), on the base's front
	kind: string, -- the item kind: Axe, Sawmill, Machine, Blueprint, Gear, Cosmetic, Truck, Trailer, Robux
	itemId: string?, -- the item, for its model and its accent
	color: Color3?, -- the item's own colour (only a fallback accent)
	gold: boolean?, -- a Robux box: RobuxBoxArt's open crate of coins (Lane P)
	robuxKey: string?, -- the Robux item's key (its coin pile)
	price: number?, -- the cash price the shop charges (StoreStock.UnitPrice): printed on the PriceTag plate; nil prints nothing
	side: string?, -- "Left" | "Right": the side facing the aisle gets a window too
	cardColor: Color3?, -- with `wood`: the name card's colour instead of the walnut (the Sparkworks' dark teal)
	wood: boolean?, -- the General Store's look (Hearth & Home, and the Sparkworks with a teal card): a wood base board flush under the box and a slim walnut name card, instead of the accent floor and band. Same box size, hover tag and focus.
}

-- The wood look: the base board and the name card (see Spec.wood).
BoxArt.Wood = {
	base = Color3.fromRGB(122, 84, 50),
	card = Color3.fromRGB(58, 38, 24),
	ink = Color3.fromRGB(243, 231, 201),
	stripH = 0.36,
	cardShare = 0.74, -- the card is this share of the box's width
}
BoxArt.WoodTealCard = Color3.fromRGB(26, 74, 74) -- the Sparkworks' name card: the same wood base, a dark teal card

BoxArt.Charcoal = BoxLook.Charcoal
BoxArt.Categories = BoxLook.Categories
BoxArt.DefaultCategory = BoxLook.Default

-- Proportions of the box, in studs.
BoxArt.Layout = {
	wall = 0.18, -- thickness of the dark walls
	edge = 0.1, -- the base's flange past the box: the accent band, all round
	pane = 0.05, -- thickness of a face panel
	proud = 0.03, -- how far a face stands off the walls (and the box), and the tape off the lid: no coplanar faces
	stripH = 0.5, -- height of the name strip (it sits in the top margin)
	stripProud = 0.1, -- the accent band, 0.1 deep off the front
	tierH = 0.3, -- height of the tier line on the base's front
	tape = 0.18, -- the tape's width, as a share of the box's width (at most this)
	tapeMax = 1.1, -- ...and never wider than this, in studs
	tag = Vector3.new(1.2, 0.6, 0.05), -- the price tag plate, under the strip, opposite the brass plate
	tagInset = 0.15, -- from the right edge of the box
	tagMinText = 8, -- the price's smallest text size, in pixels, so it stays legible
	pixelsPerStud = 60,
}

function BoxArt.CategoryColor(kind: string, itemId: string?): Color3
	return BoxLook.CategoryColor(kind, itemId)
end

function BoxArt.Accent(kind: string, itemId: string?): Color3
	return BoxLook.Accent(kind, itemId)
end

-- One shell part: welded to the body, weightless, a looks-only plate until a
-- caller says otherwise.
local function plate(
	parent: Instance,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Kit.part(parent, name, size, body.CFrame * CFrame.new(offset), color, material)
	Kit.decor(p, false)
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "Weld"
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- A kraft face: collides like the box (so it cannot be walked through), can
-- be aimed at and grabbed, never touched.
local function kraft(p: Part)
	p.Material = Enum.Material.Cardboard
	p.Color = Palette.KraftTan
	p.Transparency = 0
	p.Reflectance = 0
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
end

local function write(part: BasePart, face: Enum.NormalId, text: string, ink: Color3, font: Enum.Font)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NameMark"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BoxArt.Layout.pixelsPerStud
	gui.LightInfluence = 0.4
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = ink
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
end

-- The CollectionService tag on a PriceTag plate: the client finds the plates by it
-- and recolours the price per player.
BoxArt.PriceTagTag = "BoxPriceTag"
BoxArt.PriceLabelName = "Price"

-- The text printed on a box for a cash price: "$32", "$1,250", FREE at 0 (as the hover tag).
function BoxArt.PriceText(price: number): string
	if price > 0 then
		return Util.formatCash(price)
	end
	return "FREE"
end

-- Prints `price` on the front of the plate, CoinGold until the client says otherwise.
local function printPrice(tag: Part, price: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PriceMark"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BoxArt.Layout.pixelsPerStud
	gui.LightInfluence = 0.4
	gui.Parent = tag
	local label = Instance.new("TextLabel")
	label.Name = BoxArt.PriceLabelName
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = BoxArt.PriceText(price)
	label.TextScaled = true
	label.TextWrapped = false
	label.TextColor3 = Palette.CoinGold
	label.TextStrokeColor3 = Color3.fromRGB(40, 28, 16)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = BoxArt.Layout.tagMinText
	limit.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	tag:SetAttribute("Price", price)
	pcall(function()
		game:GetService("CollectionService"):AddTag(tag, BoxArt.PriceTagTag)
	end)
end

-- Dresses `body` (a Part whose size is the box) as a dark window box. Returns
-- the parts added (the shell, then the item's). The body is made invisible
-- here; its colour and size are the caller's.
function BoxArt.Dress(parent: Instance, body: BasePart, spec: Spec): { BasePart }
	local L = BoxArt.Layout
	local size = body.Size
	local W, H, D = size.X, size.Y, size.Z
	local gold = spec.gold == true
	if gold then
		return RobuxBoxArt.Dress(parent, body, { name = spec.name, key = spec.robuxKey })
	end
	local accent = if gold then BoxLook.Gold else BoxLook.Accent(spec.kind, spec.itemId)
	if spec.itemId == nil and not gold and not BoxLook.Known(spec.kind) and spec.color then
		accent = spec.color
	end
	local wallColor = Palette.KraftTan
	local ink = BoxLook.InkOn(accent) -- the tier line, on the accent foot
	local t, floor = L.wall, BoxSize.Floor
	local wood = spec.wood == true
	local stripH = if wood then BoxArt.Wood.stripH else L.stripH
	body.Transparency = 1
	body.CastShadow = false
	local added: { BasePart } = {}
	local function add(p: Part): Part
		table.insert(added, p)
		return p
	end

	-- The floor, in the accent colour, a hair proud of the box all round.
	local base = add(
		plate(
			parent,
			body,
			"Base",
			Vector3.new(W + 2 * L.edge, floor, D + 2 * L.edge),
			Vector3.new(0, -H / 2 + floor / 2, 0),
			if wood then BoxArt.Wood.base else accent,
			if wood then Enum.Material.Wood else Enum.Material.SmoothPlastic
		)
	)
	if spec.tier and spec.tier ~= "" then
		write(base, Enum.NormalId.Front, spec.tier, if wood then BoxArt.Wood.ink else ink, Enum.Font.GothamBold)
	end

	-- The walls: dark, from the floor to the top, flush with the box. The
	-- aisle side has a window instead of a wall.
	local wallH = H - floor
	local wallY = -H / 2 + floor + wallH / 2
	local windowSide = spec.side
	for _, sign in ipairs({ -1, 1 }) do
		local isAisle = (sign == -1 and windowSide == "Left") or (sign == 1 and windowSide == "Right")
		if not isAisle then
			add(
				plate(
					parent,
					body,
					if sign == -1 then "Left" else "Right",
					Vector3.new(t, wallH, D),
					Vector3.new(sign * (W / 2 - t / 2), wallY, 0),
					wallColor,
					Enum.Material.Cardboard
				)
			)
		end
	end
	add(
		plate(
			parent,
			body,
			"Back",
			Vector3.new(W - 2 * t, wallH, t),
			Vector3.new(0, wallY, D / 2 - t / 2),
			wallColor,
			Enum.Material.Cardboard
		)
	)

	-- The front face: between the walls, from the floor to the name strip,
	-- its outer face proud of the walls' front edge by `proud`.
	local openW = W - 2 * t
	local frontH = wallH - stripH
	local frontY = -H / 2 + floor + frontH / 2
	local front = add(
		plate(
			parent,
			body,
			"Window",
			Vector3.new(if windowSide == nil then openW else W - t, frontH, L.pane),
			Vector3.new(
				if windowSide == "Left" then -t / 2 elseif windowSide == "Right" then t / 2 else 0,
				frontY,
				-(D / 2 + L.proud + L.pane / 2)
			),
			wallColor,
			Enum.Material.Cardboard
		)
	)
	kraft(front)

	-- The lid: over the whole opening, from the front edge to the back wall.
	local topW = if windowSide == nil then openW else W - t
	local top = add(
		plate(
			parent,
			body,
			"WindowTop",
			Vector3.new(topW, L.pane, D - t),
			Vector3.new(
				if windowSide == "Left" then -t / 2 elseif windowSide == "Right" then t / 2 else 0,
				H / 2 + L.proud + L.pane / 2,
				-t / 2
			),
			wallColor,
			Enum.Material.Cardboard
		)
	)
	kraft(top)
	-- The tape: a cream strip along the lid, front to back.
	add(
		plate(
			parent,
			body,
			"Tape",
			Vector3.new(math.min(W * L.tape, L.tapeMax), L.pane / 2, D - t),
			Vector3.new(0, H / 2 + L.proud + L.pane + L.proud + L.pane / 4, -t / 2),
			Palette.SignCream,
			Enum.Material.SmoothPlastic
		)
	)

	if windowSide == "Left" or windowSide == "Right" then
		local sign = if windowSide == "Right" then 1 else -1
		local side = add(
			plate(
				parent,
				body,
				"SideWindow",
				Vector3.new(L.pane, frontH, D - t),
				Vector3.new(sign * (W / 2 + L.proud + L.pane / 2), frontY, -t / 2),
				wallColor,
				Enum.Material.Cardboard
			)
		)
		kraft(side)
	end

	-- The name strip: the accent band across the top of the front.
	local strip = add(
		plate(
			parent,
			body,
			"Strip",
			Vector3.new(if wood then W * BoxArt.Wood.cardShare else W, stripH, L.stripProud),
			Vector3.new(0, H / 2 - stripH / 2, -(D / 2 + L.stripProud / 2)),
			if wood then (spec.cardColor or BoxArt.Wood.card) else Palette.SignCream,
			if wood then Enum.Material.Wood else Enum.Material.SmoothPlastic
		)
	)
	write(
		strip,
		Enum.NormalId.Front,
		spec.name,
		if wood then BoxArt.Wood.ink else Palette.SignInk,
		Enum.Font.FredokaOne
	)

	-- A brass plate under the name band, on the left. It used to sit on
	-- the band and covered the name.
	local logoT = 0.05
	local logoH = 0.3
	local gap = 0.06
	local stripFront = -(D / 2 + L.stripProud)
	local stripBottom = H / 2 - stripH
	add(plate(
		parent,
		body,
		"Logo",
		Vector3.new(0.6, logoH, logoT),
		Vector3.new(-W / 2 + 0.55, stripBottom - gap - logoH / 2, stripFront - 0.02 - logoT / 2),
		Color3.fromHex("#C9A24A"), -- Brass
		Enum.Material.Metal
	))

	-- The price tag, opposite the brass plate: a cream plate printing the item's real price
	-- (the caller passes the price the shop charges). Boxes are shared, so the server
	-- builds the text and the client colours it for the viewer (BoxArt.PriceTagTag).
	local tagSize = L.tag
	local priceTag = add(
		plate(
			parent,
			body,
			"PriceTag",
			tagSize,
			Vector3.new(
				W / 2 - L.tagInset - tagSize.X / 2,
				stripBottom - gap - tagSize.Y / 2,
				stripFront - 0.02 - tagSize.Z / 2
			),
			Palette.SignCream,
			Enum.Material.SmoothPlastic
		)
	)
	if spec.price ~= nil then
		printPrice(priceTag, spec.price)
	end

	-- The item itself, scaled to fit with the margin, standing on the floor.
	local contents = Instance.new("Model")
	contents.Name = "Contents"
	local kind = if gold then "Robux" else spec.kind
	local itemId = spec.itemId or ""
	local display = ItemModel.Get(kind, itemId)
	local scale = ItemBox.For(kind, itemId).scale
	local m = BoxSize.Margin
	local ext = display.extent
	if ext.X > 0 and ext.Y > 0 and ext.Z > 0 then
		scale = math.min(scale, (W - 2 * m) / ext.X, (H - m - floor) / ext.Y, (D - 2 * m) / ext.Z)
	end
	local inner = ext * scale
	local at = body.CFrame * CFrame.new(BoxSize.ItemOffset(size, inner))
	-- With a model slot that has a mesh the box is sized for the MODEL (ItemModel), and the
	-- part-built copy, which stands only until the mesh lands, is fitted inside it and set on
	-- the floor on its own.
	local slot = display.slot
	local meshed = slot ~= nil and StoreModelSlots.HasMesh(slot)
	local partScale, partAt = scale, at
	if meshed and display.shown.X > 0 and display.shown.Y > 0 and display.shown.Z > 0 then
		local shown = display.shown
		partScale = math.min(scale, inner.X / shown.X, inner.Y / shown.Y, inner.Z / shown.Z)
		partAt = at * CFrame.new(0, (shown.Y * partScale - inner.Y) / 2, 0)
	end
	local parts = ItemModel.Place(display, contents, partAt, partScale)
	for _, p in ipairs(parts) do
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Weld"
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
		table.insert(added, p)
	end
	contents.Parent = parent
	-- An item with a model slot (Flashlight, Lantern, Wood Sign, Shed Blueprint) shows its real model
	-- here once one is set; until then (meshId 0) the part-built copy stays.
	local hearthSlot = ModelSlots.For(kind, itemId)
	if hearthSlot then
		ModelSlots.Dress(contents, hearthSlot, at, "display", { scale = scale, weldTo = body, remove = parts })
	end
	-- The item's own model, when its slot has a mesh (StoreModelSlots): the part-built
	-- copy above stands until the mesh is there, then it is swapped for the mesh
	-- (never waits, never errors; an unset or failed id leaves the copy).
	if meshed and slot ~= nil then
		local frame = at * CFrame.new(0, -inner.Y / 2, 0)
		local made = StoreModelArt.Dress(contents, function()
			return StoreModelArt.Build(slot, frame, {
				parent = contents,
				limit = ext,
				scale = scale,
				anchored = body.Anchored,
				weldTo = body,
			})
		end, parts)
		if made ~= nil then
			for _, old in ipairs(parts) do
				local at_ = table.find(added, old)
				if at_ then
					table.remove(added, at_)
				end
			end
			for _, mesh in ipairs(made) do
				table.insert(added, mesh)
			end
		end
	end
	return added
end

-- Opens a box: its item, faces and tape are gone, the walls, floor and
-- strip stay (an open box). Safe to call twice. The body stays too, so the
-- box still collides, is still aimed at and carried.
function BoxArt.Open(model: Instance)
	local contents = model:FindFirstChild("Contents")
	if contents then
		contents:Destroy()
	end
	for _, name in ipairs({ "Window", "WindowTop", "SideWindow", "Tape" }) do
		local window = model:FindFirstChild(name)
		if window then
			window:Destroy()
		end
	end
	model:SetAttribute("Open", true)
end

-- Which side of a box faces the aisle, from where it stands: the east
-- (Right, +X) face when the box is on the west side of the shop, and the
-- west (Left) face on the east side. nil in the middle.
function BoxArt.AisleSide(x: number): string?
	if x < -1 then
		return "Right"
	elseif x > 1 then
		return "Left"
	end
	return nil
end

return BoxArt
