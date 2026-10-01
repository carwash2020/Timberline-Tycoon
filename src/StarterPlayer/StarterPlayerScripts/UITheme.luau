--!strict
-- UITheme: the game's look, from the UI spec ("Timberline Tycoon UI",
-- Claude Design). Every screen builds from these parts so they match.
--   * Colours and fonts (Fantasy headings, Gotham body).
--   * Card(): a frame with a drop edge (a darker strip under it) instead of
--     a shadow, the spec's "chunky" look.
--   * Button(): a chunky button with named styles (buy, cant, starter,
--     locked, forged, full, use, inuse, bark, blue, amber, skip). Pressed,
--     it drops onto its edge; on a computer it brightens under the mouse.
--   * Screen(): a ScreenGui with a UIScale for the device: 1x on phones,
--     the screen height / 864 on computers (1.25x at 1080p), / 720 on
--     consoles (1.5x on a TV), never below 1x.
--   * Margin(): the gap to the screen edge: 12, or the 5% TV-safe area on
--     a console (64 at the sides, 36 at the bottom).
--   * Textures: the spec's wood grain and kraft fibre are tiled images;
--     until they're uploaded (set the ids below) surfaces are flat colour.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UITheme = {}

local player = Players.LocalPlayer

UITheme.Colors = {
	Ink = Color3.fromHex("#3C2814"),
	Cream = Color3.fromHex("#F5EBD7"),
	Paper = Color3.fromHex("#F0E1C3"),
	PaperDark = Color3.fromHex("#E2CFAA"),
	Bark = Color3.fromHex("#583A22"),
	Green = Color3.fromHex("#4C8C40"),
	GreenEdge = Color3.fromHex("#36672D"),
	Blue = Color3.fromHex("#2F6DB5"),
	BlueEdge = Color3.fromHex("#214E85"),
	Muted = Color3.fromHex("#A09178"),
	MutedEdge = Color3.fromHex("#7E7159"),
	Amber = Color3.fromHex("#FFB840"),
	AmberEdge = Color3.fromHex("#C98A1E"),
	AmberDeep = Color3.fromHex("#D08F1F"),
	Sky = Color3.fromHex("#8FD3F2"),
	SkyEdge = Color3.fromHex("#4E9CC4"),
	Ice = Color3.fromHex("#BFE8FF"),
	Locked = Color3.fromHex("#CDBA93"),
	LockedEdge = Color3.fromHex("#A89670"),
	Money = Color3.fromHex("#3F7A34"),
}
local C = UITheme.Colors

UITheme.Fonts = {
	Heading = Enum.Font.Fantasy, -- titles, names, cash
	Black = Enum.Font.GothamBlack, -- buttons, objectives, stencil-style tags
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium, -- details and hints (the spec's SemiBold)
}

-- Tiled texture image ids (rbxassetid://...). Empty = flat colour.
UITheme.Textures = {
	Wood = "", -- bark with horizontal grain, 9-slice 12
	Kraft = "", -- kraft paper fibre, tiled 64
}

export type Style = { fill: Color3, edge: Color3?, ink: Color3, outline: Color3? }

UITheme.Styles = {
	buy = { fill = C.Green, edge = C.GreenEdge, ink = C.Cream },
	cant = { fill = C.Muted, edge = C.MutedEdge, ink = C.Ink },
	starter = { fill = C.Paper, edge = nil, ink = C.Bark, outline = C.Muted },
	locked = { fill = C.Locked, edge = C.LockedEdge, ink = C.Bark },
	forged = { fill = C.Sky, edge = C.SkyEdge, ink = C.Ink },
	full = { fill = C.Bark, edge = C.Ink, ink = C.PaperDark },
	use = { fill = C.Blue, edge = C.BlueEdge, ink = C.Cream },
	inuse = { fill = C.Muted, edge = C.MutedEdge, ink = C.Ink },
	bark = { fill = C.Bark, edge = C.Ink, ink = C.Cream },
	blue = { fill = C.Blue, edge = C.BlueEdge, ink = C.Cream },
	amber = { fill = C.Amber, edge = C.AmberEdge, ink = C.Ink },
	skip = { fill = C.PaperDark, edge = C.Muted, ink = C.Ink },
} :: { [string]: Style }

---------------------------------------------------------------------------
-- Devices
---------------------------------------------------------------------------

export type Device = "phone" | "desktop" | "console"

-- What the player is using right now (the last input decides between a
-- keyboard, a gamepad and a touch screen).
function UITheme.Device(): Device
	if GuiService:IsTenFootInterface() then
		return "console"
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "phone"
	elseif string.find(last.Name, "Gamepad") then
		return "console"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "phone"
	end
	return "desktop"
end

-- A small touch screen (the spec's phone sizes: smaller buttons).
function UITheme.IsPhone(): boolean
	local camera = workspace.CurrentCamera
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and (camera == nil or camera.ViewportSize.Y < 600)
end

function UITheme.Margin(): (number, number) -- (side, bottom)
	if GuiService:IsTenFootInterface() then
		return 64, 36
	end
	return 12, 12
end

-- Where the left column (the tutorial tracker, then the Field Guide button)
-- starts: high up on a phone (its chat is a button), a third of the way
-- down elsewhere, under Roblox's chat window.
function UITheme.LeftColumnPosition(): UDim2
	local side = UITheme.Margin()
	if UITheme.IsPhone() then
		return UDim2.fromOffset(side, 60) -- the spec's y 96, under the top bar
	end
	return UDim2.new(0, side, 0.3, 0)
end

local function scaleFor(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local base = if GuiService:IsTenFootInterface() then 720 else 864
	if UITheme.IsPhone() then
		return 1
	end
	return math.max(1, camera.ViewportSize.Y / base)
end

local scales: { UIScale } = {}

-- A ScreenGui for one of the game's screens, scaled for the device.
function UITheme.Screen(name: string, displayOrder: number?, ignoreInset: boolean?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.IgnoreGuiInset = ignoreInset == true
	local scale = Instance.new("UIScale")
	scale.Scale = scaleFor()
	scale.Parent = gui
	table.insert(scales, scale)
	return gui
end

---------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------

function UITheme.corner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UITheme.stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UITheme.padding(parent: GuiObject, top: number, right: number, bottom: number, left: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingBottom = UDim.new(0, bottom)
	p.PaddingLeft = UDim.new(0, left)
	p.Parent = parent
	return p
end

function UITheme.list(parent: GuiObject, gap: number, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

-- A text label with the theme's defaults (transparent, left-aligned).
function UITheme.label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- Puts a tiled texture on a surface, if its image is set: as the image of a
-- card's face (an ImageLabel, so list layouts in it aren't disturbed), or
-- as a full-size image behind a plain frame's children.
function UITheme.texture(surface: GuiObject, kind: "Wood" | "Kraft", radius: number)
	local id = UITheme.Textures[kind]
	if id == "" then
		return
	end
	local img: ImageLabel
	if surface:IsA("ImageLabel") then
		img = surface
	else
		img = Instance.new("ImageLabel")
		img.Name = kind
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ZIndex = 0
		UITheme.corner(img, radius)
		img.Parent = surface
	end
	img.Image = id
	img.ScaleType = Enum.ScaleType.Tile
	img.TileSize = UDim2.fromOffset(64, 64)
end

---------------------------------------------------------------------------
-- Cards: a face with a drop edge under it
---------------------------------------------------------------------------

export type Card = { outer: Frame, face: ImageLabel }

-- `outer` is the edge colour and `face` sits on it, `edge` px short, so the
-- edge shows along the bottom. Size and place `outer`; put content in
-- `face`. With `auto`, both grow to fit the face's content.
function UITheme.Card(fill: Color3, edgeColor: Color3, edge: number, radius: number, auto: boolean?): Card
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = edgeColor
	outer.BorderSizePixel = 0
	UITheme.corner(outer, radius)
	local face = Instance.new("ImageLabel") -- an image, so a texture can go on it
	face.Name = "Face"
	face.Image = ""
	face.BackgroundColor3 = fill
	face.BorderSizePixel = 0
	UITheme.corner(face, radius)
	if auto then
		outer.AutomaticSize = Enum.AutomaticSize.XY
		face.AutomaticSize = Enum.AutomaticSize.XY
		UITheme.padding(outer, 0, 0, edge, 0)
	else
		face.Size = UDim2.new(1, 0, 1, -edge)
	end
	face.Parent = outer
	return { outer = outer, face = face }
end

---------------------------------------------------------------------------
-- Chunky buttons
---------------------------------------------------------------------------

export type Button = {
	root: Frame, -- place and parent this
	face: TextButton, -- connect Activated on this
	style: string,
	SetStyle: (self: Button, style: string) -> (),
	SetText: (self: Button, text: string) -> (),
}

local EDGE = 3

local function brighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 + amount), 0, 1))
end

export type ButtonOptions = {
	text: string,
	size: Vector2, -- the face, without the edge
	style: string,
	font: Enum.Font?,
	textSize: number?,
	radius: number?,
	name: string?,
}

function UITheme.Button(opts: ButtonOptions): Button
	local radius = opts.radius or 10
	local root = Instance.new("Frame")
	root.Name = opts.name or opts.text
	root.Size = UDim2.fromOffset(opts.size.X, opts.size.Y + EDGE)
	root.BorderSizePixel = 0
	UITheme.corner(root, radius)

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -EDGE)
	face.AutoButtonColor = false
	face.BorderSizePixel = 0
	face.Font = opts.font or UITheme.Fonts.Black
	face.TextSize = opts.textSize or 14
	face.TextScaled = true
	face.Text = opts.text
	UITheme.corner(face, radius)
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = opts.textSize or 14
	fit.MinTextSize = 8
	fit.Parent = face
	UITheme.padding(face, 0, 6, 0, 6)
	-- The spec's top highlight: a touch lighter along the top edge.
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.12, Color3.new(0.9, 0.9, 0.9)),
		ColorSequenceKeypoint.new(1, Color3.new(0.9, 0.9, 0.9)),
	})
	shine.Parent = face
	local outline = UITheme.stroke(face, C.Muted, 2)
	outline.Enabled = false
	face.Parent = root

	local pressed, hovered = false, false
	local button: Button

	local function paint()
		local style = UITheme.Styles[button.style] or UITheme.Styles.cant
		-- The gradient darkens by 10%, so lift the fill to match the spec.
		local fill = brighten(style.fill, 0.11)
		if pressed then
			fill = brighten(fill, -0.08)
		elseif hovered then
			fill = brighten(fill, 0.06)
		end
		face.BackgroundColor3 = fill
		face.TextColor3 = style.ink
		root.BackgroundColor3 = style.edge or style.fill
		root.BackgroundTransparency = if style.edge and not pressed then 0 else 1
		face.Position = UDim2.fromOffset(0, if pressed then EDGE else 0)
		outline.Enabled = style.outline ~= nil
		outline.Color = style.outline or C.Muted
	end

	button = {
		root = root,
		face = face,
		style = opts.style,
		SetStyle = function(self: Button, style: string)
			if self.style ~= style then
				self.style = style
				paint()
			end
		end,
		SetText = function(_self: Button, text: string)
			face.Text = text
		end,
	}

	face.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed = true
			paint()
		elseif t == Enum.UserInputType.MouseMovement then
			hovered = true
			paint()
		end
	end)
	face.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			hovered = false
		end
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.MouseMovement
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed = false
		end
		paint()
	end)
	face.SelectionLost:Connect(function()
		pressed = false
		paint()
	end)
	paint()
	return button
end

export type Bar = { outer: Frame, label: TextLabel, row: Frame }

-- A bark bar at the bottom centre, just above the control hint: a line of
-- text and a row of buttons (build mode, placing a blueprint).
function UITheme.Bar(parent: Instance, name: string): Bar
	local _, bottom = UITheme.Margin()
	local card = UITheme.Card(C.Bark, C.Ink, 3, 12, true)
	card.outer.Name = name
	card.outer.AnchorPoint = Vector2.new(0.5, 1)
	card.outer.Position = UDim2.new(0.5, 0, 1, -(bottom + 30 + 8))
	card.outer.Visible = false
	UITheme.stroke(card.face, C.Ink, 2)
	UITheme.padding(card.face, 8, 10, 10, 10)
	UITheme.list(card.face, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	UITheme.texture(card.face, "Wood", 12)
	local label = UITheme.label(card.face, "", UITheme.Fonts.Bold, 14, C.Cream)
	label.LayoutOrder = 1
	label.Size = UDim2.fromOffset(320, 20)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.LayoutOrder = 2
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	UITheme.list(row, 8, true)
	row.Parent = card.face
	card.outer.Parent = parent
	return { outer = card.outer, label = label, row = row }
end

-- A round gamepad glyph for `key`: Roblox's own image for the pad in use,
-- or a cream chip with the letter.
function UITheme.Glyph(key: Enum.KeyCode, size: number): GuiObject
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	if ok and type(image) == "string" and image ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "Glyph"
		img.Size = UDim2.fromOffset(size, size)
		img.BackgroundTransparency = 1
		img.Image = image
		return img
	end
	local chip = Instance.new("TextLabel")
	chip.Name = "Glyph"
	chip.Size = UDim2.fromOffset(size, size)
	chip.BackgroundColor3 = C.Cream
	chip.Font = UITheme.Fonts.Black
	chip.TextSize = math.floor(size * 0.55)
	chip.TextColor3 = C.Ink
	chip.Text = string.gsub(key.Name, "^Button", "")
	UITheme.corner(chip, size)
	UITheme.stroke(chip, C.Ink, 2)
	return chip
end

-- Escapes text for a RichText label.
function UITheme.escape(text: string): string
	return (
		string.gsub(text, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

-- The gamepad selection ring: 3 px ink, then 3 px amber (the spec's
-- SelectionImageObject), used for every selected button.
local function selectionRing(): Frame
	local ring = Instance.new("Frame")
	ring.Name = "SelectionRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	UITheme.corner(ring, 12)
	UITheme.stroke(ring, C.Ink, 3)
	local outer = Instance.new("Frame")
	outer.BackgroundTransparency = 1
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, 6, 1, 6)
	UITheme.corner(outer, 14)
	local amber = UITheme.stroke(outer, C.Amber, 3)
	amber.Transparency = 0
	outer.Parent = ring
	return ring
end

function UITheme.Start()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.SelectionImageObject = selectionRing()
	-- Rescale when the window changes size (or a phone rotates).
	local function rescale()
		local s = scaleFor()
		for _, scale in ipairs(scales) do
			scale.Scale = s
		end
	end
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

return UITheme
