--!strict
-- Client: entry point for the Timberline Tycoon Phase 1 client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.

local HUD = require(script.Parent.HUD)
local ChopController = require(script.Parent.ChopController)
local TreeUI = require(script.Parent.TreeUI)
local TreeFX = require(script.Parent.TreeFX)
local CarryController = require(script.Parent.CarryController)

HUD.Start() -- first, so toasts work for everything after it
ChopController.Start()
TreeUI.Start()
TreeFX.Start()
CarryController.Start()

print("[Client] Timberline Tycoon client started.")
