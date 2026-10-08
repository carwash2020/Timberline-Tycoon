--!strict
-- QualityPickerUI: the join screen that asks how the game should look.
-- "Lower quality (best for phones)" or "Higher quality (Xbox, PC, tablets)".
-- It shows once per account: when the save has loaded (ProfileLoaded) and
-- no choice is saved yet (SettingQuality is "unset", which is what every
-- old save and every new one starts as), over everything but Roblox's own
-- menu. The device's recommendation is pre-selected (a touch-only screen:
-- Lower; a console or a PC: Higher) and marked; the gamepad lands on it so A
-- is enough, and a tap or a click on either card chooses it. The choice goes
-- to the server (SetQuality: validated, rate limited, saved on the account)
-- and to Quality at once. It can be changed later in Settings (Graphics).
-- It never changes what anything costs or does: Shared/QualityProfile.
--
-- Parchment look like the other screens (UITheme). Both cards are far bigger
-- than a fingertip (UITheme.Size.Tap), text is 14 px or more, and the stick
-- stays inside the panel (GamepadNav). While it is up the character does not
-- walk, so nobody wanders off behind a screen they are reading.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local PickerSequence = require(ReplicatedStorage.Shared.PickerSequence)
local QualityProfile = require(ReplicatedStorage.Shared.QualityProfile)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local GamepadNav = require(script.Parent.GamepadNav)
local Quality = require(script.Parent.Quality)
local UITheme = require(script.Parent.UITheme)

local QualityPickerUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts
local player = Players.LocalPlayer

local ATTRIBUTE = SettingsLogic.QualityAttribute

local gui: ScreenGui? = nil
local panel: Frame? = nil
local cards: { [string]: TextButton } = {}
local open = false
local shownOnce = false -- once the player has chosen, the screen is done for this session
local controlsOff = false
local sequence = PickerSequence.Shared() -- the quality screen goes before the plot picker

-- What this device would pick.
function QualityPickerUI.Recommended(): QualityProfile.Choice
	return QualityProfile.Recommended(Quality.TouchOnly(), player:GetAttribute("SettingGraphics"))
end

-- Roblox's own movement controls (the PlayerModule): the screen switches them
-- off while it is up and back on after. A seam for the spec.
function QualityPickerUI._controls(): any?
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
	if module == nil then
		return nil
	end
	return (require(module :: ModuleScript) :: any):GetControls()
end

local function setControls(enabled: boolean)
	if enabled == not controlsOff then
		return
	end
	controlsOff = not enabled
	pcall(function(): any
		local controls = QualityPickerUI._controls()
		if controls then
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
		return nil
	end)
end

local function close()
	if not open then
		return
	end
	open = false
	local screen = gui
	if screen then
		screen.Enabled = false
	end
	setControls(true)
	GamepadNav.Restore(panel)
	sequence.Done("quality") -- the plot picker (if it is waiting) opens now
end

-- A choice was made: save it and let the world follow.
function QualityPickerUI.Choose(choice: QualityProfile.Choice)
	if not open or not QualityProfile.IsChoice(choice) then
		return
	end
	shownOnce = true
	player:SetAttribute(ATTRIBUTE, choice) -- the server sets it too; this lets the world follow at once
	-- Closed first: the screen holds the movement controls off, and nothing
	-- after this (a remote that is slow to arrive, a refresh that throws) may
	-- leave it up.
	close()
	Net.Remote("SetQuality"):FireServer(choice)
	Quality.Refresh()
end

local function card(parent: Frame, choice: QualityProfile.Choice, recommended: boolean, order: number): TextButton
	local option = QualityProfile.Options[choice]
	local button = Instance.new("TextButton")
	button.Name = "Choose" .. option.row
	button.LayoutOrder = order
	button.Size = UDim2.new(0.5, -6, 1, 0)
	button.BackgroundColor3 = C.Cream
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	UITheme.corner(button, 12)
	local outline = UITheme.stroke(button, if recommended then C.Amber else C.Bark, if recommended then 4 else 2)
	UITheme.padding(button, 10, 12, 10, 12)
	button.Parent = parent

	local list = UITheme.list(button, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local function text(name: string, content: string, font: Enum.Font, size: number, color: Color3, height: number)
		local label = UITheme.label(button, content, font, size, color)
		label.Name = name
		label.Size = UDim2.new(1, 0, 0, height)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		return label
	end
	local tag = text(
		"Tag",
		if recommended then QualityProfile.RecommendedTag else " ",
		F.Black,
		UITheme.Size.TextMin,
		C.AmberEdge,
		18
	)
	tag.LayoutOrder = 1
	local title = text("Title", option.title, F.Heading, 24, C.Ink, 30)
	title.LayoutOrder = 2
	local device = text("Device", "(" .. option.device .. ")", F.Bold, 16, C.Bark, 22)
	device.LayoutOrder = 3
	local blurb = text("Blurb", option.blurb, F.Body, UITheme.Size.TextBody, C.Bark, 60)
	blurb.LayoutOrder = 4

	button.SelectionGained:Connect(function()
		outline.Color = C.Green
		outline.Thickness = 5
		button.BackgroundColor3 = C.Paper
	end)
	button.SelectionLost:Connect(function()
		outline.Color = if recommended then C.Amber else C.Bark
		outline.Thickness = if recommended then 4 else 2
		button.BackgroundColor3 = C.Cream
	end)
	button.Activated:Connect(function()
		UITheme.Click()
		QualityPickerUI.Choose(choice)
	end)
	return button
end

local function build()
	local screen = UITheme.Screen("QualityPicker", UITheme.Layers.QualityPicker, "device")
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- The dim backdrop also eats every tap and click behind the panel.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Active = true
	backdrop.Selectable = false
	backdrop.Text = ""
	backdrop.Parent = screen

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(0.92, 0, 0, 300)
	frame.BackgroundColor3 = C.Paper
	frame.BorderSizePixel = 0
	UITheme.corner(frame, 14)
	UITheme.stroke(frame, C.Bark, 3)
	UITheme.padding(frame, 14, 16, 14, 16)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(600, 400)
	limit.MinSize = Vector2.new(280, 260)
	limit.Parent = frame
	frame.Parent = backdrop
	panel = frame

	local title = UITheme.label(frame, QualityProfile.PickerTitle, F.Heading, 26, C.Ink)
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local hint = UITheme.label(frame, QualityProfile.PickerHint, F.Body, UITheme.Size.TextBody, C.Bark)
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(0, 34)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.TextXAlignment = Enum.TextXAlignment.Center

	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 62)
	row.Size = UDim2.new(1, 0, 1, -62)
	row.Parent = frame
	local layout = UITheme.list(row, 12, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local recommended = QualityPickerUI.Recommended()
	cards.low = card(row, "low", recommended == "low", 1)
	cards.high = card(row, "high", recommended == "high", 2)
	cards.low.NextSelectionRight = cards.high
	cards.high.NextSelectionLeft = cards.low
	cards.low.NextSelectionLeft = cards.low
	cards.high.NextSelectionRight = cards.high
end

-- Moves the recommended tag to the card this device recommends (the device
-- can change before the screen shows: a keyboard plugged in).
local function markRecommended()
	local recommended = QualityPickerUI.Recommended()
	for choice, button in pairs(cards) do
		local tag = button:FindFirstChild("Tag")
		if tag and tag:IsA("TextLabel") then
			tag.Text = if choice == recommended then QualityProfile.RecommendedTag else " "
		end
		local outline = button:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Color = if choice == recommended then C.Amber else C.Bark
			outline.Thickness = if choice == recommended then 4 else 2
		end
	end
end

local function show()
	if open or shownOnce then
		return
	end
	local screen = gui
	if not screen then
		return
	end
	open = true
	sequence.Request("quality")
	markRecommended()
	screen.Enabled = true
	setControls(false)
	-- A gamepad (or a TV) lands on the recommendation so A is enough.
	if UITheme.Device() == "console" then
		local first = cards[QualityPickerUI.Recommended()]
		GamepadNav.Focus(first, panel)
	end
end

local function consider()
	if player:GetAttribute("ProfileLoaded") ~= true then
		return
	end
	if QualityProfile.NeedsPicker(player:GetAttribute(ATTRIBUTE)) then
		show()
	elseif open then
		-- The save says it is chosen already (another device, a slot swap): done.
		shownOnce = true
		close()
	end
end

function QualityPickerUI.Start()
	build()
	-- A gamepad picked up while the screen is up: put the selection on a card.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not open or GuiService.SelectedObject ~= nil then
			return
		end
		if string.find(input.UserInputType.Name, "Gamepad") then
			GamepadNav.Focus(cards[QualityPickerUI.Recommended()], panel)
		end
	end)
	-- A respawn can never leave the controls off while the screen is closed.
	local added = (player :: any).CharacterAdded
	if added ~= nil then
		added:Connect(function()
			if not open and controlsOff then
				setControls(true)
			end
		end)
	end
	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(consider)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(consider)
	consider()
end

return QualityPickerUI
