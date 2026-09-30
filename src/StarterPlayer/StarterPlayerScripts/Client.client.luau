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

HUD.Start() -- first, so toasts work for everything after it
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

print("[Client] Timberline Tycoon client started.")
