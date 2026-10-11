--!strict
-- SaveSlotUI: three save slots (SaveSlotLogic). Two ways in:
--   * THE JOIN PICK. Saves are chosen by hand: when the server says SlotPick
--     (the save is in memory but nobody has picked it), this panel opens by
--     itself, after the quality screen and before the plot picker
--     (PickerSequence "slot"), and cannot be closed. The save last played is
--     marked "Last played", not "Playing". PLAY sends play(index); a save
--     with a plot then opens the plot picker for its pad, one without just
--     enters the world (the Land Office sells a plot).
--   * THE SAVES BUTTON (any time after). Each slot's name, cash, axe, what is
--     on its plot and when it was last saved, and LOAD, which asks you to
--     confirm because the save you're playing is put away first. Restarting
--     a save is not here: it is RESTART SAVE in Settings.
--     UNLOAD BASE sits at the top of the panel (LT2 style): it saves the base
--     with the save, takes it off the pad and frees the pad. While the base is
--     unloaded the same button reads LOAD BASE and opens the free plot picker.
-- The server still checks the cooldown and pulls wood out of the world
-- before it swaps, so this screen can't duplicate cash or logs. Esc and B
-- close the SAVES panel (never the join pick).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseLogic = require(ReplicatedStorage.Shared.BaseLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local SaveNowLogic = require(ReplicatedStorage.Shared.SaveNowLogic)
local JoinPickLogic = require(ReplicatedStorage.Shared.JoinPickLogic)
local PickerSequence = require(ReplicatedStorage.Shared.PickerSequence)
local Net = require(ReplicatedStorage.Shared.Net)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local GamepadNav = require(script.Parent.GamepadNav)
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
local picking = false -- the join pick is up (the server's SlotPick attribute)
local sequence = PickerSequence.Shared()
local setOpen: (boolean) -> ()
local closeButton: GuiObject? = nil
local baseButton: UITheme.Button? = nil
local saveButton: UITheme.Button? = nil
local savedLabel: TextLabel? = nil

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

-- UNLOAD BASE / LOAD BASE: which one, and whether it is cooling down.
local function refreshBase()
	local b = baseButton
	if not b then
		return
	end
	local hasPad = player:GetAttribute("PlotSlot") ~= nil
	local saveHasPlot = false
	for _, slot in ipairs(summaries) do
		if slot.active then
			saveHasPlot = slot.hasPlot == true
		end
	end
	local kind = BaseLogic.ButtonFor(hasPad, saveHasPlot, picking)
	b.root.Visible = kind ~= nil
	if kind == nil then
		return
	end
	local untilAt = player:GetAttribute("BaseCooldownUntil")
	local cooling = kind == "unload" and type(untilAt) == "number" and os.time() < untilAt
	b.face.Text = if cooling
		then string.format("UNLOAD (%ds)", math.ceil((untilAt :: number) - os.time()))
		else BaseLogic.ButtonText(kind)
	b.face.Active = not cooling
	b.face.AutoButtonColor = not cooling
	b.root:SetAttribute("Kind", kind)
end

-- SAVE NOW: the label counts the cooldown down, the line under it says when
-- the server last wrote the save ("Saved at 11:42", from LastSavedAt).
local function refreshSave()
	local b = saveButton
	if not b then
		return
	end
	local untilAt = player:GetAttribute("SaveCooldownUntil")
	local now = os.time()
	local ready = SaveNowLogic.Ready(now, if type(untilAt) == "number" then untilAt else nil)
	b.face.Text = SaveNowLogic.ButtonText(now, if type(untilAt) == "number" then untilAt else nil)
	b.face.Active = ready
	b.face.AutoButtonColor = ready
	b.root.Visible = not picking
	local label = savedLabel
	if label then
		local at = player:GetAttribute("LastSavedAt")
		label.Visible = not picking
		if type(at) == "number" and at > 0 then
			local ok, shown = pcall(function()
				return DateTime.fromUnixTimestamp(at):FormatLocalTime("H:mm", "en-us")
			end)
			label.Text = if ok then "Saved at " .. shown else SaveNowLogic.Text(at, 0)
		else
			label.Text = SaveNowLogic.Text(nil, 0)
		end
	end
end

local function fill()
	refreshBase()
	refreshSave()
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
			label.Text = if picking
				then string.format(
					"Other saves open in %ds. The last-played one is ready now.",
					math.ceil(untilAt - os.time())
				)
				else string.format("You can change saves in %ds.", math.ceil(untilAt - os.time()))
		else
			label.Text = if picking
				then "Pick a save to play. If it has a plot, you choose where your base goes next."
				else "Loading a save puts this one away. Cash, wood, plot and visitor rules stay with each save."
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
		local plotText = JoinPickLogic.PlotText(slot.hasPlot == true, slot.pieces or 0)
		if slot.fresh then
			detail.Text = "Empty  ·  " .. saved
		else
			detail.Text =
				string.format("%s  ·  %s  ·  %s  ·  %s", Util.formatCash(slot.cash), slot.axeName, plotText, saved)
		end
		detail.TextWrapped = true
		detail.TextSize = 13
		detail.Size = UDim2.new(1, -16, 0, 36)
		detail.Parent = card

		local buttons = Instance.new("Frame")
		buttons.BackgroundTransparency = 1
		buttons.Size = UDim2.new(1, -16, 0, 44)
		buttons.Position = UDim2.fromOffset(8, 98)
		UITheme.list(buttons, 8, true)
		buttons.Parent = card

		local playLabel = JoinPickLogic.PlayLabel(picking, slot.fresh, slot.active)
		if slot.active and not picking then
			local here = Instance.new("TextLabel")
			here.BackgroundTransparency = 1
			here.Font = UITheme.Fonts.Heading
			here.TextSize = 16
			here.TextColor3 = C.GreenEdge
			here.Size = UDim2.fromOffset(160, 44)
			here.Text = JoinPickLogic.ActiveBadge(false)
			here.Parent = buttons
		elseif playLabel ~= nil and picking then
			if slot.active then
				local badge = Instance.new("TextLabel")
				badge.BackgroundTransparency = 1
				badge.Font = UITheme.Fonts.Body
				badge.TextSize = 14
				badge.TextColor3 = C.GreenEdge
				badge.Size = UDim2.fromOffset(110, 44)
				badge.Text = JoinPickLogic.ActiveBadge(true)
				badge.LayoutOrder = 0
				badge.Parent = buttons
			end
			local play = rowButton(buttons, playLabel, "buy", 1, function()
				send("play", slot.index, true)
			end)
			-- The last-played save is always playable; another one obeys the cooldown.
			local blocked = cooling and not slot.active
			play.face.Active = not blocked
			play.face.AutoButtonColor = not blocked
		elseif playLabel ~= nil then
			local load = rowButton(buttons, playLabel, "buy", 1, function()
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

setOpen = function(on: boolean)
	local p = panel
	if not p then
		return
	end
	if not on and picking then
		return -- the join pick stays up until a save is chosen
	end
	p.Visible = on
	local x = closeButton
	if x then
		x.Visible = not picking
	end
	if not on then
		hideConfirm()
		ContextActionService:UnbindAction(SAVES_CLOSE)
		GamepadNav.Restore(p) -- back to the HUD button that opened it, or to walking
	else
		fill()
		ContextActionService:BindActionAtPriority(
			SAVES_CLOSE,
			function(_name, state)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				if picking then
					return Enum.ContextActionResult.Sink -- no way out but a choice
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
			GamepadNav.Focus(pick, p) -- selects it, keeps the stick in the panel
		end
	end
end

function SaveSlotUI.Start()
	local gui = UITheme.Screen("SaveSlotUI", UITheme.Layers.SaveSlot)
	gui.Parent = UITheme.PlayerGui()

	local button = HUD.SideButton({
		name = "Saves",
		text = "SAVES",
		style = "bark",
		order = 0,
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
	outer.Size = UDim2.fromOffset(360, 360)
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
	closeButton = close.root

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

	-- The base button: UNLOAD BASE while the base is on a pad, LOAD BASE while it waits.
	local base = UITheme.Button({
		name = "BaseButton",
		text = "UNLOAD BASE",
		size = Vector2.new(164, math.max(48, UITheme.Size.Tap)),
		style = "bark",
		textSize = 14,
	})
	base.root.Position = UDim2.fromOffset(12, 90)
	base.root.Visible = false
	base.root.Parent = outer
	baseButton = base
	base.face.Activated:Connect(function()
		local kind = base.root:GetAttribute("Kind")
		if kind == "unload" then
			local untilAt = player:GetAttribute("BaseCooldownUntil")
			if type(untilAt) == "number" and os.time() < untilAt then
				return
			end
			showConfirm("unload", 0, BaseLogic.UnloadConfirm)
		elseif kind == "load" then
			Net.Remote("BaseAction"):FireServer("load")
			setOpen(false)
		end
	end)

	-- SAVE NOW beside it: writes the save on demand (30 s between writes).
	local saveNow = UITheme.Button({
		name = "SaveNowButton",
		text = "Save now",
		size = Vector2.new(164, math.max(48, UITheme.Size.Tap)),
		style = "buy",
		textSize = 14,
	})
	saveNow.root.Position = UDim2.fromOffset(184, 90)
	saveNow.root.Parent = outer
	saveButton = saveNow
	saveNow.face.Activated:Connect(function()
		local untilAt = player:GetAttribute("SaveCooldownUntil")
		if not SaveNowLogic.Ready(os.time(), if type(untilAt) == "number" then untilAt else nil) then
			return
		end
		local active = 1
		for _, slot in ipairs(summaries) do
			if slot.active then
				active = slot.index
			end
		end
		Net.Remote("SaveNow"):FireServer(active)
	end)

	local saved = Instance.new("TextLabel")
	saved.Name = "SavedAt"
	saved.BackgroundTransparency = 1
	saved.Font = UITheme.Fonts.Body
	saved.TextSize = 14
	saved.TextColor3 = C.Ink
	saved.TextXAlignment = Enum.TextXAlignment.Right
	saved.Size = UDim2.new(1, -24, 0, 18)
	saved.Position = UDim2.fromOffset(12, 142)
	saved.Text = ""
	saved.Parent = outer
	savedLabel = saved

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(12, 164)
	rows.Size = UDim2.new(1, -24, 1, -176)
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
		if want and want.action == "unload" then
			Net.Remote("BaseAction"):FireServer("unload")
		elseif want then
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

	-- The server's word that nobody has picked a save yet. The screen takes its
	-- turn after the quality screen and ahead of the plot picker.
	local function considerPick()
		local on = player:GetAttribute("SlotPick") == true
		if on == picking then
			return
		end
		picking = on
		if on then
			if sequence.Request("slot") then
				setOpen(true)
			end
		else
			sequence.Done("slot")
			setOpen(false)
		end
		local p = panel
		if p and p.Visible then
			fill()
		end
	end
	sequence.OnChange(function(active: string?)
		if active == "slot" and picking then
			setOpen(true)
		end
	end)
	player:GetAttributeChangedSignal("SlotPick"):Connect(considerPick)
	for _, attr in ipairs({ "PlotSlot", "BaseCooldownUntil" }) do
		player:GetAttributeChangedSignal(attr):Connect(refreshBase)
	end
	for _, attr in ipairs({ "LastSavedAt", "SaveCooldownUntil" }) do
		player:GetAttributeChangedSignal(attr):Connect(refreshSave)
	end

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

	task.defer(considerPick) -- the attribute may have arrived before this screen started
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
