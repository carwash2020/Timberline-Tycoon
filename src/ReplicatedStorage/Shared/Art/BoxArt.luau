--!strict
-- BoxArt: the packaged-goods look of a shop box. Pure code (Instance.new and
-- datatypes only), so the game and the previews build the same box.
--
-- The box is a kraft cardboard body with, at most BoxLogic.BoxPartCap (6)
-- parts in all:
--   Box        the body (BoxService makes it: kraft, or gold for a Robux box)
--   Tape       a band over the top and down the front and back, in the
--              item's own colour, so a box reads at a distance
--   Label      a cream paper panel on the front with the item's name
--   Stripe     a band across the top of the label in the category colour
--   Trim       a dark rim round the foot (the corner and edge trim)
--   SideLabel  the same label on the side that faces the aisle (optional)
-- Everything but the body is Kit.decor (no collision, no queries) welded to
-- the body, so a carried box moves as one. Front faces -Z. The price is the
-- BoxService billboard, not part of the art: one price only.

local Kit = require(script.Parent.Kit)

local BoxArt = {}

export type Spec = {
	name: string, -- shown on the label
	kind: string, -- the item kind, for the category stripe
	color: Color3, -- the item's colour, for the tape
	gold: boolean?, -- a Robux box: gold body and gold trim
	side: string?, -- "Left" | "Right": which side also gets a label (the aisle side)
}

BoxArt.Kraft = Color3.fromRGB(200, 160, 107)
BoxArt.KraftDark = Color3.fromRGB(122, 86, 52)
BoxArt.Paper = Color3.fromRGB(246, 238, 218)
BoxArt.Ink = Color3.fromRGB(58, 38, 22)
BoxArt.GoldDark = Color3.fromRGB(150, 108, 28)
BoxArt.GoldInk = Color3.fromRGB(107, 74, 18)

-- One colour per kind of goods. The stripe above the label.
BoxArt.Categories = {
	Axe = Color3.fromRGB(192, 57, 43),
	Sawmill = Color3.fromRGB(217, 130, 43),
	Machine = Color3.fromRGB(226, 185, 59),
	Gear = Color3.fromRGB(46, 139, 122),
	Blueprint = Color3.fromRGB(59, 111, 182),
	Cosmetic = Color3.fromRGB(142, 91, 181),
	Robux = Color3.fromRGB(107, 74, 18),
	Truck = Color3.fromRGB(60, 125, 74),
	Trailer = Color3.fromRGB(95, 122, 140),
} :: { [string]: Color3 }

BoxArt.DefaultCategory = Color3.fromRGB(110, 110, 110)

-- Proportions of the box. Fractions of its size unless noted.
BoxArt.Layout = {
	tapeWidth = 0.16, -- of W
	tapeProud = 0.04, -- studs the tape stands off the body
	labelW = 0.64, -- of W (or D on a side)
	labelH = 0.42, -- of H
	labelY = -0.08, -- of H, from the middle
	labelThick = 0.06, -- studs
	stripeH = 0.1, -- of H
	trimH = 0.1, -- of H
	trimProud = 0.07, -- studs
	pixelsPerStud = 40,
}

function BoxArt.CategoryColor(kind: string): Color3
	return BoxArt.Categories[kind] or BoxArt.DefaultCategory
end

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

local function writeName(part: BasePart, face: Enum.NormalId, text: string, ink: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NameMark"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BoxArt.Layout.pixelsPerStud
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = ink
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.Parent = label
end

-- Dresses `body` (a Part whose size is the box) in the packaging. Returns
-- the parts added. The body's colour and material are set here too.
function BoxArt.Dress(parent: Instance, body: BasePart, spec: Spec): { Part }
	local L = BoxArt.Layout
	local size = body.Size
	local gold = spec.gold == true
	body.Color = if gold then Color3.fromRGB(227, 183, 60) else BoxArt.Kraft
	body.Material = if gold then Enum.Material.Metal else Enum.Material.SmoothPlastic
	local ink = if gold then BoxArt.GoldInk else BoxArt.Ink
	local trimColor = if gold then BoxArt.GoldDark else BoxArt.KraftDark
	local tapeColor = if gold then BoxArt.GoldDark else spec.color
	local stripeColor = BoxArt.CategoryColor(spec.kind)
	local added: { Part } = {}

	local tape = plate(
		parent,
		body,
		"Tape",
		Vector3.new(size.X * L.tapeWidth, size.Y + 2 * L.tapeProud, size.Z + 2 * L.tapeProud),
		Vector3.zero,
		tapeColor,
		Enum.Material.SmoothPlastic
	)
	table.insert(added, tape)

	local labelW = size.X * L.labelW
	local labelH = size.Y * L.labelH
	local labelY = size.Y * L.labelY
	local frontZ = -(size.Z / 2 + L.tapeProud + L.labelThick / 2)
	local label = plate(
		parent,
		body,
		"Label",
		Vector3.new(labelW, labelH, L.labelThick),
		Vector3.new(0, labelY, frontZ),
		BoxArt.Paper,
		Enum.Material.SmoothPlastic
	)
	writeName(label, Enum.NormalId.Front, spec.name, ink)
	table.insert(added, label)

	local stripeH = size.Y * L.stripeH
	local stripe = plate(
		parent,
		body,
		"Stripe",
		Vector3.new(labelW, stripeH, L.labelThick + 0.02),
		Vector3.new(0, labelY + labelH / 2 + stripeH / 2, frontZ),
		stripeColor,
		Enum.Material.SmoothPlastic
	)
	table.insert(added, stripe)

	local trimH = size.Y * L.trimH
	local trim = plate(
		parent,
		body,
		"Trim",
		Vector3.new(size.X + 2 * L.trimProud, trimH, size.Z + 2 * L.trimProud),
		Vector3.new(0, -size.Y / 2 + trimH / 2, 0),
		trimColor,
		Enum.Material.SmoothPlastic
	)
	table.insert(added, trim)

	local side = spec.side
	if side == "Left" or side == "Right" then
		local sign = if side == "Right" then 1 else -1
		local sideLabel = plate(
			parent,
			body,
			"SideLabel",
			Vector3.new(L.labelThick, labelH, size.Z * L.labelW),
			Vector3.new(sign * (size.X / 2 + L.tapeProud + L.labelThick / 2), labelY, 0),
			BoxArt.Paper,
			Enum.Material.SmoothPlastic
		)
		writeName(sideLabel, if side == "Right" then Enum.NormalId.Right else Enum.NormalId.Left, spec.name, ink)
		table.insert(added, sideLabel)
	end
	return added
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
