--!strict
-- WorldUI: the world, client side.
--   * Entering a biome names it and its woods, and warns about missing gear
--     ("It's cold here: you walk slower without an Insulated Coat").
--   * A clock next to the cash: "Day 14:05" / "Night 22:10" (night is when
--     the Phantom Grove's trees come out).
--   * The Sky Bin by the sell pad shows your own count ("SKY BIN 12/30").
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
local UITheme = require(script.Parent.UITheme)

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
	local gui = UITheme.Screen("WorldClock")
	local label = UITheme.label(gui, "", UITheme.Fonts.Black, 13, UITheme.Colors.Cream)
	label.Name = "Clock"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -(UITheme.Margin() + 210), 0, 15) -- left of the cash plaque
	label.Size = UDim2.fromOffset(100, 30)
	label.BackgroundColor3 = UITheme.Colors.Bark
	label.BackgroundTransparency = 0
	label.TextXAlignment = Enum.TextXAlignment.Center
	UITheme.corner(label, 15)
	UITheme.stroke(label, UITheme.Colors.Ink, 2)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		local clock = Lighting.ClockTime
		label.Text =
			string.format("%s %s", if WorldTime.IsNight(clock) then "Night" else "Day", WorldTime.Format(clock))
	end
	refresh()
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(refresh)
end

-- The Sky Bin by the sell pad shows this player's own count.
local function watchSkyBin()
	local map = workspace:WaitForChild("TimberlineMap")
	local area = map:WaitForChild("SellArea") -- Persistent: always streamed in
	local bin = area:WaitForChild("SkyBin", 30)
	if not bin then
		return
	end
	local labels: { TextLabel } = {}
	for _, gui in ipairs(bin:GetChildren()) do
		local label = if gui:IsA("SurfaceGui") then gui:FindFirstChildOfClass("TextLabel") else nil
		if label then
			table.insert(labels, label)
		end
	end
	local sky = BiomeData.Get("sky")
	local capacity = if sky then sky.skyBinCapacity or 30 else 30
	local function refresh()
		local n = (player:GetAttribute("SkyBin") :: number?) or 0
		for _, label in ipairs(labels) do
			label.Text = string.format("SKY BIN\n%d/%d", n, capacity)
		end
	end
	player:GetAttributeChangedSignal("SkyBin"):Connect(refresh)
	refresh()
end

function WorldUI.Start()
	buildClock()
	task.spawn(watchSkyBin)
	player:GetAttributeChangedSignal("Biome"):Connect(onBiomeChanged)
end

return WorldUI
