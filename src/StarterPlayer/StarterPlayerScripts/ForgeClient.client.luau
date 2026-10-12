--!strict
-- ForgeClient: starts the Sky Forge window (ForgeUI) on its own, like
-- MiningClient, so the end game needs no line in Client's controller list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Shared may not have replicated yet: wait for it (bounded) before the first require.
local SHARED_WAIT = 30
local SharedFolder = ReplicatedStorage:WaitForChild("Shared", SHARED_WAIT)
if not SharedFolder then
	warn("[ForgeClient] ReplicatedStorage.Shared did not arrive in " .. SHARED_WAIT .. " seconds")
	return
end
local ModulesReady = require(SharedFolder:WaitForChild("ModulesReady", SHARED_WAIT))

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
