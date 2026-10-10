--!strict
-- BoxArt: the look of a shop box, after Lumber Tycoon 2: a dark, near-black
-- solid box with a big glass window on its front and top, and the REAL item
-- seen through it. Pure code (Instance.new and datatypes only), so the game
-- and the previews build the same box.
--
-- The box (front faces -Z), in at most BoxLogic.BoxPartCap parts:
--   Box         the body BoxService makes: the collision, the hover and
--               grab target, the carried assembly. Invisible (Transparency 1):
--               the dark walls below are what you see, so the window can show
--               what is inside.
--   Base        the floor, in the item's ACCENT colour, a hair wider than the
--               box all round (the coloured edge), with the tier line on its
--               front when the item has tiers (a sawmill, a planer)
--   Back, Left, Right   the dark charcoal walls
--   Window      the glass on the front, and WindowTop the glass on the top
--               (Material Glass, see-through, collides like the box)
--   SideWindow  a third window on the side that faces the aisle, in place of
--               that side's wall, when the box stands on a shelf
--   Strip       the name band across the top of the front, in the accent
--               colour. No price is printed: the price shows in a tag when
--               you aim at the box (Shared/HoverTag)
--   Contents    a Model of the item itself, scaled to fit with a margin
--               (ItemModel: low-detail copy, at most ModelBudget parts)
-- Everything but the body is welded to it, never more massive than the box
-- (Massless), and only the walls and windows can be touched; the contents
-- are decor that collides with nothing, answers no raycast and weighs
-- nothing, so a carried, dropped or loaded box behaves exactly as before.
-- No two visible faces share a plane: the windows stand WindowProud off the
-- walls and the box.

local BoxLook = require(script.Parent.Parent.BoxLook)
local BoxSize = require(script.Parent.Parent.BoxSize)
local ItemBox = require(script.Parent.Parent.ItemBox)
local ItemModel = require(script.Parent.ItemModel)
local Kit = require(script.Parent.Kit)
local RobuxBoxArt = require(script.Parent.RobuxBoxArt)

local BoxArt = {}

export type Spec = {
	name: string, -- shown on the strip
	tier: string?, -- a second line (a sawmill's "MILL, TIER 3 OF 5"), on the base's front
	kind: string, -- the item kind: Axe, Sawmill, Machine, Blueprint, Gear, Cosmetic, Truck, Trailer, Robux
	itemId: string?, -- the item, for its model and its accent
	color: Color3?, -- the item's own colour (only a fallback accent)
	gold: boolean?, -- a Robux box: RobuxBoxArt's open crate of coins (Lane P)
	robuxKey: string?, -- the Robux item's key (its coin pile)
	side: string?, -- "Left" | "Right": the side facing the aisle gets a window too
}

BoxArt.Charcoal = BoxLook.Charcoal
BoxArt.Categories = BoxLook.Categories
BoxArt.DefaultCategory = BoxLook.Default

-- Proportions of the box, in studs.
BoxArt.Layout = {
	wall = 0.18, -- thickness of the dark walls
	edge = 0.1, -- the base's flange past the box: the accent band, all round
	pane = 0.05, -- thickness of a glass pane
	proud = 0.03, -- how far a window stands off the walls (and the box): no coplanar faces
	stripH = 0.5, -- height of the name strip (it sits in the top margin)
	stripProud = 0.1, -- the accent band, 0.1 deep off the front
	tierH = 0.3, -- height of the tier line on the base's front
	glassTransparency = 0.5,
	glassColor = Color3.fromRGB(150, 192, 212),
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

-- Glass: collides like the box (so it cannot be walked through), can be aimed
-- at and grabbed through, never touched.
local function glassify(p: Part)
	p.Material = Enum.Material.Glass
	p.Color = BoxArt.Layout.glassColor
	p.Transparency = BoxArt.Layout.glassTransparency
	p.Reflectance = 0
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
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
	local wallColor = if gold then BoxLook.CharcoalGold else BoxLook.Charcoal
	local ink = BoxLook.InkOn(accent)
	local t, floor = L.wall, BoxSize.Floor
	local stripH = L.stripH
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
			accent,
			Enum.Material.SmoothPlastic
		)
	)
	if spec.tier and spec.tier ~= "" then
		write(base, Enum.NormalId.Front, spec.tier, ink, Enum.Font.GothamBold)
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
					Enum.Material.SmoothPlastic
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
			Enum.Material.SmoothPlastic
		)
	)

	-- The front window: between the walls, from the floor to the name strip,
	-- its inner face proud of the walls' front edge by `proud`.
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
			BoxLook.Light,
			Enum.Material.Glass
		)
	)
	glassify(front)

	-- The top window: over the whole opening, from the front edge to the back wall.
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
			BoxLook.Light,
			Enum.Material.Glass
		)
	)
	glassify(top)

	if windowSide == "Left" or windowSide == "Right" then
		local sign = if windowSide == "Right" then 1 else -1
		local side = add(
			plate(
				parent,
				body,
				"SideWindow",
				Vector3.new(L.pane, frontH, D - t),
				Vector3.new(sign * (W / 2 + L.proud + L.pane / 2), frontY, -t / 2),
				BoxLook.Light,
				Enum.Material.Glass
			)
		)
		glassify(side)
	end

	-- The name strip: the accent band across the top of the front.
	local strip = add(
		plate(
			parent,
			body,
			"Strip",
			Vector3.new(W, stripH, L.stripProud),
			Vector3.new(0, H / 2 - stripH / 2, -(D / 2 + L.stripProud / 2)),
			accent,
			Enum.Material.SmoothPlastic
		)
	)
	write(strip, Enum.NormalId.Front, spec.name, ink, Enum.Font.FredokaOne)

	-- A brass plate under the name band, on the left. It used to sit on
	-- the band and covered the name. This is the one spare shell part
	-- (BoxLogic.ShellPartCap is 9, and the body plus the walls, windows
	-- and strip already use 8). Four 0.1 corner bevels would need that
	-- cap raised, so they are not separate parts.
	local logoT = 0.05
	local logoH = 0.3
	local gap = 0.06
	local stripFront = -(D / 2 + L.stripProud)
	local stripBottom = H / 2 - L.stripH
	add(plate(
		parent,
		body,
		"Logo",
		Vector3.new(0.6, logoH, logoT),
		Vector3.new(-W / 2 + 0.55, stripBottom - gap - logoH / 2, stripFront - 0.02 - logoT / 2),
		Color3.fromHex("#C9A24A"), -- Brass
		Enum.Material.Metal
	))

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
	local parts = ItemModel.Place(display, contents, at, scale)
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
	return added
end

-- Opens a box: its item and its windows are gone, the dark walls, floor and
-- strip stay (an open box). Safe to call twice. The body stays too, so the
-- box still collides, is still aimed at and carried.
function BoxArt.Open(model: Instance)
	local contents = model:FindFirstChild("Contents")
	if contents then
		contents:Destroy()
	end
	for _, name in ipairs({ "Window", "WindowTop", "SideWindow" }) do
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
