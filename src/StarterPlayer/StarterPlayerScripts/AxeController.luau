--!strict
-- AxeController: dropping axes.
-- Every axe you own is in your hotbar; switch with the number keys or by
-- tapping it. While you hold one, a "Drop axe" side button shows
-- (Backspace on a keyboard, X on a gamepad when no prompt is showing). The
-- server lays it on the ground, where a "Pick up" prompt brings it back.
-- Dropped axes stay yours (AxeService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local AxeController = {}

local player = Players.LocalPlayer

local button: UITheme.Button? = nil

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
		b.root.Visible = heldAxe() ~= nil
	end
end

local function watchCharacter(char: Model)
	char.ChildAdded:Connect(refresh)
	char.ChildRemoved:Connect(refresh)
	refresh()
end

function AxeController.Start()
	button = HUD.SideButton({
		name = "DropAxe",
		text = "Drop axe",
		style = "bark",
		order = 3,
		key = Enum.KeyCode.ButtonX,
		onPress = dropHeld,
	})

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
