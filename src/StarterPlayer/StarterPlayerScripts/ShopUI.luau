--!strict
-- ShopUI: the shop screen, for both shops.
--   * Tool Shed ("Browse axes"): the whole axe ladder. The next axe can be
--     bought, owned ones bought again (for a collection), later ones show
--     as locked, and the Starfall Axe as forged. Each row says the axe's
--     damage and the toughest woods it fells.
--   * Dealership ("Browse trucks"): every truck with its bed size and top
--     speed. Buy one, or switch to one you own; the new truck waits in your
--     parking spot.
--   * Hearth & Home ("Browse gear"): gear for the far biomes, bought once
--     and worn for good. Gear for a biome that isn't built yet says Soon.
-- Buying only sends an intent (BuyItem / EquipItem); the server checks
-- everything and answers with a toast. The player attributes it changes
-- (Cash, OwnedAxes, BestAxeTier, OwnedTrucks, EquippedTruck, OwnedGear) redraw the
-- list. Walking away closes the screen, and so do the X and B on a gamepad.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)

type AxeDef = ItemCatalog.AxeDef
type TruckDef = ItemCatalog.TruckDef
type GearDef = ItemCatalog.GearDef

local ShopUI = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local PAPER_DARK = Color3.fromRGB(226, 207, 170)
local BARK = Color3.fromRGB(88, 58, 34)
local GREEN = Color3.fromRGB(76, 140, 64)
local BLUE = Color3.fromRGB(47, 109, 181)
local MUTED = Color3.fromRGB(160, 145, 120)
local SKY = Color3.fromRGB(110, 120, 190)

-- One row's look and what its button does right now.
type RowView = {
	name: string,
	detail: string,
	color: Color3,
	glow: boolean,
	dim: boolean,
	button: string,
	buttonColor: Color3,
	onClick: () -> (),
}

-- A shop: which building, the prompt, the header, and its rows.
type Shop = {
	building: string, -- model in TimberlineMap
	promptText: string,
	title: string,
	subtitle: string,
	ids: () -> { string },
	view: (id: string) -> RowView,
}

type Row = {
	id: string,
	frame: Frame,
	name: TextLabel,
	detail: TextLabel,
	button: TextButton,
	swatch: Frame,
	stroke: UIStroke,
}

local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local list: ScrollingFrame? = nil
local rows: { Row } = {}
local prompts: { [Shop]: ProximityPrompt } = {}
local points: { [Shop]: Attachment } = {}
local openShop: Shop? = nil

local function needMore(price: number, cash: number, name: string)
	HUD.Toast(string.format("You need %s more for the %s.", Util.formatCash(price - cash), name))
end

local function priceButton(price: number, cash: number): (string, Color3)
	if cash >= price then
		return "Buy " .. Util.formatCash(price), GREEN
	end
	return Util.formatCash(price), MUTED
end

---------------------------------------------------------------------------
-- Tool Shed: axes
---------------------------------------------------------------------------

local function axeState(): (number, number, { [string]: number }, number)
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local bestTier = (player:GetAttribute("BestAxeTier") :: number?) or 1
	local counts, total = ShopLogic.DecodeOwned((player:GetAttribute("OwnedAxes") :: string?) or "")
	return cash, bestTier, counts, total
end

local AXES: Shop = {
	building = "ToolShed",
	promptText = "Browse axes",
	title = "TOOL SHED",
	subtitle = "Axes are sold in order. Every axe you buy is yours to keep: switch in your hotbar.",
	ids = function()
		local ids = {}
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(ids, axe.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local axe = ItemCatalog.GetAxe(id) :: AxeDef
		local cash, bestTier, counts, total = axeState()
		local owned = counts[axe.id] or 0
		local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, bestTier, owned, total)
		local button, buttonColor
		if ShopLogic.CanPurchase(status) then
			button, buttonColor = priceButton(axe.priceCash, cash)
		elseif status == "forged" then
			button, buttonColor = "Forged", SKY
		else
			button = if status == "starter" then "Starter" elseif status == "full" then "Full" else "Locked"
			buttonColor = MUTED
		end
		return {
			name = if owned > 0 then string.format("%s  ·  you own %d", axe.displayName, owned) else axe.displayName,
			detail = ShopLogic.DamageText(axe) .. "\n" .. ShopLogic.FellSummary(axe),
			color = Color3.fromHex(axe.look.headColor),
			glow = axe.look.glow == true,
			dim = status == "locked",
			button = button,
			buttonColor = buttonColor,
			onClick = function()
				if not ShopLogic.CanPurchase(status) then
					HUD.Toast(ShopLogic.WhyNot(status, axe, bestTier))
				elseif cash < axe.priceCash then
					needMore(axe.priceCash, cash, axe.displayName)
				else
					Net.Remote("BuyItem"):FireServer("Axe", axe.id) -- the server re-checks all of it
				end
			end,
		}
	end,
}

---------------------------------------------------------------------------
-- Dealership: trucks
---------------------------------------------------------------------------

local TRUCKS: Shop = {
	building = "Dealership",
	promptText = "Browse trucks",
	title = "DEALERSHIP",
	subtitle = "Bigger beds haul more but drive slower. A truck you buy waits in your parking spot.",
	ids = function()
		local ids = {}
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			table.insert(ids, truck.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local truck = ItemCatalog.GetTruck(id) :: TruckDef
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedTrucks") :: string?) or "")
		local equipped = (player:GetAttribute("EquippedTruck") :: string?) or "Rustbucket"
		local status: ShopLogic.TruckStatus = ShopLogic.TruckStatusOf(truck, owned, equipped)
		local button, buttonColor
		if status == "buy" then
			button, buttonColor = priceButton(truck.priceCash, cash)
		elseif status == "use" then
			button, buttonColor = "Use", BLUE
		else
			button, buttonColor = "In use", MUTED
		end
		return {
			name = truck.displayName,
			detail = ShopLogic.TruckDetail(truck),
			color = Color3.fromHex(truck.look.color),
			glow = false,
			dim = false,
			button = button,
			buttonColor = buttonColor,
			onClick = function()
				if status == "inUse" then
					HUD.Toast(string.format("You're already using the %s.", truck.displayName))
				elseif status == "use" then
					Net.Remote("EquipItem"):FireServer("Truck", truck.id)
				elseif cash < truck.priceCash then
					needMore(truck.priceCash, cash, truck.displayName)
				else
					Net.Remote("BuyItem"):FireServer("Truck", truck.id)
				end
			end,
		}
	end,
}

---------------------------------------------------------------------------
-- Hearth & Home: gear
---------------------------------------------------------------------------

local GEAR: Shop = {
	building = "HearthAndHome",
	promptText = "Browse gear",
	title = "HEARTH & HOME",
	subtitle = "Gear for the far biomes. Buy it once and you wear it for good.",
	ids = function()
		local ids = {}
		for _, gear in ipairs(ItemCatalog.GearList()) do
			table.insert(ids, gear.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local gear = ItemCatalog.GetGear(id) :: GearDef
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")
		local status: ShopLogic.GearStatus = ShopLogic.GearStatusOf(gear, owned)
		local button, buttonColor
		if status == "buy" then
			button, buttonColor = priceButton(gear.priceCash, cash)
		elseif status == "owned" then
			button, buttonColor = "Owned", MUTED
		else
			button, buttonColor = "Soon", SKY
		end
		return {
			name = gear.displayName,
			detail = ShopLogic.GearDetail(gear),
			color = Color3.fromHex(gear.color),
			glow = false,
			dim = status == "soon",
			button = button,
			buttonColor = buttonColor,
			onClick = function()
				if status == "owned" then
					HUD.Toast(string.format("You already have the %s.", gear.displayName))
				elseif status == "soon" then
					HUD.Toast(string.format("The %s goes on sale when its biome opens.", gear.displayName))
				elseif cash < gear.priceCash then
					needMore(gear.priceCash, cash, gear.displayName)
				else
					Net.Remote("BuyItem"):FireServer("Gear", gear.id)
				end
			end,
		}
	end,
}

local SHOPS: { Shop } = { AXES, TRUCKS, GEAR }

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: GuiObject, text: string, size: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = INK
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function refresh()
	local shop = openShop
	if not shop then
		return
	end
	for _, row in ipairs(rows) do
		local view = shop.view(row.id)
		row.name.Text = view.name
		row.detail.Text = view.detail
		row.swatch.BackgroundColor3 = view.color
		row.swatch.BackgroundTransparency = if view.dim then 0.6 else 0
		row.stroke.Enabled = view.glow
		row.button.Text = view.button
		row.button.BackgroundColor3 = view.buttonColor
	end
end

local function buildRow(parent: Instance, shop: Shop, id: string, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 74)
	frame.BackgroundColor3 = PAPER_DARK
	frame.BorderSizePixel = 0
	corner(frame, 8)
	frame.Parent = parent

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 10, 0.5, 0)
	swatch.Size = UDim2.fromOffset(40, 40)
	swatch.BorderSizePixel = 0
	corner(swatch, 20)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 240, 180)
	stroke.Thickness = 2
	stroke.Enabled = false
	stroke.Parent = swatch
	swatch.Parent = frame

	local name = label(frame, "", 17, Enum.Font.GothamBold)
	name.Position = UDim2.fromOffset(60, 8)
	name.Size = UDim2.new(1, -172, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local detail = label(frame, "", 14, Enum.Font.Gotham)
	detail.Position = UDim2.fromOffset(60, 30)
	detail.Size = UDim2.new(1, -172, 0, 38)
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextWrapped = true
	detail.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 14
	fit.MinTextSize = 9
	fit.Parent = detail

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(100, 38)
	button.BackgroundColor3 = MUTED
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = CREAM
	button.Text = ""
	corner(button, 8)
	button.Parent = frame
	button.Activated:Connect(function()
		-- Worked out fresh on every click, from the latest cash and ownership.
		shop.view(id).onClick()
	end)

	return { id = id, frame = frame, name = name, detail = detail, button = button, swatch = swatch, stroke = stroke }
end

local function onCloseAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		ShopUI.Close()
	end
	return Enum.ContextActionResult.Sink
end

local function open(shop: Shop)
	local p, scroll = panel, list
	if not p or not scroll then
		return
	end
	ShopUI.Close()
	openShop = shop
	for _, row in ipairs(rows) do
		row.frame:Destroy()
	end
	table.clear(rows)
	for i, id in ipairs(shop.ids()) do
		table.insert(rows, buildRow(scroll, shop, id, i))
	end
	scroll.CanvasPosition = Vector2.zero
	if titleLabel then
		titleLabel.Text = shop.title
	end
	if subtitleLabel then
		subtitleLabel.Text = shop.subtitle
	end
	p.Visible = true
	local prompt = prompts[shop]
	if prompt then
		prompt.Enabled = false
	end
	refresh()
	ContextActionService:BindAction("CloseShop", onCloseAction, false, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled and rows[1] then
		GuiService.SelectedObject = rows[1].button
	end
end

function ShopUI.Close()
	local shop = openShop
	if not shop then
		return
	end
	openShop = nil
	local p = panel
	if p then
		p.Visible = false
	end
	local prompt = prompts[shop]
	if prompt then
		prompt.Enabled = true
	end
	ContextActionService:UnbindAction("CloseShop")
	if GuiService.SelectedObject and p and GuiService.SelectedObject:IsDescendantOf(p) then
		GuiService.SelectedObject = nil
	end
end

local function buildPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- under the HUD (10), so toasts show on top of the panel

	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.52)
	p.Size = UDim2.fromScale(0.92, 0.72)
	p.BackgroundColor3 = BARK
	p.BorderSizePixel = 0
	p.Visible = false
	corner(p, 12)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(560, 540)
	maxSize.Parent = p
	p.Parent = gui

	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.Position = UDim2.fromOffset(5, 5)
	paper.Size = UDim2.new(1, -10, 1, -10)
	paper.BackgroundColor3 = PAPER
	paper.BorderSizePixel = 0
	corner(paper, 9)
	paper.Parent = p

	local title = label(paper, "", 26, Enum.Font.Fantasy)
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -70, 0, 30)
	titleLabel = title

	local subtitle = label(paper, "", 13, Enum.Font.Gotham)
	subtitle.Position = UDim2.fromOffset(14, 38)
	subtitle.Size = UDim2.new(1, -28, 0, 30)
	subtitle.TextWrapped = true
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitleLabel = subtitle

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = BARK
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = CREAM
	close.Text = "X"
	corner(close, 18)
	close.Parent = paper
	close.Activated:Connect(ShopUI.Close)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.Position = UDim2.fromOffset(10, 74)
	scroll.Size = UDim2.new(1, -20, 1, -84)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = BARK
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = paper
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8) -- room for the scroll bar
	pad.Parent = scroll
	list = scroll

	panel = p
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function setupPrompt(shop: Shop)
	local map = workspace:WaitForChild("TimberlineMap")
	local building = map:WaitForChild(shop.building) -- a Persistent model: always streamed in
	local counter = building:WaitForChild("Counter")
	local point = counter:WaitForChild("ShopPoint") :: Attachment
	points[shop] = point

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = shop.promptText
	pp.ObjectText = shop.title
	pp.MaxActivationDistance = GameConfig.ShopPromptRange
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.Parent = point
	pp.Triggered:Connect(function()
		open(shop)
	end)
	prompts[shop] = pp
end

function ShopUI.Start()
	buildPanel()
	for _, attribute in ipairs({ "Cash", "BestAxeTier", "OwnedAxes", "OwnedTrucks", "EquippedTruck", "OwnedGear" }) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	for _, shop in ipairs(SHOPS) do
		task.spawn(setupPrompt, shop)
	end
	-- Walked away (or respawned somewhere else)? Close the screen.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local shop = openShop
		if not shop or elapsed < 0.25 then
			return
		end
		elapsed = 0
		local point = points[shop]
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not point or not hrp or (hrp.Position - point.WorldPosition).Magnitude > GameConfig.ShopRange then
			ShopUI.Close()
		end
	end)
end

return ShopUI
