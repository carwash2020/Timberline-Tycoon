--!strict
-- LogicPanelUI: the Set panel for a Delay, a Sustain or a Clock.
-- Opens from that piece's Set prompt. Plus and minus step the saved
-- number and fire LogicSet(uid, key, value) when that remote exists.
-- Mouse, touch and a gamepad all reach the same buttons. The stick moves
-- between them and A presses. Left and Right on a keyboard step the value.
-- The d-pad stays the HUD's. Keys are bound only while the panel is open,
-- and unbound on close. B closes.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GamepadNav = require(script.Parent.GamepadNav)
local UITheme = require(script.Parent.UITheme)

local LogicPanelUI = {}

local player = Players.LocalPlayer
local C = UITheme.Colors

-- Lane U owns UITheme. These are the Sparkworks values it does not have yet.
-- Fills, edges and ink come from UITheme.Colors and the skip, amber and buy
-- styles. U can fold Layer in as UITheme.Layers.LogicPanel.
local SparkworksTheme = {
	Layer = 16, -- over QuickMenu (15), under Store (20)
}
local ACTIONS = { "LogicMinus", "LogicPlus", "LogicClose" }

local open = false
local uid = ""
local key = ""
local value = 1
local minValue = 0.1
local maxValue = 10
local step = 0.1
local titleLabel: TextLabel? = nil
local valueLabel: TextLabel? = nil
local card: Frame? = nil
local minusButton: UITheme.Button? = nil
local inputConn: RBXScriptConnection? = nil

local function formatSeconds(n: number): string
	local rounded = math.round(n * 10) / 10
	if math.abs(rounded - math.floor(rounded + 1e-6)) < 1e-4 then
		return string.format("%d s", rounded)
	end
	return string.format("%.1f s", rounded)
end

local function showValue()
	local label = valueLabel
	if label then
		label.Text = formatSeconds(value)
	end
end

local function fire()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if folder then folder:FindFirstChild("LogicSet") else nil
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(uid, key, value)
	end
end

local function close()
	if not open then
		return
	end
	open = false
	local panel = card
	if panel then
		panel.Visible = false
	end
	for _, name in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
	GamepadNav.Restore(panel)
end

local function nudge(dir: number)
	if not open then
		return
	end
	local nextValue = value + dir * step
	if nextValue < minValue - 1e-6 or nextValue > maxValue + 1e-6 then
		return
	end
	local snapped = math.round(nextValue / step) * step
	snapped = math.round(snapped * 10) / 10
	if snapped < minValue or snapped > maxValue then
		return
	end
	value = snapped
	showValue()
	fire()
end

local function bindPad()
	local function onAction(name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if name == "LogicClose" then
			close()
		elseif name == "LogicMinus" then
			nudge(-1)
		elseif name == "LogicPlus" then
			nudge(1)
		end
		return Enum.ContextActionResult.Sink
	end
	local top = Enum.ContextActionPriority.High.Value + 120
	ContextActionService:BindActionAtPriority("LogicMinus", onAction, false, top, Enum.KeyCode.Left, Enum.KeyCode.Minus)
	ContextActionService:BindActionAtPriority(
		"LogicPlus",
		onAction,
		false,
		top,
		Enum.KeyCode.Right,
		Enum.KeyCode.Equals
	)
	ContextActionService:BindActionAtPriority(
		"LogicClose",
		onAction,
		false,
		top,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not open then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)
end

local function openFrom(prompt: ProximityPrompt)
	local pieceUid = prompt:GetAttribute("Uid")
	local pieceKey = prompt:GetAttribute("LogicKey")
	local lo = prompt:GetAttribute("LogicMin")
	local hi = prompt:GetAttribute("LogicMax")
	local pieceStep = prompt:GetAttribute("LogicStep")
	local current = prompt:GetAttribute("LogicValue")
	if
		type(pieceUid) ~= "string"
		or type(pieceKey) ~= "string"
		or type(lo) ~= "number"
		or type(hi) ~= "number"
		or type(pieceStep) ~= "number"
		or pieceStep <= 0
	then
		return
	end
	uid = pieceUid
	key = pieceKey
	minValue = lo
	maxValue = hi
	step = pieceStep
	value = if type(current) == "number" then current else lo
	local title = titleLabel
	if title then
		title.Text = if prompt.ObjectText ~= "" then prompt.ObjectText else "Set"
	end
	showValue()
	local panel = card
	if panel then
		panel.Visible = true
	end
	local was = open
	open = true
	if not was then
		bindPad()
	end
	local first = if minusButton then minusButton.face else nil
	GamepadNav.Focus(first, panel)
end

function LogicPanelUI.Start()
	local screen = UITheme.Screen("LogicPanel", SparkworksTheme.Layer)
	local panel = Instance.new("Frame")
	panel.Name = "Card"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 16)
	panel.Size = UDim2.fromOffset(320, 220)
	panel.BackgroundColor3 = C.Paper
	panel.BorderSizePixel = 0
	panel.Visible = false
	UITheme.corner(panel, 12)
	UITheme.stroke(panel, C.Bark, 2)
	panel.Parent = screen
	card = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 14)
	title.Size = UDim2.new(1, -32, 0, 28)
	title.Font = UITheme.Fonts.Heading
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3 = C.Ink
	title.Text = "Delay"
	title.Parent = panel
	titleLabel = title

	local valueText = Instance.new("TextLabel")
	valueText.Name = "Value"
	valueText.BackgroundTransparency = 1
	valueText.Position = UDim2.fromOffset(16, 48)
	valueText.Size = UDim2.new(1, -32, 0, 36)
	valueText.Font = UITheme.Fonts.Black
	valueText.TextSize = 28
	valueText.TextXAlignment = Enum.TextXAlignment.Center
	valueText.TextColor3 = C.Ink
	valueText.Text = "1 s"
	valueText.Parent = panel
	valueLabel = valueText

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(16, 100)
	row.Size = UDim2.new(1, -32, 0, 52)
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local minus = UITheme.Button({
		text = "-",
		size = Vector2.new(96, 48),
		style = "skip",
		textSize = 22,
		name = "Minus",
	})
	minus.root.LayoutOrder = 1
	minus.root.Parent = row
	minus.face.Activated:Connect(function()
		nudge(-1)
	end)
	minusButton = minus

	local plus = UITheme.Button({
		text = "+",
		size = Vector2.new(96, 48),
		style = "amber",
		textSize = 22,
		name = "Plus",
	})
	plus.root.LayoutOrder = 2
	plus.root.Parent = row
	plus.face.Activated:Connect(function()
		nudge(1)
	end)

	local done = UITheme.Button({
		text = "Done",
		size = Vector2.new(280, 44),
		style = "buy",
		textSize = 16,
		name = "Done",
	})
	done.root.Position = UDim2.fromOffset(20, 156)
	done.root.Parent = panel
	done.face.Activated:Connect(close)
	-- UITheme.Button already scales the label to the face. Say it here so
	-- the three labels stay readable if that default changes.
	for _, button in ipairs({ minus, plus, done }) do
		button.face.TextScaled = true
	end

	screen.Parent = player:WaitForChild("PlayerGui")

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt.Name ~= "SetPrompt" then
			return
		end
		openFrom(prompt)
	end)
end

return LogicPanelUI
