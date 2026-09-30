--!strict
-- HUD: builds the Phase 1 UI from code (wood-grain / kraft-paper theme).
--   * Cash plaque top-left, below Roblox's own top-bar buttons.
--   * A one-line control hint, worded for the device being used.
--   * Toasts: short messages from the server (Notify) or other controllers,
--     stacked (newest at the bottom, up to MAX_TOASTS) so none gets lost.
--   * "Loading your save..." until the server says the profile is ready.
-- Built in code so Rojo syncs it cleanly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

local HUD = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)

local MAX_TOASTS = 3
local TOAST_SECONDS = 2.4

local cashLabel: TextLabel? = nil
local toastStack: Frame? = nil
local toastOrder = 0

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function hintText(): string
	local verb = "Click"
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		verb = "Tap"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		verb = "Hold R2 on"
	end
	return verb
		.. " trees to chop  •  Pick up the logs  •  Load them at your truck's tailgate  •  Sell on the sawmill pad"
end

local function setCash(amount: number)
	local label = cashLabel
	if label then
		local full = amount >= GameConfig.CashCap
		label.Text = Util.formatCash(amount) .. (if full then " MAX" else "")
		label.TextColor3 = if full then Color3.fromRGB(176, 96, 18) else INK -- amber when the wallet is full
	end
end

-- Shows a short message in the upper middle of the screen for a few seconds.
function HUD.Toast(message: string)
	local stack = toastStack
	if not stack then
		return
	end
	-- Make room: drop the oldest toasts beyond the limit.
	local existing: { TextLabel } = {}
	for _, child in ipairs(stack:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #existing - MAX_TOASTS + 1 do
		existing[i]:Destroy()
	end

	toastOrder += 1
	local label = Instance.new("TextLabel")
	label.Name = "Toast"
	label.LayoutOrder = toastOrder
	label.Size = UDim2.new(0, 0, 0, 34)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Color3.fromRGB(240, 225, 195)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextColor3 = INK
	label.Text = message
	corner(label, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = label
	label.Parent = stack

	task.delay(TOAST_SECONDS, function()
		if label.Parent == nil then
			return -- already pushed out by newer toasts
		end
		local fade =
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
end

function HUD.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "TimberlineHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- keep clear of Roblox's menu and chat buttons
	gui.DisplayOrder = 10 -- above panels like the shop, so toasts stay visible

	-- Cash plaque, top-left.
	local plaque = Instance.new("Frame")
	plaque.Name = "CashPlaque"
	plaque.Size = UDim2.new(0, 200, 0, 50)
	plaque.Position = UDim2.new(0, 12, 0, 8)
	plaque.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	plaque.BorderSizePixel = 0
	corner(plaque, 10)
	local paper = Instance.new("Frame")
	paper.Size = UDim2.new(1, -8, 1, -8)
	paper.Position = UDim2.new(0, 4, 0, 4)
	paper.BackgroundColor3 = Color3.fromRGB(240, 225, 195)
	paper.BorderSizePixel = 0
	corner(paper, 7)
	paper.Parent = plaque

	local cash = Instance.new("TextLabel")
	cash.Size = UDim2.fromScale(1, 1)
	cash.BackgroundTransparency = 1
	cash.Font = Enum.Font.Fantasy
	cash.TextSize = 28
	cash.TextColor3 = INK
	cash.Text = "$0"
	cash.Parent = paper
	cashLabel = cash
	plaque.Parent = gui

	-- Control hint, bottom-centre, narrow enough to clear the mobile
	-- thumbstick (bottom-left) and jump button (bottom-right).
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Size = UDim2.new(0.46, 0, 0, 36)
	hint.Position = UDim2.new(0.5, 0, 1, -12)
	hint.BackgroundColor3 = Color3.fromRGB(20, 15, 10)
	hint.BackgroundTransparency = 0.35
	hint.Font = Enum.Font.Gotham
	hint.TextScaled = true
	hint.TextWrapped = true
	hint.TextColor3 = CREAM
	hint.Text = hintText()
	corner(hint, 8)
	local hintMax = Instance.new("UISizeConstraint")
	hintMax.MaxSize = Vector2.new(640, 36)
	hintMax.Parent = hint
	local hintTextSize = Instance.new("UITextSizeConstraint")
	hintTextSize.MaxTextSize = 16
	hintTextSize.Parent = hint
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 8)
	hintPad.PaddingRight = UDim.new(0, 8)
	hintPad.Parent = hint
	hint.Parent = gui

	-- Toast stack, upper-middle.
	local stack = Instance.new("Frame")
	stack.Name = "Toasts"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0.18, 0)
	stack.Size = UDim2.new(0.9, 0, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = stack
	stack.Parent = gui
	toastStack = stack

	-- "Loading your save..." until the server has the profile.
	local loading = Instance.new("TextLabel")
	loading.Name = "Loading"
	loading.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.Position = UDim2.fromScale(0.5, 0.5)
	loading.Size = UDim2.new(0, 280, 0, 48)
	loading.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	loading.Font = Enum.Font.Fantasy
	loading.TextSize = 24
	loading.TextColor3 = CREAM
	loading.Text = "Loading your save..."
	corner(loading, 10)
	loading.Parent = gui
	local function refreshLoading()
		loading.Visible = player:GetAttribute("ProfileLoaded") ~= true
	end
	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(refreshLoading)
	refreshLoading()

	gui.Parent = playerGui

	-- Server is authoritative: seed from the attribute, then listen.
	setCash((player:GetAttribute("Cash") :: number?) or 0)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		setCash((player:GetAttribute("Cash") :: number?) or 0)
	end)
	Net.Remote("CashChanged").OnClientEvent:Connect(setCash)
	Net.Remote("Notify").OnClientEvent:Connect(function(message: unknown)
		if type(message) == "string" then
			HUD.Toast(message)
		end
	end)
end

return HUD
