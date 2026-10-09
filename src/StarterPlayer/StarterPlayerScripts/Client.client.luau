--!strict
-- Client: entry point for the Timberline Tycoon client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.
-- Each one loads and starts in its own protected call: one that errors
-- (at its top level, in Start, or waiting forever on something that never
-- streams in) can't stop the others, and its error goes to Output with a
-- traceback. The HUD starts first, also protected: if it fails, the
-- others still start (without the HUD's corner and side buttons, which
-- they skip with a warning).

-- StarterPlayerScripts' modules are copied into PlayerScripts one by one,
-- and this script can start before all its siblings have arrived: a plain
-- require of one that isn't there yet stops the whole client (no HUD,
-- quest, axe or drag). So wait for every one of them first (each module
-- requires its siblings directly), MODULE_WAIT seconds for all of them
-- together. The list is every module in this folder (Client.spec checks
-- it).
local MODULES = {
	"AdminUI",
	"AmbientLife",
	"AmbientSound",
	"AxeController",
	"BadgeUI",
	"BlueprintPlacer",
	"BoxPoof",
	"BuilderTools",
	"CameraShake",
	"CanopyFade",
	"CarryController",
	"CarryPose",
	"ChopController",
	"ChopSawController",
	"CraftUI",
	"CutController",
	"DailyUI",
	"DialogueUI",
	"DoorAnim",
	"DragController",
	"FaceTarget",
	"FerryController",
	"FieldGuideUI",
	"ForestFiller",
	"ForestUI",
	"GamepadNav",
	"GondolaController",
	"HUD",
	"HammerController",
	"HoverTagUI",
	"HudLayout",
	"HudNav",
	"HudRules",
	"LeaderboardUI",
	"LifeFX",
	"LightingController",
	"LogicPanelUI",
	"LuxFX",
	"MenuPad",
	"MiningUI",
	"NPCController",
	"NewsUI",
	"PlotPickerUI",
	"PlotUI",
	"PromptSwitch",
	"PromptUI",
	"Quality",
	"QualityDressing",
	"QualityPickerUI",
	"QuestUI",
	"QuickMenuUI",
	"SaveSlotUI",
	"SawmillController",
	"SettingsUI",
	"ShopDoorAnim",
	"ShopUI",
	"StoreUI",
	"SprintController",
	"SwingPose",
	"TownFX",
	"TownMarkers",
	"TreeCosmetics",
	"TreeFX",
	"TreeUI",
	"UIArt",
	"UITheme",
	"VehicleController",
	"VehicleFX",
	"WeatherController",
	"WindSway",
	"WireTool",
	"WoodFX",
	"WorldUI",
}
local MODULE_WAIT = 30 -- seconds for all of them together, then it starts without the missing ones
do
	local folder = script.Parent
	local deadline = os.clock() + MODULE_WAIT
	for _, name in ipairs(MODULES) do
		if folder:FindFirstChild(name) == nil then
			local left = deadline - os.clock()
			if left <= 0 or folder:WaitForChild(name, left) == nil then
				warn(string.format("[Client] %s never arrived in PlayerScripts; starting without it", name))
			end
		end
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JoinFlow = require(ReplicatedStorage.Shared.JoinFlow)
local Net = require(ReplicatedStorage.Shared.Net)

type Controller = { Start: () -> () }

-- Requires one module (`get` does the require), protected: a module whose
-- top level errors, or that never arrived, is skipped with a warning.
local function load(name: string, get: () -> any): Controller?
	local ok, result = xpcall(get, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to load:\n%s", name, tostring(result)))
		return nil
	end
	return result :: Controller
end

local HUD = load("HUD", function()
	return require(script.Parent.HUD)
end)

local controllers: { { name: string, get: () -> any } } = {
	{
		name = "Quality",
		get = function()
			return require(script.Parent.Quality)
		end,
	},
	{
		name = "QualityDressing", -- the shop boxes' windows and lights for the Lower / Higher choice
		get = function()
			return require(script.Parent.QualityDressing)
		end,
	},
	{
		name = "LightingController",
		get = function()
			return require(script.Parent.LightingController)
		end,
	},
	{
		name = "ChopController",
		get = function()
			return require(script.Parent.ChopController)
		end,
	},
	{
		name = "ChopSawController",
		get = function()
			return require(script.Parent.ChopSawController)
		end,
	},
	{
		name = "TreeUI",
		get = function()
			return require(script.Parent.TreeUI)
		end,
	},
	{
		name = "TreeFX",
		get = function()
			return require(script.Parent.TreeFX)
		end,
	},
	{
		name = "CarryController",
		get = function()
			return require(script.Parent.CarryController)
		end,
	},
	{
		name = "SwingPose", -- before CarryPose, so a carried log wins the arms
		get = function()
			return require(script.Parent.SwingPose)
		end,
	},
	{
		name = "CarryPose",
		get = function()
			return require(script.Parent.CarryPose)
		end,
	},
	{
		name = "DoorAnim",
		get = function()
			return require(script.Parent.DoorAnim)
		end,
	},
	{
		name = "BoxPoof",
		get = function()
			return require(script.Parent.BoxPoof)
		end,
	},
	{
		name = "ShopDoorAnim",
		get = function()
			return require(script.Parent.ShopDoorAnim)
		end,
	},
	{
		name = "DragController", -- the v2 loop only
		get = function()
			return require(script.Parent.DragController)
		end,
	},
	{
		name = "CutController", -- the v2 loop only
		get = function()
			return require(script.Parent.CutController)
		end,
	},
	{
		name = "WoodFX", -- the v2 loop only
		get = function()
			return require(script.Parent.WoodFX)
		end,
	},
	{
		name = "LuxFX",
		get = function()
			return require(script.Parent.LuxFX)
		end,
	},
	{
		name = "AxeController",
		get = function()
			return require(script.Parent.AxeController)
		end,
	},
	{
		name = "ShopUI",
		get = function()
			return require(script.Parent.ShopUI)
		end,
	},
	{
		name = "QuestUI",
		get = function()
			return require(script.Parent.QuestUI)
		end,
	},
	{
		name = "VehicleController",
		get = function()
			return require(script.Parent.VehicleController)
		end,
	},
	{
		name = "VehicleFX",
		get = function()
			return require(script.Parent.VehicleFX)
		end,
	},
	{
		name = "GondolaController",
		get = function()
			return require(script.Parent.GondolaController)
		end,
	},
	{
		name = "FerryController",
		get = function()
			return require(script.Parent.FerryController)
		end,
	},
	-- DailyUI stays in MODULES (the file is waited for) but is not started.
	-- Start calls UITheme.Sized("DailyButton"), and that size is gone, so
	-- starting it warned in Output. Lane E (Foreman) replaces this module.
	{
		name = "DialogueUI",
		get = function()
			return require(script.Parent.DialogueUI)
		end,
	},
	{
		name = "WorldUI",
		get = function()
			return require(script.Parent.WorldUI)
		end,
	},
	{
		name = "StoreUI",
		get = function()
			return require(script.Parent.StoreUI)
		end,
	},
	{
		name = "HoverTagUI",
		get = function()
			return require(script.Parent.HoverTagUI)
		end,
	},
	{
		name = "FieldGuideUI",
		get = function()
			return require(script.Parent.FieldGuideUI)
		end,
	},
	{
		name = "BadgeUI",
		get = function()
			return require(script.Parent.BadgeUI)
		end,
	},
	{
		name = "BlueprintPlacer",
		get = function()
			return require(script.Parent.BlueprintPlacer)
		end,
	},
	{
		name = "BuilderTools",
		get = function()
			return require(script.Parent.BuilderTools)
		end,
	},
	{
		name = "WireTool",
		get = function()
			return require(script.Parent.WireTool)
		end,
	},
	{
		name = "HammerController",
		get = function()
			return require(script.Parent.HammerController)
		end,
	},
	{
		name = "PlotPickerUI",
		get = function()
			return require(script.Parent.PlotPickerUI)
		end,
	},
	{
		name = "PlotUI",
		get = function()
			return require(script.Parent.PlotUI)
		end,
	},
	{
		name = "SaveSlotUI",
		get = function()
			return require(script.Parent.SaveSlotUI)
		end,
	},
	{
		name = "SawmillController", -- the v2 loop only
		get = function()
			return require(script.Parent.SawmillController)
		end,
	},
	{
		name = "ForestUI",
		get = function()
			return require(script.Parent.ForestUI)
		end,
	},
	{
		name = "WeatherController",
		get = function()
			return require(script.Parent.WeatherController)
		end,
	},
	{
		name = "AmbientLife",
		get = function()
			return require(script.Parent.AmbientLife)
		end,
	},
	{
		name = "LifeFX",
		get = function()
			return require(script.Parent.LifeFX)
		end,
	},
	{
		name = "ForestFiller",
		get = function()
			return require(script.Parent.ForestFiller)
		end,
	},
	{
		name = "WindSway",
		get = function()
			return require(script.Parent.WindSway)
		end,
	},
	{
		name = "TreeCosmetics",
		get = function()
			return require(script.Parent.TreeCosmetics)
		end,
	},
	{
		name = "CanopyFade",
		get = function()
			return require(script.Parent.CanopyFade)
		end,
	},
	{
		name = "AmbientSound",
		get = function()
			return require(script.Parent.AmbientSound)
		end,
	},
	{
		name = "NPCController",
		get = function()
			return require(script.Parent.NPCController)
		end,
	},
	{
		name = "PromptUI",
		get = function()
			return require(script.Parent.PromptUI)
		end,
	},
	{
		name = "QualityPickerUI", -- the join screen: Lower or Higher quality, once per account
		get = function()
			return require(script.Parent.QualityPickerUI)
		end,
	},
	{
		name = "NewsUI",
		get = function()
			return require(script.Parent.NewsUI)
		end,
	},
	{
		name = "SettingsUI",
		get = function()
			return require(script.Parent.SettingsUI)
		end,
	},
	{
		name = "SprintController",
		get = function()
			return require(script.Parent.SprintController)
		end,
	},
	{
		name = "AdminUI",
		get = function()
			return require(script.Parent.AdminUI)
		end,
	},
	{
		name = "QuickMenuUI", -- the gamepad's menu of every HUD button
		get = function()
			return require(script.Parent.QuickMenuUI)
		end,
	},
	{
		name = "TownFX",
		get = function()
			return require(script.Parent.TownFX)
		end,
	},
	{
		name = "TownMarkers",
		get = function()
			return require(script.Parent.TownMarkers)
		end,
	},
}

local startedCount = 0 -- controllers whose Start has returned (or that had nothing to start)
local totalStarts = 0

local function start(name: string, module: Controller?)
	if module == nil then
		startedCount += 1
		return -- it failed to load (warned above)
	end
	local startedAt = os.clock()
	local ok, err = xpcall(function(): any
		module.Start()
		return nil
	end, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to start:\n%s", name, tostring(err)))
	end
	local took = os.clock() - startedAt
	startedCount += 1
	if took >= 0.1 then
		print(string.format("[Load] client %s Start took %.2fs", name, took))
	end
end

-- Every module loads before anything starts, in this order, as it always
-- has (only now one that fails is skipped instead of stopping the rest).
local loaded: { { name: string, module: Controller? } } = {}
local clientStart = os.clock()
for _, c in ipairs(controllers) do
	table.insert(loaded, { name = c.name, module = load(c.name, c.get) })
end

print(string.format("[Load] client: %d modules required in %.2fs", #loaded, os.clock() - clientStart))

-- First, and waited for (it starts UITheme), so toasts and side buttons
-- work for everything after it.
start("HUD", HUD)
-- HUD.Start returns once the HUD and its loading card are drawn (the wait for
-- the server's Remotes runs in its own thread), so everything below starts at
-- once; it used to wait here for the whole world build (34.8 s, 7 October).
print(
	string.format(
		"[Load] client: HUD drawn %.2fs after the client started; the controllers start now",
		os.clock() - clientStart
	)
)

totalStarts = #loaded
for _, c in ipairs(loaded) do
	task.spawn(start, c.name, c.module)
end

-- The join handshake. The controllers now start at +0.2 s, long before the
-- server has made its remotes, and each connects its handlers when its Start
-- gets past the wait for them. A one-shot the server fires before a handler
-- is connected is lost (the plot offer, the save slots, the cash). So once
-- every Start has returned (or CLIENT_READY_WAIT seconds, for one that waits
-- on something that never streams in), the client tells the server
-- ClientReady; the server holds the player's release until it hears it and
-- sends its state again (ServerScriptService/JoinSync), and every handler
-- applies state, so hearing it twice is harmless. The fire is repeated every
-- few seconds until the save is in, in case the server had not connected
-- its listener yet.
task.spawn(function()
	local waitStart = os.clock()
	local CLIENT_READY_WAIT = 20
	while startedCount < totalStarts and os.clock() - waitStart < CLIENT_READY_WAIT do
		task.wait(0.1)
	end
	local ok, remote = pcall(function(): RemoteEvent
		return Net.Remote("ClientReady")
	end)
	if not ok then
		warn("[Client] ClientReady remote not found: " .. tostring(remote))
		return
	end
	local localPlayer = Players.LocalPlayer
	local firedAt = os.clock()
	print(
		string.format(
			"[Load] client ready handshake %.2fs after the client started (%d/%d controllers started)",
			firedAt - clientStart,
			startedCount,
			totalStarts
		)
	)
	-- The server connects its listener only once its services have started,
	-- which can be later than the first fire: keep asking for longer than the
	-- server's gate wait (JoinFlow.ClientReadyTries), not for a fixed 18 s.
	for _ = 1, JoinFlow.ClientReadyTries do
		remote:FireServer()
		task.wait(JoinFlow.ClientReadyEvery)
		if localPlayer:GetAttribute("ProfileLoaded") == true then
			return
		end
	end
end)

print(string.format("[Load] client controllers started in %.2fs", os.clock() - clientStart))
print("[Client] Timberline Tycoon client started.")
