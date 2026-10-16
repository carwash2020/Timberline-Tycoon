--!strict
-- BuildMenuUI: the hammer's "Blueprints" menu. A category rail on the left and
-- a grid of picture cards on the right (like the Lumber Tycoon 2 shelves),
-- replacing the ShopUI row list for the blueprint list only. Client only: no
-- remotes, no server change. Every rule stays where it is: BlueprintBook.Row
-- says what a card shows, and a tap or A runs PlotUI's own place function (the
-- toasts, "walk onto your plot", BlueprintBook.Allowed, BlueprintPlacer.Begin),
-- so nothing is re-implemented here. The pure part (categories, card views,
-- stick and D-pad movement, the sizes) is Shared/BuildMenuLogic.
--
-- Pictures: Art/BuildMenuArt.Images[pieceId], static ImageLabels (never a
-- ViewportFrame). An id of 0 shows the piece's colour swatch, so the menu works
-- before any render is uploaded.
--
-- Phone: the screen runs at UIScale 1 (UITheme.Screen's scale function), so a
-- name is 16 real px; a computer takes the normal scale, a TV 1.5.
--
-- Gamepad: Open selects the first tile (or the one last used); the stick stays
-- in the menu (SelectionGroups); LB and RB change category and select its first
-- tile; B and Esc close and the selection goes back to the button that opened
-- it. Nothing is bound to the right trigger (grab and chop are untouched).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BlueprintArt = require(ReplicatedStorage.Shared.Art.BlueprintArt)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local BuildMenuArt = require(ReplicatedStorage.Shared.Art.BuildMenuArt)
local BuildMenuLogic = require(ReplicatedStorage.Shared.BuildMenuLogic)
local Palette = require(ReplicatedStorage.Shared.Art.Palette)
local GamepadNav = require(script.Parent.GamepadNav)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local BuildMenuUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

export type Opts = {
	entries: () -> { BlueprintBook.Entry }, -- the entries to show (BlueprintBook.Entries, filter All)
	ctx: () -> BlueprintBook.Context,
	place: (BlueprintBook.Entry) -> (), -- one tap or A: PlotUI's own place (toasts, rules, the ghost)
	land: () -> (), -- the Land row: opens the Land panel
}

local TABS_ACTION = "BuildMenuTabs"
local CLOSE_ACTION = "BuildMenuClose"
local HOLD_ACTION = "BuildMenuHoldStill"
local PANEL_MIN_WIDTH = 400 -- narrower than this beside the cash row, the panel goes under the row instead
local PANEL_MAX_H = 640

local gui: ScreenGui? = nil
local area: Frame? = nil
local panel: Frame? = nil
local railList: ScrollingFrame? = nil
local gridList: ScrollingFrame? = nil
local titleLabel: TextLabel? = nil
local hintBar: Frame? = nil
local closeFace: GuiObject? = nil

local opts: Opts? = nil
local isOpen = false
local categories: { BuildMenuLogic.Category } = {}
local catIndex = 1
local tiles: { { entry: BlueprintBook.Entry, button: TextButton, view: BuildMenuLogic.TileView } } = {}
local railRows: { TextButton } = {}
local landRow: TextButton? = nil
local selectedId: string? = nil
local phoneNow = false
-- Remembered for the session: the category and the card last used, so B out of
-- the placer comes back to the same card.
local lastKind: string? = nil
local lastTileId: string? = nil

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------

local function focusRing(stroke: number): Frame
	return UITheme.FocusRing(stroke)
end

-- AbsoluteSize / AbsolutePosition, or zero where they cannot be read (before
-- the first layout pass, and in the headless specs, which have no layout).
local function absSize(obj: GuiObject): Vector2
	local ok, v = pcall(function()
		return obj.AbsoluteSize
	end)
	return if ok and typeof(v) == "Vector2" then v else Vector2.zero
end

local function absPos(obj: GuiObject): Vector2
	local ok, v = pcall(function()
		return obj.AbsolutePosition
	end)
	return if ok and typeof(v) == "Vector2" then v else Vector2.zero
end

local function lastInputIsGamepad(): boolean
	return string.find(UserInputService:GetLastInputType().Name, "Gamepad") ~= nil
end

local function desaturate(color: Color3): Color3
	local r, g, b = color.R, color.G, color.B
	local grey = (r + g + b) / 3
	return Color3.new((r + grey) / 2, (g + grey) / 2, (b + grey) / 2)
end

---------------------------------------------------------------------------
-- A card
---------------------------------------------------------------------------

local function buildTile(
	entry: BlueprintBook.Entry,
	view: BuildMenuLogic.TileView,
	sizes: BuildMenuLogic.Sizes,
	order: number
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "Tile_" .. entry.id
	btn.LayoutOrder = order
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BackgroundColor3 = C.Cream
	btn.BorderSizePixel = 0
	btn.ClipsDescendants = true
	btn.Selectable = true
	btn.SelectionImageObject = focusRing(sizes.stroke)
	UITheme.corner(btn, 8)
	local edge = UITheme.stroke(btn, UITheme.Skin.Bark, 2)
	edge.Name = "Edge"

	local locked = view.state == "locked"
	-- The art: the render, over the swatch (which shows alone for an id of 0 and
	-- while the picture loads or if it fails). A locked card is dim and desaturated.
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.Size = UDim2.new(1, 0, 1, -sizes.plate)
	art.BackgroundTransparency = 1
	art.Parent = btn
	local swatchColor = Color3.fromHex(BuildMenuLogic.Swatch(entry.bp))
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.fromScale(0.7, 0.7)
	swatch.BackgroundColor3 = if locked then desaturate(swatchColor) else swatchColor
	swatch.BackgroundTransparency = if locked then 0.38 else 0
	swatch.BorderSizePixel = 0
	UITheme.corner(swatch, 6)
	swatch.Parent = art
	local imageId = BuildMenuArt.ImageFor(entry.id)
	if imageId then
		local image = Instance.new("ImageLabel")
		image.Name = "Picture"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. imageId
		image.ImageTransparency = if locked then 0.38 else 0
		if locked then
			image.ImageColor3 = Color3.fromRGB(150, 150, 150)
		end
		image.Active = false
		image.Parent = art
	end

	-- The corner tab: the plan's seal colour (BlueprintArt.SealColor).
	local tab = Instance.new("Frame")
	tab.Name = "SealTab"
	tab.Size = UDim2.fromOffset(30, 30)
	tab.BackgroundTransparency = 1
	tab.ClipsDescendants = true
	tab.Active = false
	local wedge = Instance.new("Frame")
	wedge.Name = "Wedge"
	wedge.AnchorPoint = Vector2.new(0.5, 0.5)
	wedge.Position = UDim2.fromOffset(0, 0)
	wedge.Size = UDim2.fromOffset(42, 42)
	wedge.Rotation = 45
	wedge.BackgroundColor3 = BlueprintArt.SealColor(entry.id)
	wedge.BorderSizePixel = 0
	wedge.Parent = tab
	tab.Parent = btn

	-- The name plate: Cream, the name wrapped over at most two lines, never cut.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0, 1)
	plate.Position = UDim2.fromScale(0, 1)
	plate.Size = UDim2.new(1, 0, 0, sizes.plate)
	plate.BackgroundColor3 = C.Cream
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Parent = btn
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -BuildMenuLogic.PlatePad * 2, 1, 0)
	name.Position = UDim2.fromOffset(BuildMenuLogic.PlatePad, 0)
	name.Font = F.Bold
	name.Text = view.name
	name.TextSize = sizes.name
	name.TextColor3 = C.Ink -- the name stays full contrast, locked or not
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.None
	name.TextScaled = false
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Center
	name.Active = false
	local fit = Instance.new("UITextSizeConstraint")
	fit.MinTextSize = sizes.minText
	fit.MaxTextSize = sizes.name
	fit.Parent = name
	name.Parent = plate

	-- A lock chip (locked) or a price chip (cannot afford yet).
	if view.chip then
		local chip = Instance.new("TextLabel")
		chip.Name = "Chip"
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -6, 0, 6)
		chip.AutomaticSize = Enum.AutomaticSize.XY
		chip.Size = UDim2.new()
		chip.BackgroundColor3 = if locked then C.Ink else C.Amber
		chip.BorderSizePixel = 0
		chip.Font = F.Bold
		chip.Text = view.chip
		chip.TextSize = 14
		chip.TextColor3 = if locked then C.Cream else C.Ink
		chip.Active = false
		UITheme.corner(chip, 8)
		UITheme.padding(chip, 2, 6, 2, 6)
		chip.Parent = btn
	end
	return btn
end

---------------------------------------------------------------------------
-- Selection, scrolling and focus
---------------------------------------------------------------------------

-- Keeps the selected card inside the grid's viewport (Roblox's own
-- scroll-to-selection does the most; this is the fallback).
local function scrollIntoView(button: GuiObject)
	local list = gridList
	if not list or absSize(list).Y <= 0 then
		return
	end
	local listSize = absSize(list)
	local top = absPos(button).Y - absPos(list).Y + list.CanvasPosition.Y
	local bottom = top + absSize(button).Y
	local viewTop, viewBottom = list.CanvasPosition.Y, list.CanvasPosition.Y + listSize.Y
	local target = list.CanvasPosition.Y
	if top < viewTop then
		target = top
	elseif bottom > viewBottom then
		target = bottom - listSize.Y
	end
	local maxY = math.max(0, list.AbsoluteCanvasSize.Y - listSize.Y)
	list.CanvasPosition = Vector2.new(list.CanvasPosition.X, math.clamp(target, 0, maxY))
end

local function paintSelected()
	for _, tile in ipairs(tiles) do
		local on = tile.entry.id == selectedId
		local edge = tile.button:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = if on then Palette.CoinGold else UITheme.Skin.Bark
			edge.Thickness = if on then BuildMenuLogic.SizesFor(phoneNow).stroke else 2
		end
	end
end

local function selectTile(id: string?)
	selectedId = id
	if id then
		lastTileId = id
	end
	paintSelected()
end

local function tileById(id: string?): number?
	if not id then
		return nil
	end
	for i, tile in ipairs(tiles) do
		if tile.entry.id == id then
			return i
		end
	end
	return nil
end

local function focusTile(index: number)
	local tile = tiles[index]
	if not tile then
		return
	end
	selectTile(tile.entry.id)
	GuiService.SelectedObject = tile.button
	scrollIntoView(tile.button)
end

---------------------------------------------------------------------------
-- The grid and the rail
---------------------------------------------------------------------------

local function wireTileNav(cols: number)
	local count = #tiles
	local railTarget: GuiObject? = railRows[catIndex]
	for i, tile in ipairs(tiles) do
		local function at(direction: BuildMenuLogic.Direction): GuiObject
			local j = BuildMenuLogic.Step(count, cols, i, direction)
			return (tiles[j] or tile).button
		end
		tile.button.NextSelectionUp = at("up")
		tile.button.NextSelectionDown = at("down")
		tile.button.NextSelectionRight = at("right")
		-- The leftmost column steps onto the rail's selected row.
		local left = BuildMenuLogic.Step(count, cols, i, "left")
		tile.button.NextSelectionLeft = if left == i and railTarget then railTarget else tiles[left].button
	end
	for i, row in ipairs(railRows) do
		-- Right from the rail lands on the grid's first card.
		row.NextSelectionRight = if tiles[1] then tiles[1].button else nil
		row.NextSelectionUp = railRows[i - 1] or row
		row.NextSelectionDown = railRows[i + 1] or landRow or row
	end
	if landRow then
		landRow.NextSelectionUp = railRows[#railRows] or landRow
		landRow.NextSelectionDown = landRow
		landRow.NextSelectionRight = if tiles[1] then tiles[1].button else nil
	end
end

local function clearGrid()
	for _, tile in ipairs(tiles) do
		tile.button:Destroy()
	end
	table.clear(tiles)
end

local function paintRail()
	for i, row in ipairs(railRows) do
		local on = i == catIndex
		local bar = row:FindFirstChild("Bar")
		if bar and bar:IsA("GuiObject") then
			bar.Visible = on
		end
		local edge = row:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = if on then Palette.CoinGold else UITheme.Skin.Bark
			edge.Thickness = if on then 3 else 1
		end
		row.BackgroundColor3 = if on then C.Cream else C.Paper
	end
end

-- Builds the cards of the current category.
local function buildGrid()
	local list, o = gridList, opts
	local cat = categories[catIndex]
	if not list or not o then
		return
	end
	clearGrid()
	local sizes = BuildMenuLogic.SizesFor(phoneNow)
	local panelWidth = if panel then absSize(panel).X / math.max(UITheme.Scale(), 0.01) else 0
	local grid = BuildMenuLogic.GridFor(
		if panelWidth > 0 then panelWidth else BuildMenuLogic.Layout(667, phoneNow, 1).panelW,
		phoneNow
	)
	local layout = list:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(math.floor(grid.tileW), sizes.tileH)
		layout.CellPadding = UDim2.fromOffset(BuildMenuLogic.TileGap, BuildMenuLogic.TileGap)
	end
	if not cat then
		return
	end
	local ctx = o.ctx()
	for i, entry in ipairs(cat.entries) do
		local view = BuildMenuLogic.Tile(entry, ctx)
		local btn = buildTile(entry, view, sizes, i)
		btn.Parent = list
		btn.Activated:Connect(function()
			BuildMenuUI.Press(entry)
		end)
		table.insert(tiles, { entry = entry, button = btn, view = view })
	end
	list.CanvasPosition = Vector2.zero
	wireTileNav(grid.cols)
	paintSelected()
end

local function selectCategory(index: number, focusFirst: boolean)
	if #categories == 0 then
		return
	end
	catIndex = math.clamp(index, 1, #categories)
	lastKind = categories[catIndex].kind
	paintRail()
	buildGrid()
	if focusFirst and #tiles > 0 then
		focusTile(BuildMenuLogic.FirstTile(categories[catIndex]))
	end
	if titleLabel then
		titleLabel.Text = "Blueprints"
	end
end

local function buildRail()
	local list, o = railList, opts
	if not list or not o then
		return
	end
	for _, row in ipairs(railRows) do
		row:Destroy()
	end
	table.clear(railRows)
	if landRow then
		landRow:Destroy()
		landRow = nil
	end
	local sizes = BuildMenuLogic.SizesFor(phoneNow)
	local function makeRow(text: string, swatch: Color3, order: number): TextButton
		local row = Instance.new("TextButton")
		row.Name = "Rail_" .. text
		row.LayoutOrder = order
		row.AutoButtonColor = false
		row.Text = ""
		row.Size = UDim2.new(1, 0, 0, sizes.row)
		row.BackgroundColor3 = C.Paper
		row.BorderSizePixel = 0
		row.Selectable = true
		row.SelectionImageObject = focusRing(3)
		UITheme.corner(row, 8)
		local edge = UITheme.stroke(row, UITheme.Skin.Bark, 1)
		edge.Name = "Edge"
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Size = UDim2.new(0, sizes.bar, 1, -8)
		bar.Position = UDim2.fromOffset(2, 4)
		bar.BackgroundColor3 = Palette.CoinGold
		bar.BorderSizePixel = 0
		bar.Visible = false
		UITheme.corner(bar, 3)
		bar.Parent = row
		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, sizes.bar + 6, 0.5, 0)
		icon.Size = UDim2.fromOffset(sizes.icon - 8, sizes.icon - 8)
		icon.BackgroundColor3 = swatch
		icon.BorderSizePixel = 0
		UITheme.corner(icon, 6)
		icon.Parent = row
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, sizes.bar + sizes.icon + 4, 0.5, 0)
		label.Size = UDim2.new(1, -(sizes.bar + sizes.icon + 8), 1, 0)
		label.Font = F.Bold
		label.Text = text
		label.TextSize = sizes.label
		label.TextColor3 = C.Ink
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = false
		label.Active = false
		label.Parent = row
		row.Parent = list
		return row
	end
	for i, cat in ipairs(categories) do
		-- The category's icon is its first piece's art (its swatch until the render is set).
		local first = cat.entries[1]
		local row = makeRow(cat.label, Color3.fromHex(BuildMenuLogic.Swatch(first.bp)), i)
		row.Activated:Connect(function()
			selectCategory(i, false)
		end)
		table.insert(railRows, row)
	end
	-- The Land row: an action, not a category (LB and RB skip it).
	local land = makeRow(BuildMenuLogic.LandLabel, Color3.fromHex("#4C8C40"), #categories + 1)
	land.Activated:Connect(function()
		local o2 = opts
		BuildMenuUI.Close()
		if o2 then
			o2.land()
		end
	end)
	landRow = land
end

---------------------------------------------------------------------------
-- Open, close, the keys
---------------------------------------------------------------------------

local function fitPanel()
	local g, a = gui, area
	if not g or not a then
		return
	end
	local scale = math.max(UITheme.Scale(), 0.01)
	local screen = absSize(g) / scale
	if screen.X <= 0 then
		local cam = workspace.CurrentCamera
		screen = if cam then cam.ViewportSize / scale else Vector2.new(667, 375)
	end
	local fit = HudLayout.ShopArea(screen, UITheme.TopBar() / scale)
	local row = HUD.TopRow()
	if row then
		local at = (absPos(row) - absPos(g)) / scale
		local size = absSize(row) / scale
		local avoid = { left = at.X, top = at.Y, right = at.X + size.X, bottom = at.Y + size.Y }
		fit = HudLayout.ClearOf(
			fit,
			Vector2.new(if phoneNow then BuildMenuLogic.PanelMax.phone else BuildMenuLogic.PanelMax.wide, PANEL_MAX_H),
			avoid,
			8,
			PANEL_MIN_WIDTH
		)
	end
	a.Position = UDim2.fromOffset(fit.left, fit.top)
	a.Size = UDim2.fromOffset(fit.right - fit.left, fit.bottom - fit.top)
end

local function reportModal()
	local p = panel
	if not isOpen or not p then
		return
	end
	local at, size = absPos(p), absSize(p)
	HUD.SetModal({ left = at.X, top = at.Y, right = at.X + size.X, bottom = at.Y + size.Y })
end

local function onTabs(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	local dir = if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
	selectCategory(BuildMenuLogic.NextCategory(catIndex, #categories, dir), true)
	return Enum.ContextActionResult.Sink
end

local function onCloseKey(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if MenuPad.Closes(input.KeyCode) then
		BuildMenuUI.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function holdStill(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink -- no walking or jumping while the menu is open
end

local function updateHint()
	local bar = hintBar
	if bar then
		bar.Visible = isOpen and lastInputIsGamepad()
	end
end

function BuildMenuUI.IsOpen(): boolean
	return isOpen
end

function BuildMenuUI.Close()
	if not isOpen then
		return
	end
	isOpen = false
	HUD.SetModal(nil)
	local g, p = gui, panel
	if g then
		g.Enabled = false
	end
	ContextActionService:UnbindAction(TABS_ACTION)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(HOLD_ACTION)
	MenuPad.Close(p) -- the selection goes back to the HUD button that opened the menu
end

-- Opens the menu. `wantKind` / `wantId` ask for a card (else the last one used).
function BuildMenuUI.Open(o: Opts, wantKind: string?, wantId: string?)
	local g, p = gui, panel
	if not g or not p then
		return
	end
	if isOpen then
		BuildMenuUI.Close()
	end
	opts = o
	phoneNow = UITheme.IsPhone()
	categories = BuildMenuLogic.Categories(o.entries())
	g.Enabled = true
	isOpen = true
	fitPanel()
	reportModal()
	buildRail()
	-- Reselect the card last used when it still exists.
	local kind, id = wantKind or lastKind, wantId or lastTileId
	local index = 1
	for i, cat in ipairs(categories) do
		if cat.kind == kind then
			index = i
		end
	end
	selectCategory(index, false)
	ContextActionService:BindActionAtPriority(
		TABS_ACTION,
		onTabs,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		onCloseKey,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	ContextActionService:BindActionAtPriority(
		HOLD_ACTION,
		holdStill,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
	local pick = tileById(id) or 1
	local firstButton: GuiObject? = if tiles[pick] then tiles[pick].button else landRow
	GamepadNav.Focus(firstButton, p) -- selects it, holds the stick in the menu, remembers the way back
	if tiles[pick] then
		selectTile(tiles[pick].entry.id)
		scrollIntoView(tiles[pick].button)
	end
	updateHint()
end

---------------------------------------------------------------------------
-- The shell
---------------------------------------------------------------------------

local function hintItem(parent: Frame, key: Enum.KeyCode, text: string, order: number)
	local holder = Instance.new("Frame")
	holder.LayoutOrder = order
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Size = UDim2.fromOffset(0, 24)
	holder.BackgroundTransparency = 1
	UITheme.list(holder, 4, true).VerticalAlignment = Enum.VerticalAlignment.Center
	local glyph = UITheme.Glyph(key, 22)
	glyph.LayoutOrder = 1
	glyph.Parent = holder
	local label = UITheme.label(holder, text, F.Bold, 14, C.Ink)
	label.LayoutOrder = 2
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	holder.Parent = parent
end

function BuildMenuUI.Start()
	if gui then
		return
	end
	-- The device's safe area with the top bar's strip in it (the scrim dims it,
	-- fitPanel keeps the panel clear of the bar). On a phone the screen runs at
	-- UIScale 1 so a name is 16 real px; elsewhere the normal scale.
	local g = UITheme.Screen("BuildMenuUI", UITheme.Layers.Shop, "device", function(base: number): number
		return if UITheme.IsPhone() then 1 else base
	end)
	g.Enabled = false
	gui = g

	local dim = Instance.new("TextButton")
	dim.Name = "Scrim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = C.Ink
	dim.BackgroundTransparency = 0.55
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Selectable = false
	dim.Modal = true
	dim.Parent = g
	dim.Activated:Connect(BuildMenuUI.Close)

	local a = Instance.new("Frame")
	a.Name = "Area"
	a.BackgroundTransparency = 1
	a.Position = UDim2.fromOffset(12, 66)
	a.Size = UDim2.new(1, -24, 1, -74)
	a.Parent = g
	area = a

	-- The Kraft panel: Paper and Cream, a 2 px Bark stroke, a 4 px Bark drop edge.
	local card = UITheme.Card(C.Paper, UITheme.Skin.Bark, 4, 12, false)
	local p = card.outer
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = UDim2.fromScale(1, 1)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(BuildMenuLogic.PanelMax.wide, PANEL_MAX_H)
	maxSize.Parent = p
	p.Parent = a
	panel = p :: Frame
	UITheme.texture(card.face, "Kraft", 12)
	UITheme.stroke(card.face, UITheme.Skin.Bark, 2)
	card.face.SelectionGroup = true
	card.face.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.face.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.face.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.face.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	UITheme.padding(card.face, BuildMenuLogic.Pad, BuildMenuLogic.Pad, BuildMenuLogic.Pad, BuildMenuLogic.Pad)

	-- Title row: "Blueprints", the gamepad hint (on a phone it lives here), the X.
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.Size = UDim2.new(1, 0, 0, 44)
	head.BackgroundTransparency = 1
	head.Parent = card.face
	local title = UITheme.label(head, "Blueprints", F.Heading, 24, C.Ink)
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.5, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel = title
	local close = UITheme.Button({
		name = "Close",
		text = "X",
		size = Vector2.new(44, 44),
		style = "primary",
		textSize = 20,
	})
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.fromScale(1, 0)
	close.root.Parent = head
	close.face.Activated:Connect(BuildMenuUI.Close)
	closeFace = close.face
	local hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(1, -52, 0.5, 0)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Size = UDim2.fromOffset(0, 24)
	hint.BackgroundTransparency = 1
	hint.Visible = false
	UITheme.list(hint, 10, true).VerticalAlignment = Enum.VerticalAlignment.Center
	hintItem(hint, Enum.KeyCode.ButtonA, "Place", 1)
	hintItem(hint, Enum.KeyCode.ButtonB, "Close", 2)
	hintItem(hint, Enum.KeyCode.ButtonL1, "", 3)
	hintItem(hint, Enum.KeyCode.ButtonR1, "Category", 4)
	hint.Parent = head
	hintBar = hint

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 50)
	body.Size = UDim2.new(1, 0, 1, -50)
	body.BackgroundTransparency = 1
	body.Parent = card.face

	local railSize = BuildMenuLogic.PhoneSizes.rail
	local rail = Instance.new("ScrollingFrame")
	rail.Name = "Rail"
	rail.Size = UDim2.new(0, railSize, 1, 0)
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.ScrollBarThickness = 4
	rail.CanvasSize = UDim2.new()
	rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rail.ScrollingDirection = Enum.ScrollingDirection.Y
	rail.SelectionGroup = true
	rail.SelectionImageObject = UITheme.HiddenSelection() -- a panel-sized box over the whole rail would hide the rows
	rail.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	rail.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	rail.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	rail.Parent = body
	UITheme.list(rail, 6)
	railList = rail

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.AnchorPoint = Vector2.new(1, 0)
	grid.Position = UDim2.fromScale(1, 0)
	grid.Size = UDim2.new(1, -(railSize + BuildMenuLogic.RailGap), 1, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = BuildMenuLogic.Scrollbar - 2
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.SelectionGroup = true
	grid.SelectionImageObject = UITheme.HiddenSelection() -- each card carries its own ring
	grid.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	grid.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	grid.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellSize = UDim2.fromOffset(BuildMenuLogic.PhoneSizes.tileW, BuildMenuLogic.PhoneSizes.tileH)
	layout.CellPadding = UDim2.fromOffset(BuildMenuLogic.TileGap, BuildMenuLogic.TileGap)
	layout.Parent = grid
	gridList = grid

	g.Parent = UITheme.PlayerGui()
	UserInputService.LastInputTypeChanged:Connect(updateHint)
	UITheme.WatchLayout(function()
		if isOpen then
			fitPanel()
			reportModal()
		end
	end)
end

-- One tap, click or A on a card: remember it and hand it to PlotUI's place
-- (a locked or too-dear card gets its toast there and nothing is placed).
function BuildMenuUI.Press(entry: BlueprintBook.Entry)
	selectTile(entry.id)
	local place = if opts then opts.place else nil
	if place then
		place(entry)
	end
end

-- For the specs.
function BuildMenuUI.Tiles(): { { entry: BlueprintBook.Entry, button: TextButton, view: BuildMenuLogic.TileView } }
	return tiles
end

function BuildMenuUI.Category(): BuildMenuLogic.Category?
	return categories[catIndex]
end

function BuildMenuUI.CloseFace(): GuiObject?
	return closeFace
end

return BuildMenuUI
