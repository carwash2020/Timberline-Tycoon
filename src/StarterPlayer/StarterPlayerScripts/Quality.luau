--!strict
-- Quality (PLAY-05): which Shared/QualityBudgets tier this device gets.
-- Cosmetic loops read Quality.Budget() (a cached table) and run on its
-- CosmeticHz: every frame on high, slower on medium, nearly off on low.
--   * "low" when the player's graphics quality (Roblox menu > Settings >
--     Graphics Quality: UserGameSettings.SavedQualityLevel) is 1 to 4, or
--     Automatic on a touch-only device (a phone or tablet with no
--     keyboard). "medium" at levels 5-7. "high" at 8-10, and Automatic
--     on anything that isn't touch-only (QualityBudgets.TierFor).
--   * Re-read when the setting changes (its changed signal) and every
--     couple of seconds anyway (a keyboard plugged in, or a signal that
--     never fires), so the effects follow the slider.
--   * Works before Start: the first Budget() reads the setting.
--   * Prints the tier when it's first read and whenever it changes, e.g.
--     "[Quality] low (QualityLevel3)".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)

local Quality = {}

local POLL_EVERY = 2 -- seconds

local budget: QualityBudgets.Budget? = nil
-- Settings override. nil (or "auto") follows the device.
local override: QualityBudgets.Tier? = nil

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

local function refresh(): QualityBudgets.Budget
	local level = savedLevel()
	local touch = touchOnly()
	local tier = override or QualityBudgets.TierFor(level, touch)
	local now = QualityBudgets.For(tier)
	pcall(applyGlint, now.Tier)
	if now ~= budget then
		budget = now
		print(
			string.format(
				"[Quality] %s (%s%s)",
				now.Tier,
				level or "level unreadable",
				if touch then ", touch only" else ""
			)
		)
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

-- "auto" follows the device again. "low" | "medium" | "high" force that tier.
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
	task.spawn(function()
		while true do
			task.wait(POLL_EVERY)
			refresh()
		end
	end)
end

return Quality
