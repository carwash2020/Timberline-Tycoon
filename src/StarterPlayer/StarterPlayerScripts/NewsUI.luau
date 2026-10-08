--!strict
-- NewsUI: "What's new in V1". Once, after the tutorial, on the first join
-- that has not stored onboarding["News:V1"]. Also from Settings. One Close
-- button. B closes. The right trigger is not bound.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NewsLogic = require(ReplicatedStorage.Shared.NewsLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local NewsUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local CLOSE_ACTION = "NewsClose"
local SEEN_ATTR = "NewsV1Seen"

local player = Players.LocalPlayer
local panel: Frame? = nil
local closeFace: GuiButton? = nil
local closeBound = false

local function icon(parent: Instance, kind: string, size: number)
	local box = Instance.new("Frame")
	box.Name = kind
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundColor3 = C.PanelAlt
	box.BorderSizePixel = 0
	box.Active = false
	UITheme.corner(box, UITheme.ChipRadius)
	UITheme.stroke(box, C.AmberEdge, UITheme.Stroke)
	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.BorderSizePixel = 0
	mark.Active = false
	if kind == "tree" then
		mark.Size = UDim2.fromOffset(8, 16)
		mark.BackgroundColor3 = C.Confirm
		UITheme.corner(mark, 3)
	elseif kind == "base" then
		mark.Size = UDim2.fromOffset(16, 12)
		mark.BackgroundColor3 = C.Amber
		UITheme.corner(mark, 2)
	elseif kind == "axe" then
		mark.Size = UDim2.fromOffset(14, 4)
		mark.Rotation = -40
		mark.BackgroundColor3 = C.Cream
		UITheme.corner(mark, 2)
	elseif kind == "box" then
		mark.Size = UDim2.fromOffset(14, 12)
		mark.BackgroundColor3 = C.AmberEdge
		UITheme.corner(mark, 2)
	elseif kind == "gear" then
		mark.Size = UDim2.fromOffset(12, 12)
		mark.BackgroundColor3 = C.Amber
		UITheme.corner(mark, 6)
	else
		mark.Size = UDim2.fromOffset(14, 10)
		mark.BackgroundColor3 = C.Cream
		UITheme.corner(mark, 3)
	end
	mark.Parent = box
	box.Parent = parent
	return box
end

local function unbind()
	if closeBound then
		closeBound = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
end

local function dismiss()
	local root = panel
	if root == nil or not root.Visible then
		return
	end
	root.Visible = false
	unbind()
	MenuPad.Close(root)
	player:SetAttribute(SEEN_ATTR, true)
	Net.Remote("NewsSeen"):FireServer()
end

local function bindClose()
	if closeBound then
		return
	end
	closeBound = true
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if MenuPad.Closes(input.KeyCode) then
				dismiss()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 40,
		InputKit.Actions.Cancel.keyboard,
		InputKit.Actions.Cancel.gamepad
	)
end

function NewsUI.Open()
	local root, face = panel, closeFace
	if root == nil or face == nil then
		return
	end
	root.Visible = true
	bindClose()
	MenuPad.Open(face, root)
end

local function consider()
	if player:GetAttribute("ProfileLoaded") ~= true then
		return
	end
	local flag = player:GetAttribute(SEEN_ATTR)
	if type(flag) ~= "boolean" then
		return -- the server has not said yet
	end
	if NewsLogic.ShouldAutoShow(player:GetAttribute("TutorialStep"), flag) then
		NewsUI.Open()
	end
end

function NewsUI.Start()
	local gui = UITheme.Screen("NewsUI", UITheme.Layers.News)
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = C.PanelAlt
	scrim.BackgroundTransparency = 0.45
	scrim.AutoButtonColor = false
	scrim.Text = ""
	scrim.Selectable = false
	scrim.Parent = gui

	local card = UITheme.Card(C.Panel, C.AmberEdge, UITheme.Stroke, UITheme.Radius, false)
	card.outer.Name = "WhatsNew"
	card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	card.outer.Position = UDim2.fromScale(0.5, 0.5)
	card.outer.Size = UDim2.fromOffset(460, 348)
	card.outer.Visible = false
	card.outer.Active = true
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 360)
	limit.Parent = card.outer
	UITheme.padding(card.face, 12, 12, 12, 12)
	UITheme.list(card.face, 8)
	card.outer.Parent = gui
	panel = card.outer

	local title = UITheme.label(card.face, "WHAT'S NEW IN V1", F.Title, 20, C.Cream)
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left

	for i, entry in ipairs(NewsLogic.Entries) do
		local row = Instance.new("Frame")
		row.Name = "Line" .. i
		row.LayoutOrder = 1 + i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 28)
		row.Parent = card.face
		icon(row, entry.icon, 28)
		local line = UITheme.label(row, entry.line, F.Body, 15, C.Cream)
		line.Position = UDim2.fromOffset(36, 0)
		line.Size = UDim2.new(1, -36, 1, 0)
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.TextYAlignment = Enum.TextYAlignment.Center
	end

	local close = UITheme.Button({
		name = "Close",
		text = "CLOSE",
		size = Vector2.new(140, UITheme.Size.Tap),
		style = "primary",
		textSize = 16,
	})
	close.root.LayoutOrder = 20
	close.root.Parent = card.face
	close.face.NextSelectionUp = close.face
	close.face.NextSelectionDown = close.face
	close.face.NextSelectionLeft = close.face
	close.face.NextSelectionRight = close.face
	close.face.Activated:Connect(dismiss)
	closeFace = close.face

	scrim.Activated:Connect(dismiss)

	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(consider)
	player:GetAttributeChangedSignal("TutorialStep"):Connect(consider)
	player:GetAttributeChangedSignal(SEEN_ATTR):Connect(consider)
	consider()

	gui.Parent = UITheme.PlayerGui()
end

return NewsUI
