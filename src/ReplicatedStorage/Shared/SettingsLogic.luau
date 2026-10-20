--!strict
-- SettingsLogic: the Settings menu's saved values. Pure, so the server
-- can reject a bad SaveSetting and the client can show the same choices.
-- Missing keys (saves from before a setting existed) come back as the
-- default. Volumes are 0 to 1. Enums are the names below, nothing else.

local SettingsLogic = {}

-- The Settings card. "visitors" is the plot permission list, "board"
-- the opt-in lifetime-earnings leaderboard and "codes" the redeem box. B on either tab returns to
-- "game"; B again closes the card.
SettingsLogic.Tabs = { "game", "visitors", "board", "report", "codes" }

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
	cameraSensitivity: number, -- 0.25 to 2, 1 = the device's own camera speed (SettingsLogic.Sensitivity)
	uiScale: UIScale,
	showTips: boolean,
	reduceFlashing: boolean, -- softens full-screen flashes (lightning); also in force while cameraShake is off (SettingsLogic.ReduceFlashing)
	showOnBoard: boolean, -- opt-in: submit lifetime earnings to the leaderboard (off until the player says so)
	uiScaleMigratedV1: boolean, -- the one-time move of every profile to the Small UI scale (Sanitize); true once done
}

export type Key =
	"music"
	| "sfx"
	| "musicVolume"
	| "sfxVolume"
	| "graphics"
	| "quality"
	| "cameraShake"
	| "cameraSensitivity"
	| "uiScale"
	| "showTips"
	| "reduceFlashing"
	| "showOnBoard"

SettingsLogic.Defaults = {
	music = true,
	sfx = true,
	musicVolume = 1,
	sfxVolume = 1,
	graphics = "auto" :: Graphics,
	quality = "unset" :: Quality,
	cameraShake = true,
	cameraSensitivity = 1,
	uiScale = "small" :: UIScale,
	showTips = true,
	reduceFlashing = false,
	showOnBoard = false,
	uiScaleMigratedV1 = false,
} :: Settings

-- The attribute for the Lower / Higher quality choice on its own (QualityProfile).
SettingsLogic.QualityAttribute = "SettingQuality"

-- The attribute for showOnBoard on its own, for the Leaderboard tab.
SettingsLogic.BoardAttribute = "SettingShowOnBoard"

-- The attribute for reduceFlashing on its own (SettingsUI, LightingController).
SettingsLogic.ReduceFlashingAttribute = "SettingReduceFlashing"

-- Player attributes the server mirrors so the client applies them on join.
SettingsLogic.Attributes = {
	music = "SettingMusic",
	sfx = "SettingSfx",
	musicVolume = "SettingMusicVolume",
	sfxVolume = "SettingSfxVolume",
	graphics = "SettingGraphics",
	quality = SettingsLogic.QualityAttribute,
	cameraShake = "SettingCameraShake",
	cameraSensitivity = "SettingCameraSensitivity",
	uiScale = "SettingUIScale",
	showTips = "SettingShowTips",
	reduceFlashing = SettingsLogic.ReduceFlashingAttribute,
	showOnBoard = SettingsLogic.BoardAttribute,
} :: { [Key]: string }

local GRAPHICS: { [string]: boolean } = { auto = true, low = true, medium = true, high = true }
local SCALES: { [string]: boolean } = { small = true, normal = true, large = true }
local QUALITIES: { [string]: boolean } = { unset = true, low = true, high = true }

-- Camera sensitivity: a multiplier on the device's own camera speed. The
-- Settings row steps through Steps; the server clamps whatever it is sent.
SettingsLogic.Sensitivity = { min = 0.25, max = 2, step = 0.25 }

local function sensitivity(n: unknown, fallback: number): number
	if type(n) ~= "number" or n ~= n then
		return fallback
	end
	return math.clamp(n, SettingsLogic.Sensitivity.min, SettingsLogic.Sensitivity.max)
end

-- The next Settings step: up by one step, back to the lowest after the highest.
function SettingsLogic.NextSensitivity(current: number): number
	local r = SettingsLogic.Sensitivity
	local nextValue = math.floor(sensitivity(current, 1) / r.step + 0.5) * r.step + r.step
	if nextValue > r.max + 1e-9 then
		return r.min
	end
	return nextValue
end

-- The camera speed to write when the device's own is `base`.
function SettingsLogic.ApplySensitivity(base: number, multiplier: unknown): number
	return base * sensitivity(multiplier, 1)
end

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
	-- One-time migration: Small became the default, so a profile that has not
	-- been moved yet goes to Small whatever it had. The flag is then set, so a
	-- later choice (Normal or Large) sticks. A new profile arrives here with
	-- no flag and gets Small and the flag the same way.
	local migrated = s.uiScaleMigratedV1 == true
	if not migrated then
		ui = "small"
		migrated = true
	end
	return {
		music = if s.music == nil then d.music else s.music == true,
		sfx = if s.sfx == nil then d.sfx else s.sfx == true,
		musicVolume = volume(s.musicVolume, d.musicVolume),
		cameraSensitivity = sensitivity(s.cameraSensitivity, d.cameraSensitivity),
		sfxVolume = volume(s.sfxVolume, d.sfxVolume),
		graphics = graphics :: Graphics,
		quality = quality :: Quality,
		cameraShake = if s.cameraShake == nil then d.cameraShake else s.cameraShake == true,
		uiScale = ui :: UIScale,
		showTips = if s.showTips == nil then d.showTips else s.showTips == true,
		-- Only a real `true` turns it on; a missing or odd value is off.
		reduceFlashing = s.reduceFlashing == true,
		-- Only a real `true` opts in; a missing or odd value is off.
		showOnBoard = s.showOnBoard == true,
		uiScaleMigratedV1 = migrated,
	}
end

-- Writes one key if `value` is legal for it. False leaves `settings` as it was.
function SettingsLogic.Set(settings: Settings, key: string, value: unknown): boolean
	if
		key == "music"
		or key == "sfx"
		or key == "cameraShake"
		or key == "showTips"
		or key == "showOnBoard"
		or key == "reduceFlashing"
	then
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
		elseif key == "reduceFlashing" then
			settings.reduceFlashing = value
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
	elseif key == "cameraSensitivity" then
		-- A real number is clamped into range; anything else (NaN, a string) is refused.
		if type(value) ~= "number" or value ~= value then
			return false
		end
		settings.cameraSensitivity = sensitivity(value, 1)
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

-- The TIPS setting: whether tips (the bottom hint bar, once-a-session tip
-- toasts, the first-cold/heat tip) show. `setting` is the SettingShowTips
-- attribute or the saved value as read: only a real `false` turns tips off
-- (nil, a missing key or odd data keeps the default, on). `step` is the
-- TutorialStep attribute as read: while a tutorial step runs (a number
-- above 0) tips stay on whatever the setting says, because the hint bar and
-- the "put your axe away" toast carry lessons the step needs. Murph's own
-- card never depends on this (QuestUI does not read the setting).
function SettingsLogic.TipsShown(setting: unknown, step: unknown): boolean
	if setting ~= false then
		return true
	end
	return type(step) == "number" and step == step and step >= 1
end

-- Reduce flashing. In force when the player turned it on, or while camera
-- shake is off (the same "calm the screen" choice: shake only switches off
-- when the attribute is exactly false, as in SettingsUI). Takes the two
-- attribute values as read, so a missing one means the default (off / on).
function SettingsLogic.ReduceFlashing(reduceAttr: unknown, shakeAttr: unknown): boolean
	return reduceAttr == true or shakeAttr == false
end

-- One full-screen flash (LightingController.Flash) as it should play.
-- Normal: unchanged. Reduced: a flash that starts after the first one is
-- dropped (no rapid pair), and the first is a quarter as bright and held
-- longer, so it is a soft pulse and never a strobe. Returns nil to skip it, else the amount and duration to use.
SettingsLogic.ReducedFlashScale = 0.25
SettingsLogic.ReducedFlashSeconds = 0.35
function SettingsLogic.SoftenFlash(
	reduce: boolean,
	amount: number,
	duration: number,
	delay: number?
): { amount: number, duration: number }?
	if not reduce then
		return { amount = amount, duration = duration }
	end
	if (delay or 0) > 0 then
		return nil
	end
	return {
		amount = amount * SettingsLogic.ReducedFlashScale,
		duration = math.max(duration, SettingsLogic.ReducedFlashSeconds),
	}
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

-- Text and touch floors for every UI scale. A scaled size is clamped UP to
-- its floor and never shrunk below it; a touch button is at least TouchMin on
-- both sides, TouchGap from the next one and SafeEdge from the safe edge.
SettingsLogic.TextFloorBody = 14
SettingsLogic.TextFloorTitle = 20
SettingsLogic.TouchMin = 44
SettingsLogic.TouchGap = 8
SettingsLogic.SafeEdge = 12

-- `size` times `multiplier` (a ScaleMultiplier, 1 when omitted), but never
-- under `floor`. ClampText(16, 14, 0.85) is 14; ClampText(24, 20, 0.85) is 20.4.
function SettingsLogic.ClampText(size: number, floor: number, multiplier: number?): number
	return math.max(size * (multiplier or 1), floor)
end

-- RESTART SAVE (Settings, Game tab). It wipes the save you are playing back
-- to a brand-new game (the old REDO button on the SAVES list, moved here at
-- Connor's request, 8 October 2026). The server does the real work through
-- the same SlotAction remote: "arm", then "reset" within seconds, behind the
-- save-slot cooldown and RateLimiter. This only says what the row shows.
SettingsLogic.RestartArmSeconds = 5
SettingsLogic.RestartConfirm =
	"Restart this save? Cash, wood, axes you bought, bases and the plot on it are wiped. Robux purchases stay. Press again to confirm."

export type RestartRow = { text: string, enabled: boolean }

-- activeSlot: the ActiveSlot attribute (nil until a save is loaded);
-- picking: the join save picker is still up (no save chosen yet);
-- cooldownUntil: SlotCooldownUntil (unix); armed: pressed once, waiting for the second press.
function SettingsLogic.RestartRow(
	activeSlot: unknown,
	picking: boolean,
	cooldownUntil: unknown,
	now: number,
	armed: boolean
): RestartRow
	if type(activeSlot) ~= "number" or activeSlot < 1 or picking then
		return { text = "RESTART SAVE (pick a save first)", enabled = false }
	end
	if type(cooldownUntil) == "number" and now < cooldownUntil then
		return { text = string.format("RESTART SAVE (in %ds)", math.ceil(cooldownUntil - now)), enabled = false }
	end
	if armed then
		return { text = "PRESS AGAIN: WIPE SAVE " .. tostring(activeSlot), enabled = true }
	end
	return { text = "RESTART SAVE " .. tostring(activeSlot), enabled = true }
end

return SettingsLogic
