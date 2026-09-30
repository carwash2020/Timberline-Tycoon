-- Client: entry point for the Timberline Tycoon Phase 1 client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and send intents.

local ChopController = require(script.Parent.ChopController)
local TreeUI = require(script.Parent.TreeUI)
local CarryController = require(script.Parent.CarryController)
local HUD = require(script.Parent.HUD)

ChopController.Start()
TreeUI.Start()
CarryController.Start()
HUD.Start()

print("[Client] Timberline Tycoon client started.")
