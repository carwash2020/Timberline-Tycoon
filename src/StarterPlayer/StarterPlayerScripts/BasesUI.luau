--!strict
-- BasesUI: Old Hank's crates. Opens when the server says so (BaseState with
-- open = true: you said Yes to "show me my bases" at the Land Office
-- counter). It lists the base on your pad and the ones crated away, with
-- big buttons: PACK UP (crate it, give up the pad), NEW BASE (crate it,
-- start a fresh one on this pad), BRING OUT / SWAP IN (a crated base), and
-- PICK A PAD when you have none. Every change asks first (a confirm card)
-- and the server checks it all again: range, cooldown, shelf room, loose
-- wood, one change at a time (PlotService.BaseAction, rules in
-- Shared/BaseLogic). Nothing here moves a piece or a coin.
--
-- Phone and Xbox: buttons are UITheme's tap size, text 14 px or more, the
-- stick stays inside the panel (MenuPad / GamepadNav), B and Esc go back
-- one step (the confirm card, then the panel).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseLogic = require(ReplicatedStorage.Shared.BaseLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Net = require(ReplicatedStorage.Shared.Net)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local BasesUI = {}

local C = UITheme.Colors
local player = Players.LocalPlayer

local CLOSE = "BasesClose"

export type State = {
	open: boolean?,
	hasPad: boolean,
	cap: number,
	cooldownUntil: number,
	live: { name: string, tier: string, pieces: number, empty: boolean },
	shelf: { BaseLogic.Row },
}

local state: State? = nil
local panel: Frame? = nil
local rows: ScrollingFrame? = nil
local note: TextLabel? = nil
local confirm: Frame? = nil
local confirmText: TextLabel? = nil
local pending: { action: string, index: number? }? = nil
local firstPick: GuiButton? = nil

local function send(action: string, index: number?)
	Net.Remote("BaseAction"):FireServer(action, index)
end

local function hideConfirm()
	pending = nil
	local c = confirm
	if c then
		c.Visible = false
	end
end

local function ask(action: string, index: number?, name: string)
	local s = state
	pending = { action = action, index = index }
	local label = confirmText
	if label and s then
		label.Text = BaseLogic.ConfirmText(action, name, s.hasPad)
	end
	local c = confirm
	if c then
		c.Visible = true
	end
end

local function button(parent: Instance, text: string, style: string, order: number, enabled: boolean, fn: () -> ())
	local b = UITheme.Button({
		text = text,
		size = Vector2.new(150, math.max(44, UITheme.Size.Tap)),
		style = style,
		textSize = 15,
	})
	b.root.LayoutOrder = order
	b.root.Parent = parent
	b.face.Active = enabled
	b.face.AutoButtonColor = enabled
	b.face.Activated:Connect(function()
		if enabled then
			fn()
		end
	end)
	if firstPick == nil and enabled then
		firstPick = b.face
	end
	return b
end

local function card(holder: Instance, order: number, accent: boolean): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, 132)
	f.BackgroundColor3 = if accent then C.PaperDark else C.Paper
	f.BorderSizePixel = 0
	UITheme.corner(f, 10)
	UITheme.stroke(f, if accent then C.GreenEdge else C.Bark, 2)
	f.Parent = holder
	return f
end

local function line(parent: Instance, text: string, y: number, size: number, font: Enum.Font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = C.Ink
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Size = UDim2.new(1, -16, 0, size + 6)
	l.Position = UDim2.fromOffset(8, y)
	l.Text = text
	l.Parent = parent
	return l
end

local function fill()
	local holder = rows
	local s = state
	if not holder or not s then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	firstPick = nil
	local now = os.time()
	local cooling = now < s.cooldownUntil
	local label = note
	if label then
		label.Text = if cooling
			then string.format("You can change bases again in %ds.", math.ceil(s.cooldownUntil - now))
			else "Crated bases keep every piece, pad and tier. Nothing is sold and nothing is lost."
	end

	-- The base on your pad (or the one waiting for a pad).
	local here = card(holder, 1, true)
	line(here, if s.hasPad then "ON YOUR PAD" else "NO PAD RIGHT NOW", 6, 13, UITheme.Fonts.Body)
	line(here, s.live.name, 24, 18, UITheme.Fonts.Heading)
	line(here, string.format("%s  ·  %d pieces", s.live.tier, s.live.pieces), 50, 14, UITheme.Fonts.Body)
	local bar = Instance.new("Frame")
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, -16, 0, 48)
	bar.Position = UDim2.fromOffset(8, 78)
	UITheme.list(bar, 8, true)
	bar.Parent = here
	if s.hasPad then
		local full = #s.shelf >= s.cap
		button(bar, "PACK UP", "buy", 1, not cooling and not s.live.empty and not full, function()
			ask("pack", nil, s.live.name)
		end)
		button(bar, "NEW BASE", "skip", 2, not cooling and not s.live.empty and not full, function()
			ask("new", nil, s.live.name)
		end)
	else
		button(bar, "PICK A PAD", "buy", 1, true, function()
			send("pad", nil)
			BasesUI.Close()
		end)
	end

	for _, base in ipairs(s.shelf) do
		local c = card(holder, 10 + base.index, false)
		line(c, "CRATED", 6, 13, UITheme.Fonts.Body)
		line(c, base.name, 24, 18, UITheme.Fonts.Heading)
		local saved = SaveSlotLogic.SavedText(base.savedAt, now)
		line(
			c,
			string.format("Tier %d  ·  %d pieces  ·  %s", base.tier, base.pieces, saved),
			50,
			14,
			UITheme.Fonts.Body
		)
		local b = Instance.new("Frame")
		b.BackgroundTransparency = 1
		b.Size = UDim2.new(1, -16, 0, 48)
		b.Position = UDim2.fromOffset(8, 78)
		UITheme.list(b, 8, true)
		b.Parent = c
		local index = base.index
		local name = base.name
		button(b, if s.hasPad then "SWAP IN" else "BRING OUT", "buy", 1, not cooling, function()
			ask("bring", index, name)
		end)
	end
end

function BasesUI.IsOpen(): boolean
	local p = panel
	return p ~= nil and p.Visible
end

function BasesUI.Close()
	local p = panel
	if not p then
		return
	end
	p.Visible = false
	hideConfirm()
	ContextActionService:UnbindAction(CLOSE)
	MenuPad.Close(p)
end

local function open()
	local p = panel
	if not p then
		return
	end
	local was = p.Visible
	p.Visible = true
	fill()
	if was then
		return
	end
	ContextActionService:BindActionAtPriority(
		CLOSE,
		function(_name, input)
			if input ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if confirm and confirm.Visible then
				hideConfirm()
			else
				BasesUI.Close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 20,
		InputKit.Actions.Cancel.keyboard,
		InputKit.Actions.Cancel.gamepad
	)
	local pick = firstPick
	if pick and UITheme.Device() == "console" then
		MenuPad.Open(pick, p)
	end
end

function BasesUI.Start()
	local screen = UITheme.Screen("BasesUI", UITheme.Layers.Bases)
	screen.Parent = UITheme.PlayerGui()

	local outer = Instance.new("Frame")
	outer.Name = "Bases"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromOffset(380, 380)
	outer.BackgroundColor3 = C.Paper
	outer.BorderSizePixel = 0
	outer.Visible = false
	UITheme.corner(outer, 14)
	UITheme.stroke(outer, C.Bark, 3)
	outer.Parent = screen
	panel = outer

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = UITheme.Fonts.Heading
	title.TextSize = 26
	title.TextColor3 = C.Ink
	title.Size = UDim2.new(1, -70, 0, 36)
	title.Position = UDim2.fromOffset(16, 10)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Your bases"
	title.Parent = outer

	local close = UITheme.Button({ text = "X", size = Vector2.new(44, 44), style = "skip", textSize = 18 })
	close.root.Position = UDim2.new(1, -52, 0, 8)
	close.root.Parent = outer
	close.face.Activated:Connect(BasesUI.Close)

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Font = UITheme.Fonts.Body
	hint.TextSize = 14
	hint.TextColor3 = C.Ink
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Size = UDim2.new(1, -24, 0, 36)
	hint.Position = UDim2.fromOffset(12, 48)
	hint.Text = ""
	hint.Parent = outer
	note = hint

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 88)
	list.Size = UDim2.new(1, -24, 1, -100)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Selectable = false
	UITheme.list(list, 8)
	list.Parent = outer
	rows = list

	local ask2 = Instance.new("Frame")
	ask2.Name = "Confirm"
	ask2.Size = UDim2.fromScale(1, 1)
	ask2.BackgroundColor3 = C.Bark
	ask2.BackgroundTransparency = 0.15
	ask2.Visible = false
	ask2.ZIndex = 5
	UITheme.corner(ask2, 14)
	ask2.Parent = outer
	confirm = ask2

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = UITheme.Fonts.Body
	text.TextSize = 16
	text.TextColor3 = C.Cream
	text.TextWrapped = true
	text.Size = UDim2.new(1, -28, 0, 150)
	text.Position = UDim2.fromOffset(14, 90)
	text.ZIndex = 6
	text.Parent = ask2
	confirmText = text

	local yes = UITheme.Button({ text = "CONFIRM", size = Vector2.new(150, 52), style = "buy", textSize = 16 })
	yes.root.Position = UDim2.new(0.5, -156, 1, -76)
	yes.root.ZIndex = 6
	yes.root.Parent = ask2
	yes.face.ZIndex = 6
	yes.face.Activated:Connect(function()
		local want = pending
		hideConfirm()
		if want then
			send(want.action, want.index)
		end
	end)

	local no = UITheme.Button({ text = "CANCEL", size = Vector2.new(150, 52), style = "skip", textSize = 16 })
	no.root.Position = UDim2.new(0.5, 6, 1, -76)
	no.root.ZIndex = 6
	no.root.Parent = ask2
	no.face.ZIndex = 6
	no.face.Activated:Connect(hideConfirm)

	-- The plot picker takes the screen (a base with no pad is being placed).
	player:GetAttributeChangedSignal("Picking"):Connect(function()
		if player:GetAttribute("Picking") == true then
			BasesUI.Close()
		end
	end)

	Net.Remote("BaseState").OnClientEvent:Connect(function(payload: unknown)
		if type(payload) ~= "table" then
			return
		end
		local data = payload :: any
		if type(data.live) ~= "table" or type(data.shelf) ~= "table" then
			return
		end
		state = data :: State
		if data.open == true then
			open()
		elseif BasesUI.IsOpen() then
			fill()
		end
	end)
end

return BasesUI
