--!strict
-- ForgeClient: starts the Sky Forge window (ForgeUI) on its own, like
-- MiningClient, so the end game needs no line in Client's controller list.

local ForgeUI = require(script.Parent:WaitForChild("ForgeUI"))

local ok, err = pcall(function(): any
	ForgeUI.Start()
	return nil
end)
if not ok then
	warn("[ForgeClient] " .. tostring(err))
end
