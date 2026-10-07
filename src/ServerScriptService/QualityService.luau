--!strict
-- QualityService: the player's Lower / Higher graphics choice
-- (Shared/QualityProfile, saved as profile.settings.quality, mirrored on the
-- SettingQuality player attribute). One remote, SetQuality(choice), fired by
-- the join screen (QualityPickerUI) and the Settings row; the server
--   * rate limits it (RateLimiter "SetQuality": two a second),
--   * needs a loaded save (a choice sent before it is dropped, never saved
--     onto nothing),
--   * accepts only "low" or "high" (SettingsLogic.Set: anything else, "unset"
--     included, is refused and the save is untouched),
--   * writes the account's setting (it is account-wide: a slot swap keeps it)
--     and mirrors the attribute the client reads.
-- The choice changes how much dressing a client builds and draws, never
-- gameplay, so nothing else reads it on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local QualityService = {}

QualityService.Attribute = SettingsLogic.QualityAttribute

-- The choice a player fired. True when it was saved.
function QualityService.Set(player: Player, value: unknown): boolean
	if not RateLimiter.Allow(player, "SetQuality") then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	if profile == nil then
		return false
	end
	if not SettingsLogic.Set(profile.settings, "quality", value) then
		return false
	end
	player:SetAttribute(QualityService.Attribute, profile.settings.quality)
	return true
end

return QualityService
