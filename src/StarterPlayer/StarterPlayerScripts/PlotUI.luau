--!strict
-- PlotUI: building on your plot (PlotService on the server; BUILD_SYSTEM.md).
--   * Building is the hammer (HammerController). While the hammer is in your
--     hand on your own plot, a bar offers PLANS, LAND, WIRE and DONE, and the
--     lines of any wiring show. Using the hammer (click, RT, tap) or PLANS
--     opens your blueprint list, drawn by ShopUI.
--   * The list is the book of buildings you own for good (BlueprintBook): a
--     row each, with its size and what it needs (planks of one wood, a fee,
--     a box from the Tool Shed). A sawmill or the chop saw you hold shows with
--     its count, and goes down free; a kit piece goes down as an empty ghost
--     for a fee, then takes planks. Rows are locked until your plot size
--     allows them (the message points to LAND). A filter row cycles the
--     groups. Picking a row hands the blueprint to BlueprintPlacer.
--   * Aiming the hammer at something you built opens its sheet instead
--     (Move, Turn, Sell: HammerController).
--   * The LAND panel has two sections: "Plot size" (level N of 5, what the
--     next level unlocks and costs) and "Expand" (squares beyond the plot
--     size). Words: plot = your claimed pad, plot size = its level,
--     expand = buying squares.
--   * Walking off your plot, or putting the hammer away, ends it.
-- Everything only sends intents; the server checks and answers with toasts.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local DragController = require(script.Parent.DragController)
local HammerController = require(script.Parent.HammerController)
local GamepadNav = require(script.Parent.GamepadNav)
local HUD = require(script.Parent.HUD)
local HudNav = require(script.Parent.HudNav)
local ShopUI = require(script.Parent.ShopUI)
local UITheme = require(script.Parent.UITheme)
local WireTool = require(script.Parent.WireTool)

local PlotUI = {}

local player = Players.LocalPlayer

local C = UITheme.Colors

local REACH = 40 -- studs past your plot's edge that still count as on it (PlotService's BUILD_REACH)

local building = false -- the hammer is in your hand, on your own plot
local hammerButton: UITheme.Button? = nil
local modeBar: Frame? = nil
local landPanel: Frame? = nil
local landPrice: TextLabel? = nil
local landGrid: Frame? = nil
local landSizeNow: TextLabel? = nil
local landSizeNext: TextLabel? = nil
local landGrow: UITheme.Button? = nil
local landOpen = false
local openLandPanel: () -> () = function() end -- set once the Land panel exists
local filter = "All" -- the list's group filter (BlueprintBook.Filters)

local function cash(): number
	return (player:GetAttribute("Cash") :: number?) or 0
end

local function tier(): number
	return (player:GetAttribute("PlotTier") :: number?) or 1
end

local function onMyPlot(): boolean
	local plotCFrame = BlueprintPlacer.PlotCFrame()
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not plotCFrame or not root then
		return false
	end
	local size = (PlotData.Tier(tier()) or PlotData.Tiers[1]).size
	local p = plotCFrame:PointToObjectSpace(root.Position)
	return math.max(math.abs(p.X), math.abs(p.Z)) <= size / 2 + REACH
end

---------------------------------------------------------------------------
-- The blueprint list
---------------------------------------------------------------------------

local FILTER_ROW = "#filter"
local LAND_ROW = "#land"

-- Boxes you hold (sawmills and the chop saw), by id.
local function myStock(): BlueprintBook.Stock
	local stock: BlueprintBook.Stock = {}
	for _, id in ipairs(SawmillLogic.DecodeStock((player:GetAttribute("SawmillStock") :: string?) or "")) do
		stock[id] = (stock[id] or 0) + 1
	end
	return stock
end

-- Your book, as the server publishes it (the Blueprints attribute).
local function myBook(): BlueprintBook.Book
	local ids: BlueprintBook.Book = {}
	for id in pairs(ShopLogic.DecodeSet((player:GetAttribute("Blueprints") :: string?) or "")) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function ownsBlueprint(id: string): boolean
	return table.find(myBook(), id) ~= nil
end

local function entries(): { BlueprintBook.Entry }
	return BlueprintBook.Filter(BlueprintBook.Entries(myBook(), myStock()), filter)
end

-- A box in stock, or a store unlock you learned, places for free. The table
-- the placer sees has price 0 so the ghost doesn't ask for cash the server
-- won't charge.
local function forPlacer(bp: PlotData.Blueprint, stocked: number): PlotData.Blueprint
	if stocked > 0 or (PlotLogic.FreeToPlace(bp) and ownsBlueprint(bp.id)) then
		local copy = table.clone(bp)
		copy.priceCash = 0
		return copy
	end
	return bp
end

local function planRow(entry: BlueprintBook.Entry): ShopUI.RowView
	local ctx: BlueprintBook.Context = { tier = tier(), cash = cash(), boxed = ShopLogic.ShelfMenusHidden() }
	local row = BlueprintBook.Row(entry, ctx)
	local bp = entry.bp
	local mill = ItemCatalog.GetSawmill(bp.id)
	local machine = ItemCatalog.GetMachine(bp.id)
	local swatch = if mill
		then mill.color
		elseif machine then machine.color
		elseif bp.boxes[1] then bp.boxes[1].color
		else "#654321"
	return {
		name = row.name,
		own = row.own,
		detail = row.detail,
		color = Color3.fromHex(swatch),
		dim = row.state == "locked",
		button = row.button,
		state = row.state,
		onClick = function()
			if not row.ready then
				HUD.Toast(row.message or "You can't place that yet.")
				return
			end
			if not onMyPlot() then
				HUD.Toast("Walk onto your plot to build.")
				return
			end
			-- The server's own rule, asked first so the ghost never shows
			-- for something it will refuse.
			local ok, why =
				BlueprintBook.Allowed(bp.id, ownsBlueprint(bp.id), entry.stock, ShopLogic.ShelfMenusHidden())
			if not ok then
				HUD.Toast(BlueprintBook.Message(why, bp))
				return
			end
			ShopUI.Close()
			BlueprintPlacer.Begin(forPlacer(bp, entry.stock), { onStop = PlotUI.Refresh })
			PlotUI.Refresh()
		end,
	}
end

local STORE: ShopUI.Shop

local function filterRow(): ShopUI.RowView
	return {
		name = "Showing: " .. filter,
		own = nil,
		detail = "Switch between " .. table.concat(BlueprintBook.Filters, ", ") .. ".",
		color = Color3.fromHex("#583A22"),
		dim = false,
		button = "Next",
		state = "use",
		onClick = function()
			filter = BlueprintBook.NextFilter(filter)
			ShopUI.OpenCustom(STORE, FILTER_ROW)
		end,
	}
end

local function landRow(): ShopUI.RowView
	return {
		name = "Land",
		own = nil,
		detail = "Plot size and new squares to expand onto.",
		color = Color3.fromHex("#4C8C40"),
		dim = false,
		button = "Open",
		state = "use",
		onClick = function()
			ShopUI.Close()
			openLandPanel()
		end,
	}
end

STORE = {
	building = nil,
	promptText = "",
	title = "Blueprints",
	subtitle = "Your plans, yours for good.",
	ids = function()
		local ids: { string } = { FILTER_ROW, LAND_ROW }
		for _, entry in ipairs(entries()) do
			table.insert(ids, entry.id)
		end
		return ids
	end,
	view = function(id: string): ShopUI.RowView
		if id == FILTER_ROW then
			return filterRow()
		elseif id == LAND_ROW then
			return landRow()
		end
		for _, entry in ipairs(entries()) do
			if entry.id == id then
				return planRow(entry)
			end
		end
		-- A box you just placed: its row stays until the list is reopened.
		local bp = PlotLogic.Blueprint(id)
		return {
			name = if bp then bp.displayName else id,
			own = nil,
			detail = "None left. Reopen the list.",
			color = Color3.fromHex("#A09178"),
			dim = true,
			button = "Gone",
			state = "cant",
			onClick = function() end,
		}
	end,
}

-- The list as a ShopUI screen (tests read it; ShopUI draws it).
function PlotUI.Plans(): ShopUI.Shop
	return STORE
end

-- Opens the list (the hammer's use, or PLANS). The tutorial counts it when
-- you do it on your own plot.
local function openPlans()
	if building then
		Net.Remote("TutorialSeen"):FireServer("build")
	end
	ShopUI.OpenCustom(STORE)
end

---------------------------------------------------------------------------
-- The hammer in hand
---------------------------------------------------------------------------

local function setBuilding(on: boolean)
	if building == on then
		return
	end
	building = on
	HUD.SetBuildMode(on)
	DragController.SetBuildMode(on)
	WireTool.SetBuilding(on)
	if not on then
		BlueprintPlacer.Stop()
		ShopUI.Close()
	end
	PlotUI.Refresh()
end

-- Shows the right buttons for where you are and what you're doing.
function PlotUI.Refresh()
	local placing = BlueprintPlacer.Active()
	local b = hammerButton
	if b then
		-- A phone has no number keys: a button takes the hammer out on your plot.
		b.root.Visible = UITheme.Device() == "phone" and not HammerController.Held() and onMyPlot()
	end
	local bar = modeBar
	if bar then
		bar.Visible = building and not placing and not WireTool.Active()
	end
end

---------------------------------------------------------------------------
-- Land panel. The LAND button (build bar) or the sign's prompt opens it. Two
-- sections: "Plot size" (the five levels, PlotData.Tiers) and "Expand"
-- (squares beyond the plot size). The expand price on the card is the price
-- the server charges (PlotLogic.ExpansionPrice). Esc and B close it.
---------------------------------------------------------------------------

local LAND_ACTION = "LandOfficeClose"

local function ownedSquares(): { string }
	local raw = player:GetAttribute("PlotSquares")
	local out: { string } = {}
	if type(raw) ~= "string" or raw == "" then
		return out
	end
	for key in string.gmatch(raw, "[^;]+") do
		table.insert(out, key)
	end
	return out
end

-- The "Plot size" section: where you are, what the next level gives, and
-- the button for it.
local function rebuildSize()
	local nowLabel = landSizeNow
	local nextLabel = landSizeNext
	local grow = landGrow
	if not nowLabel or not nextLabel or not grow then
		return
	end
	local card = PlotLogic.SizeCard(tier(), cash())
	nowLabel.Text =
		string.format("Level %d of %d: %s (%d × %d studs)", card.level, card.levels, card.name, card.size, card.size)
	local nextLevel = card.next
	if not nextLevel then
		nextLabel.Text = "That's the biggest plot size. You can still expand onto squares below."
		grow.root.Visible = false
		return
	end
	local unlocks = if nextLevel.unlocks ~= "" then " " .. nextLevel.unlocks .. "." else ""
	nextLabel.Text = string.format(
		"Next, level %d: %s, %d × %d studs.%s",
		card.level + 1,
		nextLevel.name,
		nextLevel.size,
		nextLevel.size,
		unlocks
	)
	grow.root.Visible = true
	grow.face.Text = "RAISE PLOT SIZE " .. Util.formatCash(nextLevel.price)
	grow:SetStyle(if nextLevel.affordable then "buy" else "cant")
end

local function rebuildLand()
	local grid = landGrid
	local label = landPrice
	if not grid or not label then
		return
	end
	rebuildSize()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Layout" then
			child:Destroy()
		end
	end
	local squares = ownedSquares()
	local price = PlotLogic.ExpansionPrice(#squares)
	local half = PlotLogic.GridHalf()
	local span = half * 2 + 1
	local forSale = 0
	local firstBuy: GuiButton? = nil
	local styles: { [string]: string } = { buy = "buy", bought = "bark", included = "starter", far = "skip" }
	for iz = half, -half, -1 do
		for ix = -half, half do
			local key, why = PlotLogic.ExpansionBlock(tier(), squares, ix, iz)
			local text, kind = PlotLogic.CellLabel(tier(), squares, ix, iz)
			local tap = PlotLogic.LandTap
			local button = UITheme.Button({
				name = PlotLogic.Key(ix, iz),
				text = text,
				size = Vector2.new(tap, tap),
				style = styles[kind] or "skip",
				textSize = 14,
			})
			button.root.LayoutOrder = (half - iz) * span + (ix + half)
			button.root.Parent = grid
			local buyKey = key
			local blocked = why
			local expected = #squares
			button.face.Activated:Connect(function()
				if buyKey then
					Net.Remote("ExpandLand"):FireServer(ix, iz, expected)
					-- Whatever the server says (a changed price, no cash), the
					-- panel redraws from the truth a moment later.
					task.delay(0.6, function()
						if landOpen then
							rebuildLand()
						end
					end)
				else
					HUD.Toast(PlotLogic.ExpansionMessage(blocked) or "You can't expand onto that square.")
				end
			end)
			if buyKey then
				forSale += 1
				if firstBuy == nil then
					firstBuy = button.face
				end
			end
		end
	end
	if forSale == 0 or not price then
		label.Text = "Your plot already covers every square."
	else
		label.Text = "Next square costs " .. Util.formatCash(price) .. ". Each one costs more."
	end
	if landOpen and UITheme.Device() == "console" then
		local grow = landGrow
		if firstBuy then
			GamepadNav.Focus(firstBuy, landPanel)
		elseif grow and grow.root.Visible then
			GamepadNav.Focus(grow.face, landPanel)
		end
	end
end

local function setLand(on: boolean)
	local panel = landPanel
	if not panel then
		return
	end
	local opening = on and not landOpen
	landOpen = on
	panel.Visible = on
	if on then
		rebuildLand()
		if opening then
			Net.Remote("TutorialSeen"):FireServer("land")
		end
		ContextActionService:BindActionAtPriority(
			LAND_ACTION,
			function(_name, state)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				setLand(false)
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 20,
			InputKit.Actions.Cancel.keyboard,
			InputKit.Actions.Cancel.gamepad
		)
	else
		ContextActionService:UnbindAction(LAND_ACTION)
		GamepadNav.Restore(panel) -- back to the button that opened it, or to walking
	end
end

local function sectionLabel(parent: Instance, order: number, text: string, header: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = if header then UITheme.Fonts.Heading else UITheme.Fonts.Body
	label.TextSize = if header then 18 else 16
	label.TextColor3 = if header then C.Bark else C.Ink
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -8, 0, 0)
	label.LayoutOrder = order
	label.Text = text
	label.Parent = parent
	return label
end

local function mountLand(gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "LandOffice"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 330, 0.92, 0)
	panel.BackgroundColor3 = C.Paper
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	UITheme.corner(panel, 14)
	UITheme.stroke(panel, C.Bark, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(330, 540)
	limit.Parent = panel
	panel.Parent = gui
	landPanel = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = UITheme.Fonts.Heading
	title.TextSize = 22
	title.TextColor3 = C.Ink
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -64, 0, 32)
	title.Position = UDim2.fromOffset(14, 10)
	title.Text = "Land"
	title.Parent = panel

	local close = UITheme.Button({
		text = "X",
		size = Vector2.new(PlotLogic.LandTap, PlotLogic.LandTap),
		style = "skip",
		textSize = 18,
	})
	close.root.Position = UDim2.new(1, -(PlotLogic.LandTap + 8), 0, 8)
	close.root.Parent = panel
	close.face.Activated:Connect(function()
		setLand(false)
	end)

	-- One scrolling column: Plot size, then Expand.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(12, 60)
	body.Size = UDim2.new(1, -24, 1, -70)
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.Selectable = false
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	body.Parent = panel

	sectionLabel(body, 1, "PLOT SIZE", true)
	landSizeNow = sectionLabel(body, 2, "", false)
	landSizeNext = sectionLabel(body, 3, "", false)
	local grow = UITheme.Button({
		name = "RaisePlotSize",
		text = "RAISE PLOT SIZE",
		size = Vector2.new(280, PlotLogic.LandTap),
		style = "buy",
		textSize = 15,
	})
	grow.root.LayoutOrder = 4
	grow.root.Parent = body
	grow.face.Activated:Connect(function()
		local card = PlotLogic.SizeCard(tier(), cash())
		local nextLevel = card.next
		if nextLevel and not nextLevel.affordable then
			HUD.Toast(
				string.format(
					"You need %s more to raise your plot size to %s.",
					Util.formatCash(nextLevel.short),
					nextLevel.name
				)
			)
			return
		end
		Net.Remote("UpgradePlot"):FireServer()
	end)
	landGrow = grow

	sectionLabel(body, 5, "EXPAND", true)
	landPrice = sectionLabel(body, 6, "", false)
	local holder = Instance.new("Frame")
	holder.Name = "Grid"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Size = UDim2.fromScale(1, 0)
	holder.LayoutOrder = 7
	local layout = Instance.new("UIGridLayout")
	layout.Name = "Layout"
	layout.CellSize = UDim2.fromOffset(PlotLogic.LandTap, PlotLogic.LandTap)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	holder.Parent = body
	landGrid = holder
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------

function PlotUI.Start()
	local gui = UITheme.Screen("PlotUI", UITheme.Layers.PlotUI) -- its bar draws over any side button spilling that far

	-- On a phone: take the hammer out (the hotbar's number keys are not there).
	hammerButton = HUD.SideButton({
		name = "Hammer",
		text = "HAMMER",
		style = "buy",
		order = 1,
		icon = "Hammer",
		onPress = HammerController.Equip,
	})

	local bar = UITheme.Bar(gui, "BuildMode") -- where BlueprintPlacer's bar goes
	bar.label.Text = "HAMMER · aim at a piece to move, turn or sell it"
	local blueprints = UITheme.Button({
		name = "Plans",
		text = "PLANS",
		size = Vector2.new(150, PlotLogic.LandTap),
		style = "buy",
	})
	blueprints.root.LayoutOrder = 1
	blueprints.root.Parent = bar.row
	blueprints.face.Activated:Connect(openPlans)
	HudNav.Add(blueprints.face, { id = "plans", label = "PLANS", press = openPlans })
	local land = UITheme.Button({
		text = "LAND",
		size = Vector2.new(96, PlotLogic.LandTap),
		style = "buy",
		textSize = 15,
	})
	land.root.LayoutOrder = 2
	land.root.Parent = bar.row
	land.face.Activated:Connect(function()
		setLand(not landOpen)
	end)
	HudNav.Add(land.face, {
		id = "land",
		label = "LAND",
		press = function()
			setLand(not landOpen)
		end,
	})
	local wire = UITheme.Button({
		text = "WIRE",
		size = Vector2.new(96, PlotLogic.LandTap),
		style = "buy",
		textSize = 15,
	})
	wire.root.LayoutOrder = 3
	wire.root.Parent = bar.row
	wire.face.Activated:Connect(function()
		ShopUI.Close()
		setLand(false)
		WireTool.Begin(PlotUI.Refresh)
		PlotUI.Refresh()
	end)
	local done = UITheme.Button({ text = "DONE", size = Vector2.new(98, PlotLogic.LandTap), style = "skip" })
	done.root.LayoutOrder = 4
	done.root.Parent = bar.row
	done.face.Activated:Connect(function()
		setLand(false)
		HammerController.PutAway()
	end)
	modeBar = bar.outer
	mountLand(gui)
	openLandPanel = function()
		setLand(true)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt.Name == "LandOffice" then
			-- Only your own sign opens your Land panel.
			local plot = prompt:FindFirstAncestorOfClass("Model")
			if plot and plot:GetAttribute("OwnerId") ~= player.UserId then
				HUD.Toast("That's someone else's plot. Visit your own sign to expand.")
				return
			end
			setLand(not landOpen)
		end
	end)

	-- The hammer: using it opens the list, and the Land panel keeps the click.
	HammerController.SetOpener(openPlans)
	HammerController.SetPanelCheck(function()
		return landOpen
	end)
	HammerController.OnHeldChanged(function(on: boolean)
		setBuilding(on and onMyPlot())
	end)
	for _, attribute in ipairs({ "PlotSlot", "PlotTier", "Cash", "SawmillStock", "PlotSquares", "Blueprints" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			ShopUI.Refresh()
			PlotUI.Refresh()
			if landOpen then
				rebuildLand()
			end
		end)
	end
	-- The hammer is in hand on your plot: the bar is up. Walk off, or put it
	-- away, and it ends.
	task.spawn(function()
		local wasOn = false
		local lastHint = -math.huge
		while true do
			task.wait(0.25)
			local on = HammerController.Held() and onMyPlot()
			setBuilding(on)
			-- The bar goes off your plot; say where it went, once a minute.
			if wasOn and not on and HammerController.Held() and os.clock() - lastHint > 60 then
				lastHint = os.clock()
				HUD.Toast("Walk back to your plot to build.")
			end
			wasOn = on
			PlotUI.Refresh()
		end
	end)
end

return PlotUI
