--!strict
-- StoreUI: the Robux Store (items in Shared/StoreData).
--   * A STORE button next to the clock opens it (drawn by ShopUI). It lists
--     every pass and product that's set up (has a Creator Hub id), with
--     Roblox's live price. Buying asks the server, which checks it (a cash
--     pack must fit in the wallet) and shows Roblox's purchase prompt.
--   * "Sell load here" appears while you have Instant Deliveries and logs in
--     your truck bed.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local ShopUI = require(script.Parent.ShopUI)
local UITheme = require(script.Parent.UITheme)

local StoreUI = {}

local player = Players.LocalPlayer

local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)

local prices: { [string]: number } = {} -- "Pass:DoubleCash" -> Robux
local deliveryButton: UITheme.Button? = nil

local function robux(price: number?): string
	return if price then "R$ " .. tostring(price) else "R$ …"
end

-- Loads each item's price from Roblox once, then redraws.
local function loadPrices()
	local function fetch(key: string, id: number, infoType: Enum.InfoType)
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[key] = info.PriceInRobux
				ShopUI.Refresh()
			end
		end)
	end
	for _, pass in ipairs(StoreData.Passes) do
		if pass.id ~= 0 then
			fetch("Pass:" .. pass.key, pass.id, Enum.InfoType.GamePass)
		end
	end
	for _, product in ipairs(StoreData.Products) do
		if product.id ~= 0 then
			fetch("Product:" .. product.key, product.id, Enum.InfoType.Product)
		end
	end
end

local function hoursLeft(untilTime: number): number
	return math.max(0, math.ceil((untilTime - os.time()) / 3600))
end

local STORE: ShopUI.Shop = {
	building = nil,
	promptText = "",
	title = "Store",
	subtitle = "Robux extras: nothing here makes you win, it just saves time.",
	ids = function()
		local ids = {}
		for _, pass in ipairs(StoreData.Passes) do
			if pass.id ~= 0 then
				table.insert(ids, "Pass:" .. pass.key)
			end
		end
		for _, product in ipairs(StoreData.Products) do
			if product.id ~= 0 then
				table.insert(ids, "Product:" .. product.key)
			end
		end
		return ids
	end,
	view = function(id: string): ShopUI.RowView
		local kind, key = string.match(id, "^(%a+):(%w+)$")
		if kind == "Pass" then
			local pass = StoreData.Pass(key or "") :: StoreData.Pass
			local has = player:GetAttribute("Pass_" .. pass.key) == true
			return {
				name = pass.name,
				detail = pass.description,
				color = ROBUX_GREEN,
				ring = UITheme.Colors.Amber,
				dim = false,
				button = if has then "Owned" else robux(prices[id]),
				state = if has then "inuse" else "buy",
				onClick = function()
					if has then
						HUD.Toast(string.format("You already have %s.", pass.name))
					else
						Net.Remote("BuyRobuxItem"):FireServer("Pass", pass.key)
					end
				end,
			}
		end
		local product = StoreData.Product(key or "") :: StoreData.Product
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		local fits = StoreData.PackFits(product, cash, GameConfig.CashCap)
		local name = product.name
		if product.boostHours then
			local left = hoursLeft((player:GetAttribute("DoubleWoodUntil") :: number?) or 0)
			if left > 0 then
				name ..= string.format("  ·  on, %dh left", left)
			end
		elseif product.key == "InstantDelivery" then
			local n = (player:GetAttribute("InstantDeliveries") :: number?) or 0
			if n > 0 then
				name ..= string.format("  ·  you have %d", n)
			end
		end
		return {
			name = name,
			detail = product.description,
			color = ROBUX_GREEN,
			dim = not fits,
			button = if fits then robux(prices[id]) else "Wallet full",
			state = if fits then "buy" else "inuse",
			onClick = function()
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
			end,
		}
	end,
}

local function myBedCount(): number
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

local function buildButtons()
	local gui = UITheme.Screen("StoreButtons")
	local store = UITheme.Button({
		name = "Store",
		text = "STORE",
		size = Vector2.new(90, 30),
		style = "buy",
		textSize = 14,
	})
	store.root.AnchorPoint = Vector2.new(1, 0)
	store.root.Position = UDim2.new(1, -(UITheme.Margin() + 318), 0, 15) -- left of the clock
	store.root.Visible = #STORE.ids() > 0 -- hidden until something's set up in StoreData
	store.root.Parent = gui
	store.face.Activated:Connect(function()
		ShopUI.OpenCustom(STORE)
	end)

	deliveryButton = HUD.SideButton({
		name = "InstantDelivery",
		text = "Sell here",
		style = "buy",
		order = 2,
		onPress = function()
			Net.Remote("UseInstantDelivery"):FireServer()
		end,
	})

	gui.Parent = player:WaitForChild("PlayerGui")
end

function StoreUI.Start()
	buildButtons()
	loadPrices()
	for _, attribute in ipairs({ "Pass_DoubleCash", "DoubleWoodUntil", "InstantDeliveries" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			ShopUI.Refresh()
			refreshDelivery()
		end)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			refreshDelivery()
		end
	end)
end

return StoreUI
