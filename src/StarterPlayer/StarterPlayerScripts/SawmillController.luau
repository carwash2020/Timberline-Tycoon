--!strict
-- SawmillController: the cut on a placed mill (v2).
-- The server owns the numbers. A press only sends SawmillSet.
--
-- The board on the mill has four buttons (mouse and touch). A prompt
-- (keyboard E, gamepad X, or a tap) opens a screen panel for the owner:
-- the same four buttons, each at least 44 px, arrows or the D-pad change
-- X and Y, and B or Esc closes it. The D-pad keys themselves live in
-- SawmillLogic so this file doesn't bind them alongside the HUD shortcuts.
-- While the panel is open, GuiService.SelectedObject is set, which is
-- what drops those shortcuts.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local Net = require(ReplicatedStorage.Shared.Net)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local SawmillController = {}

local BOOT_WAIT = 8 -- seconds to hear which loop runs (MapBuilder publishes it)
local hooked: { [Instance]: boolean } = {}
local openMill: Model? = nil
local panelGui: ScreenGui? = nil
local selected: GuiObject? = nil
local listening = false

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local BARK = Color3.fromRGB(88, 58, 34)

local function send(mill: Model, axis: string, dir: number)
	local uid = mill:GetAttribute("Uid")
	if type(uid) == "string" and (axis == "x" or axis == "y") and (dir == 1 or dir == -1) then
		Net.Remote("SawmillSet"):FireServer(uid, axis, dir)
	end
end

local function hookButton(mill: Model, button: TextButton)
	button.Activated:Connect(function()
		local axis = button:GetAttribute("Axis")
		local dir = button:GetAttribute("Dir")
		if (axis == "x" or axis == "y") and (dir == 1 or dir == -1) then
			send(mill, axis, dir :: number)
		end
	end)
end

-- One screen button. `face` is its box in offset pixels.
local function stepButton(
	parent: Instance,
	name: string,
	text: string,
	axis: string,
	dir: number,
	face: number
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(face, face)
	b.BackgroundColor3 = PAPER
	b.TextColor3 = INK
	b.Font = Enum.Font.GothamBold
	b.TextSize = SawmillLogic.PanelTextPx
	b.Text = text
	b.AutoButtonColor = true
	b.Active = true
	b.Selectable = true
	b:SetAttribute("Axis", axis)
	b:SetAttribute("Dir", dir)
	-- D-pad changes the cut (PadStep) instead of moving the highlight.
	b.NextSelectionUp = b
	b.NextSelectionDown = b
	b.NextSelectionLeft = b
	b.NextSelectionRight = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	b.Parent = parent
	return b
end

export type Panel = {
	gui: ScreenGui,
	root: Frame,
	readout: TextLabel,
	buttons: { TextButton },
	close: TextButton,
}

-- The screen panel. `tenFoot` uses the larger TV face. Parent it yourself.
function SawmillController.BuildPanel(tenFoot: boolean): Panel
	local face = SawmillLogic.PanelFace(tenFoot)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SawmillCut"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Core UI safe area: under the top bar, inside a notch, and inside
	-- the 10-foot TV margin. The card sits in the middle of that.
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None

	local root = Instance.new("Frame")
	root.Name = "Card"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundColor3 = BARK
	root.BorderSizePixel = 0
	root.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = root
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = root
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = SawmillLogic.PanelTextPx
	title.TextColor3 = CREAM
	title.Text = "Set the cut"
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.Parent = root

	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.LayoutOrder = 2
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.GothamBold
	readout.TextSize = SawmillLogic.PanelTextPx
	readout.TextColor3 = CREAM
	readout.Text = "1.0 × 0.6 u"
	readout.AutomaticSize = Enum.AutomaticSize.XY
	readout.Parent = root

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.LayoutOrder = 3
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Parent = root
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, 8)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = row

	local buttons = {
		stepButton(row, "XMinus", "X−", "x", -1, face),
		stepButton(row, "XPlus", "X+", "x", 1, face),
		stepButton(row, "YMinus", "Y−", "y", -1, face),
		stepButton(row, "YPlus", "Y+", "y", 1, face),
	}
	for i, b in ipairs(buttons) do
		b.LayoutOrder = i
	end

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.LayoutOrder = 4
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = SawmillLogic.PanelTextPx
	hint.TextColor3 = CREAM
	hint.TextWrapped = true
	hint.Text = "Arrows or D-pad change the cut. B or Esc closes."
	-- As wide as the four buttons, so the line wraps inside a 667-wide phone.
	hint.Size = UDim2.fromOffset(face * 4 + 8 * 3, 48)
	hint.Parent = root

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.LayoutOrder = 5
	close.Size = UDim2.fromOffset(math.max(face, 88), face)
	close.BackgroundColor3 = PAPER
	close.TextColor3 = INK
	close.Font = Enum.Font.GothamBold
	close.TextSize = SawmillLogic.PanelTextPx
	close.Text = "Close"
	close.AutoButtonColor = true
	close.Active = true
	close.Selectable = true
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = close
	close.Parent = root

	return { gui = gui, root = root, readout = readout, buttons = buttons, close = close }
end

-- Top-left of the core-UI inset. HUD's screen ignores the inset, so a
-- modal box in full-screen pixels starts here. ScreenGui.AbsolutePosition
-- can read (0, 0) for an inset screen; GetGuiInset is the same edge
-- UITheme.TopBar already reads.
local function insetOrigin(): Vector2
	local topLeft = Vector2.zero
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(inset) == "Vector2" then
		topLeft = inset
	end
	return topLeft
end

-- The card lives in a CoreUISafeInsets screen. Its AbsolutePosition is
-- inside that screen, so the modal box is the card plus the inset origin.
local function modalRect(root: Frame): { left: number, top: number, right: number, bottom: number }
	local at, size = root.AbsolutePosition, root.AbsoluteSize
	local origin = insetOrigin()
	local x, y = at.X + origin.X, at.Y + origin.Y
	return { left = x, top = y, right = x + size.X, bottom = y + size.Y }
end

-- Screen pixels inside the inset SawmillCut gui. Its AbsoluteSize is the
-- safe rect, not the camera viewport: the hotbar floor from the viewport
-- sits one inset too low, and the card lands on the hotbar.
local function placeCard(root: Frame, tenFoot: boolean)
	local gui = root:FindFirstAncestorOfClass("ScreenGui")
	if not gui then
		return
	end
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if not ok or typeof(size) ~= "Vector2" or size.X <= 0 or size.Y <= 0 then
		return
	end
	local handheld = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local ten = false
	pcall(function()
		ten = GuiService:IsTenFootInterface() == true
	end)
	local scale = UITheme.ScaleFor(size, handheld, ten or tenFoot)
	if scale <= 0 then
		return
	end
	local cardW, cardH = SawmillLogic.CardSize(tenFoot)
	local sw, sh = cardW * scale, cardH * scale
	local margin = if ten or tenFoot then 64 else 12
	local hotbar = 70
	pcall(function()
		hotbar = UITheme.Bottom()
	end)
	local column = { left = margin, top = 48, right = margin + 280, bottom = 48 + 180 }
	local box = SawmillLogic.PlaceCard(size.X, size.Y, sw, sh, column, size.Y - hotbar)
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(box.left, box.top)
end

local built: Panel? = nil

-- The open card, again, after the inset screen changes size.
local function refreshCard()
	local panel = built
	if not panel or not panel.gui.Enabled then
		return
	end
	placeCard(panel.root, GuiService:IsTenFootInterface())
	HUD.SetModal(modalRect(panel.root))
end

local function readoutText(mill: Model): string
	local x = mill:GetAttribute("CutX")
	local y = mill:GetAttribute("CutY")
	local nx = if type(x) == "number" then x else 1
	local ny = if type(y) == "number" then y else 0.6
	return string.format("%.1f × %.1f u", nx, ny)
end

local function closePanel()
	local mill = openMill
	openMill = nil
	local gui = panelGui
	if gui then
		gui.Enabled = false
	end
	if selected and GuiService.SelectedObject == selected then
		GuiService.SelectedObject = nil
	end
	selected = nil
	HUD.SetModal(nil)
	if mill and mill.Parent then
		local prompt = mill:FindFirstChild("CutPrompt", true)
		local player = Players.LocalPlayer
		if
			prompt
			and prompt:IsA("ProximityPrompt")
			and prompt.Parent
			and player
			and mill:GetAttribute("OwnerId") == player.UserId
		then
			prompt.Enabled = true
		end
	end
end

local function openPanel(mill: Model)
	local player = Players.LocalPlayer
	if not player or mill:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	local panel = built
	if not panel then
		return
	end
	openMill = mill
	panel.readout.Text = readoutText(mill)
	placeCard(panel.root, GuiService:IsTenFootInterface())
	panel.gui.Enabled = true
	local first = panel.buttons[1]
	selected = first
	GuiService.SelectedObject = first
	HUD.SetModal(modalRect(panel.root))
end

local function onInput(input: InputObject, _processed: boolean)
	local mill = openMill
	if not mill then
		return
	end
	if input.UserInputState ~= Enum.UserInputState.Begin then
		return
	end
	if SawmillLogic.PanelCloses(input.KeyCode) then
		closePanel()
		return
	end
	local axis, dir = SawmillLogic.PadStep(input.KeyCode)
	if axis and dir then
		send(mill, axis, dir)
	end
end

local function hook(inst: Instance)
	if hooked[inst] or not inst:IsA("Model") then
		return
	end
	hooked[inst] = true
	local mill = inst :: Model
	local function watch(d: Instance)
		if d:IsA("TextButton") and d:GetAttribute("Axis") ~= nil then
			hookButton(mill, d)
		end
	end
	for _, d in ipairs(mill:GetDescendants()) do
		watch(d)
	end
	mill.DescendantAdded:Connect(watch)

	local prompt = mill:FindFirstChild("CutPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		local function owned(): boolean
			local player = Players.LocalPlayer
			return player ~= nil and mill:GetAttribute("OwnerId") == player.UserId
		end
		local function syncPrompt()
			prompt.Enabled = owned() and openMill ~= mill
		end
		syncPrompt()
		mill:GetAttributeChangedSignal("OwnerId"):Connect(syncPrompt)
		prompt.Triggered:Connect(function()
			if owned() then
				syncPrompt()
				openPanel(mill)
				prompt.Enabled = false
			end
		end)
	end
	mill:GetAttributeChangedSignal("CutX"):Connect(function()
		if openMill == mill and built then
			built.readout.Text = readoutText(mill)
		end
	end)
	mill:GetAttributeChangedSignal("CutY"):Connect(function()
		if openMill == mill and built then
			built.readout.Text = readoutText(mill)
		end
	end)
end

function SawmillController.Start()
	local waited = 0
	while workspace:GetAttribute(CoreLoop.ActiveAttribute) == nil and waited < BOOT_WAIT do
		waited += task.wait(0.25)
	end
	if not CoreLoop.V2() then
		return
	end
	local player = Players.LocalPlayer
	if not player then
		return
	end
	if not built then
		local tenFoot = GuiService:IsTenFootInterface()
		local panel = SawmillController.BuildPanel(tenFoot)
		local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
		panel.gui.Parent = pg
		built = panel
		panelGui = panel.gui
		for _, b in ipairs(panel.buttons) do
			b.Activated:Connect(function()
				local mill = openMill
				local axis = b:GetAttribute("Axis")
				local dir = b:GetAttribute("Dir")
				if mill and (axis == "x" or axis == "y") and (dir == 1 or dir == -1) then
					send(mill, axis, dir :: number)
				end
			end)
		end
		panel.close.Activated:Connect(closePanel)
		panel.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshCard)
	end
	if not listening then
		listening = true
		UserInputService.InputBegan:Connect(onInput)
	end
	for _, inst in ipairs(CollectionService:GetTagged("Sawmill")) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal("Sawmill"):Connect(hook)
end

-- Specs and a re-open after close. Not used by Start's callers.
function SawmillController._open(panel: Panel?)
	local use = panel or built
	if not use then
		return
	end
	use.gui.Enabled = true
	placeCard(use.root, GuiService:IsTenFootInterface())
	selected = use.buttons[1]
	GuiService.SelectedObject = use.buttons[1]
	HUD.SetModal(modalRect(use.root))
end

function SawmillController._close()
	closePanel()
end

return SawmillController
