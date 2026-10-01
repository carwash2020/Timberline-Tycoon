--!strict
-- Client: entry point for the Timberline Tycoon client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.
-- Each one starts in its own protected thread: one that errors (or waits
-- forever on something that never streams in) can't stop the others, and
-- its error goes to Output with a traceback.

local HUD = require(script.Parent.HUD)

local controllers: { { name: string, module: { Start: () -> () } } } = {
	{ name = "LightingController", module = require(script.Parent.LightingController) },
	{ name = "ChopController", module = require(script.Parent.ChopController) },
	{ name = "TreeUI", module = require(script.Parent.TreeUI) },
	{ name = "TreeFX", module = require(script.Parent.TreeFX) },
	{ name = "CarryController", module = require(script.Parent.CarryController) },
	{ name = "AxeController", module = require(script.Parent.AxeController) },
	{ name = "ShopUI", module = require(script.Parent.ShopUI) },
	{ name = "QuestUI", module = require(script.Parent.QuestUI) },
	{ name = "VehicleController", module = require(script.Parent.VehicleController) },
	{ name = "VehicleFX", module = require(script.Parent.VehicleFX) },
	{ name = "DailyUI", module = require(script.Parent.DailyUI) },
	{ name = "WorldUI", module = require(script.Parent.WorldUI) },
	{ name = "StoreUI", module = require(script.Parent.StoreUI) },
	{ name = "FieldGuideUI", module = require(script.Parent.FieldGuideUI) },
	{ name = "BlueprintPlacer", module = require(script.Parent.BlueprintPlacer) },
	{ name = "PlotUI", module = require(script.Parent.PlotUI) },
	{ name = "ForestUI", module = require(script.Parent.ForestUI) },
	{ name = "WeatherController", module = require(script.Parent.WeatherController) },
	{ name = "AmbientLife", module = require(script.Parent.AmbientLife) },
	{ name = "WindSway", module = require(script.Parent.WindSway) },
	{ name = "AmbientSound", module = require(script.Parent.AmbientSound) },
	{ name = "NPCController", module = require(script.Parent.NPCController) },
	{ name = "PromptUI", module = require(script.Parent.PromptUI) },
	{ name = "SettingsUI", module = require(script.Parent.SettingsUI) },
	{ name = "TownFX", module = require(script.Parent.TownFX) },
}

HUD.Start() -- first (it starts UITheme), so toasts and side buttons work for everything after it

for _, c in ipairs(controllers) do
	task.spawn(function()
		local ok, err = xpcall(function(): any
			c.module.Start()
			return nil
		end, debug.traceback)
		if not ok then
			warn(string.format("[Client] %s failed to start:\n%s", c.name, tostring(err)))
		end
	end)
end

print("[Client] Timberline Tycoon client started.")
