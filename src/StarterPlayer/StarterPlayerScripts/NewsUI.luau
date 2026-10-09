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
local CLOSE_GAP = 8 -- between the last row and the Close button

local player = Players.LocalPlayer
local panel: Frame? = nil
local closeFace: GuiButton? = nil
local closeBound = false

local function icon(parent: Instance, kind: string, size: number)
	local box = Instance.new("Frame")
	box.Name = kind
	box.Size = UDim2.fromOffset(size, size)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.fromScale(0, 0.5)
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
	card.outer.Visible = false
	card.outer.Active = true
	card.outer.AutomaticSize = Enum.AutomaticSize.Y
	card.face.AutomaticSize = Enum.AutomaticSize.Y
	card.face.Size = UDim2.fromScale(1, 0)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 2000)
	limit.Parent = card.outer
	UITheme.padding(card.face, 8, 10, 8, 10)
	UITheme.list(card.face, 4)
	card.outer.Parent = gui
	panel = card.outer

	-- Sunset-into-wood strip with the wordmark. Short on a phone so the
	-- headlines and Close still fit above the jump button; a wide screen
	-- gets the taller thumbnail.
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.LayoutOrder = 1
	hero.Size = UDim2.new(1, 0, 0, 88)
	hero.BackgroundColor3 = Color3.new(1, 1, 1)
	hero.BorderSizePixel = 0
	UITheme.corner(hero, UITheme.ChipRadius)
	local wash = Instance.new("UIGradient")
	wash.Rotation = 90
	wash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#E8A15A")),
		ColorSequenceKeypoint.new(0.45, C.Amber),
		ColorSequenceKeypoint.new(1, C.Panel),
	})
	wash.Parent = hero
	local word = UITheme.label(hero, "TIMBERLINE", F.Title, 22, C.Cream)
	word.Name = "Logo"
	word.Size = UDim2.new(1, -16, 0, 26)
	word.Position = UDim2.fromOffset(10, 8)
	word.TextXAlignment = Enum.TextXAlignment.Left
	local wordStroke = Instance.new("UIStroke")
	wordStroke.Color = C.PanelAlt
	wordStroke.Thickness = 1
	wordStroke.Parent = word
	local title = UITheme.label(hero, "WHAT'S NEW IN V1", F.Title, 16, C.Cream)
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 20)
	title.Position = UDim2.fromOffset(10, 36)
	title.TextXAlignment = Enum.TextXAlignment.Left
	hero.Parent = card.face

	local rows: { Frame } = {}
	local headlines: { TextLabel } = {}
	local details: { TextLabel } = {}
	for i, entry in ipairs(NewsLogic.Entries) do
		local row = Instance.new("Frame")
		row.Name = "Line" .. i
		row.LayoutOrder = 1 + i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 44)
		row.Parent = card.face
		icon(row, entry.icon, 36)
		local line = UITheme.label(row, entry.line, F.Body, 18, C.Cream)
		line.Name = "Headline"
		line.Position = UDim2.fromOffset(44, 2)
		line.Size = UDim2.new(1, -44, 0, 20)
		line.TextTruncate = Enum.TextTruncate.AtEnd
		local detail = UITheme.label(row, entry.detail, F.Body, 15, C.Muted)
		detail.Name = "Detail"
		detail.Position = UDim2.fromOffset(44, 22)
		detail.Size = UDim2.new(1, -44, 0, 18)
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		table.insert(rows, row)
		table.insert(headlines, line)
		table.insert(details, detail)
	end

	local closeRow = Instance.new("Frame")
	closeRow.Name = "CloseRow"
	closeRow.LayoutOrder = 20
	closeRow.BackgroundTransparency = 1
	closeRow.Size = UDim2.new(1, 0, 0, CLOSE_GAP + UITheme.Size.Tap + UITheme.ButtonDrop)
	closeRow.Parent = card.face
	-- A 44 x 44 square (its X), 8 px under the last row, with the card's own
	-- padding below it, so it never touches the title or a row.
	local close = UITheme.Button({
		name = "Close",
		text = "X",
		size = Vector2.new(UITheme.Size.Tap, UITheme.Size.Tap),
		style = "primary",
		textSize = 20,
	})
	close.root.AnchorPoint = Vector2.new(0.5, 0)
	close.root.Position = UDim2.new(0.5, 0, 0, CLOSE_GAP)
	close.root.Parent = closeRow

	-- On a short screen the card is only as tall as its rows. Its bottom
	-- sits above the jump box (70px, top-left 95 from the right and 90 up)
	-- and the card stays right of the thumbstick (left 40% of the bottom
	-- half), so Close cannot land on either. A wide screen centres it.
	local function placeCard()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.zero
		local parent = card.outer.Parent
		local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
		local scale = math.max(UITheme.Scale(), 0.05)
		local short = math.min(vp.X, vp.Y)
		local compact = vp.X >= 200 and vp.Y >= 200 and short < 600
		-- Offsets, before the screen's UIScale. On a 375px phone the scale
		-- is about 0.78, so these land at 28px icons, 14px headlines and a
		-- 44px Close, and the card still ends above the jump button.
		local pad = card.face:FindFirstChildOfClass("UIPadding")
		local list = card.face:FindFirstChildOfClass("UIListLayout")
		local tap = UITheme.Size.Tap
		if compact then
			tap = math.ceil(UITheme.Size.Tap / scale)
			if pad then
				pad.PaddingTop = UDim.new(0, 4)
				pad.PaddingBottom = UDim.new(0, 4)
				pad.PaddingLeft = UDim.new(0, 8)
				pad.PaddingRight = UDim.new(0, 8)
			end
			if list then
				list.Padding = UDim.new(0, 1)
			end
			hero.Size = UDim2.new(1, 0, 0, 26)
			word.TextSize = 18
			word.Position = UDim2.fromOffset(8, 3)
			word.Size = UDim2.new(1, -12, 0, 20)
			title.Visible = false
			for i, row in ipairs(rows) do
				row.Size = UDim2.new(1, 0, 0, 34) -- headline 18 + detail 16
				local line = headlines[i]
				local sub = details[i]
				line.Position = UDim2.fromOffset(44, 0)
				line.Size = UDim2.new(1, -48, 0, 18)
				sub.Position = UDim2.fromOffset(44, 18)
				sub.Size = UDim2.new(1, -48, 0, 16)
			end
		else
			if pad then
				pad.PaddingTop = UDim.new(0, 8)
				pad.PaddingBottom = UDim.new(0, 8)
				pad.PaddingLeft = UDim.new(0, 10)
				pad.PaddingRight = UDim.new(0, 10)
			end
			if list then
				list.Padding = UDim.new(0, 4)
			end
			hero.Size = UDim2.new(1, 0, 0, 88)
			word.TextSize = 22
			word.Position = UDim2.fromOffset(10, 8)
			word.Size = UDim2.new(1, -16, 0, 26)
			title.Visible = true
			for i, row in ipairs(rows) do
				row.Size = UDim2.new(1, 0, 0, 44)
				local line = headlines[i]
				local sub = details[i]
				line.Position = UDim2.fromOffset(44, 2)
				line.Size = UDim2.new(1, -48, 0, 20)
				sub.Position = UDim2.fromOffset(44, 22)
				sub.Size = UDim2.new(1, -48, 0, 18)
			end
		end
		closeRow.Size = UDim2.new(1, 0, 0, CLOSE_GAP + tap + UITheme.ButtonDrop)
		close.root.Size = UDim2.fromOffset(tap, tap + UITheme.ButtonDrop)
		if compact then
			local margin = 8
			local left = vp.X * 0.4 + margin
			local right = vp.X - margin
			local bottom = vp.Y - 90 - margin
			card.outer.AnchorPoint = Vector2.new(0.5, 1)
			card.outer.Position = UDim2.fromOffset(((left + right) / 2 - origin.X) / scale, (bottom - origin.Y) / scale)
			card.outer.Size = UDim2.fromOffset(math.max(180, (right - left) / scale), 0)
		else
			card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
			card.outer.Position = UDim2.fromScale(0.5, 0.46)
			card.outer.Size = UDim2.fromOffset(520, 0)
		end
	end
	UITheme.WatchLayout(placeCard)
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
