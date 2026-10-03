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
	"AmbientLife",
	"AmbientSound",
	"AxeController",
	"BlueprintPlacer",
	"CameraShake",
	"CanopyFade",
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
	"UITheme",
	"VehicleController",
	"VehicleFX",
	"WeatherController",
	"WindSway",
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
		name = "LightingController",
		get = function()
			return require(script.Parent.LightingController)
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
		name = "DailyUI",
		get = function()
			return require(script.Parent.DailyUI)
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
		name = "FieldGuideUI",
		get = function()
			return require(script.Parent.FieldGuideUI)
		end,
	},
	{
		name = "BlueprintPlacer",
		get = function()
			return require(script.Parent.BlueprintPlacer)
		end,
	},
	{
		name = "PlotUI",
		get = function()
			return require(script.Parent.PlotUI)
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
		name = "SettingsUI",
		get = function()
			return require(script.Parent.SettingsUI)
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

local function start(name: string, module: Controller?)
	if module == nil then
		return -- it failed to load (warned above)
	end
	local ok, err = xpcall(function(): any
		module.Start()
		return nil
	end, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to start:\n%s", name, tostring(err)))
	end
end

-- Every module loads before anything starts, in this order, as it always
-- has (only now one that fails is skipped instead of stopping the rest).
local loaded: { { name: string, module: Controller? } } = {}
for _, c in ipairs(controllers) do
	table.insert(loaded, { name = c.name, module = load(c.name, c.get) })
end

-- First, and waited for (it starts UITheme), so toasts and side buttons
-- work for everything after it.
start("HUD", HUD)

for _, c in ipairs(loaded) do
	task.spawn(start, c.name, c.module)
end

print("[Client] Timberline Tycoon client started.")
