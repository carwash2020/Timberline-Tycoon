-- CarryController: client-side carry / sell UX.
-- The server does all the carrying work (welds, capacity, selling).
-- This controller just fires intents: E loads carried logs to your truck,
-- Q sells everything (hands + truck bed) at the sawmill.
-- ProximityPrompts on logs handle pickup; the server validates ownership,
-- range, and hand capacity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CarryController = {}

local player = Players.LocalPlayer

local remotes: Folder? = nil

local function getRemotes(): Folder
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes")
	end
	return remotes :: Folder
end

function CarryController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			getRemotes().LoadToTruck:FireServer()
		elseif input.KeyCode == Enum.KeyCode.Q then
			getRemotes().SellLogs:FireServer()
		end
	end)
end

return CarryController
