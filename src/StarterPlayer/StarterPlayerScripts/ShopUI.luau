--!strict
-- ShopUI: the shop screen, for both shops.
--   * Tool Shed ("Browse axes"): the whole axe ladder. The next axe can be
--     bought, owned ones bought again (for a collection), later ones show
--     as locked, and the Starfall Axe as forged. Each row says the axe's
--     damage and the toughest woods it fells.
--   * Dealership ("Browse trucks"): every truck with its bed size and top
--     speed, then the trailers. Buy a truck, or switch to one you own (it
--     waits in your parking spot); buy a trailer, hitch it, or unhitch it.
--   Under boxed stores (GameConfig.BoxedStores, on unless set to false)
--     none of these three opens: the shops sell boxes you carry to the
--     counter, the Dealership sells its lot's boxes, and the screen is
--     kept only for the rollback.
--   * Hearth & Home ("Browse gear"): gear for the far biomes, bought once
--     and worn for good. Gear for a biome that isn't built yet says Soon.
-- Buying only sends an intent (BuyItem / EquipItem); the server checks
-- everything and answers with a toast. The player attributes it changes
-- (Cash, OwnedAxes, BestAxeTier, OwnedTrucks, EquippedTruck, OwnedGear) redraw the
-- list. Walking away closes the screen, and so do the X, tapping outside the
-- panel, and B on a gamepad. Looks per the UI spec (02, UITheme): a dimmed
-- screen behind a wood-framed paper panel; while it's open you can't walk.
-- The panel keeps clear of Roblox's top bar (its real height), a phone's
-- notch (the screen is the device's safe area) and the HUD's cash row,
-- which is drawn over it (on a phone it moves left of the row). While it's
-- open the HUD knows where it is (HUD.SetModal), so its hint hides and its
-- toasts sit inside the panel's bottom edge, off the title and the Buy
-- buttons; every way of closing goes through ShopUI.Close, which tells the
-- HUD it's gone. On a gamepad the first Buy button is selected when it
-- opens.
-- Prices and the cards' detail lines are the core loop's (CoreLoop.Active()):
-- ShopLogic.Price, AxeDetail, TruckDetailFor, TrailerDetailFor (v2 prices
-- and per-hit stats under v2), as ShopService charges.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local UITheme = require(script.Parent.UITheme)

type AxeDef = ItemCatalog.AxeDef
type TruckDef = ItemCatalog.TruckDef
type GearDef = ItemCatalog.GearDef
type TrailerDef = ItemCatalog.TrailerDef

local ShopUI = {}

local player = Players.LocalPlayer
local storeOpener: (() -> ())? = nil

-- StoreUI sets this so the Lux Axe's "Robux" button opens the store.
function ShopUI.SetStoreOpener(fn: () -> ())
	storeOpener = fn
end

local C = UITheme.Colors
local F = UITheme.Fonts

-- One row's look and what its button does right now.
export type RowView = {
	name: string,
	own: string?, -- small text after the name ("· you own 2")
	detail: string, -- up to two lines
	color: Color3, -- the swatch
	ring: Color3?, -- a glowing ring round the swatch (the Inferno and Starfall axes)
	dim: boolean, -- a faded swatch (locked)
	button: string,
	state: string, -- the button's UITheme style: buy, cant, starter, locked, forged, full, use, inuse
	onClick: () -> (),
}

-- A shop: which building (nil for a screen opened from a button, like the
-- Robux Store), the prompt, the header, and its rows.
export type Shop = {
	building: string?, -- model in TimberlineMap
	promptOffset: Vector2?, -- so two prompts on one counter don't stack
	promptText: string,
	title: string,
	subtitle: string, -- 40 characters at most (ShopUI.SubtitleMax): two lines on a phone
	ids: () -> { string },
	view: (id: string) -> RowView,
	shelf: boolean?, -- axes, saws, the general store and the Dealership: boxes on the shelves and lot sell these
}

type Row = {
	id: string,
	frame: Frame,
	name: TextLabel,
	own: TextLabel,
	detail: TextLabel,
	button: UITheme.Button,
	swatch: Frame,
	ring: UIStroke,
}

-- The longest a shop's subtitle may be: two lines on a phone's narrowest
-- panel (UI-19).
ShopUI.SubtitleMax = 40

local PANEL_MAX = Vector2.new(560, 540)
local PANEL_MIN_WIDTH = 400 -- narrower than this beside the cash row, it goes under the row instead

local gui: ScreenGui? = nil
local focusedFace: GuiObject? = nil
local area: Frame? = nil -- what the panel is centred in
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

local function priceButton(price: number, cash: number): (string, string)
	if cash >= price then
		return "Buy " .. Util.formatCash(price), "buy"
	end
	return Util.formatCash(price), "cant"
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
	shelf = true,
	promptText = "Browse axes",
	title = "Tool Shed",
	subtitle = "Sharper axes, fewer swings.",
	ids = function()
		local ids = {}
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(ids, axe.id)
		end
		local extra = {}
		for _, axe in pairs(ItemCatalog.Axes) do
			if axe.robux then
				table.insert(extra, axe.id)
			end
		end
		table.sort(extra)
		for _, id in ipairs(extra) do
			table.insert(ids, id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local axe = ItemCatalog.GetAxe(id) :: AxeDef
		local cash, bestTier, counts, total = axeState()
		local owned = counts[axe.id] or 0
		local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, bestTier, owned, total)
		local loop = CoreLoop.Active()
		local price = ShopLogic.Price(axe, loop)
		local button, state
		if ShopLogic.CanPurchase(status) then
			button, state = priceButton(price, cash)
		elseif status == "forged" then
			button, state = "Forged", "forged"
		elseif status == "robux" then
			button, state = "Robux", "forged"
		elseif status == "starter" then
			button, state = "Starter", "starter"
		elseif status == "full" then
			button, state = "Full", "full"
		else
			button, state = "Locked", "locked"
		end
		local ring: Color3? = nil
		if axe.look.glow then
			ring = if axe.forge then C.Ice else C.Amber
		end
		return {
			name = axe.displayName,
			own = if owned > 0 then string.format("· you own %d", owned) else nil,
			detail = ShopLogic.AxeDetail(axe, loop),
			color = Color3.fromHex(axe.look.headColor),
			ring = ring,
			dim = status == "locked",
			button = button,
			state = state,
			onClick = function()
				if status == "robux" then
					local openStore = storeOpener
					if openStore then
						openStore()
					else
						HUD.Toast(ShopLogic.WhyNot(status, axe, bestTier))
					end
				elseif not ShopLogic.CanPurchase(status) then
					HUD.Toast(ShopLogic.WhyNot(status, axe, bestTier))
				elseif cash < price then
					needMore(price, cash, axe.displayName)
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

local function trailerView(id: string): RowView
	local trailer = ItemCatalog.GetTrailer(id) :: TrailerDef
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedTrailers") :: string?) or "")
	local hitched = (player:GetAttribute("HitchedTrailer") :: string?) or ""
	local status: ShopLogic.TrailerStatus = ShopLogic.TrailerStatusOf(trailer, owned, hitched)
	local loop = CoreLoop.Active()
	local price = ShopLogic.Price(trailer, loop)
	local button, state
	if status == "buy" then
		button, state = priceButton(price, cash)
	elseif status == "hitch" then
		button, state = "Hitch", "use"
	else
		button, state = "Unhitch", "full"
	end
	return {
		name = trailer.displayName,
		own = if status == "hitched" then "· hitched" elseif status == "hitch" then "· owned" else nil,
		detail = ShopLogic.TrailerDetailFor(trailer, loop),
		color = Color3.fromHex(trailer.look.color),
		dim = false,
		button = button,
		state = state,
		onClick = function()
			if status == "buy" and cash < price then
				needMore(price, cash, trailer.displayName)
			elseif status == "buy" then
				Net.Remote("BuyItem"):FireServer("Trailer", trailer.id)
			else
				Net.Remote("EquipItem"):FireServer("Trailer", trailer.id) -- hitch, or unhitch
			end
		end,
	}
end

local TRUCKS: Shop = {
	building = "Dealership",
	shelf = true,
	promptText = "Browse trucks",
	title = "Dealership",
	subtitle = "Bigger beds haul more wood per trip.",
	-- Trucks first, then trailers ("Trailer:" ids).
	ids = function()
		local ids = {}
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			table.insert(ids, truck.id)
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			table.insert(ids, "Trailer:" .. trailer.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local trailerId = string.match(id, "^Trailer:(.+)$")
		if trailerId then
			return trailerView(trailerId)
		end
		local truck = ItemCatalog.GetTruck(id) :: TruckDef
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedTrucks") :: string?) or "")
		local equipped = (player:GetAttribute("EquippedTruck") :: string?) or ""
		local status: ShopLogic.TruckStatus = ShopLogic.TruckStatusOf(truck, owned, equipped)
		local loop = CoreLoop.Active()
		local price = ShopLogic.Price(truck, loop)
		local button, state
		if status == "buy" and truck.robux == true then
			button, state = "Robux", "forged"
		elseif status == "buy" then
			button, state = priceButton(price, cash)
		elseif status == "use" then
			button, state = "Use", "use"
		else
			button, state = "In use", "inuse"
		end
		return {
			name = truck.displayName,
			own = if status ~= "buy" then "· owned" else nil,
			detail = ShopLogic.TruckDetailFor(truck, loop),
			color = Color3.fromHex(truck.look.color),
			dim = false,
			button = button,
			state = state,
			onClick = function()
				if status == "buy" and truck.robux == true then
					local openStore = storeOpener
					if openStore then
						openStore()
					else
						HUD.Toast(string.format("The %s is in the Store.", truck.displayName))
					end
				elseif status == "inUse" then
					HUD.Toast(string.format("You're already using the %s.", truck.displayName))
				elseif status == "use" then
					Net.Remote("EquipItem"):FireServer("Truck", truck.id)
				elseif cash < price then
					needMore(price, cash, truck.displayName)
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

local function gearView(id: string): RowView
	local gear = ItemCatalog.GetGear(id) :: GearDef
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")
	local status: ShopLogic.GearStatus = ShopLogic.GearStatusOf(gear, owned)
	local loop = CoreLoop.Active()
	local price = ShopLogic.Price(gear, loop)
	local button, state
	if status == "buy" then
		button, state = priceButton(price, cash)
	elseif status == "owned" then
		button, state = "Owned", "inuse"
	else
		button, state = "Soon", "locked"
	end
	return {
		name = gear.displayName,
		detail = ShopLogic.GearDetail(gear),
		color = Color3.fromHex(gear.color),
		dim = status == "soon",
		button = button,
		state = state,
		onClick = function()
			if status == "owned" then
				HUD.Toast(string.format("You already have the %s.", gear.displayName))
			elseif status == "soon" then
				HUD.Toast(string.format("The %s goes on sale when its biome opens.", gear.displayName))
			elseif cash < price then
				needMore(price, cash, gear.displayName)
			else
				Net.Remote("BuyItem"):FireServer("Gear", gear.id)
			end
		end,
	}
end

local function blueprintView(id: string): RowView
	local bp = PlotData.Blueprint(id)
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local owned = ShopLogic.DecodeSet((player:GetAttribute("Blueprints") :: string?) or "")
	local have = owned[id] == true
	local price = if bp then PlotData.Price(bp) else 0
	local name = if bp then bp.displayName else id
	local button, state
	if have then
		button, state = "Owned", "inuse"
	else
		button, state = priceButton(price, cash)
	end
	return {
		name = name,
		own = if have then "· owned" else nil,
		detail = "Place it on your plot, as many times as you like.",
		color = Color3.fromHex("#A4693E"),
		dim = false,
		button = button,
		state = state,
		onClick = function()
			if have then
				HUD.Toast(string.format("You already own the %s blueprint.", name))
			elseif cash < price then
				needMore(price, cash, name)
			else
				Net.Remote("BuyItem"):FireServer("Blueprint", id)
			end
		end,
	}
end

-- General Store (the Hearth & Home building): blueprints bought once,
-- the axe ladder (the Lux Axe still opens the Robux store), and trinkets.
local GEAR: Shop = {
	building = "HearthAndHome",
	shelf = true,
	promptText = "Browse the store",
	title = "General Store",
	subtitle = "Blueprints, axes and trinkets.",
	ids = function()
		local ids = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.unlock then
				table.insert(ids, "Bp:" .. bp.id)
			end
		end
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(ids, "Axe:" .. axe.id)
		end
		local extra = {}
		for _, axe in pairs(ItemCatalog.Axes) do
			if axe.robux then
				table.insert(extra, axe.id)
			end
		end
		table.sort(extra)
		for _, id in ipairs(extra) do
			table.insert(ids, "Axe:" .. id)
		end
		for _, gear in ipairs(ItemCatalog.GearList()) do
			table.insert(ids, gear.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local blueprintId = string.match(id, "^Bp:(.+)$")
		if blueprintId then
			return blueprintView(blueprintId)
		end
		local axeId = string.match(id, "^Axe:(.+)$")
		if axeId then
			return AXES.view(axeId)
		end
		return gearView(id)
	end,
}

-- Tool Shed: sawmills. Buying puts one in stock; BUILD on your plot places it.
local SAWS: Shop = {
	building = "ToolShed",
	shelf = true,
	promptOffset = Vector2.new(0, 70),
	promptText = "Browse saws",
	title = "Saws",
	subtitle = "Logs in, planks out. Place on your plot.",
	ids = function()
		local ids = {}
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			table.insert(ids, mill.id)
		end
		return ids
	end,
	view = function(id: string): RowView
		local mill = ItemCatalog.GetSawmill(id) :: ItemCatalog.SawmillDef
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		local affordable = cash >= mill.priceCash
		return {
			name = mill.displayName,
			detail = SawmillLogic.Detail(mill),
			color = Color3.fromHex(mill.color),
			dim = false,
			button = if affordable then "Buy " .. Util.formatCash(mill.priceCash) else Util.formatCash(mill.priceCash),
			state = if affordable then "buy" else "cant",
			onClick = function()
				if cash < mill.priceCash then
					needMore(mill.priceCash, cash, mill.displayName)
					return
				end
				Net.Remote("BuyItem"):FireServer("Sawmill", mill.id)
			end,
		}
	end,
}

local SHOPS: { Shop } = { AXES, TRUCKS, GEAR, SAWS }

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function refresh()
	local shop = openShop
	if not shop then
		return
	end
	for _, row in ipairs(rows) do
		local view = shop.view(row.id)
		row.name.Text = view.name
		row.own.Text = view.own or ""
		row.own.Visible = view.own ~= nil
		row.detail.Text = view.detail
		row.swatch.BackgroundColor3 = view.color
		row.swatch.BackgroundTransparency = if view.dim then 0.65 else 0
		row.ring.Enabled = view.ring ~= nil
		row.ring.Color = view.ring or C.Amber
		row.button:SetText(view.button)
		row.button:SetStyle(view.state)
	end
end

local function buildRow(parent: Instance, shop: Shop, id: string, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.LayoutOrder = order
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = C.PaperDark
	frame.BorderSizePixel = 0
	UITheme.corner(frame, 12)
	UITheme.padding(frame, 10, 12, 10, 12)
	local minHeight = Instance.new("UISizeConstraint")
	minHeight.MinSize = Vector2.new(0, 72)
	minHeight.Parent = frame
	frame.Parent = parent

	-- Swatch: a 44 circle with an ink rim and a shaded bottom.
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	-- Offsets, not scale, inside the auto-sized row: centred in its 52 px
	-- minimum content height.
	swatch.Position = UDim2.fromOffset(0, 4)
	swatch.Size = UDim2.fromOffset(44, 44)
	swatch.BorderSizePixel = 0
	UITheme.corner(swatch, 22)
	UITheme.stroke(swatch, C.Ink, 3)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.85, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(0.82, 0.82, 0.82)),
	})
	shade.Parent = swatch
	swatch.Parent = frame
	-- The glow ring sits just outside the rim.
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.new(1, 6, 1, 6)
	halo.BackgroundTransparency = 1
	UITheme.corner(halo, 26)
	local ring = UITheme.stroke(halo, C.Amber, 3)
	ring.Enabled = false
	halo.Parent = swatch

	-- The row's button: 96 x 44 on a phone, a fingertip tall (UITheme.Sized).
	local buy = UITheme.Sized("ShopBuy")
	local buttonSize = buy.size or Vector2.new(100, 38)
	local buttonWidth, buttonHeight = buttonSize.X, buttonSize.Y
	local text = Instance.new("Frame")
	text.Name = "Text"
	text.Position = UDim2.fromOffset(56, 0)
	text.Size = UDim2.new(1, -(56 + buttonWidth + 12), 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.BackgroundTransparency = 1
	UITheme.list(text, 2)
	text.Parent = frame

	local nameRow = Instance.new("Frame")
	nameRow.Name = "NameRow"
	nameRow.LayoutOrder = 1
	nameRow.Size = UDim2.new(1, 0, 0, 20)
	nameRow.BackgroundTransparency = 1
	local nameList = UITheme.list(nameRow, 6, true)
	nameList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	nameRow.Parent = text
	local name = UITheme.label(nameRow, "", F.Heading, 18, C.Ink)
	name.LayoutOrder = 1
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Size = UDim2.fromOffset(0, 20)
	local own = UITheme.label(nameRow, "", F.Bold, UITheme.Sized("ShopOwn").text, C.Bark)
	own.LayoutOrder = 2
	own.AutomaticSize = Enum.AutomaticSize.X
	own.Size = UDim2.fromOffset(0, 16)

	local detail = UITheme.label(text, "", F.Body, UITheme.Sized("ShopDetail").text, C.Bark)
	detail.LayoutOrder = 2
	detail.Size = UDim2.fromScale(1, 0)
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.TextWrapped = true
	detail.LineHeight = 1.1

	local button = UITheme.Button({
		name = "Action",
		text = "",
		size = Vector2.new(buttonWidth, buttonHeight),
		style = "cant",
		textSize = buy.text,
	})
	button.root.AnchorPoint = Vector2.new(1, 0)
	button.root.Position = UDim2.new(1, 0, 0, math.floor((52 - (buttonHeight + 3)) / 2))
	button.root.Parent = frame
	button.face.Activated:Connect(function()
		-- Worked out fresh on every click, from the latest cash and ownership.
		shop.view(id).onClick()
	end)

	return {
		id = id,
		frame = frame,
		name = name,
		own = own,
		detail = detail,
		button = button,
		swatch = swatch,
		ring = ring,
	}
end

local function onCloseAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		ShopUI.Close()
	end
	return Enum.ContextActionResult.Sink
end

local function holdStill(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink -- no walking or jumping while a shop is open
end

-- The panel's area (HudLayout.ShopArea): 8 under Roblox's top bar
-- (UITheme.TopBar: its real height, not a guess), 8 above the bottom and
-- 12 in from the sides of the device's safe area (this screen is it: no
-- notch), but clear of the HUD's cash row (the plaque and the ♪ button),
-- which draws over the shop. On a phone the centred panel's top-right
-- corner, with its X, would sit under them: there the area ends left of
-- the row, or if that leaves too narrow a panel, starts under it.
local function fitArea()
	local g, a, row = gui, area, HUD.TopRow()
	if not g or not a then
		return
	end
	local scale = UITheme.Scale()
	local screen = g.AbsoluteSize / scale
	-- This screen starts at the top of the screen (in landscape), where the
	-- top bar's height is measured from.
	local fit = HudLayout.ShopArea(screen, UITheme.TopBar() / scale)
	if row then
		-- The row's screen starts under the top bar and this one doesn't:
		-- measure it from this one's corner.
		local at = (row.AbsolutePosition - g.AbsolutePosition) / scale
		local size = row.AbsoluteSize / scale
		local avoid = { left = at.X, top = at.Y, right = at.X + size.X, bottom = at.Y + size.Y }
		fit = HudLayout.ClearOf(fit, PANEL_MAX, avoid, 8, PANEL_MIN_WIDTH)
	end
	a.Position = UDim2.fromOffset(fit.left, fit.top)
	a.Size = UDim2.fromOffset(fit.right - fit.left, fit.bottom - fit.top)
end

-- Tells the HUD where the open panel is on screen (HUD.SetModal): on
-- opening, and whenever it moves or resizes while open (fitArea, a turned
-- phone), so the HUD's toasts follow it.
local function reportModal()
	local p = panel
	if not openShop or not p then
		return
	end
	local at, size = p.AbsolutePosition, p.AbsoluteSize
	HUD.SetModal({ left = at.X, top = at.Y, right = at.X + size.X, bottom = at.Y + size.Y })
end

local function open(shop: Shop)
	local g, p, scroll = gui, panel, list
	if not g or not p or not scroll then
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
	g.Enabled = true
	fitArea()
	reportModal()
	local prompt = prompts[shop]
	if prompt then
		prompt.Enabled = false
	end
	refresh()
	ContextActionService:BindAction("CloseShop", onCloseAction, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	ContextActionService:BindActionAtPriority(
		"ShopHoldStill",
		holdStill,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
	if rows[1] then
		-- The first thing you can buy, else the first row.
		local pick = rows[1].button.face
		for _, row in ipairs(rows) do
			if row.button.style == "buy" then
				pick = row.button.face
				break
			end
		end
		focusedFace = pick
		GuiService.SelectedObject = pick
	else
		focusedFace = nil
	end
end

function ShopUI.FirstFace(): GuiObject?
	return focusedFace
end

function ShopUI.Close()
	local shop = openShop
	if not shop then
		return
	end
	openShop = nil
	HUD.SetModal(nil) -- the hint comes back and the toasts go back up top
	local g, p = gui, panel
	if g then
		g.Enabled = false
	end
	local prompt = prompts[shop]
	if prompt then
		prompt.Enabled = true
	end
	ContextActionService:UnbindAction("CloseShop")
	ContextActionService:UnbindAction("ShopHoldStill")
	if GuiService.SelectedObject and p and GuiService.SelectedObject:IsDescendantOf(p) then
		GuiService.SelectedObject = nil
	end
end

local function buildPanel()
	-- Over everything but the HUD (10), so the cash and toasts show on top.
	-- The device's safe area with the top bar's strip in it: the scrim dims
	-- it, and the panel keeps clear of the bar itself (fitArea).
	local g = UITheme.Screen("ShopUI", UITheme.Layers.Shop, "device")
	g.Enabled = false

	-- The scrim: dims the game, blocks taps on it, and closes on a tap.
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = C.Ink
	scrim.BackgroundTransparency = 0.55
	scrim.AutoButtonColor = false
	scrim.Text = ""
	scrim.Selectable = false
	scrim.Modal = true -- frees the mouse in first person
	scrim.Parent = g
	scrim.Activated:Connect(ShopUI.Close)

	-- The panel fits the area below the top bar (fitArea, on opening), at
	-- most 560 x 540 (on an 844 x 390 phone about 300 tall, left of the
	-- cash).
	local a = Instance.new("Frame")
	a.Name = "Area"
	a.BackgroundTransparency = 1
	a.Position = UDim2.fromOffset(12, 66)
	a.Size = UDim2.new(1, -24, 1, -74)
	a.Parent = g

	local frame = UITheme.Card(C.Bark, C.Ink, 6, 20, false, "Panel")
	local p = frame.outer
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = UDim2.fromScale(1, 1)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = PANEL_MAX
	maxSize.Parent = p
	p.Parent = a
	UITheme.texture(frame.face, "Wood", 20)

	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	-- The panel face is padded by the slice margin, so this fills the flat
	-- center the prices sit on.
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = C.Paper
	paper.BorderSizePixel = 0
	paper.ClipsDescendants = true
	-- A gamepad's selection stays in the panel (B closes it), not on the
	-- HUD's buttons over it.
	paper.SelectionGroup = true
	paper.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	paper.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	paper.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	paper.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	UITheme.corner(paper, 14)
	paper.Parent = frame.face
	UITheme.texture(paper, "Kraft", 14)

	local closeSpec = UITheme.Sized("ShopClose") -- 48 on a phone
	local closeSize = (closeSpec.size or Vector2.new(44, 44)).X
	-- On a phone the subtitle may wrap onto a second line (HudLayout.ShopHeader).
	local phone = UITheme.IsPhone()
	local subtitleHeight = (if phone then 2 else 1) * HudLayout.SubtitleLine
	local headerHeight = HudLayout.ShopHeader(phone)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.BackgroundTransparency = 1
	header.Parent = paper
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.fromScale(0, 1)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.BackgroundColor3 = C.PaperDark
	rule.BorderSizePixel = 0
	rule.Parent = header

	local title = UITheme.label(header, "", F.Heading, 28, C.Ink)
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -(18 + closeSize + 26), 0, 30)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	-- FredokaOne is a wide face: a long title shrinks rather than truncates.
	UITheme.fit(title, 28, 20)
	titleLabel = title

	local subtitle = UITheme.label(header, "", F.Body, UITheme.Sized("ShopSubtitle").text, C.Bark)
	subtitle.Position = UDim2.fromOffset(18, 46)
	subtitle.Size = UDim2.new(1, -(18 + closeSize + 26), 0, subtitleHeight)
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.TextWrapped = phone
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitleLabel = subtitle

	local close = UITheme.Button({
		name = "Close",
		text = "X",
		size = Vector2.new(closeSize, closeSize),
		style = "bark",
		textSize = closeSpec.text,
		radius = 12,
	})
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, -14, 0, 12)
	close.root.Parent = header
	close.face.Activated:Connect(ShopUI.Close)
	-- On a gamepad, B closes: show its glyph on the corner of the X.
	local glyph = UITheme.Glyph(Enum.KeyCode.ButtonB, 22)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.new(1, -2, 1, -2)
	glyph.ZIndex = 3
	glyph.Visible = UITheme.Device() == "console"
	glyph.Parent = close.face
	UserInputService.LastInputTypeChanged:Connect(function()
		glyph.Visible = UITheme.Device() == "console"
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.Position = UDim2.fromOffset(0, headerHeight)
	scroll.Size = UDim2.new(1, 0, 1, -headerHeight)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.Bark
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = paper
	UITheme.list(scroll, 8)
	UITheme.padding(scroll, 10, 12 + 8, 12, 12) -- room for the scroll bar
	list = scroll

	gui, area, panel = g, a, p
	-- A phone turning round, or a window resized, while a shop is open; or
	-- the top bar getting its real size after the first frame.
	local function refit()
		if openShop then
			fitArea()
		end
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	UITheme.WatchTopBar(refit)
	-- Wherever the panel ends up once laid out, the HUD hears of it.
	p:GetPropertyChangedSignal("AbsoluteSize"):Connect(reportModal)
	p:GetPropertyChangedSignal("AbsolutePosition"):Connect(reportModal)
	g.Parent = player:WaitForChild("PlayerGui")
end

-- Calls `fn` with the named child now, and again if a later one arrives
-- (the shops are built after the client can start). A timed WaitForChild
-- warns when the map is still building; this never waits forever.
local function whenChild(parent: Instance, name: string, fn: (Instance) -> ())
	local found = parent:FindFirstChild(name)
	if found then
		fn(found)
	end
	parent.ChildAdded:Connect(function(child: Instance)
		if child.Name == name then
			fn(child)
		end
	end)
end

-- Shelves replace these menus while boxed stores are on. The Dealership
-- board stays. The server BuyItem path stays too, for a one-line rollback.
local function shelfMenu(shop: Shop): boolean
	return shop.shelf == true and ShopLogic.ShelfMenusHidden()
end

local function setupPrompt(shop: Shop, building: Instance)
	if points[shop] then
		return
	end
	local counter = building:FindFirstChild("Counter")
	local point = if counter then counter:FindFirstChild("ShopPoint") else nil
	if not point or not point:IsA("Attachment") then
		return
	end
	points[shop] = point

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = shop.promptText
	pp.ObjectText = shop.title
	pp.MaxActivationDistance = GameConfig.ShopPromptRange
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	InputKit.PromptDefaults(pp, "Interact")
	if shop.promptOffset then
		pp.UIOffset = shop.promptOffset
	end
	pp.Parent = point
	pp.Triggered:Connect(function()
		open(shop)
	end)
	prompts[shop] = pp
end

-- Opens a screen that isn't tied to a building (the Robux Store).
function ShopUI.OpenCustom(shop: Shop)
	open(shop)
end

-- Redraws the open screen (e.g. once prices have loaded).
function ShopUI.Refresh()
	refresh()
end

function ShopUI.Start()
	buildPanel()
	for _, attribute in ipairs({
		"Cash",
		"BestAxeTier",
		"OwnedAxes",
		"OwnedTrucks",
		"EquippedTruck",
		"OwnedTrailers",
		"HitchedTrailer",
		"OwnedGear",
		"SawmillStock",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	-- Prices follow the loop MapBuilder publishes. Until that attribute
	-- replicates, Active() reads as v1 and the cards would show v1 prices.
	workspace:GetAttributeChangedSignal(CoreLoop.ActiveAttribute):Connect(refresh)
	-- Shops are Persistent, but they are parented during the map build,
	-- which can still be running when this client starts. Find them when
	-- they appear; a bare WaitForChild warns and, if one were streamed
	-- out, would wait forever.
	local function watchMap(map: Instance)
		for _, shop in ipairs(SHOPS) do
			local buildingName = shop.building
			if buildingName and not shelfMenu(shop) then
				whenChild(map, buildingName, function(building: Instance)
					setupPrompt(shop, building)
				end)
			end
		end
	end
	local mapNow = workspace:FindFirstChild("TimberlineMap")
	if mapNow then
		watchMap(mapNow)
	else
		workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "TimberlineMap" then
				watchMap(child)
			end
		end)
	end
	-- Walked away (or respawned somewhere else)? Close the screen.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local shop = openShop
		if not shop or not shop.building or elapsed < 0.25 then
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
