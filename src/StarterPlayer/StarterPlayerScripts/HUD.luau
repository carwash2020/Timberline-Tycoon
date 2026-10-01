--!strict
-- HUD: the always-on screen (UI spec 01, look from UITheme).
--   * Cash plaque top right, below Roblox's top bar (Roblox's player list,
--     which would cover it, is off: GameConfig). At the wallet cap it turns
--     amber and reads MAX.
--   * Toasts: short messages from the server (Notify) or other controllers,
--     top centre, newest on top, up to three (older ones fade back).
--     Amounts of money show in green.
--   * A one-line control hint at the bottom (above Roblox's tool hotbar),
--     worded for the device in use.
--   * The side buttons: a column on the right (Drop axe, Truck to lot, ...)
--     that other controllers add to with HUD.SideButton. It ends above a
--     phone's jump button. On a gamepad each shows its button glyph, and
--     that button presses it (unless a world prompt is using the same one).
--   * "Loading your save..." until the server says the profile is ready.
--   * Money in or out pops beside the plaque ("+$1,250") and the plaque
--     counts up to the new amount. The plaque sits in a top-right row
--     (HUD.TopRow) that SettingsUI adds its button to.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local UITheme = require(script.Parent.UITheme)

local HUD = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local MAX_TOASTS = 3
local TOAST_SECONDS = 3
local TOAST_FADE = 0.25
local TOAST_ALPHA = { 0, 0.15, 0.3 } -- newest, then older ones at 85% and 70%

type Toast = { outer: Frame, face: ImageLabel, label: TextLabel, stroke: UIStroke }

type Side = {
	button: UITheme.Button,
	key: Enum.KeyCode?,
	glyph: GuiObject?,
	onPress: () -> (),
}

local cashFace: ImageLabel? = nil
local cashInner: Frame? = nil
local cashLabel: TextLabel? = nil
local cashOuter: Frame? = nil
local cashGlow: UIStroke? = nil
local cashPops: Frame? = nil -- a zero-size spot at the row's left end the pops float from
local cashShown: NumberValue? = nil -- what the plaque shows; tweens toward the real amount
local cashTarget: number? = nil -- the real amount (nil until the first update)
local toastStack: Frame? = nil
local toasts: { Toast } = {}
local toastOrder = 0
local hintLabel: TextLabel? = nil
local sideColumn: Frame? = nil
local sides: { Side } = {}
local shownPrompts: { [ProximityPrompt]: boolean } = {}

---------------------------------------------------------------------------
-- Cash
---------------------------------------------------------------------------

local function showCash(amount: number)
	local label = cashLabel
	if not label then
		return
	end
	local full = amount >= GameConfig.CashCap
	label.Text = if full then "MAX" else Util.formatCash(math.floor(amount + 0.5))
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
	local pop = UITheme.label(spot, text, F.Heading, if gain then 24 else 20, if gain then C.Money else C.Ink)
	pop.Name = "CashPop"
	pop.AnchorPoint = Vector2.new(1, 0.5)
	pop.AutomaticSize = Enum.AutomaticSize.XY
	pop.Size = UDim2.fromOffset(0, 0)
	pop.TextXAlignment = Enum.TextXAlignment.Right
	local start = UDim2.fromOffset(-4, 0)
	pop.Position = start
	local stroke = UITheme.stroke(pop, C.Cream, 2)
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

-- The top-right row holding the cash plaque (LayoutOrder 10). Other
-- controllers add small buttons to its left with lower LayoutOrders.
-- Nil before HUD.Start.
function HUD.TopRow(): Frame?
	return if cashOuter then cashOuter.Parent :: Frame? else nil
end

-- Shows a short message at the top of the screen for a few seconds.
function HUD.Toast(message: string)
	local stack = toastStack
	if not stack then
		return
	end
	while #toasts >= MAX_TOASTS do
		removeToast(toasts[#toasts])
	end
	toastOrder += 1
	local card = UITheme.Card(C.Paper, C.Ink, 2, 16, true)
	card.outer.Name = "Toast"
	card.outer.LayoutOrder = -toastOrder -- newest on top
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(280, math.huge)
	limit.MinSize = Vector2.new(0, 34)
	limit.Parent = card.outer
	local stroke = UITheme.stroke(card.face, C.Bark, 2)
	UITheme.padding(card.face, 7, 14, 7, 14)
	local label = UITheme.label(card.face, "", F.Bold, 13, C.Ink)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.TextWrapped = true
	label.RichText = true
	label.Text = richToast(message)
	local labelLimit = Instance.new("UISizeConstraint")
	labelLimit.MaxSize = Vector2.new(252, math.huge)
	labelLimit.Parent = label
	card.outer.Parent = stack

	local toast: Toast = { outer = card.outer, face = card.face, label = label, stroke = stroke }
	table.insert(toasts, 1, toast)
	restack()

	task.delay(TOAST_SECONDS, function()
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

---------------------------------------------------------------------------
-- Hint and side buttons, by device
---------------------------------------------------------------------------

local HINTS: { [UITheme.Device]: string } = {
	phone = "Tap a tree to swing your axe",
	desktop = "Click a tree to swing · E to interact",
	console = "RT to swing · X to interact",
}

-- Whether a world prompt that uses `key` is showing (it gets the press).
local function promptOn(key: Enum.KeyCode): boolean
	for prompt in pairs(shownPrompts) do
		if prompt.Enabled and prompt.GamepadKeyCode == key then
			return true
		end
	end
	return false
end

local function layoutSide(side: Side, device: UITheme.Device)
	local phone = UITheme.IsPhone()
	local console = device == "console" and side.key ~= nil
	local width = if console then 150 elseif phone then 100 else 110
	local height = if phone then 36 else 40
	side.button.root.Size = UDim2.fromOffset(width, height + 3)
	side.button.face.TextSize = if phone then 12 else 13
	local fit = side.button.face:FindFirstChildOfClass("UITextSizeConstraint")
	if fit then
		fit.MaxTextSize = if phone then 12 else 13
	end
	local pad = side.button.face:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, if console then 36 else 6)
	end
	if side.glyph then
		side.glyph.Visible = console
	end
end

local function refreshDevice()
	local device: UITheme.Device = UITheme.Device()
	local hint = hintLabel
	if hint then
		hint.Text = HINTS[device]
	end
	for _, side in ipairs(sides) do
		layoutSide(side, device)
	end
end

export type SideOptions = {
	name: string,
	text: string,
	style: string,
	order: number, -- top to bottom
	key: Enum.KeyCode?, -- the gamepad button that presses it
	onPress: () -> (),
}

-- Adds a button to the right-hand column (hidden until you show it:
-- set `.root.Visible`). Pressing it, or its gamepad button, calls onPress.
function HUD.SideButton(opts: SideOptions): UITheme.Button
	local column = sideColumn
	assert(column, "[HUD] SideButton before HUD.Start")
	local button = UITheme.Button({
		name = opts.name,
		text = opts.text,
		size = Vector2.new(110, 40),
		style = opts.style,
		textSize = 13,
		radius = 12,
	})
	button.root.LayoutOrder = opts.order
	button.root.Visible = false
	local glyph: GuiObject? = nil
	if opts.key then
		local g = UITheme.Glyph(opts.key, 22)
		g.AnchorPoint = Vector2.new(0, 0.5)
		g.Position = UDim2.new(0, -26, 0.5, 0) -- in the face's left padding
		g.Parent = button.face
		glyph = g
	end
	button.root.Parent = column
	button.face.Activated:Connect(opts.onPress)
	local side: Side = { button = button, key = opts.key, glyph = glyph, onPress = opts.onPress }
	table.insert(sides, side)
	local device: UITheme.Device = UITheme.Device()
	layoutSide(side, device)
	return button
end

local function onGamepad(input: InputObject, processed: boolean)
	if processed or GuiService.SelectedObject ~= nil then
		return -- a menu has the pad
	end
	for _, side in ipairs(sides) do
		if side.key == input.KeyCode and side.button.root.Visible and not promptOn(input.KeyCode) then
			side.onPress()
			return
		end
	end
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function buildCash(gui: ScreenGui)
	local side = UITheme.Margin()
	local card = UITheme.Card(C.Bark, C.Ink, 3, 14, true)
	card.outer.Name = "CashPlaque"
	card.outer.LayoutOrder = 10
	-- The top-right row (HUD.TopRow): [pops][other buttons][plaque].
	local row = Instance.new("Frame")
	row.Name = "TopRow"
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.new(1, -side, 0, 8)
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
	min.MinSize = Vector2.new(150, 49)
	min.Parent = card.outer
	local glow = UITheme.stroke(card.outer, C.Amber, 4)
	glow.Transparency = 0.45
	glow.Enabled = false
	UITheme.padding(card.face, 4, 4, 4, 4)
	UITheme.texture(card.face, "Wood", 14)

	local inner = Instance.new("Frame")
	inner.Name = "Paper"
	inner.AutomaticSize = Enum.AutomaticSize.X
	inner.Size = UDim2.fromOffset(0, 38)
	inner.BackgroundColor3 = C.Paper
	inner.BorderSizePixel = 0
	UITheme.corner(inner, 10)
	UITheme.padding(inner, 0, 14, 0, 14)
	inner.Parent = card.face
	local innerMin = Instance.new("UISizeConstraint")
	innerMin.MinSize = Vector2.new(142, 38)
	innerMin.Parent = inner

	local label = UITheme.label(inner, "$0", F.Heading, 26, C.Ink)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	local labelMin = Instance.new("UISizeConstraint")
	labelMin.MinSize = Vector2.new(114, 0)
	labelMin.Parent = label

	local shown = Instance.new("NumberValue")
	shown.Name = "CashShown"
	shown.Changed:Connect(function(value: number)
		showCash(value)
	end)
	shown.Parent = card.outer

	card.outer.Parent = row
	row.Parent = gui
	cashOuter, cashFace, cashInner, cashLabel, cashGlow = card.outer, card.face, inner, label, glow
	cashPops, cashShown = pops, shown
end

local function buildHint(gui: ScreenGui)
	local hint = UITheme.label(gui, "", F.Body, 13, C.Cream)
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -UITheme.Bottom()) -- above the tool hotbar
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Size = UDim2.fromOffset(0, 30)
	hint.BackgroundColor3 = C.Ink
	hint.BackgroundTransparency = 0.2
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	UITheme.corner(hint, 15)
	UITheme.padding(hint, 0, 14, 0, 14)
	local max = Instance.new("UISizeConstraint")
	max.MaxSize = Vector2.new(320, 30)
	max.Parent = hint
	hintLabel = hint
end

local function buildSideColumn()
	-- Its own screen, under the shop panel's scrim (which blocks HUD taps),
	-- and measured from the true screen centre.
	local gui = UITheme.Screen("SideButtons", 1, true)
	local side = UITheme.Margin()
	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(1, 1)
	-- The bottom stays 44 below the centre (y 239 on a 390-tall phone), so
	-- however many buttons show, they never reach the jump button.
	column.Position = UDim2.new(1, -side, 0.5, 44)
	column.AutomaticSize = Enum.AutomaticSize.XY
	column.BackgroundTransparency = 1
	local list = UITheme.list(column, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	column.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	sideColumn = column
end

local function buildLoading(gui: ScreenGui)
	local card = UITheme.Card(C.Bark, C.Ink, 3, 14, true)
	card.outer.Name = "Loading"
	card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	card.outer.Position = UDim2.fromScale(0.5, 0.5)
	UITheme.padding(card.face, 12, 22, 12, 22)
	local label = UITheme.label(card.face, "Loading your save...", F.Heading, 24, C.Cream)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	card.outer.Parent = gui
	local function refreshLoading()
		card.outer.Visible = player:GetAttribute("ProfileLoaded") ~= true
	end
	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(refreshLoading)
	refreshLoading()
end

function HUD.Start()
	UITheme.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Above panels like the shop, so the cash and toasts stay visible.
	local gui = UITheme.Screen("TimberlineHUD", 10)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, GameConfig.ShowRobloxPlayerList)

	buildCash(gui)
	buildHint(gui)

	local stack = Instance.new("Frame")
	stack.Name = "Toasts"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 8) -- the spec's y 44, under the top bar
	stack.Size = UDim2.fromOffset(0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.XY
	stack.BackgroundTransparency = 1
	local list = UITheme.list(stack, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.Parent = gui
	toastStack = stack

	buildLoading(gui)
	gui.Parent = playerGui
	buildSideColumn()
	refreshDevice()
	UserInputService.LastInputTypeChanged:Connect(refreshDevice)
	UserInputService.InputBegan:Connect(onGamepad)
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
	Net.Remote("CashChanged").OnClientEvent:Connect(setCash)
	Net.Remote("Notify").OnClientEvent:Connect(function(message: unknown)
		if type(message) == "string" then
			HUD.Toast(message)
		end
	end)
end

return HUD
