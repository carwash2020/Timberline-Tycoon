--!strict
-- SettingsUI: a round button left of the cash plaque (HUD.TopRow) opens a
-- small card (one of the corner's popups, HUD.Popup: under the Daily Goals
-- button, never over it) with two toggles, Music and Sound effects. They
-- apply at once (SoundData.MusicEnabled / SfxEnabled, which AmbientSound
-- and every sound helper read) and are saved with your profile
-- (SaveSetting); the server mirrors them on the SettingMusic / SettingSfx
-- attributes, so they come back when you rejoin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local SettingsUI = {}

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts

type Toggle = { key: string, attribute: string, title: string, button: UITheme.Button }

local toggles: { Toggle } = {}

local function isOn(key: string): boolean
	return if key == "music" then SoundData.MusicEnabled else SoundData.SfxEnabled
end

local function apply(key: string, on: boolean)
	if key == "music" then
		SoundData.MusicEnabled = on
	else
		SoundData.SfxEnabled = on
	end
	for _, t in ipairs(toggles) do
		if t.key == key then
			t.button:SetText(string.format("%s: %s", t.title, if on then "ON" else "OFF"))
			t.button:SetStyle(if on then "buy" else "cant")
		end
	end
end

function SettingsUI.Start()
	local gui = UITheme.Screen("SettingsUI", 10)

	-- The round button, left of the cash plaque in HUD's top row.
	local open = Instance.new("TextButton")
	open.Name = "SettingsButton"
	open.LayoutOrder = 5
	open.Size = UDim2.fromOffset(38, 38)
	open.BackgroundColor3 = C.Bark
	open.Font = F.Black
	open.Text = "♪"
	open.TextSize = 20
	open.TextColor3 = C.Cream
	open.AutoButtonColor = true
	UITheme.corner(open, 19)
	UITheme.stroke(open, C.Ink, 3)
	open.Parent = HUD.TopRow() or gui

	local card = UITheme.Card(C.Paper, C.Bark, 3, 12, true)
	card.outer.Name = "Settings"
	card.outer.Visible = false
	UITheme.padding(card.face, 10, 10, 10, 10)
	UITheme.list(card.face, 8)
	local title = UITheme.label(card.face, "SETTINGS", F.Black, 14, C.Bark)
	title.Size = UDim2.fromOffset(170, 18)
	title.LayoutOrder = 0
	card.outer.Parent = gui

	for i, spec in ipairs({
		{ key = "music", attribute = "SettingMusic", title = "MUSIC" },
		{ key = "sfx", attribute = "SettingSfx", title = "SOUND FX" },
	}) do
		local button = UITheme.Button({
			name = spec.key,
			text = spec.title,
			size = Vector2.new(170, 36),
			style = "buy",
			textSize = 14,
		})
		button.root.LayoutOrder = i
		button.root.Parent = card.face
		table.insert(toggles, { key = spec.key, attribute = spec.attribute, title = spec.title, button = button })
		button.face.Activated:Connect(function()
			local on = not isOn(spec.key)
			apply(spec.key, on)
			Net.Remote("SaveSetting"):FireServer(spec.key, on)
		end)
		-- The saved value, once the save loads.
		local function fromSave()
			local saved = player:GetAttribute(spec.attribute)
			if type(saved) == "boolean" then
				apply(spec.key, saved)
			end
		end
		player:GetAttributeChangedSignal(spec.attribute):Connect(fromSave)
		fromSave()
		apply(spec.key, isOn(spec.key))
	end

	open.Activated:Connect(function()
		card.outer.Visible = not card.outer.Visible
	end)

	-- The card drops down under the corner, at the right edge (its screen
	-- stays over the shop, like the button).
	HUD.Popup(card.outer)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return SettingsUI
