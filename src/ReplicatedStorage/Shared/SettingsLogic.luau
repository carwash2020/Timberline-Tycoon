--!strict
-- SettingsLogic: the Settings menu's saved values. Pure, so the server
-- can reject a bad SaveSetting and the client can show the same choices.
-- Missing keys (saves from before a setting existed) come back as the
-- default. Volumes are 0 to 1. Enums are the names below, nothing else.

local SettingsLogic = {}

-- The Settings card. "visitors" is the plot permission list and "board"
-- the opt-in lifetime-earnings leaderboard. B on either tab returns to
-- "game"; B again closes the card.
SettingsLogic.Tabs = { "game", "visitors", "board" }

function SettingsLogic.HasTab(name: string): boolean
	return table.find(SettingsLogic.Tabs, name) ~= nil
end

export type Graphics = "auto" | "low" | "medium" | "high"
export type UIScale = "small" | "normal" | "large"
-- The player's graphics choice (Shared/QualityProfile): "unset" until they
-- pick on the join screen (so an old save is asked once), then "low" or "high".
export type Quality = "unset" | "low" | "high"

export type Settings = {
	music: boolean,
	sfx: boolean,
	musicVolume: number,
	sfxVolume: number,
	graphics: Graphics, -- the old four-way tier override: kept so old saves load, no longer shown or used (quality replaced it)
	quality: Quality,
	cameraShake: boolean,
	uiScale: UIScale,
	showTips: boolean,
	showOnBoard: boolean, -- opt-in: submit lifetime earnings to the leaderboard (off until the player says so)
}

export type Key =
	"music"
	| "sfx"
	| "musicVolume"
	| "sfxVolume"
	| "graphics"
	| "quality"
	| "cameraShake"
	| "uiScale"
	| "showTips"
	| "showOnBoard"

SettingsLogic.Defaults = {
	music = true,
	sfx = true,
	musicVolume = 1,
	sfxVolume = 1,
	graphics = "auto" :: Graphics,
	quality = "unset" :: Quality,
	cameraShake = true,
	uiScale = "normal" :: UIScale,
	showTips = true,
	showOnBoard = false,
} :: Settings

-- The attribute for the Lower / Higher quality choice on its own (QualityProfile).
SettingsLogic.QualityAttribute = "SettingQuality"

-- The attribute for showOnBoard on its own, for the Leaderboard tab.
SettingsLogic.BoardAttribute = "SettingShowOnBoard"

-- Player attributes the server mirrors so the client applies them on join.
SettingsLogic.Attributes = {
	music = "SettingMusic",
	sfx = "SettingSfx",
	musicVolume = "SettingMusicVolume",
	sfxVolume = "SettingSfxVolume",
	graphics = "SettingGraphics",
	quality = SettingsLogic.QualityAttribute,
	cameraShake = "SettingCameraShake",
	uiScale = "SettingUIScale",
	showTips = "SettingShowTips",
	showOnBoard = SettingsLogic.BoardAttribute,
} :: { [Key]: string }

local GRAPHICS: { [string]: boolean } = { auto = true, low = true, medium = true, high = true }
local SCALES: { [string]: boolean } = { small = true, normal = true, large = true }
local QUALITIES: { [string]: boolean } = { unset = true, low = true, high = true }

local function volume(n: unknown, fallback: number): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n < 0 or n > 1 then
		return fallback
	end
	return n
end

-- A full settings table from a save (or anything else). Never shares
-- Defaults, so a later edit can't change what new players start with.
function SettingsLogic.Sanitize(raw: any): Settings
	local d = SettingsLogic.Defaults
	local s = if type(raw) == "table" then raw else {}
	local graphics = s.graphics
	if type(graphics) ~= "string" or not GRAPHICS[graphics] then
		graphics = d.graphics
	end
	local ui = s.uiScale
	if type(ui) ~= "string" or not SCALES[ui] then
		ui = d.uiScale
	end
	-- Anything but a real choice (a save from before the picker, a bad value) is
	-- "unset": the join screen asks once.
	local quality = s.quality
	if type(quality) ~= "string" or not QUALITIES[quality] then
		quality = d.quality
	end
	return {
		music = if s.music == nil then d.music else s.music == true,
		sfx = if s.sfx == nil then d.sfx else s.sfx == true,
		musicVolume = volume(s.musicVolume, d.musicVolume),
		sfxVolume = volume(s.sfxVolume, d.sfxVolume),
		graphics = graphics :: Graphics,
		quality = quality :: Quality,
		cameraShake = if s.cameraShake == nil then d.cameraShake else s.cameraShake == true,
		uiScale = ui :: UIScale,
		showTips = if s.showTips == nil then d.showTips else s.showTips == true,
		-- Only a real `true` opts in; a missing or odd value is off.
		showOnBoard = s.showOnBoard == true,
	}
end

-- Writes one key if `value` is legal for it. False leaves `settings` as it was.
function SettingsLogic.Set(settings: Settings, key: string, value: unknown): boolean
	if key == "music" or key == "sfx" or key == "cameraShake" or key == "showTips" or key == "showOnBoard" then
		if type(value) ~= "boolean" then
			return false
		end
		if key == "music" then
			settings.music = value
		elseif key == "sfx" then
			settings.sfx = value
		elseif key == "cameraShake" then
			settings.cameraShake = value
		elseif key == "showTips" then
			settings.showTips = value
		else
			settings.showOnBoard = value
		end
		return true
	elseif key == "musicVolume" or key == "sfxVolume" then
		if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
			return false
		end
		if key == "musicVolume" then
			settings.musicVolume = value
		else
			settings.sfxVolume = value
		end
		return true
	elseif key == "graphics" then
		if type(value) ~= "string" or not GRAPHICS[value] then
			return false
		end
		settings.graphics = value :: Graphics
		return true
	elseif key == "quality" then
		-- A player only ever CHOOSES low or high. "unset" is what the save starts as.
		if value ~= "low" and value ~= "high" then
			return false
		end
		settings.quality = value :: Quality
		return true
	elseif key == "uiScale" then
		if type(value) ~= "string" or not SCALES[value] then
			return false
		end
		settings.uiScale = value :: UIScale
		return true
	end
	return false
end

-- How much UITheme multiplies its screen scale for this choice.
function SettingsLogic.ScaleMultiplier(uiScale: string): number
	if uiScale == "small" then
		return 0.85
	elseif uiScale == "large" then
		return 1.15
	end
	return 1
end

return SettingsLogic
