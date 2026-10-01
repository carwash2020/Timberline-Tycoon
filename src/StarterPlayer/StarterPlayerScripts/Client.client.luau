--!strict
-- Client: entry point for the Timberline Tycoon client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.

local HUD = require(script.Parent.HUD)
local ChopController = require(script.Parent.ChopController)
local TreeUI = require(script.Parent.TreeUI)
local TreeFX = require(script.Parent.TreeFX)
local CarryController = require(script.Parent.CarryController)
local AxeController = require(script.Parent.AxeController)
local ShopUI = require(script.Parent.ShopUI)
local QuestUI = require(script.Parent.QuestUI)
local VehicleController = require(script.Parent.VehicleController)
local DailyUI = require(script.Parent.DailyUI)
local WorldUI = require(script.Parent.WorldUI)
local StoreUI = require(script.Parent.StoreUI)
local FieldGuideUI = require(script.Parent.FieldGuideUI)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local PlotUI = require(script.Parent.PlotUI)
local PromptUI = require(script.Parent.PromptUI)

HUD.Start() -- first (it starts UITheme), so toasts and side buttons work for everything after it
ChopController.Start()
TreeUI.Start()
TreeFX.Start()
CarryController.Start()
AxeController.Start()
ShopUI.Start()
QuestUI.Start()
VehicleController.Start()
DailyUI.Start()
WorldUI.Start()
StoreUI.Start()
FieldGuideUI.Start()
BlueprintPlacer.Start()
PlotUI.Start()
PromptUI.Start()

print("[Client] Timberline Tycoon client started.")
