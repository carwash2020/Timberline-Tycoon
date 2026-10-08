--!strict
-- NewsService: the "What's new" flag. The client asks once (NewsSeen);
-- the save already has onboarding, so this only sets onboarding["News:V1"].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NewsLogic = require(ReplicatedStorage.Shared.NewsLogic)
local ProfileService = require(script.Parent.ProfileService)

local NewsService = {}

local ATTRIBUTE = "NewsV1Seen"

type Save = {
	onboarding: { [string]: boolean }?,
}

local function book(profile: Save): { [string]: boolean }
	if type(profile.onboarding) ~= "table" then
		profile.onboarding = {}
	end
	return profile.onboarding :: { [string]: boolean }
end

function NewsService.Start(player: Player, profile: Save)
	local seen = book(profile)[NewsLogic.Key] == true
	player:SetAttribute(ATTRIBUTE, seen)
end

function NewsService.Seen(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	NewsLogic.Mark(book(profile))
	player:SetAttribute(ATTRIBUTE, true)
end

-- Drop the attribute when they leave so a reused player in tests stays clean.
Players.PlayerRemoving:Connect(function(player: Player)
	player:SetAttribute(ATTRIBUTE, nil)
end)

return NewsService
