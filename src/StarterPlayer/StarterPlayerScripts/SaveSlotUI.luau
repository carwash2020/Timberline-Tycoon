--!strict
-- SaveSlotUI: three save slots (SaveSlotLogic). A side button opens a
-- panel: each slot's name, cash, axe and when it was last saved, a load
-- button, and Redo on the one you're playing. Load and Redo both ask you
-- to confirm, because the save you're playing is put away first. The
-- server still checks the cooldown and pulls wood out of the world before
-- it swaps, so this screen can't duplicate cash or logs. Esc and B close it.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Net = require(ReplicatedStorage.Shared.Net)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local SaveSlotUI = {}

type Summary = SaveSlotLogic.Summary

local C = UITheme.Colors
local player = Players.LocalPlayer

local SAVES_CLOSE = "SaveSlotClose"

local panel: Frame? = nil
local list: ScrollingFrame? = nil
local confirm: Frame? = nil
local confirmText: TextLabel? = nil
local cooldownLabel: TextLabel? = nil
local pending: { action: string, index: number }? = nil
local summaries: { Summary } = {}
local firstPick: GuiButton? = nil

local function send(action: string, index: number, extra: boolean | string)
	Net.Remote("SlotAction"):FireServer(action, index, extra)
end

local function hideConfirm()
	pending = nil
	local c = confirm
	if c then
		c.Visible = false
	end
end

local function showConfirm(action: string, index: number, message: string)
	pending = { action = action, index = index }
	local label = confirmText
	local c = confirm
	if label then
		label.Text = message
	end
	if c then
		c.Visible = true
	end
	if action == "reset" then
		send("arm", index, false)
	end
end

local function rowButton(parent: Instance, text: string, style: string, order: number, fn: () -> ())
	local button = UITheme.Button({
		text = text,
		size = Vector2.new(96, 44),
		style = style,
		textSize = 15,
	})
	button.root.LayoutOrder = order
	button.root.Parent = parent
	button.face.Activated:Connect(fn)
	if firstPick == nil then
		firstPick = button.face
	end
	return button
end

local function fill()
	local holder = list
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	firstPick = nil
	local now = os.time()
	local untilAt = player:GetAttribute("SlotCooldownUntil")
	local cooling = type(untilAt) == "number" and os.time() < untilAt
	local label = cooldownLabel
	if label then
		if type(untilAt) == "number" and os.time() < untilAt then
			label.Text = string.format("You can change saves in %ds.", math.ceil(untilAt - os.time()))
		else
			label.Text = "Loading a save puts this one away. Cash, wood, plot and visitor rules stay with each save."
		end
	end
	for _, slot in ipairs(summaries) do
		local card = Instance.new("Frame")
		card.Name = "Slot" .. slot.index
		card.LayoutOrder = slot.index
		card.Size = UDim2.new(1, 0, 0, 148)
		card.BackgroundColor3 = if slot.active then C.PaperDark else C.Paper
		card.BorderSizePixel = 0
		UITheme.corner(card, 10)
		UITheme.stroke(card, if slot.active then C.GreenEdge else C.Bark, 2)
		card.Parent = holder

		local nameBox = Instance.new("TextBox")
		nameBox.Name = "Name"
		nameBox.BackgroundColor3 = C.Cream
		nameBox.BorderSizePixel = 0
		nameBox.Font = UITheme.Fonts.Heading
		nameBox.TextSize = 16
		nameBox.TextColor3 = C.Ink
		nameBox.ClearTextOnFocus = false
		nameBox.TextXAlignment = Enum.TextXAlignment.Left
		nameBox.Size = UDim2.new(1, -16, 0, 44)
		nameBox.Position = UDim2.fromOffset(8, 6)
		nameBox.Text = slot.name
		nameBox.PlaceholderText = SaveSlotLogic.DefaultName(slot.index)
		UITheme.corner(nameBox, 8)
		UITheme.padding(nameBox, 8, 8, 4, 4)
		nameBox.Parent = card
		local slotIndex = slot.index
		nameBox.FocusLost:Connect(function()
			if nameBox.Text ~= slot.name then
				send("rename", slotIndex, nameBox.Text)
			end
		end)

		local detail = Instance.new("TextLabel")
		detail.BackgroundTransparency = 1
		detail.Font = UITheme.Fonts.Body
		detail.TextSize = 15
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextColor3 = C.Ink
		detail.Size = UDim2.new(1, -16, 0, 20)
		detail.Position = UDim2.fromOffset(8, 52)
		local saved = SaveSlotLogic.SavedText(slot.lastPlayed, now)
		if slot.fresh then
			detail.Text = "Empty  ·  " .. saved
		else
			detail.Text = string.format("%s  ·  %s  ·  %s", Util.formatCash(slot.cash), slot.axeName, saved)
		end
		detail.Parent = card

		local buttons = Instance.new("Frame")
		buttons.BackgroundTransparency = 1
		buttons.Size = UDim2.new(1, -16, 0, 44)
		buttons.Position = UDim2.fromOffset(8, 96)
		UITheme.list(buttons, 8, true)
		buttons.Parent = card

		if slot.active then
			rowButton(buttons, "REDO", "skip", 1, function()
				showConfirm(
					"reset",
					slot.index,
					"Redo this save? Cash, wood, axes you bought, and the plot on it are wiped. Robux purchases stay."
				)
			end)
		else
			local load = rowButton(buttons, if slot.fresh then "START" else "LOAD", "buy", 1, function()
				local what = if slot.fresh then "Start a new game on" else "Load"
				showConfirm(
					"load",
					slot.index,
					string.format(
						"%s %s? The save you're playing is put away first. Wood on the ground comes with you. It is not copied.",
						what,
						slot.name
					)
				)
			end)
			load.face.Active = not cooling
			load.face.AutoButtonColor = not cooling
		end
	end
end

local function setOpen(on: boolean)
	local p = panel
	if not p then
		return
	end
	p.Visible = on
	if not on then
		hideConfirm()
		ContextActionService:UnbindAction(SAVES_CLOSE)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(p) then
			GuiService.SelectedObject = nil
		end
	else
		fill()
		ContextActionService:BindActionAtPriority(
			SAVES_CLOSE,
			function(_name, state)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				if confirm and confirm.Visible then
					hideConfirm()
				else
					setOpen(false)
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
			GuiService.SelectedObject = pick
		end
	end
end

function SaveSlotUI.Start()
	local gui = UITheme.Screen("SaveSlotUI", 8)
	gui.Parent = UITheme.PlayerGui()

	local button = HUD.SideButton({
		name = "Saves",
		text = "SAVES",
		style = "bark",
		order = 8,
		onPress = function()
			local p = panel
			setOpen(not (p ~= nil and p.Visible))
		end,
	})
	button.root.Visible = true

	local outer = Instance.new("Frame")
	outer.Name = "Saves"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromOffset(360, 300)
	outer.BackgroundColor3 = C.Paper
	outer.BorderSizePixel = 0
	outer.Visible = false
	UITheme.corner(outer, 14)
	UITheme.stroke(outer, C.Bark, 3)
	outer.Parent = gui
	panel = outer

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = UITheme.Fonts.Heading
	title.TextSize = 26
	title.TextColor3 = C.Ink
	title.Size = UDim2.new(1, -60, 0, 36)
	title.Position = UDim2.fromOffset(16, 10)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Saves"
	title.Parent = outer

	local close = UITheme.Button({ text = "X", size = Vector2.new(44, 44), style = "skip", textSize = 18 })
	close.root.Position = UDim2.new(1, -52, 0, 8)
	close.root.Parent = outer
	close.face.Activated:Connect(function()
		setOpen(false)
	end)

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Font = UITheme.Fonts.Body
	note.TextSize = 14
	note.TextColor3 = C.Ink
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.Size = UDim2.new(1, -24, 0, 36)
	note.Position = UDim2.fromOffset(12, 48)
	note.Text = "Loading a save puts this one away. Cash, wood, plot and visitor rules stay with each save."
	note.Parent = outer
	cooldownLabel = note

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(12, 88)
	rows.Size = UDim2.new(1, -24, 1, -100)
	rows.CanvasSize = UDim2.fromOffset(0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 6
	rows.ScrollingDirection = Enum.ScrollingDirection.Y
	rows.Selectable = false
	UITheme.list(rows, 8)
	rows.Parent = outer
	list = rows

	local ask = Instance.new("Frame")
	ask.Name = "Confirm"
	ask.Size = UDim2.fromScale(1, 1)
	ask.BackgroundColor3 = C.Bark
	ask.BackgroundTransparency = 0.15
	ask.Visible = false
	ask.ZIndex = 5
	UITheme.corner(ask, 14)
	ask.Parent = outer
	confirm = ask

	local askText = Instance.new("TextLabel")
	askText.BackgroundTransparency = 1
	askText.Font = UITheme.Fonts.Body
	askText.TextSize = 16
	askText.TextColor3 = C.Cream
	askText.TextWrapped = true
	askText.Size = UDim2.new(1, -28, 0, 120)
	askText.Position = UDim2.fromOffset(14, 120)
	askText.ZIndex = 6
	askText.Parent = ask
	confirmText = askText

	local yes = UITheme.Button({ text = "CONFIRM", size = Vector2.new(140, 48), style = "buy", textSize = 16 })
	yes.root.Position = UDim2.new(0.5, -146, 1, -70)
	yes.root.ZIndex = 6
	yes.root.Parent = ask
	yes.face.ZIndex = 6
	yes.face.Activated:Connect(function()
		local want = pending
		if want then
			send(want.action, want.index, true)
		end
		hideConfirm()
		setOpen(false)
	end)

	local no = UITheme.Button({ text = "CANCEL", size = Vector2.new(140, 48), style = "skip", textSize = 16 })
	no.root.Position = UDim2.new(0.5, 6, 1, -70)
	no.root.ZIndex = 6
	no.root.Parent = ask
	no.face.ZIndex = 6
	no.face.Activated:Connect(hideConfirm)

	Net.Remote("SlotState").OnClientEvent:Connect(function(payload: unknown)
		if type(payload) ~= "table" then
			return
		end
		local nextSlots: { Summary } = {}
		for _, row in ipairs(payload :: { any }) do
			if type(row) == "table" and type(row.index) == "number" then
				table.insert(nextSlots, row :: Summary)
			end
		end
		summaries = nextSlots
		local p = panel
		if p and p.Visible then
			fill()
		end
	end)

	task.spawn(function()
		while panel do
			task.wait(1)
			local p = panel
			if p and p.Visible and confirm and not confirm.Visible then
				fill()
			end
		end
	end)
end

return SaveSlotUI
