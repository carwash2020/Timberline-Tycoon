--!strict
-- StoreUI: the Robux store (Lane P redesign on UITheme's tokens).
--   * A STORE button under the cash opens a dark panel (PanelAlt at 15%
--     see-through, 12 px corners, a 2 px brass edge) with Passes and
--     Products tabs and a grid of cream cards: two columns on a phone,
--     three on a computer or TV, so at least two cards show on a 667x375
--     phone. The button follows Roblox's live sale state.
--   * Each card is one vertical list (6 px apart): art disc, name, the Creator
--     Hub description (two lines at most), the "+$ now" amount on its own
--     20 px row, then a footer at least 44 px tall: status text on its left
--     and the price pill on its right (anchored (1, 0.5), 8 px from the card's
--     edge). Nothing is placed on top of anything else (CardLayout has the
--     rectangles). The pill is the card state (Store/StoreSale): Buy shows
--     this player's own Robux price from StorePrices ("R$" while it retries,
--     "Price unavailable" and Buy off once the last retry failed; never a
--     number written in the game), Owned is green, Wallet full is muted, and
--     Coming soon is the footer in a weathered fill with no price. An owned
--     pass always shows, on sale or not.
--   * The town bulletin board's prompt (StorePrompt) opens the same panel,
--     and its price pills (tag StorePricePill) get this player's prices.
--   * Gamepad: opening selects the first Buy pill (or the Passes tab),
--     every button carries UITheme's ring, B closes. the right trigger is never bound.
--   * "Sell here" stays while you have Instant Deliveries and wood on the truck.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PolicyLogic = require(ReplicatedStorage.Shared.PolicyLogic)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local StageOf = require(ReplicatedStorage.Shared.StageOf)
local StoreBoard = require(ReplicatedStorage.Shared.StoreBoard)
local StoreCopy = require(ReplicatedStorage.Shared.Store.StoreCopy)
local StoreArt = require(ReplicatedStorage.Shared.StoreArt)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local StoreSale = require(ReplicatedStorage.Shared.Store.StoreSale)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local HudNav = require(script.Parent.HudNav)
local MenuPad = require(script.Parent.MenuPad)
local ShopUI = require(script.Parent.ShopUI)
local StorePrices = require(script.Parent.StorePrices)
local UIArt = require(script.Parent.UIArt)
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
StoreUI.CardPad = 8 -- inside a card; the price pill sits this far from its right edge
StoreUI.RowGap = 6 -- between a card's rows
StoreUI.AmountH = 20 -- the "+$ now" row
StoreUI.DescLines = 2
StoreUI.FooterMin = SettingsLogic.TouchMin -- the footer, and the price pill, are at least this tall
StoreUI.MaxW = 900
StoreUI.MaxH = 620
StoreUI.Corner = 12
StoreUI.PanelSeeThrough = 0.15
StoreUI.PillW = 112
StoreUI.PillWFailed = 150 -- room for "Price unavailable" at the text floor
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

-- Design px for text that must read at least `floor` px on screen once the
-- UI scale multiplier (Small 0.85, Normal 1, Large 1.15) is applied.
local function textPx(size: number, floor: number, mult: number): number
	return math.max(size, math.ceil(floor / mult - 1e-9))
end

-- Price text on the pills: 14 px in hand, 18 px on a TV (never under the
-- body floor on screen: `mult` is the UI scale multiplier, 1 when omitted).
function StoreUI.PriceTextPx(tenFoot: boolean, mult: number?): number
	return textPx(if tenFoot then 18 else 14, SettingsLogic.TextFloorBody, mult or 1)
end

-- The UI scale multiplier this player chose (Settings), 1 when unknown.
local function userMult(): number
	local ok, name = pcall(function()
		return player:GetAttribute("SettingUIScale")
	end)
	return SettingsLogic.ScaleMultiplier(if ok and type(name) == "string" then name else SettingsLogic.Defaults.uiScale)
end

export type Rect = { x: number, y: number, w: number, h: number }
export type CardRects = {
	icon: Rect,
	title: Rect,
	desc: Rect,
	amount: Rect,
	footer: Rect,
	status: Rect,
	button: Rect,
	height: number,
	titlePx: number,
	bodyPx: number,
}

-- Every rectangle of one card (design px, inside the card), from the same
-- numbers the card is built with: a vertical list of icon, title, description
-- (two lines), amount (20 px) and footer, RowGap apart. The price button
-- sits on the footer's right (anchor (1, 0.5)) CardPad from the card's edge;
-- the status text takes the footer's left up to the button. Pure, so a spec
-- can check that the button never meets the amount or the description.
function StoreUI.CardLayout(cardW: number, mult: number, buttonW: number?): CardRects
	local pad, gap = StoreUI.CardPad, StoreUI.RowGap
	local inner = cardW - pad * 2
	local titlePx = textPx(20, SettingsLogic.TextFloorTitle, mult)
	local bodyPx = textPx(14, SettingsLogic.TextFloorBody, mult)
	local lineH = math.ceil(bodyPx * 1.2)
	local y = pad
	local function row(h: number): Rect
		local r = { x = pad, y = y, w = inner, h = h }
		y += h + gap
		return r
	end
	local icon = row(StoreUI.ArtPx)
	local title = row(titlePx + 2)
	local desc = row(lineH * StoreUI.DescLines)
	local amount = row(StoreUI.AmountH)
	local drop = UITheme.ButtonDrop
	local footer = row(StoreUI.FooterMin + drop + 1)
	local bw = buttonW or StoreUI.PillW
	local bh = StoreUI.FooterMin + drop -- the face is FooterMin tall, its drop edge sits under it
	local button = { x = footer.x + footer.w - bw, y = footer.y + (footer.h - bh) / 2, w = bw, h = bh }
	local status = {
		x = footer.x,
		y = footer.y + (footer.h - StoreUI.AmountH) / 2,
		w = math.max(0, footer.w - bw - StoreUI.RowGap),
		h = StoreUI.AmountH,
	}
	return {
		icon = icon,
		title = title,
		desc = desc,
		amount = amount,
		footer = footer,
		status = status,
		button = button,
		height = footer.y + footer.h + pad,
		titlePx = titlePx,
		bodyPx = bodyPx,
	}
end

-- The height of one card at a UI scale multiplier.
function StoreUI.CardHeight(mult: number?): number
	return StoreUI.CardLayout(300, mult or 1).height
end

-- Whether a pill press may ask for a purchase: a Buy card whose price did
-- not fail to load. (A failed price is "Price unavailable" and sends nothing.)
function StoreUI.CanBuy(state: string, priceFailed: boolean): boolean
	return state == "Buy" and not priceFailed
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
function StoreUI.Layout(viewport: Vector2, scale: number, mult: number?): Layout
	local s = if scale > 0 then scale else 1
	local dw, dh = viewport.X / s, viewport.Y / s
	local w = math.min(dw - StoreUI.Margin * 2, StoreUI.MaxW)
	local h = math.min(dh - StoreUI.Margin * 2, StoreUI.MaxH)
	local columns = if w >= 820 then 3 else 2
	local areaW = w - StoreUI.Pad * 2 - 8 -- the scroll bar
	local areaH = h - StoreUI.Pad * 2 - StoreUI.HeadH - StoreUI.TabsH
	local cardW = math.floor((areaW - (columns - 1) * StoreUI.Gap) / columns)
	local cardH = StoreUI.CardHeight(mult)
	local rows = math.max(1, math.floor((areaH + StoreUI.Gap) / (cardH + StoreUI.Gap)))
	return {
		panel = Vector2.new(w, h),
		columns = columns,
		card = Vector2.new(cardW, cardH),
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
-- "Pending" is a real id whose sale answer has not come back (or never will):
-- the pill reads "R$", then "Price unavailable", and nothing can be bought.
export type CardState = StoreSale.CardState | "Pending"
export type CardFacts = { state: CardState, extra: string? }

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
	-- Region rules: a restricted item is not offered at all (a pass already
	-- owned still shows, as owned). The server refuses the purchase too.
	local policy = PolicyLogic.FromAttributes(function(name)
		return player:GetAttribute(name)
	end)
	if not owned and not PolicyLogic.Allows(policy, item :: any) then
		return { state = "Hidden", extra = nil }
	end
	local answer = StorePrices.ForSale(kind, item.key)
	local state: CardState = StoreSale.CardState(item, {
		owned = owned,
		robloxForSale = answer,
		cash = cash,
		cap = GameConfig.CashCap,
		packCash = packCash,
	})
	if state == "Soon" and answer == nil and item.id > 0 and item.offSale ~= "hidden" then
		state = "Pending"
	end
	return { state = state, extra = extra }
end

local function art(parent: Instance, kind: string, item: StoreData.Pass | StoreData.Product)
	local disc = Instance.new("ImageLabel")
	disc.Name = "Art"
	disc.Size = UDim2.fromOffset(StoreUI.ArtPx, StoreUI.ArtPx)
	disc.BorderSizePixel = 0
	-- Passes sit on a pine-green disc, products on a red one (GAD icon rule).
	disc.BackgroundColor3 = if kind == "Pass" then C.Green else C.Danger
	disc.ScaleType = Enum.ScaleType.Fit
	UITheme.corner(disc, StoreUI.ArtPx // 2)
	UITheme.stroke(disc, C.AmberEdge, 2)
	-- The letter or mark is always there; a real image hides it, and an image
	-- that fails to load (a thumbnail that is not ready, moderation, no
	-- network) shows it again, so the disc is never an empty circle.
	local glyph = if item.key == "DoubleCash" or item.key == "DoubleWood"
		then "2x"
		elseif item.key == "Cash1k" or item.key == "Cash10k" then "$"
		else string.sub(item.name, 1, 1)
	local mark = UITheme.label(disc, glyph, F.Title, 22, C.Cream)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	local uri = StoreArt.ImageFor(item.image, StoreArt.Small)
	if uri ~= "" then
		disc.Image = uri
		mark.Visible = false
		UIArt.Listen(uri, function(result: UIArt.LoadStatus)
			if result == "Failure" then
				mark.Visible = true
			end
		end)
	else
		disc.Image = ""
	end
	disc.Parent = parent
end

-- One row of a card's vertical list: a full-width frame of a fixed height.
local function listRow(parent: Instance, name: string, order: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.LayoutOrder = order
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0, height)
	f.Parent = parent
	return f
end

-- One card, a vertical UIListLayout (RowGap apart): art, title, description,
-- amount, footer (status text left, price pill right). Returns its pill (the
-- selectable button), or nil for a Coming soon card.
local function card(
	parent: Instance,
	order: number,
	kind: string,
	item: StoreData.Pass | StoreData.Product,
	facts: CardFacts
): GuiObject?
	local mult = userMult()
	local r = StoreUI.CardLayout(300, mult)
	local row = Instance.new("Frame")
	row.Name = item.key
	row.LayoutOrder = order
	row.BackgroundColor3 = C.Cream
	row.BorderSizePixel = 0
	row.ClipsDescendants = true
	UITheme.corner(row, UITheme.Radius)
	UITheme.stroke(row, C.AmberEdge, UITheme.Stroke)
	UITheme.padding(row, StoreUI.CardPad, StoreUI.CardPad, StoreUI.CardPad, StoreUI.CardPad)
	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, StoreUI.RowGap)
	stack.Parent = row

	art(listRow(row, "ArtRow", 1, r.icon.h), kind, item)

	local title = UITheme.label(row, item.name, DISPLAY, r.titlePx, C.Ink)
	title.Name = "Title"
	title.LayoutOrder = 2
	title.Size = UDim2.new(1, 0, 0, r.title.h)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd

	-- The description: at most two lines, cut with an ellipsis. TextScaled with
	-- a constraint pinned to the body floor keeps it from shrinking under 14.
	local body = UITheme.label(row, item.description, F.Body, r.bodyPx, C.MutedFill)
	body.Name = "Body"
	body.LayoutOrder = 3
	body.Size = UDim2.new(1, 0, 0, r.desc.h)
	body.TextWrapped = true
	body.TextScaled = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	local bodyFit = Instance.new("UITextSizeConstraint")
	bodyFit.MinTextSize = r.bodyPx
	bodyFit.MaxTextSize = r.bodyPx
	bodyFit.Parent = body

	-- The "+$ now" amount (cash packs) has its own row; every card keeps the
	-- row so the footers line up across the grid.
	local isPack = kind == "Product" and (item :: StoreData.Product).cash ~= nil
	local amount = UITheme.label(row, if isPack and facts.extra then facts.extra else "", F.Title, r.bodyPx, C.Ink)
	amount.Name = "Live"
	amount.LayoutOrder = 4
	amount.Size = UDim2.new(1, 0, 0, StoreUI.AmountH)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.TextTruncate = Enum.TextTruncate.AtEnd

	local footer = listRow(row, "Footer", 5, r.footer.h)
	row.Parent = parent
	if facts.state == "Soon" then
		footer.BackgroundTransparency = 0
		footer.BackgroundColor3 = C.MutedFill
		UITheme.corner(footer, UITheme.Radius)
		local words = UITheme.label(footer, StoreCopy.Soon, F.Title, r.bodyPx, C.Cream)
		words.Name = "ComingSoon"
		words.Size = UDim2.fromScale(1, 1)
		words.TextXAlignment = Enum.TextXAlignment.Center
		return nil
	end
	local priceFailed = (facts.state == "Buy" or facts.state == "Pending") and StorePrices.Failed(kind, item.key)
	-- Status text on the footer's left (2x Wood hours left, Instant Deliveries held).
	local buttonW = if priceFailed then StoreUI.PillWFailed else StoreUI.PillW
	if facts.extra and not isPack then
		local status = UITheme.label(footer, facts.extra, F.Title, r.bodyPx, C.Ink)
		status.Name = "Status"
		status.AnchorPoint = Vector2.new(0, 0.5)
		status.Position = UDim2.fromScale(0, 0.5)
		status.Size = UDim2.new(1, -(buttonW + StoreUI.RowGap), 0, StoreUI.AmountH)
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local text = StoreCopy.Owned
	local style = "forged" -- the dark pill with gold text (GAD price pill)
	if facts.state == "Buy" or facts.state == "Pending" then
		text = StorePrices.Text(kind, item.key)
		if facts.state == "Pending" or priceFailed then
			style = "cant"
		end
	elseif facts.state == "WalletFull" then
		text = StoreCopy.WalletFull
		style = "cant"
	end
	local pill = UITheme.Button({
		name = "Pill",
		text = text,
		size = Vector2.new(buttonW, StoreUI.FooterMin),
		style = style,
		textSize = StoreUI.PriceTextPx(tenFoot(), mult),
	})
	if facts.state == "Owned" then
		pill.face.TextColor3 = C.Confirm -- SaleGreen on the dark pill
	end
	pill.root.AnchorPoint = Vector2.new(1, 0.5)
	pill.root.Position = UDim2.fromScale(1, 0.5)
	pill.root.Parent = footer
	pill.face.Activated:Connect(function()
		if StoreUI.CanBuy(facts.state, StorePrices.Failed(kind, item.key)) then
			Net.Remote("BuyRobuxItem"):FireServer(kind, item.key)
		elseif facts.state == "WalletFull" then
			HUD.Toast(string.format(StoreCopy.WalletCap, Util.formatCash(GameConfig.CashCap)))
		end
	end)
	return pill.face
end

-- Tests only: builds one card under `parent`.
function StoreUI._card(parent: Instance, kind: string, item: StoreData.Pass | StoreData.Product, facts: CardFacts)
	return card(parent, 1, kind, item, facts)
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
			label.TextScaled = StorePrices.Failed(kind, key) -- "Price unavailable" is wider than the pill at 21 px
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
		local listed = StoreData.IsForSale(entry.item.id)
			and StorePrices.ForSale(entry.kind, entry.key) ~= false
			and StoreUI.CardFacts(entry.kind, entry.item).state ~= "Hidden"
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
	local layout = StoreUI.Layout(viewport, UITheme.Scale(), userMult())
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
	Net.Remote("StoreOpened"):FireServer() -- analytics only: the server rate limits it and counts nothing else
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
	rows.SelectionImageObject = UITheme.HiddenSelection() -- panel-sized: no selection box over the whole list
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
	layout.CellSize = UDim2.fromOffset(300, StoreUI.CardHeight(1))
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
	for _, attribute in ipairs({
		"DoubleWoodUntil",
		"InstantDeliveries",
		"Cash",
		"StoreStage",
		"PolicyKnown",
		"PolicyPaidRandomRestricted",
		"SettingUIScale",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if panel and panel.Visible then
				applyLayout()
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
