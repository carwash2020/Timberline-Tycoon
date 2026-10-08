--!strict
-- UITheme: the game's look, from the UI spec ("Timberline Tycoon UI",
-- Claude Design). Every screen builds from these parts so they match.
--   * Colours and fonts (GothamBold titles and buttons, Gotham body;
--     Heading, Black and Bold are aliases of those, so older screens
--     keep compiling).
--   * Card(): a frame with a drop edge (a darker strip under it) instead of
--     a shadow, the spec's "chunky" look. An optional skin (UIArt) draws
--     that frame from the uploaded art once its image has loaded: sliced,
--     no corner, and texture() leaves it alone. Until that load, and if it
--     fails, the card stays flat with the same inset. Building never waits.
--   * Button(): a chunky button with named styles (buy, cant, starter,
--     locked, forged, full, use, inuse, bark, blue, amber, skip). Pressed,
--     it drops onto its edge; on a computer it brightens under the mouse.
--     Every press clicks (Click(): SoundData's UIClick, silent with SOUND
--     FX off), as do HitPads and the buttons Clicks() is given.
--   * Screen(): a ScreenGui with a UIScale for the device. A handheld
--     (touch, no keyboard) or a short window (shorter side under
--     CompactEdge) scales down (ScaleFor), so the same offsets don't
--     cover a phone. Computers scale by the screen height / 864 (1.25x
--     at 1080p), consoles / 720 (1.5x on a TV), never below 1x. Screens
--     sit under the top bar and inside the core-UI safe area, or
--     ("device") over the top bar but inside the notch. TopBar(): where
--     the top bar ends.
--   * Margin(): the gap to the screen edge: 12, or the 5% TV-safe area on
--     a console (64 at the sides, 36 at the bottom).
--   * Bottom(): where bottom-centre things (the hint, bars) start: above
--     Roblox's tool hotbar, which the spec didn't allow for.
--   * LeftColumn(): one list down the left (the Field Guide button, the
--     tutorial), under the top bar and under Roblox's chat window when
--     that window is actually open. What's in it stacks instead of
--     overlapping. WatchLeftColumn() hands its frame to whoever needs to
--     keep clear of it (the toasts).
--   * Textures: the spec's wood grain and kraft fibre are tiled images;
--     until they're uploaded (set the ids below) surfaces are flat colour.
--   * Size and Sized(): what a phone needs (a fingertip is 44 px, text at
--     least 14), and each piece's size on a phone and elsewhere, in one
--     table per device, so a test can check every phone size at once.
--     HitPad() gives a small thing (a corner pill) a fingertip-tall hit area.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local UIArt = require(script.Parent.UIArt)

local UITheme = {}

local player = Players.LocalPlayer

UITheme.Colors = {
	-- The timber palette. Owned screens read these by name.
	Panel = Color3.fromHex("#2A1F17"),
	PanelAlt = Color3.fromHex("#1E1B18"),
	Cream = Color3.fromHex("#F3E7C9"),
	Muted = Color3.fromHex("#CDBFA3"),
	Amber = Color3.fromHex("#F2C14E"),
	AmberEdge = Color3.fromHex("#C9A24A"),
	Confirm = Color3.fromHex("#4CC36A"),
	ConfirmEdge = Color3.fromHex("#2F8A48"),
	ConfirmInk = Color3.fromHex("#14240F"),
	Danger = Color3.fromHex("#B23B30"), -- dark enough that cream labels clear 4.5:1
	DangerEdge = Color3.fromHex("#7A2C26"),
	-- A short status line on walnut. The fill above is the button colour;
	-- this brighter red stays readable on a dark panel.
	DangerText = Color3.fromHex("#D9534F"),
	MutedFill = Color3.fromHex("#5A4A3E"),
	Selection = Color3.fromHex("#FFF4C2"),
	-- Older names, kept as light or dark so screens this pass does not
	-- own stay readable (a light card still gets dark ink).
	Ink = Color3.fromHex("#1E1B18"),
	Paper = Color3.fromHex("#F3E7C9"),
	PaperDark = Color3.fromHex("#E4D2AE"),
	Bark = Color3.fromHex("#3E2E22"),
	Green = Color3.fromHex("#2F8A48"),
	GreenEdge = Color3.fromHex("#1E5C30"),
	Blue = Color3.fromHex("#6E5420"),
	BlueEdge = Color3.fromHex("#4A3814"),
	MutedEdge = Color3.fromHex("#3E342C"),
	AmberDeep = Color3.fromHex("#C9A24A"),
	Sky = Color3.fromHex("#1E1B18"),
	SkyEdge = Color3.fromHex("#C9A24A"),
	Ice = Color3.fromHex("#F3E7C9"),
	Locked = Color3.fromHex("#5A4A3E"),
	LockedEdge = Color3.fromHex("#3E342C"),
	Money = Color3.fromHex("#2F8A48"),
}
local C = UITheme.Colors

UITheme.Fonts = {
	Title = Enum.Font.GothamBold, -- titles, names, cash
	Button = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham, -- details and hints
	Heading = Enum.Font.GothamBold, -- alias of Title
	Black = Enum.Font.GothamBold, -- alias of Button (GothamBlack has left the buttons)
	Bold = Enum.Font.GothamBold, -- alias of Title
}

-- Shared shape. A chip (a small pill) uses ChipRadius.
UITheme.Radius = 8
UITheme.ChipRadius = 6
UITheme.Stroke = 2
UITheme.Ring = 4 -- the gamepad selection outline, in px
UITheme.ButtonDrop = 0 -- the old 3px drop edge is the stroke now

-- Tiled texture image ids (rbxassetid://...). Empty = flat colour.
UITheme.Textures = {
	Wood = "", -- bark with horizontal grain, 9-slice 12
	Kraft = "", -- kraft paper fibre, tiled 64
}

export type Style = { fill: Color3, edge: Color3?, ink: Color3, outline: Color3? }

-- primary: amber. confirm: green. danger: red. muted / locked / cant: the
-- dim fill. Older style names point at those four.
UITheme.Styles = {
	primary = { fill = C.Amber, edge = C.AmberEdge, ink = C.ConfirmInk },
	confirm = { fill = C.Confirm, edge = C.ConfirmEdge, ink = C.ConfirmInk },
	danger = { fill = C.Danger, edge = C.DangerEdge, ink = C.Cream },
	muted = { fill = C.MutedFill, edge = C.MutedEdge, ink = C.Muted },
	buy = { fill = C.Confirm, edge = C.ConfirmEdge, ink = C.ConfirmInk },
	cant = { fill = C.MutedFill, edge = C.MutedEdge, ink = C.Muted },
	starter = { fill = C.PanelAlt, edge = nil, ink = C.Cream, outline = C.Amber },
	locked = { fill = C.MutedFill, edge = C.MutedEdge, ink = C.Muted },
	forged = { fill = C.PanelAlt, edge = C.AmberEdge, ink = C.Amber },
	full = { fill = C.Panel, edge = C.AmberEdge, ink = C.Cream },
	use = { fill = C.Amber, edge = C.AmberEdge, ink = C.ConfirmInk },
	inuse = { fill = C.MutedFill, edge = C.MutedEdge, ink = C.Muted },
	bark = { fill = C.Panel, edge = C.AmberEdge, ink = C.Cream },
	blue = { fill = C.Amber, edge = C.AmberEdge, ink = C.ConfirmInk },
	amber = { fill = C.Amber, edge = C.AmberEdge, ink = C.ConfirmInk },
	skip = { fill = C.MutedFill, edge = C.MutedEdge, ink = C.Muted },
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

-- Shorter side under this (px) is a small window. A handheld scales down
-- even when Roblox reports a dense framebuffer taller than this.
UITheme.CompactEdge = 500
UITheme.CompactDivisor = 480 -- short / this, when the short side is under CompactEdge
UITheme.DenseDivisor = 640 -- this / short, on a handheld whose framebuffer is large
UITheme.CompactFloor = 0.7
UITheme.CompactCeil = 0.85

-- True on a touch device with no keyboard, or when the shorter side of
-- `viewport` is under CompactEdge. A desktop (keyboard, a tall window)
-- is false. `viewport` nil means it isn't known yet: only the touch
-- check applies.
function UITheme.IsCompact(viewport: Vector2?, touch: boolean, keyboard: boolean): boolean
	if touch and not keyboard then
		return true
	end
	if viewport then
		local short = math.min(viewport.X, viewport.Y)
		if short > 0 and short < UITheme.CompactEdge then
			return true
		end
	end
	return false
end

function UITheme.Compact(): boolean
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else nil
	return UITheme.IsCompact(viewport, UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
end

-- The UIScale for a screen. `handheld` is touch with no keyboard. Those
-- and short windows shrink (a 390px phone is short/CompactDivisor, about
-- 0.81; a dense framebuffer uses DenseDivisor/short and is clamped, so it
-- is never scaled up the way a monitor is). Otherwise the window height
-- over 864 (720 on a TV), at least 1. A zero viewport that isn't a
-- handheld is 1 (no camera yet).
function UITheme.ScaleFor(viewport: Vector2, handheld: boolean, tenFoot: boolean): number
	local short = math.min(viewport.X, viewport.Y)
	local compact = handheld or (short > 0 and short < UITheme.CompactEdge)
	if compact then
		if short <= 0 then
			return 0.75
		end
		local raw = if short < UITheme.CompactEdge then short / UITheme.CompactDivisor else UITheme.DenseDivisor / short
		return math.clamp(raw, UITheme.CompactFloor, UITheme.CompactCeil)
	end
	if viewport.Y <= 0 then
		return 1
	end
	local base = if tenFoot then 720 else 864
	return math.max(1, viewport.Y / base)
end

---------------------------------------------------------------------------
-- Sizes
---------------------------------------------------------------------------

-- What a phone needs to be usable at arm's length: a fingertip (Apple and
-- Google both ask for 44) and text you can read.
UITheme.Size = {
	Tap = 44, -- the least anything you tap is tall on a phone: its face, or its hit area (HitPad)
	TextMin = 14, -- the smallest text on a phone
	TextBody = 15, -- a phone's body text
	TextButton = 15, -- a phone's button labels (they shrink to fit, down to ButtonMinText)
	ButtonMinText = 12, -- the least a button's label shrinks to on a phone
}
local S = UITheme.Size

-- One piece's size on a device.
export type SizeSpec = {
	text: number, -- its text size (a button's largest: its label shrinks to fit)
	size: Vector2?, -- its box; for a Button, the face without its edge
	hit: number?, -- how tall its transparent hit area is, round a smaller face (HitPad)
	tap: boolean?, -- something you tap or click
}

-- Each piece's size on a phone (UITheme.IsPhone) and everywhere else (a
-- computer, a tablet, a TV: the HUD scales those up with the screen).
-- Both have the same names; the screens read theirs with Sized(name).
UITheme.Sizes = {
	phone = {
		-- HUD
		SideButton = { size = Vector2.new(116, S.Tap), text = S.TextButton, tap = true },
		Hint = { text = S.TextMin },
		LoadChip = { text = S.TextMin },
		Toast = { text = S.TextMin },
		-- The corner (HUD.TopRow, BesideCash, UnderCash): pills 36 tall, each
		-- with a fingertip-tall hit area (the Daily Goals pill grows with
		-- its text from 200).
		Settings = { size = Vector2.new(38, 38), hit = S.Tap, text = 20, tap = true },
		Store = { size = Vector2.new(90, 36), hit = S.Tap, text = S.TextMin, tap = true },
		Clock = { size = Vector2.new(100, 36), text = S.TextMin },
		Pouch = { size = Vector2.new(84, 36), hit = S.Tap, text = S.TextMin, tap = true },
		-- The corner's popups
		DailyHeading = { text = S.TextMin },
		DailyFooter = { text = S.TextMin },
		DailyCountdown = { text = S.TextMin },
		PouchList = { text = S.TextMin },
		SettingsToggle = { size = Vector2.new(170, S.Tap), text = S.TextButton, tap = true },
		-- The shop panel (ShopUI)
		ShopBuy = { size = Vector2.new(96, S.Tap), text = S.TextButton, tap = true },
		ShopClose = { size = Vector2.new(48, 48), text = 20, tap = true },
		ShopSubtitle = { text = S.TextMin },
		ShopOwn = { text = S.TextMin },
		ShopDetail = { text = S.TextMin },
		-- The left column: the Field Guide button, the tutorial (QuestUI)
		FieldGuide = { size = Vector2.new(130, S.Tap), text = S.TextButton, tap = true },
		TrackerStep = { text = S.TextMin },
		Skip = { size = Vector2.new(120, 28), hit = S.Tap, text = S.TextMin, tap = true },
		MurphName = { text = S.TextMin },
		MurphLine = { text = S.TextMin },
		Beacon = { text = S.TextMin }, -- the distance under the arrow
		-- World prompts (PromptUI): on a touch screen the whole card is the button
		PromptObject = { text = S.TextMin },
	} :: { [string]: SizeSpec },
	-- As they always were.
	desktop = {
		SideButton = { size = Vector2.new(110, 40), text = 13, tap = true },
		Hint = { text = 13 },
		LoadChip = { text = 13 },
		Toast = { text = 13 },
		Settings = { size = Vector2.new(38, 38), text = 20, tap = true },
		Store = { size = Vector2.new(90, 30), text = 14, tap = true },
		Clock = { size = Vector2.new(100, 30), text = 13 },
		Pouch = { size = Vector2.new(84, 26), text = 14, tap = true },
		DailyHeading = { text = 13 },
		DailyFooter = { text = 13 },
		DailyCountdown = { text = 12 },
		PouchList = { text = 13 },
		SettingsToggle = { size = Vector2.new(170, 36), text = 14, tap = true },
		ShopBuy = { size = Vector2.new(100, 38), text = 14, tap = true },
		ShopClose = { size = Vector2.new(44, 44), text = 20, tap = true },
		ShopSubtitle = { text = 13 },
		ShopOwn = { text = 12 },
		ShopDetail = { text = 12 },
		FieldGuide = { size = Vector2.new(130, 34), text = 14, tap = true },
		TrackerStep = { text = 13 },
		Skip = { size = Vector2.new(112, 28), text = 11, tap = true },
		MurphName = { text = 12 },
		MurphLine = { text = 13 },
		Beacon = { text = 12 },
		PromptObject = { text = 12 },
	} :: { [string]: SizeSpec },
}

-- `name`'s size on this device (a phone's, or everyone else's).
function UITheme.Sized(name: string): SizeSpec
	local sizes = if UITheme.IsPhone() then UITheme.Sizes.phone else UITheme.Sizes.desktop
	local spec = sizes[name]
	assert(spec, "[UITheme] no size for " .. name)
	return spec
end

-- The bottom of Roblox's top bar, in screen pixels down from the top of
-- the screen: GuiService.TopbarInset, which can read zero-size until the
-- bar is laid out, and meanwhile GetGuiInset's top (the same edge). A
-- "device" screen (Screen) starts at the top of the screen in landscape, so
-- there this divided by Scale() is in its offsets. WatchTopBar() hears of
-- it changing.
function UITheme.TopBar(): number
	local bar = GuiService.TopbarInset.Max.Y
	if bar > 0 then
		return bar
	end
	local inset = GuiService:GetGuiInset()
	return math.max(0, inset.Y)
end

-- Calls `fn` whenever the top bar moves or resizes (or first gets a size).
function UITheme.WatchTopBar(fn: () -> ())
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fn)
end

function UITheme.Margin(): (number, number) -- (side, bottom)
	if GuiService:IsTenFootInterface() then
		return 64, 36
	end
	return 12, 12
end

-- Room for Roblox's tool hotbar (your axes), centred along the bottom.
local HOTBAR = 70

-- How far above the bottom edge the bottom-centre things start.
function UITheme.Bottom(): number
	local _, bottom = UITheme.Margin()
	return bottom + (if UITheme.IsPhone() then 58 else HOTBAR)
end

local userScale = 1
local rescaleFn: (() -> ())? = nil

local function scaleFor(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	local handheld = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return UITheme.ScaleFor(viewport, handheld, GuiService:IsTenFootInterface()) * userScale
end

-- Settings: small 0.85, normal 1, large 1.15, on top of the screen scale.
function UITheme.SetUserScale(multiplier: number)
	userScale = multiplier
	local rescale = rescaleFn
	if rescale then
		rescale()
	end
end

local scales: { UIScale } = {}
local currentScale = 1
local layoutWatchers: { () -> () } = {}
local leftColumn: Frame? = nil
local columnWatchers: { (Frame) -> () } = {} -- waiting for the left column to exist
local chatWatchers: { () -> () } = {} -- told when the chat window moves

local CHAT_CONFIGS = { "ChatWindowConfiguration", "ChatInputBarConfiguration" }

-- One chat config's box in screen pixels (its top-left corner and size),
-- or nil if it isn't showing. Read in a pcall (nil if it errors): a chat
-- property that can't be read must not stop the HUD or the left column.
local function configBox(config: Instance): (Vector2?, Vector2?)
	local ok, pos, size = pcall(function(): (Vector2?, Vector2?)
		local c = config :: any
		if not c.Enabled then
			return nil, nil
		end
		local p = c.AbsolutePosition :: Vector2
		local s = c.AbsoluteSize :: Vector2
		if s.Y <= 0 then
			return nil, nil
		end
		return p, s
	end)
	if ok and typeof(pos) == "Vector2" and typeof(size) == "Vector2" then
		return pos, size
	end
	return nil, nil
end

-- Roblox's chat window and its input bar, as one box in screen pixels
-- (top-left and bottom-right corners), or nil if neither is showing.
function UITheme.ChatBox(): (Vector2?, Vector2?)
	local low: Vector2?, high: Vector2? = nil, nil
	for _, className in ipairs(CHAT_CONFIGS) do
		local config = TextChatService:FindFirstChildOfClass(className)
		local pos, size = nil, nil
		if config then
			pos, size = configBox(config)
		end
		if pos and size then
			local far = pos + size
			low = if low then low:Min(pos) else pos
			high = if high then high:Max(far) else far
		end
	end
	return low, high
end

-- The bottom of Roblox's chat window (and its input bar), in screen
-- pixels; 0 if there's no chat window showing.
local function chatBottom(): number
	local _, high = UITheme.ChatBox()
	return if high then high.Y else 0
end

local function placeLeft()
	local side = UITheme.Margin()
	local scale = math.max(currentScale, 0.01)
	-- Under the top bar (the Roblox menu). Offsets are scaled by the
	-- UIScale; TopBar and the chat box are screen pixels. Never 30% down
	-- the screen: with chat closed that parked the tutorial in the middle
	-- of the view, and on a short window only its end stayed on screen.
	local yPx = math.max(UITheme.TopBar(), 36) + 8
	if not UITheme.IsPhone() then
		local bottom = chatBottom()
		if bottom > yPx then
			yPx = bottom + 10
		end
	end
	local column = leftColumn
	if column then
		column.AnchorPoint = Vector2.zero
		column.Position = UDim2.fromOffset(side, yPx / scale)
	end
end

-- The LocalPlayer's PlayerGui, waited for in short tries: a bare
-- WaitForChild prints an infinite-yield warning if it's slow to come, and
-- the HUD's loading card waits on it.
function UITheme.PlayerGui(): PlayerGui
	local found = player:FindFirstChildOfClass("PlayerGui")
	while not found do
		player:WaitForChild("PlayerGui", 5)
		found = player:FindFirstChildOfClass("PlayerGui")
	end
	return found
end

-- The UIScale every screen has now: offsets times this are screen pixels
-- (so an AbsoluteSize divided by it is in offsets again).
function UITheme.Scale(): number
	return currentScale
end

-- Calls `fn` now and whenever the scale or the viewport changes (a phone
-- rotating, a window resizing): screens that collapse on a handheld
-- (the Field Guide, Daily Goals) listen here.
function UITheme.WatchLayout(fn: () -> ())
	table.insert(layoutWatchers, fn)
	task.spawn(fn)
end

-- Puts `obj` in the left column, under the chat, at `order` (top to
-- bottom), and keeps it there.
function UITheme.LeftColumn(obj: GuiObject, order: number)
	local column = leftColumn
	local made: Frame? = nil
	if not column then
		local gui = UITheme.Screen("LeftColumn")
		local frame = Instance.new("Frame")
		frame.Name = "Column"
		frame.Size = UDim2.new()
		frame.AutomaticSize = Enum.AutomaticSize.XY
		frame.BackgroundTransparency = 1
		UITheme.list(frame, 6)
		frame.Parent = gui
		gui.Parent = player:WaitForChild("PlayerGui")
		leftColumn = frame
		column = frame
		made = frame
	end
	obj.LayoutOrder = order
	obj.Parent = column
	placeLeft()
	if made then
		local watchers = columnWatchers
		columnWatchers = {}
		for _, fn in ipairs(watchers) do
			task.spawn(fn, made)
		end
	end
end

-- Calls `fn` whenever Roblox's chat window moves, resizes, shows or hides
-- (from UITheme.Start on).
function UITheme.WatchChat(fn: () -> ())
	table.insert(chatWatchers, fn)
end

-- Calls `fn` with the left column's frame: now if it's there, or once
-- something is first put in it (the HUD keeps its toasts clear of it).
function UITheme.WatchLeftColumn(fn: (Frame) -> ())
	local column = leftColumn
	if column then
		task.spawn(fn, column)
	else
		table.insert(columnWatchers, fn)
	end
end

-- Which part of the screen a ScreenGui lays out in:
--   * nil: under the top bar and inside the core-UI safe area (clear of
--     the Roblox menu, a notch, the home indicator);
--   * "device": the device's safe area, the top bar's strip included, for
--     screens that keep clear of the bar themselves (TopBar()) or are
--     measured from the true screen centre: the side buttons, the shop,
--     the figure reveal.
export type Insets = "device"

-- DisplayOrder for every screen, in one place so two never tie by accident.
-- Higher draws over lower. Screens that share a number never show together
-- (the three world tools at 6) or never overlap.
UITheme.Layers = {
	SideButtons = 1,
	Corner = 2,
	PlotUI = 2,
	Daily = 3,
	Drag = 4,
	Shop = 5,
	World = 6, -- BlueprintPlacer, ChopSaw, Sawmill
	BuildBar = 7,
	SaveSlot = 8,
	WireTool = 9, -- the wiring mode over the build bar, under the HUD
	Hud = 10,
	Top = 11, -- the cash row
	Badge = 12,
	FigureReveal = 12,
	Settings = 13, -- a modal: over the HUD and the cash row
	Admin = 14, -- the owner menu (AdminUI), over Settings
	QuickMenu = 15, -- the gamepad's quick menu (QuickMenuUI), over the owner menu
	News = 16, -- What's new in V1 (NewsUI), over the quick menu, under the join screens
	Store = 20,
	Dialogue = 30,
	PlotPicker = 80,
	QualityPicker = 90, -- the join screen's Lower / Higher quality choice (QualityPickerUI), over everything
} :: { [string]: number }

-- A ScreenGui for one of the game's screens, scaled for the device.
function UITheme.Screen(name: string, displayOrder: number?, insets: Insets?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	-- IgnoreGuiInset first: ScreenInsets is the newer of the two and has
	-- the last word. Default screens stay inside the core UI (the Roblox
	-- menu, the top bar). Device screens cover the top bar's strip but
	-- not a notch. Neither draws into the unsafe area.
	gui.IgnoreGuiInset = insets == "device"
	gui.ScreenInsets = if insets == "device"
		then Enum.ScreenInsets.DeviceSafeInsets
		else Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
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
	-- A skinned face already reserves its slice margin. Callers that pad
	-- less than that would draw into the bark border, so the margin is a floor.
	local raw = parent:GetAttribute("SkinInset")
	if type(raw) == "number" then
		top = math.max(top, raw)
		right = math.max(right, raw)
		bottom = math.max(bottom, raw)
		left = math.max(left, raw)
	end
	local found = parent:FindFirstChildOfClass("UIPadding")
	local p = if found and found:IsA("UIPadding") then found else Instance.new("UIPadding")
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
	-- A skinned face already carries its art. A tiled texture would cover
	-- the flat paper center the digits and prices sit on.
	if surface:GetAttribute("UIArt") ~= nil then
		return
	end
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

-- A named skin with a real image id, or nil when there isn't one (missing
-- name, or an empty id): Card then builds the flat card below.
local function skinArt(name: string?): UIArt.Skin?
	if name == nil or name == "" then
		return nil
	end
	local art = UIArt.Get(name)
	if art == nil or art.id == "" then
		return nil
	end
	return art
end

-- The flat center's inset for `name`, or 0 when that skin isn't in use.
function UITheme.SkinInset(name: string): number
	local art = skinArt(name)
	return if art then UIArt.Inset(art) else 0
end

-- The sliced look only: image, transparency, slice, corners. Size,
-- AutomaticSize, and padding stay as the card was built (a side shorter
-- than the slice margin is raised up to it, and a longer one is left).
local function paintSkin(face: ImageLabel, skin: string, art: UIArt.Skin)
	face:SetAttribute("UIArt", skin)
	face:SetAttribute("UIArtWanted", skin)
	local inset = UIArt.Inset(art)
	face:SetAttribute("SkinInset", inset)
	face.Image = art.id
	face.ScaleType = Enum.ScaleType.Slice
	face.SliceCenter = art.sliceCenter
	face.SliceScale = art.sliceScale
	face.BackgroundTransparency = 1
	local corner = face:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Destroy()
	end
	local outer = face.Parent
	if outer and outer:IsA("GuiObject") then
		outer.BackgroundTransparency = 1
		local outerCorner = outer:FindFirstChildOfClass("UICorner")
		if outerCorner then
			outerCorner:Destroy()
		end
	end
	local pad = face:FindFirstChildOfClass("UIPadding")
	if pad and pad:IsA("UIPadding") then
		local function lift(current: UDim): UDim
			if current.Offset < inset then
				return UDim.new(current.Scale, inset)
			end
			return current
		end
		pad.PaddingTop = lift(pad.PaddingTop)
		pad.PaddingRight = lift(pad.PaddingRight)
		pad.PaddingBottom = lift(pad.PaddingBottom)
		pad.PaddingLeft = lift(pad.PaddingLeft)
	end
end

-- Opaque fill and corners, on the skin's layout. No image, so a slow or
-- failed load is never a blank slice.
local function paintFlat(outer: Frame, face: ImageLabel, radius: number)
	outer.BackgroundTransparency = 0
	local outerCorner = outer:FindFirstChildOfClass("UICorner")
	if not outerCorner then
		UITheme.corner(outer, radius)
	end
	face.Image = ""
	face.BackgroundTransparency = 0
	face.ScaleType = Enum.ScaleType.Stretch
	face.SliceCenter = Rect.new(0, 0, 0, 0)
	face.SliceScale = 1
	local faceCorner = face:FindFirstChildOfClass("UICorner")
	if not faceCorner then
		UITheme.corner(face, radius)
	end
end

-- Puts `skin` on a face when that image has already loaded. Pending
-- listens and paints later; it does not block and it does not blank a
-- face that is already showing. Failure leaves the face as it is.
-- Swapping Button for ButtonPressed (a prompt held down) calls this again.
function UITheme.ApplySkin(face: ImageLabel, skin: string): boolean
	local art = skinArt(skin)
	if not art then
		return false
	end
	face:SetAttribute("UIArtWanted", skin)
	local fetch = UIArt.Status(art.id)
	if fetch == "Success" then
		paintSkin(face, skin, art)
		return true
	end
	if fetch ~= "Failure" then
		UIArt.Listen(art.id, function(result: UIArt.LoadStatus)
			if result == "Success" and face:GetAttribute("UIArtWanted") == skin then
				paintSkin(face, skin, art)
			end
		end)
	end
	return false
end

-- `outer` is the edge colour and `face` sits on it, `edge` px short, so the
-- edge shows along the bottom. Size and place `outer`; put content in
-- `face`. With `auto`, both grow to fit the face's content. `skin` (a
-- UIArt name) draws the face from that art when the image has loaded:
-- the outer goes fully transparent, the face is sliced with no corner,
-- and the face is padded by the slice margin so content stays on the
-- flat center. Until that load (and if it fails) the same padding and
-- sizes are a flat opaque card, so building never waits on the image.
function UITheme.Card(
	fill: Color3,
	edgeColor: Color3,
	edge: number,
	radius: number,
	auto: boolean?,
	skin: string?
): Card
	local art = skinArt(skin)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = edgeColor
	outer.BorderSizePixel = 0
	local face = Instance.new("ImageLabel") -- an image, so a texture can go on it
	face.Name = "Face"
	face.BackgroundColor3 = fill
	face.BorderSizePixel = 0
	face.Parent = outer
	if art and skin then
		-- The shadow and the border are in the art, so the old drop edge
		-- would only add an empty gap. The face fills the outer. Pending
		-- and Failure use this same layout, with a flat opaque look, so a
		-- later swap never moves Size, AutomaticSize, or the padding.
		local inset = UIArt.Inset(art)
		face:SetAttribute("SkinInset", inset)
		if auto then
			outer.Size = UDim2.new()
			face.Size = UDim2.new()
			outer.AutomaticSize = Enum.AutomaticSize.XY
			face.AutomaticSize = Enum.AutomaticSize.XY
		else
			face.Size = UDim2.fromScale(1, 1)
		end
		UITheme.padding(face, inset, inset, inset, inset)
		local fetch = UIArt.Status(art.id)
		if fetch == "Success" then
			paintSkin(face, skin, art)
		else
			paintFlat(outer, face, radius)
			if fetch ~= "Failure" then
				face:SetAttribute("UIArtWanted", skin)
				UIArt.Listen(art.id, function(result: UIArt.LoadStatus)
					if result == "Success" and face:GetAttribute("UIArtWanted") == skin then
						paintSkin(face, skin, art)
					end
				end)
			end
		end
	else
		UITheme.corner(outer, radius)
		face.Image = ""
		UITheme.corner(face, radius)
		if auto then
			-- AutomaticSize treats Size as a minimum: start from zero so the
			-- card is exactly as big as what's in it.
			outer.Size = UDim2.new()
			face.Size = UDim2.new()
			outer.AutomaticSize = Enum.AutomaticSize.XY
			face.AutomaticSize = Enum.AutomaticSize.XY
			UITheme.padding(outer, 0, 0, edge, 0)
		else
			face.Size = UDim2.new(1, 0, 1, -edge)
		end
	end
	return { outer = outer, face = face }
end

---------------------------------------------------------------------------
-- The click
---------------------------------------------------------------------------

-- Plays the button click (SoundData's UIClick; SoundData.Play stays
-- silent while sound effects are off in Settings). Deferred until the
-- press's handlers have run, so pressing SOUND FX itself is judged by
-- the new setting: off is silent, on clicks. SoundData is required on
-- the first press, so loading this module (the specs do) needs no
-- SoundService.
function UITheme.Click()
	task.defer(function()
		local SoundData = require(ReplicatedStorage.Shared.SoundData)
		SoundData.Play("UIClick")
	end)
end

-- Makes `button` click when it's pressed (Activated: a click, a tap, the
-- gamepad's A on it). For buttons built by hand (the corner's pills); a
-- Button and a HitPad already do. Give a button one source of clicks:
-- one that plays its own sound shouldn't also get this.
function UITheme.Clicks(button: GuiButton)
	button.Activated:Connect(UITheme.Click)
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

local selectionRing: () -> Frame

function UITheme.Button(opts: ButtonOptions): Button
	local radius = opts.radius or UITheme.Radius
	local drop = UITheme.ButtonDrop
	local root = Instance.new("Frame")
	root.Name = opts.name or opts.text
	root.Size = UDim2.fromOffset(opts.size.X, opts.size.Y + drop)
	root.BorderSizePixel = 0
	root.BackgroundTransparency = 1
	UITheme.corner(root, radius)

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -drop)
	face.AutoButtonColor = false
	face.BorderSizePixel = 0
	face.Font = opts.font or UITheme.Fonts.Button
	face.TextSize = opts.textSize or 14
	face.TextScaled = true
	face.Text = opts.text
	face.SelectionImageObject = selectionRing()
	UITheme.corner(face, radius)
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = opts.textSize or 14
	fit.MinTextSize = if UITheme.IsPhone() then S.ButtonMinText else 8
	fit.Parent = face
	UITheme.padding(face, 0, 6, 0, 6)
	local edge = UITheme.stroke(face, C.AmberEdge, UITheme.Stroke)
	face.Parent = root

	local pressed, hovered = false, false
	local button: Button

	local function paint()
		local style = UITheme.Styles[button.style] or UITheme.Styles.cant
		-- Resting fill is the token. Hover and press only nudge it.
		local fill = style.fill
		if pressed then
			fill = brighten(fill, -0.08)
		elseif hovered then
			fill = brighten(fill, 0.06)
		end
		face.BackgroundColor3 = fill
		face.TextColor3 = style.ink
		local rim = style.edge or style.outline
		edge.Enabled = rim ~= nil
		edge.Color = rim or C.AmberEdge
		edge.Thickness = UITheme.Stroke
		if drop > 0 then
			root.BackgroundColor3 = style.edge or style.fill
			root.BackgroundTransparency = if style.edge and not pressed then 0 else 1
			face.Position = UDim2.fromOffset(0, if pressed then drop else 0)
		end
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
	UITheme.Clicks(face)
	paint()
	return button
end

-- A transparent button round `visual` (a corner pill, the tutorial's
-- Skip), `height` tall and as wide as it, so a small face still takes a
-- whole fingertip on a phone. It's drawn under its siblings:
--   * put in a plain button (the sound button), it takes every tap on it,
--     so connect its Activated to what the button does;
--   * put in a Button's root, or a frame round a button (the pouch's
--     slot), the face still takes the taps on itself (and looks pressed),
--     and the pad the ones just around it: connect both.
-- It follows `visual`'s size, so it mustn't go in a `visual` that sizes
-- itself to what's in it (AutomaticSize: the pad would push it wider, and
-- wider). Give such a pill a `holder`: a frame it sits in at the left,
-- the same height; the pad goes in that, beside it (the Daily Goals pill).
-- Wherever the pad goes mustn't have a UIListLayout (the pad would join
-- the list), and its padding must be the same either side. A press on
-- the pad clicks, as one on a Button's face does (only one of them gets
-- any one press: the face is drawn over the pad).
function UITheme.HitPad(visual: GuiObject, height: number, holder: GuiObject?): TextButton
	local pad = Instance.new("TextButton")
	pad.Name = "HitPad"
	if holder then
		pad.AnchorPoint = Vector2.new(0, 0.5) -- over `visual`, at the holder's left
		pad.Position = UDim2.fromScale(0, 0.5)
	else
		pad.AnchorPoint = Vector2.new(0.5, 0.5)
		pad.Position = UDim2.fromScale(0.5, 0.5)
	end
	pad.BackgroundTransparency = 1
	pad.BorderSizePixel = 0
	pad.Text = ""
	pad.AutoButtonColor = false
	pad.Selectable = false -- the gamepad selects the button itself
	pad.ZIndex = 0 -- under its siblings (a Button's face, the pill)
	local function fit()
		local size = visual.AbsoluteSize / currentScale
		pad.Size = UDim2.fromOffset(size.X, math.max(height, size.Y))
	end
	visual:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	UITheme.Clicks(pad)
	pad.Parent = holder or visual
	return pad
end

export type Bar = { outer: Frame, label: TextLabel, row: Frame }

-- A bark bar at the bottom centre, just above the control hint: a line of
-- text and a row of buttons (build mode, placing a blueprint).
function UITheme.Bar(parent: Instance, name: string): Bar
	local card = UITheme.Card(C.Paper, C.AmberEdge, UITheme.Stroke, UITheme.Radius, true, "Panel")
	card.outer.Name = name
	card.outer.AnchorPoint = Vector2.new(0.5, 1)
	card.outer.Position = UDim2.new(0.5, 0, 1, -(UITheme.Bottom() + 30 + 8))
	card.outer.Visible = false
	UITheme.padding(card.face, 8, 10, 10, 10)
	UITheme.list(card.face, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	UITheme.texture(card.face, "Wood", 12)
	local label = UITheme.label(card.face, "", UITheme.Fonts.Bold, 14, C.Ink)
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

local GLYPH_TEXT: { [string]: string } = {
	DPadUp = "▲",
	DPadDown = "▼",
	DPadLeft = "◀",
	DPadRight = "▶",
}

-- A glyph chip's text for the KeyCode named `keyName`, when Roblox has no
-- image for it: an arrow for the D-pad, else the name without "Button"
-- (ButtonB -> "B").
function UITheme.GlyphText(keyName: string): string
	return GLYPH_TEXT[keyName] or (string.gsub(keyName, "^Button", ""))
end

-- A round gamepad glyph for `key`: Roblox's own image for the pad in use,
-- or a cream chip with the letter (or the D-pad's arrow).
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
	chip.Text = UITheme.GlyphText(key.Name)
	UITheme.corner(chip, size)
	UITheme.stroke(chip, C.Ink, 2)
	return chip
end

-- Lets `label` shrink its text to fit its (fixed-size) box, from `max`
-- down to `min`: for headings in a box that a wider face or a longer name
-- could overflow.
function UITheme.fit(label: TextLabel, max: number, min: number): UITextSizeConstraint
	label.TextSize = max
	label.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = max
	fit.MinTextSize = min
	fit.Parent = label
	return fit
end

-- A small speaker drawn from frames (no glyph, no image to upload), about
-- 20 x 16, `color` on a transparent box; centre it in a round button
-- (Settings). A box (the body), a cone (a 45-degree square, its left
-- corner clipped off) and one sound wave (a ring, clipped to its right
-- half). None of it takes input: a press goes to the button under it.
function UITheme.Speaker(color: Color3): Frame
	local icon = Instance.new("Frame")
	icon.Name = "Speaker"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(20, 16)
	icon.BackgroundTransparency = 1
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(1, 5)
	body.Size = UDim2.fromOffset(5, 6)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	UITheme.corner(body, 1)
	body.Parent = icon
	-- The cone: x 5 to 11, widening from the body's 6 to the box's 16.
	local coneClip = Instance.new("Frame")
	coneClip.Name = "Cone"
	coneClip.Position = UDim2.fromOffset(5, 0)
	coneClip.Size = UDim2.fromOffset(6, 16)
	coneClip.BackgroundTransparency = 1
	coneClip.ClipsDescendants = true
	coneClip.Parent = icon
	local cone = Instance.new("Frame")
	cone.Name = "Square"
	cone.AnchorPoint = Vector2.new(0.5, 0.5)
	cone.Position = UDim2.fromScale(1, 0.5) -- centred on the clip's right edge
	-- A diagonal of 2 x 9: 6 tall at the clip's left edge, 18 at its right.
	cone.Size = UDim2.fromOffset(13, 13)
	cone.Rotation = 45
	cone.BackgroundColor3 = color
	cone.BorderSizePixel = 0
	cone.Parent = coneClip
	-- The wave: a ring centred left of its clip, so a ")" shows.
	local waveClip = Instance.new("Frame")
	waveClip.Name = "Wave"
	waveClip.Position = UDim2.fromOffset(12, 0)
	waveClip.Size = UDim2.fromOffset(8, 16)
	waveClip.BackgroundTransparency = 1
	waveClip.ClipsDescendants = true
	waveClip.Parent = icon
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0, -2, 0.5, 0)
	ring.Size = UDim2.fromOffset(12, 12)
	ring.BackgroundTransparency = 1
	UITheme.corner(ring, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = ring
	ring.Parent = waveClip
	return icon
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

-- The gamepad selection ring: Selection (#FFF4C2), Ring px, outside the
-- fill. One image, on the PlayerGui and on every Button, so a second
-- stroke is not stacked on top of it.
function selectionRing(): Frame
	local pad = UITheme.Ring * 2
	local ring = Instance.new("Frame")
	ring.Name = "SelectionRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, pad, 1, pad)
	UITheme.corner(ring, UITheme.Radius + UITheme.Ring)
	local stroke = UITheme.stroke(ring, C.Selection, UITheme.Ring)
	stroke.Transparency = 0
	return ring
end

function UITheme.Start()
	local playerGui = UITheme.PlayerGui()
	playerGui.SelectionImageObject = selectionRing()
	-- Rescale when the window changes size (or a phone rotates).
	local function rescale()
		currentScale = scaleFor()
		for _, scale in ipairs(scales) do
			scale.Scale = currentScale
		end
		placeLeft()
		for _, fn in ipairs(layoutWatchers) do
			task.spawn(fn)
		end
	end
	rescaleFn = rescale
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	-- Follow the chat window as it appears, moves or resizes (each signal
	-- in a pcall, like the reads: one that's missing is skipped).
	local function chatMoved()
		placeLeft()
		for _, fn in ipairs(chatWatchers) do
			task.spawn(fn)
		end
	end
	task.spawn(function()
		for _, className in ipairs(CHAT_CONFIGS) do
			local config = TextChatService:WaitForChild(className, 10)
			if config then
				for _, prop in ipairs({ "AbsolutePosition", "AbsoluteSize", "Enabled" }) do
					pcall(function()
						config:GetPropertyChangedSignal(prop):Connect(chatMoved)
					end)
				end
			end
		end
		chatMoved()
	end)
end

return UITheme
