--!strict
-- BuildMenuUI: the hammer's blueprint picker (T420). Tabs down the left (Walls,
-- Floors, Doors, Roofs, Fences, Supports, then any extra that has a piece) and a
-- grid of cards on the right, one per print: a picture, its name, a sentence on
-- what it is for and what it costs (Shared/HammerPicker), like the Lumber Tycoon 2
-- shelves. It replaces the ShopUI row list for the blueprint list only. Taking the
-- hammer out opens it (PlotUI.OnHammerHeld). Wire is not here: it is its own item. Client only: no
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
-- in the menu (SelectionGroups); the D-pad moves over the cards (explicit
-- NextSelection from HammerPicker.Step), LB and RB change tab and select its first
-- card, A picks, B and Esc close and the selection goes back to the button that
-- opened it. The highlight is each button's own rectangle and corner
-- (UITheme.FocusRing). Nothing is bound to the right trigger (grab and chop are
-- untouched).
--
-- Motion (Shared/PickerMotion, UITheme.Tween): the panel rises and the backdrop
-- fades in, tabs and cards grow a little under the pointer and shrink when
-- pressed, a chosen tab or card warms up, the first cards pop in one after
-- another. All of it is a few short tweens and none runs with "calm the screen".

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BlueprintArt = require(ReplicatedStorage.Shared.Art.BlueprintArt)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local BuildMenuArt = require(ReplicatedStorage.Shared.Art.BuildMenuArt)
local BuildMenuLogic = require(ReplicatedStorage.Shared.BuildMenuLogic)
local HammerPicker = require(ReplicatedStorage.Shared.HammerPicker)
local PickerMotion = require(ReplicatedStorage.Shared.PickerMotion)
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
local SCRIM_ALPHA = 0.55 -- the dimmed backdrop

local gui: ScreenGui? = nil
local scrim: TextButton? = nil
local area: Frame? = nil
local panel: Frame? = nil
local railList: ScrollingFrame? = nil
local gridList: ScrollingFrame? = nil
local titleLabel: TextLabel? = nil
local hintBar: Frame? = nil
local closeFace: GuiObject? = nil

local opts: Opts? = nil
local isOpen = false
local categories: { HammerPicker.Tab } = {}
local catIndex = 1
local tiles: { { entry: BlueprintBook.Entry, button: TextButton, view: BuildMenuLogic.TileView, card: HammerPicker.Card } } =
	{}
local closeToken = 0 -- a reopen cancels a close that is still fading
local emptyNote: TextLabel? = nil -- "nothing here yet", over the grid, for a tab with no piece
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

-- The ring a focused button shows. `radius` is the button's own corner, so the
-- highlight follows its edge exactly (T420).
local function focusRing(stroke: number, radius: number): Frame
	return UITheme.FocusRing(stroke, radius)
end

local CARD_RADIUS = 8
local ROW_RADIUS = 8

-- AbsoluteSize / AbsolutePosition, or zero where they cannot be read (before
-- the first layout pass, and in the headless specs, which have no layout).
local function absSize(obj: GuiBase2d): Vector2
	local ok, v = pcall(function()
		return obj.AbsoluteSize
	end)
	return if ok and typeof(v) == "Vector2" then v else Vector2.zero
end

local function absPos(obj: GuiBase2d): Vector2
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
	card: HammerPicker.Card,
	sizes: BuildMenuLogic.Sizes,
	cs: HammerPicker.CardSizes,
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
	btn.SelectionImageObject = focusRing(sizes.stroke, CARD_RADIUS)
	UITheme.corner(btn, CARD_RADIUS)
	local edge = UITheme.stroke(btn, UITheme.Skin.Bark, 2)
	edge.Name = "Edge"

	local locked = view.state == "locked"
	-- The art: the render, over the swatch (which shows alone for an id of 0 and
	-- while the picture loads or if it fails). A locked card is dim and desaturated.
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.Size = UDim2.new(1, 0, 0, cs.artH)
	art.BackgroundTransparency = 1
	art.Parent = btn
	local swatchColor = Color3.fromHex(BuildMenuLogic.Swatch(entry.bp))
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.fromScale(0.7, 0.8)
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
	plate.Position = UDim2.fromOffset(0, cs.artH)
	plate.Size = UDim2.new(1, 0, 0, cs.nameH + cs.gap)
	plate.BackgroundColor3 = C.Cream
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Parent = btn
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -cs.pad * 2, 1, 0)
	name.Position = UDim2.fromOffset(cs.pad, 0)
	name.Font = F.Bold
	name.Text = view.name
	name.TextSize = cs.nameText
	name.TextColor3 = C.Ink -- the name stays full contrast, locked or not
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.None
	name.TextScaled = false
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Center
	name.Active = false
	local fit = Instance.new("UITextSizeConstraint")
	fit.MinTextSize = sizes.minText
	fit.MaxTextSize = cs.nameText
	fit.Parent = name
	name.Parent = plate

	-- What it is for: a sentence, at most three lines (HammerPickerFit).
	local blurb = Instance.new("TextLabel")
	blurb.Name = "Blurb"
	blurb.BackgroundTransparency = 1
	blurb.Position = UDim2.fromOffset(cs.pad, cs.artH + cs.nameH + cs.gap * 2)
	blurb.Size = UDim2.new(1, -cs.pad * 2, 0, cs.blurbH)
	blurb.Font = F.Body
	blurb.Text = card.blurb
	blurb.TextSize = cs.blurbText
	blurb.TextColor3 = C.Bark
	blurb.TextWrapped = true
	blurb.TextTruncate = Enum.TextTruncate.None
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.Active = false
	blurb.Parent = btn

	-- What it costs: planks and the fee from the plan's own data (HammerPicker.Card).
	local cost = Instance.new("TextLabel")
	cost.Name = "Cost"
	cost.BackgroundTransparency = 1
	cost.AnchorPoint = Vector2.new(0, 1)
	cost.Position = UDim2.new(0, cs.pad, 1, -cs.gap)
	cost.Size = UDim2.new(1, -cs.pad * 2, 0, cs.costH)
	cost.Font = F.Bold
	cost.Text = card.costText
	cost.TextSize = cs.costText
	cost.TextColor3 = if card.state == "cant" then C.Danger else C.Ink
	cost.TextWrapped = true
	cost.TextTruncate = Enum.TextTruncate.None
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.TextYAlignment = Enum.TextYAlignment.Bottom
	cost.Active = false
	cost.Parent = btn

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
	-- Hover and press: the card grows a little under the pointer (PickerMotion).
	UITheme.Respond(btn)
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
	local reduced = UITheme.MotionReduced()
	local seconds = PickerMotion.Seconds(PickerMotion.Select, reduced)
	for _, tile in ipairs(tiles) do
		local on = tile.entry.id == selectedId
		local edge = tile.button:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			UITheme.Tween(edge, seconds, {
				Color = if on then Palette.CoinGold else UITheme.Skin.Bark,
				Thickness = if on then BuildMenuLogic.SizesFor(phoneNow).stroke else 2,
			})
		end
		tile.button.BackgroundColor3 = if on then C.PaperDark else C.Cream
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
		if tiles[1] then
			row.NextSelectionRight = tiles[1].button
		end
		row.NextSelectionUp = railRows[i - 1] or row
		row.NextSelectionDown = railRows[i + 1] or landRow or row
	end
	if landRow then
		landRow.NextSelectionUp = railRows[#railRows] or landRow
		landRow.NextSelectionDown = landRow
		if tiles[1] then
			landRow.NextSelectionRight = tiles[1].button
		end
	end
end

local function clearGrid()
	for _, tile in ipairs(tiles) do
		tile.button:Destroy()
	end
	table.clear(tiles)
end

local function paintRail()
	local reduced = UITheme.MotionReduced()
	local seconds = PickerMotion.Seconds(PickerMotion.Select, reduced)
	local nudge = PickerMotion.Slide(PickerMotion.TabIn, reduced) / 2.5
	local sizes = BuildMenuLogic.SizesFor(phoneNow)
	for i, row in ipairs(railRows) do
		local on = i == catIndex
		local bar = row:FindFirstChild("Bar")
		if bar and bar:IsA("GuiObject") then
			bar.Visible = on
		end
		local edge = row:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			UITheme.Tween(edge, seconds, {
				Color = if on then Palette.CoinGold else UITheme.Skin.Bark,
				Thickness = if on then 3 else 1,
			})
		end
		UITheme.Tween(row, seconds, { BackgroundColor3 = if on then C.Cream else C.Paper })
		-- The chosen tab's label steps in a little.
		local label = row:FindFirstChild("Label")
		if label and label:IsA("GuiObject") then
			UITheme.Tween(label, seconds, {
				Position = UDim2.new(0, sizes.bar + sizes.icon + 4 + (if on then nudge else 0), 0.5, 0),
			})
		end
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
	local cs = HammerPicker.CardSizes(phoneNow)
	local panelWidth = if panel then absSize(panel).X / math.max(UITheme.Scale(), 0.01) else 0
	local grid = HammerPicker.GridFor(
		if panelWidth > 0 then panelWidth else BuildMenuLogic.Layout(667, phoneNow, 1).panelW,
		phoneNow
	)
	local layout = list:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(math.floor(grid.tileW), cs.h)
		layout.CellPadding = UDim2.fromOffset(BuildMenuLogic.TileGap, BuildMenuLogic.TileGap)
	end
	if not cat then
		return
	end
	local ctx = o.ctx()
	local reduced = UITheme.MotionReduced()
	for i, entry in ipairs(cat.entries) do
		local view = BuildMenuLogic.Tile(entry, ctx)
		local card = HammerPicker.Card(entry, ctx)
		local btn = buildTile(entry, view, card, sizes, cs, i)
		btn.Parent = list
		btn.Activated:Connect(function()
			BuildMenuUI.Press(entry)
		end)
		table.insert(tiles, { entry = entry, button = btn, view = view, card = card })
		-- The first few cards pop in one after another (a few short tweens, none on a calm screen).
		if PickerMotion.Animates(i, reduced) then
			local grow = btn:FindFirstChild("Respond")
			if grow and grow:IsA("UIScale") then
				grow.Scale = PickerMotion.CardIn.fromScale :: number
				local wait = PickerMotion.Delay(i, reduced)
				task.delay(wait, function()
					if btn.Parent then
						UITheme.Tween(
							grow,
							PickerMotion.Seconds(PickerMotion.CardIn, UITheme.MotionReduced()),
							{ Scale = 1 },
							Enum.EasingStyle.Back
						)
					end
				end)
			end
		end
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
	local note = emptyNote
	if note then
		note.Visible = #tiles == 0
		note.Text = string.format(
			"No %s plans yet. New ones appear here as you learn them.",
			string.lower(categories[catIndex].label)
		)
	end
	if focusFirst then
		if #tiles > 0 then
			focusTile(BuildMenuLogic.FirstTile(categories[catIndex]))
		elseif railRows[catIndex] then
			GuiService.SelectedObject = railRows[catIndex] -- an empty tab: stay on its tab
		end
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
		row.SelectionImageObject = focusRing(3, ROW_RADIUS)
		UITheme.corner(row, ROW_RADIUS)
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
		UITheme.Respond(row)
		return row
	end
	for i, cat in ipairs(categories) do
		-- The tab's icon is its first piece's art (its swatch until the render is set);
		-- an empty tab keeps a plain wood swatch.
		local first = cat.entries[1]
		local row = makeRow(cat.label, Color3.fromHex(if first then BuildMenuLogic.Swatch(first.bp) else "#8C6A45"), i)
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
	local dir = if HammerPicker.ActionOf(input.KeyCode) == "tabPrev" then -1 else 1
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
	ContextActionService:UnbindAction(TABS_ACTION)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(HOLD_ACTION)
	MenuPad.Close(p) -- the selection goes back to the HUD button that opened the menu
	-- The panel sinks and the backdrop fades, then the screen goes. A calm screen
	-- (or no time) hides it at once.
	closeToken += 1
	local token = closeToken
	local reduced = UITheme.MotionReduced()
	local seconds = PickerMotion.Seconds(PickerMotion.Close, reduced)
	if g and p and seconds > 0 then
		UITheme.Tween(
			p,
			seconds,
			{ Position = UDim2.new(0.5, 0, 0.5, PickerMotion.Slide(PickerMotion.Close, reduced)) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		local dim = scrim
		if dim then
			UITheme.Tween(dim, seconds, { BackgroundTransparency = 1 })
		end
		task.delay(seconds, function()
			if closeToken == token and not isOpen then
				g.Enabled = false
			end
		end)
	elseif g then
		g.Enabled = false
	end
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
	categories = HammerPicker.TabList(o.entries())
	closeToken += 1 -- a close still fading does not hide it again
	g.Enabled = true
	isOpen = true
	fitPanel()
	reportModal()
	-- The panel rises into place and the backdrop fades in (PickerMotion).
	local reduced = UITheme.MotionReduced()
	local seconds = PickerMotion.Seconds(PickerMotion.Open, reduced)
	local dim = scrim
	if seconds > 0 then
		p.Position = UDim2.new(0.5, 0, 0.5, PickerMotion.Slide(PickerMotion.Open, reduced))
		if dim then
			dim.BackgroundTransparency = 1
		end
		UITheme.Tween(p, seconds, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
		if dim then
			UITheme.Tween(dim, seconds, { BackgroundTransparency = SCRIM_ALPHA })
		end
	else
		p.Position = UDim2.fromScale(0.5, 0.5)
		if dim then
			dim.BackgroundTransparency = SCRIM_ALPHA
		end
	end
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
	dim.BackgroundTransparency = SCRIM_ALPHA
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Selectable = false
	dim.Modal = true
	dim.Parent = g
	dim.Activated:Connect(BuildMenuUI.Close)
	scrim = dim

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
	hintItem(hint, Enum.KeyCode.ButtonA, "Pick", 1)
	hintItem(hint, Enum.KeyCode.ButtonB, "Close", 2)
	hintItem(hint, Enum.KeyCode.ButtonL1, "", 3)
	hintItem(hint, Enum.KeyCode.ButtonR1, "Tab", 4)
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

	local note = Instance.new("TextLabel")
	note.Name = "EmptyNote"
	note.AnchorPoint = Vector2.new(1, 0)
	note.Position = UDim2.fromScale(1, 0)
	note.Size = UDim2.new(1, -(railSize + BuildMenuLogic.RailGap), 0, 80)
	note.BackgroundTransparency = 1
	note.Font = F.Body
	note.TextSize = 16
	note.TextColor3 = C.Bark
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Visible = false
	note.Parent = body
	emptyNote = note

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
function BuildMenuUI.Tiles(): {
	{
		entry: BlueprintBook.Entry,
		button: TextButton,
		view: BuildMenuLogic.TileView,
		card: HammerPicker.Card,
	}
}
	return tiles
end

function BuildMenuUI.Category(): HammerPicker.Tab?
	return categories[catIndex]
end

function BuildMenuUI.CloseFace(): GuiObject?
	return closeFace
end

return BuildMenuUI
