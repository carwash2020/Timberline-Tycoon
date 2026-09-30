--!strict
-- AxeController: dropping axes.
-- Every axe you own is in your hotbar; switch with the number keys or by
-- tapping it. While you hold one, a "Drop axe" button shows (Backspace on
-- a keyboard does the same). The server lays it on the ground, where a
-- "Pick up" prompt brings it back. Dropped axes stay yours (AxeService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local AxeController = {}

local player = Players.LocalPlayer

local button: TextButton? = nil

local function heldAxe(): Tool?
	local char = player.Character
	local tool = if char then char:FindFirstChildOfClass("Tool") else nil
	return if tool and type(tool:GetAttribute("AxeUid")) == "string" then tool else nil
end

local function dropHeld()
	local tool = heldAxe()
	if tool then
		Net.Remote("DropAxe"):FireServer(tool:GetAttribute("AxeUid"))
	end
end

local function refresh()
	local b = button
	if b then
		b.Visible = heldAxe() ~= nil
	end
end

local function watchCharacter(char: Model)
	char.ChildAdded:Connect(refresh)
	char.ChildRemoved:Connect(refresh)
	refresh()
end

function AxeController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AxeControls"
	gui.ResetOnSpawn = false

	local b = Instance.new("TextButton")
	b.Name = "DropAxe"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -12, 0.6, 0) -- right edge, clear of the mobile jump button
	b.Size = UDim2.new(0, 110, 0, 40)
	b.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	b.BackgroundTransparency = 0.1
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(245, 235, 215)
	b.Text = "Drop axe"
	b.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	b.Parent = gui
	b.Activated:Connect(dropHeld)
	button = b
	gui.Parent = player:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Backspace then
			dropHeld()
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return AxeController
