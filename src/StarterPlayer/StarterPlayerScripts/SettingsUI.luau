--!strict
-- SettingsUI: a round button left of the cash plaque (HUD.TopRow) opens a
-- cream-and-wood card (HUD.Popup, under the corner, never over the plaque
-- or Roblox's top-left menu). Music and sound effects have a mute and a
-- volume stepper; graphics, camera shake, UI scale and tips apply at once
-- and save (SaveSetting). Reset tutorial asks twice, then ResetTutorial.
-- On a gamepad DPadRight opens it and B closes it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local CameraShake = require(script.Parent.CameraShake)
local HUD = require(script.Parent.HUD)
local Quality = require(script.Parent.Quality)
local UITheme = require(script.Parent.UITheme)

local SettingsUI = {}

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts

local GRAPHICS = { "auto", "low", "medium", "high" }
local SCALES = { "small", "normal", "large" }

local function cycle(list: { string }, current: string): string
	for i, name in ipairs(list) do
		if name == current then
			return list[i % #list + 1]
		end
	end
	return list[1]
end

local function percent(n: number): string
	return string.format("%d%%", math.floor(n * 100 + 0.5))
end

function SettingsUI.Start()
	local gui = UITheme.Screen("SettingsUI", 10)
	local roundSpec = UITheme.Sized("Settings")
	local size = roundSpec.size or Vector2.new(38, 38)
	local open = Instance.new("TextButton")
	open.Name = "SettingsButton"
	open.LayoutOrder = 5
	open.Size = UDim2.fromOffset(size.X, size.Y)
	open.BackgroundColor3 = C.Bark
	open.Text = ""
	open.AutoButtonColor = true
	UITheme.corner(open, size.Y / 2)
	UITheme.stroke(open, C.Ink, 3)
	UITheme.Speaker(C.Cream).Parent = open
	open.Parent = HUD.TopRow() or gui

	local card = UITheme.Card(C.Paper, C.Bark, 3, 12, false, "Panel")
	local inset = UITheme.SkinInset("Panel")
	UITheme.padding(card.face, inset, inset, inset, inset)
	card.outer.Name = "Settings"
	card.outer.Visible = false
	card.outer.Size = UDim2.fromOffset(280, 420)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Selectable = false
	scroll.Parent = card.face
	UITheme.padding(scroll, 8, 8, 8, 8)
	UITheme.list(scroll, 6)
	scroll.SelectionGroup = true
	scroll.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	scroll.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local title = UITheme.label(scroll, "SETTINGS", F.Black, 14, C.Bark)
	title.Size = UDim2.new(1, 0, 0, 18)

	local rowSpec = UITheme.Sized("SettingsToggle")
	local rowSize = rowSpec.size or Vector2.new(248, 44)
	local firstFace: GuiButton? = nil
	local resetArmed = false

	local function row(name: string, text: string, onPress: () -> ()): TextButton
		local button = UITheme.Button({
			name = name,
			text = text,
			size = Vector2.new(rowSize.X, math.max(rowSize.Y, UITheme.Size.Tap)),
			style = "buy",
			textSize = rowSpec.text,
		})
		button.root.Parent = scroll
		button.face.Activated:Connect(onPress)
		if firstFace == nil then
			firstFace = button.face
		end
		return button.face
	end

	local musicFace: TextButton
	local musicVolFace: TextButton
	local sfxFace: TextButton
	local sfxVolFace: TextButton
	local graphicsFace: TextButton
	local shakeFace: TextButton
	local scaleFace: TextButton
	local tipsFace: TextButton
	local resetFace: TextButton

	local function save(key: string, value: any)
		Net.Remote("SaveSetting"):FireServer(key, value)
	end

	local function applyAll()
		Quality.SetOverride((player:GetAttribute("SettingGraphics") :: string?) or "auto")
		local shake = player:GetAttribute("SettingCameraShake")
		CameraShake.SetEnabled(shake ~= false)
		local scaleName = (player:GetAttribute("SettingUIScale") :: string?) or "normal"
		UITheme.SetUserScale(SettingsLogic.ScaleMultiplier(scaleName))
		local tips = player:GetAttribute("SettingShowTips")
		HUD.SetTips(tips ~= false)
		local music = player:GetAttribute("SettingMusic")
		if type(music) == "boolean" then
			SoundData.MusicEnabled = music
		end
		local sfx = player:GetAttribute("SettingSfx")
		if type(sfx) == "boolean" then
			SoundData.SfxEnabled = sfx
		end
		local mv = player:GetAttribute("SettingMusicVolume")
		if type(mv) == "number" then
			SoundData.MusicVolume = mv
		end
		local sv = player:GetAttribute("SettingSfxVolume")
		if type(sv) == "number" then
			SoundData.SfxVolume = sv
		end
		graphicsFace.Text = "Graphics  " .. string.upper((player:GetAttribute("SettingGraphics") :: string?) or "auto")
		shakeFace.Text = if shake == false then "CAMERA SHAKE: OFF" else "CAMERA SHAKE: ON"
		scaleFace.Text = "UI scale  " .. string.upper(scaleName)
		tipsFace.Text = if tips == false then "TIPS: OFF" else "TIPS: ON"
		musicFace.Text = if SoundData.MusicEnabled then "MUSIC: ON" else "MUSIC: OFF"
		musicVolFace.Text = "Music volume  " .. percent(SoundData.MusicVolume) .. "  ±"
		sfxFace.Text = if SoundData.SfxEnabled then "SOUND FX: ON" else "SOUND FX: OFF"
		sfxVolFace.Text = "Effects volume  " .. percent(SoundData.SfxVolume) .. "  ±"
		resetFace.Text = if resetArmed then "TAP AGAIN TO RESET" else "RESET TUTORIAL"
	end

	musicFace = row("music", "MUSIC: ON", function()
		SoundData.MusicEnabled = not SoundData.MusicEnabled
		save("music", SoundData.MusicEnabled)
		applyAll()
	end)
	musicVolFace = row("musicVolume", "Music volume  100%  ±", function()
		local nextVol = if SoundData.MusicVolume >= 0.99 then 0 else SoundData.MusicVolume + 0.1
		SoundData.MusicVolume = math.floor(math.clamp(nextVol, 0, 1) * 10 + 0.5) / 10
		save("musicVolume", SoundData.MusicVolume)
		applyAll()
	end)
	sfxFace = row("sfx", "SOUND FX: ON", function()
		SoundData.SfxEnabled = not SoundData.SfxEnabled
		save("sfx", SoundData.SfxEnabled)
		applyAll()
	end)
	sfxVolFace = row("sfxVolume", "Effects volume  100%  ±", function()
		local nextVol = if SoundData.SfxVolume >= 0.99 then 0 else SoundData.SfxVolume + 0.1
		SoundData.SfxVolume = math.floor(math.clamp(nextVol, 0, 1) * 10 + 0.5) / 10
		save("sfxVolume", SoundData.SfxVolume)
		applyAll()
	end)
	graphicsFace = row("graphics", "Graphics  AUTO", function()
		local current = (player:GetAttribute("SettingGraphics") :: string?) or "auto"
		local nextName = cycle(GRAPHICS, current)
		Quality.SetOverride(nextName)
		save("graphics", nextName)
		applyAll()
	end)
	shakeFace = row("shake", "CAMERA SHAKE: ON", function()
		local on = player:GetAttribute("SettingCameraShake") == false
		CameraShake.SetEnabled(on)
		save("cameraShake", on)
		applyAll()
	end)
	scaleFace = row("scale", "UI scale  NORMAL", function()
		local current = (player:GetAttribute("SettingUIScale") :: string?) or "normal"
		local nextName = cycle(SCALES, current)
		UITheme.SetUserScale(SettingsLogic.ScaleMultiplier(nextName))
		save("uiScale", nextName)
		applyAll()
	end)
	tipsFace = row("tips", "TIPS: ON", function()
		local on = player:GetAttribute("SettingShowTips") == false
		HUD.SetTips(on)
		save("showTips", on)
		applyAll()
	end)
	resetFace = row("reset", "RESET TUTORIAL", function()
		if not resetArmed then
			resetArmed = true
			applyAll()
			task.delay(4, function()
				resetArmed = false
				applyAll()
			end)
			return
		end
		resetArmed = false
		Net.Remote("ResetTutorial"):FireServer()
		HUD.Toast("Tutorial reset.")
		card.outer.Visible = false
		applyAll()
	end)

	for _, attr in pairs(SettingsLogic.Attributes) do
		player:GetAttributeChangedSignal(attr):Connect(applyAll)
	end
	applyAll()

	local function toggle()
		card.outer.Visible = not card.outer.Visible
	end
	open.Activated:Connect(toggle)
	UITheme.Clicks(open)
	if roundSpec.hit then
		UITheme.HitPad(open, roundSpec.hit).Activated:Connect(toggle)
	end
	HUD.PadShortcut(Enum.KeyCode.DPadRight, function()
		return open.Visible
	end, toggle)
	local glyph = HUD.PadGlyph(Enum.KeyCode.DPadRight, open)
	glyph.LayoutOrder = open.LayoutOrder - 1
	glyph.Parent = open.Parent
	HUD.Popup(card.outer, firstFace)
	card.outer.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

return SettingsUI
