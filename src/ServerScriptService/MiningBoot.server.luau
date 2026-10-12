--!strict
-- MiningBoot: starts mining and crafting without editing GameServer.
-- A module that is missing or fails is skipped, with a warning.
--
-- It waits for the world, like BaseBoot: MiningService.Init builds the mine's
-- ore, rubble, furnace pad and shops at once, and reads the "MineAnchor" and
-- "Rubble" parts MapBuilder's Underground step makes (MineSites.MergeLive).
-- This script starts with the server, minutes before that step, so run at
-- once Init saw an empty world, built its own rubble from the fallback table,
-- and the Underground step then added a second, untracked wall on top of it
-- (a wall nothing could clear). GameServer makes the Remotes folder only
-- after the world is built, and both services need a remote from it anyway.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)

local function boot(name: string)
	local mod = ServerScriptService:FindFirstChild(name)
	if mod == nil or not mod:IsA("ModuleScript") then
		warn("[MiningBoot] " .. name .. " is not in ServerScriptService; it was not started")
		return
	end
	local ok, result = pcall(require, mod)
	if not ok or type(result) ~= "table" or type(result.Init) ~= "function" then
		warn("[MiningBoot] " .. name .. " did not load: " .. tostring(result))
		return
	end
	local ran, err = pcall(result.Init)
	if not ran then
		warn("[MiningBoot] " .. name .. " " .. tostring(err))
	end
end

if ReplicatedStorage:WaitForChild("Remotes", Net.RemotesWaitSeconds) == nil then
	warn(
		string.format(
			"[MiningBoot] no Remotes folder after %ds: GameServer never started, so mining and crafting were not started",
			Net.RemotesWaitSeconds
		)
	)
	return
end

boot("MiningService")
boot("CraftingService")
