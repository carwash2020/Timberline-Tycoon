--!strict
-- SettingsUI: a round button left of the cash plaque (HUD.TopRow) opens a
-- cream-and-wood card (HUD.Popup, under the corner, never over the plaque
-- or Roblox's top-left menu). Music and sound effects have a mute and a
-- volume stepper; graphics, camera shake, UI scale and tips apply at once
-- and save (SaveSetting). Reset tutorial asks twice, then ResetTutorial.
-- Visitors is the plot permission list, with a Visit button for each
-- player in the server whose plot lets you in (PlotService.Visit checks it
-- again). Leaderboard is the opt-in
-- lifetime-earnings board (LeaderboardUI). On a gamepad DPadRight opens
-- the card, the D-pad moves between the rows, B on Visitors or
-- Leaderboard returns to the game list, and B or Esc closes the card.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local LeaderboardLogic = require(ReplicatedStorage.Shared.LeaderboardLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local CameraShake = require(script.Parent.CameraShake)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local HUD = require(script.Parent.HUD)
local LeaderboardUI = require(script.Parent.LeaderboardUI)
local Quality = require(script.Parent.Quality)
local UITheme = require(script.Parent.UITheme)

local SettingsUI = {}

-- DPadRight opens Settings only while the button is showing and the
-- placer is not up. The placer binds that key at a higher priority too.
function SettingsUI.OpensOnPad(buttonVisible: boolean, placing: boolean): boolean
	return buttonVisible and not placing
end

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

-- The key B and Esc use to leave a tab: back to "game" from any other
-- tab, and closing the card from "game" (SettingsUI.BackTarget).
function SettingsUI.BackTarget(tab: string): string?
	if tab ~= "game" and SettingsLogic.HasTab(tab) then
		return "game"
	end
	return nil
end

local function tenFoot(): boolean
	local ok, ten = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and ten == true
end

local function percent(n: number): string
	return string.format("%d%%", math.floor(n * 100 + 0.5))
end

function SettingsUI.Start()
	local gui = UITheme.Screen("SettingsUI", UITheme.Layers.Settings)
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
	card.outer.Size = UDim2.fromOffset(280, 300)
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
	local tap = math.max(rowSize.Y, PermissionLogic.Tap, UITheme.Size.Tap)
	local firstFace: GuiButton? = nil
	local resetArmed = false
	local tabName = "game"
	local visitorTarget = PermissionLogic.Anyone
	local gameRows: { GuiObject } = {}

	local function makeButton(
		parent: Instance,
		name: string,
		text: string,
		style: string,
		onPress: () -> ()
	): UITheme.Button
		local button = UITheme.Button({
			name = name,
			text = text,
			size = Vector2.new(rowSize.X, tap),
			style = style,
			textSize = rowSpec.text,
		})
		button.root.Parent = parent
		button.face.Activated:Connect(onPress)
		return button
	end

	local function row(name: string, text: string, onPress: () -> ()): TextButton
		local button = makeButton(scroll, name, text, "buy", onPress)
		button.root.LayoutOrder = 10
		table.insert(gameRows, button.root)
		return button.face
	end

	local visitors = Instance.new("Frame")
	visitors.Name = "Visitors"
	visitors.BackgroundTransparency = 1
	visitors.Size = UDim2.fromScale(1, 0)
	visitors.AutomaticSize = Enum.AutomaticSize.Y
	visitors.Visible = false
	visitors.LayoutOrder = 50
	UITheme.list(visitors, 6)
	visitors.Parent = scroll

	local gameTab: UITheme.Button
	local visitorTab: UITheme.Button
	local boardTab: UITheme.Button
	local boardPanel: LeaderboardUI.Panel

	local function permissions(): { [string]: PermissionLogic.Row }
		return PermissionLogic.Decode(player:GetAttribute("PlotPermissions"))
	end

	local function people(): { { id: string, label: string } }
		local list = { { id = PermissionLogic.Anyone, label = "Anyone" } }
		local seen: { [string]: boolean } = { [PermissionLogic.Anyone] = true }
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local id = tostring(other.UserId)
				if not seen[id] then
					seen[id] = true
					local label = if other.DisplayName ~= "" then other.DisplayName else other.Name
					table.insert(list, { id = id, label = label })
				end
			end
		end
		for key in pairs(permissions()) do
			if not seen[key] and PermissionLogic.Target(key) == key then
				seen[key] = true
				table.insert(list, { id = key, label = "Player " .. key })
			end
		end
		return list
	end

	-- Players here who own a plot and whose visit flag lets you in. Their
	-- permissions ride on their own PlotPermissions attribute.
	local function visitable(): { { userId: number, name: string } }
		local candidates: { PermissionLogic.Candidate } = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				table.insert(candidates, {
					userId = other.UserId,
					name = if other.DisplayName ~= "" then other.DisplayName else other.Name,
					hasPlot = other:GetAttribute("PlotSlot") ~= nil,
					permissions = PermissionLogic.Decode(other:GetAttribute("PlotPermissions")),
				})
			end
		end
		return PermissionLogic.VisitList(candidates, player.UserId)
	end

	local function rebuildVisitors()
		for _, child in ipairs(visitors:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local visitHead = UITheme.label(visitors, "VISIT A PLOT", F.Black, if tenFoot() then 18 else 14, C.Bark)
		visitHead.Size = UDim2.new(1, 0, 0, if tenFoot() then 24 else 18)
		local visits = visitable()
		if #visits == 0 then
			local none =
				UITheme.label(visitors, "No open plots here right now.", F.Bold, if tenFoot() then 18 else 14, C.Ink)
			none.Size = UDim2.new(1, 0, 0, if tenFoot() then 24 else 18)
		end
		for _, entry in ipairs(visits) do
			local who = entry
			makeButton(visitors, "Visit" .. who.userId, "Visit " .. who.name, "buy", function()
				Net.Remote("VisitPlot"):FireServer(who.userId)
				card.outer.Visible = false
			end)
		end
		local known = false
		for _, person in ipairs(people()) do
			if person.id == visitorTarget then
				known = true
			end
		end
		if not known then
			visitorTarget = PermissionLogic.Anyone
		end
		local sheet = permissions()
		for _, person in ipairs(people()) do
			local picked = person.id == visitorTarget
			local who = person
			makeButton(
				visitors,
				"Who" .. who.id,
				if picked then who.label .. "  ·" else who.label,
				if picked then "bark" else "skip",
				function()
					visitorTarget = who.id
					rebuildVisitors()
				end
			)
		end
		for _, flag in ipairs(PermissionLogic.Flags) do
			local on = PermissionLogic.Stored(sheet, visitorTarget, flag)
			local label = PermissionLogic.Label[flag] or flag
			local name = flag
			makeButton(
				visitors,
				"Flag" .. name,
				string.format("%s: %s", label, if on then "ON" else "OFF"),
				if on then "buy" else "skip",
				function()
					local current = PermissionLogic.Stored(permissions(), visitorTarget, name)
					Net.Remote("SetPermission"):FireServer(visitorTarget, name, not current)
				end
			)
		end
	end

	local function showTab(name: string)
		if not SettingsLogic.HasTab(name) then
			return
		end
		tabName = name
		local visitorsOn = name == "visitors"
		local boardOn = name == "board"
		for _, rowRoot in ipairs(gameRows) do
			rowRoot.Visible = not visitorsOn and not boardOn
		end
		visitors.Visible = visitorsOn
		boardPanel.root.Visible = boardOn
		card.outer.Size = UDim2.fromOffset(if boardOn then LeaderboardLogic.CardWidth(tenFoot()) else 280, 300)
		gameTab:SetStyle(if name == "game" then "buy" else "skip")
		visitorTab:SetStyle(if visitorsOn then "buy" else "skip")
		boardTab:SetStyle(if boardOn then "buy" else "skip")
		if not boardOn then
			boardPanel:Link(boardTab.face)
		end
		if boardOn then
			boardPanel:Show()
			if UITheme.Device() == "console" then
				GuiService.SelectedObject = boardPanel:First()
			end
		elseif visitorsOn then
			rebuildVisitors()
			local first = visitors:FindFirstChildWhichIsA("GuiButton", true)
			if first and UITheme.Device() == "console" then
				GuiService.SelectedObject = first
			end
		elseif firstFace and UITheme.Device() == "console" then
			GuiService.SelectedObject = firstFace
		end
	end

	gameTab = makeButton(scroll, "TabGame", "GAME", "buy", function()
		showTab("game")
	end)
	gameTab.root.LayoutOrder = 1
	visitorTab = makeButton(scroll, "TabVisitors", "VISITORS", "skip", function()
		showTab("visitors")
	end)
	visitorTab.root.LayoutOrder = 2
	boardTab = makeButton(scroll, "TabBoard", "LEADERBOARD", "skip", function()
		showTab("board")
	end)
	boardTab.root.LayoutOrder = 3
	firstFace = gameTab.face

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

	-- The board tab. Opting in or out is the same SaveSetting as the
	-- others; the attribute (mirrored by the server) is what the tab reads.
	boardPanel = LeaderboardUI.Build(scroll, 60, function(): boolean
		return player:GetAttribute(SettingsLogic.BoardAttribute) == true
	end, function(on: boolean)
		player:SetAttribute(SettingsLogic.BoardAttribute, on) -- the server sets it too; this keeps the toggle snappy
		save("showOnBoard", on)
		boardPanel:SetOptIn(on)
	end)
	boardPanel:Link(boardTab.face)
	LeaderboardUI.Listen(boardPanel)

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
		if tabName == "board" then
			boardPanel:SetOptIn(player:GetAttribute(SettingsLogic.BoardAttribute) == true)
		end
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
	player:GetAttributeChangedSignal("PlotPermissions"):Connect(function()
		if tabName == "visitors" then
			rebuildVisitors()
		end
	end)
	local function refreshPeople()
		if tabName == "visitors" and card.outer.Visible then
			rebuildVisitors()
			local first = visitors:FindFirstChildWhichIsA("GuiButton", true)
			if first and UITheme.Device() == "console" then
				GuiService.SelectedObject = first
			end
		end
	end
	local function watchPlayer(other: Player)
		for _, attr in ipairs({ "PlotSlot", "PlotPermissions" }) do
			other:GetAttributeChangedSignal(attr):Connect(refreshPeople)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			watchPlayer(other)
		end
	end
	Players.PlayerAdded:Connect(function(other: Player)
		watchPlayer(other)
		refreshPeople()
	end)
	Players.PlayerRemoving:Connect(refreshPeople)
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
		return SettingsUI.OpensOnPad(open.Visible, BlueprintPlacer.Active())
	end, toggle)
	local SETTINGS_NAV = "SettingsNav"
	card.outer:GetPropertyChangedSignal("Visible"):Connect(function()
		if not card.outer.Visible then
			ContextActionService:UnbindAction(SETTINGS_NAV)
			if tabName ~= "game" then
				showTab("game")
			end
			return
		end
		ContextActionService:BindActionAtPriority(
			SETTINGS_NAV,
			function(_name, state, input)
				if state ~= Enum.UserInputState.Begin or not card.outer.Visible then
					return Enum.ContextActionResult.Pass
				end
				local code = input.KeyCode
				local back = code == InputKit.Actions.Cancel.gamepad
				local esc = code == InputKit.Actions.Cancel.keyboard
				if back and SettingsUI.BackTarget(tabName) then
					showTab("game")
					return Enum.ContextActionResult.Sink
				end
				if back or esc then
					card.outer.Visible = false
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end,
			false,
			Enum.ContextActionPriority.High.Value + 20,
			InputKit.Actions.Cancel.keyboard,
			InputKit.Actions.Cancel.gamepad
		)
	end)
	local glyph = HUD.PadGlyph(Enum.KeyCode.DPadRight, open)
	glyph.LayoutOrder = open.LayoutOrder - 1
	glyph.Parent = open.Parent
	HUD.Popup(card.outer, firstFace)
	card.outer.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

return SettingsUI
