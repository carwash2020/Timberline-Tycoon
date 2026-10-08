--!strict
-- SecretService: the server notices a player standing in a secret.
-- No client remote. Pay once per slot through EconomyService.
-- A1 adds this name to V1Boot and the secrets field. Until then MapBuilder
-- calls V1Init, and a second call does nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local WorldClock = require(script.Parent.WorldClock)
local SecretLogic = require(ReplicatedStorage.Shared.SecretLogic)
local UndergroundData = require(ReplicatedStorage.Shared.World.UndergroundData)

local SecretService = {}

local started = false

local function sweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local profile = ProfileService.GetProfile(player)
			if profile then
				local gear = if type(profile.gear) == "table" then profile.gear else {}
				local night = WorldClock.IsNight()
				local at = root.Position
				for _, secret in ipairs(UndergroundData.Secrets) do
					if SecretLogic.CanFind(profile, secret.id, at.X, at.Z, night, gear) then
						local pay = SecretLogic.Claim(profile, secret.id)
						if pay > 0 then
							EconomyService.AddCash(player, pay, "secret")
						end
					end
				end
			end
		end
	end
end

function SecretService.V1Init()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while started do
			task.wait(2)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[SecretService] " .. tostring(err))
			end
		end
	end)
end

return SecretService
