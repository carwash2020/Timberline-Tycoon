--!strict
-- SettingsLogic: the Settings menu's saved values. Pure, so the server
-- can reject a bad SaveSetting and the client can show the same choices.
-- Missing keys (saves from before a setting existed) come back as the
-- default. Volumes are 0 to 1. Enums are the names below, nothing else.

local SettingsLogic = {}

export type Graphics = "auto" | "low" | "medium" | "high"
export type UIScale = "small" | "normal" | "large"

export type Settings = {
	music: boolean,
	sfx: boolean,
	musicVolume: number,
	sfxVolume: number,
	graphics: Graphics,
	cameraShake: boolean,
	uiScale: UIScale,
	showTips: boolean,
}

export type Key = "music" | "sfx" | "musicVolume" | "sfxVolume" | "graphics" | "cameraShake" | "uiScale" | "showTips"

SettingsLogic.Defaults = {
	music = true,
	sfx = true,
	musicVolume = 1,
	sfxVolume = 1,
	graphics = "auto" :: Graphics,
	cameraShake = true,
	uiScale = "normal" :: UIScale,
	showTips = true,
} :: Settings

-- Player attributes the server mirrors so the client applies them on join.
SettingsLogic.Attributes = {
	music = "SettingMusic",
	sfx = "SettingSfx",
	musicVolume = "SettingMusicVolume",
	sfxVolume = "SettingSfxVolume",
	graphics = "SettingGraphics",
	cameraShake = "SettingCameraShake",
	uiScale = "SettingUIScale",
	showTips = "SettingShowTips",
} :: { [Key]: string }

local GRAPHICS: { [string]: boolean } = { auto = true, low = true, medium = true, high = true }
local SCALES: { [string]: boolean } = { small = true, normal = true, large = true }

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
	return {
		music = if s.music == nil then d.music else s.music == true,
		sfx = if s.sfx == nil then d.sfx else s.sfx == true,
		musicVolume = volume(s.musicVolume, d.musicVolume),
		sfxVolume = volume(s.sfxVolume, d.sfxVolume),
		graphics = graphics :: Graphics,
		cameraShake = if s.cameraShake == nil then d.cameraShake else s.cameraShake == true,
		uiScale = ui :: UIScale,
		showTips = if s.showTips == nil then d.showTips else s.showTips == true,
	}
end

-- Writes one key if `value` is legal for it. False leaves `settings` as it was.
function SettingsLogic.Set(settings: Settings, key: string, value: unknown): boolean
	if key == "music" or key == "sfx" or key == "cameraShake" or key == "showTips" then
		if type(value) ~= "boolean" then
			return false
		end
		if key == "music" then
			settings.music = value
		elseif key == "sfx" then
			settings.sfx = value
		elseif key == "cameraShake" then
			settings.cameraShake = value
		else
			settings.showTips = value
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
