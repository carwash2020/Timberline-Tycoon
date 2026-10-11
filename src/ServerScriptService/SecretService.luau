--!strict
-- SecretService: the server notices a player standing in a secret.
-- No client remote. Pay once per slot through EconomyService.
-- MapBuilder calls V1Init after the underground is built; a second call
-- does nothing. V1Boot lists the name but calls only Init or Start, so it
-- does not start a second loop.

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
			local ok, err = pcall(function(): any
				sweep()
				return nil
			end)
			if not ok then
				warn("[SecretService] " .. tostring(err))
			end
		end
	end)
end

return SecretService
