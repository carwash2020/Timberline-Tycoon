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

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
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

-- A row that must never prompt. ids() already omits anything not for sale;
-- this is the fallback if a row is asked for anyway.
local function notForSale(): ShopUI.RowView
	return {
		name = "Not for sale",
		detail = "This item isn't set up yet.",
		color = ROBUX_GREEN,
		dim = true,
		button = "Soon",
		state = "inuse",
		onClick = function() end,
	}
end

-- Loads each item's price from Roblox once, then redraws. An id of 0 is
-- skipped: GetProductInfo(0) errors.
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

local function hoursLeft(untilTime: number): number
	return math.max(0, math.ceil((untilTime - os.time()) / 3600))
end

local STORE: ShopUI.Shop = {
	building = nil,
	promptText = "",
	title = "Store",
	subtitle = "Robux time-savers. Nothing pay-to-win.",
	ids = function()
		local ids = {}
		for _, pass in ipairs(StoreData.Passes) do
			if StoreData.IsForSale(pass.id) then
				table.insert(ids, "Pass:" .. pass.key)
			end
		end
		for _, product in ipairs(StoreData.Products) do
			if StoreData.IsForSale(product.id) then
				table.insert(ids, "Product:" .. product.key)
			end
		end
		return ids
	end,
	view = function(id: string): ShopUI.RowView
		local kind, key = string.match(id, "^(%a+):(%w+)$")
		if kind == "Pass" then
			local pass = StoreData.Pass(key or "")
			if not pass or not StoreData.IsForSale(pass.id) then
				return notForSale()
			end
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
		local product = StoreData.Product(key or "")
		if not product or not StoreData.IsForSale(product.id) then
			return notForSale()
		end
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
	-- The v2 loop: the loose wood riding on your beds (TruckLoad's BedVolume, u³).
	if CoreLoop.V2() then
		local volume = player:GetAttribute("BedVolume")
		return if type(volume) == "number" and volume > 0 then volume else 0
	end
	local mirrored = player:GetAttribute("BedCount") -- set by the server even when the truck streams out
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

local function buildButtons()
	-- A corner pill: on a phone 36 tall, with a fingertip-tall hit area
	-- round it (UITheme.HitPad).
	local spec = UITheme.Sized("Store")
	local store = UITheme.Button({
		name = "Store",
		text = "STORE",
		size = spec.size or Vector2.new(90, 30),
		style = "buy",
		textSize = spec.text,
	})
	store.root.LayoutOrder = 10 -- left of the clock (HUD's corner, beside the cash)
	store.root.Visible = #STORE.ids() > 0 -- hidden while every CreatorIds entry is still 0
	store.root.Parent = HUD.BesideCash()
	local function openStore()
		ShopUI.OpenCustom(STORE)
	end
	store.face.Activated:Connect(openStore)
	if spec.hit then
		UITheme.HitPad(store.root, spec.hit).Activated:Connect(openStore) -- under the face: it still looks pressed
	end

	deliveryButton = HUD.SideButton({
		name = "InstantDelivery",
		text = "Sell here",
		style = "buy",
		order = 2,
		onPress = function()
			Net.Remote("UseInstantDelivery"):FireServer()
		end,
	})
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
