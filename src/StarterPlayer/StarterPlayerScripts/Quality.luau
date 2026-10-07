--!strict
-- Quality (PLAY-05): which Shared/QualityBudgets tier this device gets.
-- Cosmetic loops read Quality.Budget() (a cached table) and run on its
-- CosmeticHz: every frame on high, slower on medium, nearly off on low.
--   * "low" when the player's graphics quality (Roblox menu > Settings >
--     Graphics Quality: UserGameSettings.SavedQualityLevel) is 1 to 4, or
--     Automatic on a touch-only device (a phone or tablet with no
--     keyboard). "medium" at levels 5-7. "high" at 8-10, and Automatic
--     on anything that isn't touch-only (QualityBudgets.TierFor).
--   * The player's own choice (Lower or Higher quality, saved on the account,
--     asked on the join screen, QualityPickerUI) caps it: Lower is always
--     "low"; Higher is the device's tier, and a device that reports "low" gets
--     "medium" (the high world, calm motion). Shared/QualityProfile.TierFor
--     is the rule; the Roblox graphics level and touch detection above are
--     still what the device reports. Until the player has chosen, the device's
--     tier is used as before.
--   * Re-read when the setting changes (its changed signal) and every
--     couple of seconds anyway (a keyboard plugged in, or a signal that
--     never fires), so the effects follow the slider.
--   * Works before Start: the first Budget() reads the setting.
--   * Prints the tier when it's first read and whenever it changes, e.g.
--     "[Quality] low (QualityLevel3)" (", chose low" once the player has picked).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local QualityProfile = require(ReplicatedStorage.Shared.QualityProfile)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)

local Quality = {}

local POLL_EVERY = 2 -- seconds

local budget: QualityBudgets.Budget? = nil
-- A forced tier (a test or a developer tool). nil follows the player's choice and the device.
local override: QualityBudgets.Tier? = nil
local changed: { (QualityBudgets.Budget) -> () } = {}

local function applyGlint(tier: string)
	local rate = QualityBudgets.GlintRate(tier)
	local function visit(root: Instance)
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "Glint" and d:IsA("ParticleEmitter") then
				d.Rate = rate
				d.Enabled = rate > 0
			end
		end
	end
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		return
	end
	if player.Character then
		visit(player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		visit(backpack)
	end
end

-- The player's saved graphics level by name ("Automatic", "QualityLevel3"),
-- or nil if it can't be read.
local function savedLevel(): string?
	local ok, name = pcall(function(): string
		return UserSettings().GameSettings.SavedQualityLevel.Name
	end)
	return if ok and type(name) == "string" then name else nil
end

-- A touch screen with no keyboard: a phone, or a tablet without one.
local function touchOnly(): boolean
	local ok, result = pcall(function(): boolean
		local input = game:GetService("UserInputService")
		return input.TouchEnabled and not input.KeyboardEnabled
	end)
	return ok and result == true
end

-- The player's saved choice ("low", "high", or "unset" until they pick),
-- mirrored on their SettingQuality attribute by the server.
local function savedChoice(): string
	local ok, value = pcall(function(): any
		local player = game:GetService("Players").LocalPlayer
		return if player then player:GetAttribute(SettingsLogic.QualityAttribute) else nil
	end)
	return if ok then QualityProfile.Sanitize(value) else "unset"
end

local function refresh(): QualityBudgets.Budget
	local level = savedLevel()
	local touch = touchOnly()
	local saved = savedChoice()
	local device = QualityBudgets.TierFor(level, touch)
	local tier = override or QualityProfile.TierFor(saved, device)
	local now = QualityBudgets.For(tier)
	pcall(applyGlint, now.Tier)
	if now ~= budget then
		budget = now
		print(
			string.format(
				"[Quality] %s (%s%s%s)",
				now.Tier,
				level or "level unreadable",
				if touch then ", touch only" else "",
				if saved == "unset" then "" else ", chose " .. saved
			)
		)
		for _, fn in ipairs(changed) do
			local okFn, err = pcall(function(): any
				fn(now)
				return nil
			end)
			if not okFn then
				warn("[Quality] a listener failed: " .. tostring(err))
			end
		end
	end
	return now
end

-- This device's budgets (QualityBudgets.High or QualityBudgets.Low).
function Quality.Budget(): QualityBudgets.Budget
	return budget or refresh()
end

function Quality.Tier(): QualityBudgets.Tier
	return Quality.Budget().Tier
end

-- A touch screen with no keyboard (a phone, or a tablet without one): the device
-- the join screen recommends Lower quality for.
function Quality.TouchOnly(): boolean
	return touchOnly()
end

-- Runs `fn` with the new budget whenever the tier changes (the player's choice, the
-- Roblox graphics setting), after the tier it has now.
function Quality.OnChange(fn: (QualityBudgets.Budget) -> ())
	table.insert(changed, fn)
end

-- Re-reads the choice and the device now (the picker and the Settings row call it
-- the moment they save, so the world follows at once).
function Quality.Refresh(): QualityBudgets.Budget
	return refresh()
end

-- "auto" follows the player's choice and the device again. "low" | "medium" | "high" force that tier.
function Quality.SetOverride(mode: string)
	if mode == "low" or mode == "medium" or mode == "high" then
		override = mode
	else
		override = nil
	end
	refresh()
end

function Quality.Start()
	refresh()
	local ok, err = pcall(function(): any
		UserSettings().GameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
			refresh()
		end)
		return nil
	end)
	if not ok then
		warn("[Quality] can't watch the graphics setting (polling it instead): " .. tostring(err))
	end
	pcall(function(): any
		local player = game:GetService("Players").LocalPlayer
		if player then
			player:GetAttributeChangedSignal(SettingsLogic.QualityAttribute):Connect(function()
				refresh()
			end)
		end
		return nil
	end)
	task.spawn(function()
		while true do
			task.wait(POLL_EVERY)
			refresh()
		end
	end)
end

return Quality
