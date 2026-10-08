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
	if kind == "map" then
		mark.Size = UDim2.fromOffset(16, 12)
		mark.BackgroundColor3 = C.Confirm
		UITheme.corner(mark, 3)
	elseif kind == "mine" then
		mark.Size = UDim2.fromOffset(14, 4)
		mark.Rotation = -45
		mark.BackgroundColor3 = C.Muted
		UITheme.corner(mark, 2)
	elseif kind == "blueprint" then
		mark.Size = UDim2.fromOffset(14, 16)
		mark.BackgroundColor3 = C.Cream
		UITheme.corner(mark, 2)
	elseif kind == "daily" then
		mark.Size = UDim2.fromOffset(12, 12)
		mark.BackgroundColor3 = C.Amber
		UITheme.corner(mark, 6)
	elseif kind == "temper" then
		mark.Size = UDim2.fromOffset(14, 4)
		mark.Rotation = -40
		mark.BackgroundColor3 = C.Cream
		UITheme.corner(mark, 2)
	elseif kind == "spark" then
		mark.Size = UDim2.fromOffset(8, 8)
		mark.Rotation = 45
		mark.BackgroundColor3 = C.Amber
	elseif kind == "gondola" then
		mark.Size = UDim2.fromOffset(14, 8)
		mark.Position = UDim2.fromScale(0.5, 0.62)
		mark.BackgroundColor3 = C.Amber
		UITheme.corner(mark, 2)
	else
		mark.Size = UDim2.fromOffset(14, 10)
		mark.BackgroundColor3 = C.Cream
		UITheme.corner(mark, 3)
	end
	mark.Parent = box
	if kind == "mine" then
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Position = UDim2.fromScale(0.72, 0.28)
		head.Size = UDim2.fromOffset(8, 6)
		head.Rotation = -45
		head.BackgroundColor3 = C.Amber
		head.BorderSizePixel = 0
		head.Parent = box
	elseif kind == "gondola" then
		local cable = Instance.new("Frame")
		cable.Name = "Cable"
		cable.AnchorPoint = Vector2.new(0.5, 0)
		cable.Position = UDim2.fromScale(0.5, 0.22)
		cable.Size = UDim2.fromOffset(18, 2)
		cable.BackgroundColor3 = C.Cream
		cable.BorderSizePixel = 0
		cable.Parent = box
	elseif kind == "blueprint" then
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.AnchorPoint = Vector2.new(0.5, 0.5)
		rule.Position = UDim2.fromScale(0.5, 0.45)
		rule.Size = UDim2.fromOffset(8, 2)
		rule.BackgroundColor3 = C.Amber
		rule.BorderSizePixel = 0
		rule.Parent = box
	end
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
	card.outer.Size = UDim2.fromOffset(480, 400)
	card.outer.Visible = false
	card.outer.Active = true
	card.outer.ClipsDescendants = true
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 480)
	limit.Parent = card.outer
	UITheme.padding(card.face, 10, 12, 10, 12)
	UITheme.list(card.face, 6)
	card.outer.Parent = gui
	panel = card.outer

	-- On a short screen the card sits right of the thumbstick (left 40% of
	-- the bottom half) and its bottom stays above the jump box (70px, whose
	-- top-left is 95px from the right and 90px up). Close lives in that
	-- card, so it cannot land on either zone. A wide screen centres it.
	local function placeCard()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.zero
		local parent = card.outer.Parent
		local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
		local scale = math.max(UITheme.Scale(), 0.05)
		local short = math.min(vp.X, vp.Y)
		if vp.X >= 200 and vp.Y >= 200 and short < 600 then
			local margin = 8
			local left = vp.X * 0.4 + margin
			local top = margin
			local right = vp.X - margin
			local bottom = vp.Y - 90 - margin
			card.outer.AnchorPoint = Vector2.new(0, 0)
			card.outer.Position = UDim2.fromOffset((left - origin.X) / scale, (top - origin.Y) / scale)
			card.outer.Size = UDim2.fromOffset(math.max(200, right - left) / scale, math.max(180, bottom - top) / scale)
		else
			card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
			card.outer.Position = UDim2.fromScale(0.5, 0.5)
			card.outer.Size = UDim2.fromOffset(480, 400)
		end
	end
	UITheme.WatchLayout(placeCard)

	local title = UITheme.label(card.face, "WHAT'S NEW IN V1", F.Title, 18, C.Cream)
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left

	for i, entry in ipairs(NewsLogic.Entries) do
		local row = Instance.new("Frame")
		row.Name = "Line" .. i
		row.LayoutOrder = 1 + i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.Parent = card.face
		icon(row, entry.icon, 24)
		local line = UITheme.label(row, entry.line, F.Body, 15, C.Cream)
		line.Position = UDim2.fromOffset(36, 0)
		line.Size = UDim2.new(1, -36, 1, 0)
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.TextYAlignment = Enum.TextYAlignment.Center
	end

	local closeRow = Instance.new("Frame")
	closeRow.Name = "CloseRow"
	closeRow.LayoutOrder = 20
	closeRow.BackgroundTransparency = 1
	closeRow.Size = UDim2.new(1, 0, 0, UITheme.Size.Tap)
	closeRow.Parent = card.face
	local close = UITheme.Button({
		name = "Close",
		text = "CLOSE",
		size = Vector2.new(140, UITheme.Size.Tap),
		style = "primary",
		textSize = 16,
	})
	close.root.AnchorPoint = Vector2.new(0.5, 0)
	close.root.Position = UDim2.fromScale(0.5, 0)
	close.root.Parent = closeRow
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
	placeCard()
end

return NewsUI
