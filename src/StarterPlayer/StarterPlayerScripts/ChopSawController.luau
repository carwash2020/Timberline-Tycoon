--!strict
-- ChopSawController: the length panel on a placed chop saw (v2).
-- The server owns the number. A press only sends ChopSawSet.
--
-- The board on the saw has ± buttons (mouse and touch, and they repeat
-- while held). A prompt opens a screen panel: the same buttons, at least
-- 44 px, bottom-centre and AboveHotbarPx above the hotbar
-- (screenY - UITheme.Bottom() - 8). Opening tells the HUD the card's box
-- (HUD.SetModal) so toasts move inside it; closing clears that. D-pad left
-- and right change the length, A cuts, B or Esc closes. The D-pad literals
-- live in ChopSawLogic so this file doesn't bind them beside the HUD
-- shortcuts. While the panel is open, GuiService.SelectedObject is the
-- plus button, which drops those shortcuts. B clears SelectedObject.
--
-- The neon cut line is created here. The server model does not have it.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ChopSawLogic = require(ReplicatedStorage.Shared.ChopSawLogic)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local Net = require(ReplicatedStorage.Shared.Net)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local ChopSawController = {}

local BOOT_WAIT = 8
local hooked: { [Instance]: boolean } = {}
local openSaw: Model? = nil
local panelGui: ScreenGui? = nil
local selected: GuiObject? = nil
local listening = false
local holding = false

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local BARK = Color3.fromRGB(88, 58, 34)
local PLUS = Color3.fromRGB(226, 185, 59)

local function send(saw: Model, dir: number)
	local uid = saw:GetAttribute("Uid")
	if type(uid) == "string" and (dir == 1 or dir == -1) then
		Net.Remote("ChopSawSet"):FireServer(uid, "x", dir)
	end
end

local function bindHold(button: TextButton, fire: () -> ())
	local down = false
	button.MouseButton1Down:Connect(function()
		down = true
		holding = true
		fire()
		task.spawn(function()
			while down do
				task.wait(ChopSawLogic.HoldRepeat)
				if down then
					fire()
				end
			end
		end)
	end)
	local function up()
		down = false
		holding = false
	end
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)
end

local function stepButton(parent: Instance, name: string, text: string, dir: number, face: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(face, face)
	b.BackgroundColor3 = if dir == 1 then PLUS else PAPER
	b.TextColor3 = INK
	b.Font = Enum.Font.GothamBold
	b.TextSize = ChopSawLogic.PanelTextPx
	b.Text = text
	b.AutoButtonColor = true
	b.Active = true
	b.Selectable = true
	b:SetAttribute("Axis", "x")
	b:SetAttribute("Dir", dir)
	b.NextSelectionUp = b
	b.NextSelectionDown = b
	b.NextSelectionLeft = b
	b.NextSelectionRight = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = ChopSawLogic.PanelTextPx
	fit.MinTextSize = InputKit.MinTagPx
	fit.Parent = b
	b.Parent = parent
	return b
end

export type Panel = {
	gui: ScreenGui,
	root: Frame,
	readout: TextLabel,
	minus: TextButton,
	plus: TextButton,
	cut: TextButton,
	close: TextButton,
}

-- Bottom-centre, AboveHotbarPx above the hotbar. With a camera, the same
-- box ChopSawLogic.PanelRect describes (it lifts clear of the jump button
-- on a narrow phone). Offsets are before the screen's UIScale.
local function placeCard(root: Frame, tenFoot: boolean)
	root.AnchorPoint = Vector2.new(0.5, 1)
	local inset = UITheme.Bottom() + ChopSawLogic.AboveHotbarPx
	local ok, camera = pcall(function(): any
		return (workspace :: any).CurrentCamera
	end)
	if ok and typeof(camera) == "Instance" then
		local viewport = (camera :: Camera).ViewportSize
		if viewport.X > 0 and viewport.Y > 0 then
			local handheld = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			local ten = GuiService:IsTenFootInterface()
			local scale = UITheme.ScaleFor(viewport, handheld, ten)
			if scale > 0 then
				local jump = if handheld then ChopSawLogic.JumpRect(viewport) else nil
				local rect = ChopSawLogic.PanelRect(viewport, scale, UITheme.Bottom(), jump, tenFoot)
				inset = (viewport.Y - rect.bottom) / scale
			end
		end
	end
	root.Position = UDim2.new(0.5, 0, 1, -inset)
end

local function modalRect(root: Frame): { left: number, top: number, right: number, bottom: number }
	local at, size = root.AbsolutePosition, root.AbsoluteSize
	return { left = at.X, top = at.Y, right = at.X + size.X, bottom = at.Y + size.Y }
end

function ChopSawController.BuildPanel(tenFoot: boolean): Panel
	local face = ChopSawLogic.PanelFace(tenFoot)
	local card = ChopSawLogic.PanelCardSize(tenFoot)
	local gui = UITheme.Screen("ChopSawCut", 6)
	gui.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Card"
	placeCard(root, tenFoot)
	root.Size = UDim2.fromOffset(card.X, card.Y)
	root.BackgroundColor3 = BARK
	root.BorderSizePixel = 0
	root.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = root

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, face)
	row.Position = UDim2.fromOffset(0, 0)
	row.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, ChopSawLogic.PanelGapPx)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	local minus = stepButton(row, "LengthMinus", "-", -1, face)
	minus.LayoutOrder = 1

	local readout = Instance.new("TextLabel")
	readout.Name = "LengthReadout"
	readout.LayoutOrder = 2
	readout.Size = UDim2.fromOffset(ChopSawLogic.ReadoutPx, face)
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.GothamBold
	readout.TextSize = ChopSawLogic.PanelTextPx
	readout.TextColor3 = CREAM
	readout.Text = string.format("%d u", ChopSawLogic.DefaultCut)
	readout.Parent = row

	local plus = stepButton(row, "LengthPlus", "+", 1, face)
	plus.LayoutOrder = 3
	local cut = stepButton(row, "Cut", "Cut", 0, face)
	cut.LayoutOrder = 4
	cut:SetAttribute("Dir", nil)
	local close = stepButton(row, "Close", "Close", 0, face)
	close.LayoutOrder = 5
	close:SetAttribute("Dir", nil)
	-- Cut and Close share the step face so the row stays one height.
	cut.Size = UDim2.fromOffset(face, face)
	close.Size = UDim2.fromOffset(face, face)

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(0, face + ChopSawLogic.PanelGapPx)
	hint.Size = UDim2.new(1, 0, 0, ChopSawLogic.HintPx)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = ChopSawLogic.PanelTextPx
	hint.TextColor3 = CREAM
	hint.TextWrapped = true
	hint.Text = "D-pad changes the length. A cuts. B closes."
	hint.Parent = root
	local hintFit = Instance.new("UITextSizeConstraint")
	hintFit.MaxTextSize = ChopSawLogic.PanelTextPx
	hintFit.MinTextSize = InputKit.MinTagPx
	hintFit.Parent = hint

	return { gui = gui, root = root, readout = readout, minus = minus, plus = plus, cut = cut, close = close }
end

local built: Panel? = nil

local function readoutText(saw: Model): string
	local u = saw:GetAttribute("CutU")
	local n = ChopSawLogic.Clamp(if type(u) == "number" then u else ChopSawLogic.DefaultCut)
	return string.format("%d u", n)
end

local function closePanel()
	openSaw = nil
	local gui = panelGui
	if gui then
		gui.Enabled = false
	end
	HUD.SetModal(nil)
	if selected and GuiService.SelectedObject == selected then
		GuiService.SelectedObject = nil
	end
	selected = nil
end

-- Opens the panel and selects the plus button. Specs pass the panel they built.
function ChopSawController._open(saw: Model?, panel: Panel?)
	if panel then
		built = panel
		panelGui = panel.gui
	end
	panel = built
	if not panel then
		return
	end
	openSaw = saw
	if saw then
		panel.readout.Text = readoutText(saw)
		local u = saw:GetAttribute("CutU")
		local n = ChopSawLogic.Clamp(if type(u) == "number" then u else ChopSawLogic.DefaultCut)
		MachineArt.PreviewLine(saw, n)
	end
	panel.gui.Enabled = true
	HUD.SetModal(modalRect(panel.root))
	selected = panel.plus
	GuiService.SelectedObject = panel.plus
end

-- What an open-panel key does: "x" and a direction, "cut", "close", or nothing.
-- Stepping is the caller's job, so a spec can read the key without a remote.
function ChopSawController.ApplyKey(key: Enum.KeyCode): (string?, number?)
	if not built or not built.gui.Enabled then
		return nil, nil
	end
	if ChopSawLogic.PanelCloses(key) then
		closePanel()
		return "close", nil
	end
	if ChopSawLogic.Cuts(key) then
		closePanel()
		return "cut", nil
	end
	return ChopSawLogic.PadStep(key)
end

local function onInput(input: InputObject, _processed: boolean)
	if input.UserInputState ~= Enum.UserInputState.Begin then
		return
	end
	if not built or not built.gui.Enabled then
		return
	end
	local saw = openSaw
	local axis, dir = ChopSawController.ApplyKey(input.KeyCode)
	if axis == "x" and dir and saw then
		send(saw, dir)
	end
end

local function refresh(saw: Model)
	local u = saw:GetAttribute("CutU")
	local n = ChopSawLogic.Clamp(if type(u) == "number" then u else ChopSawLogic.DefaultCut)
	MachineArt.PreviewLine(saw, n)
	if openSaw == saw and built then
		built.readout.Text = string.format("%d u", n)
	end
end

local function hook(inst: Instance)
	if hooked[inst] or not inst:IsA("Model") then
		return
	end
	hooked[inst] = true
	local saw = inst :: Model
	refresh(saw)
	local function watch(d: Instance)
		if d:IsA("TextButton") and d:GetAttribute("Axis") == "x" then
			local dir = d:GetAttribute("Dir")
			if dir == 1 or dir == -1 then
				local step = dir :: number
				bindHold(d, function()
					send(saw, step)
				end)
			end
		end
	end
	for _, d in ipairs(saw:GetDescendants()) do
		watch(d)
	end
	saw.DescendantAdded:Connect(watch)
	local prompt = saw:FindFirstChild("CutPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			ChopSawController._open(saw)
		end)
	end
	saw:GetAttributeChangedSignal("CutU"):Connect(function()
		refresh(saw)
	end)
end

function ChopSawController.Start()
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
		local panel = ChopSawController.BuildPanel(tenFoot)
		local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
		panel.gui.Parent = pg
		built = panel
		panelGui = panel.gui
		UITheme.WatchLayout(function()
			local open = built
			if not open then
				return
			end
			placeCard(open.root, GuiService:IsTenFootInterface())
			if open.gui.Enabled then
				HUD.SetModal(modalRect(open.root))
			end
		end)
		bindHold(panel.minus, function()
			local saw = openSaw
			if saw then
				send(saw, -1)
			end
		end)
		bindHold(panel.plus, function()
			-- Gamepad A activates the selected plus button. That press is
			-- the Cut bind, so a gamepad click does not also step the length.
			if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
				return
			end
			local saw = openSaw
			if saw then
				send(saw, 1)
			end
		end)
		panel.cut.Activated:Connect(function()
			ChopSawController.ApplyKey(Enum.KeyCode.Return)
		end)
		panel.close.Activated:Connect(closePanel)
	end
	if not listening then
		listening = true
		UserInputService.InputBegan:Connect(onInput)
	end
	for _, inst in ipairs(CollectionService:GetTagged("ChopSaw")) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal("ChopSaw"):Connect(hook)
end

function ChopSawController._close()
	closePanel()
end

function ChopSawController._holding(): boolean
	return holding
end

return ChopSawController
