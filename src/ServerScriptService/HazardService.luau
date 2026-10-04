--!strict
-- HazardService: deep water at the map edge. Frost and the volcano drain
-- stay with their own batches. No remote. Init starts the tick.

local RunService = game:GetService("RunService")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local WorldLayout = require(game:GetService("ReplicatedStorage").Shared.World.WorldLayout)

local HazardService = {}

local elapsed = 0

function HazardService.Step(dt: number)
	elapsed += dt
	if elapsed < GameConfig.WaterTickSec then
		return
	end
	elapsed = 0
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local pos = root.Position
			if WorldLayout.InDeepSea(pos.X, pos.Z) then
				humanoid:TakeDamage(GameConfig.WaterDamage)
			end
		end
	end
end

function HazardService.Init()
	pcall(function()
		RunService.Heartbeat:Connect(function(dt: number)
			local ok, err = pcall(function()
				HazardService.Step(dt)
			end)
			if not ok then
				warn("[HazardService] " .. tostring(err))
			end
		end)
	end)
end

return HazardService
