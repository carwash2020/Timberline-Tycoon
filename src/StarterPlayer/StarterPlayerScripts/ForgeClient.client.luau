--!strict
-- ForgeClient: starts the Sky Forge window (ForgeUI) on its own, like
-- MiningClient, so the end game needs no line in Client's controller list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModulesReady = require(ReplicatedStorage.Shared.ModulesReady)

-- Wait for Client to say every sibling has arrived: ForgeUI requires others
-- (GamepadNav...) straight away, and one that is missing fails it for good.
if not ModulesReady.Wait(script.Parent) then
	warn("[ForgeClient] PlayerScripts' modules were not all in after the wait; trying anyway")
end

local ForgeUI = require(script.Parent:WaitForChild("ForgeUI"))

local ok, err = pcall(function(): any
	ForgeUI.Start()
	return nil
end)
if not ok then
	warn("[ForgeClient] " .. tostring(err))
end
