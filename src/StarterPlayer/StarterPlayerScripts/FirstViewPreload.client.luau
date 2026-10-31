--!strict
-- FirstViewPreload (T415): while the loading card is up, fetch the first view's meshes (the player's axe,
-- Murph, the spawn town) through ContentProvider:PreloadAsync. The list is FirstView.List(), capped at
-- PerfPolicy.PreloadCap; nothing else in the world is preloaded here. The player attribute FirstViewReady
-- is false while it runs and true after, and the loading card waits for it for a few seconds at most
-- (ReplicatedFirst/LoadingScreen, PRELOAD_WAIT). A failure never blocks anything: the attribute still ends true.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
	return
end
player:SetAttribute("FirstViewReady", false)

local ok, err = pcall(function(): any
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local module = if shared then shared:WaitForChild("FirstView", 10) else nil
	if not module then
		return nil
	end
	local FirstView = require(module :: ModuleScript) :: any
	local list: { string } = FirstView.List()
	ContentProvider:PreloadAsync(list)
	return nil
end)
if not ok then
	warn("[FirstViewPreload] " .. tostring(err))
end
player:SetAttribute("FirstViewReady", true)
