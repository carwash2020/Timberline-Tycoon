-- HUD: builds the Phase 1 UI from code (wood-grain / kraft-paper theme).
-- Cash readout top-left (synced from server via CashChanged), a small
-- control hint bottom-center. Built in code so Rojo syncs it cleanly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)

local HUD = {}

local player = Players.LocalPlayer
local remotes: Folder? = nil

local cashLabel: TextLabel? = nil

local function getRemotes(): Folder
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes")
	end
	return remotes :: Folder
end

local function setCash(amount: number)
	if cashLabel then
		cashLabel.Text = Util.formatCash(amount)
	end
end

function HUD.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "TimberlineHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	-- Cash plaque, top-left.
	local plaque = Instance.new("Frame")
	plaque.Name = "CashPlaque"
	plaque.Size = UDim2.new(0, 220, 0, 56)
	plaque.Position = UDim2.new(0, 16, 0, 16)
	plaque.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	plaque.BorderSizePixel = 0
	local plaqueCorner = Instance.new("UICorner")
	plaqueCorner.CornerRadius = UDim.new(0, 10)
	plaqueCorner.Parent = plaque
	local paper = Instance.new("Frame")
	paper.Size = UDim2.new(1, -8, 1, -8)
	paper.Position = UDim2.new(0, 4, 0, 4)
	paper.BackgroundColor3 = Color3.fromRGB(240, 225, 195)
	paper.BorderSizePixel = 0
	local paperCorner = Instance.new("UICorner")
	paperCorner.CornerRadius = UDim.new(0, 7)
	paperCorner.Parent = paper
	paper.Parent = plaque

	cashLabel = Instance.new("TextLabel")
	cashLabel.Size = UDim2.new(1, 0, 1, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.Fantasy
	cashLabel.TextSize = 30
	cashLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
	cashLabel.Text = "$0"
	cashLabel.Parent = paper
	plaque.Parent = gui

	-- Control hint, bottom-center.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Size = UDim2.new(0, 640, 0, 40)
	hint.Position = UDim2.new(0.5, 0, 1, -14)
	hint.BackgroundColor3 = Color3.fromRGB(20, 15, 10)
	hint.BackgroundTransparency = 0.35
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 16
	hint.TextColor3 = Color3.fromRGB(245, 235, 215)
	hint.Text = "Click a tree to chop it  •  E = load logs to truck  •  Q = sell at sawmill"
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 8)
	hintCorner.Parent = hint
	hint.Parent = gui

	gui.Parent = playerGui

	-- Server is authoritative: seed from the attribute, then listen.
	setCash(player:GetAttribute("Cash") :: number? or 0)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		setCash(player:GetAttribute("Cash") :: number? or 0)
	end)
	getRemotes().CashChanged.OnClientEvent:Connect(setCash)
end

return HUD
