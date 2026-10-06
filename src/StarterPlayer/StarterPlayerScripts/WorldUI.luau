--!strict
-- WorldUI: the world, client side.
--   * Entering a biome names it and its woods, says how its grove is doing
--     (Grove Vitality, GAME_DESIGN §16: "Starter Forest · oak, birch · a
--     thriving grove"), and warns about missing gear ("It's cold here: you
--     walk slower without an Insulated Coat"). If the grove you're in
--     changes tier, a toast says so.
--   * A clock next to the cash: "Day 2:05 PM" / "Night 10:10 PM" (night is when
--     the Gloam Hollow's trees come out). On a phone it's in the corner's
--     second line instead, and hidden during the tutorial and while the
--     save loads (HudLayout.ClockLine).
--   * The Sky Bin by the sell pad shows your own count ("SKY BIN 12/30"),
--     or under the v2 loop the u³ in it ("SKY BIN 14/120 u³", from the
--     SkyBinVolume attribute); its "Sell Sky Bin" prompt (the server's)
--     shows only while there's wood in it.
-- The server sets the Biome and OwnedGear attributes and the
-- VitalityTier_<biome> workspace attributes (ForestService). The clock
-- reads Lighting.ClockTime, the hour the sky shows: LightingController
-- sets it every frame from the server's clock (WorldTime), or in Studio
-- from the ClockOverride attribute.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local RegionLogic = require(ReplicatedStorage.Shared.RegionLogic)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local HUD = require(script.Parent.HUD)
local HudLayout = require(script.Parent.HudLayout)
local MenuPad = require(script.Parent.MenuPad)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local WorldUI = {}

local clockButton: TextButton? = nil
local clockFocused = false

function WorldUI.MakeClock(parent: Instance, size: Vector2, textSize: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Clock"
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.BackgroundColor3 = UITheme.Colors.Bark
	button.TextColor3 = UITheme.Colors.Cream
	button.Font = UITheme.Fonts.Black
	button.TextSize = textSize
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = true
	button.TextXAlignment = Enum.TextXAlignment.Center
	UITheme.corner(button, size.Y / 2)
	UITheme.stroke(button, UITheme.Colors.Ink, 2)
	button.Parent = parent
	return button
end

-- The clock can take the pad if a stick lands on it. It is not selected
-- just because the HUD is on screen: there is no clock menu.
function WorldUI._open(button: GuiObject?)
	clockFocused = true
	if button and button:IsA("TextButton") then
		clockButton = button
	end
	MenuPad.Open(button)
end

function WorldUI._close()
	clockFocused = false
	MenuPad.Close(clockButton)
end

function WorldUI.ApplyKey(key: Enum.KeyCode): string?
	if not MenuPad.Closes(key) then
		return nil
	end
	local selected = GuiService.SelectedObject
	if clockFocused or (clockButton ~= nil and selected == clockButton) then
		WorldUI._close()
		return "close"
	end
	return nil
end

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

local function gearName(id: string): string
	local gear = ItemCatalog.GetGear(id)
	return if gear then gear.displayName else id
end

-- Entering a named region: the place, its shape and what grows there.
local function onRegionChanged()
	local line = RegionLogic.Toast((player:GetAttribute("Region") :: string?) or "")
	if line then
		local biome = BiomeData.Get((player:GetAttribute("Biome") :: string?) or "")
		local tier = if biome then groveTier(biome) else nil
		HUD.Toast(if tier then line .. " · " .. tier.blurb else line)
	end
end

local function onBiomeChanged()
	local biome = BiomeData.Get((player:GetAttribute("Biome") :: string?) or "")
	if not biome then
		return
	end
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
	local label = WorldUI.MakeClock(line, size, spec.text)
	label.LayoutOrder = 20 -- left of HUD's top row (♪ + cash), right of the Store button
	clockButton = label

	-- Which line it's in (or none) for the device and the tutorial.
	local function place()
		local compact = UITheme.Compact()
		local box = if compact then Vector2.new(92, 28) else (spec.size or Vector2.new(100, 30))
		label.Size = UDim2.fromOffset(box.X, box.Y)
		label.TextSize = if compact then 13 else spec.text
		-- (nil while the save loads: hidden on a phone until it's in)
		local spot = HudLayout.ClockLine(UITheme.IsPhone(), player:GetAttribute("TutorialStep"))
		local under = HUD.UnderCash()
		local target = under or line -- always the line under the audio and cash
		if label.Parent ~= target then
			label.Parent = target
			label.LayoutOrder = 1 -- left of the Store button, the pouch and Daily Goals
		end
		label.Visible = spot ~= "none"
	end
	place()
	UITheme.WatchLayout(place)
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

-- Calls `fn` with the named child now, and when a later one arrives.
-- SellArea is parented at the end of the map build, and the Sky Bin's
-- sell prompt is added after that. A bare WaitForChild warns during boot
-- and would hang forever on a part that had streamed out.
local function whenChild(parent: Instance, name: string, fn: (Instance) -> ())
	local found = parent:FindFirstChild(name)
	if found then
		fn(found)
	end
	parent.ChildAdded:Connect(function(child: Instance)
		if child.Name == name then
			fn(child)
		end
	end)
end

local function bindSkyBin(bin: Instance)
	local labels: { TextLabel } = {}
	for _, gui in ipairs(bin:GetChildren()) do
		local label = if gui:IsA("SurfaceGui") then gui:FindFirstChildOfClass("TextLabel") else nil
		if label then
			table.insert(labels, label)
		end
	end
	local sky = BiomeData.Get("sky")
	local capacity = if sky then sky.skyBinCapacity or 30 else 30
	local volumeCap = if sky then sky.skyBinVolume or 120 else 120
	local sellPrompt: ProximityPrompt? = nil
	local function refresh()
		local text: string
		if CoreLoop.V2() then
			local used = player:GetAttribute("SkyBinVolume")
			text = "SKY BIN\n" .. SellLogic.BinText(if type(used) == "number" then used else 0, volumeCap)
		else
			local n = (player:GetAttribute("SkyBin") :: number?) or 0
			text = string.format("SKY BIN\n%d/%d", n, capacity)
		end
		for _, label in ipairs(labels) do
			label.Text = text
		end
		local prompt = sellPrompt
		if prompt then
			local used = player:GetAttribute("SkyBinVolume")
			prompt.Enabled = type(used) == "number" and used > 0
		end
	end
	player:GetAttributeChangedSignal("SkyBin"):Connect(refresh)
	player:GetAttributeChangedSignal("SkyBinVolume"):Connect(refresh)
	local armed = false
	local function armPrompt()
		if armed or not CoreLoop.V2() then
			return
		end
		armed = true
		whenChild(bin, "SellSkyBin", function(found: Instance)
			if found:IsA("ProximityPrompt") then
				sellPrompt = found
				refresh()
			end
		end)
	end
	workspace:GetAttributeChangedSignal(CoreLoop.ActiveAttribute):Connect(function()
		refresh()
		armPrompt()
	end)
	refresh()
	armPrompt()
end

-- The Sky Bin by the sell pad shows this player's own count.
local function watchSkyBinOn(map: Instance)
	whenChild(map, "SellArea", function(area: Instance)
		whenChild(area, "SkyBin", function(bin: Instance)
			bindSkyBin(bin)
		end)
	end)
end

local function watchSkyBin()
	local map = workspace:FindFirstChild("TimberlineMap")
	if map then
		watchSkyBinOn(map)
		return
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "TimberlineMap" then
			watchSkyBinOn(child)
		end
	end)
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
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		WorldUI.ApplyKey(input.KeyCode)
	end)
	buildClock()
	task.spawn(watchSkyBin)
	watchGroves()
	player:GetAttributeChangedSignal("Region"):Connect(onRegionChanged)
	player:GetAttributeChangedSignal("Biome"):Connect(onBiomeChanged)
end

return WorldUI
