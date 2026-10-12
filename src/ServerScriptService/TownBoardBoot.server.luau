--!strict
-- TownBoardBoot: starts the town leaderboard board without editing
-- GameServer or V1Boot. A module that is missing or fails is skipped, with a
-- warning (the board is the one thing a silent skip would never be noticed
-- for: nothing else in the game points at it).

local ServerScriptService = game:GetService("ServerScriptService")

local mod = ServerScriptService:FindFirstChild("TownBoardService")
if mod ~= nil and mod:IsA("ModuleScript") then
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" and type((result :: any).Init) == "function" then
		local ran, err = pcall((result :: any).Init)
		if not ran then
			warn("[TownBoardBoot] TownBoardService " .. tostring(err))
		end
	else
		warn("[TownBoardBoot] TownBoardService did not load: " .. tostring(result))
	end
else
	warn("[TownBoardBoot] TownBoardService is not in ServerScriptService; the town board was not started")
end
