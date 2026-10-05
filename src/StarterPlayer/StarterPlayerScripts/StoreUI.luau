--!strict
-- StoreUI: the Robux store.
--   * A STORE button beside the cash (HUD.BesideCash) opens a cream-and-wood
--     panel with Passes and Products tabs. Hidden while every Creator Hub
--     id is still 0. Each card has an image slot (a placeholder when the
--     decal id is 0), the name, the description, Roblox's live price, and
--     Buy. An owned pass says Owned. A card whose id is 0 is not shown.
--     A pass stays hidden until GetProductInfo says IsForSale.
--   * The town bulletin board's prompt (StorePrompt) opens the same panel.
--   * "Sell load here" stays while you have Instant Deliveries and wood
--     on the truck.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local MenuPad = require(script.Parent.MenuPad)
local ShopUI = require(script.Parent.ShopUI)
local UITheme = require(script.Parent.UITheme)

local StoreUI = {}

local STORE = {
	subtitle = "Robux time-savers. Nothing pay-to-win.",
}

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)

local prices: { [string]: number } = {}
-- GetProductInfo.IsForSale, keyed like prices. Absent until that lookup
-- returns; a pass card stays hidden until then.
local passOnSale: { [string]: boolean } = {}
local deliveryButton: UITheme.Button? = nil
local tab: "Passes" | "Products" = "Passes"
local panel: Frame? = nil
local list: ScrollingFrame? = nil
local passTab: TextButton? = nil
local productTab: TextButton? = nil
local storeOpen = false
local focus: GuiObject? = nil

-- Price tags on the cards: 14 px in hand, 18 px on a TV.
function StoreUI.PriceTextPx(tenFoot: boolean): number
	return if tenFoot then 18 else 14
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
	MenuPad.Open(button)
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

local function robux(price: number?): string
	return if price then "R$ " .. tostring(price) else "R$ …"
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
	b:SetText(string.format("Sell here (%d)", n))
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
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function card(
	parent: Instance,
	name: string,
	detail: string,
	imageId: number,
	buttonText: string,
	owned: boolean,
	onBuy: () -> ()
)
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundColor3 = C.Cream
	row.Size = UDim2.new(1, -8, 0, 188)
	row.BorderSizePixel = 0
	UITheme.corner(row, 10)
	UITheme.stroke(row, C.Bark, 2)
	local art = Instance.new("ImageLabel")
	art.Name = "Image"
	art.BackgroundColor3 = ROBUX_GREEN
	art.Size = UDim2.fromOffset(72, 72)
	art.Position = UDim2.fromOffset(10, 58)
	art.BorderSizePixel = 0
	art.ScaleType = Enum.ScaleType.Fit
	if imageId > 0 then
		art.Image = "rbxassetid://" .. tostring(imageId)
	else
		art.Image = ""
		local mark = Instance.new("TextLabel")
		mark.BackgroundTransparency = 1
		mark.Size = UDim2.fromScale(1, 1)
		mark.Font = F.Black
		mark.TextSize = 18
		mark.TextColor3 = C.Cream
		mark.Text = string.sub(name, 1, 1)
		mark.Parent = art
	end
	UITheme.corner(art, 8)
	art.Parent = row
	local title = UITheme.label(row, name, F.Black, 16, C.Ink)
	title.Position = UDim2.fromOffset(92, 8)
	title.Size = UDim2.new(1, -180, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local body = UITheme.label(row, detail, F.Body, 13, C.Bark)
	body.Position = UDim2.fromOffset(92, 32)
	body.Size = UDim2.new(1, -180, 0, 148)
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	local buy = UITheme.Button({
		name = "Buy",
		text = if owned then "Owned" else buttonText,
		size = Vector2.new(88, UITheme.Size.Tap),
		style = if owned then "inuse" else "buy",
		textSize = StoreUI.PriceTextPx(tenFoot()),
	})
	buy.root.AnchorPoint = Vector2.new(1, 0.5)
	buy.root.Position = UDim2.new(1, -8, 0.5, 0)
	buy.root.Parent = row
	buy.face.Activated:Connect(function()
		if not owned then
			onBuy()
		end
	end)
	row.Parent = parent
end

local function redraw()
	local frame = list
	local passes = passTab
	local products = productTab
	if not frame or not passes or not products then
		return
	end
	passes.BackgroundColor3 = if tab == "Passes" then C.Amber else C.Cream
	products.BackgroundColor3 = if tab == "Products" then C.Amber else C.Cream
	clear(frame)
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	if tab == "Passes" then
		local shown = 0
		for _, pass in ipairs(StoreData.Passes) do
			local id = "Pass:" .. pass.key
			if StoreData.PassCardVisible(pass.id, passOnSale[id]) then
				shown += 1
				local has = player:GetAttribute("Pass_" .. pass.key) == true
				card(frame, pass.name, pass.description, pass.image, robux(prices[id]), has, function()
					Net.Remote("BuyRobuxItem"):FireServer("Pass", pass.key)
				end)
			end
		end
		if shown == 0 then
			local empty = UITheme.label(frame, "Passes coming soon.", F.Body, 16, C.Bark)
			empty.Size = UDim2.new(1, 0, 0, 40)
		end
	else
		local shown = 0
		for _, product in ipairs(StoreData.Products) do
			if StoreData.IsForSale(product.id) then
				shown += 1
				local fits = StoreData.PackFits(product, cash, GameConfig.CashCap)
				local name = product.name
				if product.boostHours then
					local left = hoursLeft((player:GetAttribute("DoubleWoodUntil") :: number?) or 0)
					if left > 0 then
						name ..= string.format("  ·  %dh left", left)
					end
				elseif product.key == "InstantDelivery" then
					local n = (player:GetAttribute("InstantDeliveries") :: number?) or 0
					if n > 0 then
						name ..= string.format("  ·  you have %d", n)
					end
				end
				local label = if fits then robux(prices["Product:" .. product.key]) else "Wallet full"
				card(frame, name, product.description, product.image, label, false, function()
					if not fits then
						HUD.Toast(
							string.format(
								"Your wallet can't hold that much (the cap is %s).",
								Util.formatCash(GameConfig.CashCap)
							)
						)
					else
						Net.Remote("BuyRobuxItem"):FireServer("Product", product.key)
					end
				end)
			end
		end
		if shown == 0 then
			local empty = UITheme.label(frame, "Products coming soon.", F.Body, 16, C.Bark)
			empty.Size = UDim2.new(1, 0, 0, 40)
		end
	end
end

local function loadPrices()
	local function fetch(key: string, id: number, infoType: Enum.InfoType)
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			if ok and type(info) == "table" then
				if type(info.PriceInRobux) == "number" then
					prices[key] = info.PriceInRobux
				end
				if infoType == Enum.InfoType.GamePass then
					passOnSale[key] = info.IsForSale == true
				end
				redraw()
			end
		end)
	end
	for _, pass in ipairs(StoreData.Passes) do
		if StoreData.IsForSale(pass.id) then
			fetch("Pass:" .. pass.key, pass.id, Enum.InfoType.GamePass)
		end
	end
	for _, product in ipairs(StoreData.Products) do
		if StoreData.IsForSale(product.id) then
			fetch("Product:" .. product.key, product.id, Enum.InfoType.Product)
		end
	end
end

local function openStore()
	local frame = panel
	if not frame then
		return
	end
	frame.Visible = true
	redraw()
	StoreUI._open(passTab)
	task.defer(function()
		setModal(true)
	end)
end

local function closeStore()
	StoreUI._close()
end

function StoreUI.Start()
	local gui = UITheme.Screen("StoreUI", UITheme.Layers.Store)
	local spec = UITheme.Sized("Store")
	local store = UITheme.Button({
		name = "Store",
		text = "STORE",
		size = spec.size or Vector2.new(90, 30),
		style = "buy",
		textSize = spec.text,
	})
	store.root.LayoutOrder = 10
	store.root.Visible = StoreData.AnyForSale()
	store.root.Parent = HUD.BesideCash()
	store.face.Activated:Connect(openStore)
	if spec.hit then
		UITheme.HitPad(store.root, spec.hit).Activated:Connect(openStore)
	end
	ShopUI.SetStoreOpener(openStore)

	local shell = UITheme.Card(C.Paper, C.Bark, 3, 14, false, "Panel")
	local inset = UITheme.SkinInset("Panel")
	UITheme.padding(shell.face, inset, inset, inset, inset)
	shell.outer.Name = "StorePanel"
	shell.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.outer.Position = UDim2.fromScale(0.5, 0.5)
	-- 92% of the screen's height up to 520: a 520px panel hangs off a phone
	-- held sideways (about 435 tall after the scale), with Close off screen.
	shell.outer.Size = UDim2.new(0, 460, 0.92, 0)
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(460, 520)
	fit.Parent = shell.outer
	shell.outer.Visible = false
	panel = shell.outer
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 44)
	head.Parent = shell.face
	local heading = UITheme.label(head, "STORE", F.Black, 18, C.Bark)
	local sub = UITheme.label(head, STORE.subtitle, F.Body, 13, C.Bark)
	sub.Position = UDim2.fromOffset(90, 12)
	sub.Size = UDim2.new(1, -160, 0, 20)
	heading.Size = UDim2.fromOffset(120, 28)
	heading.Position = UDim2.fromOffset(8, 8)
	local close = UITheme.Button({
		name = "Close",
		text = "X",
		size = Vector2.new(44, 44),
		style = "cant",
		textSize = 18,
	})
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, -4, 0, 0)
	close.root.Parent = head
	close.face.Activated:Connect(closeStore)
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(0, 48)
	tabs.Size = UDim2.new(1, 0, 0, UITheme.Size.Tap + 4)
	tabs.Parent = shell.face
	local function tabButton(name: string, x: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(140, UITheme.Size.Tap)
		b.Position = UDim2.fromOffset(x, 0)
		b.Font = F.Black
		b.TextSize = 15
		b.Text = string.upper(name)
		b.TextColor3 = C.Ink
		b.BackgroundColor3 = C.Cream
		b.AutoButtonColor = true
		UITheme.corner(b, 8)
		UITheme.stroke(b, C.Bark, 2)
		b.Parent = tabs
		return b
	end
	local passesBtn = tabButton("Passes", 8)
	local productsBtn = tabButton("Products", 156)
	passTab = passesBtn
	productTab = productsBtn
	passesBtn.NextSelectionRight = productsBtn
	productsBtn.NextSelectionLeft = passesBtn
	close.face.NextSelectionDown = passesBtn
	passesBtn.Activated:Connect(function()
		tab = "Passes"
		redraw()
	end)
	productsBtn.Activated:Connect(function()
		tab = "Products"
		redraw()
	end)
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Cards"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(0, 100)
	rows.Size = UDim2.new(1, 0, 1, -108)
	rows.CanvasSize = UDim2.fromOffset(0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 6
	rows.Parent = shell.face
	UITheme.list(rows, 8)
	UITheme.padding(rows, 4, 8, 8, 8)
	list = rows
	shell.outer.Parent = gui

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

	loadPrices()
	redraw()
	for _, pass in ipairs(StoreData.Passes) do
		player:GetAttributeChangedSignal("Pass_" .. pass.key):Connect(redraw)
	end
	for _, attribute in ipairs({ "DoubleWoodUntil", "InstantDeliveries", "Cash" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			redraw()
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
