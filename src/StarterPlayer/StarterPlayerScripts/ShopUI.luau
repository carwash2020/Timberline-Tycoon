--!strict
-- ShopUI: the Tool Shed's axe screen.
-- A "Browse axes" prompt at the Tool Shed counter opens it. It lists the
-- whole axe ladder: the next axe can be bought, owned ones can be bought
-- again (for a collection), later ones show as locked, and the Starfall Axe
-- as forged. Each row says what the axe does: damage and the toughest woods
-- it fells, and how many hits that takes.
-- Buying only sends an intent (BuyItem); the server checks everything and
-- answers with a toast. The Cash / OwnedAxes / BestAxeTier attributes it
-- changes redraw the list. Walking away closes the screen, and so does the
-- close button (or B on a gamepad).

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

local ShopUI = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local PAPER_DARK = Color3.fromRGB(226, 207, 170)
local BARK = Color3.fromRGB(88, 58, 34)
local GREEN = Color3.fromRGB(76, 140, 64)
local MUTED = Color3.fromRGB(160, 145, 120)
local SKY = Color3.fromRGB(110, 120, 190)

type Row = {
	axe: AxeDef,
	name: TextLabel,
	button: TextButton,
	swatch: Frame,
}

local panel: Frame? = nil
local rows: { Row } = {}
local prompt: ProximityPrompt? = nil
local isOpen = false

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

-- What the shop knows about the player, from server-set attributes.
local function state(): (number, number, { [string]: number }, number)
	local cash = (player:GetAttribute("Cash") :: number?) or 0
	local bestTier = (player:GetAttribute("BestAxeTier") :: number?) or 1
	local owned = (player:GetAttribute("OwnedAxes") :: string?) or ""
	local counts, total = ShopLogic.DecodeOwned(owned)
	return cash, bestTier, counts, total
end

local function refresh()
	if not isOpen then
		return
	end
	local cash, bestTier, counts, total = state()
	for _, row in ipairs(rows) do
		local axe = row.axe
		local owned = counts[axe.id] or 0
		local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, bestTier, owned, total)
		local button = row.button
		row.name.Text = if owned > 0
			then string.format("%s  ·  you own %d", axe.displayName, owned)
			else axe.displayName
		row.swatch.BackgroundTransparency = if status == "locked" then 0.6 else 0
		if ShopLogic.CanPurchase(status) then
			local affordable = cash >= axe.priceCash
			button.Text = if affordable
				then "Buy " .. Util.formatCash(axe.priceCash)
				else Util.formatCash(axe.priceCash)
			button.BackgroundColor3 = if affordable then GREEN else MUTED
		elseif status == "forged" then
			button.Text = "Forged"
			button.BackgroundColor3 = SKY
		else
			button.Text = if status == "starter" then "Starter" elseif status == "full" then "Full" else "Locked"
			button.BackgroundColor3 = MUTED
		end
	end
end

local function onRowClicked(axe: AxeDef)
	local cash, bestTier, counts, total = state()
	local status: ShopLogic.AxeStatus = ShopLogic.StatusOf(axe, bestTier, counts[axe.id] or 0, total)
	if not ShopLogic.CanPurchase(status) then
		HUD.Toast(ShopLogic.WhyNot(status, axe, bestTier))
	elseif cash < axe.priceCash then
		HUD.Toast(string.format("You need %s more for the %s.", Util.formatCash(axe.priceCash - cash), axe.displayName))
	else
		Net.Remote("BuyItem"):FireServer("Axe", axe.id) -- the server re-checks all of it
	end
end

local function buildRow(parent: Instance, axe: AxeDef, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = axe.id
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
	swatch.BackgroundColor3 = Color3.fromHex(axe.look.headColor)
	swatch.BorderSizePixel = 0
	corner(swatch, 20)
	if axe.look.glow then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 240, 180)
		stroke.Thickness = 2
		stroke.Parent = swatch
	end
	swatch.Parent = frame

	local name = label(frame, axe.displayName, 17, Enum.Font.GothamBold)
	name.Position = UDim2.fromOffset(60, 8)
	name.Size = UDim2.new(1, -172, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local detail = label(frame, ShopLogic.DamageText(axe) .. "\n" .. ShopLogic.FellSummary(axe), 14, Enum.Font.Gotham)
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
	button.Name = "Buy"
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
		onRowClicked(axe)
	end)

	return { axe = axe, name = name, button = button, swatch = swatch }
end

local function onCloseAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		ShopUI.Close()
	end
	return Enum.ContextActionResult.Sink
end

function ShopUI.Open()
	local p = panel
	if not p or isOpen then
		return
	end
	isOpen = true
	p.Visible = true
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
	if not isOpen then
		return
	end
	isOpen = false
	local p = panel
	if p then
		p.Visible = false
	end
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

	local title = label(paper, "TOOL SHED", 26, Enum.Font.Fantasy)
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -70, 0, 30)

	local subtitle = label(
		paper,
		"Axes are sold in order. Every axe you buy is yours to keep: switch in your hotbar.",
		13,
		Enum.Font.Gotham
	)
	subtitle.Position = UDim2.fromOffset(14, 38)
	subtitle.Size = UDim2.new(1, -28, 0, 30)
	subtitle.TextWrapped = true
	subtitle.TextYAlignment = Enum.TextYAlignment.Top

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

	local list = Instance.new("ScrollingFrame")
	list.Name = "Axes"
	list.Position = UDim2.fromOffset(10, 74)
	list.Size = UDim2.new(1, -20, 1, -84)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = BARK
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = paper
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8) -- room for the scroll bar
	pad.Parent = list

	for i, axe in ipairs(ItemCatalog.AxeLadder()) do
		table.insert(rows, buildRow(list, axe, i))
	end

	panel = p
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function setupPrompt()
	local map = workspace:WaitForChild("TimberlineMap")
	local shed = map:WaitForChild("ToolShed") -- a Persistent model: always streamed in
	local counter = shed:WaitForChild("Counter")
	local point = counter:WaitForChild("ShopPoint") :: Attachment

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Browse axes"
	pp.ObjectText = "Tool Shed"
	pp.MaxActivationDistance = GameConfig.ShopPromptRange
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.Parent = point
	pp.Triggered:Connect(ShopUI.Open)
	prompt = pp

	-- Walked away (or respawned somewhere else)? Close the screen.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if not isOpen or elapsed < 0.25 then
			return
		end
		elapsed = 0
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not hrp or (hrp.Position - point.WorldPosition).Magnitude > GameConfig.ShopRange then
			ShopUI.Close()
		end
	end)
end

function ShopUI.Start()
	buildPanel()
	for _, attribute in ipairs({ "Cash", "BestAxeTier", "OwnedAxes" }) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	task.spawn(setupPrompt)
end

return ShopUI
