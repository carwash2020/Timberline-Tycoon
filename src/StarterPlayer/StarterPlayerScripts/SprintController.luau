--!strict
-- SprintController: hold Shift (keyboard) or L1 (gamepad) to run. It only
-- sends the intent; the server sets the speed (BiomeService). Read through
-- UserInputService state and InputBegan/Ended with no action bound, so no
-- other control loses a button; a text box in use or a menu isn't a run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local SprintController = {}

local RUN_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.ButtonL1] = true,
}

function SprintController.Start()
	local remote = Net.Remote("Sprint")
	local sent = false

	local function send(on: boolean)
		if on ~= sent then
			sent = on
			remote:FireServer(on)
		end
	end

	local function held(): boolean
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if RUN_KEYS[input.KeyCode] and UserInputService:GetFocusedTextBox() == nil then
			send(held())
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if RUN_KEYS[input.KeyCode] then
			send(held())
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		send(false)
	end)
end

return SprintController
