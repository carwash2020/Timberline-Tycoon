--!strict
-- Client: entry point for the Timberline Tycoon client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.
-- Each one starts in its own protected thread: one that errors (or waits
-- forever on something that never streams in) can't stop the others, and
-- its error goes to Output with a traceback. The HUD starts first, also
-- protected: if it fails, the others still start (without the HUD's corner
-- and side buttons, which they skip with a warning).

-- StarterPlayerScripts' modules are copied into PlayerScripts one by one,
-- and this script can start before all its siblings have arrived: a plain
-- require of one that isn't there yet stops the whole client (no HUD,
-- quest, axe or drag). So wait for every one of them first (each module
-- requires its siblings directly). The list is every module in this
-- folder (Client.spec checks it).
local MODULES = {
	"AmbientLife",
	"AmbientSound",
	"AxeController",
	"BlueprintPlacer",
	"CameraShake",
	"CanopyFade",
	"CarryController",
	"CarryPose",
	"ChopController",
	"CutController",
	"DailyUI",
	"DragController",
	"FaceTarget",
	"FieldGuideUI",
	"ForestFiller",
	"ForestUI",
	"GondolaController",
	"HUD",
	"HudLayout",
	"HudRules",
	"LightingController",
	"NPCController",
	"PlotUI",
	"PromptUI",
	"Quality",
	"QuestUI",
	"SettingsUI",
	"ShopUI",
	"StoreUI",
	"TownFX",
	"TownMarkers",
	"TreeFX",
	"TreeUI",
	"UITheme",
	"VehicleController",
	"VehicleFX",
	"WeatherController",
	"WindSway",
	"WoodFX",
	"WorldUI",
}
local MODULE_WAIT = 30 -- seconds for any one module before giving up on it
do
	local folder = script.Parent
	for _, name in ipairs(MODULES) do
		if folder:FindFirstChild(name) == nil and folder:WaitForChild(name, MODULE_WAIT) == nil then
			warn(string.format("[Client] %s never arrived in PlayerScripts (waited %d s)", name, MODULE_WAIT))
		end
	end
end

local HUD = require(script.Parent.HUD)

local controllers: { { name: string, module: { Start: () -> () } } } = {
	{ name = "Quality", module = require(script.Parent.Quality) },
	{ name = "LightingController", module = require(script.Parent.LightingController) },
	{ name = "ChopController", module = require(script.Parent.ChopController) },
	{ name = "TreeUI", module = require(script.Parent.TreeUI) },
	{ name = "TreeFX", module = require(script.Parent.TreeFX) },
	{ name = "CarryController", module = require(script.Parent.CarryController) },
	{ name = "CarryPose", module = require(script.Parent.CarryPose) },
	{ name = "DragController", module = require(script.Parent.DragController) }, -- the v2 loop only
	{ name = "CutController", module = require(script.Parent.CutController) }, -- the v2 loop only
	{ name = "WoodFX", module = require(script.Parent.WoodFX) }, -- the v2 loop only
	{ name = "AxeController", module = require(script.Parent.AxeController) },
	{ name = "ShopUI", module = require(script.Parent.ShopUI) },
	{ name = "QuestUI", module = require(script.Parent.QuestUI) },
	{ name = "VehicleController", module = require(script.Parent.VehicleController) },
	{ name = "VehicleFX", module = require(script.Parent.VehicleFX) },
	{ name = "GondolaController", module = require(script.Parent.GondolaController) },
	{ name = "DailyUI", module = require(script.Parent.DailyUI) },
	{ name = "WorldUI", module = require(script.Parent.WorldUI) },
	{ name = "StoreUI", module = require(script.Parent.StoreUI) },
	{ name = "FieldGuideUI", module = require(script.Parent.FieldGuideUI) },
	{ name = "BlueprintPlacer", module = require(script.Parent.BlueprintPlacer) },
	{ name = "PlotUI", module = require(script.Parent.PlotUI) },
	{ name = "ForestUI", module = require(script.Parent.ForestUI) },
	{ name = "WeatherController", module = require(script.Parent.WeatherController) },
	{ name = "AmbientLife", module = require(script.Parent.AmbientLife) },
	{ name = "ForestFiller", module = require(script.Parent.ForestFiller) },
	{ name = "WindSway", module = require(script.Parent.WindSway) },
	{ name = "CanopyFade", module = require(script.Parent.CanopyFade) },
	{ name = "AmbientSound", module = require(script.Parent.AmbientSound) },
	{ name = "NPCController", module = require(script.Parent.NPCController) },
	{ name = "PromptUI", module = require(script.Parent.PromptUI) },
	{ name = "SettingsUI", module = require(script.Parent.SettingsUI) },
	{ name = "TownFX", module = require(script.Parent.TownFX) },
	{ name = "TownMarkers", module = require(script.Parent.TownMarkers) },
}

local function start(name: string, module: { Start: () -> () })
	local ok, err = xpcall(function(): any
		module.Start()
		return nil
	end, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to start:\n%s", name, tostring(err)))
	end
end

-- First, and waited for (it starts UITheme), so toasts and side buttons
-- work for everything after it.
start("HUD", HUD)

for _, c in ipairs(controllers) do
	task.spawn(start, c.name, c.module)
end

print("[Client] Timberline Tycoon client started.")
