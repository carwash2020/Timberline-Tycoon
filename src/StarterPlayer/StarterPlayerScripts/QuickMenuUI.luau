--!strict
-- QuickMenuUI: the gamepad's way to every HUD destination.
--
-- The View (Select) button opens a panel with one big tile for each: SAVES,
-- STORE, BADGES, DAILY GOALS, FIELD GUIDE, SETTINGS, LAND ... OWNER for the
-- owner, and HUD BUTTONS, which puts the cursor on the HUD's own buttons
-- (HudNav). The tiles are in a grid; the stick or D-pad moves one step at a
-- time and wraps; A opens the tile, B or View again closes. A tile closes
-- the menu first, then does what its HUD button does, and the panel it
-- opens gives the selection back to that HUD button when it closes
-- (GamepadNav.WithReturn).
--
-- Always on: the open button is a ContextActionService action above every
-- panel's own, so it works with a menu selected, a panel open or nothing
-- selected at all (not while typing in chat). The tiles are whatever the
-- HUD's buttons registered (HudNav.Entries), so a new HUD button joins the
-- menu by registering; none is listed here. While the cursor is on a HUD
-- button, B lets go of it (walking again).
--
-- A MENU side button with the View glyph shows on a gamepad (the hint
-- glyph); the rules are Shared/QuickMenuLogic and GamepadNavLogic.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local QuickMenuLogic = require(ReplicatedStorage.Shared.QuickMenuLogic)
local GamepadNav = require(script.Parent.GamepadNav)
local HUD = require(script.Parent.HUD)
local HudNav = require(script.Parent.HudNav)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local QuickMenuUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local OPEN_ACTION = "QuickMenuOpen"
local CLOSE_ACTION = "QuickMenuClose"
local HUD_BACK_ACTION = "HudNavBack"
-- Over every panel's own B and over the HUD's pad shortcuts (High): a press of the
-- open button, or of B in the menu, is ours first.
local OPEN_PRIORITY = Enum.ContextActionPriority.High.Value + 200
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 201
local BACK_PRIORITY = Enum.ContextActionPriority.High.Value + 10

local PAD = 18 -- UI px inside the panel
local TITLE_H = 34
local FOOTER_H = 24

local gui: ScreenGui? = nil
local panel: Frame? = nil -- the card's outer frame (the selection stays inside it)
local gridHolder: Frame? = nil
local isOpen = false
local closeBound = false
local backBound = false

---------------------------------------------------------------------------
-- Building the tiles
---------------------------------------------------------------------------

local function clearTiles()
	local holder = gridHolder
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
end

-- The tile list now: every registered destination in order, then HUD
-- BUTTONS when there is at least one HUD button to walk.
local function destinations(): { HudNav.Entry }
	local list = HudNav.Entries()
	local anyButton = HudNav.First() ~= nil
	if anyButton then
		table.insert(list, {
			id = "hud",
			label = "HUD BUTTONS",
			obj = HudNav.First() :: GuiObject,
			press = function()
				HudNav.Focus()
			end,
		})
	end
	return list
end

local close: (restore: boolean?) -> ()

local function pick(entry: HudNav.Entry)
	close(true)
	if entry.id == "hud" then
		HudNav.Focus()
		return
	end
	-- The panel it opens returns to the HUD button it belongs to.
	GamepadNav.WithReturn(entry.obj, entry.press)
end

-- Draws the tiles for `entries` and sizes the panel to them; returns the
-- first tile's face.
local function build(entries: { HudNav.Entry }): GuiObject?
	local screen = gui
	local holder, outer = gridHolder, panel
	if not screen or not holder or not outer then
		return nil
	end
	clearTiles()
	local scale = UITheme.Scale()
	local view = screen.AbsoluteSize / scale
	local availW = math.max(view.X - 2 * PAD - 80, 200)
	local availH = math.max(view.Y - 2 * PAD - TITLE_H - FOOTER_H - 120, 120)
	local layout = QuickMenuLogic.Layout(#entries, availW, availH)
	holder.Size = UDim2.fromOffset(layout.gridW, layout.gridH)
	outer.Size = UDim2.fromOffset(layout.gridW + 2 * PAD, layout.gridH + 2 * PAD + TITLE_H + FOOTER_H + 6)
	local faces: { GuiObject } = {}
	for i, entry in ipairs(entries) do
		local rect = layout.rects[i]
		local style = if entry.id == "hud" then "amber" elseif entry.id == "owner" then "blue" else "bark"
		local button = UITheme.Button({
			name = entry.id,
			text = entry.label,
			size = Vector2.new(rect.w, rect.h - UITheme.ButtonDrop),
			style = style,
			textSize = 20,
			radius = UITheme.Radius,
		})
		button.root.Position = UDim2.fromOffset(rect.x, rect.y)
		button.root.Parent = holder
		button.face.Activated:Connect(function()
			pick(entry)
		end)
		faces[i] = button.face
	end
	-- One step per push, wrapping: explicit links, so Roblox's own guess
	-- (which can skip a tile in a short last row) never decides.
	for i, face in ipairs(faces) do
		local link = layout.links[i]
		face.NextSelectionUp = faces[link.up]
		face.NextSelectionDown = faces[link.down]
		face.NextSelectionLeft = faces[link.left]
		face.NextSelectionRight = faces[link.right]
	end
	return faces[1]
end

---------------------------------------------------------------------------
-- Open and close
---------------------------------------------------------------------------

local function onClosePress(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		close(true)
	end
	return Enum.ContextActionResult.Sink
end

close = function(_restore: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	if closeBound then
		closeBound = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
	local screen, outer = gui, panel
	if screen then
		screen.Enabled = false
	end
	GamepadNav.Restore(outer) -- back to where the selection was, or walking
	clearTiles()
end

function QuickMenuUI.IsOpen(): boolean
	return isOpen
end

function QuickMenuUI.Open()
	if isOpen then
		return
	end
	local screen, outer = gui, panel
	if not screen or not outer then
		return
	end
	if not QuickMenuLogic.CanOpen(UserInputService:GetFocusedTextBox() ~= nil) then
		return
	end
	local entries = destinations()
	if #entries == 0 then
		HUD.Toast("Nothing to open yet.")
		return
	end
	screen.Enabled = true -- measure it (build reads its size), then fill it
	local first = build(entries)
	isOpen = true
	GamepadNav.Focus(first, outer)
	if not closeBound then
		closeBound = true
		ContextActionService:BindActionAtPriority(
			CLOSE_ACTION,
			onClosePress,
			false,
			CLOSE_PRIORITY,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.Escape
		)
	end
end

function QuickMenuUI.Toggle()
	if isOpen then
		close(true)
	else
		QuickMenuUI.Open()
	end
end

local function onOpenPress(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		QuickMenuUI.Toggle()
	end
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------------------
-- B on the HUD's buttons: back to walking
---------------------------------------------------------------------------

local function onBackPress(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if HudNav.Release() then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function syncBack()
	local want = HudNav.OnHud() and not isOpen
	if want == backBound then
		return
	end
	backBound = want
	if want then
		ContextActionService:BindActionAtPriority(
			HUD_BACK_ACTION,
			onBackPress,
			false,
			BACK_PRIORITY,
			Enum.KeyCode.ButtonB
		)
	else
		ContextActionService:UnbindAction(HUD_BACK_ACTION)
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local function buildPanel()
	local screen = UITheme.Screen("QuickMenuUI", UITheme.Layers.QuickMenu, "device")
	screen.Enabled = false
	gui = screen

	-- Dims the game and takes taps on it (a tap outside closes).
	local dim = Instance.new("TextButton")
	dim.Name = "Scrim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = C.PanelAlt
	dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Selectable = false
	dim.Modal = true
	dim.Activated:Connect(function()
		close(true)
	end)
	dim.Parent = screen

	local shell = UITheme.Card(C.Panel, C.AmberEdge, UITheme.Stroke, UITheme.Radius, false)
	shell.outer.Name = "Panel"
	shell.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.outer.Position = UDim2.fromScale(0.5, 0.5)
	shell.outer.Size = UDim2.fromOffset(480, 300)
	UITheme.stroke(shell.outer, C.AmberEdge, UITheme.Stroke)
	shell.outer.Parent = screen
	panel = shell.outer

	local title = UITheme.label(shell.face, QuickMenuLogic.Title, F.Heading, 26, C.Cream)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(PAD, 10)
	title.Size = UDim2.new(1, -2 * PAD, 0, TITLE_H)
	title.TextXAlignment = Enum.TextXAlignment.Center

	local holder = Instance.new("Frame")
	holder.Name = "Grid"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, PAD + TITLE_H)
	holder.Size = UDim2.fromOffset(100, 100)
	holder.Parent = shell.face
	gridHolder = holder

	local footer = UITheme.label(shell.face, QuickMenuLogic.Footer, F.Bold, 16, C.Muted)
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, PAD, 1, -(PAD / 2 + 3))
	footer.Size = UDim2.new(1, -2 * PAD, 0, FOOTER_H)
	footer.TextXAlignment = Enum.TextXAlignment.Center

	screen.Parent = UITheme.PlayerGui()
end

function QuickMenuUI.Start()
	buildPanel()
	HudNav.Start()

	-- The always-available open button, over everything else's.
	ContextActionService:BindActionAtPriority(
		OPEN_ACTION,
		onOpenPress,
		false,
		OPEN_PRIORITY,
		QuickMenuLogic.OpenGamepad
	)

	-- The hint glyph on the HUD, on a gamepad: a MENU button in the side
	-- column that shows the View glyph and opens the same menu.
	local side = HUD.SideButton({
		name = "Menu",
		text = "MENU",
		style = "amber",
		order = -10,
		glyph = QuickMenuLogic.OpenGamepad,
		tile = false,
		onPress = QuickMenuUI.Toggle,
	})
	local function showSide()
		side.root.Visible = HudRules.PadGlyphs(UITheme.Device())
	end
	showSide()
	UserInputService.LastInputTypeChanged:Connect(showSide)

	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(syncBack)
	syncBack()

	-- Never stuck open: the Roblox menu, a lost window, or a respawn closes it.
	GuiService.MenuOpened:Connect(function()
		close(true)
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		close(true)
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		close(true)
	end)
end

return QuickMenuUI
