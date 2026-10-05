--!strict
-- PlotUI: building on your plot (PlotService on the server).
--   * A BUILD button shows while you stand on your own plot. It starts
--     build mode: the Blueprint Store opens (drawn by ShopUI), a bar offers
--     BLUEPRINTS and DONE, and everything you've placed gets Move (E) and
--     Sell (F, hold) prompts.
--   * The Blueprint Store lists blueprints, locked until your plot size
--     allows them (the message points to LAND). Picking one hands it to
--     BlueprintPlacer (the ghost preview); you pay on placing.
--   * The LAND panel has two sections: "Plot size" (level N of 5, what the
--     next level unlocks and costs) and "Expand" (squares beyond the plot
--     size). Words: plot = your claimed pad, plot size = its level,
--     expand = buying squares.
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

local building = false
local buildButton: UITheme.Button? = nil
local modeBar: Frame? = nil
local landPanel: Frame? = nil
local landPrice: TextLabel? = nil
local landGrid: Frame? = nil
local landSizeNow: TextLabel? = nil
local landSizeNext: TextLabel? = nil
local landGrow: UITheme.Button? = nil
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
		detail ..= " · needs plot size " .. needed.name
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
						"Raise your plot size to %s first. You do that in LAND.",
						if needed then needed.name else "a bigger one"
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
	subtitle = "You pay when you place it. Sold back: half (all of it within a minute). Plot size is in LAND.",
	ids = function()
		local ids: { string } = {}
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
	if on then
		Net.Remote("TutorialSeen"):FireServer("build")
	end
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
			GuiService.SelectedObject = firstBuy
		elseif grow and grow.root.Visible then
			GuiService.SelectedObject = grow.face
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
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then
			GuiService.SelectedObject = nil
		end
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
			-- Only your own sign opens your Land panel.
			local plot = prompt:FindFirstAncestorOfClass("Model")
			if plot and plot:GetAttribute("OwnerId") ~= player.UserId then
				HUD.Toast("That's someone else's plot. Visit your own sign to expand.")
				return
			end
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
		local wasOn = false
		local lastHint = -math.huge
		while true do
			task.wait(0.25)
			local on = onMyPlot()
			if building and not on then
				setBuilding(false)
			end
			-- The BUILD button hides off your plot; say where it went, once a minute.
			if wasOn and not on and os.clock() - lastHint > 60 then
				lastHint = os.clock()
				HUD.Toast("Walk back to your plot to build.")
			end
			wasOn = on
			PlotUI.Refresh()
		end
	end)
end

return PlotUI
