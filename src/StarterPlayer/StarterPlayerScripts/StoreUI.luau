--!strict
-- StoreUI: the Robux store (Lane P redesign on UITheme's tokens).
--   * A STORE button under the cash opens a dark panel (PanelAlt at 15%
--     see-through, 12 px corners, a 2 px brass edge) with Passes and
--     Products tabs and a grid of cream cards: two columns on a phone,
--     three on a computer or TV, so at least two cards show on a 667x375
--     phone. The button follows Roblox's live sale state.
--   * Each card: art disc, name, the Creator Hub description, a live line
--     (what a cash pack adds now, 2x Wood hours left, Instant Deliveries
--     held) and one pill. The pill is the card state (Store/StoreSale):
--     Buy shows this player's own Robux price from StorePrices ("R$" until
--     Roblox answers; never a number written in the game), Owned is green,
--     Wallet full is muted, and Coming soon is a weathered strip with no
--     price. An owned pass always shows, on sale or not.
--   * The town bulletin board's prompt (StorePrompt) opens the same panel,
--     and its price pills (tag StorePricePill) get this player's prices.
--   * Gamepad: opening selects the first Buy pill (or the Passes tab),
--     every button carries UITheme's ring, B closes. ButtonR2 is never bound.
--   * "Sell here" stays while you have Instant Deliveries and wood on the truck.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local StageOf = require(ReplicatedStorage.Shared.StageOf)
local StoreBoard = require(ReplicatedStorage.Shared.StoreBoard)
local StoreCopy = require(ReplicatedStorage.Shared.Store.StoreCopy)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local StoreSale = require(ReplicatedStorage.Shared.Store.StoreSale)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local HudNav = require(script.Parent.HudNav)
local MenuPad = require(script.Parent.MenuPad)
local ShopUI = require(script.Parent.ShopUI)
local StorePrices = require(script.Parent.StorePrices)
local UITheme = require(script.Parent.UITheme)

local StoreUI = {}

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
-- The store's display face (GAD store spec: titles in FredokaOne). UITheme
-- has no token for it yet; Cross-lane request to U for UITheme.Fonts.Display.
local DISPLAY = Enum.Font.FredokaOne

-- Shape (design px, before the screen's UIScale).
StoreUI.Margin = 12 -- the panel's gap to the safe area's edge
StoreUI.Pad = 12 -- inside the panel
StoreUI.Gap = 8 -- between cards and between tap targets
StoreUI.HeadH = 52
StoreUI.TabsH = UITheme.Size.Tap + 8
StoreUI.CardH = 148
StoreUI.MaxW = 900
StoreUI.MaxH = 620
StoreUI.Corner = 12
StoreUI.PanelSeeThrough = 0.15
StoreUI.PillW = 112
StoreUI.ArtPx = 56

local deliveryButton: UITheme.Button? = nil
local storeButton: UITheme.Button? = nil
local tab: "Passes" | "Products" = "Passes"
local panel: Frame? = nil
local list: ScrollingFrame? = nil
local grid: UIGridLayout? = nil
local passTab: UITheme.Button? = nil
local productTab: UITheme.Button? = nil
local storeOpen = false
local focus: GuiObject? = nil

-- Price text on the pills: 14 px in hand, 18 px on a TV.
function StoreUI.PriceTextPx(tenFoot: boolean): number
	return if tenFoot then 18 else 14
end

export type Layout = {
	panel: Vector2, -- design px
	columns: number,
	card: Vector2,
	cardsArea: Vector2,
	visibleCards: number, -- whole cards showing without a scroll
}

-- The panel for a safe area of `viewport` real px at UIScale `scale`.
-- Pure, so a spec can check a 667x375 phone and a 1920x1080 screen.
function StoreUI.Layout(viewport: Vector2, scale: number): Layout
	local s = if scale > 0 then scale else 1
	local dw, dh = viewport.X / s, viewport.Y / s
	local w = math.min(dw - StoreUI.Margin * 2, StoreUI.MaxW)
	local h = math.min(dh - StoreUI.Margin * 2, StoreUI.MaxH)
	local columns = if w >= 820 then 3 else 2
	local areaW = w - StoreUI.Pad * 2 - 8 -- the scroll bar
	local areaH = h - StoreUI.Pad * 2 - StoreUI.HeadH - StoreUI.TabsH
	local cardW = math.floor((areaW - (columns - 1) * StoreUI.Gap) / columns)
	local rows = math.max(1, math.floor((areaH + StoreUI.Gap) / (StoreUI.CardH + StoreUI.Gap)))
	return {
		panel = Vector2.new(w, h),
		columns = columns,
		card = Vector2.new(cardW, StoreUI.CardH),
		cardsArea = Vector2.new(areaW, areaH),
		visibleCards = rows * columns,
	}
end

local function tenFoot(): boolean
	local ok, ten = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and ten == true
end

function StoreUI._open(button: GuiObject?)
	storeOpen = true
	focus = button
	MenuPad.Open(button, panel) -- the stick stays in the store until it closes
end

function StoreUI._close()
	storeOpen = false
	local frame = panel
	if frame then
		frame.Visible = false
	end
	MenuPad.Close(frame or focus)
	focus = nil
	HUD.SetModal(nil)
end

function StoreUI.ApplyKey(key: Enum.KeyCode): string?
	if not storeOpen or not MenuPad.Closes(key) then
		return nil
	end
	StoreUI._close()
	return "close"
end

local function hoursLeft(untilTime: number): number
	return math.max(0, math.ceil((untilTime - os.time()) / 3600))
end

local function myBedCount(): number
	if CoreLoop.V2() then
		local volume = player:GetAttribute("BedVolume")
		return if type(volume) == "number" and volume > 0 then volume else 0
	end
	local mirrored = player:GetAttribute("BedCount")
	if type(mirrored) == "number" then
		return mirrored
	end
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:GetAttribute("OwnerId") == player.UserId then
			return (inst:GetAttribute("BedCount") :: number?) or 0
		end
	end
	return 0
end

local function refreshDelivery()
	local b = deliveryButton
	if not b then
		return
	end
	local n = (player:GetAttribute("InstantDeliveries") :: number?) or 0
	b.root.Visible = n > 0 and myBedCount() > 0
	b:SetText(string.format(StoreCopy.SellHere, n))
end

local function setModal(open: boolean)
	local frame = panel
	if not open or not frame then
		HUD.SetModal(nil)
		return
	end
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	local rect: HudLayout.Rect = {
		left = pos.X,
		top = pos.Y,
		right = pos.X + size.X,
		bottom = pos.Y + size.Y,
	}
	HUD.SetModal(rect)
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- The stage the client shows a pack's amount for: the server publishes it
-- as "StoreStage" (MonetizationService, from the save's StageOf) on join
-- and on each Buy press; until then, the axe rung. The real amount is
-- worked out again on the server at receipt time.
local function myStage(): number
	local published = player:GetAttribute("StoreStage")
	if type(published) == "number" then
		return math.clamp(math.floor(published), 1, StageOf.Count)
	end
	local tier = player:GetAttribute("BestAxeTier")
	return StageOf.FromProgress({ bestAxeTier = if type(tier) == "number" then tier else 1 })
end

-- What one card shows: its state and the live line.
export type CardFacts = { state: StoreSale.CardState, extra: string? }

function StoreUI.CardFacts(kind: string, item: StoreData.Pass | StoreData.Product): CardFacts
	local owned = kind == "Pass" and player:GetAttribute("Pass_" .. item.key) == true
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local extra: string? = nil
	local packCash: number? = nil
	if kind == "Product" then
		local product = item :: StoreData.Product
		if product.cash then
			packCash = StoreData.PackCashAt(product, myStage())
			extra = string.format(StoreCopy.PackNow, Util.formatCash(packCash :: number))
		elseif product.boostHours then
			local left = hoursLeft((player:GetAttribute("DoubleWoodUntil") :: number?) or 0)
			if left > 0 then
				extra = string.format(StoreCopy.HoursLeft, left)
			end
		elseif product.key == "InstantDelivery" then
			local n = (player:GetAttribute("InstantDeliveries") :: number?) or 0
			if n > 0 then
				extra = string.format(StoreCopy.YouHave, n)
			end
		end
	end
	local state: StoreSale.CardState = StoreSale.CardState(item, {
		owned = owned,
		robloxForSale = StorePrices.ForSale(kind, item.key),
		cash = cash,
		cap = GameConfig.CashCap,
		packCash = packCash,
	})
	return { state = state, extra = extra }
end

local function art(parent: Instance, kind: string, item: StoreData.Pass | StoreData.Product)
	local disc = Instance.new("ImageLabel")
	disc.Name = "Art"
	disc.Size = UDim2.fromOffset(StoreUI.ArtPx, StoreUI.ArtPx)
	disc.Position = UDim2.fromOffset(10, 10)
	disc.BorderSizePixel = 0
	-- Passes sit on a pine-green disc, products on a red one (GAD icon rule).
	disc.BackgroundColor3 = if kind == "Pass" then C.Green else C.Danger
	disc.ScaleType = Enum.ScaleType.Fit
	UITheme.corner(disc, StoreUI.ArtPx // 2)
	UITheme.stroke(disc, C.AmberEdge, 2)
	if item.image > 0 then
		disc.Image = "rbxassetid://" .. tostring(item.image)
	else
		disc.Image = ""
		local glyph = if item.key == "DoubleCash" or item.key == "DoubleWood"
			then "2x"
			elseif item.key == "Cash1k" or item.key == "Cash10k" then "$"
			else string.sub(item.name, 1, 1)
		local mark = UITheme.label(disc, glyph, F.Title, 22, C.Cream)
		mark.Size = UDim2.fromScale(1, 1)
		mark.TextXAlignment = Enum.TextXAlignment.Center
	end
	disc.Parent = parent
end

-- One card. Returns its pill (the selectable button), or nil for a
-- Coming soon card.
local function card(
	parent: Instance,
	order: number,
	kind: string,
	item: StoreData.Pass | StoreData.Product,
	facts: CardFacts
): GuiObject?
	local row = Instance.new("Frame")
	row.Name = item.key
	row.LayoutOrder = order
	row.BackgroundColor3 = C.Cream
	row.BorderSizePixel = 0
	row.ClipsDescendants = true
	UITheme.corner(row, UITheme.Radius)
	UITheme.stroke(row, C.AmberEdge, UITheme.Stroke)
	art(row, kind, item)
	local textX = StoreUI.ArtPx + 20
	local title = UITheme.label(row, item.name, DISPLAY, 19, C.Ink)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(textX, 8)
	title.Size = UDim2.new(1, -textX - 8, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local body = UITheme.label(row, item.description, F.Body, 14, C.MutedFill)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(textX, 32)
	body.Size = UDim2.new(1, -textX - 8, 0, 54)
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	local footY = StoreUI.CardH - UITheme.Size.Tap - 10
	if facts.extra then
		local extra = UITheme.label(row, facts.extra, F.Title, 14, C.Ink)
		extra.Name = "Live"
		extra.Position = UDim2.fromOffset(10, footY + 12)
		extra.Size = UDim2.new(1, -StoreUI.PillW - 28, 0, 20)
		extra.TextXAlignment = Enum.TextXAlignment.Left
		extra.TextTruncate = Enum.TextTruncate.AtEnd
	end
	row.Parent = parent
	if facts.state == "Soon" then
		local strip = Instance.new("Frame")
		strip.Name = "ComingSoon"
		strip.BackgroundColor3 = C.MutedFill
		strip.BorderSizePixel = 0
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.fromScale(0, 1)
		strip.Size = UDim2.new(1, 0, 0, 34)
		strip.Parent = row
		local words = UITheme.label(strip, StoreCopy.Soon, F.Title, 15, C.Cream)
		words.Size = UDim2.fromScale(1, 1)
		words.TextXAlignment = Enum.TextXAlignment.Center
		return nil
	end
	local text = StoreCopy.Owned
	local style = "forged" -- the dark pill with gold text (GAD price pill)
	if facts.state == "Buy" then
		text = StorePrices.Text(kind, item.key)
	elseif facts.state == "WalletFull" then
		text = StoreCopy.WalletFull
		style = "cant"
	end
	local pill = UITheme.Button({
		name = "Pill",
		text = text,
		size = Vector2.new(StoreUI.PillW, UITheme.Size.Tap),
		style = style,
		textSize = StoreUI.PriceTextPx(tenFoot()),
	})
	if facts.state == "Owned" then
		pill.face.TextColor3 = C.Confirm -- SaleGreen on the dark pill
	end
	pill.root.AnchorPoint = Vector2.new(1, 0)
	pill.root.Position = UDim2.new(1, -10, 0, footY)
	pill.root.Parent = row
	pill.face.Activated:Connect(function()
		if facts.state == "Buy" then
			Net.Remote("BuyRobuxItem"):FireServer(kind, item.key)
		elseif facts.state == "WalletFull" then
			HUD.Toast(string.format(StoreCopy.WalletCap, Util.formatCash(GameConfig.CashCap)))
		end
	end)
	return pill.face
end

local function styleTabs()
	local passes, products = passTab, productTab
	if passes and products then
		passes:SetStyle(if tab == "Passes" then "primary" else "bark")
		products:SetStyle(if tab == "Products" then "primary" else "bark")
	end
end

local firstPill: GuiObject? = nil

local function redraw()
	local frame = list
	if not frame then
		return
	end
	styleTabs()
	clear(frame)
	firstPill = nil
	local shown = 0
	for _, entry in ipairs(StoreData.Ordered()) do
		if (tab == "Passes") == (entry.kind == "Pass") then
			local facts = StoreUI.CardFacts(entry.kind, entry.item)
			if facts.state ~= "Hidden" then
				shown += 1
				local pill = card(frame, shown, entry.kind, entry.item, facts)
				if pill and firstPill == nil then
					firstPill = pill
				end
			end
		end
	end
	if shown == 0 then
		local empty = UITheme.label(
			frame,
			if tab == "Passes" then StoreCopy.EmptyPasses else StoreCopy.EmptyProducts,
			F.Body,
			16,
			C.Cream
		)
		empty.Size = UDim2.new(1, 0, 0, 40)
	end
	-- Gamepad: the tabs lead down into the first pill.
	local passes, products = passTab, productTab
	if passes and products and firstPill then
		passes.face.NextSelectionDown = firstPill
		products.face.NextSelectionDown = firstPill
	end
end

-- The board's price pills: this player's price, or "R$" while unknown.
local function paintPill(label: Instance)
	if not label:IsA("TextLabel") then
		return
	end
	local kind, key = label:GetAttribute("RobuxKind"), label:GetAttribute("RobuxKey")
	if type(kind) == "string" and type(key) == "string" then
		if kind == "Pass" and player:GetAttribute("Pass_" .. key) == true then
			label.Text = StoreCopy.Owned
			label.TextColor3 = C.Confirm -- SaleGreen
		else
			label.Text = StorePrices.Text(kind, key)
			label.TextColor3 = StoreBoard.Look.CoinGold
		end
	end
end

local function paintBoard()
	for _, inst in ipairs(CollectionService:GetTagged("StorePricePill")) do
		paintPill(inst)
	end
end

-- The STORE button shows while anything is set up and Roblox hasn't said
-- every item is off sale (or a pass is owned).
local function refreshStoreButton()
	local b = storeButton
	if not b then
		return
	end
	local visible = false
	for _, entry in ipairs(StoreData.Ordered()) do
		local listed = StoreData.IsForSale(entry.item.id) and StorePrices.ForSale(entry.kind, entry.key) ~= false
		local owned = entry.kind == "Pass" and player:GetAttribute("Pass_" .. entry.key) == true
		if listed or owned then
			visible = true
		end
	end
	b.root.Visible = visible
end

local function applyLayout()
	local frame, rows, g = panel, list, grid
	if not frame or not rows or not g then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
	if gui and gui.AbsoluteSize.X > 0 then
		viewport = gui.AbsoluteSize
	end
	local layout = StoreUI.Layout(viewport, UITheme.Scale())
	frame.Size = UDim2.fromOffset(layout.panel.X, layout.panel.Y)
	g.CellSize = UDim2.fromOffset(layout.card.X, layout.card.Y)
end

local function openStore()
	local frame = panel
	if not frame then
		return
	end
	StorePrices.RefreshIfStale()
	applyLayout()
	frame.Visible = true
	redraw()
	StoreUI._open(firstPill or (if passTab then passTab.face else nil))
	task.defer(function()
		setModal(true)
	end)
end

local function closeStore()
	StoreUI._close()
end

local function tabButton(name: string, text: string, x: number): UITheme.Button
	local b = UITheme.Button({
		name = name,
		text = text,
		size = Vector2.new(140, UITheme.Size.Tap),
		style = "bark",
		textSize = 15,
	})
	b.root.Position = UDim2.fromOffset(x, 0)
	return b
end

function StoreUI.Start()
	StorePrices.Start()
	local gui = UITheme.Screen("StoreUI", UITheme.Layers.Store)
	local spec = UITheme.Sized("Store")
	local store = UITheme.Button({
		name = "Store",
		text = StoreCopy.HudButton,
		size = spec.size or Vector2.new(90, 30),
		style = "buy",
		textSize = spec.text,
	})
	storeButton = store
	store.root.LayoutOrder = 5 -- under the cash, between the clock and Daily Goals
	store.root.Visible = StoreData.AnyForSale()
	store.root.Parent = HUD.UnderCash() or HUD.BesideCash()
	store.face.Activated:Connect(openStore)
	HudNav.Add(store.face, { id = "store", label = StoreCopy.HudButton, press = openStore })
	if spec.hit then
		UITheme.HitPad(store.root, spec.hit).Activated:Connect(openStore)
	end
	ShopUI.SetStoreOpener(openStore)

	local shell = Instance.new("Frame")
	shell.Name = "StorePanel"
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromOffset(640, 360)
	shell.BackgroundColor3 = C.PanelAlt
	shell.BackgroundTransparency = StoreUI.PanelSeeThrough
	shell.BorderSizePixel = 0
	shell.Visible = false
	UITheme.corner(shell, StoreUI.Corner)
	UITheme.stroke(shell, C.AmberEdge, UITheme.Stroke)
	UITheme.padding(shell, StoreUI.Pad, StoreUI.Pad, StoreUI.Pad, StoreUI.Pad)
	panel = shell

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, StoreUI.HeadH)
	head.Parent = shell
	local heading = UITheme.label(head, StoreCopy.Title, DISPLAY, 26, C.Amber)
	heading.Name = "Title"
	heading.Position = UDim2.fromOffset(4, 0)
	heading.Size = UDim2.new(1, -60, 0, 28)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local sub = UITheme.label(head, StoreCopy.Subtitle, F.Body, 14, C.Cream)
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromOffset(4, 28)
	sub.Size = UDim2.new(1, -60, 0, 20)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local close = UITheme.Button({
		name = "Close",
		text = StoreCopy.Close,
		size = Vector2.new(UITheme.Size.Tap, UITheme.Size.Tap),
		style = "cant",
		textSize = 18,
	})
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.fromScale(1, 0)
	close.root.Parent = head
	close.face.Activated:Connect(closeStore)

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(0, StoreUI.HeadH)
	tabs.Size = UDim2.new(1, 0, 0, StoreUI.TabsH)
	tabs.Parent = shell
	local passesBtn = tabButton("Passes", StoreCopy.TabPasses, 0)
	local productsBtn = tabButton("Products", StoreCopy.TabProducts, 140 + StoreUI.Gap)
	passesBtn.root.Parent = tabs
	productsBtn.root.Parent = tabs
	passTab = passesBtn
	productTab = productsBtn
	passesBtn.face.NextSelectionRight = productsBtn.face
	productsBtn.face.NextSelectionLeft = passesBtn.face
	productsBtn.face.NextSelectionRight = close.face
	close.face.NextSelectionDown = passesBtn.face
	passesBtn.face.Activated:Connect(function()
		tab = "Passes"
		redraw()
	end)
	productsBtn.face.Activated:Connect(function()
		tab = "Products"
		redraw()
	end)

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Cards"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(0, StoreUI.HeadH + StoreUI.TabsH)
	rows.Size = UDim2.new(1, 0, 1, -(StoreUI.HeadH + StoreUI.TabsH))
	rows.CanvasSize = UDim2.fromOffset(0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 6
	rows.ScrollBarImageColor3 = C.AmberEdge
	rows.Selectable = false
	rows.Parent = shell
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(StoreUI.Gap, StoreUI.Gap)
	layout.CellSize = UDim2.fromOffset(300, StoreUI.CardH)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows
	grid = layout
	list = rows
	shell.Parent = gui

	deliveryButton = HUD.SideButton({
		name = "InstantDelivery",
		text = "Sell here",
		style = "buy",
		order = 2,
		onPress = function()
			Net.Remote("UseInstantDelivery"):FireServer()
		end,
	})

	local function bindPrompt(inst: Instance)
		if inst:IsA("ProximityPrompt") and inst.Name == "StorePrompt" then
			inst.Triggered:Connect(function()
				openStore()
			end)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("StorePrompt")) do
		bindPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal("StorePrompt"):Connect(bindPrompt)
	CollectionService:GetInstanceAddedSignal("StorePricePill"):Connect(paintPill)

	local function onChange()
		refreshStoreButton()
		paintBoard()
		if panel and panel.Visible then
			redraw()
		end
	end
	StorePrices.OnChanged(onChange)
	UITheme.WatchLayout(applyLayout)
	applyLayout()
	redraw()
	paintBoard()
	for _, entry in ipairs(StoreData.Ordered()) do
		if entry.kind == "Pass" then
			player:GetAttributeChangedSignal("Pass_" .. entry.key):Connect(onChange)
		end
	end
	for _, attribute in ipairs({ "DoubleWoodUntil", "InstantDeliveries", "Cash", "StoreStage" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if panel and panel.Visible then
				redraw()
			end
			refreshDelivery()
		end)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			refreshDelivery()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		StoreUI.ApplyKey(input.KeyCode)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

return StoreUI
