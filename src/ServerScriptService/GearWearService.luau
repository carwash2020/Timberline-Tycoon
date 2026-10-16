--!strict
-- GearWearService: puts the gear a player owns on their character as visual
-- meshes (Art/GearWear): on spawn, and again when OwnedGear changes (ShopService
-- and RegionService set it). Visual only: no Tool, nothing to grab, no gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearWear = require(ReplicatedStorage.Shared.Art.GearWear)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)

local GearWearService = {}

local function refresh(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local owned = ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")
	GearWear.Refresh(character, owned)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		-- The R15 parts arrive with the character; wait for the last one.
		character:WaitForChild("LowerTorso", 10)
		character:WaitForChild("Head", 10)
		refresh(player)
	end)
	player:GetAttributeChangedSignal("OwnedGear"):Connect(function()
		refresh(player)
	end)
	if player.Character then
		task.spawn(refresh, player)
	end
end

function GearWearService.Init()
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
end

return GearWearService
