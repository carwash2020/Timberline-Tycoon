--!strict
-- HUD: the always-on screen (UI spec 01, look from UITheme).
--   * Cash plaque top right, below Roblox's top bar (Roblox's player list,
--     which would cover it, is off: GameConfig). At the wallet cap it turns
--     amber and reads MAX.
--   * Toasts: short messages from the server (Notify) or other controllers,
--     up for as long as they take to read (2.5 to 6 s; a confirm 6 s:
--     HudRules.ToastSeconds), newest on top (older ones fade back), in a
--     lane that keeps clear of the top-right corner and the left column
--     (HudLayout.ToastLane):
--     centred at the top between them on a computer or a TV, up to three;
--     on a phone, where there's no room between them, under the tutorial
--     tracker at its width, up to two. Amounts of money show in green.
--     While a panel is open over the game (the shop: HUD.SetModal), they
--     move inside its bottom edge instead, stacking upward, clear of its
--     title and its Buy buttons; one at a time on a phone, and there
--     above Roblox's tool hotbar (HudLayout.ModalLane).
--   * A one-line control hint at the bottom (above Roblox's tool hotbar),
--     worded for the device in use and for what you're doing
--     (Shared/HintLogic): chopping, carrying logs (the CarriedLogs
--     attribute), driving (Humanoid.Seated in a VehicleSeat), standing in
--     the sell zone with something to sell there (as the Sell prompt
--     counts it: HintLogic.SellCount), or a mode a controller sets
--     (HUD.SetHintContext: placing a blueprint). It hides while a panel is
--     open (HUD.SetModal).
--   * The load chip on the same line, left of the hint: a log, "Hands 1/2"
--     and, with a truck, "Bed 4/6" (amber and "Bed full" once it's full),
--     from the CarriedLogs, BedCount and BedCapacity attributes
--     (HudRules.LoadChip); the log bumps when they change. It shows only
--     while there are logs in your hands or your bed. The line stays clear
--     of a phone's jump button (HudLayout.BottomRow), and hides with the
--     hint.
--   * Under the v2 core loop (CoreLoop.V2()) there are no hands to count
--     (HudRules.ShowsHands): the chip shows the piece you're dragging (a
--     Wood model whose HeldBy is you: "Oak log · 26 u³ · $39"), else your
--     bed's load once TruckLoad publishes the BedVolume and BedValue
--     attributes (HudRules.LoadChipV2). The hint follows
--     HintLogic.ContextForV2 for what's known so far: driving (backing up
--     to the pad once the bed has a volume), dragging, an axe in hand
--     (an AxeId tool in the character), else how to drag.
--   * The side buttons: a column on the right (Truck to lot, Hammer, ...)
--     that other controllers add to with HUD.SideButton. It ends above a
--     phone's jump button and grows up to just under the corner's second
--     line (the Daily Goals button); what doesn't fit there starts another
--     column to its left. On a phone they're a fingertip tall (UITheme's
--     phone sizes, as the hint, the chip and the toasts' 14 px text are).
--     On a gamepad each shows its button glyph, and that button presses it
--     (unless a world prompt is using the same one).
--   * A loading card, under the ReplicatedFirst one (LoadingScreen, which
--     gives up after 30 s) so it shows if the wait runs longer: "Building
--     the world..." until the server's Remotes folder exists (GameServer
--     makes it once the map is built), then "Loading your save..." until
--     the server says the profile is ready (HudRules.LoadingText). HUD.Start
--     puts it up before anything that waits, and waits for the Remotes in
--     short tries, so a slow build never prints an infinite-yield warning.
--   * Money in or out pops beside the plaque ("+$1,250") and the plaque
--     counts up to the new amount.
--   * The top-right corner, laid out by size (UIListLayouts), so nothing
--     in it overlaps on a phone, a monitor or a TV:
--       [STORE][clock]        [♪][cash plaque]   HUD.BesideCash | HUD.TopRow
--                  [pouch][DAILY GOALS 1/3]      HUD.UnderCash
--                       [one popup at a time]    HUD.Popup
--     The cash row (HUD.TopRow, which SettingsUI adds its button to) is in
--     its own screen with no insets, in the top bar when it fits and just
--     under it when it doesn't, over the shop; the rest of the corner is in
--     a layer under the HUD. On a phone the clock is in the second line
--     (or hidden: WorldUI).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HintLogic = require(ReplicatedStorage.Shared.HintLogic)
local LoadStages = require(ReplicatedStorage.Shared.LoadStages)
local Net = require(ReplicatedStorage.Shared.Net)
local GamepadNavLogic = require(ReplicatedStorage.Shared.GamepadNavLogic)
local NoticePolicy = require(ReplicatedStorage.Shared.NoticePolicy)
local QuickMenuLogic = require(ReplicatedStorage.Shared.QuickMenuLogic)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local Util = require(ReplicatedStorage.Shared.Util)
local GamepadNav = require(script.Parent.GamepadNav)
local HudLayout = require(script.Parent.HudLayout)
local HudNav = require(script.Parent.HudNav)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local HUD = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local MAX_TOASTS = 3 -- until the lane is placed (HudLayout.ToastLane says how many it holds)
local TOAST_WIDTH = 280 -- a toast's widest
local TOAST_TEXT_INSET = 28 -- its padding either side of the text
local TOAST_LANE_MIN = 240 -- a band narrower than this between the left column and the corner: toasts go under the column
local TOAST_FADE = 0.25
local TOAST_ALPHA = { 0, 0.15, 0.3 } -- newest, then older ones at 85% and 70%
local HINT_POLL = 0.25 -- seconds between sell-zone checks for the hint
local SIDE_GAP = 8 -- between side buttons, and under the corner
local JUMP_CLEARANCE = 24 -- the side buttons end this far above a phone's jump button
local SIDE_BELOW_CENTRE = 44 -- without touch controls, they end this far under the screen's middle
local POPUP_GAP = 6 -- the corner's popups drop this far under its second line
local HINT_MAX = 320 -- the hint's widest (it truncates past this)
local ROW_HEIGHT = 30 -- the hint and the load chip
local ROW_GAP = 8 -- between them, and short of a phone's jump button
local CHIP_POP = 1.4 -- the chip's log grows to this when the load changes, and eases back
local BAR_HALF_WIDTH = 176 -- UITheme.Bar's card (340 wide plus its edge) at the bottom centre
local BAR_HEIGHT = 84 -- and its height (label, a row of buttons, padding)
local REMOTES_WAIT = 5 -- seconds per try for the server's Remotes folder (a timeout: no infinite-yield warning)

type Toast = {
	id: number?, -- NoticePolicy's id for it
	outer: Frame,
	face: ImageLabel,
	label: TextLabel,
	stroke: UIStroke,
	limit: UISizeConstraint, -- the card's width, at most the lane's
	labelLimit: UISizeConstraint, -- and its text's
}

type Chip = {
	frame: Frame,
	hands: TextLabel,
	dot: TextLabel,
	bed: TextLabel,
	pop: UIScale, -- on the log, for the bump
}

type Side = {
	button: UITheme.Button,
	key: Enum.KeyCode?,
	hint: Enum.KeyCode?, -- a button that opens it elsewhere (the quick menu's): only its glyph shows
	glyph: GuiObject?,
	onPress: () -> (),
}

local cashFace: ImageLabel? = nil
local cashInner: Frame? = nil
local cashLabel: TextLabel? = nil
local cashOuter: Frame? = nil
local cashGlow: UIStroke? = nil
local cashMin: UISizeConstraint? = nil
local cashInnerMin: UISizeConstraint? = nil
local cashLabelMin: UISizeConstraint? = nil
local cashPops: Frame? = nil -- a zero-size spot at the row's left end the pops float from
local cashShown: NumberValue? = nil -- what the plaque shows; tweens toward the real amount
local cashTarget: number? = nil -- the real amount (nil until the first update)
local toastStack: Frame? = nil
local toastList: UIListLayout? = nil
local toasts: { Toast } = {}
local toastOrder = 0
local toastWidth = TOAST_WIDTH -- the lane's width
local maxToasts = MAX_TOASTS -- how many the lane holds
local laneQueued = false
local modalRect: HudLayout.Rect? = nil -- an open panel (HUD.SetModal), in screen pixels
local hudGui: ScreenGui? = nil
local leftColumn: Frame? = nil -- UITheme's left column (the tracker), once it exists
local hintLabel: TextLabel? = nil
local hintQuiet = false -- a control you have learned: its hint is not shown
local hintGrabs = 0 -- grabs this session (HUD.NoteGrab)
local dragHintSince: number? = nil -- when the idle drag line first showed this session
local syncHint: (() -> ())? = nil -- refreshModal, once it exists
local hintLimit: UISizeConstraint? = nil -- the hint's widest right now (placeRow)
local bottomRow: Frame? = nil -- the load chip and the hint, side by side
local rowQueued = false
local chip: Chip? = nil
local chipText: string? = nil -- what the chip said last time it showed (a change bumps it)
local hintForced: HintLogic.Context? = nil -- a controller's mode (HUD.SetHintContext)
local hintState: HintLogic.State = { driving = false, inSellZone = false, carrying = false, sellable = 0 }
-- The v2 loop's sources (watchV2: only under CoreLoop.V2()).
local v2Watching = false
local heldPiece: Model? = nil -- the Wood model whose HeldBy is you
-- What the axe points at (CutController.PointingFacts): a loose piece,
-- wood too hard for the axe, and a thick face.
local pointingWood, pointingHard, pointingThick = false, false, false
local woodConns: { [Model]: RBXScriptConnection } = {}
local axeOut = false -- an axe tool in the character
local nearPad = false -- your truck by the sell pad (HintLogic.NearPad)
local sideGui: ScreenGui? = nil
local sideColumn: Frame? = nil -- a zero-size corner the side buttons stack up and left from
local sides: { Side } = {}
local arrangeQueued = false
local jumpButton: GuiObject? = nil -- a phone's jump button (Roblox's touch controls), once there is one
local shelf: Frame? = nil -- the corner's two lines
local besideCash: Frame? = nil
local underCash: Frame? = nil
local popups: { GuiObject } = {}
local popupFirst: { [GuiObject]: GuiObject } = {} -- a popup's first button, which a gamepad selects on opening it
local popupCloseBound = false -- B closes the open popup (HUD.Popup)
type PadBinding = {
	name: string,
	key: Enum.KeyCode,
	handle: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult,
}
local padBindings: { PadBinding } = {} -- the D-pad's shortcuts (HUD.PadShortcut)
local padBound = false -- whether they're bound right now (not while a menu has the selection)

local loadingCard: Frame? = nil
local loadingLabel: TextLabel? = nil
local loadingFill: Frame? = nil -- the loading card's bar (Shared/LoadStages)
local shownPrompts: { [ProximityPrompt]: boolean } = {}

---------------------------------------------------------------------------
-- Cash
---------------------------------------------------------------------------

-- What the plaque reads: formatCash, or MAX at the wallet cap.
function HUD.CashText(amount: number): string
	if amount >= GameConfig.CashCap then
		return "MAX"
	end
	return Util.formatCash(math.floor(amount + 0.5))
end

local function showCash(amount: number)
	local label = cashLabel
	if not label then
		return
	end
	local full = amount >= GameConfig.CashCap
	label.Text = HUD.CashText(amount)
	label.TextXAlignment = if full then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
end

-- "+$1,250" floats up beside the plaque and fades (dark for spending).
local function popDelta(delta: number)
	local spot = cashPops
	if not spot then
		return
	end
	local gain = delta > 0
	local text = (if gain then "+" else "-") .. Util.formatCash(math.abs(delta))
	local pop = UITheme.label(spot, text, F.Heading, if gain then 24 else 20, if gain then C.Amber else C.Ink)
	pop.Name = "CashPop"
	pop.AnchorPoint = Vector2.new(1, 0.5)
	pop.AutomaticSize = Enum.AutomaticSize.XY
	pop.Size = UDim2.fromOffset(0, 0)
	pop.TextXAlignment = Enum.TextXAlignment.Right
	local start = UDim2.fromOffset(-4, 0)
	pop.Position = start
	local stroke = UITheme.stroke(pop, if gain then C.Ink else C.Cream, 2)
	local rise = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(pop, rise, { Position = start + UDim2.fromOffset(0, if gain then -16 else 16) }):Play()
	local fade = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.75)
	TweenService:Create(pop, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(1.4, function()
		pop:Destroy()
	end)
	-- The paper flashes green for money coming in (no size change, so the
	-- row doesn't jiggle).
	local inner = cashInner
	if gain and inner and (cashTarget or 0) < GameConfig.CashCap then
		inner.BackgroundColor3 = Color3.fromHex("#CFE8B8")
		TweenService:Create(inner, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { BackgroundColor3 = C.Paper }):Play()
	end
end

local function setCash(amount: number)
	local face, inner, glow, shown = cashFace, cashInner, cashGlow, cashShown
	if not face or not inner or not glow or not shown then
		return
	end
	local full = amount >= GameConfig.CashCap
	face.BackgroundColor3 = if full then C.AmberDeep else C.Bark
	inner.BackgroundColor3 = if full then C.Amber else C.Paper
	glow.Enabled = full
	local before = cashTarget
	cashTarget = amount
	if before == nil then
		-- The first value is the save loading in: no fanfare.
		shown.Value = amount
		showCash(amount)
		return
	end
	local delta = amount - before
	if delta == 0 then
		return -- the attribute and the remote both report every change
	end
	popDelta(delta)
	-- Count up (or down) to the new amount.
	local seconds = math.clamp(math.abs(delta) / 4000, 0.25, 0.9)
	TweenService:Create(shown, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = amount,
	}):Play()
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------

-- Money in a message ("$1,250") shows in green.
local function richToast(message: string): string
	return (
		string.gsub(UITheme.escape(message), "%$[%d,]+", function(money: string)
			return string.format('<font color="#3F7A34" weight="heavy">%s</font>', money)
		end)
	)
end

local function setToastAlpha(toast: Toast, alpha: number)
	toast.outer.BackgroundTransparency = alpha
	toast.face.BackgroundTransparency = alpha
	toast.label.TextTransparency = alpha
	toast.stroke.Transparency = alpha
end

local function restack()
	for i, toast in ipairs(toasts) do
		setToastAlpha(toast, TOAST_ALPHA[i] or 1)
	end
end

local function removeToast(toast: Toast)
	local i = table.find(toasts, toast)
	if i then
		table.remove(toasts, i)
	end
	toast.outer:Destroy()
	restack()
end

local function fitToast(toast: Toast)
	toast.limit.MaxSize = Vector2.new(toastWidth, math.huge)
	toast.labelLimit.MaxSize = Vector2.new(math.max(0, toastWidth - TOAST_TEXT_INSET), math.huge)
end

-- A box in screen pixels (top-left, bottom-right) in `gui`'s offsets.
-- The corner's and the left column's screens mind the top bar inset as
-- the HUD's does; measure from its corner anyway, as the shop does.
local function boxIn(gui: ScreenGui, low: Vector2, high: Vector2): HudLayout.Rect
	local scale = UITheme.Scale()
	local a = (low - gui.AbsolutePosition) / scale
	local b = (high - gui.AbsolutePosition) / scale
	return { left = a.X, top = a.Y, right = b.X, bottom = b.Y }
end

local function rectIn(gui: ScreenGui, obj: GuiObject): HudLayout.Rect
	return boxIn(gui, obj.AbsolutePosition, obj.AbsolutePosition + obj.AbsoluteSize)
end

-- The toasts' lane at the top, clear of the corner and the left column,
-- for their sizes right now (HudLayout.ToastLane).
local function laneAtTop(gui: ScreenGui, corner: Frame, screen: Vector2): HudLayout.Lane
	local column = leftColumn
	local columnRect = if column and column.Parent then rectIn(gui, column) else nil
	-- Off a phone the column hangs under Roblox's chat window: keep the
	-- toasts clear of that too. (On a phone the chat is a button whose
	-- window opens over everything, and the column ignores it.)
	local chatLow, chatHigh = UITheme.ChatBox()
	if chatLow and chatHigh and not UITheme.IsPhone() then
		local chat = boxIn(gui, chatLow, chatHigh)
		columnRect = if columnRect
			then {
				left = math.min(columnRect.left, chat.left),
				top = math.min(columnRect.top, chat.top),
				right = math.max(columnRect.right, chat.right),
				bottom = math.max(columnRect.bottom, chat.bottom),
			}
			else chat
	end
	local _, bottomMargin = UITheme.Margin()
	return HudLayout.ToastLane(
		screen,
		rectIn(gui, corner),
		columnRect,
		TOAST_WIDTH,
		TOAST_LANE_MIN,
		screen.Y - bottomMargin
	)
end

-- Puts the toasts' lane at the top (laneAtTop), or while a panel is open
-- inside its bottom edge (HudLayout.ModalLane), growing upward there.
local function placeToasts()
	laneQueued = false
	local gui, stack, list, corner = hudGui, toastStack, toastList, shelf
	if not gui or not stack or not list or not corner then
		return
	end
	local screen = gui.AbsoluteSize / UITheme.Scale()
	if screen.X <= 0 or screen.Y <= 0 then
		return -- not laid out yet
	end
	local modal = modalRect
	local phone = UITheme.IsPhone()
	local lane = if modal
		then HudLayout.ModalLane(
			boxIn(gui, Vector2.new(modal.left, modal.top), Vector2.new(modal.right, modal.bottom)),
			TOAST_WIDTH,
			TOAST_LANE_MIN,
			phone,
			-- On a phone, above the tool hotbar (which draws over the panel).
			if phone then screen.Y - UITheme.Bottom() else nil
		)
		else laneAtTop(gui, corner, screen)
	toastWidth = lane.right - lane.left
	maxToasts = lane.max
	-- A modal lane's stack hangs from its bottom edge, so newer toasts
	-- (on top) push it up and the older ones stay put.
	stack.AnchorPoint = if lane.modal then Vector2.new(0, 1) else Vector2.zero
	stack.Position = UDim2.fromOffset(lane.left, if lane.modal then lane.bottom else lane.top)
	stack.Size = UDim2.fromOffset(toastWidth, 0)
	list.HorizontalAlignment = if lane.under or lane.modal
		then Enum.HorizontalAlignment.Left
		else Enum.HorizontalAlignment.Center
	while #toasts > maxToasts do
		removeToast(toasts[#toasts])
	end
	for _, toast in ipairs(toasts) do
		fitToast(toast)
	end
end

-- Once per frame at most, however many things moved.
local function queueToasts()
	if not laneQueued then
		laneQueued = true
		task.defer(placeToasts)
	end
end

-- The top-right row holding the cash plaque (LayoutOrder 10). Other
-- controllers add small buttons to its left with lower LayoutOrders. It's
-- drawn over the shop panel, which keeps clear of it.
-- Nil before HUD.Start.
function HUD.TopRow(): Frame?
	return if cashOuter then cashOuter.Parent :: Frame? else nil
end

-- The line left of the cash row (the clock, the Store button), and the
-- line under it (the Daily Goals button): both
-- right-aligned, by LayoutOrder (higher = further right), and under the
-- shop panel. Nil before HUD.Start.
function HUD.BesideCash(): Frame?
	return besideCash
end

function HUD.UnderCash(): Frame?
	return underCash
end

-- Popups drop down at the right margin under both lines of the corner,
-- however tall the lines are right now.
local function placePopups()
	local f = shelf
	if not f then
		return
	end
	local y = f.Position.Y.Offset + f.AbsoluteSize.Y / UITheme.Scale() + POPUP_GAP
	for _, card in ipairs(popups) do
		card.Position = UDim2.new(1, -UITheme.Margin(), 0, y)
	end
end

local POPUP_CLOSE = "HudPopupClose"

-- B on a gamepad, while a popup's open: closes it (over the placer's and a
-- shop's B, which get the next press).
local function onPopupClose(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	for _, p in ipairs(popups) do
		p.Visible = false
	end
	return Enum.ContextActionResult.Sink
end

-- Makes `card` one of the corner's popups (Settings, the goals, the pouch
-- list): HUD places it under the corner, and showing it hides the others,
-- so they never stack up. Its screen must mind the top bar inset (the
-- UITheme.Screen default), as the corner's does. On a gamepad (UI-15)
-- opening it selects `first` (its first button, if it has one) so A
-- presses it at once, and B closes it and lets go of the selection.
function HUD.Popup(card: GuiObject, first: GuiObject?)
	table.insert(popups, card)
	if first then
		popupFirst[card] = first
	end
	card.AnchorPoint = Vector2.new(1, 0)
	-- It takes the taps on its empty parts too, and while it's open the
	-- side buttons it drops over are put away (so nothing hidden under it
	-- can be pressed, by touch or by the pad).
	card.Active = true
	card:GetPropertyChangedSignal("Visible"):Connect(function()
		if card.Visible then
			for _, other in ipairs(popups) do
				if other ~= card then
					other.Visible = false
				end
			end
		end
		local open = false
		for _, p in ipairs(popups) do
			open = open or p.Visible
		end
		local gui = sideGui
		if gui then
			gui.Enabled = not open
		end
		if card.Visible then
			local pick = popupFirst[card]
			if pick and HudRules.PadSelects(UITheme.Device()) then
				GamepadNav.Focus(pick, card) -- selects it, keeps the stick in the card, remembers the button
			end
		else
			GamepadNav.Restore(card) -- back to the HUD button that opened it, or to walking
		end
		if open and not popupCloseBound then
			popupCloseBound = true
			ContextActionService:BindActionAtPriority(
				POPUP_CLOSE,
				onPopupClose,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.ButtonB
			)
		elseif not open and popupCloseBound then
			popupCloseBound = false
			ContextActionService:UnbindAction(POPUP_CLOSE)
		end
	end)
	placePopups()
end

-- A glyph chip for `key` (UITheme.Glyph), shown while `beside` is and
-- you're on a gamepad or a TV (HudRules.PadGlyphs), so you can see which
-- button opens it. The caller places and parents it.
function HUD.PadGlyph(key: Enum.KeyCode, beside: GuiObject, size: number?): GuiObject
	local glyph = UITheme.Glyph(key, size or 24)
	glyph.Name = "PadGlyph"
	local function refresh()
		glyph.Visible = beside.Visible and HudRules.PadGlyphs(UITheme.Device())
	end
	beside:GetPropertyChangedSignal("Visible"):Connect(refresh)
	UserInputService.LastInputTypeChanged:Connect(refresh)
	refresh()
	return glyph
end

-- Puts one toast on screen (NoticePolicy has already said yes).
local function presentToast(message: string, seconds: number?, id: number?)
	local stack = toastStack
	if not stack then
		return
	end
	while #toasts >= maxToasts do
		removeToast(toasts[#toasts])
	end
	toastOrder += 1
	local card = UITheme.Card(C.Panel, C.AmberEdge, UITheme.Stroke, UITheme.Radius, true)
	card.outer.Name = "Toast"
	card.outer.LayoutOrder = -toastOrder -- newest on top
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(0, 34)
	limit.Parent = card.outer
	local stroke = UITheme.stroke(card.face, C.AmberEdge, UITheme.Stroke)
	UITheme.padding(card.face, 7, 14, 7, 14)
	local label = UITheme.label(card.face, "", F.Bold, UITheme.Sized("Toast").text, C.Cream)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.TextWrapped = true
	label.RichText = true
	label.Text = richToast(message)
	local labelLimit = Instance.new("UISizeConstraint")
	labelLimit.Parent = label
	local toast: Toast = {
		id = id,
		outer = card.outer,
		face = card.face,
		label = label,
		stroke = stroke,
		limit = limit,
		labelLimit = labelLimit,
	}
	fitToast(toast)
	card.outer.Parent = stack
	table.insert(toasts, 1, toast)
	restack()

	task.delay(HudRules.ToastSeconds(message, seconds), function()
		if not table.find(toasts, toast) then
			return -- already pushed out by newer toasts
		end
		local info = TweenInfo.new(TOAST_FADE)
		TweenService:Create(card.outer, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card.face, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		local fade = TweenService:Create(label, info, { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if table.find(toasts, toast) then
			removeToast(toast)
		end
	end)
end

-- What gets through (NoticePolicy: priorities, one non-critical at a time,
-- a cooldown, no repeats, a short queue). During the first-sale flow only
-- errors show: Murph's card and the arrow are the one objective.
local policy = NoticePolicy.New()
local pumping = false

local function flowQuiet(): boolean
	return CoreLoop.V2() and NoticePolicy.FlowQuiet(player:GetAttribute("TutorialStep"), TutorialData.RefresherLast)
end

-- The dialogue box is up (DialogueUI sets TalkOpen): only errors show, the
-- rest wait for it to close (NoticePolicy hold).
local function talkHeld(): boolean
	return player:GetAttribute("TalkOpen") == true
end

local function applyDecision(decision: NoticePolicy.Decision)
	for _, id in ipairs(decision.evict) do
		for _, toast in ipairs(toasts) do
			if toast.id == id then
				removeToast(toast)
				break
			end
		end
	end
	if decision.action == "show" and decision.text then
		presentToast(decision.text, decision.seconds, decision.id)
	end
end

local function pump()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while NoticePolicy.Pending(policy) do
			task.wait(0.25)
			local decision = NoticePolicy.Tick(policy, os.clock(), flowQuiet(), talkHeld())
			if decision then
				applyDecision(decision)
			end
		end
		pumping = false
	end)
end

-- Shows a short message at the top of the screen for a few seconds: long
-- enough to read it, or `seconds` when given (HudRules.ToastSeconds; a
-- confirm, which asks for a second press, stays 6 s). `options` says how
-- much it matters (NoticePolicy: "critical" errors always show, "low" is
-- ambient news; unset, it's read from the words) and `key`/`once` show a
-- repeating tip only once per session.
function HUD.Toast(
	message: string,
	seconds: number?,
	options: { priority: NoticePolicy.Priority?, key: string?, once: boolean? }?
)
	if not toastStack then
		return
	end
	local shown = HudRules.ToastSeconds(message, seconds)
	local decision = NoticePolicy.Offer(policy, {
		text = message,
		priority = if options then options.priority else nil,
		seconds = shown,
		key = if options then options.key else nil,
		once = if options then options.once else nil,
	}, os.clock(), flowQuiet(), talkHeld())
	applyDecision(decision)
	if decision.action == "queue" then
		pump()
	end
end

---------------------------------------------------------------------------
-- Hint and side buttons, by device
---------------------------------------------------------------------------

-- A number attribute of the player as read, else 0.
local function attrAmount(name: string): number
	local n = player:GetAttribute(name)
	return if type(n) == "number" and n == n then n else 0
end

-- The longest side of the piece you're dragging, in studs, or nil.
local function heldLength(): number?
	local model = heldPiece
	if not model or model.Parent == nil then
		return nil
	end
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Y, size.Z)
end

-- What the v2 hint knows (HintLogic.StateV2): what the axe points at
-- (CutController, through SetPointing), and whether the piece you hold is
-- longer than your truck's bed (TruckLoad's BedLength).
local function hintStateV2(): HintLogic.StateV2
	return {
		driving = hintState.driving,
		axeOut = axeOut,
		holding = heldPiece ~= nil,
		onWood = pointingWood,
		tooHard = pointingHard,
		thick = pointingThick,
		tooLong = HintLogic.TooLong(heldLength(), player:GetAttribute("BedLength")),
		bedVolume = attrAmount("BedVolume"),
		nearPad = nearPad,
	}
end

-- The hint for this device and what you're doing.
local function refreshHint()
	local hint = hintLabel
	if not hint then
		return
	end
	local text
	if CoreLoop.V2() then
		local forced = hintForced :: any -- "build": a context both loops have
		local context = forced or HintLogic.ContextForV2(hintStateV2())
		text = HintLogic.PickV2(UITheme.Device(), context)
		if context == "drag" and dragHintSince == nil then
			dragHintSince = os.clock()
			task.delay(HintLogic.IdleHintSeconds + 0.1, refreshHint)
		end
		local shownFor = if dragHintSince then os.clock() - dragHintSince else nil
		local quiet = HintLogic.Quiet(context, hintGrabs, shownFor)
		if quiet ~= hintQuiet then
			hintQuiet = quiet
			local sync = syncHint
			if sync then
				sync()
			end
		end
	else
		text = HintLogic.Pick(UITheme.Device(), hintForced or HintLogic.ContextFor(hintState))
	end
	if hint.Text ~= text then
		hint.Text = text
	end
end

-- What the axe is pointing at (CutController, a few times a second): a
-- loose piece, and wood too hard for it. Refreshes the hint on a change.
function HUD.SetPointing(onWood: boolean, tooHard: boolean, thick: boolean?)
	local isThick = thick == true
	if onWood == pointingWood and tooHard == pointingHard and isThick == pointingThick then
		return
	end
	pointingWood, pointingHard, pointingThick = onWood, tooHard, isThick
	refreshHint()
end

-- A mode a controller is in that the hint should explain ("build" while
-- placing a blueprint), or nil when it's over: back to what you're doing.
function HUD.SetHintContext(context: HintLogic.Context?)
	hintForced = context
	refreshHint()
end

-- The piece you're dragging, as its attributes read, or nil.
local function heldFacts(): HudRules.Held?
	local model = heldPiece
	if not model or model.Parent == nil or model:GetAttribute("HeldBy") ~= player.UserId then
		return nil
	end
	return {
		woodId = model:GetAttribute("WoodId"),
		kind = model:GetAttribute("Kind"),
		volume = model:GetAttribute("Volume"),
		value = model:GetAttribute("Value"),
	}
end

-- The v2 chip (HudRules.LoadChipV2): what you hold, else your bed's load.
-- The bed's room has no attribute yet (nil: "Bed 41 u³ · $61").
local function refreshChipV2(c: Chip)
	local view = HudRules.LoadChipV2(
		heldFacts(),
		player:GetAttribute("BedVolume"),
		nil,
		player:GetAttribute("BedValue"),
		modalRect ~= nil,
		UITheme.IsPhone()
	)
	c.frame.Visible = view.shown
	c.hands.Text = view.text
	c.bed.Visible = false
	c.dot.Visible = false
	c.frame.BackgroundColor3 = if view.full then C.Amber else C.Ink
	c.frame.BackgroundTransparency = if view.full then 0 else 0.2
	c.hands.TextColor3 = if view.full then C.Ink else C.Cream
	if not view.shown then
		return
	end
	if chipText ~= nil and chipText ~= view.text then
		c.pop.Scale = CHIP_POP
		TweenService:Create(c.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
	chipText = view.text
end

-- The load chip, from the attributes the server keeps (HudRules.LoadChip).
-- A change in what it says, while it shows, bumps its log.
local function refreshChip()
	local c = chip
	if not c then
		return
	end
	if not HudRules.ShowsHands(CoreLoop.Active()) then
		refreshChipV2(c) -- the v2 loop: no hands to count
		return
	end
	local view = HudRules.LoadChip(
		player:GetAttribute("CarriedLogs"),
		player:GetAttribute("BedCount"),
		player:GetAttribute("BedCapacity"),
		GameConfig.HandCapacity,
		modalRect ~= nil
	)
	local bed = view.bed
	c.frame.Visible = view.shown
	c.hands.Text = view.hands
	c.bed.Text = bed or ""
	c.bed.Visible = bed ~= nil
	c.dot.Visible = bed ~= nil
	c.frame.BackgroundColor3 = if view.full then C.Amber else C.Ink
	c.frame.BackgroundTransparency = if view.full then 0 else 0.2
	local ink = if view.full then C.Ink else C.Cream
	c.hands.TextColor3 = ink
	c.dot.TextColor3 = ink
	c.bed.TextColor3 = ink
	if not view.shown then
		return
	end
	local text = view.hands .. " " .. (bed or "")
	if chipText ~= nil and chipText ~= text then
		c.pop.Scale = CHIP_POP
		TweenService:Create(c.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
	chipText = text
end

local tipsOn = true

-- The hint and the load chip show unless a panel is open over the game.
local function refreshModal()
	local hint = hintLabel
	if hint then
		hint.Visible = modalRect == nil and tipsOn and not hintQuiet
	end
	refreshChip()
end
syncHint = refreshModal

-- A piece was picked up (DragController). After a couple, the "how to drag"
-- hints stop showing.
function HUD.NoteGrab()
	hintGrabs += 1
	refreshHint()
end

-- Settings: hide the hint line without closing panels.
function HUD.SetTips(on: boolean)
	tipsOn = on
	refreshModal()
end

-- Build mode (PlotUI): the hint row hides so the builder readout is the
-- only hint. Safe to call before HUD.Start.
local buildOpen = false

function HUD.BuildOpen(): boolean
	return buildOpen
end

function HUD.SetBuildMode(on: boolean)
	buildOpen = on
	local row = bottomRow
	if row then
		row.Visible = not on
	end
end

-- A panel open over the game (ShopUI: the shops, the Store, the Field
-- Guide), as its box in screen pixels (AbsolutePosition and
-- AbsolutePosition + AbsoluteSize), or nil once it's closed. While one is
-- open the hint hides and the toasts move inside the panel's bottom edge
-- (HudLayout.ModalLane), so they never cover its title or its buttons.
-- Safe to call before HUD.Start: it applies once the HUD is built.
function HUD.SetModal(rect: HudLayout.Rect?)
	modalRect = if rect then table.clone(rect) else nil
	refreshModal()
	queueToasts()
end

-- Whether a panel is open over the game: a shop, the Store or the Field
-- Guide (HUD.SetModal), or one of the corner's popups (HUD.Popup). The
-- drop keys (DropControls) stay out of its way.
function HUD.Overlay(): boolean
	if modalRect ~= nil then
		return true
	end
	for _, p in ipairs(popups) do
		if p.Visible then
			return true
		end
	end
	return false
end

-- Fits the bottom row between the left margin and a phone's jump button
-- (or the right margin) for the chip's and the hint's sizes right now
-- (HudLayout.BottomRow): it moves left, then the hint truncates sooner.
local function placeRow()
	rowQueued = false
	local gui, row, hint, limit = hudGui, bottomRow, hintLabel, hintLimit
	if not gui or not row or not hint or not limit then
		return
	end
	local scale = UITheme.Scale()
	local screenW = gui.AbsoluteSize.X / scale
	if screenW <= 0 then
		return -- not laid out yet
	end
	local side = UITheme.Margin()
	local high = screenW - side
	local jump = jumpButton
	local touch = if jump then jump:FindFirstAncestorOfClass("ScreenGui") else nil
	if jump and touch and touch.Enabled and jump.Visible and jump.AbsoluteSize.X > 0 then
		high = math.min(high, (jump.AbsolutePosition.X - gui.AbsolutePosition.X) / scale - ROW_GAP)
	end
	local c = chip
	local chipW = if c and c.frame.Visible then c.frame.AbsoluteSize.X / scale else 0
	local hintW = if hint.Visible then hint.AbsoluteSize.X / scale else 0
	local hintMax, centre = HudLayout.BottomRow(screenW, chipW, hintW, ROW_GAP, side, high, HINT_MAX)
	if limit.MaxSize.X ~= hintMax then
		limit.MaxSize = Vector2.new(hintMax, ROW_HEIGHT)
	end
	row.Position = UDim2.new(0, centre, 1, -UITheme.Bottom()) -- above the tool hotbar
end

-- Once per frame at most, however many things changed.
local function queueRow()
	if not rowQueued then
		rowQueued = true
		task.defer(placeRow)
	end
end

-- Your truck's flat distance from the sell zone, as CarryController
-- measures it (its PrimaryPart); nil with no truck, or while it isn't
-- streamed in.
local function truckFrom(zone: BasePart): number?
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerId") == player.UserId then
			local pp = inst.PrimaryPart
			if pp then
				local d = pp.Position - zone.Position
				return Vector3.new(d.X, 0, d.Z).Magnitude
			end
		end
	end
	return nil
end

-- Your bed's count: the Player's mirror, or the truck's own while that
-- isn't set (as CarryController reads it).
local function bedCount(): unknown
	local n = player:GetAttribute("BedCount")
	if n ~= nil then
		return n
	end
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:GetAttribute("OwnerId") == player.UserId then
			return inst:GetAttribute("BedCount")
		end
	end
	return nil
end

-- Whether you stand in the sell zone, and what the pad would sell from
-- there (HintLogic.SellCount); the hint changes if either did. The sell
-- area is Persistent, but found by name each time in case it isn't there
-- yet.
local function refreshSellState()
	local map = workspace:FindFirstChild("TimberlineMap")
	local area = if map then map:FindFirstChild("SellArea") else nil
	local found = if area then area:FindFirstChild("SellZone") else nil
	local zone = if found and found:IsA("BasePart") then found else nil
	local body = player.Character
	local root = if body then body:FindFirstChild("HumanoidRootPart") else nil
	local hrp = if root and root:IsA("BasePart") then root else nil
	local inZone = false
	local sellable = 0
	if zone and hrp and Util.pointInPart(zone, hrp.Position) then
		inZone = true
		sellable = HintLogic.SellCount(
			player:GetAttribute("CarriedLogs"),
			bedCount(),
			truckFrom(zone),
			player:GetAttribute("SkyBin"),
			GameConfig.SellTruckRange
		)
	end
	if inZone ~= hintState.inSellZone or sellable ~= hintState.sellable then
		hintState.inSellZone = inZone
		hintState.sellable = sellable
		refreshHint()
	end
end

-- The v2 hint's polled sources (with the v1 ones, every HINT_POLL): an
-- axe in hand (a Tool with an AxeId in the character) and your truck by
-- the pad. The chip redraws too, in case the held piece's numbers moved.
local function refreshV2State()
	local char = player.Character
	local axe = false
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and type(child:GetAttribute("AxeId")) == "string" then
				axe = true
				break
			end
		end
	end
	local map = workspace:FindFirstChild("TimberlineMap")
	local area = if map then map:FindFirstChild("SellArea") else nil
	local found = if area then area:FindFirstChild("SellZone") else nil
	local near = found ~= nil and found:IsA("BasePart") and HintLogic.NearPad(truckFrom(found))
	if axe ~= axeOut or near ~= nearPad then
		axeOut, nearPad = axe, near
		refreshHint()
	end
	refreshChip()
end

-- Whose hands a piece is in changed: it's the one you hold now, or no
-- longer.
local function onHeldBy(model: Model)
	if model:GetAttribute("HeldBy") == player.UserId then
		heldPiece = model
	elseif heldPiece == model then
		heldPiece = nil
	end
	refreshChip()
	refreshHint()
end

local function watchWood(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	if woodConns[model] then
		return
	end
	woodConns[model] = model:GetAttributeChangedSignal("HeldBy"):Connect(function()
		onHeldBy(model)
	end)
	if model:GetAttribute("HeldBy") == player.UserId then
		onHeldBy(model)
	end
end

-- Gone (sold, cut, despawned or streamed out): forget it.
local function unwatchWood(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	local conn = woodConns[model]
	if conn then
		conn:Disconnect()
		woodConns[model] = nil
	end
	if heldPiece == model then
		heldPiece = nil
		refreshChip()
		refreshHint()
	end
end

-- The v2 loop's sources, once the loop is known to be v2: loose wood's
-- HeldBy (tag Wood, as DragController watches it), the bed's volume and
-- worth (TruckLoad's BedVolume and BedValue, M1.6), and the polled ones
-- (refreshV2State).
local function watchV2()
	if v2Watching or not CoreLoop.V2() then
		return
	end
	v2Watching = true
	for _, inst in ipairs(CollectionService:GetTagged("Wood")) do
		watchWood(inst)
	end
	CollectionService:GetInstanceAddedSignal("Wood"):Connect(watchWood)
	CollectionService:GetInstanceRemovedSignal("Wood"):Connect(unwatchWood)
	for _, name in ipairs({ "BedVolume", "BedValue" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			refreshChip()
			refreshHint()
		end)
	end
	refreshV2State()
	refreshHint()
end

-- The hint's sources: sitting in a driver's seat (re-hooked on every
-- character, R6 or R15: both have a Humanoid), logs in hand, and standing
-- in the sell zone with something to sell (polled, and again whenever
-- what you'd sell changes).
local function watchHintSources()
	local seatedConn: RBXScriptConnection? = nil
	local function onCharacter(char: Model)
		local old = seatedConn
		if old then
			old:Disconnect()
			seatedConn = nil
		end
		hintState.driving = false
		refreshHint()
		local humanoid = char:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or char ~= player.Character then
			return
		end
		seatedConn = humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
			hintState.driving = active and seatPart ~= nil and seatPart:IsA("VehicleSeat")
			refreshHint()
		end)
		local seat = humanoid.SeatPart
		hintState.driving = seat ~= nil and seat:IsA("VehicleSeat")
		refreshHint()
	end
	player.CharacterAdded:Connect(onCharacter)
	local char = player.Character
	if char then
		task.spawn(onCharacter, char)
	end

	local function onCarried()
		local n = player:GetAttribute("CarriedLogs")
		hintState.carrying = type(n) == "number" and n > 0
		refreshSellState() -- what the pad would sell changed too
		refreshHint()
	end
	player:GetAttributeChangedSignal("CarriedLogs"):Connect(onCarried)
	player:GetAttributeChangedSignal("BedCount"):Connect(refreshSellState)
	player:GetAttributeChangedSignal("SkyBin"):Connect(refreshSellState)
	onCarried()

	while true do
		task.wait(HINT_POLL)
		refreshSellState()
		if v2Watching then
			refreshV2State()
		end
	end
end

-- Whether a world prompt that uses `key` is showing (it gets the press).
local function promptOn(key: Enum.KeyCode): boolean
	for prompt in pairs(shownPrompts) do
		if prompt.Enabled and prompt.GamepadKeyCode == key then
			return true
		end
	end
	return false
end

-- A small mark on the left of Saves, Hammer and the truck button. Same
-- shapes everywhere; the colour is that button's ink so it stays readable
-- on walnut, green and amber.
local function sideMark(face: TextButton, name: string)
	local kind = if name == "Saves"
		then "saves"
		elseif name == "Hammer" then "hammer"
		elseif name == "CallTruck" then "truck"
		else nil
	if kind == nil then
		return
	end
	-- paint() has already set the label colour
	local ink = face.TextColor3
	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0, 0.5)
	mark.Position = UDim2.new(0, 8, 0.5, 0)
	mark.Size = UDim2.fromOffset(18, 18)
	mark.BackgroundTransparency = 1
	mark.BorderSizePixel = 0
	mark.ZIndex = face.ZIndex + 1
	mark.Active = false
	local function bit(w: number, h: number, x: number, y: number, rot: number?): Frame
		local part = Instance.new("Frame")
		part.Size = UDim2.fromOffset(w, h)
		part.Position = UDim2.fromOffset(x, y)
		part.Rotation = rot or 0
		part.BackgroundColor3 = ink
		part.BorderSizePixel = 0
		part.ZIndex = mark.ZIndex
		part.Parent = mark
		UITheme.corner(part, 2)
		return part
	end
	if kind == "saves" then
		bit(14, 10, 2, 4)
		bit(6, 3, 6, 2)
	elseif kind == "hammer" then
		bit(12, 3, 3, 8, -40)
		bit(7, 5, 10, 2, -40)
	else
		bit(14, 6, 2, 8)
		bit(4, 4, 3, 12)
		bit(4, 4, 11, 12)
	end
	mark.Parent = face
end

-- A side button's size for the device (UITheme.Sized: on a phone 116 x 44,
-- a fingertip tall, its label 15 and never under 12; on a gamepad wider,
-- for the glyph).
local function layoutSide(side: Side, device: UITheme.Device)
	local phone = UITheme.IsPhone()
	local spec = UITheme.Sized("SideButton")
	local face = spec.size or Vector2.new(110, 40)
	local console = device == "console" and (side.key ~= nil or side.hint ~= nil)
	local width, height = face.X, face.Y
	if device == "console" then
		width, height = GamepadNavLogic.PadSize(width, height) -- big enough for a stick to land on
	end
	side.button.root.Size = UDim2.fromOffset(width, height + UITheme.ButtonDrop)
	side.button.face.TextSize = spec.text
	local fit = side.button.face:FindFirstChildOfClass("UITextSizeConstraint")
	if fit then
		fit.MaxTextSize = spec.text
		fit.MinTextSize = if phone then UITheme.Size.ButtonMinText else 8
	end
	local pad = side.button.face:FindFirstChildOfClass("UIPadding")
	if pad then
		local iconPad = if side.button.face:FindFirstChild("Mark") then 28 else 0
		pad.PaddingLeft = UDim.new(0, (if console then 36 else 6) + iconPad)
	end
	if side.glyph then
		side.glyph.Visible = console
	end
end

-- Lays out the side buttons that are showing (HudLayout.SideColumn, then
-- Stack), up from SIDE_BELOW_CENTRE under the screen centre, or with touch
-- controls from just above the jump button, to just under the corner's
-- second line; at the right margin of the device's safe area, and no
-- further right than the jump button.
local function arrangeSide()
	arrangeQueued = false
	local gui, column, corner = sideGui, sideColumn, shelf
	if not gui or not column or not corner then
		return
	end
	local scale = UITheme.Scale()
	-- Screen pixels to this screen's offsets. It's the device's safe area
	-- with the top bar's strip in it (UITheme.Screen "device"); the
	-- corner's screen starts under the top bar, and the touch controls'
	-- may not mind the safe area at all: measure both from this one's
	-- corner.
	local origin = gui.AbsolutePosition
	local function at(pixels: Vector2): Vector2
		return (pixels - origin) / scale
	end
	local screen = gui.AbsoluteSize / scale
	local cornerBottom = at(corner.AbsolutePosition + corner.AbsoluteSize).Y
	local jumpRect: HudLayout.Rect? = nil
	local jump = jumpButton
	if jump and jump.Parent and jump.AbsoluteSize.Y > 0 then
		local low, high = at(jump.AbsolutePosition), at(jump.AbsolutePosition + jump.AbsoluteSize)
		jumpRect = { left = low.X, top = low.Y, right = high.X, bottom = high.Y }
	end
	local spot, room = HudLayout.SideColumn(
		screen,
		cornerBottom,
		jumpRect,
		UITheme.Margin(),
		SIDE_GAP,
		JUMP_CLEARANCE,
		SIDE_BELOW_CENTRE
	)
	-- From the right edge, so it stays put if the screen resizes first.
	column.Position = UDim2.new(1, spot.X - screen.X, 0, spot.Y)

	local shown: { Frame } = {}
	for _, side in ipairs(sides) do
		if side.button.root.Visible then
			table.insert(shown, side.button.root)
		end
	end
	table.sort(shown, function(a: Frame, b: Frame): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	local sizes: { Vector2 } = {}
	for i, root in ipairs(shown) do
		sizes[i] = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
	end
	local spots = HudLayout.Stack(sizes, room, SIDE_GAP)
	-- Columns that spill left mustn't reach the bars at the bottom centre
	-- (build mode, placing): lift such a column above them if there's room.
	-- The bars' screens share this one's safe area left, right and below.
	local band: HudLayout.Rect = {
		left = screen.X / 2 - BAR_HALF_WIDTH,
		right = screen.X / 2 + BAR_HALF_WIDTH,
		top = screen.Y - (UITheme.Bottom() + 38) - BAR_HEIGHT,
		bottom = screen.Y,
	}
	spots = HudLayout.LiftClear(spots, sizes, spot, band, spot.Y - room, SIDE_GAP)
	for i, root in ipairs(shown) do
		root.Position = UDim2.fromOffset(-spots[i].X, -spots[i].Y)
	end
end

-- Once per frame at most, however many things changed.
local function queueArrange()
	if not arrangeQueued then
		arrangeQueued = true
		task.defer(arrangeSide)
	end
end

-- The hint's and the load chip's text, for the device (UITheme.Sized).
local function sizeRow()
	local hint, c = hintLabel, chip
	if hint then
		hint.TextSize = UITheme.Sized("Hint").text
	end
	if c then
		local size = UITheme.Sized("LoadChip").text
		c.hands.TextSize = size
		c.dot.TextSize = size
		c.bed.TextSize = size
	end
end

local function refreshDevice()
	local device: UITheme.Device = UITheme.Device()
	refreshHint()
	sizeRow()
	for _, side in ipairs(sides) do
		layoutSide(side, device)
	end
	queueArrange()
	queueToasts()
	queueRow()
end

export type SideOptions = {
	name: string,
	text: string,
	style: string,
	order: number, -- top to bottom
	key: Enum.KeyCode?, -- the gamepad button that presses it
	glyph: Enum.KeyCode?, -- a button that does the same, bound elsewhere: shows its glyph only
	tile: boolean?, -- false: no tile for it in the quick menu (the menu's own button)
	onPress: () -> (),
}

-- Adds a button to the right-hand column (hidden until you show it:
-- set `.root.Visible`). Pressing it, or its gamepad button, calls onPress.
-- Without the column (HUD.Start failed or hasn't run) it warns and hands
-- back a button that's never on screen, so the caller still starts.
function HUD.SideButton(opts: SideOptions): UITheme.Button
	local column = sideColumn
	local spec = UITheme.Sized("SideButton") -- layoutSide keeps it right for the device
	local button = UITheme.Button({
		name = opts.name,
		text = opts.text,
		size = spec.size or Vector2.new(110, 40),
		style = opts.style,
		textSize = spec.text,
		radius = 12,
	})
	button.root.LayoutOrder = opts.order
	button.root.AnchorPoint = Vector2.new(1, 1) -- placed by arrangeSide
	button.root.Visible = false
	sideMark(button.face, opts.name)
	if not column then
		warn(string.format("[HUD] no side column (HUD.Start didn't finish): skipping the %s button", opts.name))
		return button
	end
	local glyph: GuiObject? = nil
	local glyphKey = opts.key or opts.glyph
	if glyphKey then
		local g = UITheme.Glyph(glyphKey, 22)
		g.AnchorPoint = Vector2.new(0, 0.5)
		g.Position = UDim2.new(0, -26, 0.5, 0) -- in the face's left padding
		g.Parent = button.face
		glyph = g
	end
	button.root.Parent = column
	button.face.Activated:Connect(opts.onPress)
	local side: Side = { button = button, key = opts.key, hint = opts.glyph, glyph = glyph, onPress = opts.onPress }
	table.insert(sides, side)
	-- A gamepad walks the HUD's buttons (HudNav) and the quick menu lists it.
	local tile = opts.tile ~= false
	HudNav.Add(button.face, {
		id = QuickMenuLogic.IdFor(opts.name),
		labelOf = if tile
			then function(): string
				return QuickMenuLogic.Label(button.face.Text)
			end
			else nil,
		press = if tile then opts.onPress else nil,
	})
	local device: UITheme.Device = UITheme.Device()
	layoutSide(side, device)
	button.root:GetPropertyChangedSignal("Visible"):Connect(queueArrange)
	queueArrange()
	return button
end

-- Whether you're sitting in a seat (driving your truck).
local function seated(): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- A D-pad shortcut (UI-15, HudRules.PadKeys): `key` calls `onPress` while
-- `available()` says what it opens is there, and nothing else has the pad
-- (HudRules.PadShortcut: no menu selection, no shop open, not typing, not
-- seated in a truck, no world prompt on that button). It's a
-- ContextActionService action over the default ones (Roblox's camera has
-- bound the D-pad in some versions), and it lets the press through to them,
-- and to the menus' own D-pad moves, whenever it doesn't take it. While a
-- menu has the selection they're unbound altogether (syncPad), so they can
-- never get in the way of its D-pad moves.
local function bindPad(binding: PadBinding)
	ContextActionService:BindActionAtPriority(
		binding.name,
		binding.handle,
		false,
		Enum.ContextActionPriority.High.Value,
		binding.key
	)
end

local function syncPad()
	local want = GuiService.SelectedObject == nil
	if want == padBound then
		return
	end
	padBound = want
	for _, binding in ipairs(padBindings) do
		if want then
			bindPad(binding)
		else
			ContextActionService:UnbindAction(binding.name)
		end
	end
end

function HUD.PadShortcut(key: Enum.KeyCode, available: () -> boolean, onPress: () -> ())
	-- The Daily Goals pill used the up direction. That button is gone; ignore
	-- the bind so the pill's script can stay until its own lane removes it.
	if key.Name == "DPadUp" then
		return
	end
	local took = false -- this press's Begin was ours: so is its End
	local function handle(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			if took and state ~= Enum.UserInputState.Change then
				took = false
				return Enum.ContextActionResult.Sink
			end
			return if took then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
		end
		took = false
		local allowed = HudRules.PadShortcut({
			available = available(),
			typing = UserInputService:GetFocusedTextBox() ~= nil,
			selecting = GuiService.SelectedObject ~= nil,
			modal = modalRect ~= nil,
			seated = seated(),
			prompt = promptOn(input.KeyCode),
		})
		if not allowed then
			return Enum.ContextActionResult.Pass
		end
		took = true
		UITheme.Click() -- as a press on the button itself does
		onPress()
		return Enum.ContextActionResult.Sink
	end
	local binding: PadBinding = { name = "HudPad" .. key.Name, key = key, handle = handle }
	table.insert(padBindings, binding)
	if padBound then
		bindPad(binding)
	end
	syncPad()
end

local function onGamepad(input: InputObject, processed: boolean)
	if processed or GuiService.SelectedObject ~= nil then
		return -- a menu has the pad
	end
	for _, side in ipairs(sides) do
		local shown = side.button.root.Visible and (sideGui == nil or (sideGui :: ScreenGui).Enabled)
		if side.key == input.KeyCode and shown and not promptOn(input.KeyCode) then
			UITheme.Click() -- as a press on the button itself does (UITheme.Button)
			side.onPress()
			return
		end
	end
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

-- 26 px on a desktop, 20 px on a compact screen. The top row's UIScale is
-- at least 1, so this never draws smaller than that (desktop and TV grow
-- with UITheme.Scale(); a compact screen stays at 20).
local function cashTextSize(): number
	return if UITheme.Compact() then 20 else 26
end

-- The notch probe: a full-size frame in a hidden DeviceSafeInsets screen.
-- GetGuiInset does not report the notch. leftSafe is the frame's X;
-- rightSafe is the viewport past the frame's right edge.
local safeArea: Frame? = nil

-- The notch's left inset, in screen pixels. 0 until the probe is parented.
function HUD.LeftSafe(): number
	local probe = safeArea
	if not probe then
		return 0
	end
	local ok, pos = pcall(function()
		return probe.AbsolutePosition
	end)
	if not ok or typeof(pos) ~= "Vector2" then
		return 0
	end
	return pos.X
end

-- TimberlineTop's UIScale. Offsets are multiplied by it, so a screen-pixel
-- place from HudLayout.TopRow is divided back by Scale before it's written.
local topScale: UIScale? = nil

-- Pins TopRow into the top bar, or just under it (HudLayout.TopRow).
-- `row.AbsoluteSize` is after the row's UIScale, in screen pixels.
-- HudLayout.TopRow stays in screen pixels; the position offsets are not.
local function placeTopRow()
	local row = HUD.TopRow()
	if not row then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local probe = safeArea
	local leftSafe, rightSafe = 0, 0
	if probe then
		local pos, size = probe.AbsolutePosition, probe.AbsoluteSize
		leftSafe = pos.X
		rightSafe = viewport.X - (pos.X + size.X)
	end
	local place = HudLayout.TopRow(
		viewport,
		GuiService.TopbarInset,
		row.AbsoluteSize,
		cashTextSize() * math.max(1, UITheme.Scale()),
		leftSafe,
		rightSafe,
		UITheme.TopBar() + 4
	)
	local s = if topScale and topScale.Scale > 0 then topScale.Scale else 1
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.fromOffset(place.right / s, place.top / s)

	-- STORE and the clock share the cash row's strip when it is in the top bar
	-- (HudLayout.CornerInBar); otherwise the shelf keeps its default spot.
	local frame, line = shelf, besideCash
	local gui = if frame then frame.Parent else nil
	if frame and line and gui and gui:IsA("ScreenGui") then
		local scale = math.max(UITheme.Scale(), 0.01)
		local lifted = HudLayout.CornerInBar(
			place,
			row.AbsoluteSize,
			line.AbsoluteSize,
			math.max(GuiService.TopbarInset.Min.X, leftSafe)
		)
		local want = if lifted
			then UDim2.fromOffset(
				(lifted.X - gui.AbsolutePosition.X) / scale,
				(lifted.Y - gui.AbsolutePosition.Y) / scale
			)
			else UDim2.new(1, -UITheme.Margin(), 0, HudLayout.CornerTopPad)
		local have = frame.Position
		if
			math.abs(have.X.Offset - want.X.Offset) > 0.5
			or math.abs(have.Y.Offset - want.Y.Offset) > 0.5
			or have.X.Scale ~= want.X.Scale
		then
			frame.Position = want
		end
	end
end

-- The cash row, in its own screen (no insets) parented to `playerGui`.
-- Its UIScale is at least 1, so desktop and TV text grows with the other
-- screens and a compact screen does not shrink. SettingsUI adds its
-- button to the row.
local function buildCash(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TimberlineTop"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = UITheme.Layers.Top -- over the HUD (10) and the shop; the Store (20) still covers its panel
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "Scale"
	topScale = uiScale
	local function fitScale()
		uiScale.Scale = math.max(1, UITheme.Scale())
	end
	fitScale()
	uiScale.Parent = gui

	-- Hidden: it only exists so AbsolutePosition/AbsoluteSize are the
	-- device safe rect. Not under TimberlineTop, which ignores insets.
	local probeGui = Instance.new("ScreenGui")
	probeGui.Name = "TimberlineSafeProbe"
	probeGui.ResetOnSpawn = false
	probeGui.DisplayOrder = 0
	probeGui.IgnoreGuiInset = true
	probeGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	probeGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	local probe = Instance.new("Frame")
	probe.Name = "SafeArea"
	probe.BackgroundTransparency = 1
	probe.BorderSizePixel = 0
	probe.Size = UDim2.fromScale(1, 1)
	probe.Parent = probeGui
	probeGui.Parent = playerGui
	safeArea = probe

	local border = UITheme.SkinInset("Plaque")
	local card = UITheme.Card(C.Panel, C.AmberEdge, UITheme.Stroke, UITheme.Radius, true, "Plaque")
	card.outer.Name = "CashPlaque"
	card.outer.LayoutOrder = 10
	-- The top-right row (HUD.TopRow): [pops][other buttons][plaque].
	local row = Instance.new("Frame")
	row.Name = "TopRow"
	row.AnchorPoint = Vector2.new(1, 0)
	row.Size = UDim2.new()
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	local list = UITheme.list(row, 8, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	local pops = Instance.new("Frame")
	pops.Name = "Pops"
	pops.Size = UDim2.new()
	pops.BackgroundTransparency = 1
	pops.LayoutOrder = -100
	pops.Parent = row
	local min = Instance.new("UISizeConstraint")
	min.MinSize = Vector2.new(172, 26 + 8 + border * 2) -- wide enough for $1,999,999; paper is the text plus 8
	min.Parent = card.outer
	cashMin = min
	-- The amber glow sits on the plaque, outside the digits.
	local glow = UITheme.stroke(card.outer, C.Amber, 4)
	glow.Transparency = 0.45
	glow.Enabled = false
	UITheme.padding(card.face, border, border, border, border)
	UITheme.texture(card.face, "Wood", 14)

	local inner = Instance.new("Frame")
	inner.Name = "Paper"
	inner.AutomaticSize = Enum.AutomaticSize.X
	inner.Size = UDim2.fromOffset(0, 26 + 8)
	inner.BackgroundColor3 = C.Paper
	inner.BorderSizePixel = 0
	UITheme.corner(inner, 10)
	UITheme.padding(inner, 0, 14, 0, 14)
	inner.Parent = card.face
	local innerMin = Instance.new("UISizeConstraint")
	innerMin.MinSize = Vector2.new(164, 26 + 8)
	innerMin.Parent = inner
	cashInnerMin = innerMin

	local label = UITheme.label(inner, "$0", F.Heading, 26, C.Ink)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.TextScaled = false
	local labelMin = Instance.new("UISizeConstraint")
	labelMin.MinSize = Vector2.new(136, 0)
	labelMin.Parent = label
	cashLabelMin = labelMin

	local shown = Instance.new("NumberValue")
	shown.Name = "CashShown"
	shown.Changed:Connect(function(value: number)
		showCash(value)
	end)
	shown.Parent = card.outer

	card.outer.Parent = row
	row.Parent = gui
	gui.Parent = playerGui
	cashOuter, cashFace, cashInner, cashLabel, cashGlow = card.outer, card.face, inner, label, glow
	cashPops, cashShown = pops, shown
	-- A handheld doesn't reserve room for $1,999,999: the plaque hugs the
	-- amount. The text stays 20 px there and 26 elsewhere; the screen's
	-- scale is at least 1, so neither size shrinks to fit the bar.
	local function fitCash()
		local compact = UITheme.Compact()
		local textH = cashTextSize()
		local paperH = textH + 8
		local tall = paperH + border * 2
		local cap, paper, words = cashMin, cashInnerMin, cashLabelMin
		if cap then
			cap.MinSize = Vector2.new(if compact then 72 else 172, tall)
		end
		if paper then
			paper.MinSize = Vector2.new(if compact then 56 else 164, paperH)
		end
		if words then
			words.MinSize = if compact then Vector2.new(36, 0) else Vector2.new(136, 0)
		end
		local face = cashInner
		if face then
			face.Size = UDim2.fromOffset(0, paperH)
		end
		local shownLabel = cashLabel
		if shownLabel then
			shownLabel.TextSize = textH
			shownLabel.TextScaled = false
		end
	end
	fitCash()
	UITheme.WatchLayout(fitScale)
	UITheme.WatchLayout(fitCash)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTopRow)
	probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTopRow)
	UITheme.WatchTopBar(placeTopRow)
	UITheme.WatchLayout(placeTopRow)
	placeTopRow()
end

function HUD.BuildCash(parent: Instance)
	buildCash(parent)
end

-- The load chip: a log drawn from frames (no image to upload), then
-- "Hands 1/2 · Bed 4/6". Ink like the hint; amber once the bed is full.
local function buildChip(row: Frame)
	local frame = Instance.new("Frame")
	frame.Name = "LoadChip"
	frame.LayoutOrder = 1
	frame.Size = UDim2.fromOffset(0, ROW_HEIGHT)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = C.Ink
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Visible = false
	UITheme.corner(frame, ROW_HEIGHT / 2)
	UITheme.padding(frame, 0, 12, 0, 8)
	local list = UITheme.list(frame, 6, true)
	list.VerticalAlignment = Enum.VerticalAlignment.Center

	-- The log, side on: a golden length with its pale cut end (a bark ring
	-- round a heart) at the right. Its holder keeps a fixed size, so the
	-- bump doesn't push the text about.
	local holder = Instance.new("Frame")
	holder.Name = "Log"
	holder.LayoutOrder = 1
	holder.Size = UDim2.fromOffset(26, 16)
	holder.BackgroundTransparency = 1
	holder.Parent = frame
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Parent = holder
	local pop = Instance.new("UIScale")
	pop.Parent = icon
	local body = Instance.new("Frame")
	body.Name = "Length"
	body.AnchorPoint = Vector2.new(0, 0.5)
	body.Position = UDim2.fromScale(0, 0.5)
	body.Size = UDim2.fromOffset(20, 12)
	body.BackgroundColor3 = C.AmberEdge
	body.BorderSizePixel = 0
	UITheme.corner(body, 4)
	UITheme.stroke(body, C.Ink, 1) -- shows on the amber chip
	body.Parent = icon
	local cut = Instance.new("Frame")
	cut.Name = "Cut"
	cut.AnchorPoint = Vector2.new(1, 0.5)
	cut.Position = UDim2.new(1, -1, 0.5, 0)
	cut.Size = UDim2.fromOffset(13, 13)
	cut.ZIndex = 2 -- over the length's end
	cut.BackgroundColor3 = C.Paper
	cut.BorderSizePixel = 0
	UITheme.corner(cut, 7)
	UITheme.stroke(cut, C.Bark, 2)
	cut.Parent = icon
	local heart = Instance.new("Frame")
	heart.Name = "Heart"
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.Position = UDim2.fromScale(0.5, 0.5)
	heart.Size = UDim2.fromOffset(4, 4)
	heart.BackgroundColor3 = C.AmberEdge
	heart.BorderSizePixel = 0
	UITheme.corner(heart, 2)
	heart.Parent = cut

	local function words(name: string, order: number, text: string): TextLabel
		local label = UITheme.label(frame, text, F.Bold, UITheme.Sized("LoadChip").text, C.Cream)
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.fromOffset(0, ROW_HEIGHT)
		label.AutomaticSize = Enum.AutomaticSize.X
		return label
	end
	chip = {
		frame = frame,
		hands = words("Hands", 2, ""),
		dot = words("Dot", 3, "·"),
		bed = words("Bed", 4, ""),
		pop = pop,
	}
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRow)
	frame:GetPropertyChangedSignal("Visible"):Connect(queueRow)
	frame.Parent = row
end

local function buildHint(row: Frame)
	local hint = UITheme.label(row, "", F.Body, UITheme.Sized("Hint").text, C.Cream)
	hint.Name = "Hint"
	hint.LayoutOrder = 2
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Size = UDim2.fromOffset(0, ROW_HEIGHT)
	hint.BackgroundColor3 = C.Ink
	hint.BackgroundTransparency = 0 -- solid, so cream stays 4.5:1 on grass and sky
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	UITheme.corner(hint, ROW_HEIGHT / 2)
	UITheme.padding(hint, 0, 14, 0, 14)
	local max = Instance.new("UISizeConstraint")
	max.MaxSize = Vector2.new(HINT_MAX, ROW_HEIGHT)
	max.Parent = hint
	hint:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRow)
	hint:GetPropertyChangedSignal("Visible"):Connect(queueRow)
	hintLabel, hintLimit = hint, max
end

-- The bottom line: the load chip, then the hint, centred above the tool
-- hotbar (placeRow fits it).
local function buildBottomRow(gui: ScreenGui)
	local row = Instance.new("Frame")
	row.Name = "BottomRow"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -UITheme.Bottom()) -- above the tool hotbar
	row.Size = UDim2.new()
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	local list = UITheme.list(row, ROW_GAP, true)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	buildChip(row)
	buildHint(row)
	row.Visible = not buildOpen
	row.Parent = gui
	bottomRow = row
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRow)
	refreshModal() -- a panel may already be open (HUD.SetModal before HUD.Start); fills the chip
	queueRow()
end

local function buildCorner(playerGui: Instance)
	-- The corner under and left of the cash row, in a layer of its own:
	-- under the shop panel's scrim, over the side buttons. Two right-aligned
	-- lines, stacked by a list, so each sits by the real size of the other.
	local gui = UITheme.Screen("Corner", UITheme.Layers.Corner)
	local frame = Instance.new("Frame")
	frame.Name = "Shelf"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -UITheme.Margin(), 0, HudLayout.CornerTopPad) -- the cash row's spot
	frame.Size = UDim2.new()
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundTransparency = 1
	UITheme.list(frame, 7).HorizontalAlignment = Enum.HorizontalAlignment.Right
	frame.Parent = gui
	local function line(name: string, order: number): Frame
		local l = Instance.new("Frame")
		l.Name = name
		l.LayoutOrder = order
		l.Size = UDim2.new()
		l.AutomaticSize = Enum.AutomaticSize.XY
		l.BackgroundTransparency = 1
		local list = UITheme.list(l, 8, true)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Right
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		l.Parent = frame
		return l
	end
	local beside = line("BesideCash", 1)
	-- A space the size of the cash row (drawn in the HUD's layer) ends the
	-- first line: the line's buttons sit left of the row, the second line
	-- under it.
	local space = Instance.new("Frame")
	space.Name = "CashRow"
	space.LayoutOrder = 1000
	space.BackgroundTransparency = 1
	space.Parent = beside
	local row = HUD.TopRow()
	if row then
		local function fit()
			local scale = UITheme.Scale()
			space.Size = UDim2.fromOffset(row.AbsoluteSize.X / scale, row.AbsoluteSize.Y / scale)
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end
	besideCash, underCash, shelf = beside, line("UnderCash", 2), frame
	beside:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTopRow) -- STORE or the clock appearing
	task.defer(placeTopRow)
	local function moved()
		placePopups()
		queueArrange()
		queueToasts()
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(moved)
	frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(moved)
	gui.Parent = playerGui
end

-- Roblox's touch controls make a jump button once touch is used; the side
-- buttons end just above it.
local function watchJump(playerGui: Instance)
	local touch = playerGui:WaitForChild("TouchGui", math.huge)
	local controls = if touch then touch:WaitForChild("TouchControlFrame", math.huge) else nil
	local jump = if controls then controls:WaitForChild("JumpButton", math.huge) else nil
	if jump and jump:IsA("GuiObject") then
		jumpButton = jump
		jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueArrange)
		jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueArrange)
		jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueRow)
		jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRow)
		jump:GetPropertyChangedSignal("Visible"):Connect(queueRow)
		queueArrange()
		queueRow()
	end
end

local function buildSideColumn(playerGui: Instance)
	-- Its own screen, under the shop panel's scrim (which blocks HUD taps)
	-- and the corner's popups, and measured from the true screen centre:
	-- the device's safe area, the top bar's strip included (clear of a
	-- notch and the home bar).
	local gui = UITheme.Screen("SideButtons", UITheme.Layers.SideButtons, "device")
	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(1, 1)
	column.Size = UDim2.new() -- arrangeSide moves it and stacks the buttons up and left of it
	column.BackgroundTransparency = 1
	column.Parent = gui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueArrange)
	gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueArrange) -- the safe area's insets arriving
	gui.Parent = playerGui
	sideGui, sideColumn = gui, column
	task.spawn(watchJump, playerGui)
	queueArrange()
end

-- What the loading card says (HudRules.LoadingText), or hidden once the
-- save is in.
local function refreshLoading()
	local card, label = loadingCard, loadingLabel
	if not card or not label then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes") ~= nil
	local loaded = player:GetAttribute("ProfileLoaded")
	local text = HudRules.LoadingText(remotes, loaded)
	card.Visible = text ~= nil
	if text then
		-- The server's milestone (LoadStage) drives the line and the bar, so
		-- the wait reads as progress ("Shaping the land... 40%"), not a freeze.
		local fill, stageText = LoadStages.Describe(workspace:GetAttribute("LoadStage"), remotes, loaded)
		local shown = string.format("%s %s", stageText or text, LoadStages.Percent(fill))
		if label.Text ~= shown then
			label.Text = shown
		end
		local bar = loadingFill
		if bar then
			bar.Size = UDim2.fromScale(math.min(1, math.max(0, fill)), 1)
		end
	end
end

local function buildLoading(gui: ScreenGui)
	local card = UITheme.Card(C.Bark, C.Ink, 3, 14, true)
	card.outer.Name = "Loading"
	card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	card.outer.Position = UDim2.fromScale(0.5, 0.5)
	UITheme.padding(card.face, 12, 22, 12, 22)
	local label = UITheme.label(card.face, "", F.Heading, 24, C.Cream)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	-- The progress bar under the line: a dark track and a cream fill.
	local track = Instance.new("Frame")
	track.Name = "LoadBar"
	track.Position = UDim2.new(0, 0, 1, 4) -- right under the line, in the card's bottom padding
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = C.Ink
	track.BackgroundTransparency = 0.4
	track.BorderSizePixel = 0
	track.Parent = label
	local fillBar = Instance.new("Frame")
	fillBar.Name = "Fill"
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.BackgroundColor3 = C.Cream
	fillBar.BorderSizePixel = 0
	fillBar.Parent = track
	loadingFill = fillBar
	card.outer.Parent = gui
	loadingCard, loadingLabel = card.outer, label
	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(refreshLoading)
	workspace:GetAttributeChangedSignal("LoadStage"):Connect(refreshLoading)
	refreshLoading()
end

-- The server's remotes: GameServer makes the Remotes folder once the world
-- is built, which on a new server takes a while. Waited for in short tries
-- (a bare WaitForChild warns of an infinite yield after 5 s), then the
-- loading card moves on to the save. After this, Net.Remote finds each
-- remote at once (GameServer fills the folder before it parents it).
local function waitForRemotes()
	while not ReplicatedStorage:FindFirstChild("Remotes") do
		ReplicatedStorage:WaitForChild("Remotes", REMOTES_WAIT)
	end
	refreshLoading()
end

-- Nothing in here waits before the loading card is up (PlayerGui aside,
-- which UITheme waits for in short tries); the remotes are waited for last.
function HUD.Start()
	UITheme.Start()
	local playerGui = UITheme.PlayerGui()
	-- Above panels like the shop, so the cash and toasts stay visible.
	local gui = UITheme.Screen("TimberlineHUD", UITheme.Layers.Hud)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, GameConfig.ShowRobloxPlayerList)

	buildCash(playerGui)
	buildBottomRow(gui)

	-- The toasts' lane: top centre (the spec's y 44, under the top bar)
	-- until placeToasts moves it clear of the corner and the left column.
	local stack = Instance.new("Frame")
	stack.Name = "Toasts"
	stack.Position = UDim2.new(0.5, -TOAST_WIDTH / 2, 0, 8)
	stack.Size = UDim2.fromOffset(TOAST_WIDTH, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.BackgroundTransparency = 1
	local list = UITheme.list(stack, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.Parent = gui
	toastStack, toastList, hudGui = stack, list, gui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueToasts)

	buildLoading(gui)
	gui.Parent = playerGui
	buildCorner(playerGui)
	buildSideColumn(playerGui)
	-- The left column (the tracker) is made by the first controller that
	-- puts something in it: keep the toasts clear of it from then on.
	UITheme.WatchLeftColumn(function(column: Frame)
		leftColumn = column
		column:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueToasts)
		column:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueToasts)
		queueToasts()
	end)
	UITheme.WatchChat(queueToasts)
	refreshDevice()
	UserInputService.LastInputTypeChanged:Connect(refreshDevice)
	for _, name in ipairs({ "CarriedLogs", "BedCount", "BedCapacity" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshChip)
	end
	task.spawn(watchHintSources)
	UserInputService.InputBegan:Connect(onGamepad)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(syncPad)
	syncPad()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = true
		prompt.PromptHidden:Once(function()
			shownPrompts[prompt] = nil
		end)
	end)

	-- Server is authoritative: seed from the attribute (once the save has
	-- set it), then listen.
	local initial = player:GetAttribute("Cash")
	if type(initial) == "number" then
		setCash(initial)
	else
		showCash(0)
	end
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		setCash((player:GetAttribute("Cash") :: number?) or 0)
	end)
	-- Last, in its own thread: the server's remotes can take the whole world
	-- build (35 s on a new server in Studio, 7 October 2026), and Start
	-- returning at once lets Client.client start every other controller now
	-- instead of after that wait. The card's bar and line (LoadStages) say
	-- what the server is doing meanwhile; the controllers that need a remote
	-- wait for it themselves (Net.Remote).
	task.spawn(function()
		waitForRemotes()
		-- MapBuilder published the core loop before the server made its
		-- remotes: the v2 loop's chip and hint sources start now, if it's v2
		-- (or whenever the attribute lands, should it come late).
		workspace:GetAttributeChangedSignal(CoreLoop.ActiveAttribute):Connect(watchV2)
		watchV2()
		Net.Remote("CashChanged").OnClientEvent:Connect(setCash)
		Net.Remote("Notify").OnClientEvent:Connect(function(message: unknown, seconds: unknown)
			if type(message) == "string" then
				HUD.Toast(message, if type(seconds) == "number" then seconds else nil)
			end
		end)
	end)
end

return HUD
