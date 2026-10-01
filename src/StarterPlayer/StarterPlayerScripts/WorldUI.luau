--!strict
-- WorldUI: the world, client side.
--   * Entering a biome names it and its woods, says how its grove is doing
--     (Grove Vitality, GAME_DESIGN §16: "Starter Forest · oak, birch · a
--     thriving grove"), and warns about missing gear ("It's cold here: you
--     walk slower without an Insulated Coat"). If the grove you're in
--     changes tier, a toast says so.
--   * A clock next to the cash: "Day 14:05" / "Night 22:10" (night is when
--     the Phantom Grove's trees come out). On a phone it's in the corner's
--     second line instead, and hidden during the tutorial and while the
--     save loads (HudLayout.ClockLine).
--   * The Sky Bin by the sell pad shows your own count ("SKY BIN 12/30").
-- The server sets the Biome and OwnedGear attributes and the
-- VitalityTier_<biome> workspace attributes (ForestService). The clock
-- reads Lighting.ClockTime, the hour the sky shows: LightingController
-- sets it every frame from the server's clock (WorldTime), or in Studio
-- from the ClockOverride attribute.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local WorldUI = {}

local player = Players.LocalPlayer

local TIER_TOAST_COOLDOWN = 45 -- seconds between tier toasts for one grove (no flicker at a boundary)

-- The grove's tier right now, if this biome has a vitality meter.
local function groveTier(biome: BiomeData.BiomeDef): ForestData.Tier?
	if not ForestLogic.IsGrove(biome.id) then
		return nil
	end
	local id = workspace:GetAttribute("VitalityTier_" .. biome.id)
	return if type(id) == "string" then ForestLogic.Tier(id) else nil
end

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
	local tier = groveTier(biome)
	HUD.Toast(string.format("%s · %s%s", biome.displayName, woodsOf(biome), if tier then " · " .. tier.blurb else ""))
	local gear = ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")
	local rules = BiomeData.Rules(biome, gear)
	if rules.speedFactor < 1 and biome.slowdown then
		HUD.Toast(
			string.format(
				"It's cold here: you walk slower without %s.",
				Util.article(gearName(biome.slowdown.removedBy))
			)
		)
	end
	if rules.needs and not rules.burning then
		HUD.Toast(
			string.format("Too dark to chop here without %s (Hearth & Home).", Util.article(gearName(rules.needs)))
		)
	end
	if biome.nightOnly and not WorldTime.IsNight(Lighting.ClockTime) then
		HUD.Toast("Nothing grows here by day. Come back at night.")
	end
end

local function buildClock()
	local line = HUD.BesideCash()
	if not line then
		warn("[WorldUI] no HUD corner (HUD.Start didn't finish): skipping the clock")
		return
	end
	local spec = UITheme.Sized("Clock") -- a corner pill: 36 tall on a phone
	local size = spec.size or Vector2.new(100, 30)
	local label = UITheme.label(line, "", UITheme.Fonts.Black, spec.text, UITheme.Colors.Cream)
	label.Name = "Clock"
	label.LayoutOrder = 20 -- left of HUD's top row (♪ + cash), right of the Store button
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.BackgroundColor3 = UITheme.Colors.Bark
	label.BackgroundTransparency = 0
	label.TextXAlignment = Enum.TextXAlignment.Center
	UITheme.corner(label, size.Y / 2)
	UITheme.stroke(label, UITheme.Colors.Ink, 2)

	-- Which line it's in (or none) for the device and the tutorial.
	local function place()
		-- (nil while the save loads: hidden on a phone until it's in)
		local spot = HudLayout.ClockLine(UITheme.IsPhone(), player:GetAttribute("TutorialStep"))
		local under = HUD.UnderCash()
		local target = if spot == "under" and under then under else line
		if label.Parent ~= target then
			label.Parent = target
			label.LayoutOrder = if target == line then 20 else 1 -- left of the pouch and Daily Goals
		end
		label.Visible = spot ~= "none"
	end
	place()
	player:GetAttributeChangedSignal("TutorialStep"):Connect(place)
	UserInputService.LastInputTypeChanged:Connect(place)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place) -- IsPhone reads the screen's height
	end

	-- The hour the sky shows, once a second (LightingController moves
	-- Lighting.ClockTime every frame; the label doesn't need to): the
	-- shared clock, or Studio's ClockOverride, so a tester sees that hour.
	local function refresh()
		local text = HudRules.ClockText(Lighting.ClockTime)
		if label.Text ~= text then
			label.Text = text
		end
	end
	refresh()
	task.spawn(function()
		while label.Parent do
			task.wait(1)
			refresh()
		end
	end)
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

-- A toast when the grove you're standing in changes tier.
local function watchGroves()
	local lastToast: { [string]: number } = {}
	for _, id in ipairs(ForestData.Groves) do
		workspace:GetAttributeChangedSignal("VitalityTier_" .. id):Connect(function()
			if player:GetAttribute("Biome") ~= id then
				return
			end
			local biome = BiomeData.Get(id)
			local tier = if biome then groveTier(biome) else nil
			local now = os.clock()
			if not biome or not tier or now - (lastToast[id] or -math.huge) < TIER_TOAST_COOLDOWN then
				return
			end
			lastToast[id] = now
			HUD.Toast(string.format(tier.became, biome.displayName))
		end)
	end
end

function WorldUI.Start()
	buildClock()
	task.spawn(watchSkyBin)
	watchGroves()
	player:GetAttributeChangedSignal("Biome"):Connect(onBiomeChanged)
end

return WorldUI
