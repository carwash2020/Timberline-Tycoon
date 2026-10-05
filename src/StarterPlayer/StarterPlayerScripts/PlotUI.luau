--!strict
-- PlotUI: building on your plot (PlotService on the server).
--   * A BUILD button shows while you stand on your own plot. It starts
--     build mode: the Blueprint Store opens (drawn by ShopUI), a bar offers
--     BLUEPRINTS and DONE, and everything you've placed gets Move (E) and
--     Sell (F, hold) prompts.
--   * The store's first row grows the plot to its next base tier; the rest
--     are blueprints, locked until your plot's tier allows them. Picking one
--     hands it to BlueprintPlacer (the ghost preview); you pay on placing.
--   * Walking off your plot ends build mode.
-- Everything only sends intents; the server checks and answers with toasts.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local HUD = require(script.Parent.HUD)
local ShopUI = require(script.Parent.ShopUI)
local UITheme = require(script.Parent.UITheme)

local PlotUI = {}

local player = Players.LocalPlayer

local C = UITheme.Colors

local REACH = 40 -- studs past your plot's edge that still count as on it (PlotService's BUILD_REACH)
local PLOT_ROW = "_plot"

local building = false
local buildButton: UITheme.Button? = nil
local modeBar: Frame? = nil
local landPanel: Frame? = nil
local landPrice: TextLabel? = nil
local landGrid: ScrollingFrame? = nil
local landOpen = false
local itemPrompts: { [Instance]: { ProximityPrompt } } = {}
-- Client-only. SetAttribute on a server model is rejected, so a flag
-- attribute would throw and the prompts would never appear.
local promptWait: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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
-- The Blueprint Store
---------------------------------------------------------------------------

-- Blueprint names a tier unlocks, for the upgrade row.
local function unlocksAt(tierIndex: number): string
	local names: { string } = {}
	for _, bp in ipairs(PlotData.Blueprints) do
		if bp.tier == tierIndex then
			table.insert(names, bp.displayName)
		end
	end
	return if #names > 0 then "Unlocks: " .. table.concat(names, ", ") else ""
end

local function plotRow(): ShopUI.RowView
	local now = PlotData.Tier(tier()) or PlotData.Tiers[1]
	local nextTier = PlotData.Tier(tier() + 1)
	if not nextTier then
		return {
			name = now.name,
			detail = string.format("%d × %d studs: your plot is as big as it gets.", now.size, now.size),
			color = C.Green,
			ring = C.Amber,
			dim = false,
			button = "Max",
			state = "inuse",
			onClick = function() end,
		}
	end
	local affordable = cash() >= nextTier.priceCash
	return {
		name = "Grow to " .. nextTier.name,
		detail = string.format(
			"%d × %d studs (now %d × %d). %s",
			nextTier.size,
			nextTier.size,
			now.size,
			now.size,
			unlocksAt(tier() + 1)
		),
		color = C.Blue,
		dim = false,
		button = if affordable
			then "Grow " .. Util.formatCash(nextTier.priceCash)
			else Util.formatCash(nextTier.priceCash),
		state = if affordable then "buy" else "cant",
		onClick = function()
			if cash() < nextTier.priceCash then
				HUD.Toast(
					string.format(
						"You need %s more for %s.",
						Util.formatCash(nextTier.priceCash - cash()),
						Util.article(nextTier.name)
					)
				)
				return
			end
			Net.Remote("UpgradePlot"):FireServer()
		end,
	}
end

local function stockCount(id: string): number
	return SawmillLogic.CountStock(SawmillLogic.DecodeStock((player:GetAttribute("SawmillStock") :: string?) or ""), id)
end

local function ownsBlueprint(id: string): boolean
	local owned = ShopLogic.DecodeSet((player:GetAttribute("Blueprints") :: string?) or "")
	return owned[id] == true
end

-- A sawmill you already bought, or an unlock blueprint you own, places for
-- free. The table the placer sees has price 0 so the ghost doesn't ask for
-- cash the server won't charge.
local function forPlacer(bp: PlotData.Blueprint): PlotData.Blueprint
	if stockCount(bp.id) > 0 or (bp.unlock == true and ownsBlueprint(bp.id)) then
		local copy = table.clone(bp)
		copy.priceCash = 0
		return copy
	end
	return bp
end

local function blueprintRow(bp: PlotData.Blueprint): ShopUI.RowView
	local locked = bp.tier > tier()
	local needed = PlotData.Tier(bp.tier)
	local stocked = stockCount(bp.id)
	local unlocked = bp.unlock == true and ownsBlueprint(bp.id)
	local atStore = bp.unlock == true and not unlocked
	local price = if stocked > 0 or unlocked then 0 else PlotData.Price(bp)
	local affordable = cash() >= price
	local detail = string.format("%s · %d × %d", bp.category, bp.footprint.X, bp.footprint.Y)
	if locked and needed then
		detail ..= " · needs " .. Util.article(needed.name) .. " plot"
	elseif bp.note then
		detail ..= " · " .. bp.note
	end
	if stocked > 0 then
		detail ..= string.format(" · %d ready to place", stocked)
	end
	local mill = ItemCatalog.GetSawmill(bp.id)
	local machine = ItemCatalog.GetMachine(bp.id)
	local swatch = if mill
		then mill.color
		elseif machine then machine.color
		elseif bp.boxes[1] then bp.boxes[1].color
		else "#654321"
	local button, state
	if locked then
		button, state = if needed then needed.name else "Locked", "locked"
	elseif stocked > 0 or unlocked then
		button, state = "Place", "buy"
	elseif atStore then
		button, state = "At the store", "locked"
	elseif affordable then
		button, state = "Build " .. Util.formatCash(price), "buy"
	else
		button, state = Util.formatCash(price), "cant"
	end
	return {
		name = bp.displayName,
		own = if stocked > 0 then "· in stock" else nil,
		detail = detail,
		color = Color3.fromHex(swatch),
		dim = locked,
		button = button,
		state = state,
		onClick = function()
			if bp.tier > tier() then
				HUD.Toast(
					string.format(
						"Grow your plot to %s first.",
						Util.article(if needed then needed.name else "bigger plot")
					)
				)
			elseif atStore then
				HUD.Toast(string.format("Buy the %s at the General Store first.", bp.displayName))
			elseif cash() < price then
				HUD.Toast(
					string.format("You need %s more for the %s.", Util.formatCash(price - cash()), bp.displayName)
				)
			else
				ShopUI.Close()
				BlueprintPlacer.Begin(forPlacer(bp), { onStop = PlotUI.Refresh })
				PlotUI.Refresh()
			end
		end,
	}
end

local STORE: ShopUI.Shop = {
	building = nil,
	promptText = "",
	title = "Blueprint Store",
	subtitle = "You pay when you place it. Sold back: half (all of it within a minute).",
	ids = function()
		local ids = { PLOT_ROW }
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			table.insert(ids, mill.id)
		end
		for _, machine in ipairs(ItemCatalog.MachineList()) do
			table.insert(ids, machine.id)
		end
		local sorted = table.clone(PlotData.Blueprints)
		table.sort(sorted, function(a, b)
			if a.tier ~= b.tier then
				return a.tier < b.tier
			end
			return PlotData.Price(a) < PlotData.Price(b)
		end)
		for _, bp in ipairs(sorted) do
			table.insert(ids, bp.id)
		end
		return ids
	end,
	view = function(id: string): ShopUI.RowView
		if id == PLOT_ROW then
			return plotRow()
		end
		return blueprintRow(PlotLogic.Blueprint(id) :: PlotData.Blueprint)
	end,
}

---------------------------------------------------------------------------
-- Build mode: prompts on your placed things
---------------------------------------------------------------------------

local function removePrompts(model: Instance)
	local list = itemPrompts[model]
	itemPrompts[model] = nil
	if list then
		for _, prompt in ipairs(list) do
			prompt:Destroy()
		end
	end
end

local function addPrompts(model: Instance)
	if itemPrompts[model] or model:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	local uid = model:GetAttribute("Uid") :: string?
	local bp = PlotLogic.Blueprint((model:GetAttribute("BlueprintId") :: string?) or "")
	local root = model:FindFirstChild("Root")
	if not uid or not bp or not root then
		-- An Atomic model arrives whole. One that streamed in pieces (or
		-- whose Root is a frame behind the tag) still gets its prompts.
		if uid and bp and not root and not promptWait[model] then
			promptWait[model] = true
			task.spawn(function()
				local found = model:WaitForChild("Root", 8)
				if found and found.Parent and building then
					addPrompts(model)
					PlotUI.Refresh()
				end
			end)
		end
		return
	end
	local reach = math.max(10, math.max(bp.footprint.X, bp.footprint.Y) / 2 + 6)
	local function prompt(
		action: string,
		key: Enum.KeyCode,
		pad: Enum.KeyCode,
		hold: number,
		dy: number
	): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		p.ActionText = action
		p.ObjectText = bp.displayName
		p.KeyboardKeyCode = key
		p.GamepadKeyCode = pad
		p.HoldDuration = hold
		p.MaxActivationDistance = reach
		p.RequiresLineOfSight = false
		p.UIOffset = Vector2.new(0, dy) -- the two stack, Move over Sell
		p.Parent = root
		return p
	end
	local move = prompt("Move", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0, -36)
	move.Triggered:Connect(function()
		ShopUI.Close()
		BlueprintPlacer.Begin(bp, { moveUid = uid, onStop = PlotUI.Refresh })
		PlotUI.Refresh()
	end)
	local sell = prompt(
		"Sell (+" .. Util.formatCash(PlotLogic.SellValue(bp)) .. ")",
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonY,
		0.6,
		36
	)
	sell.Triggered:Connect(function()
		Net.Remote("SellPlaced"):FireServer(uid)
	end)
	itemPrompts[model] = { move, sell }
end

local function setBuilding(on: boolean)
	if building == on then
		return
	end
	building = on
	HUD.SetBuildMode(on)
	DragController.SetBuildMode(on)
	if on then
		for _, model in ipairs(CollectionService:GetTagged("PlacedItem")) do
			addPrompts(model)
		end
		ShopUI.OpenCustom(STORE)
	else
		BlueprintPlacer.Stop()
		ShopUI.Close()
		for model in pairs(itemPrompts) do
			removePrompts(model)
		end
	end
	PlotUI.Refresh()
end

-- Shows the right buttons for where you are and what you're doing.
function PlotUI.Refresh()
	local placing = BlueprintPlacer.Active()
	local b = buildButton
	if b then
		b.root.Visible = not building and onMyPlot()
	end
	local bar = modeBar
	if bar then
		bar.Visible = building and not placing
	end
	for _, list in pairs(itemPrompts) do
		for _, prompt in ipairs(list) do
			prompt.Enabled = not placing
		end
	end
end

---------------------------------------------------------------------------
-- Land office. The sign prompt opens it. The price on the card is the
-- price the server charges (PlotLogic.ExpansionPrice). Esc and B close it.
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

local function rebuildLand()
	local grid = landGrid
	local label = landPrice
	if not grid or not label then
		return
	end
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
	for iz = half, -half, -1 do
		for ix = -half, half do
			local key, why = PlotLogic.ExpansionBlock(tier(), squares, ix, iz)
			local inside = PlotLogic.SquareInsideTier(ix, iz, (PlotData.Tier(tier()) or PlotData.Tiers[1]).size)
			local mine = PlotLogic.Owns(squares, ix, iz)
			local text = if key then "Buy" elseif inside or mine then "Yours" else ""
			local tap = PlotLogic.LandTap
			local button = UITheme.Button({
				name = PlotLogic.Key(ix, iz),
				text = text,
				size = Vector2.new(tap, tap),
				style = if key then "buy" elseif mine or inside then "bark" else "skip",
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
				elseif blocked == "away" then
					HUD.Toast("Buy a square that touches your yard.")
				elseif blocked == "yours" or blocked == "owned" then
					HUD.Toast("That ground is already yours.")
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
		label.Text = "Your yard already covers every square."
	else
		label.Text = "Next square costs " .. Util.formatCash(price)
	end
	if landOpen and firstBuy and UITheme.Device() == "console" then
		GuiService.SelectedObject = firstBuy
	end
end

local function setLand(on: boolean)
	local panel = landPanel
	if not panel then
		return
	end
	landOpen = on
	panel.Visible = on
	if on then
		rebuildLand()
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
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then
			GuiService.SelectedObject = nil
		end
	end
end

local function mountLand(gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "LandOffice"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(300, 300)
	panel.BackgroundColor3 = C.Paper
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	UITheme.corner(panel, 14)
	UITheme.stroke(panel, C.Bark, 3)
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
	title.Text = "Land office"
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

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Font = UITheme.Fonts.Body
	price.TextSize = 16
	price.TextColor3 = C.Ink
	price.TextWrapped = true
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.TextYAlignment = Enum.TextYAlignment.Top
	price.Size = UDim2.new(1, -28, 0, 40)
	price.Position = UDim2.fromOffset(14, 52)
	price.Text = ""
	price.Parent = panel
	landPrice = price

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(12, 96)
	grid.Size = UDim2.new(1, -24, 1, -108)
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollBarThickness = 6
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Selectable = false
	local layout = Instance.new("UIGridLayout")
	layout.Name = "Layout"
	layout.CellSize = UDim2.fromOffset(PlotLogic.LandTap, PlotLogic.LandTap)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = panel
	landGrid = grid
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------

function PlotUI.Start()
	local gui = UITheme.Screen("PlotUI", 2) -- its bar draws over any side button spilling that far

	buildButton = HUD.SideButton({
		name = "Build",
		text = "BUILD",
		style = "buy",
		order = 1,
		onPress = function()
			setBuilding(true)
		end,
	})

	local bar = UITheme.Bar(gui, "BuildMode") -- where BlueprintPlacer's bar goes
	bar.label.Text = "BUILD MODE · walk up to something to move or sell it"
	local blueprints =
		UITheme.Button({ text = "BLUEPRINTS", size = Vector2.new(150, PlotLogic.LandTap), style = "buy" })
	blueprints.root.LayoutOrder = 1
	blueprints.root.Parent = bar.row
	blueprints.face.Activated:Connect(function()
		ShopUI.OpenCustom(STORE)
	end)
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
	local done = UITheme.Button({ text = "DONE", size = Vector2.new(98, PlotLogic.LandTap), style = "skip" })
	done.root.LayoutOrder = 3
	done.root.Parent = bar.row
	done.face.Activated:Connect(function()
		setBuilding(false)
	end)
	modeBar = bar.outer
	mountLand(gui)
	gui.Parent = player:WaitForChild("PlayerGui")
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt.Name == "LandOffice" then
			setLand(not landOpen)
		end
	end)

	CollectionService:GetInstanceAddedSignal("PlacedItem"):Connect(function(model: Instance)
		if building then
			addPrompts(model)
			PlotUI.Refresh()
		end
	end)
	CollectionService:GetInstanceRemovedSignal("PlacedItem"):Connect(removePrompts)
	for _, attribute in ipairs({ "PlotSlot", "PlotTier", "Cash", "SawmillStock", "PlotSquares" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			ShopUI.Refresh()
			PlotUI.Refresh()
			if landOpen then
				rebuildLand()
			end
		end)
	end
	-- Walked off your plot? Build mode ends.
	task.spawn(function()
		while true do
			task.wait(0.25)
			if building and not onMyPlot() then
				setBuilding(false)
			end
			PlotUI.Refresh()
		end
	end)
end

return PlotUI
