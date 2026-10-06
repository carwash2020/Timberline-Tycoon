--!strict
-- BadgeUI: the badge list. Read-only. It is its own panel (not a Field
-- Guide page). A BADGES button in the left column opens it. The button
-- and every row are at least BadgeData.MinTapPx tall.
--   * Phone: tap the button. Rows scroll; a row toasts how to earn it.
--   * Keyboard: B opens and closes. Esc closes.
--   * Gamepad: its tile in the quick menu (the View button, QuickMenuUI) opens it; L3 stays free
--     for running. The D-pad moves between rows, A toasts the line, B closes it (HUD.Popup).
-- The server owns the earned set. BadgeSync and the Badges attribute
-- carry it. This script never fires a remote.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BadgeData = require(ReplicatedStorage.Shared.BadgeData)
local Net = require(ReplicatedStorage.Shared.Net)
local HUD = require(script.Parent.HUD)
local HudNav = require(script.Parent.HudNav)
local UITheme = require(script.Parent.UITheme)

local BadgeUI = {}

local player = Players.LocalPlayer
local C = UITheme.Colors

local ROW_W = 248

type RowButton = {
	key: string,
	button: UITheme.Button,
}

function BadgeUI.Start()
	local gui = UITheme.Screen("BadgeUI", UITheme.Layers.Badge)
	local tap = BadgeData.MinTapPx

	local open = UITheme.Button({
		name = "Badges",
		text = "BADGES",
		size = Vector2.new(100, tap),
		style = "bark",
		textSize = UITheme.Size.TextButton,
	})
	UITheme.LeftColumn(open.root, 3)

	local card = UITheme.Card(C.Paper, C.Bark, 3, 12, false, "Panel")
	local inset = UITheme.SkinInset("Panel")
	UITheme.padding(card.face, inset, inset, inset, inset)
	card.outer.Name = "Badges"
	card.outer.Visible = false
	card.outer.Size = UDim2.fromOffset(280, 280)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Selectable = true
	scroll.SelectionGroup = true
	scroll.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	scroll.Parent = card.face
	UITheme.padding(scroll, 8, 8, 8, 8)
	UITheme.list(scroll, 6)

	local title = UITheme.label(scroll, "BADGES", UITheme.Fonts.Black, UITheme.Size.TextButton, C.Bark)
	title.Size = UDim2.new(1, 0, 0, 20)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local subtitle = UITheme.label(scroll, "", UITheme.Fonts.Body, UITheme.Size.TextMin, C.Ink)
	subtitle.Name = "Count"
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left

	local rows: { RowButton } = {}
	local firstFace: GuiButton? = nil
	for _, def in ipairs(BadgeData.All()) do
		local button = UITheme.Button({
			name = def.key,
			text = def.name,
			size = Vector2.new(ROW_W, tap),
			style = "locked",
			textSize = UITheme.Size.TextButton,
		})
		button.root.Parent = scroll
		local key = def.key
		button.face.Activated:Connect(function()
			local current = BadgeData.Get(key)
			if current then
				HUD.Toast(current.detail)
			end
		end)
		if firstFace == nil then
			firstFace = button.face
		end
		table.insert(rows, { key = key, button = button })
	end

	local function panelHeight(): number
		-- Under the corner, inside a 375-tall phone, with room to scroll.
		return if UITheme.IsPhone() then 200 else 280
	end

	local function layout()
		card.outer.Size = UDim2.fromOffset(280, panelHeight())
	end
	layout()
	UITheme.WatchLayout(layout)

	local latest = ""

	local function redraw()
		local awarded = BadgeData.Decode(latest)
		local earned, total = BadgeData.Count(awarded)
		subtitle.Text = string.format("%d of %d", earned, total)
		local byKey: { [string]: BadgeData.Row } = {}
		for _, item in ipairs(BadgeData.Rows(awarded)) do
			byKey[item.key] = item
		end
		for _, row in ipairs(rows) do
			local found = byKey[row.key]
			if found then
				row.button:SetText(string.format("%s  ·  %s", found.name, found.status))
				row.button:SetStyle(if found.unlocked then "full" else "locked")
			end
		end
	end

	-- The server writes the Badges attribute and fires BadgeSync. This
	-- client only reads them; it never writes the attribute back.
	local function show(payload: unknown)
		if type(payload) ~= "string" or payload == latest then
			return
		end
		latest = payload
		redraw()
	end

	local function toggle()
		card.outer.Visible = not card.outer.Visible
	end

	open.face.Activated:Connect(toggle)
	-- A gamepad reaches it through the quick menu (View button), a tile here.
	HudNav.Add(open.face, { id = "badges", label = "BADGES", press = toggle })

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == BadgeData.CloseKeyboard and card.outer.Visible then
			card.outer.Visible = false
			return
		end
		if input.KeyCode ~= BadgeData.OpenKeyboard then
			return
		end
		if not card.outer.Visible and GuiService.SelectedObject ~= nil then
			return
		end
		toggle()
	end)

	player:GetAttributeChangedSignal("Badges"):Connect(function()
		show(player:GetAttribute("Badges"))
	end)
	task.spawn(function()
		local remote = Net.Remote("BadgeSync")
		remote.OnClientEvent:Connect(function(payload: unknown)
			show(payload)
		end)
	end)

	HUD.Popup(card.outer, firstFace)
	card.outer.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	redraw()
	show(player:GetAttribute("Badges"))
end

return BadgeUI
