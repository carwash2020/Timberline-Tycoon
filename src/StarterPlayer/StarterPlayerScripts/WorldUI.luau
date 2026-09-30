--!strict
-- WorldUI: the world, client side.
--   * Entering a biome names it and its woods, and warns about missing gear
--     ("It's cold here: you walk slower without an Insulated Coat").
--   * A clock next to the cash: "Day 14:05" / "Night 22:10" (night is when
--     the Phantom Grove's trees come out).
-- The server sets the Biome and OwnedGear attributes; the time of day is
-- Lighting.ClockTime, set by WorldClock.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local HUD = require(script.Parent.HUD)

local WorldUI = {}

local player = Players.LocalPlayer

local function woodsOf(biome: BiomeData.BiomeDef): string
	local names: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		if (biome.trees or {})[wood.id] then
			table.insert(names, string.lower(wood.displayName))
		end
	end
	return table.concat(names, ", ")
end

local function gearName(id: string): string
	local gear = ItemCatalog.GetGear(id)
	return if gear then gear.displayName else id
end

local function onBiomeChanged()
	local biome = BiomeData.Get((player:GetAttribute("Biome") :: string?) or "")
	if not biome then
		return
	end
	HUD.Toast(string.format("%s · %s", biome.displayName, woodsOf(biome)))
	local gear = ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")
	local rules = BiomeData.Rules(biome, gear)
	if rules.speedFactor < 1 and biome.slowdown then
		HUD.Toast(string.format("It's cold here: you walk slower without an %s.", gearName(biome.slowdown.removedBy)))
	end
	if rules.needs and not rules.burning then
		HUD.Toast(string.format("Too dark to chop here without a %s (Hearth & Home).", gearName(rules.needs)))
	end
	if biome.nightOnly and not WorldTime.IsNight(Lighting.ClockTime) then
		HUD.Toast("Nothing grows here by day. Come back at night.")
	end
end

local function buildClock()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldClock"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Clock"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -222, 0, 18) -- left of the cash plaque
	label.Size = UDim2.fromOffset(100, 30)
	label.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(245, 235, 215)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		local clock = Lighting.ClockTime
		label.Text =
			string.format("%s %s", if WorldTime.IsNight(clock) then "Night" else "Day", WorldTime.Format(clock))
	end
	refresh()
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(refresh)
end

function WorldUI.Start()
	buildClock()
	player:GetAttributeChangedSignal("Biome"):Connect(onBiomeChanged)
end

return WorldUI
